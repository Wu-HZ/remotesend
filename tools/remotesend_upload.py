"""Upload a build artifact through a running RemoteSend desktop app.

Requires only Python 3. Set REMOTESEND_API_TOKEN (from Settings) in your local
shell environment; do not put it in source code or command-line arguments.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import ProxyHandler, Request, build_opener

BASE_URL = "http://127.0.0.1:38764"


class UploadError(Exception):
    pass


def _request(method: str, url: str, token: str, data: dict | None = None) -> dict:
    body = json.dumps(data).encode("utf-8") if data is not None else None
    request = Request(
        url,
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            **({"Content-Type": "application/json"} if body is not None else {}),
        },
    )
    # Never send the API token to a configured system proxy.
    opener = build_opener(ProxyHandler({}))
    try:
        with opener.open(request, timeout=15) as response:
            return json.load(response)
    except HTTPError as exc:
        try:
            detail = json.load(exc).get("error", "Unknown error")
        except (ValueError, AttributeError):
            detail = "Unknown error"
        raise UploadError(f"RemoteSend HTTP {exc.code}: {detail}") from None
    except (URLError, OSError) as exc:
        raise UploadError(f"Cannot reach RemoteSend at {BASE_URL}: {exc}") from None


def upload(path: Path, token: str, *, overwrite: bool = False,
           wait: bool = True, interval: float = 1, timeout: float = 3600) -> dict:
    if not path.is_file():
        raise UploadError(f"File does not exist: {path}")
    if not token:
        raise UploadError("Set REMOTESEND_API_TOKEN from RemoteSend Settings first")
    job = _request("POST", f"{BASE_URL}/v1/uploads", token,
                   {"path": str(path.resolve()), "overwrite": overwrite})
    print(f"Queued {job['id']} -> {job['remotePath']}", file=sys.stderr)
    if not wait:
        return job
    deadline = time.monotonic() + timeout
    while True:
        job = _request("GET", f"{BASE_URL}/v1/uploads/{job['id']}", token)
        if job["status"] == "completed":
            return job
        if job["status"] == "failed":
            raise UploadError(f"Upload {job['id']} failed: {job.get('error', 'Unknown error')}")
        if time.monotonic() >= deadline:
            raise UploadError(f"Timed out waiting for {job['id']} (upload may still be running)")
        time.sleep(interval)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="Path to the local build artifact")
    parser.add_argument("--overwrite", action="store_true", help="Replace the remote basename")
    parser.add_argument("--no-wait", action="store_true", help="Return after queuing")
    parser.add_argument("--timeout", type=int, default=3600, help="Seconds to wait (default: 3600)")
    args = parser.parse_args()
    try:
        job = upload(args.path, os.getenv("REMOTESEND_API_TOKEN", ""),
                     overwrite=args.overwrite, wait=not args.no_wait,
                     timeout=args.timeout)
    except (UploadError, KeyError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(job, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
