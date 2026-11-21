import { describe, expect, it } from "vitest";
import { bytesDigest, decodeBlob } from "../src/blob-codec";
import { LEGACY_SHIPPED_TICKS, LEGACY_SHIPPED_TURNS, legacyShippedGhost, legacyShippedSplits, legacyShippedTicks } from "../src/duels/legacy-shipped-our-run";
import { boardKey, boardKeys } from "../src/leaderboards/boards";
import { runTicks, walkRun } from "../src/leaderboards/run";
import { chapter } from "../src/v2/chapters";
import type { CheckpointV2 } from "../src/v2/protocol";
import manifest from "../../game/tests/fixtures/whole_runs.json";

/**
 * LEGACY: delete with src/duels/legacy-shipped-our-run.ts. The times an older app (no X-AfterYou-Our-Run header)
 * races as Our run, against the runs it shipped, kept as game/tests/fixtures/whole_runs.json: the same boards, each
 * the same time and turns as its run, each run whole and unassisted at its chapter's rules then.
 */
type Row = { board: string; chapter: { level_id: string; level_version: number; definition_hash: string }; simulation_version: number; ticks: number; catch_assistance: boolean; byte_length: number; proof_hash: string; body: string };
const rows = (manifest as { schema_version: number; ghosts: Row[] }).ghosts;

describe("the run older apps shipped as Our run", () => {
  it("names the shipped runs' boards, with the times those runs take, and nothing for a later board", () => {
    expect((manifest as { schema_version: number }).schema_version).toBe(1);
    const boards = new Set(boardKeys());
    expect(Object.keys(LEGACY_SHIPPED_TICKS).sort()).toEqual(rows.map(row => row.board).sort());
    expect(Object.keys(LEGACY_SHIPPED_TURNS).sort()).toEqual(rows.map(row => row.board).sort());
    for (const row of rows) {
      expect(boards.has(row.board), row.board).toBe(true);
      expect(legacyShippedTicks(row.board)).toBe(row.ticks);
      expect(legacyShippedGhost(row.board, LEGACY_SHIPPED_TURNS[row.board].length)).toEqual({ source: "developer", entry_id: null, rank: null, ticks: row.ticks, names: null, splits: legacyShippedSplits(row.board) });
    }
    expect(legacyShippedTicks("no-such-board@1")).toBeNull();
    expect(legacyShippedGhost("no-such-board@1", 4)).toBeNull();
  });

  it("are whole runs with Forgiving catches off at rules their chapter still takes, in the shared blob format", async () => {
    for (const row of rows) {
      // A run shipped on a published chapter before its hand controls went solid keeps that chapter's earlier
      // definition (legacy-chapters.ts), which the server still plays for older apps.
      const adapter = chapter(row.chapter);
      expect(boardKey(adapter.key)).toBe(row.board);
      const bytes = await decodeBlob(Uint8Array.from(atob(row.body), char => char.charCodeAt(0)), row.byte_length);
      expect(bytes, row.board).not.toBeNull();
      expect(await bytesDigest(bytes!)).toBe(row.proof_hash);
      const checkpoint = JSON.parse(new TextDecoder().decode(bytes!)) as CheckpointV2;
      const rules = row.simulation_version;
      expect(adapter.supported_simulation_versions ?? [adapter.simulation_version], row.board).toContain(rules);
      expect(walkRun(checkpoint), row.board).toMatchObject({ ticks: row.ticks, assisted: false, mixed: false, simulation_version: rules });
      expect(runTicks(checkpoint, adapter.stages.length), row.board).toEqual({ ticks: row.ticks, simulation_version: rules });
      expect(row.catch_assistance).toBe(false);
      // Its turns, as a race's view gives them: the run's own, two per stage, adding up to its time.
      expect(LEGACY_SHIPPED_TURNS[row.board], row.board).toEqual(walkRun(checkpoint)!.turns);
      expect(LEGACY_SHIPPED_TURNS[row.board]).toHaveLength(adapter.stages.length * 2);
      expect(legacyShippedSplits(row.board)!.at(-1)).toBe(row.ticks);
    }
    expect(legacyShippedSplits("no-such-board@1")).toBeNull();
  });
});
