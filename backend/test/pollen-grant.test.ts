import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { BOUGHT_GAP_MS, RETRY_MS, anniversary, claimsNeeded, emptyGrant, grantDue, instalmentAmount, planGrant, type ClaimAnswer, type GrantState, type GrantSub, type Instalment, type MovedSub } from "../src/pollen/grant";
import { grantSub, lookupGrantSubs, readGrant } from "../src/pollen/grant-provider";
import { RATES } from "../src/pollen/rates";
import { OUTAGE_PAUSE_MS, settleGrant, storedGrant, type GrantDeps } from "../src/pollen/grant-settle";
import { claimFor, POLLEN_CLAIMS_OBJECT } from "../src/pollen/claims";
import { grantOn } from "../src/pollen/features";
import { fullJourneyUntil, ledgerLines, noteFullJourney, walletView } from "../src/pollen/wallet";
import { FULL_JOURNEY_HEADER, POLLEN_GRANT_HINT_MIN_VERSION, POLLEN_HEADER, grantHint } from "../src/pollen/routes";
import { CLIENT_HEADER } from "../src/app-status";
import { countingEnv, meterRows } from "./meter";
import { POLLEN_CLIENT, configJson } from "./config";

// The Full Journey monthly grant: the ladder, anniversaries, trial, grace and hold, plan switches,
// gaps, refunds, moved subscriptions, provider outages, overlapping reads and what each read costs.
// RevenueCat is always a mock here; synthetic identities and subscription ids only.
const DAY = 86_400_000, HOUR = 3_600_000;
const at = (year: number, month: number, day: number, hour = 10) => Date.UTC(year, month - 1, day, hour);
const iso = (ms: number) => new Date(ms).toISOString().slice(0, 10);
const paid = (id: string, from: number, to: number, extra: Partial<GrantSub> = {}): GrantSub => ({ id, status: "paid", started_at: from, period_start: from, period_end: to, ends_at: to, renews: true, access_until: to, ...extra });
const ended = (id: string, from: number, to: number, endsAt = to, started = from): GrantSub => ({ id, status: "ended", started_at: started, period_start: from, period_end: to, ends_at: endsAt, renews: false, access_until: 0 });
const status = (id: string, kind: GrantSub["status"], from: number, to: number): GrantSub => ({ id, status: kind, started_at: from, period_start: from, period_end: to, ends_at: to, renews: true, access_until: kind === "hold" ? 0 : to });

/** One identity's grant, read after read, with the PollenClaims rules over a shared map of holders. */
class Identity {
  state: GrantState | null = null;
  ledger: Instalment[] = [];
  refunded = new Set<string>();
  constructor(private readonly holders: Map<string, { holder: string; since: number; moved: boolean }>, private readonly name: string) {}
  /** PollenClaims' rules (claims.ts), over a map shared by every identity. */
  private claim(id: string, now: number): ClaimAnswer {
    const row = this.holders.get(id);
    if (row?.holder === this.name) return { self: !row.moved, since: row.since };
    this.holders.set(id, { holder: this.name, since: now, moved: !!row });
    return { self: !row, since: now };
  }
  read(subs: GrantSub[], now: number, moved: MovedSub[] = []) {
    const claims = Object.fromEntries(claimsNeeded(this.state, subs).map(id => [id, this.claim(id, now)]));
    const plan = planGrant(this.state, subs, claims, now, (sub, from, to) => this.ledger
      .filter(each => each.sub === sub && each.due >= from && each.due < to && !this.refunded.has(each.key)).map(({ key, amount, anchor, n, due }) => ({ key, amount, anchor, n, due, sub })), null, RATES, moved);
    for (const each of plan.pay) if (!this.ledger.some(other => other.key === each.key)) this.ledger.push(each);
    for (const refund of plan.refunds) this.refunded.add(refund.refunds);
    this.state = plan.state;
    return plan;
  }
  get balance(): number { return this.ledger.reduce((sum, each) => sum + (this.refunded.has(each.key) ? 0 : each.amount), 0); }
}
const fresh = () => new Identity(new Map(), "one");

describe("the grant ladder and its dates", () => {
  it("pays month n min(4,500 + 250 x (n - 1), 12,000)", () => {
    const table: [number, number][] = [[1, 4500], [2, 4750], [3, 5000], [4, 5250], [12, 7250], [13, 7500], [24, 10250], [30, 11750], [31, 12000], [32, 12000], [120, 12000]];
    for (const [n, amount] of table) expect([n, instalmentAmount(n)]).toEqual([n, amount]);
  });
  it("falls due on the anchor's day each month, or the month's last day, counted from the anchor every time", () => {
    const jan31 = at(2026, 1, 31, 15);
    expect([0, 1, 2, 3, 4].map(k => iso(anniversary(jan31, k)))).toEqual(["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31"]);
    expect(new Date(anniversary(jan31, 1)).getUTCHours()).toBe(15);
    // Leap years: the 31st and the 29th of February.
    expect(iso(anniversary(at(2028, 1, 31), 1))).toBe("2028-02-29");
    const leap = at(2028, 2, 29);
    expect([1, 12, 24, 48].map(k => iso(anniversary(leap, k)))).toEqual(["2028-03-29", "2029-02-28", "2030-02-28", "2032-02-29"]);
    // Across the year end.
    expect([0, 1, 2].map(k => iso(anniversary(at(2026, 11, 30), k)))).toEqual(["2026-11-30", "2026-12-30", "2027-01-30"]);
  });
});

