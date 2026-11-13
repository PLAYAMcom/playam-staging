# PLAYAM — Master Product Register
Last updated: 2026-11-13
Scope: Product requirements and delivery tracking for PLAYAM Staging. This is the source-of-truth checklist; it does not claim every item is implemented.

## Non-negotiable delivery rules
- Keep Staging (Supabase project `pwnjrdedeoxbmtfywhkk`, repository `PLAYAMcom/playam-staging`) separate from Production (Supabase project `erjxmesxmmmaxivvmbsi`, production repository).
- Do not modify Production without explicit separate approval.
- Preserve existing working game features; add incrementally, avoid destructive rewrites.
- Never copy real Production user data into Staging.
- No real purchases, creator payouts or withdrawals in testing.
- Mark each item as Built, In progress, Planned or Awaiting test. A deployed function or saved page is not the same as end-to-end tested functionality.

## Games catalogue — retain every title
### Sports and traditional
- Snooker
- Pool
- Football
- Checkers
- Ayo
- Ludo

### Combat and action
- CODs (separate game; gameplay specification to be developed independently)
- Team Deathmatch
- Battle Royale
- Tactical 5v5
- Survival Extraction
- Zombie Survival

### Challenges and social games
- Cotton Ball Challenge
- LIVE Questions and Answers
- Scoreboard
- Friendship Court (core priority)
- Would You Rather
- Truth or Dare
- Mind Battle
- Secret Confessions
- Legend

Do not drop, rename, merge or replace a catalogue title without the user's explicit decision. Build incrementally. Solo vs computer, private multiplayer and LIVE broadcasting are desired modes where suitable. Mobile-first; web/PC support later. No claim that the full catalogue is built: Staging currently has five Starter modes and 100 Starter questions.

## PLAYAM Flow — short-video and creator community
- Users can record/create and upload videos, add captions, publish after moderation, browse a vertical feed, like, comment/reply, follow creators, and view creator profiles.
- Build creator analytics: followers, qualified views, watch time, likes, comments and shares.
- Count views on the server only after anti-fraud qualification; prevent repeat/self/bot/farmed views. Do not trust client-supplied view totals.
- Creator monetisation must require BOTH a configurable minimum follower threshold AND a configurable qualified-view threshold over a defined measurement window, plus good account standing, original-content checks and any required review. Threshold values require an explicit product decision before launch.
- Likes contribute to engagement quality; a like is not itself a cash payment or guaranteed earning.
- Creator cash earnings must use the separate creator-earnings ledger, never free gameplay coins or purchased PLAYAM Coins.
- Uploads private/quarantined until media scanning, transcoding/processing, moderation and publication gates are satisfied.
- Provide reporting, blocking, comment moderation, takedowns, appeals/review, rate limits and audit trail.
- No public publishing until media processing and moderation approval.

### Flow delivery status (2026-11-13)
- Staging private bucket `flow-media-staging`: verified private; 100 MiB maximum; MIME allowlist MP4, QuickTime/MOV, WebM, JPEG, PNG, WebP.
- Storage object policies: authenticated users can insert/select only under their own first-level UID folder.
- Edge Functions deployed with JWT verification: `flow-create-upload`, `flow-save-draft`, `flow-social`, `flow-admin-moderation`.
- `flow-save-draft` creates private draft records; uploaded asset remains quarantined.
- `flow-social` supports approved public feed retrieval, likes/unlikes, comments and follow/unfollow through server-side service access.
- `flow-admin-moderation` requires authenticated session, aal2 MFA and active `super_admin` role; approval is blocked unless asset status is `ready`. No media scanning/transcoding worker currently exists, so approval should remain blocked until that pipeline is built.
- `flow-view-events` records authenticated playback starts and finishes. It uses a server timestamp, excludes creator self-views, and allows one qualified view per signed-in viewer/post/day. The server calculates elapsed wall-clock time and applies a minimum threshold (up to 10 seconds, or 80% of known short-video duration). This is an initial anti-abuse gate, not complete bot/fraud protection; it does not prove continuous attention or actual playback time.
- Staging Flow page: `site/flow.html`; upload screen is wired to upload-ticket and draft functions; feed/social and moderation panels have been added.
- No posts/assets exist yet; no real end-to-end upload, playback, like/comment/follow or moderation test has been performed.
- The nine Flow tables remain RLS-enabled with no direct client policies/grants; keep that deny-by-default stance until narrowly scoped access is justified. All app table access is intended through authenticated server functions.
- Known follow-up: correct stale older Flow status document, reconcile direct SQL schema into version-controlled migration before resets/promotions, implement actual scanner/transcoder, and test every function with two separate Staging accounts and an MFA-protected admin.

## Social, accounts and community
- Profiles, avatars, bios, followers/following, friends, invitations, messaging, blocking and reporting.
- Text/photo feed and PLAYAM Flow short-video feed are distinct but connected experiences.
- Safe discovery, notifications, privacy controls and moderation.

## LIVE and creator ecosystem
- LIVE streaming modes: gameplay only, audio only, optional face camera, or camera plus gameplay overlay.
- LIVE virtual gifts; creator dashboards; creator applications and moderation.
- PLAYAM Earn opportunities for ordinary players and creators without requiring LIVE hosting: sponsored tournaments, verified referral rewards, brand campaigns, creator marketplace, community event hosting, paid testing/moderation tasks.

## Wallets, monetisation and payments
- Keep three balances/ledgers separate: free gameplay coins, purchased PLAYAM Coins, and creator cash earnings.
- Free gameplay coins are not cash-withdrawable.
- Purchased PLAYAM Coins at launch are for LIVE virtual gifts only.
- Creator withdrawals require administrator approval: request/reserve funds, review, secure payout, mark withdrawn only after verified success, restore reservation on confirmed failure. Mandatory admin MFA, two-person approval for large withdrawals, limits/minimums, payout-detail cooling-off, fraud checks, idempotency and audit logs.
- Paystack primary provider; OPay as checkout option through Paystack where enabled; Flutterwave possible future backup; defer crypto.
- Server-side payment verification, signed webhooks and idempotent wallet crediting before purchases are enabled.
- Monetisation streams: careful ads, optional rewarded ads, sponsorships and future premium services. CODs remains free-to-play and no pay-to-win.

## Admin and safety
- Future-ready dashboard areas: Overview, Players, Games, LIVE & Streamers, Gifts & Coins, Earnings & Withdrawals, Reports & Safety, Payments, Security & Admin, Settings.
- Mandatory administrator MFA; least privilege; audited moderation and financial actions.
- Account protection: verified email, strong passwords and compromised-password checks, secure recovery, optional Google/Apple, MFA/passkeys/recovery codes, rate limits and bot/credential-stuffing protection, suspicious-login detection, secure session rotation, device/session management and security notifications.

## Delivery tracking
- Built means source/database/function exists and was verified, not necessarily tested end-to-end.
- Awaiting test means a real Staging test still needs to be run.
- Planned means not implemented.
- Never claim production readiness, full launch, or working multiplayer/media/payments without evidence.
