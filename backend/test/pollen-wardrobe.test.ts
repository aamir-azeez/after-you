import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { POLLEN_HEADER } from "../src/pollen/routes";
import { creditClear, noteFullJourney } from "../src/pollen/wallet";
import { EVERY_HARD, EVERY_HARD_LEVELS } from "../src/pollen/earned";
import { shopOn, wardrobeMode, wardrobeOn } from "../src/pollen/features";
import { chapterTier } from "../src/pollen/rates";
import { CATALOG, EARNED_TIER } from "../src/pollen/catalog";
import { BoardRewardLedger, openRewardSync, REWARD_ITEMS } from "../src/leaderboards/rewards";
import { boardKeys } from "../src/leaderboards/boards";
import { deriveJobToken } from "../src/leaderboards/job-token";
import { entryId, pairKey, type LeaderboardRun } from "../src/leaderboards/run";
import { CHAPTERS } from "../src/v2/chapters";
import { POLLEN_EARNED_TABLES } from "../src/storage-schema";
import { countingEnv } from "./meter";
import manifest from "../../game/tests/fixtures/golden/chapter_manifest.json";

// The wardrobe without the shop (POLLEN_WARDROBE), the shop on top of it (POLLEN_SHOP), and earned
// items reaching a player: board rewards through the replay job, and Every Hard. Synthetic identities only.
type Account = { player_id: string; device_token: string; recovery_code: string };
type Wallet = { balance: number; wardrobe?: Record<string, unknown>; name_price?: number };
const SECRET = "synthetic-pollen-secret-for-tests-only-0001";
const OPERATOR = "o".repeat(43);
const BASE = { V2_ROOMS_ENABLED: "true", DISPLAY_NAMES_ENABLED: "true", POLLEN_SECRET: SECRET, SAFETY_OPERATOR_TOKEN: OPERATOR };
const EARN = { ...BASE, FEATURES: "POLLEN_EARN" };
const WARDROBE = { ...BASE, FEATURES: "POLLEN_EARN,POLLEN_WARDROBE" };
const SHOP = { ...BASE, FEATURES: "POLLEN_EARN,POLLEN_WARDROBE,POLLEN_SHOP" };
const SHOP_NO_WARDROBE = { ...BASE, FEATURES: "POLLEN_EARN,POLLEN_SHOP" };
const WARDROBE_NO_EARN = { ...BASE, FEATURES: "POLLEN_WARDROBE,POLLEN_SHOP" };
const BOARDS_WARDROBE = { ...BASE, FEATURES: "LEADERBOARDS,POLLEN_EARN,POLLEN_WARDROBE" };
const BOARDS_ONLY = { ...BASE, FEATURES: "LEADERBOARDS,POLLEN_EARN" };
const RELAY_BOARD = "relay-isles@2";
const DAY = 86_400_000;
let address = 0;

async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, string> = WARDROBE, headers: Record<string, string> = {}, base: Env = env): Promise<Response> {
  return worker.fetch(new Request("https://wardrobe.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.93." + (++address % 250), [POLLEN_HEADER]: "1",
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), Object.assign({ ...base }, vars) as Env);
}
const shared = env as unknown as Record<string, unknown>;
beforeEach(() => { shared.POLLEN_SECRET = SECRET; });
afterEach(async () => { delete shared.POLLEN_SECRET; await reset(); });

async function create(): Promise<Account> {
  const made = await call("/v1/identity", "POST", undefined, {}); expect(made.status).toBe(201);
  return made.json<Account>();
}
async function fund(account: Account, balance: number): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
    noteFullJourney(state.storage, Date.now() + DAY, Date.now());
    state.storage.sql.exec("UPDATE pollen_wallet SET data=json_set(data,'$.balance',?,'$.earned',?) WHERE id=1", balance, balance);
  });
}
async function hardClears(account: Account, levels: readonly string[]): Promise<void> {
  await runInDurableObject(env.PLAYERS.getByName(account.player_id), async (_, state) => {
    for (const level of levels) expect(creditClear(state.storage, { level_id: level, hard: true, boost_percent: 0 }, Date.now(), () => true).ok, level).toBe(true);
  });
}
const wallet = async (account: Account, vars: Record<string, string> = WARDROBE) => (await call("/v1/pollen", "GET", account, undefined, vars)).json<Wallet>();
const capabilities = async (account: Account, vars: Record<string, string>) => (await call("/v2/capabilities", "GET", account, undefined, vars)).json<Record<string, unknown>>();
const equipBody = (look: Record<string, string>, revision = Date.now()) => ({ schema_version: 1, idempotency_key: crypto.randomUUID(), revision, look });
const spendBody = (id: string, expected_cost: number) => ({ schema_version: 1, idempotency_key: crypto.randomUUID(), kind: "item", id, expected_cost });
const errorOf = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;
/** Gives the player an earned item as a board delivery would. */
const giveBoardItems = (account: Account, items: string[], seq: number, board = RELAY_BOARD) =>
  env.PLAYERS.getByName(account.player_id).noteBoardRewards(account.player_id, board, items, seq);

