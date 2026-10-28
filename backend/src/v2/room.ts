import { acknowledgePhoto, photoDelivery, clearDelivery } from "./photo-delivery";
import { flags } from "../flags";
import { DurableObject } from "cloudflare:workers";
import { interactionBlocked } from "../safety";
import { friendRoomInvite } from "../friends";
import { clearTurnHints, deliverTurnHints, initializeNotifications, queueRedoHint, queueTurnHint, redoHintCurrent, scheduleGameplayNotifications, scheduleNotifications, turnHintEligible } from "../notification-storage";
import type { RoomHint } from "../notifications";
import { ApiError, IDEMPOTENCY_PATTERN, canonicalJson, digest, equalHash, fail, integer, object, ok, text, type Outcome } from "../protocol";
import { RELAY_KEY, acceptedRecording, chapter, boundedTurnValue, checkpointV2, exact, initialCheckpoint, recordingV2, type CheckpointV2, type RecordingV2, type Slot } from "./protocol";
import { sameChapter } from "./chapters";
import { checkpointAt } from "./checkpoint-chain";
import { isStub } from "./history-blob";
import { clearHistory, noteHistorySupport, storedAttempts, type AttemptRecord, type HistorySupport } from "./history";
import { v1Transferred, offloadedCount, stubReleased, acknowledgeAttempt, archived, attemptDownload, checkedUpload, historyView, loadChain, parseAck, parseWant, restoreAttempt, wantAttempt, type HistoryRoom, type HistoryView } from "./history-room";
import type { ChapterKey } from "./chapter-types";
import { initializeRoomV2Schema } from "./storage-schema";
import { clearTurnTries, parseTries, recordTries, triesField, turnTriesView, type TurnTriesView } from "./turn-tries";
import { clearEndReactions, endReactionField, endReactionsList, endReactionsView, eraseEndReactionsOf, parseEndReaction, recordEndReaction, type EndReactionsList, type EndReactionsView } from "./end-reactions";
import { clearRunReactions, eraseRunReactionsOf, parseRunReactions, partnerTrack, recordRunReactions, runReactionField, runReactionsView, withinTurn, type RunReactionsView } from "./run-reactions";
import { HardMemo, clearHard, failuresView, initializeHard, parseReset, priorReset, recordFailure, type Failure, type HardFailures, type HardRun, type Slip } from "./hard-mode";
import { exportRoomV2, restoreRoomV2 } from "./snapshot";
import { snapshotResult } from "../snapshot";
import { erasePlayerPhotos, getPhoto, getPhotoOperation, mutatePhoto, parsePhotoMutation, PHOTO_TURN_PATTERN, type PhotoMutation } from "./photos";
import { clearPairReactions, erasePlayerReactions, getPairReactions, getReactionOperation, mutateReaction, parseReaction, type ReactionMutation } from "./reactions";
import { campaignBoundaryGuard, campaignSource } from "./campaign-source";
import { campaignRoomAuthority, campaignRoomNegotiation, prepareCampaignHttpAccess, campaignHttpAccessGuard, type CampaignRoomContext } from "./campaign-room-access";
import { initializeCampaignTarget, activateCampaignTarget } from "./campaign-target";
import { readCampaignControl, readCampaignOperation } from "./campaign-control";
import { initializeCampaignRoot, joinCampaignRoot, cancelCampaignJoinRoot } from "./campaign-root";
import { eraseCampaignChildWithDefinition, eraseCampaignRoot, readCampaignRootTerminal } from "./campaign-deletion";
import { absentCensus, campaignRoomCensus } from "./campaign-drain";
import { campaignBindingRead, campaignBindingInitialize, campaignBindingInvite, campaignBindingJoin, campaignBindingCancelJoin, campaignBindingSource, campaignBindingTarget, campaignBindingAdvance, campaignBindingRedo, campaignHostAccess } from "./campaign-bindings";
import { campaignRedoAccess, campaignRedoFork, campaignRedoInput, campaignRedoMutations, campaignRedoReceipt, sameRedoValue, type CampaignRedoAccept, type CampaignRedoBinding, type CampaignRedoEnvelope, type CampaignRedoMode } from "./campaign-redo";
import { acceptedRedo, consentToRedo, initializeRedo, mutateRedo, parseRedoMutation, redoState, resetRedo, type RedoSource, type RedoState } from "../redo-control";
import { campaignProductionEnabled } from "./campaign-production";
import { acknowledgeReplay, captureReplay, checkedRestore, clearReplayTransfer, factsForArchive, matchingTransfer, parseTransferKey, prepareReplayTransfer, readReplayTransfer, restoreReplay, transferredRoom, type ReplayArchive, type ReplayTransfer, type TransferredRoom } from "./replay-transfer";
import { clearRoomInboxActivity, initializeRoomInboxActivity, recordRemoteRoomActivity } from "../room-inbox-storage";
import { relayInboxProjection } from "../room-inbox";
import { memberStateOf, type MemberRoomState } from "../room-leave";
import { anyDeparture, clearDepartures, departed, isMember, recordDeparture } from "../room-departure";
import { HostAccessMemo } from "./host-access";
import { answerWhileBlank, openLazyStorage } from "../lazy-storage";
import { UnblockedPairMemo } from "./block-memo";
import { observeRoom, pushRoomIndex } from "../room-index-sync";
import { announceRoomChange, liveRecipient, liveRoomHint, type LiveHint, type LiveRoomMembers } from "../live";
import { clearMemberNames, eraseMemberName, memberName, recordMemberName } from "../display-names";
import { clearPollenRoom, completionFacts, recordMember, recordTurnFacts, turnFacts, type PollenMember, type TurnFacts } from "../pollen/turn-facts";
import { clearLooks, eraseMemberLook, eraseTurnLooksOf, memberLook, recordMemberLook, recordTurnLook, turnLooks } from "../pollen/room-looks";
import type { Look } from "../pollen/catalog";
import { CHAPTER_NOT_OPEN, chapterOpen } from "./chapter-unlocks";

export type RoomStateV2 = {
  schema_version: 2; room_id: string; revision: number; branch: number; stage_index: number;
  level_id: string; level_version: number; definition_hash: string; host_id: string; guest_id: string | null;
  checkpoint: CheckpointV2; a_turn_id: string | null; completed_pair_ids: string[];
  invite_code: string; invite_expires_at: string; created_at: string; updated_at: string;
  simulation_version?: number;
};
export type RoomSnapshotV2 = Omit<RoomStateV2, "invite_code"> & {
  api_version: 2; invite_code?: string; hard?: HardRun; active_role: "a" | "b" | "complete";
  first_player_id: string | null; active_player_id: string | null; player_slot: Slot;
  stage_id: string; recording_a: RecordingV2 | null; validation: "structural_client_replay_required";
  /** Only beside a read for a member that asked for end reactions while they are on (end-reactions.ts). */
  end_reactions?: EndReactionsView;
  /** Only beside a full read for a member that asked for names while they are on (display-names.ts): the other member's name or null. */
  partner_name?: string | null;
  /** Only beside a read for a member that asked for run reactions while they are on (run-reactions.ts): the track of the partner's latest turn, when it has one. */
  run_reactions?: RunReactionsView;
  /** Only beside a read for a member that asked for looks while they are on (pollen/room-looks.ts): the partner's look and the looks of their turns. */
  partner_look?: Look;
  turn_looks?: Record<string, Look>;
};
export type RoomLobbyV2 = RoomSnapshotV2 | (Omit<TransferredRoom, "invite_code"> & {
  api_version: 2; active_role: "complete";
});
export type ReceiptV2 = {
  schema_version: 2; room_id: string; idempotency_key: string; request_hash: string; operation: "turns" | "fork";
  accepted_revision: number; branch: number; stage_index: number; stage_id: string;
  turn_id: string | null; recording_hash: string | null; pair_id: string | null; checkpoint_hash: string;
};
/** `end_reactions` only for a standalone member that asked for them while they are on (end-reactions.ts). */
/** `partner_name` likewise for display names (display-names.ts), and `run_reactions` for run reactions (run-reactions.ts). */
export type MutationV2 = { receipt: ReceiptV2; room: RoomSnapshotV2 } & BesideFields;
/** A standalone turn committed with a PollenMember also returns its frozen facts; the Worker takes them out before replying (pollen/routes.ts). */
export type CommittedV2 = MutationV2 & { pollen_facts?: TurnFacts };
/**
 * What a standalone member's read or turn reply carries beside the room, each
 * only when the member asked for it while it is on: the room's end reactions
 * (`faces`), the partner's name (`names`) and the run reactions on the partner's latest turn (`tracks`).
 */
export type Beside = { faces?: boolean; names?: boolean; tracks?: boolean; looks?: boolean };
type BesideFields = { end_reactions?: EndReactionsView; partner_name?: string | null; run_reactions?: RunReactionsView; partner_look?: Look; turn_looks?: Record<string, Look> };
/** The revision and branch a polling member already holds (X-AfterYou-Known-Room). */
export type KnownRoom = { revision: number; branch: number };
/** The small poll reply when nothing changed since the member's known revision and branch. */
export type RoomUnchangedV2 = { schema_version: 1; unchanged: true; revision: number; branch: number; updated_at: string };
/** A conditional poll's reply; `redo` only for a client that asked for it (X-AfterYou-Poll-Redo). */
export type PolledRoomV2 = (RoomSnapshotV2 | RoomUnchangedV2) & { redo?: RedoState };
export type PairV2 = { pair_id: string; branch: number; stage_index: number; a: RecordingV2; b: RecordingV2; checkpoint: CheckpointV2 };
type StoredTurn = { data: string; player_id: string; accepted_revision: number };
const MAX_TURNS = 128, MAX_PAIRS = 64, MAX_BRANCHES = 32, MAX_OPERATIONS = 256;

