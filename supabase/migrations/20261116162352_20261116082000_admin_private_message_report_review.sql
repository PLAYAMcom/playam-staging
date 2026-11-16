-- Allow AAL2 super-admin moderators to retrieve only the private message
-- attached to a report, without exposing private messages through general queries.
CREATE OR REPLACE FUNCTION public.admin_get_reported_private_message(p_report_id uuid)
RETURNS TABLE(message_id uuid, sender_auth_user_id uuid, message_body text, message_created_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_details text;
  v_message_id uuid;
BEGIN
  IF v_uid IS NULL
     OR coalesce(auth.jwt() ->> 'aal', '') <> 'aal2'
     OR NOT EXISTS (
       SELECT 1 FROM public.playam_admin_roles ar
       WHERE ar.auth_user_id = v_uid
         AND ar.role_name = 'super_admin'
         AND ar.is_active = true
     )
  THEN
    RAISE EXCEPTION 'Administrator AAL2 verification required';
  END IF;

  SELECT r.details INTO v_details
  FROM public.player_reports r
  WHERE r.id = p_report_id
    AND r.reason IN (
      'Harassment or bullying',
      'Hate speech or abusive behaviour',
      'Inappropriate content',
      'Spam or disruptive behaviour',
      'Other'
    )
    AND r.room_id IS NULL
  FOR SHARE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Private message report not found'; END IF;

  v_message_id := substring(v_details from '\[Private message reference: ([0-9a-fA-F-]{36})\]')::uuid;
  IF v_message_id IS NULL THEN RAISE EXCEPTION 'This report has no private message reference'; END IF;

  RETURN QUERY
  SELECT m.id, m.sender_auth_user_id, m.body, m.created_at
  FROM public.private_messages m
  WHERE m.id = v_message_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_get_reported_private_message(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_reported_private_message(uuid) TO authenticated;
