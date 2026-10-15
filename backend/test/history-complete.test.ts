import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import type { HistoryView } from "../src/v2/history-room";
import { CHAINS, GUEST, HOST, INVITE, fork, newRoom, open, play, value, type Room } from "./history-chains";

afterEach(async () => { await reset(); });
const relay = CHAINS[0], lighthouse = CHAINS[4];
async function view(room: Room, player: string): Promise<HistoryView> { return value(await room.history(player, 1)); }
async function offload(room: Room, position: number) {
  const link = (await view(room, HOST)).attempts[position].link;
  value(await room.acknowledgeHistory(HOST, position, { schema_version: 1, link }, 1));
  return value(await room.acknowledgeHistory(GUEST, position, { schema_version: 1, link }, 1));
}
const stored = (room: Room) => runInDurableObject(room, (_, ctx) => ({
  room: JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data),
  full: [...ctx.storage.sql.exec<{ id: string; data: string }>("SELECT turn_id AS id,data FROM turns UNION ALL SELECT pair_id AS id,data FROM pairs")]
    .filter(row => row.data.includes("stage_id") || row.data.includes("\"proof\"")).map(row => row.id).sort()
}));

describe("a finished room's last attempt", () => {
  it("leaves with the room's other attempts, and comes back from its bytes before a fork", async () => {
    const room = newRoom();
    let state = await play(room, await open(room, lighthouse), lighthouse, 0, 3);
    state = await fork(room, state, 2);                             // attempt 0 stops at stage 3; p0-0 and p0-1 stay in the lineage
    state = await play(room, state, lighthouse, 2);                 // attempt 1 finishes the chapter
    await offload(room, 0);
    expect((await stored(room)).full).toEqual(["p0-0", "p0-1", "p1-2", "p1-3", "p1-4", "p1-5", "t0-0-a", "t0-0-b", "t0-1-a", "t0-1-b",
      "t1-2-a", "t1-2-b", "t1-3-a", "t1-3-b", "t1-4-a", "t1-4-b", "t1-5-a", "t1-5-b"]);
    const bytes = value(await room.historyAttempt(GUEST, 1, 1)), lobby = value(await room.lobbySnapshot(HOST)), guestView = value(await room.snapshot(GUEST));
    expect((await offload(room, 1)).attempts.map(a => a.state)).toEqual(["offloaded", "offloaded"]);
    const after = await stored(room);
    expect(after.full).toEqual([]);
    expect(after.room).toMatchObject({ replay_transfer_version: 2, checkpoint_hash: state.checkpoint.checkpoint_hash });
    expect(after.room).not.toHaveProperty("checkpoint");
    expect(await room.snapshot(HOST)).toEqual({ ok: false, status: 410, code: "replay_transferred" });
    expect(await room.redo(GUEST)).toMatchObject({ ok: false, status: 410, code: "replay_transferred" });
    expect(await room.collection(HOST)).toMatchObject({ ok: false, status: 410 });
    expect(await room.fork(HOST, { base_revision: state.revision, branch: state.branch, stage_index: 0, idempotency_key: crypto.randomUUID() })).toMatchObject({ ok: false, status: 404 });
    expect(await room.memberRoomState(GUEST)).toBe("finished");
    expect(await room.resolvesInvitation(INVITE)).toBe(true);
    const { checkpoint: _checkpoint, ...metadata } = lobby as typeof lobby & { checkpoint: unknown }; void _checkpoint;
    expect(value(await room.lobbySnapshot(GUEST))).toMatchObject({ room_id: metadata.room_id, replay_transfer_version: 1, active_role: "complete", checkpoint_hash: state.checkpoint.checkpoint_hash });
    expect(await room.replayTransfer(HOST)).toMatchObject({ ok: false, code: "history_offload_active" });
    expect((await view(room, GUEST)).attempts.map(a => a.state)).toEqual(["offloaded", "offloaded"]);
    // Sending the final attempt back restores the room exactly, with every row its lineage reads.
    expect(await room.uploadHistory(HOST, 0, bytes, 1)).toMatchObject({ ok: false, code: "history_mismatch" });
    expect((value(await room.uploadHistory(HOST, 1, bytes, 1))).attempts[1]).toMatchObject({ state: "held", acked_by_you: true });
    expect(value(await room.snapshot(GUEST))).toEqual(guestView);
    expect((await stored(room)).full).toEqual(["p0-0", "p0-1", "p1-2", "p1-3", "p1-4", "p1-5", "t0-0-a", "t0-0-b", "t0-1-a", "t0-1-b",
      "t1-2-a", "t1-2-b", "t1-3-a", "t1-3-b", "t1-4-a", "t1-4-b", "t1-5-a", "t1-5-b"]);
    const forked = await fork(room, value(await room.snapshot(HOST)), 1);
    expect(forked).toMatchObject({ branch: 2, stage_index: 1, completed_pair_ids: ["p0-0"] });
    expect((await stored(room)).full).toEqual(["p0-0", "p1-2", "p1-3", "p1-4", "p1-5", "t0-0-a", "t0-0-b", "t1-2-a", "t1-2-b", "t1-3-a", "t1-3-b", "t1-4-a", "t1-4-b", "t1-5-a", "t1-5-b"]);
    // The partner still has attempt 1, so its ACK sends it away again; the room is in play now, so no tombstone.
    expect((await offload(room, 1)).attempts[1].state).toBe("offloaded");
    expect((await stored(room)).full).toEqual(["p0-0", "t0-0-a", "t0-0-b"]);
    expect(value(await room.snapshot(HOST))).toMatchObject({ branch: 2, stage_index: 1 });
  }, 60_000);

  it("restores a two-stage room the way v1 did and forks it", async () => {
    const room = newRoom();
    await play(room, await open(room, relay), relay, 0);
    const bytes = value(await room.historyAttempt(HOST, 0, 1)), state = value(await room.snapshot(HOST));
    await offload(room, 0);
    expect(await room.snapshot(HOST)).toMatchObject({ ok: false, code: "replay_transferred" });
    value(await room.uploadHistory(GUEST, 0, bytes, 1));
    expect(value(await room.snapshot(HOST))).toEqual(state);
    expect(await fork(room, state, 0)).toMatchObject({ branch: 1, stage_index: 0 });
  });
});
