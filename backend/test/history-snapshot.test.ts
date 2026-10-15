import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import type { HistoryView } from "../src/v2/history-room";
import { CHAINS, GUEST, HOST, ROOM, fork, newRoom, open, play, playA, value, type Room } from "./history-chains";

afterEach(async () => { await reset(); });
const SOURCE = "e".repeat(40), relay = CHAINS[0], tide = CHAINS[3];
async function view(room: Room, player = HOST): Promise<HistoryView> { return value(await room.history(player, 1)); }
async function offload(room: Room, position: number) {
  const link = (await view(room)).attempts[position].link;
  value(await room.acknowledgeHistory(HOST, position, { schema_version: 1, link }, 1));
  return value(await room.acknowledgeHistory(GUEST, position, { schema_version: 1, link }, 1));
}
async function copy(room: Room): Promise<{ archive: string; target: Room }> {
  const archive = value(await room.exportSnapshot(SOURCE)), target = newRoom();
  value(await target.restoreSnapshot(archive, ROOM));
  return { archive, target };
}
type Archive = { payload: { format_version: number; database_schema_version: number; summary: unknown; tables: { name: string; rows: Record<string, string | number>[] }[] }; checksum: { algorithm: string; value: string } };
async function tampered(archive: string, change: (tables: Archive["payload"]["tables"]) => void): Promise<string> {
  const parsed = JSON.parse(archive) as Archive;
  change(parsed.payload.tables);
  parsed.checksum.value = await digest(canonicalJson(parsed.payload));
  return canonicalJson(parsed);
}
const table = (tables: Archive["payload"]["tables"], name: string) => tables.find(t => t.name === name)!.rows;

describe("operator snapshots of rooms with offloaded attempts", () => {
  it("exports and imports a room in play with stubbed and held attempts, and the copy still restores from bytes", async () => {
    const room = newRoom();
    let state = await play(room, await open(room, relay), relay, 0);
    state = await fork(room, state, 1);                       // attempt 0 finished; p0-0 stays live
    state = await play(room, state, relay, 1);
    state = await fork(room, state, 0);                       // attempt 1 finished
    state = await playA(room, state, relay.stages[0]);        // live open first turn
    const bytes = value(await room.historyAttempt(GUEST, 0, 1));
    await offload(room, 0);
    const { archive, target } = await copy(room);
    const parsed = JSON.parse(archive) as Archive;
    expect([parsed.payload.format_version, parsed.payload.database_schema_version]).toEqual([11, 9]);
    expect(parsed.payload.summary).toEqual({ state: "active", revision: state.revision, branch: 2 });
    expect(value(await target.snapshot(HOST))).toEqual(value(await room.snapshot(HOST)));
    expect(await view(target)).toEqual(await view(room));
    expect(value(await target.historyAttempt(HOST, 1, 1))).toEqual(value(await room.historyAttempt(HOST, 1, 1)));
    expect((value(await target.uploadHistory(GUEST, 0, bytes, 1))).attempts[0].state).toBe("held");
    expect(value(await target.collection(HOST))).toEqual(value(await room.collection(HOST)));

    // A changed stub, a stub where the live lineage reads, or a changed chain record are refused.
    const stubbedTurn = await tampered(archive, tables => { const row = table(tables, "turns").find(r => r.turn_id === "t0-1-a")!; row.data = JSON.stringify({ recording_hash: "a".repeat(64) }); });
    expect(await newRoom().restoreSnapshot(stubbedTurn, ROOM)).toMatchObject({ ok: false });
    const liveStub = await tampered(archive, tables => { const row = table(tables, "turns").find(r => r.turn_id === "t2-0-a")!; row.data = JSON.stringify({ recording_hash: JSON.parse(String(row.data)).recording_hash }); });
    expect(await newRoom().restoreSnapshot(liveStub, ROOM)).toMatchObject({ ok: false });
    const chain = await tampered(archive, tables => { const row = table(tables, "history_attempts")[1]; const data = JSON.parse(String(row.data)); data.digest = "b".repeat(64); row.data = JSON.stringify(data); });
    expect(await newRoom().restoreSnapshot(chain, ROOM)).toMatchObject({ ok: false, code: "history_chain_mismatch" });
    const heldStub = await tampered(archive, tables => { const row = table(tables, "pairs").find(r => r.pair_id === "p1-1")!; const data = JSON.parse(String(row.data));
      row.data = JSON.stringify({ pair_id: "p1-1", branch: 1, stage_index: 1, a: { recording_hash: data.a.recording_hash }, b: { recording_hash: data.b.recording_hash }, checkpoint: { checkpoint_hash: data.checkpoint.checkpoint_hash } }); });
    expect(await newRoom().restoreSnapshot(heldStub, ROOM)).toMatchObject({ ok: false });
  });

  it("exports and imports a finished room whose last attempt left, and the copy comes back from its bytes", async () => {
    const room = newRoom();
    await play(room, await open(room, tide), tide, 0);
    const bytes = value(await room.historyAttempt(HOST, 0, 1)), before = value(await room.snapshot(GUEST));
    await offload(room, 0);
    const { archive, target } = await copy(room);
    expect((JSON.parse(archive) as Archive).payload.summary).toEqual({ state: "transferred", revision: before.revision, branch: 0 });
    expect(await target.snapshot(GUEST)).toMatchObject({ ok: false, code: "replay_transferred" });
    value(await target.uploadHistory(HOST, 0, bytes, 1));
    expect(value(await target.snapshot(GUEST))).toEqual(before);
  });

  it("exports a room replay transfer v1 compacted after attempt history stored its chain, and the chain survives v1 restore", async () => {
    const room = newRoom();
    await play(room, await open(room, relay), relay, 0);
    const before = await view(room), offered = value(await room.replayTransfer(HOST));
    const ack = { schema_version: 1, epoch: offered.manifest.epoch, archive_hash: offered.manifest.archive_hash };
    value(await room.acknowledgeReplayTransfer(HOST, ack)); value(await room.acknowledgeReplayTransfer(GUEST, ack));
    expect((await view(room)).mode).toBe("v1_transferred");
    const { target } = await copy(room);
    value(await target.restoreReplayTransfer(GUEST, { ...ack, archive: offered.archive }));
    expect(await view(target)).toEqual(before);
  });

  it("still imports format 10, and builds the same chain lazily as one built attempt by attempt", async () => {
    const plain = newRoom();
    await play(plain, await open(plain, relay), relay, 0);
    const format10 = value(await plain.exportSnapshot(SOURCE));
    expect((JSON.parse(format10) as Archive).payload.format_version).toBeLessThan(11);
    expect(await newRoom().restoreSnapshot(format10, ROOM)).toMatchObject({ ok: true });
    const eager = newRoom(), lazy = newRoom();
    let a = await open(eager, relay), b = await open(lazy, relay);
    for (let i = 0; i < 5; i++) {
      a = await fork(eager, await play(eager, a, relay, a.stage_index), i % 2); await view(eager);
      b = await fork(lazy, await play(lazy, b, relay, b.stage_index), i % 2);
    }
    expect((await view(lazy)).attempts).toEqual((await view(eager)).attempts);
    expect((await view(lazy)).attempts).toHaveLength(5);
  });
});
