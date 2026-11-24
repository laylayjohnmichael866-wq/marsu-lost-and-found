-- ============================================================================
-- MarSU Lost & Found – QR Code System Database Migration (Phase 2)
-- Migration: 20261124150000_qr_code_system.sql
-- 
-- Tables Added:
--   1. public.item_qr_codes (Item Identification QR)
--   2. public.claim_release_qr_codes (Claim Verification QR)
--   3. public.item_release_logs (Audit Trail for Physical Item Handovers)
--
-- Security Features:
--   - Stores ONLY cryptographic token hashes (token_hash text NOT NULL UNIQUE).
--   - Never stores raw/plaintext QR tokens.
--   - Row Level Security (RLS) enabled on all tables.
--   - Atomic single-use redemption with row locking (SELECT ... FOR UPDATE).
--   - Preserves all existing tables, foreign keys, RLS policies, and workflows.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Table: public.item_qr_codes (Item Identification QR)
-- ----------------------------------------------------------------------------
create table if not exists public.item_qr_codes (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.item_reports(id) on delete cascade,
  qr_type text not null default 'item_tag' check (qr_type in ('item_tag', 'item_id')),
  token_hash text not null unique,
  qr_payload text not null,
  is_active boolean not null default true,
  generated_by uuid references auth.users(id) on delete set null,
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  revocation_reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Indexes for item_qr_codes
create index if not exists item_qr_codes_report_id_idx
  on public.item_qr_codes (report_id);

create index if not exists item_qr_codes_token_hash_idx
  on public.item_qr_codes (token_hash);

create unique index if not exists unique_active_item_qr_per_report
  on public.item_qr_codes (report_id)
  where (is_active = true);

-- RLS for item_qr_codes
alter table public.item_qr_codes enable row level security;

revoke all on table public.item_qr_codes from anon, authenticated, public;
grant select on table public.item_qr_codes to authenticated;

drop policy if exists "Users can view active item QR codes or own items" on public.item_qr_codes;
create policy "Users can view active item QR codes or own items"
  on public.item_qr_codes
  for select
  to authenticated
  using (
    is_active = true
    or exists (
      select 1 from public.item_reports r
      where r.id = report_id and r.owner_id = (select auth.uid())
    )
    or public.has_role('admin')
    or public.has_role('moderator')
  );

-- ----------------------------------------------------------------------------
-- 2. Table: public.claim_release_qr_codes (Claim Verification QR)
-- ----------------------------------------------------------------------------
create table if not exists public.claim_release_qr_codes (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid not null references public.item_claims(id) on delete cascade,
  report_id uuid not null references public.item_reports(id) on delete cascade,
  claimant_id uuid not null references auth.users(id) on delete cascade,
  token_hash text not null unique,
  status text not null default 'active'
    check (status in ('active', 'redeemed', 'expired', 'revoked')),
  expires_at timestamptz not null,
  is_redeemed boolean not null default false,
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint claim_release_qr_redemption_state_check
    check (
      (is_redeemed = true and status = 'redeemed' and redeemed_at is not null)
      or (is_redeemed = false and status <> 'redeemed')
    )
);

-- Indexes for claim_release_qr_codes
create index if not exists claim_release_qr_claim_id_idx
  on public.claim_release_qr_codes (claim_id);

create index if not exists claim_release_qr_report_id_idx
  on public.claim_release_qr_codes (report_id);

create index if not exists claim_release_qr_claimant_id_idx
  on public.claim_release_qr_codes (claimant_id);

create index if not exists claim_release_qr_token_hash_idx
  on public.claim_release_qr_codes (token_hash);

create index if not exists claim_release_qr_expires_at_idx
  on public.claim_release_qr_codes (expires_at);

create unique index if not exists unique_active_claim_release_qr
  on public.claim_release_qr_codes (claim_id)
  where (status = 'active');

-- RLS for claim_release_qr_codes
alter table public.claim_release_qr_codes enable row level security;

revoke all on table public.claim_release_qr_codes from anon, authenticated, public;
grant select on table public.claim_release_qr_codes to authenticated;

drop policy if exists "Authorized parties can view claim release QR codes" on public.claim_release_qr_codes;
create policy "Authorized parties can view claim release QR codes"
  on public.claim_release_qr_codes
  for select
  to authenticated
  using (
    claimant_id = (select auth.uid())
    or exists (
      select 1 from public.item_reports r
      where r.id = report_id and r.owner_id = (select auth.uid())
    )
    or public.has_role('admin')
    or public.has_role('moderator')
  );

-- ----------------------------------------------------------------------------
-- 3. Table: public.item_release_logs (Audit Trail for Physical Item Handovers)
-- ----------------------------------------------------------------------------
create table if not exists public.item_release_logs (
  id uuid primary key default gen_random_uuid(),
  qr_code_id uuid references public.claim_release_qr_codes(id) on delete set null,
  claim_id uuid not null references public.item_claims(id) on delete cascade,
  report_id uuid not null references public.item_reports(id) on delete cascade,
  claimant_id uuid not null references auth.users(id) on delete cascade,
  released_by uuid not null references auth.users(id) on delete cascade,
  release_method text not null default 'qr_scan'
    check (release_method in ('qr_scan', 'manual_confirmation', 'admin_override')),
  release_location text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  released_at timestamptz not null default now()
);

-- Indexes for item_release_logs
create index if not exists item_release_logs_claim_id_idx
  on public.item_release_logs (claim_id);

create index if not exists item_release_logs_report_id_idx
  on public.item_release_logs (report_id);

create index if not exists item_release_logs_claimant_id_idx
  on public.item_release_logs (claimant_id);

create index if not exists item_release_logs_released_by_idx
  on public.item_release_logs (released_by);

create index if not exists item_release_logs_released_at_idx
  on public.item_release_logs (released_at desc);

-- RLS for item_release_logs
alter table public.item_release_logs enable row level security;

revoke all on table public.item_release_logs from anon, authenticated, public;
grant select on table public.item_release_logs to authenticated;

drop policy if exists "Authorized parties can view item release logs" on public.item_release_logs;
create policy "Authorized parties can view item release logs"
  on public.item_release_logs
  for select
  to authenticated
  using (
    claimant_id = (select auth.uid())
    or released_by = (select auth.uid())
    or exists (
      select 1 from public.item_reports r
      where r.id = report_id and r.owner_id = (select auth.uid())
    )
    or public.has_role('admin')
    or public.has_role('moderator')
  );

-- ----------------------------------------------------------------------------
-- 4. Stored Procedures & Atomic Functions
-- ----------------------------------------------------------------------------

-- A) Function: public.generate_item_qr
create or replace function public.generate_item_qr(
  p_report_id uuid,
  p_token_hash text,
  p_qr_payload text,
  p_metadata jsonb default '{}'::jsonb
)
returns public.item_qr_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  report_row public.item_reports;
  new_qr public.item_qr_codes;
