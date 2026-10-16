import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { campaignStoragePresent } from "../src/v2/campaign-storage";
import { initializeCampaignStorageSchema } from "../src/v2/storage-schema";
import { call, relayPair } from "./history-http";
import { meterRows } from "./meter";

// Every RoomV2 request asks whether the room holds Story (campaign) storage. The answer is
// kept per object, so a standalone room scans its table list once instead of on every call.

afterEach(async () => { await reset(); });
const KNOWN = "X-AfterYou-Known-Room";
const answer = async (response: Response) => `${response.status} ${await response.text()}`;

describe("campaign storage probe", () => {
  it("reads one row instead of a table scan once a standalone room is known", async () => {
    const { guest, room } = await relayPair(), stub = env.ROOMS_V2.getByName(room.room_id);
    await runInDurableObject(stub, async (_, ctx) => { expect(campaignStoragePresent(ctx.storage)).toBe(false); });
    const probe = await meterRows({ room: stub }, () => runInDurableObject(stub, async (_, ctx) => campaignStoragePresent(ctx.storage)));
    expect(probe.value).toBe(false);
    expect(probe.rows.room).toEqual({ read: 1, written: 0 }); // 19 with a scan
    // A warm waiting poll, as the phone sends every few seconds.
    const headers = { [KNOWN]: `${room.revision}.${room.branch}` };
    expect((await call(`/v2/rooms/${room.room_id}`, "GET", guest, undefined, {}, headers)).status).toBe(200);
    const poll = await meterRows({ room: stub }, () => call(`/v2/rooms/${room.room_id}`, "GET", guest, undefined, {}, headers));
    expect(poll.value.status).toBe(200);
    // 82 rows before the memo: four table scans of 18 rows each.
    expect(poll.rows.room).toEqual({ read: 10, written: 0 });
  });

  it("sees Story storage added mid-life, and forgets it again when that is rolled back", async () => {
    const primed = await relayPair(), cold = await relayPair();
    const path = (id: string) => `/v2/rooms/${id}`;
    expect((await call(path(primed.room.room_id), "GET", primed.guest)).status).toBe(200);
    const promote = (id: string) => runInDurableObject(env.ROOMS_V2.getByName(id), async (_, ctx) => { initializeCampaignStorageSchema(ctx.storage); });
    await promote(primed.room.room_id); await promote(cold.room.room_id);
    const after = await answer(await call(path(primed.room.room_id), "GET", primed.guest));
    expect(after).toMatch(/^409 /);
    expect(after).toBe(await answer(await call(path(cold.room.room_id), "GET", cold.guest)));

    const standalone = await relayPair(), stub = env.ROOMS_V2.getByName(standalone.room.room_id);
    await runInDurableObject(stub, async (_, ctx) => {
      expect(campaignStoragePresent(ctx.storage)).toBe(false);
      expect(() => ctx.storage.transactionSync(() => {
        initializeCampaignStorageSchema(ctx.storage);
        expect(campaignStoragePresent(ctx.storage)).toBe(true);
        throw new Error("rolled back");
      })).toThrow("rolled back");
      expect(campaignStoragePresent(ctx.storage)).toBe(false);
    });
    expect((await call(path(standalone.room.room_id), "GET", standalone.guest)).status).toBe(200);
  });
});
