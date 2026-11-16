-- Harden the SECURITY DEFINER view-heartbeat worker RPC against search_path shadowing.
-- All application relations are schema-qualified in the function body.
CREATE OR REPLACE FUNCTION public.flow_record_view_heartbeat_v1(
  p_event_id uuid,
  p_viewer uuid,
  p_post uuid
)
RETURNS TABLE(accepted boolean, watch_ms integer, heartbeat_total integer, reason text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_event public.flow_view_events%rowtype;
  v_now timestamptz := clock_timestamp();
  v_delta integer;
BEGIN
  SELECT * INTO v_event
  FROM public.flow_view_events
  WHERE id = p_event_id
    AND viewer_auth_user_id = p_viewer
    AND post_id = p_post
    AND qualified = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 0, 0, 'session_not_found';
    RETURN;
  END IF;

  IF v_event.last_heartbeat_at IS NULL THEN
    UPDATE public.flow_view_events
    SET last_heartbeat_at = v_now, heartbeat_count = heartbeat_count + 1
    WHERE id = p_event_id
    RETURNING accumulated_watch_ms, heartbeat_count INTO v_delta, heartbeat_total;
    RETURN QUERY SELECT true, v_delta, heartbeat_total, 'first_heartbeat';
    RETURN;
  END IF;

  IF v_now - v_event.last_heartbeat_at < interval '4 seconds' THEN
    RETURN QUERY SELECT false, v_event.accumulated_watch_ms, v_event.heartbeat_count, 'heartbeat_too_soon';
    RETURN;
  END IF;

  v_delta := least(10000, greatest(0, floor(extract(epoch from (v_now - v_event.last_heartbeat_at)) * 1000)::integer));

  UPDATE public.flow_view_events
  SET last_heartbeat_at = v_now,
      heartbeat_count = heartbeat_count + 1,
      accumulated_watch_ms = accumulated_watch_ms + v_delta,
      watch_time_ms = least(2147483647, accumulated_watch_ms + v_delta)
  WHERE id = p_event_id
  RETURNING accumulated_watch_ms, heartbeat_count INTO v_delta, heartbeat_total;

  RETURN QUERY SELECT true, v_delta, heartbeat_total, 'accepted';
END;
$function$;
