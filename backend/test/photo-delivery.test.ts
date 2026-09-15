import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { encode } from "jpeg-js";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { validateRoomV2 } from "../src/v2/snapshot";
import a from "../../game/tests/fixtures/v2/relay-a.json";
import b from "../../game/tests/fixtures/v2/relay-b.json";
import checkpoint from "../../game/tests/fixtures/v2/relay-checkpoint.json";
const H = "H".repeat(22), G = "G".repeat(22), R = "R".repeat(22), I = "AB".repeat(10), SOURCE = "f".repeat(40);
const key = () => crypto.randomUUID();
function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(outcome.code); return outcome.value; }
async function setup() {
  const room = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()); value(await room.initialize(R, H, I)); let state = value(await room.join(G, I));
  state = value(await room.commit(H, { base_revision: state.revision, branch: 0, idempotency_key: key(), recording: a })).room;
  value(await room.commit(G, { base_revision: state.revision, branch: 0, idempotency_key: key(), recording: b, checkpoint }));
  const bytes = new Uint8Array(encode({ data: new Uint8Array(8 * 8 * 4).fill(127), width: 8, height: 8 }, 45).data);
  const jpeg_base64 = btoa(String.fromCharCode(...bytes)), sha256 = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(v => v.toString(16).padStart(2, "0")).join("");
  const upload = { idempotency_key: key(), recording_hash: a.recording_hash, expected_photo_revision: 0, expected_photo_hash: null, jpeg_base64, sha256 };
  value(await room.updatePhoto(H, "t0-0-a", upload));
  return { room, upload, ack: { recording_hash: a.recording_hash, photo_revision: 1, sha256 }, before: value(await room.snapshot(H)) };
}
afterEach(async () => { await reset(); });
describe("durable shared-photo delivery acknowledgements", () => {
  it("retains legacy bytes until both distinct intended members acknowledge and keeps exact gameplay/receipts", async () => {
    const { room, upload, ack, before } = await setup();
    expect(value(await room.photoDelivery(H, "t0-0-a"))).toMatchObject({ available: true, acked_player_ids: [], intended_player_ids: [H, G] });
    const original = value(await room.photoOperation(H, upload.idempotency_key));
    value(await room.acknowledgePhoto(H, "t0-0-a", ack)); value(await room.acknowledgePhoto(H, "t0-0-a", ack));
    expect(value(await room.photo(G, "t0-0-a")).jpeg_base64).toBe(upload.jpeg_base64);
    const final = value(await room.acknowledgePhoto(G, "t0-0-a", ack));
    expect(final).toMatchObject({ acked: true, available: false, removed_reason: "delivered", acked_player_ids: [H, G], photo: { sha256: upload.sha256, photo_revision: 1 } });
    expect(value(await room.acknowledgePhoto(G, "t0-0-a", ack))).toEqual(final);
    expect(await room.photo(H, "t0-0-a")).toMatchObject({ ok: false, status: 410, code: "photo_payload_delivered" });
    expect(value(await room.photoOperation(H, upload.idempotency_key))).toEqual(original);
    expect(value(await room.snapshot(H))).toEqual(before);
    await runInDurableObject(room, async (_, ctx) => { const row = ctx.storage.sql.exec<{ data: string }>("SELECT data FROM photos").one(); expect(JSON.parse(row.data).jpeg_base64).toBeNull(); });
  });
  it("does not admit outsiders, absent turns, wrong hashes or stale ACKs after same-bytes replacement", async () => {
    const { room, upload, ack } = await setup();
    expect(await room.acknowledgePhoto("X".repeat(22), "t0-0-a", ack)).toMatchObject({ ok: false, status: 404 });
    expect(await room.acknowledgePhoto(H, "t0-0-b", ack)).toMatchObject({ ok: false, status: 409 });
    expect(await room.acknowledgePhoto(H, "t0-0-a", { ...ack, sha256: "0".repeat(64) })).toMatchObject({ ok: false, code: "stale_photo_ack" });
    value(await room.acknowledgePhoto(H, "t0-0-a", ack));
    value(await room.updatePhoto(H, "t0-0-a", { ...upload, idempotency_key: key(), expected_photo_revision: 1, expected_photo_hash: upload.sha256 }));
    expect(await room.acknowledgePhoto(G, "t0-0-a", ack)).toMatchObject({ ok: false, code: "stale_photo_ack" });
    expect(value(await room.photoDelivery(G, "t0-0-a"))).toMatchObject({ available: true, acked_player_ids: [] });
  });
  it("preserves schema4 reactions through migration and exports/imports strict tombstones with no payload resurrection", async () => {
    const { room, ack } = await setup();
    const reaction = value(await room.react(G, "p0-0", { idempotency_key: key(), a_hash: a.recording_hash, b_hash: b.recording_hash, expected_reaction_revision: 0, reaction: "love" }));
    const old = value(await room.exportSnapshot(SOURCE)); expect(JSON.parse(old).payload.format_version).toBe(6);
    value(await room.acknowledgePhoto(H, "t0-0-a", ack)); value(await room.acknowledgePhoto(G, "t0-0-a", ack));
    expect(value(await room.reactionOperation(G, reaction.receipt.idempotency_key))).toEqual(reaction);
    const archive = value(await room.exportSnapshot(SOURCE)), parsed = JSON.parse(archive);
    expect(parsed.payload).toMatchObject({ format_version: 7, database_schema_version: 5 });
    const restored = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()); value(await restored.restoreSnapshot(archive, R));
    expect(value(await restored.photoDelivery(H, "t0-0-a"))).toEqual(value(await room.photoDelivery(H, "t0-0-a")));
    const bad = JSON.parse(archive); const row = bad.payload.tables.find((t: { name: string }) => t.name === "photo_delivery").rows[0];
    const d = JSON.parse(row.data); d.acked_player_ids = [H]; row.data = JSON.stringify(d); bad.checksum.value = await digest(canonicalJson(bad.payload));
    await expect(validateRoomV2(canonicalJson(bad), R)).rejects.toBeDefined();
    const oldTarget = env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId()); value(await oldTarget.restoreSnapshot(old, R));
    expect(value(await oldTarget.photo(H, "t0-0-a")).jpeg_base64).not.toBeNull();
  });
  it("separates owner deletion from delivery and erases all delivery rows with room deletion", async () => {
    const { room, upload, ack } = await setup(); value(await room.acknowledgePhoto(H, "t0-0-a", ack));
    value(await room.updatePhoto(H, "t0-0-a", { idempotency_key: key(), recording_hash: a.recording_hash, expected_photo_revision: 1, expected_photo_hash: upload.sha256 }, true));
    expect(value(await room.photoDelivery(G, "t0-0-a"))).toMatchObject({ available: false, removed_reason: "owner_deleted", acked_player_ids: [], photo: { sha256: null, photo_revision: 2 } });
    value(await room.eraseForPlayer(H)); const archive = JSON.parse(value(await room.exportSnapshot(SOURCE)));
    expect(archive.payload.tables.every((t: { name: string; rows: unknown[] }) => t.name === "room" || t.rows.length === 0)).toBe(true);
  });
  it("does not treat a one-member room as fully delivered", async () => {
    const { room, ack, upload } = await setup();
    // Isolate the pre-join safety guard; normal accepted turns require a partner.
    await runInDurableObject(room, (_, ctx) => { ctx.storage.sql.exec("UPDATE room SET data=json_set(data,'$.guest_id',NULL)"); });
    expect(await room.acknowledgePhoto(H, "t0-0-a", ack)).toMatchObject({ ok: false, code: "photo_recipients_unsettled" });
    expect(value(await room.photo(H, "t0-0-a")).jpeg_base64).toBe(upload.jpeg_base64);
    expect(value(await room.photoDelivery(H, "t0-0-a"))).toMatchObject({ intended_player_ids: [H], acked_player_ids: [], available: true });
  });
});
