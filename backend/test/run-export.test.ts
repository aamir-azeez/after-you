import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { RUN_EXPORT_ALIAS, RUN_EXPORT_HEADER, RUN_EXPORT_VERSION } from "../src/run-export";
import { configJson } from "./config";

// Synthetic identities only: every account here is made by POST /v1/identity in the test runtime.
type Account = { player_id: string; device_token: string; recovery_code: string };
const ASK = { [RUN_EXPORT_HEADER]: "1" };
let address = 0;

async function call(path: string, method: string, account: Account | undefined, config: string | undefined, headers: Record<string, string> = {}): Promise<Response> {
  const { CONFIG: _shared, ...rest } = env as Env & { CONFIG?: string };
  const configured = (config === undefined ? rest : { ...rest, CONFIG: config }) as Env;
  return worker.fetch(new Request("https://run-export.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: method === "POST" ? "{}" : undefined }), configured);
}
async function create(): Promise<Account> {
  const made = await call("/v1/identity", "POST", undefined, undefined);
  expect(made.status).toBe(201);
  return made.json<Account>();
}
async function capabilities(account: Account, config: string, headers: Record<string, string> = {}): Promise<{ text: string; body: Record<string, unknown> }> {
  const response = await call("/v2/capabilities", "GET", account, config, headers);
  expect(response.status).toBe(200);
  const text = await response.text();
  return { text, body: JSON.parse(text) as Record<string, unknown> };
}

describe("run export capability", () => {
  it("goes only to the aliased owner on a request that asks", async () => {
    const owner = await create(), other = await create();
    const config = configJson({ friend_aliases: { [RUN_EXPORT_ALIAS]: owner.player_id } });

    const asked = await capabilities(owner, config, ASK);
    expect(asked.body.run_export_version).toBe(RUN_EXPORT_VERSION);

    // The owner without the header, and anyone else with or without it, gets the bytes as before.
    const plain = await capabilities(owner, config);
    expect(plain.body).not.toHaveProperty("run_export_version");
    const { run_export_version: _added, ...rest } = asked.body;
    expect(JSON.stringify(rest)).toBe(plain.text);

    const otherAsked = await capabilities(other, config, ASK), otherPlain = await capabilities(other, config);
    expect(otherAsked.body).not.toHaveProperty("run_export_version");
    expect(otherAsked.text).toBe(otherPlain.text);
  });

  it("goes to nobody without the alias, under another alias, or when the alias map is invalid", async () => {
    const owner = await create(), other = await create();
    for (const config of [
      configJson({}),
      configJson({ friend_aliases: { someone: owner.player_id } }),
      // One malformed entry disables every alias (config.ts fails closed).
      configJson({ friend_aliases: { [RUN_EXPORT_ALIAS]: owner.player_id, Bad: other.player_id } }, { raw: true }),
      configJson({ friend_aliases: { [RUN_EXPORT_ALIAS]: owner.player_id, again: owner.player_id } }, { raw: true }),
    ]) {
      const asked = await capabilities(owner, config, ASK), plain = await capabilities(owner, config);
      expect(asked.body).not.toHaveProperty("run_export_version");
      expect(asked.text).toBe(plain.text);
    }
  });

  it("is not a header any value turns on", async () => {
    const owner = await create();
    const config = configJson({ friend_aliases: { [RUN_EXPORT_ALIAS]: owner.player_id } });
    for (const value of ["0", "2", "true", ""]) {
      expect((await capabilities(owner, config, { [RUN_EXPORT_HEADER]: value })).body).not.toHaveProperty("run_export_version");
    }
  });
});
