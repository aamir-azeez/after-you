/**
 * The Worker's configuration, in one place. Every setting has exactly one home:
 *
 * - APP (below): public values that are the same for every deployment and change only with the code. The app,
 *   the web page or every email already shows them, so they are code, not config.
 * - CONFIG: one plain var holding a JSON object (ServerConfig, parsed by parseConfig) for everything that is not
 *   secret but must change without a code deploy, or must never reach Git: the server flags, the minimum app
 *   versions, the owner's friend aliases and the RevenueCat identifiers. It lives only in
 *   Cloudflare and in the deploy runners' pinned copy, never in wrangler.jsonc.
 * - Secrets: keys and tokens, each its own `wrangler secret`, so a rotation touches nothing else. Never here.
 *
 * This file imports nothing at runtime and uses only erasable TypeScript, so the private deploy runners load this
 * same file with Node and refuse to write a CONFIG that `parseConfig(raw, knownFlags)` reports anything for.
 */
import type { ServerVars } from "./flags";

/** Public, fixed values. Changing one is a code change. */
export const APP = Object.freeze({
  /** Answered on GET /health and in every entitlement reply. There is one deployment; the name predates the store launch. */
  environment: "test-store",
  /** The Play Games Services project (application) id the Android app ships with. */
  playGamesAppId: "665737720520",
  /** The OAuth web client the Android app asks Google for a server auth code with. Its secret is PLAY_GAMES_CLIENT_SECRET. */
  playGamesWebClientId: "665737720520-vh41m91imtvb0sol5vtn0vsfhdod7mgq.apps.googleusercontent.com",
  /** The iOS bundle id Game Center signs. */
  gameCenterBundleId: "com.aamirazeez.afteryou",
  /** The friend link page's Turnstile site key, served by GET /v1/waitlist/ios. Its secret is TURNSTILE_SECRET_KEY. */
  turnstileSiteKey: "0x4AAAAAAFcV13jW0771Uryu",
  /** The waitlist email's sender, on a domain verified in Resend, shown as "After You". */
  waitlistFrom: "waitlist@afteryou.aamirazeez.com",
  /** The reply-to address on waitlist emails. */
  waitlistReplyTo: "afteryou-reply@aamirazeez.com",
  /** The Resend segment (formerly audience) waitlist contacts join. It names the list; only RESEND_API_KEY can use it. */
  resendSegmentId: "68cf69ad-59d6-4b84-8865-72dbc72f1a49",
  /** The RevenueCat environment real Play purchases are made in. App Review and TestFlight testers exist only on iPhone. */
  playEnvironment: "production",
});

/** Cloudflare allows 5 KB per var; the cap keeps a margin and bounds the parse. */
export const MAX_CONFIG_LENGTH = 4096;
/** A flag's name, as FLAG_VARS in flags.ts spells it. */
const FLAG_NAME = /^[A-Z][A-Z0-9_]{0,63}$/;
const MAX_FEATURES = 64;
const MINIMUM_CHANNELS = Object.freeze(["play", "github", "app_store"] as const);
export type MinimumChannel = typeof MINIMUM_CHANNELS[number];
/** An owner-reserved short friend name (friend-aliases.ts). */
export const ALIAS_PATTERN = /^[a-z][a-z0-9]{2,15}$/;
export const MAX_FRIEND_ALIASES = 32;
/** A player id, as protocol.ts ID_PATTERN (a test pins the two equal). */
const PLAYER_ID = /^[a-zA-Z0-9_-]{22}$/;
export const PROJECT_PATTERN = /^[A-Za-z0-9_-]{4,100}$/;
export const LOOKUP_PATTERN = /^entl[A-Za-z0-9_-]+$/;
export const PRODUCT_PATTERN = /^prod[A-Za-z0-9_-]+$/;
const MAX_PRODUCTS = 8;
const MAX_REVIEWERS = 16;
const APP_STORE_ENVIRONMENTS = Object.freeze(["production", "sandbox", "both"] as const);

