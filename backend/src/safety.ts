import { DurableObject } from "cloudflare:workers";
import { ApiError, HASH_PATTERN, IDEMPOTENCY_PATTERN, ID_PATTERN, canonicalJson, digest, equalHash, fail, object, ok, text, type Outcome } from "./protocol";
import { TERMS_VERSION } from "./public-policy";
import { ERASURE_SCHEMA, checkedErasure, erasureReceipt, readErasure, requestProviderErasure, writeErasure } from "./account-erasure";
import { isAlarmMetadataTable } from "./notification-storage";

export const SAFETY_REPORT_REASONS = ["sexual_content", "child_safety", "harassment", "hate", "privacy", "other"] as const;
export const REPORT_TTL = 90 * 86400000;
const PROFILE_SCHEMA = "CREATE TABLE safety_profile (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)";
const INBOX_SCHEMA = "CREATE TABLE safety_reports (report_id TEXT PRIMARY KEY, reporter_id TEXT NOT NULL, created_at INTEGER NOT NULL, data TEXT NOT NULL)";
function knownSchema(storage: DurableObjectStorage, schemas: string[]): void {
  const found = storage.sql.exec<{ name: string; sql: string }>("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name!='_cf_KV' ORDER BY name").toArray().filter(row => !isAlarmMetadataTable(row)).map(row => row.sql).sort();
  if (JSON.stringify(found) !== JSON.stringify([...schemas].sort()) || [...storage.kv.list({ limit: 1 })].length) throw new ApiError(409, "unsupported_safety_storage");
}
type Profile = { schema_version: 1; owner: string; accepted_at: string | null; terms_version: string | null; blocks: string[] };
export type ReportBody = { schema_version: 1; idempotency_key: string; room_family: "legacy" | "relay"; room_id: string; reason: typeof SAFETY_REPORT_REASONS[number]; photo: { turn_id: string; photo_revision: number; sha256: string } | null };
export type SafetyReport = ReportBody & { reporter_id: string; target_id: string; request_hash: string; report_id: string; created_at: number; resolved_at: number | null };
export type ReportReceipt = { schema_version: 1; report_id: string; request_hash: string; received: true };
const exact = (v: Record<string, unknown>, keys: string[]) => { if (Object.keys(v).length !== keys.length || Object.keys(v).some(key => !keys.includes(key))) throw new ApiError(400, "invalid_safety_request"); };
const iso = (v: unknown) => typeof v === "string" && Number.isFinite(Date.parse(v)) && new Date(v).toISOString() === v;
export function parseReport(input: unknown): ReportBody {
  const v = object(input); exact(v, ["schema_version", "idempotency_key", "room_family", "room_id", "reason", "photo"]);
  if (v.schema_version !== 1 || !["legacy", "relay"].includes(String(v.room_family)) || !SAFETY_REPORT_REASONS.includes(v.reason as ReportBody["reason"])) throw new ApiError(400, "invalid_safety_request");
  text(v.idempotency_key, IDEMPOTENCY_PATTERN); text(v.room_id, ID_PATTERN);
  if (v.photo !== null) {
    const photo = object(v.photo); exact(photo, ["turn_id", "photo_revision", "sha256"]);
    text(photo.turn_id, /^t(?:[0-9]|[12][0-9]|3[01])-[01]-[ab]$/);
    text(photo.sha256, HASH_PATTERN);
    if (v.room_family !== "relay" || typeof photo.photo_revision !== "number" || !Number.isSafeInteger(photo.photo_revision) || photo.photo_revision < 1) throw new ApiError(400, "invalid_safety_request");
  }
  return v as ReportBody;
}
function checkedProfile(input: unknown, owner: string): Profile {
  const v = object(input); exact(v, ["schema_version", "owner", "accepted_at", "terms_version", "blocks"]);
  if (v.schema_version !== 1 || v.owner !== owner || !ID_PATTERN.test(owner) ||
    !(v.accepted_at === null && v.terms_version === null || iso(v.accepted_at) && v.terms_version === TERMS_VERSION) ||
    !Array.isArray(v.blocks) || v.blocks.length > 128 || v.blocks.some(x => typeof x !== "string" || !ID_PATTERN.test(x) || x === owner) || new Set(v.blocks).size !== v.blocks.length) throw new ApiError(409, "unsupported_safety_state");
  return v as Profile;
}
function checkedReport(input: unknown): SafetyReport {
  const v = object(input); exact(v, ["schema_version", "idempotency_key", "room_family", "room_id", "reason", "photo", "reporter_id", "target_id", "request_hash", "report_id", "created_at", "resolved_at"]);
  parseReport({ schema_version: v.schema_version, idempotency_key: v.idempotency_key, room_family: v.room_family, room_id: v.room_id, reason: v.reason, photo: v.photo });
  text(v.reporter_id, ID_PATTERN); text(v.target_id, ID_PATTERN); text(v.request_hash, HASH_PATTERN); text(v.report_id, HASH_PATTERN);
  if (v.reporter_id === v.target_id || typeof v.created_at !== "number" || !Number.isSafeInteger(v.created_at) || v.created_at <= 0 ||
    !(v.resolved_at === null || typeof v.resolved_at === "number" && Number.isSafeInteger(v.resolved_at) && v.resolved_at >= v.created_at)) throw new ApiError(409, "unsupported_safety_state");
  return v as SafetyReport;
}
const receipt = (row: SafetyReport): ReportReceipt => ({ schema_version: 1, report_id: row.report_id, request_hash: row.request_hash, received: true });