describe("grant instalments", () => {
  it("pays on each monthly anniversary from the 31st, at a growing step, once a month", () => {
    const player = fresh(), anchor = at(2026, 1, 31), ann = (k: number) => anniversary(anchor, k);
    expect(player.read([paid("m", anchor, ann(1))], anchor + HOUR).pay.map(each => [each.key, each.amount])).toEqual([[`grant:${anchor}:1`, 4500]]);
    expect(player.read([paid("m", anchor, ann(1))], anchor + 2 * HOUR).pay).toEqual([]);
    for (const k of [1, 2, 3]) player.read([paid("m", ann(k), ann(k + 1))], ann(k) + HOUR);
    expect(player.ledger.map(each => [iso(each.due), each.amount])).toEqual([["2026-01-31", 4500], ["2026-02-28", 4750], ["2026-03-31", 5000], ["2026-04-30", 5250]]);
    expect(player.state!.months).toBe(4);
  });
  it("pays the yearly plan monthly, never a lump, and catches up missed months each at its own step", () => {
    const player = fresh(), anchor = at(2026, 3, 10), year = anniversary(anchor, 12);
    expect(player.read([paid("y", anchor, year)], anchor + HOUR).pay).toHaveLength(1);
    const late = player.read([paid("y", anchor, year)], anniversary(anchor, 3) + HOUR);
    expect(late.pay.map(each => [each.n, each.amount])).toEqual([[2, 4750], [3, 5000], [4, 5250]]);
    expect(player.read([paid("y", anchor, year)], anniversary(anchor, 3) + 2 * HOUR).pay).toEqual([]);
  });
  it("starts a yearly plan first seen months in at its latest anniversary: one instalment, never a lump", () => {
    const player = fresh(), start = at(2026, 1, 31), year = anniversary(start, 12), seen = anniversary(start, 7) + 3 * DAY;
    const first = player.read([paid("y", start, year)], seen);
    expect(first.pay.map(each => [iso(each.due), each.amount])).toEqual([["2026-08-31", 4500]]);
    expect(player.read([paid("y", start, year)], anniversary(start, 8) + HOUR).pay.map(each => [iso(each.due), each.amount])).toEqual([["2026-09-30", 4750]]);
  });
  it("pays nothing in a trial, grace or hold, counts none of those months, and pays a recovered month on recovery", () => {
    const player = fresh(), start = at(2026, 5, 1), trialEnd = start + 7 * DAY;
    const trial = player.read([status("t", "trial", start, trialEnd)], start + HOUR);
    expect(trial.pay).toEqual([]); expect(trial.state.months).toBe(0); expect(trial.state.recheck_at).toBe(trialEnd);
    const ann = (k: number) => anniversary(trialEnd, k);
    expect(player.read([paid("t", trialEnd, ann(1))], trialEnd + HOUR).pay.map(each => [each.anchor, each.amount])).toEqual([[trialEnd, 4500]]);
    // Grace at the next anniversary: nothing yet, and the anchor waits.
    const grace = player.read([status("t", "grace", ann(1), ann(2))], ann(1) + HOUR);
    expect(grace.pay).toEqual([]); expect(grace.state.live).toBe(true);
    expect(player.read([paid("t", ann(1), ann(2))], ann(1) + 3 * DAY).pay.map(each => each.amount)).toEqual([4750]);
    // A hold that never recovers: the month is never paid and never counted.
    expect(player.read([status("t", "hold", ann(2), ann(3))], ann(2) + HOUR).pay).toEqual([]);
    const lapsed = player.read([ended("t", ann(1), ann(2))], ann(2) + 20 * DAY);
    expect(lapsed.pay).toEqual([]); expect(lapsed.state).toMatchObject({ live: false, months: 2 });
  });
  it("keeps the anchor and the count through a monthly to yearly switch, with no extra instalment", () => {
    const player = fresh(), anchor = at(2026, 1, 5), ann = (k: number) => anniversary(anchor, k);
    for (const k of [0, 1, 2]) player.read([paid("m", ann(k), ann(k + 1))], ann(k) + HOUR);
    const switchAt = at(2026, 3, 10), yearEnd = anniversary(switchAt, 12);
    // The old plan ends early at the switch and the new one carries on from there: not a refund.
    const switched = player.read([ended("m", ann(2), ann(3), switchAt), paid("y", switchAt, yearEnd)], switchAt + HOUR);
    expect(switched.pay).toEqual([]); expect(switched.refunds).toEqual([]);
    const april = player.read([ended("m", ann(2), ann(3), switchAt), paid("y", switchAt, yearEnd)], ann(3) + HOUR);
    expect(april.pay.map(each => [each.key, each.amount, each.sub])).toEqual([[`grant:${anchor}:4`, 5250, "y"]]);
    expect(player.state).toMatchObject({ anchor, months: 4 });
  });
  it("starts a new anchor after a gap with no subscription, keeping the count", () => {
    const player = fresh(), anchor = at(2026, 1, 5), ann = (k: number) => anniversary(anchor, k);
    player.read([paid("m", ann(0), ann(1))], ann(0) + HOUR);
    player.read([paid("m", ann(1), ann(2), { renews: false })], ann(1) + HOUR);
    expect(player.read([ended("m", ann(1), ann(2))], ann(2) + DAY).state).toMatchObject({ live: false, months: 2 });
    const back = at(2026, 4, 20);
    const again = player.read([ended("m", ann(1), ann(2)), paid("n", back, anniversary(back, 1))], back + HOUR);
    expect(again.pay.map(each => [each.key, each.amount])).toEqual([[`grant:${back}:1`, 5000]]);
    expect(player.state).toMatchObject({ anchor: back, months: 3, live: true });
  });
  it("takes back a refunded month and moves the count back, so the next paid month pays that step", () => {
    const player = fresh(), anchor = at(2026, 1, 5), ann = (k: number) => anniversary(anchor, k);
    player.read([paid("m", ann(0), ann(1))], ann(0) + HOUR);
    player.read([paid("m", ann(1), ann(2))], ann(1) + HOUR);
    expect(player.balance).toBe(4500 + 4750);
    const refundAt = ann(1) + 5 * DAY;
    const refund = player.read([ended("m", ann(1), ann(2), refundAt)], refundAt + HOUR);
    expect(refund.refunds).toEqual([{ key: `grantrefund:${anchor}:2`, refunds: `grant:${anchor}:2`, amount: 4750, sub: "m" }]);
    expect(player.state!.months).toBe(1); expect(player.balance).toBe(4500);
    // Seen again: nothing more is taken back.
    expect(player.read([ended("m", ann(1), ann(2), refundAt)], refundAt + 2 * HOUR).refunds).toEqual([]);
    const back = at(2026, 3, 20);
    expect(player.read([ended("m", ann(1), ann(2), refundAt), paid("n", back, anniversary(back, 1))], back + HOUR).pay.map(each => each.amount)).toEqual([4750]);
  });
  it("never pays a moved subscription's month twice: the new holder starts a month after the move, the old one stops", () => {
    const holders = new Map<string, { holder: string; since: number; moved: boolean }>();
    const first = new Identity(holders, "first"), second = new Identity(holders, "second");
    const anchor = at(2026, 6, 1), year = anniversary(anchor, 12);
    first.read([paid("s", anchor, year)], anchor + HOUR);
    const moveAt = anchor + 10 * DAY;
    const refused = second.read([paid("s", anchor, year)], moveAt);
    expect(refused.pay).toEqual([]);
    expect(refused.state.recheck_at).toBe(anniversary(moveAt, 1));
    // The old holder no longer has it listed: nothing more there.
    expect(first.read([], anniversary(anchor, 1) + HOUR).pay).toEqual([]);
    const later = second.read([paid("s", anchor, year)], anniversary(moveAt, 1) + HOUR);
    expect(later.pay.map(each => [each.anchor, each.amount])).toEqual([[anniversary(moveAt, 1), 4500]]);
    expect(first.ledger.length + second.ledger.length).toBe(2);
  });
  it("takes back a moved subscription's refunded month once, looking it up when the cover seen here ends", () => {
    const holders = new Map<string, { holder: string; since: number; moved: boolean }>();
    const first = new Identity(holders, "first"), second = new Identity(holders, "second");
    const anchor = at(2026, 6, 1), next = anniversary(anchor, 1);
    first.read([paid("s", anchor, next)], anchor + HOUR);
    expect(first.balance).toBe(4500);
    // Restored to the second identity; the first no longer lists it.
    second.read([paid("s", anchor, next)], anchor + DAY);
    const gone = first.read([], anchor + 2 * DAY);
    expect(gone.refunds).toEqual([]);
    // One read when the cover seen here ends, not a daily one.
    expect(gone.state.recheck_at).toBe(next);
    // Still in the period this identity saw past its end (grace at the new holder): kept, and looked at again tomorrow.
    const live = first.read([], next + HOUR, [{ id: "s", sub: status("s", "grace", anchor, next), others: [] }]);
    expect(live.refunds).toEqual([]);
    expect(live.state.subs.s).toBeDefined();
    expect(live.state.recheck_at).toBe(next + HOUR + RETRY_MS);
    // Refunded at the new holder: ended early, with no plan carrying on there.
    const refundAt = anchor + 4 * DAY;
    const back = first.read([], next + DAY, [{ id: "s", sub: ended("s", anchor, next, refundAt), others: [] }]);
    expect(back.refunds).toEqual([{ key: `grantrefund:${anchor}:1`, refunds: `grant:${anchor}:1`, amount: 4500, sub: "s" }]);
    expect(first.balance).toBe(0);
    expect(back.state.months).toBe(0);
    // Forgotten here: no more lookups, no daily read for it, and nothing taken back twice.
    expect(back.state.subs.s).toBeUndefined();
    expect(back.state.recheck_at).toBe(0);
    expect(first.read([], next + 2 * DAY, [{ id: "s", sub: ended("s", anchor, next, refundAt), others: [] }]).refunds).toEqual([]);
    expect(Object.keys(back.state)).toHaveLength(13);
  });
  it("takes nothing back from a moved subscription that switched plan at its holder, renewed past the cover seen here, or is gone", () => {
    const anchor = at(2026, 6, 1), next = anniversary(anchor, 1), endAt = anchor + 9 * DAY;
    const setup = () => { const one = new Identity(new Map(), "one"); one.read([paid("s", anchor, next)], anchor + HOUR); one.read([], anchor + DAY); return one; };
    const switched = setup().read([], endAt + HOUR, [{ id: "s", sub: ended("s", anchor, next, endAt), others: [paid("y", endAt, anniversary(endAt, 12))] }]);
    expect(switched.refunds).toEqual([]);
    expect(switched.state.subs.s).toBeUndefined();
    const renewed = setup().read([], next + DAY, [{ id: "s", sub: paid("s", next, anniversary(anchor, 2)), others: [] }]);
    expect(renewed.refunds).toEqual([]);
    expect(renewed.state.subs.s).toBeUndefined();
    const missing = setup().read([], next + DAY, [{ id: "s", sub: null, others: [] }]);
    expect(missing.refunds).toEqual([]);
    expect(missing.state.subs.s).toBeUndefined();
    // Still this identity's (only a config change dropped it from the list): kept, with no daily read for it.
    const held = setup().read([], next + DAY, [{ id: "s", sub: null, others: [], held: true }]);
    expect(held.refunds).toEqual([]);
    expect(held.state.subs.s).toBeDefined();
    expect(held.state.recheck_at).toBe(0);
  });
  it("never pays one store month to two identities when a subscription is restored back and forth", () => {
    const holders = new Map<string, { holder: string; since: number; moved: boolean }>();
    const first = new Identity(holders, "first"), second = new Identity(holders, "second");
    const t0 = at(2026, 6, 1), ann = (k: number) => anniversary(t0, k), sub = (k: number) => paid("s", ann(k), ann(k + 1));
    first.read([sub(0)], t0 + HOUR);
    second.read([sub(0)], t0 + DAY);
    // Back to the first a day before its next due date, then to the second again just after it.
    first.read([sub(1)], ann(1) + HOUR - 2 * DAY + 1);
    const back = first.read([sub(1)], ann(1) + HOUR);
    expect(back.pay).toEqual([]);
    const again = second.read([sub(1)], ann(1) + 12 * HOUR);
    expect(again.pay).toEqual([]);
    // Over three months only the months each one held from a month on are paid, never one store month twice.
    for (const k of [2, 3]) { first.read([], ann(k) + HOUR); second.read([sub(k)], ann(k) + 13 * HOUR); }
    const dues = [...first.ledger, ...second.ledger].map(each => each.due).sort((a, b) => a - b);
    expect(first.ledger.map(each => iso(each.due))).toEqual(["2026-06-01"]);
    for (let index = 1; index < dues.length; index++) expect(dues[index] - dues[index - 1]).toBeGreaterThanOrEqual(28 * DAY);
  });
  it("plans the same on a retry: a moved subscription's answer never turns into the first holder's", () => {
    const holders = new Map<string, { holder: string; since: number; moved: boolean }>();
    const first = new Identity(holders, "first"), anchor = at(2026, 6, 1), year = anniversary(anchor, 12);
    first.read([paid("s", anchor, year)], anchor + HOUR);
    const lost = new Identity(holders, "second"), moveAt = anchor + 10 * DAY;
    lost.read([paid("s", anchor, year)], moveAt);
    // The first read's save was lost: a fresh identity state asks again and still waits a month.
    const retry = new Identity(holders, "second");
    expect(retry.read([paid("s", anchor, year)], moveAt + HOUR).pay).toEqual([]);
    expect(retry.state!.subs.s.from).toBe(anniversary(moveAt, 1));
  });
  it("pays no month while paused or on hold, and the month that ends in recovery at the recovery", () => {
    const player = fresh(), anchor = at(2026, 1, 5), ann = (k: number) => anniversary(anchor, k);
    player.read([paid("m", ann(0), ann(1))], ann(0) + HOUR);
    player.read([paid("m", ann(1), ann(2))], ann(1) + HOUR);
    expect(player.read([status("m", "hold", ann(2), ann(3))], ann(2) + HOUR).pay).toEqual([]);
    expect(player.read([status("m", "hold", ann(2), ann(3))], ann(3) + HOUR).pay).toEqual([]);
    const resume = at(2026, 4, 20);
    const resumed = player.read([paid("m", resume, anniversary(resume, 1))], resume + HOUR);
    expect(resumed.pay.map(each => [each.anchor, each.amount])).toEqual([[resume, 5000]]);
    expect(player.state!.months).toBe(3);
  });
  it("pays no paused month even when nobody read during the pause: a resume restarts off the anniversaries", () => {
    const player = fresh(), anchor = at(2026, 1, 5), ann = (k: number) => anniversary(anchor, k);
    player.read([paid("m", ann(0), ann(1))], ann(0) + HOUR);
    const resume = at(2026, 4, 20);
    const resumed = player.read([paid("m", resume, anniversary(resume, 1))], resume + HOUR);
    expect(resumed.pay.map(each => [each.anchor, each.amount])).toEqual([[resume, 4750]]);
    expect(player.state!.months).toBe(2);
  });
  it("keeps reading a plan on hold at its due dates, so a recovery is seen", () => {
    const player = fresh(), anchor = at(2026, 1, 5), ann = (k: number) => anniversary(anchor, k);
    player.read([paid("m", ann(0), ann(1))], ann(0) + HOUR);
    const held = player.read([status("m", "hold", ann(1), ann(2))], ann(1) + HOUR);
    expect(held.state.renews).toBe(true);
    expect(grantDue(held.state, 0, ann(1) + 2 * DAY)).toBe(true);
  });
  it("is no plan switch when the other plan was bought days before the refunded one ended", () => {
    const player = fresh(), anchor = at(2026, 1, 5), ann = (k: number) => anniversary(anchor, k);
    const other = ann(0) + 2 * DAY;
    player.read([paid("a", ann(0), ann(1)), paid("b", other, anniversary(other, 1))], other + HOUR);
    const refundAt = ann(0) + 6 * DAY;
    const read = player.read([ended("a", ann(0), ann(1), refundAt), paid("b", other, anniversary(other, 1))], refundAt + HOUR);
    expect(read.refunds.map(each => each.refunds)).toEqual([`grant:${anchor}:1`]);
  });
  it("still catches up a monthly plan that renewed while nobody read it", () => {
    const player = fresh(), anchor = at(2026, 1, 5), ann = (k: number) => anniversary(anchor, k);
    player.read([paid("m", ann(0), ann(1))], ann(0) + HOUR);
    const late = player.read([paid("m", ann(3), ann(4))], ann(3) + HOUR);
    expect(late.pay.map(each => each.n)).toEqual([2, 3, 4]);
  });
  it("takes back a refunded month even when a new plan is bought soon after: only a switch carries on", () => {
    const player = fresh(), anchor = at(2026, 1, 5), ann = (k: number) => anniversary(anchor, k);
    player.read([paid("a", ann(0), ann(1))], ann(0) + HOUR);
    const refundAt = ann(0) + 3 * DAY, rebuy = refundAt + 2 * HOUR;
    const read = player.read([ended("a", ann(0), ann(1), refundAt), paid("b", rebuy, anniversary(rebuy, 1))], rebuy + HOUR);
    expect(read.refunds.map(each => each.refunds)).toEqual([`grant:${anchor}:1`]);
    expect(player.state!.months).toBe(0);
  });
  it("pays the Lifetime thank-you once, and only to the identity that first held the purchase", () => {
    expect(planGrant(null, [], {}, at(2026, 1, 1), () => [], { claim: { self: true, since: 1 } }).lifetime).toBe(4500);
    expect(planGrant(null, [], {}, at(2026, 1, 1), () => [], { claim: { self: false, since: 1 } }).lifetime).toBe(0);
    const done = planGrant(null, [], {}, at(2026, 1, 1), () => [], { claim: { self: true, since: 1 } }).state;
    expect(planGrant(done, [], {}, at(2026, 2, 1), () => [], { claim: { self: true, since: 1 } }).lifetime).toBe(0);
  });
});

