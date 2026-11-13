-- Exported from PLAYAM Staging migration history (20261113153023).
-- Apply only to the matching Staging project after reviewing the migration.

create or replace function public.has_playam_submitted(p_code text)
returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare
 v_uid uuid:=auth.uid();
 v_room_id uuid;
 v_player_id uuid;
 v_round_id uuid;
 v_game text;
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 select r.id,p.id,r.game into v_room_id,v_player_id,v_game
 from public.rooms r join public.players p on p.room_id=r.id
 where r.code=upper(btrim(coalesce(p_code,'')))
   and p.auth_user_id=v_uid
   and r.game_status='playing'
 limit 1;
 if v_room_id is null then raise exception 'You are not a member of an active game'; end if;
 select gr.id into v_round_id
 from public.game_rounds gr join public.rooms r on r.id=gr.room_id
 where gr.room_id=v_room_id and gr.round_number=r.current_round
 limit 1;
 if v_round_id is null then return false; end if;
 if v_game='friendship-court' then
  return exists(select 1 from public.votes v where v.round_id=v_round_id and v.voter_player_id=v_player_id);
 end if;
 return exists(select 1 from public.answers a where a.round_id=v_round_id and a.player_id=v_player_id);
end;
$$;
revoke all on function public.has_playam_submitted(text) from public,anon;
grant execute on function public.has_playam_submitted(text) to authenticated;