describe("the flags", () => {
  it("reads the wardrobe on only with earning, and the shop only with the wardrobe", () => {
    const vars = (features: string, secret = true) => ({ FEATURES: features, ...(secret ? { POLLEN_SECRET: SECRET } : {}) });
    expect([wardrobeMode(vars("POLLEN_EARN")), wardrobeMode(vars("POLLEN_EARN,POLLEN_WARDROBE")), wardrobeMode(vars("POLLEN_EARN,POLLEN_WARDROBE,POLLEN_SHOP"))]).toEqual(["off", "wardrobe", "shop"]);
    expect(wardrobeOn(vars("POLLEN_WARDROBE"))).toBe(false);
    expect(wardrobeOn(vars("POLLEN_EARN,POLLEN_WARDROBE", false))).toBe(false);
    expect(shopOn(vars("POLLEN_EARN,POLLEN_SHOP"))).toBe(false);
    expect(wardrobeMode(vars("POLLEN_EARN,POLLEN_SHOP"))).toBe("off");
  });
});

describe("each route under each combination", () => {
  type Expect = { caps: string[]; wardrobe: "none" | "owned" | "shop"; equip: number; spend: number; equipCode?: string; spendCode?: string };
  const cases: [string, Record<string, string>, Expect][] = [
    ["earning only", EARN, { caps: ["pollen_version"], wardrobe: "none", equip: 503, spend: 503, equipCode: "pollen_wardrobe_disabled", spendCode: "pollen_shop_disabled" }],
    ["earning and the wardrobe", WARDROBE, { caps: ["pollen_version", "pollen_wardrobe_version"], wardrobe: "owned", equip: 200, spend: 503, spendCode: "pollen_shop_disabled" }],
    ["earning, the wardrobe and the shop", SHOP, { caps: ["pollen_version", "pollen_wardrobe_version", "pollen_shop_version"], wardrobe: "shop", equip: 200, spend: 200 }],
    ["the shop without the wardrobe", SHOP_NO_WARDROBE, { caps: ["pollen_version"], wardrobe: "none", equip: 503, spend: 503, equipCode: "pollen_wardrobe_disabled", spendCode: "pollen_shop_disabled" }],
  ];
  it.each(cases)("%s", async (_name, vars, expected) => {
    const player = await create(); await fund(player, 5000);
    expect((await giveBoardItems(player, ["gold_leaf"], 1)).ok).toBe(true);
    const caps = await capabilities(player, vars);
    expect(Object.keys(caps).filter(key => key.startsWith("pollen_")).sort()).toEqual([...expected.caps].sort());
    const read = await wallet(player, vars);
    expect(read.balance).toBe(5000);
    if (expected.wardrobe === "none") { expect(read).not.toHaveProperty("wardrobe"); expect(read).not.toHaveProperty("name_price"); }
    if (expected.wardrobe === "owned") {
      expect(read.wardrobe).toEqual({ items: ["gold_leaf"], packs: [], look: {}, look_revision: 0, offered: Object.keys(CATALOG.items).filter(id => CATALOG.items[id].released) });
      expect(read).not.toHaveProperty("name_price");
    }
    if (expected.wardrobe === "shop") {
      expect(read.wardrobe).toMatchObject({ items: ["gold_leaf"], prices: { daisy: 1000 }, unlocked: [] });
      expect(read.name_price).toBe(0);
    }
    const equipped = await call("/v1/pollen/equip", "POST", player, equipBody({ leaf: "gold_leaf" }), vars);
    expect(equipped.status).toBe(expected.equip);
    if (expected.equipCode) expect(await errorOf(equipped)).toBe(expected.equipCode);
    const bought = await call("/v1/pollen/spend", "POST", player, spendBody("daisy", 1000), vars);
    expect(bought.status).toBe(expected.spend);
    if (expected.spendCode) expect(await errorOf(bought)).toBe(expected.spendCode);
  });
  it("is all off without earning, whatever else FEATURES lists", async () => {
    const player = await create();
    expect(Object.keys(await capabilities(player, WARDROBE_NO_EARN)).filter(key => key.startsWith("pollen_"))).toEqual([]);
    expect((await call("/v1/pollen/equip", "POST", player, equipBody({}), WARDROBE_NO_EARN)).status).toBe(404);
  });
});

