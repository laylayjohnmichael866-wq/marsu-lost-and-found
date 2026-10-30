do $$
begin
  if to_regclass('public.item_claims') is null then
    create table public.item_claims (
      id uuid primary key default gen_random_uuid(),
      item_report_id uuid not null references public.item_reports(id) on delete cascade,
      report_id uuid not null references public.item_reports(id) on delete cascade,
      claimant_id uuid not null references auth.users(id) on delete cascade,
      claimant_name text not null,
      claimant_contact text not null default '',
      claimant_contact_hidden boolean not null default true,
      private_claim_details text not null default '',
      claim_message text,
      status text not null default 'pending'
        check (status in ('pending', 'approved', 'rejected', 'completed')),
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );
  end if;
end $$;

alter table public.item_claims
  add column if not exists item_report_id uuid;

alter table public.item_claims
  add column if not exists report_id uuid;

alter table public.item_claims
  add column if not exists claimant_contact text not null default '';

alter table public.item_claims
  add column if not exists claimant_contact_hidden boolean not null default true;

update public.item_claims
set report_id = item_report_id
where report_id is null and item_report_id is not null;

update public.item_claims
set item_report_id = report_id
where item_report_id is null and report_id is not null;

create or replace function public.sync_item_claim_report_ids()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.report_id is null and new.item_report_id is null then
    raise exception 'Claim must reference an item report';
  end if;

  if new.report_id is null then
    new.report_id := new.item_report_id;
  end if;

  if new.item_report_id is null then
    new.item_report_id := new.report_id;
  end if;

  if new.report_id <> new.item_report_id then
    raise exception 'Claim report identifiers must match';
  end if;

  return new;
end;
$$;

drop trigger if exists item_claims_sync_report_ids on public.item_claims;
create trigger item_claims_sync_report_ids
before insert or update on public.item_claims
for each row execute function public.sync_item_claim_report_ids();

alter table public.item_claims
  alter column item_report_id set not null;

alter table public.item_claims
  alter column report_id set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_attribute a
      on a.attrelid = c.conrelid
      and a.attnum = any (c.conkey)
    where c.conrelid = 'public.item_claims'::regclass
      and c.contype = 'f'
      and a.attname = 'item_report_id'
  ) then
    alter table public.item_claims
      add constraint item_claims_item_report_id_fkey
      foreign key (item_report_id)
      references public.item_reports(id)
      on delete cascade;
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_attribute a
      on a.attrelid = c.conrelid
      and a.attnum = any (c.conkey)
    where c.conrelid = 'public.item_claims'::regclass
      and c.contype = 'f'
      and a.attname = 'report_id'
  ) then
    alter table public.item_claims
      add constraint item_claims_report_id_fkey
      foreign key (report_id)
      references public.item_reports(id)
      on delete cascade;
  end if;
end $$;

drop index if exists public.one_pending_claim_per_report;

create unique index if not exists one_pending_claim_per_claimant
  on public.item_claims (report_id, claimant_id)
  where status = 'pending';

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
  with check (
    claimant_id = (select auth.uid())
    and status = 'pending'
    and report_id is not null
    and exists (
      select 1 from public.item_reports r
      where r.id = report_id
        and r.report_type = 'found'
        and r.owner_id <> (select auth.uid())
        and r.status in ('open', 'claimPending')
    )
  );

revoke all on table public.item_claims from anon, authenticated, public;
grant select, insert on table public.item_claims to authenticated;

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
  report_row public.item_reports;
  caller_role text := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
begin
  if caller_role <> 'admin' then
    raise exception 'Only administrators can decide claims';
  end if;

  if p_status not in ('approved', 'rejected') then
    raise exception 'Invalid claim decision';
  end if;

  select * into claim_row
  from public.item_claims
  where id = p_claim_id
  for update;

  if claim_row.id is null then
    raise exception 'Claim not found';
  end if;

  select * into report_row
  from public.item_reports
  where id = claim_row.report_id
  for update;

  if report_row.id is null then
    raise exception 'Report not found';
  end if;

  if claim_row.status <> 'pending' then
    raise exception 'Claim was already decided';
  end if;

  update public.item_claims
  set status = p_status
  where id = p_claim_id
  returning * into claim_row;

  if p_status = 'approved' then
    update public.item_claims
    set status = 'rejected'
    where report_id = claim_row.report_id
      and id <> claim_row.id
      and status = 'pending';

    update public.item_reports
    set status = 'returned'
    where id = claim_row.report_id;
  else
    update public.item_reports
    set status = case
      when exists (
        select 1 from public.item_claims
        where report_id = claim_row.report_id
          and status = 'pending'
      ) then 'claimPending'
      else 'open'
    end
    where id = claim_row.report_id;
  end if;

  return claim_row;
end;
$$;

revoke all on function public.decide_claim(uuid, text) from public;
grant execute on function public.decide_claim(uuid, text) to authenticated;

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

  select * into report_row
  from public.item_reports
  where id = p_report_id
  for update;

  if report_row.id is null then
    raise exception 'Report not found';
  end if;

  if caller_role not in ('admin', 'moderator')
     and not (
       report_row.owner_id = auth.uid()
       and p_status in ('open', 'closed')
     ) then
    raise exception 'Not authorized to update this item status';
  end if;

  update public.item_reports
  set status = p_status
  where id = p_report_id
  returning * into report_row;

  return report_row;
end;
$$;

revoke all on function public.update_item_status(uuid, text) from public;
grant execute on function public.update_item_status(uuid, text) to authenticated;

notify pgrst, 'reload schema';
