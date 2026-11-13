# PLAYAM Flow media worker (Staging)

This worker is intentionally separate from Supabase Edge Functions. It polls the private Staging job queue, scans media with ClamAV, validates the video stream with ffprobe, transcodes H.264/AAC MP4 with FFmpeg, creates a thumbnail, uploads both to the private Staging bucket, then calls the completion RPC. Errors fail closed and never publish the post.

## Safety
- Use only the Staging Supabase URL and Staging service-role secret.
- Put the service-role secret in the private host's secret store or an untracked `.env`; never commit it.
- Keep `.env` private. Do not paste credentials into chat.
- Do not use Production credentials or real user media.
- The worker does not make posts public. Administrator moderation is still required.
- Malware scanner startup fails closed if virus definitions cannot be refreshed or clamd is unavailable.

## Run
1. Provision a private worker host with Docker and enough disk/RAM for temporary media.
2. Copy `.env.example` to `.env` on that host only.
3. Set the Staging service-role key in that host's secret store.
4. From this directory run `docker compose up --build -d`.
5. Inspect worker logs and confirm a test upload progresses from quarantined to ready.
6. Remove test media and rotate the worker credential if it was exposed.

The worker is not running just because this source is in GitHub. It must be deployed on a private host. No hosting provider, secret, or paid service is configured by this repository.

## Limits
Default maximum input is 100 MB and 180 seconds. Tune only after capacity and abuse testing. This first version creates one 1080p-compatible MP4 and one JPEG thumbnail; adaptive bitrate renditions, audio-only handling, and licensed music processing are future work.