describe("when the grant reads RevenueCat", () => {
  const now = at(2026, 6, 15);
  it("never for a player who never subscribed, and only when an instalment is due after that", () => {
    expect(grantDue(null, 0, now)).toBe(false);
    expect(grantDue(null, now - DAY, now)).toBe(false);
    expect(grantDue(null, now + DAY, now)).toBe(true);
    const live: GrantState = { ...emptyGrant(), anchor: at(2026, 6, 1), next: 1, live: true, renews: true, months: 1, subs: { m: { from: at(2026, 6, 1), through: at(2026, 7, 1), claimed_at: 1, held: false } } };
    expect(grantDue(live, at(2026, 7, 1), now)).toBe(false);
    expect(grantDue(live, at(2026, 7, 1), at(2026, 7, 1, 11))).toBe(true);
    // A cancelled plan stops after its paid period.
    expect(grantDue({ ...live, renews: false }, at(2026, 7, 1), at(2026, 7, 2))).toBe(false);
    expect(grantDue({ ...live, retry_at: at(2026, 7, 3) }, 0, at(2026, 7, 2))).toBe(false);
    expect(grantDue({ ...emptyGrant(), recheck_at: now }, 0, now)).toBe(true);
  });
  it("on the phone's word only within its bounds: once with no state, daily while it says Full Journey, ten minutes apart after a purchase", () => {
    expect(grantDue(null, 0, now, "none")).toBe(false);
    for (const hint of ["held", "bought", "legacy"] as const) expect(grantDue(null, 0, now, hint)).toBe(true);
    // What a read that found nothing saves.
    const looked: GrantState = { ...emptyGrant(), checked_at: now, retry_at: now + RETRY_MS };
    // A legacy app's one read is spent: its word, or none, never reads again.
    expect(grantDue(looked, 0, now + 30 * DAY, "legacy")).toBe(false);
    expect(grantDue(looked, 0, now + 30 * DAY, "none")).toBe(false);
    expect(grantDue(looked, 0, now + RETRY_MS - 1, "held")).toBe(false);
    expect(grantDue(looked, 0, now + RETRY_MS, "held")).toBe(true);
    expect(grantDue(looked, 0, now + BOUGHT_GAP_MS - 1, "bought")).toBe(false);
    expect(grantDue(looked, 0, now + BOUGHT_GAP_MS, "bought")).toBe(true);
    // A live anchor keeps its own dates: a purchase hint reads nothing before the next is due.
    const live: GrantState = { ...emptyGrant(), anchor: at(2026, 6, 1), next: 1, live: true, renews: false, months: 1, checked_at: at(2026, 6, 1), subs: { m: { from: at(2026, 6, 1), through: at(2026, 7, 1), claimed_at: 1, held: false } } };
    expect(grantDue(live, 0, now, "bought")).toBe(false);
    // A plan that said it would not renew, whose phone still says Full Journey past its date: worth a read.
    expect(grantDue(live, 0, at(2026, 7, 2))).toBe(false);
    expect(grantDue(live, 0, at(2026, 7, 2), "held")).toBe(true);
  });
  it("takes the phone's word from its header, and an app before the hint version as legacy", () => {
    const ask = (headers: Record<string, string>) => grantHint(new Request("https://grant.test/v1/pollen", { headers }));
    const newer = { [CLIENT_HEADER]: POLLEN_GRANT_HINT_MIN_VERSION + " play" };
    expect(ask({ ...newer })).toBe("none");
    expect(ask({ ...newer, [FULL_JOURNEY_HEADER]: "1" })).toBe("held");
    expect(ask({ ...newer, [FULL_JOURNEY_HEADER]: "bought" })).toBe("bought");
    expect(ask({ ...newer, [FULL_JOURNEY_HEADER]: "yes" })).toBe("none");
    expect(ask({ ...POLLEN_CLIENT })).toBe("legacy");
    // 0.7.8 shipped before the phone sent the header: without it, it still gets the legacy read.
    expect(ask({ [CLIENT_HEADER]: "0.7.8 play" })).toBe("legacy");
    expect(ask({})).toBe("legacy");
  });
});

