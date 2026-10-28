import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { FLAG_VARS, flagOn, flags, type FlagName, type FlagVar, type ServerVars } from "../src/flags";

/**
 * The 34 flags that were live as their own "true" var and now live in FEATURES only. Deploys list them there, and
 * once their own vars are dropped FEATURES is their only switch, so each must be read through flagOn.
 */
const FOLDED: readonly FlagVar[] = [
  "COOP_CHAPTERS_ENABLED", "DISPLAY_NAMES_ENABLED", "END_REACTIONS_ENABLED", "FINISHED_ROOM_LEAVE_ENABLED", "FIRST_STEPS_ENABLED",
  "FRIEND_ROOM_EVENTS_ENABLED", "HARD_MODE_ENABLED", "HISTORY_OFFLOAD_ENABLED", "HOUSE_CHAPTER_ENABLED", "IN_RUN_REACTIONS_ENABLED",
  "IOS_WAITLIST_ENABLED", "JOURNEY_CHAPTERS_ENABLED", "LEGACY_TRANSFERRED_ROOM_UNBLOCK", "LIGHTHOUSE_V2_CHAPTER_ENABLED",
  "LIVE_CONNECTION_ENABLED", "LONG_WAY_HOME_V2_CHAPTER_ENABLED", "NOTIFICATIONS_ENABLED", "PHOTO_DELIVERY_ENABLED", "PHOTO_TRANSFER_ENABLED",
  "PLAY_GAMES_ENABLED", "PRESENCE_ENABLED", "PRESET_REACTIONS_ENABLED", "RELAY_PHOTOS_ENABLED", "REPLAY_TRANSFER_ENABLED",
  "REVENUECAT_DELETION_ENABLED", "ROOM_INDEX_ENABLED", "SAFETY_ENFORCEMENT_ENABLED", "TESTER_ACCESS_ENABLED", "TURN_OF_THE_TIDE_CHAPTER_ENABLED",
  "TURN_OF_THE_TIDE_V2_CHAPTER_ENABLED", "TURN_TRIES_ENABLED", "UPDATE_GATE_ENABLED", "V2_ROOMS_ENABLED", "WISHING_WELL_CHAPTER_ENABLED"];
const ROWS = Object.entries(FLAG_VARS) as [FlagName, FlagVar][];
const VAR_NAMES = new Set<string>(Object.values(FLAG_VARS));
const SOURCES = import.meta.glob<string>("../src/**/*.ts", { query: "?raw", import: "default", eager: true });

/** The source with its comments blanked (string-aware, so "https://" in a string stays), keeping offsets. */
function withoutComments(text: string): string {
  let out = "", quote: string | null = null;
  for (let i = 0; i < text.length; i++) {
    const c = text[i], next = text[i + 1];
    if (quote) { out += c; if (c === "\\") { out += next ?? ""; i++; } else if (c === quote) quote = null; continue; }
    if (c === '"' || c === "'" || c === "`") { quote = c; out += c; continue; }
    if (c === "/" && next === "/") { while (i < text.length && text[i] !== "\n") { out += " "; i++; } out += "\n"; continue; }
    if (c === "/" && next === "*") { const end = text.indexOf("*/", i + 2); const stop = end < 0 ? text.length : end + 2; out += text.slice(i, stop).replace(/[^\n]/g, " "); i = stop - 1; continue; }
    out += c;
  }
  return out;
}

/**
 * Where a flag var name may appear outside flags.ts: as a quoted FlagVar the chapter table hands to flagOn, or as a
 * quoted key in a Pick<ServerVars, ...> type. Anything else (env.X, env["X"], a destructured X) reads it directly.
 */
function allowed(file: string, code: string, at: number, name: string): boolean {
  const quoted = code[at - 1] === '"' && code[at + name.length] === '"';
  if (!quoted) return false;
  if (file.endsWith("/v2/chapters.ts") && /flag:\s*$/.test(code.slice(Math.max(0, at - 12), at - 1))) return true;
  const pick = code.lastIndexOf("Pick<ServerVars,", at);
  return pick >= 0 && !code.slice(pick, at).includes(">");
}

describe("flags folded into FEATURES", () => {
  it("lists 34 known flags, once each", () => {
    expect(FOLDED.length).toBe(34);
    expect(new Set(FOLDED).size).toBe(34);
    for (const name of FOLDED) expect(VAR_NAMES.has(name), name).toBe(true);
  });

  it("turns each folded flag on through FEATURES alone, with its own var absent", () => {
    for (const name of FOLDED) {
      const vars = { FEATURES: name } as ServerVars;
      expect(Object.hasOwn(vars, name)).toBe(false);
      expect(flagOn(vars, name), name).toBe(true);
      const [accessor] = ROWS.find(([, variable]) => variable === name)!;
      expect(flags[accessor](vars), accessor).toBe(true);
    }
  });

  it("turns on exactly the folded flags when FEATURES lists all 34, whatever their own vars said", () => {
    const vars = { FEATURES: FOLDED.join(","), ...Object.fromEntries(FOLDED.map(name => [name, "false"])) } as ServerVars;
    for (const [accessor, name] of ROWS) expect(flags[accessor](vars), name).toBe(FOLDED.includes(name));
  });

  it("reads no flag var outside flags.ts except through flagOn", () => {
    const found: string[] = [];
    for (const [file, text] of Object.entries(SOURCES)) {
      if (file.endsWith("/src/flags.ts")) continue;
      const code = withoutComments(text);
      for (const name of VAR_NAMES) {
        for (const match of code.matchAll(new RegExp(`\\b${name}\\b`, "g"))) {
          if (!allowed(file, code, match.index!, name)) found.push(`${file}: ${code.slice(Math.max(0, match.index! - 30), match.index! + name.length + 10).replace(/\s+/g, " ")}`);
        }
      }
    }
    expect(found).toEqual([]);
  });

  it("keeps FEATURES in every narrowed env type that names a flag var", () => {
    const missing: string[] = [];
    for (const [file, text] of Object.entries(SOURCES)) {
      for (const match of withoutComments(text).matchAll(/Pick<ServerVars,([^>]*)>/g)) {
        const keys = [...match[1].matchAll(/"([A-Z0-9_]+)"/g)].map(m => m[1]);
        if (keys.some(key => VAR_NAMES.has(key)) && !keys.includes("FEATURES")) missing.push(`${file}: ${match[0]}`);
      }
    }
    expect(missing).toEqual([]);
  });

  it("declares no flag var and no FEATURES in wrangler.jsonc, so a deploy never brings a folded var back", () => {
    const declared = Object.keys(env).filter(key => VAR_NAMES.has(key) || key === "FEATURES");
    expect(declared).toEqual([]);
  });
});
