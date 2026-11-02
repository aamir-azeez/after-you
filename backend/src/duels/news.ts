import { flags, type ServerVars } from "../flags";
import { hintPlayers, type LiveHint } from "../live";
import { duelsOn } from "./turn-hook";

/**
 * Duel hints over the live socket (live.ts), so an open duel screen reads only
 * when something it shows has moved, instead of polling.
 *
 * - The board (leaderboards/board.ts) announces the changes it makes to a duel
 *   it holds: an answer, a room claimed (that side only), a finish, a leave, a
 *   check result, an expiry or an end (model.ts milestone). A mid-run turn
 *   announces nothing.
 * - The routes (routes.ts) announce a new duel once every player's pointer to
 *   it exists, and party changes, to the players whose rows changed.
 *
 * Each recipient costs one Player RPC, which writes nothing and sends only to
 * an open socket of the current device. Best effort: a lost hint is caught by
 * the phone's slower backup read or its catch-up read when the socket comes back.
 * Off (DUELS, LEADERBOARDS or LIVE_CONNECTION) means no call at all.
 */
export type DuelNews = { duel_id: string; at: number; recipients: string[] };

/** Duel hints go out, and phones are told so in every duel read (hintsField), only while duels and the live socket are both on. */
export function duelHintsOn(env: ServerVars): boolean { return duelsOn(env) && flags.liveConnection(env); }

/**
 * Board side: one hint per duel to each of its recipients, so a phone with that duel open reads it
 * (several duels at once, as a verdict batch, is rare; the phone reads its lobby once for them all).
 */
export function announceDuelNews(env: ServerVars & Pick<Env, "PLAYERS">, news: readonly DuelNews[]): Promise<unknown> {
  if (!news.length || !duelHintsOn(env)) return Promise.resolve();
  return Promise.all(news.map(item => hintPlayers(env, item.recipients, { kind: "duels", duel_id: item.duel_id, at: item.at })));
}

/** Beside every duel read the phone paces itself by: while true, duel changes come as hints, so it may read at its backup pace. */
export function hintsField(env: ServerVars): { duel_hints_version?: number } {
  return duelHintsOn(env) ? { duel_hints_version: 1 } : {};
}

/** Route side: the players whose lobby changed, told after the change is stored. `duel`: the one new duel, when that is the change. */
export function announceLobby(env: ServerVars & Pick<Env, "PLAYERS">, recipients: readonly (string | null | undefined)[], at: number, duel: string | null = null): Promise<unknown> {
  const ids = recipients.filter((id): id is string => typeof id === "string");
  if (!ids.length || !duelHintsOn(env)) return Promise.resolve();
  const hint: LiveHint = { kind: "duels", duel_id: duel, at };
  return hintPlayers(env, ids, hint);
}