describe("the grant's own RevenueCat status filter", () => {
  const store = { store: "play_store" as const, products: ["prodMonthly", "prodYearly"], environment: "production" };
  const item = (extra: Record<string, unknown> = {}) => ({ object: "subscription", id: "sub_1", product_id: "prodMonthly", store: "play_store", environment: "production", ownership: "purchased",
    status: "active", gives_access: true, current_period_starts_at: 1_000, current_period_ends_at: 2_000, ends_at: 2_000, auto_renewal_status: "will_renew", ...extra });
  it("pays only an active paid period, never a trial, grace or hold", () => {
    expect(grantSub(item(), store)).toMatchObject({ status: "paid", period_start: 1000, period_end: 2000, renews: true, access_until: 2000 });
    expect(grantSub(item({ status: "trialing" }), store)!.status).toBe("trial");
    expect(grantSub(item({ status: "in_grace_period" }), store)!.status).toBe("grace");
    for (const hold of ["in_billing_retry", "paused", "unknown", "incomplete"]) expect(grantSub(item({ status: hold, gives_access: false }), store)!.status).toBe("hold");
    expect(grantSub(item({ status: "active", gives_access: false }), store)!.status).toBe("hold");
    expect(grantSub(item({ status: "expired", gives_access: false }), store)).toMatchObject({ status: "ended", access_until: 0 });
    expect(grantSub(item({ auto_renewal_status: "will_not_renew" }), store)!.renews).toBe(false);
  });
  it("counts only the configured products in their store and environment, owned by purchase", () => {
    expect(grantSub(item({ ownership: "family_shared" }), store)).toBeNull();
    expect(grantSub(item({ product_id: "prodOther" }), store)).toBeNull();
    expect(grantSub(item({ store: "app_store" }), store)).toBeNull();
    expect(grantSub(item({ environment: "sandbox" }), store)).toBeNull();
    expect(grantSub(item({ id: "bad id with spaces" }), store)).toBeNull();
  });
  it("reads nothing while unconfigured and answers an incomplete or failed list as unavailable", async () => {
    const config = { REVENUECAT_SECRET_KEY: "synthetic-test-key", CONFIG: configJson({ revenuecat: { project_id: "proj1234", play_subscription_product_ids: ["prodMonthly"] } }) };
    const request = vi.fn(async () => ({ ok: true as const, status: 200, value: { object: "list", items: [item()], next_page: null } }));
    expect(await readGrant("P".repeat(22), { ...config, CONFIG: configJson({ revenuecat: { play_subscription_product_ids: ["prodMonthly"] } }) }, false, request)).toEqual({ ok: false, reason: "unconfigured" });
    expect(request).not.toHaveBeenCalled();
    expect(await readGrant("P".repeat(22), config, false, request)).toMatchObject({ ok: true, subs: [{ id: "sub_1", status: "paid" }], lifetime: null });
    expect(String((request.mock.calls[0] as unknown[])[0])).toContain("/subscriptions?environment=production&limit=100");
    const partial = vi.fn(async () => ({ ok: true as const, status: 200, value: { object: "list", items: [item()], next_page: "next" } }));
    expect(await readGrant("P".repeat(22), config, false, partial)).toEqual({ ok: false, reason: "provider_incomplete_list" });
    expect(await readGrant("P".repeat(22), config, false, async () => ({ ok: false, reason: "provider_http_500" }))).toEqual({ ok: false, reason: "provider_http_500" });
    expect(await readGrant("P".repeat(22), config, false, async () => ({ ok: true, status: 404, value: null }))).toEqual({ ok: true, subs: [], lifetime: null });
  });
  it("reads every player's sandbox subscriptions too, with one more list read made at once", async () => {
    const tester = "T".repeat(22);
    const config = (features: string[] = []) => ({ REVENUECAT_SECRET_KEY: "synthetic-test-key", CONFIG: configJson({ features, revenuecat: { project_id: "proj1234", play_subscription_product_ids: ["prodMonthly"],
      app_store_subscription_product_ids: ["prodIosMonthly"] } }) });
    const lists: Record<string, unknown[]> = { production: [item()], sandbox: [item({ id: "sub_test", environment: "sandbox" }), item({ id: "sub_ios", environment: "sandbox", store: "app_store", product_id: "prodIosMonthly" })] };
    const request = vi.fn(async (url: string) => ({ ok: true as const, status: 200, value: { object: "list", items: lists[new URL(url).searchParams.get("environment")!], next_page: null } }));
    const environments = () => request.mock.calls.map(([url]) => new URL(url).searchParams.get("environment"));
    expect(await readGrant(tester, config(), false, request)).toMatchObject({ ok: true, subs: [{ id: "sub_1" }, { id: "sub_test", status: "paid" }] });
    expect(environments()).toEqual(["production", "sandbox"]);
    // With the App Store check on, the same sandbox read serves both stores.
    request.mockClear();
    expect((await readGrant(tester, config(["APP_STORE_ENTITLEMENTS_ENABLED"]), false, request) as { subs: GrantSub[] }).subs.map(sub => sub.id)).toEqual(["sub_1", "sub_test", "sub_ios"]);
    expect(environments()).toEqual(["production", "sandbox"]);
    // A failed sandbox read pays nothing.
    expect(await readGrant(tester, config(), false, async url => new URL(url).searchParams.get("environment") === "sandbox" ? { ok: false, reason: "provider_http_500" } : request(url))).toEqual({ ok: false, reason: "provider_http_500" });
  });
});

