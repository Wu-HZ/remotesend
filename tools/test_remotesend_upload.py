import importlib.util
import json
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("remotesend_upload", Path(__file__).with_name("remotesend_upload.py"))
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


class Handler(BaseHTTPRequestHandler):
    requests = []
    fail = False

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.requests.append((self.path, self.headers.get("Authorization"), payload))
        self.reply(202, {"id": "upload_1", "remotePath": "/RemoteSend/Files/artifact-uuid.zip", "status": "pending"})

    def do_GET(self):
        self.reply(200, {"id": "upload_1", "status": "failed" if self.fail else "completed",
                         "remotePath": "/RemoteSend/Files/artifact-uuid.zip", "error": "offline" if self.fail else None})

    def reply(self, status, body):
        encoded = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, *_):
        pass


class UploadTest(unittest.TestCase):
    def setUp(self):
        self.http = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.worker = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.worker.start()
        self.address = f"http://127.0.0.1:{self.http.server_port}"
        Handler.requests = []
        Handler.fail = False
        self.temp = tempfile.TemporaryDirectory()
        self.file = Path(self.temp.name, "artifact.zip")
        self.file.write_bytes(b"build")
        self.url_patch = patch.object(client, "BASE_URL", self.address)
        self.url_patch.start()

    def tearDown(self):
        self.url_patch.stop()
        self.http.shutdown()
        self.http.server_close()
        self.worker.join()
        self.temp.cleanup()

    def test_waits_for_actual_completion(self):
        result = client.upload(self.file, "secret", interval=0)
        self.assertEqual(result["status"], "completed")
        self.assertEqual(Handler.requests[0][1], "Bearer secret")
        self.assertEqual(Handler.requests[0][2], {"path": str(self.file.resolve()), "overwrite": False})

    def test_just_queued_does_not_claim_success(self):
        result = client.upload(self.file, "secret", wait=False, overwrite=True)
        self.assertEqual(result["status"], "pending")
        self.assertEqual(Handler.requests[0][2]["overwrite"], True)

    def test_failure_and_missing_token_return_errors(self):
        Handler.fail = True
        with self.assertRaisesRegex(client.UploadError, "offline"):
            client.upload(self.file, "secret", interval=0)
        with self.assertRaisesRegex(client.UploadError, "REMOTESEND_API_TOKEN"):
            client.upload(self.file, "")

    def test_missing_file_is_not_sent(self):
        with self.assertRaisesRegex(client.UploadError, "File does not exist"):
            client.upload(self.file.parent / "missing", "secret")
        self.assertFalse(Handler.requests)


if __name__ == "__main__":
    unittest.main()
