import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { routeV2 } from "../src/v2/routes";
import { digest, randomToken } from "../src/protocol";
import { PLATFORM_LINKS_OBJECT } from "../src/platform-links";
import { certificateKey, forgetGameCenterCertificates, gameCenterKeyUrl, gameCenterPayload, verifyGameCenter, verifyPlayGames } from "../src/platform-verify";
import { countingEnv, meterRows } from "./meter";

type Account = { player_id: string; device_token: string; recovery_code: string };
type Loose = Record<string, unknown>;
const APP_ID = "123456789012", CLIENT_ID = "123456789012-syntheticclientabc.apps.googleusercontent.com", SECRET = "synthetic-client-secret";
const PLAY_ON = { ...env, PLAY_GAMES_ENABLED: "true", PLAY_GAMES_APP_ID: APP_ID, PLAY_GAMES_WEB_CLIENT_ID: CLIENT_ID, PLAY_GAMES_CLIENT_SECRET: SECRET } as unknown as Env;
const GC_ON = { ...env, GAME_CENTER_ENABLED: "true" } as unknown as Env;
let address = 0;

afterEach(async () => { vi.restoreAllMocks(); forgetGameCenterCertificates(); await reset(); });

async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Env = env, headers: Record<string, string> = {}) {
  return worker.fetch(new Request("https://game.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100." + (++address % 250), ...headers,
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), vars);
}
const create = async (): Promise<Account> => { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); };
const links = () => env.PLATFORM_LINKS.getByName(PLATFORM_LINKS_OBJECT);

/** A synthetic Google: each auth code maps to one Play Games player id. "bad" is refused, "down" fails upstream. */
function google(players: Record<string, string>) {
  const seen: { url: string; init?: RequestInit }[] = [];
  const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = String(input); seen.push({ url, init });
    expect(init?.redirect).toBe("manual"); expect(init?.signal).toBeInstanceOf(AbortSignal);
    if (url === "https://oauth2.googleapis.com/token") {
      const form = new URLSearchParams(String(init?.body));
      expect(form.get("client_id")).toBe(CLIENT_ID); expect(form.get("client_secret")).toBe(SECRET);
      expect(form.get("grant_type")).toBe("authorization_code"); expect(form.get("redirect_uri")).toBe("");
      const code = form.get("code")!.replace(CODE_PREFIX, "");
      if (code.startsWith("down")) return new Response("{}", { status: 503 });
      if (!(code in players)) return Response.json({ error: "invalid_grant" }, { status: 400 });
      return Response.json({ access_token: "synthetic-access-" + code, expires_in: 3599, token_type: "Bearer" });
    }
    if (url === `https://games.googleapis.com/games/v1/applications/${APP_ID}/verify`) {
      const token = new Headers(init?.headers).get("Authorization")!.replace("Bearer synthetic-access-", "");
      return Response.json({ kind: "games#applicationVerifyResponse", player_id: players[token] });
    }
    throw new Error("unexpected fetch " + url);
  });
  return { spy, seen };
}
/** Real server auth codes are long; the synthetic Google strips this prefix again. */
const CODE_PREFIX = "4/0Asynthetic-";
const playCredential = (code: string) => ({ server_auth_code: CODE_PREFIX + code });
const link = (a: Account, code: string, replace?: boolean, vars = PLAY_ON) =>
  call("/v1/platform/link", "POST", a, { schema_version: 1, provider: "play_games", credential: playCredential(code), recovery_code: a.recovery_code, ...(replace === undefined ? {} : { replace }) }, vars);
const restore = (code: string, next: { device_token: string; recovery_code: string }, key = "idem-" + "k".repeat(20), vars = PLAY_ON) =>
  call("/v1/platform/restore", "POST", undefined, { schema_version: 1, provider: "play_games", credential: playCredential(code), idempotency_key: key, next_device_token: next.device_token, next_recovery_code: next.recovery_code }, vars);

