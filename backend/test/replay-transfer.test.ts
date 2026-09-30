import { env } from "cloudflare:workers";
import { reset, runInDurableObject, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { encode } from "jpeg-js";
import worker from "../src/index";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import type { RoomSnapshotV2 } from "../src/v2/room";
import { validateRoomV2 } from "../src/v2/snapshot";
import { checkedRestore, type ReplayArchive, type ReplayTransfer } from "../src/v2/replay-transfer";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";

const H = "H".repeat(22), G = "G".repeat(22), R = "R".repeat(22), I = "AB".repeat(10), SOURCE = "f".repeat(40);
const key = () => crypto.randomUUID();
const stub = () => env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
type Stub = ReturnType<typeof stub>;
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
async function turn(room: Stub, state: RoomSnapshotV2, owner: string, recording: unknown, checkpoint?: unknown) {
  const request = { base_revision: state.revision, branch: state.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) };
  return { ...value(await room.commit(owner, request)), request };
}
async function complete(room = stub(), host = H, guest = G, roomId = R) {
  value(await room.initialize(roomId, host, I));
  let state = value(await room.join(guest, I));
  const receipts = [];
  for (const [owner, recording, checkpoint] of [[host, firstA, undefined], [guest, firstB, middle], [guest, secondA, undefined], [host, secondB, final]] as const) {
    const accepted = await turn(room, state, owner, recording, checkpoint); state = accepted.room; receipts.push(accepted.receipt);
  }
  return { room, state, receipts };
}
function acknowledgement(manifest: { epoch: number; archive_hash: string }) { return { schema_version: 1, epoch: manifest.epoch, archive_hash: manifest.archive_hash }; }
async function compact(room: Stub) {
  const offered = value(await room.replayTransfer(H));
  const ack = acknowledgement(offered.manifest);
  value(await room.acknowledgeReplayTransfer(H, ack)); value(await room.acknowledgeReplayTransfer(G, ack));
  return { offered, ack, restore: { ...ack, archive: offered.archive } };
}
async function photo(room: Stub) {
  const bytes = new Uint8Array(encode({ data: new Uint8Array(8 * 8 * 4).fill(127), width: 8, height: 8 }, 45).data);
  const jpeg_base64 = btoa(String.fromCharCode(...bytes));
  const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(v => v.toString(16).padStart(2, "0")).join("");
  const request = { idempotency_key: key(), recording_hash: firstA.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, jpeg_base64, sha256 };
  const accepted = value(await room.updatePhoto(H, "t0-0-a", request));
  return { request, accepted, ack: { recording_hash: firstA.recording_hash, photo_revision: 1, sha256 } };
}
afterEach(async () => { await reset(); });

