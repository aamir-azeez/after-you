import { describe, expect, it } from "vitest";
import blocklist from "../../game/content/display_name_blocklist.json";
import anonymous from "../../game/content/anonymous_names.json";
import vectors from "../../game/tests/fixtures/display_names/name_filter_vectors.json";
import { blockEntries, blockedName, foldName, runPattern } from "../src/name-filter";
import { cleanDisplayName } from "../src/display-names";

// The game runs the same checks on the same files (game/tests/test_name_filter.gd).
const entries = [...blockEntries("substrings"), ...blockEntries("words")];
const lookalikes = blocklist.folding.lookalikes as Record<string, string>;

/** Ways a player might write an entry. The game's suite makes the same ones. */
function disguises(entry: string): string[] {
  const letters = [...entry];
  const map = (table: Record<string, string>) => letters.map(c => table[c] ?? c).join("");
  // The first lookalike listed for each Latin letter.
  const look: Record<string, string> = {};
  for (const [from, to] of Object.entries(lookalikes)) if (to.length === 1 && !(to in look)) look[to] = from;
  const full = (c: string) => /[a-z]/.test(c) ? String.fromCodePoint(0xff41 + c.charCodeAt(0) - 97) : /[0-9]/.test(c) ? String.fromCodePoint(0xff10 + c.charCodeAt(0) - 48) : c;
  const bold = (c: string) => /[a-z]/.test(c) ? String.fromCodePoint(0x1d400 + c.charCodeAt(0) - 97) : /[0-9]/.test(c) ? String.fromCodePoint(0x1d7ce + c.charCodeAt(0) - 48) : c;
  return [
    entry,
    entry.toUpperCase(),
    entry[0].toUpperCase() + entry.slice(1),
    letters.join(" "),
    letters.join("."),
    letters.join("-"),
    letters.map(c => c + c).join(""),
    letters.map(c => "aeiouy".includes(c) ? c + "́" : c).join(""),
    map({ o: "0", i: "1", e: "3", a: "4", s: "5", t: "7", b: "8", g: "9" }),
    map({ o: "0", l: "1", e: "3", a: "4", s: "$" }),
    map(look),
    letters.map(full).join(""),
    letters.map(bold).join(""),
    `Big ${entry}`,
    `${entry}_99`
  ];
}

describe("display name word filter", () => {
  it("keeps one tidy list: lowercase a to z or digits, sorted, no repeats, no entry inside another", () => {
    const categories = blocklist.categories as Record<string, { substrings: string[]; words: string[] }>;
    expect(Object.keys(categories).sort()).toEqual(["ableist", "hate_violence", "homophobic_transphobic", "racial_ethnic", "sexual"]);
    for (const [name, category] of Object.entries(categories)) {
      expect(Object.keys(category).sort(), name).toEqual(["substrings", "words"]);
      for (const list of [category.substrings, category.words]) expect(list, name).toEqual([...list].sort());
    }
    expect(new Set(entries).size).toBe(entries.length);
    for (const entry of entries) expect(entry).toMatch(/^[a-z0-9]+$/);
    // A substring inside another entry makes that entry pointless.
    for (const part of blockEntries("substrings")) for (const entry of entries) if (entry !== part) expect(entry.includes(part), `${part} in ${entry}`).toBe(false);
    for (const word of blocklist.allowed_words) expect(new RegExp(`^(?:${blockEntries("words").map(runPattern).join("|")})$`).test(word), word).toBe(true);
  });

  it("matches runs of a letter that many times or more", () => {
    expect(runPattern("nigger")).toBe("n+i+g{2,}e+r+");
    expect(runPattern("kkk")).toBe("k{3,}");
    expect(runPattern("1488")).toBe("1+4+8{2,}");
  });

  it("refuses every entry, plain and disguised", () => {
    for (const entry of entries) for (const name of disguises(entry)) expect(blockedName(name), JSON.stringify(name)).toBe(true);
  });

  it("refuses the shared blocked names and passes the shared allowed ones", () => {
    for (const name of vectors.blocked) expect(blockedName(name), JSON.stringify(name)).toBe(true);
    for (const name of vectors.allowed) {
      expect(blockedName(name), name).toBe(false);
      expect(cleanDisplayName(name), name).toMatchObject({ ok: true });
    }
  });

  it("folds names the same way the game does", () => {
    for (const { input, plain } of vectors.folds) expect(foldName(input), JSON.stringify(input)).toBe(plain);
  });

  it("passes every anonymous name", () => {
    for (const word of anonymous.words) {
      expect(blockedName(word), word).toBe(false);
      for (let n = 10; n < 100; n++) expect(blockedName(`${word} ${n}`), `${word} ${n}`).toBe(false);
    }
  });
});
