import { withEnergy } from "./energy-charge";
import { clientReach } from "../app-status";
import type { Reach } from "../flags";
import { energyOn } from "../pollen/features";
import { ApiError, IDEMPOTENCY_PATTERN, ID_PATTERN, boundedJson, digest, isObject, ok, randomToken, unwrap, type Outcome } from "../protocol";
import { pooled } from "../room-inbox";
import { interactionBlocked } from "../safety";
import { duelPairKeys } from "../leaderboards/platform-rule";
import { samePair, type PairKeys } from "../leaderboards/pair-accounts";
import { boardKeys, knownBoard } from "../leaderboards/boards";
import { cachedView, storeView } from "../leaderboards/view-cache";
import { pollenEarning } from "../pollen/routes";
import { RATES } from "../pollen/rates";
import type { DuelRoomPay, DuelWin, DuelWinAnswer } from "../pollen/duel-pay";
import { CHAPTERS, creatable } from "../v2/chapters";
import { blankSide, isFinal, isOpen, knownKey, newFriendDuel, newGhostRace, sideOf, viewFor, type Duel, type DuelView, type Ghost, type ProgressNote, type Side, type SideRoom } from "./model";
import type { DuelAction, FinishProof } from "./store";
import { mutual, type DuelRef, type PartyOp, type PartyState } from "./party";
import type { MemberState } from "../leaderboards/member";
import { CHALLENGE_TTL_MS, PARTY_ACTIONS, MAX_FRIEND_DUELS_PER_PAIR, MAX_GHOST_RACES_PER_PAIR, MAX_RECENT_DUELS, RESULT_SHOWN_MS } from "./rules";
import { duelsOn, roomNote } from "./turn-hook";
import type { DuelLink } from "./room-link";
import { THEIR_RUN_KEEP_MS } from "./their-run";
import { developerGhost, developerGhostSplits } from "./developer-ghosts";
import { announceLobby, hintsField } from "./news";
import { blobBase64 } from "../blob-codec";
import { looksOn } from "../pollen/features";
import { flags } from "../flags";
import type { Look } from "../pollen/catalog";
import { servedLook } from "../leaderboards/run-looks";
import { publicDetail, publicDuelsCapability, publicDuelsOn, publicLobby, routePublicDuels, settlePublic, type PublicSettle } from "./public-routes";
import { lastingAnswer, receiptOf, type PayoutShown } from "./payout-receipt";

/**
 * The phone's duel routes, all absent (falling through to 404) unless duels
 * are on (turn-hook.ts duelsOn), after auth():
 * - GET  /v1/duels: the lobby. The party, invites, and every duel this player
 *   is in, read from the boards their pointers name (one request per board).
 *   It also pays a won friend duel's win bonus, or a first win over the
 *   developers' ghost, the first time it sees one.
 * - GET  /v1/duels/ghosts: each chapter's recorded times to race, from the
 *   board views (cached, so usually no request) and the developers' ghosts.
 * - POST /v1/duels/party/{invite,accept,dismiss,cancel,leave}
 * - POST /v1/duels/challenge, POST /v1/duels/ghost
 * - GET  /v1/duels/<board>/<duel_id>: one duel, with what it paid this player.
 * - POST /v1/duels/<board>/<duel_id>/{accept,decline,leave,sync}
 * A duel's rooms are made through POST /v2/rooms with a `duel` field
 * (prepareDuelRoom below), so every room rule still applies there.
 * While looks are on (POLLEN_LOOKS), every duel view carries each side's looks
 * (model.ts), and the lobby the partner's (party.partner_look), all from rows
 * these calls already read: no request is added for a look.
 */
export const DUELS_PREFIX = "/v1/duels";
export const DUELS_HEADER = "X-AfterYou-Duels";
const PUBLIC_PREFIX = "/v1/duels/public";
const BOARD = "([a-z0-9-]{1,48}@[1-9][0-9]{0,3})", DUEL_ID = "([a-f0-9]{32})";
const DUEL_PATH = new RegExp(`^/v1/duels/${BOARD}/${DUEL_ID}(?:/(accept|decline|leave|sync|their-run|their-run/ack))?$`);
const PARTY_PATH = new RegExp(`^/v1/duels/party/(${PARTY_ACTIONS.join("|")})$`);
const BOARD_CONCURRENCY = 4;
const GHOSTS_SHOWN = 3;

/**
 * `duels_version: 1` on /v2/capabilities for a phone that asks while duels are on, and `race_ghost_version: 1` with it
 * while RACE_GHOST is on (flags.ts): the phone then plays a ghost race's raced run beside each turn, from the run's
 * replay_hash on the race (model.ts Ghost) and the board's replay route. No request or row is added by the flag.
 */
export function duelsCapability(request: Request, env: Env): { duels_version?: number; race_ghost_version?: number; public_duels_version?: number } {
  if (!duelsOn(env) || request.headers.get(DUELS_HEADER) !== "1") return {};
  // Public duels ride the same header (public-routes.ts publicDuelsCapability).
  return { duels_version: 1, ...(flags.raceGhost(env) ? { race_ghost_version: 1 } : {}), ...publicDuelsCapability(request, env, DUELS_HEADER), ...(energyOn(env, clientReach(request)) ? { duels_energy_version: 1 } : {}) };
}

