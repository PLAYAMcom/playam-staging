-- Bind a private-message idempotency key to the original conversation and body.
-- Replays of the same request return the original message; payload changes are rejected.
CREATE OR REPLACE FUNCTION public.send_private_message_v1(
 p_conversation_id uuid,
 p_body text,
 p_idempotency_key uuid
)
RETURNS TABLE(message_id uuid, created_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid := auth.uid();
 v_body text := btrim(coalesce(p_body, ''));
 v_message_id uuid;
 v_created_at timestamptz;
 v_existing_conversation_id uuid;
 v_existing_body text;
BEGIN
 IF v_uid IS NULL THEN
   RAISE EXCEPTION 'Authentication required';
 END IF;
 IF p_conversation_id IS NULL OR p_idempotency_key IS NULL THEN
   RAISE EXCEPTION 'Conversation and request key are required';
 END IF;
 IF length(v_body) < 1 OR length(v_body) > 4000 THEN
   RAISE EXCEPTION 'Message must contain 1 to 4000 characters';
 END IF;
 IF NOT EXISTS (
   SELECT 1
   FROM public.private_conversations c
   WHERE c.id = p_conversation_id
     AND v_uid IN (c.user_one_auth_user_id, c.user_two_auth_user_id)
     AND NOT public.playam_storage_pair_is_blocked_v1(
       CASE
         WHEN c.user_one_auth_user_id = v_uid THEN c.user_two_auth_user_id
         ELSE c.user_one_auth_user_id
       END
     )
 ) THEN
   RAISE EXCEPTION 'Conversation unavailable';
 END IF;
 INSERT INTO public.private_messages
   (conversation_id, sender_auth_user_id, body, idempotency_key)
 VALUES
   (p_conversation_id, v_uid, v_body, p_idempotency_key)
 ON CONFLICT (sender_auth_user_id, idempotency_key)
   WHERE idempotency_key IS NOT NULL
 DO NOTHING
 RETURNING id, public.private_messages.created_at
 INTO v_message_id, v_created_at;
 IF v_message_id IS NULL THEN
   SELECT m.id, m.created_at, m.conversation_id, m.body
   INTO v_message_id, v_created_at, v_existing_conversation_id, v_existing_body
   FROM public.private_messages m
   WHERE m.sender_auth_user_id = v_uid
     AND m.idempotency_key = p_idempotency_key;
   IF v_existing_conversation_id IS DISTINCT FROM p_conversation_id
      OR v_existing_body IS DISTINCT FROM v_body THEN
     RAISE EXCEPTION 'Idempotency key was already used for a different message';
   END IF;
 END IF;
 RETURN QUERY SELECT v_message_id, v_created_at;
END;
$function$;
REVOKE ALL ON FUNCTION public.send_private_message_v1(uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_private_message_v1(uuid, text, uuid) TO authenticated;
