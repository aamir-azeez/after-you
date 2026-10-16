import { env } from "cloudflare:workers";
import { describe, expect, it, vi } from "vitest";

const production = vi.hoisted(() => ({ on: false }));
vi.mock("../src/v2/campaign-production", () => ({
  campaignProductionEnabled: () => production.on,
  requireCampaignProduction: () => { if (!production.on) throw new Error("campaign_unavailable"); }
}));

import { FLAG_VARS, commaList, flags, flagOn, type FlagName, type FlagVar, type ServerVars } from "../src/flags";
import { productList, reviewer } from "../src/play-entitlement";
import { MAX_JOIN_VERSIONS, routeV2 } from "../src/v2/routes";
import { advertisedChapters } from "../src/v2/chapters";
import { advertisedCampaigns } from "../src/v2/campaign-registry";
import { campaignProductionEnabled } from "../src/v2/campaign-production";
import { MAX_ROOM_STAGES } from "../src/v2/chapter-types";
import { HISTORY_HEADER } from "../src/v2/history";

type Loose = Record<string, unknown>;
const loose = (value: Loose) => value as ServerVars;
const ROWS = Object.entries(FLAG_VARS) as [FlagName, FlagVar][];
/** Every shape a var can take: wrangler strings, near misses, test booleans, null and an undefined value. Only "true" (and true, as tests pass it) is on. */
const VALUES: readonly [unknown, boolean][] = [["true", true], [true, true], ["false", false], ["TRUE", false], ["True", false], [" true", false], ["true ", false],
  ["1", false], ["yes", false], ["on", false], ["", false], [false, false], [1, false], [0, false], [null, false], [undefined, false]];

// Every *_ENABLED var the generated Env or ServerVars declares has a row in FLAG_VARS.
type Unlisted = Exclude<Extract<keyof Env | keyof ServerVars, `${string}_ENABLED`>, FlagVar>;
const everyEnabledVarListed: [Unlisted] extends [never] ? true : Unlisted = true;

describe("flags", () => {
  it("has one accessor per table row, and each var in one row only", () => {
    expect(everyEnabledVarListed).toBe(true);
    expect(Object.keys(flags).sort()).toEqual(ROWS.map(([name]) => name).sort());
    expect(new Set(ROWS.map(([, variable]) => variable)).size).toBe(ROWS.length);
  });
  it("lists every *_ENABLED var the worker is configured with", () => {
    const listed = new Set<string>(Object.values(FLAG_VARS));
    for (const key of Object.keys(env).filter(key => key.endsWith("_ENABLED"))) expect(listed.has(key), key).toBe(true);
  });
  it("turns each accessor on only for its own var set to exactly \"true\"", () => {
    for (const [set, variable] of ROWS) {
      for (const [value, on] of VALUES) {
        const vars = loose({ [variable]: value });
        for (const [name, own] of ROWS) {
          const label = `${name} with ${variable}=${JSON.stringify(value)}`;
          expect(flags[name](vars), label).toBe(name === set && on);
          expect(flagOn(vars, own), label).toBe(name === set && on);
        }
      }
    }
    for (const [name] of ROWS) expect(flags[name](loose({})), `${name} missing`).toBe(false);
  });
  it("reads the configured worker env, whose vars all default off", () => {
    for (const [name] of ROWS) expect(flags[name](env), name).toBe(false);
  });
});

