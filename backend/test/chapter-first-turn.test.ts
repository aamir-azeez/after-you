import { env } from "cloudflare:workers";
import { reset } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest } from "../src/protocol";
import { TESTER_CODE_DOMAIN } from "../src/tester-access";
import { chapter } from "../src/v2/protocol";
import type { ChapterCheckpoint, ChapterRecording } from "../src/v2/chapter-types";
import type { MutationV2, RoomSnapshotV2 } from "../src/v2/room";
import native from "../../game/tests/fixtures/comfort8/recordings.json";

type Account = { player_id: string; device_token: string };
type Proof = { pairs: { a: ChapterRecording; b: ChapterRecording }[]; checkpoints: ChapterCheckpoint[] };
const proofs = native as unknown as Record<string, Proof>;
const chapters = ["rolling-home", "a-house-for-two", "long-way-home"];
const code = "SYNTHETIC-FIRST-TURN-HOST";
let requestNo = 0;
async function call(path: string, method = "GET", owner?: Account, body?: unknown) {
  const configured: Env = { ...env };
  Object.assign(configured, { V2_ROOMS_ENABLED: "true", COOP_CHAPTERS_ENABLED: "true", HOUSE_CHAPTER_ENABLED: "true", JOURNEY_CHAPTERS_ENABLED: "true",
    TESTER_ACCESS_ENABLED: "true", TESTER_CODE_SHA256: await digest(TESTER_CODE_DOMAIN + code),
    REVENUECAT_VERIFICATION_MODE: "play_store", REVENUECAT_SECRET_KEY: "synthetic-only", REVENUECAT_PROJECT_ID: "projSynthetic",
    REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID: "entlPlay", REVENUECAT_PLAY_PRODUCT_ID: "prodPlay", REVENUECAT_PLAY_ENVIRONMENT: "production" });
  return worker.fetch(new Request("https://after-you.test" + path, { method,
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.18.17." + ++requestNo,
      ...(owner ? { "X-Player-Id": owner.player_id, Authorization: "Bearer " + owner.device_token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) }), configured);
}
async function account(): Promise<Account> {
  const response = await call("/v1/identity", "POST", undefined, {});
  expect(response.status).toBe(201); return response.json<Account>();
}
async function create(name: string) {
  const host = await account(), guest = await account(), proof = proofs[name];
  expect((await call("/v1/tester-access", "POST", host, { schema_version: 1, code })).status).toBe(200);
  expect(await env.PLAYERS.getByName(guest.player_id).storedTesterGrant(guest.player_id)).toBeNull();
  const reply = await call("/v2/rooms", "POST", host, { ...chapter(proof.pairs[0].a).key, simulation_version: 8, idempotency_key: crypto.randomUUID() });
  expect(reply.status).toBe(200);
  return { host, guest, proof, room: await reply.json<RoomSnapshotV2>() };
}
function turn(room: RoomSnapshotV2, recording: ChapterRecording, checkpoint?: ChapterCheckpoint) {
  return { base_revision: room.revision, branch: room.branch, idempotency_key: crypto.randomUUID(), recording, ...(checkpoint ? { checkpoint } : {}) };
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("first-turn arrival and host access", () => {
  it.each(chapters)("allows an unentitled guest to join and finish both %s pairs using only the host grant", async name => {
    const provider = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("Provider unavailable"));
    const { host, guest, proof, room: waiting } = await create(name);
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: waiting.invite_code, supported_simulation_versions: [8] });
    expect(joined.status).toBe(200); let room = await joined.json<RoomSnapshotV2>();
    for (const [index, pair] of proof.pairs.entries()) {
      for (const recording of [pair.a, pair.b]) {
        const actor = recording.player_slot === "p0" ? host : guest;
        const response = await call(`/v2/rooms/${room.room_id}/turns`, "POST", actor, turn(room, recording, recording.role === "b" ? proof.checkpoints[index + 1] : undefined));
        expect(response.status).toBe(200); room = (await response.json<MutationV2>()).room;
      }
    }
    expect(room.active_role).toBe("complete");
    expect(await env.PLAYERS.getByName(guest.player_id).storedTesterGrant(guest.player_id)).toBeNull();
    expect(provider).not.toHaveBeenCalled();
  });

  it.each(chapters.flatMap(name => [false, true].map(dense => ({ name, dense }))))("preserves exact revision fencing for a guest arriving during $name A (dense=$dense)", async ({ name, dense }) => {
    const { host, guest, proof, room: waiting } = await create(name);
    let recording = structuredClone(proof.pairs[0].a);
    if (dense) {
      // Structural-envelope stress only: these uncompressed controls preserve
      // the input sequence, but this server does not attest native replay.
      recording.actions = recording.actions.flatMap(action => Array.from({ length: action.ticks }, () => ({ ...action, ticks: 1 })));
      const { recording_hash: ignored, ...body } = recording; void ignored;
      recording = { ...body, recording_hash: await digest(canonicalJson(body)) };
      expect(recording.actions.length).toBe(recording.duration_ticks);
    }
    const original = turn(waiting, recording);
    const joined = await call("/v2/rooms/join", "POST", guest, { invite_code: waiting.invite_code, supported_simulation_versions: [8] });
    expect(joined.status).toBe(200); const current = await joined.json<RoomSnapshotV2>();
    expect(current.revision).toBe(1); expect(waiting.revision).toBe(0);
    const path = `/v2/rooms/${waiting.room_id}/turns`;
    const stale = await call(path, "POST", host, original);
    expect(stale.status).toBe(409); expect(await stale.json()).toMatchObject({ error: { code: "stale_revision" } });
    const absent = await call(`/v2/rooms/${waiting.room_id}/operations/${original.idempotency_key}`, "GET", host);
    expect(absent.status).toBe(404);
    const replacement = { ...original, base_revision: current.revision, idempotency_key: crypto.randomUUID() };
    const accepted = await call(path, "POST", host, replacement);
    expect(accepted.status).toBe(200); const result = await accepted.json<MutationV2>();
    expect(result.receipt.accepted_revision).toBe(replacement.base_revision + 1);
    expect(result.room.recording_a).toEqual(recording);
    expect(await (await call(path, "POST", host, replacement)).json()).toEqual(result);
    expect((await call(path, "POST", host, original)).status).toBe(409);
  });
});
