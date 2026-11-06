import { ApiError, IDEMPOTENCY_PATTERN, boundedJson, canonicalJson, digest, isObject, randomToken, unwrap } from "../protocol";
import { flags, type ServerVars } from "../flags";
import { bearerDigest } from "../http";
import { shownName } from "../display-names";
import { pairKey } from "../leaderboards/run";
import { pooled } from "../room-inbox";
import { pollenEarning } from "../pollen/routes";
import { looksOn } from "../pollen/features";
import type { Look } from "../pollen/catalog";
import type { DuelExtraAnswer, DuelWinAnswer } from "../pollen/duel-pay";
import { publicDuelsChosen, publicOpenTo, type DuelBlock, type MemberState } from "../leaderboards/member";
import { creatable } from "../v2/chapters";
import { termsCovered, termsVersion } from "../public-policy";
import { SAFETY_REPORT_REASONS, ownBlocks, type SafetyReport } from "../safety";
import { DUEL_REQUEST_PREFIX, requestFriend } from "../friends-routes";
import { isFinal, isOpen, knownKey, viewFor, type Duel } from "./model";
import { lastingAnswer, type ShownHeld } from "./payout-receipt";
import { heldState, holder, listingOf, newPublicDuel, publicKnown, seatOf, seated, type JoinAs } from "./public";
import { boardOf, chapterRow, duelsAt, duelsOf, fields, party } from "./routes";
import { duelsOn } from "./turn-hook";
import { announceLobby } from "./news";
import { sendListings } from "./directory";
import { forgetListings, listings, page, type ListSort } from "./public-list";
import type { DuelRef, PartyState } from "./party";
import { MAX_FRIEND_DUELS_PER_PAIR } from "./rules";

/**
 * Public duels' routes (PLAN 2 to 8), all absent while PUBLIC_DUELS is off (publicDuelsOn), after auth():
 * - PUT  /v1/duels/public/me: the player's switch, {on}, on by default; turning on needs the current community rules
 *   accepted, and so does every post and join (joiners).
 * - GET  /v1/duels/public/list/<all|board>/<newest|almost_full>/<page>: the list, 20 a page, for this reader.
 * - POST /v1/duels/public: post a duel, alone or with the party.
 * - POST /v1/duels/public/<board>/<duel_id>/{join,block,report,friend}: take a spot; block, report or ask to be
 *   friends with the player in a seat. The seat is turned into an id here, on the server; no id reaches a phone.
 * And the lobby's `public` part (publicLobby), a public duel's settling at its end (settlePublic) and its held extra
 * on the duel page (publicDetail), which duels/routes.ts calls.
 *
 * Requests (Cloudflare Free plan, PLAN 11): a list page is auth + Member + SafetyProfile (none when this isolate read
 * the reader's own blocks under their current safety token in the last minute, safety.ts ownBlocks) + the directory
 * only when the list cache misses; a post or join adds one SafetyProfile per joiner (the rules and blocks, and a Member write
 * only when its copy of the rules was lost), the boards holding the player's duels (the limit of 10), the board's
 * create or claim, the pointer writes and the hints; the board sends the directory its new listing (1 request, 1 row).
 */
const PUBLIC_PREFIX = "/v1/duels/public";
const LIST_PATH = /^\/v1\/duels\/public\/list\/(all|[a-z0-9-]{1,48}@[1-9][0-9]{0,3})\/(newest|almost_full)\/([0-9]{1,3})$/;
const SEAT_PATH = /^\/v1\/duels\/public\/([a-z0-9-]{1,48}@[1-9][0-9]{0,3})\/([a-f0-9]{32})\/(join|block|report|friend)$/;

/** Public duels run while PUBLIC_DUELS is on beside duels. */
export function publicDuelsOn(env: ServerVars): boolean { return duelsOn(env) && flags.publicDuels(env); }
/** `public_duels_version: 1` on /v2/capabilities for a phone that asks for duels while public duels are on. */
export function publicDuelsCapability(request: Request, env: ServerVars, header: string): { public_duels_version?: number } {
  return publicDuelsOn(env) && request.headers.get(header) === "1" ? { public_duels_version: 1 } : {};
}

