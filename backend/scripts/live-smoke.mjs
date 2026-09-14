import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { pathToFileURL } from "node:url";

// Synthetic identities exist only for this run; credentials are never printed or written.
const fixture = async role => JSON.parse(await readFile(new URL(`../../game/tests/fixtures/first-light-${role}.json`, import.meta.url), "utf8"));
const MAX_RESPONSE_BYTES = 1024 * 1024;

async function boundedResponseText(response) {
  if (!response.body) return "";
  const reader = response.body.getReader();
  // A single fixed buffer also bounds bookkeeping for streams of tiny chunks.
  const bytes = new Uint8Array(MAX_RESPONSE_BYTES);
  let size = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      if (next.value.byteLength > MAX_RESPONSE_BYTES - size) {
        try { await reader.cancel(); } catch { /* Keep the bounded diagnostic. */ }
        throw new Error("oversized response");
      }
      bytes.set(next.value, size);
      size += next.value.byteLength;
    }
  } finally { reader.releaseLock(); }
  try { return new TextDecoder("utf-8", { fatal: true }).decode(bytes.subarray(0, size)); }
  catch { throw new Error("invalid UTF-8 response"); }
}

export function makeApi(base, fetchImpl = fetch) {
  if (!base || !/^https:\/\/[a-z0-9.-]+\.workers\.dev$/.test(base)) throw new Error("Pass the verified https://<worker>.<subdomain>.workers.dev origin.");
  return async (path, method = "GET", body, account) => {
    const headers = { "Content-Type": "application/json" };
    if (account) { headers.Authorization = `Bearer ${account.device_token}`; headers["X-Player-Id"] = account.player_id; }
    const response = await fetchImpl(base + path, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(20000), redirect: "manual"
    });
    const text = await boundedResponseText(response);
    let parsed;
    try { parsed = JSON.parse(text); } catch { parsed = {}; }
    return { status: response.status, body: parsed };
  };
}

export async function eraseSyntheticIdentity(api, account) {
  // GET 401 alone also occurs while deletion is incomplete. Require a DELETE
  // acknowledgement, or a second DELETE 401, together with revoked access.
  for (let attempt = 0; attempt < 2; attempt++) {
    let deleted, inaccessible;
    try { deleted = await api("/v1/identity", "DELETE", undefined, account); } catch { /* Reconcile below. */ }
    try { inaccessible = await api("/v1/identity", "GET", undefined, account); } catch { /* One bounded retry. */ }
    if ((deleted?.status === 200 || (attempt === 1 && deleted?.status === 401)) && inaccessible?.status === 401) return true;
  }
  return false;
}

export async function runLiveSmoke(base, { requireEntitlement = false, fetchImpl = fetch, loadFixture = fixture } = {}) {
  const api = makeApi(base, fetchImpl);
  const accounts = [];
  const report = { origin: base, checks: [], cleanup: [], failures: [] };
  const assert = (condition, label) => { if (!condition) throw new Error(label); report.checks.push(label); };
  let phase = "health";
  try {
    const health = await api("/health"); assert(health.status === 200 && health.body.api_version === 1, "health");
    phase = "identity creation";
    for (let index = 0; index < 2; index++) {
      const response = await api("/v1/identity", "POST", {});
      if (response.status !== 201 || !response.body.device_token) throw new Error("identity creation");
      accounts.push(response.body);
    }
    report.checks.push("two anonymous identities");
    const [a, b] = accounts;
    if (requireEntitlement) {
      phase = "provider entitlement";
      const entitlement = await api("/v1/entitlement", "GET", undefined, a);
      assert(entitlement.status === 200 && entitlement.body.status === "verified" && entitlement.body.full_journey === false, "fresh identity has no provider entitlement");
    }
    phase = "room creation";
    let response = await api("/v1/rooms", "POST", { idempotency_key: randomUUID() }, a);
    assert(response.status === 200 && response.body.invite_code, "create room");
    let room = response.body;
    phase = "partner join";
    response = await api("/v1/rooms/join", "POST", { invite_code: room.invite_code }, b);
    assert(response.status === 200 && response.body.guest_id === b.player_id, "join partner"); room = response.body;
    phase = "first contribution and retry";
    const aBody = { base_revision: room.revision, idempotency_key: randomUUID(), recording: await loadFixture("a") };
    response = await api(`/v1/rooms/${room.room_id}/turns`, "POST", aBody, a);
    assert(response.status === 200 && response.body.active_role === "b", "native A fixture accepted"); room = response.body;
    response = await api(`/v1/rooms/${room.room_id}/turns`, "POST", aBody, a);
    assert(response.status === 200 && response.body.revision === room.revision, "uncertain-response retry idempotent");
    response = await api(`/v1/rooms/${room.room_id}/turns`, "POST", { ...aBody, idempotency_key: randomUUID() }, a);
    assert(response.status === 409 && response.body.error?.code === "stale_revision", "stale revision rejected");
    phase = "partner handoff";
    response = await api(`/v1/rooms/${room.room_id}`, "GET", undefined, b);
    assert(response.status === 200 && response.body.recordings.a.final_state_hash === aBody.recording.final_state_hash, "partner fetches saved first turn"); room = response.body;
    response = await api(`/v1/rooms/${room.room_id}/turns`, "POST", { base_revision: room.revision, idempotency_key: randomUUID(), recording: await loadFixture("b") }, b);
    assert(response.status === 200 && response.body.active_role === "complete", "native B fixture accepted"); room = response.body;
    phase = "collection and fork";
    response = await api(`/v1/rooms/${room.room_id}/collection`, "GET", undefined, a);
    assert(response.status === 200 && response.body.islands.length === 1 && response.body.islands[0].recordings.b.completed, "completed replay collection");
    response = await api(`/v1/rooms/${room.room_id}/fork`, "POST", { base_revision: room.revision, idempotency_key: randomUUID() }, b);
    assert(response.status === 200 && response.body.recordings.a === null && response.body.recordings.b === null, "fork clears dependent turns");
    response = await api(`/v1/rooms/${room.room_id}/collection`, "GET", undefined, a);
    assert(response.status === 200 && response.body.islands.length === 1, "original completed replay retained");
  } catch {
    // Never include raw server bodies, network exception text or credentials.
    report.failures.push(`Failed during ${phase}; see the last completed named check.`);
  } finally {
    for (const account of accounts) {
      const erased = await eraseSyntheticIdentity(api, account);
      report.cleanup.push(erased ? "synthetic identity and associated room data erased" : "cleanup incomplete after bounded reconciliation");
    }
  }
  // A process kill cannot run finally. No persistent credential/cleanup journal
  // exists; retain incomplete results and diagnose instead of retrying storms.
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const report = await runLiveSmoke(process.argv[2], { requireEntitlement: process.argv.includes("--require-entitlement") });
  console.log(JSON.stringify(report, null, 2));
  if (report.failures.length || report.cleanup.some(item => item !== "synthetic identity and associated room data erased")) process.exitCode = 1;
}
