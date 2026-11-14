// Version gates (config.ts feature_min_version, flags.ts gatedOn): FRUITS, ENERGY, FACE_SINGLES and the cosmetics release
// list on for apps at a version or newer only. An older app (0.7.9, 0.8.0, a pre-release of 0.8.1, or one naming no
// version) gets exactly what it got with the flags off and nothing released, is never charged energy, and costs no Durable
// Object request or row more; 0.8.1 gets every part. Synthetic ids only.
import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { GATED_KEYS, parseConfig, parseVersion, type Version } from "../src/config";
import { FLAG_NAMES, LEDGER, gatedOn, type Reach } from "../src/flags";
import { CLIENT_HEADER } from "../src/app-status";
import { POLLEN_HEADER, receiptFor } from "../src/pollen/routes";
import { CATALOG, OFFERED_TAG, catalogFor } from "../src/pollen/catalog";
import { energyOn, faceSinglesOn, fruitsOn } from "../src/pollen/features";
import { withEnergy } from "../src/duels/energy-charge";
import { DUELS_HEADER } from "../src/duels/routes";
import { FACE_PACKS_HEADER } from "../src/v2/end-reactions";
import { ledgerLines } from "../src/pollen/wallet";
import { isoWeek } from "../src/pollen/week";
import type { TurnFacts } from "../src/pollen/turn-facts";
import { countingEnv, meterAllRows } from "./meter";
import { withConfig } from "./config";

type Account = { player_id: string; device_token: string };
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const HATS = [200, 201, 202, 203, 204, 205, 206, 207], SKINS = [300, 301, 302, 303, 304, 305];
const FACES = Array.from({ length: 29 }, (_, n) => 400 + n);
const BASE = ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP", "POLLEN_REFUNDS", "POLLEN_BUNDLES", "POLLEN_BUNDLES_APP_STORE", "LEADERBOARDS", "DUELS"];
/** The first gated flip: the three flags and the first release list, each for 0.8.1 and newer. */
const GATED = { POLLEN_SECRET: SECRET, features: BASE, cosmetics_released: [...HATS, ...SKINS, ...FACES],
  feature_min_version: { FRUITS: "0.8.1", ENERGY: "0.8.1", FACE_SINGLES: "0.8.1", cosmetics_released: "0.8.1" } };
/** What every app got before: the three flags off and nothing released. */
const OFF = { POLLEN_SECRET: SECRET, features: BASE };
/** The same parts on for every app, as a global flip would be. */
const ALL_ON = { POLLEN_SECRET: SECRET, features: [...BASE, "FRUITS", "ENERGY", "FACE_SINGLES"], cosmetics_released: [...HATS, ...SKINS, ...FACES] };
const OLD = ["0.7.9 app_store", "0.8.0 play", "0.8.0 app_store", "0.8.1-rc.1 app_store"], NEW = "0.8.1 app_store";
const version = (text: string) => parseVersion(text) as Version;

let address = 0;
const shared = env as unknown as Record<string, unknown>;
const objectConfigs = new Map<Record<string, unknown>, unknown>();
/** The Player reads its own CONFIG (in production both come from one deploy): set it there too. */
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
function withoutConfig(base: Env): Record<string, unknown> {
  const { CONFIG: _config, ...rest } = base as unknown as Record<string, unknown>;
  return rest;
}
function call(path: string, method: string, account: Account | undefined, vars: Record<string, unknown>, client: string | null, body?: unknown, base: Env = env): Promise<Response> {
  return worker.fetch(new Request("https://version-gates.test" + path, { method, body: body === undefined ? undefined : JSON.stringify(body),
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.94." + (++address % 250), [POLLEN_HEADER]: "1", [DUELS_HEADER]: "1", [FACE_PACKS_HEADER]: "2",
      ...(client ? { [CLIENT_HEADER]: client } : {}), ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) } }),
  withConfig(Object.assign(withoutConfig(base), vars)) as unknown as Env);
}
const create = async (): Promise<Account> => (await call("/v1/identity", "POST", undefined, OFF, NEW, {})).json<Account>();
const read = async (path: string, account: Account, vars: Record<string, unknown>, client: string | null) => {
  await playerConfig(account, vars);
  const response = await call(path, "GET", account, vars, client);
  expect(response.status, path).toBe(200);
  return response.json<Record<string, unknown>>();
};

