-- Secure claim review and handover workflow.
-- Run after supabase_rbac_migration.sql and the existing claim schema migration.
-- This migration is additive. It removes direct client claim insertion so all
-- claim creation and state transitions are validated by server-side functions.

alter table public.item_claims
  add column if not exists reviewed_by uuid references auth.users(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists rejection_reason text,
  add column if not exists completed_at timestamptz,
  add column if not exists handover_confirmed_by uuid references auth.users(id);

create index if not exists item_claims_reviewed_by_idx on public.item_claims (reviewed_by);
create index if not exists item_claims_handover_confirmed_by_idx
  on public.item_claims (handover_confirmed_by);
create index if not exists active_claims_per_claimant
  on public.item_claims (report_id, claimant_id)
  where status in ('pending', 'approved');

create table if not exists public.claim_audit_log (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid not null references public.item_claims(id) on delete cascade,
  actor_id uuid not null references auth.users(id),
  action text not null check (action in ('submitted', 'approved', 'rejected', 'handover_confirmed', 'completed')),
  previous_status text,
  new_status text not null,
  created_at timestamptz not null default now()
);

create index if not exists claim_audit_log_claim_idx
  on public.claim_audit_log (claim_id, created_at desc);

alter table public.claim_audit_log enable row level security;
revoke all on table public.claim_audit_log from anon, authenticated, public;
grant select on table public.claim_audit_log to authenticated;
drop policy if exists "Administrators can view claim audit logs" on public.claim_audit_log;
create policy "Administrators can view claim audit logs"
  on public.claim_audit_log for select to authenticated
  using (public.has_role('admin'));

create table if not exists public.claim_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  claim_id uuid references public.item_claims(id) on delete cascade,
  notification_type text not null,
  title text not null,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists claim_notifications_recipient_idx
  on public.claim_notifications (recipient_id, created_at desc);
alter table public.claim_notifications enable row level security;
revoke all on table public.claim_notifications from anon, authenticated, public;
grant select on table public.claim_notifications to authenticated;
drop policy if exists "Users can view their own claim notifications" on public.claim_notifications;
create policy "Users can view their own claim notifications"
  on public.claim_notifications for select to authenticated
  using (recipient_id = (select auth.uid()));
create or replace function public.mark_claim_notification_read(p_notification_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.claim_notifications
  set read_at = coalesce(read_at, now())
  where id = p_notification_id and recipient_id = auth.uid();
end;
$$;
revoke all on function public.mark_claim_notification_read(uuid) from public;
grant execute on function public.mark_claim_notification_read(uuid) to authenticated;

-- Direct inserts are intentionally removed. The RPC below is the only client
-- entry point and derives claimant_id and claimant_name from auth/session data.
drop policy if exists "Users can create their own claims" on public.item_claims;
revoke insert on public.item_claims from authenticated;

drop policy if exists "Claimants owners and moderators can view claims" on public.item_claims;
create policy "Claimants owners and moderators can view claims"
  on public.item_claims for select to authenticated
  using (
    claimant_id = (select auth.uid())
    or exists (
      select 1 from public.item_reports r
      where r.id = report_id and r.owner_id = (select auth.uid())
    )
    or public.has_role('admin')
    or public.has_role('moderator')
  );

create or replace function public.submit_claim(
  p_report_id uuid,
  p_private_claim_details text,
  p_claimant_contact text,
  p_claimant_contact_hidden boolean default true
)
returns public.item_claims
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  report_row public.item_reports;
  claim_row public.item_claims;
  claimant_display_name text;
begin
  if caller_id is null then raise exception 'You must be signed in to submit a claim'; end if;
  if nullif(trim(coalesce(p_private_claim_details, '')), '') is null
     or nullif(trim(coalesce(p_claimant_contact, '')), '') is null then
    raise exception 'Ownership details and contact information are required';
  end if;

  select * into report_row from public.item_reports where id = p_report_id for update;
  if report_row.id is null then raise exception 'Item report not found'; end if;
  if report_row.report_type <> 'found' then raise exception 'Claims require a found-item report'; end if;
  if report_row.owner_id = caller_id then raise exception 'You cannot claim your own report'; end if;
  if report_row.status not in ('open', 'claimPending') then
    raise exception 'This item is no longer open for claims';
  end if;
  if exists (
    select 1 from public.item_claims
    where report_id = p_report_id and claimant_id = caller_id and status in ('pending', 'approved')
  ) then raise exception 'You already have an active claim for this item'; end if;

  select coalesce(nullif(trim(full_name), ''), email, '') into claimant_display_name
  from public.user_profiles where id = caller_id;
  claimant_display_name := coalesce(claimant_display_name, '');

  insert into public.item_claims (
    id, item_report_id, report_id, claimant_id, claimant_name,
    claimant_contact, claimant_contact_hidden, private_claim_details, status
  ) values (
    gen_random_uuid(), p_report_id, p_report_id, caller_id, claimant_display_name,
    trim(p_claimant_contact), coalesce(p_claimant_contact_hidden, true),
    trim(p_private_claim_details), 'pending'
  ) returning * into claim_row;

  update public.item_reports set status = 'claimPending'
  where id = p_report_id and status = 'open';

  insert into public.claim_audit_log (claim_id, actor_id, action, previous_status, new_status)
  values (claim_row.id, caller_id, 'submitted', null, 'pending');

  insert into public.claim_notifications (recipient_id, claim_id, notification_type, title, body)
  select ur.user_id, claim_row.id, 'claim_submitted', 'New claim submitted',
         'A found-item claim is waiting for review.'
  from public.user_roles ur
  where ur.role in ('moderator', 'admin');

  return claim_row;
exception
  when unique_violation then
    raise exception 'You already have an active claim for this item';
end;
$$;
revoke all on function public.submit_claim(uuid, text, text, boolean) from public;
grant execute on function public.submit_claim(uuid, text, text, boolean) to authenticated;

create or replace function public.review_claim(
  p_claim_id uuid,
  p_status text,
  p_rejection_reason text default null
)
returns public.item_claims
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  claim_row public.item_claims;
  report_row public.item_reports;
  reason text := nullif(trim(coalesce(p_rejection_reason, '')), '');
begin
  if caller_id is null or not (public.has_role('moderator') or public.has_role('admin')) then
    raise exception 'Only moderators and administrators can review claims';
  end if;
  if p_status not in ('approved', 'rejected') then raise exception 'Invalid claim decision'; end if;
  if p_status = 'rejected' and reason is null then raise exception 'A rejection reason is required'; end if;

  select * into claim_row from public.item_claims where id = p_claim_id for update;
  if claim_row.id is null then raise exception 'Claim not found'; end if;
  if claim_row.status <> 'pending' then raise exception 'Claim was already reviewed'; end if;
  select * into report_row from public.item_reports where id = claim_row.report_id for update;
  if report_row.id is null then raise exception 'Report not found'; end if;
  if report_row.status in ('returned', 'closed') then raise exception 'This item is no longer reviewable'; end if;
  if p_status = 'approved' and exists (
    select 1 from public.item_claims where report_id = claim_row.report_id and status = 'approved'
  ) then raise exception 'This item already has an approved claim'; end if;

  update public.item_claims
  set status = p_status, reviewed_by = caller_id, reviewed_at = now(),
      rejection_reason = case when p_status = 'rejected' then reason else null end
  where id = p_claim_id returning * into claim_row;

  if p_status = 'rejected' then
    update public.item_reports set status = case when exists (
      select 1 from public.item_claims where report_id = claim_row.report_id and status = 'pending'
    ) then 'claimPending' else 'open' end where id = claim_row.report_id;
  end if;

  insert into public.claim_audit_log (claim_id, actor_id, action, previous_status, new_status)
  values (claim_row.id, caller_id,
          case when p_status = 'approved' then 'approved' else 'rejected' end,
          'pending', p_status);

  insert into public.claim_notifications (recipient_id, claim_id, notification_type, title, body)
  values
    (claim_row.claimant_id, claim_row.id,
     case when p_status = 'approved' then 'claim_approved' else 'claim_rejected' end,
     case when p_status = 'approved' then 'Claim approved' else 'Claim rejected' end,
     case when p_status = 'approved' then 'Your claim was approved and is awaiting item handover.' else 'Your claim was rejected: ' || reason end),
    (report_row.owner_id, claim_row.id, 'claim_reviewed',
     case when p_status = 'approved' then 'Claim approved - handover required' else 'Claim rejected' end,
     case when p_status = 'approved' then 'Please confirm the physical handover after meeting the claimant.' else 'A claim for your item was rejected.' end);

  return claim_row;
end;
$$;
revoke all on function public.review_claim(uuid, text, text) from public;
grant execute on function public.review_claim(uuid, text, text) to authenticated;

create or replace function public.confirm_claim_handover(p_claim_id uuid)
returns public.item_claims
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  claim_row public.item_claims;
  report_row public.item_reports;
begin
  if caller_id is null then raise exception 'You must be signed in'; end if;
  select * into claim_row from public.item_claims where id = p_claim_id for update;
  if claim_row.id is null then raise exception 'Claim not found'; end if;
  if claim_row.status <> 'approved' then raise exception 'Only approved claims can be completed'; end if;
  select * into report_row from public.item_reports where id = claim_row.report_id for update;
  if report_row.owner_id <> caller_id then raise exception 'Only the original report owner can confirm handover'; end if;
  if report_row.status in ('returned', 'closed') then raise exception 'This item is already finalized'; end if;

  update public.item_claims
  set status = 'completed', completed_at = now(), handover_confirmed_by = caller_id
  where id = p_claim_id returning * into claim_row;
  update public.item_reports set status = 'returned' where id = report_row.id;

  insert into public.claim_audit_log (claim_id, actor_id, action, previous_status, new_status)
  values (claim_row.id, caller_id, 'handover_confirmed', 'approved', 'completed');
  insert into public.claim_audit_log (claim_id, actor_id, action, previous_status, new_status)
  values (claim_row.id, caller_id, 'completed', 'approved', 'completed');
  insert into public.claim_notifications (recipient_id, claim_id, notification_type, title, body)
  values
    (claim_row.claimant_id, claim_row.id, 'claim_completed', 'Item returned', 'The item owner confirmed the physical handover.'),
    (report_row.owner_id, claim_row.id, 'claim_completed', 'Handover recorded', 'The item was marked as successfully returned.');
  return claim_row;
end;
$$;
revoke all on function public.confirm_claim_handover(uuid) from public;
grant execute on function public.confirm_claim_handover(uuid) to authenticated;

-- Disable the legacy function from supabase_claims_schema_repair.sql and the
-- earlier RBAC migration. Review decisions must use review_claim so moderators,
-- rejection reasons, audit rows, and handover semantics cannot be bypassed.
revoke all on function public.decide_claim(uuid, text) from public;

notify pgrst, 'reload schema';
