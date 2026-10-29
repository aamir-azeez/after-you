import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { withConfig } from "./config";
import { digest, type Outcome } from "../src/protocol";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import { rollingHome } from "../src/v2/protocol-cooperative";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { BASE_FACES, END_REACTIONS } from "../src/v2/end-reactions";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";
import weightA from "../../game/tests/fixtures/cooperative/weight-of-a-friend-a.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
type View = { schema_version: 1; faces: Record<string, string>; partner?: string };
type Inbox = { rooms: { room_id: string; partner_reaction?: string }[] };
const key = () => crypto.randomUUID(), CODE = "SYNTHETIC-FACES-TESTER", LOOKUP = "SELECT name FROM sqlite_master WHERE type='table' AND name=?";
const ON = {}, ASK = { "X-AfterYou-End-Reactions": "1" };
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
async function submit(room: RoomSnapshotV2, account: Account, recording: unknown, face?: unknown, checkpoint?: unknown, vars: Record<string, string> = {}, headers: Record<string, string> = {}): Promise<MutationV2> {
  const result = await call(`/v2/rooms/${room.room_id}/turns`, "POST", account, body(room, recording, face === undefined ? {} : { end_reaction: face }, checkpoint), vars, headers);
  expect(result.status).toBe(200); return result.json<MutationV2>();
}
async function joined(): Promise<{ host: Account; guest: Account; room: RoomSnapshotV2 }> {
  const host = await create(), guest = await create();
  const made = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
  expect(made.status).toBe(200);
  const join = await call("/v2/rooms/join", "POST", guest, { invite_code: (await made.json<RoomSnapshotV2>()).invite_code }); expect(join.status).toBe(200);
  return { host, guest, room: await join.json<RoomSnapshotV2>() };
}
/** Relay: the host plays t0-0-a and t0-1-b, the guest t0-0-b and t0-1-a. */
async function finished(faces: [unknown, unknown, unknown, unknown]) {
  const { host, guest, room } = await joined();
  let current = (await submit(room, host, firstA, faces[0])).room;
  current = (await submit(current, guest, firstB, faces[1], middle)).room;
  current = (await submit(current, guest, secondA, faces[2])).room;
  current = (await submit(current, host, secondB, faces[3], final)).room;
  expect(current.active_role).toBe("complete");
  return { host, guest, room: current };
}
const list = (roomId: string, account: Account, vars = ON) => call(`/v2/rooms/${roomId}/end-reactions`, "GET", account, undefined, vars);
const read = (roomId: string, account: Account, vars: Record<string, string> = ON, headers: Record<string, string> = ASK) => call(`/v2/rooms/${roomId}`, "GET", account, undefined, vars, headers);
const inbox = async (account: Account, vars: Record<string, string> = ON, headers: Record<string, string> = ASK) => (await call("/v1/room-inbox", "GET", account, undefined, vars, headers)).json<Inbox>();
const table = (roomId: string) => runInDurableObject(env.ROOMS_V2.getByName(roomId), async (_instance, state) => state.storage.sql.exec(LOOKUP, END_REACTIONS.name).toArray().length > 0);

afterEach(async () => { await reset(); });

