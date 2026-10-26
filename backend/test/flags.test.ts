import { env } from "cloudflare:workers";
import { describe, expect, it, vi } from "vitest";

const production = vi.hoisted(() => ({ on: false }));
vi.mock("../src/v2/campaign-production", () => ({
  campaignProductionEnabled: () => production.on,
  requireCampaignProduction: () => { if (!production.on) throw new Error("campaign_unavailable"); }
}));

import { FLAG_VARS, commaList, featureNames, flags, flagOn, type FlagName, type FlagVar, type ServerVars } from "../src/flags";
import { KEY_LABELS, KEY_SALT, MIN_SECRET_LENGTH, derivedKey, hmac, pollenSecret } from "../src/pollen/keys";
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
    expect(Object.hasOwn(env, "FEATURES"), "FEATURES stays a deploy var, not a wrangler.jsonc one").toBe(false);
  });
});

describe("FEATURES", () => {
  it("turns on exactly the flags it lists, whatever their own vars say", () => {
    for (const [set, variable] of ROWS) {
      for (const own of [undefined, "false", "", "TRUE"]) {
        const vars = loose({ FEATURES: variable, [variable]: own });
        for (const [name, other] of ROWS) {
          expect(flags[name](vars), `${name} with FEATURES=${variable} and own ${JSON.stringify(own)}`).toBe(name === set);
          expect(flagOn(vars, other)).toBe(name === set);
        }
      }
    }
  });
  it("adds to the dedicated vars, so either one turns a flag on", () => {
    const vars = loose({ FEATURES: "PRESENCE_ENABLED", V2_ROOMS_ENABLED: "true" });
    expect(flags.presence(vars)).toBe(true);
    expect(flags.v2Rooms(vars)).toBe(true);
    expect(flags.hardMode(vars)).toBe(false);
  });
  it("trims items, matches case exactly and ignores unknown names and empty items", () => {
    const vars = loose({ FEATURES: " V2_ROOMS_ENABLED ,,hard_mode_enabled, NOT_A_FLAG,\tPOLLEN_EARN\n, HARD_MODE_ENABLED_X,displayNames" });
    expect(ROWS.filter(([name]) => flags[name](vars)).map(([name]) => name).sort()).toEqual(["pollenEarn", "v2Rooms"]);
    expect([...featureNames("NOT_A_FLAG, also_not")]).toEqual([]);
  });
  it("reads nothing from a FEATURES value that is not a string or is empty", () => {
    for (const raw of [undefined, null, "", " , ", 1, true, ["V2_ROOMS_ENABLED"], { V2_ROOMS_ENABLED: true }]) {
      expect(featureNames(raw).size, JSON.stringify(raw)).toBe(0);
      for (const [name] of ROWS) expect(flags[name](loose({ FEATURES: raw })), `${name} ${JSON.stringify(raw)}`).toBe(false);
    }
  });
  it("reads a changed value at once, and every flag from one value at a time", () => {
    const first = loose({ FEATURES: "V2_ROOMS_ENABLED" }), second = loose({ FEATURES: "HARD_MODE_ENABLED" });
    for (let round = 0; round < 3; round++) {
      expect([flags.v2Rooms(first), flags.hardMode(first), flags.v2Rooms(second), flags.hardMode(second)]).toEqual([true, false, false, true]);
    }
    // A FEATURES string built from FLAG_VARS turns every flag on: the deploy note pastes one made this way.
    const all = loose({ FEATURES: Object.values(FLAG_VARS).join(",") });
    for (const [name] of ROWS) expect(flags[name](all), name).toBe(true);
  });
  it("defaults POLLEN_EARN off, and reads it from FEATURES", () => {
    expect(FLAG_VARS.pollenEarn).toBe("POLLEN_EARN");
    expect(flags.pollenEarn(env)).toBe(false);
    expect(flags.pollenEarn(loose({ FEATURES: "POLLEN_EARN" }))).toBe(true);
  });
});

// Vectors made outside the worker with Node's crypto.hkdfSync and createHmac (a different
// implementation from WebCrypto), from a synthetic secret used nowhere else.
const TEST_SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const VECTORS: readonly [string, string, string][] = [
  [KEY_LABELS.bloom, "pollen-bloom-v1|AAAAAAAAAAAAAAAAAAAAAA|2026-W44|first-steps|first-path|a", "b8b4c5419bfb79c9657e4d16bee23b310d655b239d294dcbcd363b8e76a07bd6"],
  [KEY_LABELS.bloom, "pollen-bloom-v1|AAAAAAAAAAAAAAAAAAAAAA|2026-W53|relay-isles|second-path|b", "e1b17c225ec3e19bf2f248966ae2983e97a1d5fa616a747e2aff8f320f25035d"]
];
const hex = (bytes: Uint8Array) => [...bytes].map(byte => byte.toString(16).padStart(2, "0")).join("");

describe("POLLEN_SECRET key derivation", () => {
  it("derives HKDF-SHA256 keys that sign as Node's implementation does", async () => {
    expect(KEY_SALT).toBe("after-you-pollen-keys-v1");
    for (const [label, message, expected] of VECTORS) expect(hex(await hmac((await derivedKey({ POLLEN_SECRET: TEST_SECRET }, label as typeof KEY_LABELS.bloom))!, message)), message).toBe(expected);
  });
  it("gives each label and each secret its own key", async () => {
    const message = VECTORS[0][1], signed = new Set<string>();
    for (const label of Object.values(KEY_LABELS)) signed.add(hex(await hmac((await derivedKey({ POLLEN_SECRET: TEST_SECRET }, label))!, message)));
    expect(signed.size).toBe(Object.values(KEY_LABELS).length);
    const other = await derivedKey({ POLLEN_SECRET: TEST_SECRET.replace("0001", "0002") }, KEY_LABELS.bloom);
    expect(hex(await hmac(other!, message))).not.toBe(VECTORS[0][2]);
  });
  it("derives nothing while the secret is unset or shorter than the minimum", () => {
    for (const secret of [undefined, "", "x".repeat(MIN_SECRET_LENGTH - 1)]) {
      expect(pollenSecret({ POLLEN_SECRET: secret })).toBeNull();
      expect(derivedKey({ POLLEN_SECRET: secret }, KEY_LABELS.bloom)).toBeNull();
    }
    expect(pollenSecret({ POLLEN_SECRET: "x".repeat(MIN_SECRET_LENGTH) })).toBe("x".repeat(MIN_SECRET_LENGTH));
    expect(pollenSecret(env)).toBeNull();
  });
  it("derives each key once per secret and label", async () => {
    const spy = vi.spyOn(crypto.subtle, "deriveBits");
    const secret = TEST_SECRET.replace("0001", "0003");
    await derivedKey({ POLLEN_SECRET: secret }, KEY_LABELS.bloom); await derivedKey({ POLLEN_SECRET: secret }, KEY_LABELS.bloom);
    expect(spy).toHaveBeenCalledTimes(1);
    spy.mockRestore();
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
    campaign_creation_enabled: String(env.V2_ROOMS_ENABLED) === "true" && String((env as Env & { CAMPAIGN_CREATION_ENABLED?: string }).CAMPAIGN_CREATION_ENABLED) === "true" && advertisedCampaigns(env).length > 0,
    campaign_mutations_enabled: campaignProductionEnabled() && String(env.V2_ROOMS_ENABLED) === "true" && String((env as Env & { CAMPAIGN_MUTATIONS_ENABLED?: string }).CAMPAIGN_MUTATIONS_ENABLED) === "true",
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
