CREATE OR REPLACE FUNCTION public.playam_mark_creator_withdrawal_failed_v1(
  p_request_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  v_creator uuid;
  v_amount bigint;
  v_status text;
  v_reason text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Trusted payout backend required';
  end if;

  v_reason := coalesce(nullif(trim(p_reason), ''), 'Verified payout failure');
  if length(v_reason) > 500 then
    raise exception 'Failure reason is too long';
  end if;

  select auth_user_id, amount_minor, status
  into v_creator, v_amount, v_status
  from public.playam_creator_withdrawal_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Withdrawal request not found';
  end if;

  -- Paystack may redeliver the same signed failure webhook. Once the
  -- request is failed and its reserve has been released, repeated delivery
  -- must be a successful no-op rather than a second ledger/audit write.
  if v_status = 'failed' then
    return;
  end if;

  if v_status <> 'processing' then
    raise exception 'Withdrawal is not awaiting payout confirmation';
  end if;

  update public.playam_creator_withdrawal_requests
  set status = 'failed',
      processed_at = now(),
      failure_reason = v_reason
  where id = p_request_id;

  insert into public.playam_creator_earnings_transactions (
    auth_user_id, amount_minor, transaction_type, status,
    reference_type, reference_id, idempotency_key, metadata
  )
  values (
    v_creator, v_amount, 'withdrawal_released', 'reversed',
    'withdrawal_request', p_request_id,
    'withdrawal-release:' || p_request_id::text,
    jsonb_build_object('reason', v_reason,
                       'confirmation_source', 'trusted_backend')
  );

  insert into public.playam_creator_withdrawal_audit (
    withdrawal_request_id, actor_type, event_type, metadata
  )
  values (
    p_request_id, 'system', 'verified_payout_failure',
    jsonb_build_object('reason', v_reason)
  );
end;
$function$;
