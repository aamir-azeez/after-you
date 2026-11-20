import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { LEGACY_CHAPTERS } from "../src/v2/legacy-chapters";
import { CHAPTERS, advertisedChapters, chapter, creatable } from "../src/v2/chapters";

const files = import.meta.glob<{ default: Record<string, unknown> }>("../src/v2/legacy/*.json", { eager: true });
const definitions = Object.entries(files).filter(([path]) => !path.endsWith("-initial.json")).map(([, module]) => module.default);

// Published chapters as older apps hold them (solid hand controls, owner 2026-11-20).
describe("legacy chapters", () => {
  it("keeps each published definition's old hash, as its own bytes digest", async () => {
    expect(LEGACY_CHAPTERS).toHaveLength(definitions.length);
    for (const entry of LEGACY_CHAPTERS) {
      const definition = definitions.find(value => value.id === entry.key.level_id && value.version === entry.key.level_version)!;
      expect(await digest(canonicalJson(definition)), `${entry.key.level_id}@${entry.key.level_version}`).toBe(entry.key.definition_hash);
    }
  });
  it("finds an old room's chapter and lists it after the rows on room level 2 only, beside a row with the new hash", () => {
    const advertised = advertisedChapters(env as Env, 2);
    expect(advertised.slice(-LEGACY_CHAPTERS.length).map(item => item.definition_hash)).toEqual(LEGACY_CHAPTERS.map(entry => entry.key.definition_hash));
    expect(advertised.length).toBeLessThanOrEqual(64);
    for (const entry of LEGACY_CHAPTERS) {
      expect(chapter(entry.key)).toBe(entry);
      expect(creatable(entry, env as Env)).toBe(true);
      expect(advertisedChapters(env as Env, 1).some(item => item.definition_hash === entry.key.definition_hash)).toBe(false);
      const current = CHAPTERS.find(row => row.adapter.key.level_id === entry.key.level_id && row.adapter.key.level_version === entry.key.level_version);
      expect(current?.adapter.key.definition_hash, `${entry.key.level_id}@${entry.key.level_version} has a new hash`).not.toBe(entry.key.definition_hash);
    }
  });
});