/** Longest version string either side accepts. */
export const MAX_VERSION_LENGTH = 40;
// Semantic version without build metadata: 0.6.2, 0.6.2-rc.1. No leading zeros.
const NUMBER = "(0|[1-9][0-9]{0,3})";
const VERSION = new RegExp(`^${NUMBER}\\.${NUMBER}\\.${NUMBER}(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?$`);
export type Version = { core: [number, number, number]; pre: string[] };
export function parseVersion(value: unknown): Version | null {
  if (typeof value !== "string" || value.length > MAX_VERSION_LENGTH) return null;
  const found = VERSION.exec(value);
  if (!found) return null;
  const pre = found[4] === undefined ? [] : found[4].split(".");
  // A numeric pre-release identifier has no leading zeros either (semver 9).
  if (pre.some(part => /^[0-9]+$/.test(part) && (part.length > 1 && part.startsWith("0") || part.length > 6))) return null;
  return { core: [Number(found[1]), Number(found[2]), Number(found[3])], pre };
}

export type FriendAliases = { readonly byAlias: ReadonlyMap<string, string>; readonly byId: ReadonlyMap<string, string> };
/**
 * The RevenueCat identifiers. They name things in RevenueCat and grant nothing without REVENUECAT_SECRET_KEY.
 * Each consumer checks its own pattern, so a malformed value holds that check ("unconfigured") as it always has.
 */
export type RevenueCatSettings = {
  readonly project_id?: string;
  readonly play_entitlement_lookup_id?: string;
  /** The one-time Full Journey (Lifetime) product. */
  readonly play_product_id?: string;
  /** [] keeps one-time-only admission; null is a set but malformed list, which holds rather than refusing every subscriber. */
  readonly play_subscription_product_ids: readonly string[] | null;
  /** Required while APP_STORE_ENTITLEMENTS_ENABLED is on; null as above. */
  readonly app_store_subscription_product_ids: readonly string[] | null;
  /** production, sandbox or both (the default when unset); anything else holds App Store hosts. */
  readonly app_store_environment?: string;
  /** Unset reuses the Play lookup id. */
  readonly app_store_entitlement_lookup_id?: string;
  /** Player ids whose real Full Journey entitlement counts as a review grant, and whose App Store sandbox Pollen bundles pay (pollen/bundle-provider.ts): the App Review identity. */
  readonly reviewer_ids: readonly string[];
};
export type ServerConfig = {
  /** The FLAG_VARS names that are on (flags.ts reads only names it knows). */
  readonly features: ReadonlySet<string>;
  /** The oldest app version each channel may play online with (app-status.ts). A missing or malformed one is no minimum. */
  readonly min_client_version: Readonly<Partial<Record<MinimumChannel, string>>>;
  readonly friend_aliases: FriendAliases;
  readonly revenuecat: RevenueCatSettings;
};
/**
 * `problems`: values that are malformed. Each malformed value fails safe where it is read: the whole object when it
 * is not a JSON object within MAX_CONFIG_LENGTH (EMPTY_CONFIG: every flag off, no minimum, no alias, RevenueCat
 * unconfigured), otherwise only its own key (features off, that minimum absent, every alias off, that RevenueCat
 * check held). `unknown`: keys and flag names this code does not know. The Worker ignores them, so a rollback to older
 * code keeps working under a newer CONFIG; the deploy runners refuse both lists.
 */
export type ConfigCheck = { config: ServerConfig; problems: string[]; unknown: string[] };