describe("platform games capability", () => {
  const read = async (vars: Loose, header = true) => JSON.parse(await (await routeV2(new Request("https://after-you.test/v2/capabilities", { headers: header ? { "X-AfterYou-Platform-Games": "1" } : {} }), "/v2/capabilities", "c".repeat(22), vars as unknown as Env)).text()) as Loose;
  it("is absent with the flags off, without the opt-in header, or when Play Games is on without its config", async () => {
    const off = await read({ ...env }, false);
    expect(await read({ ...env })).toEqual(off);
    expect(await read({ ...PLAY_ON }, false)).toEqual(off);
    expect(await read({ ...env, PLAY_GAMES_ENABLED: "true" })).toEqual(off);
    expect(await read({ ...PLAY_ON, PLAY_GAMES_CLIENT_SECRET: "" })).toEqual(off);
    expect(await read({ ...PLAY_ON, PLAY_GAMES_APP_ID: "abc" })).toEqual(off);
  });
  it("names each provider only while it is on, with the public web client id for Play Games", async () => {
    const off = await read({ ...env });
    expect(await read({ ...PLAY_ON })).toEqual({ ...off, play_games_version: 1, play_games_web_client_id: CLIENT_ID });
    expect(await read({ ...GC_ON })).toEqual({ ...off, game_center_version: 1 });
    expect(JSON.stringify(await read({ ...PLAY_ON }))).not.toContain(SECRET);
  });
});