type Seated = { party: PartyState; member: MemberState };
const read = async (env: Env, id: string, now: number, look?: Look): Promise<Seated> => (await party(env, id).publicRead(now, look)) as unknown as Seated;

/** What a stranger sees of `player`: their shown name only while they chose to show it, else null ("A player"). One Player read when shown. */
async function labelOf(env: Env, player: string, member: MemberState): Promise<string | null> {
  if (!member.show_name) return null;
  try { return shownName(await env.PLAYERS.getByName(player).publicDisplayName(player)); } catch { return null; }
}

/** Open friend and public duels holding any of `players`: the one limit of 10 (rules.ts). Ghost races keep their own. */
function running(duels: readonly Duel[], players: readonly string[]): number {
  return duels.filter(duel => duel.kind === "friend" && isOpen(duel) && players.some(id => seatIn(duel, id))).length;
}
const seatIn = (duel: Duel, id: string) => duel.sides.some(side => side?.members.includes(id));

type Team = { players: string[]; rows: Seated[]; looks: (Look | undefined)[];
  /** Everyone the joiners blocked or who blocked them: their own block lists and the rows' `blocked_by`. */
  avoid: Set<string> };
/**
 * The player (and partner) as a post or join needs them: switch on (on unless turned off, leaderboards/member.ts
 * publicDuelsChosen), not paused, the community rules in force accepted, and a party that counts when asked. Public
 * duels are on by default, so accepting the rules here, at the first post or join, is what lets a player meet strangers;
 * the partner of a party is held to the same. One SafetyProfile request each gives the rules and the blocks.
 */
async function joiners(env: Env, player: string, as: JoinAs, now: number, look?: Look): Promise<Team> {
  const version = termsVersion(env), gate = (id: string) => env.SAFETY_PROFILES.getByName(id).publicGate(id, version);
  const [mine, myGate] = await Promise.all([read(env, player, now, look), gate(player)]);
  if (!publicDuelsChosen(mine.member)) throw new ApiError(403, "public_duels_off");
  if (mine.member.public_paused) throw new ApiError(403, "public_paused");
  if (!myGate.accepted) throw new ApiError(403, "terms_acceptance_required");
  await healRules(env, player, mine.member, version, now);
  const avoid = (rows: readonly Seated[], lists: readonly string[][]) => new Set([...lists.flat(), ...rows.flatMap(row => row.member.blocked_by ?? [])]);
  if (as === "alone") return { players: [player], rows: [mine], looks: [mine.party.look], avoid: avoid([mine], [myGate.blocked_players]) };
  const partner = mine.party.partner;
  if (!partner) throw new ApiError(409, "party_required");
  const [theirs, theirGate] = await Promise.all([read(env, partner, now), gate(partner)]);
  if (theirs.party.partner !== player) throw new ApiError(409, "party_required");
  if (!publicOpenTo(theirs.member)) throw new ApiError(409, "partner_public_off");
  if (!theirGate.accepted) throw new ApiError(409, "partner_rules_required");
  await healRules(env, partner, theirs.member, version, now);
  return { players: [player, partner], rows: [mine, theirs], looks: [mine.party.look, theirs.party.look], avoid: avoid([mine, theirs], [myGate.blocked_players, theirGate.blocked_players]) };
}

/**
 * Whether the Member row says `member` accepted the rules in force (`rules_version`, kept by noteRulesAccepted): what
 * the lobby tells the phone, so a party join greys before the tap with no SafetyProfile read. The SafetyProfile stays
 * the truth for a post or join (joiners).
 */
function rulesNoted(env: ServerVars, member: MemberState): boolean { return termsCovered(member.rules_version ?? null, termsVersion(env)); }

/**
 * The player accepted the public duel rules `version` (POST /v1/safety/terms from a phone shown them): their Member row
 * keeps a copy, and their party partner, whose lobby greyed a party join, hears of it. Every accept writes it again
 * when missing, so a lost write heals on the next one. 1 Member request (1 row only when it changed), 1 hint then.
 */
export async function noteRulesAccepted(env: Env, player: string, version: string, now: number): Promise<void> {
  const noted = await party(env, player).noteRules(version);
  if (noted.partner) await announceLobby(env, [noted.partner], now).catch(() => undefined);
}

