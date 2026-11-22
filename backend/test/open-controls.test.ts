import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { chapter, checkpointV2, initialCheckpoint, recordingV2, acceptedRecording } from "../src/v2/protocol";
import { conservatoryV2, longWayHomeV3, turnOfTheTideV3, CONSERVATORY_V2_HASH, LONG_WAY_HOME_V3_HASH, TURN_OF_THE_TIDE_V3_HASH } from "../src/v2/protocol-journey";
import { advertisedChapters, chapterFlag, creatable } from "../src/v2/chapters";
import { COMFORT_RULES, comfortRules, openControls, openTurns, sharedBall, tideRules, type ChapterAdapter, type ChapterCheckpoint, type ChapterRecording } from "../src/v2/chapter-types";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import homeDefinition from "../../game/tests/fixtures/journey/long-way-home-v3-definition.json";
import homeInitial from "../../game/tests/fixtures/journey/long-way-home-v3-initial-checkpoint.json";
import homePathA from "../../game/tests/fixtures/journey/long-way-home-v3-the-path-you-leave-a.json";
import homePathB from "../../game/tests/fixtures/journey/long-way-home-v3-the-path-you-leave-b.json";
import homePathC from "../../game/tests/fixtures/journey/long-way-home-v3-the-path-you-leave-c.json";
import homePathEnd from "../../game/tests/fixtures/journey/long-way-home-v3-the-path-you-leave-checkpoint.json";
import homePlaceA from "../../game/tests/fixtures/journey/long-way-home-v3-a-place-beside-you-a.json";
import homePlaceB from "../../game/tests/fixtures/journey/long-way-home-v3-a-place-beside-you-b.json";
import homePlaceC from "../../game/tests/fixtures/journey/long-way-home-v3-a-place-beside-you-c.json";
import homePlaceEnd from "../../game/tests/fixtures/journey/long-way-home-v3-a-place-beside-you-checkpoint.json";
import tideDefinition from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-definition.json";
import tideInitial from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-initial-checkpoint.json";
import tideSetA from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-a.json";
import tideSetB from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-b.json";
import tideSetC from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-c.json";
import tideSetEnd from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-checkpoint.json";
import tideSlackA from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-slack-water-a.json";
import tideSlackB from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-slack-water-b.json";
import tideSlackC from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-slack-water-c.json";
import tideSlackEnd from "../../game/tests/fixtures/journey/turn-of-the-tide-v3-slack-water-checkpoint.json";
import roomsDefinition from "../../game/tests/fixtures/journey/conservatory-v2-definition.json";
import roomsInitial from "../../game/tests/fixtures/journey/conservatory-v2-initial-checkpoint.json";
import roomsAboveA from "../../game/tests/fixtures/journey/conservatory-v2-a-light-above-a.json";
import roomsAboveB from "../../game/tests/fixtures/journey/conservatory-v2-a-light-above-b.json";
import roomsAboveC from "../../game/tests/fixtures/journey/conservatory-v2-a-light-above-c.json";
import roomsAboveEnd from "../../game/tests/fixtures/journey/conservatory-v2-a-light-above-checkpoint.json";
import roomsReturnA from "../../game/tests/fixtures/journey/conservatory-v2-the-way-light-returns-a.json";
import roomsReturnB from "../../game/tests/fixtures/journey/conservatory-v2-the-way-light-returns-b.json";
import roomsReturnC from "../../game/tests/fixtures/journey/conservatory-v2-the-way-light-returns-c.json";
import roomsReturnEnd from "../../game/tests/fixtures/journey/conservatory-v2-the-way-light-returns-checkpoint.json";
import { unpackRecording } from "../src/v2/recording-codec";
import bundledHome from "../src/v2/long-way-home-v3.json";
import bundledHomeInitial from "../src/v2/long-way-home-v3-initial.json";
import bundledTide from "../src/v2/turn-of-the-tide-v3.json";
import bundledTideInitial from "../src/v2/turn-of-the-tide-v3-initial.json";
import bundledRooms from "../src/v2/conservatory-v2.json";
import bundledRoomsInitial from "../src/v2/conservatory-v2-initial.json";
import { highAndLowV2, houseForTwoV2, rollingHomeV2, HIGH_AND_LOW_V2_HASH, HOUSE_V2_HASH, ROLLING_HOME_V2_HASH } from "../src/v2/protocol-cooperative";
import highDefinition from "../../game/tests/fixtures/cooperative/high-and-low-v2-definition.json";
import highInitial from "../../game/tests/fixtures/cooperative/high-and-low-v2-initial-checkpoint.json";
import highUpperA from "../../game/tests/fixtures/cooperative/high-and-low-v2-upper-path-a.json";
import highUpperB from "../../game/tests/fixtures/cooperative/high-and-low-v2-upper-path-b.json";
import highUpperC from "../../game/tests/fixtures/cooperative/high-and-low-v2-upper-path-c.json";
import highUpperEnd from "../../game/tests/fixtures/cooperative/high-and-low-v2-upper-path-checkpoint.json";
import highDownA from "../../game/tests/fixtures/cooperative/high-and-low-v2-down-and-around-a.json";
import highDownB from "../../game/tests/fixtures/cooperative/high-and-low-v2-down-and-around-b.json";
import highDownC from "../../game/tests/fixtures/cooperative/high-and-low-v2-down-and-around-c.json";
import highDownEnd from "../../game/tests/fixtures/cooperative/high-and-low-v2-down-and-around-checkpoint.json";
import bundledHigh from "../src/v2/high-and-low-v2.json";
import bundledHighInitial from "../src/v2/high-and-low-v2-initial.json";
import rollingDefinition from "../../game/tests/fixtures/cooperative/rolling-home-v2-definition.json";
import rollingInitial from "../../game/tests/fixtures/cooperative/rolling-home-v2-initial-checkpoint.json";
import rollingFriendA from "../../game/tests/fixtures/cooperative/rolling-home-v2-weight-of-a-friend-a.json";
import rollingFriendB from "../../game/tests/fixtures/cooperative/rolling-home-v2-weight-of-a-friend-b.json";
import rollingFriendC from "../../game/tests/fixtures/cooperative/rolling-home-v2-weight-of-a-friend-c.json";
import rollingFriendEnd from "../../game/tests/fixtures/cooperative/rolling-home-v2-weight-of-a-friend-checkpoint.json";
import rollingHomeA from "../../game/tests/fixtures/cooperative/rolling-home-v2-bring-it-home-a.json";
import rollingHomeB from "../../game/tests/fixtures/cooperative/rolling-home-v2-bring-it-home-b.json";
import rollingHomeC from "../../game/tests/fixtures/cooperative/rolling-home-v2-bring-it-home-c.json";
import rollingHomeEnd from "../../game/tests/fixtures/cooperative/rolling-home-v2-bring-it-home-checkpoint.json";
import bundledRolling from "../src/v2/rolling-home-v2.json";
import bundledRollingInitial from "../src/v2/rolling-home-v2-initial.json";
import houseDefinition from "../../game/tests/fixtures/cooperative/a-house-for-two-v2-definition.json";
import houseInitial from "../../game/tests/fixtures/cooperative/a-house-for-two-v2-initial-checkpoint.json";
import houseOpenA from "../../game/tests/fixtures/cooperative/a-house-for-two-v2-open-the-house-a.json";
import houseOpenB from "../../game/tests/fixtures/cooperative/a-house-for-two-v2-open-the-house-b.json";
import houseOpenC from "../../game/tests/fixtures/cooperative/a-house-for-two-v2-open-the-house-c.json";
import houseOpenEnd from "../../game/tests/fixtures/cooperative/a-house-for-two-v2-open-the-house-checkpoint.json";
import houseBelowA from "../../game/tests/fixtures/cooperative/a-house-for-two-v2-the-room-below-a.json";
import houseBelowB from "../../game/tests/fixtures/cooperative/a-house-for-two-v2-the-room-below-b.json";
import houseBelowC from "../../game/tests/fixtures/cooperative/a-house-for-two-v2-the-room-below-c.json";
import houseBelowEnd from "../../game/tests/fixtures/cooperative/a-house-for-two-v2-the-room-below-checkpoint.json";
import bundledHouse from "../src/v2/a-house-for-two-v2.json";
import bundledHouseInitial from "../src/v2/a-house-for-two-v2-initial.json";
import { withConfig } from "./config";
import { LEGACY_CHAPTERS } from "../src/v2/legacy-chapters";
// The published chapters as older apps hold them, which room level 2 lists after the rows (legacy-chapters.ts).
const current = <T extends { definition_hash: string }>(items: T[]): T[] => items.filter(item => !LEGACY_CHAPTERS.some(entry => entry.key.definition_hash === item.definition_hash));
import { grantFullJourney } from "./full-journey";

