-- Serialize lobby readiness changes with room joins and game starts.
-- Apply only to the isolated PLAYAM Staging project after review.

CREATE OR REPLACE FUNCTION public.set_playam_ready(p_ready boolean,p_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_room_id uuid;
  v_player_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Lock the room first. join_playam_room and start_playam_game use the
  -- same room-row lock, so a readiness change cannot race game startup.
  SELECT r.id,p.id
  INTO v_room_id,v_player_id
  FROM public.rooms r
  JOIN public.players p ON p.room_id=r.id
  WHERE r.code=upper(btrim(coalesce(p_code,'')))
    AND p.auth_user_id=v_uid
    AND coalesce(r.game_status,r.status)='waiting'
  ORDER BY p.joined_at DESC
  LIMIT 1
  FOR UPDATE OF r;

  IF v_room_id IS NULL OR v_player_id IS NULL THEN
    RAISE EXCEPTION 'You are not a member of this waiting room';
  END IF;

  UPDATE public.players
  SET is_ready=coalesce(p_ready,false)
  WHERE id=v_player_id AND room_id=v_room_id;

  RETURN coalesce(p_ready,false);
END;
$$;

REVOKE ALL ON FUNCTION public.set_playam_ready(boolean,text) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.set_playam_ready(boolean,text) TO authenticated;
