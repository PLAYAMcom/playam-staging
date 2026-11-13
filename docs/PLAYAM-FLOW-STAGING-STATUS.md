# PLAYAM Flow — Current Staging status
Checked: 2026-11-13
Environment: Staging only (`pwnjrdedeoxbmtfywhkk`).

## Database
Nine Flow tables exist: posts, post assets, likes, comments, follows, view events, daily creator metrics, creator eligibility and content moderation. They have RLS enabled and no direct client policies/grants. This is intentional deny-by-default; use authenticated server functions rather than opening direct table access.

## Private media storage
- Bucket `flow-media-staging` exists and is private.
- Maximum object size: 100 MiB.
- Allowed MIME types: MP4, QuickTime/MOV, WebM, JPEG, PNG and WebP.
- Authenticated users can upload/read only inside their own UID folder through the two bucket policies.
- Do not make this bucket public.

## Deployed Edge Functions (JWT verification enabled)
- `flow-create-upload`: creates a signed upload ticket for an authenticated user and their UID-scoped path.
- `flow-save-draft`: verifies uploaded object and stores a private draft plus quarantined asset record.
- `flow-social`: approved public feed retrieval, likes/unlikes, comments and follows/unfollows, via server-side access.
- `flow-admin-moderation`: requires a valid authenticated user, aal2 MFA and active `super_admin` role; lists pending drafts and records review decisions. Approval is blocked unless media asset processing status is `ready`.
- `flow-view-events`: records authenticated playback start/finish, excludes self-views, and permits one qualified event per viewer/post/day. Qualification is based on server elapsed time (up to 10 seconds, or 80% of known short-video duration). This is a baseline anti-abuse check, not proof of continuous attention or complete fraud prevention.

## Interface
- `site/flow.html` has Staging sign-in, upload/caption UI, feed, creator space and admin review panel.
- Upload screen calls `flow-create-upload`, uploads into private storage, then calls `flow-save-draft`.
- Feed/social actions call `flow-social`.
- Admin review panel calls `flow-admin-moderation`.
- Landing page links to Flow.

## Important limitations / not yet verified
- There are currently zero Flow posts and zero assets.
- No scanner, malware/content inspection or transcoding worker exists. Assets remain quarantined; public approval cannot succeed until a trusted processing pipeline marks assets ready.
- No end-to-end test with signed-in Staging users has been completed. No video upload/playback, feed, like, comment, follow or moderation action is claimed tested.
- Basic qualified-view event recording is implemented, but advanced anti-fraud/device risk analysis, continuous playback verification, creator analytics evaluator and monetisation eligibility thresholds are not implemented.
- No creator earnings or payouts were issued.
- Older Flow UI and schema commits may not yet have successful GitHub Actions / Pages deployment confirmation. Check the latest commit status before treating the hosted page as updated.

## Required next steps
1. Build secure media scanning/transcoding and thumbnail pipeline; only trusted worker can set asset `processing_status=ready`.
2. Strengthen view qualification with anti-bot/device risk checks, playback continuity validation and abuse monitoring; current implementation is only a first baseline.
3. Add profile/creator stats endpoints and creator dashboard.
4. Decide and document exact follower + qualified-view thresholds before enabling monetisation; require good standing and original-content checks.
5. Test upload, private draft, processing, moderation, publication, playback, likes, comments, follows and role/MFA denial using separate Staging accounts.
6. Reconcile the direct-applied SQL schema into version-controlled migrations before any reset or promotion.

## Safety
- Keep Staging and Production isolated; do not modify Production without explicit approval.
- Never grant broad client table access or expose service-role keys.
- Never publish unprocessed/unmoderated uploads.
- Never trust client-supplied likes/views/eligibility/earnings.
- No real payments or withdrawals in testing.
