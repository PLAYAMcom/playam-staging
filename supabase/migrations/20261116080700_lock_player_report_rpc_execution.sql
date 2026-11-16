-- Lock report RPC execution to authenticated users; RPCs enforce ownership/AAL2.
REVOKE ALL ON FUNCTION public.submit_player_report(uuid,text,text,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_player_reports(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_review_player_report(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_player_report(uuid,text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_player_reports(text,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_player_report(uuid,text,text) TO authenticated;
