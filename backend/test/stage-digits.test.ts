import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, expect, it } from "vitest";
import { encode } from "jpeg-js";
import worker from "../src/index";
import { withConfig } from "./config";
import { RELAY_KEY } from "../src/v2/protocol";
import { TERMS_VERSION } from "../src/public-policy";

// Stage digits may reach 7 for chapters with more stages. On a two-stage room
// every request that names stage 2 or later keeps the exact status and code it
// had before, for members, strangers and missing rooms. Safety reports and
// account photo transfers name turns too and keep their outcomes as well.
type Account = { player_id: string; device_token: string };
let requestNo = 0;
const flags = { RELAY_PHOTOS_ENABLED: "true" };
async function call(path: string, method = "GET", account?: Account, body?: BodyInit, headers: Record<string, string> = {}): Promise<Response> {
  const configured: Env = withConfig({ ...env, ...flags });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.16." + (++requestNo % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers }, body }), configured);
}
async function account(): Promise<Account> { const r = await call("/v1/identity", "POST", undefined, "{}"); expect(r.status).toBe(201); return r.json<Account>(); }
async function outcome(r: Response): Promise<string> { const text = await r.text(); let code = ""; try { code = JSON.parse(text)?.error?.code ?? "ok"; } catch { code = "?"; } return `${r.status} ${code}`; }
afterEach(async () => { await reset(); });

it("keeps every published stage-digit and body-size outcome on a two-stage room", async () => {
  const host = await account(), guest = await account(), stranger = await account();
  const created = await call("/v2/rooms", "POST", host, JSON.stringify({ ...RELAY_KEY, idempotency_key: crypto.randomUUID() })); expect(created.status).toBe(200);
  const room = await created.json<{ room_id: string; invite_code: string }>();
  expect((await call("/v2/rooms/join", "POST", guest, JSON.stringify({ invite_code: room.invite_code, supported_simulation_versions: [2, 4, 5, 6, 7, 8, 9] }))).status).toBe(200);
  const rows: Record<string, string> = {};
  const id = room.room_id, missing = "z".repeat(22);
  for (const [who, actor] of [["host", host], ["stranger", stranger]] as const) {
    for (const target of [id, missing]) {
      const tag = `${who}${target === id ? "" : ":missing"}`;
      for (const [method, item] of [["GET", "pairs/p0-1"], ["GET", "pairs/p0-2"], ["GET", "pairs/p0-9"], ["GET", "photos/t0-2-a"], ["GET", "photos/t0-1-a"], ["POST", "photos/t0-3-b"],
        ["GET", "reactions/p0-2"], ["POST", "reactions/p0-4"], ["GET", "photos/t0-2-a/delivery"], ["POST", "photos/t0-5-b/ack"]] as const)
        rows[`${tag} ${method} ${item}`] = await outcome(await call(`/v2/rooms/${target}/${item}`, method, actor, method === "POST" ? "{}" : undefined));
    }
  }
  const big = JSON.stringify({ pad: "x".repeat(340000) }), length = { "Content-Length": String(big.length) };
  const stream = () => new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode(big)); c.close(); } });
  rows["host POST turns oversized (content-length)"] = await outcome(await call(`/v2/rooms/${id}/turns`, "POST", host, big, length));
  rows["stranger POST turns oversized (content-length)"] = await outcome(await call(`/v2/rooms/${id}/turns`, "POST", stranger, big, length));
  rows["host:missing POST turns oversized (content-length)"] = await outcome(await call(`/v2/rooms/${missing}/turns`, "POST", host, big, length));
  rows["host POST turns oversized (string body)"] = await outcome(await call(`/v2/rooms/${id}/turns`, "POST", host, big));
  rows["host POST turns oversized (stream, no length)"] = await outcome(await call(`/v2/rooms/${id}/turns`, "POST", host, stream()));
  rows["host POST turns small junk"] = await outcome(await call(`/v2/rooms/${id}/turns`, "POST", host, "{}"));
  rows["host POST fork oversized (content-length)"] = await outcome(await call(`/v2/rooms/${id}/fork`, "POST", host, big, length));
  expect(rows).toEqual(EXPECTED);
});

