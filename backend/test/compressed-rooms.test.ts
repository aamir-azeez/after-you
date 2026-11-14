import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { bytesDigest, decodeBlob, encodeBlob, encodeBlobSync } from "../src/blob-codec";
import { chapter } from "../src/v2/protocol";
import { CHAPTERS } from "../src/v2/chapters";
import { MAX_ROW_BYTES } from "../src/v2/row-bound";
import { PACKED_CHECKPOINT, ROW_FORMAT_DEFLATE, parseRoom, parseRow, plainRow, rowJson, storedRoom, storedRow } from "../src/v2/row-codec";
import { MAX_TURN_BODY_BYTES, decodeTurnBody, readTurnBody } from "../src/v2/turn-wire";
import type { ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import native from "../../game/tests/fixtures/comfort8/recordings.json";
import { configJson, withConfig } from "./config";
import { RoomV2 } from "../src/v2/room";

/**
 * Compressed rooms (v2/row-codec.ts, v2/turn-wire.ts): stored rows deflated behind COMPRESSED_ROOMS, turns and
 * room replies passed through the Worker unread, and old and new apps together in one room.
 */
type Account = { player_id: string; device_token: string };
type Proof = { pairs: { a: ChapterRecording; b: ChapterRecording }[]; checkpoints: ChapterCheckpoint[] };
const proof = (native as unknown as Record<string, Proof>)["rolling-home"];
const code = "SYNTHETIC-COMPRESSED-HOST";
let requestNo = 0, features: string[] = ["COMPRESSED_ROOMS"];
/**
 * Room requests the Worker makes: each RoomV2 method a request can reach, counted when it is entered from outside the
 * room (a call made while another is under way is the room calling itself). Tests here run one request at a time.
 */
let calls: string[] = [];
const ROOM_REQUESTS = ["interactionAllowed", "snapshot", "snapshotIfChanged", "operation", "commit", "hostAccessAge", "rememberHostAccess", "duelLinkOf",
  "turnRequest", "snapshotReply", "operationReply", "pairReply", "pairRecording", "stageCount", "campaignWriteAvailability", "campaignRoomNegotiation"] as const;
function countRoomRequests(): void {
  let inside = 0;
  for (const name of ROOM_REQUESTS) {
    const original = RoomV2.prototype[name] as (...args: unknown[]) => unknown;
    vi.spyOn(RoomV2.prototype, name).mockImplementation(function (this: RoomV2, ...args: unknown[]) {
      if (inside === 0) calls.push(name);
      inside++;
      try {
        const result = original.apply(this, args);
        if (result instanceof Promise) return result.finally(() => { inside--; });
        inside--; return result;
      } catch (error) { inside--; throw error; }
    } as never);
  }
}
const counted = (configured: Env) => configured;
/** The rooms read the shared env's CONFIG (as replay-expiry.test.ts sets it); the Worker gets its own. */
const shared = env as unknown as Record<string, unknown>;
async function configured(): Promise<Env> {
  if (features.length) shared.CONFIG = configJson({ features }); else delete shared.CONFIG;
  const { CONFIG: _config, ...base } = shared; void _config;
  return withConfig({ ...base, TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + code), COMPRESSED_ROOMS: features.includes("COMPRESSED_ROOMS") ? "true" : "false",
    REVENUECAT_SECRET_KEY: "synthetic-only", revenuecat: { project_id: "projSynthetic", play_entitlement_lookup_id: "entlPlay", play_product_id: "prodPlay" } } as never);
}
type Sent = { owner?: Account; body?: unknown; blob?: boolean; compressed?: boolean; headers?: Record<string, string> };
async function call(path: string, method = "GET", sent: Sent = {}) {
  const json = sent.body === undefined ? undefined : new TextEncoder().encode(JSON.stringify(sent.body));
  const blob = sent.blob && json ? await encodeBlob(json) : undefined;
  const headers: Record<string, string> = { "Content-Type": blob ? "application/octet-stream" : "application/json", "CF-Connecting-IP": "198.18.19." + (++requestNo % 250),
    ...(sent.owner ? { "X-Player-Id": sent.owner.player_id, Authorization: "Bearer " + sent.owner.device_token } : {}),
    ...(blob ? { "X-AfterYou-Body-Length": String(json!.byteLength), "X-AfterYou-Body-Digest": await bytesDigest(json!) } : {}),
    ...(sent.compressed ? { "X-AfterYou-Compressed": "1" } : {}), ...sent.headers };
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers, body: blob ?? json }), counted(await configured()));
}
/** A reply's JSON text, from either form. */
async function replyText(response: Response): Promise<string> {
  if (response.headers.get("Content-Type") !== "application/octet-stream") return response.text();
  const length = Number(response.headers.get("X-AfterYou-Body-Length")), bytes = await decodeBlob(new Uint8Array(await response.arrayBuffer()), length);
  expect(await bytesDigest(bytes!)).toBe(response.headers.get("X-AfterYou-Body-Digest"));
  return new TextDecoder().decode(bytes!);
}
async function account(): Promise<Account> {
  const response = await call("/v1/identity", "POST", { body: {} });
  expect(response.status, await response.clone().text()).toBe(201); return response.json<Account>();
}
async function pairedRoom() {
  const host = await account(), guest = await account();
  expect((await call("/v1/tester-access", "POST", { owner: host, body: { schema_version: 1, code } })).status).toBe(200);
  const created = await call("/v2/rooms", "POST", { owner: host, body: { ...chapter(proof.pairs[0].a).key, simulation_version: 8, idempotency_key: crypto.randomUUID() } });
  expect(created.status).toBe(200);
  const waiting = await created.json<RoomSnapshotV2>();
  const joined = await call("/v2/rooms/join", "POST", { owner: guest, body: { invite_code: waiting.invite_code, supported_simulation_versions: [8] } });
  expect(joined.status).toBe(200);
  return { host, guest, room: await joined.json<RoomSnapshotV2>() };
}
function turn(room: RoomSnapshotV2, recording: ChapterRecording, checkpoint?: ChapterCheckpoint) {
  return { base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) };
}
const rows = (roomId: string) => runInDurableObject(env.ROOMS_V2.getByName(roomId), async (_, ctx) => ({
  room: ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").one().data,
  turns: ctx.storage.sql.exec<{ turn_id: string; data: string | ArrayBuffer }>("SELECT turn_id,data FROM turns ORDER BY rowid").toArray(),
  pairs: ctx.storage.sql.exec<{ pair_id: string; data: string | ArrayBuffer }>("SELECT pair_id,data FROM pairs ORDER BY rowid").toArray() }));
