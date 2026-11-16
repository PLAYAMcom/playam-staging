-- Harden private messaging block visibility and client message insert columns.
-- Apply to PLAYAM Staging; production migration is intentionally separate.

DROP POLICY IF EXISTS private_conversations_select ON public.private_conversations;
CREATE POLICY private_conversations_select
ON public.private_conversations
FOR SELECT TO authenticated
USING (
  (user_one_auth_user_id = (SELECT auth.uid())
   AND NOT public.playam_storage_pair_is_blocked_v1(user_two_auth_user_id))
  OR
  (user_two_auth_user_id = (SELECT auth.uid())
   AND NOT public.playam_storage_pair_is_blocked_v1(user_one_auth_user_id))
);

-- Prevent clients from forging server-managed message metadata on INSERT.
REVOKE INSERT ON TABLE public.private_messages FROM authenticated;
GRANT INSERT (conversation_id, sender_auth_user_id, body, attachment_path)
ON TABLE public.private_messages TO authenticated;