describe("completed replay transfer", () => {
  it("preserves old clients and one-member ACK, then removes only coordinates after two exact durable claims", async () => {
    const { room, state, receipts } = await complete(), picture = await photo(room);
    const reaction = value(await room.react(G, "p0-0", { idempotency_key: key(), a_hash: firstA.recording_hash, b_hash: firstB.recording_hash, expected_reaction_revision: 0, reaction: "love" }));
    const oldArchive = value(await room.exportSnapshot(SOURCE));
    const offered = value(await room.replayTransfer(H));
    expect(offered.archive?.turns).toHaveLength(4); expect(offered.archive?.pairs).toHaveLength(2);
    expect(offered.archive?.room).not.toHaveProperty("invite_code");
    expect(offered.manifest.archive_hash).toBe(await digest(canonicalJson(offered.archive)));
    const ack = acknowledgement(offered.manifest);
    value(await room.acknowledgeReplayTransfer(H, ack)); value(await room.acknowledgeReplayTransfer(H, ack));
    expect(value(await room.snapshot(G))).toMatchObject({ checkpoint: state.checkpoint });
    expect(value(await room.operation(H, receipts[0].idempotency_key)).receipt).toEqual(receipts[0]);
    expect(await room.acknowledgeReplayTransfer(G, { ...ack, epoch: ack.epoch + 1 })).toMatchObject({ ok: false, code: "stale_replay_ack" });
    expect(await room.acknowledgeReplayTransfer("X".repeat(22), ack)).toMatchObject({ ok: false, status: 404 });
    const finished = value(await room.acknowledgeReplayTransfer(G, ack));
    expect(finished).toMatchObject({ transferred: true, acked_player_ids: [H, G] });
    expect(value(await room.acknowledgeReplayTransfer(H, ack))).toEqual(finished);
    expect(await room.snapshot(H)).toEqual({ ok: false, status: 410, code: "replay_transferred" });
    expect(await room.redo(H)).toMatchObject({ ok: false, status: 410, code: "replay_transferred" });
    expect(await room.join(G, I)).toMatchObject({ ok: false, status: 410, code: "replay_transferred" });
    expect(await room.initialize(R, H, I)).toMatchObject({ ok: false, status: 410, code: "replay_transferred" });
    expect(await room.friendInvite(H, G)).toMatchObject({ ok: false, status: 410, code: "replay_transferred" });
    expect(await room.friendInvite(H, "X".repeat(22))).toMatchObject({ ok: false, status: 404 });
    expect(await room.pairRecording(G, "p0-0")).toMatchObject({ ok: false, status: 410 });
    expect(value(await room.replayTransferOperation(H, receipts[0].idempotency_key)).receipt).toEqual(receipts[0]);
    expect(value(await room.photo(H, "t0-0-a")).jpeg_base64).toBe(picture.request.jpeg_base64);
    expect(value(await room.photoOperation(H, picture.request.idempotency_key))).toEqual(picture.accepted);
    expect(value(await room.reactionOperation(G, reaction.receipt.idempotency_key))).toEqual(reaction);
    expect(value(await room.safetyMembers(H))).toEqual({ host_id: H, guest_id: G });
    await runInDurableObject(room, (_, ctx) => {
      const stored = JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data);
      expect(stored).not.toHaveProperty("checkpoint");
      for (const row of ctx.storage.sql.exec<{ data: string }>("SELECT data FROM turns")) expect(Object.keys(JSON.parse(row.data))).toEqual(["recording_hash"]);
      expect(ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM operations").one().n).toBe(4);
    });
    const oldTarget = stub(); value(await oldTarget.restoreSnapshot(oldArchive, R)); expect(value(await oldTarget.snapshot(H))).toEqual(state);
  });

  it("exports every retired pair and orphan A, restores exact gameplay, and never reuses old ACKs", async () => {
    const { room, state } = await complete();
    let current = value(await room.fork(H, { base_revision: state.revision, branch: state.branch, stage_index: 1, idempotency_key: key() })).room;
    current = (await turn(room, current, G, secondA)).room; // Accepted orphan on branch 1.
    current = value(await room.fork(H, { base_revision: current.revision, branch: current.branch, stage_index: 1, idempotency_key: key() })).room;
    current = (await turn(room, current, G, secondA)).room;
    current = (await turn(room, current, H, secondB, final)).room;
    const { offered, ack, restore } = await compact(room);
    expect(offered.archive?.turns.map(t => t.turn_id)).toContain("t1-1-a");
    expect(offered.archive?.pairs.map(p => p.pair_id)).toEqual(["p0-0", "p0-1", "p2-1"]);
    const bad = structuredClone(restore); bad.archive!.turns[0].recording.duration_ticks++;
    expect(await room.restoreReplayTransfer(H, bad)).toMatchObject({ ok: false, code: "replay_archive_mismatch" });
    const restored = value(await room.restoreReplayTransfer(H, restore));
    expect(restored.transfer.manifest.epoch).toBe(ack.epoch + 1); expect(restored.transfer.acked_player_ids).toEqual([]);
    expect(value(await room.restoreReplayTransfer(G, restore))).toEqual(restored);
    expect(value(await room.snapshot(H))).toEqual(current);
    expect(value(await room.replayTransfer(H)).archive).toEqual(offered.archive);
    expect(await room.acknowledgeReplayTransfer(G, ack)).toMatchObject({ ok: false, code: "stale_replay_ack" });
    const request = { base_revision: current.revision, branch: current.branch, stage_index: 0, idempotency_key: key() };
    const forked = value(await room.fork(H, request));
    expect(value(await room.operation(H, request.idempotency_key)).receipt).toEqual(forked.receipt);
    expect(value(await room.fork(H, request))).toEqual(forked);
    expect(await room.restoreReplayTransfer(H, restore)).toMatchObject({ ok: false, code: "stale_replay_restore" });
  });

  it("holds stale completed ACKs after a fork and leaves unfinished rooms untouched", async () => {
    const { room, state } = await complete();
    const offer = value(await room.replayTransfer(H)), ack = acknowledgement(offer.manifest);
    value(await room.acknowledgeReplayTransfer(H, ack));
    const forked = value(await room.fork(H, { base_revision: state.revision, branch: state.branch, stage_index: 0, idempotency_key: key() }));
    expect(await room.acknowledgeReplayTransfer(G, ack)).toMatchObject({ ok: false, code: "stale_replay_ack" });
    expect(await room.replayTransfer(G)).toMatchObject({ ok: false, code: "replay_not_complete" });
    expect(value(await room.snapshot(H))).toEqual(forked.room);
    const saved = value(await room.exportSnapshot(SOURCE)), target = stub(); value(await target.restoreSnapshot(saved, R));
    expect(value(await target.snapshot(H))).toEqual(forked.room);
  });

  it("retains photo deletion and retry receipts through compaction/restore without resurrecting pixels", async () => {
    const { room } = await complete(), picture = await photo(room);
    const { restore } = await compact(room);
    // Coordinate ACKs do not substitute for either photo delivery ACK.
    value(await room.acknowledgePhoto(H, "t0-0-a", picture.ack));
    expect(value(await room.photo(G, "t0-0-a")).jpeg_base64).toBe(picture.request.jpeg_base64);
    value(await room.acknowledgePhoto(G, "t0-0-a", picture.ack));
    expect(await room.photo(H, "t0-0-a")).toMatchObject({ ok: false, code: "photo_payload_delivered" });
    const deletion = { idempotency_key: key(), recording_hash: firstA.recording_hash, expected_photo_revision: 1, expected_photo_hash: picture.request.sha256 };
    const deleted = value(await room.updatePhoto(H, "t0-0-a", deletion, true));
    value(await room.restoreReplayTransfer(G, restore));
    expect(value(await room.photo(H, "t0-0-a"))).toMatchObject({ photo: { sha256: null, photo_revision: 2 }, jpeg_base64: null });
    expect(value(await room.photoOperation(H, deletion.idempotency_key))).toEqual(deleted);
    expect(value(await room.updatePhoto(H, "t0-0-a", deletion, true))).toEqual(deleted);
  });

  it("rejects oversized restore structure before hashing without changing archived room or receipts", async () => {
    const { room, receipts } = await complete(), { ack, restore } = await compact(room);
    const before = JSON.parse(value(await room.exportSnapshot(SOURCE))).payload.tables;
    let nested: unknown = null;
    for (let index = 0; index < 64; index++) nested = { child: nested };
    expect(await room.restoreReplayTransfer(H, { ...ack, archive: { nested } })).toEqual({ ok: false, status: 413, code: "structure_too_large" });
    // The wide form exercises the node admission without a recursive or wide
    // per-node traversal stack. It stays below the separate 16MiB byte cap.
    await expect(checkedRestore({ ...ack, archive: { nodes: new Array(2_000_000).fill(null) } })).rejects.toMatchObject({ status: 413, code: "structure_too_large" });
    expect(JSON.parse(value(await room.exportSnapshot(SOURCE))).payload.tables).toEqual(before);
    expect(value(await room.replayTransferOperation(H, receipts[0].idempotency_key)).receipt).toEqual(receipts[0]);
    value(await room.restoreReplayTransfer(H, restore));
    expect(value(await room.snapshot(H)).active_role).toBe("complete");
  });

  it("round-trips a compact archive across eviction and rejects incomplete ACK or receipt tampering", async () => {
    const { room, receipts } = await complete(); await photo(room); await compact(room);
    const archive = value(await room.exportSnapshot(SOURCE)), parsed = JSON.parse(archive);
    expect(parsed.payload).toMatchObject({ format_version: 10, database_schema_version: 8, summary: { state: "transferred" } });
    const target = stub(); value(await target.restoreSnapshot(archive, R)); await evictDurableObject(target);
    expect(await target.snapshot(H)).toMatchObject({ ok: false, code: "replay_transferred" });
    expect(value(await target.replayTransferOperation(H, receipts[0].idempotency_key)).receipt).toEqual(receipts[0]);
    for (const kind of ["ack", "receipt", "turn", "photo"] as const) {
      const bad = JSON.parse(archive);
      const table = bad.payload.tables.find((t: { name: string }) => t.name === ({ ack: "replay_transfer", receipt: "operations", turn: "turns", photo: "photos" }[kind]));
      const field = kind === "receipt" ? "receipt" : "data", raw = JSON.parse(table.rows[0][field]);
      if (kind === "ack") raw.acked_player_ids = [H];
      if (kind === "receipt") raw.recording_hash = "0".repeat(64);
      if (kind === "turn") raw.recording_hash = "0".repeat(64);
      if (kind === "photo") raw.jpeg_base64 = null;
      table.rows[0][field] = JSON.stringify(raw); bad.checksum.value = await digest(canonicalJson(bad.payload));
      await expect(validateRoomV2(canonicalJson(bad), R)).rejects.toBeDefined();
    }
    value(await room.eraseForPlayer(G));
    const deleted = JSON.parse(value(await room.exportSnapshot(SOURCE)));
    expect(deleted.payload.summary.state).toBe("deleted");
    expect(deleted.payload.tables.every((t: { name: string; rows: unknown[] }) => t.name === "room" || t.rows.length === 0)).toBe(true);
  });
});