begin
  if caller_id is null then
    raise exception 'Authentication required to generate an item QR code';
  end if;

  if nullif(trim(coalesce(p_token_hash, '')), '') is null then
    raise exception 'A valid token hash is required';
  end if;

  if nullif(trim(coalesce(p_qr_payload, '')), '') is null then
    raise exception 'A valid QR payload is required';
  end if;

  select * into report_row from public.item_reports where id = p_report_id;
  if report_row.id is null then
    raise exception 'Item report not found';
  end if;

  if report_row.owner_id <> caller_id
     and not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'Not authorized to generate a QR code for this item report';
  end if;

  -- Deactivate any previously active QR code for this item report
  update public.item_qr_codes
  set is_active = false,
      revoked_at = now(),
      revoked_by = caller_id,
      revocation_reason = 'Replaced by newly generated QR code',
      updated_at = now()
  where report_id = p_report_id and is_active = true;

  insert into public.item_qr_codes (
    report_id,
    qr_type,
    token_hash,
    qr_payload,
    is_active,
    generated_by,
    metadata,
    created_at,
    updated_at
  ) values (
    p_report_id,
    'item_tag',
    trim(p_token_hash),
    trim(p_qr_payload),
    true,
    caller_id,
    coalesce(p_metadata, '{}'::jsonb),
    now(),
    now()
  ) returning * into new_qr;

  return new_qr;
