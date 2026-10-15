import { env } from "cloudflare:workers";
import { expect } from "vitest";
import worker from "../src/index";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { RoomSnapshotV2 } from "../src/v2/room";

export type Account = { player_id: string; device_token: string; recovery_code: string };
export const HISTORY = { "X-AfterYou-History": "1" };
let address = 0;
/** One Worker request; `body` is JSON unless it is already bytes. */
export async function call(path: string, method = "GET", account?: Account, body?: unknown, vars: Record<string, string> = {}, headers: Record<string, string> = {}): Promise<Response> {
  const configured: Env = { ...env };
  Object.assign(configured, { V2_ROOMS_ENABLED: "true", ...vars });
  const raw = body instanceof Uint8Array;
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": raw ? "application/octet-stream" : "application/json", "CF-Connecting-IP": "198.51.100." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : raw ? body : JSON.stringify(body) }), configured);
}
export async function account(): Promise<Account> { const result = await call("/v1/identity", "POST", undefined, {}); expect(result.status).toBe(201); return result.json<Account>(); }
export async function relayPair(): Promise<{ host: Account; guest: Account; room: RoomSnapshotV2 }> {
  const host = await account(), guest = await account();
  const created = await call("/v2/rooms", "POST", host, { idempotency_key: crypto.randomUUID(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
  expect(created.status).toBe(200);
  const invite = (await created.json<RoomSnapshotV2>()).invite_code;
  const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: invite }); expect(joined.status).toBe(200);
  return { host, guest, room: await joined.json<RoomSnapshotV2>() };
}
export const ON = { HISTORY_OFFLOAD_ENABLED: "true" };
