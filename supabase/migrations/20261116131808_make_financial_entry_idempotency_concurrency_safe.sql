-- Make financial-entry idempotency safe under concurrent retries.
CREATE OR REPLACE FUNCTION public.playam_record_financial_entry_v1(
 p_entry_type text,
 p_category text,
 p_amount_minor bigint,
 p_currency text,
 p_occurred_on date,
 p_description text,
 p_external_reference text,
 p_idempotency_key text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
 v_actor uuid := auth.uid();
 v_id uuid;
 v_existing public.playam_financial_entries%rowtype;
BEGIN
 IF v_actor IS NULL OR coalesce(auth.jwt()->>'aal','') <> 'aal2' THEN
  RAISE EXCEPTION 'Verified administrator MFA (aal2) is required';
 END IF;

 IF NOT EXISTS (
  SELECT 1 FROM public.playam_admin_roles
  WHERE auth_user_id=v_actor AND is_active=true
    AND role_name IN ('super_admin','finance_admin')
 ) THEN RAISE EXCEPTION 'Finance administrator permission required'; END IF;

 IF p_entry_type NOT IN ('income','expense')
    OR p_amount_minor IS NULL OR p_amount_minor<=0
    OR p_currency !~ '^[A-Z]{3}$'
    OR p_description IS NULL OR length(trim(p_description)) NOT BETWEEN 3 AND 500
    OR p_idempotency_key IS NULL OR length(trim(p_idempotency_key)) NOT BETWEEN 8 AND 200
    OR p_category NOT IN (
     'live_platform_share','advertising_revenue','sponsorship_revenue','marketplace_revenue','other_income',
     'payment_processing_fees','creator_withdrawal_fees','refunds_chargebacks','fraud_losses',
     'hosting_database_storage_bandwidth','email_sms','security_monitoring',
     'customer_support','moderation','marketing','staffing_administration',
     'legal_accounting','taxes','other_expense'
    ) THEN RAISE EXCEPTION 'Invalid financial entry'; END IF;

 IF (p_entry_type='income' AND p_category NOT IN
    ('live_platform_share','advertising_revenue','sponsorship_revenue','marketplace_revenue','other_income'))
    OR (p_entry_type='expense' AND p_category NOT IN
    ('payment_processing_fees','creator_withdrawal_fees','refunds_chargebacks','fraud_losses',
     'hosting_database_storage_bandwidth','email_sms','security_monitoring',
     'customer_support','moderation','marketing','staffing_administration','legal_accounting','taxes','other_expense'))
 THEN RAISE EXCEPTION 'Category does not match entry type'; END IF;

 INSERT INTO public.playam_financial_entries
 (entry_type,category,amount_minor,currency,occurred_on,description,external_reference,idempotency_key,recorded_by)
 VALUES (p_entry_type,p_category,p_amount_minor,p_currency,coalesce(p_occurred_on,current_date),
         trim(p_description),p_external_reference,trim(p_idempotency_key),v_actor)
 ON CONFLICT (idempotency_key) DO NOTHING
 RETURNING id INTO v_id;

 IF v_id IS NOT NULL THEN
  RETURN v_id;
 END IF;

 -- A concurrent request won the unique-key race. Return its row only if
 -- every material field matches; otherwise reject key reuse.
 SELECT * INTO v_existing FROM public.playam_financial_entries
 WHERE idempotency_key=trim(p_idempotency_key);

 IF NOT FOUND THEN
  RAISE EXCEPTION 'Financial entry retry could not be resolved; retry safely';
 END IF;

 IF v_existing.entry_type<>p_entry_type OR v_existing.category<>p_category
    OR v_existing.amount_minor<>p_amount_minor OR v_existing.currency<>p_currency
    OR v_existing.occurred_on<>coalesce(p_occurred_on,current_date)
    OR v_existing.description<>trim(p_description)
    OR v_existing.external_reference IS DISTINCT FROM p_external_reference THEN
  RAISE EXCEPTION 'Idempotency key already used for a different financial entry';
 END IF;

 RETURN v_existing.id;
END;
$function$;
