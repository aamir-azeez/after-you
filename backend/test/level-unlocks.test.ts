import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { FLAG_VARS } from "../src/flags";
import { FRUIT_PREFIX, purse } from "../src/pollen/currency";
import { LEVEL_ID_PATTERN, LEVEL_PRICES, levelUnlockKey, levelsView, paidLevels, unlockLevel } from "../src/pollen/level-unlocks";
import { applyLedger, ledgerLine, noteFullJourney } from "../src/pollen/wallet";
import { spend } from "../src/pollen/wardrobe";
import { fruitHistory } from "../src/pollen/fruit-ops";
import { POLLEN_HEADER } from "../src/pollen/routes";
import type { Outcome } from "../src/protocol";
import manifest from "../../game/tests/fixtures/golden/chapter_manifest.json";
import { POLLEN_CLIENT, withConfig } from "./config";
import { meterRows } from "./meter";

// Opening a level with Fruits (pollen/level-unlocks.ts, the owner's word of 2026-11-16: Fog Marsh costs 3 Fruits once,
// free with Full Journey): the price pinned to the game, the one kept unlock line, refusals, retries under one key and
// another, the flag, and the rows a read and a spend cost. Synthetic player ids and a synthetic price table only.
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const T0 = Date.UTC(2026, 10, 16, 9), DAY = 86_400_000;
const TABLE = Object.freeze({ "test-level-a": 3, "test-level-b": 7 });
let serial = 0;
const value = <T>(outcome: Outcome<T>): T => { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; };
const fund = (storage: DurableObjectStorage, fruits: number) => applyLedger(storage, [{ key: `${FRUIT_PREFIX}bundle:GPA.level-${++serial}`, kind: "fruitbundle", amount: fruits, detail: { bundle: "crate" } }], T0);
async function inPlayer<T>(work: (storage: DurableObjectStorage) => T): Promise<T> {
  return runInDurableObject(env.PLAYERS.getByName("level-unlock-" + ++serial), async (_, state) => work(state.storage));
}
afterEach(async () => { await reset(); });

describe("the level price table", () => {
  it("agrees with every chapter the game registers (chapter_manifest unlock_fruits), and prices only well formed levels", () => {
    for (const row of Object.values(manifest.chapters) as { level_id: string; unlock_fruits: number }[]) {
      expect([row.level_id, row.unlock_fruits]).toEqual([row.level_id, LEVEL_PRICES[row.level_id] ?? 0]);
    }
    for (const [level, price] of Object.entries(LEVEL_PRICES)) {
      expect(LEVEL_ID_PATTERN.test(level)).toBe(true);
      expect(Number.isSafeInteger(price) && price > 0).toBe(true);
    }
    expect(FLAG_VARS.levelUnlocks).toBe("LEVEL_UNLOCKS");
  });
});

