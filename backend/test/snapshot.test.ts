import { env, exports } from "cloudflare:workers";
import { reset, evictDurableObject, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { canonicalJson, digest, randomToken, type Outcome, type Recording } from "../src/protocol";
import { MAX_SNAPSHOT_BYTES, MAX_SNAPSHOT_ROW_BYTES, exportSnapshot, restoreSnapshot, snapshotResult, type PortableSnapshot } from "../src/snapshot";
import firstA from "../../game/tests/fixtures/first-light-a.json";
import firstB from "../../game/tests/fixtures/first-light-b.json";

const commit = "f".repeat(40);
const playerId = "A".repeat(22), guestId = "B".repeat(22), roomId = "c".repeat(22);
const hash = (letter: string) => letter.repeat(64);
const key = () => crypto.randomUUID();
const player = () => env.PLAYERS.get(env.PLAYERS.newUniqueId());
const room = () => env.ROOMS.get(env.ROOMS.newUniqueId());
async function exported(stub: ReturnType<typeof player> | ReturnType<typeof room>): Promise<string> {
  const outcome = await stub.exportSnapshot(commit);
  if (!outcome.ok) throw new Error(outcome.code);
  return outcome.value;
}
async function rejected<T>(pending: Promise<Outcome<T>>, code?: string): Promise<void> {
  const outcome = await pending;
  expect(outcome).toMatchObject({ ok: false, ...(code ? { code } : {}) });
}
const parse = (value: string): PortableSnapshot => JSON.parse(value) as PortableSnapshot;
async function encode(archive: PortableSnapshot): Promise<string> {
  archive.checksum.value = await digest(canonicalJson(archive.payload)); return canonicalJson(archive);
}
async function sourcePlayer() {
  const stub = player();
  expect((await stub.create(playerId, hash("a"), hash("b"))).ok).toBe(true);
  return stub;
}
async function sourceRoom() {
  const stub = room();
  expect((await stub.initialize(roomId, playerId, "A".repeat(20))).ok).toBe(true);
  expect((await stub.join(guestId, "A".repeat(20))).ok).toBe(true);
  return stub;
}
async function completeRoom(stub: ReturnType<typeof room>) {
  expect((await stub.commit(playerId, 1, "first-turn-key-001", hash("a"), firstA as Recording)).ok).toBe(true);
  expect((await stub.commit(guestId, 2, "second-turn-key-01", hash("b"), firstB as Recording)).ok).toBe(true);
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("binding-only portable snapshots in SQLite Workers runtime", () => {
  it("exports and restores the real HTTP guest link without a host invitation", async () => {
    type Account = { player_id: string; device_token: string; recovery_code: string };
    const call = (path: string, body: unknown, account?: Account) => exports.default.fetch(new Request("https://after-you.test" + path, {
      method: "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.51.100.42", ...(account ? { Authorization: "Bearer " + account.device_token, "X-Player-Id": account.player_id } : {}) }, body: JSON.stringify(body)
    }));
    const host = await (await call("/v1/identity", {})).json<Account>();
    const guest = await (await call("/v1/identity", {})).json<Account>();
    const created = await (await call("/v1/rooms", { idempotency_key: key() }, host)).json<{ invite_code: string; room_id: string }>();
    expect((await call("/v1/rooms/join", { invite_code: created.invite_code }, guest)).status).toBe(200);
    const archive = await exported(env.PLAYERS.getByName(guest.player_id)), target = player();
    expect(parse(archive).payload.tables[1].rows[0].data).toBe(JSON.stringify({ room_id: created.room_id, invite_code: "", host: false }));
    expect((await target.restoreSnapshot(archive, guest.player_id)).ok).toBe(true);
    expect(await target.listRooms()).toEqual([{ room_id: created.room_id, invite_code: "", host: false }]);
    expect(await target.authorize(await digest(guest.device_token))).toBe(true);
  });
  it("preserves every Player row, raw JSON and full-width rowids across a new object and eviction", async () => {
    const source = await sourcePlayer();
    const link = { room_id: roomId, invite_code: "A".repeat(20), host: true };
    await source.reserveRoom("create-room-key-01", link);
    await source.recover(hash("b"), hash("c"), hash("d"), hash("e"));
    await runInDurableObject(source, async (_, state) => {
      const stored = state.storage.sql.exec<{ data: string }>("SELECT data FROM identity").one().data;
      state.storage.sql.exec("UPDATE identity SET data=?", JSON.stringify(JSON.parse(stored), null, 2));
      state.storage.sql.exec("UPDATE creations SET rowid=CAST(? AS INTEGER)", "9223372036854775806");
      state.storage.sql.exec("UPDATE rooms SET rowid=CAST(? AS INTEGER)", "9007199254740993");
    });
    const archiveText = await exported(source), archive = parse(archiveText);
    expect(archive.payload.logical_id).toBe(playerId);
    expect(archive.payload.tables[0].rows[0].data).toContain("\n");
    expect(archive.payload.tables[2].rows[0].rowid).toBe("9223372036854775806");
    const target = player();
    expect(await target.restoreSnapshot(archiveText, playerId)).toEqual({ ok: true, value: { restored: true, checksum: archive.checksum.value } });
    await evictDurableObject(target);
    const restored = parse(await exported(target));
    expect(restored.payload.source_object_id).not.toBe(archive.payload.source_object_id);
    expect(restored.payload.tables).toEqual(archive.payload.tables);
    expect(restored.payload.summary).toEqual(archive.payload.summary);
    expect(await target.authorize(hash("a"))).toBe(false);
    expect(await target.authorize(hash("c"))).toBe(true);
    expect(await target.recover(hash("b"), hash("c"), hash("d"), hash("e"))).toEqual({ ok: true, value: { player_id: playerId, recovered: true } });
    expect(await target.recover(hash("b"), hash("c"), hash("d"), hash("f"))).toMatchObject({ ok: false, code: "recovery_request_mismatch" });
    expect(await target.reserveRoom("create-room-key-01", { ...link, room_id: "d".repeat(22) })).toEqual({ ok: true, value: link });
  });

  it("preserves deleting identity state and an identity whose rows have been erased", async () => {
    const source = await sourcePlayer(); await source.beginDelete();
    const target = player(); await target.restoreSnapshot(await exported(source), playerId);
    expect(await target.authorize(hash("a"))).toBe(false);
    expect(await target.authorize(hash("a"), true)).toBe(true);
    await source.finishDelete();
    const archive = await exported(source), empty = player();
    expect(parse(archive).payload.summary.state).toBe("empty");
    expect(parse(archive).payload.logical_id).toBe(null);
    await empty.restoreSnapshot(archive, null);
    expect(parse(await exported(empty)).payload.tables).toEqual(parse(archive).payload.tables);
  });

  it("preserves room revisions, both replay kinds, versions, reactions and mutation receipts", async () => {
    const source = await sourceRoom(); await completeRoom(source);
    await source.react(playerId, 3, "reaction-key-0001", hash("c"), "love");
    await source.fork(playerId, 4, "fork-key-00000001", hash("d"));
    await source.commit(playerId, 5, "first-turn-key-002", hash("e"), firstA as Recording);
    await source.fork(playerId, 6, "fork-key-00000002", hash("f"));
    const original = await exported(source), target = room();
    await target.restoreSnapshot(original, roomId); await evictDurableObject(target);
    const archive = parse(original), restored = parse(await exported(target));
    expect(restored.payload.tables).toEqual(archive.payload.tables);
    expect(restored.payload.summary).toEqual({ state: "active", revision: 7, attempt: 2 });
    expect(restored.payload.tables[2].rows).toHaveLength(2);
    expect(await target.collection(playerId)).toEqual(await source.collection(playerId));
    expect(await target.snapshot(guestId)).toEqual(await source.snapshot(guestId));
    expect(await target.commit(playerId, 1, "first-turn-key-001", hash("a"), firstA as Recording)).toEqual(await source.snapshot(playerId));
    expect(await target.commit(playerId, 1, "first-turn-key-001", hash("b"), firstA as Recording)).toMatchObject({ ok: false, code: "idempotency_key_reused" });
    expect(await target.commit(playerId, 1, key(), hash("a"), firstA as Recording)).toMatchObject({ ok: false, code: "stale_revision" });
  });

  it("preserves a room tombstone and prevents its resurrection", async () => {
    const source = await sourceRoom(); await completeRoom(source); await source.eraseForPlayer(playerId);
    const archive = await exported(source), target = room();
    expect(parse(archive).payload.summary.state).toBe("deleted");
    await target.restoreSnapshot(archive, null);
    expect(parse(await exported(target)).payload.tables).toEqual(parse(archive).payload.tables);
    expect(await target.initialize(roomId, playerId, "A".repeat(20))).toMatchObject({ ok: false, code: "room_deleted" });
    expect(await target.snapshot(playerId)).toMatchObject({ ok: false, code: "room_not_found" });
  });

  it("rejects all nonempty target tables, including orphan receipts and tombstones", async () => {
    const source = await sourcePlayer(), archive = await exported(source);
    const occupied = await sourcePlayer();
    await rejected(occupied.restoreSnapshot(archive, playerId), "snapshot_target_not_empty");
    const receiptsOnly = player();
    await runInDurableObject(receiptsOnly, async (_, state) => { state.storage.sql.exec("INSERT INTO creations VALUES (?,?)", "orphan-key-000001", "{}"); });
    await rejected(receiptsOnly.restoreSnapshot(archive, playerId), "snapshot_target_not_empty");
    const sourceR = await sourceRoom(), dead = room(); await dead.eraseForPlayer(playerId, true);
    await rejected(dead.restoreSnapshot(await exported(sourceR), roomId), "snapshot_target_not_empty");
    expect(await occupied.authorize(hash("a"))).toBe(true);
  });

  it("rejects tampering, wrong logical identity, wrong object kind and duplicate envelope keys", async () => {
    const source = await sourcePlayer(), archive = await exported(source), target = player();
    await rejected(target.restoreSnapshot(archive.replace(hash("a"), hash("c")), playerId), "snapshot_checksum_mismatch");
    await rejected(target.restoreSnapshot(archive, guestId), "snapshot_identity_mismatch");
    await rejected(room().restoreSnapshot(archive, playerId), "unsupported_snapshot_format");
    const duplicate = archive.replace('"format_version":1', '"format_version":1,"format_version":1');
    await rejected(target.restoreSnapshot(duplicate, playerId), "noncanonical_snapshot");
    expect(parse(await exported(target)).payload.summary.state).toBe("empty");
  });

  it("validates schemas, row values and summaries even with a recomputed checksum", async () => {
    const source = await sourcePlayer(), original = await exported(source), target = player();
    const changes: ((a: PortableSnapshot) => void)[] = [
      a => { a.payload.format_version = 99 as 1; },
      a => { a.payload.database_schema_version = 2 as 1; },
      a => { a.payload.tables.pop(); },
      a => { a.payload.tables[0].schema += "; DROP TABLE identity"; },
      a => { a.payload.tables[0].columns.push("extra"); },
      a => { a.payload.tables[0].rows[0].extra = "extra"; },
      a => { a.payload.tables[0].rows[0].rowid = "9007199254740993"; },
      a => { a.payload.tables[0].rows[0].data = "[]"; },
      a => { a.payload.tables[0].rows[0].data = "{"; },
      a => { a.payload.tables[0].rows[0].data = String(a.payload.tables[0].rows[0].data).replace('"state":', '"state":"active","state":'); },
      a => { a.payload.summary.state = "deleting"; },
      a => { a.payload.source_object_id = "invalid"; },
      a => { a.payload.exported_at = "2026-02-31T00:00:00.000Z"; },
      a => { const identity = JSON.parse(String(a.payload.tables[0].rows[0].data)); identity.device_hash = "not-a-hash"; a.payload.tables[0].rows[0].data = JSON.stringify(identity); }
    ];
    for (const change of changes) {
      const archive = parse(original); change(archive);
      await rejected(target.restoreSnapshot(await encode(archive), playerId));
      expect(parse(await exported(target)).payload.summary.state).toBe("empty");
    }
  });

  it("rejects duplicate keys, unsorted rowids, unsafe rowids and table overflow", async () => {
    const source = await sourcePlayer();
    await source.reserveRoom("room-key-00000001", { room_id: roomId, invite_code: "A".repeat(20), host: true });
    await source.reserveRoom("room-key-00000002", { room_id: "d".repeat(22), invite_code: "B".repeat(20), host: true });
    const original = await exported(source), target = player();
    for (const change of [
      (a: PortableSnapshot) => { a.payload.tables[2].rows[1].request_key = a.payload.tables[2].rows[0].request_key; },
      (a: PortableSnapshot) => { a.payload.tables[2].rows.reverse(); },
      (a: PortableSnapshot) => { a.payload.tables[2].rows[1].rowid = "9223372036854775808"; },
      (a: PortableSnapshot) => { a.payload.tables[2].rows = Array.from({ length: 129 }, () => ({ ...a.payload.tables[2].rows[0] })); }
    ]) {
      const archive = parse(original); change(archive);
      await rejected(target.restoreSnapshot(await encode(archive), playerId));
    }
  });

  it("rejects oversized archives and individual JSON rows before mutation", async () => {
    const target = player();
    await rejected(target.restoreSnapshot(" ".repeat(MAX_SNAPSHOT_BYTES + 1), null), "snapshot_too_large");
    const original = parse(await exported(await sourcePlayer()));
    original.payload.tables[0].rows[0].data = " ".repeat(MAX_SNAPSHOT_ROW_BYTES + 1);
    await rejected(target.restoreSnapshot(await encode(original), playerId), "snapshot_row_too_large");
    expect(parse(await exported(target)).payload.summary.state).toBe("empty");
  });

  it("rejects unknown live schemas and unhandled KV state rather than omitting them", async () => {
    const extra = await sourcePlayer();
    await runInDurableObject(extra, async (_, state) => { state.storage.sql.exec("CREATE TABLE unexpected (data TEXT)"); });
    await rejected(extra.exportSnapshot(commit), "unsupported_storage_schema");
    const kv = await sourcePlayer();
    await runInDurableObject(kv, async (_, state) => { state.storage.kv.put("unhandled", { value: 1 }); });
    await rejected(kv.exportSnapshot(commit));
    await rejected(kv.restoreSnapshot(await exported(await sourcePlayer()), playerId));
    await runInDurableObject(kv, async (_, state) => { state.storage.kv.delete("unhandled"); });
    // Cloudflare leaves its empty internal _cf_KV table behind.
    const first = parse(await exported(kv)), second = parse(await exported(kv));
    expect(first.payload.tables).toEqual(second.payload.tables);
    const target = player();
    await runInDurableObject(target, async (_, state) => { state.storage.kv.put("temporary", 1); state.storage.kv.delete("temporary"); });
    expect((await target.restoreSnapshot(await exported(kv), playerId)).ok).toBe(true);
  });

  it("rejects inconsistent room history, receipts, reactions and recording versions", async () => {
    const source = await sourceRoom(); await completeRoom(source);
    await source.react(playerId, 3, "reaction-key-0001", hash("c"), "love");
    await source.fork(playerId, 4, "fork-key-00000001", hash("d"));
    const original = await exported(source), target = room();
    const changes: ((a: PortableSnapshot) => void)[] = [
      a => { a.payload.tables[1].rows[0].revision = 999; },
      a => { a.payload.tables[1].rows[0].request_key = "Z".repeat(22) + ":first-turn-key-001"; },
      a => { a.payload.tables[2].rows[0].attempt = 4; a.payload.tables[2].rows[0].rowid = "4"; },
      a => { a.payload.tables[2].rows[0].data = String(a.payload.tables[2].rows[0].data).replace('"simulation_version":1', '"simulation_version":2'); },
      a => { a.payload.tables[2].rows[0].data = String(a.payload.tables[2].rows[0].data).replace('"level_version":1', '"level_version":2'); },
      a => { a.payload.tables[2].rows[0].data = String(a.payload.tables[2].rows[0].data).replace('"love"', '["love"]'); },
      a => { a.payload.tables[2].rows[0].data = String(a.payload.tables[2].rows[0].data).replace('"room_id":"' + roomId + '"', '"room_id":"' + "d".repeat(22) + '"'); }
    ];
    for (const change of changes) {
      const archive = parse(original); change(archive);
      await rejected(target.restoreSnapshot(await encode(archive), roomId));
      expect(parse(await exported(target)).payload.summary.state).toBe("empty");
    }
    expect((await target.restoreSnapshot(original, roomId)).ok).toBe(true);
  });

  it("rejects alarm state without claiming it is included", async () => {
    const source = await sourcePlayer();
    await runInDurableObject(source, async (_, state) => { await state.storage.setAlarm(Date.now() + 86_400_000); });
    await rejected(source.exportSnapshot(commit), "unsupported_storage_alarm");
    const target = player(), original = await exported(await sourcePlayer());
    await runInDurableObject(target, async (_, state) => { await state.storage.setAlarm(Date.now() + 86_400_000); });
    await rejected(target.restoreSnapshot(original, playerId), "unsupported_storage_alarm");
  });

  it("hashes a detached snapshot even if state changes while the digest is pending", async () => {
    const source = await sourcePlayer();
    await runInDurableObject(source, async (instance, state) => {
      const actualDigest = crypto.subtle.digest.bind(crypto.subtle);
      const intercept = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => {
        instance.beginDelete(); return actualDigest(algorithm, data);
      });
      let original: string;
      try { original = await exportSnapshot(state, "Player", commit); } finally { intercept.mockRestore(); }
      expect(parse(original).payload.summary.state).toBe("active");
      expect(parse(original).checksum.value).toBe(await digest(canonicalJson(parse(original).payload)));
      expect(parse(await exportSnapshot(state, "Player", commit)).payload.summary.state).toBe("deleting");
    });
  });

  it("rechecks target emptiness after asynchronous checksum validation", async () => {
    const source = await sourcePlayer(), archive = await exported(source), target = player();
    await runInDurableObject(target, async (instance, state) => {
      const actualDigest = crypto.subtle.digest.bind(crypto.subtle);
      const intercept = vi.spyOn(crypto.subtle, "digest").mockImplementationOnce(async (algorithm, data) => {
        instance.create(guestId, hash("e"), hash("f")); return actualDigest(algorithm, data);
      });
      try { await rejected(snapshotResult(() => restoreSnapshot(state, "Player", archive, playerId)), "snapshot_target_not_empty"); }
      finally { intercept.mockRestore(); }
      expect(instance.authorize(hash("e"))).toBe(true);
      expect(instance.authorize(hash("a"))).toBe(false);
    });
  });

  it("rolls back all earlier inserts on a later storage failure", async () => {
    const source = await sourcePlayer();
    await source.reserveRoom("create-room-key-01", { room_id: roomId, invite_code: "A".repeat(20), host: true });
    const archive = await exported(source), target = player();
    await runInDurableObject(target, async (_, state) => {
      const failingSql = new Proxy(state.storage.sql, { get(sql, property) {
        if (property === "exec") return (query: string, ...bindings: unknown[]) => {
          if (query.startsWith("INSERT INTO creations")) throw new Error("injected_storage_failure");
          return sql.exec(query, ...bindings);
        };
        return Reflect.get(sql, property, sql);
      } });
      const storage = new Proxy(state.storage, { get(actual, property) {
        if (property === "sql") return failingSql;
        const value: unknown = Reflect.get(actual, property, actual);
        return typeof value === "function" ? value.bind(actual) : value;
      } });
      const context = new Proxy(state, { get(actual, property) { return property === "storage" ? storage : Reflect.get(actual, property, actual); } });
      const result = await snapshotResult(() => restoreSnapshot(context, "Player", archive, playerId));
      expect(result).toEqual({ ok: false, status: 500, code: "snapshot_storage_error" });
      for (const query of ["SELECT * FROM identity", "SELECT * FROM rooms", "SELECT * FROM creations"]) expect(state.storage.sql.exec(query).toArray()).toEqual([]);
    });
    expect((await target.restoreSnapshot(archive, playerId)).ok).toBe(true);
  });

  it("does not expose maintenance RPCs through public HTTP even with a player token", async () => {
    const id = randomToken(16), secret = randomToken();
    await env.PLAYERS.getByName(id).create(id, await digest(secret), hash("a"));
    for (const path of ["/v1/exportSnapshot", "/v1/identity/exportSnapshot", "/v1/identity/restoreSnapshot", `/v1/rooms/${roomId}/exportSnapshot`, `/v1/rooms/${roomId}/restoreSnapshot`]) {
      const response = await exports.default.fetch(new Request("https://after-you.test" + path, { method: "POST", headers: { "Authorization": "Bearer " + secret, "X-Player-Id": id, "Content-Type": "application/json" }, body: "{}" }));
      expect(response.status).toBe(404);
    }
  });
});