describe("platform routes while off", () => {
  it("answer as before: link 404 after auth, restore falls through to auth 401", async () => {
    const a = await create(); const fetchSpy = vi.spyOn(globalThis, "fetch");
    const linked = await link(a, "code-a", undefined, env);
    expect(linked.status).toBe(404); expect(await linked.json()).toEqual({ error: { code: "not_found", retryable: false } });
    expect((await call("/v1/platform/unlink", "POST", a, { schema_version: 1, provider: "play_games" })).status).toBe(404);
    expect((await restore("code-a", { device_token: randomToken(), recovery_code: randomToken() }, undefined, env)).status).toBe(401);
    // One provider on does not open the other.
    expect((await call("/v1/platform/link", "POST", a, { schema_version: 1, provider: "play_games", credential: playCredential("code-a") }, GC_ON)).status).toBe(404);
    expect(fetchSpy).not.toHaveBeenCalled();
  });
  it("fails closed with 503 when Play Games is on without its config, before any upstream call", async () => {
    const a = await create(); const fetchSpy = vi.spyOn(globalThis, "fetch");
    const response = await link(a, "code-a", undefined, { ...env, PLAY_GAMES_ENABLED: "true" } as unknown as Env);
    expect(response.status).toBe(503); expect(await response.json()).toEqual({ error: { code: "platform_unavailable", retryable: true } });
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});

describe("Play Games linking", () => {
  it("links on first sign-in, answers the same link without writing, and never takes an id from the client", async () => {
    const a = await create(); google({ "code-a": "g-player-one", "code-b": "g-player-one" });
    const first = await link(a, "code-a");
    expect(first.status).toBe(200); expect(await first.json()).toEqual({ schema_version: 1, provider: "play_games", status: "linked", changed: true });
    expect(await links().linkedProviders(a.player_id)).toEqual(["play_games"]);
    const again = await meterRows({ links: links() }, () => link(a, "code-b"));
    expect(await again.value.json()).toEqual({ schema_version: 1, provider: "play_games", status: "linked", changed: false });
    expect(again.rows.links.written).toBe(0);
    // A client-supplied player id is refused outright.
    const forged = await call("/v1/platform/link", "POST", a, { schema_version: 1, provider: "play_games", credential: { server_auth_code: CODE_PREFIX + "code-a", player_id: "g-player-two" }, recovery_code: a.recovery_code }, PLAY_ON);
    expect(forged.status).toBe(400);
    expect((await call("/v1/platform/link", "POST", a, { schema_version: 1, provider: "play_games", credential: playCredential("code-a"), recovery_code: a.recovery_code, player_id: "x" }, PLAY_ON)).status).toBe(400);
  });
  it("needs the recovery code too, so a device token alone can never set up a restore", async () => {
    const a = await create(); const { spy } = google({ "code-a": "g-player-one" });
    const missing = await call("/v1/platform/link", "POST", a, { schema_version: 1, provider: "play_games", credential: playCredential("code-a") }, PLAY_ON);
    expect(missing.status).toBe(400);
    const wrong = await call("/v1/platform/link", "POST", a, { schema_version: 1, provider: "play_games", credential: playCredential("code-a"), recovery_code: randomToken() }, PLAY_ON);
    expect(wrong.status).toBe(401); expect(await wrong.json()).toEqual({ error: { code: "invalid_recovery", retryable: false } });
    expect(spy).not.toHaveBeenCalled();
    expect(await links().linkedProviders(a.player_id)).toEqual([]);
    const limited = { ...PLAY_ON, TESTER_CODE_LIMITER: { limit: async ({ key }: { key: string }) => ({ success: !key.startsWith("platform-player:") }) } } as unknown as Env;
    expect((await link(a, "code-a", undefined, limited)).status).toBe(429);
  });
  it("costs one auth call and one link call, writing one row and its index entry on a first link", async () => {
    const a = await create(); google({ "code-a": "g-player-one" });
    const counted = countingEnv(PLAY_ON);
    const metered = await meterRows({ links: links() }, () => link(a, "code-a", undefined, counted.env));
    expect(metered.value.status).toBe(200);
    expect(counted.calls).toEqual(["PLAYERS.authorize", "PLAYERS.recoveryMatches", "PLATFORM_LINKS.link"]);
    expect(metered.rows.links.written).toBeLessThanOrEqual(2);
  });
  it("reports a conflict without writing, and moves the link only when the player chose to replace it", async () => {
    const a = await create(), b = await create(); google({ "code-a": "g-player-one", "code-b": "g-player-one", "code-c": "g-player-one" });
    expect((await link(a, "code-a")).status).toBe(200);
    const conflict = await meterRows({ links: links() }, () => link(b, "code-b"));
    expect(await conflict.value.json()).toEqual({ schema_version: 1, provider: "play_games", status: "conflict", changed: false });
    expect(conflict.rows.links.written).toBe(0);
    expect(await links().linkedProviders(a.player_id)).toEqual(["play_games"]);
    expect(await (await link(b, "code-c", true)).json()).toEqual({ schema_version: 1, provider: "play_games", status: "linked", changed: true });
    expect(await links().linkedProviders(a.player_id)).toEqual([]);
    expect(await links().linkedProviders(b.player_id)).toEqual(["play_games"]);
  });
  it("keeps one account per player: a second account answers other_account until replaced", async () => {
    const a = await create(); google({ "code-a": "g-player-one", "code-b": "g-player-two", "code-c": "g-player-two", "code-d": "g-player-one" });
    await link(a, "code-a");
    expect((await (await link(a, "code-b")).json<Loose>()).status).toBe("other_account");
    expect((await (await link(a, "code-c", true)).json<Loose>()).status).toBe("linked");
    // The first account is free again.
    const other = await create();
    expect((await (await link(other, "code-d")).json<Loose>()).status).toBe("linked");
  });
  it("maps Google's answers: refused code 401, upstream failure 503, wrong game 401", async () => {
    const a = await create(); google({ "code-a": "g-player-one" });
    const refused = await link(a, "bad-code-1");
    expect(refused.status).toBe(401); expect(await refused.json()).toEqual({ error: { code: "platform_credential_invalid", retryable: false } });
    const down = await link(a, "down-code-1");
    expect(down.status).toBe(503);
    // Google refusing our own client (a rotated secret) or rationing quota is never the player's fault.
    vi.restoreAllMocks();
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => Response.json({ error: "invalid_client" }, { status: 401 }));
    expect((await link(a, "code-a")).status).toBe(503);
    vi.restoreAllMocks();
    vi.spyOn(globalThis, "fetch").mockImplementation(async input => String(input).startsWith("https://oauth2") ? Response.json({ access_token: "synthetic-access-x".padEnd(20, "x") })
      : Response.json({ error: { code: 403, errors: [{ reason: "dailyLimitExceeded" }] } }, { status: 403 }));
    expect((await link(a, "code-a")).status).toBe(503);
    vi.restoreAllMocks();
    vi.spyOn(globalThis, "fetch").mockImplementation(async input => String(input).startsWith("https://oauth2") ? Response.json({ access_token: "synthetic-access-x".padEnd(20, "x") }) : new Response("{}", { status: 403 }));
    expect((await link(a, "code-a")).status).toBe(401);
    expect(await links().linkedProviders(a.player_id)).toEqual([]);
  });
  it("unlinks only the caller's own link", async () => {
    const a = await create(), b = await create(); google({ "code-a": "g-player-one" });
    await link(a, "code-a");
    const other = await call("/v1/platform/unlink", "POST", b, { schema_version: 1, provider: "play_games" }, PLAY_ON);
    expect(await other.json()).toEqual({ schema_version: 1, provider: "play_games", unlinked: false });
    expect(await (await call("/v1/platform/unlink", "POST", a, { schema_version: 1, provider: "play_games" }, PLAY_ON)).json()).toEqual({ schema_version: 1, provider: "play_games", unlinked: true });
    expect(await links().linkedProviders(a.player_id)).toEqual([]);
  });
});

describe("Play Games restore", () => {
  it("rotates the linked player's credentials to the device's proposal, like recovery", async () => {
    const a = await create(); google({ "code-a": "g-player-one", "code-r": "g-player-one", "code-s": "g-player-one" });
    await link(a, "code-a");
    const next = { device_token: randomToken(), recovery_code: randomToken() };
    const counted = countingEnv(PLAY_ON);
    const restored = await restore("code-r", next, undefined, counted.env);
    expect(restored.status).toBe(200);
    expect(await restored.json()).toEqual({ schema_version: 1, provider: "play_games", player_id: a.player_id, restored: true });
    expect(counted.calls).toEqual(["PLATFORM_LINKS.lookup", "PLAYERS.restoreLinked"]);
    // The old device token and recovery code stop working; the proposed ones work.
    expect((await call("/v1/identity", "GET", a)).status).toBe(401);
    expect((await call("/v1/identity", "GET", { player_id: a.player_id, ...next })).status).toBe(200);
    const recovered = await call("/v1/identity/recover", "POST", undefined, { player_id: a.player_id, recovery_code: a.recovery_code, idempotency_key: "idem-" + "z".repeat(20), next_device_token: randomToken(), next_recovery_code: randomToken() });
    expect(recovered.status).toBe(409);
    // A lost reply: the same proposal with a fresh code answers the same and rotates nothing.
    const retry = await restore("code-s", next);
    expect(await retry.json()).toEqual({ schema_version: 1, provider: "play_games", player_id: a.player_id, restored: true });
    expect((await call("/v1/identity", "GET", { player_id: a.player_id, ...next })).status).toBe(200);
  });
  it("answers whether an account is linked without rotating anything, so the phone can ask first", async () => {
    const a = await create(); google({ "code-a": "g-player-one", "code-c": "g-player-one", "code-n": "g-nobody" });
    await link(a, "code-a");
    const check = (code: string, vars = PLAY_ON) => call("/v1/platform/restore", "POST", undefined, { schema_version: 1, provider: "play_games", credential: playCredential(code), check: true }, vars);
    const counted = countingEnv(PLAY_ON);
    const linked = await meterRows({ links: links() }, () => check("code-c", counted.env));
    expect(await linked.value.json()).toEqual({ schema_version: 1, provider: "play_games", linked: true });
    expect(counted.calls).toEqual(["PLATFORM_LINKS.lookup"]);
    expect(linked.rows.links.written).toBe(0);
    expect(await (await check("code-n")).json()).toEqual({ schema_version: 1, provider: "play_games", linked: false });
    // The old device and recovery code still work: nothing rotated.
    expect((await call("/v1/identity", "GET", a)).status).toBe(200);
    const mixed = await call("/v1/platform/restore", "POST", undefined, { schema_version: 1, provider: "play_games", credential: playCredential("code-c"), check: true, next_device_token: randomToken() }, PLAY_ON);
    expect(mixed.status).toBe(400);
    expect((await call("/v1/platform/restore", "POST", undefined, { schema_version: 1, provider: "play_games", credential: playCredential("code-c"), check: false }, PLAY_ON)).status).toBe(400);
    expect((await check("code-c", env)).status).toBe(401);
  });
  it("answers 404 without a link, and refuses an equal or reused proposal", async () => {
    const a = await create(); google({ "code-a": "g-player-one", "code-n": "g-nobody", "code-x": "g-player-one" });
    expect((await restore("code-n", { device_token: randomToken(), recovery_code: randomToken() })).status).toBe(404);
    await link(a, "code-a");
    const same = randomToken();
    expect((await restore("code-x", { device_token: same, recovery_code: same })).status).toBe(400);
    expect((await restore("code-x", { device_token: a.device_token, recovery_code: randomToken() }, "idem-" + "q".repeat(20))).status).toBe(400);
  });
  it("tells a phone with no identity whether its provider is on, without a proof or a Durable Object", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    const probe = (provider: string, vars: Env) => call("/v1/platform/restore", "POST", undefined, { provider }, vars);
    const counted = countingEnv(PLAY_ON);
    const on = await probe("play_games", counted.env);
    expect(on.status).toBe(400); expect(await on.json()).toEqual({ error: { code: "invalid_platform_request", retryable: false } });
    expect(counted.calls).toEqual([]);
    expect((await probe("game_center", PLAY_ON)).status).toBe(404);
    expect((await probe("play_games", env)).status).toBe(401);
    expect(fetchSpy).not.toHaveBeenCalled();
  });
  it("is rate limited per address on its own bucket", async () => {
    google({ "code-a": "g-player-one" });
    const blocked = { ...PLAY_ON, TESTER_CODE_LIMITER: { limit: async ({ key }: { key: string }) => ({ success: !key.startsWith("platform-ip:") }) } } as unknown as Env;
    const response = await restore("code-a", { device_token: randomToken(), recovery_code: randomToken() }, undefined, blocked);
    expect(response.status).toBe(429);
  });
  it("drops a link whose player was erased, and erasure removes a player's links", async () => {
    const a = await create(), b = await create(); google({ "code-a": "g-player-one", "code-b": "g-player-two", "code-r": "g-player-two" });
    await link(a, "code-a"); await link(b, "code-b");
    expect((await call("/v1/identity", "DELETE", a)).status).toBe(200);
    expect(await links().linkedProviders(a.player_id)).toEqual([]);
    // A row that outlived its player (written straight in, as a race would leave it).
    await links().link("play_games", await digest("play_games:g-player-three"), "d".repeat(22), false);
    google({ "code-z": "g-player-three" });
    expect((await restore("code-z", { device_token: randomToken(), recovery_code: randomToken() })).status).toBe(404);
    expect(await links().linkedProviders("d".repeat(22))).toEqual([]);
    expect(await links().linkedProviders(b.player_id)).toEqual(["play_games"]);
  });
});

