-- Prevent a creator from reusing a withdrawal idempotency key with a different amount or destination.
CREATE OR REPLACE FUNCTION public.playam_request_creator_withdrawal_v1(
 p_amount_minor bigint,p_destination_id uuid,p_idempotency_key text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_user uuid;
 v_request_id uuid;
 v_existing_user uuid;
 v_existing_amount bigint;
 v_existing_destination uuid;
 v_available bigint;
 v_minimum bigint;
 v_maximum bigint;
 v_destination_user uuid;
 v_key text := nullif(trim(p_idempotency_key),'');
BEGIN
 v_user:=auth.uid();
 IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF p_amount_minor IS NULL OR p_amount_minor<=0 OR v_key IS NULL
   OR length(v_key)<8 OR length(v_key)>200 THEN
  RAISE EXCEPTION 'Invalid withdrawal request';
 END IF;

 SELECT id,auth_user_id,amount_minor,payout_destination_id
 INTO v_request_id,v_existing_user,v_existing_amount,v_existing_destination
 FROM public.playam_creator_withdrawal_requests
 WHERE idempotency_key=v_key;

 IF FOUND THEN
  IF v_existing_user<>v_user THEN
   RAISE EXCEPTION 'Idempotency key already belongs to another account';
  END IF;
  IF v_existing_amount<>p_amount_minor OR v_existing_destination IS DISTINCT FROM p_destination_id THEN
   RAISE EXCEPTION 'Idempotency key already used for a different withdrawal request';
  END IF;
  RETURN v_request_id;
 END IF;

 SELECT minimum_withdrawal_minor,maximum_withdrawal_minor
 INTO v_minimum,v_maximum
 FROM public.playam_creator_withdrawal_settings WHERE id=TRUE;
 IF NOT FOUND OR v_minimum IS NULL OR p_amount_minor<v_minimum
   OR (v_maximum IS NOT NULL AND p_amount_minor>v_maximum) THEN
  RAISE EXCEPTION 'Withdrawal amount is outside configured limits';
 END IF;

 SELECT auth_user_id INTO v_destination_user
 FROM public.playam_creator_payout_destinations
 WHERE id=p_destination_id AND auth_user_id=v_user
  AND provider='paystack' AND is_active=TRUE
  AND verified_at IS NOT NULL AND eligible_at<=NOW();
 IF NOT FOUND THEN
  RAISE EXCEPTION 'Payout destination is not verified or is in its cooling-off period';
 END IF;

 INSERT INTO public.playam_creator_earnings_wallets
 (auth_user_id,available_balance_minor,pending_balance_minor,withdrawn_balance_minor,reserved_withdrawal_balance_minor)
 VALUES(v_user,0,0,0,0) ON CONFLICT(auth_user_id) DO NOTHING;

 SELECT available_balance_minor INTO v_available
 FROM public.playam_creator_earnings_wallets WHERE auth_user_id=v_user FOR UPDATE;

 -- Recheck after acquiring the wallet lock: a concurrent identical request
 -- may have committed while this request waited for the same wallet row.
 SELECT id,auth_user_id,amount_minor,payout_destination_id
 INTO v_request_id,v_existing_user,v_existing_amount,v_existing_destination
 FROM public.playam_creator_withdrawal_requests WHERE idempotency_key=v_key;
 IF FOUND THEN
  IF v_existing_user<>v_user THEN
   RAISE EXCEPTION 'Idempotency key already belongs to another account';
  END IF;
  IF v_existing_amount<>p_amount_minor OR v_existing_destination IS DISTINCT FROM p_destination_id THEN
   RAISE EXCEPTION 'Idempotency key already used for a different withdrawal request';
  END IF;
  RETURN v_request_id;
 END IF;

 IF v_available<p_amount_minor THEN RAISE EXCEPTION 'Insufficient available creator earnings'; END IF;

 INSERT INTO public.playam_creator_withdrawal_requests
 (auth_user_id,amount_minor,currency,status,payout_destination_id,idempotency_key)
 VALUES(v_user,p_amount_minor,'NGN','pending',p_destination_id,v_key)
 ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO v_request_id;

 IF v_request_id IS NULL THEN
  SELECT id,auth_user_id,amount_minor,payout_destination_id
  INTO v_request_id,v_existing_user,v_existing_amount,v_existing_destination
  FROM public.playam_creator_withdrawal_requests WHERE idempotency_key=v_key;
  IF NOT FOUND THEN RAISE EXCEPTION 'Withdrawal retry could not be resolved; retry safely'; END IF;
  IF v_existing_user<>v_user THEN RAISE EXCEPTION 'Idempotency key already belongs to another account'; END IF;
  IF v_existing_amount<>p_amount_minor OR v_existing_destination IS DISTINCT FROM p_destination_id THEN
   RAISE EXCEPTION 'Idempotency key already used for a different withdrawal request';
  END IF;
  RETURN v_request_id;
 END IF;

 INSERT INTO public.playam_creator_earnings_transactions
 (auth_user_id,amount_minor,transaction_type,status,reference_type,reference_id,idempotency_key,metadata)
 VALUES(v_user,p_amount_minor,'withdrawal_reserved','pending','withdrawal_request',v_request_id,
  'withdrawal-reserve:'||v_request_id::text,jsonb_build_object('source','creator_withdrawal_request'));
 INSERT INTO public.playam_creator_withdrawal_audit
 (withdrawal_request_id,actor_auth_user_id,actor_type,event_type)
 VALUES(v_request_id,v_user,'creator','withdrawal_requested_and_reserved');
 RETURN v_request_id;
END;
$function$;