/** A gate that says accepted while the Member row has no copy (a write lost after the SafetyProfile's): written now. */
async function healRules(env: Env, player: string, member: MemberState, version: string, now: number): Promise<void> {
  if (!termsCovered(member.rules_version ?? null, version)) await noteRulesAccepted(env, player, version, now);
}

/** Stops a post or join past the limit of 10, counted over the players' own pointers. */
async function underLimit(env: Env, players: readonly string[], rows: readonly Seated[], player: string): Promise<void> {
  const refs = new Map<string, DuelRef>();
  for (const row of rows) for (const ref of row.party.duels) refs.set(ref.duel_id, ref);
  const { duels } = await duelsOf(env, [...refs.values()], player);
  if (running(duels, players) >= MAX_FRIEND_DUELS_PER_PAIR) throw new ApiError(409, "duel_limit_reached");
}

function joinAs(value: unknown): JoinAs {
  if (value !== "alone" && value !== "party") throw new ApiError(400, "invalid_duel_request");
  return value;
}
function idempotency(value: unknown): string {
  if (typeof value !== "string" || !IDEMPOTENCY_PATTERN.test(value)) throw new ApiError(400, "invalid_duel_request");
  return value;
}

/** POST /v1/duels/public: a duel on `board` with every other seat open, running at once. A retry answers the duel it made. */
async function post(env: Env, player: string, input: unknown, now: number, look?: Look): Promise<unknown> {
  const body = fields(input, ["idempotency_key", "board", "as"]);
  const key = idempotency(body.idempotency_key), as = joinAs(body.as), board = boardOf(body.board), row = chapterRow(board);
  if (!creatable(row.adapter, env)) throw new ApiError(503, "chapter_creation_disabled");
  const duelId = (await digest(`after-you public duel v1\n${player}\n${key}`)).slice(0, 32);
  const team = await joiners(env, player, as, now, look);
  const held = team.rows[0].party.duels.find(ref => ref.duel_id === duelId);
  if (held) { const [duel] = await duelsAt(env, held.board).read([duelId], player); if (duel) return { schema_version: 1, duel: viewFor(duel, player, looksOn(env)) }; }
  await underLimit(env, team.players, team.rows, player);
  const labels = await Promise.all(team.players.map((id, index) => labelOf(env, id, team.rows[index].member)));
  const duel = newPublicDuel({ duel_id: duelId, board, chapter: { ...row.adapter.key }, steps: row.adapter.stages.length * 2, players: team.players, labels,
    looks: looksOn(env) ? team.looks : undefined, known: team.players.length === 2 ? [knownKey(team.players[0], team.players[1])] : [] }, now);
  const made = await duelsAt(env, board).create(duel);
  if (!made) throw new ApiError(503, "public_list_full");
  // Listed before the reply, not only after the board's: a lost update would leave a post nobody can find.
  await sendListings(env, [{ duel_id: duelId, listing: listingOf(made, now), updated_ms: made.updated_ms }]);
  await addPublicRefs(env, team.players, { duel_id: duelId, board, at: now, public: true }, now);
  forgetListings();
  await announceLobby(env, team.players.filter(id => id !== player), made.updated_ms, duelId);
  return { schema_version: 1, duel: viewFor(made, player, looksOn(env)) };
}

/**
 * POST .../join: takes the spot a join asks for (public.ts claimSeats) in one board transaction. Checked first, here:
 * the joiners are on and not paused, under the limit, and nobody seated blocked them or was blocked by them. A repeat
 * by someone already seated answers the duel; a join that lost the race is 409 spot_taken with the row as it is now.
 */
