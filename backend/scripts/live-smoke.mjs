import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";

// Synthetic identities exist only for this run; credentials are never printed or written.
const base = process.argv[2];
if (!base || !/^https:\/\/[a-z0-9.-]+\.workers\.dev$/.test(base)) throw new Error("Pass the verified https://<worker>.<subdomain>.workers.dev origin.");
const accounts = [];
const report = { checks: [], cleanup: [], failures: [] };
const fixture = async role => JSON.parse(await readFile(new URL(`../../game/tests/fixtures/first-light-${role}.json`, import.meta.url), "utf8"));
const assert = (condition, label) => { if (!condition) throw new Error(label); report.checks.push(label); };
async function api(path, method = "GET", body, account) {
  const headers = { "Content-Type": "application/json" };
  if (account) { headers.Authorization = `Bearer ${account.device_token}`; headers["X-Player-Id"] = account.player_id; }
  const response = await fetch(base + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(20000) });
  let parsed;
  try { parsed = await response.json(); } catch { parsed = {}; }
  return { status: response.status, body: parsed };
}
try {
  const health = await api("/health"); assert(health.status === 200 && health.body.api_version === 1, "health");
  for (let index = 0; index < 2; index++) {
    const response = await api("/v1/identity", "POST", {});
    if (response.status !== 201 || !response.body.device_token) throw new Error("identity creation");
    accounts.push(response.body);
  }
  report.checks.push("two anonymous identities");
  const [a, b] = accounts;
  if (process.argv.includes("--require-entitlement")) {
    const entitlement = await api("/v1/entitlement", "GET", undefined, a);
    assert(entitlement.status === 200 && entitlement.body.status === "verified" && entitlement.body.full_journey === false, "fresh identity has no provider entitlement");
  }
  let response = await api("/v1/rooms", "POST", { idempotency_key: randomUUID() }, a);
  assert(response.status === 200 && response.body.invite_code, "create room");
  let room = response.body;
  response = await api("/v1/rooms/join", "POST", { invite_code: room.invite_code }, b);
  assert(response.status === 200 && response.body.guest_id === b.player_id, "join partner"); room = response.body;
  const aBody = { base_revision: room.revision, idempotency_key: randomUUID(), recording: await fixture("a") };
  response = await api(`/v1/rooms/${room.room_id}/turns`, "POST", aBody, a);
  assert(response.status === 200 && response.body.active_role === "b", "native A fixture accepted"); room = response.body;
  response = await api(`/v1/rooms/${room.room_id}/turns`, "POST", aBody, a);
  assert(response.status === 200 && response.body.revision === room.revision, "uncertain-response retry idempotent");
  response = await api(`/v1/rooms/${room.room_id}/turns`, "POST", { ...aBody, idempotency_key: randomUUID() }, a);
  assert(response.status === 409 && response.body.error?.code === "stale_revision", "stale revision rejected");
  response = await api(`/v1/rooms/${room.room_id}`, "GET", undefined, b);
  assert(response.status === 200 && response.body.recordings.a.final_state_hash === aBody.recording.final_state_hash, "partner fetches saved first turn"); room = response.body;
  response = await api(`/v1/rooms/${room.room_id}/turns`, "POST", { base_revision: room.revision, idempotency_key: randomUUID(), recording: await fixture("b") }, b);
  assert(response.status === 200 && response.body.active_role === "complete", "native B fixture accepted"); room = response.body;
  response = await api(`/v1/rooms/${room.room_id}/collection`, "GET", undefined, a);
  assert(response.status === 200 && response.body.islands.length === 1 && response.body.islands[0].recordings.b.completed, "completed replay collection");
  response = await api(`/v1/rooms/${room.room_id}/fork`, "POST", { base_revision: room.revision, idempotency_key: randomUUID() }, b);
  assert(response.status === 200 && response.body.recordings.a === null && response.body.recordings.b === null, "fork clears dependent turns");
  response = await api(`/v1/rooms/${room.room_id}/collection`, "GET", undefined, a);
  assert(response.status === 200 && response.body.islands.length === 1, "original completed replay retained");
} catch (error) {
  report.failures.push(error instanceof Error ? error.message : "smoke test failed");
} finally {
  for (const account of accounts) {
    try {
      const deleted = await api("/v1/identity", "DELETE", undefined, account);
      const inaccessible = await api("/v1/identity", "GET", undefined, account);
      report.cleanup.push(deleted.status === 200 && inaccessible.status === 401 ? "synthetic identity and associated room data erased" : "cleanup incomplete");
    } catch { report.cleanup.push("cleanup request failed"); }
  }
}
console.log(JSON.stringify({ origin: base, ...report }, null, 2));
if (report.failures.length || report.cleanup.some(item => item !== "synthetic identity and associated room data erased")) process.exitCode = 1;