export function fields(input: unknown, keys: string[]): Record<string, unknown> {
  if (!isObject(input) || input.schema_version !== 1 || Object.keys(input).length !== keys.length + 1 || !keys.every(key => Object.hasOwn(input, key))) throw new ApiError(400, "invalid_duel_request");
  return input;
}
export function playerId(value: unknown): string {
  if (typeof value !== "string" || !ID_PATTERN.test(value)) throw new ApiError(400, "invalid_duel_request");
  return value;
}
export function boardOf(value: unknown): string {
  const board = knownBoard(value);
  if (!board) throw new ApiError(400, "invalid_duel_request");
  return board;
}
/** The chapter row a board key names. */
export function chapterRow(board: string) {
  const row = CHAPTERS.find(item => `${item.adapter.key.level_id}@${item.adapter.key.level_version}` === board);
  if (!row) throw new ApiError(400, "invalid_duel_request");
  return row;
}
export const party = (env: Env, id: string) => env.LEADERBOARD_MEMBERS.getByName(id);
const board = (env: Env, key: string) => env.LEADERBOARD_BOARDS.getByName(key);
/**
 * The board's duel calls, typed as the model's own shapes: RPC answers come back as plain
 * structured clones, which TypeScript sees with tuples widened to arrays.
 */
export function duelsAt(env: Env, key: string) {
  const stub = board(env, key);
  return {
    /** `reader`: whose read this is; a duel it settles (an expiry, a stall) is news to the others only. */
    read: async (ids: string[], reader?: string) => (await stub.duelRead(ids, reader)) as unknown as Duel[],
    create: async (duel: Duel) => (await stub.duelCreate(duel)) as unknown as Duel | null,
    act: async (id: string, action: DuelAction) => (await stub.duelAct(id, action)) as unknown as Outcome<{ duel: Duel; room?: SideRoom }>,
    progress: async (id: string, note: ProgressNote, proof?: FinishProof, actor?: string) => (await stub.duelProgress(id, note, proof, actor)) as unknown as Outcome<Duel>,
    /** A player's label or list pause on the public duels named (duels/public-routes.ts). */
    publicPlayer: (player: string, ids: string[], change: { label?: string | null; hidden?: boolean }) => stub.duelPublicPlayer(player, ids, change),
    /** Keeps a final duel's pay as `player`'s read showed it (payout-receipt.ts). */
    receipt: (id: string, player: string, shown: PayoutShown) => stub.duelReceipt(id, player, shown)
  };
}

/** Friends both ways and neither blocking the other. Requests: 2 Players and the block check. */
async function friends(env: Env, a: string, b: string): Promise<boolean> {
  if (a === b) return false;
  const [one, two] = await Promise.all([env.PLAYERS.getByName(a).friendEdge(a, b), env.PLAYERS.getByName(b).friendEdge(b, a)]);
  return Boolean(one?.link.accepted && two?.link.accepted) && !await interactionBlocked(env, a, b);
}

/**
 * A player's party, with whether it counts (both name each other) and both members' looks as their rows keep
 * them (party.ts `look`), the player's first. `look`: the caller's own look from auth(), kept in their row when it
 * changed. Requests: 1, or 2 with a partner.
 */
async function pairOf(env: Env, player: string, now: number, look?: Look): Promise<{ state: PartyState; partner: string | null; intact: boolean; looks: [Look | undefined, Look | undefined]; members?: (MemberState | null)[] }> {
  // While public duels are on, the same request also brings each player's settings (their switch, pause): no request added.
  const open = publicDuelsOn(env);
  const read = async (id: string, worn?: Look): Promise<{ party: PartyState; member: MemberState | null }> =>
    open ? (await party(env, id).publicRead(now, worn)) as unknown as { party: PartyState; member: MemberState } : { party: await party(env, id).partyRead(now, worn), member: null };
  const mine = await read(player, look), state = mine.party;
  if (!state.partner) return { state, partner: null, intact: false, looks: [state.look, undefined], ...(open ? { members: [mine.member, null] } : {}) };
  const theirs = await read(state.partner);
  return { state, partner: state.partner, intact: mutual(player, state, state.partner, theirs.party), looks: [state.look, theirs.party.look], ...(open ? { members: [mine.member, theirs.member] } : {}) };
}

/** The duels `player`'s pointers name, settled now, read one request per board. */
export async function duelsOf(env: Env, refs: readonly DuelRef[], player: string): Promise<{ duels: Duel[]; missing: string[] }> {
  const byBoard = new Map<string, string[]>();
  for (const ref of refs) byBoard.set(ref.board, [...(byBoard.get(ref.board) ?? []), ref.duel_id]);
  const lists = await pooled([...byBoard], BOARD_CONCURRENCY, async ([key, ids]) => duelsAt(env, key).read(ids, player));
  const duels = lists.flat() as Duel[];
  const found = new Set(duels.map(duel => duel.duel_id));
  return { duels, missing: refs.map(ref => ref.duel_id).filter(id => !found.has(id)) };
}

/** `read`: the duels the caller just read; those already over lose their pointers first when a list is full (party.ts add_duels). */
export async function addRefs(env: Env, players: readonly string[], ref: DuelRef, now: number, read: readonly Duel[] = []): Promise<void> {
  const final = read.filter(isFinal).map(duel => duel.duel_id);
  await pooled([...new Set(players)], BOARD_CONCURRENCY, async id => { await party(env, id).partyApply(id, { kind: "add_duels", refs: [ref], ...(final.length ? { final } : {}) }, now); });
}

