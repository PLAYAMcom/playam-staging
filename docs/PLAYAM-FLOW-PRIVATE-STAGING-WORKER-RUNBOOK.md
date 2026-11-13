# PLAYAM Flow private Staging worker deployment runbook

Status: preparation only. This document does not mean a worker host is provisioned or a deployment has occurred.

## Preconditions

- Confirm the target is the PLAYAM Staging Supabase project; never use Production credentials.
- Provision a private Linux host with Docker Engine and the Compose plugin.
- Restrict host access to authorised operators; enable host patching, disk monitoring and log retention.
- Confirm the Staging database migrations and Edge Functions required by the worker are applied and healthy.
- Confirm the private `flow-media-staging` bucket exists and remains non-public.
- Use a dedicated Staging service-role key stored only in the host secret manager. Never put it in Git, CI logs, tickets or chat.
- Confirm a synthetic test fixture is used; do not process real user media during initial validation.

## Configure and start

1. Check out the reviewed worker commit on the private host.
2. Populate the environment variables from `worker/.env.example` in the host's secret store or a host-only `.env` file with permissions restricted to the service account.
3. Verify `SUPABASE_URL` points to the Staging project and `WORKER_ID` is unique for this instance.
4. From `worker/`, run `docker compose config` and inspect the resolved configuration without printing secret values.
5. Build and start with `docker compose up --build -d`.
6. Check `docker compose ps` and review `docker compose logs --tail=200 flow-media-worker`. Do not share logs if they contain credentials or signed URLs.

## Acceptance test

Use one short, generated synthetic video and a dedicated Staging test account.

- Upload creates a private draft and quarantined asset.
- Worker claims the queued job and renews its lease while processing.
- Malware scanner is healthy; scanner outage fails closed.
- File validation and FFmpeg complete within configured resource/time limits.
- Processed MP4 and JPEG thumbnail upload to the private bucket.
- Database asset state becomes ready only after verified uploads and worker completion.
- Admin moderation requires an authenticated super-admin with MFA (AAL2).
- Rejected content never appears in the public feed.
- Approved synthetic content appears in the feed and plays for a separate test viewer.
- Like, follow, comment and playback event actions are checked with separate test accounts.
- Expired lease recovery and competing-worker behavior are exercised in database integration tests.

Record timestamps, commit SHA, job ID, sanitized logs and observed state transitions. Do not record access tokens, service-role keys or signed media URLs.

## Rollback and cleanup

- Stop the worker with `docker compose down` if it repeatedly fails, leaks resources or behaves unexpectedly.
- Preserve sanitized logs and the failing job identifier for diagnosis.
- Remove synthetic test posts and media using the approved Staging cleanup procedure.
- Revoke/rotate the Staging worker key if exposure is suspected.
- Do not change Production as part of this runbook.

## Release gate

A successful image build or a running container alone is not acceptance. The worker milestone remains unverified until every acceptance-test item above has evidence from the private Staging runtime and the end-to-end feed playback test succeeds.