describe("the wardrobe without the shop", () => {
  it("wears and takes off earned items, refuses what is not owned, and charges nothing for a name", async () => {
    const player = await create(); await fund(player, 5000);
    const unowned = await call("/v1/pollen/equip", "POST", player, equipBody({ hat: "daisy" }));
    expect(unowned.status).toBe(403); expect(await errorOf(unowned)).toBe("not_owned");
    expect((await giveBoardItems(player, ["gold_leaf", "top_ten_ribbon"], 1)).ok).toBe(true);
    const revision = Date.now();
    expect((await call("/v1/pollen/equip", "POST", player, equipBody({ leaf: "gold_leaf", hat: "top_ten_ribbon" }, revision))).status).toBe(200);
    expect((await wallet(player)).wardrobe).toMatchObject({ items: ["gold_leaf", "top_ten_ribbon"], look: { leaf: "gold_leaf", hat: "top_ten_ribbon" }, look_revision: revision });
    expect((await call("/v1/pollen/equip", "POST", player, equipBody({ hat: "top_ten_ribbon" }, revision + 1))).status).toBe(200);
    expect((await wallet(player)).wardrobe).toMatchObject({ look: { hat: "top_ten_ribbon" } });
    // No paid name change while the shop is off: a third change is free, and a price sent along is ignored.
    let rev = Date.now();
    for (const name of ["One", "Two", "Three", "Four"]) expect((await call("/v1/profile/name", "PUT", player, { schema_version: 1, display_name: name, revision: ++rev, pollen_price: 0 })).status, name).toBe(200);
    expect((await wallet(player)).balance).toBe(5000);
  });
  it("reads the wallet with one Player request, as before", async () => {
    const player = await create(); await fund(player, 100);
    const meter = countingEnv(Object.assign({ ...env }, WARDROBE) as Env);
    expect((await call("/v1/pollen", "GET", player, undefined, WARDROBE, {}, meter.env)).status).toBe(200);
    expect(meter.calls).toEqual(["PLAYERS.authorizeWallet"]);
  });
  it("shows looks in rooms with POLLEN_LOOKS on: the worn earned item rides into the room", async () => {
    const host = await create(), guest = await create();
    expect((await giveBoardItems(host, ["gold_leaf"], 1)).ok).toBe(true);
    const LOOKS = { ...BASE, FEATURES: "POLLEN_EARN,POLLEN_WARDROBE,POLLEN_LOOKS" };
    expect((await call("/v1/pollen/equip", "POST", host, equipBody({ leaf: "gold_leaf" }), LOOKS)).status).toBe(200);
    const made = await call("/v2/rooms", "POST", host, { idempotency_key: crypto.randomUUID(), level_id: "relay-isles", level_version: 2, definition_hash: CHAPTERS[0].adapter.key.definition_hash }, LOOKS, { "X-AfterYou-Looks": "1" });
    expect(made.status).toBe(200);
    const room = await made.json<{ invite_code: string; room_id: string }>();
    expect((await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code }, LOOKS, { "X-AfterYou-Looks": "1" })).status).toBe(200);
    const seen = await call(`/v2/rooms/${room.room_id}`, "GET", guest, undefined, LOOKS, { "X-AfterYou-Looks": "1" });
    expect(await seen.json()).toMatchObject({ partner_look: { leaf: "gold_leaf" } });
  });
});

