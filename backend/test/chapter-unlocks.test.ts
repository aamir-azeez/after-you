import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { DEFINITION_HASH, RELAY } from "../src/v2/protocol";
import type { RoomSnapshotV2 } from "../src/v2/room";
import { OPEN_CHAPTERS_HEADER, chapterOpen, openChapters } from "../src/v2/chapter-unlocks";
import { countingEnv } from "./meter";

type Account = { player_id: string; device_token: string; recovery_code: string };
const key = () => crypto.randomUUID();
let address = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, headers: Record<string, string> = {}, base: Env = env): Promise<Response> {
  const configured: Env = { ...base };
  Object.assign(configured, { V2_ROOMS_ENABLED: "true" });
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113." + (++address % 250),
      ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
const errorCode = async (response: Response) => (await response.json<{ error: { code: string } }>()).error.code;
async function create(): Promise<Account> { const result = await call("/v1/identity", "POST", undefined, {}); expect(result.status).toBe(201); return result.json<Account>(); }
async function relayRoom(host: Account): Promise<RoomSnapshotV2> {
  const made = await call("/v2/rooms", "POST", host, { idempotency_key: key(), level_id: RELAY.id, level_version: 2, definition_hash: DEFINITION_HASH });
  expect(made.status).toBe(200); return made.json<RoomSnapshotV2>();
}
const open = (...levels: string[]) => ({ [OPEN_CHAPTERS_HEADER]: levels.join(",") });

afterEach(async () => { await reset(); });

describe("chapter unlocks on join", () => {
  it("read the header, and check nothing without it", () => {
    const request = (value?: string) => new Request("https://after-you.test/", value === undefined ? {} : { headers: { [OPEN_CHAPTERS_HEADER]: value } });
    expect(openChapters(request())).toBeUndefined();
    expect(openChapters(request("first-steps, relay-isles"))).toEqual(["first-steps", "relay-isles"]);
    expect(() => openChapters(request("first-steps,Not Ok"))).toThrow();
    expect(() => openChapters(request(Array.from({ length: 65 }, (_, i) => "level-" + i).join(",")))).toThrow();
    expect(chapterOpen("relay-isles", undefined)).toBe(true);
    expect(chapterOpen("relay-isles", ["first-steps"])).toBe(false);
    expect(chapterOpen("relay-isles", ["first-steps", "relay-isles"])).toBe(true);
  });

  it("refuse a new guest who has not reached the room's chapter, and leave the room free", async () => {
    const host = await create(), newcomer = await create(), veteran = await create();
    const room = await relayRoom(host);
    const refused = await call("/v2/rooms/join", "POST", newcomer, { invite_code: room.invite_code }, open("first-steps"));
    expect(refused.status).toBe(403); expect(await errorCode(refused)).toBe("chapter_not_open");
    // The refused guest holds no link to the room.
    const listed = await call("/v2/rooms", "GET", newcomer);
    expect(JSON.stringify(await listed.json())).not.toContain(room.room_id);
    // The seat stays free for a guest who has reached it.
    const joined = await call("/v2/rooms/join", "POST", veteran, { invite_code: room.invite_code }, open("first-steps", RELAY.id));
    expect(joined.status).toBe(200);
    // A member who joins again (a lost reply) is never refused, whatever it sends.
    const again = await call("/v2/rooms/join", "POST", veteran, { invite_code: room.invite_code }, open("first-steps"));
    expect(again.status).toBe(200);
  });

  it("let older builds join as before, and refuse a malformed list as a bad field", async () => {
    const host = await create(), guest = await create(), other = await create();
    const room = await relayRoom(host);
    const odd = await call("/v2/rooms/join", "POST", other, { invite_code: room.invite_code }, { [OPEN_CHAPTERS_HEADER]: "first steps" });
    expect(odd.status).toBe(400); expect(await errorCode(odd)).toBe("invalid_field");
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code });
    expect(joined.status).toBe(200);
  });

  it("cost no Durable Object request beyond the join itself", async () => {
    const host = await create(), guest = await create();
    const room = await relayRoom(host);
    const plain = countingEnv(env), gated = countingEnv(env);
    await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code }, {}, plain.env);
    const other = await create(), second = await relayRoom(host);
    await call("/v2/rooms/join", "POST", other, { invite_code: second.invite_code }, open("first-steps", RELAY.id), gated.env);
    expect(gated.calls).toEqual(plain.calls);
  });

  it("cost a refused guest no more than a full room does", async () => {
    const host = await create(), guest = await create(), newcomer = await create(), late = await create();
    const room = await relayRoom(host);
    const refused = countingEnv(env), full = countingEnv(env);
    expect((await call("/v2/rooms/join", "POST", newcomer, { invite_code: room.invite_code }, open("first-steps"), refused.env)).status).toBe(403);
    expect((await call("/v2/rooms/join", "POST", guest, { invite_code: room.invite_code })).status).toBe(200);
    expect((await call("/v2/rooms/join", "POST", late, { invite_code: room.invite_code }, {}, full.env)).status).toBe(409);
    expect(refused.calls).toEqual(full.calls);
  });
});
