import hashlib
import os
import socket
import subprocess
import tempfile
import threading
import time
import uuid

import httpx
from pathlib import Path
from datetime import datetime, timezone

import clamd
from supabase import create_client

URL = os.environ["SUPABASE_URL"]
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
BUCKET = "flow-media-staging"
MAX_BYTES = int(os.getenv("MAX_SOURCE_BYTES", str(100 * 1024 * 1024)))
MAX_SECONDS = int(os.getenv("MAX_VIDEO_SECONDS", "180"))
POLL_SECONDS = float(os.getenv("POLL_SECONDS", "4"))
LEASE_HEARTBEAT_SECONDS = int(os.getenv("LEASE_HEARTBEAT_SECONDS", "300"))
WORKER_ID = os.getenv("WORKER_ID", "playam-flow") + "-" + str(uuid.uuid4())
OUTPUT_WORKER_TOKEN = uuid.uuid4().hex
supabase = create_client(URL, SERVICE_KEY)


class PermanentMediaError(Exception):
    """Input is unsafe or invalid and must not be retried."""


class LeaseLostError(Exception):
    """The worker can no longer prove ownership of its processing lease."""


class LeaseHeartbeat:
    def __init__(self, job_id: str, worker_id: str, interval: int = LEASE_HEARTBEAT_SECONDS):
        if interval < 15:
            raise ValueError("lease heartbeat interval must be at least 15 seconds")
        self.job_id = job_id
        self.worker_id = worker_id
        self.interval = interval
        self._stop = threading.Event()
        self._lost = threading.Event()
        self._thread = threading.Thread(target=self._run, name="flow-lease-heartbeat", daemon=True)

    def _renew(self):
        try:
            response = supabase.rpc("flow_renew_media_job_lease_v1", {
                "p_job_id": self.job_id,
                "p_worker_id": self.worker_id,
            }).execute()
        except Exception as exc:
            raise LeaseLostError("worker lease renewal could not be confirmed") from exc
        if not isinstance(response.data, dict) or response.data.get("ok") is not True:
            raise LeaseLostError("worker lease renewal was not confirmed")

    def _run(self):
        while not self._stop.wait(self.interval):
            try:
                self._renew()
            except Exception:
                self._lost.set()
                return

    def check(self):
        if self._lost.is_set():
            raise LeaseLostError("worker lease was lost or could not be renewed")

    def stop(self):
        self._stop.set()
        if self._thread.is_alive() and threading.current_thread() is not self._thread:
            self._thread.join(timeout=3)

    def __enter__(self):
        self._renew()
        self._thread.start()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.stop()
        if self._lost.is_set():
            raise LeaseLostError("worker lease was lost or could not be renewed")
        return False


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(args, timeout=900):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=timeout)



def download_bounded(storage, object_key: str, destination: Path):
    """Stream a private object to disk and stop immediately at the configured cap."""
    signed = storage.create_signed_url(object_key, 300)
    signed_url = signed.get("signedURL") if isinstance(signed, dict) else None
    if not signed_url:
        raise RuntimeError("source_download_url_unavailable")
    from urllib.parse import urljoin
    if signed_url.startswith(("https://", "http://")):
        pass
    elif signed_url.startswith("/storage/v1/"):
        signed_url = urljoin(URL.rstrip("/") + "/", signed_url.lstrip("/"))
    else:
        signed_url = urljoin(URL.rstrip("/") + "/storage/v1/", signed_url.lstrip("/"))
    total = 0
    with httpx.stream("GET", signed_url, follow_redirects=True,
                      timeout=httpx.Timeout(60.0, read=120.0)) as response:
        response.raise_for_status()
        declared = response.headers.get("content-length")
        if declared:
            try:
                if int(declared) > MAX_BYTES:
                    raise PermanentMediaError("source_size_invalid")
            except ValueError as exc:
                if str(exc) == "source_size_invalid":
                    raise
                raise PermanentMediaError("source_size_invalid") from exc
        with destination.open("wb") as target:
            for chunk in response.iter_bytes(chunk_size=1024 * 1024):
                if not chunk:
                    continue
                total += len(chunk)
                if total > MAX_BYTES:
                    raise PermanentMediaError("source_size_invalid")
                target.write(chunk)
    if total < 1024:
        raise PermanentMediaError("source_size_invalid")
    return total


def upload_file(storage, object_key: str, path: Path, content_type: str):
    """Pass a file handle to the storage client rather than materializing it in RAM."""
    with path.open("rb") as handle:
        storage.upload(object_key, handle, {
            "content-type": content_type,
            "upsert": "true",
        })


def cleanup_processed_objects(storage, object_keys):
    """Best-effort cleanup for this worker's uniquely namespaced partial uploads."""
    keys = [key for key in object_keys if key]
    if not keys:
        return
    try:
        storage.remove(keys)
    except Exception as exc:
        # Preserve the original processing/upload error; orphan cleanup can be retried.
        print("processed object cleanup failed", len(keys), type(exc).__name__, flush=True)