// A frozen copy of the /v2/capabilities body before flags.ts.
function oldCapabilities(request: Request, env: Env): unknown {
  const roomLevel = request.headers.get("X-AfterYou-Room-Level") === "2" ? 2 : 1;
  return { api_version: 2,
    mutations_enabled: String(env.V2_ROOMS_ENABLED) === "true", recording_version: 2, simulation_version: 2,
    photo_uploads_enabled: String(env.V2_ROOMS_ENABLED) === "true" && String(env.RELAY_PHOTOS_ENABLED) === "true",
    preset_reactions_enabled: String(env.V2_ROOMS_ENABLED) === "true" && String(env.PRESET_REACTIONS_ENABLED) === "true",
    photo_delivery_enabled: String(env.PHOTO_DELIVERY_ENABLED) === "true",
    replay_transfer_version: String((env as Env & { REPLAY_TRANSFER_ENABLED?: string }).REPLAY_TRANSFER_ENABLED) === "true" ? 1 : 0,
    ...(campaignProductionEnabled() ? { campaign_control_version: 2, campaign_redo_version: 1 } : {}),
    campaign_creation_enabled: String(env.V2_ROOMS_ENABLED) === "true" && String(env.CAMPAIGN_CREATION_ENABLED) === "true" && advertisedCampaigns(env).length > 0,
    campaign_mutations_enabled: campaignProductionEnabled() && String(env.V2_ROOMS_ENABLED) === "true" && String(env.CAMPAIGN_MUTATIONS_ENABLED) === "true",
    campaign_definitions: advertisedCampaigns(env),
    chapters: advertisedChapters(env, roomLevel),
    ...(roomLevel >= 2 ? { room_level: 2, max_join_versions: MAX_JOIN_VERSIONS, max_stages: MAX_ROOM_STAGES } : {}),
    ...(request.headers.get(HISTORY_HEADER) === "1" ? { history_version: 1, history_offload_enabled: String((env as Env & { HISTORY_OFFLOAD_ENABLED?: string }).HISTORY_OFFLOAD_ENABLED) === "true" } : {}),
    validation: "structural_client_replay_required" };
}
const CAPABILITY_VARS = ["V2_ROOMS_ENABLED", "RELAY_PHOTOS_ENABLED", "PRESET_REACTIONS_ENABLED", "PHOTO_DELIVERY_ENABLED",
  "REPLAY_TRANSFER_ENABLED", "CAMPAIGN_CREATION_ENABLED", "CAMPAIGN_MUTATIONS_ENABLED", "HISTORY_OFFLOAD_ENABLED"];
const CHAPTER_VARS = ["FIRST_STEPS_ENABLED", "COOP_CHAPTERS_ENABLED", "HOUSE_CHAPTER_ENABLED", "JOURNEY_CHAPTERS_ENABLED"];

describe("/v2/capabilities", () => {
  it("answers byte for byte as before for every combination of the flags it reads", async () => {
    const player = "c".repeat(22), seen = new Set<string>();
    for (const productionOn of [false, true]) {
      production.on = productionOn;
      for (const [on, off] of [["true", "false"], [true, undefined], ["TRUE", ""]] as const) {
        for (let mask = 0; mask < 1 << CAPABILITY_VARS.length; mask++) {
          const vars: Loose = { ...env };
          CAPABILITY_VARS.forEach((name, bit) => { vars[name] = mask & (1 << bit) ? on : off; });
          // Campaign creation also needs every campaign chapter creatable; follow the lowest bit.
          for (const name of CHAPTER_VARS) vars[name] = mask & 1 ? "true" : "false";
          for (const headers of [{}, { "X-AfterYou-Room-Level": "2" }, { [HISTORY_HEADER]: "1" }, { "X-AfterYou-Room-Level": "2", [HISTORY_HEADER]: "1" }] as Record<string, string>[]) {
            const request = new Request("https://after-you.test/v2/capabilities", { headers });
            const response = await routeV2(request, "/v2/capabilities", player, vars as unknown as Env);
            const label = `production ${productionOn} on ${JSON.stringify(on)} mask ${mask} ${JSON.stringify(headers)}`;
            expect(response.status, label).toBe(200);
            const body = await response.text();
            expect(body, label).toBe(JSON.stringify(oldCapabilities(request, vars as unknown as Env)));
            const parsed = JSON.parse(body) as Record<string, unknown>;
            for (const key of ["mutations_enabled", "photo_uploads_enabled", "preset_reactions_enabled", "photo_delivery_enabled", "campaign_creation_enabled", "campaign_mutations_enabled", "history_offload_enabled"])
              if (parsed[key] === true) seen.add(key);
            if (parsed.replay_transfer_version === 1) seen.add("replay_transfer_version");
          }
        }
      }
    }
    production.on = false;
    // The matrix reaches every capability's on state, so each comparison above is not vacuous.
    expect([...seen].sort()).toEqual(["campaign_creation_enabled", "campaign_mutations_enabled", "history_offload_enabled", "mutations_enabled",
      "photo_delivery_enabled", "photo_uploads_enabled", "preset_reactions_enabled", "replay_transfer_version"]);
  });
  it("adds room_leave_version only while leaving finished rooms is on", async () => {
    const read = async (vars: Loose) => JSON.parse(await (await routeV2(new Request("https://after-you.test/v2/capabilities"), "/v2/capabilities", "c".repeat(22), vars as unknown as Env)).text()) as Loose;
    const off = await read({ ...env });
    expect(off).not.toHaveProperty("room_leave_version");
    expect(await read({ ...env, FINISHED_ROOM_LEAVE_ENABLED: "true" })).toEqual({ ...off, room_leave_version: 1 });
  });
});

