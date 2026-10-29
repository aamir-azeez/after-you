import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { FLAG_NAMES, RETIRED_FLAGS } from "../src/flags";
import { CHAPTERS } from "../src/v2/chapters";

/**
 * Every server flag folded into CONFIG's features list (the 2026-10-28 fold put them in FEATURES; lean-config moved
 * FEATURES into CONFIG and retired the 25 that must stay on). These guards keep it that way.
 */
const SOURCES = import.meta.glob<string>("../src/**/*.ts", { query: "?raw", import: "default", eager: true });
const WRANGLER = Object.values(import.meta.glob<string>("../wrangler.jsonc", { query: "?raw", import: "default", eager: true }))[0];

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
 * Where a flag name may appear outside flags.ts: as a quoted FlagVar a chapter row hands to flagOn. Anything else
 * (env.X, env["X"], a destructured X) would read a var no deploy sets.
 */
function allowed(file: string, code: string, at: number, name: string): boolean {
  const quoted = code[at - 1] === '"' && code[at + name.length] === '"';
  return quoted && file.endsWith("/v2/chapters.ts") && /flag:\s*$/.test(code.slice(Math.max(0, at - 12), at - 1));
}

describe("flags in CONFIG", () => {
  it("reads no flag or retired flag name outside flags.ts except through flagOn", () => {
    const found: string[] = [];
    for (const [file, text] of Object.entries(SOURCES)) {
      if (file.endsWith("/src/flags.ts")) continue;
      const code = withoutComments(text);
      for (const name of [...FLAG_NAMES, ...RETIRED_FLAGS]) {
        for (const match of code.matchAll(new RegExp(`\\b${name}\\b`, "g"))) {
          if (!allowed(file, code, match.index!, name)) found.push(`${file}: ${code.slice(Math.max(0, match.index! - 30), match.index! + name.length + 10).replace(/\s+/g, " ")}`);
        }
      }
    }
    expect(found).toEqual([]);
  });

  it("gates no chapter with a retired flag", () => {
    for (const row of CHAPTERS) expect((RETIRED_FLAGS as readonly string[]).includes(row.flag), row.flag).toBe(false);
  });

  it("declares no var at all in wrangler.jsonc, so a deploy never ships a default or the owner's aliases", () => {
    expect(withoutComments(WRANGLER)).not.toMatch(/"vars"\s*:/);
    expect(Object.entries(env).filter(([, value]) => typeof value === "string").map(([key]) => key)).toEqual([]);
  });
});
