import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { encode } from "jpeg-js";
import worker from "../src/index";
import { withConfig } from "./config";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { TERMS_VERSION } from "../src/public-policy";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { checkpointV2, initialCheckpoint, recordingV2, acceptedRecording, boundedTurnValue, chapter } from "../src/v2/protocol";
import { advertisedChapters } from "../src/v2/chapters";
import { sleepingLighthouseV2, LIGHTHOUSE_V2_HASH, LIGHTHOUSE_LIMITS, LIGHTHOUSE_MAX_BRANCHES } from "../src/v2/protocol-lighthouse";
import { validateTransfer } from "../src/v2/replay-transfer";
import type { ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import chain from "../../game/tests/fixtures/lighthouse/v2-chain.json";
import bundledDefinition from "../src/v2/sleeping-lighthouse-v2.json";
import bundledInitial from "../src/v2/sleeping-lighthouse-v2-initial.json";

// sleeping-lighthouse@2: one six-stage chapter on the shared format. Fixtures come from
// game/tests/test_lighthouse_v2_proof.gd.
type Account = { player_id: string; device_token: string };
type Any = Record<string, any>;
const CODE = "SYNTHETIC-LIGHTHOUSE-HOST", ON = {};
const OLD_CLIENT = [2, 4, 5, 6, 7, 8, 9], NSTAGE_CLIENT = [2, 4, 5, 6, 7, 8, 9, 10, 11];
const PHOTOS = { RELAY_PHOTOS_ENABLED: "true", PHOTO_TRANSFER_ENABLED: "true" };
const pairs = (chain as Any).pairs as { a: Any; b: Any }[], checkpoints = (chain as Any).checkpoints as Any[];
let requestNo = 0;
async function call(path: string, method = "GET", account?: Account, body?: unknown, overrides: Record<string, unknown> = {}, extra: Record<string, string> = {}): Promise<Response> {
  const configured: Env = withConfig({ ...env, TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + CODE), ...overrides });
  return worker.fetch(new Request("https://after-you.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.12." + (++requestNo % 250),
    ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}), ...extra }, body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function account(): Promise<Account> { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); }
async function grant(owner: Account) { expect((await call("/v1/tester-access", "POST", owner, { schema_version: 1, code: CODE })).status).toBe(200); }
async function rehash(input: Any): Promise<Any> { const body = { ...input }; delete body.checkpoint_hash; delete body.proof; return { ...input, checkpoint_hash: await digest(canonicalJson(body)) }; }
async function rerecord(input: Any): Promise<Any> { const { recording_hash: _h, ...body } = input; void _h; return { ...input, recording_hash: await digest(canonicalJson(body)) }; }
async function status(response: Response): Promise<string> { const text = await response.text(); let code = "ok"; try { code = JSON.parse(text)?.error?.code ?? "ok"; } catch { code = "?"; } return `${response.status} ${code}`; }
function unwrap<T>(result: Outcome<T>): T { if (!result.ok) throw new Error(result.code); return result.value; }
const host = "A".repeat(22), guest = "B".repeat(22), invite = "E".repeat(20);
const owner = (slot: string) => slot === "p0" ? host : guest;
async function playAll(room: DurableObjectStub<import("../src/v2/room").RoomV2>, roomId: string) {
  unwrap(await room.initialize(roomId, host, invite, sleepingLighthouseV2.key));
  let state = unwrap(await room.join(guest, invite, NSTAGE_CLIENT));
  for (const [index, pair] of pairs.entries()) {
    state = unwrap(await room.commit(owner(pair.a.player_slot), { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording: pair.a })).room;
    state = unwrap(await room.commit(owner(pair.b.player_slot), { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording: pair.b, checkpoint: checkpoints[index + 1] })).room;
  }
  return state;
}
async function jpeg() {
  const bytes = new Uint8Array(encode({ data: new Uint8Array(8 * 8 * 4).fill(127), width: 8, height: 8 }, 45).data);
  const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(v => v.toString(16).padStart(2, "0")).join("");
  return { bytes, sha256, base64: btoa(String.fromCharCode(...bytes)) };
}
afterEach(async () => { await reset(); });

