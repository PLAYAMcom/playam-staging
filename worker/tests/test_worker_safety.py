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
        requested_urls = []
        @contextmanager
        def stream(url, *args, **kwargs):
            requested_urls.append(url)
            yield response
        storage = Mock()
        storage.create_signed_url.return_value = {"signedURL": "/object/sign/private/source?token=test"}
        with tempfile.TemporaryDirectory() as tmp, patch.object(worker.httpx, "stream", stream):
            target = Path(tmp) / "source.bin"
            size = worker.download_bounded(storage, "creator/source", target)
            self.assertEqual(size, 1200)
            self.assertEqual(target.stat().st_size, 1200)
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


if __name__ == "__main__":
    unittest.main()