describe("looking up a moved subscription", () => {
  const store = { store: "play_store", environment: "production", product_id: "prodMonthly", ownership: "purchased" };
  const config = { REVENUECAT_SECRET_KEY: "synthetic-test-key", CONFIG: configJson({ revenuecat: { project_id: "proj1234", play_subscription_product_ids: ["prodMonthly"] } }) };
  const item = (id: string, extra: Record<string, unknown> = {}) => ({ object: "subscription", id, customer_id: "holder_2", ...store, status: "expired", gives_access: false,
    current_period_starts_at: 1_000, current_period_ends_at: 9_000, ends_at: 3_000, starts_at: 1_000, auto_renewal_status: "will_not_renew", ...extra });
  it("reads each by id in one round, and an ended one's holder list, so a switch there is seen", async () => {
    const request = vi.fn(async (url: string) => {
      const path = new URL(url).pathname;
      if (path.endsWith("/subscriptions/sub_a")) return { ok: true as const, status: 200, value: item("sub_a") };
      if (path.endsWith("/subscriptions/sub_b")) return { ok: true as const, status: 200, value: item("sub_b", { status: "active", gives_access: true, ends_at: 9_000 }) };
      if (path.endsWith("/subscriptions/sub_c")) return { ok: true as const, status: 404, value: null };
      return { ok: true as const, status: 200, value: { object: "list", items: [item("sub_new", { status: "active", gives_access: true, starts_at: 3_000, current_period_starts_at: 3_000, ends_at: 99_000, current_period_ends_at: 99_000 })], next_page: null } };
    });
    const found = await lookupGrantSubs(["sub_a", "sub_b", "sub_c"], "P".repeat(22), config, request);
    expect(found).toMatchObject({ ok: true, found: [{ id: "sub_a", sub: { status: "ended", ends_at: 3_000 }, others: [{ id: "sub_new", started_at: 3_000 }] }, { id: "sub_b", sub: { status: "paid" }, others: [] }, { id: "sub_c", sub: null, others: [] }] });
    const paths = request.mock.calls.map(([url]) => new URL(url).pathname + new URL(url).search);
    expect(paths.filter(path => path.includes("/customers/"))).toEqual(["/v2/projects/proj1234/customers/holder_2/subscriptions?environment=production&limit=100"]);
    expect(paths.filter(path => !path.includes("/customers/")).sort()).toEqual(["/v2/projects/proj1234/subscriptions/sub_a", "/v2/projects/proj1234/subscriptions/sub_b", "/v2/projects/proj1234/subscriptions/sub_c"]);
    // One this player still holds is never treated as moved.
    expect(await lookupGrantSubs(["sub_a"], "holder_2", config, request)).toEqual({ ok: true, found: [{ id: "sub_a", sub: null, others: [], held: true }] });
    // One failed request takes nothing back.
    expect(await lookupGrantSubs(["sub_a"], "P".repeat(22), config, async url => url.includes("/customers/") ? { ok: false, reason: "provider_http_500" } : request(url))).toEqual({ ok: false, reason: "provider_http_500" });
  });
});

describe("a tester's fast test renewals", () => {
  it("pay one instalment a calendar month however often the test subscription renews or is bought again", () => {
    // A Play license tester's monthly plan renews every 5 minutes, up to 6 times, then expires.
    const player = fresh(), start = at(2026, 11, 2), FIVE = 5 * 60_000;
    let paidCount = 0;
    for (let renewal = 0; renewal <= 6; renewal++) {
      const from = start + renewal * FIVE;
      paidCount += player.read([paid("test_a", from, from + FIVE, { started_at: start })], from + 60_000).pay.length;
    }
    expect(paidCount).toBe(1);
    expect(player.ledger.map(each => each.key)).toEqual([`grant:${start}:1`]);
    // Expired, bought again the same day and the next week, renewing fast again: still nothing more this month.
    player.read([{ ...ended("test_a", start + 6 * FIVE, start + 7 * FIVE), started_at: start }], start + DAY);
    for (const [id, day] of [["test_b", 1], ["test_c", 8]] as const) {
      const from = start + day * DAY;
      for (let renewal = 0; renewal <= 6; renewal++)
        paidCount += player.read([ended("test_a", start + 6 * FIVE, start + 7 * FIVE, start + 7 * FIVE, start), paid(id, from + renewal * FIVE, from + (renewal + 1) * FIVE, { started_at: from })], from + renewal * FIVE + 60_000).pay.length;
    }
    expect(paidCount).toBe(1);
    // Once the month's due date passes with no cover, the anchor lapses; a new test buy after it pays the next step, once.
    const nextMonth = anniversary(start, 1) + DAY;
    player.read([ended("test_c", start + 8 * DAY, start + 8 * DAY + FIVE)], anniversary(start, 1) + HOUR);
    expect(player.state).toMatchObject({ live: false, months: 1 });
    for (let renewal = 0; renewal <= 6; renewal++)
      paidCount += player.read([paid("test_d", nextMonth + renewal * FIVE, nextMonth + (renewal + 1) * FIVE, { started_at: nextMonth })], nextMonth + renewal * FIVE + 60_000).pay.length;
    expect(paidCount).toBe(2);
    expect(player.ledger.map(each => [each.key, each.amount])).toEqual([[`grant:${start}:1`, instalmentAmount(1)], [`grant:${nextMonth}:1`, instalmentAmount(2)]]);
  });
});

