CREATE UNIQUE INDEX IF NOT EXISTS playam_creator_withdrawal_reversal_event_uidx
ON public.playam_creator_withdrawal_audit
  (withdrawal_request_id, event_type, (metadata ->> 'provider_reference'))
WHERE event_type = 'paystack_transfer_reversed_manual_review'
  AND metadata ? 'provider_reference';

CREATE OR REPLACE FUNCTION public.playam_record_paystack_transfer_reversal_v1(
  p_request_id uuid,
  p_provider_reference text,
  p_transfer_code text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required';
  END IF;
  IF p_request_id IS NULL OR p_provider_reference IS NULL
     OR length(p_provider_reference) < 4 OR length(p_provider_reference) > 120 THEN
    RAISE EXCEPTION 'Invalid transfer reversal reference';
  END IF;

  INSERT INTO public.playam_creator_withdrawal_audit (
    withdrawal_request_id, actor_type, event_type, metadata
  )
  VALUES (
    p_request_id,
    'system',
    'paystack_transfer_reversed_manual_review',
    jsonb_build_object(
      'provider_reference', p_provider_reference,
      'transfer_code', nullif(left(coalesce(p_transfer_code, ''), 120), ''),
      'note', 'Provider reversed a previously successful payout; manual financial reconciliation required.'
    )
  )
  ON CONFLICT (
    withdrawal_request_id,
    event_type,
    (metadata ->> 'provider_reference')
  )
  WHERE event_type = 'paystack_transfer_reversed_manual_review'
    AND metadata ? 'provider_reference'
  DO NOTHING;

  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.playam_record_paystack_transfer_reversal_v1(uuid,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.playam_record_paystack_transfer_reversal_v1(uuid,text,text) TO service_role;
