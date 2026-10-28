import { describe, expect, it } from "vitest";
import { accept, blankSide, claimRoom, decide, decline, forgetPlayer, isOpen, knownKey, leave, newFriendDuel, newGhostRace, players, progress, score, settle, sideOf, verdict, viewFor, type Duel, type ProgressNote } from "../src/duels/model";
import { CHALLENGE_TTL_MS, ROOM_CLAIM_TAKEOVER_MS, STALL_MS } from "../src/duels/rules";
import { runProgress } from "../src/duels/ticks";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";
import type { CheckpointV2, RecordingV2 } from "../src/v2/protocol";

// Synthetic ids only.
const [A1, A2, B1, B2, X] = ["a1".padEnd(22, "a"), "a2".padEnd(22, "a"), "b1".padEnd(22, "b"), "b2".padEnd(22, "b"), "xx".padEnd(22, "x")];
const CHAPTER = { level_id: "relay-isles", level_version: 2, definition_hash: "f".repeat(64) };
const T0 = 1_800_000_000_000;

function friend(now = T0): Duel {
  return newFriendDuel({ duel_id: "d".repeat(32), board: "relay-isles@2", chapter: CHAPTER, steps: 4, starter: A1,
    a: blankSide([A1, A2], "pa"), b: blankSide([B1, B2], "pb"), known: [knownKey(A1, B1)] }, now);
}
function ghost(ticks = 1000, now = T0): Duel {
  return newGhostRace({ duel_id: "g".repeat(32), board: "relay-isles@2", chapter: CHAPTER, steps: 4, starter: A1, a: blankSide([A1, A2], "pa"),
    ghost: { source: "board", entry_id: "e".repeat(32), rank: 1, ticks, names: null } }, now);
}
function note(room: string, revision: number, ticks: number, complete = false, steps = complete ? 4 : 1, at = T0 + revision * 1000): ProgressNote {
  return { room_id: room, revision, steps, ticks, assisted: false, turn: complete ? null : A1, complete, at_ms: at, entry_id: complete ? room.padEnd(32, "0").slice(0, 32) : null };
}
function running(now = T0): Duel {
  const duel = friend(now);
  expect(accept(duel, B1, now + 1, true, true).ok).toBe(true);
  expect(claimRoom(duel, A1, { room_id: "ra", invite_code: "ia" }, now + 2).ok).toBe(true);
  expect(claimRoom(duel, B2, { room_id: "rb", invite_code: "ib" }, now + 3).ok).toBe(true);
  return duel;
}
function finishBoth(duel: Duel, a: number, b: number): void {
  progress(duel, note("ra", 9, a, true), T0 + 50_000);
  progress(duel, note("rb", 9, b, true), T0 + 60_000);
}

