-- ============================================================================
-- MarSU Lost & Found – Phase 3: QR Scanner & Verification Hardening
-- Migration: 20261126120000_qr_scanner_verification_hardening.sql
--
-- Purpose:
--   1. Harden public.verify_item_qr(p_token) to require authentication,
--      validate strictly via SHA-256(raw_token) (no direct hash/payload bypass),
--      and scope returned item fields by caller permissions.
--   2. Harden public.verify_claim_qr(p_token) to validate strictly via
--      SHA-256(raw_token), verify claimant/finder/staff authorization,
--      and return unambiguous lifecycle states + can_release permission.
--   3. Add public.redeem_verified_claim_qr(p_token, p_confirmed, ...) for atomic
--      camera-scanned claim QR redemption by authorized administrators/moderators.
--   4. Harden public.admin_release_claim_item(...) so supplied tokens/hashes
--      cannot silently bypass missing, revoked, or expired QR validation.
--   5. Add public.admin_list_release_logs() for release transaction history.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Hardened Item QR Verification (public.verify_item_qr)
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
  caller_id uuid := auth.uid();
  v_cleaned_token text;
  v_token_hash text;
  v_viewer_role text;
  v_is_staff boolean;
  v_is_owner boolean;
  v_is_available boolean;
  v_can_claim boolean;
  v_has_active_claim boolean := false;
  v_active_claim_count integer := 0;
  qr_row public.item_qr_codes;
  report_row public.item_reports;
begin
  if caller_id is null then
    raise exception 'Authentication required to verify item QR codes';
  end if;

  v_cleaned_token := trim(coalesce(p_token, ''));
  if v_cleaned_token ~* '^marsu://.*[?&]token=' then
    v_cleaned_token := trim(coalesce(substring(v_cleaned_token from '[?&]token=([^&]+)'), ''));
  end if;

  if v_cleaned_token = '' then
    return json_build_object(
      'is_valid', false,
      'status', 'invalid',
      'is_available', false,
      'message', 'A valid QR token is required.'
    );
  end if;

  v_viewer_role := public.current_user_role();
  v_is_staff := (v_viewer_role in ('admin', 'moderator'));

  -- Always compute SHA-256 of the scanned raw token; never accept raw token_hash directly
  v_token_hash := encode(sha256(convert_to(v_cleaned_token, 'UTF8')), 'hex');

  select * into qr_row
  from public.item_qr_codes
  where token_hash = v_token_hash;

  if qr_row.id is null then
    return json_build_object(
      'is_valid', false,
      'status', 'invalid',
      'is_available', false,
      'viewer_role', v_viewer_role,
      'message', 'Invalid or unrecognized item QR code.'
    );
  end if;

  select * into report_row
  from public.item_reports
  where id = qr_row.report_id;

  if report_row.id is null then
    return json_build_object(
      'is_valid', false,
      'status', 'missing_report',
      'is_available', false,
      'qr_id', qr_row.id,
      'report_id', qr_row.report_id,
      'viewer_role', v_viewer_role,
      'message', 'Associated item report has been deleted or is unavailable.'
    );
  end if;

  v_is_owner := (report_row.owner_id = caller_id);

  if not qr_row.is_active then
    return json_build_object(
      'is_valid', false,
      'status', 'revoked',
      'is_available', false,
      'qr_id', qr_row.id,
      'report_id', qr_row.report_id,
      'item_name', case when (v_is_owner or v_is_staff) then report_row.item_name else null end,
      'revoked_at', qr_row.revoked_at,
      'revocation_reason', coalesce(qr_row.revocation_reason, 'Revoked by authorized user'),
      'viewer_role', v_viewer_role,
      'is_owner', v_is_owner,
      'is_staff', v_is_staff,
      'message', 'This item QR code has been revoked and is no longer active.'
    );
  end if;

  if report_row.is_flagged and not (v_is_owner or v_is_staff) then
    return json_build_object(
      'is_valid', false,
      'status', 'unavailable',
      'is_available', false,
      'qr_id', qr_row.id,
      'report_id', report_row.id,
      'viewer_role', v_viewer_role,
      'is_owner', false,
      'is_staff', false,
      'message', 'This item report is currently unavailable while under moderation review.'
    );
  end if;

  v_is_available := (report_row.status in ('open', 'claimPending') and not report_row.is_flagged);
  v_can_claim := (
    report_row.report_type = 'found'
    and report_row.status in ('open', 'claimPending')
    and not report_row.is_flagged
    and not v_is_owner
  );

  select exists (
    select 1
    from public.item_claims c
    where c.report_id = report_row.id
      and c.claimant_id = caller_id
      and c.status in ('pending', 'approved')
  ) into v_has_active_claim;

  if v_is_owner or v_is_staff then
    select count(*)::integer into v_active_claim_count
    from public.item_claims c
    where c.report_id = report_row.id
      and c.status in ('pending', 'approved');
  end if;

  return json_build_object(
    'is_valid', true,
    'status', case when v_is_available then 'active' else 'unavailable' end,
    'is_available', v_is_available,
    'qr_id', qr_row.id,
    'report_id', report_row.id,
    'item_name', report_row.item_name,
    'category', report_row.category,
    'report_type', report_row.report_type,
    'description', report_row.description,
    'general_location', report_row.general_location,
    'incident_date', report_row.incident_date,
    'report_status', report_row.status,
    'image_path', report_row.image_path,
    'qr_type', qr_row.qr_type,
    'created_at', qr_row.created_at,
    'viewer_role', v_viewer_role,
    'is_owner', v_is_owner,
    'is_staff', v_is_staff,
    'can_claim', v_can_claim and not v_has_active_claim,
    'has_active_claim', v_has_active_claim,
    'owner_id', case when (v_is_owner or v_is_staff) then report_row.owner_id else null end,
    'owner_name', case when (v_is_owner or v_is_staff) then report_row.owner_name else null end,
    'is_flagged', case when (v_is_owner or v_is_staff) then report_row.is_flagged else null end,
    'active_claim_count', case when (v_is_owner or v_is_staff) then v_active_claim_count else null end,
    'message', case
      when report_row.is_flagged then 'This item report is flagged for moderation review.'
      when report_row.status = 'returned' then 'This item has already been marked as returned.'
      when report_row.status = 'closed' then 'This item report has been closed and is no longer active.'
      else 'Valid active item QR code.'
    end
  );