/** Safety state is separate from immutable gameplay archives, never ephemeral. */
export class SafetyProfile extends DurableObject<Env> {
  private erasureBusy = false;
  constructor(ctx: DurableObjectState, env: Env) { super(ctx, env); this.ctx.storage.sql.exec(PROFILE_SCHEMA.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS ")); this.ctx.storage.sql.exec(ERASURE_SCHEMA.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS ")); }
  private read(owner: string): Profile {
    knownSchema(this.ctx.storage, [PROFILE_SCHEMA, ERASURE_SCHEMA]);
    text(owner, ID_PATTERN);
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM safety_profile WHERE id=1").toArray()[0];
    return row ? checkedProfile(JSON.parse(row.data), owner) : { schema_version: 1, owner, terms_version: null, accepted_at: null, blocks: [] };
  }
  private write(state: Profile): void { this.ctx.storage.sql.exec("INSERT OR REPLACE INTO safety_profile VALUES (1,?)", JSON.stringify(state)); }
  terms(owner: string) { const p = this.read(owner); return { schema_version: 1, terms_version: TERMS_VERSION, accepted: p.terms_version === TERMS_VERSION, accepted_at: p.accepted_at }; }
  blocks(owner: string) { return { schema_version: 1, blocked_players: [...this.read(owner).blocks] }; }
  hasBlocked(owner: string, peer: string): boolean { return this.read(owner).blocks.includes(peer); }
  async accept(owner: string, deviceHash: string, version: string): Promise<Outcome<ReturnType<SafetyProfile["terms"]>>> {
    if (version !== TERMS_VERSION) return fail(409, "unsupported_terms_version");
    if (!await this.env.PLAYERS.getByName(owner).authorize(deviceHash)) return fail(401, "invalid_auth");
    if (readErasure(this.ctx.storage)) return fail(409, "identity_deletion_pending");
    const p = this.read(owner);
    if (p.terms_version !== TERMS_VERSION) { p.terms_version = TERMS_VERSION; p.accepted_at = new Date().toISOString(); this.write(p); }
    return ok(this.terms(owner));
  }
  async setBlock(owner: string, deviceHash: string, peer: string, blocked: boolean): Promise<Outcome<{ schema_version: 1; blocked: boolean; player_id: string }>> {
    text(peer, ID_PATTERN); if (owner === peer) return fail(400, "invalid_block_target");
    if (!await this.env.PLAYERS.getByName(owner).authorize(deviceHash)) return fail(401, "invalid_auth");
    if (readErasure(this.ctx.storage)) return fail(409, "identity_deletion_pending");
    const p = this.read(owner); const has = p.blocks.includes(peer);
    if (blocked && !has && p.blocks.length >= 128) return fail(409, "block_list_full");
    if (blocked !== has) { p.blocks = blocked ? [...p.blocks, peer].sort() : p.blocks.filter(id => id !== peer); this.write(p); }
    return ok({ schema_version: 1, blocked, player_id: peer });
  }
  async operatorBlock(owner: string, peer: string): Promise<Outcome<{ schema_version: 1; blocked: true; player_id: string }>> {
    text(peer, ID_PATTERN); if (peer === owner) return fail(400, "invalid_block_target");
    if (!await this.env.PLAYERS.getByName(owner).safetyIdentityActive(owner)) return fail(409, "reporter_unavailable");
    const p = this.read(owner); if (readErasure(this.ctx.storage)) return fail(409, "identity_deletion_pending");
    if (!p.blocks.includes(peer)) { if (p.blocks.length >= 128) return fail(409, "block_list_full"); p.blocks.push(peer); p.blocks.sort(); this.write(p); }
    return ok({ schema_version: 1, blocked: true, player_id: peer });
  }
  eraseOwner(owner: string): void { this.read(owner); const job = readErasure(this.ctx.storage); if (job && job.owner !== owner) throw new ApiError(409, "invalid_erasure_owner"); this.ctx.storage.sql.exec("DELETE FROM safety_profile"); }
  deletionReceipt(owner: string, deviceHash: string): boolean { return erasureReceipt(this.ctx.storage, owner, deviceHash); }
  async acknowledgeDeletion(owner: string, deviceHash: string): Promise<Outcome<{ schema_version: 1; acknowledged: true }>> {
    text(owner, ID_PATTERN); text(deviceHash, HASH_PATTERN);
    return this.ctx.storage.transaction(async () => {
      knownSchema(this.ctx.storage, [PROFILE_SCHEMA, ERASURE_SCHEMA]);
      const job = readErasure(this.ctx.storage);
      // Absence is a harmless repeat after a lost acknowledgement. This endpoint
      // cannot authenticate an account or authorize any other operation.
      if (job && !erasureReceipt(this.ctx.storage, owner, deviceHash)) return fail(401, "invalid_auth");
      if (job) {
        if (this.ctx.storage.sql.exec("SELECT id FROM safety_profile").toArray().length) return fail(409, "deletion_not_ready");
        this.ctx.storage.sql.exec("DELETE FROM safety_erasure"); await this.ctx.storage.deleteAlarm();
      }
      return ok({ schema_version: 1, acknowledged: true });
    });
  }
  async ensureErasure(owner: string, deviceHash: string, playerObjectId: string): Promise<boolean> {
    text(owner, ID_PATTERN); text(deviceHash, HASH_PATTERN); text(playerObjectId, HASH_PATTERN);
    let job = readErasure(this.ctx.storage);
    if (job && (job.owner !== owner || !equalHash(job.device_hash, deviceHash) || job.player_object_id !== playerObjectId)) return false;
    if (job?.state === "complete") return true;
    const target = this.env.PLAYERS.get(this.env.PLAYERS.idFromString(playerObjectId));
    if (!await target.deletionInProgress(owner) || !await target.authorize(deviceHash, true)) return false;
    job = readErasure(this.ctx.storage);
    if (job && (job.owner !== owner || !equalHash(job.device_hash, deviceHash) || job.player_object_id !== playerObjectId)) return false;
    if (job?.state === "complete") return true;
    if (!job) {
      job = { schema_version: 1, owner, device_hash: deviceHash, player_object_id: playerObjectId, state: "pending", created_at: Date.now(), attempts: 0, cleanup_attempts: 0, next_at: Date.now() + 60000 };
      await this.ctx.storage.transaction(async () => { writeErasure(this.ctx.storage, job!); await this.ctx.storage.setAlarm(job!.next_at!); });
    } else if (job.state === "pending" && job.attempts >= 8) {
      // An explicit authenticated retry may resume a held job; no silent loop.
      job.attempts = 0; job.next_at = Date.now() + 60000; writeErasure(this.ctx.storage, job); await this.ctx.storage.setAlarm(job.next_at);
    } else if (job.state === "accepted" && job.cleanup_attempts >= 8) {
      job.cleanup_attempts = 0; job.next_at = Date.now() + 60000; writeErasure(this.ctx.storage, job); await this.ctx.storage.setAlarm(job.next_at);
    }
    await this.processErasure(false);
    const after = readErasure(this.ctx.storage); return !!after && after.state !== "pending";
  }
  async markErasureComplete(owner: string): Promise<void> {
    const job = readErasure(this.ctx.storage); if (!job || job.owner !== owner || job.state === "pending") throw new ApiError(409, "erasure_not_accepted");
    if (job.state !== "complete") {
      job.state = "complete"; job.next_at = null;
      await this.ctx.storage.transaction(async () => { writeErasure(this.ctx.storage, job); await this.ctx.storage.deleteAlarm(); });
    }
  }
  async alarm(): Promise<void> { await this.processErasure(true); }
  private async processErasure(finishAccount: boolean): Promise<void> {
    if (this.erasureBusy) return;
    const job = readErasure(this.ctx.storage); if (!job) { await this.ctx.storage.deleteAlarm(); return; }
    if (job.state === "complete") { await this.ctx.storage.deleteAlarm(); return; }
    if (finishAccount && job.next_at !== null && job.next_at > Date.now()) { await this.ctx.storage.setAlarm(job.next_at); return; }
    this.erasureBusy = true;
    try {
      if (job.state === "pending") {
        if (job.attempts >= 8) { await this.ctx.storage.deleteAlarm(); return; }
        job.attempts++; job.next_at = Date.now() + Math.min(86400000, 60000 * 2 ** (job.attempts - 1));
        // Reserve the retry before outbound I/O. Provider DELETE is idempotent.
        await this.ctx.storage.transaction(async () => { writeErasure(this.ctx.storage, job); await this.ctx.storage.setAlarm(job.next_at!); });
        const accepted = await requestProviderErasure(job.owner, this.env);
        const current = readErasure(this.ctx.storage);
        if (!current || current.state !== "pending" || current.owner !== job.owner || !equalHash(current.device_hash, job.device_hash)) return;
        if (!accepted) { if (job.attempts >= 8) await this.ctx.storage.deleteAlarm(); return; }
        current.state = "accepted"; current.next_at = Date.now() + 60000; writeErasure(this.ctx.storage, current); await this.ctx.storage.setAlarm(current.next_at);
      }
      if (finishAccount) {
        const current = readErasure(this.ctx.storage)!;
        // Reserve cleanup retry too: provider acceptance does not imply that
        // room, transfer, safety or local provider-state cleanup succeeded.
        if (current.cleanup_attempts >= 8) { await this.ctx.storage.deleteAlarm(); return; }
        current.cleanup_attempts++; current.next_at = Date.now() + Math.min(86400000, 60000 * 2 ** (current.cleanup_attempts - 1));
        await this.ctx.storage.transaction(async () => { writeErasure(this.ctx.storage, current); await this.ctx.storage.setAlarm(current.next_at!); });
        try { await this.env.PLAYERS.get(this.env.PLAYERS.idFromString(current.player_object_id)).finalizeErasure(current.owner, current.device_hash); } catch { /* Reserved retry owns transient cleanup failures. */ }
        if (readErasure(this.ctx.storage)?.state === "accepted" && current.cleanup_attempts >= 8) await this.ctx.storage.deleteAlarm();
      }
    } finally { this.erasureBusy = false; }
  }
  async exportSnapshot(owner: string): Promise<string> {
    const alarm = await this.ctx.storage.getAlarm(); knownSchema(this.ctx.storage, [PROFILE_SCHEMA, ERASURE_SCHEMA]);
    const erasure = readErasure(this.ctx.storage);
    if (erasure && erasure.owner !== owner || alarm !== null && alarm !== erasure?.next_at) throw new ApiError(409, "unsupported_safety_alarm");
    const checked = this.read(owner);
    const profile = this.ctx.storage.sql.exec("SELECT id FROM safety_profile").toArray().length ? checked : null;
    const payload = { format: "after-you-safety-profile", schema_version: 1, owner, profile, erasure };
    return canonicalJson({ payload, checksum: await digest(canonicalJson(payload)) });
  }
  async restoreSnapshot(owner: string, archive: string, targetPlayerObjectId?: string): Promise<Outcome<{ restored: true }>> {
    try {
      if (archive.length > 32768) throw new ApiError(400, "invalid_safety_archive");
      const envelope = object(JSON.parse(archive)); exact(envelope, ["payload", "checksum"]);
      const p = object(envelope.payload); exact(p, ["format", "schema_version", "owner", "profile", "erasure"]);
      if (p.format !== "after-you-safety-profile" || p.schema_version !== 1 || p.owner !== owner || envelope.checksum !== await digest(canonicalJson(p))) throw new ApiError(409, "invalid_safety_archive");
      text(owner, ID_PATTERN);
      const profile = p.profile === null ? null : checkedProfile(p.profile, owner);
      const erasure = p.erasure === null ? null : checkedErasure(p.erasure);
      if (erasure && erasure.owner !== owner) throw new ApiError(409, "invalid_safety_archive");
      if (erasure?.state === "complete" && profile !== null) throw new ApiError(409, "invalid_safety_archive");
      // Portable restore selects the destination Player explicitly; never send
      // a restored deletion job to an archived source object's physical ID.
      if (erasure) erasure.player_object_id = text(targetPlayerObjectId ?? this.env.PLAYERS.idFromName(owner).toString(), HASH_PATTERN);
      return await this.ctx.storage.transaction(async () => {
        knownSchema(this.ctx.storage, [PROFILE_SCHEMA, ERASURE_SCHEMA]);
        if (this.ctx.storage.sql.exec("SELECT id FROM safety_profile").toArray().length || readErasure(this.ctx.storage) || await this.ctx.storage.getAlarm() !== null) return fail(409, "restore_target_not_empty");
        if (profile) this.write(profile);
        if (erasure) {
          if (erasure.next_at !== null && (erasure.state === "pending" && erasure.attempts < 8 || erasure.state === "accepted" && erasure.cleanup_attempts < 8)) {
            erasure.next_at = Math.max(Date.now() + 1000, erasure.next_at); await this.ctx.storage.setAlarm(erasure.next_at);
          }
          writeErasure(this.ctx.storage, erasure);
        }
        return ok({ restored: true });
      });
    } catch { return fail(409, "invalid_safety_archive"); }
  }
}

