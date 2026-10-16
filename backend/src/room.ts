import { DurableObject } from "cloudflare:workers";
import { ApiError, LEVEL_IDS, equalHash, fail, ok, type LegacySimulationVersion, type Outcome, type Recording, type RoomSnapshot, type RoomState } from "./protocol";
import { acceptedRedo, consentToRedo, initializeRedo, mutateRedo, parseRedoMutation, redoState, resetRedo, type RedoSource, type RedoState } from "./redo-control";
import { initializeSchema } from "./storage-schema";
import type { MemberRoomState } from "./room-leave";
import { anyDeparture, clearDepartures, departed, recordDeparture } from "./room-departure";
import { exportSnapshot, restoreSnapshot, snapshotResult } from "./snapshot";
import { clearTurnHints, deliverTurnHints, initializeNotifications, queueRedoHint, queueTurnHint, redoHintCurrent, scheduleGameplayNotifications, scheduleNotifications, turnHintEligible } from "./notification-storage";
import type { RoomHint } from "./notifications";
import { interactionBlocked } from "./safety";
import { friendRoomInvite } from "./friends";
import { clearRoomInboxActivity, initializeRoomInboxActivity, recordRemoteRoomActivity } from "./room-inbox-storage";
import { legacyInboxProjection } from "./room-inbox";