/** What a RevenueCat id that is not a string reads as: no pattern accepts it, so its check holds. */
const MALFORMED = "(malformed)";
const NO_ALIASES: FriendAliases = Object.freeze({ byAlias: new Map<string, string>(), byId: new Map<string, string>() });
const NO_REVENUECAT: RevenueCatSettings = Object.freeze({ play_subscription_product_ids: [], app_store_subscription_product_ids: [], reviewer_ids: [] });
export const EMPTY_CONFIG: ServerConfig = Object.freeze({ features: new Set<string>(), min_client_version: Object.freeze({}), friend_aliases: NO_ALIASES, revenuecat: NO_REVENUECAT });
const TOP_KEYS = ["features", "min_client_version", "friend_aliases", "revenuecat"];
const STRING_IDS = { project_id: PROJECT_PATTERN, play_entitlement_lookup_id: LOOKUP_PATTERN, play_product_id: PRODUCT_PATTERN, app_store_entitlement_lookup_id: LOOKUP_PATTERN } as const;
const PRODUCT_LISTS = ["play_subscription_product_ids", "app_store_subscription_product_ids"] as const;
const REVENUECAT_KEYS = [...Object.keys(STRING_IDS), ...PRODUCT_LISTS, "app_store_environment", "reviewer_ids"];

function plainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
}

/** Aliases: all valid or none (fail closed), so a bad entry never points a name at the wrong player. */
export function aliasesFrom(value: unknown): FriendAliases | null {
  if (!plainObject(value)) return null;
  const entries = Object.entries(value);
  if (entries.length > MAX_FRIEND_ALIASES) return null;
  const byAlias = new Map<string, string>(), byId = new Map<string, string>();
  for (const [alias, id] of entries) {
    if (!ALIAS_PATTERN.test(alias) || typeof id !== "string" || !PLAYER_ID.test(id) || byId.has(id)) return null;
    byAlias.set(alias, id); byId.set(id, alias);
  }
  return { byAlias, byId };
}
/** A product list: at most MAX_PRODUCTS ids of the `prod…` shape, or null when it is anything else. */
function productsFrom(value: unknown[]): string[] | null {
  return value.length <= MAX_PRODUCTS && value.every(item => typeof item === "string" && PRODUCT_PATTERN.test(item)) ? value as string[] : null;
}
function reviewersFrom(value: unknown[]): string[] | null {
  return value.length <= MAX_REVIEWERS && value.every(item => typeof item === "string" && PLAYER_ID.test(item)) ? value as string[] : null;
}

/**
 * The one CONFIG parser, for the Worker and the deploy runners alike. `knownFlags` (the runners pass every FLAG_VARS
 * name of the code they deploy) also reports feature names that code does not know. Messages name keys, never values.
 */