describe("Every Hard", () => {
  it("lists every chapter the game offers Hard on, each one a chapter the rates pay a first clear for", () => {
    const rows = Object.values(manifest.chapters) as { level_id: string; hard: boolean }[];
    expect([...new Set(rows.filter(row => row.hard).map(row => row.level_id))].sort()).toEqual([...EVERY_HARD_LEVELS].sort());
    for (const level of EVERY_HARD_LEVELS) expect(chapterTier(level), level).not.toBeNull();
    expect(CATALOG.items[EVERY_HARD].tier).toBe(EARNED_TIER);
  });
  it("is earned with the last together Hard first clear, kept, and written once", async () => {
    const player = await create();
    await hardClears(player, EVERY_HARD_LEVELS.slice(0, -1));
    expect((await wallet(player)).wardrobe!.items).toEqual([]);
    await hardClears(player, EVERY_HARD_LEVELS.slice(-1));
    expect((await wallet(player)).wardrobe!.items).toEqual([EVERY_HARD]);
    const rows = await runInDurableObject(env.PLAYERS.getByName(player.player_id), async (_, state) => state.storage.sql.exec<{ source: string; items: string }>("SELECT source,items FROM pollen_earned").toArray());
    expect(rows).toEqual([{ source: EVERY_HARD, items: JSON.stringify([EVERY_HARD]) }]);
    expect((await call("/v1/pollen/equip", "POST", player, equipBody({ leaf: EVERY_HARD }))).status).toBe(200);
  });
  it("is recorded while only earning is on, so the wardrobe shows it once it goes on", async () => {
    const player = await create();
    await hardClears(player, EVERY_HARD_LEVELS);
    expect(await wallet(player, EARN)).not.toHaveProperty("wardrobe");
    expect((await wallet(player, WARDROBE)).wardrobe!.items).toEqual([EVERY_HARD]);
  });
  it("needs Hard clears: plain first clears of every chapter give nothing", async () => {
    const player = await create();
    await runInDurableObject(env.PLAYERS.getByName(player.player_id), async (_, state) => {
      for (const level of EVERY_HARD_LEVELS) creditClear(state.storage, { level_id: level, hard: false, boost_percent: 0 }, Date.now(), () => true);
    });
    expect((await wallet(player)).wardrobe!.items).toEqual([]);
  });
});