async function join(env: Env, player: string, board: string, duelId: string, input: unknown, now: number, look?: Look): Promise<unknown> {
  const body = fields(input, ["idempotency_key", "as", "seat"]);
  idempotency(body.idempotency_key);
  const as = joinAs(body.as);
  if (body.seat !== null && !(typeof body.seat === "number" && Number.isInteger(body.seat) && body.seat >= 0 && body.seat <= 3)) throw new ApiError(400, "invalid_duel_request");
  const at = duelsAt(env, board);
  const [current] = await at.read([duelId], player);
  if (!current?.public) throw new ApiError(404, "duel_not_found");
  if (seatOf(current, player) >= 0) return { schema_version: 1, duel: viewFor(current, player, looksOn(env)) };
  const team = await joiners(env, player, as, now, look);
  const avoid = team.avoid;
  // The seated players' own blocks of the joiners, which a block made before public duels did not note on the joiners' rows.
  const others = seated(current).filter(id => !avoid.has(id));
  const theirs = await pooled(others, 4, async id => (await env.SAFETY_PROFILES.getByName(id).blocks(id)).blocked_players.some(blocked => team.players.includes(blocked)) ? id : null);
  for (const id of theirs) if (id) avoid.add(id);
  await underLimit(env, team.players, team.rows, player);
  const labels = await Promise.all(team.players.map((id, index) => labelOf(env, id, team.rows[index].member)));
  const answer = await at.act(duelId, { kind: "join", player, claim: { players: team.players, as, seat: body.seat as number | null, labels,
    looks: looksOn(env) ? team.looks : undefined, avoid: [...avoid], known: team.players.length === 2 ? [knownKey(team.players[0], team.players[1])] : [] } });
  if (!answer.ok) {
    if (answer.code !== "spot_taken") unwrap(answer);
    // The list may be a moment behind: the board's listing now heals it, and the phone redraws the row from it.
    const [fresh] = await at.read([duelId], player);
    const listing = fresh ? listingOf(fresh, now) : null;
    if (fresh) await sendListings(env, [{ duel_id: duelId, listing, updated_ms: fresh.updated_ms }]);
    forgetListings();
    throw new ApiError(409, "spot_taken", { row: listing && !listing.sides.some(side => side.seats.some(seat => seat.id !== null && avoid.has(seat.id))) ? page([listing], player, avoid, "all", "newest", 0, now, looksOn(env)).rows[0] ?? null : null });
  }
  const duel = answer.value.duel;
  await addPublicRefs(env, team.players, { duel_id: duelId, board, at: now, public: true }, now);
  forgetListings();
  // "A partner joined": every player already in the duel hears of it, besides the board's own news of the change.
  await announceLobby(env, seated(duel).filter(id => !team.players.includes(id) && id !== player), duel.updated_ms, duelId);
  if (team.players.length === 2) await announceLobby(env, [team.players[1]], duel.updated_ms, duelId);
  return { schema_version: 1, duel: viewFor(duel, player, looksOn(env)) };
}

/** The duel and the player in `seat` for a player in it; the seat must hold someone else. */
async function seatTarget(env: Env, player: string, board: string, duelId: string, input: unknown, extra: string[]): Promise<{ duel: Duel; seat: number; target: string; body: Record<string, unknown> }> {
  const body = fields(input, ["seat", ...extra]);
  if (!(typeof body.seat === "number" && Number.isInteger(body.seat) && body.seat >= 0 && body.seat <= 3)) throw new ApiError(400, "invalid_duel_request");
  const [duel] = await duelsAt(env, board).read([duelId], player);
  if (!duel?.public || seatOf(duel, player) < 0) throw new ApiError(404, "duel_not_found");
  const target = holder(duel, body.seat);
  if (target === null || target === player) throw new ApiError(404, "seat_empty");
  return { duel, seat: body.seat, target, body };
}

/** A handle for a stranger's block: stable per blocker and blocked, never the id. */
async function blockHandle(owner: string, target: string): Promise<string> { return (await digest(`after-you duel block v1\n${owner}\n${target}`)).slice(0, 22); }

/**
 * Blocks the player in a seat (PLAN 7): the SafetyProfile block as any block, the blocked player's row notes it so
 * the list hides the blocker's duels from them, and a stranger's block is listed by its handle. Blocking your own
 * partner leaves the duel, a leave that costs neither of you the held extra.
 */
async function block(env: Env, request: Request, player: string, board: string, duelId: string, input: unknown, now: number): Promise<unknown> {
  const { duel, seat, target } = await seatTarget(env, player, board, duelId, input, []);
  await blockPlayer(env, player, await bearerDigest(request), target, publicKnown(duel, player, target) ? undefined : duel.public!.seats[seat].label, now);
  const left = seat >> 1 === seatOf(duel, player) >> 1 && await leaveForBlock(env, player, board, duelId);
  return { schema_version: 1, blocked: true, left };
}