/** A fixture checkpoint as an open turns room takes it: no proof nests in it (v2/open-turns.ts fingerprints), and its hash never covered one. */
function flat<T extends object>(checkpoint: T): Omit<T, "proof"> { const { proof: _proof, ...rest } = checkpoint as T & { proof?: unknown }; void _proof; return rest; }
type Account = { player_id: string; device_token: string };
type Chain = { name: string; adapter: ChapterAdapter; hash: string; rules: number; flag: string; definition: unknown; initial: unknown; bundled: unknown; bundledInitial: unknown;
  /** Each stage's first turn, its second turn (a pass), its closing third turn and its checkpoint (open turns). */
  stages: [unknown, unknown, unknown, unknown][] };
const CHAINS: Chain[] = [
  { name: "long-way-home@3", adapter: longWayHomeV3, hash: LONG_WAY_HOME_V3_HASH, rules: 14, flag: "LONG_WAY_HOME_V3_CHAPTER_ENABLED", definition: homeDefinition, initial: homeInitial,
    bundled: bundledHome, bundledInitial: bundledHomeInitial, stages: [[homePathA, homePathB, homePathC, flat(homePathEnd)], [homePlaceA, homePlaceB, homePlaceC, flat(homePlaceEnd)]] },
  { name: "turn-of-the-tide@3", adapter: turnOfTheTideV3, hash: TURN_OF_THE_TIDE_V3_HASH, rules: 15, flag: "TURN_OF_THE_TIDE_V3_CHAPTER_ENABLED", definition: tideDefinition, initial: tideInitial,
    bundled: bundledTide, bundledInitial: bundledTideInitial, stages: [[tideSetA, tideSetB, tideSetC, flat(tideSetEnd)], [tideSlackA, tideSlackB, tideSlackC, flat(tideSlackEnd)]] },
  { name: "conservatory@2", adapter: conservatoryV2, hash: CONSERVATORY_V2_HASH, rules: 14, flag: "CONSERVATORY_V2_CHAPTER_ENABLED", definition: roomsDefinition, initial: roomsInitial,
    bundled: bundledRooms, bundledInitial: bundledRoomsInitial, stages: [[roomsAboveA, roomsAboveB, roomsAboveC, flat(roomsAboveEnd)], [roomsReturnA, roomsReturnB, roomsReturnC, flat(roomsReturnEnd)]] },
  // The cooperative family on the same open turns (protocol-cooperative.ts): both players end at each bell.
  { name: "high-and-low@2", adapter: highAndLowV2, hash: HIGH_AND_LOW_V2_HASH, rules: 14, flag: "HIGH_AND_LOW_V2_CHAPTER_ENABLED", definition: highDefinition, initial: highInitial,
    bundled: bundledHigh, bundledInitial: bundledHighInitial, stages: [[highUpperA, highUpperB, highUpperC, flat(highUpperEnd)], [highDownA, highDownB, highDownC, flat(highDownEnd)]] },
  // The shared ball (17): both players push one ball; Rolling Home's last stage ends with it in its cradle and both players home.
  { name: "rolling-home@2", adapter: rollingHomeV2, hash: ROLLING_HOME_V2_HASH, rules: 17, flag: "ROLLING_HOME_V2_CHAPTER_ENABLED", definition: rollingDefinition, initial: rollingInitial,
    bundled: bundledRolling, bundledInitial: bundledRollingInitial, stages: [[rollingFriendA, rollingFriendB, rollingFriendC, flat(rollingFriendEnd)], [rollingHomeA, rollingHomeB, rollingHomeC, flat(rollingHomeEnd)]] },
  { name: "a-house-for-two@2", adapter: houseForTwoV2, hash: HOUSE_V2_HASH, rules: 17, flag: "A_HOUSE_FOR_TWO_V2_CHAPTER_ENABLED", definition: houseDefinition, initial: houseInitial,
    bundled: bundledHouse, bundledInitial: bundledHouseInitial, stages: [[houseOpenA, houseOpenB, houseOpenC, flat(houseOpenEnd)], [houseBelowA, houseBelowB, houseBelowC, flat(houseBelowEnd)]] },
];
// 0.8.1 and older: none of them offers 12 or 13 (11 is the Lighthouse room's).
const OLD_CLIENTS = [[2, 4, 5, 6, 7, 8, 9, 10], [2, 4, 5, 6, 7, 8, 9, 10, 11], [2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]], NEW_CLIENT = [2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
const key = () => crypto.randomUUID();
let requestNo = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, overrides: Record<string, unknown> = {}): Promise<Response> {
  const configured: Env = withConfig({ ...env, ...overrides });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.14." + (++requestNo % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function account(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
async function submit(room: RoomSnapshotV2, owner: Account, recording: unknown, checkpoint: unknown, flags: Record<string, unknown>): Promise<MutationV2> {
  const body = { base_revision: room.revision, branch: room.branch, idempotency_key: key(), recording, ...(checkpoint ? { checkpoint } : {}) };
  const response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", owner, body, flags); expect(response.status).toBe(200); return response.json<MutationV2>();
}
async function rehash(input: Record<string, unknown>): Promise<Record<string, unknown>> {
  const body = { ...input }; delete body.checkpoint_hash; delete body.proof;
  return { ...input, checkpoint_hash: await digest(canonicalJson(body)) };
}
async function records(chain: Chain, index: number): Promise<[ChapterRecording, ChapterRecording, ChapterRecording]> {
  const [a, b, c] = chain.stages[index];
  return [await recordingV2(a, chain.adapter.key) as ChapterRecording, await recordingV2(b, chain.adapter.key) as ChapterRecording, await recordingV2(c, chain.adapter.key) as ChapterRecording];
}
async function stageOne(chain: Chain): Promise<ChapterCheckpoint> {
  const [a, b, c] = await records(chain, 0);
  return checkpointV2(chain.stages[0][3], initialCheckpoint(chain.adapter.key) as ChapterCheckpoint, a, c, [b]);
}
afterEach(async () => { await reset(); });

describe("open controls (rules 12 and 13)", () => {
  it("numbers the open rules apart from every published one", () => {
    expect(COMFORT_RULES).toEqual([8, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]);
    expect([9, 10, 11, 12, 13, 14, 15, 16, 17].map(openControls)).toEqual([false, false, false, true, true, true, true, true, true]);
    expect([9, 10, 11, 12, 13, 14, 15, 16, 17].map(tideRules)).toEqual([false, true, false, false, true, false, true, true, false]);
    // 17 is 14 with the shared ball: open turns, no tide.
    expect([14, 15, 16, 17].map(sharedBall)).toEqual([false, false, false, true]); expect(openTurns(17)).toBe(true);
    expect(comfortRules(11)).toBe(false);
  });
  for (const chain of CHAINS) {
    it(`${chain.name}: bundles its native definition, pins rules ${chain.rules}, and is only created behind its flag`, async () => {
      expect(chain.bundled).toEqual(chain.definition); expect(chain.bundledInitial).toEqual(chain.initial);
      expect(await digest(canonicalJson(chain.definition))).toBe(chain.hash);
      expect((chain.definition as { simulation_version: number }).simulation_version).toBe(chain.rules);
      expect(chain.adapter).toMatchObject({ simulation_version: chain.rules, supported_simulation_versions: [chain.rules], require_supported_simulation_on_join: true });
      expect(chapter(chain.adapter.key)).toBe(chain.adapter);
      expect(chapterFlag(chain.adapter)).toBe(chain.flag);
      expect(creatable(chain.adapter, withConfig({ ...env }) as Env)).toBe(false);
      expect(advertisedChapters(withConfig({ ...env }) as Env, 2).some(item => item.level_id === chain.adapter.key.level_id && item.level_version === chain.adapter.key.level_version)).toBe(false);
      const on = withConfig({ ...env, [chain.flag]: "true" }) as Env;
      expect(creatable(chain.adapter, on)).toBe(true);
      expect(current(advertisedChapters(on, 2)).at(-1)).toMatchObject({ ...chain.adapter.key, supported_simulation_versions: [chain.rules] });
      // No control in it names an owner.
      for (const stage of (chain.definition as { stages: Record<string, { owner_slot?: string }[]>[] }).stages)
        for (const kind of ["controls", "levers", "pressure_pads"]) for (const item of stage[kind] ?? []) expect(item, `${kind} ${JSON.stringify(item)}`).not.toHaveProperty("owner_slot");
    });
    it(`${chain.name}: accepts the native chain`, async () => {
      let previous = initialCheckpoint(chain.adapter.key) as ChapterCheckpoint;
      for (let index = 0; index < chain.stages.length; index++) {
        const [a, b, c] = await records(chain, index);
        expect(acceptedRecording(a) && acceptedRecording(b) && acceptedRecording(c)).toBe(true);
        previous = await checkpointV2(chain.stages[index][3], previous, a, c, [b]);
        expect(previous).toEqual(chain.stages[index][3]);
      }
      // Its turns are packed, as open turns always record; the same turn as JSON is refused.
      const { packed, ...rest } = chain.stages[0][0] as Record<string, any>;
      expect(typeof packed).toBe("string");
      const json = { ...rest, ...unpackRecording(packed, rest.duration_ticks, rest.final_state_hash, rest.duration_ticks) };
      await expect(recordingV2(json, chain.adapter.key)).rejects.toMatchObject({ code: "packed_recording_required" });
    });
  }
  it("ends an open turns stage only with both players at its goal", async () => {
    // Long Way Home@3's homecoming ends with both players at the second window; one of them away is refused.
    const chain = CHAINS[0], first = await stageOne(chain), [a, b, c] = await records(chain, 1);
    const end = structuredClone(flat(homePlaceEnd)) as Record<string, any>;
    expect(end.players.p0).toMatchObject({ x: 1408, z: 108, surface_id: "home-room" });
    expect(end.players.p1).toMatchObject({ x: 1408, z: 72, surface_id: "home-room" });
    const away = structuredClone(end); away.players.p1 = { ...away.players.p1, x: 1200, z: 32 };
    await expect(checkpointV2(await rehash(away), first, a, c, [b])).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
  });
  it("ends a cooperative open turns stage only with both players at its bell", async () => {
    // High and Low@2's upper path ends with both players at the loft bell; one of them left on the loft away from it is refused.
    const chain = CHAINS.find(row => row.name === "high-and-low@2")!, [a, b, c] = await records(chain, 0);
    const end = structuredClone(flat(highUpperEnd)) as Record<string, any>;
    expect(end.players.p0).toMatchObject({ surface_id: "loft" }); expect(end.players.p1).toMatchObject({ surface_id: "loft" });
    const away = structuredClone(end); away.players.p0 = { ...away.players.p0, x: 0, z: 0 };
    await expect(checkpointV2(await rehash(away), initialCheckpoint(chain.adapter.key) as ChapterCheckpoint, a, c, [b])).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
  });
  it("ends a ball home stage only with the ball in its cradle and both players on its floor", async () => {
    // Rolling Home@2's Bring It Home: the ball fitted at the cradle's centre, both players home.
    const chain = CHAINS.find(row => row.name === "rolling-home@2")!, [firstA, firstB, firstC] = await records(chain, 0);
    const first = await checkpointV2(chain.stages[0][3], initialCheckpoint(chain.adapter.key) as ChapterCheckpoint, firstA, firstC, [firstB]);
    const [a, b, c] = await records(chain, 1);
    const end = structuredClone(flat(rollingHomeEnd)) as Record<string, any>, ball = end.mechanisms.props["round-ball"];
    expect(ball).toMatchObject({ status: "fitted", socket_id: "home-cradle", holder_slot: "", x: 1376, z: 0, surface_id: "home" });
    expect(end.players.p0).toMatchObject({ surface_id: "home" }); expect(end.players.p1).toMatchObject({ surface_id: "home" });
    const away = structuredClone(end); away.players.p0 = { x: 900, z: 160, height: 0, surface_id: "far-bank" };
    await expect(checkpointV2(await rehash(away), first, a, c, [b])).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
    const out = structuredClone(end); out.mechanisms.props["round-ball"] = { ...ball, status: "free", socket_id: "", x: 1300 };
    await expect(checkpointV2(await rehash(out), first, a, c, [b])).rejects.toMatchObject({ code: "checkpoint_prop_mismatch" });
    const off = structuredClone(end); off.mechanisms.props["round-ball"] = { ...ball, x: 1370 };
    await expect(checkpointV2(await rehash(off), first, a, c, [b])).rejects.toMatchObject({ code: "checkpoint_prop_mismatch" });
    const held = structuredClone(end); held.mechanisms.props["round-ball"] = { ...ball, holder_slot: "p0" };
    await expect(checkpointV2(await rehash(held), first, a, c, [b])).rejects.toMatchObject({ code: "checkpoint_prop_mismatch" });
  });
  it("keeps a shared ball free and on a floor it may rest on until its cradle", async () => {
    // Weight of a Friend ends with the ball free on the middle island's pad; fitted there, or left on a crossing that is not kept, is refused.
    const chain = CHAINS.find(row => row.name === "rolling-home@2")!, [a, b, c] = await records(chain, 0), opening = initialCheckpoint(chain.adapter.key) as ChapterCheckpoint;
    const end = structuredClone(flat(rollingFriendEnd)) as Record<string, any>, ball = end.mechanisms.props["round-ball"];
    expect(ball).toMatchObject({ status: "free", socket_id: "", holder_slot: "", surface_id: "middle" });
    const fitted = structuredClone(end); fitted.mechanisms.props["round-ball"] = { ...ball, status: "fitted", socket_id: "home-cradle" };
    await expect(checkpointV2(await rehash(fitted), opening, a, c, [b])).rejects.toMatchObject({ code: "checkpoint_prop_mismatch" });
    const stranded = structuredClone(end); stranded.mechanisms.props["round-ball"] = { ...ball, x: 1040, z: 0, surface_id: "far-home" };
    await expect(checkpointV2(await rehash(stranded), opening, a, c, [b])).rejects.toMatchObject({ code: "checkpoint_surface_mismatch" });
    const extra = structuredClone(end); extra.mechanisms.props["round-ball"] = { ...ball, owner: "p0" };
    await expect(checkpointV2(await rehash(extra), opening, a, c, [b])).rejects.toMatchObject({ code: "unexpected_fields" });
  });
  it("keeps the tide rules on 15: no route latches", async () => {
    const chain = CHAINS[1], [a, b, c] = await records(chain, 0);
    const kept = structuredClone(flat(tideSetEnd)) as Record<string, any>; kept.mechanisms.latched_bridges = [kept.players.p0.surface_id];
    await expect(checkpointV2(await rehash(kept), initialCheckpoint(chain.adapter.key) as ChapterCheckpoint, a, c, [b])).rejects.toMatchObject({ code: "checkpoint_mechanism_mismatch" });
  });
  it("refuses a guest whose client never offered the open rules, and plays a room to completion", async () => {
    // Turn of the Tide@3 is Full Journey, so its host holds a tester grant.
    for (const chain of [CHAINS[1]]) {
      const flags = { [chain.flag]: "true" }, host = await account(), oldGuest = await account(), guest = await account();
      await grantFullJourney(host);
      const created = await call("/v2/rooms", "POST", host, { ...chain.adapter.key, idempotency_key: key() }, flags);
      expect(created.status, chain.name).toBe(200);
      const room = await created.json<RoomSnapshotV2>();
      for (const versions of [undefined, ...OLD_CLIENTS]) {
        const rejected = await call("/v2/rooms/join", "POST", oldGuest, { invite_code: room.invite_code, ...(versions ? { supported_simulation_versions: versions } : {}) }, flags);
        expect(rejected.status, chain.name).toBe(422); expect(await rejected.json()).toMatchObject({ error: { code: "unsupported_simulation_version" } });
      }
      const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, supported_simulation_versions: NEW_CLIENT }, flags);
      expect(joined.status, chain.name).toBe(200);
      // Each stage: the first turn, a pass, then the first player's closing turn with both at the goal.
      const [[setA, setB, setC, setEnd], [nextA, nextB, nextC, nextEnd]] = chain.stages;
      const first = (setA as { player_slot: string }).player_slot === "p0" ? host : guest, second = first === host ? guest : host;
      const one = await submit(await joined.json<RoomSnapshotV2>(), first, setA, undefined, flags), two = await submit(one.room, second, setB, undefined, flags);
      const three = await submit(two.room, first, setC, setEnd, flags);
      expect(three.room).toMatchObject({ stage_index: 1, checkpoint: setEnd });
      const four = await submit(three.room, second, nextA, undefined, flags), five = await submit(four.room, first, nextB, undefined, flags);
      const six = await submit(five.room, second, nextC, nextEnd, flags);
      expect(six.room).toMatchObject({ stage_index: 2, active_role: "complete", checkpoint: nextEnd });
    }
  });
});