describe("the gate rule", () => {
  it("gates only real flags and the release list", () => {
    expect(GATED_KEYS.filter(key => key !== "cosmetics_released" && !FLAG_NAMES.has(key))).toEqual([]);
  });
  it("parses one version per gated part, closes a malformed gate, and refuses keys it cannot gate", () => {
    const parse = (value: unknown, features: string[] = []) => parseConfig(JSON.stringify({ features, feature_min_version: value }), FLAG_NAMES);
    const good = parse({ FRUITS: "0.8.1", ENERGY: "0.8.1", FACE_SINGLES: "0.8.1", cosmetics_released: "0.8.1" });
    expect([good.problems, good.unknown]).toEqual([[], []]);
    expect([...good.config.feature_min_version.keys()]).toEqual([...GATED_KEYS]);
    const bad = parse({ FRUITS: "soon" });
    expect(bad.problems).toEqual(["feature_min_version.FRUITS must be a version like 0.8.1"]);
    expect(bad.config.feature_min_version.get("FRUITS")).toBeNull();
    expect(parse({ DUELS: "0.8.1" }).unknown).toEqual(["feature_min_version.DUELS"]);
    expect(parse({ FRUITS: "0.8.1" }, ["FRUITS"]).problems).toEqual(["FRUITS is both in features and gated in feature_min_version: the gate decides"]);
    const whole = parse(["FRUITS"]);
    expect(whole.problems).toEqual(["feature_min_version must be an object"]);
    expect([...whole.config.feature_min_version.values()]).toEqual(GATED_KEYS.map(() => null));
  });

  it("opens a part to apps at the version or newer and to the server's own bookkeeping, and to nothing when malformed", () => {
    const vars = withConfig(GATED);
    const reaches: [Reach, boolean][] = [[null, false], [version("0.7.9"), false], [version("0.8.0"), false], [version("0.8.1-rc.1"), false],
      [version("0.8.1"), true], [version("0.8.2"), true], [version("1.0.0"), true], [LEDGER, true]];
    for (const [reach, on] of reaches) for (const key of GATED_KEYS) expect(gatedOn(vars, key, reach), `${key} ${JSON.stringify(reach)}`).toBe(on);
    for (const [reach, on] of reaches) expect([fruitsOn(vars, reach), energyOn(vars, reach), faceSinglesOn(vars, reach)]).toEqual([on, on, on]);
    // A gate wins over the features list; a malformed one is off for every app and for bookkeeping too.
    const both = { ...withoutConfig(env), CONFIG: JSON.stringify({ features: ["FRUITS"], feature_min_version: { FRUITS: "0.8.1", ENERGY: "later" } }) };
    expect([gatedOn(both, "FRUITS", version("0.8.0")), gatedOn(both, "FRUITS", version("0.8.1"))]).toEqual([false, true]);
    expect([gatedOn(both, "ENERGY", version("9.0.0")), gatedOn(both, "ENERGY", LEDGER)]).toEqual([false, false]);
    // Not gated: a flag is what features says for every app, and the release list is on for every app.
    for (const reach of [null, version("0.7.9"), LEDGER] as Reach[]) {
      expect(gatedOn(withConfig(ALL_ON), "FRUITS", reach)).toBe(true);
      expect(gatedOn(withConfig(OFF), "FRUITS", reach)).toBe(false);
      expect(gatedOn(withConfig(OFF), "cosmetics_released", reach)).toBe(true);
    }
  });

  it("drops and sells from the catalogue as built for an older app, and from the release list for 0.8.1", () => {
    const vars = withConfig(GATED);
    for (const client of OLD) expect(catalogFor(vars, version(client.split(" ")[0]))).toBe(CATALOG);
    expect(catalogFor(vars, null)).toBe(CATALOG);
    const released = catalogFor(vars, version("0.8.1"));
    expect(["paper_boat", "glass_house", "knit", "sea_glass", "aww", "reaction_slot_6"].map(id => released.items[id].released)).toEqual([true, true, true, true, true, true]);
    expect(["bud", "leaves", "pocket_pebble"].map(id => released.items[id].released)).toEqual([false, false, false]);
  });

  it("keeps a credit's Fruits part from an app Fruits are off for", () => {
    const vars = withConfig(GATED), receipt = { schema_version: 1, earned: 5, fruits: { paid: 10 } };
    const request = (client: string | null) => new Request("https://version-gates.test/", { headers: client ? { [CLIENT_HEADER]: client } : {} });
    for (const client of [...OLD, null]) expect(receiptFor(request(client), vars, receipt)).toEqual({ schema_version: 1, earned: 5 });
    expect(receiptFor(request(NEW), vars, receipt)).toBe(receipt);
  });
});