type Account = { player_id: string; device_token: string };
let ip = 0;
async function call(path: string, method = "GET", owner?: Account, body?: unknown, enabled = false) {
  const configured = { ...env, V2_ROOMS_ENABLED: "true", REPLAY_TRANSFER_ENABLED: enabled ? "true" : "false" } as unknown as Env;
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.19." + ++ip,
    ...(owner ? { "X-Player-Id": owner.player_id, Authorization: "Bearer " + owner.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
describe("replay transfer HTTP compatibility", () => {
  it("keeps ACK disabled by default and preserves unrelated lobby rooms and archived receipt recovery", async () => {
    const host = await (await call("/v1/identity", "POST", undefined, {})).json<Account>();
    const guest = await (await call("/v1/identity", "POST", undefined, {})).json<Account>();
    const room = env.ROOMS_V2.getByName(R), { receipts } = await complete(room, host.player_id, guest.player_id);
    value(await env.PLAYERS.getByName(host.player_id).addRoom({ room_id: R, invite_code: I, host: true, api_version: 2 }));
    const otherId = "Q".repeat(22), other = env.ROOMS_V2.getByName(otherId); value(await other.initialize(otherId, host.player_id, "CD".repeat(10)));
    value(await env.PLAYERS.getByName(host.player_id).addRoom({ room_id: otherId, invite_code: "CD".repeat(10), host: true, api_version: 2 }));
    const base = `/v2/rooms/${R}/replay-transfer`;
    expect((await call(base, "GET", host)).status).toBe(503);
    expect((await call(base + "/manifest", "GET", host)).status).toBe(503);
    await runInDurableObject(room, (_, ctx) => {
      expect(ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE name='replay_transfer'").toArray()).toEqual([]);
    });
    const offered = await call(base, "GET", host, undefined, true); expect(offered.status).toBe(200);
    const offer = await offered.json<ReplayTransfer & { archive: ReplayArchive | null }>();
    const ack = acknowledgement(offer.manifest);
    expect((await call(base + "/ack", "POST", host, ack)).status).toBe(503);
    expect((await call(base + "/ack", "POST", host, ack, true)).status).toBe(200);
    expect((await call(base + "/ack", "POST", guest, ack, true)).status).toBe(200);
    expect((await call(base + "/manifest", "GET", host)).status).toBe(200);
    const listing = await call("/v2/rooms", "GET", host); expect(listing.status).toBe(200);
    expect((await listing.json<{ rooms: { room_id: string }[] }>()).rooms.map(r => r.room_id)).toEqual([otherId]);
    expect((await env.PLAYERS.getByName(host.player_id).listRooms()).map(r => r.room_id)).toContain(R);
    const operation = await call(base + "/operations/" + receipts[0].idempotency_key, "GET", host);
    expect(operation.status).toBe(200); expect(await operation.json()).toMatchObject({ receipt: receipts[0], transfer: { transferred: true } });
    expect((await call(base + "/restore", "POST", host, { ...ack, archive: offer.archive })).status).toBe(200);
  });
});
