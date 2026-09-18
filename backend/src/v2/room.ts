import { acknowledgePhoto, photoDelivery, clearDelivery } from "./photo-delivery";
import { DurableObject } from "cloudflare:workers";
import { interactionBlocked } from "../safety";
import { clearTurnHints, deliverTurnHints, initializeNotifications, queueTurnHint, scheduleNotifications, turnHintEligible } from "../notification-storage";
import type { NotificationEnvironment, TurnHint } from "../notifications";
import { ApiError, IDEMPOTENCY_PATTERN, canonicalJson, digest, equalHash, fail, integer, object, ok, text, type Outcome } from "../protocol";
import { RELAY_KEY, acceptedRecording, chapter, boundedValue, checkpointV2, exact, initialCheckpoint, recordingV2, type CheckpointV2, type RecordingV2, type Slot } from "./protocol";
import { sameChapter } from "./chapters";
import type { ChapterKey } from "./chapter-types";
import { initializeRoomV2Schema } from "./storage-schema";
import { exportRoomV2, restoreRoomV2 } from "./snapshot";
import { snapshotResult } from "../snapshot";
import { getPhoto, getPhotoOperation, mutatePhoto, parsePhotoMutation, PHOTO_TURN_PATTERN, type PhotoMutation } from "./photos";
import { clearPairReactions, getPairReactions, getReactionOperation, mutateReaction, parseReaction, type ReactionMutation } from "./reactions";

export type RoomStateV2 = {
  schema_version: 2; room_id: string; revision: number; branch: number; stage_index: number;
  level_id: string; level_version: number; definition_hash: string; host_id: string; guest_id: string | null;
  checkpoint: CheckpointV2; a_turn_id: string | null; completed_pair_ids: string[];
  invite_code: string; invite_expires_at: string; created_at: string; updated_at: string;
  simulation_version?: number;
};
export type RoomSnapshotV2 = Omit<RoomStateV2, "invite_code"> & {
  api_version: 2; invite_code?: string; active_role: "a" | "b" | "complete";
  first_player_id: string | null; active_player_id: string | null; player_slot: Slot;
  stage_id: string; recording_a: RecordingV2 | null; validation: "structural_client_replay_required";
};
export type ReceiptV2 = {
  schema_version: 2; room_id: string; idempotency_key: string; request_hash: string; operation: "turns" | "fork";
  accepted_revision: number; branch: number; stage_index: number; stage_id: string;
  turn_id: string | null; recording_hash: string | null; pair_id: string | null; checkpoint_hash: string;
};
export type MutationV2 = { receipt: ReceiptV2; room: RoomSnapshotV2 };
export type PairV2 = { pair_id: string; branch: number; stage_index: number; a: RecordingV2; b: RecordingV2; checkpoint: CheckpointV2 };
type StoredTurn = { data: string; player_id: string; accepted_revision: number };
const MAX_TURNS = 128, MAX_PAIRS = 64, MAX_BRANCHES = 32, MAX_OPERATIONS = 256;

