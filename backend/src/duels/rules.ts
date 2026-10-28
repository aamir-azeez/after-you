/**
 * The duel rules as numbers. Pure: no storage, no env.
 *
 * A duel is two pairs racing the same chapter version, each in its own fresh
 * room (duels-concepts/IDEAS.md). The faster total of game ticks wins: the
 * ticks of every turn on the finishing branch, as the Fastest pair board counts
 * them, with assisted turns allowed. A ghost race is one pair against a
 * recorded time. Pay is in pollen/ (POLLEN-RULES.md "Duels and ghost races").
 */

/** Friend duels a pair may have waiting or running at once (challenges it sent or got count too). Ghost races do not count. */
export const MAX_FRIEND_DUELS_PER_PAIR = 3;
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
/** Duel pointers kept per player, the oldest going first past it. MAX_RECENT_DUELS keeps the open ones well inside it. */
export const MAX_MEMBER_DUELS = 24;
/** A player holding this many duels started in the last CHALLENGE_TTL_MS takes no new challenge. */
export const MAX_RECENT_DUELS = 12;
/** A decided duel stays on the lobby this long, as a result tile. */
export const RESULT_SHOWN_MS = 7 * 86_400_000;
/** Raw duel runs waiting for the replay check, per board: a friend duel's run is checked before its win counts. */
export const MAX_DUEL_PROOFS = 64;
/** Duel records kept per board, newest first; settled ones go first past it. */
export const MAX_BOARD_DUELS = 512;
/** A stored duel run's final checkpoint is at most this long (as the board's own proofs). */
export const MAX_DUEL_PROOF_CHARS = 1_900_000;
/** Ticks per second, as every recording's tick_rate. */
export const TICK_RATE = 30;
