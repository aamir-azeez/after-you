import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { APP } from "../src/config";
import { CLIENT_HEADER } from "../src/app-status";
import { PLATFORM_HEADER } from "../src/platform-gate";
import { countingEnv } from "./meter";
import { withConfig } from "./config";

/**
 * REQUIRE_PLATFORM (platform-gate.ts): online writes need a Play Games or Game Center link, gated by app version,
 * with the mark kept on the identity row so no request pays for it, and the way in and the way out always open.
 */
type Account = { player_id: string; device_token: string; recovery_code: string };
const APP_ID = APP.playGamesAppId, SECRET = "synthetic-client-secret", CODE_PREFIX = "4/0Asynthetic-";
const NEW = "0.9.0 play", OLD = "0.8.1 play";
let address = 0;
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

const vars = (gate: Record<string, string> | null, revenuecat: Record<string, unknown> = {}) => withConfig({ ...env, PLAY_GAMES_ENABLED: "true", PLAY_GAMES_CLIENT_SECRET: SECRET,
  ...(gate ? { feature_min_version: gate } : {}), ...(Object.keys(revenuecat).length ? { revenuecat } : {}) }) as unknown as Env;
const ON = vars({ REQUIRE_PLATFORM: "0.9.0" });
const OFF = vars(null);

async function call(path: string, method: string, account: Account | undefined, base: Env, client: string | null = NEW, body?: unknown, headers: Record<string, string> = {}) {
  return worker.fetch(new Request("https://gate.test" + path, { method, body: body === undefined ? undefined : JSON.stringify(body),
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100." + (++address % 250), ...(client ? { [CLIENT_HEADER]: client } : {}), ...headers,
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) } }), base);
}
const create = async (): Promise<Account> => (await call("/v1/identity", "POST", undefined, OFF, null, {})).json<Account>();
/** A gated write: sending a friend request (its own answer does not matter, only whether the rule stopped it). */
const write = (account: Account, base: Env, client: string | null = NEW) => call("/v1/friends/requests", "POST", account, base, client, { friend_id: "z".repeat(22) });
const refused = async (response: Response) => response.status === 403 && (await response.clone().json<{ error: { code: string } }>()).error.code === "platform_required";

function google(players: Record<string, string>) {
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = String(input);
    if (url === "https://oauth2.googleapis.com/token") {
      const code = new URLSearchParams(String(init?.body)).get("code")!.replace(CODE_PREFIX, "");
      return Response.json({ access_token: "synthetic-access-" + code, expires_in: 3599, token_type: "Bearer" });
    }
    if (url === `https://games.googleapis.com/games/v1/applications/${APP_ID}/verify`) {
      const token = new Headers(init?.headers).get("Authorization")!.replace("Bearer synthetic-access-", "");
      return Response.json({ kind: "games#applicationVerifyResponse", player_id: players[token] });
    }
    throw new Error("unexpected fetch " + url);
  });
}
const link = (a: Account, code: string, base: Env, replace?: boolean) => call("/v1/platform/link", "POST", a, base, NEW,
  { schema_version: 1, provider: "play_games", credential: { server_auth_code: CODE_PREFIX + code }, recovery_code: a.recovery_code, ...(replace ? { replace } : {}) });
const capability = async (a: Account, base: Env) => (await call("/v2/capabilities", "GET", a, base, NEW, undefined, { [PLATFORM_HEADER]: "1" })).json<Record<string, unknown>>();

describe("REQUIRE_PLATFORM", () => {
  it("changes nothing while off, for older apps, or for requests naming no app", async () => {
    const a = await create();
    expect(await refused(await write(a, OFF))).toBe(false);
    expect(await refused(await write(a, ON, OLD))).toBe(false);
    expect(await refused(await write(a, ON, null))).toBe(false);
    expect(await capability(a, OFF)).not.toHaveProperty("platform_required_version");
  });
  it("refuses an unlinked player's online writes, and lets them through once linked, with no per-request cost", async () => {
    const a = await create(); google({ "code-a": "g-player-one" });
    expect(await refused(await write(a, ON))).toBe(true);
    expect(await capability(a, ON)).toMatchObject({ platform_required_version: 1, platform_linked: false });
    expect((await link(a, "code-a", ON)).status).toBe(200);
    expect(await capability(a, ON)).toMatchObject({ platform_required_version: 1, platform_linked: true });
    const counted = countingEnv(ON);
    expect(await refused(await write(a, counted.env))).toBe(false);
    expect(counted.calls.filter(name => name.startsWith("PLATFORM_LINKS."))).toEqual([]);
  });
  it("keeps the way in and the way out open: reads, linking, bundle claims, safety and deletion", async () => {
    const a = await create();
    expect((await call("/v2/capabilities", "GET", a, ON)).status).toBe(200);
    expect(await refused(await call("/v1/pollen/bundle-claims", "POST", a, ON, NEW, { schema_version: 1 }))).toBe(false);
    expect(await refused(await call("/v1/safety/terms", "POST", a, ON, NEW, {}))).toBe(false);
    const deleted = await call("/v1/identity", "DELETE", a, ON);
    expect(deleted.status).toBe(200);
  });
  it("follows the link: a replaced or unlinked account takes the mark away, a restore brings it", async () => {
    const a = await create(), b = await create(); google({ "code-a": "g-player-one", "code-b": "g-player-one", "code-r": "g-player-one" });
    await link(a, "code-a", ON);
    expect((await (await link(b, "code-b", ON, true)).json<{ status: string }>()).status).toBe("linked");
    expect(await refused(await write(a, ON))).toBe(true);
    expect(await refused(await write(b, ON))).toBe(false);
    expect((await call("/v1/platform/unlink", "POST", b, ON, NEW, { schema_version: 1, provider: "play_games" })).status).toBe(200);
    expect(await refused(await write(b, ON))).toBe(true);
    // Linked again, then restored on a new phone: the restored identity keeps playing online.
    await link(b, "code-b", ON);
    const next = { device_token: "n".repeat(43), recovery_code: "m".repeat(43) };
    const restored = await call("/v1/platform/restore", "POST", undefined, ON, NEW, { schema_version: 1, provider: "play_games", credential: { server_auth_code: CODE_PREFIX + "code-r" },
      idempotency_key: "idem-" + "k".repeat(20), next_device_token: next.device_token, next_recovery_code: next.recovery_code });
    expect(restored.status).toBe(200);
    expect(await refused(await write({ player_id: b.player_id, ...next }, ON))).toBe(false);
  });
  it("never gates testers or the App Review identity, and tells their phones so", async () => {
    const tester = await create(), reviewer = await create();
    const base = vars({ REQUIRE_PLATFORM: "0.9.0" }, { tester_ids: [tester.player_id], reviewer_ids: [reviewer.player_id] });
    expect(await refused(await write(tester, base))).toBe(false);
    expect(await refused(await write(reviewer, base))).toBe(false);
    expect(await capability(tester, base)).toMatchObject({ platform_required_version: 1, platform_exempt: true });
  });
});
