import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { canonicalJson } from "../src/protocol";
import { checkpointAt } from "../src/v2/checkpoint-chain";
import type { CheckpointV2 } from "../src/v2/protocol";
import { CHAINS, fork, newRoom, open, play, playA } from "./history-chains";

afterEach(async () => { await reset(); });

describe("fork from the checkpoint nested in the live checkpoint", () => {
  it("unwraps every adapter's final checkpoint to each earlier stage exactly", () => {
    for (const chain of CHAINS) {
      const final = chain.stages.at(-1)!.checkpoint as CheckpointV2;
      for (let k = 1; k <= chain.stages.length; k++) expect(canonicalJson(checkpointAt(final, k)), `${chain.name} stage ${k}`).toBe(canonicalJson(chain.stages[k - 1].checkpoint));
      expect(checkpointAt(final, 0).stage_index).toBe(0);
      expect(() => checkpointAt(chain.stages[0].checkpoint as CheckpointV2, 2)).toThrow();
    }
  });

  it("gives every fork the same stored checkpoint bytes as the pair row it used to read", async () => {
    for (const chain of CHAINS) {
      for (let k = 1; k < chain.stages.length; k++) {
        const room = newRoom();
        const complete = await play(room, await open(room, chain), chain, 0);
        const pairRow = await runInDurableObject(room, (_, ctx) => JSON.stringify(JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM pairs WHERE pair_id=?", `p0-${k - 1}`).one().data).checkpoint));
        const forked = await fork(room, complete, k);
        expect(forked.stage_index).toBe(k);
        const stored = await runInDurableObject(room, (_, ctx) => JSON.stringify(JSON.parse(ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room").one().data).checkpoint));
        expect(stored, `${chain.name} fork at ${k}`).toBe(pairRow);
        expect(JSON.stringify(forked.checkpoint)).toBe(pairRow);
      }
    }
  });

  it("keeps the live checkpoint when forking the stage whose first turn is open", async () => {
    const chain = CHAINS.at(-1)!, room = newRoom();
    let state = await play(room, await open(room, chain), chain, 0, 3);
    const before = JSON.stringify(state.checkpoint);
    state = await playA(room, state, chain.stages[3]);
    const forked = await fork(room, state, 3);
    expect(JSON.stringify(forked.checkpoint)).toBe(before);
    expect(forked).toMatchObject({ branch: 1, stage_index: 3, a_turn_id: null, completed_pair_ids: ["p0-0", "p0-1", "p0-2"] });
  });
});
