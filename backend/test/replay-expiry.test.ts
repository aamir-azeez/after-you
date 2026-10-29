import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { notificationAlarmOwned } from "../src/notification-storage";
import { REPLAY_KEEP_MS, replayExpiryDue } from "../src/v2/replay-expiry";
import type { HistoryView } from "../src/v2/history-room";
import { CHAINS, GUEST, HOST, fork, newRoom, open, play, value, type Room } from "./history-chains";
import { configJson } from "./config";
import { meterRows } from "./meter";

// The replay time limit on finished rooms (v2/replay-expiry.ts), behind REPLAY_EXPIRY.
const shared = env as unknown as Record<string, unknown>;
const ON = configJson({ features: ["REPLAY_EXPIRY"] });
const relay = CHAINS[0], lighthouse = CHAINS[4];
const DAY = 86_400_000;
beforeEach(() => { delete shared.CONFIG; });
afterEach(async () => { delete shared.CONFIG; await reset(); });

type Facts = { alarm: number | null; due: number | null; owned: boolean; held: number; stubs: number };
const facts = (room: Room) => runInDurableObject(room, async (_, ctx): Promise<Facts> => {
  const alarm = await ctx.storage.getAlarm();
  const rows = ctx.storage.sql.exec<{ data: string }>("SELECT data FROM turns").toArray();
  const stub = (data: string) => Object.keys(JSON.parse(data)).length === 1;
  return { alarm, due: replayExpiryDue(ctx.storage), owned: notificationAlarmOwned(ctx.storage, "RoomV2", alarm), held: rows.filter(row => !stub(row.data)).length, stubs: rows.filter(row => stub(row.data)).length };
});
/** Moves the clock to run out now, keeping the alarm's marker in step, as time passing would. */
const runOut = (room: Room) => runInDurableObject(room, async (_, ctx) => {
  ctx.storage.sql.exec("UPDATE replay_expiry SET due_at=?", Date.now() - 1);
  ctx.storage.sql.exec("UPDATE notification_alarm SET due_at=?", Date.now() - 1);
  await ctx.storage.setAlarm(Date.now() - 1);
});
const fire = (room: Room) => runInDurableObject(room, async (instance: { alarm(): Promise<void> }) => instance.alarm());
async function finished(chain = relay): Promise<Room> {
  const room = newRoom();
  await play(room, await open(room, chain), chain, 0);
  return room;
}
const history = async (room: Room, player: string) => value(await room.history(player, 1)) as HistoryView;

describe("the replay time limit", () => {
  it("is off by default: a finished room arms nothing and keeps its replays", async () => {
    const room = await finished();
    expect(await facts(room)).toMatchObject({ alarm: null, due: null, owned: true, stubs: 0 });
  });

  it("arms 90 days when a room finishes, shares the alarm, keeps export working, and never deletes on a read", async () => {
    shared.CONFIG = ON;
    const before = Date.now();
    const room = await finished();
    const armed = await facts(room);
    expect(armed.due).toBeGreaterThanOrEqual(before + REPLAY_KEEP_MS);
    expect(armed).toMatchObject({ alarm: armed.due, owned: true, stubs: 0 });
    // Export still accepts the room's alarm as owned.
    expect((await room.exportSnapshot("d".repeat(40))).ok).toBe(true);
    // Reads only read.
    for (let i = 0; i < 3; i++) value(await room.snapshot(HOST));
    expect(await facts(room)).toMatchObject({ due: armed.due, stubs: 0 });
  });

  it("at the end keeps only hashes, the listing and the times, as if both phones had saved it, and costs one alarm", async () => {
    shared.CONFIG = ON;
    const room = await finished(lighthouse);
    const listed = value(await room.lobbySnapshot(HOST));
    await runOut(room);
    const { rows } = await meterRows({ room }, () => fire(room));
    // Measured 2026-10-29 on the six stage Lighthouse: one Durable Object request (the alarm), 413 rows read and 44 written.
    expect(rows.room.written).toBeLessThan(80);
    expect(rows.room.read).toBeLessThan(600);
    const after = await facts(room);
    expect(after).toMatchObject({ alarm: null, due: null, owned: true, held: 0 });
    expect(after.stubs).toBeGreaterThan(0);
    // Listing, times and hashes stay; the room now reads as finished with its replays gone.
    const relisted = value(await room.lobbySnapshot(HOST)) as { room_id: string; created_at: string; updated_at: string };
    expect([relisted.room_id, relisted.created_at, relisted.updated_at]).toEqual([listed.room_id, listed.created_at, listed.updated_at]);
    expect(await room.snapshot(HOST)).toMatchObject({ ok: false, code: "replay_transferred" });
    const attempts = (await history(room, GUEST)).attempts;
    expect(attempts.every(item => item.state === "offloaded" && /^[a-f0-9]{64}$/.test(item.digest))).toBe(true);
    // Export still works on what is left.
    expect((await room.exportSnapshot("d".repeat(40))).ok).toBe(true);
  });

  it("leaves a room that is not finished any more, arms rooms finished before the switch on their next read, and does nothing switched off", async () => {
    shared.CONFIG = ON;
    const forked = await finished();
    await fork(forked, value(await forked.snapshot(HOST)), 1);
    await runOut(forked);
    await fire(forked);
    expect(await facts(forked)).toMatchObject({ due: null, stubs: 0, owned: true });

    delete shared.CONFIG;
    const older = await finished();
    expect((await facts(older)).due).toBeNull();
    shared.CONFIG = ON;
    value(await older.snapshot(GUEST));
    await expect.poll(async () => (await facts(older)).due, { timeout: 2000 }).toBeGreaterThan(Date.now() + REPLAY_KEEP_MS - DAY);
    expect((await facts(older)).owned).toBe(true);

    // Switched off when the clock runs out: nothing goes, and the clock does.
    await runOut(older);
    delete shared.CONFIG;
    await fire(older);
    expect(await facts(older)).toMatchObject({ due: null, stubs: 0, alarm: null, owned: true });
  });

  it("drops the clock when the room is erased, and a restored room starts without one", async () => {
    shared.CONFIG = ON;
    const room = await finished();
    const archive = value(await room.exportSnapshot("d".repeat(40)));
    const target = newRoom();
    expect(await target.restoreSnapshot(archive, "R".repeat(22))).toMatchObject({ ok: true });
    expect(await facts(target)).toMatchObject({ due: null, alarm: null, owned: true, stubs: 0 });
    // Both members leave: the room is erased with its clock.
    for (const who of [HOST, GUEST]) value(await room.leaveFinished(who));
    expect(await facts(room)).toMatchObject({ due: null, alarm: null, owned: true });
  });
});
