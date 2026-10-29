import { afterEach, describe, expect, it, vi } from "vitest";
import { APP, EMPTY_CONFIG, MAX_CONFIG_LENGTH, parseConfig, serverConfig, type ServerConfig } from "../src/config";
import { FLAG_NAMES, RETIRED_FLAGS } from "../src/flags";
import { ID_PATTERN, randomToken } from "../src/protocol";
import { configJson } from "./config";

// Synthetic values only. The ids have the real shapes; none of them is a real RevenueCat or player id.
const ALIAS_ID = "A".repeat(22);
const RC = { project_id: "projSynthetic1", play_entitlement_lookup_id: "entlSyntheticPlay", play_product_id: "prodSyntheticLifetime",
  play_subscription_product_ids: ["prodSyntheticMonthly", "prodSyntheticYearly"] };
const KEPT = ["TESTER_ACCESS_ENABLED", "NOTIFICATIONS_ENABLED", "POLLEN_EARN", "LEADERBOARDS"];
const FULL = { features: KEPT, min_client_version: { play: "0.7.0", github: "0.7.0", app_store: "0.0.0" }, friend_aliases: { owner: ALIAS_ID }, revenuecat: RC };
const view = (config: ServerConfig) => ({ ...config, features: [...config.features].sort(), friend_aliases: [...config.friend_aliases.byAlias] });

afterEach(() => { vi.restoreAllMocks(); });

describe("CONFIG schema", () => {
  it("reads a full CONFIG with nothing to report", () => {
    const check = parseConfig(JSON.stringify(FULL), FLAG_NAMES);
    expect(check.problems).toEqual([]); expect(check.unknown).toEqual([]);
    expect(view(check.config)).toEqual({ ...FULL, features: [...KEPT].sort(), friend_aliases: [["owner", ALIAS_ID]],
      revenuecat: { ...RC, app_store_subscription_product_ids: [], reviewer_ids: [] } });
    expect(check.config.friend_aliases.byId.get(ALIAS_ID)).toBe("owner");
    // A live-sized CONFIG, with every RevenueCat id and a few aliases, stays far under the cap and Cloudflare's 5 KB.
    expect(JSON.stringify({ ...FULL, features: [...FLAG_NAMES], friend_aliases: { a1b: ALIAS_ID, c2d: "B".repeat(22), e3f: "C".repeat(22), g4h: "D".repeat(22) } }).length).toBeLessThan(MAX_CONFIG_LENGTH / 2);
  });
  it("fails safe as a whole when it is not a JSON object within the cap", () => {
    for (const raw of [undefined, 7, "", "{", "[]", "null", "\"x\"", JSON.stringify({ ...FULL, pad: "x".repeat(MAX_CONFIG_LENGTH) })]) {
      const check = parseConfig(raw);
      expect(check.config, String(raw).slice(0, 30)).toBe(EMPTY_CONFIG);
      expect(check.problems.length, String(raw).slice(0, 30)).toBe(1);
    }
    expect(EMPTY_CONFIG.features.size).toBe(0); expect(EMPTY_CONFIG.min_client_version).toEqual({}); expect(EMPTY_CONFIG.friend_aliases.byAlias.size).toBe(0);
    expect(EMPTY_CONFIG.revenuecat.project_id).toBeUndefined();
  });
  it("fails safe key by key: a malformed value costs only its own key", () => {
    const cases: [Record<string, unknown>, (config: ServerConfig) => unknown, unknown][] = [
      [{ features: "POLLEN_EARN" }, c => c.features.size, 0],
      [{ features: ["POLLEN_EARN", "lower_case"] }, c => c.features.size, 0],
      [{ min_client_version: { ...FULL.min_client_version, play: "latest" } }, c => c.min_client_version, { github: "0.7.0", app_store: "0.0.0" }],
      [{ min_client_version: "0.7.0" }, c => c.min_client_version, {}],
      [{ friend_aliases: { owner: ALIAS_ID, Bad: "B".repeat(22) } }, c => c.friend_aliases.byAlias.size, 0],
      [{ friend_aliases: { owner: ALIAS_ID, again: ALIAS_ID } }, c => c.friend_aliases.byAlias.size, 0],
      [{ revenuecat: { ...RC, play_subscription_product_ids: ["prodA", "not-a-product"] } }, c => c.revenuecat.play_subscription_product_ids, null],
      [{ revenuecat: { ...RC, play_subscription_product_ids: "prodA" } }, c => c.revenuecat.play_subscription_product_ids, null],
      [{ revenuecat: { ...RC, play_entitlement_lookup_id: "full_journey" } }, c => c.revenuecat.play_entitlement_lookup_id, "full_journey"],
      [{ revenuecat: { ...RC, project_id: 5 } }, c => c.revenuecat.project_id, "(malformed)"],
      [{ revenuecat: { ...RC, app_store_entitlement_lookup_id: 5 } }, c => c.revenuecat.app_store_entitlement_lookup_id, "(malformed)"],
      [{ revenuecat: { ...RC, app_store_environment: "Production" } }, c => c.revenuecat.app_store_environment, "Production"],
      [{ revenuecat: { ...RC, reviewer_ids: ["short"] } }, c => c.revenuecat.reviewer_ids, []],
    ];
    for (const [change, read, expected] of cases) {
      const check = parseConfig(JSON.stringify({ ...FULL, ...change }), FLAG_NAMES);
      expect(check.problems.length, JSON.stringify(change)).toBeGreaterThan(0);
      expect(read(check.config), JSON.stringify(change)).toEqual(expected);
      // Everything else still reads as given.
      if (!("features" in change)) expect([...check.config.features].sort(), JSON.stringify(change)).toEqual([...KEPT].sort());
      if (!("revenuecat" in change)) expect(check.config.revenuecat.project_id, JSON.stringify(change)).toBe(RC.project_id);
    }
  });
  it("lets the Worker ignore keys and flag names it does not know, which the runners refuse", () => {
    const later = { ...FULL, features: [...KEPT, "SOME_LATER_FLAG", ...RETIRED_FLAGS], later_key: 1, revenuecat: { ...RC, later_id: "x" }, min_client_version: { ...FULL.min_client_version, tv: "1.0.0" } };
    const worker = parseConfig(JSON.stringify(later)), runner = parseConfig(JSON.stringify(later), FLAG_NAMES);
    expect(worker.problems).toEqual([]); expect(runner.problems).toEqual([]);
    expect(runner.unknown.sort()).toEqual(["features.SOME_LATER_FLAG", ...RETIRED_FLAGS.map(name => "features." + name), "later_key", "min_client_version.tv", "revenuecat.later_id"].sort());
    expect(view(worker.config).min_client_version).toEqual(FULL.min_client_version);
    expect(() => configJson(later as never)).toThrow(/refused/);
  });
  it("names keys in its problems, never values", () => {
    const secretish = { ...FULL, friend_aliases: { owner: ALIAS_ID, Bad: ALIAS_ID }, revenuecat: { ...RC, project_id: "p", play_entitlement_lookup_id: "entl bad" } };
    const text = parseConfig(JSON.stringify(secretish), FLAG_NAMES).problems.join(" ");
    for (const value of [ALIAS_ID, "entl bad", RC.play_product_id]) expect(text).not.toContain(value);
  });
  it("matches the player id shape protocol.ts uses", () => {
    expect(parseConfig(JSON.stringify({ friend_aliases: { owner: randomToken(16) } })).problems).toEqual([]);
    expect(ID_PATTERN.source).toBe("^[a-zA-Z0-9_-]{22}$");
  });
});

