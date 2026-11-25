import io
import threading
import unittest
from contextlib import redirect_stdout
from http.server import ThreadingHTTPServer
from unittest.mock import patch
from urllib.error import HTTPError, URLError
from urllib.request import urlopen

import app


class ServiceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), app.Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = "http://127.0.0.1:%s" % cls.server.server_port

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def get(self, path):
        try:
            with urlopen(self.url + path, timeout=5) as response:
                return response.status, response.read()
        except HTTPError as exc:
            return exc.code, exc.read()

    def test_hello_and_peer_call(self):
        with patch.object(app, "PEER_URL", self.url):
            self.assertEqual(self.get("/hello"), self.get("/call"))
            self.assertIn(app.NAMESPACE.encode(), self.get("/hello")[1])

    def test_probe_modes(self):
        with patch.object(app, "CHECK_PEER", False), patch.object(
            app, "call_peer", return_value=(502, b"failed")
        ) as peer:
            for path in ("/health", "/ready"):
                self.assertEqual(self.get(path)[0], 200)
            peer.assert_not_called()
            self.assertEqual(self.get("/startup")[0], 503)
        for peer_status, expected in ((200, 200), (502, 503), (504, 503)):
            with patch.object(app, "CHECK_PEER", True), patch.object(
                app, "call_peer", return_value=(peer_status, b"")
            ):
                for path in ("/startup", "/health", "/ready"):
                    self.assertEqual(self.get(path)[0], expected)

    def test_peer_failures_and_timeouts(self):
        for error, expected in (
            (URLError(ConnectionRefusedError("refused")), 502),
            (URLError(TimeoutError("timed out")), 504),
            (TimeoutError("timed out"), 504),
            (HTTPError(self.url, 500, "failed", {}, None), 502),
        ):
            with patch.object(app, "PEER_URL", self.url), patch.object(
                app.HTTP, "open", side_effect=error
            ) as request:
                self.assertEqual(self.get("/call")[0], expected)
                request.assert_called_once_with(self.url + "/hello", timeout=2)

    def test_missing_peer_and_unknown_path(self):
        with patch.object(app, "PEER_URL", ""):
            self.assertEqual(self.get("/call")[0], 502)
        self.assertEqual(self.get("/missing")[0], 404)

    def test_peer_log_contains_target_and_error(self):
        output = io.StringIO()
        with patch.object(app, "PEER_URL", ""), redirect_stdout(output):
            app.call_peer()
        import json
        record = json.loads(output.getvalue())
        self.assertEqual(record["event"], "peer_request")
        self.assertEqual(record["status"], 502)
        self.assertIn("PEER_URL", record["error"])
        self.assertIn("target", record)
        self.assertIn("duration", record)


if __name__ == "__main__":
    unittest.main()