describe("opening a level", () => {
  it("charges its price once into one kept Fruit line, and refuses what it must", async () => {
    await inPlayer(storage => {
      expect(unlockLevel(storage, "test-level-a", 3, T0, false, TABLE)).toMatchObject({ status: 402, code: "fruits_short" });
      fund(storage, 5);
      expect(unlockLevel(storage, "test-level-z", 3, T0, false, TABLE)).toMatchObject({ status: 404, code: "unknown_item" });
      expect(unlockLevel(storage, "Bad_Id", 3, T0, false, TABLE)).toMatchObject({ status: 404, code: "unknown_item" });
      expect(unlockLevel(storage, "test-level-a", 2, T0, false, TABLE)).toMatchObject({ status: 409, code: "pollen_price_changed" });
      expect(unlockLevel(storage, "test-level-a", 3, T0, true, TABLE)).toMatchObject({ status: 409, code: "level_free" });
      expect(value(unlockLevel(storage, "test-level-a", 3, T0, false, TABLE))).toEqual({ fruit_balance: 2, cost: 3 });
      expect(unlockLevel(storage, "test-level-a", 3, T0 + DAY, false, TABLE)).toMatchObject({ status: 409, code: "already_owned" });
      // Paid once, it stays open even with Full Journey, and the next one is short.
      expect(unlockLevel(storage, "test-level-a", 3, T0, true, TABLE)).toMatchObject({ code: "already_owned" });
      expect(unlockLevel(storage, "test-level-b", 7, T0, false, TABLE)).toMatchObject({ status: 402, code: "fruits_short" });
      expect(purse(storage, "fruits").balance).toBe(2);
      expect(ledgerLine(storage, levelUnlockKey("test-level-a"))).toMatchObject({ amount: -3, detail: { level_id: "test-level-a" } });
      expect(paidLevels(storage)).toEqual(["test-level-a"]);
      expect(levelsView(storage, TABLE)).toEqual({ prices: { "test-level-a": 3, "test-level-b": 7 }, open: ["test-level-a"] });
      expect(fruitHistory(storage).find(entry => entry.kind === "level")).toMatchObject({ amount: -3, level_id: "test-level-a" });
    });
  });
  it("is refused while Fruits are blocked by a refund", async () => {
    await inPlayer(storage => {
      fund(storage, 5);
      applyLedger(storage, [{ key: `${FRUIT_PREFIX}bundlerefund:GPA.level-r`, kind: "fruitbundlerefund", amount: -9, detail: {} }], T0);
      expect(unlockLevel(storage, "test-level-a", 3, T0, false, TABLE)).toMatchObject({ status: 403, code: "fruits_blocked" });
      expect(paidLevels(storage)).toEqual([]);
    });
  });
  it("answers the same receipt for the same key, and already_owned for any other key, through the spend", async () => {
    await inPlayer(storage => {
      fund(storage, 10);
      const op = { key: "a".repeat(32), hash: "1".repeat(64) }, request = { kind: "level" as const, id: "test-level-b" }, terms = { fullJourney: false, prices: TABLE };
      expect(spend(storage, op, request, 7, T0, () => true, undefined, true, null)).toMatchObject({ status: 503, code: "level_unlocks_disabled" });
      expect(spend(storage, op, request, 7, T0, () => true, undefined, false, terms)).toMatchObject({ status: 503, code: "fruits_disabled" });
      const first = value(spend(storage, op, request, 7, T0, () => true, undefined, true, terms));
      expect(first).toMatchObject({ kind: "level", id: "test-level-b", cost: 7, currency: "fruits", fruit_balance: 3, pieces: [] });
      expect(value(spend(storage, op, request, 7, T0 + 1, () => true, undefined, true, terms))).toEqual(first);
      expect(spend(storage, { ...op, hash: "2".repeat(64) }, request, 7, T0, () => true, undefined, true, terms)).toMatchObject({ code: "idempotency_key_reused" });
      expect(spend(storage, { key: "b".repeat(32), hash: "3".repeat(64) }, request, 7, T0, () => true, undefined, true, terms)).toMatchObject({ status: 409, code: "already_owned" });
      expect(purse(storage, "fruits").balance).toBe(3);
    });
  });
});

// The routes through the Worker, with LEVEL_UNLOCKS on and off, against the real price table.
type Account = { player_id: string; device_token: string; recovery_code: string };
const FRUITS = { POLLEN_SECRET: SECRET, features: ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "FRUITS"] };
const LEVELS = { ...FRUITS, features: [...FRUITS.features, "LEVEL_UNLOCKS"] };
const [PRICED, PRICE] = Object.entries(LEVEL_PRICES)[0];
let address = 0;
const shared = env as unknown as Record<string, unknown>;
beforeEach(() => { shared.POLLEN_SECRET = SECRET; });
async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, unknown> = LEVELS): Promise<Response> {
  return worker.fetch(new Request("https://levels.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.96." + (++address % 250), [POLLEN_HEADER]: "1", ...POLLEN_CLIENT,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) }), withConfig(Object.assign({ ...env }, vars)) as Env);
}
async function create(): Promise<Account> {
  const made = await call("/v1/identity", "POST", undefined, {}); expect(made.status).toBe(201);
  return made.json<Account>();
}
const player = (account: Account) => env.PLAYERS.getByName(account.player_id);
const inAccount = <T>(account: Account, work: (storage: DurableObjectStorage) => T) => runInDurableObject(player(account), async (_, state) => work(state.storage));
const unlockBody = (id: string, expected_cost: number, key: string = crypto.randomUUID()) => ({ schema_version: 1, idempotency_key: key, kind: "level", id, expected_cost });
type Read = { fruits?: { balance: number; levels?: { prices: Record<string, number>; open: string[] } } };
const code = async (response: Response) => [response.status, (await response.json<{ error: { code: string } }>()).error.code];

