import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { ChapterAdapter } from "../src/v2/chapter-types";

// A create whose reply was lost, retried with the same key after its chapter's flag was switched off, gets its room
// back. Without this the phone kept the create pending forever: every retry was refused before the saved intent was
// read, and a pending create blocks every other create and join on the phone. Every published chapter's flag has
// retired, but a new chapter ships behind its own flag (scripts/new_chapter.py), so this stands in for one.
const gate = vi.hoisted(() => ({ off: false }));
vi.mock("../src/v2/chapters", async importOriginal => {
  const original = await importOriginal<typeof import("../src/v2/chapters")>();
  return { ...original, creatable: (entry: ChapterAdapter, vars: Env) => !gate.off && original.creatable(entry, vars) };
});
import worker from "../src/index";
import { wishingWell } from "../src/v2/protocol-cooperative";
import type { RoomSnapshotV2 } from "../src/v2/room";

type Account = { player_id: string; device_token: string; recovery_code: string };
let requestNo = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown): Promise<Response> {
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.10." + (++requestNo % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), env);
}
async function account(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
afterEach(async () => { gate.off = false; await reset(); });

describe("a chapter create retried after its chapter was switched off", () => {
  it("answers the retried create with the room it made, and still refuses a new create", async () => {
    const host = await account();
    const idempotency_key = crypto.randomUUID();
    const made = await call("/v2/rooms", "POST", host, { ...wishingWell.key, idempotency_key });
    expect(made.status).toBe(200);
    const room = await made.json<RoomSnapshotV2>();
    // The reply never reached the phone; the chapter is switched off; the phone retries.
    gate.off = true;
    const retried = await call("/v2/rooms", "POST", host, { ...wishingWell.key, idempotency_key });
    expect(retried.status).toBe(200);
    const again = await retried.json<RoomSnapshotV2>();
    expect(again.room_id).toBe(room.room_id);
    expect(again.invite_code).toBe(room.invite_code);
    expect((await env.PLAYERS.getByName(host.player_id).listRooms()).map(link => link.room_id)).toEqual([room.room_id]);
    const fresh = await call("/v2/rooms", "POST", host, { ...wishingWell.key, idempotency_key: crypto.randomUUID() });
    expect(fresh.status).toBe(503);
    expect(await fresh.json()).toMatchObject({ error: { code: "chapter_creation_disabled" } });
    expect((await env.PLAYERS.getByName(host.player_id).listRooms()).length).toBe(1);
  });
});
