import test from "node:test";
import assert from "node:assert/strict";
import { eraseSyntheticIdentity, makeApi, runLiveSmoke } from "./live-smoke.mjs";

// All transport responses are synthetic. No test contacts a provider.
const origin = "https://synthetic.workers.dev";
const account = { player_id: "synthetic-player", device_token: "synthetic-device" };
const json = (body, status = 200) => new Response(JSON.stringify(body), { status });

test("transport refuses redirects and preserves scoped authentication", async () => {
  const calls = [];
  const api = makeApi(origin, async (url, options) => {
    calls.push({ url, options });
    return new Response(null, { status: 302, headers: { Location: "https://unrelated.example/" } });
  });
  const response = await api("/v1/identity", "GET", undefined, account);
  assert.equal(response.status, 302);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, origin + "/v1/identity");
  assert.equal(calls[0].options.redirect, "manual");
  assert.equal(calls[0].options.headers.Authorization, "Bearer synthetic-device");
  assert.equal(calls[0].options.headers["X-Player-Id"], "synthetic-player");
  assert.ok(calls[0].options.signal instanceof AbortSignal);
});

test("invalid origin is rejected before transport", () => {
  let called = false;
  assert.throws(() => makeApi("https://unrelated.example", async () => { called = true; }));
  assert.equal(called, false);
});

test("malformed and oversized response bodies cannot pass JSON checks", async () => {
  const malformed = makeApi(origin, async () => new Response("not-json"));
  assert.deepEqual((await malformed("/health")).body, {});
  const oversized = makeApi(origin, async () => new Response("x".repeat(1024 * 1024 + 1)));
  await assert.rejects(oversized("/health"), /oversized response/);
});

test("oversized chunked response is cancelled before reading more chunks", async () => {
  let pulls = 0;
  let cancelled = false;
  const stream = new ReadableStream({
    pull(controller) {
      pulls++;
      controller.enqueue(new Uint8Array(pulls === 1 ? 1024 * 1024 - 2 : 3));
    },
    cancel() { cancelled = true; }
  }, { highWaterMark: 0 });
  const api = makeApi(origin, async () => new Response(stream, { headers: { "Content-Length": "1" } }));
  await assert.rejects(api("/health"), /oversized response/);
  assert.equal(cancelled, true);
  assert.equal(pulls, 2);
  assert.equal(stream.locked, false);
});

test("exact byte limit accepts split UTF-8 but rejects Unicode byte overflow", async () => {
  const encoder = new TextEncoder();
  const prefix = '{"message":"', suffix = '"}';
  const value = "é".repeat((1024 * 1024 - encoder.encode(prefix + suffix).byteLength) / 2);
  const bytes = encoder.encode(prefix + value + suffix);
  assert.equal(bytes.byteLength, 1024 * 1024);
  const split = encoder.encode(prefix).byteLength + 1; // Split the first é between its two bytes.
  const stream = new ReadableStream({ start(controller) {
    controller.enqueue(bytes.subarray(0, split));
    controller.enqueue(bytes.subarray(split));
    controller.close();
  } });
  const api = makeApi(origin, async () => new Response(stream));
  assert.equal((await api("/health")).body.message, value);
  assert.equal(stream.locked, false);
  const overflow = makeApi(origin, async () => new Response(prefix + value + "é" + suffix));
  await assert.rejects(overflow("/health"), /oversized response/);
});

test("invalid UTF-8 is rejected instead of silently replacing response content", async () => {
  const invalid = new Uint8Array([0x7b, 0x22, 0x76, 0x22, 0x3a, 0x22, 0xc3, 0x28, 0x22, 0x7d]);
  const api = makeApi(origin, async () => new Response(invalid));
  await assert.rejects(api("/health"), /invalid UTF-8 response/);
});

function cleanupApi(replies) {
  const calls = [];
  return {
    calls,
    api: async (path, method, body, identity) => {
      calls.push(method);
      assert.equal(path, "/v1/identity");
      assert.equal(body, undefined);
      assert.equal(identity, account);
      const reply = replies.shift();
      if (reply instanceof Error) throw reply;
      assert.equal(typeof reply, "number", "unexpected cleanup retry");
      return { status: reply, body: {} };
    }
  };
}

test("acknowledged deletion with revoked access finishes immediately", async () => {
  const fake = cleanupApi([200, 401]);
  assert.equal(await eraseSyntheticIdentity(fake.api, account), true);
  assert.deepEqual(fake.calls, ["DELETE", "GET"]);
});

test("lost deletion reply reconciles on a second deletion plus revoked access", async () => {
  const fake = cleanupApi([new Error("synthetic loss"), 401, 401, 401]);
  assert.equal(await eraseSyntheticIdentity(fake.api, account), true);
  assert.deepEqual(fake.calls, ["DELETE", "GET", "DELETE", "GET"]);
});

test("revoked GET alone does not establish completed room cleanup", async () => {
  const fake = cleanupApi([503, 401, 503, 401]);
  assert.equal(await eraseSyntheticIdentity(fake.api, account), false);
  assert.equal(fake.calls.length, 4);
});

test("unavailable cleanup stops after two attempts", async () => {
  const fake = cleanupApi(Array.from({ length: 4 }, () => new Error("synthetic unavailable")));
  assert.equal(await eraseSyntheticIdentity(fake.api, account), false);
  assert.equal(fake.calls.length, 4);
});

test("raw network error text stays out of the failure report", async () => {
  const report = await runLiveSmoke(origin, { fetchImpl: async () => { throw new Error("synthetic-private-marker"); } });
  assert.deepEqual(report.failures, ["Failed during health; see the last completed named check."]);
  assert.equal(JSON.stringify(report).includes("synthetic-private-marker"), false);
});

test("failure after identity creation still cleans every captured identity", async () => {
  let created = 0;
  const erased = [];
  const report = await runLiveSmoke(origin, {
    requireEntitlement: true,
    fetchImpl: async (url, options) => {
      if (url.endsWith("/health")) return json({ api_version: 1 });
      if (url.endsWith("/v1/identity") && options.method === "POST") return json({ player_id: `test-${++created}`, device_token: `test-device-${created}` }, 201);
      if (url.endsWith("/v1/entitlement")) throw new Error("synthetic-private-marker");
      if (options.method === "DELETE") { erased.push(options.headers["X-Player-Id"]); return json({ deleted: true }); }
      if (url.endsWith("/v1/identity") && options.method === "GET") return json({}, 401);
      throw new Error("unexpected synthetic request");
    }
  });
  assert.deepEqual(erased, ["test-1", "test-2"]);
  assert.equal(report.cleanup.length, 2);
  assert.ok(report.cleanup.every(value => value === "synthetic identity and associated room data erased"));
  assert.deepEqual(report.failures, ["Failed during provider entitlement; see the last completed named check."]);
  assert.equal(JSON.stringify(report).includes("synthetic-private-marker"), false);
});

test("incomplete cleanup remains an explicit failure result", async () => {
  let created = 0;
  let cleanupRequests = 0;
  const report = await runLiveSmoke(origin, { fetchImpl: async (url, options) => {
    if (url.endsWith("/health")) return json({ api_version: 1 });
    if (url.endsWith("/v1/identity") && options.method === "POST") {
      if (++created === 1) return json(account, 201);
      return json({}, 503);
    }
    cleanupRequests++;
    return json({}, options.method === "GET" ? 401 : 503);
  } });
  assert.equal(cleanupRequests, 4);
  assert.deepEqual(report.cleanup, ["cleanup incomplete after bounded reconciliation"]);
  assert.deepEqual(report.failures, ["Failed during identity creation; see the last completed named check."]);
});
