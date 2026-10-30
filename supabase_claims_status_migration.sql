do $$
begin
  if to_regclass('public.item_claims') is null
     or not exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
         and table_name = 'item_claims'
         and column_name = 'claimant_contact_hidden'
         and data_type = 'boolean'
     )
     or not exists (
       select 1
       from pg_indexes
       where schemaname = 'public'
         and indexname = 'one_pending_claim_per_claimant'
     ) then
    raise exception 'This migration is superseded. Run supabase_claim_rls_fix.sql instead.';
  end if;
end $$;