/** Open public duels among `duels` holding any of `players`: they share the friend duels' limit of 10. */
function openPublicWith(duels: readonly Duel[], players: readonly string[]): number {
  return duels.filter(duel => duel.public && isOpen(duel) && duel.sides.some(side => side?.members.some(id => id !== null && players.includes(id)))).length;
}

/** Open friend duels (or ghost races still being played: a finished run waiting for its check holds no slot) of the pair `keys` (pair-accounts.ts samePair) among `duels`. */
function openFor(duels: readonly Duel[], keys: PairKeys, kind: Duel["kind"]): number {
  return duels.filter(duel => duel.kind === kind && isOpen(duel) && (kind === "friend" || duel.sides[0].finished_ms === null) && duel.sides.some(side => side !== null && samePair(side, keys))).length;
}

/**
 * The win against `other` for the wallet's weekly cap on the same opposing pair: its account key when it has one
 * (leaderboards/pair-accounts.ts), with its id key beside it so a line written before the platform rule still counts.
 */
function opponentWin(duel: Duel, other: Side, decidedMs: number): DuelWin {
  const base = { duel_id: duel.duel_id, opponent: other.account_key ?? other.pair_key, decided_ms: decidedMs };
  return other.account_key === undefined ? base : { ...base, opponent_pair: other.pair_key };
}

/**
 * `answer`: null when nothing is due or the wallet could not be asked. `asked`: the wallet was asked. `final`: the answer
 * is one the wallet will give again, or nothing is due by the duel's own facts, so a read may keep it (payout-receipt.ts).
 */
type WinAsk = { answer: DuelWinAnswer | null; asked: boolean; final: boolean };
const NOTHING_DUE: WinAsk = { answer: null, asked: false, final: true };
/**
 * The bonus a decided duel owes `player`, once per player (pollen/duel-pay.ts): a won friend duel's
 * win bonus, or the first win over the developers' ghost on its board. No account rule (dropped 2026-10-31). Asked of the
 * wallet only while `settled` (the party row's, and the duels whose row keeps the player's receipt) does not name it.
 */
async function winBonus(env: Env, player: string, duel: Duel, settled: readonly string[], force = false): Promise<WinAsk> {
  // A public duel settles its win with its held extra (public-routes.ts settlePublic).
  if (duel.public) return NOTHING_DUE;
  const mine = sideOf(duel, player);
  // Only a win on time pays (POLLEN-RULES.md), its runs passed by the replay check while duel run checks are on (model.ts
  // awaitsCheck), as they finished while off: never one the other pair left or failed.
  if (!pollenEarning(env) || duel.status !== "decided" || duel.result?.winner !== mine || duel.result.reason !== "faster") return NOTHING_DUE;
  const friend = duel.kind === "friend";
  // A ghost race pays only against the developers' ghost, on a run the check passed or that counted without it while duel
  // run checks were off (model.ts Side.waived), never one decided before the bonus existed; a rate of 0 writes nothing.
  const run = duel.sides[0];
  const ghost = duel.kind === "ghost" && duel.ghost?.source === "developer" && (run.check === "passed" || run.waived === true) && RATES.duels.ghost_win_bonus > 0;
  if (!friend && !ghost) return NOTHING_DUE;
  if (!force && settled.includes(duel.duel_id)) return NOTHING_DUE;
  const wallet = env.PLAYERS.getByName(player);
  try {
    const answer = friend
      ? await wallet.creditDuelWin(player, opponentWin(duel, duel.sides[1 - mine]!, duel.result.decided_ms))
      : await wallet.creditGhostWin(player, { duel_id: duel.duel_id, board: duel.board });
    if (answer.ok) return { answer: answer.value, asked: true, final: true };
    // A final refusal (an old win, no identity) is settled too, so it is never asked again; a read keeps only the expiry.
    return { answer: answer.status < 500 ? { amount: 0, counted: false, balance: 0 } : null, asked: true, final: lastingAnswer(answer) };
  } catch { return { answer: null, asked: true, final: false }; }
}

/**
 * The lobby. Requests: 1 (own party) + 1 (partner, when named) + 1 per board holding a duel + a wallet credit per new win + 1 write when pointers change.
 * While looks are on, `party.partner_look` is the partner's look from the row already read ({} for the default).
 */
async function lobby(env: Env, player: string, now: number, look?: Look): Promise<unknown> {
  const pair = await pairOf(env, player, now, look);
  const shownLooks = looksOn(env);
  const { duels, missing } = await duelsOf(env, pair.state.duels, player);
  // A result shown long enough goes, and so does a public duel whose seat this player gave back (public.ts).
  const stale = duels.filter(duel => isFinal(duel) && now - (duel.result?.decided_ms ?? duel.updated_ms) >= RESULT_SHOWN_MS || sideOf(duel, player) < 0).map(duel => duel.duel_id);
  const shown = duels.filter(duel => !stale.includes(duel.duel_id));
  const settled: string[] = [];
  // Every won duel is paid before its pointer goes, so a winner who stays away a while still gets it; a public duel's
  // held extra too, for every player of it, once. A duel whose row keeps this player's receipt was paid by a read.
  const paid = [...pair.state.settled, ...duels.filter(duel => receiptOf(duel, player)).map(duel => duel.duel_id)];
  for (const duel of duels) if (duel.public ? await settlePublic(env, player, duel, paid) : (await winBonus(env, player, duel, paid)).answer) settled.push(duel.duel_id);
  const ops: PartyOp[] = [];
  if (missing.length || stale.length) ops.push({ kind: "drop_duels", ids: [...missing, ...stale] });
  if (settled.length) ops.push({ kind: "settle_wins", ids: settled });
  for (const op of ops) await party(env, player).partyApply(player, op, now);
  return {
    schema_version: 1,
    party: { partner: pair.partner, intact: pair.intact, invites_in: pair.state.invites_in.map(invite => invite.from), invite_out: pair.state.invite_out?.to ?? null,
      ...(shownLooks && pair.partner ? { partner_look: servedLook(pair.looks[1]) } : {}) },
    duels: shown.map(duel => viewFor(duel, player, shownLooks)).filter((view): view is DuelView => view !== null).sort((a, b) => b.updated_ms - a.updated_ms),
    limits: { friend: MAX_FRIEND_DUELS_PER_PAIR, ghost: MAX_GHOST_RACES_PER_PAIR },
    ...hintsField(env), ...publicLobby(env, player, pair.members, pair.intact, duels)
  };
}

