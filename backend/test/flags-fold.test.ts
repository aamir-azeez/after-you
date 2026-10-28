import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { FLAG_VARS, flagOn, flags, type FlagName, type FlagVar, type ServerVars } from "../src/flags";
import { CHAPTERS } from "../src/v2/chapters";

const ROWS = Object.entries(FLAG_VARS) as [FlagName, FlagVar][];
const FLAGS_SOURCE = Object.values(import.meta.glob<string>("../src/flags.ts", { query: "?raw", import: "default", eager: true }))[0];
/**
 * The flags whose FLAG_VARS doc ends "Set only through FEATURES.": FEATURES is their one switch in production, so each
 * must be read through flagOn. flags.ts is the one list; the deploy runner and flip-features read the same marker.
 */
const FEATURES_ONLY: readonly FlagVar[] = (() => {
  const block = FLAGS_SOURCE.slice(FLAGS_SOURCE.indexOf("export const FLAG_VARS"), FLAGS_SOURCE.indexOf("} as const);"));
  return [...block.matchAll(/\/\*\*(.*?)\*\/\s*\n\s*\w+: "([A-Z0-9_]+)",/g)].filter(m => m[1].includes("Set only through FEATURES.")).map(m => m[2] as FlagVar);
})();
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
  it("marks the 34 folded flags and the seven born in FEATURES, each once, and every chapter flag", () => {
    expect(FEATURES_ONLY.length).toBe(41);
    expect(new Set(FEATURES_ONLY).size).toBe(41);
    expect(FEATURES_ONLY.filter(name => name.endsWith("_ENABLED") || name === "LEGACY_TRANSFERRED_ROOM_UNBLOCK").length).toBe(34);
    for (const row of CHAPTERS) if (row.flag) expect(FEATURES_ONLY.includes(row.flag), row.flag).toBe(true);
  });

  it("turns each marked flag on through FEATURES alone, with its own var absent", () => {
    for (const name of FEATURES_ONLY) {
      const vars = { FEATURES: name } as ServerVars;
      expect(Object.hasOwn(vars, name)).toBe(false);
      expect(flagOn(vars, name), name).toBe(true);
      const [accessor] = ROWS.find(([, variable]) => variable === name)!;
      expect(flags[accessor](vars), accessor).toBe(true);
    }
  });

  it("turns on exactly the marked flags when FEATURES lists them all, whatever their own vars said", () => {
    const vars = { FEATURES: FEATURES_ONLY.join(","), ...Object.fromEntries(FEATURES_ONLY.map(name => [name, "false"])) } as ServerVars;
    for (const [accessor, name] of ROWS) expect(flags[accessor](vars), name).toBe(FEATURES_ONLY.includes(name));
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
