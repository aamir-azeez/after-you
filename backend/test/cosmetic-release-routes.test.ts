// The release list end to end, through the Worker and the Player: this file's catalogue has one item built unreleased
// (reed_cap, made-up code 901: test codes stay in the 900s, clear of every real block), so the routes the phone uses can be seen refusing it and then
// selling it once CONFIG lists its code.
vi.mock("../src/pollen/catalog.json", async importOriginal => {
  const real = (await importOriginal()) as { default: { items: Record<string, unknown> } };
  const data = structuredClone(real.default);
  data.items.reed_cap = { code: 901, slot: "hat", tier: "common", unlock: "", set: "", released: false };
  return { default: data };
});

import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { POLLEN_HEADER } from "../src/pollen/routes";
import { CATALOG, OFFERED_TAG } from "../src/pollen/catalog";
import { noteFullJourney } from "../src/pollen/wallet";
import { countingEnv, meterAllRows } from "./meter";
import { POLLEN_CLIENT, withConfig } from "./config";

type Account = { player_id: string; device_token: string };
type WardrobePart = { offered: string[]; prices: Record<string, number>; items: string[] };
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const SHOP = { POLLEN_SECRET: SECRET, features: ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP"] };
const RELEASED = { ...SHOP, cosmetics_released: [901] };
const DAY = 86_400_000;
let address = 0;
const shared = env as unknown as Record<string, unknown>;
/** The Player reads its own CONFIG, which the Worker's vars never reach (as in production, both come from the one deploy): set it there too. */
const objectConfigs = new Map<Record<string, unknown>, unknown>();
async function playerConfig(account: Account, vars: Record<string, unknown>): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), instance => {
    const target = Reflect.get(instance, "env") as Record<string, unknown>;
    if (!objectConfigs.has(target)) objectConfigs.set(target, target.CONFIG);
    target.CONFIG = withConfig(vars).CONFIG;
  });
}
beforeEach(() => { shared.POLLEN_SECRET = SECRET; });
afterEach(async () => {
  for (const [target, value] of objectConfigs) { if (value === undefined) delete target.CONFIG; else target.CONFIG = value; }
  objectConfigs.clear();
  delete shared.POLLEN_SECRET; await reset();
});

function call(path: string, method: string, account: Account | undefined, vars: Record<string, unknown>, body?: unknown, base: Env = env): Promise<Response> {
  return worker.fetch(new Request("https://cosmetics-routes.test" + path, { method, body: body === undefined ? undefined : JSON.stringify(body),
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.95." + (++address % 250), [POLLEN_HEADER]: "1", ...POLLEN_CLIENT,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) } }), withConfig(Object.assign(withoutConfig(base), vars)) as unknown as Env);
}
/** The env's own vars without the CONFIG a test set for the Player (in the test runtime the Player shares `env`). */
function withoutConfig(base: Env): Record<string, unknown> {
  const { CONFIG: _config, ...rest } = base as unknown as Record<string, unknown>;
  return rest;
}
const create = async (): Promise<Account> => (await call("/v1/identity", "POST", undefined, SHOP, {})).json<Account>();
async function fund(account: Account, balance: number): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
    noteFullJourney(state.storage, Date.now() + DAY, Date.now());
    state.storage.sql.exec("UPDATE pollen_wallet SET data=json_set(data,'$.balance',?,'$.earned',?) WHERE id=1", balance, balance);
  });
}
const wardrobe = async (account: Account, vars: Record<string, unknown>) => (await (await call("/v1/pollen", "GET", account, vars)).json<{ wardrobe: WardrobePart }>()).wardrobe;
const caps = async (account: Account, vars: Record<string, unknown>) => (await call("/v2/capabilities", "GET", account, vars)).json<Record<string, unknown>>();
const buy = (account: Account, vars: Record<string, unknown>) =>
  call("/v1/pollen/spend", "POST", account, vars, { schema_version: 1, idempotency_key: crypto.randomUUID(), kind: "item", id: "reed_cap", expected_cost: 1000 });

describe("an item built unreleased", () => {
  it("is neither offered, priced nor sold until CONFIG lists its code, then is all three", async () => {
    expect(CATALOG.items.reed_cap?.released).toBe(false);
    const player = await create(); await fund(player, 5000);
    await playerConfig(player, SHOP);
    const before = await wardrobe(player, SHOP);
    expect(before.offered).not.toContain("reed_cap");
    expect(before.prices).not.toHaveProperty("reed_cap");
    expect((await caps(player, SHOP)).pollen_offered_tag).toBe(OFFERED_TAG);
    const refused = await buy(player, SHOP);
    expect(refused.status).toBe(409);
    expect((await refused.json<{ error: { code: string } }>()).error.code).toBe("not_for_sale");
    // Featuring it while it is unreleased features nothing.
    expect(await caps(player, { ...SHOP, cosmetics_featured: 901 })).not.toHaveProperty("pollen_featured_code");

    // Released by CONFIG: a new tag sends phones to read once, and the read offers and prices it.
    const released = await caps(player, { ...RELEASED, cosmetics_featured: 901 });
    expect(released.pollen_offered_tag).toMatch(/^[a-f0-9]{8}$/);
    expect(released.pollen_offered_tag).not.toBe(OFFERED_TAG);
    expect(released.pollen_featured_code).toBe(901);
    await playerConfig(player, RELEASED);
    const after = await wardrobe(player, RELEASED);
    expect(after.offered).toContain("reed_cap");
    expect(after.prices.reed_cap).toBe(1000);
    const bought = await buy(player, RELEASED);
    expect(bought.status).toBe(200);
    expect((await wardrobe(player, RELEASED)).items).toContain("reed_cap");
  });

  it("costs no Durable Object request or row more to read under a release list", async () => {
    const player = await create();
    const measure = async (vars: Record<string, unknown>) => {
      await playerConfig(player, vars);
      const meter = countingEnv(env);
      const { rows } = await meterAllRows(async () => {
        for (const [path, method] of [["/v2/capabilities", "GET"], ["/v1/pollen", "GET"]] as const) expect((await call(path, method, player, vars, undefined, meter.env)).status, path).toBe(200);
      });
      return { calls: meter.calls, written: rows.written };
    };
    await measure(SHOP);
    const without = await measure(SHOP), with_ = await measure({ ...RELEASED, cosmetics_featured: 901 });
    expect(with_.calls).toEqual(without.calls);
    expect(with_.written).toBe(without.written);
  });
});
