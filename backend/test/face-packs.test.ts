import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { withConfig } from "./config";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import { BASE_FACES, END_REACTIONS, FACE_PACKS_HEADER, LEGACY_SCHEMAS, PACK_FACES, PACK_FALLBACK, isEndReactionsTable, shownFace } from "../src/v2/end-reactions";
import { FACE_PACK_NOT_OWNED, packsNeeded } from "../src/v2/face-packs";
import { CATALOG, offeredPacks, packOfFace } from "../src/pollen/catalog";
import { POLLEN_SHOP_TABLES } from "../src/storage-schema";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Faces = { schema_version: 1; faces: Record<string, string>; partner?: string };
type Tracks = { schema_version: 1; tracks: Record<string, { tick: number; id: string }[]> };
const key = () => crypto.randomUUID();
const FACES_ASK = { "X-AfterYou-End-Reactions": "1" }, TRACKS_ASK = { "X-AfterYou-Run-Reactions": "1" }, PACKS = { [FACE_PACKS_HEADER]: "1" };
const ALL = { ...FACES_ASK, ...TRACKS_ASK, ...PACKS }, OLD = { ...FACES_ASK, ...TRACKS_ASK };
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, headers: Record<string, string> = {}): Promise<Response> {
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), withConfig({ ...env }));
}
const errorCode = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;
async function create(): Promise<Account> { const result = await call("/v1/identity", "POST", undefined, {}); expect(result.status).toBe(201); return result.json<Account>(); }
const body = (room: RoomSnapshotV2, recording: unknown, extra: Record<string, unknown> = {}, checkpoint?: unknown) =>
  ({ base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint === undefined ? {} : { checkpoint }), ...extra });
const turn = (room: RoomSnapshotV2, account: Account, sent: unknown, headers: Record<string, string> = ALL) => call(`/v2/rooms/${room.room_id}/turns`, "POST", account, sent, headers);
async function joined(): Promise<{ host: Account; guest: Account; room: RoomSnapshotV2 }> {
  const host = await create(), guest = await create();
  const made = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
  expect(made.status).toBe(200);
  const join = await call("/v2/rooms/join", "POST", guest, { invite_code: (await made.json<RoomSnapshotV2>()).invite_code }); expect(join.status).toBe(200);
  return { host, guest, room: await join.json<RoomSnapshotV2>() };
}
/** The player owns `packs`, as a purchase leaves them (pollen/wardrobe.ts spend). */
async function own(account: Account, ...packs: string[]): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
    for (const table of POLLEN_SHOP_TABLES) state.storage.sql.exec(table.schema.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
    for (const pack of packs) state.storage.sql.exec("INSERT INTO pollen_items VALUES (?,?,?,?)", pack, "pack", "bought", Date.now());
  });
}
const read = (roomId: string, account: Account, headers: Record<string, string>) => call(`/v2/rooms/${roomId}`, "GET", account, undefined, headers);
const list = (roomId: string, account: Account, headers: Record<string, string>) => call(`/v2/rooms/${roomId}/end-reactions`, "GET", account, undefined, headers);
const inbox = async (account: Account, headers: Record<string, string>) => (await call("/v1/room-inbox", "GET", account, undefined, headers)).json<{ rooms: { room_id: string; partner_reaction?: string }[] }>();
const tableSql = (roomId: string) => runInDurableObject(env.ROOMS_V2.getByName(roomId), async (_, state) =>
  state.storage.sql.exec<{ sql: string }>("SELECT sql FROM sqlite_master WHERE type='table' AND name='end_reactions'").toArray()[0]?.sql);

afterEach(async () => { await reset(); });

