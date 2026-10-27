-- Run once in Supabase Dashboard > SQL Editor after the existing schema.
-- This migration does not delete existing reports or image paths.

create table if not exists public.item_claims (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.item_reports(id) on delete cascade,
  claimant_id uuid not null references auth.users(id) on delete cascade,
  claimant_name text not null,
  claimant_contact_hidden text not null,
  private_claim_details text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'completed')),
  created_at timestamptz not null default now()
);

create unique index if not exists one_pending_claim_per_report
  on public.item_claims (report_id)
  where status = 'pending';

alter table public.item_claims enable row level security;

drop policy if exists "Users can view claims" on public.item_claims;
create policy "Claimants owners and moderators can view claims"
  on public.item_claims for select to authenticated
  using (
    claimant_id = (select auth.uid())
    or exists (
      select 1 from public.item_reports r
      where r.id = report_id and r.owner_id = (select auth.uid())
    )
    or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'moderator')
  );

create policy "Users can create their own claims"
  on public.item_claims for insert to authenticated
  with check (claimant_id = (select auth.uid()));

-- Remove direct client updates. Status changes now go through the guarded RPCs.
drop policy if exists "Users can update their own reports" on public.item_reports;
drop policy if exists "Admins can moderate reports" on public.item_reports;

create or replace function public.mark_claim_pending()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.item_reports
  set status = 'claimPending'
  where id = new.report_id and status = 'open';
  return new;
end;
$$;

drop trigger if exists item_claim_pending_trigger on public.item_claims;
create trigger item_claim_pending_trigger
after insert on public.item_claims
for each row execute function public.mark_claim_pending();

create or replace function public.update_item_status(
  p_report_id uuid,
  p_status text
)
returns public.item_reports
language plpgsql
security definer
set search_path = public
as $$
declare
  report_row public.item_reports;
  caller_role text := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
begin
  if p_status not in ('open', 'returned', 'closed') then
    raise exception 'Invalid item status';
  end if;

  select * into report_row from public.item_reports
  where id = p_report_id for update;

  if report_row.id is null then raise exception 'Report not found'; end if;

  if caller_role not in ('admin', 'moderator')
     and not (report_row.owner_id = auth.uid() and p_status in ('open', 'closed')) then
    raise exception 'Not authorized to update this item status';
  end if;

  update public.item_reports
  set status = p_status
  where id = p_report_id
  returning * into report_row;
  return report_row;
end;
$$;

create or replace function public.decide_claim(
  p_claim_id uuid,
  p_status text
)
returns public.item_claims
language plpgsql
security definer
set search_path = public
as $$
declare
  claim_row public.item_claims;
  caller_role text := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
begin
  if caller_role not in ('admin', 'moderator') then
    raise exception 'Only admins and moderators can decide claims';
  end if;
  if p_status not in ('approved', 'rejected') then
    raise exception 'Invalid claim decision';
  end if;

  select * into claim_row from public.item_claims
  where id = p_claim_id for update;
  if claim_row.id is null then raise exception 'Claim not found'; end if;
  if claim_row.status <> 'pending' then raise exception 'Claim was already decided'; end if;

  update public.item_claims
  set status = p_status
  where id = p_claim_id
  returning * into claim_row;

  update public.item_reports
  set status = case when p_status = 'approved' then 'returned' else 'open' end
  where id = claim_row.report_id;
  return claim_row;
end;
$$;

revoke all on function public.update_item_status(uuid, text) from public;
grant execute on function public.update_item_status(uuid, text) to authenticated;
revoke all on function public.decide_claim(uuid, text) from public;
grant execute on function public.decide_claim(uuid, text) to authenticated;
