import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { LOOKS_HEADER } from "../src/pollen/looks-routes";
import { noteFullJourney } from "../src/pollen/wallet";
import { LOOKS_ROOM_TABLES } from "../src/storage-schema";
import { countingEnv, meterRows } from "./meter";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";
import { withConfig } from "./config";

// Looks in rooms: each member's own look rides into the room on calls already made, is kept per
// turn, is served only to members whose phone asks, and survives replay transfer. Synthetic ids only.
type Account = { player_id: string; device_token: string; recovery_code: string };
type Read = RoomSnapshotV2 & { partner_look?: Record<string, string>; turn_looks?: Record<string, Record<string, string>> };
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const ON = { features: ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_LOOKS"], POLLEN_SECRET: SECRET };
const OFF = { features: ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP"], POLLEN_SECRET: SECRET };
const ASK = { [LOOKS_HEADER]: "1" };
const DAY = 86_400_000;
const key = () => crypto.randomUUID();
let address = 0;

async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, unknown> = ON, headers: Record<string, string> = ASK, base: Env = env): Promise<Response> {
  const configured = withConfig({ ...base, ...vars }) as unknown as Env;
  return worker.fetch(new Request("https://looks.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.93." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
const shared = env as unknown as Record<string, unknown>;
beforeEach(() => { shared.POLLEN_SECRET = SECRET; });
afterEach(async () => { delete shared.POLLEN_SECRET; await reset(); });

async function create(): Promise<Account> {
  const made = await call("/v1/identity", "POST", undefined, {}); expect(made.status).toBe(201);
  return made.json<Account>();
}
/** Buys and wears `look` through the shop, as the phone would. */
async function wear(account: Account, look: Record<string, string>): Promise<void> {
  const prices: Record<string, number> = { daisy: 1000, seashell: 1000, straw_hat: 5000, tide: 20000 };
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
    noteFullJourney(state.storage, Date.now() + DAY, Date.now());
    state.storage.sql.exec("UPDATE pollen_wallet SET data=json_set(data,'$.balance',100000,'$.earned',100000) WHERE id=1");
  });
  for (const id of Object.values(look)) expect((await call("/v1/pollen/spend", "POST", account, { schema_version: 1, idempotency_key: key(), kind: "item", id, expected_cost: prices[id] })).status).toBe(200);
  expect((await call("/v1/pollen/equip", "POST", account, { schema_version: 1, idempotency_key: key(), revision: Date.now(), look })).status).toBe(200);
}
async function room(host: Account, guest: Account, vars: Record<string, unknown> = ON): Promise<RoomSnapshotV2> {
  const made = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH }, vars);
  expect(made.status).toBe(200);
  const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: (await made.json<RoomSnapshotV2>()).invite_code }, vars); expect(joined.status).toBe(200);
  return joined.json<RoomSnapshotV2>();
}
const turnBody = (current: RoomSnapshotV2, recording: unknown, checkpoint?: unknown) =>
  ({ base_revision: current.revision, branch: current.branch, idempotency_key: key(), recording, ...(checkpoint === undefined ? {} : { checkpoint }) });
async function turn(current: RoomSnapshotV2, account: Account, recording: unknown, checkpoint?: unknown, vars: Record<string, unknown> = ON, headers: Record<string, string> = ASK): Promise<MutationV2 & Read> {
  const sent = await call(`/v2/rooms/${current.room_id}/turns`, "POST", account, turnBody(current, recording, checkpoint), vars, headers);
  expect(sent.status).toBe(200); return sent.json<MutationV2 & Read>();
}
const read = async (current: RoomSnapshotV2, account: Account, vars: Record<string, unknown> = ON, headers: Record<string, string> = ASK) =>
  (await call(`/v2/rooms/${current.room_id}`, "GET", account, undefined, vars, headers)).json<Read>();
