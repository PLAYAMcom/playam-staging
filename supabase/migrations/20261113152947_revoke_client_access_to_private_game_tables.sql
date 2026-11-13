-- Exported from PLAYAM Staging migration history (20261113152947).
-- Apply only to the matching Staging project after reviewing the migration.

revoke all on table public.game_awards from anon, authenticated;
revoke all on table public.game_levels from anon, authenticated;
revoke all on table public.game_results from anon, authenticated;
revoke all on table public.player_profiles from anon, authenticated;
revoke all on table public.rounds from anon, authenticated;

