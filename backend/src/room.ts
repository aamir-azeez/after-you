import { DurableObject } from "cloudflare:workers";
import { LEVEL_IDS, equalHash, fail, ok, type Outcome, type Recording, type RoomSnapshot, type RoomState } from "./protocol";
import { initializeSchema } from "./storage-schema";
import { exportSnapshot, restoreSnapshot, snapshotResult } from "./snapshot";

export class Room extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      initializeSchema(this.ctx.storage, "Room");
    });
  }
  // Binding-only maintenance primitives; never dispatched by the public router.
  exportSnapshot(sourceCommit: string): Promise<Outcome<string>> { return snapshotResult(() => exportSnapshot(this.ctx, "Room", sourceCommit)); }
  restoreSnapshot(archive: string, expectedLogicalId: string | null): Promise<Outcome<{ restored: true; checksum: string }>> { return snapshotResult(() => restoreSnapshot(this.ctx, "Room", archive, expectedLogicalId)); }
  private read(): RoomState | null {
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").toArray()[0];
    if (!row) return null;
    const state = JSON.parse(row.data) as RoomState & { deleted?: boolean };
    return state.deleted ? null : state;
  }
  private member(state: RoomState, playerId: string): boolean { return state.host_id === playerId || state.guest_id === playerId; }
  private view(state: RoomState, playerId: string): RoomSnapshot {
    const { invite_code, ...snapshot } = state;
    return playerId === state.host_id ? { ...snapshot, invite_code } : snapshot;
  }
  private write(state: RoomState): void {
    state.updated_at = new Date().toISOString();
    this.ctx.storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify(state));
  }
  private archive(state: RoomState): Outcome<null> {
    const count = this.ctx.storage.sql.exec<{ total: number }>("SELECT COUNT(*) AS total FROM archive WHERE json_extract(data, '$.active_role')='complete'").one().total;
    if (count >= 64 && state.active_role === "complete") return fail(409, "room_history_full");
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO archive VALUES (?,?)", state.attempt, JSON.stringify(state));
    // Failed rehearsals are bounded. Completed replays are never silently removed by a fork.
    this.ctx.storage.sql.exec("DELETE FROM archive WHERE json_extract(data, '$.active_role')!='complete' AND attempt NOT IN (SELECT attempt FROM archive WHERE json_extract(data, '$.active_role')!='complete' ORDER BY attempt DESC LIMIT 24)");
    return ok(null);
  }
  initialize(roomId: string, hostId: string, inviteCode: string): Outcome<RoomSnapshot> {
    const existing = this.read();
    if (existing) return existing.host_id === hostId ? ok(this.view(existing, hostId)) : fail(409, "room_exists");
    if (this.ctx.storage.sql.exec("SELECT id FROM room WHERE id=1").toArray().length) return fail(410, "room_deleted");
    const now = new Date().toISOString();
    const state: RoomState = {
      schema_version: 1, room_id: roomId, revision: 0, attempt: 0,
      host_id: hostId, guest_id: null, level_index: 0, level_id: LEVEL_IDS[0], first_player_id: hostId,
      active_role: "a", recordings: { a: null, b: null }, completed_islands: [],
      created_at: now, updated_at: now, invite_code: inviteCode,
      invite_expires_at: new Date(Date.now() + 7 * 86_400_000).toISOString(), reactions: {}
    };
    this.ctx.storage.sql.exec("INSERT INTO room VALUES (1,?)", JSON.stringify(state));
    return ok(this.view(state, hostId));
  }
  snapshot(playerId: string): Outcome<RoomSnapshot> {
    const state = this.read();
    if (!state || !this.member(state, playerId)) return fail(404, "room_not_found");
    return ok(this.view(state, playerId));
  }
  join(playerId: string, inviteCode: string): Outcome<RoomSnapshot> {
    const state = this.read();
    if (!state || !equalHash(state.invite_code, inviteCode)) return fail(404, "invite_not_found");
    if (this.member(state, playerId)) return ok(this.view(state, playerId));
    if (Date.parse(state.invite_expires_at) < Date.now()) return fail(410, "invite_expired");
    if (state.guest_id) return fail(409, "room_full");
    state.guest_id = playerId; state.revision += 1; this.write(state);
    return ok(this.view(state, playerId));
  }
  private change(playerId: string, revision: number, key: string, requestHash: string, mutate: (state: RoomState) => Outcome<null>): Outcome<RoomSnapshot> {
    const state = this.read();
    if (!state || !this.member(state, playerId)) return fail(404, "room_not_found");
    const scopedKey = playerId + ":" + key;
    const previous = this.ctx.storage.sql.exec<{ request_hash: string }>("SELECT request_hash FROM operations WHERE request_key=?", scopedKey).toArray()[0];
    if (previous) return equalHash(previous.request_hash, requestHash) ? ok(this.view(state, playerId)) : fail(409, "idempotency_key_reused");
    if (state.revision !== revision) return fail(409, "stale_revision");
    return this.ctx.storage.transactionSync(() => {
      const result = mutate(state); if (!result.ok) return result;
      state.revision += 1; this.write(state);
      this.ctx.storage.sql.exec("INSERT INTO operations VALUES (?,?,?)", scopedKey, requestHash, state.revision);
      this.ctx.storage.sql.exec("DELETE FROM operations WHERE rowid NOT IN (SELECT rowid FROM operations ORDER BY rowid DESC LIMIT 256)");
      return ok(this.view(state, playerId));
    });
  }
  commit(playerId: string, revision: number, key: string, requestHash: string, recording: Recording): Outcome<RoomSnapshot> {
    return this.change(playerId, revision, key, requestHash, state => {
      if (recording.level_id !== state.level_id) return fail(409, "wrong_level");
      const expectedRole = state.first_player_id === playerId ? "a" : "b";
      if (recording.role !== expectedRole || state.active_role !== expectedRole) return fail(409, "wrong_turn");
      if (expectedRole === "a") {
        if (!recording.outcome.threw_seed || recording.completed || recording.source_recording_hash) return fail(422, "incomplete_first_turn");
        state.recordings.a = recording; state.active_role = "b";
      } else {
        if (!state.recordings.a || recording.source_recording_hash !== state.recordings.a.final_state_hash) return fail(409, "source_recording_mismatch");
        if (!recording.completed || !recording.outcome.caught_seed || !recording.outcome.planted_seed) return fail(422, "incomplete_second_turn");
        state.recordings.b = recording; state.active_role = "complete";
        if (!state.completed_islands.includes(state.level_id)) state.completed_islands.push(state.level_id);
      }
      return ok(null);
    });
  }
  fork(playerId: string, revision: number, key: string, requestHash: string): Outcome<RoomSnapshot> {
    return this.change(playerId, revision, key, requestHash, state => {
      if (!state.recordings.a) return fail(409, "nothing_to_fork");
      const archived = this.archive(state); if (!archived.ok) return archived;
      state.attempt += 1; state.recordings = { a: null, b: null }; state.active_role = "a"; state.reactions = {};
      return ok(null);
    });
  }
  advance(playerId: string, revision: number, key: string, requestHash: string): Outcome<RoomSnapshot> {
    return this.change(playerId, revision, key, requestHash, state => {
      if (state.active_role !== "complete") return fail(409, "island_not_complete");
      if (state.level_index >= LEVEL_IDS.length - 1) return fail(409, "journey_complete");
      if (!state.guest_id) return fail(409, "partner_required");
      const archived = this.archive(state); if (!archived.ok) return archived;
      state.level_index += 1; state.level_id = LEVEL_IDS[state.level_index]; state.attempt += 1;
      state.first_player_id = state.level_index % 2 === 0 ? state.host_id : state.guest_id;
      state.recordings = { a: null, b: null }; state.active_role = "a"; state.reactions = {};
      return ok(null);
    });
  }
  collection(playerId: string): Outcome<RoomSnapshot[]> {
    const state = this.read();
    if (!state || !this.member(state, playerId)) return fail(404, "room_not_found");
    const saved = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM archive ORDER BY attempt DESC").toArray().map(row => JSON.parse(row.data) as RoomState).filter(item => item.active_role === "complete");
    if (state.active_role === "complete") saved.unshift(state);
    return ok(saved.map(item => this.view(item, playerId)));
  }
  react(playerId: string, revision: number, key: string, requestHash: string, reaction: "love" | "sparkles" | "again"): Outcome<RoomSnapshot> {
    return this.change(playerId, revision, key, requestHash, state => {
      if (state.active_role !== "complete") return fail(409, "island_not_complete");
      state.reactions[playerId] = reaction; return ok(null);
    });
  }
  eraseForPlayer(playerId: string, pendingCreation = false): Outcome<{ deleted: boolean }> {
    const state = this.read();
    if (!state && pendingCreation) {
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO room VALUES (1,?)", JSON.stringify({ deleted: true }));
      return ok({ deleted: true });
    }
    if (!state) return fail(404, "room_not_found");
    if (!this.member(state, playerId)) return fail(404, "room_not_found");
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify({ deleted: true }));
      this.ctx.storage.sql.exec("DELETE FROM archive"); this.ctx.storage.sql.exec("DELETE FROM operations");
    });
    return ok({ deleted: true });
  }
}
