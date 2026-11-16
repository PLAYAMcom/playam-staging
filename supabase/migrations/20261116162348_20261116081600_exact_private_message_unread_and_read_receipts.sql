-- Exact unread totals and safe server-side read receipts, independent of UI page limits.
CREATE OR REPLACE FUNCTION public.get_private_message_unread_counts_v1()
RETURNS TABLE(conversation_id uuid, unread_count bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid();
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 RETURN QUERY
 SELECT m.conversation_id,count(*)::bigint
 FROM public.private_messages m
 JOIN public.private_conversations c ON c.id=m.conversation_id
 WHERE v_uid IN(c.user_one_auth_user_id,c.user_two_auth_user_id)
   AND m.sender_auth_user_id<>v_uid
   AND m.read_at IS NULL AND m.deleted_at IS NULL
   AND (m.expires_at IS NULL OR m.expires_at>now())
   AND NOT public.playam_storage_pair_is_blocked_v1(
     CASE WHEN c.user_one_auth_user_id=v_uid THEN c.user_two_auth_user_id ELSE c.user_one_auth_user_id END
   )
 GROUP BY m.conversation_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_private_conversation_read_v1(p_conversation_id uuid)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_other uuid; v_count integer;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT CASE WHEN c.user_one_auth_user_id=v_uid THEN c.user_two_auth_user_id ELSE c.user_one_auth_user_id END
 INTO v_other
 FROM public.private_conversations c
 WHERE c.id=p_conversation_id AND v_uid IN(c.user_one_auth_user_id,c.user_two_auth_user_id);
 IF v_other IS NULL OR public.playam_storage_pair_is_blocked_v1(v_other) THEN
  RAISE EXCEPTION 'Conversation unavailable';
 END IF;
 UPDATE public.private_messages m SET read_at=now()
 WHERE m.conversation_id=p_conversation_id AND m.sender_auth_user_id=v_other
   AND m.read_at IS NULL AND m.deleted_at IS NULL
   AND (m.expires_at IS NULL OR m.expires_at>now());
 GET DIAGNOSTICS v_count=ROW_COUNT;
 RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_private_message_unread_counts_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_private_conversation_read_v1(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_private_message_unread_counts_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_private_conversation_read_v1(uuid) TO authenticated;