describe("duel state machine", () => {
  it("accepting twice answers the running duel and only the challenged pair may accept", () => {
    const duel = friend();
    expect(accept(duel, A2, T0 + 1, true, true)).toMatchObject({ ok: false, code: "duel_not_yours" });
    expect(accept(duel, X, T0 + 1, true, true)).toMatchObject({ ok: false, code: "duel_not_yours" });
    expect(accept(duel, B1, T0 + 1, true, true).ok).toBe(true);
    expect(duel.status).toBe("running");
    expect(accept(duel, B2, T0 + 5, true, false).ok).toBe(true);
    // The second accept changes nothing: the first one's time and account answer stay.
    expect(duel.accepted_ms).toBe(T0 + 1);
    expect(duel.eligible).toBe(true);
  });

  it("a challenge to a pair that dissolved closes, and stays closed", () => {
    const duel = friend();
    expect(accept(duel, B1, T0 + 1, false, true)).toMatchObject({ ok: false, code: "challenge_pair_gone" });
    expect(duel.status).toBe("pair_gone");
    expect(accept(duel, B2, T0 + 2, true, true)).toMatchObject({ ok: false, code: "challenge_pair_gone" });
  });

  it("Not now declines, the sender takes a challenge back, and both repeat safely", () => {
    const one = friend();
    expect(decline(one, B2, T0 + 1).ok).toBe(true);
    expect(one.status).toBe("declined");
    expect(decline(one, B1, T0 + 2).ok).toBe(true);
    expect(accept(one, B1, T0 + 3, true, true)).toMatchObject({ ok: false, code: "challenge_declined" });
    const two = friend();
    expect(decline(two, A2, T0 + 1).ok).toBe(true);
    expect(two.status).toBe("withdrawn");
    expect(decline(running(), B1, T0 + 9)).toMatchObject({ ok: false, code: "challenge_running" });
  });

  it("an unanswered challenge fades after its time, with no other effect", () => {
    const duel = friend();
    expect(settle(duel, T0 + CHALLENGE_TTL_MS - 1)).toBe(false);
    expect(settle(duel, T0 + CHALLENGE_TTL_MS)).toBe(true);
    expect(duel.status).toBe("expired");
    expect(accept(duel, B1, T0 + CHALLENGE_TTL_MS + 1, true, true)).toMatchObject({ ok: false, code: "challenge_expired" });
    expect(decline(duel, B1, T0 + CHALLENGE_TTL_MS + 1).ok).toBe(true);
  });

  it("the first member to open claims the side's room and the partner gets the same room", () => {
    const duel = friend();
    expect(claimRoom(duel, A1, { room_id: "ra", invite_code: "ia" }, T0)).toMatchObject({ ok: false, code: "duel_not_running" });
    accept(duel, B1, T0 + 1, true, true);
    expect(claimRoom(duel, A1, { room_id: "ra", invite_code: "ia" }, T0 + 2)).toMatchObject({ ok: true, value: { room_id: "ra", host: A1 } });
    // Both partners tapped at once: the second claim answers the first room.
    expect(claimRoom(duel, A2, { room_id: "ra2", invite_code: "ia2" }, T0 + 3)).toMatchObject({ ok: true, value: { room_id: "ra", host: A1 } });
    // A retried claim of the same room answers it again.
    expect(claimRoom(duel, A1, { room_id: "ra", invite_code: "ia" }, T0 + 4)).toMatchObject({ ok: true, value: { room_id: "ra" } });
    expect(claimRoom(duel, X, { room_id: "rx", invite_code: "ix" }, T0 + 4)).toMatchObject({ ok: false, code: "duel_not_yours" });
  });

  it("a room claim that never became a room passes to the partner after a while, never sooner", () => {
    const duel = friend();
    accept(duel, B1, T0, true, true);
    claimRoom(duel, A1, { room_id: "ra", invite_code: "ia" }, T0);
    expect(claimRoom(duel, A2, { room_id: "rb", invite_code: "ib" }, T0 + ROOM_CLAIM_TAKEOVER_MS - 1, true)).toMatchObject({ ok: true, value: { room_id: "ra" } });
    expect(claimRoom(duel, A2, { room_id: "rb", invite_code: "ib" }, T0 + ROOM_CLAIM_TAKEOVER_MS, false)).toMatchObject({ ok: true, value: { room_id: "ra" } });
    expect(claimRoom(duel, A2, { room_id: "rb", invite_code: "ib" }, T0 + ROOM_CLAIM_TAKEOVER_MS, true)).toMatchObject({ ok: true, value: { room_id: "rb", host: A2 } });
  });

  it("progress takes only newer revisions, so repeats and late notes never move a time back", () => {
    const duel = running();
    progress(duel, note("ra", 3, 400), T0 + 10);
    progress(duel, note("ra", 2, 999), T0 + 11);
    progress(duel, note("ra", 3, 999), T0 + 12);
    expect(duel.sides[0]).toMatchObject({ revision: 3, ticks: 400 });
    expect(progress(duel, note("rz", 4, 1), T0 + 13)).toMatchObject({ ok: false, code: "duel_room_unknown" });
  });

  it("both pairs finishing at once waits for both checks, then the faster run wins", () => {
    const duel = running();
    finishBoth(duel, 3000, 3100);
    expect(duel.status).toBe("running");
    expect(duel.sides.map(side => side!.check)).toEqual(["waiting", "waiting"]);
    // A finished side ignores later notes, even a redo with a better time.
    progress(duel, note("ra", 12, 10, true), T0 + 70_000);
    expect(duel.sides[0].ticks).toBe(3000);
    expect(verdict(duel, duel.sides[1]!.entry_id!, "passed", T0 + 80_000)).toBe(true);
    expect(duel.status).toBe("running");
    expect(verdict(duel, duel.sides[0].entry_id!, "passed", T0 + 90_000)).toBe(true);
    expect(duel.status).toBe("decided");
    expect(duel.result).toMatchObject({ winner: 0, reason: "faster", margin_ticks: 100 });
    // A repeated verdict is ignored.
    expect(verdict(duel, duel.sides[0].entry_id!, "failed", T0 + 91_000)).toBe(false);
    expect(viewFor(duel, A2)!.result!.outcome).toBe("won");
    expect(viewFor(duel, B1)!.result!.outcome).toBe("lost");
  });

  it("equal ticks is a draw, whoever finished first", () => {
    const duel = running();
    finishBoth(duel, 3000, 3000);
    verdict(duel, duel.sides[0].entry_id!, "passed", T0 + 1);
    verdict(duel, duel.sides[1]!.entry_id!, "passed", T0 + 2);
    expect(duel.status).toBe("decided");
    expect(duel.result).toMatchObject({ winner: null, reason: "draw", margin_ticks: 0 });
    expect(viewFor(duel, A1)!.result!.outcome).toBe("draw");
  });

  it("a run that fails the check loses, and one the job could not judge ends the duel unfinished", () => {
    const failed = running();
    finishBoth(failed, 3000, 3100);
    verdict(failed, failed.sides[0].entry_id!, "failed", T0 + 1);
    verdict(failed, failed.sides[1]!.entry_id!, "passed", T0 + 2);
    expect(failed.result).toMatchObject({ winner: 1, reason: "failed_check" });
    const unjudged = running();
    finishBoth(unjudged, 3000, 3100);
    verdict(unjudged, unjudged.sides[0].entry_id!, "passed", T0 + 1);
    verdict(unjudged, unjudged.sides[1]!.entry_id!, "error", T0 + 2);
    expect(unjudged.status).toBe("unfinished");
    expect(unjudged.result).toMatchObject({ winner: null, reason: "unchecked" });
  });

  it("a pair leaving mid duel hands the other pair the win once its run passes", () => {
    const duel = running();
    progress(duel, note("ra", 3, 500), T0 + 10);
    expect(leave(duel, B2, T0 + 20).ok).toBe(true);
    expect(duel.status).toBe("running");
    progress(duel, note("ra", 9, 2000, true), T0 + 30);
    expect(duel.status).toBe("running");
    verdict(duel, duel.sides[0].entry_id!, "passed", T0 + 40);
    expect(duel.result).toMatchObject({ winner: 0, reason: "left" });
    // Leaving again, or after the end, changes nothing.
    expect(leave(duel, B1, T0 + 50).ok).toBe(true);
    expect(duel.result!.winner).toBe(0);
  });

  it("leave is turned off once your own pair finished, and both pairs leaving ends it unfinished", () => {
    const duel = running();
    progress(duel, note("ra", 9, 2000, true), T0 + 30);
    expect(leave(duel, A1, T0 + 31)).toMatchObject({ ok: false, code: "duel_finished_for_you" });
    const both = running();
    leave(both, A1, T0 + 1);
    leave(both, B1, T0 + 2);
    expect(both.status).toBe("unfinished");
    expect(both.result!.reason).toBe("left");
  });

  it("leaving before an answer is a decline or a withdrawal", () => {
    const duel = friend();
    expect(leave(duel, B1, T0 + 1).ok).toBe(true);
    expect(duel.status).toBe("declined");
  });

  it("a stall ends the duel unfinished even when one pair finished", () => {
    const duel = running();
    progress(duel, note("ra", 9, 2000, true), T0 + 30);
    verdict(duel, duel.sides[0].entry_id!, "passed", T0 + 40);
    // The last turn was the finish, noted at its own time.
    expect(settle(duel, T0 + 9000 + STALL_MS - 1)).toBe(false);
    expect(settle(duel, T0 + 9000 + STALL_MS)).toBe(true);
    expect(duel.status).toBe("unfinished");
    expect(duel.result!.reason).toBe("stalled");
    expect(progress(duel, note("rb", 20, 10, true), T0 + STALL_MS * 2).ok).toBe(true);
    expect(duel.sides[1]!.finished_ms).toBeNull();
  });

  it("a ghost race is decided the moment the pair finishes, with no check", () => {
    const won = ghost(3000);
    claimRoom(won, A2, { room_id: "rg", invite_code: "ig" }, T0);
    progress(won, note("rg", 5, 2999, true), T0 + 10);
    expect(won.status).toBe("decided");
    expect(won.sides[0].check).toBe("none");
    expect(viewFor(won, A1)!.result).toMatchObject({ outcome: "won", margin_ticks: 1 });
    const lost = ghost(3000);
    claimRoom(lost, A1, { room_id: "rg", invite_code: "ig" }, T0);
    progress(lost, note("rg", 5, 3001, true), T0 + 10);
    expect(viewFor(lost, A2)!.result!.outcome).toBe("lost");
    expect(score(lost, 1)).toBe(3000);
    const tied = ghost(3000);
    claimRoom(tied, A1, { room_id: "rg", invite_code: "ig" }, T0);
    progress(tied, note("rg", 5, 3000, true), T0 + 10);
    expect(viewFor(tied, A2)!.result!.outcome).toBe("draw");
    const left = ghost();
    leave(left, A1, T0 + 1);
    expect(left.status).toBe("unfinished");
    expect(decide(left, T0 + 2)).toBe(false);
  });

  it("only the pair and checked friends see ids, and only your own side carries the room", () => {
    const duel = running();
    const forA1 = viewFor(duel, A1)!, forA2 = viewFor(duel, A2)!, forB1 = viewFor(duel, B1)!;
    expect(forA1.sides[0].members).toEqual([A1, A2]);
    expect(forA1.sides[1]!.members).toEqual([B1, null]);
    expect(forA2.sides[1]!.members).toEqual([null, null]);
    expect(forB1.sides[0].members).toEqual([A1, null]);
    expect(forA1.sides[0].room_id).toBe("ra");
    expect(forA1.sides[1]!.room_id).toBeUndefined();
    expect(forB1.mine).toBe(1);
    expect(viewFor(duel, X)).toBeNull();
  });

  it("erasing a player removes their id everywhere and ends an open duel unfinished", () => {
    const duel = running();
    expect(forgetPlayer(duel, B2, T0 + 5)).toBe(true);
    expect(players(duel)).not.toContain(B2);
    expect(duel.status).toBe("unfinished");
    expect(duel.result!.reason).toBe("erased");
    expect(forgetPlayer(friend(), X, T0)).toBe(false);
    const fresh = friend();
    forgetPlayer(fresh, A1, T0 + 1);
    expect(fresh.status).toBe("withdrawn");
    expect(fresh.starter).toBeNull();
    expect(fresh.known).toEqual([]);
  });

  it("open and side helpers", () => {
    const duel = friend();
    expect(isOpen(duel)).toBe(true);
    expect(sideOf(duel, B2)).toBe(1);
    expect(sideOf(duel, X)).toBe(-1);
    decline(duel, B1, T0);
    expect(isOpen(duel)).toBe(false);
  });
});

