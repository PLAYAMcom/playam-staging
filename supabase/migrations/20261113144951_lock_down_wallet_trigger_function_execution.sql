-- Exported from PLAYAM Staging migration history (20261113144951).
-- Apply only to the matching Staging project after reviewing the migration.
REVOKE EXECUTE ON FUNCTION public.playam_apply_wallet_transaction_v1() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.playam_apply_purchased_coin_transaction_v1() FROM PUBLIC, anon, authenticated;