/** Only report submission/review uses the bounded inbox; gameplay never does. */
export class SafetyInbox extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.storage.sql.exec(INBOX_SCHEMA.replace("CREATE TABLE ", "CREATE TABLE IF NOT EXISTS "));
  }
  private prune(): void { knownSchema(this.ctx.storage, [INBOX_SCHEMA]); this.ctx.storage.sql.exec("DELETE FROM safety_reports WHERE created_at<=?", Date.now() - REPORT_TTL); }
  private async schedule(): Promise<void> {
    const row = this.ctx.storage.sql.exec<{ earliest: number | null }>("SELECT MIN(created_at) AS earliest FROM safety_reports").one();
    if (row.earliest === null) await this.ctx.storage.deleteAlarm(); else await this.ctx.storage.setAlarm(row.earliest + REPORT_TTL);
  }
  async alarm(): Promise<void> { this.prune(); await this.schedule(); }
  async submit(report: SafetyReport, deviceHash: string): Promise<Outcome<ReportReceipt>> {
    checkedReport(report);
    text(deviceHash, HASH_PATTERN);
    if (!await this.env.PLAYERS.getByName(report.reporter_id).authorize(deviceHash)) return fail(401, "invalid_auth");
    const result = await this.ctx.storage.transaction(async () => {
      this.prune();
      const old = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM safety_reports WHERE report_id=?", report.report_id).toArray()[0];
      if (old) { const existing = checkedReport(JSON.parse(old.data)); return equalHash(existing.request_hash, report.request_hash) ? ok(receipt(existing)) : fail(409, "idempotency_key_reused"); }
      if (this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM safety_reports WHERE reporter_id=? AND created_at>?", report.reporter_id, Date.now() - 86400000).one().n >= 10) return fail(429, "report_rate_limited");
      if (this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM safety_reports").one().n >= 1000) return fail(503, "report_inbox_full");
      this.ctx.storage.sql.exec("INSERT INTO safety_reports VALUES (?,?,?,?)", report.report_id, report.reporter_id, report.created_at, JSON.stringify(report));
      await this.schedule(); return ok(receipt(report));
    });
    if (result.ok && !await this.env.PLAYERS.getByName(report.reporter_id).authorize(deviceHash)) {
      // Erasure may have run after the first authorization returned but before
      // this object's insert resumed. Close that ordering before acknowledging.
      // Credential rotation alone must not retract the same owner's existing
      // report; an inactive/deleted identity must leave no late report behind.
      if (!await this.env.PLAYERS.getByName(report.reporter_id).safetyIdentityActive(report.reporter_id)) {
        this.ctx.storage.sql.exec("DELETE FROM safety_reports WHERE report_id=? AND reporter_id=? AND json_extract(data,'$.request_hash')=?", report.report_id, report.reporter_id, report.request_hash);
        await this.schedule();
      }
      return fail(401, "invalid_auth");
    }
    return result;
  }
  async reportReceipt(owner: string, key: string): Promise<Outcome<ReportReceipt>> {
    const id = await digest(owner + ":" + key); this.prune();
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM safety_reports WHERE report_id=? AND reporter_id=?", id, owner).toArray()[0];
    return row ? ok(receipt(checkedReport(JSON.parse(row.data)))) : fail(404, "report_not_found");
  }
  async eraseReporter(owner: string): Promise<Outcome<{ erased: true }>> {
    try { text(owner, ID_PATTERN); knownSchema(this.ctx.storage, [INBOX_SCHEMA]); this.ctx.storage.sql.exec("DELETE FROM safety_reports WHERE reporter_id=?", owner); await this.schedule(); return ok({ erased: true }); }
    catch (error) { if (error instanceof ApiError) return fail(error.status, error.code); throw error; }
  }
  // Binding-only operator tools; no public route exposes report contents.
  getReport(id: string): Outcome<SafetyReport> {
    this.prune(); const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM safety_reports WHERE report_id=?", text(id, HASH_PATTERN)).toArray()[0];
    return row ? ok(checkedReport(JSON.parse(row.data))) : fail(404, "report_not_found");
  }
  listReports(): SafetyReport[] { this.prune(); return this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM safety_reports ORDER BY created_at,report_id LIMIT 1001").toArray().map(row => checkedReport(JSON.parse(row.data))); }
  resolveReport(id: string): Outcome<{ resolved: true }> {
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM safety_reports WHERE report_id=?", text(id, HASH_PATTERN)).toArray()[0];
    if (!row) return fail(404, "report_not_found");
    const report = checkedReport(JSON.parse(row.data)); report.resolved_at ??= Date.now(); this.ctx.storage.sql.exec("UPDATE safety_reports SET data=? WHERE report_id=?", JSON.stringify(report), id); return ok({ resolved: true });
  }
  async exportSnapshot(): Promise<string> {
    const alarm = await this.ctx.storage.getAlarm(); knownSchema(this.ctx.storage, [INBOX_SCHEMA]);
    const earliest = this.ctx.storage.sql.exec<{ t: number | null }>("SELECT MIN(created_at) AS t FROM safety_reports").one().t;
    if (alarm !== null && (earliest === null || alarm !== earliest + REPORT_TTL)) throw new ApiError(409, "unsupported_safety_alarm");
    const payload = { format: "after-you-safety-inbox", schema_version: 1, reports: this.listReports() };
    return canonicalJson({ payload, checksum: await digest(canonicalJson(payload)) });
  }
  async restoreSnapshot(archive: string): Promise<Outcome<{ restored: true }>> {
    try {
      if (archive.length > 2097152) throw new ApiError(400, "invalid_safety_archive");
      const envelope = object(JSON.parse(archive)); exact(envelope, ["payload", "checksum"]);
      const p = object(envelope.payload); exact(p, ["format", "schema_version", "reports"]);
      if (p.format !== "after-you-safety-inbox" || p.schema_version !== 1 || !Array.isArray(p.reports) || p.reports.length > 1000 || envelope.checksum !== await digest(canonicalJson(p))) throw new ApiError(409, "invalid_safety_archive");
      const reports = p.reports.map(checkedReport); if (new Set(reports.map(r => r.report_id)).size !== reports.length) throw new ApiError(409, "invalid_safety_archive");
      for (const r of reports) {
        const { reporter_id, target_id: _target, request_hash, report_id, created_at: _created, resolved_at: _resolved, ...body } = r;
        if (report_id !== await digest(reporter_id + ":" + body.idempotency_key) || request_hash !== await digest(canonicalJson({ operation: "safety_report", reporter_id, ...body }))) throw new ApiError(409, "invalid_safety_archive");
      }
      return await this.ctx.storage.transaction(async () => {
        knownSchema(this.ctx.storage, [INBOX_SCHEMA]);
        if (this.ctx.storage.sql.exec("SELECT report_id FROM safety_reports LIMIT 1").toArray().length || await this.ctx.storage.getAlarm() !== null) return fail(409, "restore_target_not_empty");
        for (const report of reports) this.ctx.storage.sql.exec("INSERT INTO safety_reports VALUES (?,?,?,?)", report.report_id, report.reporter_id, report.created_at, JSON.stringify(report));
        this.prune(); await this.schedule(); return ok({ restored: true });
      });
    } catch { return fail(409, "invalid_safety_archive"); }
  }
}

export async function interactionBlocked(env: Env, a: string, b: string | null): Promise<boolean> {
  if (!b) return false;
  const [ab, ba] = await Promise.all([env.SAFETY_PROFILES.getByName(a).hasBlocked(a, b), env.SAFETY_PROFILES.getByName(b).hasBlocked(b, a)]);
  return ab || ba;
}
