import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { canonicalJson } from "../src/protocol";
import { ZERO_LINK, attemptBlob, attemptLink, attemptRows, blobBytes, lastStage, type AttemptRoom } from "../src/v2/history-blob";
import { bytesDigest, decodeBlob, encodeBlob, ENCODING_RAW } from "../src/blob-codec";
import { finishedAttempts, historyChain } from "../src/v2/history";
import { CHAINS, ROOM, fork, newRoom, open, play, playA, type Room } from "./history-chains";
import vectors from "../../game/tests/fixtures/history/vectors.json";
import relayBlob from "../../game/tests/fixtures/history/relay-attempt.json";

afterEach(async () => { await reset(); });
/** The vector file is the canonical bytes themselves, so re-canonicalizing it is the identity. */
const relayJson = canonicalJson(relayBlob);
const roomKey = (chain: (typeof CHAINS)[number]): AttemptRoom => ({ room_id: ROOM, ...chain.key });
const inRoom = <T>(room: Room, read: (storage: DurableObjectStorage) => T | Promise<T>) => runInDurableObject(room, (_, ctx) => read(ctx.storage));
const base64 = (text: string) => Uint8Array.from(atob(text), char => char.charCodeAt(0));

describe("attempt blobs and the attempt hash chain", () => {
  it("builds the shared vector blob from a played room and hashes it to the shared digest and links", async () => {
    const room = newRoom(), chain = CHAINS[0];
    await play(room, await open(room, chain), chain, 0);
    const blob = await inRoom(room, storage => attemptBlob(storage, roomKey(chain), 0));
    const bytes = blobBytes(blob!);
    expect(new TextDecoder().decode(bytes)).toBe(relayJson);
    expect(bytes.byteLength).toBe(vectors.byte_length);
    expect(await bytesDigest(bytes)).toBe(vectors.digest);
    const link0 = await attemptLink(vectors.room, 0, ZERO_LINK, vectors.digest, vectors.byte_length);
    expect([link0, await attemptLink(vectors.room, 1, link0, vectors.digest, vectors.byte_length)]).toEqual(vectors.links);
    expect(await attemptLink({ ...vectors.room, room_id: "S".repeat(22) }, 0, ZERO_LINK, vectors.digest, vectors.byte_length)).not.toBe(link0);
    expect(await attemptLink({ ...vectors.room, level_version: 3 }, 0, ZERO_LINK, vectors.digest, vectors.byte_length)).not.toBe(link0);
  });

  it("decodes Godot's and zlib's deflate, round-trips every chapter's blob, and refuses anything but the exact length", async () => {
    const expected = new TextEncoder().encode(relayJson);
    for (const encoded of [vectors.deflate_base64.zlib, vectors.deflate_base64.godot]) {
      const body = base64(encoded);
      expect(body[0]).toBe(1);
      expect(await decodeBlob(body, expected.byteLength)).toEqual(expected);
      expect(await decodeBlob(body, expected.byteLength - 1)).toBeNull();
      expect(await decodeBlob(body, expected.byteLength + 1)).toBeNull();
      expect(await decodeBlob(body.subarray(0, body.byteLength - 9), expected.byteLength)).toBeNull();
      const flipped = body.slice(); flipped[40] ^= 0x10;
      const decoded = await decodeBlob(flipped, expected.byteLength);
      expect(decoded === null || await bytesDigest(decoded) !== vectors.digest).toBe(true);
    }
    for (const chain of CHAINS) {
      const room = newRoom();
      await play(room, await open(room, chain), chain, 0);
      const bytes = blobBytes((await inRoom(room, storage => attemptBlob(storage, roomKey(chain), 0)))!);
      const deflated = await encodeBlob(bytes), raw = await encodeBlob(bytes, ENCODING_RAW);
      console.log("ATTEMPT", chain.name, bytes.byteLength, "bytes, deflate", deflated.byteLength - 1, (bytes.byteLength / (deflated.byteLength - 1)).toFixed(1) + "x");
      expect(deflated.byteLength * 2).toBeLessThan(bytes.byteLength);
      expect(await decodeBlob(deflated, bytes.byteLength)).toEqual(bytes);
      expect(await decodeBlob(raw, bytes.byteLength)).toEqual(bytes);
      expect(await bytesDigest((await decodeBlob(deflated, bytes.byteLength))!)).toBe(await bytesDigest(bytes));
      const extra = new Uint8Array(raw.byteLength + 1); extra.set(raw);
      expect(await decodeBlob(extra, bytes.byteLength)).toBeNull();
      expect(await decodeBlob(new Uint8Array([2, ...raw.subarray(1)]), bytes.byteLength)).toBeNull();
    }
  });

  it("stops inflating a bomb once it passes the expected length", async () => {
    const bomb = await encodeBlob(new Uint8Array(64 * 1024 * 1024));
    expect(bomb.byteLength).toBeLessThan(128 * 1024);
    const started = Date.now();
    expect(await decodeBlob(bomb, 4 * 1024 * 1024)).toBeNull();
    expect(Date.now() - started).toBeLessThan(5000);
  });

  it("rebuilds every turn and pair row of an attempt canonically equal to the rows it came from", async () => {
    for (const chain of CHAINS) {
      const room = newRoom();
      await play(room, await open(room, chain), chain, 0);
      await inRoom(room, storage => {
        const blob = attemptBlob(storage, roomKey(chain), 0)!, rows = attemptRows(blob);
        expect(lastStage(blob)).toBe(chain.stages.length);
        for (const row of storage.sql.exec<{ pair_id: string; data: string }>("SELECT pair_id,data FROM pairs")) expect(canonicalJson(rows.pairs.get(row.pair_id))).toBe(canonicalJson(JSON.parse(row.data)));
        for (const row of storage.sql.exec<{ turn_id: string; data: string }>("SELECT turn_id,data FROM turns")) expect(canonicalJson(rows.turns.get(row.turn_id))).toBe(canonicalJson(JSON.parse(row.data)));
        expect(rows.pairs.size).toBe(chain.stages.length); expect(rows.turns.size).toBe(2 * chain.stages.length);
      });
    }
  });

  it("chains finished attempts in order, with open first turns, empty attempts and a completed room's last attempt", async () => {
    const chain = CHAINS.at(-1)!, room = newRoom(), key = roomKey(chain);
    let state = await play(room, await open(room, chain), chain, 0, 2);
    state = await fork(room, state, 1);                       // attempt 0: two pairs
    state = await playA(room, state, chain.stages[1]);
    state = await fork(room, state, 1);                       // attempt 1: one open first turn
    state = await fork(room, state, 0);                       // attempt 2: empty
    state = await play(room, state, chain, 0);                // attempt 3: the whole chapter
    const live = await inRoom(room, storage => historyChain(storage, key, finishedAttempts(state.branch, false)));
    expect(live.records.map(record => [record.position, record.last_stage, record.pair_ids])).toEqual([[0, 2, ["p0-0", "p0-1"]], [1, 1, []], [2, 0, []]]);
    const done = await inRoom(room, storage => historyChain(storage, key, finishedAttempts(state.branch, state.stage_index === chain.stages.length)));
    expect(done.records).toHaveLength(4); expect(done.records.slice(0, 3)).toEqual(live.records);
    expect(done.records[3]).toMatchObject({ last_stage: 6, state: "held", pair_ids: ["p3-0", "p3-1", "p3-2", "p3-3", "p3-4", "p3-5"] });
    let previous = ZERO_LINK;
    for (const { record, bytes } of done.fresh) {
      expect(record.digest).toBe(await bytesDigest(bytes));
      expect(record.link).toBe(await attemptLink(key, record.position, previous, record.digest, bytes.byteLength));
      previous = record.link;
    }
    await inRoom(room, storage => {
      const open = attemptBlob(storage, key, 1)!;
      expect(open.checkpoint).toBeNull(); expect(open.open_turn?.recording_hash).toBe(chain.stages[1].a.recording_hash);
      expect(attemptRows(open).turns.get("t1-1-a")?.recording_hash).toBe(chain.stages[1].a.recording_hash);
      expect(attemptBlob(storage, key, 2)).toMatchObject({ checkpoint: null, open_turn: null, rows: { turns: [], pairs: [] } });
      storage.sql.exec("UPDATE turns SET data=? WHERE turn_id='t0-0-a'", JSON.stringify({ recording_hash: chain.stages[0].a.recording_hash }));
      expect(attemptBlob(storage, key, 0)).toBeNull();
    });
  });
});
