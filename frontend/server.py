#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST = os.getenv("FRONTEND_HOST", "0.0.0.0")
PORT = int(os.getenv("FRONTEND_PORT", "4041"))
BACKEND_URL = os.getenv("BACKEND_URL", "http://127.0.0.1:4040").rstrip("/")

ROOT = Path(__file__).resolve().parent
CANDIDATES = [
    ROOT / "dist" / "linux-monitoring-ui" / "browser",
    ROOT / "dist" / "linux-monitoring-ui",
    ROOT / "dist",
]

for candidate in CANDIDATES:
    if (candidate / "index.html").exists():
        WEB_ROOT = candidate
        break
else:
    raise SystemExit(
        "No frontend index.html found. Run `npm run build` first. "
        "Checked: " + ", ".join(str(path) for path in CANDIDATES)
    )


HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length",
    "accept-encoding",
}


class ProxyingSpaHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_ROOT), **kwargs)

    def end_headers(self) -> None:
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def do_GET(self) -> None:
        if self.path == "/api" or self.path.startswith("/api/"):
            self._proxy_to_backend()
            return
        self._serve_spa()

    def do_HEAD(self) -> None:
        if self.path == "/api" or self.path.startswith("/api/"):
            self._proxy_to_backend()
            return
        self._serve_spa()

    def do_POST(self) -> None:
        if self.path == "/api" or self.path.startswith("/api/"):
            self._proxy_to_backend()
            return
        self.send_error(404)

    def do_PUT(self) -> None:
        if self.path == "/api" or self.path.startswith("/api/"):
            self._proxy_to_backend()
            return
        self.send_error(404)

    def do_PATCH(self) -> None:
        if self.path == "/api" or self.path.startswith("/api/"):
            self._proxy_to_backend()
            return
        self.send_error(404)

    def do_DELETE(self) -> None:
        if self.path == "/api" or self.path.startswith("/api/"):
            self._proxy_to_backend()
            return
        self.send_error(404)

    def do_OPTIONS(self) -> None:
        if self.path == "/api" or self.path.startswith("/api/"):
            self._proxy_to_backend()
            return
        self.send_response(204)
        self.end_headers()

    def _serve_spa(self) -> None:
        requested = WEB_ROOT / self.path.lstrip("/").split("?", 1)[0]
        if self.path != "/" and not requested.exists() and "." not in requested.name:
            self.path = "/index.html"
        super().do_GET()

    def _proxy_to_backend(self) -> None:
        body = None
        length = self.headers.get("Content-Length")
        if length:
            body = self.rfile.read(int(length))

        target = f"{BACKEND_URL}{self.path}"
        headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in HOP_BY_HOP_HEADERS
        }

        request = urllib.request.Request(
            target,
            data=body,
            headers=headers,
            method=self.command,
        )

        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                payload = response.read()
                self.send_response(response.status)
                for key, value in response.headers.items():
                    if key.lower() not in HOP_BY_HOP_HEADERS:
                        self.send_header(key, value)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(payload)

        except urllib.error.HTTPError as error:
            payload = error.read()
            self.send_response(error.code)
            for key, value in error.headers.items():
                if key.lower() not in HOP_BY_HOP_HEADERS:
                    self.send_header(key, value)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(payload)

        except Exception as error:
            payload = json.dumps(
                {
                    "detail": "Backend proxy error",
                    "error": str(error),
                    "backend_url": BACKEND_URL,
                }
            ).encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(payload)


def main() -> None:
    print(
        f"Serving frontend from {WEB_ROOT} on http://{HOST}:{PORT}; "
        f"proxying /api to {BACKEND_URL}",
        flush=True,
    )
    server = ThreadingHTTPServer((HOST, PORT), ProxyingSpaHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
