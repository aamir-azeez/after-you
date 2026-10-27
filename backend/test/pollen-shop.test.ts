import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { POLLEN_HEADER } from "../src/pollen/routes";
import { creditClear, noteFullJourney, type WalletView } from "../src/pollen/wallet";
import { MAX_OPS, type EquipReceipt, type SpendReceipt, type WardrobeView } from "../src/pollen/wardrobe";
import { NAME_CHANGE_PRICE, namePrice, nextNamePrice } from "../src/pollen/name-price";
import { POLLEN_SHOP_TABLES, POLLEN_WALLET_TABLES } from "../src/storage-schema";
import { countingEnv, meterRows } from "./meter";

// The wardrobe through the Worker: spending and wearing with idempotency keys, ownership, the
// Special unlock, the flag off, the name change price, and what each costs. Synthetic identities only.
type Account = { player_id: string; device_token: string; recovery_code: string };
type ShopWallet = WalletView & { wardrobe: WardrobeView; name_price: number };
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const SHOP = { FEATURES: "POLLEN_EARN,POLLEN_SHOP", POLLEN_SECRET: SECRET, DISPLAY_NAMES_ENABLED: "true" };
const EARN_ONLY = { FEATURES: "POLLEN_EARN", POLLEN_SECRET: SECRET, DISPLAY_NAMES_ENABLED: "true" };
const ASK = { [POLLEN_HEADER]: "1" };
const DAY = 86_400_000;
const key = () => crypto.randomUUID();
let address = 0;

async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, string | undefined> = SHOP, base: Env = env): Promise<Response> {
  const configured = Object.assign({ ...base }, { V2_ROOMS_ENABLED: "true", ...vars }) as Env;
  return worker.fetch(new Request("https://shop.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.92." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...ASK },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function counted(path: string, method: string, account: Account, body: unknown, vars: Record<string, string> = SHOP) {
  const meter = countingEnv({ ...env, V2_ROOMS_ENABLED: "true", ...vars } as unknown as Env);
  const response = await call(path, method, account, body, vars, meter.env);
  return { response, calls: meter.calls };
}
const shared = env as unknown as Record<string, unknown>;
beforeEach(() => { shared.POLLEN_SECRET = SECRET; });
afterEach(async () => { delete shared.POLLEN_SECRET; vi.restoreAllMocks(); await reset(); });

async function create(): Promise<Account> {
  const made = await call("/v1/identity", "POST", undefined, {}); expect(made.status).toBe(201);
  return made.json<Account>();
}
/** A balance on the player's own wallet, as earning would leave it. */
async function fund(account: Account, balance: number): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
    noteFullJourney(state.storage, Date.now() + DAY, Date.now());
    state.storage.sql.exec("UPDATE pollen_wallet SET data=json_set(data,'$.balance',?,'$.earned',?) WHERE id=1", balance, balance);
  });
}
async function clear(account: Account, levelId: string): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
    expect(creditClear(state.storage, { level_id: levelId, hard: false, boost_percent: 0 }, Date.now(), () => true).ok).toBe(true);
  });
}
const wallet = async (account: Account, vars: Record<string, string> = SHOP) => (await call("/v1/pollen", "GET", account, undefined, vars)).json<ShopWallet>();
const spendBody = (id: string, expected_cost: number, kind = "item", idempotency_key = key()) => ({ schema_version: 1, idempotency_key, kind, id, expected_cost });
const equipBody = (look: Record<string, string>, revision = Date.now(), idempotency_key = key()) => ({ schema_version: 1, idempotency_key, revision, look });
const spend = (account: Account, body: unknown, vars: Record<string, string> = SHOP) => call("/v1/pollen/spend", "POST", account, body, vars);
const equip = (account: Account, body: unknown) => call("/v1/pollen/equip", "POST", account, body);
const tables = (account: Account) => runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) =>
  state.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'pollen_%' ORDER BY name").toArray().map(row => row.name));