// Frozen copies of the comma-list reads in play-entitlement.ts and store-entitlement.ts before commaList.
function oldPlayProducts(raw: string | undefined): string[] | null {
  const subscriptionProducts = (raw ?? "").split(",").map(value => value.trim()).filter(Boolean);
  if ((raw ?? "").trim() && (subscriptionProducts.length > 8 || !subscriptionProducts.every(value => /^prod[A-Za-z0-9_-]+$/.test(value)))) return null;
  return subscriptionProducts;
}
function oldStoreProducts(raw: string | undefined): string[] | null {
  const values = (raw ?? "").split(",").map(value => value.trim()).filter(Boolean);
  if ((raw ?? "").trim() && (values.length > 8 || !values.every(value => /^prod[A-Za-z0-9_-]+$/.test(value)))) return null;
  return values;
}
function oldReviewer(raw: string | undefined, playerId: string): boolean {
  const reviewers = (raw ?? "").split(",").map(value => value.trim()).filter(Boolean);
  return reviewers.length <= 16 && reviewers.every(value => /^[A-Za-z0-9_-]{22}$/.test(value)) && reviewers.includes(playerId);
}
const ID = "r".repeat(22);
const LISTS: readonly (string | undefined)[] = [undefined, "", " ", ",", " , ", "prodA", " prodA ", "prodA,prodB", "prodA, prodB", "prodA,,prodB", "prodA,", ",prodA",
  "prodA,bad", "bad", "PRODA", "prod", "prod-x_9", Array.from({ length: 8 }, (_, i) => "prod" + i).join(","), Array.from({ length: 9 }, (_, i) => "prod" + i).join(","),
  ID, ` ${ID} `, `${ID},${"s".repeat(22)}`, `${ID},short`, Array.from({ length: 16 }, (_, i) => i === 0 ? ID : String(i).padStart(22, "x")).join(","),
  Array.from({ length: 17 }, (_, i) => i === 0 ? ID : String(i).padStart(22, "x")).join(","), "r".repeat(23), "\tprodA\n"];

describe("comma-list vars", () => {
  it("split, validate and match exactly as the old Play and store copies", () => {
    for (const raw of LISTS) {
      expect(commaList(raw), JSON.stringify(raw)).toEqual((raw ?? "").split(",").map(value => value.trim()).filter(Boolean));
      expect(productList(raw), JSON.stringify(raw)).toEqual(oldPlayProducts(raw));
      expect(productList(raw), JSON.stringify(raw)).toEqual(oldStoreProducts(raw));
      for (const player of [ID, "s".repeat(22), "x"]) expect(reviewer({ REVENUECAT_REVIEWER_IDS: raw }, player), `${JSON.stringify(raw)} ${player}`).toBe(oldReviewer(raw, player));
    }
  });
});
