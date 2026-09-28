// Retained Story protocol coverage; production withdrawal is tested without
// this test-only substitution in campaign-production.test.ts.
vi.mock("../src/v2/campaign-production", () => ({
  campaignProductionEnabled: () => true, requireCampaignProduction: () => {}
}));

import { env } from "cloudflare:workers";
import { evictDurableObject, reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import type { RedoRequest } from "../src/redo-control";
import { RELAY_KEY } from "../src/v2/chapters";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import type { RoomV2Archive } from "../src/v2/snapshot";
import { initializeCampaignJoinSchema, initializeCampaignStorageSchema } from "../src/v2/storage-schema";
import comfort from "../../game/tests/fixtures/comfort8/recordings.json";

const host = "H".repeat(22), guest = "G".repeat(22), roomId = "R".repeat(22);
const invite = "A".repeat(20), sourceCommit = "8".repeat(40), relay = comfort.relay;
const room = () => env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
type Stub = ReturnType<typeof room>;
function value<T>(result: Outcome<T>): T { if (!result.ok) throw new Error(result.code); return result.value; }
const archive = (raw: string): RoomV2Archive => JSON.parse(raw) as RoomV2Archive;
async function exported(stub: Stub) { return value(await stub.exportSnapshot(sourceCommit)); }
async function submit(stub: Stub, state: RoomSnapshotV2, owner: string, recording: unknown, checkpoint?: unknown): Promise<MutationV2> {
  return value(await stub.commit(owner, { base_revision: state.revision, branch: state.branch,
    idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) }));
}
async function runtime(stub: Stub) {
  return runInDurableObject(stub, async (_, ctx) => ctx.storage.sql.exec<{ id: number; data: string }>("SELECT id,data FROM redo_control ORDER BY id").toArray());
}
async function putRuntime(stub: Stub, request: RedoRequest) {
  await runInDurableObject(stub, async (_, ctx) => { ctx.storage.sql.exec("INSERT OR REPLACE INTO redo_control VALUES(1,?)", JSON.stringify(request)); });
}
async function retainedRequest(): Promise<RedoRequest> {
  const source = { room_id: roomId, revision: 4, branch: 0, stage_index: 1,
    a_hash: relay.pairs[1].a.recording_hash, first_player_id: guest, second_player_id: host };
  return { request_id: await digest(canonicalJson(source)), source, status: "pending" };
}
afterEach(async () => { await reset(); });

