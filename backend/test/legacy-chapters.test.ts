import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { LEGACY_CHAPTERS } from "../src/v2/legacy-chapters";
import { CHAPTERS, RELAY_KEY, advertisedChapters, chapter, creatable } from "../src/v2/chapters";
import { DEFINITION_BOARDS_HEADER, boardChapter, boardKey, boardsFor, knownBoard } from "../src/leaderboards/boards";
import openings from "../../game/content/board_openings.json";

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
  it("leaves each changed chapter's board to older apps and ranks its current definition on a fresh board", () => {
    // The file the app's board keys read too (game/services/leaderboard_runs.gd) names exactly these boards' openings.
    expect((openings as { boards: Record<string, string> }).boards).toEqual(Object.fromEntries(LEGACY_CHAPTERS.map(entry => [`${entry.key.level_id}@${entry.key.level_version}`, entry.key.definition_hash])));
    const ask = (header?: string) => new Request("https://example.invalid/v1/duels/ghosts", { headers: header ? { [DEFINITION_BOARDS_HEADER]: header } : {} });
    expect(boardsFor(ask("1"))).toHaveLength(boardsFor(ask()).length);
    for (const entry of LEGACY_CHAPTERS) {
      const plain = `${entry.key.level_id}@${entry.key.level_version}`;
      const current = CHAPTERS.find(row => row.adapter.key.level_id === entry.key.level_id && row.adapter.key.level_version === entry.key.level_version)!.adapter;
      const fresh = `${entry.key.level_id}-${current.key.definition_hash.slice(0, 8)}@${entry.key.level_version}`;
      expect(boardKey(entry.key)).toBe(plain);
      expect(boardKey(current.key)).toBe(fresh);
      expect([knownBoard(plain), knownBoard(fresh)]).toEqual([plain, fresh]);
      expect(boardChapter(plain)).toBe(entry);
      expect(boardChapter(fresh)).toBe(current);
      expect(boardsFor(ask("1"))).toContain(fresh);
      expect(boardsFor(ask("1"))).not.toContain(plain);
      expect(boardsFor(ask())).toContain(plain);
      expect(boardsFor(ask())).not.toContain(fresh);
    }
    // An unchanged chapter keeps its one board for every app.
    expect(boardKey(RELAY_KEY)).toBe(`${RELAY_KEY.level_id}@${RELAY_KEY.level_version}`);
    expect(boardChapter(boardKey(RELAY_KEY))).toBe(chapter(RELAY_KEY));
    expect(boardsFor(ask("1"))).toContain(boardKey(RELAY_KEY));
    expect(boardsFor(ask())).toContain(boardKey(RELAY_KEY));
  });
});