describe("serverConfig", () => {
  it("parses each CONFIG value once and logs a malformed one once, by key", () => {
    const raw = JSON.stringify({ ...FULL, revenuecat: { ...RC, play_product_id: "bad value!" } });
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const first = serverConfig({ CONFIG: raw }), second = serverConfig({ CONFIG: raw });
    expect(second).toBe(first);
    expect(warn).toHaveBeenCalledTimes(1);
    expect(String(warn.mock.calls[0][0])).toContain("config_invalid");
    expect(String(warn.mock.calls[0][0])).not.toContain("bad value!");
    expect(serverConfig({ CONFIG: JSON.stringify(FULL) })).not.toBe(first);
  });
  it("reads no CONFIG as the empty configuration", () => {
    expect(serverConfig({})).toBe(EMPTY_CONFIG);
    expect(serverConfig({ NOTIFICATIONS_ENABLED: "true", FEATURES: "NOTIFICATIONS_ENABLED" } as never).features.size).toBe(0);
  });
});

describe("APP", () => {
  it("holds the public values the app and the pages already show", () => {
    expect(APP.environment).toBe("test-store");
    expect(APP.playGamesWebClientId.startsWith(APP.playGamesAppId + "-")).toBe(true);
    expect(APP.playGamesWebClientId.endsWith(".apps.googleusercontent.com")).toBe(true);
    expect(APP.gameCenterBundleId).toBe("com.aamirazeez.afteryou");
    expect(APP.playEnvironment).toBe("production");
    expect(APP.resendSegmentId).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
    expect(Object.isFrozen(APP)).toBe(true);
  });
});