export class Room extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      initializeSchema(this.ctx.storage, "Room");
      initializeNotifications(this.ctx.storage, "Room");
      initializeRedo(this.ctx.storage);
      initializeRoomInboxActivity(this.ctx.storage);
    });
  }
  // Binding-only maintenance primitives; never dispatched by the public router.
  exportSnapshot(sourceCommit: string): Promise<Outcome<string>> { return snapshotResult(() => exportSnapshot(this.ctx, "Room", sourceCommit)); }
  restoreSnapshot(archive: string, expectedLogicalId: string | null): Promise<Outcome<{ restored: true; checksum: string }>> { return snapshotResult(() => restoreSnapshot(this.ctx, "Room", archive, expectedLogicalId)); }
  alarm(): Promise<void> { return deliverTurnHints(this.ctx.storage, this.env, () => this.read()); }
  notificationEligible(player: string, hint: RoomHint): boolean {
    const state = this.read();
    return turnHintEligible(this.ctx.storage, state, player, hint) && (hint.kind !== "redo_requested" || redoHintCurrent(this.ctx.storage, state && this.redoSource(state), player, hint));
  }
  inboxProjection(player: string) { return legacyInboxProjection(this.ctx.storage, player); }
  /** Whether this member's island is in play (or waiting for a friend), finished, or gone. */
  memberRoomState(player: string): MemberRoomState {
    const state = this.read();
    if (!state || !this.member(state, player)) return "gone";
    return state.active_role === "complete" ? "finished" : "in_play";
  }
  resolvesInvitation(inviteCode: string): boolean {
    return this.ctx.storage.sql.exec("SELECT 1 AS found FROM room WHERE id=1 AND (json_extract(data,'$.invite_code')=? OR json_extract(data,'$.deleted') IS 1)", inviteCode).toArray().length > 0;
  }
  private read(): RoomState | null {
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").toArray()[0];
    if (!row) return null;
    const state = JSON.parse(row.data) as RoomState & { deleted?: boolean };
    return state.deleted ? null : state;
  }
  /** A member who left the finished room (room-departure.ts) is no longer one. */
  private member(state: RoomState, playerId: string): boolean { return (state.host_id === playerId || state.guest_id === playerId) && !departed(this.ctx.storage, playerId); }
  private redoSource(state: RoomState): RedoSource | null {
    if (!state.guest_id || state.active_role !== "b" || !state.recordings.a || state.recordings.b) return null;
    return { room_id: state.room_id, revision: state.revision, branch: state.attempt, stage_index: state.level_index,
      a_hash: state.recordings.a.final_state_hash, first_player_id: state.first_player_id,
      second_player_id: state.first_player_id === state.host_id ? state.guest_id : state.host_id };
  }
  async redo(playerId: string, value?: unknown, deviceHash?: string): Promise<Outcome<RedoState>> {
    try {
      const observed = this.read();
      if (!observed || !this.member(observed, playerId)) return fail(404, "room_not_found");
      if (await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
      const input = value === undefined ? null : await parseRedoMutation(value);
      if (deviceHash !== undefined && !await this.env.PLAYERS.getByName(playerId).authorize(deviceHash)) return fail(401, "invalid_auth");
      return await this.ctx.storage.transaction(async () => {
        const state = this.read();
        if (!state || !this.member(state, playerId)) return fail(404, "room_not_found");
        const source = this.redoSource(state);
        if (!input) return ok(redoState(this.ctx.storage, source));
        // Only a first request reaches the partner; retries return the stored state silently.
        const first = input.action === "request" && source !== null && redoState(this.ctx.storage, source).request === null;
        const result = mutateRedo(this.ctx.storage, source, playerId, input);
        if (first && result.ok && result.value.request?.status === "pending" &&
          queueRedoHint(this.ctx.storage, this.env, "legacy", state, source.first_player_id, result.value.request.request_id)) await scheduleGameplayNotifications(this.ctx.storage);
        return result;
      });
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
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
  initialize(roomId: string, hostId: string, inviteCode: string, simulationVersion: LegacySimulationVersion = 1): Outcome<RoomSnapshot> {
    const existing = this.read();
    if (existing) {
      if (existing.host_id !== hostId) return fail(409, "room_exists");
      return (existing.simulation_version ?? 1) === simulationVersion ? ok(this.view(existing, hostId)) : fail(409, "idempotency_key_reused");
    }
    if (this.ctx.storage.sql.exec("SELECT id FROM room WHERE id=1").toArray().length) return fail(410, "room_deleted");
    const now = new Date().toISOString();
    const state: RoomState = {
      schema_version: 1, room_id: roomId, revision: 0, attempt: 0,
      ...(simulationVersion === 1 ? {} : { simulation_version: simulationVersion }),
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
  operationSnapshot(playerId: string, key: string, requestHash: string): Outcome<{ accepted: boolean; room: RoomSnapshot }> {
    const snapshot = this.snapshot(playerId); if (!snapshot.ok) return snapshot;
    const previous = this.ctx.storage.sql.exec<{ request_hash: string }>("SELECT request_hash FROM operations WHERE request_key=?", playerId + ":" + key).toArray()[0];
    if (previous && !equalHash(previous.request_hash, requestHash)) return fail(409, "idempotency_key_reused");
    return ok({ accepted: !!previous, room: snapshot.value });
  }
  safetyMembers(playerId: string): Outcome<{ host_id: string; guest_id: string | null }> {
    const state = this.read(); if (!state || !this.member(state, playerId)) return fail(404, "room_not_found");
    return ok({ host_id: state.host_id, guest_id: state.guest_id });
  }
  /** Binding only; friendship, blocks and device authorization live in the router. */
  friendInvite(host: string, visitor: string) { return friendRoomInvite(this.ctx.storage, host, visitor); }
  async join(playerId: string, inviteCode: string, supportedSimulationVersion: LegacySimulationVersion = 1): Promise<Outcome<RoomSnapshot>> {
    const observed = this.read();
    if (observed && equalHash(observed.invite_code, inviteCode) && playerId !== observed.host_id && await interactionBlocked(this.env, observed.host_id, playerId)) return fail(403, "player_blocked");
    return this.ctx.storage.transaction(async () => {
    const state = this.read();
    if (!state || !equalHash(state.invite_code, inviteCode)) return fail(404, "invite_not_found");
    if ((state.simulation_version ?? 1) > supportedSimulationVersion) return fail(422, "unsupported_simulation_version");
    if (this.member(state, playerId)) return ok(this.view(state, playerId));
    if (Date.parse(state.invite_expires_at) < Date.now()) return fail(410, "invite_expired");
    if (state.guest_id) return fail(409, "room_full");
    state.guest_id = playerId; state.revision += 1; this.write(state);
    recordRemoteRoomActivity(this.ctx.storage, playerId, state.host_id, state.guest_id);
    if (state.recordings.a) queueTurnHint(this.ctx.storage, this.env, "legacy", state, state.host_id, playerId);
    await scheduleGameplayNotifications(this.ctx.storage);
    return ok(this.view(state, playerId));
    });
  }
  private async change(playerId: string, revision: number, key: string, requestHash: string, mutate: (state: RoomState) => Outcome<null>, notify = false, redoDeviceHash?: string, trackRemoteActivity = false): Promise<Outcome<RoomSnapshot>> {
    const observed = this.read();
    if (observed && await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
    if (redoDeviceHash !== undefined && !await this.env.PLAYERS.getByName(playerId).authorize(redoDeviceHash)) return fail(401, "invalid_auth");
    return this.ctx.storage.transaction(async () => {
    const state = this.read();
    if (!state || !this.member(state, playerId)) return fail(404, "room_not_found");
    const scopedKey = playerId + ":" + key;
    const previous = this.ctx.storage.sql.exec<{ request_hash: string }>("SELECT request_hash FROM operations WHERE request_key=?", scopedKey).toArray()[0];
    if (previous) return equalHash(previous.request_hash, requestHash) ? ok(this.view(state, playerId)) : fail(409, "idempotency_key_reused");
    if (state.revision !== revision) return fail(409, "stale_revision");
      const result = mutate(state); if (!result.ok) return result;
      state.revision += 1; this.write(state);
      if (trackRemoteActivity) recordRemoteRoomActivity(this.ctx.storage, playerId, state.host_id, state.guest_id);
      this.ctx.storage.sql.exec("INSERT INTO operations VALUES (?,?,?)", scopedKey, requestHash, state.revision);
      this.ctx.storage.sql.exec("DELETE FROM operations WHERE rowid NOT IN (SELECT rowid FROM operations ORDER BY rowid DESC LIMIT 256)");
      if (notify) queueTurnHint(this.ctx.storage, this.env, "legacy", state, playerId);
      await scheduleGameplayNotifications(this.ctx.storage);
      return ok(this.view(state, playerId));
    });
  }
  commit(playerId: string, revision: number, key: string, requestHash: string, recording: Recording): Promise<Outcome<RoomSnapshot>> {
    return this.change(playerId, revision, key, requestHash, state => {
      if (recording.level_id !== state.level_id) return fail(409, "wrong_level");
      if (recording.simulation_version !== (state.simulation_version ?? 1)) return fail(422, "unsupported_simulation_version");
      const expectedRole = state.first_player_id === playerId ? "a" : "b";
      if (recording.role !== expectedRole || state.active_role !== expectedRole) return fail(409, "wrong_turn");
      if (expectedRole === "a") {
        if (!recording.outcome.threw_seed || recording.completed || recording.source_recording_hash) return fail(422, "incomplete_first_turn");
        state.recordings.a = recording; state.active_role = "b";
      } else {
        if (!state.recordings.a || recording.source_recording_hash !== state.recordings.a.final_state_hash || recording.simulation_version !== state.recordings.a.simulation_version) return fail(409, "source_recording_mismatch");
        if (!recording.completed || !recording.outcome.caught_seed || !recording.outcome.planted_seed) return fail(422, "incomplete_second_turn");
        state.recordings.b = recording; state.active_role = "complete";
        if (!state.completed_islands.includes(state.level_id)) state.completed_islands.push(state.level_id);
      }
      return ok(null);
    }, true, undefined, true);
  }
  fork(playerId: string, revision: number, key: string, requestHash: string, redoRequestId?: string, redoDeviceHash?: string): Promise<Outcome<RoomSnapshot>> {
    return this.change(playerId, revision, key, requestHash, state => {
      if (anyDeparture(this.ctx.storage)) return fail(409, "room_member_left");
      if (redoRequestId !== undefined) { const consent = consentToRedo(this.ctx.storage, this.redoSource(state), playerId, redoRequestId); if (!consent.ok) return consent; }
      if (!state.recordings.a) return fail(409, "nothing_to_fork");
      const archived = this.archive(state); if (!archived.ok) return archived;
      state.attempt += 1; state.recordings = { a: null, b: null }; state.active_role = "a"; state.reactions = {};
      if (redoRequestId !== undefined) acceptedRedo(this.ctx.storage);
      clearTurnHints(this.ctx.storage);
      return ok(null);
    }, false, redoRequestId === undefined ? undefined : redoDeviceHash, redoRequestId !== undefined);
  }
  advance(playerId: string, revision: number, key: string, requestHash: string): Promise<Outcome<RoomSnapshot>> {
    return this.change(playerId, revision, key, requestHash, state => {
      if (state.active_role !== "complete") return fail(409, "island_not_complete");
      if (anyDeparture(this.ctx.storage)) return fail(409, "room_member_left");
      if (state.level_index >= LEVEL_IDS.length - 1) return fail(409, "journey_complete");
      if (!state.guest_id) return fail(409, "partner_required");
      const archived = this.archive(state); if (!archived.ok) return archived;
      state.level_index += 1; state.level_id = LEVEL_IDS[state.level_index]; state.attempt += 1;
      state.first_player_id = state.level_index % 2 === 0 ? state.host_id : state.guest_id;
      state.recordings = { a: null, b: null }; state.active_role = "a"; state.reactions = {};
      return ok(null);
    }, true);
  }
  collection(playerId: string): Outcome<RoomSnapshot[]> {
    const state = this.read();
    if (!state || !this.member(state, playerId)) return fail(404, "room_not_found");
    const saved = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM archive ORDER BY attempt DESC").toArray().map(row => JSON.parse(row.data) as RoomState).filter(item => item.active_role === "complete");
    if (state.active_role === "complete") saved.unshift(state);
    return ok(saved.map(item => this.view(item, playerId)));
  }
  react(playerId: string, revision: number, key: string, requestHash: string, reaction: "love" | "sparkles" | "again"): Promise<Outcome<RoomSnapshot>> {
    return this.change(playerId, revision, key, requestHash, state => {
      if (state.active_role !== "complete") return fail(409, "island_not_complete");
      state.reactions[playerId] = reaction; return ok(null);
    });
  }
  async eraseForPlayer(playerId: string, pendingCreation = false): Promise<Outcome<{ deleted: boolean }>> {
    return this.ctx.storage.transaction(async () => {
    const state = this.read();
    if (!state && pendingCreation) {
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO room VALUES (1,?)", JSON.stringify({ deleted: true }));
      return ok({ deleted: true });
    }
    if (!state) return fail(404, "room_not_found");
    if (!this.member(state, playerId)) return fail(404, "room_not_found");
    await this.eraseRoom();
    return ok({ deleted: true });
    });
  }
  /** Erases the whole room for both members; the caller owns the transaction and has checked membership. */
  private async eraseRoom(): Promise<void> {
    this.ctx.storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify({ deleted: true }));
    clearRoomInboxActivity(this.ctx.storage);
    this.ctx.storage.sql.exec("DELETE FROM archive"); this.ctx.storage.sql.exec("DELETE FROM operations");
    resetRedo(this.ctx.storage);
    clearDepartures(this.ctx.storage);
    clearTurnHints(this.ctx.storage); await scheduleNotifications(this.ctx.storage);
  }
  /**
   * A member leaves an island that is finished for them: their reaction is
   * erased from the live island and every archived one, and they stop being a
   * member, while the partner keeps the room and both players' turns. The last
   * member out erases the whole room. 404 means the caller is no longer a member.
   */
  async leaveFinished(playerId: string): Promise<Outcome<{ left: true }>> {
    return this.ctx.storage.transaction(async () => {
      const state = this.read();
      if (!state || !this.member(state, playerId)) return fail(404, "room_not_found");
      if (this.memberRoomState(playerId) !== "finished") return fail(409, "room_not_closed");
      const partner = playerId === state.host_id ? state.guest_id : state.host_id;
      if (partner === null || departed(this.ctx.storage, partner)) { await this.eraseRoom(); return ok({ left: true }); }
      if (Object.hasOwn(state.reactions, playerId)) { delete state.reactions[playerId]; state.revision += 1; this.write(state); }
      for (const row of this.ctx.storage.sql.exec<{ attempt: number; data: string }>("SELECT attempt,data FROM archive").toArray()) {
        const island = JSON.parse(row.data) as RoomState;
        if (!Object.hasOwn(island.reactions ?? {}, playerId)) continue;
        delete island.reactions[playerId];
        this.ctx.storage.sql.exec("UPDATE archive SET data=? WHERE attempt=?", JSON.stringify(island), row.attempt);
      }
      recordDeparture(this.ctx.storage, playerId);
      return ok({ left: true });
    });
  }
}