const EXPECTED: Record<string, string> = {
    "host GET pairs/p0-1": "404 pair_not_found",
    "host GET pairs/p0-2": "400 invalid_field",
    "host GET pairs/p0-9": "400 invalid_field",
    "host GET photos/t0-2-a": "400 invalid_photo_turn",
    "host GET photos/t0-1-a": "404 turn_not_found",
    "host POST photos/t0-3-b": "400 invalid_photo_turn",
    "host GET reactions/p0-2": "400 invalid_reaction_pair",
    "host POST reactions/p0-4": "400 invalid_reaction_pair",
    "host GET photos/t0-2-a/delivery": "404 not_found",
    "host POST photos/t0-5-b/ack": "404 not_found",
    "host:missing GET pairs/p0-1": "404 room_not_found",
    "host:missing GET pairs/p0-2": "404 room_not_found",
    "host:missing GET pairs/p0-9": "404 room_not_found",
    "host:missing GET photos/t0-2-a": "404 room_not_found",
    "host:missing GET photos/t0-1-a": "404 room_not_found",
    "host:missing POST photos/t0-3-b": "404 room_not_found",
    "host:missing GET reactions/p0-2": "404 room_not_found",
    "host:missing POST reactions/p0-4": "404 room_not_found",
    // A room id the caller holds no link to is refused before routing, so these say room_not_found, not not_found.
    "host:missing GET photos/t0-2-a/delivery": "404 room_not_found",
    "host:missing POST photos/t0-5-b/ack": "404 room_not_found",
    "stranger GET pairs/p0-1": "404 room_not_found",
    "stranger GET pairs/p0-2": "404 room_not_found",
    "stranger GET pairs/p0-9": "404 room_not_found",
    "stranger GET photos/t0-2-a": "404 room_not_found",
    "stranger GET photos/t0-1-a": "404 room_not_found",
    "stranger POST photos/t0-3-b": "404 room_not_found",
    "stranger GET reactions/p0-2": "404 room_not_found",
    "stranger POST reactions/p0-4": "404 room_not_found",
    "stranger GET photos/t0-2-a/delivery": "404 room_not_found",
    "stranger POST photos/t0-5-b/ack": "404 room_not_found",
    "stranger:missing GET pairs/p0-1": "404 room_not_found",
    "stranger:missing GET pairs/p0-2": "404 room_not_found",
    "stranger:missing GET pairs/p0-9": "404 room_not_found",
    "stranger:missing GET photos/t0-2-a": "404 room_not_found",
    "stranger:missing GET photos/t0-1-a": "404 room_not_found",
    "stranger:missing POST photos/t0-3-b": "404 room_not_found",
    "stranger:missing GET reactions/p0-2": "404 room_not_found",
    "stranger:missing POST reactions/p0-4": "404 room_not_found",
    "stranger:missing GET photos/t0-2-a/delivery": "404 room_not_found",
    "stranger:missing POST photos/t0-5-b/ack": "404 room_not_found",
    "host POST turns oversized (content-length)": "413 body_too_large",
    "stranger POST turns oversized (content-length)": "404 room_not_found",
    "host:missing POST turns oversized (content-length)": "404 room_not_found",
    "host POST turns oversized (string body)": "413 body_too_large",
    "host POST turns oversized (stream, no length)": "413 body_too_large",
    "host POST turns small junk": "400 invalid_object",
    "host POST fork oversized (content-length)": "413 body_too_large"
  };

