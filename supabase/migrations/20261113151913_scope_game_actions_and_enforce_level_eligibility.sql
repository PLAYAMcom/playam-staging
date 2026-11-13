-- Exported from PLAYAM Staging migration history (20261113151913).
-- Apply only to the matching Staging project after reviewing the migration.

-- Scope every gameplay action to the room the signed-in player is actually using.
create or replace function public.create_playam_room(
  p_nickname text,p_rounds integer,p_game text,p_level_key text
) returns table(room_code text,player_id uuid)
language plpgsql security definer set search_path=''
as $$
declare
 v_uid uuid:=auth.uid(); v_room_id uuid; v_code text; v_player_id uuid; v_attempt integer;
 v_level public.game_levels%rowtype; v_xp integer:=0; v_wins integer:=0; v_age_verified boolean:=false;
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 if length(btrim(coalesce(p_nickname,''))) not between 1 and 20 then raise exception 'Nickname must be 1 to 20 characters'; end if;
 if p_rounds not in (5,10,15,20) then raise exception 'Invalid round count'; end if;
 if p_game not in ('friendship-court','would-you-rather','truth-or-dare','mind-battle','secret-confessions') then raise exception 'Unsupported game mode'; end if;
 select * into v_level from public.game_levels where level_key=p_level_key;
 if not found then raise exception 'Invalid difficulty'; end if;
 select coalesce(xp,0),coalesce(wins,0) into v_xp,v_wins from public.player_profiles where auth_user_id=v_uid;
 select coalesce((raw_app_meta_data->>'age_verified')='true',false) into v_age_verified from auth.users where id=v_uid;
 if v_level.adults_only and not v_age_verified then raise exception 'This level requires verified adult status'; end if;
 if v_xp<v_level.minimum_xp or v_wins<v_level.minimum_wins then raise exception 'This difficulty is locked. Meet its XP and win requirements first'; end if;
 for v_attempt in 1..10 loop
  v_code:=upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
  begin
   insert into public.rooms(code,game,rounds,status,current_round,game_status,level_key)
   values(v_code,p_game,p_rounds,'waiting',0,'waiting',p_level_key) returning id into v_room_id;
   exit;
  exception when unique_violation then v_room_id:=null;
  end;
 end loop;
 if v_room_id is null then raise exception 'Could not create a unique room code'; end if;
 insert into public.players(room_id,nickname,is_host,is_ready,auth_user_id)
 values(v_room_id,btrim(p_nickname),true,false,v_uid) returning id into v_player_id;
 insert into public.player_profiles(auth_user_id,nickname)
 values(v_uid,btrim(p_nickname)) on conflict(auth_user_id) do update set nickname=excluded.nickname,updated_at=now();
 return query select v_code,v_player_id;
end;
$$;

create or replace function public.join_playam_room(p_code text,p_nickname text)
returns table(room_code text,player_id uuid)
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_room public.rooms%rowtype; v_level public.game_levels%rowtype;
 v_player_id uuid; v_xp integer:=0; v_wins integer:=0; v_age_verified boolean:=false;
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 if length(btrim(coalesce(p_nickname,''))) not between 1 and 20 then raise exception 'Nickname must be 1 to 20 characters'; end if;
 select * into v_room from public.rooms where code=upper(btrim(coalesce(p_code,''))) for update;
 if not found then raise exception 'Room not found'; end if;
 if coalesce(v_room.game_status,v_room.status)<>'waiting' then raise exception 'This room has already started'; end if;
 select * into v_level from public.game_levels where level_key=v_room.level_key;
 select coalesce(xp,0),coalesce(wins,0) into v_xp,v_wins from public.player_profiles where auth_user_id=v_uid;
 select coalesce((raw_app_meta_data->>'age_verified')='true',false) into v_age_verified from auth.users where id=v_uid;
 if v_level.adults_only and not v_age_verified then raise exception 'This level requires verified adult status'; end if;
 if v_xp<v_level.minimum_xp or v_wins<v_level.minimum_wins then raise exception 'You do not yet meet this room difficulty requirement'; end if;
 if (select count(*) from public.players where room_id=v_room.id)>=20 then raise exception 'This room is full'; end if;
 select id into v_player_id from public.players where room_id=v_room.id and auth_user_id=v_uid limit 1;
 if v_player_id is null then
  insert into public.players(room_id,nickname,is_host,is_ready,auth_user_id)
  values(v_room.id,btrim(p_nickname),false,false,v_uid) returning id into v_player_id;
 end if;
 insert into public.player_profiles(auth_user_id,nickname)
 values(v_uid,btrim(p_nickname)) on conflict(auth_user_id) do update set nickname=excluded.nickname,updated_at=now();
 return query select v_room.code,v_player_id;
end;
$$;