/** A separate SQLite namespace. This coordinator does not execute game physics. */
export class RoomV2 extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => openLazyStorage(this, this.ctx.storage, "room", () => {
      initializeRoomV2Schema(this.ctx.storage);
      initializeNotifications(this.ctx.storage, "RoomV2");
      initializeRedo(this.ctx.storage);
      initializeRoomInboxActivity(this.ctx.storage);
    }));
  }
  // Binding-only maintenance methods; never exposed by the public router.
  exportSnapshot(sourceCommit: string): Promise<Outcome<string>> { return snapshotResult(() => exportRoomV2(this.ctx, sourceCommit)); }
  async restoreSnapshot(archive: string, expectedLogicalId: string | null): Promise<Outcome<{ restored: true; checksum: string }>> {
    this.hard.forget();
    try { return await snapshotResult(() => restoreRoomV2(this.ctx, archive, expectedLogicalId)); }
    finally { this.hard.forget(); }
  }
  /** Whether this object holds a hard room (v2/hard-mode.ts); read at most once per object. */
  private readonly hard = new HardMemo();
  observeCampaignSource(value: unknown) { return campaignSource(this.ctx.storage, value, false); }
  campaignTerminalFact(rootId: string) { return readCampaignRootTerminal(this.ctx.storage, rootId); }
  /** Read-only operator Story drain census (campaign-drain.ts). */
  campaignDrainCensus(roomId: string) { return campaignRoomCensus(this.ctx.storage, roomId); }
  campaignHttpRead(owner: string, context: unknown, operation?: string) { return campaignBindingRead(this.ctx.storage, this.env, owner, context, operation); }
  campaignHttpSettlement(owner: string, context: unknown) { return campaignBindingRead(this.ctx.storage, this.env, owner, context, undefined, true); }
  campaignHttpInitialize(owner: string, value: unknown, context: unknown, retainedDefinition?: unknown) { return campaignBindingInitialize(this.ctx.storage, this.env, owner, value, context, retainedDefinition); }
  campaignHttpInvite(owner: string, value: unknown, context: unknown) { return campaignBindingInvite(this.ctx.storage, this.env, owner, value, context); }
  campaignHttpJoin(owner: string, value: unknown, context: unknown) { return campaignBindingJoin(this.ctx.storage, this.env, owner, value, context); }
  campaignHttpCancelJoin(owner: string, value: unknown, context: unknown) { return campaignBindingCancelJoin(this.ctx.storage, this.env, owner, value, context); }
  campaignBoundSource(value: unknown, seal: boolean, definition: unknown) { return campaignBindingSource(this.ctx.storage, value, seal, definition); }
  campaignBoundTarget(value: unknown, activate: boolean, definition: unknown) { return campaignBindingTarget(this.ctx.storage, value, activate, definition); }
  campaignHttpAdvance(owner: string, value: unknown, context: unknown, resume: boolean) { return campaignBindingAdvance(this.ctx.storage, this.env, owner, value, context, resume); }
  campaignHttpRedo(owner: string, context: unknown, index: number, mode: CampaignRedoMode, value?: unknown): Promise<Outcome<CampaignRedoEnvelope>> {
    return campaignBindingRedo(this.ctx.storage, this.env, owner, context, index, mode, value,
      (binding, childContext) => this.campaignBoundRedo(owner, binding, mode, value, childContext));
  }
  async campaignBoundRedo(owner: string, binding: CampaignRedoBinding, mode: CampaignRedoMode, value: unknown, context: CampaignRoomContext): Promise<Outcome<CampaignRedoEnvelope>> {
    try {
      if (mode === "read" || mode === "mutate") {
        const result = await this.redoInternal(owner, mode === "read" ? undefined : value, context.device_hash, context, binding);
        return result.ok ? ok({ schema_version: 1, binding, redo: result.value }) : result;
      }
      if (mode === "accept") {
        const input = await campaignRedoInput(value, binding, true);
        const result = await this.forkInternal(owner, campaignRedoFork(input), context, context.device_hash, input);
        return result.ok ? ok({ schema_version: 1, binding, receipt: campaignRedoReceipt(result.value.receipt, binding, input.idempotency_key) }) : result;
      }
      if (mode !== "operation") return fail(422, "invalid_redo_request");
      const key = text(value, IDEMPOTENCY_PATTERN), access = await prepareCampaignHttpAccess(this.ctx.storage, this.env, owner, context);
      campaignRedoAccess(access, binding);
      const result = await this.operation(owner, key, context);
      return result.ok ? ok({ schema_version: 1, binding, receipt: campaignRedoReceipt(result.value.receipt, binding, key) }) : result;
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  sealCampaignSource(value: unknown) { return campaignSource(this.ctx.storage, value, true); }
  initializeCampaignTarget(value: unknown) { return initializeCampaignTarget(this.ctx.storage, value); }
  activateCampaignTarget(value: unknown) { return activateCampaignTarget(this.ctx.storage, value); }
  campaignControl(player: string) { return readCampaignControl(this.ctx.storage, player); }
  campaignOperation(player: string, key: string) { return readCampaignOperation(this.ctx.storage, player, key); }
  initializeCampaignRoot(value: unknown) { return initializeCampaignRoot(this.ctx.storage, value); }
  joinCampaignRoot(player: string, value: unknown) { return joinCampaignRoot(this.ctx.storage, player, value); }
  cancelCampaignJoinRoot(player: string, value: unknown) { return cancelCampaignJoinRoot(this.ctx.storage, player, value); }
  eraseCampaignChild(value: unknown, definition: unknown) { return eraseCampaignChildWithDefinition(this.ctx.storage, value, definition); }
  eraseCampaignRoot(player: string, roomId: string, allocation: unknown) { return eraseCampaignRoot(this.ctx.storage, player, roomId, allocation, {
    erase: (request, definition) => this.env.ROOMS_V2.getByName(request.binding.room_id).eraseCampaignChild(request, definition)
  }); }
  campaignRoomAuthority(player: string, room: string) { return campaignRoomAuthority(this.ctx.storage, player, room); }
  campaignRoomNegotiation(supported: boolean) { return campaignRoomNegotiation(this.ctx.storage, supported === true); }
  private readonly unblocked = new UnblockedPairMemo();
  /**
   * The router's check before a room request: membership as safetyMembers answers it, then blocks.
   * With the requester's safety token the pair's "not blocked" is remembered until a block changes a token.
   */
  async interactionAllowed(player: string, context?: CampaignRoomContext, safetyToken?: string): Promise<Outcome<true>> {
    const members = await this.safetyMembers(player, context); if (!members.ok) return members;
    const { host_id: host, guest_id: guest } = members.value, check = () => interactionBlocked(this.env, host, guest);
    const blocked = safetyToken === undefined ? await check() : await this.unblocked.blocked(player, safetyToken, host, guest, check);
    return blocked ? fail(403, "player_blocked") : ok(true);
  }
  // Premium turn admission memo; the policy lives in v2/host-access.ts.
  private readonly hostAccess = new HostAccessMemo();
  hostAccessAge(host: string): number | null { return this.hostAccess.age(host); }
  rememberHostAccess(host: string, verified: boolean): void { this.hostAccess.remember(host, verified); }
  private async project<T>(player: string, context: CampaignRoomContext | undefined, read: () => Outcome<T>): Promise<Outcome<T>> {
    try {
      const access = await prepareCampaignHttpAccess(this.ctx.storage, this.env, player, context);
      return campaignHttpAccessGuard(this.ctx.storage, access) ?? read();
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  // Campaign notification orchestration is not enabled by the control2 foundation.
  private notificationsAvailable(): boolean { return campaignBoundaryGuard(this.ctx.storage, "campaign_notifications_unavailable") === null; }
  /** The live hint a change makes (live.ts), or null: the flag is off, or a Story room, which sends none. */
  private liveHintFrom(room: LiveRoomMembers): LiveHint | null {
    return flags.liveConnection(this.env) && this.notificationsAvailable() ? liveRoomHint(room) : null;
  }
  /** After a committed change indexed() does not cover (a join, a redo request): one live hint to the other member. */
  private announce(actor: string, room?: LiveRoomMembers | null): void {
    if (!flags.liveConnection(this.env)) return;
    const members = room === undefined ? this.read() : room;
    if (members && this.notificationsAvailable()) announceRoomChange(this.env, promise => this.ctx.waitUntil(promise), members, actor);
  }
  alarm(): Promise<void> {
    if (!this.notificationsAvailable()) return Promise.resolve();
    return deliverTurnHints(this.ctx.storage, this.env, () => this.notificationsAvailable() ? this.read() : null, () => this.notificationsAvailable());
  }
  notificationEligible(player: string, hint: RoomHint): boolean {
    const state = this.notificationsAvailable() ? this.read() : null;
    if (!state || !turnHintEligible(this.ctx.storage, state, player, hint)) return false;
    if (hint.kind !== "redo_requested") return true;
    try { return redoHintCurrent(this.ctx.storage, this.redoSource(state), player, hint); } catch { return false; }
  }
  inboxProjection(player: string) { return this.projection(player); }
  /** Binding only: the member's inbox projection with this room's clock, for their room index. */
  indexEntry(player: string) { return observeRoom(() => this.projection(player)); }
  /** A member's inbox projection; it carries the partner's name only while display names are on. */
  private projection(player: string) { return relayInboxProjection(this.ctx.storage, player, flags.displayNames(this.env)); }
  /**
   * After a committed change, sends each member's projection to their room
   * index (room-index-sync.ts), but only when the room is now settled for its
   * members (finished, replay-transferred) or `reopened` says it may have been
   * before (a fork). The index reads rooms in play live, so ordinary turns
   * need no push. While the index is off it reads nothing.
   *
   * With `actor`, the member who did not act also gets one live hint
   * (live.ts): on the index push when there is one, else on its own call.
   */
  private indexed<T>(outcome: Outcome<T>, reopened = false, actor?: string): Outcome<T> {
    const live = actor !== undefined && flags.liveConnection(this.env);
    if (!outcome.ok || (!flags.roomIndex(this.env) && !live)) return outcome;
    const state = this.stored();
    if (!state) return outcome;
    const partner = actor === undefined ? null : liveRecipient(state, actor);
    const hint = live && partner ? this.liveHintFrom(state) : null;
    const project = (player: string) => this.projection(player);
    if (flags.roomIndex(this.env) && (reopened || memberStateOf(project(state.host_id)) !== "in_play")) {
      pushRoomIndex(this.ctx, this.env, state.room_id, 2, [state.host_id, state.guest_id], project, hint && partner ? { to: partner, hint } : undefined);
    } else if (hint) announceRoomChange(this.env, promise => this.ctx.waitUntil(promise), state, actor!);
    return outcome;
  }
  /** Whether this member's chapter has a stage left (or waits for a friend), is finished (archived replays too), or is gone. */
  memberRoomState(player: string): MemberRoomState { return memberStateOf(relayInboxProjection(this.ctx.storage, player)); }
  resolvesInvitation(inviteCode: string): boolean {
    return this.ctx.storage.sql.exec("SELECT 1 AS found FROM room WHERE id=1 AND (json_extract(data,'$.invite_code')=? OR json_extract(data,'$.deleted') IS 1 OR json_extract(data,'$.replay_transfer_version') IN (1,2))", inviteCode).toArray().length > 0;
  }
  /** Stage count of this room's chapter (2 when absent or unknown); used only to keep stage-digit errors unchanged. */
  stageCount(): number { const state = this.stored(); if (!state) return 2; try { return chapter(state).stages.length; } catch { return 2; } }
  private read(): RoomStateV2 | null {
    const raw = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM room WHERE id=1").toArray()[0];
    if (!raw) return null;
    const value = JSON.parse(raw.data);
    return value.deleted || value.replay_transfer_version === 1 || value.replay_transfer_version === 2 ? null : value as RoomStateV2;
  }
  private member(state: Pick<RoomStateV2, "host_id" | "guest_id">, player: string): boolean { return isMember(this.ctx.storage, state, player); }
  /** The live room or its replay-transfer record, for anyone; not a membership check. */
  private stored(): RoomStateV2 | TransferredRoom | null { return this.read() ?? transferredRoom(this.ctx.storage); }
  /** The stored room as `player` may see it: null unless they are a member (room-departure.ts isMember). */
  private memberView(player: string): RoomStateV2 | TransferredRoom | null {
    const state = this.stored();
    return state && this.member(state, player) ? state : null;
  }
  private unavailable(player: string): Outcome<never> {
    const archived = transferredRoom(this.ctx.storage);
    return archived && this.member(archived, player) ? fail(410, "replay_transferred") : fail(404, "room_not_found");
  }
  private redoSource(state: RoomStateV2): RedoSource | null {
    const stage = chapter(state).stages[state.stage_index];
    if (!state.guest_id || !state.a_turn_id || !stage) return null;
    return { room_id: state.room_id, revision: state.revision, branch: state.branch, stage_index: state.stage_index,
      a_hash: this.turn(state.a_turn_id).recording_hash,
      first_player_id: stage.first_player_slot === "p0" ? state.host_id : state.guest_id,
      second_player_id: stage.first_player_slot === "p0" ? state.guest_id : state.host_id };
  }
  redo(player: string, value?: unknown, deviceHash?: string): Promise<Outcome<RedoState>> { return this.redoInternal(player, value, deviceHash); }
  private async redoInternal(player: string, value?: unknown, deviceHash?: string, context?: CampaignRoomContext, binding?: CampaignRedoBinding): Promise<Outcome<RedoState>> {
    try {
      if (!binding) { const boundary = campaignBoundaryGuard(this.ctx.storage, "campaign_redo_unavailable"); if (boundary) return boundary; }
      const observed = this.read();
      if (!observed || !this.member(observed, player)) return this.unavailable(player);
      if (await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
      const input = value === undefined ? null : binding ? await campaignRedoInput(value, binding, false) : await parseRedoMutation(value);
      const access = binding ? await prepareCampaignHttpAccess(this.ctx.storage, this.env, player, context) : null;
      if (deviceHash !== undefined && !await this.env.PLAYERS.getByName(player).authorize(deviceHash)) return fail(401, "invalid_auth");
      const outcome = await this.ctx.storage.transaction(async () => {
        if (!binding) { const boundary = campaignBoundaryGuard(this.ctx.storage, "campaign_redo_unavailable"); if (boundary) return boundary; }
        else {
          const guard = campaignHttpAccessGuard(this.ctx.storage, access, input !== null); if (guard) return guard;
          campaignRedoAccess(access, binding, input !== null);
          if (input) campaignRedoMutations(this.env);
        }
        const state = this.read();
        if (!state || !this.member(state, player)) return this.unavailable(player);
        const source = this.redoSource(state);
        if (!input) return ok(redoState(this.ctx.storage, source));
        if (this.hard.run(this.ctx.storage)) return fail(409, "hard_run_no_redo");
        // Only a first request on a standalone room reaches the partner; Story rooms stay excluded.
        const first = !binding && input.action === "request" && source !== null && redoState(this.ctx.storage, source).request === null;
        const result = mutateRedo(this.ctx.storage, source, player, input);
        if (first && result.ok && result.value.request?.status === "pending" && this.notificationsAvailable() &&
          queueRedoHint(this.ctx.storage, this.env, "relay", state, source.first_player_id, result.value.request.request_id)) await scheduleGameplayNotifications(this.ctx.storage);
        return result;
      });
      if (input && !binding && outcome.ok) this.announce(player);
      return outcome;
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  private unsupported(state: RoomStateV2): Outcome<never> | null {
    try { chapter(state); return null; } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  private turn(id: string): RecordingV2 {
    return JSON.parse(this.ctx.storage.sql.exec<StoredTurn>("SELECT data,player_id,accepted_revision FROM turns WHERE turn_id=?", id).one().data) as RecordingV2;
  }
  private view(state: RoomStateV2, player: string): RoomSnapshotV2 {
    const { invite_code, ...safe } = state;
    const stage = chapter(state).stages[state.stage_index];
    const first = !stage ? null : stage.first_player_slot === "p0" ? state.host_id : state.guest_id;
    const second = !stage ? null : stage.first_player_slot === "p0" ? state.guest_id : state.host_id;
    const hard = this.hard.run(this.ctx.storage);
    return { ...safe, ...(player === state.host_id ? { invite_code } : {}), ...(hard ? { hard } : {}), api_version: 2,
      active_role: !stage ? "complete" : state.a_turn_id ? "b" : "a", first_player_id: first,
      active_player_id: !stage ? null : state.a_turn_id ? second : first,
      player_slot: player === state.host_id ? "p0" : "p1", stage_id: stage?.id ?? "",
      recording_a: state.a_turn_id ? this.turn(state.a_turn_id) : null, validation: "structural_client_replay_required" };
  }
  private partnerOf(state: { host_id: string; guest_id: string | null }, player: string): string | null {
    return player === state.host_id ? state.guest_id : state.host_id;
  }
  /** A room view with what the member asked for beside it (Beside). */
  private withBeside(view: RoomSnapshotV2, state: RoomStateV2, player: string, wanted: Beside): RoomSnapshotV2 {
    return wanted.faces || wanted.names || wanted.tracks || wanted.looks ? { ...view, ...this.beside(state, player, wanted) } : view;
  }
  /** The optional fields a room read or a turn reply carries beside the room. */
  private beside(state: { host_id: string; guest_id: string | null }, player: string, wanted: Beside): BesideFields {
    const partner = this.partnerOf(state, player);
    return { ...(wanted.faces ? { end_reactions: endReactionsView(this.ctx.storage, partner) } : {}), ...(wanted.names ? { partner_name: memberName(this.ctx.storage, partner) } : {}),
      ...(wanted.tracks ? { run_reactions: partnerTrack(this.ctx.storage, partner) } : {}),
      ...(wanted.looks ? { partner_look: memberLook(this.ctx.storage, partner), turn_looks: turnLooks(this.ctx.storage, partner) } : {}) };
  }
  private write(state: RoomStateV2): void {
    state.updated_at = new Date().toISOString();
    this.ctx.storage.sql.exec("UPDATE room SET data=? WHERE id=1", JSON.stringify(state));
  }
  /**
   * `name`: the host's display name while names are on (display-names.ts recordMemberName); undefined writes nothing.
   * `pollen`: the host's Full Journey end while Pollen earning is on (pollen/turn-facts.ts recordMember); undefined writes nothing.
   * `look`: the host's look while looks are on (pollen/room-looks.ts recordMemberLook); undefined writes nothing.
   */
  initialize(roomId: string, host: string, invite: string, requestedChapter: ChapterKey = RELAY_KEY, simulationVersion?: number, mode?: "hard", name?: string | null, pollen?: PollenMember, look?: Look): Outcome<RoomSnapshotV2> {
    const boundary = campaignBoundaryGuard(this.ctx.storage, "campaign_initialize_required"); if (boundary) return boundary;
    let selected;
    try { selected = chapter(requestedChapter); } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
    if (simulationVersion !== undefined && (!Number.isInteger(simulationVersion) || simulationVersion === selected.simulation_version || !(selected.supported_simulation_versions ?? []).includes(simulationVersion))) return fail(422, "unsupported_simulation_version");
    const existing = this.read();
    if (existing && !sameChapter(existing, selected.key)) return fail(409, "idempotency_chapter_mismatch");
    if (existing && existing.simulation_version !== simulationVersion) return fail(409, "idempotency_simulation_mismatch");
    if (existing && (this.hard.run(this.ctx.storage) !== null) !== (mode === "hard")) return fail(409, "idempotency_mode_mismatch");
    if (existing && (existing.host_id !== host || !equalHash(existing.invite_code, invite))) return fail(409, "room_exists");
    // A host who left reads the room as gone, even through their own create retry.
    if (existing) return this.member(existing, host) ? ok(this.view(existing, host)) : fail(410, "room_deleted");
    const archived = transferredRoom(this.ctx.storage);
    if (archived && archived.host_id === host && equalHash(archived.invite_code, invite)) return this.unavailable(host);
    if (this.ctx.storage.sql.exec("SELECT id FROM room WHERE id=1").toArray().length) return fail(410, "room_deleted");
    const now = new Date().toISOString();
    const state: RoomStateV2 = { schema_version: 2, room_id: roomId, revision: 0, branch: 0, stage_index: 0,
      ...selected.key, ...(simulationVersion === undefined ? {} : { simulation_version: simulationVersion }), host_id: host, guest_id: null,
      checkpoint: selected.initial(), a_turn_id: null, completed_pair_ids: [], invite_code: invite,
      invite_expires_at: new Date(Date.now() + 7 * 86_400_000).toISOString(), created_at: now, updated_at: now };
    this.ctx.storage.transactionSync(() => {
      this.ctx.storage.sql.exec("INSERT INTO room VALUES (1,?)", JSON.stringify(state));
      if (mode === "hard") initializeHard(this.ctx.storage, this.hard);
      recordMemberName(this.ctx.storage, host, name);
      recordMember(this.ctx.storage, host, pollen);
      recordMemberLook(this.ctx.storage, host, look);
    });
    return ok(this.view(state, host));
  }
  /** `history` is what the member's request said about keeping attempts (the router passes it only while offload is on). */
  /** `beside`: what a standalone member read asked for beside the room (Beside); a Story read gets none. */
  snapshot(player: string, context?: CampaignRoomContext, history?: HistorySupport, beside: Beside = {}): Promise<Outcome<RoomSnapshotV2>> {
    return this.project(player, context, () => {
      const state = this.polledState(player, context, history);
      return state.ok ? ok(this.withBeside(this.view(state.value, player), state.value, player, context === undefined ? beside : {})) : state;
    });
  }
  /**
   * A standalone room poll from a member that already holds `known`. Every check
   * runs exactly as in `snapshot`, history support is still noted, and only then
   * an unchanged room answers with a small reply instead of the full view.
   * With `withRedo`, either reply ends with `redo`: the same state GET /redo reads.
   */
  snapshotIfChanged(player: string, known: KnownRoom, history?: HistorySupport, withRedo = false, beside: Beside = {}): Promise<Outcome<PolledRoomV2>> {
    return this.project<PolledRoomV2>(player, undefined, () => {
      const state = this.polledState(player, undefined, history);
      if (!state.ok) return state;
      // Faces and tracks only move with a turn, which moves the revision, so the small reply never needs them; names are left out of it too.
      const reply: RoomSnapshotV2 | RoomUnchangedV2 = state.value.revision === known.revision && state.value.branch === known.branch
        ? { schema_version: 1, unchanged: true, revision: state.value.revision, branch: state.value.branch, updated_at: state.value.updated_at }
        : this.withBeside(this.view(state.value, player), state.value, player, beside);
      return ok(withRedo ? { ...reply, redo: redoState(this.ctx.storage, this.redoSource(state.value)) } : reply);
    });
  }
  /** The checks every member poll shares; a standalone poll also notes the member's history support. */
  private polledState(player: string, context: CampaignRoomContext | undefined, history: HistorySupport | undefined): Outcome<RoomStateV2> {
    const state = this.read();
    if (!state || !this.member(state, player)) return this.unavailable(player);
    const unsupported = this.unsupported(state); if (unsupported) return unsupported;
    if (history !== undefined && context === undefined) noteHistorySupport(this.ctx.storage, player, history);
    return ok(state);
  }
  /** List metadata only: transferred rooms remain discoverable without restoring gameplay. */
  lobbySnapshot(player: string): Promise<Outcome<RoomLobbyV2>> {
    return this.project<RoomLobbyV2>(player, undefined, () => {
      const state = this.read();
      if (state) {
        if (!this.member(state, player)) return fail(404, "room_not_found");
        return this.unsupported(state) ?? ok(this.view(state, player));
      }
      const archived = transferredRoom(this.ctx.storage);
      if (!archived || !this.member(archived, player)) return fail(404, "room_not_found");
      const { invite_code: _invite, ...metadata } = archived; void _invite;
      // Every client knows a finished room whose replays left the server as version 1.
      return ok<RoomLobbyV2>({ ...metadata, replay_transfer_version: 1, api_version: 2, active_role: "complete" });
    });
  }
  safetyMembers(player: string, context?: CampaignRoomContext): Promise<Outcome<{ host_id: string; guest_id: string | null }>> {
    return this.project(player, context, () => {
      const state = this.memberView(player); if (!state) return fail(404, "room_not_found");
      return ok({ host_id: state.host_id, guest_id: state.guest_id });
    });
  }
  /** Binding only; ordinary social invites cannot admit campaign members. */
  friendInvite(host: string, visitor: string) {
    const boundary = campaignBoundaryGuard(this.ctx.storage, "campaign_social_unavailable"); if (boundary) return boundary;
    const archived = transferredRoom(this.ctx.storage);
    if (archived) return archived.host_id === host && this.member(archived, visitor) ? fail(410, "replay_transferred") : fail(404, "room_not_found");
    return friendRoomInvite(this.ctx.storage, host, visitor);
  }
  /** Cheap classification before a route considers a premium provider check. */
  campaignWriteAvailability(): Outcome<never> | null {
    if (campaignProductionEnabled()) return null;
    const boundary = campaignBoundaryGuard(this.ctx.storage, "campaign_unavailable");
    return boundary && !boundary.ok && boundary.code === "campaign_unavailable" ? fail(503, boundary.code) : boundary;
  }
  /** `hardClient`: the joining phone plays hard rooms (X-AfterYou-Hard-Mode). `name`, `pollen` and `look`: as in initialize, for a member who joins or returns.
   * `open`: the level ids the joining phone has open (chapter-unlocks.ts); a new guest whose list leaves out this room's chapter is refused. */
  async join(player: string, invite: string, supportedVersions?: number[], hardClient = false, name?: string | null, pollen?: PollenMember, look?: Look, open?: string[]): Promise<Outcome<RoomSnapshotV2>> {
    const boundary = campaignBoundaryGuard(this.ctx.storage, "campaign_join_required"); if (boundary) return boundary;
    const observed = this.stored();
    if (observed && equalHash(observed.invite_code, invite) && player !== observed.host_id && await interactionBlocked(this.env, observed.host_id, player)) return fail(403, "player_blocked");
    let joined = false;
    const outcome = await this.ctx.storage.transaction(async () => {
    const boundary = campaignBoundaryGuard(this.ctx.storage, "campaign_join_required"); if (boundary) return boundary;
    const state = this.read();
    const archived = transferredRoom(this.ctx.storage);
    if (!state && archived && equalHash(archived.invite_code, invite) && this.member(archived, player)) return this.unavailable(player);
    if (!state || !equalHash(state.invite_code, invite)) return fail(404, "invite_not_found");
    const unsupported = this.unsupported(state); if (unsupported) return unsupported;
    const selected = chapter(state);
    const requiredVersion = state.simulation_version ?? (selected.require_supported_simulation_on_join ? selected.simulation_version : undefined);
    if (requiredVersion !== undefined && !supportedVersions?.includes(requiredVersion)) return fail(422, "unsupported_simulation_version");
    // A phone that would offer retries never joins a hard room.
    if (!hardClient && this.hard.run(this.ctx.storage)) return fail(409, "hard_mode_client_required");
    if (this.member(state, player)) { recordMemberName(this.ctx.storage, player, name); recordMember(this.ctx.storage, player, pollen); recordMemberLook(this.ctx.storage, player, look); return ok(this.view(state, player)); }
    if (Date.parse(state.invite_expires_at) < Date.now()) return fail(410, "invite_expired");
    if (state.guest_id) return fail(409, "room_full");
    if (!chapterOpen(state.level_id, open)) return fail(403, CHAPTER_NOT_OPEN);
    state.guest_id = player; state.revision++; this.write(state);
    recordMemberName(this.ctx.storage, player, name);
    recordMember(this.ctx.storage, player, pollen);
    recordMemberLook(this.ctx.storage, player, look);
    recordRemoteRoomActivity(this.ctx.storage, player, state.host_id, state.guest_id);
    if (state.a_turn_id) queueTurnHint(this.ctx.storage, this.env, "relay", state, state.host_id, player);
    await scheduleGameplayNotifications(this.ctx.storage);
    joined = true;
    return ok(this.view(state, player));
    });
    if (joined && outcome.ok) this.announce(player, outcome.value);
    return outcome;
  }
  operation(player: string, key: string, context?: CampaignRoomContext): Promise<Outcome<MutationV2>> {
    return this.project(player, context, () => {
      const state = this.read();
      if (!state || !this.member(state, player)) return this.unavailable(player);
      const unsupported = this.unsupported(state); if (unsupported) return unsupported;
      const row = this.ctx.storage.sql.exec<{ receipt: string }>("SELECT receipt FROM operations WHERE request_key=?", player + ":" + key).toArray()[0];
      return row ? ok({ receipt: JSON.parse(row.receipt) as ReceiptV2, room: this.view(state, player) }) : fail(404, "operation_not_found");
    });
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
  /** `looks`: also every turn's look by recording hash, beside the archive and never in it (the archive's hash is unchanged; pollen/room-looks.ts). */
  async replayTransfer(player: string, includeArchive = true, allowPrepare = true, looks = false): Promise<Outcome<ReplayTransfer & { archive: ReplayArchive | null; turn_looks?: Record<string, Look> }>> {
    try {
      const boundary = campaignBoundaryGuard(this.ctx.storage, "replay_transfer_standalone_only"); if (boundary) return boundary;
      // A v1 archive needs every row; once attempt history has offloaded one, only history can bring it back.
      if (offloadedCount(this.ctx.storage)) return fail(409, "history_offload_active");
      const observed = this.memberView(player); if (!observed) return fail(404, "room_not_found");
      if (await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
      const state = this.read();
      if (!state) {
        const archived = transferredRoom(this.ctx.storage), value = readReplayTransfer(this.ctx.storage);
        return archived && this.member(archived, player) && value?.transferred ? ok({ ...value, archive: null, ...this.transferLooks(looks) }) : this.unavailable(player);
      }
      if (!this.member(state, player)) return fail(404, "room_not_found");
      if (!allowPrepare && !readReplayTransfer(this.ctx.storage)) return fail(503, "replay_transfer_disabled");
      const archive = this.ctx.storage.transactionSync(() => captureReplay(this.ctx.storage, state));
      const fingerprint = canonicalJson(archive), archiveHash = await digest(fingerprint);
      return this.ctx.storage.transactionSync(() => {
        const current = this.read(); if (!current || !this.member(current, player)) return this.unavailable(player);
        if (canonicalJson(captureReplay(this.ctx.storage, current)) !== fingerprint) return fail(409, "replay_source_changed");
        const prior = readReplayTransfer(this.ctx.storage);
        if (!allowPrepare && (!prior || prior.transferred || canonicalJson(prior.manifest) !== canonicalJson(factsForArchive(archive, prior.manifest.epoch, archiveHash)))) return fail(503, "replay_transfer_disabled");
        const value = allowPrepare ? prepareReplayTransfer(this.ctx.storage, archive, archiveHash) : prior!;
        return ok({ ...value, archive: includeArchive ? archive : null, ...this.transferLooks(looks) });
      });
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  private transferLooks(looks: boolean): { turn_looks?: Record<string, Look> } {
    return looks ? { turn_looks: turnLooks(this.ctx.storage) } : {};
  }
  async acknowledgeReplayTransfer(player: string, input: unknown): Promise<Outcome<ReplayTransfer>> {
    try {
      const boundary = campaignBoundaryGuard(this.ctx.storage, "replay_transfer_standalone_only"); if (boundary) return boundary;
      // A v1 archive needs every row; once attempt history has offloaded one, only history can bring it back.
      if (offloadedCount(this.ctx.storage)) return fail(409, "history_offload_active");
      const key = parseTransferKey(input), observed = this.memberView(player);
      if (!observed) return fail(404, "room_not_found");
      if (await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
      const prior = matchingTransfer(this.ctx.storage, key), state = this.read();
      if (!state) return prior.transferred && transferredRoom(this.ctx.storage) ? ok(prior) : this.unavailable(player);
      if (state.stage_index !== chapter(state).stages.length) return fail(409, "stale_replay_ack");
      const archive = this.ctx.storage.transactionSync(() => captureReplay(this.ctx.storage, state));
      const fingerprint = canonicalJson(archive);
      if (await digest(fingerprint) !== key.archive_hash) return fail(409, "stale_replay_ack");
      return this.indexed(this.ctx.storage.transactionSync(() => {
        const current = this.read(), transfer = matchingTransfer(this.ctx.storage, key);
        if (!current || !this.member(current, player)) return this.unavailable(player);
        if (canonicalJson(captureReplay(this.ctx.storage, current)) !== fingerprint) return fail(409, "stale_replay_ack");
        if (canonicalJson(factsForArchive(archive, key.epoch, key.archive_hash)) !== canonicalJson(transfer.manifest)) return fail(409, "replay_manifest_mismatch");
        return ok(acknowledgeReplay(this.ctx.storage, current, player, transfer));
      }));
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  async restoreReplayTransfer(player: string, input: unknown): Promise<Outcome<{ restored: true; transfer: ReplayTransfer }>> {
    try {
      const boundary = campaignBoundaryGuard(this.ctx.storage, "replay_transfer_standalone_only"); if (boundary) return boundary;
      // A v1 archive needs every row; once attempt history has offloaded one, only history can bring it back.
      if (offloadedCount(this.ctx.storage)) return fail(409, "history_offload_active");
      const observed = this.memberView(player); if (!observed) return fail(404, "room_not_found");
      if (await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
      const { key, archive } = await checkedRestore(input);
      return this.indexed(this.ctx.storage.transactionSync(() => {
        const current = this.memberView(player); if (!current) return fail(404, "room_not_found");
        const transfer = readReplayTransfer(this.ctx.storage);
        if (!transfer || transfer.manifest.archive_hash !== key.archive_hash) return fail(409, "replay_archive_mismatch");
        const live = this.read();
        if (live) {
          // A lost restore response is retryable only while its exact restored
          // payload is still current. Never hide a fork accepted in between.
          if (live.stage_index === chapter(live).stages.length && !transfer.transferred && transfer.manifest.epoch === key.epoch + 1 && canonicalJson(captureReplay(this.ctx.storage, live)) === canonicalJson(archive)) return ok({ restored: true, transfer });
          return fail(409, "stale_replay_restore");
        }
        if (transfer.manifest.epoch !== key.epoch) return fail(409, "stale_replay_restore");
        return ok({ restored: true, transfer: restoreReplay(this.ctx.storage, current as TransferredRoom, transfer, archive) });
      }));
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  replayTransferOperation(player: string, key: string): Promise<Outcome<{ schema_version: 1; receipt: ReceiptV2; transfer: ReplayTransfer }>> {
    return this.project(player, undefined, () => {
      const boundary = campaignBoundaryGuard(this.ctx.storage, "replay_transfer_standalone_only"); if (boundary) return boundary;
      const state = this.memberView(player); if (!state) return fail(404, "room_not_found");
      const transfer = readReplayTransfer(this.ctx.storage); if (!transfer) return fail(404, "replay_transfer_not_found");
      const row = this.ctx.storage.sql.exec<{ receipt: string }>("SELECT receipt FROM operations WHERE request_key=?", player + ":" + key).toArray()[0];
      return row ? ok({ schema_version: 1, receipt: JSON.parse(row.receipt) as ReceiptV2, transfer }) : fail(404, "operation_not_found");
    });
  }
  /** Standalone member access for attempt history; also records what the request said about support. */
  private async historyAccess(player: string, support?: HistorySupport): Promise<HistoryRoom> {
    if (campaignBoundaryGuard(this.ctx.storage, "history_standalone_only")) throw new ApiError(409, "history_standalone_only");
    const room = this.memberView(player); if (!room) throw new ApiError(404, "room_not_found");
    if (await interactionBlocked(this.env, room.host_id, room.guest_id)) throw new ApiError(403, "player_blocked");
    if (!archived(room)) { const unsupported = this.unsupported(room); if (unsupported && !unsupported.ok) throw new ApiError(unsupported.status, unsupported.code); }
    if (support !== undefined) noteHistorySupport(this.ctx.storage, player, support);
    return this.stored()!;
  }
  private async historyRecord(player: string, position: number, support: HistorySupport | undefined, promote: boolean): Promise<{ room: HistoryRoom; record: AttemptRecord; records: AttemptRecord[] }> {
    const room = await this.historyAccess(player, support);
    if (archived(room) && room.replay_transfer_version === 1) throw new ApiError(409, "history_v1_transferred");
    const records = await loadChain(this.ctx.storage, room, promote), record = records[position];
    if (!record) throw new ApiError(404, "history_not_found");
    return { room, record, records };
  }
  /** Re-reads the room and the stored record inside the writing transaction. */
  private historyCurrent(player: string, record: AttemptRecord): { room: HistoryRoom; record: AttemptRecord } {
    const room = this.memberView(player); if (!room) throw new ApiError(404, "room_not_found");
    const stored = storedAttempts(this.ctx.storage)[record.position];
    if (!stored || stored.link !== record.link) throw new ApiError(409, "history_changed");
    return { room, record: stored };
  }
  async history(player: string, support?: HistorySupport): Promise<Outcome<HistoryView>> {
    try {
      const room = await this.historyAccess(player, support);
      if (archived(room) && room.replay_transfer_version === 1) return ok(v1Transferred(this.ctx.storage, room, player));
      return ok(historyView(this.ctx.storage, room, await loadChain(this.ctx.storage, room, false), player));
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  async historyAttempt(player: string, position: number, support?: HistorySupport): Promise<Outcome<Uint8Array>> {
    try {
      const { room, record } = await this.historyRecord(player, position, support, false);
      return ok(await attemptDownload(this.ctx.storage, room, record));
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  /** The router allows this only while HISTORY_OFFLOAD_ENABLED is true. */
  async acknowledgeHistory(player: string, position: number, input: unknown, support?: HistorySupport): Promise<Outcome<HistoryView>> {
    try {
      const link = parseAck(input), { record } = await this.historyRecord(player, position, support, true);
      if (record.link !== link) return fail(409, "history_mismatch");
      return this.indexed(this.ctx.storage.transactionSync(() => {
        const current = this.historyCurrent(player, record);
        acknowledgeAttempt(this.ctx.storage, current.room, current.record, player);
        return ok(historyView(this.ctx.storage, current.room, storedAttempts(this.ctx.storage), player));
      }));
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  async uploadHistory(player: string, position: number, body: Uint8Array, support?: HistorySupport): Promise<Outcome<HistoryView>> {
    try {
      const { room, record, records } = await this.historyRecord(player, position, support, false);
      const blob = await checkedUpload(records, position, body, room);
      return this.indexed(this.ctx.storage.transactionSync(() => {
        const current = this.historyCurrent(player, record);
        restoreAttempt(this.ctx.storage, current.room, current.record, blob, player);
        return ok(historyView(this.ctx.storage, this.stored()!, storedAttempts(this.ctx.storage), player));
      }));
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  async wantHistory(player: string, position: number, input: unknown, support?: HistorySupport): Promise<Outcome<HistoryView>> {
    try {
      parseWant(input);
      const { room, record } = await this.historyRecord(player, position, support, false);
      if (record.state === "held") return ok(historyView(this.ctx.storage, room, await loadChain(this.ctx.storage, room, false), player));
      return this.ctx.storage.transactionSync(() => {
        const current = this.historyCurrent(player, record);
        wantAttempt(this.ctx.storage, current.room, current.record, player);
        return ok(historyView(this.ctx.storage, current.room, storedAttempts(this.ctx.storage), player));
      });
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  /**
   * `beside`: what the reply carries beside the room for a standalone member (Beside).
   * `name`: the member's own display name, stored with an accepted standalone turn (display-names.ts).
   * `pollen`: the member's Full Journey end while Pollen earning is on. An accepted standalone turn then
   * freezes its facts (pollen/turn-facts.ts), and the outcome carries them as `pollen_facts`, for a
   * retried commit too. Undefined writes and returns nothing more.
   * `look`: the member's look while looks are on, kept as theirs and as this turn's own look (pollen/room-looks.ts).
   */
  async commit(player: string, value: unknown, context?: CampaignRoomContext, beside: Beside = {}, name?: string | null, pollen?: PollenMember, look?: Look): Promise<Outcome<CommittedV2>> {
    const outcome = await this.commitTurn(player, value, context, name, pollen, look);
    if (!outcome.ok || context !== undefined) return outcome;
    const facts = pollen !== undefined && outcome.value.receipt.recording_hash ? turnFacts(this.ctx.storage, outcome.value.receipt.recording_hash) : null;
    const extra = facts?.player_id === player ? { pollen_facts: facts } : {};
    if (!(beside.faces || beside.names || beside.tracks || beside.looks)) return facts ? ok<CommittedV2>({ ...outcome.value, ...extra }) : outcome;
    const state = this.stored();
    return state ? ok<CommittedV2>({ ...outcome.value, ...this.beside(state, player, beside), ...extra }) : outcome;
  }
  private async commitTurn(player: string, value: unknown, context?: CampaignRoomContext, name?: string | null, pollen?: PollenMember, look?: Look): Promise<Outcome<MutationV2>> {
    try {
      const input = object(value);
      const raw = object(input.recording);
      exact(input, ["base_revision", "idempotency_key", "branch", "recording", ...(raw.role === "b" ? ["checkpoint"] : []), ...triesField(input), ...endReactionField(input), ...runReactionField(input)]);
      const tries = parseTries(input), face = parseEndReaction(input), track = parseRunReactions(input);
      const revision = integer(input.base_revision, 0, Number.MAX_SAFE_INTEGER), branch = integer(input.branch, 0, MAX_BRANCHES - 1);
      const key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
      const bounded = this.read();
      let limits; try { limits = bounded ? chapter(bounded).limits : undefined; } catch { limits = undefined; }
      boundedTurnValue(input, limits);
      const observed = this.read();
      if (!observed || !this.member(observed, player)) return fail(404, "room_not_found");
      const recording = await recordingV2(raw, observed), hash = await digest(canonicalJson({ operation: "turns", ...input }));
      if (recording.simulation_version !== (observed.simulation_version ?? chapter(observed).simulation_version)) return fail(422, "unsupported_simulation_version");
      withinTurn(track, recording.duration_ticks);
      const retryAccess = await prepareCampaignHttpAccess(this.ctx.storage, this.env, player, context);
      const retryGuard = campaignHttpAccessGuard(this.ctx.storage, retryAccess); if (retryGuard) return retryGuard;
      const currentRetry = this.read();
      if (!currentRetry || !this.member(currentRetry, player)) return fail(404, "room_not_found");
      const retried = this.retry(currentRetry, player, key, hash); if (retried) return retried;
      if (retryAccess && !campaignProductionEnabled()) return fail(503, "campaign_unavailable");
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
      const access = await prepareCampaignHttpAccess(this.ctx.storage, this.env, player, context);
      return this.indexed(await this.ctx.storage.transaction(async () => {
        const projectionGuard = campaignHttpAccessGuard(this.ctx.storage, access); if (projectionGuard) return projectionGuard;
        const state = this.read();
        if (!state || !this.member(state, player)) return fail(404, "room_not_found");
        const prior = this.retry(state, player, key, hash); if (prior) return prior;
        const writeGuard = campaignHttpAccessGuard(this.ctx.storage, access, true); if (writeGuard) return writeGuard;
        if (state.revision !== revision || state.branch !== branch) return fail(409, "stale_revision");
        if (recording.simulation_version !== (state.simulation_version ?? chapter(state).simulation_version)) return fail(422, "unsupported_simulation_version");
        const current = this.view(state, player);
        if (current.active_player_id !== player || current.active_role !== recording.role) return fail(409, "wrong_turn");
        // A hard room takes only first tries, and nothing once its run is over.
        if (current.hard?.over) return fail(409, "hard_run_over");
        if (current.hard && tries !== undefined && tries > 1) return fail(409, "hard_run_retry");
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
        if (context === undefined) recordTries(this.ctx.storage, turn_id, recording.recording_hash, tries);
        if (context === undefined) recordEndReaction(this.ctx.storage, turn_id, recording.recording_hash, player, face);
        if (context === undefined) recordRunReactions(this.ctx.storage, turn_id, recording.recording_hash, player, track);
        if (context === undefined) recordMemberName(this.ctx.storage, player, name);
        if (context === undefined) { recordMemberLook(this.ctx.storage, player, look); recordTurnLook(this.ctx.storage, recording.recording_hash, player, look); }
        if (recording.role === "a") state.a_turn_id = turn_id;
        else {
          const pair: PairV2 = { pair_id: pair_id!, branch, stage_index, a: this.turn(state.a_turn_id!), b: recording, checkpoint: checkpoint! };
          this.ctx.storage.sql.exec("INSERT INTO pairs VALUES (?,?)", pair_id, JSON.stringify(pair));
          state.completed_pair_ids.push(pair_id!); state.checkpoint = checkpoint!; state.stage_index++; state.a_turn_id = null;
        }
        if (context === undefined && pollen !== undefined) {
          recordMember(this.ctx.storage, player, pollen);
          recordTurnFacts(this.ctx.storage, { room_id: state.room_id, recording_hash: recording.recording_hash, turn_id, player, partner: this.partnerOf(state, player),
            host: player === state.host_id, level_id: state.level_id, stage_id, role: recording.role, ticks: recording.duration_ticks, tries,
            premium: chapter(state).premium, hard: Boolean(current.hard), complete: recording.role === "b" && state.stage_index >= chapter(state).stages.length, accepted_at: Date.now() });
        }
        const receipt: ReceiptV2 = { schema_version: 2, room_id: state.room_id, idempotency_key: key, request_hash: hash, operation: "turns",
          accepted_revision: state.revision, branch, stage_index, stage_id, turn_id, recording_hash: recording.recording_hash, pair_id, checkpoint_hash: state.checkpoint.checkpoint_hash };
        const saved = this.saveReceipt(state, player, receipt);
        recordRemoteRoomActivity(this.ctx.storage, player, state.host_id, state.guest_id);
        if (this.notificationsAvailable()) {
          queueTurnHint(this.ctx.storage, this.env, "relay", state, player);
          await scheduleGameplayNotifications(this.ctx.storage);
        }
        return ok(saved);
      }), false, player);
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  fork(player: string, value: unknown, context?: CampaignRoomContext, redoDeviceHash?: string): Promise<Outcome<MutationV2>> {
    return this.forkInternal(player, value, context, redoDeviceHash);
  }
  private async forkInternal(player: string, value: unknown, context?: CampaignRoomContext, redoDeviceHash?: string, campaignRedo?: CampaignRedoAccept): Promise<Outcome<MutationV2>> {
    try {
      const input = object(value); exact(input, ["base_revision", "idempotency_key", "branch", "stage_index", ...(input.redo_request_id === undefined ? [] : ["redo_request_id"])]);
      const redoRequestId = input.redo_request_id === undefined ? undefined : text(input.redo_request_id, /^[a-f0-9]{64}$/);
      if (redoRequestId !== undefined && !campaignRedo) {
        const boundary = campaignBoundaryGuard(this.ctx.storage, "campaign_redo_unavailable"); if (boundary) return boundary;
      }
      const revision = integer(input.base_revision, 0, Number.MAX_SAFE_INTEGER), branch = integer(input.branch, 0, MAX_BRANCHES - 1);
      const observed = this.read();
      if (!observed || !this.member(observed, player)) return fail(404, "room_not_found");
      const stageIndex = integer(input.stage_index, 0, chapter(observed).stages.length - 1), key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
      const hash = await digest(canonicalJson({ operation: "fork", ...input }));
      if (await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
      let access = await prepareCampaignHttpAccess(this.ctx.storage, this.env, player, context);
      if (campaignRedo) {
        campaignRedoAccess(access, campaignRedo.binding);
        const guard = campaignHttpAccessGuard(this.ctx.storage, access); if (guard) return guard;
        const current = this.read(); if (!current || !this.member(current, player)) return fail(404, "room_not_found");
        // Accepted retries precede fresh source, consent, flags and purchase
        // checks, including after the parent publishes a later chapter.
        const prior = this.retry(current, player, key, hash); if (prior) return prior;
        campaignRedoMutations(this.env); campaignRedoAccess(access, campaignRedo.binding, true);
        if (campaignRedo.binding.chapter.premium) await campaignHostAccess(this.env, current.host_id);
        access = await prepareCampaignHttpAccess(this.ctx.storage, this.env, player, context);
      }
      if (redoRequestId !== undefined && redoDeviceHash !== undefined && !await this.env.PLAYERS.getByName(player).authorize(redoDeviceHash)) return fail(401, "invalid_auth");
      return this.indexed(await this.ctx.storage.transaction(async () => {
        if (redoRequestId !== undefined && !campaignRedo) {
          const boundary = campaignBoundaryGuard(this.ctx.storage, "campaign_redo_unavailable"); if (boundary) return boundary;
        }
        const projectionGuard = campaignHttpAccessGuard(this.ctx.storage, access); if (projectionGuard) return projectionGuard;
        const state = this.read();
        if (!state || !this.member(state, player)) return fail(404, "room_not_found");
        const prior = this.retry(state, player, key, hash); if (prior) return prior;
        const writeGuard = campaignHttpAccessGuard(this.ctx.storage, access, true); if (writeGuard) return writeGuard;
        if (campaignRedo) {
          campaignRedoMutations(this.env); campaignRedoAccess(access, campaignRedo.binding, true);
          if (!sameRedoValue(this.redoSource(state), campaignRedo.source)) return fail(409, "redo_source_changed");
        }
        if (state.revision !== revision || state.branch !== branch) return fail(409, "stale_revision");
        if (anyDeparture(this.ctx.storage)) return fail(409, "room_member_left");
        // A hard room goes back only through its own reset.
        if (this.hard.run(this.ctx.storage)) return fail(409, "hard_run_no_redo");
        if (redoRequestId !== undefined) {
          if (stageIndex !== state.stage_index) return fail(409, "redo_source_changed");
          const consent = consentToRedo(this.ctx.storage, this.redoSource(state), player, redoRequestId); if (!consent.ok) return consent;
        }
        if (stageIndex > state.stage_index || (stageIndex === state.stage_index && !state.a_turn_id)) return fail(409, "nothing_to_fork");
        // A chapter's branch limit counts only attempts the server holds in full; offloaded ones are hashes.
        const held = state.branch + 2 - offloadedCount(this.ctx.storage);
        if (!this.capacity() || state.branch + 1 >= MAX_BRANCHES || held > Math.min(MAX_BRANCHES, chapter(state).max_branches ?? MAX_BRANCHES)) return fail(409, "room_history_full");
        // Every checkpoint nests its predecessor exactly, so the fork point comes from the live checkpoint.
        state.checkpoint = stageIndex === 0 ? initialCheckpoint(state) : checkpointAt(state.checkpoint, stageIndex);
        state.completed_pair_ids = state.completed_pair_ids.slice(0, stageIndex); state.a_turn_id = null;
        state.stage_index = stageIndex; state.branch++; state.revision++;
        if (redoRequestId !== undefined) acceptedRedo(this.ctx.storage);
        const receipt: ReceiptV2 = { schema_version: 2, room_id: state.room_id, idempotency_key: key, request_hash: hash, operation: "fork",
          accepted_revision: state.revision, branch: state.branch, stage_index: stageIndex, stage_id: chapter(state).stages[stageIndex].id,
          turn_id: null, recording_hash: null, pair_id: null, checkpoint_hash: state.checkpoint.checkpoint_hash };
        const saved = this.saveReceipt(state, player, receipt);
        stubReleased(this.ctx.storage, state);
        if (redoRequestId !== undefined) recordRemoteRoomActivity(this.ctx.storage, player, state.host_id, state.guest_id);
        if (!campaignRedo) { clearTurnHints(this.ctx.storage); await scheduleGameplayNotifications(this.ctx.storage); }
        return ok(saved);
      }), true, campaignRedo ? undefined : player);
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  /**
   * A hard room's slip (v2/hard-mode.ts): one request, one transaction. The
   * slipping player, on their turn, sends the room they played on; the room
   * goes back to its first stage on a new branch (a fork) when it has
   * anything to undo, or only moves its revision when the slip was the first
   * turn, and records who slipped with the slip's recording, checkpoint and
   * first turn. When the room has no space left for a whole new run it keeps
   * the slip and ends the run (over) instead. A resend answers the same.
   * `enabled`: the hard mode flag; a room that is not hard says 503 while it
   * is off, so the route is inert until it is on.
   */
  async hardReset(player: string, value: unknown, enabled: boolean): Promise<Outcome<{ room: RoomSnapshotV2; failure: Failure }>> {
    try {
      const observed = this.read();
      if (!observed || !this.member(observed, player)) return this.unavailable(player);
      if (!this.hard.run(this.ctx.storage)) return fail(enabled ? 409 : 503, enabled ? "not_hard_room" : "hard_mode_disabled");
      const stages = chapter(observed).stages.length;
      const input = parseReset(value, stages);
      const hash = await digest(canonicalJson({ operation: "hard-reset", ...input }));
      // A slip that does not check is dropped, never the reset: the room must start again.
      let slipRecording: RecordingV2 | null = null;
      if (input.slip !== undefined) { try { slipRecording = await recordingV2(input.slip, observed); } catch { slipRecording = null; } }
      if (await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
      return this.indexed(await this.ctx.storage.transaction(async () => {
        const state = this.read();
        if (!state || !this.member(state, player)) return this.unavailable(player);
        const done = priorReset(this.ctx.storage, player, input.idempotency_key, hash);
        if (done) return ok({ room: this.view(state, player), failure: done });
        if (state.revision !== input.base_revision || state.branch !== input.branch) return fail(409, "stale_revision");
        if (anyDeparture(this.ctx.storage)) return fail(409, "room_member_left");
        const current = this.view(state, player);
        if (current.active_role === "complete") return fail(409, "hard_run_complete");
        if (current.hard?.over) return fail(409, "hard_run_over");
        if (current.active_player_id !== player) return fail(409, "hard_not_your_turn");
        if (input.stage_index !== state.stage_index || input.role !== current.active_role) return fail(409, "stale_revision");
        const slip: Slip | null = slipRecording && slipRecording.stage_id === current.stage_id && slipRecording.role === input.role && slipRecording.checkpoint_hash === state.checkpoint.checkpoint_hash
          ? { recording: slipRecording, checkpoint: state.checkpoint, prior: input.role === "b" && state.a_turn_id ? this.turn(state.a_turn_id) : null } : null;
        const failure: Failure = { by: player, stage_index: state.stage_index, role: input.role, reason: input.reason, at: new Date().toISOString() };
        const progress = state.stage_index > 0 || state.a_turn_id !== null;
        // Only a reset with progress to undo needs a branch; a first-turn slip always fits.
        const room = !progress || this.hardRunSpace(state);
        if (progress && room) {
          state.checkpoint = initialCheckpoint(state);
          state.completed_pair_ids = []; state.a_turn_id = null; state.stage_index = 0; state.branch++;
        }
        state.revision++;
        this.write(state);
        recordFailure(this.ctx.storage, this.hard, player, input.idempotency_key, hash, failure, slip, progress && !room);
        if (progress && room) stubReleased(this.ctx.storage, state);
        recordRemoteRoomActivity(this.ctx.storage, player, state.host_id, state.guest_id);
        clearTurnHints(this.ctx.storage);
        if (this.notificationsAvailable()) {
          queueTurnHint(this.ctx.storage, this.env, "relay", state, player);
          await scheduleGameplayNotifications(this.ctx.storage);
        }
        return ok({ room: this.view(state, player), failure });
      // A reset never reopens a settled room, so the index needs no push (as a turn).
      }), false, player);
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  /**
   * Whether a hard room can hold one more whole run after this one: a branch
   * to fork to under the room's and chapter's limits, and turns, pairs and
   * receipts for every stage of it.
   */
  private hardRunSpace(state: RoomStateV2): boolean {
    const count = (table: string) => this.ctx.storage.sql.exec<{ n: number }>(`SELECT COUNT(*) AS n FROM ${table}`).one().n;
    const stages = chapter(state).stages.length;
    const held = state.branch + 2 - offloadedCount(this.ctx.storage);
    return state.branch + 1 < MAX_BRANCHES && held <= Math.min(MAX_BRANCHES, chapter(state).max_branches ?? MAX_BRANCHES) &&
      count("turns") + 2 * stages <= MAX_TURNS && count("pairs") + stages <= MAX_PAIRS && count("operations") + 2 * stages <= MAX_OPERATIONS;
  }
  /** A hard room's kept slips for its members (GET .../hard). */
  hardFailures(player: string, enabled: boolean, since = 0): Promise<Outcome<HardFailures>> {
    return this.project(player, undefined, () => {
      if (!this.memberView(player)) return fail(404, "room_not_found");
      const view = failuresView(this.ctx.storage, this.hard, since);
      return view ? ok(view) : fail(enabled ? 409 : 503, enabled ? "not_hard_room" : "hard_mode_disabled");
    });
  }
  collection(player: string, context?: CampaignRoomContext): Promise<Outcome<{ pairs: { pair_id: string; branch: number; stage_index: number; a_hash: string; b_hash: string; checkpoint_hash: string }[]; active_pair_ids: string[] }>> {
    return this.project(player, context, () => {
      const state = this.read();
      if (!state || !this.member(state, player)) return this.unavailable(player);
      const pairs = this.ctx.storage.sql.exec<{ pair_id: string; branch: number; stage_index: number; a_hash: string; b_hash: string; checkpoint_hash: string }>(
        "SELECT pair_id,json_extract(data,'$.branch') AS branch,json_extract(data,'$.stage_index') AS stage_index,json_extract(data,'$.a.recording_hash') AS a_hash,json_extract(data,'$.b.recording_hash') AS b_hash,json_extract(data,'$.checkpoint.checkpoint_hash') AS checkpoint_hash FROM pairs ORDER BY rowid"
      ).toArray();
      return ok({ pairs, active_pair_ids: state.completed_pair_ids });
    });
  }
  /** Standalone rooms: every turn's sent face, live, offloaded or replay-transferred alike, and with `tracks` every turn's run reactions beside them. */
  endReactions(player: string, tracks = false): Promise<Outcome<EndReactionsList & { run_reactions?: RunReactionsView }>> {
    return this.project(player, undefined, () => this.memberView(player)
      ? ok({ ...endReactionsList(this.ctx.storage), ...(tracks ? { run_reactions: runReactionsView(this.ctx.storage) } : {}) }) : fail(404, "room_not_found"));
  }
  /** Standalone rooms: every turn's sent try count, live, offloaded or replay-transferred alike. */
  tries(player: string): Promise<Outcome<TurnTriesView>> {
    return this.project(player, undefined, () => this.memberView(player) ? ok(turnTriesView(this.ctx.storage)) : fail(404, "room_not_found"));
  }
  pairRecording(player: string, id: string, context?: CampaignRoomContext): Promise<Outcome<PairV2>> {
    return this.project(player, context, () => {
      const state = this.read();
      if (!state || !this.member(state, player)) return this.unavailable(player);
      const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM pairs WHERE pair_id=?", id).toArray()[0];
      if (!row) return fail(404, "pair_not_found");
      if (isStub(row.data)) return fail(410, "history_offloaded");
      return ok(JSON.parse(row.data) as PairV2);
    });
  }
  reactions(player: string, pairId: string, context?: CampaignRoomContext) { return this.project(player, context, () => getPairReactions(this.ctx.storage, this.memberView(player), player, pairId)); }
  reactionOperation(player: string, key: string, context?: CampaignRoomContext) { return this.project(player, context, () => getReactionOperation(this.ctx.storage, this.memberView(player), player, key)); }
  async react(player: string, pairId: string, value: unknown, context?: CampaignRoomContext): Promise<Outcome<ReactionMutation>> {
    try {
      const available = await this.reactions(player, pairId, context); if (!available.ok) return available;
      const input = await parseReaction(pairId, value);
      const observed = this.stored();
      if (observed && await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
      const access = await prepareCampaignHttpAccess(this.ctx.storage, this.env, player, context);
      return this.ctx.storage.transactionSync(() => campaignHttpAccessGuard(this.ctx.storage, access) ?? mutateReaction(this.ctx.storage, this.memberView(player), player, input));
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); return fail(500, "reaction_storage_error"); }
  }
  photoDelivery(player: string, turn: string, context?: CampaignRoomContext) { return this.project(player, context, () => photoDelivery(this.ctx.storage, this.memberView(player), player, turn)); }
  async acknowledgePhoto(player: string, turn: string, value: unknown, context?: CampaignRoomContext) {
    try { const access = await prepareCampaignHttpAccess(this.ctx.storage, this.env, player, context); return this.ctx.storage.transactionSync(() => campaignHttpAccessGuard(this.ctx.storage, access) ?? acknowledgePhoto(this.ctx.storage, this.memberView(player), player, turn, value)); }
    catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  photo(player: string, turnId: string, context?: CampaignRoomContext) { return this.project(player, context, () => getPhoto(this.ctx.storage, this.memberView(player), player, turnId)); }
  photoOperation(player: string, key: string, context?: CampaignRoomContext) { return this.project(player, context, () => getPhotoOperation(this.ctx.storage, this.memberView(player), player, key)); }
  async updatePhoto(player: string, turnId: string, value: unknown, remove = false, context?: CampaignRoomContext): Promise<Outcome<PhotoMutation>> {
    try {
      const observed = this.memberView(player);
      if (!observed) return fail(404, "room_not_found");
      text(turnId, PHOTO_TURN_PATTERN, "invalid_photo_turn");
      const hash = text(object(value).recording_hash, /^[a-f0-9]{64}$/);
      const accepted = this.ctx.storage.sql.exec<{ player_id: string; data: string }>("SELECT player_id,data FROM turns WHERE turn_id=?", turnId).toArray()[0];
      if (!accepted || accepted.player_id !== player) return fail(404, "turn_not_found");
      if (JSON.parse(accepted.data).recording_hash !== hash) return fail(409, "photo_recording_mismatch");
      const input = await parsePhotoMutation(turnId, value, remove);
      if (!remove) {
        if (await interactionBlocked(this.env, observed.host_id, observed.guest_id)) return fail(403, "player_blocked");
        if (flags.safetyEnforcement(this.env) && !(await this.env.SAFETY_PROFILES.getByName(player).terms(player)).accepted) return fail(403, "terms_acceptance_required");
      }
      const access = await prepareCampaignHttpAccess(this.ctx.storage, this.env, player, context);
      return this.ctx.storage.transactionSync(() => campaignHttpAccessGuard(this.ctx.storage, access) ?? mutatePhoto(this.ctx.storage, this.memberView(player), player, input));
    } catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); return fail(500, "photo_storage_error"); }
  }
  /**
   * The erase always tells the other member's room index, whatever the flag,
   * so no index row keeps the erased member's id (room-index-sync.ts).
   */
  async eraseForPlayer(player: string, pendingCreation = false): Promise<Outcome<{ deleted: boolean }>> {
    let erased: { room_id: string; partner: string | null; hint: LiveHint | null } | null = null;
    const result = await this.ctx.storage.transaction(async () => {
    const boundary = campaignBoundaryGuard(this.ctx.storage, "campaign_delete_required"); if (boundary) return boundary;
    const state = this.stored();
    if (!state && pendingCreation) {
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO room VALUES (1,?)", '{"deleted":true}'); return ok({ deleted: true });
    }
    if (!state || !this.member(state, player)) return fail(404, "room_not_found");
      erased = { room_id: state.room_id, partner: player === state.host_id ? state.guest_id : state.host_id, hint: this.liveHintFrom(state) };
    await this.eraseRoom();
    return ok({ deleted: true });
    });
    const done = erased as { room_id: string; partner: string | null; hint: LiveHint | null } | null;
    // The erase push always reaches the partner; a live hint rides on it.
    if (result.ok && done?.partner) pushRoomIndex(this.ctx, this.env, done.room_id, 2, [done.partner], member => this.projection(member), done.hint ? { to: done.partner, hint: done.hint } : undefined);
    return result;
  }
  /** Erases the whole room for both members; the caller owns the transaction and has checked membership. */
  private async eraseRoom(): Promise<void> {
    this.ctx.storage.sql.exec("UPDATE room SET data=? WHERE id=1", '{"deleted":true}');
    clearRoomInboxActivity(this.ctx.storage);
    this.ctx.storage.sql.exec("DELETE FROM turns"); this.ctx.storage.sql.exec("DELETE FROM pairs"); this.ctx.storage.sql.exec("DELETE FROM operations");
    this.ctx.storage.sql.exec("DELETE FROM photos"); this.ctx.storage.sql.exec("DELETE FROM photo_operations"); clearDelivery(this.ctx.storage);
    clearPairReactions(this.ctx.storage);
    clearReplayTransfer(this.ctx.storage);
    clearHistory(this.ctx.storage);
    clearTurnTries(this.ctx.storage);
    clearEndReactions(this.ctx.storage);
    clearRunReactions(this.ctx.storage);
    clearMemberNames(this.ctx.storage);
    clearPollenRoom(this.ctx.storage);
    clearLooks(this.ctx.storage);
    clearHard(this.ctx.storage, this.hard);
    resetRedo(this.ctx.storage);
    clearTurnHints(this.ctx.storage); await scheduleNotifications(this.ctx.storage);
    // Last, so nothing after it can roll back the drop under the cached answer in room-departure.ts.
    clearDepartures(this.ctx.storage);
  }
  /**
   * A member leaves a room that is finished for them: their photos, photo
   * deliveries and reactions are erased and they stop being a member, while the
   * partner keeps the room, its replay and both players' turns. The last member
   * out erases the whole room. 404 means the caller is no longer a member.
   */
  async leaveFinished(player: string): Promise<Outcome<{ left: true }>> {
    // The partner's index row picks up partner_left; a leave is not an erasure, so the push stays flag-gated.
    return this.indexed(await this.ctx.storage.transaction(async () => {
      const boundary = campaignBoundaryGuard(this.ctx.storage, "campaign_leave_unavailable"); if (boundary) return boundary;
      const state = this.memberView(player);
      if (!state) return fail(404, "room_not_found");
      if (this.memberRoomState(player) !== "finished") return fail(409, "room_not_closed");
      const partner = player === state.host_id ? state.guest_id : state.host_id;
      // The partner is waiting for an attempt only a member's phone still holds.
      if (partner !== null && storedAttempts(this.ctx.storage).some(record => record.state === "offloaded" && record.wanted.includes(partner))) return fail(409, "history_offload_active");
      if (partner === null || departed(this.ctx.storage, partner)) { await this.eraseRoom(); return ok({ left: true }); }
      for (const turn of erasePlayerPhotos(this.ctx.storage, player)) clearDelivery(this.ctx.storage, turn);
      erasePlayerReactions(this.ctx.storage, player);
      eraseEndReactionsOf(this.ctx.storage, player);
      eraseRunReactionsOf(this.ctx.storage, player);
      eraseMemberName(this.ctx.storage, player);
      eraseMemberLook(this.ctx.storage, player);
      eraseTurnLooksOf(this.ctx.storage, player);
      recordDeparture(this.ctx.storage, player);
      return ok({ left: true });
    }), true, player);
  }
  /**
   * Binding only (POST /v1/pollen/turn-claims): the frozen facts of one of `player`'s accepted turns.
   * Read only; facts outlive replay transfer and history offload, which never touch them.
   */
  pollenTurnFacts(player: string, recordingHash: string): Outcome<TurnFacts> {
    const facts = turnFacts(this.ctx.storage, recordingHash);
    return facts && facts.player_id === player ? ok(facts) : fail(404, "pollen_turn_not_found");
  }
  /**
   * Binding only (POST /v1/pollen/clear-claims): the facts of the turn that finished this room's chapter,
   * for a member of the room. Read only.
   */
  pollenClearFacts(player: string): Outcome<TurnFacts> {
    const state = this.stored() ?? transferredRoom(this.ctx.storage);
    const facts = state && this.member(state, player) ? completionFacts(this.ctx.storage) : null;
    return facts ? ok(facts) : fail(404, "pollen_clear_not_found");
  }
  /**
   * Binding only (operator clear-name): deletes `player`'s stored name. When a row went and the room
   * index is on, the other member's index row is pushed again so it stops showing the name.
   */
  clearMemberName(player: string): boolean {
    const cleared = this.ctx.storage.transactionSync(() => eraseMemberName(this.ctx.storage, player));
    const state = cleared && flags.roomIndex(this.env) ? this.stored() : null;
    const partner = state ? this.partnerOf(state, player) : null;
    if (state && partner) pushRoomIndex(this.ctx, this.env, state.room_id, 2, [partner], member => this.projection(member));
    return cleared;
  }
}

// A RoomV2 nobody has written to answers these reads as an empty room did, and stores nothing.
const roomNotFound = () => fail(404, "room_not_found");
answerWhileBlank(RoomV2, {
  join: async () => fail(404, "invite_not_found"), resolvesInvitation: () => false, memberRoomState: () => "gone", notificationEligible: () => false,
  stageCount: () => 2, campaignRoomNegotiation: () => ok(true), friendInvite: roomNotFound, inboxProjection: roomNotFound, indexEntry: () => observeRoom(roomNotFound),
  safetyMembers: async () => roomNotFound(), snapshot: async () => roomNotFound(), snapshotIfChanged: async () => roomNotFound(), lobbySnapshot: async () => roomNotFound(),
  operation: async () => roomNotFound(), collection: async () => roomNotFound(), pairRecording: async () => roomNotFound(), reactions: async () => roomNotFound(),
  reactionOperation: async () => roomNotFound(), photo: async () => roomNotFound(), photoOperation: async () => roomNotFound(), photoDelivery: async () => roomNotFound(),
  redo: async () => roomNotFound(), history: async () => roomNotFound(), tries: async () => roomNotFound(), endReactions: async () => roomNotFound(), interactionAllowed: async () => roomNotFound(),
  hardReset: async () => roomNotFound(), hardFailures: async () => roomNotFound(), clearMemberName: () => false,
  pollenTurnFacts: () => fail(404, "pollen_turn_not_found"), pollenClearFacts: () => fail(404, "pollen_clear_not_found"),
  campaignDrainCensus: () => absentCensus()
});
