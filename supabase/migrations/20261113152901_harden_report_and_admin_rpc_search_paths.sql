-- Exported from PLAYAM Staging migration history (20261113152901).
-- Apply only to the matching Staging project after reviewing the migration.

alter function public.admin_list_player_reports(text,integer) set search_path='';
alter function public.admin_review_player_report(uuid,text,text) set search_path='';
alter function public.get_playam_admin_overview() set search_path='';
alter function public.list_room_report_targets(uuid) set search_path='';
alter function public.submit_player_report(uuid,text,text,uuid) set search_path='';

