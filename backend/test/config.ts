import { FLAG_NAMES, RETIRED_FLAGS } from "../src/flags";
import { parseConfig } from "../src/config";

/** What a test may put in CONFIG: its JSON keys (config.ts ServerConfig), with features as a list. */
export type ConfigSettings = { features?: string[]; min_client_version?: Record<string, unknown>; friend_aliases?: Record<string, unknown>; revenuecat?: Record<string, unknown> };
const CONFIG_KEYS = ["features", "min_client_version", "friend_aliases", "revenuecat"];
/** Vars that moved into CONFIG or APP (config.ts). A test still setting one would test nothing. */
const MOVED = ["FEATURES", "MIN_CLIENT_VERSION_PLAY", "MIN_CLIENT_VERSION_GITHUB", "MIN_CLIENT_VERSION_APP_STORE", "FRIEND_ALIASES", "RESEND_SEGMENT_ID",
  "REVENUECAT_PROJECT_ID", "REVENUECAT_ENTITLEMENT_LOOKUP_ID", "REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID", "REVENUECAT_PLAY_PRODUCT_ID", "REVENUECAT_PLAY_SUBSCRIPTION_PRODUCT_IDS",
  "REVENUECAT_APP_STORE_SUBSCRIPTION_PRODUCT_IDS", "REVENUECAT_APP_STORE_ENVIRONMENT", "REVENUECAT_APP_STORE_ENTITLEMENT_LOOKUP_ID", "REVENUECAT_REVIEWER_IDS",
  "REVENUECAT_VERIFICATION_MODE", "REVENUECAT_API_VERSION", "REVENUECAT_ENTITLEMENT", "REVENUECAT_PLAY_ENVIRONMENT", "ENVIRONMENT", "PLAY_GAMES_APP_ID",
  "PLAY_GAMES_WEB_CLIENT_ID", "GAME_CENTER_BUNDLE_ID", "TURNSTILE_SITE_KEY", "WAITLIST_FROM", "WAITLIST_REPLY_TO"];

/**
 * The CONFIG value a deploy would write for these settings. It must pass the same parser the runners use, so a test
 * never runs on a CONFIG production would refuse; pass `{ raw: true }` to write a malformed one on purpose.
 */
export function configJson(settings: ConfigSettings, options: { raw?: boolean } = {}): string {
  const text = JSON.stringify(settings);
  if (!options.raw) {
    const check = parseConfig(text, FLAG_NAMES);
    if (check.problems.length || check.unknown.length) throw new Error(`test CONFIG refused: ${[...check.problems, ...check.unknown].join("; ")}`);
  }
  return text;
}

/**
 * An env for a test, with every setting folded into CONFIG. Tests switch a flag beside the other vars, as
 * `NAME: "true"` (any other value is off), so overrides spread as before: `withConfig({ ...env, ...ON, NAME: "false" })`.
 * CONFIG keys (features, min_client_version, friend_aliases, revenuecat) are taken as they are.
 * A retired flag name, or a var that moved into CONFIG or APP, is refused, so no test sets something nothing reads.
 */
export function withConfig<T extends object>(vars: T): T & { CONFIG: string } {
  const out: Record<string, unknown> = {}, settings: ConfigSettings = {}, on = new Set<string>();
  for (const [key, value] of Object.entries(vars)) {
    if (key === "CONFIG") throw new Error("withConfig: the vars already hold CONFIG");
    if ((RETIRED_FLAGS as readonly string[]).includes(key)) throw new Error(`withConfig: ${key} is retired; its behaviour is always on`);
    if (MOVED.includes(key)) throw new Error(`withConfig: ${key} is no longer a var; use its CONFIG key or APP (config.ts)`);
    if (FLAG_NAMES.has(key)) { if (value === "true" || value === true) on.add(key); else on.delete(key); continue; }
    if (key === "features") { for (const name of value as string[]) on.add(name); continue; }
    if (CONFIG_KEYS.includes(key)) { if (value !== undefined) (settings as Record<string, unknown>)[key] = value; continue; }
    out[key] = value;
  }
  if (on.size) settings.features = [...FLAG_NAMES].filter(name => on.has(name));
  return { ...out, CONFIG: configJson(settings) } as T & { CONFIG: string };
}
