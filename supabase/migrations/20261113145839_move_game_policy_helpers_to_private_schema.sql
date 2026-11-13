-- Exported from PLAYAM Staging migration history (20261113145839).
-- Apply only to the matching Staging project after reviewing the migration.

create schema if not exists private;
revoke all on schema private from public,anon;
grant usage on schema private to authenticated;

create or replace function private.playam_is_room_member(p_room_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select (select auth.uid()) is not null and exists(
    select 1 from public.players p
    where p.room_id=p_room_id and p.auth_user_id=(select auth.uid())
  );
$$;

create or replace function private.playam_can_cast_vote(p_round_id uuid,p_voter_id uuid,p_target_id uuid)
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
revoke all on function private.playam_is_room_member(uuid) from public,anon;
revoke all on function private.playam_can_cast_vote(uuid,uuid,uuid) from public,anon;
grant execute on function private.playam_is_room_member(uuid) to authenticated;
grant execute on function private.playam_can_cast_vote(uuid,uuid,uuid) to authenticated;

drop policy if exists playam_rooms_member_read on public.rooms;
drop policy if exists playam_players_room_member_read on public.players;
drop policy if exists playam_game_rounds_member_read on public.game_rounds;
drop policy if exists playam_votes_member_insert on public.votes;

create policy playam_rooms_member_read on public.rooms for select to authenticated
using (private.playam_is_room_member(id));
create policy playam_players_room_member_read on public.players for select to authenticated
using (private.playam_is_room_member(room_id));
create policy playam_game_rounds_member_read on public.game_rounds for select to authenticated
using (private.playam_is_room_member(room_id));
create policy playam_votes_member_insert on public.votes for insert to authenticated
with check (private.playam_can_cast_vote(round_id,voter_player_id,target_player_id));

drop function if exists public.playam_is_room_member(uuid);
drop function if exists public.playam_can_cast_vote(uuid,uuid,uuid);

