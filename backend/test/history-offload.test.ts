import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { encode } from "jpeg-js";
import { canonicalJson } from "../src/protocol";
import type { HistoryView } from "../src/v2/history-room";
import { sleepingLighthouseV2 } from "../src/v2/protocol-lighthouse";
import { turnOfTheTide } from "../src/v2/protocol-journey";
import { CHAINS, GUEST, HOST, fork, newRoom, open, owner, play, value, type Chain, type Room } from "./history-chains";
import type { RoomSnapshotV2 } from "../src/v2/room";
import { acceptTerms } from "./terms";

afterEach(async () => { await reset(); });
const relay = CHAINS[0], tide = CHAINS[3], lighthouse = CHAINS[4];
async function view(room: Room, player: string, support: 0 | 1 = 1): Promise<HistoryView> { return value(await room.history(player, support)); }
async function ack(room: Room, player: string, position: number, support: 0 | 1 = 1) {
  const link = (await view(room, player, support)).attempts[position].link;
  return value(await room.acknowledgeHistory(player, position, { schema_version: 1, link }, support));
}
async function offload(room: Room, position: number) { await ack(room, HOST, position); return ack(room, GUEST, position); }
type Rows = { turns: Record<string, string>; pairs: Record<string, string>; operations: number; photos: string[]; reactions: string[] };
const rows = (room: Room) => runInDurableObject(room, (_, ctx): Rows => ({
  turns: Object.fromEntries(ctx.storage.sql.exec<{ turn_id: string; data: string }>("SELECT turn_id,data FROM turns").toArray().map(r => [r.turn_id, canonicalJson(JSON.parse(r.data))])),
  pairs: Object.fromEntries(ctx.storage.sql.exec<{ pair_id: string; data: string }>("SELECT pair_id,data FROM pairs").toArray().map(r => [r.pair_id, canonicalJson(JSON.parse(r.data))])),
  operations: ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM operations").one().n,
  photos: ctx.storage.sql.exec<{ data: string }>("SELECT data FROM photos").toArray().map(r => r.data),
  reactions: ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE name='pair_reactions'").toArray().length ? ctx.storage.sql.exec<{ data: string }>("SELECT data FROM pair_reactions").toArray().map(r => r.data) : []
}));
const databaseSize = (room: Room) => runInDurableObject(room, (_, ctx) => ctx.storage.sql.databaseSize);
const isStub = (data: string) => !data.includes("stage_id") && !data.includes("\"a\":{\"a");
async function photo(room: Room, turnId: string, recording: Record<string, any>) {
  const bytes = new Uint8Array(encode({ data: new Uint8Array(8 * 8 * 4).fill(127), width: 8, height: 8 }, 45).data);
  const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(v => v.toString(16).padStart(2, "0")).join("");
  await acceptTerms(owner(recording));
  return value(await room.updatePhoto(owner(recording), turnId, { idempotency_key: crypto.randomUUID(), recording_hash: recording.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, jpeg_base64: btoa(String.fromCharCode(...bytes)), sha256 }));
}
/** `attempts` finished attempts, each played through and forked back to `forkTo`, offloading each when asked. */
async function attempts(chain: Chain, count: number, offloadEach: boolean): Promise<{ room: Room; state: RoomSnapshotV2; error: string | null }> {
  const room = newRoom();
  let state = await open(room, chain);
  for (let i = 0; i < count; i++) {
    state = await play(room, state, chain, 0);
    const forked = await room.fork(HOST, { base_revision: state.revision, branch: state.branch, stage_index: 0, idempotency_key: crypto.randomUUID() });
    if (!forked.ok) return { room, state, error: `${i + 1} ${forked.code}` };
    state = forked.value.room;
    if (offloadEach) await offload(room, i);
  }
  return { room, state, error: null };
}

