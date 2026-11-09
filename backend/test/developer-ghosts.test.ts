import { describe, expect, it } from "vitest";
import { bytesDigest, decodeBlob } from "../src/blob-codec";
import { DEVELOPER_GHOSTS, DEVELOPER_GHOST_TURNS, developerGhost, developerGhostSplits } from "../src/duels/developer-ghosts";
import { boardKey, boardKeys } from "../src/leaderboards/boards";
import { runTicks, walkRun } from "../src/leaderboards/run";
import { CHAPTERS } from "../src/v2/chapters";
import type { CheckpointV2 } from "../src/v2/protocol";
import manifest from "../../game/content/dev_ghosts.json";

/**
 * The developers' ghosts a ghost race times (src/duels/developer-ghosts.ts)
 * against the recorded runs in game/content/dev_ghosts.json: one per
 * board, each the same time as its run, and each run whole, unassisted on every
 * turn and played at the newest rules its chapter takes, as the board itself
 * would rank it. game/tests/test_dev_ghosts.gd replays every turn.
 */
type Row = { board: string; chapter: { level_id: string; level_version: number; definition_hash: string }; simulation_version: number; ticks: number; catch_assistance: boolean; byte_length: number; proof_hash: string; body: string };
const rows = (manifest as { schema_version: number; ghosts: Row[] }).ghosts;

describe("developers' ghosts", () => {
  it("cover every board, with the times their recorded runs take", () => {
    expect((manifest as { schema_version: number }).schema_version).toBe(1);
    expect(rows.map(row => row.board).sort()).toEqual([...boardKeys()].sort());
    expect(Object.keys(DEVELOPER_GHOSTS).sort()).toEqual([...boardKeys()].sort());
    for (const row of rows) expect(developerGhost(row.board)).toBe(row.ticks);
    expect(developerGhost("no-such-board@1")).toBeNull();
  });

  it("are whole runs with Forgiving catches off at each chapter's newest rules, in the shared blob format", async () => {
    for (const row of rows) {
      const adapter = CHAPTERS.map(entry => entry.adapter).find(entry => boardKey(entry.key) === row.board)!;
      expect(row.chapter).toEqual(adapter.key);
      const bytes = await decodeBlob(Uint8Array.from(atob(row.body), char => char.charCodeAt(0)), row.byte_length);
      expect(bytes, row.board).not.toBeNull();
      expect(await bytesDigest(bytes!)).toBe(row.proof_hash);
      const checkpoint = JSON.parse(new TextDecoder().decode(bytes!)) as CheckpointV2;
      const newest = Math.max(...(adapter.supported_simulation_versions ?? [adapter.simulation_version]));
      expect(walkRun(checkpoint), row.board).toMatchObject({ ticks: row.ticks, assisted: false, mixed: false, simulation_version: newest });
      expect(runTicks(checkpoint, adapter.stages.length), row.board).toEqual({ ticks: row.ticks, simulation_version: newest });
      expect(row.catch_assistance).toBe(false);
      // Its turns, as a race's view gives them: the run's own, two per stage, adding up to its time.
      expect(DEVELOPER_GHOST_TURNS[row.board], row.board).toEqual(walkRun(checkpoint)!.turns);
      expect(DEVELOPER_GHOST_TURNS[row.board]).toHaveLength(adapter.stages.length * 2);
      expect(developerGhostSplits(row.board)!.at(-1)).toBe(row.ticks);
    }
    expect(Object.keys(DEVELOPER_GHOST_TURNS).sort()).toEqual([...boardKeys()].sort());
    expect(developerGhostSplits("no-such-board@1")).toBeNull();
  });
});
