# PLAYAM Flow media worker (Staging)

This is a separate, containerized worker. It is not part of the public browser app.

## What it does
- Claims one queued job using the atomic Staging RPC.
- Downloads only from the private `flow-media-staging` bucket.
- Enforces a 100 MB default input cap.
- Runs ClamAV; scanner errors fail closed.
- Uses ffprobe to validate video stream, duration (default 180 seconds), and dimensions.
- Transcodes to H.264/AAC MP4 and generates a JPEG thumbnail using FFmpeg.
- Stores outputs in the same private bucket under `processed/`.
- Calls the service-only completion RPC, which is the only route to mark an asset ready.
- Retries transient failures through the job queue; permanent validation/scanner rejection is not retried.

## Important limitations
- This is a first Staging worker, not a complete production media security programme.
- ClamAV signatures must be kept current. The image intentionally does not auto-run with stale definitions: deploy/run a signature-update step and monitor freshness before enabling the worker.
- The worker assumes the Staging bucket is private and the database service-only RPCs from the matching migrations are installed.
- It does not publish posts or grant creator earnings. Admin approval remains a separate gate.
- Storage lifecycle cleanup, abuse quotas across multiple worker replicas, privacy-safe retention, and operational alerting still need configuration.
- Never use this worker with Production credentials or real player media.

## Build and run locally
1. Copy `.env.example` to `.env` and fill values from the Staging project only. Never commit `.env`.
2. Build: `docker build -t playam-flow-worker .`
3. Start with a persistent work directory and environment variables. Provide `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and a unique `FLOW_WORKER_ID`.
4. Before processing jobs, update ClamAV signatures in the image/container and confirm `freshclam` succeeds. Then run the worker.
5. Keep logs private; do not log signed URLs, tokens, file contents, or secrets.

## Resource defaults
- Input cap: 100 MiB
- Maximum duration: 180 seconds
- Maximum dimensions: 3840x2160
- Output width: at most 1920 pixels
- Worker polls every 5 seconds

## Safety
The service-role key is a server secret. Put it only in the worker host's secret manager. Never add it to GitHub source, browser code, or issue comments. Use a dedicated Staging project.