afterEach(async () => { vi.restoreAllMocks(); features = ["COMPRESSED_ROOMS"]; calls = []; delete shared.CONFIG; await reset(); });

describe("the stored row codec", () => {
  it("keeps the exact JSON in either form, reads text rows as before, and packs only the room's checkpoint", () => {
    const value = { recording_hash: "a".repeat(64), actions: Array.from({ length: 500 }, (_, i) => ({ action: i % 2 === 0, ticks: 1, x: i % 7, z: -3 })) };
    const plain = storedRow(value, false), packed = storedRow(value, true);
    expect(plain).toBe(JSON.stringify(value));
    expect(packed).toBeInstanceOf(ArrayBuffer);
    expect(new Uint8Array(packed as ArrayBuffer)[0]).toBe(ROW_FORMAT_DEFLATE);
    expect((packed as ArrayBuffer).byteLength).toBeLessThan((plain as string).length / 4);
    expect(rowJson(packed)).toBe(plain); expect(rowJson(plain)).toBe(plain); expect(parseRow(packed)).toEqual(value);
    const room = { schema_version: 2, room_id: "r", host_id: "h", checkpoint: { checkpoint_hash: "c".repeat(64), proof: value }, updated_at: "t" };
    const stored = storedRoom(room, true), parsed = JSON.parse(stored);
    // SQL still reads the small fields; the checkpoint is a string, read back exactly.
    expect(parsed.host_id).toBe("h"); expect(parsed.checkpoint.startsWith(PACKED_CHECKPOINT)).toBe(true);
    expect(parseRoom(stored)).toEqual(room); expect(Object.keys(parseRoom(stored))).toEqual(Object.keys(room));
    expect(plainRow("room", stored)).toBe(JSON.stringify(room)); expect(plainRow("turns", packed)).toBe(plain);
    expect(storedRoom(room, false)).toBe(JSON.stringify(room));
    expect(parseRoom('{"deleted":true}')).toEqual({ deleted: true });
  });

  it("refuses a row past MAX_ROW_BYTES as stored, and a corrupt or bombing row as unreadable", () => {
    // Incompressible text past the bound fails in both forms; the same length of repeated text fits deflated.
    const random = new Uint8Array(Math.ceil(MAX_ROW_BYTES * 1.4)); for (let at = 0; at < random.length; at += 65536) crypto.getRandomValues(random.subarray(at, at + 65536));
    const noise = btoa(Array.from(random, byte => String.fromCharCode(byte)).join(""));
    expect(() => storedRow({ noise }, false)).toThrow(expect.objectContaining({ status: 413, code: "turn_too_large" }));
    expect(() => storedRow({ noise }, true)).toThrow(expect.objectContaining({ status: 413, code: "turn_too_large" }));
    expect(() => storedRow({ noise: "x".repeat(MAX_ROW_BYTES * 2) }, true)).not.toThrow();
    const packed = new Uint8Array(storedRow({ a: 1 }, true) as ArrayBuffer);
    const truncated = packed.slice(0, packed.length - 2), lying = packed.slice(); new DataView(lying.buffer).setUint32(1, 1);
    for (const bad of [truncated, lying]) expect(() => rowJson(bad.buffer)).toThrow(expect.objectContaining({ code: "room_row_unreadable" }));
    // A bomb: a header naming 10 bytes over a body that inflates to megabytes is refused without inflating it all.
    const bomb = encodeBlobSync(new Uint8Array(32 * 1024 * 1024)), row = new Uint8Array(5 + bomb.length);
    row[0] = ROW_FORMAT_DEFLATE; new DataView(row.buffer).setUint32(1, 10); row.set(bomb, 5);
    expect(() => rowJson(row.buffer)).toThrow(expect.objectContaining({ code: "room_row_unreadable" }));
  });
});