/** Each board's times to race: its top runs from the view (cached when it can be) and the developers' ghost. */
async function ghosts(env: Env): Promise<unknown> {
  const boards = await pooled([...boardKeys()], BOARD_CONCURRENCY, async key => {
    let view = await cachedView(key);
    if (!view) { view = await board(env, key).view(key); await storeView(view); }
    return { board: key, developer: developerGhost(key), top: view.top.slice(0, GHOSTS_SHOWN).map(row => ({ rank: row.rank, entry_id: row.entry_id, ticks: row.ticks, names: row.names })) };
  });
  return { schema_version: 1, boards };
}

/**
 * A party op, answered with the lobby. Every other player whose row it changed (an invite arrived or
 * was taken back, an invite was accepted, a partner left) is told once it is stored (news.ts).
 */
async function partyRoute(env: Env, action: string, player: string, input: unknown, now: number, look?: Look): Promise<unknown> {
  const told: string[] = [];
  const apply = async (id: string, op: PartyOp) => unwrap(await party(env, id).partyApply(id, op, now));
  // Leaving the old party when a new one forms: the old partner stops naming this player.
  const release = async (previous: string | null, from: string) => {
    if (!previous || previous === from) return;
    await party(env, previous).partyApply(previous, { kind: "unpartner", partner: from }, now);
    told.push(previous);
  };
  // A friend whose row changed is told even when a later step fails: the backup read heals the rest.
  try {
    if (action === "invite") {
      const friend = playerId(fields(input, ["friend"]).friend);
      if (!await friends(env, player, friend)) throw new ApiError(403, "party_friends_only");
      await apply(friend, { kind: "invited", from: player });
      told.push(friend);
      await apply(player, { kind: "invite", to: friend });
    } else if (action === "accept") {
      const from = playerId(fields(input, ["from"]).from);
      if (!await friends(env, player, from)) throw new ApiError(403, "party_friends_only");
      // The inviter's own row first: their invite must still stand.
      const confirmed = await party(env, from).partyApply(from, { kind: "confirm", partner: player }, now);
      if (!confirmed.ok) { await party(env, player).partyApply(player, { kind: "dismiss", from }, now); throw new ApiError(confirmed.status, confirmed.code); }
      told.push(from);
      await release(confirmed.value.previous, from);
      const accepted = await apply(player, { kind: "accept", from });
      await release(accepted.previous, player);
    } else if (action === "dismiss") {
      await apply(player, { kind: "dismiss", from: playerId(fields(input, ["from"]).from) });
    } else if (action === "cancel") {
      fields(input, []);
      const state = await party(env, player).partyRead(now);
      if (state.invite_out) { await party(env, state.invite_out.to).partyApply(state.invite_out.to, { kind: "dismiss", from: player }, now); told.push(state.invite_out.to); }
      await apply(player, { kind: "cancel" });
    } else {
      fields(input, []);
      const left = await apply(player, { kind: "leave" });
      await release(left.previous, player);
    }
  } finally {
    await announceLobby(env, told.filter(id => id !== player), now);
  }
  return lobby(env, player, now, look);
}

/** Every pair of players across the two pairs who are friends: they see each other's ids. Requests: 2 per pair checked. */
async function knownAcross(env: Env, a: readonly string[], b: readonly string[]): Promise<string[]> {
  const pairs = a.flatMap(x => b.map(y => [x, y] as const));
  const found = await pooled(pairs, BOARD_CONCURRENCY, async ([x, y]) => await friends(env, x, y) ? knownKey(x, y) : null);
  return found.filter((key): key is string => key !== null);
}

