import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { bytesDigest, decodeAttempt, encodeAttempt, ENCODING_RAW } from "../src/v2/history-blob";
import type { HistoryView } from "../src/v2/history-room";
import type { RoomSnapshotV2 } from "../src/v2/room";
import { CHAINS, fork, play } from "./history-chains";
import { HISTORY, ON, call, relayPair, type Account } from "./history-http";

afterEach(async () => { await reset(); });
const chain = CHAINS[0];
type Setup = { host: Account; guest: Account; room: RoomSnapshotV2; path: string; stub: DurableObjectStub<import("../src/v2/room").RoomV2> };
/** A relay room with `attempts` finished attempts (each played through and then forked back to the start). */
async function setup(attempts: number): Promise<Setup & { state: RoomSnapshotV2 }> {
  const { host, guest, room } = await relayPair(), stub = env.ROOMS_V2.getByName(room.room_id), players = { host: host.player_id, guest: guest.player_id };
  let state = room;
  for (let i = 0; i < attempts; i++) state = await fork(stub, await play(stub, state, chain, 0, undefined, players), 0, host.player_id);
  return { host, guest, room, state, path: `/v2/rooms/${room.room_id}/history`, stub };
}
async function list(setup: Setup, who: Account, vars: Record<string, string> = ON): Promise<HistoryView> {
  const response = await call(setup.path, "GET", who, undefined, vars, HISTORY); expect(response.status).toBe(200); return response.json<HistoryView>();
}
async function download(setup: Setup, who: Account, position: number, vars: Record<string, string> = ON): Promise<Uint8Array> {
  const response = await call(`${setup.path}/${position}`, "GET", who, undefined, vars, HISTORY);
  expect(response.status).toBe(200); expect(response.headers.get("content-type")).toBe("application/octet-stream");
  return new Uint8Array(await response.arrayBuffer());
}
const code = async (response: Response) => `${response.status} ${response.status === 200 ? "ok" : (await response.json<{ error: { code: string } }>()).error.code}`;
const tables = (setup: Setup) => runInDurableObject(setup.stub, (_, ctx) => ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE name LIKE 'history_%'").toArray().length);

describe("attempt history endpoints", () => {
  it("lists and serves finished attempts with offload off, without touching storage, and never the live attempt", async () => {
    const s = await setup(2);
    const view = await list(s, s.host, {});
    expect(view).toMatchObject({ schema_version: 1, mode: "attempts", head: view.attempts[1].link });
    expect(view.attempts.map(a => [a.position, a.state, a.last_stage, a.pair_ids, a.acked_by_you, a.partner_acked, a.wanted_by_partner]))
      .toEqual([[0, "held", 2, ["p0-0", "p0-1"], false, false, false], [1, "held", 2, ["p1-0", "p1-1"], false, false, false]]);
    expect(await tables(s)).toBe(0);
    const body = await download(s, s.guest, 1, {});
    expect(body[0]).toBe(1);
    const bytes = (await decodeAttempt(body, view.attempts[1].byte_length))!;
    expect(await bytesDigest(bytes)).toBe(view.attempts[1].digest);
    expect(JSON.parse(new TextDecoder().decode(bytes))).toMatchObject({ format: "after-you.attempt", room_id: s.room.room_id, position: 1, branch: 1 });
    expect(await code(await call(`${s.path}/2`, "GET", s.host, undefined, {}, HISTORY))).toBe("404 history_not_found");
    expect(await code(await call(`${s.path}/32`, "GET", s.host))).toBe("400 invalid_field");
    expect(await code(await call(`${s.path}/0/ack`, "POST", s.host, { schema_version: 1, link: view.attempts[0].link }))).toBe("503 history_offload_disabled");
    expect(await code(await call(s.path, "GET", (await relayPair()).host))).toBe("404 room_not_found");
    expect(await tables(s)).toBe(0);
  });

  it("records ACKs with offload on and shows each member the other's", async () => {
    const s = await setup(1), view = await list(s, s.host), link = view.attempts[0].link;
    expect(await code(await call(`${s.path}/0/ack`, "POST", s.host, { schema_version: 1, link: "0".repeat(64) }, ON, HISTORY))).toBe("409 history_mismatch");
    expect(await code(await call(`${s.path}/0/ack`, "POST", s.host, { schema_version: 2, link }, ON, HISTORY))).toBe("422 invalid_history_request");
    const acked = await call(`${s.path}/0/ack`, "POST", s.host, { schema_version: 1, link }, ON, HISTORY);
    expect((await acked.json<HistoryView>()).attempts[0]).toMatchObject({ acked_by_you: true, partner_acked: false, state: "held" });
    expect((await list(s, s.guest)).attempts[0]).toMatchObject({ acked_by_you: false, partner_acked: true });
    expect(await code(await call(`${s.path}/1/ack`, "POST", s.host, { schema_version: 1, link }, ON, HISTORY))).toBe("404 history_not_found");
  });

  it("accepts only the exact bytes of this room's attempt at this place in the chain", async () => {
    const s = await setup(2), other = await setup(1), view = await list(s, s.host);
    const zero = await download(s, s.host, 0), one = await download(s, s.host, 1), foreign = await download(other, other.host, 0);
    const upload = (position: number, body: Uint8Array, headers: Record<string, string> = HISTORY) => call(`${s.path}/${position}`, "POST", s.host, body, ON, headers);
    expect(await code(await upload(1, zero))).toBe("422 history_mismatch");
    expect(await code(await upload(0, one))).toBe("422 history_mismatch");
    expect(await code(await upload(0, foreign))).toBe("422 history_mismatch");
    expect(await code(await upload(0, zero.subarray(0, zero.byteLength - 5)))).toBe("422 history_mismatch");
    const flipped = zero.slice(); flipped[30] ^= 1; expect(await code(await upload(0, flipped))).toBe("422 history_mismatch");
    const raw = await encodeAttempt((await decodeAttempt(zero, view.attempts[0].byte_length))!, ENCODING_RAW);
    const longer = new Uint8Array(raw.byteLength + 1); longer.set(raw); longer[raw.byteLength] = 0x20;
    expect(await code(await upload(0, longer))).toBe("422 history_mismatch");
    expect(await code(await upload(0, new Uint8Array(4 * 1024 * 1024 + 2)))).toBe("413 body_too_large");
    expect(await code(await call(`${s.path}/0`, "POST", s.host, { schema_version: 1 }, ON, HISTORY))).toBe("415 bytes_required");
    // Both encodings of the right bytes are accepted; a held attempt is left as it is.
    for (const body of [zero, raw]) expect((await (await upload(0, body)).json<HistoryView>()).attempts[0]).toMatchObject({ state: "held", acked_by_you: false });
    expect(await code(await call(`${s.path}/0/want`, "POST", s.guest, { schema_version: 1 }, ON, HISTORY))).toBe("200 ok");
    expect((await list(s, s.host)).attempts[0].wanted_by_partner).toBe(false);
  });

  it("answers v1-transferred rooms with their mode and nothing else", async () => {
    const s = await setup(0), players = { host: s.host.player_id, guest: s.guest.player_id };
    await play(s.stub, s.room, chain, 0, undefined, players);
    const offered = await s.stub.replayTransfer(s.host.player_id); if (!offered.ok) throw new Error(offered.code);
    const ack = { schema_version: 1, epoch: offered.value.manifest.epoch, archive_hash: offered.value.manifest.archive_hash };
    await s.stub.acknowledgeReplayTransfer(s.host.player_id, ack); await s.stub.acknowledgeReplayTransfer(s.guest.player_id, ack);
    expect(await list(s, s.guest)).toEqual({ schema_version: 1, mode: "v1_transferred", head: "0".repeat(64), attempts: [] });
    expect(await code(await call(`${s.path}/0`, "GET", s.host, undefined, ON, HISTORY))).toBe("409 history_v1_transferred");
  });
});
