-- Exported from PLAYAM Staging migration history (20261113145709).
-- Apply only to the matching Staging project after reviewing the migration.

-- PLAYAM Staging-only gameplay foundation. No production data or objects touched.
-- Existing tables are retained; no destructive statements are used.

create or replace function public.create_playam_room(
  p_nickname text, p_rounds integer, p_game text, p_level_key text
) returns table(room_code text, player_id uuid)
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room_id uuid;
  v_code text;
  v_player_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_nickname,''))) not between 1 and 20 then
    raise exception 'Nickname must be 1 to 20 characters';
  end if;
  if p_rounds not in (5,10,15,20) then raise exception 'Invalid round count'; end if;
  if p_game not in ('friendship-court','would-you-rather','truth-or-dare','mind-battle','secret-confessions') then
    raise exception 'Unsupported game mode';
  end if;
  if not exists(select 1 from public.game_levels gl where gl.level_key=p_level_key) then
    raise exception 'Invalid difficulty';
  end if;

  for v_code in 1..10 loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text),1,6));
    begin
      insert into public.rooms(code,game,rounds,status,current_round,game_status,level_key)
      values(v_code,p_game,p_rounds,'waiting',0,'waiting',p_level_key)
      returning id into v_room_id;
      exit;
    exception when unique_violation then
      v_room_id := null;
    end;
  end loop;
  if v_room_id is null then raise exception 'Could not create a unique room code'; end if;

  insert into public.players(room_id,nickname,is_host,is_ready,auth_user_id)
  values(v_room_id,btrim(p_nickname),true,false,v_uid)
  returning id into v_player_id;

  return query select v_code,v_player_id;
end;
$$;

create or replace function public.join_playam_room(p_code text,p_nickname text)
returns table(room_code text,player_id uuid)
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_player_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_nickname,''))) not between 1 and 20 then
    raise exception 'Nickname must be 1 to 20 characters';
  end if;
  select * into v_room from public.rooms r
  where r.code=upper(btrim(coalesce(p_code,''))) for update;
  if not found then raise exception 'Room not found'; end if;
  if coalesce(v_room.game_status,v_room.status) <> 'waiting' then
    raise exception 'This room has already started';
  end if;
  if (select count(*) from public.players p where p.room_id=v_room.id) >= 20 then
    raise exception 'This room is full';
  end if;
  select p.id into v_player_id from public.players p
  where p.room_id=v_room.id and p.auth_user_id=v_uid limit 1;
  if v_player_id is null then
    insert into public.players(room_id,nickname,is_host,is_ready,auth_user_id)
    values(v_room.id,btrim(p_nickname),false,false,v_uid)
    returning id into v_player_id;
  end if;
  return query select v_room.code,v_player_id;
end;
$$;

create or replace function public.get_playam_lobby(p_code text)
returns table(
  room_id uuid, room_code text, player_id uuid, nickname text,
  is_host boolean, is_ready boolean, game_status text,
  current_round integer, total_rounds integer
)
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_room_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select r.id into v_room_id from public.rooms r
  where r.code=upper(btrim(coalesce(p_code,'')));
  if v_room_id is null then raise exception 'Room not found'; end if;
  if not exists(select 1 from public.players p where p.room_id=v_room_id and p.auth_user_id=v_uid) then
    raise exception 'You are not a member of this room';
  end if;
  return query
  select r.id,r.code,p.id,p.nickname,coalesce(p.is_host,false),coalesce(p.is_ready,false),
         coalesce(r.game_status,r.status),r.current_round,r.rounds
  from public.rooms r join public.players p on p.room_id=r.id
  where r.id=v_room_id order by p.joined_at,p.id;
end;
$$;

create or replace function public.set_playam_ready(p_ready boolean)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_player_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select p.id into v_player_id
  from public.players p join public.rooms r on r.id=p.room_id
  where p.auth_user_id=v_uid and coalesce(r.game_status,r.status)='waiting'
  order by p.joined_at desc limit 1;
  if v_player_id is null then raise exception 'No waiting room membership found'; end if;
  update public.players set is_ready=coalesce(p_ready,false) where id=v_player_id;
  return coalesce(p_ready,false);
end;
$$;