describe("offloading finished attempts", () => {
  it("offloads only after both members ACK with support, stubs only rows nothing live reads, and keeps media working", async () => {
    const room = newRoom();
    let state = await play(room, await open(room, relay), relay, 0);
    const picture = await photo(room, "t0-1-a", relay.stages[1].a);
    const reaction = value(await room.react(GUEST, "p0-1", { idempotency_key: crypto.randomUUID(), a_hash: relay.stages[1].a.recording_hash, b_hash: relay.stages[1].b.recording_hash, expected_reaction_revision: 0, reaction: "love" }));
    state = await fork(room, state, 1);
    const before = await rows(room), collection = value(await room.collection(HOST)), sizeBefore = await databaseSize(room);
    expect(await room.acknowledgeHistory(HOST, 1, { schema_version: 1, link: "0".repeat(64) }, 1)).toMatchObject({ ok: false, code: "history_not_found" });
    await ack(room, HOST, 0);
    await ack(room, GUEST, 0, 0); // an older build on the guest's side: both ACKed, nothing leaves
    expect((await view(room, HOST)).attempts[0]).toMatchObject({ state: "held", acked_by_you: true, partner_acked: true });
    expect(await rows(room)).toEqual(before);
    expect((await ack(room, GUEST, 0)).attempts[0]).toMatchObject({ state: "offloaded", acked_by_you: false, partner_acked: false });
    const after = await rows(room);
    console.log("DATABASE SIZE relay offload", sizeBefore, "->", await databaseSize(room));
    expect(Object.keys(after.turns)).toEqual(Object.keys(before.turns));
    for (const id of ["t0-0-a", "t0-0-b"]) expect(after.turns[id]).toBe(before.turns[id]);
    for (const id of ["t0-1-a", "t0-1-b"]) expect(after.turns[id]).toBe(canonicalJson({ recording_hash: JSON.parse(before.turns[id]).recording_hash }));
    expect(after.pairs["p0-0"]).toBe(before.pairs["p0-0"]);
    expect(JSON.parse(after.pairs["p0-1"])).toEqual({ pair_id: "p0-1", branch: 0, stage_index: 1, a: { recording_hash: relay.stages[1].a.recording_hash }, b: { recording_hash: relay.stages[1].b.recording_hash }, checkpoint: { checkpoint_hash: relay.stages[1].checkpoint.checkpoint_hash } });
    expect([after.operations, after.photos, after.reactions]).toEqual([before.operations, before.photos, before.reactions]);
    expect(value(await room.collection(HOST))).toEqual(collection);
    expect(await room.pairRecording(GUEST, "p0-1")).toEqual({ ok: false, status: 410, code: "history_offloaded" });
    expect(value(await room.pairRecording(GUEST, "p0-0")).pair_id).toBe("p0-0");
    expect(value(await room.photo(GUEST, "t0-1-a")).jpeg_base64).toBe(JSON.parse(before.photos[0]).jpeg_base64);
    expect(value(await room.reactions(HOST, "p0-1"))).toEqual(value(await room.reactions(HOST, "p0-1")));
    expect(value(await room.reactionOperation(GUEST, reaction.receipt.idempotency_key))).toEqual(reaction);
    expect(value(await room.photoOperation(owner(relay.stages[1].a), picture.receipt.idempotency_key))).toEqual(picture);
    expect(value(await room.acknowledgePhoto(GUEST, "t0-1-a", { recording_hash: relay.stages[1].a.recording_hash, photo_revision: 1, sha256: picture.photo!.sha256 }))).toBeTruthy();
    expect(await room.replayTransfer(HOST)).toMatchObject({ ok: false, code: "history_offload_active" });
    // The live lineage lets go of p0-0 when the room forks back to the start.
    state = await fork(room, state, 0);
    expect(isStub((await rows(room)).pairs["p0-0"])).toBe(true);
    expect((await rows(room)).turns["t0-0-a"]).toBe(canonicalJson({ recording_hash: relay.stages[0].a.recording_hash }));
  });

  it("restores an offloaded attempt from its bytes exactly, and a friend's phone can ask for it", async () => {
    const room = newRoom();
    let state = await play(room, await open(room, relay), relay, 0);
    state = await fork(room, state, 0);
    state = await play(room, state, relay, 0, 1);
    const before = await rows(room), collection = value(await room.collection(GUEST));
    const bytes = value(await room.historyAttempt(GUEST, 0, 1));
    await offload(room, 0);
    expect(await room.historyAttempt(GUEST, 0, 1)).toMatchObject({ ok: false, status: 410, code: "history_offloaded" });
    expect(await room.uploadHistory(GUEST, 0, bytes.slice(0, -2), 1)).toMatchObject({ ok: false, code: "history_mismatch" });
    expect((value(await room.wantHistory(GUEST, 0, { schema_version: 1 }, 1))).attempts[0]).toMatchObject({ state: "offloaded" });
    expect((await view(room, HOST)).attempts[0]).toMatchObject({ wanted_by_partner: true });
    const restored = value(await room.uploadHistory(HOST, 0, bytes, 1));
    expect(restored.attempts[0]).toMatchObject({ state: "held", acked_by_you: true, partner_acked: false, wanted_by_partner: false });
    expect(await rows(room)).toEqual(before);
    expect(value(await room.collection(GUEST))).toEqual(collection);
    expect(value(await room.pairRecording(HOST, "p0-1")).checkpoint.checkpoint_hash).toBe(relay.stages[1].checkpoint.checkpoint_hash);
    expect(value(await room.historyAttempt(GUEST, 0, 1))).toEqual(bytes);
    expect((await ack(room, GUEST, 0)).attempts[0].state).toBe("offloaded");
    state = await play(room, state, relay, 1);
    expect(state.stage_index).toBe(2);
  });

  it("counts only attempts held in full against a chapter's branch limit", async () => {
    expect(turnOfTheTide.max_branches).toBe(7); expect(sleepingLighthouseV2.max_branches).toBe(7);
    expect((await attempts(tide, 7, false)).error).toBe("7 room_history_full");
    expect((await attempts(lighthouse, 7, false)).error).toBe("7 room_history_full");
    const tideOffload = await attempts(tide, 31, true);
    expect(tideOffload.error).toBeNull();
    const last = await play(tideOffload.room, tideOffload.state, tide, 0);
    expect([last.branch, last.stage_index]).toEqual([31, 2]);
    expect(await tideOffload.room.fork(HOST, { base_revision: last.revision, branch: last.branch, stage_index: 0, idempotency_key: crypto.randomUUID() })).toMatchObject({ ok: false, code: "room_history_full" });
    const light = await attempts(lighthouse, 9, true);
    expect(light.error).toBeNull();
    const tenth = await play(light.room, light.state, lighthouse, 0);
    expect([tenth.branch, tenth.stage_index]).toEqual([9, 6]);
    const forked = await fork(light.room, tenth, 0);
    // Turn rows still count stubs: 128 turn rows end the eleventh attempt part way.
    await expect(play(light.room, forked, lighthouse, 0)).rejects.toThrow("room_history_full");
    const sizes = await runInDurableObject(light.room, (_, ctx) => ctx.storage.sql.databaseSize);
    console.log("DATABASE SIZE lighthouse after 10 attempts with 9 offloaded", sizes);
  }, 120_000);
});
