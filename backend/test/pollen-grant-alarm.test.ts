import { env } from "cloudflare:workers";
import { reset, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { anniversary, emptyGrant, grantDue, type GrantState } from "../src/pollen/grant";
import { GIVE_UP_MS, LATE_MAX_MS, LATE_MIN_MS, SETTLE_MS, grantAlarmAt, grantWake } from "../src/pollen/grant-alarm";
import { storedGrant } from "../src/pollen/grant-settle";
import { POLLEN_CLAIMS_OBJECT } from "../src/pollen/claims";
import { ledgerLines, noteFullJourney, walletView } from "../src/pollen/wallet";
import { POLLEN_HEADER } from "../src/pollen/routes";
import { presenceAlarmOwned, schedulePresence } from "../src/presence";
import { forgetFcmAccess, makePollenHint, pollenPushBody, validPollenHint } from "../src/notifications";
import { countingEnv, meterRows } from "./meter";
import { POLLEN_CLIENT, configJson } from "./config";

// The monthly grant's own alarm (pollen/grant-alarm.ts) and its push (pollen/grant-push.ts): the Player wakes on the
// instalment's date, pays it once whatever else reads, stops for a cancelled plan, and tells only opted-in phones.
// RevenueCat and FCM are mocks; synthetic identities, tokens and subscription ids only.
const DAY = 86_400_000, HOUR = 3_600_000;

describe("when the grant wakes the Player", () => {
  const anchor = Date.UTC(2026, 0, 31, 10);
  const live = (extra: Partial<GrantState> = {}): GrantState => ({ ...emptyGrant(), months: 1, anchor, next: 1, live: true, renews: true, checked_at: anchor, ...extra });
  it("wakes a live anchor once its instalment is due, a settle margin after the anniversary", () => {
    const due = anniversary(anchor, 1);
    expect(grantWake(live(), 0, anchor + HOUR)).toEqual({ at: due + SETTLE_MS, run: false });
    expect(grantWake(live(), 0, due + SETTLE_MS)).toEqual({ at: due + SETTLE_MS, run: true });
    expect(grantAlarmAt(live(), 0, anchor + HOUR)).toBe(due + SETTLE_MS);
    // From the 31st: the last day of February, counted from the anchor.
    expect(new Date(due).toISOString().slice(0, 10)).toBe("2026-02-28");
  });
  it("never wakes a player with no live anchor, nor a plan that will not renew once its cover ran out", () => {
    expect(grantWake(null, 0, anchor)).toBeNull();
    expect(grantWake({ ...emptyGrant(), checked_at: anchor, retry_at: anchor + DAY }, anchor + 30 * DAY, anchor)).toBeNull();
    expect(grantWake(live({ live: false, lapsed_at: anchor }), 0, anchor)).toBeNull();
    // Cancelled: no renewal and nothing noted past the due date. It stays live in storage, so this is what stops it.
    const cancelled = live({ renews: false, subs: { s: { from: anchor, through: anniversary(anchor, 1), claimed_at: anchor, held: false } } });
    expect(grantWake(cancelled, anniversary(anchor, 1), anchor + HOUR)).toBeNull();
    expect(grantAlarmAt(cancelled, anniversary(anchor, 1), anniversary(anchor, 1) + DAY)).toBeNull();
  });
  it("only ever names a later time at which the read would really ask RevenueCat", () => {
    const states = [live(), live({ renews: false }), live({ checked_at: anniversary(anchor, 1) + 3 * HOUR }), live({ retry_at: anniversary(anchor, 1) + 2 * DAY }),
      live({ renews: false, subs: { s: { from: anchor, through: anniversary(anchor, 1) + DAY, claimed_at: anchor, held: false } } })];
    for (const state of states) for (const fj of [0, anniversary(anchor, 1), anniversary(anchor, 2)]) for (let now = anchor; now < anniversary(anchor, 1) + 70 * DAY; now += 7 * HOUR) {
      const at = grantAlarmAt(state, fj, now);
      if (at === null) continue;
      expect(at).toBeGreaterThan(now);
      expect(grantDue(state, fj, at)).toBe(true);
    }
  });
  it("waits longer after each late read: an hour, two, four, then daily, and stops after the store's longest retry", () => {
    const due = anniversary(anchor, 1);
    // A read on the due date that paid nothing (a renewal not listed yet).
    expect(grantWake(live({ checked_at: due + SETTLE_MS }), 0, due + SETTLE_MS)).toEqual({ at: due + SETTLE_MS + LATE_MIN_MS, run: false });
    expect(grantWake(live({ checked_at: due + 2 * HOUR }), 0, due + 2 * HOUR)!.at).toBe(due + 4 * HOUR);
    expect(grantWake(live({ checked_at: due + 4 * HOUR }), 0, due + 4 * HOUR)!.at).toBe(due + 8 * HOUR);
    expect(grantWake(live({ checked_at: due + 3 * DAY }), 0, due + 3 * DAY)!.at).toBe(due + 3 * DAY + LATE_MAX_MS);
    // A failed read writes nothing: the next wake counts from the wake itself, never at once again.
    expect(grantAlarmAt(live(), 0, due + SETTLE_MS)).toBe(due + SETTLE_MS + LATE_MIN_MS);
    expect(grantAlarmAt(live(), 0, due + 10 * DAY)).toBe(due + 11 * DAY);
    expect(grantAlarmAt(live(), 0, due + GIVE_UP_MS)).toBeNull();
    expect(grantWake(live({ checked_at: due + GIVE_UP_MS + HOUR }), 0, due + GIVE_UP_MS + 2 * HOUR)).toBeNull();
    // A wake that only came late (nothing read since the due date) still runs, and catches up.
    expect(grantWake(live(), 0, due + 90 * DAY)).toEqual({ at: due + SETTLE_MS, run: true });
  });
});

describe("the monthly Pollen push message", () => {
  it("carries an opaque id, the amount and nothing about the player, with the apps' words", async () => {
    const hint = (await makePollenHint(`grant:${Date.UTC(2026, 0, 31, 10)}:2`, 4750))!;
    expect(validPollenHint(hint)).toBe(true);
    expect(Object.keys(hint)).toEqual(["schema_version", "event_id", "kind", "amount"]);
    expect(hint.event_id).toMatch(/^pollen_[a-f0-9]{32}$/);
    expect(hint.event_id).not.toContain(String(Date.UTC(2026, 0, 31, 10)));
    expect(hint.amount).toBe("4750");
    expect(await makePollenHint("grant:1:1", 0)).toBeNull();
    expect(pollenPushBody("4500")).toBe("+4,500 Pollen from Full Journey");
    expect(pollenPushBody("15000")).toBe("+15,000 Pollen from Full Journey");
    expect(pollenPushBody("576000")).toBe("+576,000 Pollen from Full Journey");
    expect(pollenPushBody("750")).toBe("+750 Pollen from Full Journey");
    for (const bad of [{ ...hint, amount: "0" }, { ...hint, amount: "04750" }, { ...hint, amount: "12345678" }, { ...hint, event_id: "pollen_xyz" }, { ...hint, room_id: "r".repeat(22) }]) expect(validPollenHint(bad)).toBe(false);
  });
});

// Through the Worker and the Player's real alarm.
type Account = { player_id: string; device_token: string; recovery_code: string };
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const FEATURES = ["POLLEN_EARN", "POLLEN_GRANT", "POLLEN_GRANT_ALARM", "NOTIFICATIONS_ENABLED", "IOS_PUSH_ENABLED"];
const REVENUECAT = { project_id: "proj1234", play_subscription_product_ids: ["prodMonthly"] };
let VARS: Record<string, string> = {};
const shared = env as unknown as Record<string, unknown>;
let address = 0, serial = 0, clock = 0, subId = "", items: unknown[] | null = [], providerCalls = 0, gate: Promise<void> | null = null;
let pushes: Record<string, unknown>[] = [];
const realNow = Date.now.bind(Date);
const start = () => clock;
beforeAll(async () => {
  const keys = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const exported = await crypto.subtle.exportKey("pkcs8", keys.privateKey) as ArrayBuffer;
  let raw = ""; for (const byte of new Uint8Array(exported)) raw += String.fromCharCode(byte);
  VARS = {
    POLLEN_SECRET: SECRET, REVENUECAT_SECRET_KEY: "synthetic-revenuecat-key-for-tests",
    FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({ project_id: "afteryou-synthetic", client_email: "test@afteryou-synthetic.iam.gserviceaccount.com", private_key: `-----BEGIN PRIVATE KEY-----\n${btoa(raw)}\n-----END PRIVATE KEY-----\n` }),
    CONFIG: configJson({ features: FEATURES, revenuecat: REVENUECAT })
  };
});
beforeEach(() => {
  Object.assign(shared, VARS);
  // A fixed clock, kept ahead of the real one: workerd's own alarms run on the real clock, and every wake set here stays in its future.
  clock = realNow() + HOUR; subId = "sub_alarm_" + ++serial; items = []; providerCalls = 0; pushes = []; gate = null;
  vi.spyOn(Date, "now").mockImplementation(() => clock);
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url === "https://oauth2.googleapis.com/token") return Response.json({ access_token: "synthetic-oauth-access-token", expires_in: 3600 });
    if (url.startsWith("https://fcm.googleapis.com/")) { pushes.push(JSON.parse(String(init?.body)).message); return Response.json({ name: "projects/afteryou-synthetic/messages/synthetic" }); }
    if (!url.startsWith("https://api.revenuecat.com/")) throw new Error("unexpected fetch");
    providerCalls++;
    if (gate) await gate;
    if (items === null) return new Response(null, { status: 503 });
    return url.includes("/subscriptions?") ? Response.json({ object: "list", items, next_page: null }) : new Response(null, { status: 404 });
  });
});
afterEach(async () => { for (const key of Object.keys(VARS)) delete shared[key]; forgetFcmAccess(); vi.restoreAllMocks(); await reset(); });

