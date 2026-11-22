import { env } from "cloudflare:workers";
import { expect } from "vitest";
import worker from "../src/index";
import { digest } from "../src/protocol";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { withConfig } from "./config";

const CODE = "SYNTHETIC-FULL-JOURNEY-HOST";
let requestNo = 0;

/** Gives a synthetic account Full Journey through a tester grant, for a test that hosts a paid chapter (v2/chapters.ts paid()). */
export async function grantFullJourney(account: { player_id: string; device_token: string }): Promise<void> {
  const configured: Env = withConfig({ ...env, TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + CODE) });
  const response = await worker.fetch(new Request("https://after-you.test/v1/tester-access", { method: "POST", headers: { "Content-Type": "application/json",
    "CF-Connecting-IP": "198.18.77." + (++requestNo % 250), "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token },
    body: JSON.stringify({ schema_version: 1, code: CODE }) }), configured);
  expect(response.status).toBe(200);
}