/**
 * Blocking your own partner leaves the duel, a leave that costs neither of you the held extra (PLAN 7). A duel already
 * over, or a side already finished, leaves nothing; the block stands either way. Answers whether this left the duel.
 */
export async function leaveForBlock(env: Env, player: string, board: string, duelId: string): Promise<boolean> {
  const answer = await duelsAt(env, board).act(duelId, { kind: "leave", player, blocked: true });
  if (!answer.ok) return false;
  const seat = seatOf(answer.value.duel, player);
  // Gone from the seat (it went back on the list) or their side ended by this leave.
  return seat < 0 || answer.value.duel.sides.some(side => side?.left_by === seat);
}

/**
 * The block itself, shared with a public duel room's block (safety-routes.ts): `label` null for a player whose id the
 * blocker knows (an ordinary block), else the stranger's label for their handle entry. Answers the handle or the id.
 */
export async function blockPlayer(env: Env, owner: string, deviceHash: string, target: string, label: string | null | undefined, now: number): Promise<string> {
  // The handle first, so a block list never shows a stranger's block by id, even when a later step fails.
  const handle = label === undefined ? null : await blockHandle(owner, target);
  if (handle !== null) await party(env, owner).addDuelBlock({ handle, id: target, label: label ?? null, at: now } satisfies DuelBlock);
  unwrap(await env.SAFETY_PROFILES.getByName(owner).setBlock(owner, deviceHash, target, true));
  await party(env, target).noteBlockedBy(owner, true);
  return handle ?? target;
}

/** DELETE /v1/safety/blocks/duel/<handle>: undoes a stranger's block by its handle. */
export async function unblockHandle(env: Env, request: Request, owner: string, handle: string): Promise<unknown> {
  const entry = ((await party(env, owner).read()) as unknown as MemberState).duel_blocks?.find(item => item.handle === handle);
  // The block goes before its handle, so a failure in between never leaves the id in the plain list.
  if (entry) {
    unwrap(await env.SAFETY_PROFILES.getByName(owner).setBlock(owner, await bearerDigest(request), entry.id, false));
    await party(env, entry.id).noteBlockedBy(owner, false);
    await party(env, owner).removeDuelBlock(handle);
  }
  return { schema_version: 1, blocked: false };
}

/** The stranger blocks a block list shows (GET /v1/safety/blocks): handles and labels only, and the ids to leave out of the plain list. */
export async function duelBlocks(env: Env, owner: string): Promise<{ ids: Set<string>; shown: { handle: string; label: string | null }[] }> {
  const member = await party(env, owner).read();
  const entries = member.duel_blocks ?? [];
  return { ids: new Set(entries.map(entry => entry.id)), shown: entries.map(entry => ({ handle: entry.handle, label: entry.label === null ? null : shownName(entry.label) })) };
}

/**
 * Reports the player in a seat with one of the usual reasons (PLAN 8), into the same inbox, and counts it toward their
 * pause: PUBLIC_REPORTS_TO_PAUSE different reporters in a week take their duels off the list until an operator clears it.
 */
async function report(env: Env, request: Request, player: string, board: string, duelId: string, input: unknown, now: number): Promise<unknown> {
  const { seat, target, body } = await seatTarget(env, player, board, duelId, input, ["idempotency_key", "reason"]);
  const key = idempotency(body.idempotency_key);
  if (!SAFETY_REPORT_REASONS.includes(body.reason as SafetyReport["reason"])) throw new ApiError(400, "invalid_safety_request");
  const inbox = env.SAFETY_INBOX.getByName("moderation-v1"), deviceHash = await bearerDigest(request);
  const reportBody = { schema_version: 1 as const, idempotency_key: key, room_family: "duel" as const, room_id: duelId.slice(0, 22), reason: body.reason as SafetyReport["reason"], photo: null, duel: { board, duel_id: duelId, seat } };
  const hash = await digest(canonicalJson({ operation: "safety_report", reporter_id: player, ...reportBody }));
  const previous = await inbox.reportReceipt(player, key);
  if (previous.ok) { if (previous.value.request_hash !== hash) throw new ApiError(409, "idempotency_key_reused"); return previous.value; }
  const receipt = unwrap(await inbox.submit({ ...reportBody, reporter_id: player, target_id: target, request_hash: hash, report_id: await digest(player + ":" + key), created_at: now, resolved_at: null }, deviceHash));
  await countReport(env, player, target, now);
  return receipt;
}

