import json
import os
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test-only-placeholder-key")

import worker


class FakeResponse:
    def __init__(self, chunks=(), headers=None):
        self._chunks = chunks
        self.headers = headers or {}

    def raise_for_status(self):
        return None

    def iter_bytes(self, chunk_size):
        yield from self._chunks


class WorkerSafetyTests(unittest.TestCase):
    def test_download_streams_under_limit(self):
        response = FakeResponse([b"x" * 700, b"y" * 500], {"content-length": "1200"})
        requested_methods = []
        requested_urls = []

        @contextmanager
        def stream(method, url, *args, **kwargs):
            requested_methods.append(method)
            requested_urls.append(url)
            yield response

        storage = Mock()
        storage.create_signed_url.return_value = {"signedURL": "/object/sign/private/source?token=test"}
        with tempfile.TemporaryDirectory() as tmp, patch.object(worker.httpx, "stream", stream):
            target = Path(tmp) / "source.bin"
            size = worker.download_bounded(storage, "creator/source", target)
            self.assertEqual(size, 1200)
            self.assertEqual(target.stat().st_size, 1200)
        self.assertEqual(requested_methods, ["GET"])
        self.assertEqual(requested_urls[0], "https://example.supabase.co/storage/v1/object/sign/private/source?token=test")

    def test_download_rejects_declared_oversize_before_stream(self):
        response = FakeResponse([], {"content-length": str(worker.MAX_BYTES + 1)})

        @contextmanager
        def stream(*args, **kwargs):
            yield response

        storage = Mock()
        storage.create_signed_url.return_value = {"signedURL": "https://storage.invalid/signed"}
        with tempfile.TemporaryDirectory() as tmp, patch.object(worker.httpx, "stream", stream):
            with self.assertRaises(worker.PermanentMediaError):
                worker.download_bounded(storage, "creator/source", Path(tmp) / "source.bin")

    def test_download_stops_when_chunked_body_exceeds_limit(self):
        response = FakeResponse([b"x" * worker.MAX_BYTES, b"y"], {})

        @contextmanager
        def stream(*args, **kwargs):
            yield response

        storage = Mock()
        storage.create_signed_url.return_value = {"signedURL": "https://storage.invalid/signed"}
        with tempfile.TemporaryDirectory() as tmp, patch.object(worker.httpx, "stream", stream):
            with self.assertRaises(worker.PermanentMediaError):
                worker.download_bounded(storage, "creator/source", Path(tmp) / "source.bin")

    def test_upload_passes_file_handle_not_bytes(self):
        storage = Mock()
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "playback.mp4"
            source.write_bytes(b"video")
            worker.upload_file(storage, "processed/asset/playback.mp4", source, "video/mp4")
        args, kwargs = storage.upload.call_args
        self.assertTrue(hasattr(args[1], "read"))
        self.assertEqual(kwargs, {})
        self.assertEqual(args[2]["content-type"], "video/mp4")

    def test_malformed_video_is_permanent(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "bad.mp4"
            source.write_bytes(b"x" * 2048)
            with patch.object(worker, "run", return_value=SimpleNamespace(stdout=json.dumps({"streams": []}))):
                with self.assertRaises(worker.PermanentMediaError):
                    worker.inspect_video(source)

    def test_video_over_size_is_permanent(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "oversize.mp4"
            source.write_bytes(b"x" * 2048)
            with patch.object(worker, "MAX_BYTES", 1024):
                with self.assertRaises(worker.PermanentMediaError):
                    worker.inspect_video(source)

    def test_malware_signature_is_permanent_rejection(self):
        scanner = Mock()
        scanner.ping.return_value = True
        scanner.instream.return_value = {"stream": ("FOUND", "Eicar-Test-Signature")}
        with patch.object(worker.clamd, "ClamdNetworkSocket", return_value=scanner):
            with tempfile.TemporaryDirectory() as tmp:
                source = Path(tmp) / "sample.mp4"
                source.write_bytes(b"x" * 2048)
                with self.assertRaises(worker.PermanentMediaError):
                    worker.scan(source)

    def test_scanner_unavailable_is_transient(self):
        scanner = Mock()
        scanner.ping.side_effect = OSError("clamd unavailable")
        with patch.object(worker.clamd, "ClamdNetworkSocket", return_value=scanner):
            with tempfile.TemporaryDirectory() as tmp:
                source = Path(tmp) / "sample.mp4"
                source.write_bytes(b"x" * 2048)
                with self.assertRaises(OSError):
                    worker.scan(source)


    def test_lease_heartbeat_renews_only_when_database_confirms(self):
        response = SimpleNamespace(data={"ok": True, "locked_at": "2026-11-13T18:00:00Z"})
        client = Mock()
        client.rpc.return_value.execute.return_value = response
        with patch.object(worker, "supabase", client):
            heartbeat = worker.LeaseHeartbeat("job-id", "worker-id-123", interval=30)
            heartbeat._renew()
        client.rpc.assert_called_once_with("flow_renew_media_job_lease_v1", {
            "p_job_id": "job-id", "p_worker_id": "worker-id-123"
        })

    def test_lease_heartbeat_fails_closed_when_renewal_is_not_confirmed(self):
        response = SimpleNamespace(data={"ok": False})
        client = Mock()
        client.rpc.return_value.execute.return_value = response
        with patch.object(worker, "supabase", client):
            heartbeat = worker.LeaseHeartbeat("job-id", "worker-id-123", interval=30)
            with self.assertRaises(worker.LeaseLostError):
                heartbeat._renew()

    def test_lease_heartbeat_rejects_nonpositive_interval(self):
        with self.assertRaises(ValueError):
            worker.LeaseHeartbeat("job-id", "worker-id-123", interval=0)

    def test_lease_heartbeat_fails_closed_on_rpc_exception(self):
        client = Mock()
        client.rpc.return_value.execute.side_effect = TimeoutError("database timeout")
        with patch.object(worker, "supabase", client):
            heartbeat = worker.LeaseHeartbeat("job-id", "worker-id-123", interval=30)
            with self.assertRaises(worker.LeaseLostError):
                heartbeat._renew()

    def test_partial_second_upload_failure_removes_first_attempt_object(self):
        storage = Mock()
        storage.upload.side_effect = [None, RuntimeError("thumbnail upload failed")]
        with tempfile.TemporaryDirectory() as tmp:
            video = Path(tmp) / "video.mp4"
            thumb = Path(tmp) / "thumbnail.jpg"
            video.write_bytes(b"video")
            thumb.write_bytes(b"thumbnail")
            with self.assertRaisesRegex(RuntimeError, "thumbnail upload failed"):
                worker.upload_processed_pair(storage, "processed/u/a/job/worker/playback.mp4",
                                             "processed/u/a/job/worker/thumbnail.jpg", video, thumb)
        storage.remove.assert_called_once_with(["processed/u/a/job/worker/playback.mp4"])

    def test_cleanup_failure_does_not_mask_original_upload_error(self):
        storage = Mock()
        storage.upload.side_effect = [None, RuntimeError("upload failed")]
        storage.remove.side_effect = OSError("storage cleanup unavailable")
        with tempfile.TemporaryDirectory() as tmp:
            video = Path(tmp) / "video.mp4"
            thumb = Path(tmp) / "thumbnail.jpg"
            video.write_bytes(b"video")
            thumb.write_bytes(b"thumbnail")
            with patch.object(worker.time, "sleep"):
                with self.assertRaisesRegex(RuntimeError, "upload failed"):
                    worker.upload_processed_pair(storage, "processed/u/a/job/worker/playback.mp4",
                                                 "processed/u/a/job/worker/thumbnail.jpg", video, thumb)
        self.assertEqual(storage.remove.call_count, 3)

    def test_cleanup_ignores_empty_object_list(self):
        storage = Mock()
        worker.cleanup_processed_objects(storage, [])
        storage.remove.assert_not_called()

if __name__ == "__main__":
    unittest.main()
