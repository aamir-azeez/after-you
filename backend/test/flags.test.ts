import { env } from "cloudflare:workers";
import { describe, expect, it, vi } from "vitest";

import { FLAG_NAMES, FLAG_VARS, RETIRED_FLAGS, flags, flagOn, type FlagName, type FlagVar, type ServerVars } from "../src/flags";
import { KEY_LABELS, KEY_SALT, MIN_SECRET_LENGTH, derivedKey, hmac, pollenSecret } from "../src/pollen/keys";
import worker from "../src/index";
import { routeV2 } from "../src/v2/routes";
import { CHAPTERS, advertisedChapters } from "../src/v2/chapters";
import { POLLEN_CLIENT, configJson, withConfig } from "./config";
import LIVE_ANSWERS from "./fixtures/live-answers-5601cb81.json";

const ROWS = Object.entries(FLAG_VARS) as [FlagName, FlagVar][];
const NAMES = ROWS.map(([, name]) => name);
const config = (features: string[]): ServerVars => ({ CONFIG: configJson({ features }) });
/** FEATURES on the live Worker c51b509d (2026-10-29), every one of them on, before the 25 retired flags left the code. */
const LIVE_FEATURES = ["PRESENCE_ENABLED", "TESTER_ACCESS_ENABLED", "SAFETY_ENFORCEMENT_ENABLED", "REVENUECAT_DELETION_ENABLED", "NOTIFICATIONS_ENABLED",
  "FRIEND_ROOM_EVENTS_ENABLED", "V2_ROOMS_ENABLED", "FIRST_STEPS_ENABLED", "COOP_CHAPTERS_ENABLED", "HOUSE_CHAPTER_ENABLED", "JOURNEY_CHAPTERS_ENABLED",
  "WISHING_WELL_CHAPTER_ENABLED", "LONG_WAY_HOME_V2_CHAPTER_ENABLED", "TURN_OF_THE_TIDE_CHAPTER_ENABLED", "LIGHTHOUSE_V2_CHAPTER_ENABLED",
  "TURN_OF_THE_TIDE_V2_CHAPTER_ENABLED", "RELAY_PHOTOS_ENABLED", "PRESET_REACTIONS_ENABLED", "PHOTO_DELIVERY_ENABLED", "PHOTO_TRANSFER_ENABLED",
  "REPLAY_TRANSFER_ENABLED", "HISTORY_OFFLOAD_ENABLED", "UPDATE_GATE_ENABLED", "LEGACY_TRANSFERRED_ROOM_UNBLOCK", "FINISHED_ROOM_LEAVE_ENABLED",
  "ROOM_INDEX_ENABLED", "LIVE_CONNECTION_ENABLED", "TURN_TRIES_ENABLED", "END_REACTIONS_ENABLED", "IN_RUN_REACTIONS_ENABLED", "HARD_MODE_ENABLED",
  "PLAY_GAMES_ENABLED", "IOS_WAITLIST_ENABLED", "DISPLAY_NAMES_ENABLED", "POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_LOOKS", "LEADERBOARDS"];
/** What live CONFIG lists once the retired names are gone. */
const LIVE_KEPT = LIVE_FEATURES.filter(name => FLAG_NAMES.has(name));

// Every *_ENABLED var the generated Env declares, or that ServerVars still names, is a flag.
type Unlisted = Exclude<Extract<keyof Env | keyof ServerVars, `${string}_ENABLED`>, FlagVar>;
const everyEnabledVarListed: [Unlisted] extends [never] ? true : Unlisted = true;

describe("flags", () => {
  it("has one accessor per table row, and each name in one row only", () => {
    expect(everyEnabledVarListed).toBe(true);
    expect(Object.keys(flags).sort()).toEqual(ROWS.map(([name]) => name).sort());
    expect(FLAG_NAMES.size).toBe(ROWS.length);
    expect(new Set(NAMES)).toEqual(FLAG_NAMES);
  });
  it("turns each accessor on exactly when CONFIG lists its name", () => {
    for (const [set, variable] of ROWS) {
      const vars = config([variable]);
      for (const [name, own] of ROWS) {
        expect(flags[name](vars), `${name} with ${variable}`).toBe(name === set);
        expect(flagOn(vars, own)).toBe(name === set);
      }
    }
    const all = config(NAMES);
    for (const [name] of ROWS) expect(flags[name](all), name).toBe(true);
  });
  it("reads every flag off for the test worker's env, which has no CONFIG", () => {
    expect(Object.hasOwn(env, "CONFIG"), "CONFIG is a deploy var, never a wrangler.jsonc one").toBe(false);
    for (const [name] of ROWS) expect(flags[name](withConfig({ ...env })), name).toBe(false);
  });
  it("ignores a name CONFIG lists that this code does not know, as an older Worker would after a rollback", () => {
    const vars: ServerVars = { CONFIG: JSON.stringify({ features: ["POLLEN_EARN", "SOME_LATER_FLAG", ...RETIRED_FLAGS] }) };
    expect(ROWS.filter(([name]) => flags[name](vars)).map(([name]) => name)).toEqual(["pollenEarn"]);
  });
  it("turns every flag off for a malformed features list or CONFIG", () => {
    for (const raw of ["{", "[]", "null", JSON.stringify({ features: "POLLEN_EARN" }), JSON.stringify({ features: ["pollen_earn"] }),
      JSON.stringify({ features: [1] }), JSON.stringify({ features: Array.from({ length: 65 }, (_, i) => "FLAG_" + i) }), "x".repeat(5000)])
      for (const [name] of ROWS) expect(flags[name]({ CONFIG: raw }), `${name} ${raw.slice(0, 40)}`).toBe(false);
  });
  it("reads a changed CONFIG at once", () => {
    const first = config(["POLLEN_EARN"]), second = config(["LEADERBOARDS"]);
    for (let round = 0; round < 3; round++)
      expect([flags.pollenEarn(first), flags.leaderboards(first), flags.pollenEarn(second), flags.leaderboards(second)]).toEqual([true, false, false, true]);
  });
});