describe("duel time", () => {
  const stages = 2;
  // The fixtures were recorded with forgiving catches on, as most runs are.
  it("counts every turn on the branch, with the pending first turn of the stage under way", () => {
    const whole = runProgress(final as unknown as CheckpointV2, stages)!;
    const total = [firstA, firstB, secondA, secondB].reduce((sum, turn) => sum + turn.duration_ticks, 0);
    expect(whole).toEqual({ steps: 4, ticks: total, assisted: true, complete: true });
    const half = runProgress(middle as unknown as CheckpointV2, stages, secondA as unknown as RecordingV2)!;
    expect(half).toEqual({ steps: 3, ticks: firstA.duration_ticks + firstB.duration_ticks + secondA.duration_ticks, assisted: true, complete: false });
  });

  it("allows assisted turns and says so, where the board would refuse the run", () => {
    type Turn = { catch_assistance: boolean };
    type Link = { proof: { a: Turn; b: Turn; checkpoint?: Link; previous_checkpoint?: Link } };
    const plain = structuredClone(final) as unknown as CheckpointV2 & Link;
    for (let link: Link | undefined = plain; link?.proof?.a; link = link.proof.checkpoint ?? link.proof.previous_checkpoint) { link.proof.a.catch_assistance = false; link.proof.b.catch_assistance = false; }
    expect(runProgress(plain, stages)).toMatchObject({ assisted: false, complete: true });
    expect(runProgress(final as unknown as CheckpointV2, stages)).toMatchObject({ assisted: true, complete: true });
  });

  it("refuses a broken chain", () => {
    const broken = structuredClone(final) as unknown as CheckpointV2 & { proof?: unknown };
    delete broken.proof;
    expect(runProgress(broken, stages)).toBeNull();
    expect(runProgress({ ...(final as unknown as CheckpointV2), stage_index: 9 }, stages)).toBeNull();
  });
});
