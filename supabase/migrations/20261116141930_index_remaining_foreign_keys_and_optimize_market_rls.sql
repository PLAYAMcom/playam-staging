-- Staging performance follow-up:
-- Add indexes for foreign-key columns reported by the Supabase advisor.
-- Keep indexes narrow and deterministic; no table data or wallet logic is changed.

create index if not exists playam_creator_currency_ledger_auth_user_id_idx
  on private.playam_creator_currency_ledger_v1 (auth_user_id);

create index if not exists playam_market_payment_methods_country_currency_idx
  on private.playam_market_payment_methods (country_code, currency_code);
create index if not exists playam_market_payment_methods_country_idx
  on private.playam_market_payment_methods (country_code);

create index if not exists flow_cloudflare_uploads_post_id_idx
  on public.flow_cloudflare_uploads (post_id);
create index if not exists flow_content_moderation_post_id_idx
  on public.flow_content_moderation (post_id);
create index if not exists flow_content_moderation_reporter_id_idx
  on public.flow_content_moderation (reporter_auth_user_id);
create index if not exists flow_content_moderation_reviewer_id_idx
  on public.flow_content_moderation (reviewer_auth_user_id);
create index if not exists flow_creator_eligibility_reviewed_by_idx
  on public.flow_creator_eligibility (reviewed_by);
create index if not exists flow_media_processing_jobs_post_id_idx
  on public.flow_media_processing_jobs (post_id);
create index if not exists flow_post_assets_creator_id_idx
  on public.flow_post_assets (creator_auth_user_id);
create index if not exists flow_post_comments_author_id_idx
  on public.flow_post_comments (author_auth_user_id);
create index if not exists flow_post_comments_parent_id_idx
  on public.flow_post_comments (parent_comment_id);
create index if not exists flow_post_likes_user_id_idx
  on public.flow_post_likes (user_auth_user_id);
create index if not exists flow_video_creator_rewards_approved_by_idx
  on public.flow_video_creator_rewards (approved_by);
create index if not exists flow_video_reward_approval_audit_creator_id_idx
  on public.flow_video_reward_approval_audit (creator_auth_user_id);
create index if not exists flow_video_reward_approval_audit_ledger_id_idx
  on public.flow_video_reward_approval_audit (ledger_transaction_id);
create index if not exists flow_video_reward_approval_audit_period_id_idx
  on public.flow_video_reward_approval_audit (period_id);
create index if not exists flow_video_reward_policy_updated_by_idx
  on public.flow_video_reward_policy (updated_by);
create index if not exists flow_view_events_viewer_id_idx
  on public.flow_view_events (viewer_auth_user_id);
create index if not exists playam_live_gift_events_sender_id_idx
  on public.playam_live_gift_events (sender_auth_user_id);
create index if not exists playam_user_market_preferences_country_currency_idx
  on public.playam_user_market_preferences (country_code, preferred_currency_code);
create index if not exists playam_user_market_preferences_country_idx
  on public.playam_user_market_preferences (country_code);

-- Evaluate auth.uid() once per statement rather than once per candidate row.
drop policy if exists playam_users_insert_own_market_preference
  on public.playam_user_market_preferences;
create policy playam_users_insert_own_market_preference
  on public.playam_user_market_preferences
  for insert to authenticated
  with check ((select auth.uid()) = auth_user_id);

drop policy if exists playam_users_read_own_market_preference
  on public.playam_user_market_preferences;
create policy playam_users_read_own_market_preference
  on public.playam_user_market_preferences
  for select to authenticated
  using ((select auth.uid()) = auth_user_id);

drop policy if exists playam_users_update_own_market_preference
  on public.playam_user_market_preferences;
create policy playam_users_update_own_market_preference
  on public.playam_user_market_preferences
  for update to authenticated
  using ((select auth.uid()) = auth_user_id)
  with check ((select auth.uid()) = auth_user_id);
