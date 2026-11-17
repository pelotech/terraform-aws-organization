"""Tests for modules/risk-alerts/forwarder.py against a local HTTP server.

    python3 -m unittest discover -s tests
"""

import http.server
import importlib.util
import json
import os
import pathlib
import threading
import unittest

FORWARDER = pathlib.Path(__file__).parent.parent / "modules/risk-alerts/forwarder.py"
EVENT = {"text": "AWS Health risk alert: X in account 111111111111 (us-gov-west-1)."}


class Webhook(http.server.BaseHTTPRequestHandler):
    received = []

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        Webhook.received.append((self.path, self.headers["Content-Type"], json.loads(body)))
        self.send_response(404 if self.path == "/gone" else 200)
        self.end_headers()

    def log_message(self, *args):
        pass


class ForwarderTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.HTTPServer(("127.0.0.1", 0), Webhook)
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        Webhook.received.clear()

    def forward(self, paths):
        """Loads the module with the given webhooks and invokes the handler."""
        os.environ["WEBHOOK_URLS"] = json.dumps({p: f"{self.base}/{p}" for p in paths})
        spec = importlib.util.spec_from_file_location("forwarder", FORWARDER)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.handler(EVENT, None)

    def test_posts_the_event_to_every_webhook(self):
        self.forward(["slack", "chat"])
        self.assertEqual(
            Webhook.received,
            [("/slack", "application/json", EVENT), ("/chat", "application/json", EVENT)],
        )

    def test_a_failing_webhook_fails_the_invocation_after_trying_the_rest(self):
        with self.assertRaisesRegex(RuntimeError, "gone"):
            self.forward(["gone", "slack"])
        self.assertEqual([path for path, _, _ in Webhook.received], ["/gone", "/slack"])


if __name__ == "__main__":
    unittest.main()