async function challenge(env: Env, reach: Reach, player: string, input: unknown, now: number, look?: Look): Promise<unknown> {
  const shownLooks = looksOn(env);
  const body = fields(input, ["idempotency_key", "friend", "board"]);
  if (typeof body.idempotency_key !== "string" || !IDEMPOTENCY_PATTERN.test(body.idempotency_key)) throw new ApiError(400, "invalid_duel_request");
  const friend = playerId(body.friend), key = boardOf(body.board), row = chapterRow(key);
  if (!creatable(row.adapter, env)) throw new ApiError(503, "chapter_creation_disabled");
  const duelId = (await digest(`after-you duel v1\n${player}\n${body.idempotency_key}`)).slice(0, 32);
  // Friends first, so nobody can ask about a stranger's party.
  if (!await friends(env, player, friend)) throw new ApiError(403, "duel_friends_only");
  const mine = await pairOf(env, player, now, look);
  // A retried challenge answers the duel it made.
  const held = mine.state.duels.find(ref => ref.duel_id === duelId);
  if (held) { const [duel] = await duelsAt(env, held.board).read([duelId], player); if (duel) return { schema_version: 1, duel: viewFor(duel, player, shownLooks) }; }
  if (!mine.intact || !mine.partner) throw new ApiError(409, "party_required");
  const theirs = await pairOf(env, friend, now);
  if (!theirs.intact || !theirs.partner) throw new ApiError(409, "opponent_party_required");
  const a = [player, mine.partner] as [string, string], b = [friend, theirs.partner] as [string, string];
  if (a.some(id => b.includes(id))) throw new ApiError(409, "same_party");
  // A pair already holding many recent duels takes no more, so its open ones never drop off its list.
  if (theirs.state.duels.filter(ref => now - ref.at < CHALLENGE_TTL_MS).length >= MAX_RECENT_DUELS) throw new ApiError(409, "opponent_busy");
  // While the platform rule is on a pair is also its two platform accounts (leaderboards/pair-accounts.ts).
  const [aKeys, bKeys] = await duelPairKeys(env, [a, b]);
  const { duels } = await duelsOf(env, mine.state.duels, player);
  // One limit of 10, friend and public together (rules.ts): the pair's friend duels and the public duels either of them is in.
  if (openFor(duels, aKeys, "friend") + openPublicWith(duels, a) >= MAX_FRIEND_DUELS_PER_PAIR) throw new ApiError(409, "duel_limit_reached");
  if (duels.some(duel => duel.kind === "friend" && isOpen(duel) && duel.board === key && duel.sides.some(side => side !== null && samePair(side, bKeys)))) throw new ApiError(409, "duel_already_open");
  const known = await knownAcross(env, a, b);
  // Each side starts in the looks its members' party rows keep (read above); turns bring their room's looks.
  // Each of the starting pair pays 1 energy while ENERGY is on, given back if the board refuses (energy-charge.ts). The board
  // is asked only inside, after the charge: an RPC starts when it is called, so it must not be called before.
  const { value: made, energy } = await withEnergy(env, reach, player, a, duelId, async () => {
    const made = await duelsAt(env, key).create(newFriendDuel({ duel_id: duelId, board: key, chapter: { ...row.adapter.key }, steps: row.adapter.stages.length * 2, starter: player,
      a: blankSide(a, aKeys.pair_key, shownLooks ? mine.looks : undefined, aKeys.account_key), b: blankSide(b, bKeys.pair_key, shownLooks ? theirs.looks : undefined, bKeys.account_key), known }, now));
    if (!made) throw new ApiError(503, "duels_busy");
    return made;
  });
  await addRefs(env, [...a, ...b], { duel_id: duelId, board: key, at: now }, now, duels);
  // Only now does every lobby list it.
  await announceLobby(env, [...a, ...b].filter(id => id !== player), made.updated_ms, duelId);
  return { schema_version: 1, duel: viewFor(made, player, shownLooks), ...(energy ? { energy } : {}) };
}

async function ghostRace(env: Env, reach: Reach, player: string, input: unknown, now: number, look?: Look): Promise<unknown> {
  const shownLooks = looksOn(env);
  const body = fields(input, ["idempotency_key", "board", "source", "entry_id"]);
  if (typeof body.idempotency_key !== "string" || !IDEMPOTENCY_PATTERN.test(body.idempotency_key) || (body.source !== "board" && body.source !== "developer")) throw new ApiError(400, "invalid_duel_request");
  const key = boardOf(body.board), row = chapterRow(key);
  if (!creatable(row.adapter, env)) throw new ApiError(503, "chapter_creation_disabled");
  const duelId = (await digest(`after-you ghost v1\n${player}\n${body.idempotency_key}`)).slice(0, 32);
  const mine = await pairOf(env, player, now, look);
  const held = mine.state.duels.find(ref => ref.duel_id === duelId);
  if (held) { const [duel] = await duelsAt(env, held.board).read([duelId], player); if (duel) return { schema_version: 1, duel: viewFor(duel, player, shownLooks) }; }
  if (!mine.intact || !mine.partner) throw new ApiError(409, "party_required");
  let ghost: Ghost;
  if (body.source === "developer") {
    const ticks = developerGhost(key);
    if (ticks === null || body.entry_id !== null) throw new ApiError(404, "ghost_not_found");
    // Its time after each turn, so a phone can set it beside the pair's after the same number of turns.
    const splits = developerGhostSplits(key);
    ghost = { source: "developer", entry_id: null, rank: null, ticks, names: null, ...(splits && splits.length === row.adapter.stages.length * 2 ? { splits } : {}) };
  } else {
    if (typeof body.entry_id !== "string" || !/^[a-f0-9]{32}$/.test(body.entry_id)) throw new ApiError(400, "invalid_duel_request");
    let view = await cachedView(key);
    if (!view) { view = await board(env, key).view(key); await storeView(view); }
    const top = view.top.find(item => item.entry_id === body.entry_id);
    if (!top) throw new ApiError(404, "ghost_not_found");
    // Names stay on the board, where erasure reaches them; the race keeps only the place, the time and, while looks are on,
    // the pair's cosmetic looks as the row showed them (no ids, so nobody's account is named by them).
    // The run's replay_hash too, so a phone can play the raced run beside each turn (the race ghost): the same hash the
    // board row already shows anyone, naming no account. Kept whatever RACE_GHOST says; older code reads it as extra.
    ghost = { source: "board", entry_id: top.entry_id, rank: top.rank, ticks: top.ticks, names: null, ...(top.replay_hash ? { replay_hash: top.replay_hash } : {}), ...(shownLooks && top.looks ? { looks: top.looks } : {}) };
  }
  const a = [player, mine.partner] as [string, string], [aKeys] = await duelPairKeys(env, [a]);
  const { duels } = await duelsOf(env, mine.state.duels, player);
  if (openFor(duels, aKeys, "ghost") >= MAX_GHOST_RACES_PER_PAIR) throw new ApiError(409, "duel_limit_reached");
  const { value: made, energy } = await withEnergy(env, reach, player, a, duelId, async () => {
    const made = await duelsAt(env, key).create(newGhostRace({ duel_id: duelId, board: key, chapter: { ...row.adapter.key }, steps: row.adapter.stages.length * 2, starter: player,
      a: blankSide(a, aKeys.pair_key, shownLooks ? mine.looks : undefined, aKeys.account_key), ghost }, now));
    if (!made) throw new ApiError(503, "duels_busy");
    return made;
  });
  await addRefs(env, a, { duel_id: duelId, board: key, at: now }, now, duels);
  await announceLobby(env, [mine.partner], made.updated_ms, duelId);
  return { schema_version: 1, duel: viewFor(made, player, shownLooks), ...(energy ? { energy } : {}) };
}

