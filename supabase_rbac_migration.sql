-- MarSU Lost & Found RBAC migration. Run in Supabase SQL Editor.

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'student' check (role in ('student', 'moderator', 'admin')),
  created_at timestamptz not null default now()
);
alter table public.user_roles enable row level security;
drop policy if exists "Users can view their own role" on public.user_roles;
create policy "Users can view their own role" on public.user_roles
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on table public.user_roles from anon, authenticated, public;
grant select on table public.user_roles to authenticated;

create or replace function public.current_user_role() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select role from public.user_roles where user_id = auth.uid()), 'student');
$$;
revoke all on function public.current_user_role() from public;
grant execute on function public.current_user_role() to authenticated;

create or replace function public.has_role(required_role text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.current_user_role() = required_role;
$$;
revoke all on function public.has_role(text) from public;
grant execute on function public.has_role(text) to authenticated;

create or replace function public.handle_new_user_role() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.user_roles (user_id, role) values (new.id, 'student')
  on conflict (user_id) do nothing;
  return new;
end;
$$;
revoke all on function public.handle_new_user_role() from public;
drop trigger if exists on_auth_user_created_role on auth.users;
create trigger on_auth_user_created_role after insert on auth.users
for each row execute function public.handle_new_user_role();

insert into public.user_roles (user_id, role)
select id, 'student' from auth.users on conflict (user_id) do nothing;

create or replace function public.set_user_role(target_user_id uuid, target_role text)
returns public.user_roles language plpgsql security definer set search_path = public as $$
declare result public.user_roles;
begin
  if auth.uid() is null or not public.has_role('admin') then
    raise exception 'Only administrators can manage roles';
  end if;
  if target_user_id = auth.uid() then raise exception 'Administrators cannot change their own role'; end if;
  if target_role not in ('student', 'moderator') then
    raise exception 'Only student and moderator assignments are allowed';
  end if;
  insert into public.user_roles (user_id, role) values (target_user_id, target_role)
  on conflict (user_id) do update set role = excluded.role returning * into result;
  return result;
end;
$$;
revoke all on function public.set_user_role(uuid, text) from public;
grant execute on function public.set_user_role(uuid, text) to authenticated;

create or replace function public.list_user_roles()
returns table (user_id uuid, email text, full_name text, student_number text, role text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select ur.user_id, coalesce(au.email, ''), coalesce(up.full_name, ''),
         coalesce(up.student_number, ''), ur.role, ur.created_at
  from public.user_roles ur join auth.users au on au.id = ur.user_id
  left join public.user_profiles up on up.id = ur.user_id
  where public.has_role('admin')
  order by lower(coalesce(up.full_name, au.email, ''));
$$;
revoke all on function public.list_user_roles() from public;
grant execute on function public.list_user_roles() to authenticated;

drop policy if exists "Admins can moderate reports" on public.item_reports;
create policy "Admins can moderate reports" on public.item_reports for update to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "Claimants owners and moderators can view claims" on public.item_claims;
create policy "Claimants owners and moderators can view claims" on public.item_claims for select to authenticated
using (claimant_id = (select auth.uid())
  or exists (select 1 from public.item_reports r where r.id = report_id and r.owner_id = (select auth.uid()))
  or public.has_role('admin') or public.has_role('moderator'));

create or replace function public.decide_claim(p_claim_id uuid, p_status text)
returns public.item_claims language plpgsql security definer set search_path = public as $$
declare claim_row public.item_claims; report_row public.item_reports;
begin
  if not public.has_role('admin') then raise exception 'Only administrators can decide claims'; end if;
  if p_status not in ('approved', 'rejected') then raise exception 'Invalid claim decision'; end if;
  select * into claim_row from public.item_claims where id = p_claim_id for update;
  if claim_row.id is null then raise exception 'Claim not found'; end if;
  select * into report_row from public.item_reports where id = claim_row.report_id for update;
  if report_row.id is null then raise exception 'Report not found'; end if;
  if claim_row.status <> 'pending' then raise exception 'Claim was already decided'; end if;
  update public.item_claims set status = p_status where id = p_claim_id returning * into claim_row;
  if p_status = 'approved' then
    update public.item_claims set status = 'rejected' where report_id = claim_row.report_id and id <> claim_row.id and status = 'pending';
    update public.item_reports set status = 'returned' where id = claim_row.report_id;
  else
    update public.item_reports set status = case when exists (select 1 from public.item_claims where report_id = claim_row.report_id and status = 'pending') then 'claimPending' else 'open' end where id = claim_row.report_id;
  end if;
  return claim_row;
end;
$$;
revoke all on function public.decide_claim(uuid, text) from public;
grant execute on function public.decide_claim(uuid, text) to authenticated;

create or replace function public.update_item_status(p_report_id uuid, p_status text)
returns public.item_reports language plpgsql security definer set search_path = public as $$
declare report_row public.item_reports;
begin
  if p_status not in ('open', 'returned', 'closed') then raise exception 'Invalid item status'; end if;
  select * into report_row from public.item_reports where id = p_report_id for update;
  if report_row.id is null then raise exception 'Report not found'; end if;
  if not (public.has_role('admin') or public.has_role('moderator')) and not (report_row.owner_id = auth.uid() and p_status in ('open', 'closed')) then
    raise exception 'Not authorized to update this item status';
  end if;
  update public.item_reports set status = p_status where id = p_report_id returning * into report_row;
  return report_row;
end;
$$;
revoke all on function public.update_item_status(uuid, text) from public;
grant execute on function public.update_item_status(uuid, text) to authenticated;
notify pgrst, 'reload schema';
