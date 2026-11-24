-- ============================================================================
-- MarSU Lost & Found – QR Code System Backend Operations (Phase 3)
-- Migration: 20261124160000_qr_backend_operations.sql
-- (Mirror for Supabase SQL Editor execution)
--
-- Backend Operations Implemented:
--   1. verify_item_qr: Item QR Verification & Public Info Retrieval
--   2. verify_claim_qr: Claim QR Verification with clear result statuses:
--      (Valid, Invalid, Expired, Revoked, Already Used)
--   3. admin_release_claim_item: Secure, atomic item release by administrators
--      with explicit confirmation requirement & audit logging
--   4. admin_revoke_item_qr: Administrator revocation of item QR tags
--   5. admin_revoke_claim_qr: Administrator revocation of claim release QR codes
--   6. admin_list_item_qr_codes: Admin overview of all item QR codes
--   7. admin_list_claim_qr_codes: Admin overview of all claim release QR codes
--
-- Security Features:
--   - Supabase auth.uid() identity validation
--   - RBAC enforcement via public.has_role('admin') / public.has_role('moderator')
--   - Single-use atomic locking (SELECT ... FOR UPDATE)
--   - Cryptographic SHA-256 token hashing (raw tokens are never stored)
--   - Comprehensive item release audit trail logging
--   - Preserves all Phase 1 & Phase 2 tables, policies, and workflows
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Function: public.verify_item_qr (Item QR Verification)
-- ----------------------------------------------------------------------------
create or replace function public.verify_item_qr(
  p_token text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cleaned_token text;
  v_token_hash text;
  qr_row public.item_qr_codes;
  report_row public.item_reports;
begin
  v_cleaned_token := trim(coalesce(p_token, ''));
  if v_cleaned_token = '' then
    return json_build_object(
      'is_valid', false,
      'status', 'invalid',
      'message', 'A QR token or identifier is required.'
    );
  end if;

  -- Support both direct token hash and raw token by computing SHA-256 digest
  -- If token is already 64-char hex, check direct match first
  if length(v_cleaned_token) = 64 and v_cleaned_token ~* '^[a-f0-9]{64}$' then
    select * into qr_row
    from public.item_qr_codes
    where token_hash = v_cleaned_token;
  end if;

  -- If not found by direct hash, compute SHA-256 of raw token string
  if qr_row.id is null then
    v_token_hash := encode(sha256(convert_to(v_cleaned_token, 'UTF8')), 'hex');
    select * into qr_row
    from public.item_qr_codes
    where token_hash = v_token_hash;
  end if;

  -- Also check if token matches qr_payload or report_id as fallback
  if qr_row.id is null then
    select * into qr_row
    from public.item_qr_codes
    where qr_payload = v_cleaned_token and is_active = true
    order by created_at desc
    limit 1;
  end if;

  if qr_row.id is null then
    return json_build_object(
      'is_valid', false,
      'status', 'not_found',
      'message', 'Invalid or unrecognized item QR code.'
    );
  end if;

  -- Check if QR code is revoked or inactive
  if not qr_row.is_active then
    return json_build_object(
      'is_valid', false,
      'status', 'revoked',
      'qr_id', qr_row.id,
      'report_id', qr_row.report_id,
      'revoked_at', qr_row.revoked_at,
      'revocation_reason', coalesce(qr_row.revocation_reason, 'Revoked by authorized user'),
      'message', 'This item QR code has been revoked and is no longer active.'
    );
  end if;

  -- Retrieve associated item report
  select * into report_row
  from public.item_reports
  where id = qr_row.report_id;

  if report_row.id is null then
    return json_build_object(
      'is_valid', false,
      'status', 'missing_report',
      'message', 'Associated item report no longer exists.'
    );
  end if;

  -- Return ONLY permitted public information (no private personal contact details)
  return json_build_object(
    'is_valid', true,
    'status', 'active',
    'qr_id', qr_row.id,
    'report_id', report_row.id,
    'item_name', report_row.item_name,
    'category', report_row.category,
    'report_type', report_row.report_type,
    'general_location', report_row.general_location,
    'incident_date', report_row.incident_date,
    'report_status', report_row.status,
    'image_path', report_row.image_path,
    'qr_type', qr_row.qr_type,
    'qr_payload', qr_row.qr_payload,
    'created_at', qr_row.created_at,
    'message', 'Valid active item QR code.'
  );
end;
$$;

revoke all on function public.verify_item_qr(text) from public;
grant execute on function public.verify_item_qr(text) to authenticated, anon;

-- ----------------------------------------------------------------------------
-- 2. Function: public.verify_claim_qr (Claim QR Verification with Clear Statuses)
-- Statuses: Valid, Invalid, Expired, Revoked, Already Used
-- ----------------------------------------------------------------------------
create or replace function public.verify_claim_qr(
  p_token text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  v_cleaned_token text;
  v_token_hash text;
  qr_row public.claim_release_qr_codes;
  claim_row public.item_claims;
  report_row public.item_reports;
  claimant_profile public.user_profiles;
  v_result text;
  v_is_valid boolean;
  v_message text;
begin
  if caller_id is null then
    raise exception 'Authentication required to verify claim release QR codes';
  end if;

  v_cleaned_token := trim(coalesce(p_token, ''));
  if v_cleaned_token = '' then
    return json_build_object(
      'result', 'Invalid',
      'is_valid', false,
      'message', 'QR token is required.'
    );
  end if;

  -- Check direct 64-char hex hash first
  if length(v_cleaned_token) = 64 and v_cleaned_token ~* '^[a-f0-9]{64}$' then
    select * into qr_row
    from public.claim_release_qr_codes
    where token_hash = v_cleaned_token;
  end if;

  -- Compute SHA-256 of raw token if not matched directly
  if qr_row.id is null then
    v_token_hash := encode(sha256(convert_to(v_cleaned_token, 'UTF8')), 'hex');
    select * into qr_row
    from public.claim_release_qr_codes
    where token_hash = v_token_hash;
  end if;

  if qr_row.id is null then
    return json_build_object(
      'result', 'Invalid',
      'is_valid', false,
      'message', 'Invalid or unrecognized claim QR token.'
    );
  end if;

  select * into claim_row from public.item_claims where id = qr_row.claim_id;
  select * into report_row from public.item_reports where id = qr_row.report_id;
  select * into claimant_profile from public.user_profiles where id = qr_row.claimant_id;

  -- Authorization check: claimant, report owner (finder), or campus staff (admin/moderator)
  if qr_row.claimant_id <> caller_id
     and report_row.owner_id <> caller_id
     and not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'You are not authorized to inspect this claim verification QR code';
  end if;

  -- Validate distinct lifecycle states in order of priority:
  -- 1. Already Used (Redeemed)
  if qr_row.is_redeemed or qr_row.status = 'redeemed' then
    v_result := 'Already Used';
    v_is_valid := false;
    v_message := 'This claim QR code has already been redeemed and completed.';

  -- 2. Revoked
  elsif qr_row.status = 'revoked' then
    v_result := 'Revoked';
    v_is_valid := false;
    v_message := 'This claim QR code has been revoked by campus administration.';

  -- 3. Expired
  elsif qr_row.expires_at < now() or qr_row.status = 'expired' then
    -- Synchronize expired status in DB
    if qr_row.status <> 'expired' then
      update public.claim_release_qr_codes
      set status = 'expired'
      where id = qr_row.id;
    end if;
    v_result := 'Expired';
    v_is_valid := false;
    v_message := 'This claim QR code has expired. A new code must be generated.';

  -- 4. Claim no longer approved
  elsif claim_row.id is null or claim_row.status <> 'approved' then
    v_result := 'Invalid';
    v_is_valid := false;
    v_message := 'The associated claim is no longer in approved status.';

  -- 5. Item already returned or closed
  elsif report_row.id is null or report_row.status in ('returned', 'closed') then
    v_result := 'Already Used';
    v_is_valid := false;
    v_message := 'The associated item has already been marked as returned or closed.';

  -- 6. Valid
  else
    v_result := 'Valid';
    v_is_valid := true;
    v_message := 'Valid claim verification QR code. Ready for release confirmation.';
  end if;

  return json_build_object(
    'result', v_result,
    'is_valid', v_is_valid,
    'qr_id', qr_row.id,
    'claim_id', qr_row.claim_id,
    'report_id', qr_row.report_id,
    'claimant_id', qr_row.claimant_id,
    'claimant_name', coalesce(claim_row.claimant_name, claimant_profile.full_name, 'Unknown Claimant'),
    'claimant_student_number', coalesce(claimant_profile.student_number, ''),
    'item_name', coalesce(report_row.item_name, 'Unknown Item'),
    'category', coalesce(report_row.category, ''),
    'general_location', coalesce(report_row.general_location, ''),
    'claim_status', coalesce(claim_row.status, ''),
    'qr_status', qr_row.status,
    'expires_at', qr_row.expires_at,
    'is_redeemed', qr_row.is_redeemed,
    'redeemed_at', qr_row.redeemed_at,
    'message', v_message
  );
end;
$$;

revoke all on function public.verify_claim_qr(text) from public;
grant execute on function public.verify_claim_qr(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. Function: public.admin_release_claim_item (Secure Item Release)
-- Requires:
--   - Authorized administrator/moderator role
--   - Explicit confirmation (p_confirmed = true)
--   - Atomic transaction with row-level locks (FOR UPDATE)
--   - Item release audit trail & notification logging
-- ----------------------------------------------------------------------------
create or replace function public.admin_release_claim_item(
  p_claim_id uuid,
  p_token_hash text default null,
  p_confirmed boolean default false,
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
  v_released_at timestamptz := now();
  qr_row public.claim_release_qr_codes;
  claim_row public.item_claims;
  report_row public.item_reports;
  v_release_log_id uuid;
  v_method text := 'admin_override';
begin
  -- 1. Authentication & Role Check
  if caller_id is null then
    raise exception 'Authentication required to release an item';
  end if;

  if not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'Only authorized campus administrators or moderators can execute item releases';
  end if;

  -- 2. Explicit Confirmation Requirement
  if p_confirmed is not true then
    raise exception 'Explicit administrator confirmation is required to finalize item release';
  end if;

  -- 3. Lock Claim row
  select * into claim_row
  from public.item_claims
  where id = p_claim_id
  for update;

  if claim_row.id is null then
    raise exception 'Target claim record not found';
  end if;

  if claim_row.status = 'completed' then
    raise exception 'This claim has already been completed and handed over';
  end if;

  if claim_row.status <> 'approved' then
    raise exception 'Item release requires the claim to be in approved status (current: %)', claim_row.status;
  end if;

  -- 4. Lock Item Report row
  select * into report_row
  from public.item_reports
  where id = claim_row.report_id
  for update;

  if report_row.id is null then
    raise exception 'Associated item report not found';
  end if;

  if report_row.status in ('returned', 'closed') then
    raise exception 'This item is already marked as %', report_row.status;
  end if;

  -- 5. Lock and update QR record if token provided or active QR exists
  if nullif(trim(coalesce(p_token_hash, '')), '') is not null then
    select * into qr_row
    from public.claim_release_qr_codes
    where claim_id = p_claim_id
      and (token_hash = trim(p_token_hash)
           or token_hash = encode(sha256(convert_to(trim(p_token_hash), 'UTF8')), 'hex'))
    for update;
    v_method := 'qr_scan';
  else
    select * into qr_row
    from public.claim_release_qr_codes
    where claim_id = p_claim_id and status = 'active'
    order by created_at desc
    limit 1
    for update;
  end if;

  if qr_row.id is not null then
    if qr_row.is_redeemed or qr_row.status = 'redeemed' then
      raise exception 'This claim QR code has already been redeemed';
    end if;

    update public.claim_release_qr_codes
    set is_redeemed = true,
        status = 'redeemed',
        redeemed_at = v_released_at,
        redeemed_by = caller_id
    where id = qr_row.id;
  end if;

  -- 6. Atomic state transitions
  -- Update claim status to completed
  update public.item_claims
  set status = 'completed',
      completed_at = v_released_at,
      handover_confirmed_by = caller_id,
      updated_at = v_released_at
  where id = claim_row.id;

  -- Update item report status to returned
  update public.item_reports
  set status = 'returned'
  where id = report_row.id;

  -- 7. Insert Item Release Audit Trail Entry
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
    v_method,
    nullif(trim(p_release_location), ''),
    nullif(trim(p_notes), ''),
    v_released_at,
    jsonb_build_object(
      'admin_id', caller_id,
      'claimant_id', claim_row.claimant_id,
      'claimant_name', claim_row.claimant_name,
      'item_name', report_row.item_name,
      'confirmed_explicitly', true
    )
  ) returning id into v_release_log_id;

  -- 8. Insert into claim_audit_log
  insert into public.claim_audit_log (
    claim_id,
    actor_id,
    action,
    previous_status,
    new_status,
    created_at
  ) values
    (claim_row.id, caller_id, 'handover_confirmed', 'approved', 'completed', v_released_at),
    (claim_row.id, caller_id, 'completed', 'approved', 'completed', v_released_at);

  -- 9. Insert Notifications
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
      'Belonging Handover Completed',
      'Your approved claim for "' || report_row.item_name || '" has been officially released and completed by campus administration.',
      v_released_at
    ),
    (
      report_row.owner_id,
      claim_row.id,
      'claim_completed',
      'Item Release Completed',
      'The belonging "' || report_row.item_name || '" has been verified and released to claimant ' || claim_row.claimant_name || '.',
      v_released_at
    );

  return json_build_object(
    'success', true,
    'message', 'Item release confirmed and completed successfully by administrator.',
    'claim_id', claim_row.id,
    'report_id', report_row.id,
    'release_log_id', v_release_log_id,
    'released_by', caller_id,
    'claimant_id', claim_row.claimant_id,
    'released_at', v_released_at
  );
end;
$$;

revoke all on function public.admin_release_claim_item(uuid, text, boolean, text, text) from public;
grant execute on function public.admin_release_claim_item(uuid, text, boolean, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Function: public.admin_revoke_item_qr
-- ----------------------------------------------------------------------------
create or replace function public.admin_revoke_item_qr(
  p_qr_id uuid,
  p_reason text default 'Revoked by administrator'
)
returns public.item_qr_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  qr_row public.item_qr_codes;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  if not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'Only administrators or moderators can perform administrative QR revocation';
  end if;

  select * into qr_row from public.item_qr_codes where id = p_qr_id;
  if qr_row.id is null then
    raise exception 'Item QR code not found';
  end if;

  update public.item_qr_codes
  set is_active = false,
      revoked_at = now(),
      revoked_by = caller_id,
      revocation_reason = coalesce(nullif(trim(p_reason), ''), 'Revoked by administrator'),
      updated_at = now()
  where id = p_qr_id
  returning * into qr_row;

  return qr_row;
end;
$$;

revoke all on function public.admin_revoke_item_qr(uuid, text) from public;
grant execute on function public.admin_revoke_item_qr(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. Function: public.admin_revoke_claim_qr
-- ----------------------------------------------------------------------------
create or replace function public.admin_revoke_claim_qr(
  p_qr_id uuid,
  p_reason text default 'Revoked by administrator'
)
returns public.claim_release_qr_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  qr_row public.claim_release_qr_codes;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  if not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'Only administrators or moderators can revoke claim release QR codes';
  end if;

  select * into qr_row from public.claim_release_qr_codes where id = p_qr_id;
  if qr_row.id is null then
    raise exception 'Claim release QR code not found';
  end if;

  if qr_row.is_redeemed or qr_row.status = 'redeemed' then
    raise exception 'Cannot revoke a QR code that has already been redeemed';
  end if;

  update public.claim_release_qr_codes
  set status = 'revoked',
      metadata = jsonb_set(
        jsonb_set(metadata, '{revoked_by}', to_jsonb(caller_id::text)),
        '{revocation_reason}',
        to_jsonb(coalesce(nullif(trim(p_reason), ''), 'Revoked by administrator'))
      )
  where id = p_qr_id
  returning * into qr_row;

  return qr_row;
end;
$$;

revoke all on function public.admin_revoke_claim_qr(uuid, text) from public;
grant execute on function public.admin_revoke_claim_qr(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 6. Function: public.admin_list_item_qr_codes
-- ----------------------------------------------------------------------------
create or replace function public.admin_list_item_qr_codes()
returns table (
  id uuid,
  report_id uuid,
  qr_type text,
  token_hash text,
  qr_payload text,
  is_active boolean,
  generated_by uuid,
  revoked_by uuid,
  revoked_at timestamptz,
  revocation_reason text,
  created_at timestamptz,
  item_name text,
  category text,
  report_type text,
  owner_id uuid,
  owner_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'Administrator access required';
  end if;

  return query
  select
    q.id,
    q.report_id,
    q.qr_type,
    q.token_hash,
    q.qr_payload,
    q.is_active,
    q.generated_by,
    q.revoked_by,
    q.revoked_at,
    q.revocation_reason,
    q.created_at,
    r.item_name,
    r.category,
    r.report_type,
    r.owner_id,
    r.owner_name
  from public.item_qr_codes q
  left join public.item_reports r on r.id = q.report_id
  order by q.created_at desc;
end;
$$;

revoke all on function public.admin_list_item_qr_codes() from public;
grant execute on function public.admin_list_item_qr_codes() to authenticated;

-- ----------------------------------------------------------------------------
-- 7. Function: public.admin_list_claim_qr_codes
-- ----------------------------------------------------------------------------
create or replace function public.admin_list_claim_qr_codes()
returns table (
  id uuid,
  claim_id uuid,
  report_id uuid,
  claimant_id uuid,
  claimant_name text,
  token_hash text,
  status text,
  expires_at timestamptz,
  is_redeemed boolean,
  redeemed_at timestamptz,
  redeemed_by uuid,
  created_at timestamptz,
  item_name text,
  category text,
  claim_status text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'Administrator access required';
  end if;

  return query
  select
    cq.id,
    cq.claim_id,
    cq.report_id,
    cq.claimant_id,
    c.claimant_name,
    cq.token_hash,
    cq.status,
    cq.expires_at,
    cq.is_redeemed,
    cq.redeemed_at,
    cq.redeemed_by,
    cq.created_at,
    r.item_name,
    r.category,
    c.status as claim_status
  from public.claim_release_qr_codes cq
  left join public.item_claims c on c.id = cq.claim_id
  left join public.item_reports r on r.id = cq.report_id
  order by cq.created_at desc;
end;
$$;

revoke all on function public.admin_list_claim_qr_codes() from public;
grant execute on function public.admin_list_claim_qr_codes() to authenticated;

-- Notify PostgREST schema cache reload
notify pgrst, 'reload schema';