async function call(path: string, method = "GET", account?: Account, body?: unknown, extra: Record<string, string> = {}, base: Env = env): Promise<Response> {
  const configured = Object.assign({ ...base }, VARS) as Env;
  return worker.fetch(new Request("https://grant.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.94." + (++address % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), [POLLEN_HEADER]: "1", ...POLLEN_CLIENT, ...extra },
    body: body === undefined ? (method === "POST" ? "{}" : undefined) : JSON.stringify(body) }), configured);
}
const create = async (): Promise<Account> => { const made = await call("/v1/identity", "POST"); expect(made.status).toBe(201); return made.json<Account>(); };
const player = (account: Account) => env.PLAYERS.getByName(account.player_id);
const subscribe = (account: Account, until: number) => runInDurableObject(player(account), async (_, state) => noteFullJourney(state.storage, until, Date.now()));
const subscription = (periodStart: number, extra: Record<string, unknown> = {}) => ({ object: "subscription", id: subId, product_id: "prodMonthly", store: "play_store",
  environment: "production", ownership: "purchased", status: "active", gives_access: true, current_period_starts_at: periodStart, current_period_ends_at: anniversary(periodStart, 1),
  ends_at: anniversary(periodStart, 1), auto_renewal_status: "will_renew", starts_at: periodStart, ...extra });
