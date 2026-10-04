"""Offline checks for the project-local WebDAV MCP server."""

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import webdav_mcp_server as server


class WebdavMcpTest(unittest.TestCase):
    def test_requires_credentials(self):
        with patch.dict(os.environ, {"WEBDAV_URL": "REPLACE_ME", "WEBDAV_USERNAME": "", "WEBDAV_PASSWORD": ""}):
            with self.assertRaisesRegex(ValueError, "Configure WEBDAV_URL"):
                server._client()

    def test_allows_explicit_http_server(self):
        with patch.dict(os.environ, {"WEBDAV_URL": "http://files.example.test/dav", "WEBDAV_USERNAME": "user", "WEBDAV_PASSWORD": "test"}):
            with patch.object(server, "Client") as client:
                server._client()
                client.assert_called_once_with("http://files.example.test/dav", auth=("user", "test"), timeout=60, trust_env=False)

    def test_rejects_non_http_url(self):
        with patch.dict(os.environ, {"WEBDAV_URL": "file:///private/data", "WEBDAV_USERNAME": "user", "WEBDAV_PASSWORD": "test"}):
            with self.assertRaisesRegex(ValueError, "HTTP\\(S\\)"):
                server._client()

    def test_authentication_is_passed_via_env_not_cli(self):
        with patch.dict(os.environ, {"WEBDAV_URL": "http://127.0.0.1:5244/dav", "WEBDAV_USERNAME": "user", "WEBDAV_PASSWORD": "test"}):
            with patch.object(server, "Client") as client:
                server._client()
                client.assert_called_once_with("http://127.0.0.1:5244/dav", auth=("user", "test"), timeout=60, trust_env=False)

    def test_upload_passes_overwrite_flag(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "app-release.apk"
            source.write_bytes(b"fake apk")
            with patch.object(server, "_client") as client:
                result = server.webdav_upload(str(source), "/RemoteSend/Files/RemoteSend-Android.apk", overwrite=True)
                client.return_value.upload_file.assert_called_once_with(source, "/RemoteSend/Files/RemoteSend-Android.apk", overwrite=True)
                self.assertIn("RemoteSend-Android.apk", result)

    def test_upload_rejects_missing_file_and_parent_traversal(self):
        with patch.object(server, "_client") as client:
            with self.assertRaises(ValueError):
                server.webdav_upload("nonexistent.apk", "/RemoteSend/Files/RemoteSend-Android.apk")
            with tempfile.TemporaryDirectory() as folder:
                source = Path(folder) / "app-release.apk"
                source.write_bytes(b"fake apk")
                with self.assertRaises(ValueError):
                    server.webdav_upload(str(source), "/RemoteSend/../secret", overwrite=True)
            client.assert_not_called()

    def test_delete_requires_explicit_confirmation(self):
        with patch.object(server, "_client") as client:
            with self.assertRaises(ValueError):
                server.webdav_delete("/RemoteSend/Files/file.apk")
            with self.assertRaises(ValueError):
                server.webdav_delete("/", confirm=True)
            client.assert_not_called()
            server.webdav_delete("/RemoteSend/Files/file.apk", confirm=True)
            client.return_value.remove.assert_called_once_with("/RemoteSend/Files/file.apk")


if __name__ == "__main__":
    unittest.main()
