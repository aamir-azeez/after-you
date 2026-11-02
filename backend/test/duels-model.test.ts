import { describe, expect, it } from "vitest";
import { accept, awaitsCheck, blankSide, claimRoom, decide, decline, forgetPlayer, isOpen, knownKey, leave, milestone, newFriendDuel, newsRecipients, newGhostRace, players, progress as progressWith, score, settle, sideOf, verdict, viewFor, waiveChecks, type Duel, type ProgressNote } from "../src/duels/model";
import { CHALLENGE_TTL_MS, ROOM_CLAIM_TAKEOVER_MS, STALL_MS } from "../src/duels/rules";
import { blankParty, noteLook } from "../src/duels/party";
import { runProgress } from "../src/duels/ticks";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
import firstB from "../../game/tests/fixtures/v2/relay-b.json";
import secondA from "../../game/tests/fixtures/v2/garden-a.json";
import secondB from "../../game/tests/fixtures/v2/garden-b.json";
import middle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import final from "../../game/tests/fixtures/v2/final-checkpoint.json";
import type { CheckpointV2, RecordingV2 } from "../src/v2/protocol";
import { price } from "../src/pollen/earn";
import { duelPremium, validDuelLink } from "../src/duels/room-link";
import { validTurnFacts } from "../src/pollen/turn-facts";
import { isoWeek } from "../src/pollen/week";

// Synthetic ids only.
const [A1, A2, B1, B2, X] = ["a1".padEnd(22, "a"), "a2".padEnd(22, "a"), "b1".padEnd(22, "b"), "b2".padEnd(22, "b"), "xx".padEnd(22, "x")];
const CHAPTER = { level_id: "relay-isles", level_version: 2, definition_hash: "f".repeat(64) };
const T0 = 1_800_000_000_000;
/** A turn's note with duel run checks on (DUEL_RUN_CHECKS), as most of these cases are; "duel run checks off" below passes false. */
const progress = (duel: Duel, note: ProgressNote, now: number) => progressWith(duel, note, now, true);