end;
$$;

revoke all on function public.verify_item_qr(text) from public, anon;
grant execute on function public.verify_item_qr(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. Hardened Claim QR Verification (public.verify_claim_qr)
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
  v_viewer_role text;
  v_is_staff boolean;
  v_is_claimant boolean;
  v_is_report_owner boolean;
  qr_row public.claim_release_qr_codes;
  claim_row public.item_claims;
  report_row public.item_reports;
  claimant_profile public.user_profiles;
  redeemer_profile public.user_profiles;
  v_result text;
  v_is_valid boolean;
  v_can_release boolean;
  v_message text;
begin
  if caller_id is null then
    raise exception 'Authentication required to verify claim release QR codes';
  end if;

  v_viewer_role := public.current_user_role();
  v_is_staff := (v_viewer_role in ('admin', 'moderator'));

  v_cleaned_token := trim(coalesce(p_token, ''));
  if v_cleaned_token ~* '^marsu://.*[?&]token=' then
    v_cleaned_token := trim(coalesce(substring(v_cleaned_token from '[?&]token=([^&]+)'), ''));
  end if;

  if v_cleaned_token = '' then
    return json_build_object(
      'result', 'Invalid',
      'is_valid', false,
      'can_release', false,
      'viewer_role', v_viewer_role,
      'message', 'A valid claim QR token is required.'
    );
  end if;

  -- Strictly compute SHA-256 of the raw token; never accept raw token_hash directly
  v_token_hash := encode(sha256(convert_to(v_cleaned_token, 'UTF8')), 'hex');

  select * into qr_row
  from public.claim_release_qr_codes
  where token_hash = v_token_hash;

  if qr_row.id is null then
    return json_build_object(
      'result', 'Invalid',
      'is_valid', false,
      'can_release', false,
      'viewer_role', v_viewer_role,
      'message', 'Invalid or unrecognized claim QR code.'
    );
  end if;

  select * into claim_row from public.item_claims where id = qr_row.claim_id;
  select * into report_row from public.item_reports where id = qr_row.report_id;

  v_is_claimant := (qr_row.claimant_id = caller_id);
  v_is_report_owner := (report_row.id is not null and report_row.owner_id = caller_id);

  -- Enforce strict server-side authorization; never leak claim/item data to unauthorized callers
  if not (v_is_staff or v_is_claimant or v_is_report_owner) then
    return json_build_object(
      'result', 'Unauthorized',
      'is_valid', false,
      'can_release', false,
      'viewer_role', v_viewer_role,
      'message', 'You are not authorized to inspect or verify this claim QR code.'
    );
  end if;

  select * into claimant_profile from public.user_profiles where id = qr_row.claimant_id;
  if qr_row.redeemed_by is not null then
    select * into redeemer_profile from public.user_profiles where id = qr_row.redeemed_by;
  end if;

  -- Evaluate lifecycle states in strict priority order
  if qr_row.is_redeemed or qr_row.status = 'redeemed' then
    v_result := 'Already Used';
    v_is_valid := false;
    v_message := 'This claim QR code has already been redeemed and completed.';
  elsif qr_row.status = 'revoked' then
    v_result := 'Revoked';
    v_is_valid := false;
    v_message := 'This claim QR code has been revoked and cannot be used.';
  elsif qr_row.expires_at < now() or qr_row.status = 'expired' then
    if qr_row.status <> 'expired' then
      update public.claim_release_qr_codes
      set status = 'expired'
      where id = qr_row.id;
      qr_row.status := 'expired';
    end if;
    v_result := 'Expired';
    v_is_valid := false;
    v_message := 'This claim QR code has expired. The claimant must generate a new voucher.';
  elsif claim_row.id is null
     or claim_row.claimant_id <> qr_row.claimant_id
     or claim_row.report_id <> qr_row.report_id then
    v_result := 'Invalid';
    v_is_valid := false;
    v_message := 'Claim QR metadata does not match a valid claim record.';
  elsif claim_row.status = 'completed' then
    v_result := 'Already Used';
    v_is_valid := false;
    v_message := 'This claim has already been completed and handed over.';
  elsif claim_row.status <> 'approved' then
    v_result := 'Invalid';
    v_is_valid := false;
    v_message := 'The associated claim is not in approved status.';
  elsif report_row.id is null then
    v_result := 'Invalid';
    v_is_valid := false;
    v_message := 'The associated item report no longer exists.';
  elsif report_row.status in ('returned', 'closed') then
    v_result := 'Already Used';
    v_is_valid := false;
    v_message := 'The associated item has already been marked as returned or closed.';
  else
    v_result := 'Valid';
    v_is_valid := true;
    v_message := case
      when v_is_staff and not v_is_claimant then 'Valid claim verification QR code. Ready for administrator release confirmation.'
      when v_is_claimant then 'Your claim handover QR voucher is active. Present it to a campus administrator to complete release.'
      else 'Valid claim verification QR code. Only an authorized campus administrator can finalize QR release.'
    end;
  end if;

  v_can_release := (v_is_valid and v_is_staff and not v_is_claimant);

  return json_build_object(
    'result', v_result,
    'is_valid', v_is_valid,
    'can_release', v_can_release,
    'viewer_role', v_viewer_role,
    'is_staff', v_is_staff,
    'is_claimant', v_is_claimant,
    'is_report_owner', v_is_report_owner,
    'qr_id', qr_row.id,
    'claim_id', qr_row.claim_id,
    'report_id', qr_row.report_id,
    'claimant_id', qr_row.claimant_id,
    'claimant_name', coalesce(nullif(trim(claim_row.claimant_name), ''), claimant_profile.full_name, 'Unknown Claimant'),
    'claimant_student_number', case
      when (v_is_staff or v_is_claimant) then coalesce(claimant_profile.student_number, '')
      else ''
    end,
    'item_name', coalesce(report_row.item_name, 'Unknown Item'),
    'category', coalesce(report_row.category, ''),
    'general_location', coalesce(report_row.general_location, ''),
    'image_path', report_row.image_path,
    'report_status', coalesce(report_row.status, ''),
    'claim_status', coalesce(claim_row.status, ''),
    'qr_status', qr_row.status,
    'expires_at', qr_row.expires_at,
    'is_redeemed', qr_row.is_redeemed,
    'redeemed_at', qr_row.redeemed_at,
    'redeemed_by', qr_row.redeemed_by,
    'redeemed_by_name', case when redeemer_profile.id is not null then redeemer_profile.full_name else null end,
    'message', v_message
  );
end;
$$;

revoke all on function public.verify_claim_qr(text) from public, anon;
grant execute on function public.verify_claim_qr(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. Atomic Claim QR Redemption via Scanned Token (public.redeem_verified_claim_qr)
-- ----------------------------------------------------------------------------
create or replace function public.redeem_verified_claim_qr(
  p_token text,
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
  v_caller_role text;
  v_released_at timestamptz := now();
  v_cleaned_token text;
  v_token_hash text;
  qr_row public.claim_release_qr_codes;
  claim_row public.item_claims;
  report_row public.item_reports;
  admin_profile public.user_profiles;
  v_release_log_id uuid;
  v_admin_name text;
begin
  if caller_id is null then
    raise exception 'Authentication required to release an item';
  end if;

  v_caller_role := public.current_user_role();
  if v_caller_role not in ('admin', 'moderator') then
    raise exception 'Only authorized campus administrators or moderators can verify and release items';
  end if;

  if p_confirmed is not true then
    raise exception 'Explicit administrator confirmation is required to finalize item release';
  end if;

  v_cleaned_token := trim(coalesce(p_token, ''));
  if v_cleaned_token ~* '^marsu://.*[?&]token=' then
    v_cleaned_token := trim(coalesce(substring(v_cleaned_token from '[?&]token=([^&]+)'), ''));
  end if;

  if v_cleaned_token = '' then
    raise exception 'A valid claim QR token is required';
  end if;

  v_token_hash := encode(sha256(convert_to(v_cleaned_token, 'UTF8')), 'hex');

  -- Lock the QR row atomically to prevent concurrent double redemption
  select * into qr_row
  from public.claim_release_qr_codes
  where token_hash = v_token_hash
  for update;

  if qr_row.id is null then
    raise exception 'Invalid or unrecognized claim verification QR code';
  end if;

  if qr_row.is_redeemed or qr_row.status = 'redeemed' then
    raise exception 'This claim QR code has already been redeemed';
  end if;

  if qr_row.status = 'revoked' then
    raise exception 'This claim QR code has been revoked';
  end if;

  if qr_row.expires_at < v_released_at or qr_row.status = 'expired' then
    raise exception 'This claim QR code has expired';
  end if;

  if qr_row.claimant_id = caller_id then
    raise exception 'Administrators cannot redeem their own claim QR code';
  end if;

  -- Lock associated claim and item report
  select * into claim_row
  from public.item_claims
  where id = qr_row.claim_id
  for update;

  if claim_row.id is null then
    raise exception 'Associated claim record not found';
  end if;

  if claim_row.claimant_id <> qr_row.claimant_id or claim_row.report_id <> qr_row.report_id then
    raise exception 'Claim QR record mismatch detected';
  end if;

  if claim_row.status = 'completed' then
    raise exception 'This claim has already been completed and handed over';
  end if;

  if claim_row.status <> 'approved' then
    raise exception 'Item release requires an approved claim (current: %)', claim_row.status;
  end if;

  select * into report_row
  from public.item_reports
  where id = qr_row.report_id
  for update;

  if report_row.id is null then
    raise exception 'Associated item report not found';
  end if;

  if report_row.status in ('returned', 'closed') then
    raise exception 'This item has already been marked as %', report_row.status;
  end if;

  select * into admin_profile from public.user_profiles where id = caller_id;
  v_admin_name := coalesce(nullif(trim(admin_profile.full_name), ''), nullif(trim(admin_profile.email), ''), v_caller_role);

  -- Atomic state transitions
  update public.claim_release_qr_codes
  set is_redeemed = true,
      status = 'redeemed',
      redeemed_at = v_released_at,
      redeemed_by = caller_id
  where id = qr_row.id;

  update public.item_claims
  set status = 'completed',
      completed_at = v_released_at,
      handover_confirmed_by = caller_id,
      updated_at = v_released_at
  where id = claim_row.id;

  update public.item_reports
  set status = 'returned'
  where id = report_row.id;

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
      'admin_id', caller_id,
      'admin_name', v_admin_name,
      'admin_role', v_caller_role,
      'claimant_id', claim_row.claimant_id,
      'claimant_name', claim_row.claimant_name,
      'item_name', report_row.item_name,
      'token_hash_preview', substring(qr_row.token_hash from 1 for 8) || '...',
      'confirmed_explicitly', true
    )
  ) returning id into v_release_log_id;

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
      'Item Release Completed',
      'Your approved claim for "' || report_row.item_name || '" has been verified via QR scan and released by ' || v_admin_name || '.',
      v_released_at
    ),
    (
      report_row.owner_id,
      claim_row.id,
      'claim_completed',
      'Item Handover Verified',
      'The belonging "' || report_row.item_name || '" has been verified via QR scan and released to claimant ' || claim_row.claimant_name || '.',
      v_released_at
    );

  return json_build_object(
    'success', true,
    'message', 'Item release verified and recorded successfully.',
    'claim_id', claim_row.id,
    'report_id', report_row.id,
    'qr_code_id', qr_row.id,
    'release_log_id', v_release_log_id,
    'released_by', caller_id,
    'released_by_name', v_admin_name,
    'claimant_id', claim_row.claimant_id,
    'claimant_name', claim_row.claimant_name,
    'item_name', report_row.item_name,
    'release_location', nullif(trim(p_release_location), ''),
    'released_at', v_released_at
  );