describe("through the Worker", () => {
  it("shows an older app exactly what it saw with the flags off, and 0.8.1 the Fruits tab, packs, energy, faces and the new items", async () => {
    const player = await create();
    for (const client of [...OLD, null]) {
      const [gated, off] = [await read("/v2/capabilities", player, GATED, client), await read("/v2/capabilities", player, OFF, client)];
      expect(gated, `capabilities ${client}`).toEqual(off);
      expect(gated).not.toHaveProperty("pollen_fruits_version");
      expect(gated).not.toHaveProperty("pollen_app_store_fruit_packs_version");
      expect(gated).not.toHaveProperty("duels_energy_version");
      expect(await read("/v1/pollen", player, GATED, client), `wallet ${client}`).toEqual(await read("/v1/pollen", player, OFF, client));
    }
    const old = await read("/v2/capabilities", player, GATED, "0.8.0 app_store");
    expect(old.pollen_offered_tag).toBe(OFFERED_TAG);
    expect(old.face_packs_version).toBe(1);

    const caps = await read("/v2/capabilities", player, GATED, NEW);
    expect(caps).toMatchObject({ pollen_fruits_version: 1, pollen_app_store_fruit_packs_version: 1, pollen_fruit_packs_version: 1, duels_energy_version: 1, face_packs_version: 2 });
    expect(caps.pollen_offered_tag).not.toBe(OFFERED_TAG);
    expect(caps).toEqual(await read("/v2/capabilities", player, ALL_ON, NEW));
    const wallet = await read("/v1/pollen", player, GATED, NEW) as { fruits?: unknown; energy?: unknown; wardrobe: { offered: string[]; prices: Record<string, number> } };
    expect(wallet.fruits).toBeDefined();
    expect(wallet.energy).toMatchObject({ energy: 5, max: 5 });
    expect(wallet.wardrobe.offered).toEqual(expect.arrayContaining(["paper_boat", "glass_house", "knit", "sea_glass", "aww"]));
    expect(wallet.wardrobe.prices).toHaveProperty("paper_boat");
  });

  it("refuses Fruit spends and the energy refill from an older app", async () => {
    const player = await create();
    await playerConfig(player, GATED);
    const spend = (kind: string, id: string, client: string) => call("/v1/pollen/spend", "POST", player, GATED, client, { schema_version: 1, idempotency_key: crypto.randomUUID(), kind, id, expected_cost: 20 });
    for (const client of OLD) for (const [kind, id] of [["energy", "energy"], ["sunshine", "sunshine"], ["convert", "10"]]) {
      const refused = await spend(kind, id, client);
      expect(refused.status, `${kind} ${client}`).toBe(503);
      expect((await refused.json<{ error: { code: string } }>()).error.code).toBe("fruits_disabled");
    }
    // 0.8.1 reaches the Player: a full meter is not refilled.
    expect((await (await spend("energy", "energy", NEW)).json<{ error: { code: string } }>()).error.code).toBe("energy_full");
  });

  it("costs no Durable Object request or row more for either kind of app", async () => {
    const player = await create();
    const measure = async (vars: Record<string, unknown>, client: string) => {
      await playerConfig(player, vars);
      const meter = countingEnv(env);
      const { rows } = await meterAllRows(async () => {
        for (const path of ["/v2/capabilities", "/v1/pollen"]) expect((await call(path, "GET", player, vars, client, undefined, meter.env)).status, path).toBe(200);
      });
      return { calls: meter.calls, written: rows.written, read: rows.read };
    };
    // A first Fruits read may sweep achievements once (an existing cost of FRUITS itself), so each kind is read once first.
    for (const client of [...OLD, NEW]) await measure(GATED, client);
    for (const client of OLD) expect(await measure(GATED, client), client).toEqual(await measure(OFF, client));
    expect(await measure(GATED, NEW)).toEqual(await measure(ALL_ON, NEW));
  });
});

