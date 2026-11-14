import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { POLLEN_HEADER } from "../src/pollen/routes";
import { noteFullJourney } from "../src/pollen/wallet";
import { CATALOG, ownedFaces } from "../src/pollen/catalog";
import { DEFAULT_SLOTS, FREE_SLOTS, SLOT_COUNT, slotsAllowed, validSlots } from "../src/pollen/reaction-loadout";
import { POLLEN_CLIENT, withConfig } from "./config";

// Face cosmetics on the wardrobe (FACE_SINGLES): the reaction slots kept beside the look, the resting face slot, the
// reaction slot items, and a face owned through a pack never sold again. Synthetic identities only.
type Account = { player_id: string; device_token: string; recovery_code: string };
type Wardrobe = { items: string[]; faces?: string[]; reactions?: string[]; reaction_slots?: number; look: Record<string, string>; prices?: Record<string, number> };
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const DAY = 86_400_000;
const SHOP = { POLLEN_SECRET: SECRET, features: ["POLLEN_EARN", "POLLEN_WARDROBE", "POLLEN_SHOP"] };
const codes = (...ids: string[]) => ids.map(id => CATALOG.items[id].code);
const FACES_ON = (...released: string[]) => ({ ...SHOP, features: [...SHOP.features, "FACE_SINGLES"], cosmetics_released: codes(...released) });
let address = 0;

/** The Player reads its own CONFIG, which the Worker's vars never reach (as in production, both come from the one deploy): set it there too. */
const objectConfigs = new Map<Record<string, unknown>, unknown>();
async function playerConfig(account: Account, vars: Record<string, unknown>): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), instance => {
    const target = Reflect.get(instance, "env") as Record<string, unknown>;
    if (!objectConfigs.has(target)) objectConfigs.set(target, target.CONFIG);
    target.CONFIG = withConfig(vars).CONFIG;
  });
}
async function call(path: string, method: string, account: Account | undefined, body: unknown, vars: Record<string, unknown>): Promise<Response> {
  if (account) await playerConfig(account, vars);
  return worker.fetch(new Request("https://faces.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.94." + (++address % 250), [POLLEN_HEADER]: "1", ...POLLEN_CLIENT,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) }), withConfig(Object.assign(withoutConfig(), vars)) as unknown as Env);
}
/** The env's own vars without the CONFIG set for the Player (in the test runtime the Player shares `env`). */
function withoutConfig(): Record<string, unknown> {
  const { CONFIG: _config, ...rest } = env as unknown as Record<string, unknown>; void _config;
  return rest;
}
const shared = env as unknown as Record<string, unknown>;
beforeEach(() => { shared.POLLEN_SECRET = SECRET; });
afterEach(async () => {
  for (const [target, value] of objectConfigs) { if (value === undefined) delete target.CONFIG; else target.CONFIG = value; }
  objectConfigs.clear();
  delete shared.POLLEN_SECRET; await reset();
});

async function create(): Promise<Account> {
  const made = await call("/v1/identity", "POST", undefined, {}, SHOP); expect(made.status).toBe(201);
  return made.json<Account>();
}
async function fund(account: Account, balance: number): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
    noteFullJourney(state.storage, Date.now() + DAY, Date.now());
    state.storage.sql.exec("UPDATE pollen_wallet SET data=json_set(data,'$.balance',?,'$.earned',?) WHERE id=1", balance, balance);
  });
}
const wardrobe = async (account: Account, vars: Record<string, unknown>) => (await (await call("/v1/pollen", "GET", account, undefined, vars)).json<{ wardrobe: Wardrobe }>()).wardrobe;
let revision = Date.now();
const equip = (account: Account, look: Record<string, string>, vars: Record<string, unknown>, reactions?: unknown) =>
  call("/v1/pollen/equip", "POST", account, { schema_version: 1, idempotency_key: crypto.randomUUID(), revision: ++revision, look, ...(reactions === undefined ? {} : { reactions }) }, vars);
const buy = (account: Account, kind: string, id: string, cost: number, vars: Record<string, unknown>) =>
  call("/v1/pollen/spend", "POST", account, { schema_version: 1, idempotency_key: crypto.randomUUID(), kind, id, expected_cost: cost }, vars);
const errorOf = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;