end;
$$;

revoke all on function public.redeem_verified_claim_qr(text, boolean, text, text) from public, anon;
grant execute on function public.redeem_verified_claim_qr(text, boolean, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Harden Existing public.admin_release_claim_item
--    Fixes silent bypass when p_token_hash does not match or QR is revoked/expired
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
  v_cleaned_token text;
  qr_row public.claim_release_qr_codes;
  claim_row public.item_claims;
  report_row public.item_reports;
  v_release_log_id uuid;
  v_method text := 'admin_override';
begin
  if caller_id is null then
    raise exception 'Authentication required to release an item';
  end if;

  if not (public.has_role('admin') or public.has_role('moderator')) then
    raise exception 'Only authorized campus administrators or moderators can execute item releases';
  end if;

  if p_confirmed is not true then
    raise exception 'Explicit administrator confirmation is required to finalize item release';
  end if;

  select * into claim_row
  from public.item_claims
  where id = p_claim_id
  for update;

  if claim_row.id is null then
    raise exception 'Target claim record not found';
  end if;

  if claim_row.claimant_id = caller_id then
    raise exception 'Administrators cannot release their own claim';
  end if;

  if claim_row.status = 'completed' then
    raise exception 'This claim has already been completed and handed over';
  end if;

  if claim_row.status <> 'approved' then
    raise exception 'Item release requires the claim to be in approved status (current: %)', claim_row.status;
  end if;

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

  v_cleaned_token := nullif(trim(coalesce(p_token_hash, '')), '');
  if v_cleaned_token is not null then
    select * into qr_row
    from public.claim_release_qr_codes
    where claim_id = p_claim_id
      and (
        token_hash = v_cleaned_token
        or token_hash = encode(sha256(convert_to(v_cleaned_token, 'UTF8')), 'hex')
      )
    for update;

    if qr_row.id is null then
      raise exception 'Invalid or unrecognized claim QR token for this claim';
    end if;

    if qr_row.is_redeemed or qr_row.status = 'redeemed' then
      raise exception 'This claim QR code has already been redeemed';
    end if;

    if qr_row.status = 'revoked' then
      raise exception 'This claim QR code has been revoked';
    end if;

    if qr_row.expires_at < v_released_at or qr_row.status = 'expired' then
      raise exception 'This claim QR code has expired';
    end if;

    v_method := 'qr_scan';

    update public.claim_release_qr_codes
    set is_redeemed = true,
        status = 'redeemed',
        redeemed_at = v_released_at,
        redeemed_by = caller_id
    where id = qr_row.id;
  else
    select * into qr_row
    from public.claim_release_qr_codes
    where claim_id = p_claim_id and status = 'active'
    order by created_at desc
    limit 1
    for update;

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
  end if;

  update public.item_claims
  set status = 'completed',
      completed_at = v_released_at,
      handover_confirmed_by = caller_id,
      updated_at = v_released_at
  where id = claim_row.id;

  update public.item_reports
  set status = 'returned'
  where id = report_row.id;

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

revoke all on function public.admin_release_claim_item(uuid, text, boolean, text, text) from public, anon;
grant execute on function public.admin_release_claim_item(uuid, text, boolean, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. Function: public.admin_list_release_logs (Release Transaction History)
-- ----------------------------------------------------------------------------
create or replace function public.admin_list_release_logs()
returns table (
  id uuid,
  qr_code_id uuid,
  claim_id uuid,
  report_id uuid,
  claimant_id uuid,
  claimant_name text,
  released_by uuid,
  released_by_name text,
  release_method text,
  release_location text,
  notes text,
  metadata jsonb,
  released_at timestamptz,
  item_name text,
  category text
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
    l.id,
    l.qr_code_id,
    l.claim_id,
    l.report_id,
    l.claimant_id,
    coalesce(nullif(trim(c.claimant_name), ''), cp.full_name, 'Claimant') as claimant_name,
    l.released_by,
    coalesce(nullif(trim(ap.full_name), ''), ap.email, 'Administrator') as released_by_name,
    l.release_method,
    l.release_location,
    l.notes,
    l.metadata,
    l.released_at,
    r.item_name,
    r.category
  from public.item_release_logs l
  left join public.item_claims c on c.id = l.claim_id
  left join public.item_reports r on r.id = l.report_id
  left join public.user_profiles cp on cp.id = l.claimant_id
  left join public.user_profiles ap on ap.id = l.released_by
  order by l.released_at desc
  limit 100;
end;
$$;

revoke all on function public.admin_list_release_logs() from public, anon;
grant execute on function public.admin_list_release_logs() to authenticated;

notify pgrst, 'reload schema';