async function duelAction(env: Env, reach: Reach, player: string, key: string, duelId: string, action: string | undefined, input: unknown, now: number): Promise<unknown> {
  const shownLooks = looksOn(env);
  const [duel] = await duelsAt(env, key).read([duelId], player);
  const mine = duel ? sideOf(duel, player) : -1;
  if (!duel || mine < 0) throw new ApiError(404, "duel_not_found");
  if (action === undefined) return duelDetail(env, player, duel);
  fields(input, []);
  if (action === "accept") {
    const partner = duel.sides[1]!.members.find(id => id !== player) ?? null;
    let intact = false;
    if (partner && duel.status === "challenged") {
      const pair = await pairOf(env, player, now);
      intact = pair.intact && pair.partner === partner;
      if (intact) {
        const { duels } = await duelsOf(env, pair.state.duels.filter(ref => ref.duel_id !== duelId), player);
        if (duels.filter(item => item.kind === "friend" && item.status === "running" && item.sides.some(side => side !== null && samePair(side, duel.sides[1]!))).length + openPublicWith(duels, [player, partner]) >= MAX_FRIEND_DUELS_PER_PAIR) throw new ApiError(409, "duel_limit_reached");
      }
    }
    // The accepting pair pays 1 energy each; a refused accept gives it back (energy-charge.ts).
    const payers = duel.status === "challenged" ? duel.sides[1]!.members.filter((id): id is string => typeof id === "string") : [];
    const { value: answer, energy } = payers.length ? await withEnergy(env, reach, player, payers, duelId, async () => unwrap(await duelsAt(env, key).act(duelId, { kind: "accept", player, intact })))
      : { value: unwrap(await duelsAt(env, key).act(duelId, { kind: "accept", player, intact })), energy: null };
    return { schema_version: 1, duel: viewFor(answer.duel, player, shownLooks), ...(energy ? { energy } : {}) };
  }
  if (action === "decline" || action === "leave") {
    const answer = unwrap(await duelsAt(env, key).act(duelId, { kind: action, player }));
    // A public seat left before entering goes back on the list: the leaver is no longer in the duel (public.ts).
    const view = viewFor(answer.duel, player, shownLooks);
    return view ? { schema_version: 1, duel: view } : { schema_version: 1, duel: null, left: true };
  }
  // sync: the phone saw its room ahead of the duel; note the room as it is now.
  const room = duel.sides[mine as 0 | 1]!.room;
  if (room && duel.status === "running") {
    const snapshot = await env.ROOMS_V2.getByName(room.room_id).snapshot(player);
    const link = snapshot.ok ? await env.ROOMS_V2.getByName(room.room_id).duelLinkOf() : null;
    if (snapshot.ok && link?.duel_id === duelId) {
      const made = await roomNote(snapshot.value, link);
      if (made) { const noted = await duelsAt(env, key).progress(duelId, made.note, made.proof, player); if (noted.ok) return { schema_version: 1, duel: viewFor(noted.value, player, shownLooks) }; }
    }
  }
  return { schema_version: 1, duel: viewFor(duel, player, shownLooks) };
}

/**
 * One duel, with this player's pay from it once it is over: `win_bonus` on a friend duel, `ghost_bonus`
 * on the ghost race that paid the first win over the developers' ghost on its board, and nothing on a
 * later win there. Requests: the board read, plus 1 or 2 on the player's own wallet when over, and the
 * board's write of the receipt (payout-receipt.ts) once what they show can no longer change; a read after
 * that answers from the receipt the board read brought, so it is the sign-in and the board read only.
 */