function friend(now = T0): Duel {
  return newFriendDuel({ duel_id: "d".repeat(32), board: "relay-isles@2", chapter: CHAPTER, steps: 4, starter: A1,
    a: blankSide([A1, A2], "pa"), b: blankSide([B1, B2], "pb"), known: [knownKey(A1, B1)] }, now);
}
function ghost(ticks = 1000, now = T0, source: "board" | "developer" = "board"): Duel {
  return newGhostRace({ duel_id: "g".repeat(32), board: "relay-isles@2", chapter: CHAPTER, steps: 4, starter: A1, a: blankSide([A1, A2], "pa"),
    ghost: source === "board" ? { source, entry_id: "e".repeat(32), rank: 1, ticks, names: null } : { source, entry_id: null, rank: null, ticks, names: null } }, now);
}
function note(room: string, revision: number, ticks: number, complete = false, steps = complete ? 4 : 1, at = T0 + revision * 1000): ProgressNote {
  return { room_id: room, revision, steps, ticks, turn: complete ? null : A1, complete, at_ms: at, entry_id: complete ? room.padEnd(32, "0").slice(0, 32) : null };
}
function running(now = T0): Duel {
  const duel = friend(now);
  expect(accept(duel, B1, now + 1, true).ok).toBe(true);
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
    expect(accept(duel, A2, T0 + 1, true)).toMatchObject({ ok: false, code: "duel_not_yours" });
    expect(accept(duel, X, T0 + 1, true)).toMatchObject({ ok: false, code: "duel_not_yours" });
    expect(accept(duel, B1, T0 + 1, true).ok).toBe(true);
    expect(duel.status).toBe("running");
    expect(accept(duel, B2, T0 + 5, true).ok).toBe(true);
    // The second accept changes nothing: the first one's time and account answer stay.
    expect(duel.accepted_ms).toBe(T0 + 1);
    expect(duel.eligible).toBe(true);
  });

  it("a challenge to a pair that dissolved closes, and stays closed", () => {
    const duel = friend();
    expect(accept(duel, B1, T0 + 1, false)).toMatchObject({ ok: false, code: "challenge_pair_gone" });
    expect(duel.status).toBe("pair_gone");
    expect(accept(duel, B2, T0 + 2, true)).toMatchObject({ ok: false, code: "challenge_pair_gone" });
  });

  it("Not now declines, the sender takes a challenge back, and both repeat safely", () => {
    const one = friend();
    expect(decline(one, B2, T0 + 1).ok).toBe(true);
    expect(one.status).toBe("declined");
    expect(decline(one, B1, T0 + 2).ok).toBe(true);
    expect(accept(one, B1, T0 + 3, true)).toMatchObject({ ok: false, code: "challenge_declined" });
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
    expect(accept(duel, B1, T0 + CHALLENGE_TTL_MS + 1, true)).toMatchObject({ ok: false, code: "challenge_expired" });
    expect(decline(duel, B1, T0 + CHALLENGE_TTL_MS + 1).ok).toBe(true);
  });

  it("the first member to open claims the side's room and the partner gets the same room", () => {
    const duel = friend();
    expect(claimRoom(duel, A1, { room_id: "ra", invite_code: "ia" }, T0)).toMatchObject({ ok: false, code: "duel_not_running" });
    accept(duel, B1, T0 + 1, true);
    expect(claimRoom(duel, A1, { room_id: "ra", invite_code: "ia" }, T0 + 2)).toMatchObject({ ok: true, value: { room_id: "ra", host: A1 } });
    // Both partners tapped at once: the second claim answers the first room.
    expect(claimRoom(duel, A2, { room_id: "ra2", invite_code: "ia2" }, T0 + 3)).toMatchObject({ ok: true, value: { room_id: "ra", host: A1 } });
    // A retried claim of the same room answers it again.
    expect(claimRoom(duel, A1, { room_id: "ra", invite_code: "ia" }, T0 + 4)).toMatchObject({ ok: true, value: { room_id: "ra" } });
    expect(claimRoom(duel, X, { room_id: "rx", invite_code: "ix" }, T0 + 4)).toMatchObject({ ok: false, code: "duel_not_yours" });
  });

  it("a room claim that never became a room passes to the partner after a while, never sooner", () => {
    const duel = friend();
    accept(duel, B1, T0, true);
    claimRoom(duel, A1, { room_id: "ra", invite_code: "ia" }, T0);
    expect(claimRoom(duel, A2, { room_id: "rb", invite_code: "ib" }, T0 + ROOM_CLAIM_TAKEOVER_MS - 1, true)).toMatchObject({ ok: true, value: { room_id: "ra" } });
    expect(claimRoom(duel, A2, { room_id: "rb", invite_code: "ib" }, T0 + ROOM_CLAIM_TAKEOVER_MS, false)).toMatchObject({ ok: true, value: { room_id: "ra" } });
    expect(claimRoom(duel, A2, { room_id: "rb", invite_code: "ib" }, T0 + ROOM_CLAIM_TAKEOVER_MS, true)).toMatchObject({ ok: true, value: { room_id: "rb", host: A2 } });
    // The claimer may take its own absent claim back too, with a new room.
    expect(claimRoom(duel, A2, { room_id: "rc", invite_code: "ic" }, T0 + 2 * ROOM_CLAIM_TAKEOVER_MS, true)).toMatchObject({ ok: true, value: { room_id: "rc", host: A2 } });
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

  it("a pair that left changes nothing more, even if its room plays on", () => {
    const duel = running();
    leave(duel, B1, T0 + 1);
    progress(duel, note("rb", 9, 100, true), T0 + 2);
    expect(duel.sides[1]).toMatchObject({ left: true, finished_ms: null, ticks: 0 });
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

  it("a race against a board run is decided the moment the pair finishes, with no check", () => {
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

  it("a run faster than the developers' ghost waits for the check, which decides it; a slower one is decided at once", () => {
    const finished = (check?: "passed" | "failed" | "error", ticks = 2999) => {
      const race = ghost(3000, T0, "developer");
      claimRoom(race, A2, { room_id: "rg", invite_code: "ig" }, T0);
      progress(race, note("rg", 5, ticks, true), T0 + 10);
      if (check) expect(verdict(race, race.sides[0].entry_id!, check, T0 + 20)).toBe(true);
      return race;
    };
    const waiting = finished();
    expect(waiting).toMatchObject({ status: "running", result: null });
    expect(waiting.sides[0].check).toBe("waiting");
    expect(settle(waiting, T0 + 30)).toBe(false);
    const passed = finished("passed");
    expect(viewFor(passed, A1)!.result).toMatchObject({ outcome: "won", reason: "faster", margin_ticks: 1 });
    expect(verdict(passed, passed.sides[0].entry_id!, "failed", T0 + 40)).toBe(false);
    // A run that fails the check, or one the job could not judge, ends the race with no result.
    expect(viewFor(finished("failed"), A1)!.result).toMatchObject({ outcome: "none", reason: "failed_check" });
    expect(viewFor(finished("error"), A1)!.result).toMatchObject({ outcome: "none", reason: "unchecked" });
    for (const ticks of [3000, 3001]) {
      const slow = finished(undefined, ticks);
      expect(slow.sides[0].check).toBe("none");
      expect(slow.status).toBe("decided");
    }
    // Only the developers' ghost and friend duels ask for the check, and only while duel run checks are on.
    expect(awaitsCheck(ghost(3000), 1, true)).toBe(false);
    expect(awaitsCheck(ghost(3000, T0, "developer"), 3000, true)).toBe(false);
    expect(awaitsCheck(friend(), 999_999, true)).toBe(true);
    expect(awaitsCheck(ghost(3000, T0, "developer"), 1, false)).toBe(false);
    expect(awaitsCheck(friend(), 999_999, false)).toBe(false);
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
  // The fixtures were recorded with forgiving catches on; a duel's room takes only unassisted turns, so the time reads them with it off.
  type Turn = { catch_assistance: boolean };
  type Link = { proof: { a: Turn; b: Turn; checkpoint?: Link; previous_checkpoint?: Link } };
  const unassisted = (checkpoint: unknown): CheckpointV2 => {
    const plain = structuredClone(checkpoint) as CheckpointV2 & Link;
    for (let link: Link | undefined = plain; link?.proof?.a; link = link.proof.checkpoint ?? link.proof.previous_checkpoint) { link.proof.a.catch_assistance = false; link.proof.b.catch_assistance = false; }
    return plain;
  };
  const plainA = { ...secondA, catch_assistance: false } as unknown as RecordingV2;

  it("counts every turn on the branch, with the pending first turn of the stage under way", () => {
    const whole = runProgress(unassisted(final), stages)!;
    const total = [firstA, firstB, secondA, secondB].reduce((sum, turn) => sum + turn.duration_ticks, 0);
    expect(whole).toEqual({ steps: 4, ticks: total, complete: true });
    const half = runProgress(unassisted(middle), stages, plainA)!;
    expect(half).toEqual({ steps: 3, ticks: firstA.duration_ticks + firstB.duration_ticks + secondA.duration_ticks, complete: false });
  });

  it("reads no duel time from a run with an assisted turn, as the board refuses it too", () => {
    expect(runProgress(final as unknown as CheckpointV2, stages)).toBeNull();
    expect(runProgress(unassisted(middle), stages, secondA as unknown as RecordingV2)).toBeNull();
  });

  it("refuses a broken chain", () => {
    const broken = structuredClone(final) as unknown as CheckpointV2 & { proof?: unknown };
    delete broken.proof;
    expect(runProgress(broken, stages)).toBeNull();
    expect(runProgress({ ...(final as unknown as CheckpointV2), stage_index: 9 }, stages)).toBeNull();
  });
});

describe("duel pay", () => {
  it("pays the premium in a friend duel's room until its run first finishes, never in a ghost race", () => {
    const link = { schema_version: 1 as const, duel_id: "d".repeat(32), board: "relay-isles@2", kind: "friend" as const, side: 0 as const, members: [A1, A2] };
    expect(duelPremium(link)).toBe(true);
    expect(duelPremium({ ...link, done: true })).toBe(false);
    expect(duelPremium({ ...link, kind: "ghost" })).toBe(false);
    expect(duelPremium(null)).toBe(false);
    expect(validDuelLink({ ...link, done: true })).toBe(true);
    expect(validDuelLink({ ...link, done: false })).toBe(false);
  });
  // POLLEN-RULES.md's worked example: a short-chapter bank turn of base 89 with a first try (111).
  const facts = { level_id: "first-steps", stage_id: "s1", role: "a" as const, ticks: 10, tries: 1, premium: false, hard: false, host: true, subscriber: false };
  it("adds half again on base and bonuses, worked out with the room boost and rounded once", () => {
    expect(price({ facts: { ...facts, boost_percent: 0, duel: true }, bank: true, tail_index: 0, bloom: 1 })).toMatchObject({ amount: 111, boost: 0, duel: 56, duel_percent: 50, total: 167 });
    expect(price({ facts: { ...facts, boost_percent: 10, duel: true }, bank: true, tail_index: 0, bloom: 1 })).toMatchObject({ amount: 111, boost: 11, duel: 56, total: 178 });
  });
  it("leaves blooms on the plain amount, the after-bank tail and ordinary turns as they were", () => {
    expect(price({ facts: { ...facts, boost_percent: 0, duel: true }, bank: true, tail_index: 0, bloom: 2 })).toMatchObject({ bloom_extra: 111, duel: 56, total: 278 });
    expect(price({ facts: { ...facts, boost_percent: 0, duel: true }, bank: false, tail_index: 0, bloom: 1 })).not.toHaveProperty("duel");
    expect(price({ facts: { ...facts, boost_percent: 0 }, bank: true, tail_index: 0, bloom: 1 })).not.toHaveProperty("duel");
  });
  it("accepts facts frozen before duels, and only true for the duel key", () => {
    const base = { schema_version: 1, room_id: "r".repeat(22), recording_hash: "a".repeat(64), turn_id: "t0-0-a", player_id: "p".repeat(22), accepted_at: T0, week: isoWeek(T0),
      level_id: "first-steps", stage_id: "s1", role: "a", ticks: 10, tries: 1, premium: false, hard: false, host: true, together: true, complete: false, subscriber: false, partner_subscriber: false, boost_percent: 0 };
    expect(validTurnFacts(base)).toBe(true);
    expect(validTurnFacts({ ...base, duel: true })).toBe(true);
    expect(validTurnFacts({ ...base, duel: false })).toBe(false);
  });
});

describe("duel run checks off", () => {
  const off = (duel: Duel, item: ProgressNote, now: number) => progressWith(duel, item, now, false);
  it("decide a friend duel the moment both runs finish, or one finishes and the other pair left", () => {
    const duel = running();
    expect(off(duel, note("ra", 9, 2000, true), T0 + 30).ok).toBe(true);
    expect(duel.sides[0]).toMatchObject({ check: "none", waived: true });
    expect(duel.status).toBe("running");
    expect(off(duel, note("rb", 9, 2100, true), T0 + 40).ok).toBe(true);
    expect(viewFor(duel, A1)!.result).toMatchObject({ outcome: "won", reason: "faster", margin_ticks: 100 });
    const left = running();
    off(left, note("ra", 9, 2000, true), T0 + 30);
    expect(leave(left, B1, T0 + 40).ok).toBe(true);
    expect(viewFor(left, A1)!.result).toMatchObject({ outcome: "won", reason: "left" });
  });

  it("decide a race faster than the developers' ghost at once, marked as counted without its check; other races as before", () => {
    const race = ghost(3000, T0, "developer");
    claimRoom(race, A2, { room_id: "rg", invite_code: "ig" }, T0);
    off(race, note("rg", 5, 2999, true), T0 + 10);
    expect(race.sides[0]).toMatchObject({ check: "none", waived: true });
    expect(viewFor(race, A1)!.result).toMatchObject({ outcome: "won", reason: "faster", margin_ticks: 1 });
    // A slower run, or one against a board run, never would have waited: nothing is waived.
    for (const [made, ticks] of [[ghost(3000, T0, "developer"), 3001], [ghost(3000), 1]] as const) {
      claimRoom(made, A2, { room_id: "rg", invite_code: "ig" }, T0);
      off(made, note("rg", 5, ticks, true), T0 + 10);
      expect(made.status).toBe("decided");
      expect(made.sides[0].waived).toBeUndefined();
    }
  });

  it("settle runs still waiting for a check as passed, once, and leave other duels alone", () => {
    const duel = running();
    progress(duel, note("ra", 9, 2000, true), T0 + 30);
    progress(duel, note("rb", 9, 2100, true), T0 + 40);
    expect(duel.sides.map(side => side!.check)).toEqual(["waiting", "waiting"]);
    expect(waiveChecks(duel, T0 + 50)).toBe(true);
    expect(duel.sides[0]).toMatchObject({ check: "passed", waived: true });
    expect(viewFor(duel, A1)!.result).toMatchObject({ outcome: "won", reason: "faster" });
    expect(duel.updated_ms).toBe(T0 + 50);
    expect(waiveChecks(duel, T0 + 60)).toBe(false);
    // One pair still playing: its finished rival counts as passed, and the duel waits for the other run.
    const half = running();
    progress(half, note("ra", 9, 2000, true), T0 + 30);
    expect(waiveChecks(half, T0 + 50)).toBe(true);
    expect(half).toMatchObject({ status: "running", result: null });
    expect(half.sides[0]!.check).toBe("passed");
    // Phones see a run that counted without its check as having none, so none says it waits for one.
    expect(viewFor(half, A1)!.sides[0].check).toBe("none");
    // A check already given stands, and a duel nobody waits on is not touched.
    const failed = running();
    progress(failed, note("ra", 9, 2000, true), T0 + 30);
    verdict(failed, failed.sides[0].entry_id!, "failed", T0 + 35);
    expect(waiveChecks(failed, T0 + 50)).toBe(false);
    expect(waiveChecks(running(), T0 + 50)).toBe(false);
    const race = ghost(3000, T0, "developer");
    claimRoom(race, A2, { room_id: "rg", invite_code: "ig" }, T0);
    progress(race, note("rg", 5, 2999, true), T0 + 10);
    expect(waiveChecks(race, T0 + 20)).toBe(true);
    expect(viewFor(race, A1)!.result).toMatchObject({ outcome: "won", reason: "faster" });
  });
});

describe("duel news", () => {
  it("tells both pairs of an answer, every turn, a finish, a leave, a check result and an end, never the player who acted", () => {
    const duel = friend();
    expect(newsRecipients(null, duel, A1).sort()).toEqual([A2, B1, B2].sort());
    let before = milestone(duel);
    expect(accept(duel, B1, T0 + 1, true).ok).toBe(true);
    expect(newsRecipients(before, duel, B1).sort()).toEqual([A1, A2, B2].sort());
    before = milestone(duel);
    expect(claimRoom(duel, A1, { room_id: "ra", invite_code: "ia" }, T0 + 2).ok).toBe(true);
    // A room claimed is news to its own pair only.
    expect(newsRecipients(before, duel, A1)).toEqual([A2]);
    expect(claimRoom(duel, B2, { room_id: "rb", invite_code: "ib" }, T0 + 3).ok).toBe(true);
    before = milestone(duel);
    // A mid-run turn moves the steps, time and whose turn it is that both pages show: the other pair and the partner hear it.
    expect(progress(duel, note("ra", 1, 100), T0 + 4).ok).toBe(true);
    expect(newsRecipients(before, duel, A1).sort()).toEqual([A2, B1, B2].sort());
    before = milestone(duel);
    // A repeated or older note moves nothing, so it tells nobody.
    expect(progress(duel, note("ra", 1, 100), T0 + 4).ok).toBe(true);
    expect(newsRecipients(before, duel, A1)).toEqual([]);
    expect(progress(duel, note("rb", 1, 90), T0 + 5).ok).toBe(true);
    expect(newsRecipients(before, duel, B2).sort()).toEqual([A1, A2, B1].sort());
    // Whose turn alone is news too: the partner's pill turns to "Your turn".
    before = milestone(duel);
    expect(progress(duel, { ...note("rb", 2, 90), turn: B2 }, T0 + 5).ok).toBe(true);
    expect(newsRecipients(before, duel, B1).sort()).toEqual([A1, A2, B2].sort());
    before = milestone(duel);
    expect(progress(duel, note("ra", 4, 400, true), T0 + 6).ok).toBe(true);
    expect(newsRecipients(before, duel, A1).sort()).toEqual([A2, B1, B2].sort());
    before = milestone(duel);
    expect(leave(duel, B1, T0 + 7).ok).toBe(true);
    expect(newsRecipients(before, duel, B1).sort()).toEqual([A1, A2, B2].sort());
    before = milestone(duel);
    expect(verdict(duel, duel.sides[0].entry_id!, "passed", T0 + 8)).toBe(true);
    expect(duel.status).toBe("decided");
    // A check result has no actor: everyone hears it.
    expect(newsRecipients(before, duel, null).sort()).toEqual([A1, A2, B1, B2].sort());
    expect(newsRecipients(milestone(duel), duel, null)).toEqual([]);
  });

  it("tells a ghost race's pair of its turns and check result and an expired challenge's players, and nobody erased", () => {
    const race = ghost(1000, T0, "developer");
    expect(claimRoom(race, A1, { room_id: "ra", invite_code: "ia" }, T0 + 1).ok).toBe(true);
    const claimed = milestone(race);
    expect(progress(race, note("ra", 1, 100), T0 + 2).ok).toBe(true);
    // A ghost race's turn has only the partner to tell.
    expect(newsRecipients(claimed, race, A1)).toEqual([A2]);
    expect(progress(race, note("ra", 4, 900, true), T0 + 2).ok).toBe(true);
    const waiting = milestone(race);
    expect(verdict(race, race.sides[0].entry_id!, "passed", T0 + 3)).toBe(true);
    expect(newsRecipients(waiting, race, null).sort()).toEqual([A1, A2].sort());
    const challenge = friend();
    const sent = milestone(challenge);
    expect(settle(challenge, T0 + CHALLENGE_TTL_MS)).toBe(true);
    expect(newsRecipients(sent, challenge, null).sort()).toEqual([A1, A2, B1, B2].sort());
    const open = friend(), asked = milestone(open);
    expect(forgetPlayer(open, B2, T0 + 1)).toBe(true);
    expect(newsRecipients(asked, open, null).sort()).toEqual([A1, A2, B1].sort());
  });
});

describe("duel looks", () => {
  const DAISY = { hat: "daisy" }, TIDE = { body: "tide" };
  it("keep only looks that are not the default, in members order, and nothing for a pair in the default", () => {
    expect(blankSide([A1, A2], "pa", [DAISY, undefined]).looks).toEqual([DAISY, {}]);
    expect(blankSide([A1, A2], "pa", [{}, undefined])).not.toHaveProperty("looks");
    expect(blankSide([A1, A2], "pa", [{ hat: "no_such_item" }, {}])).not.toHaveProperty("looks");
    expect(blankSide([A1, A2], "pa")).not.toHaveProperty("looks");
  });

  it("take each turn's room looks by member id, keep a look the note leaves out, and ignore an older note", () => {
    const duel = running();
    duel.sides[0].looks = [DAISY, {}];
    progress(duel, { ...note("ra", 2, 100), looks: { [A2]: TIDE } }, T0 + 10_000);
    expect(duel.sides[0].looks).toEqual([DAISY, TIDE]);
    progress(duel, { ...note("ra", 3, 120), looks: { [A1]: {}, [A2]: TIDE } }, T0 + 11_000);
    expect(duel.sides[0].looks).toEqual([{}, TIDE]);
    progress(duel, { ...note("ra", 1, 90), looks: { [A2]: DAISY } }, T0 + 12_000);
    expect(duel.sides[0].looks).toEqual([{}, TIDE]);
    progress(duel, { ...note("ra", 4, 130), looks: { [A2]: {} } }, T0 + 13_000);
    expect(duel.sides[0]).not.toHaveProperty("looks");
    // A note for one side never dresses the other.
    expect(duel.sides[1]).not.toHaveProperty("looks");
  });

  it("serve two looks per side, and the ghost's, only while looks are on, also for a member whose id is hidden", () => {
    const duel = running();
    duel.sides[0].looks = [DAISY, TIDE];
    const forB1 = viewFor(duel, B1, true)!;
    expect(forB1.sides[0].members).toEqual([A1, null]);
    expect(forB1.sides[0].looks).toEqual([DAISY, TIDE]);
    expect(forB1.sides[1]!.looks).toEqual([{}, {}]);
    expect(viewFor(duel, B1)!.sides[0]).not.toHaveProperty("looks");
    const race = ghost();
    race.ghost!.looks = [DAISY, {}];
    expect(viewFor(race, A1, true)!.ghost!.looks).toEqual([DAISY, {}]);
    expect(viewFor(race, A1)!.ghost).not.toHaveProperty("looks");
    // A stored look the catalogue no longer knows is served as the default.
    duel.sides[0].looks = [{ hat: "gone_item" }, TIDE];
    expect(viewFor(duel, A1, true)!.sides[0].looks).toEqual([{}, TIDE]);
  });

  it("keep a party row's look only when it changed, the default as no look at all", () => {
    const row = blankParty();
    expect(noteLook(row, {})).toBe(false);
    expect(row).not.toHaveProperty("look");
    expect(noteLook(row, DAISY)).toBe(true);
    expect(noteLook(row, { hat: "daisy" })).toBe(false);
    expect(noteLook(row, {})).toBe(true);
    expect(row).not.toHaveProperty("look");
  });

  it("erasing a player takes their look with their id", () => {
    const duel = running();
    duel.sides[0].looks = [DAISY, TIDE];
    duel.sides[1]!.looks = [{}, TIDE];
    forgetPlayer(duel, A1, T0 + 5);
    expect(duel.sides[0].looks).toEqual([{}, TIDE]);
    forgetPlayer(duel, B2, T0 + 6);
    expect(duel.sides[1]).not.toHaveProperty("looks");
  });
});