describe("reaction pack faces", () => {
  it("each belong to exactly one released pack, and every everyday face to none", () => {
    expect(PACK_FACES).toEqual(["heart_eyes", "proud", "wink", "wow", "crying", "dizzy"]);
    expect(offeredPacks()).toEqual(["garden_faces", "big_feelings"]);
    expect(CATALOG.pack_price).toBe(5000);
    expect(Object.fromEntries(PACK_FACES.map(face => [face, packOfFace(face)]))).toEqual({
      heart_eyes: "garden_faces", proud: "garden_faces", wink: "garden_faces", wow: "big_feelings", crying: "big_feelings", dizzy: "big_feelings" });
    for (const face of BASE_FACES) expect(packOfFace(face), face).toBeUndefined();
    // Each pack face stands in as an everyday face for phones that do not draw it.
    for (const face of PACK_FACES) { expect(BASE_FACES).toContain(PACK_FALLBACK[face]); expect(shownFace(face, false)).toBe(PACK_FALLBACK[face]); expect(shownFace(face, true)).toBe(face); }
    for (const face of BASE_FACES) expect(shownFace(face, false)).toBe(face);
    expect([...packsNeeded({ end_reaction: "wow", run_reactions: [{ tick: 1, id: "proud" }, { tick: 2, id: "happy" }, { tick: 3, id: "dizzy" }] })].sort()).toEqual(["big_feelings", "garden_faces"]);
    expect([...packsNeeded({ end_reaction: "happy", run_reactions: "nonsense" })]).toEqual([]);
  });

  it("are advertised only to phones that draw them", async () => {
    const player = await create();
    expect(await (await call("/v2/capabilities", "GET", player, undefined, FACES_ASK)).json()).not.toHaveProperty("face_packs_version");
    expect(await (await call("/v2/capabilities", "GET", player, undefined, ALL)).json()).toMatchObject({ face_packs_version: 1, end_reactions_version: 1, run_reactions_version: 1 });
  });

  it("are refused when the pack is not owned, keep nothing, and the same turn then goes through without them", async () => {
    const { host, guest, room } = await joined();
    await own(host, "garden_faces");
    const sent: Record<string, unknown> = body(room, firstA, { end_reaction: "wow", run_reactions: [{ tick: 12, id: "heart_eyes" }] });
    for (const headers of [ALL, OLD]) {
      const refused = await turn(room, host, sent, headers);
      expect(refused.status).toBe(403); expect(await errorCode(refused)).toBe(FACE_PACK_NOT_OWNED);
    }
    // A run reaction from an unowned pack is refused the same way.
    const track = await turn(room, host, { ...sent, end_reaction: "heart_eyes", run_reactions: [{ tick: 12, id: "crying" }] });
    expect(track.status).toBe(403); expect(await errorCode(track)).toBe(FACE_PACK_NOT_OWNED);
    // Nothing was kept: the room did not move and holds no face.
    expect((await (await read(room.room_id, guest, ALL)).json<RoomSnapshotV2>()).revision).toBe(room.revision);
    expect(await tableSql(room.room_id)).toBeUndefined();
    // The phone sends the very same turn and key again without the unowned face.
    const { end_reaction: _dropped, ...without } = sent; void _dropped;
    const again = await turn(room, host, without);
    expect(again.status).toBe(200);
    expect((await (await list(room.room_id, guest, ALL)).json<Faces & { run_reactions?: Tracks }>()).run_reactions?.tracks).toEqual({ [firstA.recording_hash]: [{ tick: 12, id: "heart_eyes" }] });
  });

  it("go through for the pack's owner and reach each phone as drawn or as its everyday stand-in", async () => {
    const { host, guest, room } = await joined();
    await own(host, "big_feelings", "garden_faces");
    const sent = await turn(room, host, body(room, firstA, { end_reaction: "wow", run_reactions: [{ tick: 12, id: "dizzy" }, { tick: 40, id: "happy" }] }));
    expect(sent.status).toBe(200);
    // A room's first face being a pack face makes today's table straight away.
    expect(await tableSql(room.room_id)).toBe(END_REACTIONS.schema);
    const hash = firstA.recording_hash;
    const drawn = await (await read(room.room_id, guest, ALL)).json<RoomSnapshotV2 & { end_reactions: Faces; run_reactions: Tracks }>();
    expect(drawn.end_reactions).toEqual({ schema_version: 1, faces: { [hash]: "wow" }, partner: "wow" });
    expect(drawn.run_reactions.tracks[hash]).toEqual([{ tick: 12, id: "dizzy" }, { tick: 40, id: "happy" }]);
    const older = await (await read(room.room_id, guest, OLD)).json<RoomSnapshotV2 & { end_reactions: Faces; run_reactions: Tracks }>();
    expect(older.end_reactions).toEqual({ schema_version: 1, faces: { [hash]: "surprised" }, partner: "surprised" });
    expect(older.run_reactions.tracks[hash]).toEqual([{ tick: 12, id: "knocked_out" }, { tick: 40, id: "happy" }]);
    // The rest of the read is the same bytes either way.
    const { end_reactions: _a, run_reactions: _b, ...plainNew } = drawn; const { end_reactions: _c, run_reactions: _d, ...plainOld } = older; void _a; void _b; void _c; void _d;
    expect(plainNew).toEqual(plainOld);
    // Replays' list and the room list follow the same rule.
    expect((await (await list(room.room_id, guest, ALL)).json<Faces>()).faces).toEqual({ [hash]: "wow" });
    expect((await (await list(room.room_id, guest, OLD)).json<Faces>()).faces).toEqual({ [hash]: "surprised" });
    expect((await inbox(guest, ALL)).rooms.find(entry => entry.room_id === room.room_id)?.partner_reaction).toBe("wow");
    expect((await inbox(guest, OLD)).rooms.find(entry => entry.room_id === room.room_id)?.partner_reaction).toBe("surprised");
    // The turn reply to the guest's own next turn carries the host's face, mapped for an older phone.
    const current = (await sent.json<MutationV2>()).room;
    const reply = await turn(current, guest, body(current, firstB, {}, middle), OLD);
    expect(reply.status).toBe(200);
    expect((await reply.json<MutationV2 & { end_reactions: Faces }>()).end_reactions.partner).toBe("surprised");
  });

  it("keep a room's table readable by older code until a pack face arrives, then rebuild it with every row kept", async () => {
    const { host, guest, room } = await joined();
    // Everyday faces make the table older code reads, as rooms did before this release.
    const first = await turn(room, host, body(room, firstA, { end_reaction: "happy" }));
    expect(first.status).toBe(200);
    expect(await tableSql(room.room_id)).toBe(LEGACY_SCHEMAS[0]);
    expect(isEndReactionsTable({ name: END_REACTIONS.name, sql: LEGACY_SCHEMAS[0] })).toBe(true);
    expect(isEndReactionsTable({ name: END_REACTIONS.name, sql: END_REACTIONS.schema })).toBe(true);
    expect(isEndReactionsTable({ name: END_REACTIONS.name, sql: LEGACY_SCHEMAS[0].replace("'heart'", "'other'") })).toBe(false);
    // The first pack face rebuilds it with today's schema inside its own turn.
    await own(guest, "garden_faces");
    const current = (await first.json<MutationV2>()).room;
    const second = await turn(current, guest, body(current, firstB, { end_reaction: "heart_eyes" }, middle));
    expect(second.status).toBe(200);
    expect(await tableSql(room.room_id)).toBe(END_REACTIONS.schema);
    expect((await (await list(room.room_id, host, ALL)).json<Faces>()).faces).toEqual({ [firstA.recording_hash]: "happy", [firstB.recording_hash]: "heart_eyes" });
    const leftovers = await runInDurableObject(env.ROOMS_V2.getByName(room.room_id), async (_, state) =>
      state.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE name LIKE 'end_reactions%'").toArray().map(row => row.name));
    expect(leftovers).toEqual(["end_reactions"]);
  });
});
