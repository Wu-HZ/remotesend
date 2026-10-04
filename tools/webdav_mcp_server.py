"""Project-local WebDAV MCP server. Credentials arrive via the ignored .mcp.json.

Run with ``python tools/webdav_mcp_server.py`` (stdio is reserved for MCP).
"""

from __future__ import annotations

import os
from pathlib import Path
from urllib.parse import urlsplit

from mcp.server.fastmcp import FastMCP
from webdav4.client import Client


mcp = FastMCP("webdav")


def _client() -> Client:
    url = os.getenv("WEBDAV_URL", "").strip()
    username = os.getenv("WEBDAV_USERNAME", "").strip()
    password = os.getenv("WEBDAV_PASSWORD", "")
    if not url or not username or not password or "REPLACE_ME" in (url, username, password):
        raise ValueError("Configure WEBDAV_URL, WEBDAV_USERNAME and WEBDAV_PASSWORD in the local .mcp.json first.")
    parts = urlsplit(url)
    if parts.scheme not in ("https", "http") or not parts.hostname:
        raise ValueError("WEBDAV_URL must be an HTTP(S) URL with a host.")
    if parts.username or parts.password or parts.fragment:
        raise ValueError("Do not embed credentials or fragments in WEBDAV_URL.")
    # A system proxy can intercept private WebDAV hosts and return HTTP 502.
    # Connect directly to the address explicitly configured by the user.
    return Client(url, auth=(username, password), timeout=60, trust_env=False)


def _remote_path(remote_path: str) -> str:
    if not remote_path.startswith("/") or any(part in (".", "..") for part in remote_path.split("/")):
        raise ValueError("remote_path must be an absolute WebDAV path without . or .. segments")
    return remote_path


@mcp.tool()
def webdav_upload(local_path: str, remote_path: str, overwrite: bool = False) -> str:
    """Upload a local file to WebDAV. Use overwrite=true to replace an existing APK.

    For RemoteSend: local_path=build/app/outputs/flutter-apk/app-release.apk,
    remote_path=/RemoteSend/Files/RemoteSend-Android.apk, overwrite=true.
    """
    source = Path(local_path).expanduser()
    if not source.is_file():
        raise ValueError(f"Local file does not exist: {source}")
    destination = _remote_path(remote_path)
    _client().upload_file(source, destination, overwrite=overwrite)
    return f"Uploaded {source} -> {destination}"


@mcp.tool()
def webdav_download(remote_path: str, local_path: str, overwrite: bool = False) -> str:
    """Download a WebDAV file to a local path; refuses to overwrite unless requested."""
    destination = Path(local_path).expanduser()
    if destination.exists() and not overwrite:
        raise ValueError(f"Local file already exists: {destination}")
    if not destination.parent.is_dir():
        raise ValueError(f"Local parent directory does not exist: {destination.parent}")
    source = _remote_path(remote_path)
    _client().download_file(source, destination)
    return f"Downloaded {source} -> {destination}"


@mcp.tool()
def webdav_list(remote_path: str = "/") -> list[str]:
    """List names of files or folders in a WebDAV directory."""
    return _client().ls(_remote_path(remote_path), detail=False)


@mcp.tool()
def webdav_mkdir(remote_path: str) -> str:
    """Create one directory on the WebDAV server (parent must exist)."""
    destination = _remote_path(remote_path)
    _client().mkdir(destination)
    return f"Created {destination}"


@mcp.tool()
def webdav_delete(remote_path: str, confirm: bool = False) -> str:
    """Delete a WebDAV resource. Requires confirm=true; deletion cannot be undone."""
    destination = _remote_path(remote_path)
    if destination == "/" or not confirm:
        raise ValueError("Refusing to delete without confirm=true (or to delete the WebDAV root).")
    _client().remove(destination)
    return f"Deleted {destination}"


if __name__ == "__main__":
    mcp.run(transport="stdio")