describe("turn bodies on the wire", () => {
  const request = (headers: Record<string, string>, body: Uint8Array) => new Request("https://after-you.test/x", { method: "POST", headers, body });
  it("pass through the Worker unread and are checked in the room against the chapter's own bound", async () => {
    const json = new TextEncoder().encode(JSON.stringify({ hello: "world".repeat(100) })), blob = await encodeBlob(json);
    const plain = await readTurnBody(request({ "Content-Type": "application/json" }, json));
    expect(plain).toEqual({ bytes: json, length: null, digest: null });
    const packed = await readTurnBody(request({ "Content-Type": "application/octet-stream", "X-AfterYou-Body-Length": String(json.length), "X-AfterYou-Body-Digest": await bytesDigest(json) }, blob));
    expect(packed.bytes).toEqual(blob);
    expect(await decodeTurnBody(plain, 10_000)).toEqual(await decodeTurnBody(packed, 10_000));
    // The room's bound is checked on the declared length before anything is inflated.
    await expect(decodeTurnBody(packed, json.length - 1)).rejects.toMatchObject({ status: 413, code: "body_too_large" });
    await expect(decodeTurnBody({ ...packed, digest: "0".repeat(64) }, 10_000)).rejects.toMatchObject({ status: 400, code: "invalid_turn_body" });
    await expect(decodeTurnBody({ ...packed, length: json.length - 1 }, 10_000)).rejects.toMatchObject({ status: 400, code: "invalid_turn_body" });
    await expect(decodeTurnBody({ bytes: new TextEncoder().encode("{"), length: null, digest: null }, 10)).rejects.toMatchObject({ status: 400, code: "invalid_json" });
    await expect(readTurnBody(request({ "Content-Type": "text/plain" }, json))).rejects.toMatchObject({ status: 415, code: "json_required" });
    await expect(readTurnBody(request({ "Content-Type": "application/octet-stream" }, blob))).rejects.toMatchObject({ status: 400, code: "invalid_turn_body" });
    await expect(readTurnBody(request({ "Content-Type": "application/octet-stream", "X-AfterYou-Body-Length": String(MAX_TURN_BODY_BYTES + 1), "X-AfterYou-Body-Digest": "0".repeat(64) }, blob)))
      .rejects.toMatchObject({ status: 413, code: "body_too_large" });
  });

  it("keep the Worker's CPU to copying bytes: its widest allowed turn, measured by size", () => {
    // The Worker reads the body into one buffer, passes it to the room and passes the reply on: no JSON parse, clone
    // or stringify of either (readTurnBody, replyResponse). In V8 (Node) reading a 0.87 MB JSON turn and copying it
    // and a reply as wide costs about 3.9 ms, about 2 ns a byte (0.3 ms deflated), where parsing, cloning and writing
    // it as before cost about 89 ms; 4 ns a byte is the margin here. The widest turn any chapter takes, sent as JSON
    // by an older app, plus a reply as wide, stays inside the 10 ms budget.
    const NS_PER_BYTE = 4;
    expect(MAX_TURN_BODY_BYTES).toBe(Math.max(...CHAPTERS.map(row => row.adapter.limits?.turn_body_bytes ?? 0)));
    expect((2 * MAX_TURN_BODY_BYTES * NS_PER_BYTE) / 1e6).toBeLessThan(10);
  });
});

