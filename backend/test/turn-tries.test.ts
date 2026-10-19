import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { digest, type Outcome } from "../src/protocol";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import { rollingHome } from "../src/v2/protocol-cooperative";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { TURN_TRIES } from "../src/v2/turn-tries";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";
import weightA from "../../game/tests/fixtures/cooperative/weight-of-a-friend-a.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Tries = { schema_version: 1; tries: Record<string, number> };
const key = () => crypto.randomUUID(), CODE = "SYNTHETIC-TRIES-TESTER", LOOKUP = "SELECT name FROM sqlite_master WHERE type='table' AND name=?";
const ON = { TURN_TRIES_ENABLED: "true" }, ASK = { "X-AfterYou-Turn-Tries": "1" };
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, string> = {}, headers: Record<string, string> = {}): Promise<Response> {
  const configured: Env = { ...env };
  Object.assign(configured, { V2_ROOMS_ENABLED: "true", COOP_CHAPTERS_ENABLED: "true", ...vars });
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
const errorCode = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;
async function create(): Promise<Account> { const result = await call("/v1/identity", "POST", undefined, {}); expect(result.status).toBe(201); return result.json<Account>(); }
const body = (room: RoomSnapshotV2, recording: unknown, extra: Record<string, unknown> = {}, checkpoint?: unknown) =>
  ({ base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint === undefined ? {} : { checkpoint }), ...extra });
async function submit(room: RoomSnapshotV2, account: Account, recording: unknown, tries?: unknown, checkpoint?: unknown): Promise<RoomSnapshotV2> {
  const result = await call(`/v2/rooms/${room.room_id}/turns`, "POST", account, body(room, recording, tries === undefined ? {} : { tries }, checkpoint));
  expect(result.status).toBe(200); return (await result.json<MutationV2>()).room;
}
async function joined(): Promise<{ host: Account; guest: Account; room: RoomSnapshotV2 }> {
  const host = await create(), guest = await create();
  const made = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
  expect(made.status).toBe(200);
  const join = await call("/v2/rooms/join", "POST", guest, { invite_code: (await made.json<RoomSnapshotV2>()).invite_code }); expect(join.status).toBe(200);
  return { host, guest, room: await join.json<RoomSnapshotV2>() };
}
const tries = async (roomId: string, account: Account, vars = ON) => call(`/v2/rooms/${roomId}/tries`, "GET", account, undefined, vars);
const table = (roomId: string) => runInDurableObject(env.ROOMS_V2.getByName(roomId), async (_instance, state) => state.storage.sql.exec(LOOKUP, TURN_TRIES.name).toArray().length > 0);

afterEach(async () => { await reset(); });

