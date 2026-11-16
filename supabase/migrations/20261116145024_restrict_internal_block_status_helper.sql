-- This helper is called internally by SECURITY DEFINER messaging RPCs.
-- Do not expose pair-block status as a directly callable authenticated RPC.
REVOKE EXECUTE ON FUNCTION public.playam_storage_pair_is_blocked_v1(uuid) FROM authenticated;