async function duelDetail(env: Env, player: string, duel: Duel): Promise<unknown> {
  const view = viewFor(duel, player, looksOn(env))!;
  const earning = isFinal(duel) && pollenEarning(env);
  const kept = earning ? receiptOf(duel, player) : null;
  if (kept) return { schema_version: 1, duel: view, ...kept, ...hintsField(env) };
  const side = duel.sides[sideOf(duel, player) as 0 | 1]!, room = side.room;
  let pay: DuelRoomPay | undefined, bonus: DuelWinAnswer | null = null, settledNow: PublicSettle | null = null, asked = false, final = false;
  if (earning) {
    if (room) pay = await env.PLAYERS.getByName(player).duelRoomPay(room.room_id);
    if (duel.public) { settledNow = await settlePublic(env, player, duel, [], true); bonus = settledNow?.win ?? null; asked = true; final = settledNow?.final ?? false; }
    else ({ answer: bonus, asked, final } = await winBonus(env, player, duel, [], true));
  }
  const won = bonus ? { amount: bonus.amount, counted: bonus.counted, ...(bonus.reason ? { reason: bonus.reason } : {}) } : null;
  const shown: PayoutShown = { ...(pay ? { pay } : {}), ...(won && duel.kind === "friend" ? { win_bonus: won } : {}), ...(won?.counted && duel.kind === "ghost" ? { ghost_bonus: won } : {}),
    ...await publicDetail(env, player, duel, settledNow) };
  // Kept once nothing shown can change and a later read would ask something again. A side whose room never finished its
  // run keeps none: that room may still take turns that hold or pay. A lost write only means the next read asks again.
  if (earning && final && (room ? side.finished_ms !== null : asked)) {
    try { await duelsAt(env, duel.board).receipt(duel.duel_id, player, shown); } catch { /* asked again next read */ }
  }
  return { schema_version: 1, duel: view, ...shown, ...hintsField(env) };
}

/**
 * The signed-in routes under /v1/duels; null for any other path or while duels are off. `look`: the caller's
 * look from auth() while looks are on (pollen/looks-routes.ts looksDuelRoute), undefined otherwise. `safetyToken`: the
 * caller's, which auth() gives the public list read (public-routes.ts publicListRoute).
 */
export async function routeDuels(request: Request, path: string, player: string, env: Env, look?: Look, safetyToken?: string): Promise<unknown | null> {
  if ((path !== DUELS_PREFIX && !path.startsWith(DUELS_PREFIX + "/")) || !duelsOn(env)) return null;
  const now = Date.now();
  // PUT is only the public duels switch.
  if (request.method === "PUT" && path.startsWith(PUBLIC_PREFIX) && publicDuelsOn(env)) return routePublicDuels(request, path, player, env, now, await boundedJson(request, 1024), look);
  if (request.method === "GET") {
    if (path === DUELS_PREFIX) return lobby(env, player, now, look);
    if (path === DUELS_PREFIX + "/ghosts") return ghosts(env);
    if (path.startsWith(PUBLIC_PREFIX) && publicDuelsOn(env)) { const answer = await routePublicDuels(request, path, player, env, now, null, look, safetyToken); if (answer !== null) return answer; }
    const match = DUEL_PATH.exec(path);
    if (match && !match[3]) return duelAction(env, clientReach(request), player, boardOf(match[1]), match[2], undefined, null, now);
    if (match?.[3] === "their-run") return theirRun(env, player, boardOf(match[1]), match[2], now);
    throw new ApiError(404, "not_found");
  }
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const input = await boundedJson(request, 2048);
  // Public duels (public-routes.ts), absent while PUBLIC_DUELS is off.
  if (path.startsWith(PUBLIC_PREFIX) && publicDuelsOn(env)) { const answer = await routePublicDuels(request, path, player, env, now, input, look); if (answer !== null) return answer; }
  const partyMatch = PARTY_PATH.exec(path);
  if (partyMatch) return partyRoute(env, partyMatch[1], player, input, now, look);
  if (path === DUELS_PREFIX + "/challenge") return challenge(env, clientReach(request), player, input, now, look);
  if (path === DUELS_PREFIX + "/ghost") return ghostRace(env, clientReach(request), player, input, now, look);
  const match = DUEL_PATH.exec(path);
  if (match?.[3] === "their-run/ack") return acknowledgeRun(env, player, boardOf(match[1]), match[2], input);
  if (match?.[3] && match[3] !== "their-run") return duelAction(env, clientReach(request), player, boardOf(match[1]), match[2], match[3], input, now);
  throw new ApiError(404, "not_found");
}

/**
 * The other pair's side of a friend duel `player` is in, and that side's room, or a refusal: the duel
 * must be a friend duel and the other pair's run finished in its room (duels/their-run.ts).
 */
async function otherRun(env: Env, player: string, board: string, duelId: string): Promise<{ duel: Duel; mine: 0 | 1; room_id: string }> {
  const [duel] = await duelsAt(env, board).read([duelId], player);
  const mine = duel ? sideOf(duel, player) : -1;
  if (!duel || mine < 0) throw new ApiError(404, "duel_not_found");
  const other = duel.sides[1 - mine];
  if (duel.kind !== "friend" || !other?.room || other.finished_ms === null) throw new ApiError(404, "their_run_not_found");
  return { duel, mine: mine as 0 | 1, room_id: other.room.room_id };
}

/**
 * GET /v1/duels/<board>/<duel>/their-run: the other pair's run, from the room that played it, once the
 * duel is over for this pair (their own run finished or they left, or the duel settled) and until its
 * keep is over. The answer names the duel only: the final checkpoint holds no player or room id.
 * While looks are on it also carries `turn_looks`, each turn's look by recording hash from the same
 * room, which the phone keeps as for any replay (services/turn_looks.gd). Requests: 2 (the board, to
 * check and find the room; the room).
 */
