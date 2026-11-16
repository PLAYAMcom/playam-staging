-- Allow a participant to report a specific private message through the existing
-- player moderation queue. No message body is copied into the report record.
CREATE OR REPLACE FUNCTION public.submit_private_message_report(
  p_message_id uuid,
  p_reason text,
  p_details text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_message public.private_messages%ROWTYPE;
  v_report_id uuid;
  v_count integer;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_details text := nullif(btrim(coalesce(p_details, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_message_id IS NULL THEN
    RAISE EXCEPTION 'Message is required';
  END IF;
  IF v_reason NOT IN (
    'Harassment or bullying',
    'Hate speech or abusive behaviour',
    'Inappropriate content',
    'Spam or disruptive behaviour',
    'Other'
  ) THEN
    RAISE EXCEPTION 'Invalid report reason';
  END IF;
  IF length(coalesce(v_details, '')) > 1500 THEN
    RAISE EXCEPTION 'Report details exceed 1500 characters';
  END IF;

  SELECT m.* INTO v_message
  FROM public.private_messages m
  JOIN public.private_conversations c ON c.id = m.conversation_id
  WHERE m.id = p_message_id
    AND m.sender_auth_user_id <> v_uid
    AND m.deleted_at IS NULL
    AND v_uid IN (c.user_one_auth_user_id, c.user_two_auth_user_id)
  FOR SHARE OF m;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Message not found or you are not allowed to report it';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));
  SELECT count(*)::integer INTO v_count
  FROM public.player_reports r
  WHERE r.reporter_auth_user_id = v_uid
    AND r.created_at >= now() - interval '1 hour';
  IF v_count >= 5 THEN
    RAISE EXCEPTION 'Report limit reached. Try again later';
  END IF;

  INSERT INTO public.player_reports (
    reporter_auth_user_id, reported_auth_user_id, room_id,
    reason, details, status
  ) VALUES (
    v_uid, v_message.sender_auth_user_id, NULL,
    v_reason,
    concat('[Private message reference: ', p_message_id::text, ']',
      CASE WHEN v_details IS NULL THEN '' ELSE E'\n' || v_details END),
    'open'
  ) RETURNING id INTO v_report_id;

  RETURN v_report_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_private_message_report(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_private_message_report(uuid,text,text) TO authenticated;
