import { errorCode, logWarning } from "../log";
import { sideOf, type Duel } from "./model";
import type { DuelLink } from "./room-link";

/**
 * A public duel side's room and its board (duels/public.ts). The room is made by whichever seated player opens it
 * first, possibly before their partner's seat is taken; a player seated later joins it with the invite code their
 * own duel view carries. The room asks the board once whether that player holds the seat (seatHeld) before it lets
 * them in, then tells the board they entered (enteredSeat), after which their leaving ends the side.
 */

/** Whether `player` holds a seat on the room's side of its running duel. One board request; false on any failure. */
export async function seatHeld(env: Pick<Env, "LEADERBOARD_BOARDS">, link: DuelLink, player: string): Promise<boolean> {
  try {
    const [duel] = (await env.LEADERBOARD_BOARDS.getByName(link.board).duelRead([link.duel_id])) as unknown as Duel[];
    return !!duel && duel.status === "running" && sideOf(duel, player) === link.side;
  } catch (error) {
    logWarning("public_seat_check_failed", { code: errorCode(error) });
    return false;
  }
}

/** After the join: the seat is entered. Best effort: the side's next turn note naming the player marks it too (model.ts progress). */
export async function enteredSeat(env: Pick<Env, "LEADERBOARD_BOARDS">, link: DuelLink, player: string): Promise<void> {
  try { await env.LEADERBOARD_BOARDS.getByName(link.board).duelAct(link.duel_id, { kind: "enter", player, side: link.side }); }
  catch (error) { logWarning("public_seat_enter_failed", { code: errorCode(error) }); }
}