describe("retired flags", () => {
  it("were all on live, are gone from the table, and every live name is either kept or retired", () => {
    expect(RETIRED_FLAGS.length).toBe(25);
    expect(new Set(RETIRED_FLAGS).size).toBe(RETIRED_FLAGS.length);
    for (const name of RETIRED_FLAGS) {
      expect(FLAG_NAMES.has(name), name).toBe(false);
      expect(LIVE_FEATURES.includes(name), `${name} was on live`).toBe(true);
    }
    expect([...RETIRED_FLAGS, ...LIVE_KEPT].sort()).toEqual([...LIVE_FEATURES].sort());
    // Kept: the kill switches and the parts not launched yet. Nothing left the table that was off live.
    expect(LIVE_KEPT).toEqual(["TESTER_ACCESS_ENABLED", "NOTIFICATIONS_ENABLED", "FRIEND_ROOM_EVENTS_ENABLED", "RELAY_PHOTOS_ENABLED", "PHOTO_TRANSFER_ENABLED",
      "LIVE_CONNECTION_ENABLED", "PLAY_GAMES_ENABLED", "IOS_WAITLIST_ENABLED", "DISPLAY_NAMES_ENABLED", "POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_LOOKS", "LEADERBOARDS"]);
    expect(NAMES.filter(name => !LIVE_FEATURES.includes(name))).toEqual(["IOS_PUSH_ENABLED", "CAMPAIGN_CREATION_ENABLED", "CAMPAIGN_MUTATIONS_ENABLED",
      "STORY_DRAIN_ENABLED", "APP_STORE_ENTITLEMENTS_ENABLED", "GAME_CENTER_ENABLED", "POLLEN_SHOP", "POLLEN_ITEM_BLOOMS", "POLLEN_GRANT", "POLLEN_BUNDLES"]);
  });
  it("leaves every published chapter creatable with no flag", () => {
    for (const row of CHAPTERS) expect(row.flag, row.adapter.key.level_id).toBe("");
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

const ASKING = ["X-AfterYou-History", "X-AfterYou-Poll-Redo", "X-AfterYou-Turn-Tries", "X-AfterYou-End-Reactions", "X-AfterYou-Run-Reactions", "X-AfterYou-Hard-Mode",
  "X-AfterYou-Live", "X-AfterYou-Platform-Games", "X-AfterYou-Display-Names", "X-AfterYou-Pollen", "X-AfterYou-Looks", "X-AfterYou-Leaderboards"];
/** Live's settings as CONFIG (the retired names left out) beside the same synthetic secrets the capture used. */
const LIVE_ENV = () => withConfig({ ...env, features: LIVE_KEPT, min_client_version: { app_store: "0.0.0", github: "0.7.0", play: "0.7.0" },
  PLAY_GAMES_CLIENT_SECRET: "synthetic-client-secret", POLLEN_SECRET: "synthetic-pollen-secret-for-tests-only-0001" }) as unknown as Env;
const sha = async (text: string) => "sha256:" + hex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))));

/** The worker's answers to every capabilities client, /health and /v1/app-status, capabilities as hashes. Capabilities come from an app new enough for Pollen replies (pollen/routes.ts), as live answered every app then. */
async function liveAnswers(vars: Env): Promise<Record<string, string>> {
  const answers: Record<string, string> = {};
  for (const level of [{}, { "X-AfterYou-Room-Level": "2" }] as Record<string, string>[]) {
    const tag = Object.keys(level).length ? "L2" : "L1";
    const combos: [string, Record<string, string>][] = [[`${tag}:none`, level], ...ASKING.map((header): [string, Record<string, string>] => [`${tag}:${header}`, { ...level, [header]: "1" }]),
      [`${tag}:all`, { ...level, ...Object.fromEntries(ASKING.map(header => [header, "1"])) }]];
    for (const [key, headers] of combos)
      answers["capabilities " + key] = await sha(await (await routeV2(new Request("https://after-you.test/v2/capabilities", { headers: { ...headers, ...POLLEN_CLIENT } }), "/v2/capabilities", "c".repeat(22), vars)).text());
  }
  answers.health = await (await worker.fetch(new Request("https://after-you.test/health"), vars)).text();
  for (const client of [undefined, "0.6.9 play", "0.7.0 play", "0.6.9 github", "0.7.0 github", "0.0.0 app_store", "0.0.1 dev", "bad"]) {
    const response = await worker.fetch(new Request("https://after-you.test/v1/app-status", { headers: { "CF-Connecting-IP": "198.18.9.9", ...(client ? { "X-AfterYou-Client": client } : {}) } }), vars);
    answers["app-status " + client] = `${response.status} ${await response.text()}`;
  }
  return answers;
}
describe("live answers", () => {
  // LIVE_ANSWERS is the worker's own output on main 5601cb81 with live's 16 vars (FEATURES with all 38 names).
  it("answers /v2/capabilities, /health and /v1/app-status byte for byte as live did before the flags retired", async () => {
    const vars = LIVE_ENV();
    expect(await liveAnswers(vars)).toEqual(LIVE_ANSWERS);
    // Every chapter is advertised, as live's flags had it.
    expect(advertisedChapters(vars, 2).length).toBe(CHAPTERS.length);
  });
});
