import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { isDeepStrictEqual } from "node:util";

// This exercises the real HTTP API with native fixtures, not Android gameplay.
// Only newly created synthetic identities are used. Never log response bodies.
const base = process.argv[2];
const local = process.argv.includes("--local");
const allowed = local ? /^http:\/\/127\.0\.0\.1:\d{2,5}$/ : /^https:\/\/[a-z0-9.-]+\.workers\.dev$/;
if (!base || !allowed.test(base)) throw new Error("Pass a verified workers.dev origin, or an explicit --local loopback origin.");
const accounts = [];
const report = { origin: base, scope: "synthetic HTTP fixtures; not native gameplay", checks: [], cleanup: [], failures: [] };
let roomId;
let phase = "fixture preflight";
const check = (condition, label) => {
  if (!condition) throw new Error(label);
  report.checks.push(label);
};
async function api(path, method = "GET", body, account) {
  const headers = { "Content-Type": "application/json" };
  if (account) { headers.Authorization = `Bearer ${account.device_token}`; headers["X-Player-Id"] = account.player_id; }
  const response = await fetch(base + path, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(20000), redirect: "manual"
  });
  const text = await response.text();
  if (text.length > 1024 * 1024) throw new Error("oversized response");
  let data;
  try { data = JSON.parse(text); } catch { data = {}; }
  return { status: response.status, data };
}
const fixture = async name => JSON.parse(await readFile(new URL(`../../game/tests/fixtures/v2/${name}.json`, import.meta.url), "utf8"));
const turn = (room, recording, checkpoint) => ({
  base_revision: room.revision, branch: room.branch, idempotency_key: randomUUID(), recording,
  ...(checkpoint ? { checkpoint } : {})
});
try {
  const [initial, firstA, firstB, middle, secondA, secondB, final] = await Promise.all(
    ["initial-checkpoint", "relay-a", "relay-b", "relay-checkpoint", "garden-a", "garden-b", "final-checkpoint"].map(fixture)
  );
  check([firstA, firstB, secondA, secondB].every(item => item.definition_hash === initial.definition_hash), "fixtures use one catalog");
  phase = "identity creation";
  for (let i = 0; i < 3; i++) {
    const created = await api("/v1/identity", "POST", {});
    if (created.status !== 201 || typeof created.data.device_token !== "string" || typeof created.data.player_id !== "string") throw new Error("identity unavailable");
    accounts.push(created.data);
  }
  report.checks.push("three disposable identities created");
  const [host, guest, outsider] = accounts;
  phase = "v2 capabilities";
  const capabilities = await api("/v2/capabilities", "GET", undefined, host);
  check(capabilities.status === 200 && capabilities.data.mutations_enabled === true, "v2 mutations explicitly enabled");
  phase = "room creation";
  const createBody = { idempotency_key: randomUUID(), level_id: initial.level_id, level_version: initial.level_version, definition_hash: initial.definition_hash };
  let response = await api("/v2/rooms", "POST", createBody, host);
  check(response.status === 200 && response.data.checkpoint?.checkpoint_hash === initial.checkpoint_hash, "create exact native chapter");
  let room = response.data;
  roomId = room.room_id;
  const invite = room.invite_code;
  response = await api("/v2/rooms", "POST", createBody, host);
  check(response.status === 200 && response.data.room_id === roomId, "creation retry keeps the room");
  response = await api(`/v2/rooms/${roomId}`, "GET", undefined, outsider);
  check(response.status === 404, "nonmember cannot read room");

  phase = "host contribution before joining";
  const aBody = turn(room, firstA);
  response = await api(`/v2/rooms/${roomId}/turns`, "POST", aBody, host);
  check(response.status === 200 && response.data.room.active_role === "b" && response.data.room.active_player_id === null, "host can leave first recording before invitation is joined");
  // Discard the successful mutation response and reconcile through the operation endpoint.
  response = undefined;
  response = await api(`/v2/rooms/${roomId}/operations/${aBody.idempotency_key}`, "GET", undefined, host);
  check(response.status === 200 && response.data.receipt.recording_hash === firstA.recording_hash && response.data.receipt.idempotency_key === aBody.idempotency_key, "lost acknowledgement reconciles exact recording");
  const firstReceipt = response.data.receipt;
  room = response.data.room;
  response = await api(`/v2/rooms/${roomId}/turns`, "POST", aBody, host);
  check(response.status === 200 && isDeepStrictEqual(response.data.receipt, firstReceipt) && response.data.room.revision === room.revision, "exact retry does not duplicate a turn");
  response = await api(`/v2/rooms/${roomId}/turns`, "POST", { ...aBody, idempotency_key: randomUUID() }, host);
  check(response.status === 409, "stale changed operation rejected");

  phase = "guest join and midpoint";
  response = await api("/v2/rooms/join", "POST", { invite_code: invite }, guest);
  check(response.status === 200 && response.data.active_player_id === guest.player_id && isDeepStrictEqual(response.data.recording_a, firstA), "guest receives the exact saved first recording");
  room = response.data;
  response = await api(`/v2/rooms/${roomId}/operations/${aBody.idempotency_key}`, "GET", undefined, guest);
  check(response.status === 404, "operation receipt remains scoped to its player");
  response = await api(`/v2/rooms/${roomId}/turns`, "POST", turn(room, firstB, middle), guest);
  check(response.status === 200 && response.data.room.stage_index === 1 && response.data.room.active_player_id === guest.player_id && isDeepStrictEqual(response.data.room.checkpoint, middle), "midpoint persists and first-player role alternates");
  room = response.data.room;

  phase = "second pair and collection";
  response = await api(`/v2/rooms/${roomId}/turns`, "POST", turn(room, secondA), guest);
  check(response.status === 200 && response.data.room.active_player_id === host.player_id, "guest leaves second-stage recording for host");
  room = response.data.room;
  response = await api(`/v2/rooms/${roomId}/turns`, "POST", turn(room, secondB, final), host);
  check(response.status === 200 && response.data.room.active_role === "complete" && isDeepStrictEqual(response.data.room.checkpoint, final), "whole chapter final checkpoint matches native proof");
  room = response.data.room;
  response = await api(`/v2/rooms/${roomId}/collection`, "GET", undefined, guest);
  check(response.status === 200 && response.data.pairs?.length === 2 && response.data.active_pair_ids?.length === 2, "both pairs appear in collection");
  const pairIds = response.data.active_pair_ids;
  for (let i = 0; i < 2; i++) {
    response = await api(`/v2/rooms/${roomId}/pairs/${pairIds[i]}`, "GET", undefined, guest);
    check(response.status === 200 && isDeepStrictEqual(response.data.a, i ? secondA : firstA) && isDeepStrictEqual(response.data.b, i ? secondB : firstB), `pair ${i + 1} replays preserve exact recordings`);
  }
  phase = "checkpoint fork";
  response = await api(`/v2/rooms/${roomId}/fork`, "POST", { base_revision: room.revision, branch: room.branch, stage_index: 1, idempotency_key: randomUUID() }, host);
  check(response.status === 200 && response.data.room.branch === room.branch + 1 && response.data.room.stage_index === 1 && isDeepStrictEqual(response.data.room.checkpoint, middle), "fork restores midpoint without changing preceding pair");
  response = await api(`/v2/rooms/${roomId}/collection`, "GET", undefined, guest);
  check(response.status === 200 && response.data.pairs?.length === 2 && response.data.active_pair_ids?.length === 1, "fork retains old completed replay");
  response = await api(`/v2/rooms/${roomId}/operations/${aBody.idempotency_key}`, "GET", undefined, host);
  check(response.status === 200 && isDeepStrictEqual(response.data.receipt, firstReceipt), "original receipt stays immutable after chapter advancement and fork");
} catch {
  // Avoid including network exception text, raw server responses or credentials.
  report.failures.push(`Failed during ${phase}; see the last completed named check.`);
} finally {
  for (const account of accounts) {
    let erased = false;
    // Keep the credential in memory for one bounded reconciliation if DELETE's
    // response is lost. A partially deleting identity still permits DELETE;
    // GET alone returning 401 does not establish that all room cleanup finished.
    for (let attempt = 0; attempt < 2 && !erased; attempt++) {
      let deleted, revoked;
      try { deleted = await api("/v1/identity", "DELETE", undefined, account); } catch { /* Reconcile below. */ }
      try { revoked = await api("/v1/identity", "GET", undefined, account); } catch { /* Bounded next attempt. */ }
      erased = (deleted?.status === 200 || (attempt === 1 && deleted?.status === 401)) && revoked?.status === 401;
    }
    report.cleanup.push(erased ? "synthetic identity erased and credential revoked" : "cleanup incomplete after bounded reconciliation");
  }
}
report.checked_at = new Date().toISOString();
console.log(JSON.stringify(report, null, 2));
if (report.failures.length || report.cleanup.some(item => item !== "synthetic identity erased and credential revoked")) process.exitCode = 1;
