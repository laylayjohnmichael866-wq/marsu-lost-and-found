create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  student_number text not null default '',
  email text not null default '',
  college text not null default '',
  course text not null default '',
  year_level text not null default '',
  contact_number text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists user_profiles_student_number_unique
  on public.user_profiles (lower(trim(student_number)))
  where trim(student_number) <> '';

create index if not exists user_profiles_email_idx
  on public.user_profiles (lower(email));

alter table public.user_profiles enable row level security;

drop policy if exists "Users can view their own profile" on public.user_profiles;
create policy "Users can view their own profile"
  on public.user_profiles for select to authenticated
  using (id = (select auth.uid()));

drop policy if exists "Users can insert their own profile" on public.user_profiles;
create policy "Users can insert their own profile"
  on public.user_profiles for insert to authenticated
  with check (id = (select auth.uid()));

drop policy if exists "Users can update their own profile" on public.user_profiles;
create policy "Users can update their own profile"
  on public.user_profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create or replace function public.set_user_profile_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists user_profiles_set_updated_at on public.user_profiles;
create trigger user_profiles_set_updated_at
before update on public.user_profiles
for each row execute function public.set_user_profile_updated_at();

create or replace function public.prevent_student_number_change()
returns trigger
language plpgsql
as $$
begin
  if trim(coalesce(old.student_number, '')) <> ''
     and new.student_number is distinct from old.student_number then
    raise exception 'Student number cannot be changed';
  end if;

  if trim(coalesce(new.student_number, '')) = '' then
    new.student_number := old.student_number;
  end if;

  return new;
end;
$$;

drop trigger if exists user_profiles_prevent_student_number_change on public.user_profiles;
create trigger user_profiles_prevent_student_number_change
before update on public.user_profiles
for each row execute function public.prevent_student_number_change();

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full_name text := trim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  v_student_number text := trim(
    coalesce(
      new.raw_user_meta_data ->> 'student_number',
      new.raw_user_meta_data ->> 'student_or_emp_id',
      ''
    )
  );
begin
  if v_full_name = '' and v_student_number = '' then
    return new;
  end if;

  insert into public.user_profiles (
    id,
    full_name,
    student_number,
    email,
    college,
    course,
    year_level,
    contact_number
  )
  values (
    new.id,
    v_full_name,
    v_student_number,
    coalesce(new.email, ''),
    trim(coalesce(new.raw_user_meta_data ->> 'college', '')),
    trim(coalesce(new.raw_user_meta_data ->> 'course', '')),
    trim(coalesce(new.raw_user_meta_data ->> 'year_level', '')),
    trim(coalesce(new.raw_user_meta_data ->> 'contact_number', ''))
  )
  on conflict (id) do nothing;

  return new;
exception
  when unique_violation then
    raise exception 'Student number is already registered.'
      using errcode = '23505';
end;
$$;

revoke all on function public.handle_new_user_profile() from public;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute function public.handle_new_user_profile();

create or replace function public.is_student_number_available(
  p_student_number text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1
    from public.user_profiles
    where trim(student_number) <> ''
      and lower(trim(student_number)) = lower(trim(p_student_number))
  );
$$;

revoke all on function public.is_student_number_available(text) from public;
grant execute on function public.is_student_number_available(text)
  to anon, authenticated;

revoke all on table public.user_profiles from anon, public;
grant select, insert, update on table public.user_profiles to authenticated;

notify pgrst, 'reload schema';
