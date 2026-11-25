"""Small HTTP peer used to demonstrate Kubernetes NetworkPolicies."""
import json
import os
import socket
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, build_opener

NAMESPACE = os.environ.get("POD_NAMESPACE", "local")
PEER_URL = os.environ.get("PEER_URL", "").rstrip("/")
CHECK_PEER = os.environ.get("CHECK_PEER", "false").lower() == "true"
PEER_TIMEOUT = 2
# Cluster traffic must not accidentally pass through an environment HTTP proxy.
HTTP = build_opener(ProxyHandler({}))


def log(**fields):
    print(json.dumps({"timestamp": datetime.now(timezone.utc).isoformat(),
                      "namespace": NAMESPACE, **fields}), flush=True)


def call_peer():
    started = time.monotonic()
    target = PEER_URL + "/hello"
    status, body, error = 502, b"Peer connection failed\n", None
    try:
        if not PEER_URL:
            raise ValueError("PEER_URL is not configured")
        with HTTP.open(target, timeout=PEER_TIMEOUT) as response:
            body = response.read()
            status = response.status
    except HTTPError as exc:
        error = str(exc)
        body = b"Peer returned an HTTP error\n"
    except (TimeoutError, socket.timeout) as exc:
        status, body, error = 504, b"Peer request timed out\n", str(exc)
    except URLError as exc:
        error = str(exc.reason)
        if isinstance(exc.reason, (TimeoutError, socket.timeout)):
            status, body = 504, b"Peer request timed out\n"
    except (OSError, ValueError) as exc:
        error = str(exc)
    log(event="peer_request", target=target, status=status,
        duration=time.monotonic() - started, error=error)
    return status, body


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        started = time.monotonic()
        path = urlsplit(self.path).path
        status = 200
        if path == "/hello":
            body = ("Hello from " + NAMESPACE + "\n").encode()
        elif path == "/call":
            status, body = call_peer()
        elif path in {"/health", "/ready", "/startup"}:
            if CHECK_PEER or path == "/startup":
                peer_status, _ = call_peer()
                status = 200 if 200 <= peer_status < 300 else 503
            body = b"ok\n" if status == 200 else b"Peer unavailable\n"
        else:
            status, body = 404, b"Not found\n"
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            log(event="request", path=path, status=status,
                duration=time.monotonic() - started)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