create or replace function public.start_playam_game()
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_room public.rooms%rowtype;
  v_room_id uuid; v_player_count integer; v_ready_count integer;
  v_question_id uuid; v_round_id uuid; v_type text;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select r.id into v_room_id
  from public.rooms r join public.players p on p.room_id=r.id
  where p.auth_user_id=v_uid and p.is_host=true and coalesce(r.game_status,r.status)='waiting'
  order by p.joined_at desc limit 1;
  if v_room_id is null then raise exception 'Only the host of a waiting room can start the game'; end if;
  select * into v_room from public.rooms where id=v_room_id for update;
  select count(*),count(*) filter(where is_ready)
  into v_player_count,v_ready_count from public.players where room_id=v_room_id;
  if v_player_count < 2 then raise exception 'At least two players are required'; end if;
  if v_ready_count <> v_player_count then raise exception 'Every player must be ready before the game starts'; end if;

  v_type := case v_room.game
    when 'would-you-rather' then 'choice'
    when 'truth-or-dare' then 'truth'
    when 'secret-confessions' then 'confession'
    else 'open' end;
  select q.id into v_question_id from public.questions q
  where q.active=true and q.game_key=v_room.game
    and q.difficulty_key=v_room.level_key
    and (q.question_type=v_type or (v_room.game='truth-or-dare' and q.question_type='dare'))
  order by random() limit 1;
  if v_question_id is null then
    raise exception 'No active questions are available for this game and difficulty yet';
  end if;

  insert into public.game_rounds(room_id,round_number,question_id,status,starts_at,ends_at)
  values(v_room_id,1,v_question_id,'voting',now(),now()+interval '30 seconds')
  returning id into v_round_id;
  update public.rooms set status='playing',game_status='playing',current_round=1 where id=v_room_id;
  return v_round_id;
end;
$$;

create or replace function public.submit_playam_answer(p_answer text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_room_id uuid; v_player_id uuid;
        v_round_id uuid; v_game text; v_answer_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_answer,''))) not between 1 and 2000 then
    raise exception 'Answer must be 1 to 2,000 characters';
  end if;
  select p.id,r.id,r.game into v_player_id,v_room_id,v_game
  from public.players p join public.rooms r on r.id=p.room_id
  where p.auth_user_id=v_uid and r.game_status='playing'
  order by p.joined_at desc limit 1;
  if v_player_id is null then raise exception 'No active game found'; end if;
  if v_game='friendship-court' then raise exception 'Friendship Court uses private player voting'; end if;
  select gr.id into v_round_id from public.game_rounds gr
  join public.rooms r on r.id=gr.room_id
  where gr.room_id=v_room_id and gr.round_number=r.current_round
    and gr.status='voting' and gr.ends_at>now()
  for update of gr;
  if v_round_id is null then raise exception 'The round is closed'; end if;
  insert into public.answers(round_id,player_id,answer)
  values(v_round_id,v_player_id,btrim(p_answer))
  returning id into v_answer_id;
  return v_answer_id;
exception when unique_violation then
  raise exception 'You have already submitted an answer for this round';
end;
$$;

-- Only authenticated players may read the game data needed by the existing client.
revoke all on public.rooms,public.players,public.questions,public.game_rounds,public.votes,public.answers from anon,authenticated;
grant select on public.rooms,public.players,public.questions,public.game_rounds to authenticated;
grant insert on public.votes to authenticated;

drop policy if exists playam_rooms_member_read on public.rooms;
create policy playam_rooms_member_read on public.rooms for select to authenticated
using (exists(select 1 from public.players p where p.room_id=rooms.id and p.auth_user_id=(select auth.uid())));

drop policy if exists playam_players_room_member_read on public.players;
create policy playam_players_room_member_read on public.players for select to authenticated
using (exists(select 1 from public.players me where me.room_id=players.room_id and me.auth_user_id=(select auth.uid())));

drop policy if exists playam_questions_active_read on public.questions;
create policy playam_questions_active_read on public.questions for select to authenticated
using (active=true);

drop policy if exists playam_game_rounds_member_read on public.game_rounds;
create policy playam_game_rounds_member_read on public.game_rounds for select to authenticated
using (exists(select 1 from public.players p where p.room_id=game_rounds.room_id and p.auth_user_id=(select auth.uid())));

drop policy if exists playam_votes_member_insert on public.votes;
create policy playam_votes_member_insert on public.votes for insert to authenticated
with check (
  exists(
    select 1 from public.players voter
    join public.game_rounds gr on gr.id=votes.round_id
    join public.rooms r on r.id=gr.room_id
    join public.players target on target.id=votes.target_player_id and target.room_id=voter.room_id
    where voter.id=votes.voter_player_id
      and voter.auth_user_id=(select auth.uid())
      and voter.id<>target.id
      and r.game='friendship-court'
      and r.game_status='playing'
      and gr.status='voting'
      and gr.ends_at>now()
  )
);

revoke all on function public.create_playam_room(text,integer,text,text) from public,anon;
revoke all on function public.join_playam_room(text,text) from public,anon;
revoke all on function public.get_playam_lobby(text) from public,anon;
revoke all on function public.set_playam_ready(boolean) from public,anon;
revoke all on function public.start_playam_game() from public,anon;
revoke all on function public.submit_playam_answer(text) from public,anon;
grant execute on function public.create_playam_room(text,integer,text,text) to authenticated;
grant execute on function public.join_playam_room(text,text) to authenticated;
grant execute on function public.get_playam_lobby(text) to authenticated;
grant execute on function public.set_playam_ready(boolean) to authenticated;
grant execute on function public.start_playam_game() to authenticated;
grant execute on function public.submit_playam_answer(text) to authenticated;