describe("the shop flag", () => {
  it("is absent while off: no capability, no wardrobe on the wallet read, and spend and equip answer 503", async () => {
    const player = await create(); await fund(player, 5000);
    const capabilities = async (vars: Record<string, string>) => (await call("/v2/capabilities", "GET", player, undefined, vars)).json<Record<string, unknown>>();
    expect(await capabilities(SHOP)).toMatchObject({ pollen_version: 1, pollen_shop_version: 1 });
    expect(await capabilities(EARN_ONLY)).not.toHaveProperty("pollen_shop_version");
    expect(await capabilities({ FEATURES: "POLLEN_SHOP", POLLEN_SECRET: SECRET })).not.toHaveProperty("pollen_shop_version");
    const plain = await wallet(player, EARN_ONLY);
    expect(plain).not.toHaveProperty("wardrobe"); expect(plain).not.toHaveProperty("name_price");
    expect((await spend(player, spendBody("daisy", 1000), EARN_ONLY)).status).toBe(503);
    expect((await call("/v1/pollen/equip", "POST", player, equipBody({}), EARN_ONLY)).status).toBe(503);
    expect(await tables(player)).toEqual(POLLEN_WALLET_TABLES.map(table => table.name).sort());
  });
  it("lists what the server sells, what is owned and worn, and what a Special waits for", async () => {
    const player = await create();
    const view = await wallet(player);
    expect(view.wardrobe).toEqual({ items: [], packs: [], look: {}, look_revision: 0,
      offered: ["daisy", "seashell", "straw_hat", "tide", "lantern", "lighthouse_lamp", "gold_leaf", "every_hard", "top_ten_ribbon"], offered_packs: [], sets: {}, unlocked: [] });
    expect(view.name_price).toBe(0);
    await clear(player, "sleeping-lighthouse");
    expect((await wallet(player)).wardrobe.unlocked).toEqual(["lighthouse_lamp"]);
  });
});