// ---- Game Center ----------------------------------------------------------------------------

function der(tag: number, ...parts: Uint8Array[]): Uint8Array {
  const body = new Uint8Array(parts.reduce((n, p) => n + p.length, 0)); let o = 0; for (const p of parts) { body.set(p, o); o += p.length; }
  const length = body.length < 128 ? [body.length] : body.length < 256 ? [0x81, body.length] : [0x82, body.length >> 8, body.length & 255];
  return new Uint8Array([tag, ...length, ...body]);
}
const ascii = (text: string) => new TextEncoder().encode(text);
/** Just enough of an X.509 certificate for the DER walk: validity and the public key. */
function certificate(spki: Uint8Array, notBefore = "200101000000Z", notAfter = "491231235959Z"): Uint8Array {
  const tbs = der(0x30, der(0xa0, der(0x02, new Uint8Array([2]))), der(0x02, new Uint8Array([1])), der(0x30), der(0x30),
    der(0x30, der(0x17, ascii(notBefore)), der(0x17, ascii(notAfter))), der(0x30), spki);
  return der(0x30, tbs, der(0x30), der(0x03, new Uint8Array([0, 1, 2])));
}
const KEY_URL = "https://static.gc.apple.com/public-key/gc-prod-11.cer";
async function appleKeys(notAfter?: string) {
  const pair = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey) as ArrayBuffer);
  const cert = certificate(spki, undefined, notAfter);
  const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    expect(String(input)).toBe(KEY_URL); expect(init?.redirect).toBe("manual");
    return new Response(cert);
  });
  const sign = async (player: string, timestamp = Date.now(), bundle = "com.aamirazeez.afteryou") => {
    const salt = crypto.getRandomValues(new Uint8Array(32));
    const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", pair.privateKey, gameCenterPayload(player, bundle, timestamp, salt)));
    const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
    return { public_key_url: KEY_URL, signature: b64(signature), salt: b64(salt), timestamp, team_player_id: player };
  };
  return { sign, fetchSpy };
}

