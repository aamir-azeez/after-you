/// <reference types="vite/client" />
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { CHAPTERS, RELAY_KEY, advertisedChapters, chapter, chapterFlag } from "../src/v2/chapters";
import manifest from "../../game/tests/fixtures/golden/chapter_manifest.json";

// The game writes this manifest from its chapter registry (game/tests/test_chapter_manifest.gd).
// Every server chapter must agree with it, or the game drops the chapter from Play with a friend.
type Row = {
  key: string; level_id: string; level_version: number; definition_hash: string; premium: boolean; stage_count: number; family: string;
  recording_version: number; simulation_version: number; supported_simulation_versions: number[]; initial_checkpoint_hash: string;
  flag: string; max_branches: number; definition_fixture: string; initial_fixture: string;
};
const rows = Object.values(manifest.chapters) as Row[];
const bundled = import.meta.glob<{ default: unknown }>("../src/v2/*.json", { eager: true });
const fixtures = import.meta.glob<{ default: unknown }>(["../../game/tests/fixtures/*/*definition.json", "../../game/tests/fixtures/*/*initial-checkpoint.json"], { eager: true });
const fixture = (path: string) => fixtures["../../game/tests/fixtures/" + path]?.default;
/** Every server chapter's flag on, so a chapter only the server lists is advertised and caught. */
const ALL_FLAGS_ON = (): Env => {
  const result: Env = { ...env };
  for (const row of CHAPTERS) if (row.flag) Object.assign(result, { [row.flag]: "true" });
  return result;
};
const RELAY = `${RELAY_KEY.level_id}@${RELAY_KEY.level_version}`;

describe("chapter manifest shared with the game", () => {
  it("has one row per game key; order is the game's and is never compared", () => {
    expect(rows.map(row => row.key).sort()).toEqual([...manifest.keys].sort());
    expect(new Set(rows.map(row => `${row.level_id}@${row.level_version}`))).toEqual(new Set(manifest.keys));
  });
  it.each(rows.map(row => [row.key, row] as const))("%s matches its server adapter", async (_key, row) => {
    const adapter = chapter(row);
    expect(adapter.premium).toBe(row.premium);
    expect(adapter.stages.length).toBe(row.stage_count);
    expect(adapter.recording_version).toBe(row.recording_version);
    expect(adapter.simulation_version).toBe(row.simulation_version);
    expect(adapter.supported_simulation_versions).toEqual(row.supported_simulation_versions);
    expect(adapter.max_branches ?? 32).toBe(row.max_branches);
    // "" means always creatable: only Relay. Any other chapter needs its own flag, off by default.
    expect(typeof row.flag).toBe("string");
    expect(row.flag === "").toBe(row.key === RELAY);
    expect(chapterFlag(adapter)).toBe(row.flag);
    if (row.key !== RELAY) expect(env[row.flag as keyof Env]).toBe("false");
    // Exactly one bundled definition hashes to the game's definition hash.
    const matching: string[] = [];
    for (const [path, json] of Object.entries(bundled)) if (await digest(canonicalJson(json.default)) === row.definition_hash) matching.push(path);
    expect(matching).toHaveLength(1);
    if (row.definition_fixture) expect(bundled[matching[0]].default).toEqual(fixture(row.definition_fixture));
    const initial = adapter.initial();
    expect(initial.checkpoint_hash).toBe(row.initial_checkpoint_hash);
    expect({ level_id: initial.level_id, level_version: initial.level_version, definition_hash: initial.definition_hash })
      .toEqual({ level_id: row.level_id, level_version: row.level_version, definition_hash: row.definition_hash });
    if (row.initial_fixture) expect(initial).toEqual(fixture(row.initial_fixture));
  });
  it("lets only Relay be always creatable on the server", () => {
    for (const row of CHAPTERS) expect(row.flag === "", `${row.adapter.key.level_id}@${row.adapter.key.level_version}`).toBe(row.adapter === chapter(RELAY_KEY));
  });
  it("advertises exactly the manifest's chapters with every server flag on, in any order", () => {
    expect(CHAPTERS).toHaveLength(rows.length);
    const advertised = advertisedChapters(ALL_FLAGS_ON(), 2);
    expect(new Set(advertised.map(entry => `${entry.level_id}@${entry.level_version}`))).toEqual(new Set(manifest.keys));
    expect(advertised).toHaveLength(rows.length);
    for (const entry of advertised) expect(rows.find(row => row.definition_hash === entry.definition_hash)?.stage_count).toBe(entry.stage_count);
  });
});
