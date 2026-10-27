-- Safe repair for the existing MarSU Lost & Found claim schema.
-- Run once in Supabase Dashboard > SQL Editor.
-- This script does not drop tables, columns, rows, or relationships.

do $$
begin
  if to_regclass('public.item_claims') is null then
    create table public.item_claims (
      id uuid primary key default gen_random_uuid(),
      report_id uuid not null references public.item_reports(id) on delete cascade,
      claimant_id uuid not null references auth.users(id) on delete cascade,
      claimant_name text not null,
      claimant_contact_hidden text not null default '',
      private_claim_details text not null,
      status text not null default 'pending'
        check (status in ('pending', 'approved', 'rejected', 'completed')),
      created_at timestamptz not null default now()
    );
  else
    -- The Flutter model and payload use report_id. Preserve old data if an
    -- earlier table used item_report_id instead.
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'item_claims'
        and column_name = 'item_report_id'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'item_claims'
        and column_name = 'report_id'
    ) then
      alter table public.item_claims rename column item_report_id to report_id;
    end if;

    -- The correct application column is claimant_contact_hidden. If a
    -- legacy typo exists and the correct column does not, rename it safely.
    -- Both misspellings have appeared in older versions of this schema.
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'item_claims'
        and column_name = 'claimant_contactt_hidden'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'item_claims'
        and column_name = 'claimant_contact_hidden'
    ) then
      alter table public.item_claims
        rename column claimant_contactt_hidden to claimant_contact_hidden;
    end if;

    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'item_claims'
        and column_name = 'claimant_contacr_hidden'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'item_claims'
        and column_name = 'claimant_contact_hidden'
    ) then
      alter table public.item_claims
        rename column claimant_contacr_hidden to claimant_contact_hidden;
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'item_claims'
        and column_name = 'claimant_contact_hidden'
    ) then
      alter table public.item_claims
        add column claimant_contact_hidden text not null default '';
    end if;

    -- The application stores the claimant contact value as text (for example,
    -- a phone number). Convert an incorrectly-created boolean column without
    -- dropping the column or existing rows.
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'item_claims'
        and column_name = 'claimant_contact_hidden'
        and data_type = 'boolean'
    ) then
      alter table public.item_claims
        alter column claimant_contact_hidden type text
        using claimant_contact_hidden::text;
    end if;
  end if;
end $$;

alter table public.item_claims enable row level security;

drop policy if exists "Claimants owners and moderators can view claims"
  on public.item_claims;
create policy "Claimants owners and moderators can view claims"
  on public.item_claims for select to authenticated
  using (
    claimant_id = (select auth.uid())
    or exists (
      select 1 from public.item_reports r
      where r.id = report_id and r.owner_id = (select auth.uid())
    )
    or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
       in ('admin', 'moderator')
  );

drop policy if exists "Users can create their own claims"
  on public.item_claims;
create policy "Users can create their own claims"
  on public.item_claims for insert to authenticated
  with check (claimant_id = (select auth.uid()));

-- No UPDATE or DELETE policy is granted to ordinary clients. Decisions use
-- the guarded decide_claim RPC below.

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

  select * into claim_row
  from public.item_claims
  where id = p_claim_id
  for update;

  if claim_row.id is null then raise exception 'Claim not found'; end if;
  if claim_row.status <> 'pending' then
    raise exception 'Claim was already decided';
  end if;

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

revoke all on function public.decide_claim(uuid, text) from public;
grant execute on function public.decide_claim(uuid, text) to authenticated;

notify pgrst, 'reload schema';