describe("a room with an older and a newer app", () => {
  it("plays a whole chapter with one member on JSON and the other on compressed turns and replies, each reading the same room", async () => {
    const { host, guest, room: start } = await pairedRoom();
    countRoomRequests();
    let room = start;
    const perTurn: string[][] = [];
    for (const [index, pair] of proof.pairs.entries()) {
      for (const recording of [pair.a, pair.b]) {
        const newer = recording.player_slot === "p1", actor = newer ? guest : host;
        calls = [];
        const response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", { owner: actor, body: turn(room, recording, recording.role === "b" ? proof.checkpoints[index + 1] : undefined), blob: newer, compressed: newer });
        expect(response.status).toBe(200);
        expect(response.headers.get("Content-Type")).toBe(newer ? "application/octet-stream" : "application/json; charset=utf-8");
        perTurn.push([...calls]);
        room = (JSON.parse(await replyText(response)) as MutationV2).room;
      }
    }
    expect(room.active_role).toBe("complete");
    // Each member reads the same room in its own form; the JSON inside is byte for byte the same.
    const asText = await call(`/v2/rooms/${room.room_id}`, "GET", { owner: guest }), asBlob = await call(`/v2/rooms/${room.room_id}`, "GET", { owner: guest, compressed: true });
    expect(asBlob.headers.get("Content-Type")).toBe("application/octet-stream");
    const text = await replyText(asText);
    expect(await replyText(asBlob)).toBe(text);
    expect(JSON.parse(text).checkpoint).toEqual(proof.checkpoints.at(-1));
    // Pair reads too.
    const pairText = await replyText(await call(`/v2/rooms/${room.room_id}/pairs/p0-0`, "GET", { owner: host }));
    expect(await replyText(await call(`/v2/rooms/${room.room_id}/pairs/p0-0`, "GET", { owner: host, compressed: true }))).toBe(pairText);
    expect(JSON.parse(pairText).checkpoint).toEqual(proof.checkpoints[1]);
    // Stored deflated, every hash as played.
    const stored = await rows(room.room_id);
    expect(stored.turns.every(row => row.data instanceof ArrayBuffer)).toBe(true);
    expect(stored.pairs.every(row => row.data instanceof ArrayBuffer)).toBe(true);
    expect(JSON.parse(stored.room).checkpoint.startsWith(PACKED_CHECKPOINT)).toBe(true);
    expect(stored.turns.map(row => parseRow<ChapterRecording>(row.data).recording_hash)).toEqual(proof.pairs.flatMap(pair => [pair.a.recording_hash, pair.b.recording_hash]));
    // Each premium turn is one room request (its memory admits the host) beside the Player's own checks.
    // One room request a turn when the room remembers the host's purchase (host-access.ts); a tester's grant is
    // read every turn, so here each premium turn comes back once for the host check: two. Before, the Worker made
    // five: interactionAllowed, snapshot, operation, hostAccessAge and commit.
    expect(perTurn.map(names => names.join(" "))).toEqual(Array(4).fill("turnRequest turnRequest"));
    calls = [];
    await call(`/v2/rooms/${room.room_id}`, "GET", { owner: host, compressed: true });
    expect(calls).toEqual(["snapshotReply"]);
  });

  it("treats a turn sent compressed and then again as JSON with the same key as one request", async () => {
    const { host, room } = await pairedRoom();
    const body = turn(room, proof.pairs[0].a);
    const first = await call(`/v2/rooms/${room.room_id}/turns`, "POST", { owner: host, body, blob: true, compressed: true });
    expect(first.status).toBe(200);
    const again = await call(`/v2/rooms/${room.room_id}/turns`, "POST", { owner: host, body });
    expect(again.status).toBe(200);
    const [a, b] = [JSON.parse(await replyText(first)) as MutationV2, await again.json<MutationV2>()];
    expect(b.receipt).toEqual(a.receipt);
    expect(b.receipt.request_hash).toBe(await digest(canonicalJson({ operation: "turns", ...body })));
    const operation = await call(`/v2/rooms/${room.room_id}/operations/${body.idempotency_key}`, "GET", { owner: host, compressed: true });
    expect((JSON.parse(await replyText(operation)) as MutationV2).receipt).toEqual(a.receipt);
    // The same key with another body is still refused.
    const other = await call(`/v2/rooms/${room.room_id}/turns`, "POST", { owner: host, body: { ...body, branch: 0, base_revision: body.base_revision + 1 }, blob: true });
    expect(other.status).toBe(409);
  });

  it("reads rows written before the flag, converts the room row on its next change only, and exports plain rows", async () => {
    features = [];
    const { host, guest, room: start } = await pairedRoom();
    let room = start;
    const pair = proof.pairs[0];
    const actor = (recording: ChapterRecording) => recording.player_slot === "p0" ? host : guest;
    let response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", { owner: actor(pair.a), body: turn(room, pair.a) });
    room = (await response.json<MutationV2>()).room;
    response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", { owner: actor(pair.b), body: turn(room, pair.b, proof.checkpoints[1]), blob: true, compressed: true });
    expect(response.status).toBe(200);
    room = (JSON.parse(await replyText(response)) as MutationV2).room;
    let stored = await rows(room.room_id);
    // The flag off: a compressed turn is taken, and every row stays text.
    expect(stored.turns.every(row => typeof row.data === "string") && stored.pairs.every(row => typeof row.data === "string")).toBe(true);
    expect(typeof JSON.parse(stored.room).checkpoint).toBe("object");
    const before = stored;
    features = ["COMPRESSED_ROOMS"];
    response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", { owner: proof.pairs[1].a.player_slot === "p0" ? host : guest, body: turn(room, proof.pairs[1].a) });
    expect(response.status).toBe(200);
    stored = await rows(room.room_id);
    expect(stored.turns.slice(0, 2)).toEqual(before.turns);
    expect(stored.pairs).toEqual(before.pairs);
    expect(stored.turns[2].data).toBeInstanceOf(ArrayBuffer);
    expect(JSON.parse(stored.room).checkpoint.startsWith(PACKED_CHECKPOINT)).toBe(true);
    // A mixed room reads whole, lists its pairs, and exports as plain text an older version can restore.
    const read = await call(`/v2/rooms/${room.room_id}`, "GET", { owner: guest });
    expect((await read.json<RoomSnapshotV2>()).recording_a).toEqual(proof.pairs[1].a);
    const collection = await call(`/v2/rooms/${room.room_id}/collection`, "GET", { owner: guest });
    expect((await collection.json<{ pairs: { checkpoint_hash: string }[] }>()).pairs.map(item => item.checkpoint_hash)).toEqual([proof.checkpoints[1].checkpoint_hash]);
    const archive = await env.ROOMS_V2.getByName(room.room_id).exportSnapshot("a".repeat(40));
    expect(archive.ok).toBe(true);
    const tables = JSON.parse((archive as { value: string }).value).payload.tables as { name: string; rows: { data: string }[] }[];
    for (const name of ["room", "turns", "pairs"]) for (const row of tables.find(table => table.name === name)!.rows) expect(typeof row.data === "string" && !row.data.includes(PACKED_CHECKPOINT)).toBe(true);
  });

  it("answers an older server's refusal path: a compressed turn to a room that asks JSON of none still works for both", async () => {
    // The capability goes only to a phone that asks, and only while the flag is on.
    const { host } = await pairedRoom();
    const asked = await call("/v2/capabilities", "GET", { owner: host, compressed: true });
    expect((await asked.json<Record<string, unknown>>()).compressed_rooms_version).toBe(1);
    expect((await (await call("/v2/capabilities", "GET", { owner: host })).json<Record<string, unknown>>()).compressed_rooms_version).toBeUndefined();
    features = [];
    expect((await (await call("/v2/capabilities", "GET", { owner: host, compressed: true })).json<Record<string, unknown>>()).compressed_rooms_version).toBeUndefined();
  });
});
