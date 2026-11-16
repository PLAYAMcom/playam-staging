CREATE INDEX IF NOT EXISTS private_messages_conversation_created_id_idx
ON public.private_messages(conversation_id,created_at DESC,id DESC)
WHERE deleted_at IS NULL;