describe("board rewards reaching a player", () => {
  const operator = (action: string, vars: Record<string, string>, base?: Env) => deriveJobToken(OPERATOR).then(token =>
    call(`/operator/leaderboards/${action}`, "POST", undefined, { schema_version: 1 }, vars, { Authorization: "Bearer " + token }, base));
  const board = () => env.LEADERBOARD_BOARDS.getByName(RELAY_BOARD);
  let serial = 0;
  async function rank(members: [string, string], ticks: number, finished_ms = 1000 + ++serial): Promise<LeaderboardRun> {
    const run: LeaderboardRun = { schema_version: 1, board: RELAY_BOARD, entry_id: await entryId(`room${++serial}`.padEnd(22, "z"), 0), pair_key: await pairKey(...members), members, ticks,
      finished_at: new Date(finished_ms).toISOString(), finished_ms, chapter: { ...CHAPTERS[0].adapter.key }, simulation_version: 8, checkpoint: { stage_index: 2, marker: serial } as never };
    await board().submit(RELAY_BOARD, run);
    await board().standings(RELAY_BOARD, [{ entry_id: run.entry_id, eligible: true, reason: "", members: [{ show: false, name: null, rev: 0 }, { show: false, name: null, rev: 0 }] }]);
    const work = await board().pendingWork();
    const mine = work.replay.find(item => item.entry_id === run.entry_id)!;
    await board().verdicts(RELAY_BOARD, [{ entry_id: run.entry_id, proof_hash: mine.proof_hash, valid: true, measured_ticks: ticks, reason: "" }], 1);
    return run;
  }
  const items = async (account: Account) => (await wallet(account)).wardrobe!.items as string[];

  it("maps each reward to an earned catalogue item", () => {
    for (const item of Object.values(REWARD_ITEMS)) expect(CATALOG.items[item].tier).toBe(EARNED_TIER);
  });
  it("gives both players of a ranked pair their ribbon and Gold leaf at the next pending call, once", async () => {
    const host = await create(), guest = await create();
    await rank([host.player_id, guest.player_id], 100);
    expect(await items(host)).toEqual([]);
    const meter = countingEnv(Object.assign({ ...env }, BOARDS_WARDROBE) as Env);
    expect((await operator("pending", BOARDS_WARDROBE, meter.env)).status).toBe(200);
    expect(meter.calls.filter(name => name === "PLAYERS.noteBoardRewards")).toHaveLength(2);
    expect(meter.calls.filter(name => name === "LEADERBOARD_BOARDS.rewardsDelivered")).toHaveLength(1);
    expect(await items(host)).toEqual(["gold_leaf", "top_ten_ribbon"]);
    expect(await items(guest)).toEqual(["gold_leaf", "top_ten_ribbon"]);
    // Nothing marked any more: the next pending call costs one request per board, as before the wardrobe.
    const again = countingEnv(Object.assign({ ...env }, BOARDS_WARDROBE) as Env);
    expect((await operator("pending", BOARDS_WARDROBE, again.env)).status).toBe(200);
    expect(again.calls).toEqual(boardKeys().map(() => "LEADERBOARD_BOARDS.pendingWork"));
  });
  it("keeps the marks while the wardrobe is off and delivers them once it is on", async () => {
    const host = await create(), guest = await create();
    await rank([host.player_id, guest.player_id], 100);
    expect((await operator("pending", BOARDS_ONLY)).status).toBe(200);
    expect(await items(host)).toEqual([]);
    expect((await operator("pending", BOARDS_WARDROBE)).status).toBe(200);
    expect(await items(host)).toEqual(["gold_leaf", "top_ten_ribbon"]);
  });
  it("takes a struck run's leaf back, off the look too, and the pair keeps what another run earned", async () => {
    const host = await create(), guest = await create(), other = await create(), friend = await create();
    await rank([other.player_id, friend.player_id], 200);
    // Close enough to first place that no person has to look at it first (rules.ts holdsFor).
    const fake = await rank([host.player_id, guest.player_id], 195);
    expect((await operator("pending", BOARDS_WARDROBE)).status).toBe(200);
    expect(await items(host)).toEqual(["gold_leaf", "top_ten_ribbon"]);
    expect(await items(other)).toEqual(["gold_leaf", "top_ten_ribbon"]);
    expect((await call("/v1/pollen/equip", "POST", host, equipBody({ leaf: "gold_leaf", hat: "top_ten_ribbon" }))).status).toBe(200);
    expect((await board().strike(RELAY_BOARD, fake.entry_id)).done).toBe(true);
    expect((await operator("pending", BOARDS_WARDROBE)).status).toBe(200);
    expect(await items(host)).toEqual([]);
    expect((await wallet(host)).wardrobe!.look).toEqual({});
    // The pushed-down pair keeps theirs, and holds first place again.
    expect(await items(other)).toEqual(["gold_leaf", "top_ten_ribbon"]);
  });
  it("never lets an older delivery undo a newer one, and answers a deleted player as done", async () => {
    const player = await create();
    expect(await giveBoardItems(player, ["gold_leaf", "top_ten_ribbon"], 20)).toMatchObject({ ok: true, value: { changed: true } });
    expect(await giveBoardItems(player, [], 10)).toMatchObject({ ok: true, value: { changed: false } });
    expect(await giveBoardItems(player, ["gold_leaf", "top_ten_ribbon"], 20)).toMatchObject({ ok: true, value: { changed: false } });
    expect(await items(player)).toEqual(["gold_leaf", "top_ten_ribbon"]);
    expect(await giveBoardItems(player, ["top_ten_ribbon"], 30)).toMatchObject({ ok: true, value: { changed: true } });
    expect(await items(player)).toEqual(["top_ten_ribbon"]);
    // A second board's Gold leaf stays when this board's goes.
    expect((await giveBoardItems(player, ["gold_leaf"], 1, "first-steps@1")).ok).toBe(true);
    expect((await giveBoardItems(player, [], 40)).ok).toBe(true);
    expect(await items(player)).toEqual(["gold_leaf"]);
    for (const bad of [[["daisy"], 50], [["gold_leaf", "gold_leaf"], 50], [["gold_leaf"], 0]] as [string[], number][]) {
      expect(await giveBoardItems(player, bad[0], bad[1]), JSON.stringify(bad)).toMatchObject({ ok: false, status: 400 });
    }
    expect(await env.PLAYERS.getByName(player.player_id).noteBoardRewards(player.player_id, "nowhere@1", ["gold_leaf"], 60)).toMatchObject({ ok: false, status: 400 });
    expect((await call("/v1/identity", "DELETE", player)).status).toBe(200);
    expect(await giveBoardItems(player, ["gold_leaf"], 70)).toMatchObject({ ok: false, code: "identity_absent" });
    const tables = await runInDurableObject(env.PLAYERS.getByName(player.player_id), async (_, state) =>
      state.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE name=?", POLLEN_EARNED_TABLES[0].name).toArray());
    expect(tables).toEqual([]);
  });
  it("never lets an older delivery bring back what a newer, empty one took, even with nothing stored before", async () => {
    const player = await create();
    expect(await giveBoardItems(player, [], 6)).toMatchObject({ ok: true, value: { changed: false } });
    expect(await giveBoardItems(player, ["gold_leaf"], 5)).toMatchObject({ ok: true, value: { changed: false } });
    expect(await items(player)).toEqual([]);
  });
  it("gives a released or unreleased earned item alike, and refuses anything sold", async () => {
    const player = await create();
    expect(await giveBoardItems(player, ["every_hard"], 1)).toMatchObject({ ok: true });
    expect(await giveBoardItems(player, ["lighthouse_lamp"], 2)).toMatchObject({ ok: false, status: 400 });
  });
  it("marks a player only when what the board gives them changes, and moves a failed delivery behind the rest", async () => {
    const pair: [string, string] = ["p".repeat(22), "q".repeat(22)];
    await rank(pair, 200);
    const marks = () => runInDurableObject(board(), async (_, state) =>
      state.storage.sql.exec<{ player_id: string; seq: number }>("SELECT player_id,seq FROM lb_reward_sync WHERE player_id!='' ORDER BY seq, player_id").toArray());
    const first = await marks();
    expect(first.map(row => row.player_id).sort()).toEqual([...pair].sort());
    await runInDurableObject(board(), async (_, state) => new BoardRewardLedger(state.storage).delivered(first));
    expect(await marks()).toEqual([]);
    // The same pair beats its own time: a new ribbon grant, but nothing new to wear.
    await rank(pair, 190);
    expect(await marks()).toEqual([]);
    await runInDurableObject(board(), async (_, state) => {
      const ledger = new BoardRewardLedger(state.storage);
      state.storage.sql.exec("INSERT INTO lb_reward_sync VALUES (?,?),(?,?)", pair[0], 10, pair[1], 11);
      ledger.delivered([], [{ player_id: pair[0], seq: 10 }, { player_id: pair[1], seq: 99 }]);
    });
    const moved = await marks();
    expect(moved.map(row => row.player_id)).toEqual([pair[1], pair[0]]);
    expect(moved[1].seq).toBeGreaterThan(11);
    expect(moved[0].seq).toBe(11);
  });
  it("forgets an erased player's marks with their grants", async () => {
    const host = await create(), guest = await create();
    await rank([host.player_id, guest.player_id], 100);
    await board().forget(RELAY_BOARD, host.player_id);
    const marked = await runInDurableObject(board(), async (_, state) =>
      state.storage.sql.exec<{ player_id: string }>("SELECT player_id FROM lb_reward_sync WHERE player_id!=''").toArray().map(row => row.player_id));
    expect(marked).toEqual([guest.player_id]);
  });
  it("backfills a board whose grants were recorded before deliveries existed", async () => {
    const host = await create(), guest = await create();
    await rank([host.player_id, guest.player_id], 100);
    await runInDurableObject(board(), async (_, state) => {
      state.storage.sql.exec("DROP TABLE lb_reward_sync");
      openRewardSync(state.storage);
      openRewardSync(state.storage);
      const marked = state.storage.sql.exec<{ player_id: string }>("SELECT player_id FROM lb_reward_sync WHERE player_id!='' ORDER BY player_id").toArray().map(row => row.player_id);
      expect(marked).toEqual([host.player_id, guest.player_id].sort());
    });
    expect((await operator("pending", BOARDS_WARDROBE)).status).toBe(200);
    expect(await items(guest)).toEqual(["gold_leaf", "top_ten_ribbon"]);
  });
});
