// Tests for modules/risk-alerts/forwarder.mjs against a local HTTP server.
//
//   node --test tests/forwarder.test.mjs

import assert from "node:assert/strict";
import http from "node:http";
import { after, before, beforeEach, test } from "node:test";

import { handler } from "../modules/risk-alerts/forwarder.mjs";

const event = { text: "AWS Health risk alert: X in account 111111111111 (us-gov-west-1)." };
const received = [];
let server;
let base;

before(async () => {
  server = http.createServer((request, response) => {
    let body = "";
    request.on("data", (chunk) => (body += chunk));
    request.on("end", () => {
      received.push([request.url, request.headers["content-type"], JSON.parse(body)]);
      response.writeHead(request.url === "/gone" ? 404 : 200).end();
    });
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

beforeEach(() => (received.length = 0));

// Invokes the handler with one webhook per path.
function forward(paths) {
  process.env.WEBHOOK_URLS = JSON.stringify(Object.fromEntries(paths.map((path) => [path, `${base}/${path}`])));
  return handler(event);
}

test("posts the event to every webhook", async () => {
  await forward(["slack", "chat"]);
  assert.deepEqual(received, [
    ["/slack", "application/json", event],
    ["/chat", "application/json", event],
  ]);
});

test("a failing webhook fails the invocation after trying the rest", async () => {
  await assert.rejects(forward(["gone", "slack"]), /webhooks failed: gone/);
  assert.deepEqual(received.map(([path]) => path), ["/gone", "/slack"]);
});