describe("Game Center verification", () => {
  it("accepts only https apple.com certificate URLs", () => {
    expect(gameCenterKeyUrl(KEY_URL)).not.toBeNull();
    for (const bad of ["http://static.gc.apple.com/public-key/a.cer", "https://static.gc.apple.com/a.cer", "https://other.apple.com/public-key/a.cer", "https://static.gc.apple.com/public-key/../x.cer", "http://static.gc.apple.com/a.cer", "https://static.gc.apple.com.evil.test/a.cer", "https://apple.com.evil.test/a.cer", "https://evil.test/apple.com/a.cer",
      "https://static.gc.apple.com:8443/a.cer", "https://user@static.gc.apple.com/a.cer", "https://static.gc.apple.com/a.cer?x=1", "https://static.gc.apple.com/a.pem", 7])
      expect(gameCenterKeyUrl(bad)).toBeNull();
  });
  it("verifies Apple's signed payload and rejects a tampered, stale, wrong-app or expired one", async () => {
    const { sign } = await appleKeys();
    const good = await sign("T:_synthetic_team_player");
    expect(await verifyGameCenter(good, {})).toEqual({ ok: true, external_id: "T:_synthetic_team_player" });
    expect((await verifyGameCenter({ ...good, team_player_id: "T:_someone_else" }, {})).ok).toBe(false);
    expect((await verifyGameCenter(await sign("T:_a", Date.now() - 11 * 60_000), {})).ok).toBe(false);
    expect((await verifyGameCenter(await sign("T:_a", Date.now(), "com.other.app"), {})).ok).toBe(false);
    expect((await verifyGameCenter({ ...good, extra: 1 }, {})).ok).toBe(false);
    forgetGameCenterCertificates(); vi.restoreAllMocks();
    const expired = await appleKeys("210101000000Z");
    expect(await verifyGameCenter(await expired.sign("T:_a"), {})).toEqual({ ok: false, reason: "invalid" });
  });
  it("finds the key in a certificate only inside its validity window", () => {
    const cert = certificate(der(0x30, der(0x30), der(0x03, new Uint8Array([0]))), "200101000000Z", "300101000000Z");
    expect(certificateKey(cert, Date.UTC(2025, 0, 1))).not.toBeNull();
    expect(certificateKey(cert, Date.UTC(2031, 0, 1))).toBeNull();
    expect(certificateKey(cert.slice(0, cert.length - 1), Date.UTC(2025, 0, 1))).toBeNull();
  });
  it("links and restores, and a signature works once", async () => {
    const { sign } = await appleKeys();
    const a = await create();
    const credential = await sign("T:_synthetic_team_player");
    const linked = await call("/v1/platform/link", "POST", a, { schema_version: 1, provider: "game_center", credential, recovery_code: a.recovery_code }, GC_ON);
    expect(await linked.json()).toEqual({ schema_version: 1, provider: "game_center", status: "linked", changed: true });
    const replayed = await call("/v1/platform/link", "POST", a, { schema_version: 1, provider: "game_center", credential, recovery_code: a.recovery_code }, GC_ON);
    expect(replayed.status).toBe(401);
    // The same signature spelled differently (no padding) is not a new signature.
    const respelled = { ...credential, signature: credential.signature.replace(/=+$/, "") };
    const restoreBody = (cred: unknown) => ({ schema_version: 1, provider: "game_center", credential: cred, idempotency_key: "idem-" + "h".repeat(20), next_device_token: randomToken(), next_recovery_code: randomToken() });
    if (respelled.signature !== credential.signature) expect((await call("/v1/platform/restore", "POST", undefined, restoreBody(respelled), GC_ON)).status).toBe(401);
    expect((await call("/v1/platform/restore", "POST", undefined, restoreBody(credential), GC_ON)).status).toBe(401);
    const next = { device_token: randomToken(), recovery_code: randomToken() };
    const restored = await call("/v1/platform/restore", "POST", undefined, { schema_version: 1, provider: "game_center", credential: await sign("T:_synthetic_team_player"),
      idempotency_key: "idem-" + "g".repeat(20), next_device_token: next.device_token, next_recovery_code: next.recovery_code }, GC_ON);
    expect(await restored.json()).toEqual({ schema_version: 1, provider: "game_center", player_id: a.player_id, restored: true });
  });
});

describe("Play Games verification transport", () => {
  it("refuses malformed codes before calling Google", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    expect(await verifyPlayGames("short", PLAY_ON)).toEqual({ ok: false, reason: "invalid" });
    expect(await verifyPlayGames(42, PLAY_ON)).toEqual({ ok: false, reason: "invalid" });
    expect(await verifyPlayGames("x".repeat(30), env)).toEqual({ ok: false, reason: "unconfigured" });
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