/** A public duel report counts toward the target's pause; pausing takes their open duels off the list. */
export async function countReport(env: Env, reporter: string, target: string, now: number): Promise<void> {
  const counted = await party(env, target).publicReport(reporter, now);
  if (counted.paused_now) await hidePlayer(env, target, true, now);
}

/** Takes a player's public duels off the list (switched off or paused), or puts them back once they are open to strangers again. */
export async function hidePlayer(env: Env, player: string, hidden: boolean, now: number): Promise<void> {
  const refs = (await party(env, player).partyRead(now)).duels.filter(ref => ref.public);
  await byBoard(refs, (board, ids) => duelsAt(env, board).publicPlayer(player, ids, { hidden }));
}

/** A changed name or name choice reaches the labels on the player's public duels (leaderboards/members.ts syncMemberName). */
export async function relabelPlayer(env: Env, player: string, label: string | null, now: number): Promise<void> {
  const refs = (await party(env, player).partyRead(now)).duels.filter(ref => ref.public);
  await byBoard(refs, (board, ids) => duelsAt(env, board).publicPlayer(player, ids, { label }));
}

async function byBoard(refs: readonly DuelRef[], run: (board: string, ids: string[]) => Promise<unknown>): Promise<void> {
  const boards = new Map<string, string[]>();
  for (const ref of refs) boards.set(ref.board, [...(boards.get(ref.board) ?? []), ref.duel_id]);
  await pooled([...boards], 4, ([board, ids]) => run(board, ids));
}

/**
 * Asks the player in a seat to be friends, once the duel is over (owner, 2026-11-03): an ordinary friend request
 * from the asker, through the friend request path, so the other player sees the asker's code and name as with any
 * request. The asker's phone never gets the other id: the reply says only that it was sent, and their own list
 * hides the request until it is accepted (DUEL_REQUEST_PREFIX).
 */
async function friend(env: Env, request: Request, player: string, board: string, duelId: string, input: unknown): Promise<unknown> {
  const { duel, target } = await seatTarget(env, player, board, duelId, input, []);
  if (!isFinal(duel)) throw new ApiError(409, "duel_not_over");
  try { await requestFriend(env, player, await bearerDigest(request), target, DUEL_REQUEST_PREFIX + randomToken(13).slice(0, 17)); }
  catch (error) {
    // Blocked, gone or full answers the same, so nothing about the other player shows.
    if (error instanceof ApiError && error.status < 500 && error.code !== "invalid_auth") throw new ApiError(409, "friend_unavailable");
    throw error;
  }
  return { schema_version: 1, sent: true };
}

const UNPAUSE_PATH = /^\/operator\/safety\/players\/([A-Za-z0-9_-]{22})\/public-unpause$/;
/**
 * POST /operator/safety/players/<id>/public-unpause, after requireOperator: clears a public duels pause and the reports
 * behind it, and puts the player's open public duels back on the list. Safe to repeat. Null for any other path.
 */
export async function routePublicPauseOperator(request: Request, path: string, env: Env): Promise<unknown | null> {
  const match = UNPAUSE_PATH.exec(path);
  if (!match) return null;
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const body = await boundedJson(request, 1024);
  if (!isObject(body) || Object.keys(body).length !== 1 || body.schema_version !== 1) throw new ApiError(400, "invalid_safety_request");
  const state = (await party(env, match[1]).clearPublicPause()) as unknown as MemberState;
  // A player who turned the switch off stays off the list.
  await hidePlayer(env, match[1], !publicOpenTo(state), Date.now());
  return { schema_version: 1, unpaused: true };
}

/**
 * PUT /v1/duels/public/me {on}: the switch, on by default (leaderboards/member.ts publicDuelsChosen). Turning it on
 * needs the current community rules accepted. Off takes the player's open duels off the list before the switch says
 * so, so no join lands between the two; every on puts them back unless a pause keeps them off. A post or join already on
 * its way meets the off through its pointer (addPublicRefs).
 */
