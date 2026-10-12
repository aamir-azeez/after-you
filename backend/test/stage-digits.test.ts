import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, expect, it } from "vitest";
import worker from "../src/index";
import { RELAY_KEY } from "../src/v2/protocol";

// Stage digits may reach 7 for chapters with more stages. On a two-stage room
// every request that names stage 2 or later keeps the exact status and code it
// had before, for members, strangers and missing rooms.
type Account = { player_id: string; device_token: string };
let requestNo = 0;
const flags = { V2_ROOMS_ENABLED: "true", RELAY_PHOTOS_ENABLED: "true", PRESET_REACTIONS_ENABLED: "true", PHOTO_DELIVERY_ENABLED: "true" };
async function call(path: string, method = "GET", account?: Account, body?: BodyInit, headers: Record<string, string> = {}): Promise<Response> {
  const configured: Env = { ...env }; Object.assign(configured, flags);
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
    "host:missing GET photos/t0-2-a/delivery": "404 not_found",
    "host:missing POST photos/t0-5-b/ack": "404 not_found",
    "stranger GET pairs/p0-1": "404 room_not_found",
    "stranger GET pairs/p0-2": "404 room_not_found",
    "stranger GET pairs/p0-9": "404 room_not_found",
    "stranger GET photos/t0-2-a": "404 room_not_found",
    "stranger GET photos/t0-1-a": "404 room_not_found",
    "stranger POST photos/t0-3-b": "404 room_not_found",
    "stranger GET reactions/p0-2": "404 room_not_found",
    "stranger POST reactions/p0-4": "404 room_not_found",
    "stranger GET photos/t0-2-a/delivery": "404 not_found",
    "stranger POST photos/t0-5-b/ack": "404 not_found",
    "stranger:missing GET pairs/p0-1": "404 room_not_found",
    "stranger:missing GET pairs/p0-2": "404 room_not_found",
    "stranger:missing GET pairs/p0-9": "404 room_not_found",
    "stranger:missing GET photos/t0-2-a": "404 room_not_found",
    "stranger:missing GET photos/t0-1-a": "404 room_not_found",
    "stranger:missing POST photos/t0-3-b": "404 room_not_found",
    "stranger:missing GET reactions/p0-2": "404 room_not_found",
    "stranger:missing POST reactions/p0-4": "404 room_not_found",
    "stranger:missing GET photos/t0-2-a/delivery": "404 not_found",
    "stranger:missing POST photos/t0-5-b/ack": "404 not_found",
    "host POST turns oversized (content-length)": "413 body_too_large",
    "stranger POST turns oversized (content-length)": "404 room_not_found",
    "host:missing POST turns oversized (content-length)": "404 room_not_found",
    "host POST turns oversized (string body)": "413 body_too_large",
    "host POST turns oversized (stream, no length)": "413 body_too_large",
    "host POST turns small junk": "400 invalid_object",
    "host POST fork oversized (content-length)": "413 body_too_large"
  };