def inspect_video(path: Path):
    if not path.is_file() or path.stat().st_size < 1024 or path.stat().st_size > MAX_BYTES:
        raise PermanentMediaError("source_size_invalid")
    result = run(["ffprobe", "-v", "error", "-show_entries",
                  "format=duration,format_name:stream=codec_type,codec_name,width,height",
                  "-of", "json", str(path)], timeout=30)
    import json
    meta = json.loads(result.stdout)
    streams = meta.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), None)
    if not video:
        raise PermanentMediaError("video_stream_missing")
    duration = float(meta.get("format", {}).get("duration", 0))
    if duration <= 0 or duration > MAX_SECONDS:
        raise PermanentMediaError("video_duration_invalid")
    if int(video.get("width", 0)) < 160 or int(video.get("height", 0)) < 160:
        raise PermanentMediaError("video_dimensions_invalid")
    return duration


def scan(path: Path):
    host = os.getenv("CLAMD_HOST", "127.0.0.1")
    port = int(os.getenv("CLAMD_PORT", "3310"))
    scanner = clamd.ClamdNetworkSocket(host=host, port=port, timeout=120)
    scanner.ping()
    with path.open("rb") as media:
        result = scanner.instream(media)
    if not result or result.get("stream", (None, "ERROR"))[0] not in ("OK", "FOUND"):
        raise RuntimeError("scanner_unavailable")
    status, signature = result["stream"]
    if status == "FOUND":
        raise PermanentMediaError("malware_detected")
    if status != "OK":
        raise RuntimeError("scanner_error")


def update_job(job_id, **values):
    values["updated_at"] = "now()"
    # Use RPC-backed stages only for status transitions; metadata is internal worker state.
    supabase.table("flow_media_processing_jobs").update(values).eq("id", job_id).eq("locked_by", WORKER_ID).execute()


def process(job):
    job_id, asset_id = job["job_id"], job["asset_id"]
    source_bucket, source_key = job["source_bucket"], job["source_object_key"]
    # Never allow a queued job to make the service worker read outside the
    # dedicated private Staging bucket or another creator's storage prefix.
    if source_bucket != BUCKET or not isinstance(source_key, str):
        raise PermanentMediaError("source_location_invalid")
    if not source_key.startswith(job["creator_auth_user_id"] + "/") or ".." in source_key.split("/"):
        raise PermanentMediaError("source_location_invalid")

    with LeaseHeartbeat(job_id, WORKER_ID) as lease:
        with tempfile.TemporaryDirectory(prefix="playam-flow-") as temp:
            root = Path(temp)
            source = root / "source.media"
            output = root / "playback.mp4"
            thumb = root / "thumbnail.jpg"
            storage = supabase.storage.from_(source_bucket)
            download_bounded(storage, source_key, source)
            lease.check()
            source_hash = sha256(source)
            scan(source)
            lease.check()
            duration = inspect_video(source)
            lease.check()
            supabase.table("flow_media_processing_jobs").update({
                "status": "transcoding",
                "updated_at": datetime.now(timezone.utc).isoformat()
            }).eq("id", job_id).eq("locked_by", WORKER_ID).execute()
            supabase.table("flow_post_assets").update({
                "processing_status": "processing"
            }).eq("id", asset_id).execute()
            run(["ffmpeg", "-nostdin", "-y", "-i", str(source), "-t", str(MAX_SECONDS),
                 "-map", "0:v:0", "-map", "0:a:0?", "-vf", "scale='min(1080,iw)':-2",
                 "-c:v", "libx264", "-preset", "veryfast", "-crf", "25",
                 "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
                 "-movflags", "+faststart", str(output)], timeout=1200)
            lease.check()
            if not output.exists() or output.stat().st_size < 1024:
                raise RuntimeError("transcode_output_invalid")
            supabase.table("flow_media_processing_jobs").update({
                "status": "thumbnailing",
                "updated_at": datetime.now(timezone.utc).isoformat()
            }).eq("id", job_id).eq("locked_by", WORKER_ID).execute()
            run(["ffmpeg", "-nostdin", "-y", "-ss", str(min(1.0, duration / 4)),
                 "-i", str(output), "-frames:v", "1", "-vf", "scale='min(640,iw)':-2",
                 "-q:v", "4", str(thumb)], timeout=60)
            lease.check()
            if not thumb.exists() or thumb.stat().st_size < 512:
                raise RuntimeError("thumbnail_output_invalid")
            # Each attempt has an isolated prefix so cleanup cannot delete another worker's output.
            prefix = f"processed/{job['creator_auth_user_id']}/{asset_id}/{job_id}/{OUTPUT_WORKER_TOKEN}"
            video_key, thumb_key = f"{prefix}/playback.mp4", f"{prefix}/thumbnail.jpg"
            storage = supabase.storage.from_(BUCKET)
            upload_processed_pair(storage, video_key, thumb_key, output, thumb)
            lease.check()
            output_hash = sha256(output)
            # Stop heartbeats before terminal RPC; it checks the last lease expiry.
            lease.check()
            lease.stop()
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
            except LeaseLostError as exc:
                # Do not call the failure RPC: another worker may now own this job.
                print("worker lease lost; leaving job for safe recovery", claimed["job_id"], type(exc).__name__, flush=True)
            except PermanentMediaError as exc:
                code = str(exc)[:80]
                rejected = True
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