// The settle step on a real Player's storage, with the provider and PollenClaims as mocks unless named.
let serial = 0;
const DUE = at(2026, 8, 3);
const monthly = (start = DUE - HOUR): GrantSub => paid("sub_settle", start, anniversary(start, 1));
async function inPlayer<T>(work: (storage: DurableObjectStorage) => Promise<T>): Promise<T> {
  return runInDurableObject(env.PLAYERS.getByName("grant-" + serial), async (_, state) => work(state.storage));
}
/** The test env with the Pollen secret PollenClaims derives its holder key from. */
const keyed = () => ({ ...env, POLLEN_SECRET: "synthetic-pollen-secret-for-tests-only-0001" }) as unknown as Env;
const self = async (keys: string[]) => Object.fromEntries(keys.map(key => [key, { self: true, since: DUE }]));

describe("settling the grant in the Player", () => {
  afterEach(async () => { await reset(); });
  it("never reads RevenueCat or writes anything for a player who never subscribed, on a phone that says nothing", async () => {
    serial++;
    await inPlayer(async storage => {
      const read = vi.fn<GrantDeps["read"]>();
      expect(await settleGrant(storage, DUE, () => true, { read, claim: self })).toBe("not_due");
      expect(read).not.toHaveBeenCalled();
      expect(storage.sql.exec("SELECT name FROM sqlite_master WHERE name LIKE 'pollen_%'").toArray()).toEqual([]);
    });
  });
  it("pays nothing during a provider outage, and the next read after the pause pays the month once", async () => {
    serial++;
    await inPlayer(async storage => {
      noteFullJourney(storage, DUE + 20 * DAY, DUE);
      const down: GrantDeps = { read: async () => ({ ok: false, reason: "provider_http_503" }), claim: self };
      expect(await settleGrant(storage, DUE, () => true, down)).toBe("unavailable");
      expect(walletView(storage, DUE).balance).toBe(0);
      expect(storedGrant(storage)).toBeNull();
      const up: GrantDeps = { read: async () => ({ ok: true, subs: [monthly()], lifetime: null }), claim: self };
      expect(await settleGrant(storage, DUE + 60_000, () => true, up)).toBe("paused");
      expect(await settleGrant(storage, DUE + OUTAGE_PAUSE_MS + 1, () => true, up)).toBe("settled");
      expect(walletView(storage, DUE + OUTAGE_PAUSE_MS + 1).balance).toBe(4500);
      // A claims outage pays nothing either.
      serial++;
    });
    await inPlayer(async storage => {
      noteFullJourney(storage, DUE + 20 * DAY, DUE);
      expect(await settleGrant(storage, DUE, () => true, { read: async () => ({ ok: true, subs: [monthly()], lifetime: null }), claim: async () => null })).toBe("unavailable");
      expect(walletView(storage, DUE).balance).toBe(0);
    });
  });
  it("looks up a moved subscription without asking PollenClaims about it, and takes its refunded month back once", async () => {
    serial++;
    await inPlayer(async storage => {
      noteFullJourney(storage, DUE + 20 * DAY, DUE);
      const sub = monthly();
      const claimed: string[] = [];
      const claim = async (keys: string[]) => { claimed.push(...keys); return self(keys); };
      expect(await settleGrant(storage, DUE, () => true, { read: async () => ({ ok: true, subs: [sub], lifetime: null }), claim })).toBe("settled");
      expect(walletView(storage, DUE).balance).toBe(4500);
      claimed.length = 0;
      // Moved away: the read at the next due date lists nothing and looks it up; still in its period (grace at the new
      // holder), it is kept and looked at again in a day.
      const lookup = vi.fn<NonNullable<GrantDeps["lookup"]>>(async (ids: string[]) => ({ ok: true, found: ids.map(id => ({ id, sub: { ...sub, status: "grace" }, others: [] })) }));
      const due = anniversary(sub.period_start, 1) + HOUR;
      const empty = async () => ({ ok: true as const, subs: [] as GrantSub[], lifetime: null });
      expect(await settleGrant(storage, due, () => true, { read: empty, claim, lookup })).toBe("settled");
      expect(lookup).toHaveBeenCalledWith(["sub_settle"]);
      expect(storedGrant(storage)!.recheck_at).toBe(due + RETRY_MS);
      expect(await settleGrant(storage, due + RETRY_MS - 1, () => true, { read: empty, claim, lookup })).toBe("not_due");
      // Refunded at its new holder: the month is taken back under its key, once.
      const refundAt = DUE + 5 * DAY;
      lookup.mockImplementation(async (ids: string[]) => ({ ok: true as const, found: ids.map(id => ({ id, sub: { ...sub, status: "ended" as const, ends_at: refundAt, renews: false, access_until: 0 }, others: [] as GrantSub[] })) }));
      expect(await settleGrant(storage, due + RETRY_MS, () => true, { read: empty, claim, lookup })).toBe("settled");
      expect(walletView(storage, due + RETRY_MS).balance).toBe(0);
      expect(ledgerLines(storage, "grantrefund").map(line => line.amount)).toEqual([-4500]);
      expect(claimed).toEqual([]);
      expect(storedGrant(storage)!.subs).toEqual({});
      lookup.mockClear();
      expect(await settleGrant(storage, due + 3 * RETRY_MS, () => true, { read: empty, claim, lookup }, "held")).toBe("settled");
      expect(lookup).not.toHaveBeenCalled();
    });
  });
  it("pays once when two reads overlap across the provider call", async () => {
    serial++;
    await inPlayer(async storage => {
      noteFullJourney(storage, DUE + 20 * DAY, DUE);
      let answer!: () => void;
      const gate = new Promise<void>(resolve => { answer = resolve; });
      const deps: GrantDeps = { read: async () => { await gate; return { ok: true, subs: [monthly()], lifetime: null }; }, claim: self };
      const both = Promise.all([settleGrant(storage, DUE, () => true, deps), settleGrant(storage, DUE, () => true, deps)]);
      answer();
      expect(await both).toEqual(["settled", "settled"]);
      expect(ledgerLines(storage, "grant").map(line => line.amount)).toEqual([4500]);
      expect(walletView(storage, DUE).balance).toBe(4500);
      expect(storedGrant(storage)!.months).toBe(1);
    });
  });
  it("starts a subscriber whose Full Journey end was never noted on a legacy app's read, once, and notes the end", async () => {
    serial++;
    await inPlayer(async storage => {
      const sub = monthly(DUE - 4 * DAY), read = vi.fn<GrantDeps["read"]>(async () => ({ ok: true, subs: [sub], lifetime: null }));
      expect(fullJourneyUntil(storage)).toBe(0);
      expect(await settleGrant(storage, DUE, () => true, { read, claim: self }, "legacy")).toBe("settled");
      expect(walletView(storage, DUE).balance).toBe(4500);
      expect(fullJourneyUntil(storage)).toBe(sub.access_until);
      expect(await settleGrant(storage, DUE + HOUR, () => true, { read, claim: self }, "legacy")).toBe("not_due");
      expect(await settleGrant(storage, DUE + 2 * DAY, () => true, { read, claim: self }, "held")).toBe("not_due");
      expect(read).toHaveBeenCalledTimes(1);
      expect(ledgerLines(storage, "grant").map(line => line.amount)).toEqual([4500]);
    });
  });
  it("reads a free player at most once ever on a legacy app, once a day while the phone says Full Journey, and ten minutes apart after a purchase", async () => {
    serial++;
    await inPlayer(async storage => {
      const read = vi.fn<GrantDeps["read"]>(async () => ({ ok: true, subs: [], lifetime: null })), deps = { read, claim: self };
      expect(await settleGrant(storage, DUE, () => true, deps, "legacy")).toBe("settled");
      for (const later of [HOUR, DAY, 40 * DAY]) expect(await settleGrant(storage, DUE + later, () => true, deps, "legacy")).toBe("not_due");
      expect(read).toHaveBeenCalledTimes(1);
      expect(storedGrant(storage)).toMatchObject({ live: false, latest: null, subs: {} });
      // Held: one more read a day after the last, whatever the phone sends in between.
      for (const later of [HOUR, 12 * HOUR, RETRY_MS - 1]) expect(await settleGrant(storage, DUE + later, () => true, deps, "held")).toBe("not_due");
      expect(await settleGrant(storage, DUE + RETRY_MS, () => true, deps, "held")).toBe("settled");
      expect(read).toHaveBeenCalledTimes(2);
      // Bought: not within ten minutes of the last read, then once.
      const last = DUE + RETRY_MS;
      expect(await settleGrant(storage, last + BOUGHT_GAP_MS - 1, () => true, deps, "bought")).toBe("not_due");
      expect(await settleGrant(storage, last + BOUGHT_GAP_MS, () => true, deps, "bought")).toBe("settled");
      expect(await settleGrant(storage, last + BOUGHT_GAP_MS + 60_000, () => true, deps, "bought")).toBe("not_due");
      expect(read).toHaveBeenCalledTimes(3);
      // A newer phone that says nothing never reads.
      expect(await settleGrant(storage, last + 30 * DAY, () => true, deps, "none")).toBe("not_due");
      expect(read).toHaveBeenCalledTimes(3);
    });
  });
  it("pays a purchase at once on the read right after it, though a read found nothing minutes before", async () => {
    serial++;
    await inPlayer(async storage => {
      let subs: GrantSub[] = [];
      const read = vi.fn<GrantDeps["read"]>(async () => ({ ok: true, subs, lifetime: null })), deps = { read, claim: self };
      expect(await settleGrant(storage, DUE - BOUGHT_GAP_MS, () => true, deps, "held")).toBe("settled");
      subs = [monthly(DUE - 60_000)];
      expect(await settleGrant(storage, DUE, () => true, deps, "bought")).toBe("settled");
      expect(walletView(storage, DUE).balance).toBe(4500);
      expect(storedGrant(storage)!.live).toBe(true);
      // Live now: another purchase word reads nothing before next month.
      expect(await settleGrant(storage, DUE + BOUGHT_GAP_MS * 2, () => true, deps, "bought")).toBe("not_due");
      expect(read).toHaveBeenCalledTimes(2);
    });
  });
  it("makes one provider read for a burst of hinted reads that overlap", async () => {
    serial++;
    await inPlayer(async storage => {
      let answer!: () => void;
      const gate = new Promise<void>(resolve => { answer = resolve; });
      const read = vi.fn<GrantDeps["read"]>(async () => { await gate; return { ok: true, subs: [monthly(DUE - 4 * DAY)], lifetime: null }; });
      const burst = Promise.all(Array.from({ length: 6 }, (_, n) => settleGrant(storage, DUE, () => true, { read, claim: self }, n % 2 ? "bought" : "held")));
      answer();
      expect(await burst).toEqual(Array(6).fill("settled"));
      expect(read).toHaveBeenCalledTimes(1);
      expect(walletView(storage, DUE).balance).toBe(4500);
    });
  });
  it("is refused by PollenClaims for a subscription another identity holds", async () => {
    const holder = "H".repeat(22), mover = "M".repeat(22), sub = monthly();
    const deps = (player: string): GrantDeps => ({ read: async () => ({ ok: true, subs: [sub], lifetime: null }), claim: keys => claimFor(keyed(), player, keys, DUE) });
    serial++;
    await inPlayer(async storage => { noteFullJourney(storage, DUE + 20 * DAY, DUE); await settleGrant(storage, DUE, () => true, deps(holder)); expect(walletView(storage, DUE).balance).toBe(4500); });
    serial++;
    await inPlayer(async storage => {
      noteFullJourney(storage, DUE + 20 * DAY, DUE);
      expect(await settleGrant(storage, DUE, () => true, deps(mover))).toBe("settled");
      expect(walletView(storage, DUE).balance).toBe(0);
      expect(storedGrant(storage)!.subs.sub_settle.from).toBe(anniversary(DUE, 1));
    });
    // Asked again (a retry after a lost save), the mover still gets a moved answer with the same time.
    const twice = [await claimFor(keyed(), mover, ["sub:sub_settle"], DUE + HOUR), await claimFor(keyed(), mover, ["sub:sub_settle"], DUE + 2 * HOUR)];
    expect(twice[0]).toEqual(twice[1]);
    expect(twice[0]!["sub:sub_settle"].self).toBe(false);
    // The holder record names nobody: only a keyed hash of the player id is kept.
    const rows = await runInDurableObject(env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT), async (_, state) => state.storage.sql.exec<{ holder: string }>("SELECT holder FROM pollen_claims_held").toArray());
    expect(rows).toHaveLength(1);
    expect(rows[0].holder).toMatch(/^[a-f0-9]{64}$/);
    expect(rows[0].holder).not.toContain(mover);
  });
});

