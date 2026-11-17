"""Posts the event it is given to every chat webhook.

Used where EventBridge API destinations don't exist (GovCloud). The rule's
input transformer has already shaped the event into {"text": "..."}.
"""

import json
import os
import urllib.request

# Name => URL. The URLs are secrets: never log them.
WEBHOOK_URLS = json.loads(os.environ["WEBHOOK_URLS"])


def handler(event, context):
    body = json.dumps(event).encode()
    failed = []
    for name, url in WEBHOOK_URLS.items():
        request = urllib.request.Request(
            url, data=body, headers={"Content-Type": "application/json"}
        )
        try:
            with urllib.request.urlopen(request, timeout=5):
                pass
        except Exception as error:  # try every webhook, then fail
            status = getattr(error, "code", "")
            print(f"webhook {name} failed: {type(error).__name__} {status}")
            failed.append(name)
    if failed:
        # A failed invocation shows in the function's error metric and is retried.
        raise RuntimeError(f"webhooks failed: {failed}")
