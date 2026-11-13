-- Exported from PLAYAM Staging migration history (20261113152518).
-- Apply only to the matching Staging project after reviewing the migration.

create index if not exists answers_player_id_idx on public.answers(player_id);
create index if not exists game_awards_player_id_idx on public.game_awards(player_id);
create index if not exists game_awards_room_id_idx on public.game_awards(room_id);
create index if not exists game_results_player_id_idx on public.game_results(player_id);
create index if not exists game_rounds_question_id_idx on public.game_rounds(question_id);
create index if not exists players_room_id_idx on public.players(room_id);
create index if not exists rooms_level_key_idx on public.rooms(level_key);
create index if not exists rooms_winner_id_idx on public.rooms(winner_id);
create index if not exists votes_target_player_id_idx on public.votes(target_player_id);
create index if not exists votes_voter_player_id_idx on public.votes(voter_player_id);
create index if not exists questions_active_game_difficulty_type_idx
 on public.questions(game_key,difficulty_key,question_type) where active=true;

-- The UNIQUE constraint already creates votes_round_id_voter_player_id_key.
-- Remove the identical standalone index only after confirming the constraint index exists.
drop index if exists public.one_vote_per_player_per_round;