create or replace function public.set_playam_ready(p_ready boolean,p_code text)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_player_id uuid;
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 select p.id into v_player_id from public.players p join public.rooms r on r.id=p.room_id
 where p.auth_user_id=v_uid and r.code=upper(btrim(coalesce(p_code,''))) and coalesce(r.game_status,r.status)='waiting'
 limit 1;
 if v_player_id is null then raise exception 'You are not a member of this waiting room'; end if;
 update public.players set is_ready=coalesce(p_ready,false) where id=v_player_id;
 return coalesce(p_ready,false);
end;
$$;

create or replace function public.start_playam_game(p_code text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_room public.rooms%rowtype; v_player_count integer; v_ready_count integer;
 v_question_id uuid; v_round_id uuid; v_type text; v_xp integer:=0; v_wins integer:=0; v_age_verified boolean:=false;
 v_level public.game_levels%rowtype;
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 select r.* into v_room from public.rooms r join public.players p on p.room_id=r.id
 where r.code=upper(btrim(coalesce(p_code,''))) and p.auth_user_id=v_uid and p.is_host=true
 and coalesce(r.game_status,r.status)='waiting' for update of r;
 if not found then raise exception 'Only the host of this waiting room can start the game'; end if;
 select * into v_level from public.game_levels where level_key=v_room.level_key;
 select coalesce(xp,0),coalesce(wins,0) into v_xp,v_wins from public.player_profiles where auth_user_id=v_uid;
 select coalesce((raw_app_meta_data->>'age_verified')='true',false) into v_age_verified from auth.users where id=v_uid;
 if v_level.adults_only and not v_age_verified then raise exception 'This level requires verified adult status'; end if;
 if v_xp<v_level.minimum_xp or v_wins<v_level.minimum_wins then raise exception 'Difficulty requirements are not met'; end if;
 select count(*),count(*) filter(where is_ready) into v_player_count,v_ready_count from public.players where room_id=v_room.id;
 if v_player_count<2 then raise exception 'At least two players are required'; end if;
 if v_ready_count<>v_player_count then raise exception 'Every player must be ready before the game starts'; end if;
 v_type:=case v_room.game when 'would-you-rather' then 'choice' when 'truth-or-dare' then 'truth' when 'secret-confessions' then 'confession' else 'open' end;
 select q.id into v_question_id from public.questions q
 where q.active=true and q.game_key=v_room.game and q.difficulty_key=v_room.level_key
 and (q.question_type=v_type or (v_room.game='truth-or-dare' and q.question_type='dare'))
 and not exists(select 1 from public.game_rounds old where old.room_id=v_room.id and old.question_id=q.id)
 order by random() limit 1;
 if v_question_id is null then raise exception 'No unused questions are available for this game and difficulty'; end if;
 insert into public.game_rounds(room_id,round_number,question_id,status,starts_at,ends_at)
 values(v_room.id,1,v_question_id,'voting',now(),now()+interval '30 seconds') returning id into v_round_id;
 update public.rooms set status='playing',game_status='playing',current_round=1 where id=v_room.id;
 return v_round_id;
end;
$$;

create or replace function public.submit_playam_answer(p_answer text,p_code text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_room_id uuid; v_player_id uuid; v_round_id uuid; v_game text; v_answer_id uuid;
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 if length(btrim(coalesce(p_answer,''))) not between 1 and 2000 then raise exception 'Answer must be 1 to 2,000 characters'; end if;
 select p.id,r.id,r.game into v_player_id,v_room_id,v_game
 from public.players p join public.rooms r on r.id=p.room_id
 where p.auth_user_id=v_uid and r.code=upper(btrim(coalesce(p_code,''))) and r.game_status='playing' limit 1;
 if v_player_id is null then raise exception 'You are not a player in this active game'; end if;
 if v_game='friendship-court' then raise exception 'Friendship Court uses private player voting'; end if;
 select gr.id into v_round_id from public.game_rounds gr join public.rooms r on r.id=gr.room_id
 where gr.room_id=v_room_id and gr.round_number=r.current_round and gr.status='voting' and gr.ends_at>now()
 for update of gr;
 if v_round_id is null then raise exception 'The round is closed'; end if;
 insert into public.answers(round_id,player_id,answer) values(v_round_id,v_player_id,btrim(p_answer)) returning id into v_answer_id;
 return v_answer_id;
exception when unique_violation then raise exception 'You have already submitted an answer for this round';
end;
$$;

create or replace function public.advance_playam_round(p_code text)
returns text language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_room public.rooms%rowtype; v_round public.game_rounds%rowtype;
 v_players integer; v_submissions integer; v_question_id uuid; v_type text; v_winner uuid;
begin
 if v_uid is null then raise exception 'Authentication required'; end if;
 select r.* into v_room from public.rooms r join public.players p on p.room_id=r.id
 where r.code=upper(btrim(coalesce(p_code,''))) and p.auth_user_id=v_uid and r.game_status='playing'
 for update of r;
 if not found then raise exception 'You are not a member of this active game'; end if;
 select * into v_round from public.game_rounds where room_id=v_room.id and round_number=v_room.current_round for update;
 if v_round.id is null or v_round.status<>'voting' then return 'already_advanced'; end if;
 select count(*) into v_players from public.players where room_id=v_room.id;
 if v_room.game='friendship-court' then
  select count(*) into v_submissions from public.votes where round_id=v_round.id;
 else
  select count(*) into v_submissions from public.answers where round_id=v_round.id;
 end if;
 if now()<v_round.ends_at and v_submissions<v_players then return 'waiting'; end if;
 if v_room.game='friendship-court' then
  update public.players p set score=coalesce(p.score,0)+coalesce(v.cnt,0)
  from (select target_player_id,count(*)::integer cnt from public.votes where round_id=v_round.id group by target_player_id) v
  where p.id=v.target_player_id and p.room_id=v_room.id;
 end if;
 update public.game_rounds set status='complete',scored_at=now() where id=v_round.id;
 if v_room.current_round>=v_room.rounds then
  if v_room.game='friendship-court' then
   insert into public.game_results(room_id,player_id,total_votes_received,times_accused,most_voted_category)
   select v_room.id,p.id,coalesce(sum(vc.vote_count),0)::integer,coalesce(count(distinct vc.round_id),0)::integer,
     (select q.category from public.votes vv join public.game_rounds gr on gr.id=vv.round_id
       join public.questions q on q.id=gr.question_id where gr.room_id=v_room.id and vv.target_player_id=p.id
       group by q.category order by count(*) desc,q.category limit 1)
   from public.players p left join (
     select target_player_id,round_id,count(*)::integer vote_count from public.votes v
     join public.game_rounds gr on gr.id=v.round_id where gr.room_id=v_room.id group by target_player_id,round_id
   ) vc on vc.target_player_id=p.id
   where p.room_id=v_room.id group by p.id
   on conflict(room_id,player_id) do update set total_votes_received=excluded.total_votes_received,
    times_accused=excluded.times_accused,most_voted_category=excluded.most_voted_category;
   select id into v_winner from public.players where room_id=v_room.id order by score desc,id limit 1;
   if (select count(*) from public.players where room_id=v_room.id and score=(select max(score) from public.players where room_id=v_room.id))=1 then
    update public.rooms set winner_id=v_winner,status='finished',game_status='finished' where id=v_room.id;
    update public.player_profiles pp set wins=pp.wins+1,xp=pp.xp+10,updated_at=now()
    from public.players p where p.room_id=v_room.id and p.id=v_winner and pp.auth_user_id=p.auth_user_id;
    update public.player_profiles pp set losses=pp.losses+1,xp=pp.xp+5,updated_at=now()
    from public.players p where p.room_id=v_room.id and p.id<>v_winner and pp.auth_user_id=p.auth_user_id;
   else
    update public.rooms set winner_id=null,status='finished',game_status='finished' where id=v_room.id;
    update public.player_profiles pp set xp=pp.xp+5,updated_at=now()
    from public.players p where p.room_id=v_room.id and pp.auth_user_id=p.auth_user_id;
   end if;
  else
   update public.rooms set status='finished',game_status='finished' where id=v_room.id;
  end if;
  return 'finished';
 end if;
 v_type:=case v_room.game when 'would-you-rather' then 'choice' when 'truth-or-dare' then 'truth' when 'secret-confessions' then 'confession' else 'open' end;
 select q.id into v_question_id from public.questions q
 where q.active=true and q.game_key=v_room.game and q.difficulty_key=v_room.level_key
 and (q.question_type=v_type or (v_room.game='truth-or-dare' and q.question_type='dare'))
 and not exists(select 1 from public.game_rounds old where old.room_id=v_room.id and old.question_id=q.id)
 order by random() limit 1;
 if v_question_id is null then
  update public.rooms set status='finished',game_status='finished' where id=v_room.id;
  return 'finished_no_more_questions';
 end if;
 update public.rooms set current_round=current_round+1 where id=v_room.id;
 insert into public.game_rounds(room_id,round_number,question_id,status,starts_at,ends_at)
 values(v_room.id,v_room.current_round+1,v_question_id,'voting',now(),now()+interval '30 seconds');
 return 'advanced';
end;
$$;

-- Keep the API limited to signed-in users; the frontend uses the new room-scoped signatures.
revoke all on function public.set_playam_ready(boolean) from public,anon,authenticated;
revoke all on function public.start_playam_game() from public,anon,authenticated;
revoke all on function public.submit_playam_answer(text) from public,anon,authenticated;
revoke all on function public.advance_playam_round() from public,anon,authenticated;
revoke all on function public.set_playam_ready(boolean,text) from public,anon;
revoke all on function public.start_playam_game(text) from public,anon;
revoke all on function public.submit_playam_answer(text,text) from public,anon;
revoke all on function public.advance_playam_round(text) from public,anon;
grant execute on function public.set_playam_ready(boolean,text) to authenticated;
grant execute on function public.start_playam_game(text) to authenticated;
grant execute on function public.submit_playam_answer(text,text) to authenticated;
grant execute on function public.advance_playam_round(text) to authenticated;

