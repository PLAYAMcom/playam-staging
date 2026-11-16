CREATE OR REPLACE FUNCTION public.flow_apply_cloudflare_stream_webhook_v1(
  p_cloudflare_uid text,
  p_state text,
  p_duration_seconds numeric DEFAULT NULL,
  p_width integer DEFAULT NULL,
  p_height integer DEFAULT NULL,
  p_thumbnail_url text DEFAULT NULL,
  p_playback_hls_url text DEFAULT NULL,
  p_playback_dash_url text DEFAULT NULL,
  p_error_code text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_upload public.flow_cloudflare_uploads%ROWTYPE;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required';
  END IF;
  IF p_cloudflare_uid IS NULL OR length(p_cloudflare_uid) < 1 OR length(p_cloudflare_uid) > 200 THEN
    RAISE EXCEPTION 'Invalid Cloudflare UID';
  END IF;
  IF p_state NOT IN ('processing', 'ready', 'failed') THEN
    RAISE EXCEPTION 'Invalid Cloudflare processing state';
  END IF;
  IF p_duration_seconds IS NOT NULL AND p_duration_seconds <= 0 THEN
    p_duration_seconds := NULL;
  END IF;
  IF p_width IS NOT NULL AND p_width <= 0 THEN p_width := NULL; END IF;
  IF p_height IS NOT NULL AND p_height <= 0 THEN p_height := NULL; END IF;

  SELECT * INTO v_upload
  FROM public.flow_cloudflare_uploads
  WHERE cloudflare_uid = p_cloudflare_uid
  FOR UPDATE;

  IF NOT FOUND THEN RETURN 'ignored'; END IF;

  IF v_upload.status IN ('ready', 'failed', 'rejected') THEN
    RETURN v_upload.status || '_unchanged';
  END IF;

  IF p_state = 'ready' THEN
    UPDATE public.flow_post_assets
    SET processing_status = 'ready',
        duration_seconds = p_duration_seconds,
        width = p_width,
        height = p_height
    WHERE id = v_upload.asset_id
      AND processing_status IN ('quarantined', 'scanning', 'processing');
    IF NOT FOUND THEN RETURN 'asset_state_blocked'; END IF;

    UPDATE public.flow_cloudflare_uploads
    SET status = 'ready', ready_at = now(),
        duration_seconds = p_duration_seconds, width = p_width, height = p_height,
        thumbnail_url = p_thumbnail_url,
        playback_hls_url = p_playback_hls_url,
        playback_dash_url = p_playback_dash_url,
        updated_at = now()
    WHERE id = v_upload.id;
    RETURN 'ready';
  ELSIF p_state = 'failed' THEN
    UPDATE public.flow_post_assets
    SET processing_status = 'failed'
    WHERE id = v_upload.asset_id
      AND processing_status IN ('quarantined', 'scanning', 'processing');
    IF NOT FOUND THEN RETURN 'asset_state_blocked'; END IF;

    UPDATE public.flow_cloudflare_uploads
    SET status = 'failed',
        error_code = left(coalesce(p_error_code, 'PROCESSING_FAILED'), 80),
        updated_at = now()
    WHERE id = v_upload.id;
    RETURN 'failed';
  ELSE
    UPDATE public.flow_cloudflare_uploads
    SET status = 'processing', updated_at = now()
    WHERE id = v_upload.id AND status = 'awaiting_upload';
    UPDATE public.flow_post_assets
    SET processing_status = 'processing'
    WHERE id = v_upload.asset_id
      AND processing_status IN ('quarantined', 'scanning');
    RETURN 'processing';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.flow_apply_cloudflare_stream_webhook_v1(text,text,numeric,integer,integer,text,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.flow_apply_cloudflare_stream_webhook_v1(text,text,numeric,integer,integer,text,text,text,text) TO service_role;
