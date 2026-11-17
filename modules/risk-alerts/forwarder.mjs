// Posts the event it is given to every chat webhook.
//
// Used where EventBridge API destinations don't exist (GovCloud). The rule's
// input transformer has already shaped the event into {"text": "..."}.
// No dependencies and no build step: fetch is built into the runtime.

export async function handler(event) {
  // Name => URL. The URLs are secrets: never log them.
  const webhookUrls = JSON.parse(process.env.WEBHOOK_URLS);
  const body = JSON.stringify(event);
  const failed = [];

  for (const [name, url] of Object.entries(webhookUrls)) {
    let reason;
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body,
        signal: AbortSignal.timeout(5000),
      });
      if (response.ok) continue;
      reason = `HTTP ${response.status}`;
    } catch (error) {
      // The name, not the message: the message can contain the URL.
      reason = error.name;
    }
    console.log(`webhook ${name} failed: ${reason}`);
    failed.push(name);
  }

  // A failed invocation shows in the function's error metric and is retried.
  if (failed.length > 0) throw new Error(`webhooks failed: ${failed.join(", ")}`);
}