it("keeps every published safety-report and photo-transfer stage-digit outcome on a two-stage room", async () => {
  const on = { ...flags, PHOTO_TRANSFER_ENABLED: "true" };
  const send = (path: string, method: string, account: Account | undefined, body: unknown, overrides: Record<string, string> = {}) => {
    const configured: Env = withConfig({ ...env, ...on, ...overrides });
    return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.18." + (++requestNo % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: JSON.stringify(body) }), configured);
  };
  const host = await account(), guest = await account(), stranger = await account();
  for (const a of [host, guest, stranger]) expect((await send("/v1/safety/terms", "POST", a, { schema_version: 1, terms_version: TERMS_VERSION })).status).toBe(200);
  const created = await send("/v2/rooms", "POST", host, { ...RELAY_KEY, idempotency_key: crypto.randomUUID() }); expect(created.status).toBe(200);
  const room = await created.json<{ room_id: string; invite_code: string }>();
  expect((await send("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, supported_simulation_versions: [2, 4, 5, 6, 7, 8, 9] })).status).toBe(200);
  const rows: Record<string, string> = {};
  const missing = "z".repeat(22), sha = "a".repeat(64);
  const report = (roomId: string, turn: string, extra: Record<string, unknown> = {}) => ({ schema_version: 1, idempotency_key: crypto.randomUUID(), room_family: "relay", room_id: roomId, reason: "privacy", photo: { turn_id: turn, photo_revision: 1, sha256: sha }, ...extra });
  for (const [who, actor] of [["guest", guest], ["stranger", stranger]] as const) {
    for (const target of [room.room_id, missing]) {
      const tag = `${who}${target === missing ? ":missing" : ""}`;
      for (const turn of ["t0-1-a", "t0-2-a", "t0-3-b", "t0-5-a", "t0-7-b", "t0-8-a", "t9-2-a"])
        rows[`report ${tag} ${turn}`] = await outcome(await send("/v1/safety/report", "POST", actor, report(target, turn)));
    }
  }
  rows["report guest legacy t0-2-a"] = await outcome(await send("/v1/safety/report", "POST", guest, report(room.room_id, "t0-2-a", { room_family: "legacy" })));
  rows["report guest legacy t0-1-a"] = await outcome(await send("/v1/safety/report", "POST", guest, report(room.room_id, "t0-1-a", { room_family: "legacy" })));
  rows["report guest t0-2-a bad sha"] = await outcome(await send("/v1/safety/report", "POST", guest, report(room.room_id, "t0-2-a", { photo: { turn_id: "t0-2-a", photo_revision: 1, sha256: "x" } })));
  rows["report guest t0-2-a revision 0"] = await outcome(await send("/v1/safety/report", "POST", guest, report(room.room_id, "t0-2-a", { photo: { turn_id: "t0-2-a", photo_revision: 0, sha256: sha } })));
  rows["report guest t0-2-a bad room id"] = await outcome(await send("/v1/safety/report", "POST", guest, report("short", "t0-2-a")));
  rows["report guest t0-2-a bad reason"] = await outcome(await send("/v1/safety/report", "POST", guest, report(room.room_id, "t0-2-a", { reason: "nope" })));
  const reused = crypto.randomUUID();
  rows["report guest null photo (key K)"] = await outcome(await send("/v1/safety/report", "POST", guest, { ...report(room.room_id, "t0-0-a"), idempotency_key: reused, photo: null }));
  rows["report guest t0-2-a reused key K"] = await outcome(await send("/v1/safety/report", "POST", guest, report(room.room_id, "t0-2-a", { idempotency_key: reused })));
  rows["report guest t0-1-a reused key K"] = await outcome(await send("/v1/safety/report", "POST", guest, report(room.room_id, "t0-1-a", { idempotency_key: reused })));
  rows["report no auth t0-2-a"] = await outcome(await send("/v1/safety/report", "POST", undefined, report(room.room_id, "t0-2-a")));
  const bytes = new Uint8Array(encode({ data: new Uint8Array(8 * 8 * 4).fill(127), width: 8, height: 8 }, 45).data);
  const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(v => v.toString(16).padStart(2, "0")).join("");
  let entryNo = 0;
  const entry = (owner: Account, roomId: string, turn: string, extra: Record<string, unknown> = {}) => ({ entry_id: (++entryNo).toString(16).padStart(64, "0"), room_id: roomId, turn_id: turn, recording_hash: "a".repeat(64), photo_revision: 0, photo_owner: owner.player_id,
    local_only: true, sha256, width: 8, height: 8, byte_length: bytes.length, created_at: new Date().toISOString(), jpeg_base64: btoa(String.fromCharCode(...bytes)), deleted: false, ...extra });
  for (const [who, owner] of [["host", host], ["stranger", stranger]] as const) {
    const session = crypto.randomUUID();
    expect((await send("/v1/photo-transfer/sessions", "POST", owner, { schema_version: 1, idempotency_key: session })).status).toBe(200);
    const upload = (entries: unknown[]) => send(`/v1/photo-transfer/${session}/entries`, "POST", owner, { schema_version: 1, idempotency_key: crypto.randomUUID(), entries });
    for (const target of [room.room_id, missing]) {
      const tag = `${who}${target === missing ? ":missing" : ""}`;
      for (const turn of ["t0-1-a", "t0-2-a", "t0-5-b", "t0-7-a", "t0-8-a"]) rows[`transfer ${tag} ${turn}`] = await outcome(await upload([entry(owner, target, turn)]));
      rows[`transfer ${tag} [t0-0-a, t0-2-a]`] = await outcome(await upload([entry(owner, target, "t0-0-a"), entry(owner, target, "t0-2-a")]));
      rows[`transfer ${tag} [t0-2-a, bad date]`] = await outcome(await upload([entry(owner, target, "t0-2-a"), entry(owner, target, "t0-0-a", { created_at: "x" })]));
      rows[`transfer ${tag} [bad date, t0-2-a]`] = await outcome(await upload([entry(owner, target, "t0-0-a", { created_at: "x" }), entry(owner, target, "t0-2-a")]));
      rows[`transfer ${tag} t0-2-a bad room`] = await outcome(await upload([entry(owner, "bad", "t0-2-a")]));
      rows[`transfer ${tag} t0-2-a bad hash`] = await outcome(await upload([entry(owner, target, "t0-2-a", { recording_hash: "x" })]));
      rows[`transfer ${tag} t0-2-a bad sha`] = await outcome(await upload([entry(owner, target, "t0-2-a", { sha256: "0".repeat(64) })]));
    }
  }
  rows["transfer host disabled t0-2-a"] = await outcome(await send(`/v1/photo-transfer/${crypto.randomUUID()}/entries`, "POST", host, { schema_version: 1, idempotency_key: crypto.randomUUID(), entries: [entry(host, room.room_id, "t0-2-a")] }, { PHOTO_TRANSFER_ENABLED: "false" }));
  expect(rows).toEqual(EXPECTED_SAFETY_TRANSFER);
});

const EXPECTED_SAFETY_TRANSFER: Record<string, string> = {
    "report guest t0-1-a": "404 turn_not_found",
    "report guest t0-2-a": "400 invalid_field",
    "report guest t0-3-b": "400 invalid_field",
    "report guest t0-5-a": "400 invalid_field",
    "report guest t0-7-b": "400 invalid_field",
    "report guest t0-8-a": "400 invalid_field",
    "report guest t9-2-a": "400 invalid_field",
    "report guest:missing t0-1-a": "404 room_not_found",
    "report guest:missing t0-2-a": "400 invalid_field",
    "report guest:missing t0-3-b": "400 invalid_field",
    "report guest:missing t0-5-a": "400 invalid_field",
    "report guest:missing t0-7-b": "400 invalid_field",
    "report guest:missing t0-8-a": "400 invalid_field",
    "report guest:missing t9-2-a": "400 invalid_field",
    "report stranger t0-1-a": "404 room_not_found",
    "report stranger t0-2-a": "400 invalid_field",
    "report stranger t0-3-b": "400 invalid_field",
    "report stranger t0-5-a": "400 invalid_field",
    "report stranger t0-7-b": "400 invalid_field",
    "report stranger t0-8-a": "400 invalid_field",
    "report stranger t9-2-a": "400 invalid_field",
    "report stranger:missing t0-1-a": "404 room_not_found",
    "report stranger:missing t0-2-a": "400 invalid_field",
    "report stranger:missing t0-3-b": "400 invalid_field",
    "report stranger:missing t0-5-a": "400 invalid_field",
    "report stranger:missing t0-7-b": "400 invalid_field",
    "report stranger:missing t0-8-a": "400 invalid_field",
    "report stranger:missing t9-2-a": "400 invalid_field",
    "report guest legacy t0-2-a": "400 invalid_field",
    "report guest legacy t0-1-a": "400 invalid_safety_request",
    "report guest t0-2-a bad sha": "400 invalid_field",
    "report guest t0-2-a revision 0": "400 invalid_field",
    "report guest t0-2-a bad room id": "400 invalid_field",
    "report guest t0-2-a bad reason": "400 invalid_safety_request",
    "report guest null photo (key K)": "200 ok",
    "report guest t0-2-a reused key K": "400 invalid_field",
    "report guest t0-1-a reused key K": "409 idempotency_key_reused",
    "report no auth t0-2-a": "401 invalid_auth",
    "transfer host t0-1-a": "200 ok",
    "transfer host t0-2-a": "400 invalid_field",
    "transfer host t0-5-b": "400 invalid_field",
    "transfer host t0-7-a": "400 invalid_field",
    "transfer host t0-8-a": "400 invalid_field",
    "transfer host [t0-0-a, t0-2-a]": "400 invalid_field",
    "transfer host [t0-2-a, bad date]": "400 invalid_field",
    "transfer host [bad date, t0-2-a]": "400 invalid_transfer_date",
    "transfer host t0-2-a bad room": "400 invalid_field",
    "transfer host t0-2-a bad hash": "400 invalid_field",
    "transfer host t0-2-a bad sha": "400 invalid_field",
    "transfer host:missing t0-1-a": "200 ok",
    "transfer host:missing t0-2-a": "400 invalid_field",
    "transfer host:missing t0-5-b": "400 invalid_field",
    "transfer host:missing t0-7-a": "400 invalid_field",
    "transfer host:missing t0-8-a": "400 invalid_field",
    "transfer host:missing [t0-0-a, t0-2-a]": "400 invalid_field",
    "transfer host:missing [t0-2-a, bad date]": "400 invalid_field",
    "transfer host:missing [bad date, t0-2-a]": "400 invalid_transfer_date",
    "transfer host:missing t0-2-a bad room": "400 invalid_field",
    "transfer host:missing t0-2-a bad hash": "400 invalid_field",
    "transfer host:missing t0-2-a bad sha": "400 invalid_field",
    "transfer stranger t0-1-a": "200 ok",
    "transfer stranger t0-2-a": "400 invalid_field",
    "transfer stranger t0-5-b": "400 invalid_field",
    "transfer stranger t0-7-a": "400 invalid_field",
    "transfer stranger t0-8-a": "400 invalid_field",
    "transfer stranger [t0-0-a, t0-2-a]": "400 invalid_field",
    "transfer stranger [t0-2-a, bad date]": "400 invalid_field",
    "transfer stranger [bad date, t0-2-a]": "400 invalid_transfer_date",
    "transfer stranger t0-2-a bad room": "400 invalid_field",
    "transfer stranger t0-2-a bad hash": "400 invalid_field",
    "transfer stranger t0-2-a bad sha": "400 invalid_field",
    "transfer stranger:missing t0-1-a": "200 ok",
    "transfer stranger:missing t0-2-a": "400 invalid_field",
    "transfer stranger:missing t0-5-b": "400 invalid_field",
    "transfer stranger:missing t0-7-a": "400 invalid_field",
    "transfer stranger:missing t0-8-a": "400 invalid_field",
    "transfer stranger:missing [t0-0-a, t0-2-a]": "400 invalid_field",
    "transfer stranger:missing [t0-2-a, bad date]": "400 invalid_field",
    "transfer stranger:missing [bad date, t0-2-a]": "400 invalid_transfer_date",
    "transfer stranger:missing t0-2-a bad room": "400 invalid_field",
    "transfer stranger:missing t0-2-a bad hash": "400 invalid_field",
    "transfer stranger:missing t0-2-a bad sha": "400 invalid_field",
    "transfer host disabled t0-2-a": "503 photo_transfer_disabled"
  };
