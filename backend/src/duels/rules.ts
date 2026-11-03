/**
 * The duel rules as numbers. Pure: no storage, no env.
 *
 * A duel is two pairs racing the same chapter version, each in its own fresh
 * room (duels-concepts/IDEAS.md). The faster total of game ticks wins: the
 * ticks of every turn on the finishing branch, as the Fastest pair board counts
 * them. Every turn is unassisted: a duel's room refuses Forgiving catches
 * (v2/room.ts), and the replay check fails an assisted run. A ghost race is one pair against a
 * recorded time; while duel run checks are on (DUEL_RUN_CHECKS, off by default), a run faster than the
 * developers' ghost is checked too (model.ts awaitsCheck).
 * Pay is in pollen/ (POLLEN-RULES.md "Duels and ghost races").
 */

/** The party actions, POST /v1/duels/party/<action> (routes.ts; pollen/looks-routes.ts keeps the caller's look on each). */
export const PARTY_ACTIONS = ["invite", "accept", "dismiss", "cancel", "leave"] as const;
/**
 * Friend duels a pair may have waiting or running at once (challenges it sent or got count too). Ghost races do not count.
 * Plenty for normal play, too few for spam (owner, 2026-11-02). The lobby reports it (routes.ts `limits.friend`), so the
 * phone's limit line follows; game/services/duels_client.gd FRIEND_LIMIT is only its fallback and stays in step.
 */
export const MAX_FRIEND_DUELS_PER_PAIR = 10;
/** Ghost races a pair may have running at once. */
export const MAX_GHOST_RACES_PER_PAIR = 3;
/** A challenge nobody answers fades after this long, with no countdown shown. */
export const CHALLENGE_TTL_MS = 7 * 86_400_000;
/** A running duel with no turn from anyone for this long ends unfinished: no win and no loss. */
export const STALL_MS = 30 * 86_400_000;
/** A side's room claim whose room never appeared may be taken over by the partner after this long. */
export const ROOM_CLAIM_TAKEOVER_MS = 120_000;
/** A party invite fades after this long. */
export const PARTY_INVITE_TTL_MS = 7 * 86_400_000;
/** Party invites a player may hold at once; the oldest goes past it. */
export const MAX_PARTY_INVITES = 8;
/**
 * Duel pointers kept per player, the oldest going first past it: room for the open friend duels and ghost races and a
 * week of result tiles. MAX_RECENT_DUELS keeps the open ones well inside it.
 */
export const MAX_MEMBER_DUELS = 40;
/** A player holding this many duels started in the last CHALLENGE_TTL_MS takes no new challenge. Above MAX_FRIEND_DUELS_PER_PAIR, so a busy pair still reaches its limit. */
export const MAX_RECENT_DUELS = 30;
/** A decided duel stays on the lobby this long, as a result tile. */
export const RESULT_SHOWN_MS = 7 * 86_400_000;
/** Raw duel runs waiting for the replay check, per board, while duel run checks are on (DUEL_RUN_CHECKS): a friend duel's run, or a ghost race's beating the developers' ghost, is checked before its win counts. */
export const MAX_DUEL_PROOFS = 64;
/** Duel records kept per board, newest first; settled ones go first past it. */
export const MAX_BOARD_DUELS = 512;
/** A stored duel run's final checkpoint is at most this long (as the board's own proofs). */
export const MAX_DUEL_PROOF_CHARS = 1_900_000;
/** Ticks per second, as every recording's tick_rate. */
export const TICK_RATE = 30;
/**
 * A ghost race whose pair never opened its room (no claim) ends unfinished this long after it started. The phone
 * opens the race's page with Play the moment it starts (presentation/duels/duels_flow.gd _race), and its first tap
 * on Play claims the room, so a race nobody claimed in two days was never going to be played.
 */
export const UNCLAIMED_RACE_MS = 2 * 86_400_000;
/**
 * An accepted friend duel in which neither pair opened its room ends unfinished this long after the accept. The
 * accepting player taps it on the lobby, whose tile then offers Play (duels_flow.gd _on_duel_action), and the sending
 * pair hears of it within a minute (lobby read, or a hint), but nothing pushes it and no deadline shows, so three days
 * leave room for a pair that accepts on Friday to play on Sunday. Once either pair taps Play the duel runs to STALL_MS.
 */
export const UNCLAIMED_DUEL_MS = 3 * 86_400_000;
/**
 * The no-room timers above count from this date at the earliest: while duels are off nobody can open a room, so a duel
 * accepted or a race started before duels came back on must not end the moment they do. Set it to the DUELS flip date.
 */
export const UNCLAIMED_SINCE_MS = Date.UTC(2026, 10, 3);
/** A full board settles at most this many of its open duels (those past a time rule) before it refuses a new one (store.ts makeRoom). */
export const MAX_SETTLED_ON_FULL = 32;
