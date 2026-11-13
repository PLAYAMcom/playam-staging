-- Exported from PLAYAM Staging migration history (20261113153104).
-- Apply only to the matching Staging project after reviewing the migration.

create index if not exists friend_requests_recipient_auth_user_id_idx on public.friend_requests(recipient_auth_user_id);
create index if not exists friend_requests_sender_auth_user_id_idx on public.friend_requests(sender_auth_user_id);
create index if not exists game_invitations_room_id_idx on public.game_invitations(room_id);
create index if not exists playam_admin_roles_granted_by_idx on public.playam_admin_roles(granted_by);
create index if not exists playam_creator_withdrawal_audit_actor_idx on public.playam_creator_withdrawal_audit(actor_auth_user_id);
create index if not exists playam_creator_withdrawal_requests_first_approver_idx on public.playam_creator_withdrawal_requests(first_approved_by);
create index if not exists playam_creator_withdrawal_requests_second_approver_idx on public.playam_creator_withdrawal_requests(second_approved_by);
create index if not exists playam_report_audit_admin_idx on public.playam_report_audit(admin_auth_user_id);
create index if not exists playam_report_audit_report_idx on public.playam_report_audit(report_id);
create index if not exists player_blocks_blocked_auth_user_id_idx on public.player_blocks(blocked_auth_user_id);
create index if not exists private_conversation_settings_auth_user_id_idx on public.private_conversation_settings(auth_user_id);
create index if not exists private_messages_sender_auth_user_id_idx on public.private_messages(sender_auth_user_id);
create index if not exists player_reports_reported_auth_user_id_idx on public.player_reports(reported_auth_user_id);
create index if not exists rounds_question_id_idx on public.rounds(question_id);