async function setSwitch(env: Env, player: string, input: unknown, now: number): Promise<unknown> {
  const body = fields(input, ["on"]);
  if (typeof body.on !== "boolean") throw new ApiError(400, "invalid_duel_request");
  if (body.on && !(await env.SAFETY_PROFILES.getByName(player).terms(player, termsVersion(env))).accepted) throw new ApiError(403, "terms_acceptance_required");
  if (!body.on) await hidePlayer(env, player, true, now);
  const state = (await party(env, player).setPublicDuels(body.on)) as unknown as MemberState;
  // Every on settles the marks again, so an on retried after a lost reply, or after a failed off, still lists them.
  if (body.on) await hidePlayer(env, player, !publicOpenTo(state), now);
  return { schema_version: 1, on: publicDuelsChosen(state), show_name: state.show_name, paused: !!state.public_paused };
}

/**
 * The joiners' pointers to a public duel they just posted or joined (as addRefs, one Member request each), and their
 * seats hidden there when one of them switched off or was paused meanwhile: the switch's own hiding (setSwitch) reads
 * the pointers, and this duel's was not there yet.
 */
async function addPublicRefs(env: Env, players: readonly string[], ref: DuelRef, now: number): Promise<void> {
  const closed = await pooled([...new Set(players)], 2, async id => (await party(env, id).addPublicRef(id, ref, now)).open ? null : id);
  for (const id of closed) if (id) await duelsAt(env, ref.board).publicPlayer(id, [ref.duel_id], { hidden: true });
}

/** The list read (GET .../list/...), whose auth() also gives the reader's safety token for ownBlocks. */
export function publicListRoute(request: Request, path: string): boolean { return request.method === "GET" && LIST_PATH.test(path); }

/**
 * GET .../list/<scope>/<sort>/<page>: one reader's page. Its own checks: the Member row (who blocked them) and their
 * own block list, which safety.ts ownBlocks keeps per safety token, so a page read again soon costs auth and the Member.
 */
async function list(env: Env, player: string, scope: string, sort: ListSort, index: number, now: number, safetyToken?: string): Promise<unknown> {
  if (scope !== "all") boardOf(scope);
  const [member, blocked, all] = await Promise.all([party(env, player).read() as Promise<MemberState>, ownBlocks(env, player, safetyToken), listings(env, now)]);
  const avoid = new Set([...blocked, ...(member.blocked_by ?? [])]);
  return { schema_version: 1, page: index, ...page(all, player, avoid, scope, sort, index, now, looksOn(env)) };
}

/** The signed-in routes under /v1/duels/public; null for any other path. The caller checked publicDuelsOn. */
export async function routePublicDuels(request: Request, path: string, player: string, env: Env, now: number, input: unknown, look?: Look, safetyToken?: string): Promise<unknown | null> {
  if (path !== PUBLIC_PREFIX && !path.startsWith(PUBLIC_PREFIX + "/")) return null;
  if (request.method === "GET") {
    const match = LIST_PATH.exec(path);
    if (!match) throw new ApiError(404, "not_found");
    return list(env, player, match[1], match[2] as ListSort, Number(match[3]), now, safetyToken);
  }
  if (path === PUBLIC_PREFIX + "/me") {
    if (request.method !== "PUT") throw new ApiError(405, "method_not_allowed");
    return setSwitch(env, player, input, now);
  }
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  if (path === PUBLIC_PREFIX) return post(env, player, input, now, look);
  const match = SEAT_PATH.exec(path);
  if (!match) throw new ApiError(404, "not_found");
  const [, board, duelId, action] = match;
  boardOf(board);
  if (action === "join") return join(env, player, board, duelId, input, now, look);
  if (action === "block") return block(env, request, player, board, duelId, input, now);
  if (action === "report") return report(env, request, player, board, duelId, input, now);
  return friend(env, request, player, board, duelId, input);
}

/**
 * The lobby's `public` part while public duels are on: the switches, whether the player and their partner accepted the
 * rules in force (`rules`, `partner_rules`, from the Member rows the party read brings: no request added) and the count
 * toward the limit of 10. Older phones read only the keys they know.
 */
