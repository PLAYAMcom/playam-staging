# PLAYAM Flow — implementation blueprint (Staging)

**Status:** Flow schema foundation created in Staging (nine RLS-protected tables, deny-by-default); media storage, app APIs, feed UI and monetisation engine are not implemented yet.
**Environment:** Staging repository only. Do not apply this plan to Production without explicit approval.

## Product promise

PLAYAM Flow is one connected, mobile-first vertical video feed. People can create or upload videos, publish posts, discover creators, follow people, and interact with videos. Flow connects to games, LIVE sessions, challenges, profiles and messaging.

## Creator journey

1. A person creates an account and publishes original videos.
2. They build a real audience and receive genuine views, likes, comments and followers.
3. A creator dashboard shows progress toward monetisation eligibility.
4. Cash monetisation remains locked until the creator meets the published follower AND qualified-view thresholds and passes account, content and policy checks.
5. Eligible creators can earn from funded advertising and sponsorship programmes, subject to transparent programme rules and available revenue.
6. Creator cash uses the existing separate creator-earnings ledger and administrator-approved withdrawal lifecycle. Never credit free gameplay coins or purchased PLAYAM Coins for Flow engagement.

## Monetisation rules to preserve

- Both a minimum follower count and a minimum qualified-view total are required. Meeting only one is not enough.
- Likes matter: record them and use genuine engagement as a quality/performance signal. Likes alone do not create a guaranteed cash entitlement or a fixed cash-per-like promise.
- Count qualified views using server-side rules, deduplication and reasonable watch-time/engagement signals. Exclude bots, artificial repeat plays, purchased traffic and suspected view farms.
- Display the eligibility thresholds, measurement window, review status and reason for any rejection or pause.
- Monetisation requires policy-compliant original content and good account standing. Provide a review/appeal route for enforcement decisions.
- Pay creators only from actually funded ad/sponsorship programmes, with clear calculation records. Avoid promising earnings from estimated ad revenue.
- Exact follower threshold, qualified-view threshold, measurement window, minimum age/region rules, revenue share and payout schedule are launch decisions and must be agreed and published before monetisation is enabled. Do not hard-code guessed values.

## Proposed Staging data model (design only; do not run SQL yet)

Use a separate Flow domain. Do not extend the existing five-value `rooms.game` or `questions.game_key` checks to represent videos.

- `flow_posts`: creator, caption, visibility, moderation state, publication timestamps, asset reference and safe status fields.
- `flow_post_assets`: storage object key, media type, duration, dimensions, processing state, thumbnail and transcoding metadata. Keep uploaded media in private/quarantined storage until checks pass.
- `flow_post_likes`: one unique like per authenticated user and post; support safe unlike/re-like history if needed.
- `flow_post_comments`: post, author, text, timestamps, moderation state and parent comment for replies.
- `flow_follows`: follower/followed user pair, unique constraint, no self-follow; integrate block rules.
- `flow_view_events`: server-validated, privacy-conscious view events with deduplication keys, qualified status and fraud signals. Avoid storing unnecessary device fingerprints.
- `flow_creator_metrics_daily`: aggregated follower, qualified-view, watch-time, like, comment and share counts by creator/day; derived from validated events, not client-submitted counters.
- `flow_monetization_eligibility`: creator, policy version, thresholds snapshot, measurement window, computed metrics, eligibility state, reviewer and audit timestamps.
- `flow_content_moderation`: report/review state, reason codes, reviewer actions and audit trail. Reuse existing safety workflows where the data model safely supports it; do not bypass report controls.

Do not create a second creator cash wallet. After a funded programme is approved and earnings are verified, credit the existing `playam_creator_earnings_wallets` / transaction ledger through a server-only, idempotent function. Preserve the existing withdrawal approval and audit safeguards.

## Security and abuse controls

- RLS on every user-facing table; deny direct public writes to counters, eligibility, moderation outcomes and earnings.
- All critical writes and metric aggregation are server-authoritative. Never trust a client-supplied view count, follower count, eligibility flag or earnings amount.
- Unique constraints and idempotency for likes, follows, view qualification, campaign rewards and earnings events.
- Check blocks, privacy settings, age/region restrictions and content visibility on every feed/read path.
- Rate-limit upload, comments, likes, follows and view events. Detect coordinated fake engagement and repeated automated traffic.
- Validate media type, file size, duration and content; scan/moderate before broad distribution. Use signed upload/download URLs and safe transcoding.
- Report, block, mute and appeal flows; copyright/takedown process; creator strikes and human review for serious cases.
- Keep admin access behind mandatory MFA, least privilege and immutable audit events. Two-person approval remains required for large cash withdrawals.
- Separate Staging and Production buckets, keys, URLs and data. Never copy real user media or personal data into Staging.

## Suggested build order

1. Finalise product rules and threshold values before monetisation is enabled.
2. Design and review schema, indexes, storage buckets, RLS policies, grants and server functions.
3. Build upload pipeline and safe media processing.
4. Build post publishing, profile, follow, like, comment, report and block flows.
5. Build feed ranking and pagination using privacy-safe, server-side signals.
6. Build validated view/engagement aggregation and creator analytics.
7. Build eligibility calculation and admin review; keep payouts disabled until verified.
8. Connect approved funded campaigns to the existing creator earnings ledger using idempotent server-side transactions.
9. Test with synthetic Staging accounts and media, including abuse/security cases; no real payouts.

## Acceptance tests before launch

- A creator cannot self-award followers, views, likes, eligibility or earnings by calling the client/API directly.
- A duplicate like/follow/view event cannot inflate metrics.
- Blocked users and private posts obey access rules in every endpoint.
- Unreviewed or rejected media is not publicly served.
- Eligibility requires both follower and qualified-view thresholds and current policy compliance.
- Likes affect engagement reporting but do not automatically create cash credits.
- A funded earning is credited once only, with a complete audit trail and no wallet mixing.
- Admin moderation and payout controls enforce MFA, authorisation and audit logging.
- Mobile upload, playback, accessibility, low-bandwidth handling and moderation are tested.
- Staging tests do not touch Production or issue real payments.

## Decisions still required

Before monetisation launch, approve:
- Minimum followers.
- Minimum qualified views and measurement period.
- Minimum creator age and supported regions.
- Revenue-pool funding source and creator/platform split.
- Minimum payout and payout cadence.
- Content categories/brand-safety rules and appeal process.

Until those decisions and security tests are complete, Flow can be developed and tested without enabling cash monetisation.