describe("turn credits", () => {
  const facts = (owner: string): TurnFacts => ({ schema_version: 1, room_id: "R".repeat(22), recording_hash: "a".repeat(64), turn_id: "t0-0-a", player_id: owner, accepted_at: Date.now(),
    week: isoWeek(Date.now()), level_id: "first-steps", stage_id: "first-path", role: "a", ticks: 900, tries: null, premium: false, hard: false, host: true, together: true,
    complete: true, subscriber: false, partner_subscriber: false, boost_percent: 0 });
  const credit = async (vars: Record<string, unknown>, reach: Version | null) => {
    const player = await create();
    await playerConfig(player, vars);
    const stub = env.PLAYERS.getByName(player.player_id);
    const { value, rows } = await meterAllRows(async () => JSON.parse(JSON.stringify(await stub.creditTurn(player.player_id, facts(player.player_id), true, reach))) as { ok: boolean; value: Record<string, unknown> });
    const partner = await create();
    await playerConfig(partner, vars);
    const clear = await meterAllRows(async () => { await env.PLAYERS.getByName(partner.player_id).creditTogetherClear(partner.player_id, "first-steps", false, 0, "R".repeat(22)); });
    return { value, written: rows.written, partner: clear.rows.written };
  };
  it("writes no Fruit row for a chapter an older app finishes, nor for its partner who never read Fruits", async () => {
    const off = await credit(OFF, version("0.7.9"));
    for (const client of OLD) {
      const gated = await credit(GATED, version(client.split(" ")[0]));
      expect(gated.value.ok && !("fruits" in gated.value.value), client).toBe(true);
      expect([gated.written, gated.partner], client).toEqual([off.written, off.partner]);
    }
    // 0.8.1 finishing the same chapter is paid its achievement there and then.
    const shown = await credit(GATED, version("0.8.1"));
    expect(shown.value.ok && "fruits" in shown.value.value).toBe(true);
  });
});

describe("duel energy", () => {
  async function account(): Promise<Account> { return (await call("/v1/identity", "POST", undefined, OFF, NEW, {})).json<Account>(); }
  const spends = (who: Account) => runInDurableObject(env.PLAYERS.getByName(who.player_id), async (_, state) => ledgerLines(state.storage, "energy:", 16).length);
  const vars = () => withConfig({ ...withoutConfig(env), ...GATED }) as unknown as Env;

  it("charges nobody when an older app starts or joins", async () => {
    const [a, b] = [await account(), await account()];
    for (const client of OLD) {
      const done = await withEnergy(vars(), version(client.split(" ")[0]), a.player_id, [a.player_id, b.player_id], "old-" + client.replace(/[^a-z0-9]/g, ""), async () => "made");
      expect(done).toEqual({ value: "made", energy: null });
    }
    expect(await withEnergy(vars(), null, a.player_id, [a.player_id, b.player_id], "old-none", async () => "made")).toEqual({ value: "made", energy: null });
    expect([await spends(a), await spends(b)]).toEqual([0, 0]);
  });

  it("charges a 0.8.1 starter, and a partner only once their own meter has been used, so an older app's partner never pays", async () => {
    const [a, b] = [await account(), await account()];
    const v081 = version("0.8.1");
    expect(await withEnergy(vars(), v081, a.player_id, [a.player_id, b.player_id], "duel-1", async () => "made")).toMatchObject({ energy: { energy: 4 } });
    expect([await spends(a), await spends(b)]).toEqual([1, 0]);
    // b starts from 0.8.1 too: b pays, and a (whose meter was used) pays as the partner.
    await withEnergy(vars(), v081, b.player_id, [b.player_id, a.player_id], "duel-2", async () => "made");
    expect([await spends(a), await spends(b)]).toEqual([2, 1]);
    // From then on both pay whoever starts, as with ENERGY on for every app.
    await withEnergy(vars(), v081, a.player_id, [a.player_id, b.player_id], "duel-3", async () => "made");
    expect([await spends(a), await spends(b)]).toEqual([3, 2]);
  });
});