const tableNames = (roomId: string) => runInDurableObject(env.ROOMS_V2.getByName(roomId), async (_, state) =>
  state.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('member_looks','turn_looks') ORDER BY name").toArray().map(row => row.name));

describe("looks in rooms", () => {
  it("answers the capability only to a phone that asks while looks are on", async () => {
    const player = await create();
    const capabilities = async (vars: Record<string, unknown>, headers: Record<string, string>) => (await call("/v2/capabilities", "GET", player, undefined, vars, headers)).json<Record<string, unknown>>();
    expect(await capabilities(ON, ASK)).toMatchObject({ looks_version: 1 });
    expect(await capabilities(ON, {})).not.toHaveProperty("looks_version");
    expect(await capabilities(OFF, ASK)).not.toHaveProperty("looks_version");
  });
  it("serves each member the other's look and the looks of the other's turns, only when the phone asks", async () => {
    const host = await create(), guest = await create();
    await wear(host, { hat: "daisy", body: "tide" });
    const current = await room(host, guest);
    const played = await turn(current, host, firstA);
    expect(played.partner_look).toEqual({});
    const seen = await read(played.room, guest);
    expect(seen.partner_look).toEqual({ hat: "daisy", body: "tide" });
    expect(seen.turn_looks).toEqual({ [firstA.recording_hash]: { hat: "daisy", body: "tide" } });
    const plain = await read(played.room, guest, ON, {});
    expect(plain).not.toHaveProperty("partner_look"); expect(plain).not.toHaveProperty("turn_looks");
    // The host sees only the guest's turns, and the guest wears the default look.
    const answer = await turn(seen, guest, firstB, middle);
    expect(answer.partner_look).toEqual({ hat: "daisy", body: "tide" });
    expect(answer.turn_looks).toEqual({ [firstA.recording_hash]: { hat: "daisy", body: "tide" } });
    expect(await read(answer.room, host)).toMatchObject({ partner_look: {}, turn_looks: {} });
    // A turn keeps the look it was played in after the player changes it.
    expect((await call("/v1/pollen/equip", "POST", host, { schema_version: 1, idempotency_key: key(), revision: Date.now() + 1, look: {} })).status).toBe(200);
    const after = await turn(answer.room, guest, secondA);
    const later = await turn(after.room, host, secondB, final);
    expect(await read(later.room, guest)).toMatchObject({ partner_look: {}, turn_looks: { [firstA.recording_hash]: { hat: "daisy", body: "tide" } } });
  });
  it("adds no request and stores nothing while off, and nothing for the default look while on", async () => {
    const host = await create(), guest = await create(), bare = await create(), other = await create();
    await wear(host, { hat: "daisy" });
    const off = await room(host, guest, OFF), plain = await room(bare, other);
    const offTurn = countingEnv(env), onTurn = countingEnv(env);
    expect((await call(`/v2/rooms/${off.room_id}/turns`, "POST", host, turnBody(off, firstA), OFF, ASK, offTurn.env)).status).toBe(200);
    expect((await call(`/v2/rooms/${plain.room_id}/turns`, "POST", bare, turnBody(plain, firstA), ON, ASK, onTurn.env)).status).toBe(200);
    expect(onTurn.calls).toEqual(offTurn.calls);
    expect(await tableNames(off.room_id)).toEqual([]);
    expect(await tableNames(plain.room_id)).toEqual([]);
    const offRead = await read(off, guest, OFF);
    expect(offRead).not.toHaveProperty("partner_look");
  });
  it("writes one row for each turn in a look, beside the table made once per room", async () => {
    const host = await create(), guest = await create();
    await wear(host, { hat: "daisy" }); await wear(guest, { hat: "seashell" });
    const current = await room(host, guest);
    const stub = env.ROOMS_V2.getByName(current.room_id);
    // Create and join already wrote both members' looks; the same turn with looks off is the base.
    const base = await meterRows({ room: stub }, async () => turn(current, host, firstA, undefined, OFF));
    const next = await room(host, guest), nextStub = env.ROOMS_V2.getByName(next.room_id);
    const looked = await meterRows({ room: nextStub }, async () => turn(next, host, firstA));
    expect(await tableNames(next.room_id)).toEqual(LOOKS_ROOM_TABLES.map(table => table.name).sort());
    // The table, made once per room, and the turn's row.
    expect(looked.rows.room.written - base.rows.room.written).toBe(3);
    // The next turn in the same look writes its own turn row only.
    const second = await meterRows({ room: nextStub }, async () => turn(looked.value.room, guest, firstB, middle));
    const secondBase = await meterRows({ room: stub }, async () => turn(base.value.room, guest, firstB, middle, OFF));
    expect(second.rows.room.written - secondBase.rows.room.written).toBe(1);
  });
  it("lets a member who leaves a finished room take their look and their turns' looks", async () => {
    const host = await create(), guest = await create();
    await wear(host, { hat: "daisy" });
    let current = await room(host, guest);
    current = (await turn(current, host, firstA)).room; current = (await turn(current, guest, firstB, middle)).room;
    current = (await turn(current, guest, secondA)).room; current = (await turn(current, host, secondB, final)).room;
    expect((await call(`/v2/rooms/${current.room_id}/leave`, "POST", host, { schema_version: 1, leave_finished: true }, ON)).status).toBe(200);
    expect(await read(current, guest, ON)).toMatchObject({ partner_look: {}, turn_looks: {} });
    expect(await runInDurableObject(env.ROOMS_V2.getByName(current.room_id), async (_, state) => state.storage.sql.exec("SELECT player_id FROM member_looks").toArray())).toEqual([]);
  });
  it("drops every look with the room", async () => {
    const host = await create(), guest = await create();
    await wear(host, { hat: "daisy" });
    const current = await room(host, guest);
    await turn(current, host, firstA);
    expect((await call(`/v2/rooms/${current.room_id}`, "DELETE", host, undefined, ON)).status).toBe(200);
    expect(await tableNames(current.room_id)).toEqual([]);
  });
});

describe("looks through replay transfer", () => {
  const H = "H".repeat(22), G = "G".repeat(22), R = "R".repeat(22), I = "AB".repeat(10);
  function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
  async function complete(look: Record<string, string> | undefined) {
    const room = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    value(await room.initialize(R, H, I, undefined, undefined, undefined, undefined, undefined, look));
    let state = value(await room.join(G, I));
    for (const [owner, recording, checkpoint] of [[H, firstA, undefined], [G, firstB, middle], [G, secondA, undefined], [H, secondB, final]] as const) {
      const request = { base_revision: state.revision, branch: state.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) };
      state = value(await room.commit(owner, request, undefined, {}, undefined, undefined, owner === H ? look : undefined)).room;
    }
    return room;
  }
  it("carries every turn's look beside the archive, never in it, and keeps them through transfer and restore", async () => {
    const look = { hat: "daisy" }, room = await complete(look), plain = await complete(undefined);
    const offered = value(await room.replayTransfer(H, true, true));
    const expected = { [firstA.recording_hash]: look, [secondB.recording_hash]: look };
    expect(offered.turn_looks).toEqual(expected);
    expect(value(await room.replayTransfer(H))).not.toHaveProperty("turn_looks");
    // No look enters the archive or its hash.
    expect(offered.manifest.archive_hash).toBe(await digest(canonicalJson(offered.archive)));
    expect(JSON.stringify(offered.archive)).not.toContain("daisy");
    expect(Object.keys(offered.archive!)).toEqual(Object.keys(value(await plain.replayTransfer(H)).archive!));
    const ack = { schema_version: 1, epoch: offered.manifest.epoch, archive_hash: offered.manifest.archive_hash };
    value(await room.acknowledgeReplayTransfer(H, ack)); value(await room.acknowledgeReplayTransfer(G, ack));
    const transferred = value(await room.replayTransfer(G, true, true));
    expect(transferred).toMatchObject({ transferred: true, archive: null, turn_looks: expected });
    value(await room.restoreReplayTransfer(H, { ...ack, archive: offered.archive }));
    expect(value(await room.snapshot(G, undefined, undefined, { looks: true }))).toMatchObject({ partner_look: look, turn_looks: expected });
    expect(value(await room.replayTransfer(G, false, true)).turn_looks).toEqual(expected);
  });
});
