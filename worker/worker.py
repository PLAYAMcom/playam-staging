import hashlib
import os
import socket
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

import clamd
from supabase import create_client

URL = os.environ["SUPABASE_URL"]
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
BUCKET = "flow-media-staging"
MAX_BYTES = int(os.getenv("MAX_SOURCE_BYTES", str(100 * 1024 * 1024)))
MAX_SECONDS = int(os.getenv("MAX_VIDEO_SECONDS", "180"))
POLL_SECONDS = float(os.getenv("POLL_SECONDS", "4"))
WORKER_ID = os.getenv("WORKER_ID", "playam-flow-" + str(uuid.uuid4()))
supabase = create_client(URL, SERVICE_KEY)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(args, timeout=900):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=timeout)


def inspect_video(path: Path):
    if not path.is_file() or path.stat().st_size < 1024 or path.stat().st_size > MAX_BYTES:
        raise ValueError("source_size_invalid")
    result = run(["ffprobe", "-v", "error", "-show_entries",
                  "format=duration,format_name:stream=codec_type,codec_name,width,height",
                  "-of", "json", str(path)], timeout=30)
    import json
    meta = json.loads(result.stdout)
    streams = meta.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), None)
    if not video:
        raise ValueError("video_stream_missing")
    duration = float(meta.get("format", {}).get("duration", 0))
    if duration <= 0 or duration > MAX_SECONDS:
        raise ValueError("video_duration_invalid")
    if int(video.get("width", 0)) < 160 or int(video.get("height", 0)) < 160:
        raise ValueError("video_dimensions_invalid")
    return duration


def scan(path: Path):
    host = os.getenv("CLAMD_HOST", "127.0.0.1")
    port = int(os.getenv("CLAMD_PORT", "3310"))
    scanner = clamd.ClamdNetworkSocket(host=host, port=port, timeout=120)
    scanner.ping()
    with path.open("rb") as media:
        result = scanner.instream(media)
    if not result or result.get("stream", (None, "ERROR"))[0] != "stream":
        raise RuntimeError("scanner_unavailable")
    status, signature = result["stream"]
    if status == "FOUND":
        raise ValueError("malware_detected")
    if status != "OK":
        raise RuntimeError("scanner_error")


def update_job(job_id, **values):
    values["updated_at"] = "now()"
    # Use RPC-backed stages only for status transitions; metadata is internal worker state.
    supabase.table("flow_media_processing_jobs").update(values).eq("id", job_id).eq("locked_by", WORKER_ID).execute()


def process(job):
    job_id, asset_id = job["job_id"], job["asset_id"]
    source_bucket, source_key = job["source_bucket"], job["source_object_key"]
    with tempfile.TemporaryDirectory(prefix="playam-flow-") as temp:
        root = Path(temp)
        source = root / "source.media"
        output = root / "playback.mp4"
        thumb = root / "thumbnail.jpg"
        data = supabase.storage.from_(source_bucket).download(source_key)
        source.write_bytes(data)
        source_hash = sha256(source)
        scan(source)
        duration = inspect_video(source)
        supabase.table("flow_media_processing_jobs").update({"status": "transcoding", "updated_at": "now()"}).eq("id", job_id).eq("locked_by", WORKER_ID).execute()
        supabase.table("flow_post_assets").update({"processing_status": "processing"}).eq("id", asset_id).execute()
        run(["ffmpeg", "-nostdin", "-y", "-i", str(source), "-t", str(MAX_SECONDS),
             "-map", "0:v:0", "-map", "0:a:0?", "-vf", "scale='min(1080,iw)':-2",
             "-c:v", "libx264", "-preset", "veryfast", "-crf", "25",
             "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
             "-movflags", "+faststart", str(output)], timeout=1200)
        if not output.exists() or output.stat().st_size < 1024:
            raise RuntimeError("transcode_output_invalid")
        supabase.table("flow_media_processing_jobs").update({"status": "thumbnailing", "updated_at": "now()"}).eq("id", job_id).eq("locked_by", WORKER_ID).execute()
        run(["ffmpeg", "-nostdin", "-y", "-ss", str(min(1.0, duration / 4)),
             "-i", str(output), "-frames:v", "1", "-vf", "scale='min(640,iw)':-2",
             "-q:v", "4", str(thumb)], timeout=60)
        if not thumb.exists() or thumb.stat().st_size < 512:
            raise RuntimeError("thumbnail_output_invalid")
        prefix = f"processed/{job['creator_auth_user_id']}/{asset_id}"
        video_key, thumb_key = f"{prefix}/playback.mp4", f"{prefix}/thumbnail.jpg"
        storage = supabase.storage.from_(BUCKET)
        storage.upload(video_key, output.read_bytes(), {"content-type": "video/mp4", "upsert": "true"})
        storage.upload(thumb_key, thumb.read_bytes(), {"content-type": "image/jpeg", "upsert": "true"})
        output_hash = sha256(output)
        result = supabase.rpc("flow_complete_media_job_v1", {
            "p_job_id": job_id, "p_worker_id": WORKER_ID,
            "p_output_bucket": BUCKET, "p_output_object_key": video_key,
            "p_thumbnail_object_key": thumb_key,
            "p_source_sha256": source_hash, "p_output_sha256": output_hash
        }).execute()
        if not result.data:
            raise RuntimeError("completion_not_confirmed")


def main():
    print("PLAYAM Flow media worker started; worker id:", WORKER_ID, flush=True)
    while True:
        try:
            claimed = supabase.rpc("flow_claim_media_job_v1", {"p_worker_id": WORKER_ID}).execute().data
            if not claimed:
                time.sleep(POLL_SECONDS)
                continue
            try:
                process(claimed)
                print("completed media job", claimed["job_id"], flush=True)
            except ValueError as exc:
                code = str(exc)[:80]
                rejected = code == "malware_detected"
                supabase.rpc("flow_fail_media_job_v1", {
                    "p_job_id": claimed["job_id"], "p_worker_id": WORKER_ID,
                    "p_error_code": code,
                    "p_safe_message": "Video failed security or media validation.",
                    "p_rejected": rejected
                }).execute()
                print("media rejected/failed", claimed["job_id"], code, flush=True)
            except Exception as exc:
                supabase.rpc("flow_fail_media_job_v1", {
                    "p_job_id": claimed["job_id"], "p_worker_id": WORKER_ID,
                    "p_error_code": "worker_processing_error",
                    "p_safe_message": "Video processing could not be completed.",
                    "p_rejected": False
                }).execute()
                print("media processing failed", claimed["job_id"], type(exc).__name__, flush=True)
        except Exception as exc:
            print("worker loop error", type(exc).__name__, flush=True)
            time.sleep(max(POLL_SECONDS, 10))


if __name__ == "__main__":
    main()