describe("turn try counts", () => {
  it("are advertised only to clients that ask, and only while the flag is on", async () => {
    const host = await create();
    const plain = await (await call("/v2/capabilities", "GET", host, undefined, ON)).json<Record<string, unknown>>();
    expect(plain).not.toHaveProperty("turn_tries_version");
    expect(await (await call("/v2/capabilities", "GET", host, undefined, {}, ASK)).json()).not.toHaveProperty("turn_tries_version");
    expect(await (await call("/v2/capabilities", "GET", host, undefined, ON, ASK)).json()).toMatchObject({ turn_tries_version: 1 });
  });

  it("travel beside each turn, keyed by recording hash, without touching the recording or the room", async () => {
    const { host, guest, room } = await joined();
    let current = await submit(room, host, firstA, 3);
    expect(current.recording_a).toEqual(firstA);
    expect(Object.keys(current)).not.toContain("tries");
    current = await submit(current, guest, firstB, 1, middle);
    current = await submit(current, guest, secondA);
    current = await submit(current, host, secondB, 999, final);
    expect(current.active_role).toBe("complete");
    for (const member of [host, guest]) {
      const read = await tries(room.room_id, member); expect(read.status).toBe(200);
      expect(await read.json<Tries>()).toEqual({ schema_version: 1, tries: { [firstA.recording_hash]: 3, [firstB.recording_hash]: 1, [secondB.recording_hash]: 999 } });
    }
    const pair = await (await call(`/v2/rooms/${room.room_id}/pairs/p0-0`, "GET", host)).json<Record<string, unknown>>();
    expect(Object.keys(pair).sort()).toEqual(["a", "b", "branch", "checkpoint", "pair_id", "stage_index"]);
    expect(pair.a).toEqual(firstA);
  });

  it("are accepted whatever the flag, and a body without one is unchanged", async () => {
    const { host, guest, room } = await joined();
    const sent = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, firstA, { tries: 2 }), { TURN_TRIES_ENABLED: "false" });
    expect(sent.status).toBe(200);
    const off = await tries(room.room_id, host, { TURN_TRIES_ENABLED: "false" });
    expect(off.status).toBe(503); expect(await errorCode(off)).toBe("turn_tries_disabled");
    await submit((await sent.json<MutationV2>()).room, guest, firstB, undefined, middle);
    expect(await (await tries(room.room_id, guest)).json<Tries>()).toEqual({ schema_version: 1, tries: { [firstA.recording_hash]: 2 } });
  });

  it("are bounded whole numbers, and other fields stay refused", async () => {
    const { host, room } = await joined();
    for (const bad of [0, 1000, 2.5, "3", null, -1]) {
      const refused = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, firstA, { tries: bad }));
      expect(refused.status).toBe(400); expect(await errorCode(refused)).toBe("invalid_integer");
    }
    const extra = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, firstA, { tries: 2, attempts: 2 }));
    expect(extra.status).toBe(400); expect(await errorCode(extra)).toBe("unexpected_fields");
    expect(await table(room.room_id)).toBe(false);
  });

  it("are part of the request a retried key must repeat", async () => {
    const { host, room } = await joined();
    const sent = body(room, firstA, { tries: 4 });
    const first = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, sent);
    expect(first.status).toBe(200);
    const again = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, sent);
    expect(again.status).toBe(200);
    expect((await again.json<MutationV2>()).receipt).toEqual((await first.json<MutationV2>()).receipt);
    const changed = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, { ...sent, tries: 5 });
    expect(changed.status).toBe(409); expect(await errorCode(changed)).toBe("idempotency_key_reused");
    expect(await (await tries(room.room_id, host)).json<Tries>()).toEqual({ schema_version: 1, tries: { [firstA.recording_hash]: 4 } });
  });

  it("read nothing and create nothing in a room no count was sent to", async () => {
    const { host, guest, room } = await joined();
    await submit(room, host, firstA);
    const read = await tries(room.room_id, guest); expect(read.status).toBe(200);
    expect(await read.json<Tries>()).toEqual({ schema_version: 1, tries: {} });
    expect(await table(room.room_id)).toBe(false);
    const stranger = await create();
    expect((await tries(room.room_id, stranger)).status).toBe(404);
  });

  it("outlive the rows replay transfer stubs, and leave with the room", async () => {
    const { host, guest, room } = await joined();
    let current = await submit(room, host, firstA, 2);
    current = await submit(current, guest, firstB, 3, middle);
    current = await submit(current, guest, secondA, 4);
    current = await submit(current, host, secondB, 5, final);
    for (const member of [host, guest]) {
      const offer = await (await call(`/v2/rooms/${room.room_id}/replay-transfer`, "GET", member, undefined, { REPLAY_TRANSFER_ENABLED: "true" })).json<{ manifest: { epoch: number; archive_hash: string } }>();
      expect((await call(`/v2/rooms/${room.room_id}/replay-transfer/ack`, "POST", member, { schema_version: 1, epoch: offer.manifest.epoch, archive_hash: offer.manifest.archive_hash }, { REPLAY_TRANSFER_ENABLED: "true" })).status).toBe(200);
    }
    expect((await call(`/v2/rooms/${room.room_id}/collection`, "GET", host)).status).toBe(410);
    const read = await tries(room.room_id, guest); expect(read.status).toBe(200);
    expect(await read.json<Tries>()).toEqual({ schema_version: 1, tries: { [firstA.recording_hash]: 2, [firstB.recording_hash]: 3, [secondA.recording_hash]: 4, [secondB.recording_hash]: 5 } });
    value(await env.ROOMS_V2.getByName(room.room_id).eraseForPlayer(host.player_id));
    expect(await table(room.room_id)).toBe(false);
  });

  it("outlive an attempt the server offloads to the phones", async () => {
    const { host, guest, room } = await joined();
    let current = await submit(room, host, firstA, 2);
    current = await submit(current, guest, firstB, undefined, middle);
    current = await submit(current, guest, secondA, 8);
    current = await submit(current, host, secondB, undefined, final);
    const offload = { HISTORY_OFFLOAD_ENABLED: "true" }, keeps = { "X-AfterYou-History": "1" };
    const listed = async (member: Account) => (await (await call(`/v2/rooms/${room.room_id}/history`, "GET", member, undefined, offload, keeps)).json<{ attempts: { link: string; state: string }[] }>()).attempts;
    await listed(host); const link = (await listed(guest))[0].link;
    for (const member of [host, guest]) expect((await call(`/v2/rooms/${room.room_id}/history/0/ack`, "POST", member, { schema_version: 1, link }, offload, keeps)).status).toBe(200);
    expect((await listed(host))[0].state).toBe("offloaded");
    expect((await call(`/v2/rooms/${room.room_id}/collection`, "GET", host)).status).toBe(410);
    expect(await (await tries(room.room_id, guest)).json<Tries>()).toEqual({ schema_version: 1, tries: { [firstA.recording_hash]: 2, [secondA.recording_hash]: 8 } });
  });

  it("stay with an earlier attempt after a fork", async () => {
    const { host, guest, room } = await joined();
    const first = await submit(room, host, firstA, 6);
    const fork = await call(`/v2/rooms/${room.room_id}/fork`, "POST", guest, { base_revision: first.revision, branch: first.branch, idempotency_key: key(), stage_index: 0 });
    expect(fork.status).toBe(200);
    const forked = (await fork.json<MutationV2>()).room;
    expect(forked.branch).toBe(1);
    const again = await submit(forked, host, firstA, 2);
    expect(again.a_turn_id).toBe("t1-0-a");
    const rows = await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), async (_instance, state) => state.storage.sql.exec("SELECT turn_id,tries FROM turn_tries ORDER BY rowid").toArray());
    expect(rows).toEqual([{ turn_id: "t0-0-a", tries: 6 }, { turn_id: "t1-0-a", tries: 2 }]);
    // The same recording on both branches reads once, as the later count.
    expect(await (await tries(room.room_id, host)).json<Tries>()).toEqual({ schema_version: 1, tries: { [firstA.recording_hash]: 2 } });
  });

  it("keep the operator snapshot working and out of its bytes", async () => {
    const { host, room } = await joined();
    await submit(room, host, firstA, 7);
    const stub = env.ROOMS_V2.getByName(room.room_id);
    const archive = value(await stub.exportSnapshot("d".repeat(40)));
    expect(archive).not.toContain(TURN_TRIES.name);
    const target = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    expect(await target.restoreSnapshot(archive, room.room_id)).toMatchObject({ ok: true });
  });

  it("pass the premium turn's own field check", async () => {
    const host = await create(), guest = await create();
    expect((await call("/v1/tester-access", "POST", host, { schema_version: 1, code: CODE }, { TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + CODE) })).status).toBe(200);
    const made = await call("/v2/rooms", "POST", host, { ...rollingHome.key, idempotency_key: key() }); expect(made.status).toBe(200);
    const join = await call("/v2/rooms/join", "POST", guest, { invite_code: (await made.json<RoomSnapshotV2>()).invite_code, supported_simulation_versions: [2, 4, 5, 6] });
    const room = await join.json<RoomSnapshotV2>();
    const refused = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, weightA, { tries: 2, other: 1 }));
    expect(refused.status).toBe(400); expect(await errorCode(refused)).toBe("unexpected_fields");
    const sent = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, weightA, { tries: 2 }));
    expect(sent.status).toBe(200);
    expect(await (await tries(room.room_id, guest)).json<Tries>()).toEqual({ schema_version: 1, tries: { [weightA.recording_hash]: 2 } });
  });
});
