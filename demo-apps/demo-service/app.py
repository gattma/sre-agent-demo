"""Small HTTP service with bounded metric labels and JSON request logs."""
import json
import os
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

LABELS = ["service", "method", "path", "status"]
REQUESTS = Counter("http_requests_total", "Completed HTTP requests", LABELS)
DURATION = Histogram(
    "http_request_duration_seconds", "HTTP request duration", LABELS
)
SERVICE = "demo-service"
VERSION = os.environ.get("SERVICE_VERSION", "0.1.0")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        started = time.monotonic()
        path = urlsplit(self.path).path
        routes = {"/", "/health", "/ready", "/metrics"}
        label_path = path if path in routes else "other"
        status = 200
        content_type = "application/json"
        if path == "/metrics":
            body = generate_latest()
            content_type = CONTENT_TYPE_LATEST
        elif path == "/":
            body = json.dumps({"service": SERVICE, "version": VERSION}).encode()
        elif path in {"/health", "/ready"}:
            body = b'{"status":"ok"}'
        else:
            status = 404
            body = b'{"error":"not found"}'
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        finally:
            duration = time.monotonic() - started
            labels = (SERVICE, "GET", label_path, str(status))
            REQUESTS.labels(*labels).inc()
            DURATION.labels(*labels).observe(duration)
            record = {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "level": "ERROR" if status >= 500 else "INFO",
                "service": SERVICE,
                "version": VERSION,
                "method": "GET",
                "path": label_path,
                "status": status,
                "duration": duration,
            }
            print(json.dumps(record), flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
