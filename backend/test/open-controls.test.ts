import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { chapter, checkpointV2, initialCheckpoint, recordingV2, acceptedRecording } from "../src/v2/protocol";
import { conservatoryV2, longWayHomeV3, turnOfTheTideV3, CONSERVATORY_V2_HASH, LONG_WAY_HOME_V3_HASH, TURN_OF_THE_TIDE_V3_HASH } from "../src/v2/protocol-journey";
import { advertisedChapters, chapterFlag, creatable } from "../src/v2/chapters";
import { COMFORT_RULES, comfortRules, openControls, tideRules, type ChapterAdapter, type ChapterCheckpoint, type ChapterRecording } from "../src/v2/chapter-types";
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
import { withConfig } from "./config";

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
    expect(COMFORT_RULES).toEqual([8, 9, 10, 12, 13, 14, 15]);
    expect([9, 10, 11, 12, 13, 14, 15].map(openControls)).toEqual([false, false, false, true, true, true, true]);
    expect([9, 10, 11, 12, 13, 14, 15].map(tideRules)).toEqual([false, true, false, false, true, false, true]);
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
      expect(advertisedChapters(on, 2).at(-1)).toMatchObject({ ...chain.adapter.key, supported_simulation_versions: [chain.rules] });
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
    expect(end.players.p0).toMatchObject({ x: 1408, z: 96, surface_id: "home-room" });
    expect(end.players.p1).toMatchObject({ x: 1408, z: 96, surface_id: "home-room" });
    const away = structuredClone(end); away.players.p1 = { ...away.players.p1, x: 1200, z: 32 };
    await expect(checkpointV2(await rehash(away), first, a, c, [b])).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
  });
  it("keeps the tide rules on 15: no route latches", async () => {
    const chain = CHAINS[1], [a, b, c] = await records(chain, 0);
    const kept = structuredClone(flat(tideSetEnd)) as Record<string, any>; kept.mechanisms.latched_bridges = [kept.players.p0.surface_id];
    await expect(checkpointV2(await rehash(kept), initialCheckpoint(chain.adapter.key) as ChapterCheckpoint, a, c, [b])).rejects.toMatchObject({ code: "checkpoint_mechanism_mismatch" });
  });
  it("refuses a guest whose client never offered the open rules, and plays a room to completion", async () => {
    // Turn of the Tide@3 is free, so a room needs no purchase.
    for (const chain of [CHAINS[1]]) {
      const flags = { [chain.flag]: "true" }, host = await account(), oldGuest = await account(), guest = await account();
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