describe("the level unlock routes", () => {
  it("say nothing and charge nothing while LEVEL_UNLOCKS is off", async () => {
    const account = await create();
    await inAccount(account, storage => { fund(storage, 10); });
    const read = await (await call("/v1/pollen", "GET", account, undefined, FRUITS)).json<Read>();
    expect(read.fruits).toBeDefined();
    expect(read.fruits).not.toHaveProperty("levels");
    expect(await code(await call("/v1/pollen/spend", "POST", account, unlockBody(PRICED, PRICE), FRUITS))).toEqual([503, "level_unlocks_disabled"]);
    expect(await inAccount(account, storage => [purse(storage, "fruits").balance, paidLevels(storage)])).toEqual([10, []]);
  });
  it("open a level once for its price, answer a retry with the same receipt, and show it open on the next read", async () => {
    const account = await create();
    const before = await (await call("/v1/pollen", "GET", account)).json<Read>();
    expect(before.fruits!.levels).toEqual({ prices: LEVEL_PRICES, open: [] });
    expect(await code(await call("/v1/pollen/spend", "POST", account, unlockBody(PRICED, PRICE)))).toEqual([402, "fruits_short"]);
    await inAccount(account, storage => { fund(storage, PRICE + 2); });
    expect(await code(await call("/v1/pollen/spend", "POST", account, unlockBody("not-a-level", PRICE)))).toEqual([404, "unknown_item"]);
    expect(await code(await call("/v1/pollen/spend", "POST", account, unlockBody("Bad_Level", PRICE)))).toEqual([400, "invalid_pollen_spend"]);
    const body = unlockBody(PRICED, PRICE);
    const bought = await (await call("/v1/pollen/spend", "POST", account, body)).json<Record<string, unknown>>();
    expect(bought).toMatchObject({ kind: "level", id: PRICED, cost: PRICE, currency: "fruits", fruit_balance: 2 });
    // A retry of the same tap (no answer came) answers the first receipt; a second tap is refused, never charged.
    expect(await (await call("/v1/pollen/spend", "POST", account, body)).json()).toEqual(bought);
    expect(await code(await call("/v1/pollen/spend", "POST", account, unlockBody(PRICED, PRICE)))).toEqual([409, "already_owned"]);
    const after = await (await call("/v1/pollen", "GET", account)).json<Read>();
    expect(after.fruits).toMatchObject({ balance: 2, levels: { open: [PRICED] } });
    const history = await (await call("/v1/pollen/history", "GET", account)).json<{ fruit_entries: { kind: string; amount: number; level_id?: string }[] }>();
    expect(history.fruit_entries[0]).toMatchObject({ kind: "level", amount: -PRICE, level_id: PRICED });
  });
  it("refuse a player with Full Journey, who plays it free", async () => {
    const account = await create();
    await inAccount(account, storage => { fund(storage, 10); noteFullJourney(storage, Date.now() + 30 * DAY, Date.now()); });
    expect(await code(await call("/v1/pollen/spend", "POST", account, unlockBody(PRICED, PRICE)))).toEqual([409, "level_free"]);
    expect(await inAccount(account, storage => purse(storage, "fruits").balance)).toBe(10);
  });
  it("measure the rows a read and an unlock write", async () => {
    const account = await create();
    await call("/v1/pollen", "GET", account);
    await inAccount(account, storage => { fund(storage, 10 + PRICE); });
    // A first spend makes the receipt tables, as any first purchase does; measured after it.
    await call("/v1/pollen/spend", "POST", account, { schema_version: 1, idempotency_key: crypto.randomUUID(), kind: "convert", id: "10", expected_cost: 10 });
    const stubs = { player: player(account) };
    const read = await meterRows(stubs, () => call("/v1/pollen", "GET", account));
    const unlock = await meterRows(stubs, () => call("/v1/pollen/spend", "POST", account, unlockBody(PRICED, PRICE)));
    const again = await meterRows(stubs, () => call("/v1/pollen", "GET", account));
    const measured = { read: read.rows.player.written, unlock: unlock.rows.player.written, read_after: again.rows.player.written };
    console.log("level unlock rows", JSON.stringify({ written: measured, read: { read: read.rows.player.read, unlock: unlock.rows.player.read, read_after: again.rows.player.read } }));
    // The unlock line, the purse and the receipt; a read writes nothing.
    expect(measured).toEqual({ read: 0, unlock: 3, read_after: 0 });
  });
});