describe("Story and comfort RoomV2 merge", () => {
  it("retains rules8, Garden role reversal and completed history through redo receipt recovery and portable restore", async () => {
    const stub = room();
    expect(value(await stub.initialize(roomId, host, invite, RELAY_KEY, 8)).simulation_version).toBe(8);
    let state = value(await stub.join(guest, invite, [2, 4, 5, 6, 7, 8]));
    state = (await submit(stub, state, host, relay.pairs[0].a)).room;
    state = (await submit(stub, state, guest, relay.pairs[0].b, relay.checkpoints[1])).room;
    const completed = value(await stub.pairRecording(host, "p0-0"));
    expect(completed).toMatchObject({ a: relay.pairs[0].a, b: relay.pairs[0].b, checkpoint: relay.checkpoints[1] });
    state = (await submit(stub, state, guest, relay.pairs[1].a)).room;
    const offered = value(await stub.redo(host));
    expect(offered.source).toMatchObject({ stage_index: 1, first_player_id: guest, second_player_id: host,
      a_hash: relay.pairs[1].a.recording_hash });
    const requested = value(await stub.redo(host, { action: "request", source: offered.source }));
    const body = { base_revision: state.revision, branch: state.branch, stage_index: 1,
      idempotency_key: crypto.randomUUID(), redo_request_id: requested.request!.request_id };
    // Ignore the accepted response; reconcile only by the saved operation key.
    value(await stub.fork(guest, body));
    await evictDurableObject(stub);
    const recovered = value(await stub.operation(guest, body.idempotency_key));
    expect(recovered.receipt).toMatchObject({ operation: "fork", request_hash: await digest(canonicalJson({ operation: "fork", ...body })),
      accepted_revision: state.revision + 1, branch: 1, stage_index: 1, checkpoint_hash: relay.checkpoints[1].checkpoint_hash });
    expect(recovered.room).toMatchObject({ simulation_version: 8, branch: 1, stage_index: 1, active_role: "a",
      active_player_id: guest, first_player_id: guest, a_turn_id: null, completed_pair_ids: ["p0-0"] });
    expect(recovered.room.checkpoint).toEqual(relay.checkpoints[1]);
    expect(value(await stub.fork(guest, body))).toEqual(recovered);
    expect(value(await stub.pairRecording(host, "p0-0"))).toEqual(completed);
    expect((await runtime(stub)).map(row => JSON.parse(row.data).status)).toEqual(["accepted"]);

    const raw = await exported(stub), before = archive(raw), target = room();
    expect(before.payload.tables.some(table => table.name === "redo_control")).toBe(false);
    // A stale local advisory is safe to clear during an otherwise empty restore.
    await putRuntime(target, requested.request!);
    expect(await target.restoreSnapshot(raw, roomId)).toMatchObject({ ok: true });
    expect(await runtime(target)).toEqual([]);
    await evictDurableObject(target);
    expect(value(await target.snapshot(guest))).toEqual(recovered.room);
    expect(value(await target.operation(guest, body.idempotency_key))).toEqual(recovered);
    expect(value(await target.pairRecording(host, "p0-0"))).toEqual(completed);
    expect(archive(await exported(target)).payload.tables).toEqual(before.payload.tables);
  });

  it.each([6, 7] as const)("keeps schema%s archives and terminal campaign boundaries with valid advisory runtime", async version => {
    const stub = room(), request = await retainedRequest();
    await runInDurableObject(stub, async (_, ctx) => {
      initializeCampaignStorageSchema(ctx.storage);
      if (version === 7) initializeCampaignJoinSchema(ctx.storage);
      ctx.storage.sql.exec("INSERT INTO room VALUES(1,?)", JSON.stringify({ deleted: true }));
      ctx.storage.sql.exec("INSERT INTO campaign_anchor VALUES(1,?)", JSON.stringify({ schema_version: 1, state: "deleted", campaign_room_id: roomId }));
      ctx.storage.sql.exec("INSERT INTO campaign_member VALUES(1,?)", JSON.stringify({ schema_version: 1, status: "deleted", campaign_room_id: roomId, room_id: roomId }));
    });
    const baseline = archive(await exported(stub));
    await putRuntime(stub, request);
    await evictDurableObject(stub);
    const raw = await exported(stub), current = archive(raw);
    expect(current.payload).toMatchObject({ database_schema_version: version, format_version: version === 7 ? 9 : 8,
      logical_id: roomId, summary: { state: "deleted", revision: null, branch: null } });
    expect(current.payload.tables).toEqual(baseline.payload.tables);
    expect(current.payload.tables.some(table => table.name === "redo_control")).toBe(false);
    expect(await stub.friendInvite(host, guest)).toMatchObject({ ok: false, status: 409, code: "campaign_social_unavailable" });
    for (const input of [undefined, { action: "request", source: request.source }]) {
      expect(await stub.redo(host, input)).toMatchObject({ ok: false, status: 409, code: "campaign_redo_unavailable" });
    }
    expect(await stub.fork(guest, { base_revision: 4, branch: 0, stage_index: 1,
      idempotency_key: crypto.randomUUID(), redo_request_id: request.request_id })).toMatchObject({ ok: false, status: 409, code: "campaign_redo_unavailable" });
    expect(await runtime(stub)).toEqual([{ id: 1, data: JSON.stringify(request) }]);
    const target = room();
    expect(await target.restoreSnapshot(raw, roomId)).toMatchObject({ ok: false, code: "campaign_restore_unsupported" });
    expect(archive(await exported(target)).payload.summary.state).toBe("empty");
    expect(await runtime(target)).toEqual([]);
    expect(archive(await exported(stub)).payload.tables).toEqual(baseline.payload.tables);
  });

  it("refuses ordinary restore and social access into a head-omitted schema7 target", async () => {
    const source = room(), target = room(), request = await retainedRequest();
    value(await source.initialize(roomId, host, invite, RELAY_KEY, 8));
    const raw = await exported(source);
    await runInDurableObject(target, async (_, ctx) => {
      initializeCampaignStorageSchema(ctx.storage); initializeCampaignJoinSchema(ctx.storage);
    });
    await putRuntime(target, request);
    expect(await target.restoreSnapshot(raw, roomId)).toMatchObject({ ok: false, code: "campaign_restore_unsupported" });
    expect(await target.friendInvite(host, guest)).toMatchObject({ ok: false, code: "campaign_social_unavailable" });
    expect(await target.redo(host)).toMatchObject({ ok: false, code: "campaign_redo_unavailable" });
    expect(await runtime(target)).toEqual([{ id: 1, data: JSON.stringify(request) }]);
    await runInDurableObject(target, async (_, ctx) => {
      expect(ctx.storage.sql.exec("SELECT id FROM room").toArray()).toEqual([]);
      expect(ctx.storage.sql.exec<{ schema_version: number }>("SELECT schema_version FROM metadata").one().schema_version).toBe(7);
    });
  });

  it("fails closed on malformed advisory rows in schema7 without changing campaign storage", async () => {
    const stub = room();
    await runInDurableObject(stub, async (_, ctx) => {
      initializeCampaignStorageSchema(ctx.storage); initializeCampaignJoinSchema(ctx.storage);
      ctx.storage.sql.exec("INSERT INTO redo_control VALUES(1,?)", '{"status":"pending"}');
    });
    const before = await runtime(stub);
    expect(await stub.exportSnapshot(sourceCommit)).toMatchObject({ ok: false, code: "unsupported_redo_state" });
    expect(await stub.redo(host)).toMatchObject({ ok: false, code: "campaign_redo_unavailable" });
    expect(await runtime(stub)).toEqual(before);
  });
});
