import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { appStatus, clientHeader, compareVersions } from "../src/app-status";
import { parseVersion, type Version } from "../src/config";
import vectors from "../../game/tests/fixtures/update_gate/versions.json";
import { withConfig } from "./config";

type Account = { player_id: string; device_token: string; recovery_code: string };
const MINIMUMS = { play: "0.6.4", github: "0.6.3", app_store: "1.0.0" };
const ON = { min_client_version: MINIMUMS };
let ip = 0;
function limiter(success = true) { return { limit: vi.fn(async () => ({ success })) }; }
async function call(path: string, options: { client?: string; method?: string; account?: Account; vars?: Record<string, unknown>; body?: unknown } = {}) {
  const headers: Record<string, string> = { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.1." + (++ip % 250) };
  if (options.client !== undefined) headers["X-AfterYou-Client"] = options.client;
  if (options.account) { headers["X-Player-Id"] = options.account.player_id; headers.Authorization = "Bearer " + options.account.device_token; }
  // vars that bring their own CONFIG (a malformed one on purpose) go in as they are; others are folded into CONFIG.
  const vars = options.vars ?? {}, merged = "CONFIG" in vars ? { ...env, ...vars } : withConfig({ ...env, ...vars });
  return worker.fetch(new Request("https://game.test" + path, { method: options.method ?? "GET", headers, body: options.body === undefined ? undefined : JSON.stringify(options.body) }), merged as Env);
}
const status = async (client: string | undefined, vars: Record<string, unknown>) => {
  const response = await call("/v1/app-status", { client, vars });
  expect(response.status).toBe(200);
  return response.json();
};
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("version grammar shared with the app", () => {
  it("accepts and rejects the shared vectors", () => {
    for (const value of vectors.valid) expect(parseVersion(value), value).not.toBeNull();
    for (const value of vectors.invalid) expect(parseVersion(value), value).toBeNull();
    expect(parseVersion(undefined)).toBeNull();
    expect(parseVersion(6)).toBeNull();
  });
  it("orders releases and pre-releases by semantic version precedence", () => {
    const ordered = vectors.ordered.map(value => parseVersion(value) as Version);
    for (let i = 0; i < ordered.length; i++) for (let j = 0; j < ordered.length; j++) {
      expect(Math.sign(compareVersions(ordered[i], ordered[j])), `${vectors.ordered[i]} vs ${vectors.ordered[j]}`).toBe(Math.sign(i - j));
    }
  });
  it("reads the client header strictly", () => {
    for (const [header, expected] of Object.entries(vectors.headers)) {
      const parsed = clientHeader(new Request("https://game.test/", { headers: header === "" ? {} : { "X-AfterYou-Client": header } }));
      if (expected === null) expect(parsed, JSON.stringify(header)).toBeNull();
      else expect([parsed?.text, parsed?.channel], header).toEqual(expected);
    }
    expect(clientHeader(new Request("https://game.test/", { headers: { "X-AfterYou-Client": "0.6.2-" + "a".repeat(60) + " play" } }))).toBeNull();
  });
});

describe("GET /v1/app-status without minimums", () => {
  it("gates nobody when CONFIG has no minimum, or no CONFIG at all", async () => {
    for (const vars of [{}, { CONFIG: "{}" }, { CONFIG: "not json" }])
      for (const client of [undefined, "0.0.1 play", "0.6.2 github", "0.0.1 app_store"])
        expect(await status(client, vars), `${JSON.stringify(vars)} ${client}`).toEqual({ schema_version: 1, gate: "off" });
  });
});

describe("GET /v1/app-status with the gate on", () => {
  it("gates each channel below its own minimum and nothing at or above it", async () => {
    expect(await status("0.6.3 play", ON)).toEqual({ schema_version: 1, gate: "required", min_version: "0.6.4", channel: "play" });
    expect(await status("0.6.4 play", ON)).toEqual({ schema_version: 1, gate: "off" });
    expect(await status("0.7.0 play", ON)).toEqual({ schema_version: 1, gate: "off" });
    expect(await status("0.6.2 github", ON)).toEqual({ schema_version: 1, gate: "required", min_version: "0.6.3", channel: "github" });
    expect(await status("0.6.3 github", ON)).toEqual({ schema_version: 1, gate: "off" });
    expect(await status("0.9.9 app_store", ON)).toEqual({ schema_version: 1, gate: "required", min_version: "1.0.0", channel: "app_store" });
    expect(await status("1.0.0 app_store", ON)).toEqual({ schema_version: 1, gate: "off" });
    // Minimums are independent: a GitHub-only minimum never gates Play or the App Store.
    const githubOnly = { min_client_version: { github: "0.6.2" } };
    expect(await status("0.6.1 github", githubOnly)).toEqual({ schema_version: 1, gate: "required", min_version: "0.6.2", channel: "github" });
    expect(await status("0.6.1 play", githubOnly)).toEqual({ schema_version: 1, gate: "off" });
    expect(await status("0.6.1 app_store", githubOnly)).toEqual({ schema_version: 1, gate: "off" });
  });
  it("treats a pre-release as older than its release", async () => {
    expect(await status("0.6.4-rc.1 play", ON)).toEqual({ schema_version: 1, gate: "required", min_version: "0.6.4", channel: "play" });
    expect(await status("0.6.5-rc.1 play", ON)).toEqual({ schema_version: 1, gate: "off" });
    expect(await status("0.6.4-rc.2 play", { min_client_version: { ...MINIMUMS, play: "0.6.4-rc.10" } })).toEqual({ schema_version: 1, gate: "required", min_version: "0.6.4-rc.10", channel: "play" });
  });
  it("never gates dev, a missing header or a malformed one", async () => {
    for (const client of [undefined, "0.0.1 dev", "0.0.1", "0.0.1 ios", "0.0.1 Play", "0.0.1  play", "v0.0.1 play", "0.0.1 play x", "0.0.1-" + "a".repeat(80) + " play"]) {
      expect(await status(client, ON), String(client)).toEqual({ schema_version: 1, gate: "off" });
    }
  });
  it("reads an empty, malformed or missing minimum as no minimum", async () => {
    // The runners refuse such a CONFIG; the Worker still never gates on one.
    for (const minimum of ["", " ", "latest", "0.6", "v1.0.0", "1.0.0 ", "99999.0.0", "1.0.0+5", 7, null]) {
      const vars = { CONFIG: JSON.stringify({ min_client_version: { ...MINIMUMS, play: minimum } }) };
      expect(await status("0.0.1 play", vars), JSON.stringify(minimum)).toEqual({ schema_version: 1, gate: "off" });
      expect(await status("0.6.2 github", vars), JSON.stringify(minimum)).toEqual({ schema_version: 1, gate: "required", min_version: "0.6.3", channel: "github" });
    }
    expect(await status("0.0.1 play", { min_client_version: {} })).toEqual({ schema_version: 1, gate: "off" });
  });
  it("answers with exact keys, no-store and no identity", async () => {
    const response = await call("/v1/app-status", { client: "0.6.3 play", vars: ON });
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(Object.keys(await response.json()).sort()).toEqual(["channel", "gate", "min_version", "schema_version"]);
    const off = await call("/v1/app-status", { client: "0.6.4 play", vars: ON });
    expect(Object.keys(await off.json()).sort()).toEqual(["gate", "schema_version"]);
    expect(appStatus(new Request("https://game.test/v1/app-status"), withConfig(ON))).toEqual({ schema_version: 1, gate: "off" });
  });
  it("goes through the public limiter and returns its 429", async () => {
    const allowed = limiter();
    expect((await call("/v1/app-status", { client: "0.6.3 play", vars: { ...ON, PUBLIC_LIMITER: allowed } })).status).toBe(200);
    expect(allowed.limit).toHaveBeenCalledTimes(1);
    const refused = await call("/v1/app-status", { client: "0.6.3 play", vars: { ...ON, PUBLIC_LIMITER: limiter(false) } });
    expect(refused.status).toBe(429);
    expect(refused.headers.get("Retry-After")).toBe("60");
  });
  it("still refuses a query string and leaves other methods to the existing routes", async () => {
    const query = await call("/v1/app-status?v=1", { client: "0.6.3 play", vars: ON });
    expect([query.status, await query.json()]).toEqual([400, { error: { code: "query_not_supported", retryable: false } }]);
    const post = await call("/v1/app-status", { method: "POST", client: "0.6.3 play", vars: ON, body: {} });
    expect([post.status, await post.json()]).toEqual([401, { error: { code: "invalid_auth", retryable: false } }]);
  });
});

describe("the client header changes nothing else", () => {
  it("keeps /health, /v1/safety/config and /v2/capabilities byte-identical whatever the minimums", async () => {
    const created = await call("/v1/identity", { method: "POST", body: {} });
    expect(created.status).toBe(201);
    const account = await created.json<Account>();
    for (const path of ["/health", "/v1/safety/config", "/v2/capabilities", "/v1/room-inbox"]) {
      const reference = await call(path, { account });
      const text = await reference.text();
      for (const vars of [{}, ON, { min_client_version: { ...MINIMUMS, play: "99.0.0" } }]) {
        for (const client of [undefined, "0.0.1 play", "0.6.2 github", "1.0.0 app_store"]) {
          const response = await call(path, { account, client, vars });
          expect([response.status, await response.text()], `${path} ${client}`).toEqual([reference.status, text]);
        }
      }
    }
  });
});