async function theirRun(env: Env, player: string, board: string, duelId: string, now: number) {
  const { duel, mine, room_id } = await otherRun(env, player, board, duelId);
  const own = duel.sides[mine]!;
  if (!isFinal(duel) && own.finished_ms === null && !own.left) throw new ApiError(409, "their_run_not_yet");
  if (isFinal(duel) && (duel.result?.decided_ms ?? duel.updated_ms) + THEIR_RUN_KEEP_MS <= now) throw new ApiError(410, "their_run_gone");
  const run = unwrap(await env.ROOMS_V2.getByName(room_id).theirRun(player, now, looksOn(env)));
  return { schema_version: 1, duel_id: duel.duel_id, board, digest: run.digest, byte_length: run.byte_length, body: blobBase64(run.body), ...(run.turn_looks ? { turn_looks: run.turn_looks } : {}) };
}

/**
 * POST /v1/duels/<board>/<duel>/their-run/ack: this phone keeps the run named by `digest`. A repeat,
 * or one after the copy went, answers ok. Requests: 2 (the board; the room).
 */
async function acknowledgeRun(env: Env, player: string, board: string, duelId: string, input: unknown) {
  if (!isObject(input) || Object.keys(input).length !== 2 || input.schema_version !== 1 || typeof input.digest !== "string" || !/^[a-f0-9]{64}$/.test(input.digest)) throw new ApiError(400, "invalid_duel_request");
  const { room_id } = await otherRun(env, player, board, duelId);
  const answer = unwrap(await env.ROOMS_V2.getByName(room_id).acknowledgeTheirRun(player, input.digest));
  return { schema_version: 1, kept: answer.kept };
}

/** A create's `duel` field: which duel's room this is. */
export type DuelRoomAsk = { duel_id: string; board: string };
export function parseDuelAsk(value: unknown): DuelRoomAsk {
  if (!isObject(value) || Object.keys(value).length !== 2 || typeof value.duel_id !== "string" || !/^[a-f0-9]{32}$/.test(value.duel_id)) throw new ApiError(400, "invalid_duel_room");
  return { duel_id: value.duel_id, board: boardOf(value.board) };
}

/**
 * Before a duel room is reserved (v2/routes.ts create): the duel must be
 * running, the caller in it, and the chapter the duel's own. Answers the
 * link the room will keep.
 */
export async function prepareDuelRoom(env: Env, player: string, ask: DuelRoomAsk, key: { level_id: string; level_version: number; definition_hash: string }): Promise<DuelLink> {
  if (!duelsOn(env)) throw new ApiError(503, "duels_disabled");
  const [duel] = await duelsAt(env, ask.board).read([ask.duel_id], player);
  const side = duel ? sideOf(duel, player) : -1;
  if (!duel || side < 0) throw new ApiError(404, "duel_not_found");
  if (duel.status !== "running") throw new ApiError(409, "duel_not_running");
  const c = duel.chapter;
  if (c.level_id !== key.level_id || c.level_version !== key.level_version || c.definition_hash !== key.definition_hash) throw new ApiError(422, "duel_chapter_mismatch");
  const members = duel.sides[side as 0 | 1]!.members;
  if (!duel.public && members.some(id => id === null)) throw new ApiError(409, "duel_not_running");
  // A friend duel's room knows the other pair, who may watch its run once it is over (their-run.ts).
  const others = duel.kind === "friend" ? ((duel.sides[1 - side]?.members ?? []) as (string | null)[]).filter((id): id is string => id !== null) : [];
  // A public duel's room names only the player making it; whoever else takes a seat on the side is admitted by the board
  // when they join (public-rooms.ts). Its replies show stand-ins for the partner (public-mask.ts) until the room learns the
  // second player is someone the first knows.
  if (duel.public) return { schema_version: 1, duel_id: duel.duel_id, board: duel.board, kind: duel.kind, side: side as 0 | 1, members: [player], others, public: true, masks: [randomToken(16), randomToken(16)] };
  return { schema_version: 1, duel_id: duel.duel_id, board: duel.board, kind: duel.kind, side: side as 0 | 1, members: members as string[], ...(duel.kind === "friend" ? { others } : {}) };
}

/**
 * Claims the side's room for the room just reserved. Ok when this room is the
 * side's (made by this call or an earlier try of it); otherwise the side's
 * room is someone else's, which the caller should join instead.
 */
export async function claimDuelRoom(env: Env, player: string, link: DuelLink, roomId: string, invite: string): Promise<Outcome<true>> {
  const stub = duelsAt(env, link.board);
  let claim = await stub.act(link.duel_id, { kind: "claim", player, room_id: roomId, invite_code: invite, room_absent: false });
  if (!claim.ok) return claim;
  if (claim.value.room?.room_id === roomId) return ok(true);
  // A claim whose room never appeared may pass on after a while.
  const held = claim.value.room?.room_id;
  if (held && (await env.ROOMS_V2.getByName(held).duelLinkOf()) === null) {
    claim = await stub.act(link.duel_id, { kind: "claim", player, room_id: roomId, invite_code: invite, room_absent: true });
    if (!claim.ok) return claim;
    if (claim.value.room?.room_id === roomId) return ok(true);
  }
  return { ok: false, status: 409, code: "duel_room_taken" };
}