export function parseConfig(raw: unknown, knownFlags?: ReadonlySet<string>): ConfigCheck {
  const problems: string[] = [], unknown: string[] = [];
  if (typeof raw !== "string" || raw.length > MAX_CONFIG_LENGTH) return { config: EMPTY_CONFIG, problems: [`CONFIG must be a JSON object of at most ${MAX_CONFIG_LENGTH} characters`], unknown };
  let value: unknown;
  try { value = JSON.parse(raw); } catch { return { config: EMPTY_CONFIG, problems: ["CONFIG is not valid JSON"], unknown }; }
  if (!plainObject(value)) return { config: EMPTY_CONFIG, problems: ["CONFIG is not a JSON object"], unknown };
  for (const key of Object.keys(value)) if (!TOP_KEYS.includes(key)) unknown.push(key);

  const features = new Set<string>();
  if (value.features !== undefined) {
    const list = value.features;
    // Malformed as a whole: every flag stays off.
    if (!Array.isArray(list) || list.length > MAX_FEATURES || !list.every(item => typeof item === "string" && FLAG_NAME.test(item))) problems.push(`features must be a list of at most ${MAX_FEATURES} flag names`);
    else {
      for (const name of list as string[]) { if (features.has(name)) problems.push(`features lists ${name} twice`); features.add(name); }
      if (knownFlags) for (const name of features) if (!knownFlags.has(name)) unknown.push(`features.${name}`);
    }
  }

  const minimums: Partial<Record<MinimumChannel, string>> = {};
  if (value.min_client_version !== undefined) {
    const given = value.min_client_version;
    if (!plainObject(given)) problems.push("min_client_version must be an object");
    else for (const [channel, version] of Object.entries(given)) {
      if (!(MINIMUM_CHANNELS as readonly string[]).includes(channel)) { unknown.push(`min_client_version.${channel}`); continue; }
      if (parseVersion(version) === null) { problems.push(`min_client_version.${channel} must be a version like 0.7.0`); continue; }
      minimums[channel as MinimumChannel] = version as string;
    }
  }

  let aliases = NO_ALIASES;
  if (value.friend_aliases !== undefined) {
    const parsed = aliasesFrom(value.friend_aliases);
    if (parsed) aliases = parsed;
    else problems.push(`friend_aliases must map at most ${MAX_FRIEND_ALIASES} distinct short names to distinct player ids`);
  }

  let revenuecat = NO_REVENUECAT;
  if (value.revenuecat !== undefined) {
    const given = value.revenuecat;
    if (!plainObject(given)) problems.push("revenuecat must be an object");
    else {
      for (const key of Object.keys(given)) if (!REVENUECAT_KEYS.includes(key)) unknown.push(`revenuecat.${key}`);
      // A malformed id stays a string the consumer's own pattern refuses, so that check holds ("unconfigured"); a value
      // that is not a string becomes MALFORMED, never "", which would read as unset (an unset App Store lookup reuses Play's).
      const out: { -readonly [K in keyof RevenueCatSettings]: RevenueCatSettings[K] } = { play_subscription_product_ids: [], app_store_subscription_product_ids: [], reviewer_ids: [] };
      for (const [key, pattern] of Object.entries(STRING_IDS) as [keyof typeof STRING_IDS, RegExp][]) {
        const item = given[key];
        if (item === undefined) continue;
        if (typeof item !== "string" || !pattern.test(item)) problems.push(`revenuecat.${key} is malformed`);
        out[key] = typeof item === "string" ? item : MALFORMED;
      }
      for (const key of PRODUCT_LISTS) {
        const item = given[key];
        if (item === undefined) continue;
        const list = Array.isArray(item) ? productsFrom(item) : null;
        if (list === null) problems.push(`revenuecat.${key} must be a list of at most ${MAX_PRODUCTS} prod ids`);
        else if (new Set(list).size !== list.length) problems.push(`revenuecat.${key} lists an id twice`);
        out[key] = list;
      }
      const environment = given.app_store_environment;
      if (environment !== undefined) {
        if (typeof environment !== "string" || !(APP_STORE_ENVIRONMENTS as readonly string[]).includes(environment)) problems.push("revenuecat.app_store_environment must be production, sandbox or both");
        out.app_store_environment = typeof environment === "string" ? environment : MALFORMED;
      }
      if (given.reviewer_ids !== undefined) {
        const list = Array.isArray(given.reviewer_ids) ? reviewersFrom(given.reviewer_ids) : null;
        if (list === null) problems.push(`revenuecat.reviewer_ids must be a list of at most ${MAX_REVIEWERS} player ids`);
        out.reviewer_ids = list ?? [];
      }
      revenuecat = Object.freeze(out);
    }
  }
  const config: ServerConfig = Object.freeze({ features, min_client_version: Object.freeze(minimums), friend_aliases: aliases, revenuecat });
  return { config, problems, unknown };
}

let parsed: { raw: unknown; config: ServerConfig } | null = null;
/**
 * The configuration this request runs with. CONFIG is parsed once per isolate, cached by its raw string. Without
 * CONFIG (local development, tests) every flag is off, there is no minimum or alias, and RevenueCat is unconfigured.
 */
export function serverConfig(env: ServerVars): ServerConfig {
  const raw = env.CONFIG;
  if (raw === undefined) return EMPTY_CONFIG;
  if (parsed !== null && parsed.raw === raw) return parsed.config;
  const check = parseConfig(raw);
  // Once per isolate and value. Problems name keys only, never values.
  if (check.problems.length) console.warn(JSON.stringify({ event: "config_invalid", problems: check.problems.join("; ").slice(0, 400) }));
  parsed = { raw, config: check.config };
  return check.config;
}
