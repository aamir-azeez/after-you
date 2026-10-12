import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, expect, it } from "vitest";
import worker from "../src/index";
import { RELAY_KEY } from "../src/v2/protocol";
import { campaignAdmissionRequest } from "../src/v2/campaign-admission-intent";

// Clients that do not ask keep the published two-stage capability list. A
// client asks for chapters with more stages with X-AfterYou-Room-Level: 2, and
// any client may send up to 16 rules numbers when it joins.
type Account = { player_id: string; device_token: string };
type Capabilities = Record<string, unknown> & { chapters: Record<string, unknown>[] };
let requestNo = 0;
const allOn = { V2_ROOMS_ENABLED: "true", RELAY_PHOTOS_ENABLED: "true", PRESET_REACTIONS_ENABLED: "true", PHOTO_DELIVERY_ENABLED: "true", REPLAY_TRANSFER_ENABLED: "true",
  COOP_CHAPTERS_ENABLED: "true", HOUSE_CHAPTER_ENABLED: "true", JOURNEY_CHAPTERS_ENABLED: "true", FIRST_STEPS_ENABLED: "true", WISHING_WELL_CHAPTER_ENABLED: "true",
  LONG_WAY_HOME_V2_CHAPTER_ENABLED: "true", TURN_OF_THE_TIDE_CHAPTER_ENABLED: "true" };
async function call(path: string, method = "GET", account?: Account, body?: unknown, headers: Record<string, string> = {}): Promise<Response> {
  const configured: Env = { ...env }; Object.assign(configured, allOn);
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.17." + (++requestNo % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function account(): Promise<Account> { const r = await call("/v1/identity", "POST", undefined, {}); expect(r.status).toBe(201); return r.json<Account>(); }
afterEach(async () => { await reset(); });

it("keeps the headerless capability list two-stage and within old-client limits", async () => {
  const host = await account();
  const plain = await (await call("/v2/capabilities", "GET", host)).text();
  const levelOne = await (await call("/v2/capabilities", "GET", host, undefined, { "X-AfterYou-Room-Level": "1" })).text();
  const levelThree = await (await call("/v2/capabilities", "GET", host, undefined, { "X-AfterYou-Room-Level": "3" })).text();
  expect(levelOne).toBe(plain);
  expect(levelThree).toBe(plain);
  const body = JSON.parse(plain) as Capabilities;
  for (const key of ["room_level", "max_join_versions", "max_stages"]) expect(body).not.toHaveProperty(key);
  // 0.5.x refuses the whole response above 16 chapters, or above 8 rules for one chapter.
  expect(body.chapters.length).toBeGreaterThan(0);
  expect(body.chapters.length).toBeLessThanOrEqual(16);
  for (const row of body.chapters) {
    expect(row).not.toHaveProperty("stage_count");
    expect(((row.supported_simulation_versions as number[] | undefined) ?? [row.simulation_version]).length).toBeLessThanOrEqual(8);
  }
});

it("names stage counts and the join limit only for level-2 clients", async () => {
  const host = await account();
  const plain = await (await call("/v2/capabilities", "GET", host)).json<Capabilities>();
  const level2 = await (await call("/v2/capabilities", "GET", host, undefined, { "X-AfterYou-Room-Level": "2" })).json<Capabilities>();
  expect(level2).toMatchObject({ room_level: 2, max_join_versions: 16, max_stages: 8 });
  for (const row of level2.chapters) {
    expect(Number.isInteger(row.stage_count) && (row.stage_count as number) >= 1 && (row.stage_count as number) <= 8).toBe(true);
  }
  // Rows with two stages are exactly the level-1 rows, in the same order.
  const { room_level: _level, max_join_versions: _join, max_stages: _stages, ...rest } = level2;
  expect({ ...rest, chapters: level2.chapters.filter(row => row.stage_count === 2).map(({ stage_count: _count, ...row }) => row) }).toEqual(plain);
});

it("accepts up to 16 rules numbers on join and keeps the old refusal above that", async () => {
  const host = await account();
  const outcome = async (versions: number[]) => {
    const created = await call("/v2/rooms", "POST", host, { ...RELAY_KEY, idempotency_key: crypto.randomUUID() }); expect(created.status).toBe(200);
    const room = await created.json<{ invite_code: string }>(), guest = await account();
    const r = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code, supported_simulation_versions: versions });
    return `${r.status} ${r.status === 200 ? "ok" : (await r.json<{ error: { code: string } }>()).error.code}`;
  };
  expect(await outcome([2, 4, 5, 6, 7, 8, 9, 10])).toBe("200 ok");
  expect(await outcome([2, 4, 5, 6, 7, 8, 9, 10, 11])).toBe("200 ok");
  expect(await outcome(Array.from({ length: 16 }, (_, i) => i + 1))).toBe("200 ok");
  expect(await outcome(Array.from({ length: 17 }, (_, i) => i + 1))).toBe("422 unsupported_simulation_version");
  expect(await outcome([2, 2])).toBe("422 unsupported_simulation_version");
});

it("lets a campaign join name up to 16 rules numbers", () => {
  const join = (versions: number[]) => ({ schema_version: 2, idempotency_key: crypto.randomUUID(), invite_code: "A".repeat(20),
    campaign_key: { campaign_id: "c", campaign_version: 1, definition_hash: "0".repeat(64) }, supported_simulation_versions: versions });
  expect((campaignAdmissionRequest(join(Array.from({ length: 16 }, (_, i) => i + 1)), "join") as { supported_simulation_versions: number[] }).supported_simulation_versions).toHaveLength(16);
  expect(() => campaignAdmissionRequest(join(Array.from({ length: 17 }, (_, i) => i + 1)), "join")).toThrow();
});