export function publicLobby(env: Env, player: string, members: readonly (MemberState | null)[] | undefined, intact: boolean, duels: readonly Duel[]): { public?: Record<string, unknown> } {
  if (!publicDuelsOn(env) || !members?.[0]) return {};
  const [mine, theirs] = [members[0], intact ? members[1] ?? null : null];
  return { public: { version: 1, on: publicDuelsChosen(mine), show_name: mine.show_name, partner_on: theirs ? publicOpenTo(theirs) : null, paused: !!mine.public_paused,
    running: running(duels, [player]), rules: rulesNoted(env, mine), partner_rules: theirs ? rulesNoted(env, theirs) : null } };
}

/** `final`: every answer is one the wallet will give again (paid, or refused for good), so a read may keep it (payout-receipt.ts). */
export type PublicSettle = { extra: DuelExtraAnswer | null; win: DuelWinAnswer | null; final: boolean };
/**
 * A final public duel's pay for `player`, once (their party row's `settled`, as a win today, or the receipt on the duel's
 * row): the held extra, paid or forfeited by the duel's rules (public.ts heldState), and the win bonus on a win on time,
 * in one wallet request. Null while there is nothing to ask: not final, Pollen off, or settled before unless `force`.
 */
export async function settlePublic(env: Env, player: string, duel: Duel, settled: readonly string[], force = false): Promise<PublicSettle | null> {
  if (!duel.public || !isFinal(duel) || !pollenEarning(env) || (!force && settled.includes(duel.duel_id))) return null;
  const seat = seatOf(duel, player);
  if (seat < 0) return null;
  const mine = seat >> 1, state = heldState(duel, seat), decided = duel.result?.decided_ms ?? duel.updated_ms;
  const won = duel.status === "decided" && duel.result?.winner === mine && duel.result.reason === "faster";
  let win;
  if (won) {
    const other = duel.sides[1 - mine]!.members;
    win = { duel_id: duel.duel_id, opponent: other[0] && other[1] ? await pairKey(other[0], other[1]) : `public:${duel.duel_id}`, decided_ms: decided };
  }
  try {
    const answer = await env.PLAYERS.getByName(player).settlePublicDuel(player, { duel_id: duel.duel_id, room_id: duel.sides[mine]!.room?.room_id ?? null, decided_ms: decided, paid: state.paid, ...(state.reason ? { reason: state.reason } : {}) }, win);
    const extra = answer.extra.ok ? answer.extra.value : null, paid = answer.win?.ok ? answer.win.value : null;
    // A final refusal (an old end, no identity) is settled too, so it is never asked again.
    if (!answer.extra.ok && answer.extra.status >= 500) return null;
    // An extra paid with nothing held wrote no line, so a held turn whose credit lands late (a turn claim) is summed only
    // by a later ask: such an answer is not final while the side has a room. A forfeit stays unpaid either way.
    const unsummed = extra !== null && extra.paid && extra.held === 0 && duel.sides[mine]!.room !== null;
    return { extra, win: paid, final: lastingAnswer(answer.extra) && lastingAnswer(answer.win) && !unsummed };
  } catch { return null; }
}

/**
 * The duel page's held extra for a public duel: while it runs, what the player's turns in their room hold (1 Player
 * read); once over, what the settle paid or why not.
 */
export async function publicDetail(env: Env, player: string, duel: Duel, settledNow: PublicSettle | null): Promise<{ held?: ShownHeld }> {
  if (!duel.public || !pollenEarning(env)) return {};
  const seat = seatOf(duel, player);
  if (seat < 0) return {};
  if (!isFinal(duel)) {
    const room = duel.sides[seat >> 1]!.room;
    const amount = room ? (await env.PLAYERS.getByName(player).duelRoomPay(room.room_id)).held : 0;
    return { held: { amount, state: "running" } };
  }
  const extra = settledNow?.extra, state = heldState(duel, seat);
  return { held: { amount: extra ? (extra.paid ? extra.amount : extra.held) : 0, state: state.paid ? "paid" : "forfeit", ...(state.reason ? { reason: state.reason } : {}) } };
}