// Through the Worker: GET /v1/pollen pays on auth's own Player call, with RevenueCat mocked.
type Account = { player_id: string; device_token: string; recovery_code: string };
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const VARS: Record<string, string> = {
  POLLEN_SECRET: SECRET, REVENUECAT_SECRET_KEY: "synthetic-revenuecat-key-for-tests",
  CONFIG: configJson({ features: ["POLLEN_EARN", "POLLEN_GRANT"], revenuecat: { project_id: "proj1234", play_subscription_product_ids: ["prodMonthly", "prodYearly"] } })
};
const shared = env as unknown as Record<string, unknown>;
let address = 0, offset = 0, items: unknown[] = [], providerCalls = 0;
const realNow = Date.now.bind(Date);
/** An app that sends the Full Journey hint (pollen/routes.ts grantHint); POLLEN_CLIENT is older, a legacy app. */
const HINT_CLIENT = { [CLIENT_HEADER]: POLLEN_GRANT_HINT_MIN_VERSION + " play" };
async function call(path: string, method = "GET", account?: Account, base: Env = env, extra: Record<string, string> = {}): Promise<Response> {
  const configured = Object.assign({ ...base }, VARS) as Env;
  return worker.fetch(new Request("https://grant.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.93." + (++address % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), [POLLEN_HEADER]: "1", ...POLLEN_CLIENT, ...extra }, body: method === "POST" ? "{}" : undefined }), configured);
}
const subscription = (start: number, months = 1, extra: Record<string, unknown> = {}) => ({ object: "subscription", id: "sub_worker_1", product_id: months === 12 ? "prodYearly" : "prodMonthly", store: "play_store",
  environment: "production", ownership: "purchased", status: "active", gives_access: true, current_period_starts_at: start, current_period_ends_at: anniversary(start, months), ends_at: anniversary(start, months), auto_renewal_status: "will_renew", ...extra });

