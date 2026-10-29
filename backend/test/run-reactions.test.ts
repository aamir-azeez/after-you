import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { type Outcome } from "../src/protocol";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { MAX_RUN_REACTIONS, RUN_REACTIONS, RUN_REACTIONS_HEADER } from "../src/v2/run-reactions";
import { FACES } from "../src/v2/end-reactions";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";
import { withConfig } from "./config";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Track = { tick: number; id: string }[];
type Tracks = { schema_version: 1; tracks: Record<string, Track> };
const key = () => crypto.randomUUID(), LOOKUP = "SELECT name FROM sqlite_master WHERE type='table' AND name=?";
const ASK = { [RUN_REACTIONS_HEADER]: "1" };
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, string> = {}, headers: Record<string, string> = {}): Promise<Response> {
  const configured: Env = withConfig({ ...env, ...vars });
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
async function submit(room: RoomSnapshotV2, account: Account, recording: unknown, track?: unknown, checkpoint?: unknown, vars: Record<string, string> = {}, headers: Record<string, string> = {}): Promise<MutationV2> {
  const result = await call(`/v2/rooms/${room.room_id}/turns`, "POST", account, body(room, recording, track === undefined ? {} : { run_reactions: track }, checkpoint), vars, headers);
  expect(result.status).toBe(200); return result.json<MutationV2>();
}
async function joined(): Promise<{ host: Account; guest: Account; room: RoomSnapshotV2 }> {
  const host = await create(), guest = await create();
  const made = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
  expect(made.status).toBe(200);
  const join = await call("/v2/rooms/join", "POST", guest, { invite_code: (await made.json<RoomSnapshotV2>()).invite_code }); expect(join.status).toBe(200);
  return { host, guest, room: await join.json<RoomSnapshotV2>() };
}
const read = (roomId: string, account: Account, vars: Record<string, string> = {}, headers: Record<string, string> = ASK) => call(`/v2/rooms/${roomId}`, "GET", account, undefined, vars, headers);
const list = (roomId: string, account: Account, vars: Record<string, string> = {}, headers: Record<string, string> = ASK) => call(`/v2/rooms/${roomId}/end-reactions`, "GET", account, undefined, vars, headers);
const table = (roomId: string) => runInDurableObject(env.ROOMS_V2.getByName(roomId), async (_instance, state) => state.storage.sql.exec(LOOKUP, RUN_REACTIONS.name).toArray().length > 0);
const HAPPY: Track = [{ tick: 12, id: "happy" }, { tick: 140, id: "heart" }];

afterEach(async () => { await reset(); });

describe("run reactions", () => {
  it("are advertised only to clients that ask", async () => {
    const host = await create();
    expect(await (await call("/v2/capabilities", "GET", host)).json()).not.toHaveProperty("run_reactions_version");
    expect(await (await call("/v2/capabilities", "GET", host, undefined, {}, ASK)).json()).toMatchObject({ run_reactions_version: 1 });
  });

  it("ride on their turn and come back to the friend beside the memory, never inside the room or its recordings", async () => {
    const { host, guest, room } = await joined();
    const sent = await submit(room, host, firstA, HAPPY);
    expect(Object.keys(sent)).toEqual(["receipt", "room"]);
    expect(sent.room.recording_a).toEqual(firstA);
    const seen = await (await read(room.room_id, guest)).json<RoomSnapshotV2>();
    expect(seen.run_reactions).toEqual({ schema_version: 1, tracks: { [firstA.recording_hash]: HAPPY } });
    // Without the header the read is exactly as before.
    const { run_reactions: _tracks, end_reactions: _faces, ...rest } = seen; void _tracks; void _faces;
    expect(rest).toEqual(await (await read(room.room_id, guest, {}, {})).json());
    // A reply carries the partner's latest track, never the sender's own.
    const reply = await submit(sent.room, guest, firstB, [{ tick: 3, id: "sad" }], middle, {}, ASK);
    expect(reply.run_reactions).toEqual({ schema_version: 1, tracks: { [firstA.recording_hash]: HAPPY } });
    // The friend's turn that finished the pair comes back to the host's next read.
    expect((await (await read(room.room_id, host)).json<RoomSnapshotV2>()).run_reactions?.tracks).toEqual({ [firstB.recording_hash]: [{ tick: 3, id: "sad" }] });
    const pair = await (await call(`/v2/rooms/${room.room_id}/pairs/p0-0`, "GET", host, undefined, {}, ASK)).json<Record<string, unknown>>();
    expect(Object.keys(pair).sort()).toEqual(["a", "b", "branch", "checkpoint", "pair_id", "stage_index"]);
    // Replays read every track beside the end reactions list.
    expect((await (await list(room.room_id, host)).json<{ run_reactions: Tracks }>()).run_reactions).toEqual({ schema_version: 1,
      tracks: { [firstA.recording_hash]: HAPPY, [firstB.recording_hash]: [{ tick: 3, id: "sad" }] } });
  });

  it("stay out of reads, replies and the list while the client does not ask", async () => {
    const { host, guest, room } = await joined();
    expect(await submit(room, host, firstA, HAPPY)).not.toHaveProperty("run_reactions");
    expect(await (await read(room.room_id, guest, {}, {})).json()).not.toHaveProperty("run_reactions");
    expect(await (await list(room.room_id, guest, {}, {})).json()).toEqual({ schema_version: 1, faces: {} });
    // The track a turn carried without asking is kept all the same.
    expect((await (await read(room.room_id, guest)).json<RoomSnapshotV2>()).run_reactions?.tracks).toEqual({ [firstA.recording_hash]: HAPPY });
  });

  it("leave the small unchanged poll reply as it was", async () => {
    const { host, guest, room } = await joined();
    const sent = await submit(room, host, firstA, HAPPY);
    const known = { ...ASK, "X-AfterYou-Known-Room": `${sent.room.revision}.${sent.room.branch}` };
    const small = await (await read(room.room_id, guest, {}, known)).json<Record<string, unknown>>();
    expect(Object.keys(small).sort()).toEqual(["branch", "revision", "schema_version", "unchanged", "updated_at"]);
  });

  it("accept only a short, rising track of catalog faces inside the turn", async () => {
    const { host, room } = await joined();
    const many = Array.from({ length: MAX_RUN_REACTIONS + 1 }, (_, index) => ({ tick: index, id: "happy" }));
    const refusals: unknown[] = [[], many, {}, "happy", null, [{ tick: 5, id: "happy" }, { tick: 5, id: "sad" }], [{ tick: 9, id: "happy" }, { tick: 4, id: "sad" }],
      [{ tick: -1, id: "happy" }], [{ tick: 1.5, id: "happy" }], [{ tick: "1", id: "happy" }], [{ tick: 1, id: "normal" }], [{ tick: 1, id: "Happy" }],
      [{ tick: 1 }], [{ tick: 1, id: "happy", extra: true }], [["happy", 1]], [{ tick: firstA.duration_ticks + 1, id: "happy" }]];
    for (const bad of refusals) {
      const refused = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, firstA, { run_reactions: bad }));
      expect(refused.status).toBe(400); expect(await errorCode(refused)).toBe("invalid_run_reactions");
    }
    const extra = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, firstA, { run_reactions: HAPPY, reactions: HAPPY }));
    expect(extra.status).toBe(400); expect(await errorCode(extra)).toBe("unexpected_fields");
    expect(await table(room.room_id)).toBe(false);
    const full = Array.from({ length: MAX_RUN_REACTIONS }, (_, index) => ({ tick: index * 7, id: FACES[index % FACES.length] }));
    await submit(room, host, firstA, full);
    expect((await (await list(room.room_id, host)).json<{ run_reactions: Tracks }>()).run_reactions.tracks).toEqual({ [firstA.recording_hash]: full });
  });

  it("travel with the end face and are part of the request a retried key must repeat", async () => {
    const { host, guest, room } = await joined();
    const sent = body(room, firstA, { run_reactions: HAPPY, end_reaction: "squeeze", tries: 2 });
    const first = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, sent);
    expect(first.status).toBe(200);
    const again = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, sent);
    expect((await again.json<MutationV2>()).receipt).toEqual((await first.json<MutationV2>()).receipt);
    const changed = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, { ...sent, run_reactions: [{ tick: 1, id: "sad" }] });
    expect(changed.status).toBe(409); expect(await errorCode(changed)).toBe("idempotency_key_reused");
    const seen = await (await read(room.room_id, guest, {}, { ...ASK, "X-AfterYou-End-Reactions": "1" })).json<RoomSnapshotV2>();
    expect(seen.run_reactions?.tracks).toEqual({ [firstA.recording_hash]: HAPPY });
    expect(seen.end_reactions?.partner).toBe("squeeze");
  });

  it("read nothing and create nothing in a room no track was sent to", async () => {
    const { host, guest, room } = await joined();
    await submit(room, host, firstA);
    expect((await (await read(room.room_id, guest)).json<RoomSnapshotV2>()).run_reactions).toEqual({ schema_version: 1, tracks: {} });
    expect((await (await list(room.room_id, guest)).json<{ run_reactions: Tracks }>()).run_reactions).toEqual({ schema_version: 1, tracks: {} });
    expect(await table(room.room_id)).toBe(false);
  });

  it("leave with the member who leaves a finished room, and with the room", async () => {
    const { host, guest, room } = await joined();
    let current = (await submit(room, host, firstA, HAPPY)).room;
    current = (await submit(current, guest, firstB, [{ tick: 1, id: "sad" }], middle)).room;
    current = (await submit(current, guest, secondA, [{ tick: 2, id: "angry" }])).room;
    current = (await submit(current, host, secondB, [{ tick: 3, id: "sleepy" }], final)).room;
    expect(current.active_role).toBe("complete");
    const leave = await call(`/v2/rooms/${room.room_id}/leave`, "POST", host, { schema_version: 1, leave_finished: true });
    expect(leave.status).toBe(200);
    expect((await (await list(room.room_id, guest)).json<{ run_reactions: Tracks }>()).run_reactions.tracks).toEqual({
      [firstB.recording_hash]: [{ tick: 1, id: "sad" }], [secondA.recording_hash]: [{ tick: 2, id: "angry" }] });
    value(await env.ROOMS_V2.getByName(room.room_id).eraseForPlayer(guest.player_id));
    expect(await table(room.room_id)).toBe(false);
  });

  it("keep the operator snapshot working and out of its bytes, and a restore clears them", async () => {
    const { host, room } = await joined();
    await submit(room, host, firstA, HAPPY);
    const stub = env.ROOMS_V2.getByName(room.room_id);
    const archive = value(await stub.exportSnapshot("d".repeat(40)));
    expect(archive).not.toContain(RUN_REACTIONS.name);
    // A stray table in the target (left by an earlier, failed restore) is dropped.
    const target = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    const present = () => runInDurableObject(target, async (_instance, state) => state.storage.sql.exec(LOOKUP, RUN_REACTIONS.name).toArray().length);
    await runInDurableObject(target, async (_instance, state) => { state.storage.sql.exec(RUN_REACTIONS.schema); });
    expect(await present()).toBe(1);
    expect(await target.restoreSnapshot(archive, room.room_id)).toMatchObject({ ok: true });
    expect(await present()).toBe(0);
  });

  it("come back only from the partner's latest turn", async () => {
    const { host, guest, room } = await joined();
    let current = (await submit(room, host, firstA, HAPPY)).room;
    current = (await submit(current, guest, firstB, undefined, middle)).room;
    // The host's latest turn carries none, though an earlier one did.
    expect((await (await read(room.room_id, guest)).json<RoomSnapshotV2>()).run_reactions).toEqual({ schema_version: 1, tracks: { [firstA.recording_hash]: HAPPY } });
    current = (await submit(current, guest, secondA)).room;
    current = (await submit(current, host, secondB, undefined, final)).room;
    expect((await (await read(room.room_id, guest)).json<RoomSnapshotV2>()).run_reactions).toEqual({ schema_version: 1, tracks: {} });
  });
});
