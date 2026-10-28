import { fail, ok, type Outcome } from "../protocol";
import { MAX_MEMBER_DUELS, MAX_PARTY_INVITES, PARTY_INVITE_TTL_MS } from "./rules";

/**
 * A player's duel party and duel pointers, one JSON row in their own
 * LeaderboardMember object (leaderboards/member.ts), never the Player: the
 * Player's portable snapshot accepts only its known tables.
 *
 * A party is exactly two friends. One invites (invite_out), the friend sees
 * it (invites_in) and accepts; each side then names the other as `partner`.
 * Each player's row is written by its own object, so the two sides can
 * disagree for a moment (a lost write, a race between two invites): a party
 * counts only while both name each other, which every route that uses one
 * checks (mutual). Joining a new party leaves the old one.
 *
 * `duels`: the duels this player is in, by board, so the lobby asks only
 * those boards. Pure functions here; member.ts runs them in a transaction.
 */
export type PartyInvite = { from: string; at: number };
export type DuelRef = { duel_id: string; board: string; at: number };
export type PartyState = {
  schema_version: 1; partner: string | null; since: number;
  invites_in: PartyInvite[]; invite_out: { to: string; at: number } | null; duels: DuelRef[];
  /** Duels whose win bonus this player was already paid or refused, so a read asks the wallet once. */
  settled: string[];
};
export type PartyOp =
  | { kind: "invite"; to: string }
  | { kind: "invited"; from: string }
  | { kind: "accept"; from: string }
  | { kind: "confirm"; partner: string }
  | { kind: "dismiss"; from: string }
  | { kind: "cancel" }
  | { kind: "unpartner"; partner: string }
  | { kind: "leave" }
  | { kind: "add_duels"; refs: DuelRef[] }
  | { kind: "drop_duels"; ids: string[] }
  | { kind: "settle_wins"; ids: string[] };
/** `previous`: the partner this op replaced or removed, whose own row should be told. */
export type PartyAnswer = { state: PartyState; previous: string | null };

export function blankParty(): PartyState {
  return { schema_version: 1, partner: null, since: 0, invites_in: [], invite_out: null, duels: [], settled: [] };
}

/** Drops invites past their time. Returns whether anything went. */
export function prune(state: PartyState, now: number): boolean {
  const before = state.invites_in.length, out = state.invite_out;
  state.invites_in = state.invites_in.filter(invite => now - invite.at < PARTY_INVITE_TTL_MS);
  if (out && now - out.at >= PARTY_INVITE_TTL_MS) state.invite_out = null;
  return state.invites_in.length !== before || state.invite_out !== out;
}

/** Applies one op for `owner`. Every op is safe to repeat. */
export function applyParty(state: PartyState, owner: string, op: PartyOp, now: number): Outcome<PartyAnswer> {
  prune(state, now);
  let previous: string | null = null;
  const setPartner = (partner: string) => {
    if (state.partner !== partner) { previous = state.partner; state.partner = partner; state.since = now; }
    state.invites_in = state.invites_in.filter(invite => invite.from !== partner);
    if (state.invite_out?.to === partner) state.invite_out = null;
  };
  switch (op.kind) {
    case "invite":
      if (op.to === owner) return fail(400, "party_self");
      if (state.partner !== op.to) state.invite_out = { to: op.to, at: now };
      break;
    case "invited":
      if (op.from === owner) return fail(400, "party_self");
      if (state.partner === op.from) break;
      state.invites_in = [...state.invites_in.filter(invite => invite.from !== op.from), { from: op.from, at: now }].slice(-MAX_PARTY_INVITES);
      break;
    case "accept":
      if (state.partner === op.from) break;
      if (!state.invites_in.some(invite => invite.from === op.from)) return fail(409, "party_invite_gone");
      setPartner(op.from);
      break;
    case "confirm":
      // The inviter's side of an accept: only while their invite to this friend stands.
      if (state.partner === op.partner) break;
      if (state.invite_out?.to !== op.partner) return fail(409, "party_invite_gone");
      setPartner(op.partner);
      break;
    case "dismiss":
      state.invites_in = state.invites_in.filter(invite => invite.from !== op.from);
      break;
    case "cancel":
      state.invite_out = null;
      break;
    case "unpartner":
      if (state.partner === op.partner) { previous = state.partner; state.partner = null; state.since = now; }
      break;
    case "leave":
      if (state.partner !== null) { previous = state.partner; state.partner = null; state.since = now; }
      break;
    case "add_duels": {
      const fresh = op.refs.filter(ref => !state.duels.some(held => held.duel_id === ref.duel_id));
      state.duels = [...state.duels, ...fresh].slice(-MAX_MEMBER_DUELS);
      break;
    }
    case "drop_duels":
      state.duels = state.duels.filter(ref => !op.ids.includes(ref.duel_id));
      state.settled = state.settled.filter(id => !op.ids.includes(id));
      break;
    case "settle_wins":
      state.settled = [...new Set([...state.settled, ...op.ids])].slice(-MAX_MEMBER_DUELS * 2);
      break;
  }
  return ok({ state, previous });
}

/** Whether two rows name each other: a party that counts. */
export function mutual(a: string, stateA: PartyState, b: string, stateB: PartyState): boolean {
  return a !== b && stateA.partner === b && stateB.partner === a;
}

/** A stored row, or blank when it is not one this build wrote. */
export function parsedParty(text: string | undefined): PartyState {
  if (!text) return blankParty();
  try {
    const value = JSON.parse(text) as PartyState;
    return value?.schema_version === 1 && Array.isArray(value.invites_in) && Array.isArray(value.duels) ? { ...blankParty(), ...value, settled: Array.isArray(value.settled) ? value.settled : [] } : blankParty();
  } catch { return blankParty(); }
}