describe("the grant through the wallet read", () => {
  beforeEach(() => {
    Object.assign(shared, VARS);
    offset = 0; items = []; providerCalls = 0;
    vi.spyOn(Date, "now").mockImplementation(() => realNow() + offset);
    vi.spyOn(globalThis, "fetch").mockImplementation(async input => {
      const url = String(input instanceof Request ? input.url : input);
      if (!url.startsWith("https://api.revenuecat.com/")) throw new Error("unexpected fetch");
      // A read is the production and sandbox lists made at once (grant-provider.ts readGrant): counted once, by its production list.
      if (!url.includes("environment=sandbox")) providerCalls++;
      return url.includes("/subscriptions?") ? Response.json({ object: "list", items, next_page: null }) : new Response(null, { status: 404 });
    });
  });
  afterEach(async () => { for (const key of Object.keys(VARS)) delete shared[key]; vi.restoreAllMocks(); await reset(); });
  const create = async (): Promise<Account> => { const made = await call("/v1/identity", "POST"); expect(made.status).toBe(201); return made.json<Account>(); };
  const subscribe = (account: Account, until: number) => runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => noteFullJourney(state.storage, until, Date.now()));
  type Wallet = { balance: number; grant?: { months: number; next: number; top: number; latest?: { key: string; amount: number } } };

  it("is on only with POLLEN_GRANT and earning, and tells a phone that asks", async () => {
    const features = (...names: string[]) => configJson({ features: names });
    expect(grantOn({ CONFIG: features("POLLEN_EARN", "POLLEN_GRANT"), POLLEN_SECRET: SECRET })).toBe(true);
    expect(grantOn({ CONFIG: features("POLLEN_GRANT"), POLLEN_SECRET: SECRET })).toBe(false);
    expect(grantOn({ CONFIG: features("POLLEN_EARN"), POLLEN_SECRET: SECRET })).toBe(false);
    const player = await create();
    expect(await (await call("/v2/capabilities", "GET", player)).json()).toMatchObject({ pollen_version: 1, pollen_grant_version: 1 });
  });
  it("pays an instalment on auth's own Player call: one PollenClaims request a month, writing only for a new subscription", async () => {
    const player = await create(), start = Date.now() - HOUR;
    items = [subscription(start)];
    await subscribe(player, anniversary(start, 1));
    const meter = countingEnv({ ...env, ...VARS } as unknown as Env);
    const stubs = { player: env.PLAYERS.getByName(player.player_id), claims: env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT) };
    const first = await meterRows(stubs, async () => (await call("/v1/pollen", "GET", player, meter.env)).json<Wallet>());
    expect(meter.calls).toEqual(["PLAYERS.authorizeWallet"]);
    expect(providerCalls).toBe(1);
    expect(first.value).toMatchObject({ balance: 4500, grant: { months: 1, next: 4750, top: 12000, latest: { amount: 4500 } } });
    // Next read the same month: a date check only.
    const again = await meterRows(stubs, async () => (await call("/v1/pollen", "GET", player)).json<Wallet>());
    expect(providerCalls).toBe(1);
    expect(again.rows.player.written + again.rows.claims.written + again.rows.claims.read).toBe(0);
    // A month on, renewed: one provider read and one PollenClaims read that writes nothing.
    offset = anniversary(start, 1) - start + HOUR;
    items = [subscription(anniversary(start, 1))];
    const month = await meterRows(stubs, async () => (await call("/v1/pollen", "GET", player)).json<Wallet>());
    expect(month.value).toMatchObject({ balance: 4500 + 4750, grant: { months: 2, next: 5000 } });
    expect(providerCalls).toBe(2);
    expect(month.rows.claims.written).toBe(0);
    expect(month.rows.claims.read).toBeGreaterThan(0);
    console.log("grant rows", JSON.stringify({ first: first.rows, again: again.rows, month: month.rows }));
    // First: claim row, wallet row, grant row (plus the tables); PollenClaims: one holder row.
    expect(first.rows.claims.written).toBeGreaterThanOrEqual(1);
    expect(month.rows.player.written).toBeLessThanOrEqual(4);
  });
  it("costs a free player's wallet read from a newer app that says nothing no provider call and no write", async () => {
    const player = await create();
    const meter = countingEnv({ ...env, ...VARS } as unknown as Env);
    const read = await meterRows({ player: env.PLAYERS.getByName(player.player_id) }, async () => (await call("/v1/pollen", "GET", player, meter.env, HINT_CLIENT)).json<Wallet>());
    expect(meter.calls).toEqual(["PLAYERS.authorizeWallet"]);
    expect(providerCalls).toBe(0);
    expect(read.rows.player.written).toBe(0);
    expect(read.value).not.toHaveProperty("grant");
  });
  it("costs a free player on a legacy app one provider read and one grant row (with its table), once ever", async () => {
    const player = await create();
    const meter = countingEnv({ ...env, ...VARS } as unknown as Env), stubs = { player: env.PLAYERS.getByName(player.player_id) };
    const first = await meterRows(stubs, async () => (await call("/v1/pollen", "GET", player, meter.env)).json<Wallet>());
    expect(meter.calls).toEqual(["PLAYERS.authorizeWallet"]);
    expect(providerCalls).toBe(1);
    expect(first.value).not.toHaveProperty("grant");
    expect(first.rows.player.written).toBeLessThanOrEqual(3);
    for (const later of [HOUR, 2 * DAY, 40 * DAY]) {
      offset = later;
      const again = await meterRows(stubs, async () => (await call("/v1/pollen", "GET", player)).json<Wallet>());
      expect(again.rows.player.written).toBe(0);
    }
    expect(providerCalls).toBe(1);
  });
  it("pays a subscriber whose Full Journey end was never noted on their next wallet read, from a legacy app or a hinting one", async () => {
    const cases = [{}, { ...HINT_CLIENT, [FULL_JOURNEY_HEADER]: "1" }, { ...HINT_CLIENT, [FULL_JOURNEY_HEADER]: "bought" }];
    for (const [n, extra] of cases.entries()) {
      providerCalls = 0;
      const player = await create(), start = Date.now() - 4 * DAY;
      // Each its own subscription: PollenClaims would see one id on three identities as moved.
      items = [subscription(start, 1, { id: "sub_start_" + n })];
      const first = await (await call("/v1/pollen", "GET", player, env, extra)).json<Wallet>();
      expect(first).toMatchObject({ balance: 4500, grant: { months: 1, next: 4750, latest: { amount: 4500 } } });
      expect(providerCalls).toBe(1);
      for (let n = 0; n < 3; n++) expect((await (await call("/v1/pollen", "GET", player, env, extra)).json<Wallet>()).balance).toBe(4500);
      expect(providerCalls).toBe(1);
    }
  });
  it("lets a just-bought hint start a provider read at most three times a day", async () => {
    const player = await create(), bought = { ...HINT_CLIENT, [FULL_JOURNEY_HEADER]: "bought" };
    items = [];
    // The first read of a player with no grant state is the hint's own; then one read per BOUGHT_GAP_MS, three a day.
    for (let n = 0; n < 6; n++) { offset = n * BOUGHT_GAP_MS; await call("/v1/pollen", "GET", player, env, bought); }
    expect(providerCalls).toBe(4);
  });
  it("pays a trial nothing through the read, and reads again only when the trial ends", async () => {
    const player = await create(), start = Date.now() - HOUR;
    items = [subscription(start, 1, { status: "trialing", current_period_ends_at: start + 7 * DAY, ends_at: start + 7 * DAY })];
    await subscribe(player, start + 7 * DAY);
    expect((await (await call("/v1/pollen", "GET", player)).json<Wallet>()).balance).toBe(0);
    await call("/v1/pollen", "GET", player);
    expect(providerCalls).toBe(1);
    offset = 7 * DAY;
    items = [subscription(start + 7 * DAY)];
    expect((await (await call("/v1/pollen", "GET", player)).json<Wallet>()).balance).toBe(4500);
    expect(providerCalls).toBe(2);
  });
  it("erases the grant with the account", async () => {
    const player = await create(), start = Date.now() - HOUR;
    items = [subscription(start)];
    await subscribe(player, anniversary(start, 1));
    await call("/v1/pollen", "GET", player);
    const deleted = await call("/v1/identity", "DELETE", player);
    expect(deleted.status).toBe(200);
    const left = await runInDurableObject(env.PLAYERS.getByName(player.player_id), async (_, state) => state.storage.sql.exec("SELECT name FROM sqlite_master WHERE name LIKE 'pollen_%'").toArray());
    expect(left).toEqual([]);
  });
});