/** A separate SQLite namespace. This coordinator does not execute game physics. */
export class RoomV2 extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      initializeRoomV2Schema(this.ctx.storage);
      initializeNotifications(this.ctx.storage, "RoomV2");
    });
  }
  // Binding-only maintenance methods; never exposed by the public router.
  exportSnapshot(sourceCommit: string): Promise<Outcome<string>> { return snapshotResult(() => exportRoomV2(this.ctx, sourceCommit)); }
  restoreSnapshot(archive: string, expectedLogicalId: string | null): Promise<Outcome<{ restored: true; checksum: string }>> { return snapshotResult(() => restoreRoomV2(this.ctx, archive, expectedLogicalId)); }
  alarm(): Promise<void> { return deliverTurnHints(this.ctx.storage, this.env, () => this.read()); }
  notificationEligible(player: string, hint: TurnHint): boolean { return turnHintEligible(this.ctx.storage, this.read(), player, hint); }
  private read(): RoomStateV2 | null {
    const raw = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").toArray()[0];
    if (!raw) return null;
    const value = JSON.parse(raw.data);
    return value.deleted ? null : value as RoomStateV2;
  }
  private member(state: RoomStateV2, player: string): boolean { return player === state.host_id || player === state.guest_id; }
  private unsupported(state: RoomStateV2): Outcome<never> | null {
    try { chapter(state); return null; } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  private turn(id: string): RecordingV2 {
    return JSON.parse(this.ctx.storage.sql.exec<StoredTurn>("SELECT data,player_id,accepted_revision FROM turns WHERE turn_id=?", id).one().data) as RecordingV2;
  }
  private pair(id: string): PairV2 { return JSON.parse(this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM pairs WHERE pair_id=?", id).one().data) as PairV2; }
  private view(state: RoomStateV2, player: string): RoomSnapshotV2 {
    const { invite_code, ...safe } = state;
    const stage = chapter(state).stages[state.stage_index];
    const first = !stage ? null : stage.first_player_slot === "p0" ? state.host_id : state.guest_id;
    const second = !stage ? null : stage.first_player_slot === "p0" ? state.guest_id : state.host_id;
    return { ...safe, ...(player === state.host_id ? { invite_code } : {}), api_version: 2,
      active_role: !stage ? "complete" : state.a_turn_id ? "b" : "a", first_player_id: first,
      active_player_id: !stage ? null : state.a_turn_id ? second : first,
      player_slot: player === state.host_id ? "p0" : "p1", stage_id: stage?.id ?? "",
      recording_a: state.a_turn_id ? this.turn(state.a_turn_id) : null, validation: "structural_client_replay_required" };
  }
  private write(state: RoomStateV2): void {
    state.updated_at = new Date().toISOString();
    this.ctx.storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify(state));
  }
  initialize(roomId: string, host: string, invite: string, requestedChapter: ChapterKey = RELAY_KEY, simulationVersion?: number): Outcome<RoomSnapshotV2> {
    let selected;
    try { selected = chapter(requestedChapter); } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
    if (simulationVersion !== undefined && (!Number.isInteger(simulationVersion) || simulationVersion === selected.simulation_version || !(selected.supported_simulation_versions ?? []).includes(simulationVersion))) return fail(422, "unsupported_simulation_version");
    const existing = this.read();
    if (existing && !sameChapter(existing, selected.key)) return fail(409, "idempotency_chapter_mismatch");
    if (existing && existing.simulation_version !== simulationVersion) return fail(409, "idempotency_simulation_mismatch");
    if (existing) return existing.host_id === host && equalHash(existing.invite_code, invite) ? ok(this.view(existing, host)) : fail(409, "room_exists");
    if (this.ctx.storage.sql.exec("SELECT id FROM room WHERE id=1").toArray().length) return fail(410, "room_deleted");
    const now = new Date().toISOString();
    const state: RoomStateV2 = { schema_version: 2, room_id: roomId, revision: 0, branch: 0, stage_index: 0,
      ...selected.key, ...(simulationVersion === undefined ? {} : { simulation_version: simulationVersion }), host_id: host, guest_id: null,
      checkpoint: selected.initial(), a_turn_id: null, completed_pair_ids: [], invite_code: invite,
      invite_expires_at: new Date(Date.now() + 7 * 86_400_000).toISOString(), created_at: now, updated_at: now };
    this.ctx.storage.sql.exec("INSERT INTO room VALUES (1,?)", JSON.stringify(state));
    return ok(this.view(state, host));
  }
  snapshot(player: string): Outcome<RoomSnapshotV2> {
    const state = this.read();
    if (!state || !this.member(state, player)) return fail(404, "room_not_found");
    return this.unsupported(state) ?? ok(this.view(state, player));
  }
  safetyMembers(player: string): Outcome<{ host_id: string; guest_id: string | null }> {
    const state = this.read(); if (!state || !this.member(state, player)) return fail(404, "room_not_found");
    return ok({ host_id: state.host_id, guest_id: state.guest_id });
  }
  async join(player: string, invite: string, supportedVersions?: number[]): Promise<Outcome<RoomSnapshotV2>> {
    const observed = this.read();
    if (observed && equalHash(observed.invite_code, invite) && player !== observed.host_id && await interactionBlocked(this.env, observed.host_id, player)) return fail(403, "player_blocked");
    return this.ctx.storage.transaction(async () => {
    const state = this.read();
    if (!state || !equalHash(state.invite_code, invite)) return fail(404, "invite_not_found");
    const unsupported = this.unsupported(state); if (unsupported) return unsupported;
    if (state.simulation_version !== undefined && !supportedVersions?.includes(state.simulation_version)) return fail(422, "unsupported_simulation_version");
    if (this.member(state, player)) return ok(this.view(state, player));
    if (Date.parse(state.invite_expires_at) < Date.now()) return fail(410, "invite_expired");
    if (state.guest_id) return fail(409, "room_full");
    state.guest_id = player; state.revision++; this.write(state);
    if (state.a_turn_id) queueTurnHint(this.ctx.storage, this.env as Env & NotificationEnvironment, "relay", state, state.host_id, player);
    await scheduleNotifications(this.ctx.storage);
    return ok(this.view(state, player));
    });
  }
  operation(player: string, key: string): Outcome<MutationV2> {
    const state = this.read();
    if (!state || !this.member(state, player)) return fail(404, "room_not_found");
    const unsupported = this.unsupported(state); if (unsupported) return unsupported;
    const row = this.ctx.storage.sql.exec<{ receipt: string }>("SELECT receipt FROM operations WHERE request_key=?", player + ":" + key).toArray()[0];
    return row ? ok({ receipt: JSON.parse(row.receipt) as ReceiptV2, room: this.view(state, player) }) : fail(404, "operation_not_found");
  }
  private retry(state: RoomStateV2, player: string, key: string, hash: string): Outcome<MutationV2> | null {
    const row = this.ctx.storage.sql.exec<{ request_hash: string; receipt: string }>("SELECT request_hash,receipt FROM operations WHERE request_key=?", player + ":" + key).toArray()[0];
    return !row ? null : equalHash(row.request_hash, hash) ? ok({ receipt: JSON.parse(row.receipt) as ReceiptV2, room: this.view(state, player) }) : fail(409, "idempotency_key_reused");
  }
  private saveReceipt(state: RoomStateV2, player: string, receipt: ReceiptV2): MutationV2 {
    this.write(state);
    this.ctx.storage.sql.exec("INSERT INTO operations VALUES (?,?,?)", player + ":" + receipt.idempotency_key, receipt.request_hash, JSON.stringify(receipt));
    return { receipt, room: this.view(state, player) };
  }
  private capacity(): boolean {
    return this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM operations").one().n < MAX_OPERATIONS;
  }
  async commit(player: string, value: unknown): Promise<Outcome<MutationV2>> {
    try {
      const input = object(value);
      const raw = object(input.recording);
      exact(input, ["base_revision", "idempotency_key", "branch", "recording", ...(raw.role === "b" ? ["checkpoint"] : [])]);
      const revision = integer(input.base_revision, 0, Number.MAX_SAFE_INTEGER), branch = integer(input.branch, 0, MAX_BRANCHES - 1);
      const key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
      boundedValue(input, 327_680);
      const observed = this.read();
      if (!observed || !this.member(observed, player)) return fail(404, "room_not_found");
      const recording = await recordingV2(raw, observed), hash = await digest(canonicalJson({ operation: "turns", ...input }));
      if (recording.simulation_version !== (observed.simulation_version ?? chapter(observed).simulation_version)) return fail(422, "unsupported_simulation_version");
      const retried = this.retry(observed, player, key, hash); if (retried) return retried;
      if (observed.revision !== revision || observed.branch !== branch) return fail(409, "stale_revision");
      let checkpoint: CheckpointV2 | null = null;
      if (recording.role === "b") {
        if (!observed.a_turn_id) return fail(409, "wrong_turn");
        checkpoint = await checkpointV2(input.checkpoint, observed.checkpoint, this.turn(observed.a_turn_id), recording);
      }
      // Hashing/validation may yield. Re-read every authority value in the same
      // transaction that persists turn/checkpoint/receipt and the delivery alarm.
      // Its only await is storage; no provider request participates in acceptance.
      if (await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
      return await this.ctx.storage.transaction(async () => {
        const state = this.read();
        if (!state || !this.member(state, player)) return fail(404, "room_not_found");
        const prior = this.retry(state, player, key, hash); if (prior) return prior;
        if (state.revision !== revision || state.branch !== branch) return fail(409, "stale_revision");
        if (recording.simulation_version !== (state.simulation_version ?? chapter(state).simulation_version)) return fail(422, "unsupported_simulation_version");
        const current = this.view(state, player);
        if (current.active_player_id !== player || current.active_role !== recording.role) return fail(409, "wrong_turn");
        if (recording.stage_id !== current.stage_id || recording.checkpoint_hash !== state.checkpoint.checkpoint_hash) return fail(409, "recording_context_mismatch");
        if (!this.capacity() || this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM turns").one().n >= MAX_TURNS) return fail(409, "room_history_full");
        if (recording.role === "a") {
          if (!acceptedRecording(recording)) return fail(422, "incomplete_first_turn");
        } else {
          const first = this.turn(state.a_turn_id!);
          if (recording.source_recording_hash !== first.recording_hash || recording.duration_ticks < first.duration_ticks) return fail(409, "source_recording_mismatch");
          if (!acceptedRecording(recording) || !checkpoint || checkpoint.previous_checkpoint_hash !== state.checkpoint.checkpoint_hash || checkpoint.a_recording_hash !== first.recording_hash) return fail(422, "incomplete_second_turn");
          if (this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM pairs").one().n >= MAX_PAIRS) return fail(409, "room_history_full");
        }
        const stage_index = state.stage_index, stage_id = current.stage_id, turn_id = `t${branch}-${stage_index}-${recording.role}`;
        const pair_id = recording.role === "b" ? `p${branch}-${stage_index}` : null;
        state.revision++;
        this.ctx.storage.sql.exec("INSERT INTO turns VALUES (?,?,?,?)", turn_id, player, state.revision, JSON.stringify(recording));
        if (recording.role === "a") state.a_turn_id = turn_id;
        else {
          const pair: PairV2 = { pair_id: pair_id!, branch, stage_index, a: this.turn(state.a_turn_id!), b: recording, checkpoint: checkpoint! };
          this.ctx.storage.sql.exec("INSERT INTO pairs VALUES (?,?)", pair_id, JSON.stringify(pair));
          state.completed_pair_ids.push(pair_id!); state.checkpoint = checkpoint!; state.stage_index++; state.a_turn_id = null;
        }
        const receipt: ReceiptV2 = { schema_version: 2, room_id: state.room_id, idempotency_key: key, request_hash: hash, operation: "turns",
          accepted_revision: state.revision, branch, stage_index, stage_id, turn_id, recording_hash: recording.recording_hash, pair_id, checkpoint_hash: state.checkpoint.checkpoint_hash };
        const saved = this.saveReceipt(state, player, receipt);
        queueTurnHint(this.ctx.storage, this.env as Env & NotificationEnvironment, "relay", state, player);
        await scheduleNotifications(this.ctx.storage);
        return ok(saved);
      });
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  async fork(player: string, value: unknown): Promise<Outcome<MutationV2>> {
    try {
      const input = object(value); exact(input, ["base_revision", "idempotency_key", "branch", "stage_index"]);
      const revision = integer(input.base_revision, 0, Number.MAX_SAFE_INTEGER), branch = integer(input.branch, 0, MAX_BRANCHES - 1);
      const observed = this.read();
      if (!observed || !this.member(observed, player)) return fail(404, "room_not_found");
      const stageIndex = integer(input.stage_index, 0, chapter(observed).stages.length - 1), key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
      const hash = await digest(canonicalJson({ operation: "fork", ...input }));
      if (await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
      return await this.ctx.storage.transaction(async () => {
        const state = this.read();
        if (!state || !this.member(state, player)) return fail(404, "room_not_found");
        const prior = this.retry(state, player, key, hash); if (prior) return prior;
        if (state.revision !== revision || state.branch !== branch) return fail(409, "stale_revision");
        if (stageIndex > state.stage_index || (stageIndex === state.stage_index && !state.a_turn_id)) return fail(409, "nothing_to_fork");
        if (!this.capacity() || state.branch + 1 >= MAX_BRANCHES) return fail(409, "room_history_full");
        state.checkpoint = stageIndex === 0 ? initialCheckpoint(state) : this.pair(state.completed_pair_ids[stageIndex - 1]).checkpoint;
        state.completed_pair_ids = state.completed_pair_ids.slice(0, stageIndex); state.a_turn_id = null;
        state.stage_index = stageIndex; state.branch++; state.revision++;
        const receipt: ReceiptV2 = { schema_version: 2, room_id: state.room_id, idempotency_key: key, request_hash: hash, operation: "fork",
          accepted_revision: state.revision, branch: state.branch, stage_index: stageIndex, stage_id: chapter(state).stages[stageIndex].id,
          turn_id: null, recording_hash: null, pair_id: null, checkpoint_hash: state.checkpoint.checkpoint_hash };
        const saved = this.saveReceipt(state, player, receipt);
        clearTurnHints(this.ctx.storage); await scheduleNotifications(this.ctx.storage);
        return ok(saved);
      });
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  collection(player: string): Outcome<{ pairs: { pair_id: string; branch: number; stage_index: number; a_hash: string; b_hash: string; checkpoint_hash: string }[]; active_pair_ids: string[] }> {
    const state = this.read();
    if (!state || !this.member(state, player)) return fail(404, "room_not_found");
    const pairs = this.ctx.storage.sql.exec<{ pair_id: string; branch: number; stage_index: number; a_hash: string; b_hash: string; checkpoint_hash: string }>(
      "SELECT pair_id,json_extract(data,'$.branch') AS branch,json_extract(data,'$.stage_index') AS stage_index,json_extract(data,'$.a.recording_hash') AS a_hash,json_extract(data,'$.b.recording_hash') AS b_hash,json_extract(data,'$.checkpoint.checkpoint_hash') AS checkpoint_hash FROM pairs ORDER BY rowid"
    ).toArray();
    return ok({ pairs, active_pair_ids: state.completed_pair_ids });
  }
  pairRecording(player: string, id: string): Outcome<PairV2> {
    const state = this.read();
    if (!state || !this.member(state, player)) return fail(404, "room_not_found");
    if (!this.ctx.storage.sql.exec("SELECT pair_id FROM pairs WHERE pair_id=?", id).toArray().length) return fail(404, "pair_not_found");
    return ok(this.pair(id));
  }
  reactions(player: string, pairId: string) { return getPairReactions(this.ctx.storage, this.read(), player, pairId); }
  reactionOperation(player: string, key: string) { return getReactionOperation(this.ctx.storage, this.read(), player, key); }
  async react(player: string, pairId: string, value: unknown): Promise<Outcome<ReactionMutation>> {
    try {
      const available = this.reactions(player, pairId); if (!available.ok) return available;
      const input = await parseReaction(pairId, value);
      const observed = this.read();
      if (observed && await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
      return this.ctx.storage.transactionSync(() => mutateReaction(this.ctx.storage, this.read(), player, input));
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); return fail(500, "reaction_storage_error"); }
  }
  photoDelivery(player: string, turn: string) { return photoDelivery(this.ctx.storage, this.read(), player, turn); }
  acknowledgePhoto(player: string, turn: string, value: unknown) {
    try { return this.ctx.storage.transactionSync(() => acknowledgePhoto(this.ctx.storage, this.read(), player, turn, value)); }
    catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  photo(player: string, turnId: string) { return getPhoto(this.ctx.storage, this.read(), player, turnId); }
  photoOperation(player: string, key: string) { return getPhotoOperation(this.ctx.storage, this.read(), player, key); }
  async updatePhoto(player: string, turnId: string, value: unknown, remove = false): Promise<Outcome<PhotoMutation>> {
    try {
      const observed = this.read();
      if (!observed || !this.member(observed, player)) return fail(404, "room_not_found");
      text(turnId, PHOTO_TURN_PATTERN, "invalid_photo_turn");
      const hash = text(object(value).recording_hash, /^[a-f0-9]{64}$/);
      const accepted = this.ctx.storage.sql.exec<{ player_id: string; data: string }>("SELECT player_id,data FROM turns WHERE turn_id=?", turnId).toArray()[0];
      if (!accepted || accepted.player_id !== player) return fail(404, "turn_not_found");
      if (JSON.parse(accepted.data).recording_hash !== hash) return fail(409, "photo_recording_mismatch");
      const input = await parsePhotoMutation(turnId, value, remove);
      if (!remove) {
        if (await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
        if (String(this.env.SAFETY_ENFORCEMENT_ENABLED) === "true" && !(await this.env.SAFETY_PROFILES.getByName(player).terms(player)).accepted) return fail(403, "terms_acceptance_required");
      }
      return this.ctx.storage.transactionSync(() => mutatePhoto(this.ctx.storage, this.read(), player, input));
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); return fail(500, "photo_storage_error"); }
  }
  async eraseForPlayer(player: string, pendingCreation = false): Promise<Outcome<{ deleted: boolean }>> {
    return this.ctx.storage.transaction(async () => {
    const state = this.read();
    if (!state && pendingCreation) {
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO room VALUES (1,?)", '{"deleted":true}'); return ok({ deleted: true });
    }
    if (!state || !this.member(state, player)) return fail(404, "room_not_found");
      this.ctx.storage.sql.exec("UPDATE room SET data=? WHERE id=1", '{"deleted":true}');
      this.ctx.storage.sql.exec("DELETE FROM turns"); this.ctx.storage.sql.exec("DELETE FROM pairs"); this.ctx.storage.sql.exec("DELETE FROM operations");
      this.ctx.storage.sql.exec("DELETE FROM photos"); this.ctx.storage.sql.exec("DELETE FROM photo_operations"); clearDelivery(this.ctx.storage);
      clearPairReactions(this.ctx.storage);
      clearTurnHints(this.ctx.storage); await scheduleNotifications(this.ctx.storage);
    return ok({ deleted: true });
    });
  }
}