describe("the reaction slots", () => {
  it("have their shape: six places, faces once, never the heart", () => {
    expect(SLOT_COUNT).toBe(6); expect(FREE_SLOTS).toBe(4);
    expect(validSlots([...DEFAULT_SLOTS])).toBe(true);
    for (const bad of [DEFAULT_SLOTS.slice(0, 5), ["happy", "happy", "", "", "", ""], ["heart", "", "", "", "", ""], ["nope", "", "", "", "", ""], [1, "", "", "", "", ""], "happy"]) expect(validSlots(bad), JSON.stringify(bad)).toBe(false);
    // A face in a place past the open ones, or one not owned, is not allowed.
    expect(slotsAllowed(["happy", "", "", "", "sad", ""], new Set(), 0)).toBe(false);
    expect(slotsAllowed(["happy", "", "", "", "sad", ""], new Set(), 1)).toBe(true);
    expect(slotsAllowed(["yay", "", "", "", "", ""], new Set(), 0)).toBe(false);
    expect(slotsAllowed(["yay", "", "", "", "", ""], new Set(["yay"]), 0)).toBe(true);
    expect(ownedFaces(["garden_faces", "aww", "daisy"])).toEqual(["aww", "heart_eyes", "proud", "wink"]);
  });

  it("are not read, written or offered while FACE_SINGLES is off", async () => {
    const player = await create();
    const plain = await wardrobe(player, SHOP);
    expect(plain).not.toHaveProperty("faces"); expect(plain).not.toHaveProperty("reactions");
    const refused = await equip(player, {}, SHOP, [...DEFAULT_SLOTS]);
    expect(refused.status).toBe(400); expect(await errorOf(refused)).toBe("invalid_pollen_equip");
    // A released face code is still not sold while the switch is off.
    await fund(player, 10_000);
    const off = { ...SHOP, cosmetics_released: codes("aww", "rest_bean", "reaction_slot_5") };
    expect((await wardrobe(player, off)).prices).not.toHaveProperty("aww");
    expect((await buy(player, "item", "aww", 1000, off)).status).toBe(409);
  });

  it("start with the free starters, keep a saved order, open one place per slot bought and refuse what is not owned", async () => {
    const player = await create();
    const vars = FACES_ON("aww", "reaction_slot_5");
    expect(await wardrobe(player, vars)).toMatchObject({ faces: [], reactions: [...DEFAULT_SLOTS], reaction_slots: 4 });
    const swapped = ["sad", "happy", "angry", "squeeze", "", ""];
    expect((await equip(player, {}, vars, swapped)).status).toBe(200);
    expect((await wardrobe(player, vars)).reactions).toEqual(swapped);
    expect(await errorOf(await equip(player, {}, vars, ["aww", "", "", "", "", ""]))).toBe("not_owned");
    expect(await errorOf(await equip(player, {}, vars, ["happy", "", "", "", "sad", ""]))).toBe("not_owned");
    await fund(player, 10_000);
    expect((await buy(player, "item", "aww", 1000, vars)).status).toBe(200);
    expect((await buy(player, "item", "reaction_slot_5", 2500, vars)).status).toBe(200);
    const five = ["aww", "happy", "", "", "sad", ""];
    expect((await equip(player, {}, vars, five)).status).toBe(200);
    expect(await wardrobe(player, vars)).toMatchObject({ faces: ["aww"], reactions: five, reaction_slots: 5 });
    // An equip without slots (an app older than the faces) keeps them.
    expect((await equip(player, {}, vars)).status).toBe(200);
    expect((await wardrobe(player, vars)).reactions).toEqual(five);
  });

  it("count a pack's faces as owned and never sell one of them again", async () => {
    const player = await create();
    await fund(player, 10_000);
    const vars = FACES_ON("wink");
    // Garden faces still sells while none of its faces sells alone.
    expect((await buy(player, "pack", "garden_faces", 5000, SHOP)).status).toBe(200);
    expect((await wardrobe(player, vars)).faces).toEqual(["heart_eyes", "proud", "wink"]);
    expect(await errorOf(await buy(player, "item", "wink", 1000, vars))).toBe("already_owned");
    expect((await equip(player, {}, vars, ["wink", "heart_eyes", "", "", "", ""])).status).toBe(200);
    // With Wink sold alone, its pack no longer sells; the other pack still does.
    const other = await create();
    await fund(other, 10_000);
    expect(await errorOf(await buy(other, "pack", "garden_faces", 5000, vars))).toBe("not_for_sale");
    expect((await buy(other, "pack", "big_feelings", 5000, vars)).status).toBe(200);
  });
});

describe("the resting face", () => {
  it("is worn in its own look slot, and an older app's equip leaves it on", async () => {
    const player = await create();
    await fund(player, 10_000);
    const vars = FACES_ON("rest_bean", "daisy");
    expect((await buy(player, "item", "rest_bean", 1000, vars)).status).toBe(200);
    expect((await buy(player, "item", "daisy", 1000, vars)).status).toBe(200);
    expect((await equip(player, { rest_face: "rest_bean" }, vars, [...DEFAULT_SLOTS])).status).toBe(200);
    expect((await wardrobe(player, vars)).look).toEqual({ rest_face: "rest_bean" });
    // An older app sends the whole look with no slots and no resting face: the resting face stays.
    expect((await equip(player, { hat: "daisy" }, vars)).status).toBe(200);
    expect((await wardrobe(player, vars)).look).toEqual({ hat: "daisy", rest_face: "rest_bean" });
    // A current app takes it off by sending its slots with a look that leaves it out.
    expect((await equip(player, { hat: "daisy" }, vars, [...DEFAULT_SLOTS])).status).toBe(200);
    expect((await wardrobe(player, vars)).look).toEqual({ hat: "daisy" });
    // A resting face not owned is refused like any item.
    expect(await errorOf(await equip(player, { rest_face: "rest_round" }, vars, [...DEFAULT_SLOTS]))).toBe("not_owned");
  });
});
