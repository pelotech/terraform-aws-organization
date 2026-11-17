"""Forwards AWS Health RISK events from SNS to chat webhooks as {"text": "..."}.

Used where EventBridge API destinations don't exist (GovCloud). Slack, Google
Chat and anything else that accepts a JSON body with a "text" field work.
"""

import json
import os
import urllib.request

# Name => URL. The URLs are secrets: never log them.
WEBHOOK_URLS = json.loads(os.environ["WEBHOOK_URLS"])


def text(message):
    """One line for an AWS Health event; anything else is passed through."""
    try:
        event = json.loads(message)
    except ValueError:
        return message
    if not isinstance(event, dict) or not isinstance(event.get("detail"), dict):
        return message
    detail = event["detail"]
    return (
        "AWS Health risk alert: {type} in account {account} ({region}). "
        "Open AWS Health in that account for details."
    ).format(
        type=detail.get("eventTypeCode", "unknown"),
        account=detail.get("affectedAccount", event.get("account", "unknown")),
        region=detail.get("eventRegion", event.get("region", "unknown")),
    )


def handler(event, context):
    failed = set()
    for record in event["Records"]:
        body = json.dumps({"text": text(record["Sns"]["Message"])}).encode()
        for name, url in WEBHOOK_URLS.items():
            request = urllib.request.Request(
                url, data=body, headers={"Content-Type": "application/json"}
            )
            try:
                with urllib.request.urlopen(request, timeout=10):
                    pass
            except Exception as error:  # noqa: BLE001 - report every webhook, then fail
                print(f"webhook {name} failed: {type(error).__name__}")
                failed.add(name)
    if failed:
        # Failing the invocation makes it visible in the function's error metric.
        raise RuntimeError(f"webhooks failed: {sorted(failed)}")