describe("spending", () => {
  it("buys an item once: the same key and body answers the same receipt, another body with that key is 409", async () => {
    const player = await create(); await fund(player, 24000);
    const body = spendBody("tide", 20000);
    const first = await spend(player, body), again = await spend(player, body);
    expect(first.status).toBe(200); expect(again.status).toBe(200);
    const receipt = await first.json<SpendReceipt>();
    expect(receipt).toEqual({ schema_version: 1, op: "spend", kind: "item", id: "tide", pieces: ["tide"], cost: 20000, balance: 4000 });
    expect(await again.json()).toEqual(receipt);
    const reused = await spend(player, { ...body, id: "daisy", expected_cost: 1000 });
    expect(reused.status).toBe(409); expect(await reused.json()).toMatchObject({ error: { code: "idempotency_key_reused" } });
    expect(await wallet(player)).toMatchObject({ balance: 4000, wardrobe: { items: ["tide"] } });
    // A new key for an item already owned never charges again.
    const twice = await spend(player, spendBody("tide", 20000));
    expect(twice.status).toBe(409); expect(await twice.json()).toMatchObject({ error: { code: "already_owned" } });
    expect((await wallet(player)).balance).toBe(4000);
  });
  it("refuses a short balance, a cost the phone did not show, an earned item and a locked Special, and changes nothing", async () => {
    const player = await create(); await fund(player, 120000);
    const refused = async (body: unknown, status: number, error: string) => { const response = await spend(player, body); expect(response.status, error).toBe(status); expect(await response.json()).toMatchObject({ error: { code: error } }); };
    await refused(spendBody("daisy", 900), 409, "pollen_price_changed");
    await refused(spendBody("gold_leaf", 0), 409, "not_for_sale");
    await refused(spendBody("lighthouse_lamp", 100000), 403, "pollen_locked");
    await refused(spendBody("nothing", 1000), 404, "unknown_item");
    await refused(spendBody("daisy", 1000, "set"), 404, "unknown_item");
    await refused({ ...spendBody("daisy", 1000), extra: 1 }, 400, "invalid_pollen_spend");
    await refused(spendBody("Daisy!", 1000), 400, "invalid_pollen_spend");
    await refused(spendBody("daisy", 1000, "hat"), 400, "invalid_pollen_spend");
    expect(await wallet(player)).toMatchObject({ balance: 120000, wardrobe: { items: [] } });
    await clear(player, "sleeping-lighthouse");
    const lamp = await spend(player, spendBody("lighthouse_lamp", 100000));
    expect(lamp.status).toBe(200);
    await refused(spendBody("lantern", 50000), 402, "pollen_short");
    expect((await wallet(player)).balance).toBe(20000 + 2500);
  });
  it("starts the wardrobe on a wallet earning made before the shop existed", async () => {
    const player = await create(); await fund(player, 3000);
    expect(await tables(player)).toEqual(["pollen_claims", "pollen_wallet"]);
    expect((await spend(player, spendBody("daisy", 1000))).status).toBe(200);
    expect(await tables(player)).toEqual([...POLLEN_WALLET_TABLES, ...POLLEN_SHOP_TABLES].map(table => table.name).sort());
    expect(await wallet(player)).toMatchObject({ balance: 2000, earned: 3000, wardrobe: { items: ["daisy"] } });
  });
  it("keeps only the newest receipts, and an old key sent again can still never charge twice", async () => {
    const player = await create(); await fund(player, 10000);
    const first = spendBody("daisy", 1000);
    expect((await spend(player, first)).status).toBe(200);
    let revision = Date.now();
    for (let index = 0; index < MAX_OPS; index++) expect((await equip(player, equipBody(index % 2 ? {} : { hat: "daisy" }, ++revision))).status).toBe(200);
    const kept = await runInDurableObject(env.PLAYERS.getByName(player.player_id), async (_, state) => state.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM pollen_ops").one().n);
    expect(kept).toBe(MAX_OPS);
    const late = await spend(player, first);
    expect(late.status).toBe(409); expect(await late.json()).toMatchObject({ error: { code: "already_owned" } });
    expect((await wallet(player)).balance).toBe(9000);
  });
  it("costs one Player request beside auth, and writes the wallet, the item and the receipt", async () => {
    const player = await create(); await fund(player, 5000);
    const metered = await counted("/v1/pollen/spend", "POST", player, spendBody("daisy", 1000));
    expect(metered.response.status).toBe(200);
    expect(metered.calls).toEqual(["PLAYERS.authorize", "PLAYERS.pollenSpend"]);
    const stub = env.PLAYERS.getByName(player.player_id);
    const rows = await meterRows({ player: stub }, async () => expect((await spend(player, spendBody("seashell", 1000))).status).toBe(200));
    // The wallet row, the item and the receipt (with its key index).
    expect(rows.rows.player.written).toBe(4);
    const read = await counted("/v1/pollen", "GET", player, undefined);
    expect(read.calls).toEqual(["PLAYERS.authorizeWallet"]);
  });
});

describe("wearing", () => {
  it("wears only owned items, answers the same receipt for the same key and refuses another body with it", async () => {
    const player = await create(); await fund(player, 30000);
    const unowned = await equip(player, equipBody({ hat: "daisy" }));
    expect(unowned.status).toBe(403); expect(await unowned.json()).toMatchObject({ error: { code: "not_owned" } });
    expect((await spend(player, spendBody("daisy", 1000))).status).toBe(200);
    expect((await spend(player, spendBody("tide", 20000))).status).toBe(200);
    const body = equipBody({ hat: "daisy", body: "tide" });
    const worn = await equip(player, body);
    expect(worn.status).toBe(200);
    const receipt = await worn.json<EquipReceipt>();
    expect(receipt).toEqual({ schema_version: 1, op: "equip", look: { hat: "daisy", body: "tide" }, revision: body.revision });
    expect(await (await equip(player, body)).json()).toEqual(receipt);
    expect((await equip(player, { ...body, look: {} })).status).toBe(409);
    expect((await wallet(player)).wardrobe).toMatchObject({ look: { hat: "daisy", body: "tide" }, look_revision: body.revision });
    for (const look of [{ body: "daisy" }, { hat: "nothing" }, { shoe: "daisy" }]) expect((await equip(player, equipBody(look))).status, JSON.stringify(look)).toBe(400);
  });
  it("never lets an older equip that arrives late undo a newer one", async () => {
    const player = await create(); await fund(player, 2000);
    expect((await spend(player, spendBody("daisy", 1000))).status).toBe(200);
    expect((await spend(player, spendBody("seashell", 1000))).status).toBe(200);
    const older = equipBody({ hat: "daisy" }, Date.now() - 5000), newer = equipBody({ hat: "seashell" }, Date.now());
    expect((await equip(player, newer)).status).toBe(200);
    const late = await equip(player, older);
    expect(late.status).toBe(200);
    expect(await late.json()).toMatchObject({ look: { hat: "seashell" }, revision: newer.revision });
    expect((await wallet(player)).wardrobe.look).toEqual({ hat: "seashell" });
    expect((await equip(player, equipBody({}, Date.now() + 2 * DAY))).status).toBe(400);
  });
  it("costs one Player request beside auth", async () => {
    const player = await create(); await fund(player, 1000);
    expect((await spend(player, spendBody("daisy", 1000))).status).toBe(200);
    const metered = await counted("/v1/pollen/equip", "POST", player, equipBody({ hat: "daisy" }));
    expect(metered.response.status).toBe(200);
    expect(metered.calls).toEqual(["PLAYERS.authorize", "PLAYERS.pollenEquip"]);
    const rows = await meterRows({ player: env.PLAYERS.getByName(player.player_id) }, async () => expect((await equip(player, equipBody({}, Date.now() + 1000))).status).toBe(200));
    // The look row and the receipt (with its key index).
    expect(rows.rows.player.written).toBe(3);
  });
  it("goes with the account", async () => {
    const player = await create(); await fund(player, 1000);
    expect((await spend(player, spendBody("daisy", 1000))).status).toBe(200);
    expect((await call("/v1/identity", "DELETE", player)).status).toBe(200);
    expect(await tables(player)).toEqual([]);
  });
});

describe("the name change price", () => {
  const rename = (account: Account, name: string | null, revision: number, price?: number) =>
    call("/v1/profile/name", "PUT", account, { schema_version: 1, display_name: name, revision, ...(price === undefined ? {} : { pollen_price: price }) });
  it("is free for the first name and the first change, then 1,000 each, charged with the change", async () => {
    const player = await create(); await fund(player, 2500);
    let revision = Date.now() - 60_000;
    expect((await wallet(player)).name_price).toBe(0);
    expect((await rename(player, "Robin", ++revision, 0)).status).toBe(200);
    expect((await wallet(player)).name_price).toBe(0);
    expect((await rename(player, "Robin Sky", ++revision, 0)).status).toBe(200);
    expect((await wallet(player)).name_price).toBe(NAME_CHANGE_PRICE);
    const free = await rename(player, "Sky", ++revision, 0);
    expect(free.status).toBe(409); expect(await free.json()).toMatchObject({ error: { code: "name_change_price" } });
    const paid = ++revision;
    expect((await rename(player, "Sky", paid, 1000)).status).toBe(200);
    expect(await wallet(player)).toMatchObject({ balance: 1500, name_price: 1000 });
    // A retry of the same revision is never charged again.
    expect((await rename(player, "Sky", paid, 1000)).status).toBe(200);
    expect((await wallet(player)).balance).toBe(1500);
    // Going anonymous and saving the same name are free.
    expect((await rename(player, null, ++revision)).status).toBe(200);
    expect((await wallet(player)).balance).toBe(1500);
    expect((await rename(player, "Sea", ++revision, 1000)).status).toBe(200);
    const short = await rename(player, "Shore", ++revision, 1000);
    expect(short.status).toBe(402); expect(await short.json()).toMatchObject({ error: { code: "pollen_short" } });
    expect(await wallet(player)).toMatchObject({ balance: 500 });
  });
  it("refuses a paid change from a phone that shows no price with a code it settles on", async () => {
    const player = await create(); await fund(player, 5000);
    let revision = Date.now() - 60_000;
    for (const name of ["One", "Two"]) expect((await rename(player, name, ++revision)).status).toBe(200);
    const old = await rename(player, "Three", ++revision);
    expect(old.status).toBe(403); expect(await old.json()).toMatchObject({ error: { code: "display_name_locked" } });
    expect((await wallet(player)).balance).toBe(5000);
  });
  it("stays free while the shop is off, and counts nothing", async () => {
    const player = await create(); await fund(player, 5000);
    let revision = Date.now() - 60_000;
    for (const name of ["One", "Two", "Three"]) expect((await call("/v1/profile/name", "PUT", player, { schema_version: 1, display_name: name, revision: ++revision }, EARN_ONLY)).status).toBe(200);
    const identity = await runInDurableObject(env.PLAYERS.getByName(player.player_id), async (_, state) => JSON.parse(state.storage.sql.exec<{ data: string }>("SELECT data FROM identity").one().data) as Record<string, unknown>);
    expect(identity).not.toHaveProperty("display_name_sets");
    expect((await wallet(player)).balance).toBe(5000);
  });
  it("keeps every free case: a moderator's clear, a name the filter now refuses and a name set before the shop", () => {
    const now = Date.now();
    expect(nextNamePrice({}, now)).toBe(0);
    expect(nextNamePrice({ display_name: "Robin" }, now)).toBe(0);
    expect(nextNamePrice({ display_name: "Robin", display_name_sets: 2 }, now)).toBe(1000);
    expect(nextNamePrice({ display_name_sets: 2, display_name_locked_until: now - 1 }, now)).toBe(0);
    expect(nextNamePrice({ display_name_sets: 2, display_name_locked_until: now + DAY }, now)).toBe(1000);
    expect(nextNamePrice({ display_name: "x\u0000y", display_name_sets: 2 }, now)).toBe(0);
    expect(namePrice({ display_name: "Robin", display_name_sets: 2 }, null, now)).toBe(0);
    expect(namePrice({ display_name: "Robin", display_name_sets: 2 }, "Robin", now)).toBe(0);
    expect(namePrice({ display_name: "Robin", display_name_sets: 2 }, "Sky", now)).toBe(1000);
  });
  it("adds nothing to a name change's requests", async () => {
    const player = await create();
    const metered = await counted("/v1/profile/name", "PUT", player, { schema_version: 1, display_name: "Robin", revision: Date.now() - 1000, pollen_price: 0 });
    expect(metered.response.status).toBe(200);
    expect(metered.calls).toEqual(["PLAYERS.authorize", "PLAYERS.setDisplayName"]);
  });
});