const wallet = async (account: Account) => (await (await call("/v1/pollen", "GET", account)).json<{ balance: number }>()).balance;
const alarmOf = (account: Account) => runInDurableObject(player(account), async (_, state) => ({ alarm: await state.storage.getAlarm(),
  marker: state.storage.sql.exec<{ due_at: number }>("SELECT due_at FROM presence_alarm WHERE id=1").toArray()[0]?.due_at ?? null }));
const register = (account: Account, binding: string, token: string, extra: Record<string, string> = {}) =>
  call("/v1/notifications/registration", "POST", account, { schema_version: 1, token, binding_epoch: binding }, extra);
/** A subscriber paid their first month by a wallet read at `first`, with the alarm set for the next one. */
async function subscriber(extra: Record<string, unknown> = {}) {
  const account = await create(), first = start() - HOUR;
  // Each its own subscription: PollenClaims would see one id on two identities as moved.
  subId = "sub_alarm_" + ++serial;
  items = [subscription(first, extra)];
  await subscribe(account, anniversary(first, 1));
  expect(await wallet(account)).toBe(4500);
  return { account, first };
}
const at = (time: number) => { clock = time; };
const pollenPushes = () => pushes.filter(message => (message.data as { kind?: string }).kind === "pollen_monthly");

describe("the grant's alarm in the Player", () => {
  it("is set to the next instalment's date by the read that paid, and the marker agrees", async () => {
    const { account, first } = await subscriber();
    expect(await alarmOf(account)).toEqual({ alarm: anniversary(first, 1) + SETTLE_MS, marker: anniversary(first, 1) + SETTLE_MS });
    // A read that settles nothing new writes nothing and leaves it.
    const meter = await meterRows({ player: player(account) }, () => wallet(account));
    expect(meter.rows.player.written).toBe(0);
  });
  it("pays on the date as the wallet read would, once, sets the next month and tells the opted-in phones only", async () => {
    const { account, first } = await subscriber();
    expect((await register(account, "a".repeat(22), "synthetic-android-token-0001")).status).toBe(200);
    expect((await register(account, "b".repeat(22), "synthetic-iphone-turns-0001", { "X-AfterYou-Platform": "ios", "X-AfterYou-Push-Categories": "turns" })).status).toBe(200);
    expect((await register(account, "c".repeat(22), "synthetic-iphone-hosting-01", { "X-AfterYou-Platform": "ios", "X-AfterYou-Push-Categories": "hosting" })).status).toBe(200);
    at(anniversary(first, 1) + SETTLE_MS);
    items = [subscription(anniversary(first, 1))];
    const calls = providerCalls;
    const stubs = { player: player(account), claims: env.POLLEN_CLAIMS.getByName(POLLEN_CLAIMS_OBJECT) };
    const run = await meterRows(stubs, () => runDurableObjectAlarm(player(account)));
    expect(run.value).toBe(true);
    expect(providerCalls - calls).toBe(1);
    expect(await runInDurableObject(player(account), async (_, state) => walletView(state.storage, Date.now()).balance)).toBe(4500 + 4750);
    expect(await alarmOf(account)).toEqual({ alarm: anniversary(first, 2) + SETTLE_MS, marker: anniversary(first, 2) + SETTLE_MS });
    console.log("grant alarm rows", JSON.stringify(run.rows));
    // Ledger line, wallet, grant state and the alarm marker; PollenClaims reads its holder row and writes nothing.
    expect(run.rows.player.written).toBeLessThanOrEqual(5);
    expect(run.rows.claims.written).toBe(0);
    const sent = pollenPushes();
    expect(sent.map(message => message.token).sort()).toEqual(["synthetic-android-token-0001", "synthetic-iphone-turns-0001"]);
    for (const message of sent) {
      const data = message.data as Record<string, string>;
      expect(Object.keys(data).sort()).toEqual(["amount", "binding_epoch", "event_id", "kind", "schema_version"]);
      expect(data.amount).toBe("4750");
      expect(data.event_id).toMatch(/^pollen_[a-f0-9]{32}$/);
    }
    const iphone = sent.find(message => message.token === "synthetic-iphone-turns-0001")!;
    expect((iphone.apns as { payload: { aps: { alert: unknown; "thread-id": string } } }).payload.aps).toMatchObject({ alert: { title: "Your monthly Pollen is here", body: "+4,750 Pollen from Full Journey" }, "thread-id": "after_you_pollen" });
    expect(sent.find(message => message.token === "synthetic-android-token-0001")!.apns).toBeUndefined();
    // The app opening right after: a date check only, no second payment and no push.
    expect(await wallet(account)).toBe(4500 + 4750);
    expect(providerCalls - calls).toBe(1);
    expect(pollenPushes()).toHaveLength(2);
  });
  for (const first of ["alarm", "wallet"] as const) it(`pays once when the alarm and a wallet read overlap, the ${first} first`, async () => {
    const { account, first: began } = await subscriber();
    await register(account, "a".repeat(22), "synthetic-android-token-0002");
    at(anniversary(began, 1) + SETTLE_MS);
    items = [subscription(anniversary(began, 1))];
    let open!: () => void;
    gate = new Promise<void>(resolve => { open = resolve; });
    const calls = providerCalls;
    const alarm = () => runDurableObjectAlarm(player(account)), read = () => wallet(account);
    // The second starts only once the first is inside its RevenueCat read.
    const opened = first === "alarm" ? alarm() : read();
    while (providerCalls === calls) await new Promise(resolve => setTimeout(resolve, 5));
    const joined = first === "alarm" ? read() : alarm();
    await new Promise(resolve => setTimeout(resolve, 50));
    open();
    await Promise.all([opened, joined]);
    expect(providerCalls - calls).toBe(1);
    const lines = await runInDurableObject(player(account), async (_, state) => ledgerLines(state.storage, "grant:").map(line => line.amount));
    expect(lines).toEqual([4500, 4750]);
    expect(await wallet(account)).toBe(4500 + 4750);
    expect(await alarmOf(account)).toMatchObject({ alarm: anniversary(began, 2) + SETTLE_MS });
    // The alarm's own settle tells the phone; one that joined the open app's read leaves it to the Home card.
    expect(pollenPushes().length).toBe(first === "alarm" ? 1 : 0);
  });
  it("catches up the months it missed after downtime, at their own steps, with one push for the total", async () => {
    const { account, first } = await subscriber();
    // Nothing woke for three months; the plan kept renewing on its anniversaries.
    at(anniversary(first, 3) + HOUR);
    // A phone registers again each time the app opens; one silent for POLLEN_PUSH_REACH_MS (two months) gets no push.
    await register(account, "a".repeat(22), "synthetic-android-token-0003");
    items = [subscription(anniversary(first, 3), { starts_at: first })];
    expect(await runDurableObjectAlarm(player(account))).toBe(true);
    expect(await runInDurableObject(player(account), async (_, state) => ledgerLines(state.storage, "grant:").map(line => line.amount))).toEqual([4500, 4750, 5000, 5250]);
    const sent = pollenPushes();
    expect(sent).toHaveLength(1);
    expect((sent[0].data as Record<string, string>).amount).toBe(String(4750 + 5000 + 5250));
    expect(await alarmOf(account)).toMatchObject({ alarm: anniversary(first, 4) + SETTLE_MS });
  });
  it("stops for a cancelled plan: no alarm once its cover ran out, and none after a read finds it ended", async () => {
    // Cancelled before the first month ended: the read that paid sets no wake, since no read is due again.
    const cancelled = await subscriber({ auto_renewal_status: "will_not_renew" });
    expect(await alarmOf(cancelled.account)).toEqual({ alarm: null, marker: null });
    // Renewing when paid, then it ended at the anniversary: the wake reads once, the anchor lapses and the alarm goes.
    const { account, first } = await subscriber();
    await register(account, "a".repeat(22), "synthetic-android-token-0004");
    at(anniversary(first, 1) + SETTLE_MS);
    items = [subscription(first, { status: "expired", gives_access: false, ends_at: anniversary(first, 1) })];
    const calls = providerCalls;
    expect(await runDurableObjectAlarm(player(account))).toBe(true);
    expect(providerCalls - calls).toBe(1);
    expect(await runInDurableObject(player(account), async (_, state) => storedGrant(state.storage)!.live)).toBe(false);
    expect(await alarmOf(account)).toEqual({ alarm: null, marker: null });
    expect(pollenPushes()).toEqual([]);
    // Nothing wakes it again, whatever the clock says.
    at(anniversary(first, 3));
    expect(await runDurableObjectAlarm(player(account))).toBe(false);
  });
  it("sends no push when the wake paid nothing, and looks again an hour on, never at once", async () => {
    const { account, first } = await subscriber();
    await register(account, "a".repeat(22), "synthetic-android-token-0005");
    // The renewal is not listed yet: the old period still ends on the due date.
    at(anniversary(first, 1) + SETTLE_MS);
    expect(await runDurableObjectAlarm(player(account))).toBe(true);
    expect(pollenPushes()).toEqual([]);
    expect(await alarmOf(account)).toMatchObject({ alarm: anniversary(first, 1) + SETTLE_MS + LATE_MIN_MS });
    // RevenueCat down an hour later: nothing written, the next wake is as long after this one as it is late.
    const outage = anniversary(first, 1) + SETTLE_MS + LATE_MIN_MS;
    at(outage);
    items = null;
    expect(await runDurableObjectAlarm(player(account))).toBe(true);
    expect((await alarmOf(account)).alarm).toBe(outage + SETTLE_MS + LATE_MIN_MS);
    expect(pollenPushes()).toEqual([]);
    // Listed at last: paid, told, and on to next month.
    at(outage + SETTLE_MS + LATE_MIN_MS);
    items = [subscription(anniversary(first, 1))];
    expect(await runDurableObjectAlarm(player(account))).toBe(true);
    expect(pollenPushes()).toHaveLength(1);
    expect((await alarmOf(account)).alarm).toBe(anniversary(first, 2) + SETTLE_MS);
  });
  it("never wakes a free player, and sets nothing with POLLEN_GRANT_ALARM off", async () => {
    const free = await create();
    await wallet(free);
    expect(await alarmOf(free)).toEqual({ alarm: null, marker: null });
    shared.CONFIG = configJson({ features: FEATURES.filter(name => name !== "POLLEN_GRANT_ALARM"), revenuecat: REVENUECAT });
    const { account, first } = await subscriber();
    expect(await alarmOf(account)).toEqual({ alarm: null, marker: null });
    // An alarm set before the flag went off wakes once, settles nothing and clears itself.
    await runInDurableObject(player(account), async (_, state) => { state.storage.sql.exec("INSERT OR REPLACE INTO presence_alarm VALUES (1,?)", anniversary(first, 1) + SETTLE_MS); await state.storage.setAlarm(anniversary(first, 1) + SETTLE_MS); });
    at(anniversary(first, 1) + SETTLE_MS);
    items = [subscription(anniversary(first, 1))];
    const calls = providerCalls;
    expect(await runDurableObjectAlarm(player(account))).toBe(true);
    expect(providerCalls).toBe(calls);
    expect(await alarmOf(account)).toEqual({ alarm: null, marker: null });
  });
  it("costs the wake one Player alarm, one RevenueCat read and one PollenClaims request", async () => {
    const { account, first } = await subscriber();
    at(anniversary(first, 1) + SETTLE_MS);
    items = [subscription(anniversary(first, 1))];
    // The Player reaches PollenClaims through its own binding: count that binding's calls while the alarm runs.
    const meter = countingEnv({ ...env, ...VARS } as unknown as Env), calls = providerCalls, binding = shared.POLLEN_CLAIMS;
    shared.POLLEN_CLAIMS = meter.env.POLLEN_CLAIMS;
    try { expect(await runDurableObjectAlarm(player(account))).toBe(true); }
    finally { shared.POLLEN_CLAIMS = binding; }
    expect(meter.calls).toEqual(["POLLEN_CLAIMS.claim"]);
    expect(providerCalls - calls).toBe(1);
  });
});

