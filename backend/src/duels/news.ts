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

/** Duel hints go out, and phones are told so (duelsCapability), only while duels and the live socket are both on. */
export function duelHintsOn(env: ServerVars): boolean { return duelsOn(env) && flags.liveConnection(env); }

/** Board side: one hint per recipient. A player told of more than one duel at once gets one hint naming none, so their lobby reads once. */
export function announceDuelNews(env: ServerVars & Pick<Env, "PLAYERS">, news: readonly DuelNews[]): Promise<unknown> {
  if (!news.length || !duelHintsOn(env)) return Promise.resolve();
  const byPlayer = new Map<string, DuelNews[]>();
  for (const item of news) for (const id of item.recipients) byPlayer.set(id, [...(byPlayer.get(id) ?? []), item]);
  return Promise.all([...byPlayer].map(([id, items]) => hintPlayers(env, [id], items.length === 1
    ? { kind: "duels", duel_id: items[0].duel_id, at: items[0].at }
    : { kind: "duels", duel_id: null, at: Math.max(...items.map(item => item.at)) })));
}

/** Route side: the players whose lobby changed, told after the change is stored. `duel`: the one new duel, when that is the change. */
export function announceLobby(env: ServerVars & Pick<Env, "PLAYERS">, recipients: readonly (string | null | undefined)[], at: number, duel: string | null = null): Promise<unknown> {
  const ids = recipients.filter((id): id is string => typeof id === "string");
  if (!ids.length || !duelHintsOn(env)) return Promise.resolve();
  const hint: LiveHint = { kind: "duels", duel_id: duel, at };
  return hintPlayers(env, ids, hint);
}