end;
$$;

revoke all on function public.generate_item_qr(uuid, text, text, jsonb) from public;
grant execute on function public.generate_item_qr(uuid, text, text, jsonb) to authenticated;

-- B) Function: public.revoke_item_qr
create or replace function public.revoke_item_qr(
  p_qr_id uuid,
  p_reason text default 'Revoked by user'
)
returns public.item_qr_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  qr_row public.item_qr_codes;
  report_row public.item_reports;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  select * into qr_row from public.item_qr_codes where id = p_qr_id;
  if qr_row.id is null then
    raise exception 'Item QR code not found';
  end if;

  select * into report_row from public.item_reports where id = qr_row.report_id;
  if report_row.id is null then
    raise exception 'Associated item report not found';
  end if;

  if report_row.owner_id <> caller_id
     and not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'Not authorized to revoke this item QR code';
  end if;

  update public.item_qr_codes
  set is_active = false,
      revoked_at = now(),
      revoked_by = caller_id,
      revocation_reason = coalesce(nullif(trim(p_reason), ''), 'Revoked by user'),
      updated_at = now()
  where id = p_qr_id
  returning * into qr_row;

  return qr_row;
end;
$$;

revoke all on function public.revoke_item_qr(uuid, text) from public;
grant execute on function public.revoke_item_qr(uuid, text) to authenticated;

-- C) Function: public.generate_claim_release_qr
create or replace function public.generate_claim_release_qr(
  p_claim_id uuid,
  p_token_hash text,
  p_validity_hours integer default 48,
  p_metadata jsonb default '{}'::jsonb
)
returns public.claim_release_qr_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  claim_row public.item_claims;
  report_row public.item_reports;
  new_release_qr public.claim_release_qr_codes;
  valid_hours integer;
begin
  if caller_id is null then
    raise exception 'Authentication required to generate a claim release QR code';
  end if;

  if nullif(trim(coalesce(p_token_hash, '')), '') is null then
    raise exception 'A valid token hash is required';
  end if;

  select * into claim_row from public.item_claims where id = p_claim_id for update;
  if claim_row.id is null then
    raise exception 'Claim not found';
  end if;

  if claim_row.status <> 'approved' then
    raise exception 'Only approved claims can generate a release QR code';
  end if;

  if claim_row.claimant_id <> caller_id
     and not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'Only the approved claimant or staff can generate this verification QR code';
  end if;

  select * into report_row from public.item_reports where id = claim_row.report_id for update;
  if report_row.id is null then
    raise exception 'Associated item report not found';
  end if;

  if report_row.status in ('returned', 'closed') then
    raise exception 'This item has already been marked as returned or closed';
  end if;

  valid_hours := greatest(coalesce(p_validity_hours, 48), 1);

  -- Revoke any existing active release QR codes for this claim
  update public.claim_release_qr_codes
  set status = 'revoked'
  where claim_id = p_claim_id and status = 'active';

  insert into public.claim_release_qr_codes (
    claim_id,
    report_id,
    claimant_id,
    token_hash,
    status,
    expires_at,
    is_redeemed,
    metadata,
    created_at
  ) values (
    p_claim_id,
    claim_row.report_id,
    claim_row.claimant_id,
    trim(p_token_hash),
    'active',
    now() + (valid_hours || ' hours')::interval,
    false,
    coalesce(p_metadata, '{}'::jsonb),
    now()
  ) returning * into new_release_qr;

  return new_release_qr;
end;
$$;

revoke all on function public.generate_claim_release_qr(uuid, text, integer, jsonb) from public;
grant execute on function public.generate_claim_release_qr(uuid, text, integer, jsonb) to authenticated;

