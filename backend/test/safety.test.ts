import { env } from "cloudflare:workers";
import { reset, runInDurableObject, evictDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { encode } from "jpeg-js";
import worker from "../src/index";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { TERMS_VERSION } from "../src/public-policy";
import { REPORT_TTL, type SafetyReport, type ReportBody } from "../src/safety";
import { RELAY_KEY } from "../src/v2/protocol";
import type { RoomSnapshotV2 } from "../src/v2/room";
import firstA from "../../game/tests/fixtures/v2/relay-a.json";
type Account = { player_id: string; device_token: string; recovery_code: string };
let address = 0;
const realNow = Date.now.bind(Date);
const value = <T>(result: Outcome<T>): T => { if (!result.ok) throw new Error(result.code); return result.value; };
async function call(path: string, method = "GET", account?: Account, body?: unknown) {
  return worker.fetch(new Request("https://game.test" + path, { method, headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.19.0." + ++address, ...(account ? { "X-Player-Id": account.player_id, Authorization: "Bearer " + account.device_token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), { ...env, V2_ROOMS_ENABLED: "true", RELAY_PHOTOS_ENABLED: "true", SAFETY_ENFORCEMENT_ENABLED: "true" } as unknown as Env);
}
const create = async () => { const response = await call("/v1/identity", "POST", undefined, {}); expect(response.status).toBe(201); return response.json<Account>(); };
async function operator(path: string, body?: unknown, token = "o".repeat(43)) {
  return worker.fetch(new Request("https://game.test/operator/safety/" + path, { method: body === undefined ? "GET" : "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.21.0." + ++address, Authorization: "Bearer " + token }, body: body === undefined ? undefined : JSON.stringify(body) }), { ...env, SAFETY_OPERATOR_TOKEN: "o".repeat(43) } as Env);
}
async function pair(family = "relay") {
  const host = await create(), guest = await create(); const prefix = family === "relay" ? "/v2/rooms" : "/v1/rooms";
  const room = await (await call(prefix, "POST", host, { idempotency_key: crypto.randomUUID(), ...(family === "relay" ? RELAY_KEY : {}) })).json<RoomSnapshotV2>();
  expect((await call(prefix + "/join", "POST", guest, { invite_code: room.invite_code })).status).toBe(200);
  return { host, guest, room, path: prefix + "/" + room.room_id, target: { schema_version: 1, room_family: family, room_id: room.room_id } };
}
async function report(owner = "a".repeat(22), key = crypto.randomUUID(), created_at = Date.now()): Promise<SafetyReport> {
  const player = env.PLAYERS.getByName(owner); if (!await player.authorize("d".repeat(64))) value(await player.create(owner, "d".repeat(64), "e".repeat(64)));
  const body: ReportBody = { schema_version: 1, idempotency_key: key, room_family: "relay", room_id: "r".repeat(22), reason: "harassment", photo: null };
  return { ...body, reporter_id: owner, target_id: "b".repeat(22), request_hash: await digest(canonicalJson({ operation: "safety_report", reporter_id: owner, ...body })), report_id: await digest(owner + ":" + key), created_at, resolved_at: null };
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });
describe("public policies and authenticated safety", () => {
  it("serves standalone public HTML with deletion contact and no account or script requirement", async () => {
    for (const path of ["/privacy", "/account-deletion", "/community-rules"]) {
      const r = await call(path); expect(r.status).toBe(200); expect(r.headers.get("content-type")).toContain("text/html");
      const body = await r.text(); expect(body).toContain("hackathon-shipaton@aamirazeez.com"); expect(body).not.toContain("<script");
      expect((await call(path, "HEAD")).body).toBeNull(); expect((await call(path, "POST")).status).toBe(405);
    }
    expect((await call("/v1/safety/config")).status).toBe(401);
  });
  it("requires explicit exact rules acceptance and preserves its first date across retry/eviction", async () => {
    const a = await create(); const config = await (await call("/v1/safety/config", "GET", a)).json();
    expect(config).toEqual({ schema_version: 1, enforced: true, terms_version: TERMS_VERSION, privacy_path: "/privacy", deletion_path: "/account-deletion", rules_path: "/community-rules" });
    expect(await (await call("/v1/safety/terms", "GET", a)).json()).toMatchObject({ accepted: false, accepted_at: null });
    expect((await call("/v1/safety/terms", "POST", a, { schema_version: 1, terms_version: "future" })).status).toBe(409);
    const body = { schema_version: 1, terms_version: TERMS_VERSION }; const accepted = await (await call("/v1/safety/terms", "POST", a, body)).json();
    await evictDurableObject(env.SAFETY_PROFILES.getByName(a.player_id));
    expect(await (await call("/v1/safety/terms", "POST", a, body)).json()).toEqual(accepted);
    expect((await call("/v1/safety/terms", "POST", a, { ...body, accepted_at: "forged" })).status).toBe(400);
  });
  it.each(["legacy", "relay"])("blocks both directions and rejoin for %s, while allowing deletion and explicit unblock", async family => {
    const p = await pair(family); const before = await (await call(p.path, "GET", p.host)).json();
    const outsider = await create(); expect((await call("/v1/safety/block", "POST", outsider, p.target)).status).toBe(404);
    const blocked = await call("/v1/safety/block", "POST", p.guest, p.target); expect(await blocked.json()).toEqual({ schema_version: 1, blocked: true, player_id: p.host.player_id });
    for (const a of [p.host, p.guest]) { expect((await call(p.path, "GET", a)).status).toBe(403); expect((await call(p.path + "/turns", "POST", a, {})).status).toBe(403); }
    expect((await call(family === "relay" ? "/v2/rooms/join" : "/v1/rooms/join", "POST", p.guest, { invite_code: p.room.invite_code })).status).toBe(403);
    expect((await call("/v1/safety/blocks/" + p.host.player_id, "DELETE", p.host)).status).toBe(400);
    expect((await call("/v1/safety/blocks/" + p.host.player_id, "DELETE", p.guest)).status).toBe(200);
    expect((await env.PLAYERS.getByName(p.guest.player_id).listRooms()).some(link => link.room_id === p.room.room_id)).toBe(true);
    expect(await (await call(p.path, "GET", p.host)).json()).toEqual(before);
    expect((await call("/v1/safety/block", "POST", p.guest, p.target)).status).toBe(200);
    expect((await call(p.path, "DELETE", p.host)).status).toBe(200);
  });
  it("keeps photos optional: rejected terms/upload leaves accepted gameplay unchanged; own deletion remains possible while blocked", async () => {
    const p = await pair(); const stub = env.ROOMS_V2.getByName(p.room.room_id); const joined = value(await stub.snapshot(p.host.player_id));
    const accepted = value(await stub.commit(p.host.player_id, { base_revision: joined.revision, branch: 0, idempotency_key: crypto.randomUUID(), recording: firstA }));
    const bytes = new Uint8Array(encode({ width: 2, height: 2, data: new Uint8Array(16).fill(120) }, 40).data); let raw = ""; for (const byte of bytes) raw += String.fromCharCode(byte);
    const body = { idempotency_key: crypto.randomUUID(), recording_hash: firstA.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, jpeg_base64: btoa(raw), sha256: [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(x => x.toString(16).padStart(2, "0")).join("") };
    const path = p.path + "/photos/t0-0-a";
    expect((await call(path, "POST", p.host, body)).status).toBe(403);
    expect(value(await stub.snapshot(p.host.player_id))).toEqual(accepted.room);
    expect((await call("/v1/safety/terms", "POST", p.host, { schema_version: 1, terms_version: TERMS_VERSION })).status).toBe(200);
    const upload = await call(path, "POST", p.host, body); expect(upload.status).toBe(200);
    expect((await call("/v1/safety/block", "POST", p.guest, p.target)).status).toBe(200);
    expect((await call(path, "GET", p.guest)).status).toBe(403);
    expect((await call(path, "DELETE", p.host, { idempotency_key: crypto.randomUUID(), recording_hash: firstA.recording_hash, expected_photo_revision: 1, expected_photo_hash: body.sha256 })).status).toBe(200);
    expect(value(await stub.snapshot(p.host.player_id))).toEqual(accepted.room);
  });
  it("binds report receipts to caller and exact intent, including retry after the room is deleted", async () => {
    const p = await pair(); const body = { ...p.target, idempotency_key: crypto.randomUUID(), reason: "harassment", photo: null };
    const response = await call("/v1/safety/report", "POST", p.guest, body); expect(response.status).toBe(200); const receipt = await response.json<{ request_hash: string; report_id: string }>();
    expect(receipt.request_hash).toBe(await digest(canonicalJson({ operation: "safety_report", reporter_id: p.guest.player_id, ...body })));
    expect(receipt.report_id).toBe(await digest(p.guest.player_id + ":" + body.idempotency_key));
    expect((await call("/v1/safety/reports/" + body.idempotency_key, "GET", p.host)).status).toBe(404);
    expect((await call("/v1/safety/report", "POST", p.guest, { ...body, reason: "privacy" })).status).toBe(409);
    await call(p.path, "DELETE", p.host);
    expect(await (await call("/v1/safety/report", "POST", p.guest, body)).json()).toEqual(receipt);
    expect(await (await call("/v1/safety/reports/" + body.idempotency_key, "GET", p.guest)).json()).toEqual(receipt);
  });
  it("rejects nonmember, arbitrary target/text and changed photo evidence", async () => {
    const p = await pair(); const body = { ...p.target, idempotency_key: crypto.randomUUID(), reason: "privacy", photo: null };
    expect((await call("/v1/safety/report", "POST", await create(), body)).status).toBe(404);
    expect((await call("/v1/safety/report", "POST", p.guest, { ...body, text: "arbitrary" })).status).toBe(400);
    expect((await call("/v1/safety/report", "POST", p.guest, { ...body, photo: { turn_id: "t0-0-a", photo_revision: 1, sha256: "a".repeat(64) } })).status).toBe(404);
  });
  it("lets only the authenticated operator review, block and remove the exact reported photo with a retry-safe receipt", async () => {
    const p = await pair(); const stub = env.ROOMS_V2.getByName(p.room.room_id); const joined = value(await stub.snapshot(p.host.player_id));
    const accepted = value(await stub.commit(p.host.player_id, { base_revision: joined.revision, branch: 0, idempotency_key: crypto.randomUUID(), recording: firstA }));
    const bytes = new Uint8Array(encode({ width: 2, height: 2, data: new Uint8Array(16).fill(150) }, 40).data); let raw = ""; for (const byte of bytes) raw += String.fromCharCode(byte);
    const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(x => x.toString(16).padStart(2, "0")).join("");
    const upload = { idempotency_key: crypto.randomUUID(), recording_hash: firstA.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, jpeg_base64: btoa(raw), sha256 };
    value(await stub.updatePhoto(p.host.player_id, "t0-0-a", upload));
    const body = { ...p.target, idempotency_key: crypto.randomUUID(), reason: "privacy", photo: { turn_id: "t0-0-a", photo_revision: 1, sha256 } };
    const response = await call("/v1/safety/report", "POST", p.guest, body); expect(response.status).toBe(200); const receipt = await response.json<{ report_id: string }>();
    expect((await operator("reports", undefined, p.host.device_token)).status).toBe(401);
    const listing = await (await operator("reports")).json<{ reports: SafetyReport[] }>(); expect(listing.reports).toHaveLength(1); expect(JSON.stringify(listing)).not.toContain("jpeg_base64");
    const path = "reports/" + receipt.report_id;
    expect((await operator(path + "/remove-photo", { schema_version: 1, photo_revision: 2, sha256 })).status).toBe(409);
    const deletion = { schema_version: 1, photo_revision: 1, sha256 };
    expect(await (await operator(path + "/remove-photo", deletion)).json()).toEqual({ schema_version: 1, removed: true });
    expect(value(await stub.photo(p.guest.player_id, "t0-0-a")).jpeg_base64).toBeNull();
    value(await stub.updatePhoto(p.host.player_id, "t0-0-a", { ...upload, idempotency_key: crypto.randomUUID(), expected_photo_revision: 2 }));
    expect((await operator(path + "/remove-photo", deletion)).status).toBe(200);
    expect(value(await stub.photo(p.guest.player_id, "t0-0-a")).jpeg_base64).toBe(upload.jpeg_base64);
    expect((await operator(path + "/block", { schema_version: 1 })).status).toBe(200);
    expect((await call(p.path, "GET", p.host)).status).toBe(403);
    expect((await operator(path + "/resolve", { schema_version: 1 })).status).toBe(200);
    expect(value(await stub.snapshot(p.host.player_id))).toEqual(accepted.room);
  });
  it("rejects a player-created moderation-looking receipt for another photo revision", async () => {
    const p = await pair(); const stub = env.ROOMS_V2.getByName(p.room.room_id); const joined = value(await stub.snapshot(p.host.player_id));
    value(await stub.commit(p.host.player_id, { base_revision: joined.revision, branch: 0, idempotency_key: crypto.randomUUID(), recording: firstA }));
    const bytes = new Uint8Array(encode({ width: 2, height: 2, data: new Uint8Array(16).fill(130) }, 40).data); let raw = ""; for (const byte of bytes) raw += String.fromCharCode(byte);
    const sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(x => x.toString(16).padStart(2, "0")).join("");
    const upload = { idempotency_key: crypto.randomUUID(), recording_hash: firstA.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, jpeg_base64: btoa(raw), sha256 };
    value(await stub.updatePhoto(p.host.player_id, "t0-0-a", upload));
    const reportKey = crypto.randomUUID(), reportId = await digest(p.guest.player_id + ":" + reportKey);
    value(await stub.updatePhoto(p.host.player_id, "t0-0-a", { idempotency_key: "moderation_" + reportId, recording_hash: firstA.recording_hash, expected_photo_revision: 1, expected_photo_hash: sha256 }, true));
    value(await stub.updatePhoto(p.host.player_id, "t0-0-a", { ...upload, idempotency_key: crypto.randomUUID(), expected_photo_revision: 2 }));
    expect((await call("/v1/safety/report", "POST", p.guest, { ...p.target, idempotency_key: reportKey, reason: "privacy", photo: { turn_id: "t0-0-a", photo_revision: 3, sha256 } })).status).toBe(200);
    expect((await operator("reports/" + reportId + "/remove-photo", { schema_version: 1, photo_revision: 3, sha256 })).status).toBe(409);
    expect(value(await stub.photo(p.guest.player_id, "t0-0-a")).photo?.photo_revision).toBe(3);
    expect(value(await env.SAFETY_INBOX.getByName("moderation-v1").getReport(reportId)).resolved_at).toBeNull();
  });
});
describe("bounded safety retention and portable state", () => {
  it("removes a late report inserted after deletion consumed the reporter's cleanup", async () => {
    const item = await report(); const inbox = env.SAFETY_INBOX.getByName("moderation-v1");
    await runInDurableObject(inbox, async (instance, ctx) => {
      const settings = (instance as unknown as { env: { PLAYERS: Env["PLAYERS"] } }).env;
      const original = settings.PLAYERS, player = original.getByName(item.reporter_id);
      let calls = 0, observedLateInsert = false;
      settings.PLAYERS = { getByName: () => ({
        authorize: async (hash: string) => {
          const authorized = await player.authorize(hash); calls++;
          if (calls === 1) { expect((await player.beginDelete()).ok).toBe(true); expect((await instance.eraseReporter(item.reporter_id)).ok).toBe(true); }
          else observedLateInsert = ctx.storage.sql.exec("SELECT report_id FROM safety_reports").toArray().length === 1;
          return authorized;
        }, safetyIdentityActive: (owner: string) => player.safetyIdentityActive(owner)
      }) } as unknown as Env["PLAYERS"];
      try {
        expect(await instance.submit(item, "d".repeat(64))).toMatchObject({ ok: false, status: 401 });
        expect(observedLateInsert).toBe(true); expect(ctx.storage.sql.exec("SELECT report_id FROM safety_reports").toArray()).toHaveLength(0);
      } finally { settings.PLAYERS = original; }
    });
  });
  it("caps daily reports, permits exact retry and expires metadata without a photo copy", async () => {
    vi.spyOn(Date, "now").mockReturnValue(realNow() + 3600000);
    const inbox = env.SAFETY_INBOX.getByName("moderation-v1"); const first = await report();
    for (let i = 0; i < 10; i++) expect((await inbox.submit(i ? await report() : first, "d".repeat(64))).ok).toBe(true);
    expect(await inbox.submit(await report(), "d".repeat(64))).toMatchObject({ ok: false, status: 429 });
    expect(await inbox.submit(first, "d".repeat(64))).toMatchObject({ ok: true });
    const archive = await inbox.exportSnapshot(); expect(archive).not.toContain("jpeg_base64");
    vi.spyOn(Date, "now").mockReturnValue(first.created_at + REPORT_TTL + 1);
    expect(await inbox.reportReceipt(first.reporter_id, first.idempotency_key)).toMatchObject({ ok: false, status: 404 });
  });
  it("round trips exact safety state separately and holds on unknown schemas/alarms", async () => {
    const a = await create(); const original = env.SAFETY_PROFILES.getByName(a.player_id); await original.accept(a.player_id, await digest(a.device_token), TERMS_VERSION);
    const archive = await original.exportSnapshot(a.player_id); const restored = env.SAFETY_PROFILES.get(env.SAFETY_PROFILES.newUniqueId());
    expect(await restored.restoreSnapshot(a.player_id, archive)).toEqual({ ok: true, value: { restored: true } });
    expect(await restored.terms(a.player_id)).toEqual(await original.terms(a.player_id));
    expect((await restored.restoreSnapshot(a.player_id, archive)).ok).toBe(false);
    await runInDurableObject(restored, async (_, ctx) => { ctx.storage.sql.exec("CREATE TABLE unknown_state (data TEXT)"); });
    await runInDurableObject(restored, async instance => {
      let code = ""; try { await instance.exportSnapshot(a.player_id); } catch (error) { code = (error as Error).message; } expect(code).toBe("unsupported_safety_storage");
      expect(() => instance.terms(a.player_id)).toThrow("unsupported_safety_storage");
    });
    const alarmed = env.SAFETY_PROFILES.get(env.SAFETY_PROFILES.newUniqueId());
    await runInDurableObject(alarmed, async (_, ctx) => { await ctx.storage.setAlarm(Date.now() + 3600000); });
    await runInDurableObject(alarmed, async instance => { let code = ""; try { await instance.exportSnapshot(a.player_id); } catch (error) { code = (error as Error).message; } expect(code).toBe("unsupported_safety_alarm"); });
  });
  it("restores report receipts, rejects checksum-valid forged intent, and erases only the deleting reporter", async () => {
    const inbox = env.SAFETY_INBOX.getByName("moderation-v1"), first = await report(), other = await report("c".repeat(22));
    value(await inbox.submit(first, "d".repeat(64))); value(await inbox.submit(other, "d".repeat(64)));
    const archive = await inbox.exportSnapshot(); const restored = env.SAFETY_INBOX.get(env.SAFETY_INBOX.newUniqueId()); expect((await restored.restoreSnapshot(archive)).ok).toBe(true);
    expect(await restored.reportReceipt(first.reporter_id, first.idempotency_key)).toEqual(await inbox.reportReceipt(first.reporter_id, first.idempotency_key));
    await restored.eraseReporter(first.reporter_id); expect(await restored.listReports()).toEqual([other]);
    const forged = JSON.parse(archive); forged.payload.reports[0].reason = "other"; forged.checksum = await digest(canonicalJson(forged.payload));
    expect((await env.SAFETY_INBOX.get(env.SAFETY_INBOX.newUniqueId()).restoreSnapshot(canonicalJson(forged))).ok).toBe(false);
  });
});
