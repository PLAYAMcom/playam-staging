# PLAYAM Flow — Staging schema status

Checked: 2026-11-13
Environment: Supabase Staging project only.

## Created database foundation

Nine new tables were created additively in Staging:

- `flow_posts` — creator, caption, visibility, publication and moderation state.
- `flow_post_assets` — storage object references and quarantined/processing/ready state.
- `flow_post_likes` — one like per user per post.
- `flow_post_comments` — comments and replies with moderation state.
- `flow_follows` — unique follower/followed relationship; self-follow prohibited.
- `flow_view_events` — deduplicated view events and server qualification fields.
- `flow_creator_metrics_daily` — daily aggregated creator performance metrics.
- `flow_creator_eligibility` — locked-by-default monetisation eligibility, threshold snapshots and review fields.
- `flow_content_moderation` — post reports and review outcomes.

Indexes were added for creator posts, feed ordering, assets, comments, follows, view events and moderation queues.

## Security state verified

All nine tables have Row Level Security enabled. There are currently no RLS policies and no grants to `anon` or `authenticated`. This is intentional deny-by-default protection while the server-side API and narrowly scoped access rules are being built. The tables are not yet accessible to the app.

The Supabase security advisor reports the nine new tables among its RLS-enabled/no-policy informational findings. This is expected at this foundation stage. Existing advisor findings remain: 18 SECURITY DEFINER functions need individual review, and leaked-password protection remains disabled. No broad permission changes were made.

## Not built yet

- No Flow Storage bucket exists in Staging; the storage bucket query returned zero.
- No upload or transcoding pipeline.
- No feed API, feed UI, or client interactions.
- No server-side view qualification/anti-fraud pipeline.
- No monetisation eligibility evaluator or funded campaign payout integration.
- No creator earnings were issued; no payments or withdrawals were run.

## Migration-history caveat

Staging's migration history was previously found empty. This additive schema was applied directly through the database SQL interface and verified in place; it has not yet been reconciled into a version-controlled Supabase migration. Before any future reset, branch promotion or deployment automation, capture and reconcile the remote schema into a proper migration. Do not run a reset or destructive migration.

## Non-negotiable safeguards

- Do not grant direct client write access to view counts, qualification, moderation outcomes, eligibility or earnings.
- Build authenticated, server-authoritative APIs and specific RLS rules before enabling app access.
- Keep video uploads quarantined/private until scanning and processing succeed.
- Monetisation requires both the approved follower and qualified-view thresholds plus policy checks. Likes contribute to engagement quality but do not directly create cash.
- Credit only funded and verified earnings through the existing creator earnings ledger.
- Keep Staging and Production separate; no Production resources or user data were touched.