-- D) Function: public.verify_claim_release_qr_preview
create or replace function public.verify_claim_release_qr_preview(
  p_token_hash text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  qr_row public.claim_release_qr_codes;
  claim_row public.item_claims;
  report_row public.item_reports;
  claimant_profile public.user_profiles;
  is_valid boolean;
  validation_message text;
begin
  if caller_id is null then
    raise exception 'Authentication required to scan QR code';
  end if;

  select * into qr_row
  from public.claim_release_qr_codes
  where token_hash = trim(p_token_hash);

  if qr_row.id is null then
    raise exception 'Invalid or unrecognized QR token';
  end if;

  select * into claim_row from public.item_claims where id = qr_row.claim_id;
  select * into report_row from public.item_reports where id = qr_row.report_id;
  select * into claimant_profile from public.user_profiles where id = qr_row.claimant_id;

  -- Scanner authorization: report owner (finder) or admin/moderator
  if report_row.owner_id <> caller_id
     and not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'You are not authorized to verify release for this item';
  end if;

  -- Determine validity
  if qr_row.is_redeemed or qr_row.status = 'redeemed' then
    is_valid := false;
    validation_message := 'QR code has already been redeemed.';
  elsif qr_row.status = 'revoked' then
    is_valid := false;
    validation_message := 'QR code has been revoked.';
  elsif qr_row.expires_at < now() or qr_row.status = 'expired' then
    is_valid := false;
    validation_message := 'QR code has expired.';
  elsif claim_row.status <> 'approved' then
    is_valid := false;
    validation_message := 'Associated claim is no longer approved.';
  elsif report_row.status in ('returned', 'closed') then
    is_valid := false;
    validation_message := 'Item has already been finalized as returned.';
  else
    is_valid := true;
    validation_message := 'Valid claim release QR code.';
  end if;

  return json_build_object(
    'qr_id', qr_row.id,
    'claim_id', qr_row.claim_id,
    'report_id', qr_row.report_id,
    'item_name', report_row.item_name,
    'category', report_row.category,
    'general_location', report_row.general_location,
    'claimant_id', qr_row.claimant_id,
    'claimant_name', coalesce(claim_row.claimant_name, claimant_profile.full_name, 'Unknown'),
    'claimant_student_number', coalesce(claimant_profile.student_number, ''),
    'claim_status', claim_row.status,
    'qr_status', qr_row.status,
    'expires_at', qr_row.expires_at,
    'is_redeemed', qr_row.is_redeemed,
    'is_valid', is_valid,
    'validation_message', validation_message
  );
end;
$$;

revoke all on function public.verify_claim_release_qr_preview(text) from public;
grant execute on function public.verify_claim_release_qr_preview(text) to authenticated;

-- E) Function: public.redeem_claim_release_qr (Atomic Single-Use Redemption)
create or replace function public.redeem_claim_release_qr(
  p_token_hash text,
  p_release_location text default null,
  p_notes text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  qr_row public.claim_release_qr_codes;
  claim_row public.item_claims;
  report_row public.item_reports;
  v_release_log_id uuid;
  v_released_at timestamptz := now();
begin
  if caller_id is null then
    raise exception 'Authentication required to redeem QR code';
  end if;

  -- 1. Lock and validate the QR record atomically
  select * into qr_row
  from public.claim_release_qr_codes
  where token_hash = trim(p_token_hash)
  for update;

  if qr_row.id is null then
    raise exception 'Invalid or unrecognized QR token';
  end if;

  if qr_row.is_redeemed or qr_row.status = 'redeemed' then
    raise exception 'This claim verification QR has already been redeemed';
  end if;

  if qr_row.status = 'revoked' then
    raise exception 'This claim verification QR has been revoked';
  end if;

  if qr_row.expires_at < v_released_at or qr_row.status = 'expired' then
    update public.claim_release_qr_codes
    set status = 'expired'
    where id = qr_row.id;
    raise exception 'This claim verification QR has expired';
  end if;

  -- 2. Lock and validate associated claim and report
  select * into claim_row
  from public.item_claims
  where id = qr_row.claim_id
  for update;

  if claim_row.id is null then
    raise exception 'Associated claim record not found';
  end if;

  if claim_row.status = 'completed' then
    raise exception 'This claim has already been completed';
  end if;

  if claim_row.status <> 'approved' then
    raise exception 'Claim must be in approved status to be redeemed';
  end if;

  select * into report_row
  from public.item_reports
  where id = qr_row.report_id
  for update;

  if report_row.id is null then
    raise exception 'Associated item report record not found';
  end if;

  if report_row.status in ('returned', 'closed') then
    raise exception 'This item has already been marked as returned or closed';
  end if;

  -- 3. Authorization check
  -- Claimant cannot self-redeem their own QR code (unless authorized administrator/moderator)
  if qr_row.claimant_id = caller_id
     and not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'Claimants cannot redeem their own release QR code. Only the item finder or campus staff can verify release.';
  end if;

  if report_row.owner_id <> caller_id
     and not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'Only the item finder or campus staff are authorized to verify item release';
  end if;

  -- 4. Execute atomic state transitions
  -- Step 4a: Mark QR as redeemed
  update public.claim_release_qr_codes
  set is_redeemed = true,
      status = 'redeemed',
      redeemed_at = v_released_at,
      redeemed_by = caller_id
  where id = qr_row.id;

  -- Step 4b: Update claim status to completed
  update public.item_claims
  set status = 'completed',
      completed_at = v_released_at,
      handover_confirmed_by = caller_id,
      updated_at = v_released_at
  where id = claim_row.id;

  -- Step 4c: Update item report status to returned
  update public.item_reports
  set status = 'returned'
  where id = report_row.id;

  -- Step 4d: Create immutable item release log entry
  insert into public.item_release_logs (
    qr_code_id,
    claim_id,
    report_id,
    claimant_id,
    released_by,
    release_method,
    release_location,
    notes,
    released_at,
    metadata
  ) values (
    qr_row.id,
    claim_row.id,
    report_row.id,
    claim_row.claimant_id,
    caller_id,
    'qr_scan',
    nullif(trim(p_release_location), ''),
    nullif(trim(p_notes), ''),
    v_released_at,
    jsonb_build_object(
      'token_hash_preview', substring(qr_row.token_hash from 1 for 8) || '...',
      'claimant_name', claim_row.claimant_name,
      'item_name', report_row.item_name
    )
  ) returning id into v_release_log_id;

  -- Step 4e: Record audit log entries (compatible with claim_audit_log check constraint)
  insert into public.claim_audit_log (
    claim_id,
    actor_id,
    action,
    previous_status,
    new_status,
    created_at
  ) values (
    claim_row.id,
    caller_id,
    'handover_confirmed',
    'approved',
    'completed',
    v_released_at
  );

  insert into public.claim_audit_log (
    claim_id,
    actor_id,
    action,
    previous_status,
    new_status,
    created_at
  ) values (
    claim_row.id,
    caller_id,
    'completed',
    'approved',
    'completed',
    v_released_at
  );

  -- Step 4f: Send in-app claim notifications
  insert into public.claim_notifications (
    recipient_id,
    claim_id,
    notification_type,
    title,
    body,
    created_at
  ) values
    (
      claim_row.claimant_id,
      claim_row.id,
      'claim_completed',
      'Item returned via QR handover',
      'Your item handover has been verified and logged successfully via QR verification.',
      v_released_at
    ),
    (
      report_row.owner_id,
      claim_row.id,
      'claim_completed',
      'Item release logged',
      'You have verified and logged the physical item handover via QR verification.',
      v_released_at
    );

  return json_build_object(
    'success', true,
    'message', 'Item release verified and completed successfully.',
    'claim_id', claim_row.id,
    'report_id', report_row.id,
    'qr_code_id', qr_row.id,
    'release_log_id', v_release_log_id,
    'released_at', v_released_at
  );
end;
$$;

revoke all on function public.redeem_claim_release_qr(text, text, text) from public;
grant execute on function public.redeem_claim_release_qr(text, text, text) to authenticated;

-- Notify PostgREST schema cache reload
notify pgrst, 'reload schema';