describe("sleeping-lighthouse@2: one six-stage chapter", () => {
  it("bundles the Godot definition and initial checkpoint and pins rules 11", async () => {
    expect(bundledDefinition).toEqual((chain as Any).definition); expect(bundledInitial).toEqual((chain as Any).initial);
    expect(await digest(canonicalJson(bundledDefinition))).toBe(LIGHTHOUSE_V2_HASH);
    expect(sleepingLighthouseV2).toMatchObject({ premium: true, recording_version: 8, simulation_version: 11, supported_simulation_versions: [11], require_supported_simulation_on_join: true, max_branches: 7 });
    expect(sleepingLighthouseV2.stages.map(stage => stage.first_player_slot)).toEqual(["p0", "p1", "p0", "p1", "p0", "p1"]);
    expect(chapter(sleepingLighthouseV2.key)).toBe(sleepingLighthouseV2);
    expect(initialCheckpoint(sleepingLighthouseV2.key)).toEqual(checkpoints[0]);
  });

  it("never reaches a client that does not ask", async () => {
    const legacy = advertisedChapters(env);
    expect(legacy.some(entry => entry.level_id === "sleeping-lighthouse")).toBe(false);
    expect(legacy.length).toBeLessThanOrEqual(16);
    expect(legacy.every(entry => !("stage_count" in entry) && (entry.supported_simulation_versions?.length ?? 1) <= 8)).toBe(true);
    const level2 = advertisedChapters(env, 2);
    expect(level2.find(entry => entry.level_id === "sleeping-lighthouse")).toEqual({ ...sleepingLighthouseV2.key, premium: true, recording_version: 8, simulation_version: 11, supported_simulation_versions: [11], stage_count: 6 });
    expect(level2.filter(entry => entry.stage_count === 2).map(({ stage_count: _s, ...rest }) => { void _s; return rest; })).toEqual(legacy);
    const viewer = await account();
    // Headerless capabilities leave it out, and say nothing of room levels.
    const plain = await (await call("/v2/capabilities", "GET", viewer)).json<Any>();
    expect(plain).not.toHaveProperty("room_level"); expect(plain.chapters.some((entry: Any) => entry.level_id === "sleeping-lighthouse")).toBe(false);
    const asked = await (await call("/v2/capabilities", "GET", viewer, undefined, ON, { "X-AfterYou-Room-Level": "2" })).json<Any>();
    expect(asked).toMatchObject({ room_level: 2, max_join_versions: 16, max_stages: 8 }); expect(asked.chapters.some((entry: Any) => entry.level_id === "sleeping-lighthouse")).toBe(true);
  });

  it("accepts all six pairs on the shared shape and nests six proofs", async () => {
    let previous = initialCheckpoint(sleepingLighthouseV2.key) as ChapterCheckpoint;
    for (const [index, pair] of pairs.entries()) {
      const a = await recordingV2(pair.a, sleepingLighthouseV2.key) as ChapterRecording, b = await recordingV2(pair.b, sleepingLighthouseV2.key) as ChapterRecording;
      expect(acceptedRecording(a) && acceptedRecording(b)).toBe(true);
      previous = await checkpointV2(checkpoints[index + 1], previous, a, b); expect(previous).toEqual(checkpoints[index + 1]);
    }
    expect(previous.stage_index).toBe(6);
    // The real stage-6 receiver body fits the published body bound and depth 16.
    const body = { base_revision: 11, idempotency_key: crypto.randomUUID(), branch: 0, recording: pairs[5].b, checkpoint: checkpoints[6] };
    expect(() => boundedTurnValue(body)).not.toThrow(); expect(() => boundedTurnValue(body, LIGHTHOUSE_LIMITS)).not.toThrow();
    expect(LIGHTHOUSE_LIMITS.turn_body_bytes).toBeGreaterThan(327_680);
  });

  it("refuses end states the native proof could not make", async () => {
    const at = async (index: number) => ({ previous: checkpoints[index] as ChapterCheckpoint,
      a: await recordingV2(pairs[index].a, sleepingLighthouseV2.key) as ChapterRecording, b: await recordingV2(pairs[index].b, sleepingLighthouseV2.key) as ChapterRecording });
    const last = await at(5);
    const dropped = structuredClone(checkpoints[6]); delete dropped.mechanisms.flags["beacon-lit"];
    await expect(checkpointV2(await rehash(dropped), last.previous, last.a, last.b)).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
    const unlatched = structuredClone(checkpoints[6]); unlatched.mechanisms.latched_bridges = unlatched.mechanisms.latched_bridges.filter((id: string) => id !== "rest-tower");
    await expect(checkpointV2(await rehash(unlatched), last.previous, last.a, last.b)).rejects.toMatchObject({ code: "checkpoint_mechanism_mismatch" });
    const offIsland = structuredClone(checkpoints[6]); offIsland.players.p0 = { ...offIsland.players.p0, x: 5000 };
    await expect(checkpointV2(await rehash(offIsland), last.previous, last.a, last.b)).rejects.toMatchObject({ code: "checkpoint_surface_mismatch" });
    const turned = structuredClone(checkpoints[6]); turned.mechanisms.mirrors["court-mirror"] = "backslash";
    await expect(checkpointV2(await rehash(turned), last.previous, last.a, last.b)).rejects.toMatchObject({ code: "checkpoint_mechanism_mismatch" });
    const lifted = structuredClone(checkpoints[6]); lifted.players.p1 = { ...lifted.players.p1, height: 48 };
    await expect(checkpointV2(await rehash(lifted), last.previous, last.a, last.b)).rejects.toMatchObject({ code: "checkpoint_surface_mismatch" });
    const stage2 = await at(1);
    const unfitted = structuredClone(checkpoints[2]); unfitted.mechanisms.props["portable-lens"].status = "held";
    await expect(checkpointV2(await rehash(unfitted), stage2.previous, stage2.a, stage2.b)).rejects.toMatchObject({ code: "checkpoint_goal_mismatch" });
    await expect(checkpointV2(structuredClone(checkpoints[3]), stage2.previous, stage2.a, stage2.b)).rejects.toMatchObject({ code: "checkpoint_stage_mismatch" });
    await expect(checkpointV2(checkpoints[2], stage2.previous, stage2.b, stage2.a)).rejects.toMatchObject({ code: "checkpoint_recording_mismatch" });
    const long = structuredClone(pairs[0].a); long.actions.push({ ticks: 600, x: 0, z: 0, action: false }); long.duration_ticks += 600;
    long.replay_checks.push({ tick: long.duration_ticks, state_hash: long.final_state_hash });
    await expect(recordingV2(await rerecord(long), sleepingLighthouseV2.key)).rejects.toThrow();
    const rules9 = await rerecord({ ...structuredClone(pairs[0].a), simulation_version: 9 });
    await expect(recordingV2(rules9, sleepingLighthouseV2.key)).rejects.toMatchObject({ code: "unsupported_simulation_version" });
    const wrongSlot = await rerecord({ ...structuredClone(pairs[1].a), player_slot: "p0" });
    await expect(recordingV2(wrongSlot, sleepingLighthouseV2.key)).rejects.toMatchObject({ code: "wrong_player_slot" });
  });

  it("plays a six-stage room to completion, exports and restores it, and forks back", async () => {
    const room = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    unwrap(await room.initialize("c".repeat(22), host, invite, sleepingLighthouseV2.key));
    expect(await room.join(guest, invite, OLD_CLIENT)).toMatchObject({ ok: false, code: "unsupported_simulation_version" });
    let state = unwrap(await room.join(guest, invite, NSTAGE_CLIENT));
    expect(await room.stageCount()).toBe(6);
    for (const [index, pair] of pairs.entries()) {
      expect(state).toMatchObject({ stage_index: index, active_role: "a", stage_id: sleepingLighthouseV2.stages[index].id, active_player_id: owner(pair.a.player_slot) });
      state = unwrap(await room.commit(owner(pair.a.player_slot), { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording: pair.a })).room;
      const done: MutationV2 = unwrap(await room.commit(owner(pair.b.player_slot), { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording: pair.b, checkpoint: checkpoints[index + 1] }));
      expect(done.receipt).toMatchObject({ stage_index: index, pair_id: `p0-${index}`, turn_id: `t0-${index}-b` });
      state = done.room;
    }
    expect(state).toMatchObject({ stage_index: 6, active_role: "complete", active_player_id: null, stage_id: "" });
    expect(state.checkpoint).toEqual(checkpoints[6]); expect(state.completed_pair_ids).toEqual(["p0-0", "p0-1", "p0-2", "p0-3", "p0-4", "p0-5"]);
    expect(unwrap(await room.collection(host)).pairs.map(pair => pair.stage_index)).toEqual([0, 1, 2, 3, 4, 5]);
    expect(unwrap(await room.pairRecording(guest, "p0-5")).checkpoint).toEqual(checkpoints[6]);
    const archive = unwrap(await room.exportSnapshot("d".repeat(40)));
    const target = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()); expect(await target.restoreSnapshot(archive, "c".repeat(22))).toMatchObject({ ok: true });
    expect(JSON.parse(unwrap(await target.exportSnapshot("d".repeat(40)))).payload.tables).toEqual(JSON.parse(archive).payload.tables);
    const forked = unwrap(await room.fork(host, { base_revision: state.revision, branch: state.branch, stage_index: 3, idempotency_key: crypto.randomUUID() }));
    expect(forked.room).toMatchObject({ stage_index: 3, branch: 1, active_role: "a", stage_id: "after-the-first-bell", active_player_id: guest });
  });

  it("caps a six-stage room at seven branches", async () => {
    const room = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
    unwrap(await room.initialize("f".repeat(22), host, invite, sleepingLighthouseV2.key));
    let state = unwrap(await room.join(guest, invite, NSTAGE_CLIENT));
    for (let branch = 0; branch < LIGHTHOUSE_MAX_BRANCHES - 1; branch++) {
      state = unwrap(await room.commit(host, { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording: pairs[0].a })).room;
      state = unwrap(await room.fork(guest, { base_revision: state.revision, branch: state.branch, stage_index: 0, idempotency_key: crypto.randomUUID() })).room;
    }
    expect(state.branch).toBe(LIGHTHOUSE_MAX_BRANCHES - 1);
    state = unwrap(await room.commit(host, { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording: pairs[0].a })).room;
    expect(await room.fork(guest, { base_revision: state.revision, branch: state.branch, stage_index: 0, idempotency_key: crypto.randomUUID() })).toMatchObject({ ok: false, status: 409, code: "room_history_full" });
  });

  it("transfers a completed six-stage room, keeps its stage count once compacted, and restores it", async () => {
    const roomId = "t".repeat(22), done = env.ROOMS_V2.getByName(roomId);
    await playAll(done, roomId);
    const transfer = unwrap(await done.replayTransfer(host, true));
    expect(transfer.archive!.turns.length).toBe(12); expect(transfer.archive!.pairs.length).toBe(6);
    expect(() => validateTransfer({ schema_version: 1, manifest: transfer.manifest, acked_player_ids: transfer.acked_player_ids, transferred: transfer.transferred })).not.toThrow();
    const ack = { schema_version: 1, epoch: transfer.manifest.epoch, archive_hash: transfer.manifest.archive_hash };
    unwrap(await done.acknowledgeReplayTransfer(host, ack));
    expect(unwrap(await done.acknowledgeReplayTransfer(guest, ack))).toMatchObject({ transferred: true, acked_player_ids: [host, guest] });
    expect(await done.snapshot(host)).toMatchObject({ ok: false, status: 410, code: "replay_transferred" });
    expect(await done.stageCount()).toBe(6);
    // An account photo transfer still names the compacted room's later stages.
    const sender = await account(), image = await jpeg(), session = crypto.randomUUID();
    expect((await call("/v1/photo-transfer/sessions", "POST", sender, { schema_version: 1, idempotency_key: session }, PHOTOS)).status).toBe(200);
    const entry = (turn: string, id: string) => ({ entry_id: id.repeat(64), room_id: roomId, turn_id: turn, recording_hash: "a".repeat(64), photo_revision: 0, photo_owner: sender.player_id,
      local_only: true, sha256: image.sha256, width: 8, height: 8, byte_length: image.bytes.length, created_at: new Date().toISOString(), jpeg_base64: image.base64, deleted: false });
    const upload = (entries: unknown[]) => call(`/v1/photo-transfer/${session}/entries`, "POST", sender, { schema_version: 1, idempotency_key: crypto.randomUUID(), entries }, PHOTOS);
    expect(await status(await upload([entry("t0-5-b", "1"), entry("t0-2-a", "2")]))).toBe("200 ok");
    expect(await status(await upload([entry("t0-6-a", "3")]))).toBe("400 invalid_field");
    const compacted = unwrap(await done.exportSnapshot("d".repeat(40)));
    const copy = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()); expect(await copy.restoreSnapshot(compacted, roomId)).toMatchObject({ ok: true });
    expect(JSON.parse(unwrap(await copy.exportSnapshot("d".repeat(40)))).payload.tables).toEqual(JSON.parse(compacted).payload.tables);
    expect(unwrap(await done.restoreReplayTransfer(host, { ...ack, archive: transfer.archive }))).toMatchObject({ restored: true });
    const live = unwrap(await done.snapshot(guest));
    expect(live).toMatchObject({ stage_index: 6, active_role: "complete" }); expect(live.checkpoint).toEqual(checkpoints[6]);
    expect(unwrap(await done.pairRecording(host, "p0-5")).checkpoint).toEqual(checkpoints[6]);
  });

  it("plays over HTTP, and reports and transfers photos of later stages", async () => {
    const creator = await account(), friend = await account(), other = await account(); await grant(creator);
    for (const player of [creator, friend]) expect((await call("/v1/safety/terms", "POST", player, { schema_version: 1, terms_version: TERMS_VERSION }, PHOTOS)).status).toBe(200);
    const created = await call("/v2/rooms", "POST", creator, { ...sleepingLighthouseV2.key, idempotency_key: crypto.randomUUID() }, ON);
    expect(created.status).toBe(200); const room = await created.json<RoomSnapshotV2>();
    expect((await call("/v2/rooms/join", "POST", other, { invite_code: room.invite_code, supported_simulation_versions: Array.from({ length: 17 }, (_, i) => i + 1) }, ON)).status).toBe(422);
    expect(await status(await call("/v2/rooms/join", "POST", other, { invite_code: room.invite_code, supported_simulation_versions: OLD_CLIENT }, ON))).toBe("422 unsupported_simulation_version");
    const joined = await call("/v2/rooms/join", "POST", friend, { invite_code: room.invite_code, supported_simulation_versions: NSTAGE_CLIENT }, ON);
    expect(joined.status).toBe(200);
    let seated = await joined.json<RoomSnapshotV2>();
    const who = (slot: string) => slot === "p0" ? creator : friend;
    for (const [index, pair] of pairs.entries()) {
      const ra = await call(`/v2/rooms/${seated.room_id}/turns`, "POST", who(pair.a.player_slot), { base_revision: seated.revision, branch: seated.branch, idempotency_key: crypto.randomUUID(), recording: pair.a }, ON);
      expect(ra.status).toBe(200); seated = (await ra.json<MutationV2>()).room;
      const rb = await call(`/v2/rooms/${seated.room_id}/turns`, "POST", who(pair.b.player_slot), { base_revision: seated.revision, branch: seated.branch, idempotency_key: crypto.randomUUID(), recording: pair.b, checkpoint: checkpoints[index + 1] }, ON);
      expect(rb.status).toBe(200); seated = (await rb.json<MutationV2>()).room;
    }
    expect(seated).toMatchObject({ stage_index: 6, active_role: "complete" });
    const path = `/v2/rooms/${seated.room_id}`;
    expect((await call(`${path}/pairs/p0-5`, "GET", creator, undefined, ON)).status).toBe(200);
    expect(await status(await call(`${path}/pairs/p0-6`, "GET", creator, undefined, ON))).toBe("400 invalid_field");
    expect(await status(await call(`${path}/photos/t0-6-a`, "GET", creator, undefined, ON))).toBe("400 invalid_photo_turn");
    // The friend recorded stage 4's A (t0-3-a); the host reports that photo.
    const image = await jpeg();
    const photo = await call(`${path}/photos/t0-3-a`, "POST", friend, { idempotency_key: crypto.randomUUID(), recording_hash: pairs[3].a.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, jpeg_base64: image.base64, sha256: image.sha256 }, { ...ON, ...PHOTOS });
    expect(photo.status).toBe(200);
    const report = (turn: string) => ({ schema_version: 1, idempotency_key: crypto.randomUUID(), room_family: "relay", room_id: seated.room_id, reason: "privacy", photo: { turn_id: turn, photo_revision: 1, sha256: image.sha256 } });
    expect(await status(await call("/v1/safety/report", "POST", creator, report("t0-3-a"), PHOTOS))).toBe("200 ok");
    expect(await status(await call("/v1/safety/report", "POST", creator, report("t0-6-a"), PHOTOS))).toBe("400 invalid_field");
    expect(await status(await call("/v1/safety/report", "POST", creator, report("t0-8-a"), PHOTOS))).toBe("400 invalid_field");
    // Legacy rooms keep the published grammar and its error order.
    expect(await status(await call("/v1/safety/report", "POST", creator, { ...report("t0-4-a"), room_family: "legacy" }, PHOTOS))).toBe("400 invalid_field");
    expect(await status(await call("/v1/safety/report", "POST", creator, { ...report("t0-1-a"), room_family: "legacy" }, PHOTOS))).toBe("400 invalid_safety_request");
    // The stored report reads back (receipts and listing use the full grammar).
    const listed = await env.SAFETY_INBOX.getByName("moderation-v1").listReports();
    expect(listed.map(row => row.photo?.turn_id)).toEqual(["t0-3-a"]);
    // Account photo transfer names the room's later stages, and only those.
    const session = crypto.randomUUID();
    expect((await call("/v1/photo-transfer/sessions", "POST", friend, { schema_version: 1, idempotency_key: session }, PHOTOS)).status).toBe(200);
    const entry = (turn: string, id: string) => ({ entry_id: id.repeat(64), room_id: seated.room_id, turn_id: turn, recording_hash: pairs[3].a.recording_hash, photo_revision: 0, photo_owner: friend.player_id,
      local_only: true, sha256: image.sha256, width: 8, height: 8, byte_length: image.bytes.length, created_at: new Date().toISOString(), jpeg_base64: image.base64, deleted: false });
    const upload = (entries: unknown[]) => call(`/v1/photo-transfer/${session}/entries`, "POST", friend, { schema_version: 1, idempotency_key: crypto.randomUUID(), entries }, PHOTOS);
    expect(await status(await upload([entry("t0-3-a", "1"), entry("t0-5-b", "2")]))).toBe("200 ok");
    expect(await status(await upload([entry("t0-6-a", "3")]))).toBe("400 invalid_field");
    expect(await status(await upload([entry("t0-7-b", "4")]))).toBe("400 invalid_field");
    // A deleted room has no chapter left to read, so its later stages keep the published refusal.
    expect((await call(path, "DELETE", creator, undefined, ON)).status).toBe(200);
    expect(await status(await upload([entry("t0-4-a", "5")]))).toBe("400 invalid_field");
    expect(await status(await upload([entry("t0-1-a", "6")]))).toBe("200 ok");
  });
});
