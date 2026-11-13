-- Exported from PLAYAM Staging migration history (20261113145740).
-- Apply only to the matching Staging project after reviewing the migration.

-- Correct the room-code retry variable and use non-recursive membership checks.
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
  v_attempt integer;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if length(btrim(coalesce(p_nickname,''))) not between 1 and 20 then raise exception 'Nickname must be 1 to 20 characters'; end if;
  if p_rounds not in (5,10,15,20) then raise exception 'Invalid round count'; end if;
  if p_game not in ('friendship-court','would-you-rather','truth-or-dare','mind-battle','secret-confessions') then raise exception 'Unsupported game mode'; end if;
  if not exists(select 1 from public.game_levels gl where gl.level_key=p_level_key) then raise exception 'Invalid difficulty'; end if;
  for v_attempt in 1..10 loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text),1,6));
    begin
      insert into public.rooms(code,game,rounds,status,current_round,game_status,level_key)
      values(v_code,p_game,p_rounds,'waiting',0,'waiting',p_level_key)
      returning id into v_room_id;
      exit;
    exception when unique_violation then v_room_id := null;
    end;
  end loop;
  if v_room_id is null then raise exception 'Could not create a unique room code'; end if;
  insert into public.players(room_id,nickname,is_host,is_ready,auth_user_id)
  values(v_room_id,btrim(p_nickname),true,false,v_uid) returning id into v_player_id;
  return query select v_code,v_player_id;
end;
$$;

create or replace function public.playam_is_room_member(p_room_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select (select auth.uid()) is not null and exists(
    select 1 from public.players p
    where p.room_id=p_room_id and p.auth_user_id=(select auth.uid())
  );
$$;

create or replace function public.playam_can_cast_vote(p_round_id uuid,p_voter_id uuid,p_target_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select (select auth.uid()) is not null and exists(
    select 1
    from public.players voter
    join public.game_rounds gr on gr.id=p_round_id
    join public.rooms r on r.id=gr.room_id
    join public.players target on target.id=p_target_id and target.room_id=voter.room_id
    where voter.id=p_voter_id
      and voter.auth_user_id=(select auth.uid())
      and voter.id<>target.id
      and r.game='friendship-court'
      and r.game_status='playing'
      and gr.status='voting'
      and gr.ends_at>now()
  );
$$;

drop policy if exists playam_rooms_member_read on public.rooms;
create policy playam_rooms_member_read on public.rooms for select to authenticated
using (public.playam_is_room_member(id));

drop policy if exists playam_players_room_member_read on public.players;
create policy playam_players_room_member_read on public.players for select to authenticated
using (public.playam_is_room_member(room_id));

drop policy if exists playam_game_rounds_member_read on public.game_rounds;
create policy playam_game_rounds_member_read on public.game_rounds for select to authenticated
using (public.playam_is_room_member(room_id));

drop policy if exists playam_votes_member_insert on public.votes;
create policy playam_votes_member_insert on public.votes for insert to authenticated
with check (public.playam_can_cast_vote(round_id,voter_player_id,target_player_id));

revoke all on function public.playam_is_room_member(uuid) from public,anon;
revoke all on function public.playam_can_cast_vote(uuid,uuid,uuid) from public,anon;
grant execute on function public.playam_is_room_member(uuid) to authenticated;
grant execute on function public.playam_can_cast_vote(uuid,uuid,uuid) to authenticated;

-- Starter Friendship Court content recovered from the user's original project files.
insert into public.questions(text,category,active,level,game_key,difficulty_key,question_type)
select v.question_text,v.category,true,1,'friendship-court','starter','open'
from (values
('Who is most likely to disappear and reply three days later? 😭','Friendship Chaos'),
('Who is most likely to borrow money and suddenly forget? 💀','Money'),
('Who is most likely to go back to their ex? 👀','Relationships'),
('Who is the biggest red flag in this friendship group? 🚩','Red Flags'),
('Who is most likely to stalk someone for one hour? 😂','Social Media'),
('Who would expose the group secret first? 😭','Friendship Chaos'),
('Who acts rich but is always asking for urgent 2k? 💸','Money'),
('Who falls in love the fastest? ❤️','Relationships'),
('Who should NEVER be trusted with your phone unlocked? 📱','Red Flags'),
('Who is most likely to start drama and say ''I hate drama''? 💀','Friendship Chaos'),
('Who is most likely to delete a post because it did not get enough likes? 😂','Social Media'),
('Who has the worst taste in partners? 😭','Relationships'),
('Who is most likely to spend their last money on enjoyment? 🔥','Money'),
('Who would be the hardest person to date in this room? 🚩','Red Flags'),
('Who would survive the longest in a reality show? 👀','Friendship Chaos')
) as v(question_text,category)
where not exists (
  select 1 from public.questions q
  where q.game_key='friendship-court' and q.difficulty_key='starter' and q.text=v.question_text
);

create or replace function public.advance_playam_round()
returns text language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid := auth.uid();
  v_room_id uuid;
  v_room public.rooms%rowtype;
  v_round public.game_rounds%rowtype;
  v_players integer;
  v_submissions integer;
  v_question_id uuid;
  v_type text;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select r.id into v_room_id
  from public.rooms r join public.players p on p.room_id=r.id
  where p.auth_user_id=v_uid and r.game_status='playing'
  order by p.joined_at desc limit 1;
  if v_room_id is null then raise exception 'No active game found'; end if;
  select * into v_room from public.rooms where id=v_room_id for update;
  select * into v_round from public.game_rounds
  where room_id=v_room_id and round_number=v_room.current_round for update;
  if v_round.id is null or v_round.status<>'voting' then return 'already_advanced'; end if;

  select count(*) into v_players from public.players where room_id=v_room_id;
  if v_room.game='friendship-court' then
    select count(*) into v_submissions from public.votes where round_id=v_round.id;
  else
    select count(*) into v_submissions from public.answers where round_id=v_round.id;
  end if;
  if now()<v_round.ends_at and v_submissions<v_players then return 'waiting'; end if;

  if v_room.game='friendship-court' then
    update public.players p set score=coalesce(p.score,0)+coalesce(v.cnt,0)
    from (select target_player_id,count(*)::integer cnt from public.votes where round_id=v_round.id group by target_player_id) v
    where p.id=v.target_player_id;
  end if;
  update public.game_rounds set status='complete',scored_at=now() where id=v_round.id;

  if v_room.current_round>=v_room.rounds then
    update public.rooms set status='finished',game_status='finished' where id=v_room_id;
    return 'finished';
  end if;

  v_type := case v_room.game
    when 'would-you-rather' then 'choice'
    when 'truth-or-dare' then 'truth'
    when 'secret-confessions' then 'confession'
    else 'open' end;
  select q.id into v_question_id from public.questions q
  where q.active=true and q.game_key=v_room.game and q.difficulty_key=v_room.level_key
    and (q.question_type=v_type or (v_room.game='truth-or-dare' and q.question_type='dare'))
  order by random() limit 1;
  if v_question_id is null then
    update public.rooms set status='finished',game_status='finished' where id=v_room_id;
    return 'finished_no_more_questions';
  end if;
  update public.rooms set current_round=current_round+1 where id=v_room_id;
  insert into public.game_rounds(room_id,round_number,question_id,status,starts_at,ends_at)
  values(v_room_id,v_room.current_round+1,v_question_id,'voting',now(),now()+interval '30 seconds');
  return 'advanced';
end;
$$;
revoke all on function public.advance_playam_round() from public,anon;
grant execute on function public.advance_playam_round() to authenticated;