describe("end-of-run reactions", () => {
  it("are advertised only to clients that ask", async () => {
    const host = await create();
    expect(await (await call("/v2/capabilities", "GET", host, undefined, ON)).json()).not.toHaveProperty("end_reactions_version");
    expect(await (await call("/v2/capabilities", "GET", host, undefined, ON, ASK)).json()).toMatchObject({ end_reactions_version: 1 });
  });

  it("ride on their turns and come back beside room reads and turn replies, never inside the room or its recordings", async () => {
    const { host, guest, room } = await joined();
    const plain = await submit(room, host, firstA, "happy");
    expect(Object.keys(plain)).toEqual(["receipt", "room"]);
    expect(plain.room.recording_a).toEqual(firstA);
    expect(plain.room).not.toHaveProperty("end_reactions");
    // The guest's room read carries the host's face and names it as the friend's latest.
    const seen = await (await read(room.room_id, guest)).json<RoomSnapshotV2>();
    expect(seen.end_reactions).toEqual({ schema_version: 1, faces: { [firstA.recording_hash]: "happy" }, partner: "happy" });
    const { end_reactions: _faces, ...snapshot } = seen; void _faces;
    expect(snapshot).toEqual(await (await read(room.room_id, guest, ON, {})).json());
    // A reply to an asking client carries every face; the host's own face is not their partner's.
    const asked = await submit(plain.room, guest, firstB, "knocked_out", middle, ON, ASK);
    expect(asked.end_reactions).toEqual({ schema_version: 1, faces: { [firstA.recording_hash]: "happy", [firstB.recording_hash]: "knocked_out" }, partner: "happy" });
    expect(asked.room).not.toHaveProperty("end_reactions");
    const hostView = await (await read(room.room_id, host)).json<RoomSnapshotV2>();
    expect(hostView.end_reactions?.partner).toBe("knocked_out");
    const pair = await (await call(`/v2/rooms/${room.room_id}/pairs/p0-0`, "GET", host)).json<Record<string, unknown>>();
    expect(Object.keys(pair).sort()).toEqual(["a", "b", "branch", "checkpoint", "pair_id", "stage_index"]);
    expect(pair.a).toEqual(firstA);
  });

  it("stay out of reads and replies while the client does not ask", async () => {
    const { host, guest, room } = await joined();
    const sent = await submit(room, host, firstA, "heart");
    expect(sent).not.toHaveProperty("end_reactions");
    expect(await (await read(room.room_id, guest, ON, {})).json()).not.toHaveProperty("end_reactions");
    // The face the turn carried is kept all the same.
    expect(await (await list(room.room_id, guest)).json<View>()).toEqual({ schema_version: 1, faces: { [firstA.recording_hash]: "heart" } });
  });

  it("leave the small unchanged poll reply as it was", async () => {
    const { host, guest, room } = await joined();
    const sent = await submit(room, host, firstA, "sad");
    const known = { ...ASK, "X-AfterYou-Known-Room": `${sent.room.revision}.${sent.room.branch}` };
    const small = await (await read(room.room_id, guest, ON, known)).json<Record<string, unknown>>();
    expect(Object.keys(small).sort()).toEqual(["branch", "revision", "schema_version", "unchanged", "updated_at"]);
    const stale = { ...ASK, "X-AfterYou-Known-Room": `${room.revision}.${room.branch}` };
    expect((await (await read(room.room_id, guest, ON, stale)).json<RoomSnapshotV2>()).end_reactions?.faces).toEqual({ [firstA.recording_hash]: "sad" });
  });

  it("accept every face and only faces, and other fields stay refused", async () => {
    const { host, room } = await joined();
    for (const bad of ["normal", "Happy", "", 1, null, ["happy"], { face: "happy" }]) {
      const refused = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, firstA, { end_reaction: bad }));
      expect(refused.status).toBe(400); expect(await errorCode(refused)).toBe("invalid_end_reaction");
    }
    const extra = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, firstA, { end_reaction: "happy", reaction: "happy" }));
    expect(extra.status).toBe(400); expect(await errorCode(extra)).toBe("unexpected_fields");
    expect(await table(room.room_id)).toBe(false);
    expect(BASE_FACES).toHaveLength(9);
    for (const face of BASE_FACES) {
      const fresh = await joined();
      await submit(fresh.room, fresh.host, firstA, face);
      expect(await (await list(fresh.room.room_id, fresh.guest)).json<View>()).toEqual({ schema_version: 1, faces: { [firstA.recording_hash]: face } });
    }
  });

  it("travel with tries and are part of the request a retried key must repeat", async () => {
    const { host, room } = await joined();
    const sent = body(room, firstA, { end_reaction: "squeeze", tries: 3 });
    const first = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, sent);
    expect(first.status).toBe(200);
    const again = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, sent);
    expect(again.status).toBe(200);
    expect((await again.json<MutationV2>()).receipt).toEqual((await first.json<MutationV2>()).receipt);
    const changed = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, { ...sent, end_reaction: "angry" });
    expect(changed.status).toBe(409); expect(await errorCode(changed)).toBe("idempotency_key_reused");
    expect(await (await list(room.room_id, host)).json<View>()).toEqual({ schema_version: 1, faces: { [firstA.recording_hash]: "squeeze" } });
    expect(await (await call(`/v2/rooms/${room.room_id}/tries`, "GET", host)).json()).toEqual({ schema_version: 1, tries: { [firstA.recording_hash]: 3 } });
  });

  it("read nothing and create nothing in a room no face was sent to", async () => {
    const { host, guest, room } = await joined();
    await submit(room, host, firstA);
    expect(await (await list(room.room_id, guest)).json<View>()).toEqual({ schema_version: 1, faces: {} });
    expect((await (await read(room.room_id, guest)).json<RoomSnapshotV2>()).end_reactions).toEqual({ schema_version: 1, faces: {} });
    expect(await table(room.room_id)).toBe(false);
    expect((await list(room.room_id, await create())).status).toBe(404);
  });

  it("name the friend's face only when it rode on the friend's latest turn", async () => {
    const { host, guest, room } = await joined();
    let current = (await submit(room, host, firstA, "happy")).room;
    current = (await submit(current, guest, firstB, "angry", middle)).room;
    current = (await submit(current, guest, secondA)).room;
    // The guest's latest turn carried nothing, so the host has no friend's face even though an earlier turn did.
    expect((await (await read(room.room_id, host)).json<RoomSnapshotV2>()).end_reactions).toEqual({ schema_version: 1,
      faces: { [firstA.recording_hash]: "happy", [firstB.recording_hash]: "angry" } });
    expect((await inbox(host)).rooms[0]).not.toHaveProperty("partner_reaction");
    expect((await inbox(guest)).rooms[0].partner_reaction).toBe("happy");
    await submit(current, host, secondB, "sleepy", final);
    expect((await inbox(guest)).rooms[0].partner_reaction).toBe("sleepy");
  });

  it("reach the room list from the room index only for clients that ask", async () => {
    const { host, guest, room } = await finished(["happy", "sad", undefined, "heart"]);
    expect((await inbox(guest)).rooms.find(entry => entry.room_id === room.room_id)?.partner_reaction).toBe("heart");
    expect((await inbox(host)).rooms.find(entry => entry.room_id === room.room_id)).not.toHaveProperty("partner_reaction");
    expect((await inbox(guest, ON, {})).rooms[0]).not.toHaveProperty("partner_reaction");
  });

  it("leave with the member who leaves a finished room, and with the room", async () => {
    const { host, guest, room } = await finished(["happy", "sad", "angry", "heart"]);
    const leave = await call(`/v2/rooms/${room.room_id}/leave`, "POST", host, { schema_version: 1, leave_finished: true });
    expect(leave.status).toBe(200);
    expect(await (await list(room.room_id, guest)).json<View>()).toEqual({ schema_version: 1, faces: { [firstB.recording_hash]: "sad", [secondA.recording_hash]: "angry" } });
    expect((await inbox(guest)).rooms[0] ?? {}).not.toHaveProperty("partner_reaction");
    value(await env.ROOMS_V2.getByName(room.room_id).eraseForPlayer(guest.player_id));
    expect(await table(room.room_id)).toBe(false);
  });

  it("outlive the rows replay transfer stubs", async () => {
    const { host, guest, room } = await finished(["happy", undefined, "surprised", "annoyed"]);
    for (const member of [host, guest]) {
      const offer = await (await call(`/v2/rooms/${room.room_id}/replay-transfer`, "GET", member)).json<{ manifest: { epoch: number; archive_hash: string } }>();
      expect((await call(`/v2/rooms/${room.room_id}/replay-transfer/ack`, "POST", member, { schema_version: 1, epoch: offer.manifest.epoch, archive_hash: offer.manifest.archive_hash })).status).toBe(200);
    }
    expect((await call(`/v2/rooms/${room.room_id}/collection`, "GET", host)).status).toBe(410);
    expect(await (await list(room.room_id, guest)).json<View>()).toEqual({ schema_version: 1,
      faces: { [firstA.recording_hash]: "happy", [secondA.recording_hash]: "surprised", [secondB.recording_hash]: "annoyed" } });
  });

  it("keep the operator snapshot working and out of its bytes", async () => {
    const { host, room } = await joined();
    await submit(room, host, firstA, "happy");
    const stub = env.ROOMS_V2.getByName(room.room_id);
    const archive = value(await stub.exportSnapshot("d".repeat(40)));
    expect(archive).not.toContain(END_REACTIONS.name);
    const target = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    expect(await target.restoreSnapshot(archive, room.room_id)).toMatchObject({ ok: true });
  });

  it("pass the premium turn's own field check", async () => {
    const host = await create(), guest = await create();
    expect((await call("/v1/tester-access", "POST", host, { schema_version: 1, code: CODE }, { TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + CODE) })).status).toBe(200);
    const made = await call("/v2/rooms", "POST", host, { ...rollingHome.key, idempotency_key: key() }); expect(made.status).toBe(200);
    const join = await call("/v2/rooms/join", "POST", guest, { invite_code: (await made.json<RoomSnapshotV2>()).invite_code, supported_simulation_versions: [2, 4, 5, 6] });
    const room = await join.json<RoomSnapshotV2>();
    const refused = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, weightA, { end_reaction: "happy", other: 1 }));
    expect(refused.status).toBe(400); expect(await errorCode(refused)).toBe("unexpected_fields");
    const sent = await call(`/v2/rooms/${room.room_id}/turns`, "POST", host, body(room, weightA, { end_reaction: "happy" }), ON, ASK);
    expect(sent.status).toBe(200);
    expect((await sent.json<MutationV2>()).end_reactions?.faces).toEqual({ [weightA.recording_hash]: "happy" });
    expect(await (await list(room.room_id, guest)).json<View>()).toEqual({ schema_version: 1, faces: { [weightA.recording_hash]: "happy" } });
  });
});
