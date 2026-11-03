import { errorCode, logWarning } from "../log";
import type { Outcome } from "../protocol";
import { knownKey, type Duel } from "./model";
import type { DuelLink } from "./room-link";

/**
 * A public duel side's room and its board (duels/public.ts). The room is made by whichever seated player opens it
 * first, possibly before their partner's seat is taken, and its link names only that player; a player seated later
 * joins with the invite code their own duel view carries. Before letting them in, the room asks the board to mark
 * their seat entered (admitSeat): one board request that checks the seat is theirs on this side and makes it final
 * in the same transaction, so a seat can never be given back and taken by someone else while they join.
 */

/** The board's answer for a joiner: admitted, and whether the room's first player already knows them (a party). Null when refused or on any failure. */
export async function admitSeat(env: Pick<Env, "LEADERBOARD_BOARDS">, link: DuelLink, player: string): Promise<{ known: boolean } | null> {
  try {
    const answer = (await env.LEADERBOARD_BOARDS.getByName(link.board).duelAct(link.duel_id, { kind: "enter", player, side: link.side })) as unknown as Outcome<{ duel: Duel }>;
    if (!answer.ok) return null;
    const first = link.members[0];
    return { known: first !== undefined && answer.value.duel.known.includes(knownKey(first, player)) };
  } catch (error) {
    logWarning("public_seat_admit_failed", { code: errorCode(error) });
    return null;
  }
}