describe("the one alarm shared with presence", () => {
  it("keeps the grant's wake under presence leases, and gets it back when the phone goes offline", async () => {
    const { account, first } = await subscriber();
    const grantAt = anniversary(first, 1) + SETTLE_MS;
    expect((await call("/v1/presence", "POST", account, { schema_version: 1, session_id: "a".repeat(36), online: true })).status).toBe(200);
    const leased = await alarmOf(account);
    expect(leased.alarm).toBeLessThan(grantAt);
    expect(leased.alarm).toBe(leased.marker);
    // A presence wake before the grant's date settles nothing.
    const calls = providerCalls;
    expect(await runDurableObjectAlarm(player(account))).toBe(true);
    expect(providerCalls).toBe(calls);
    expect((await call("/v1/presence", "POST", account, { schema_version: 1, session_id: "a".repeat(36), online: false })).status).toBe(200);
    expect(await alarmOf(account)).toEqual({ alarm: grantAt, marker: grantAt });
  });
  it("leaves only states older code accepts: a marker with or without leases is owned, live and consumed, and its own schedule clears it", async () => {
    const { account, first } = await subscriber();
    const grantAt = anniversary(first, 1) + SETTLE_MS;
    await runInDurableObject(player(account), async (_, state) => {
      const storage = state.storage;
      expect(presenceAlarmOwned(storage, await storage.getAlarm())).toBe(true);
      expect(presenceAlarmOwned(storage, null, true)).toBe(true);
      expect(await storage.getAlarm()).toBe(grantAt);
      // With a lease that ends after the grant's wake: the marker is the earlier time.
      storage.sql.exec("INSERT INTO presence_leases VALUES (?,?,?)", "b".repeat(36), JSON.parse(storage.sql.exec<{ data: string }>("SELECT data FROM identity WHERE id=1").one().data).device_hash, grantAt + DAY);
      await schedulePresence(storage, grantAt);
      expect(await storage.getAlarm()).toBe(grantAt);
      expect(presenceAlarmOwned(storage, grantAt)).toBe(true);
      expect(presenceAlarmOwned(storage, null, true)).toBe(true);
      // What an older alarm does: prune, then schedule from the leases only. It throws nothing and drops the grant's wake.
      storage.sql.exec("DELETE FROM presence_leases");
      await schedulePresence(storage);
      expect(await storage.getAlarm()).toBeNull();
      expect(storage.sql.exec("SELECT * FROM presence_alarm").toArray()).toEqual([]);
    });
    // The next read that settles sets it again.
    at(anniversary(first, 1) + HOUR);
    items = [subscription(anniversary(first, 1))];
    expect(await wallet(account)).toBe(4500 + 4750);
    expect((await alarmOf(account)).alarm).toBe(anniversary(first, 2) + SETTLE_MS);
  });
  it("hands the alarm to an identity deletion and wakes no grant after it", async () => {
    const { account } = await subscriber();
    expect((await call("/v1/identity", "DELETE", account)).status).toBe(200);
    const left = await runInDurableObject(player(account), async (_, state) => state.storage.sql.exec("SELECT name FROM sqlite_master WHERE name='pollen_grant'").toArray());
    expect(left).toEqual([]);
    // A wake left from before cleans itself up without a read, once.
    const calls = providerCalls;
    await runDurableObjectAlarm(player(account));
    expect(providerCalls).toBe(calls);
    expect(await runDurableObjectAlarm(player(account))).toBe(false);
  });
});
