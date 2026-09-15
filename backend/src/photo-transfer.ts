import { DurableObject } from "cloudflare:workers";
import { ApiError, type Outcome, canonicalJson, digest, HASH_PATTERN, IDEMPOTENCY_PATTERN, ID_PATTERN, integer, object, text } from "./protocol";
import { exact } from "./v2/protocol";
import { checkPhoto } from "./v2/photo-image";
import { PHOTO_TURN_PATTERN } from "./v2/photos";

export const TRANSFER_TTL = 14 * 86400000, TRANSFER_COOLDOWN = 86400000;
export const TRANSFER_MAX_BYTES = 32 * 1024 * 1024, TRANSFER_MAX_ENTRIES = 1000, TRANSFER_MAX_OPERATIONS = 10000;
export const TRANSFER_BODY_BYTES = 1024 * 1024, TRANSFER_BATCH = 16, TRANSFER_SLOTS = 64;
type Session = { session_id: string; created_at: string; expires_at: string; next_session_at: string };
type Control = { owner: string; session: Session | null; session_history: Session[]; accepted_writes: number; upload_operations: number; next_revision: number; next_session_at: number; reservation: string | null; deleted: boolean };
export type TransferEntry = { entry_id: string; room_id: string; turn_id: string; recording_hash: string; photo_revision: number; photo_owner: string; local_only: boolean; sha256: string; width: number; height: number; byte_length: number; created_at: string; jpeg_base64: string; deleted: boolean; entry_revision: number; expires_at: string };
type EntryAck = Pick<TransferEntry, "entry_id" | "sha256" | "entry_revision">;
type Receipt = { idempotency_key: string; request_hash: string; operation: "upload" | "restore_ack"; session_id: string | null; entries: EntryAck[]; evicted_entry_ids: string[] };
const iso = (time: number) => new Date(time).toISOString();
function need(value: unknown, code: string, status = 400): asserts value { if (!value) throw new ApiError(status, code); }
function version(value: Record<string, unknown>): void { need(value.schema_version === 1, "unsupported_transfer_version"); }
function list(value: unknown): unknown[] { need(Array.isArray(value) && value.length > 0 && value.length <= TRANSFER_BATCH, "invalid_transfer_batch"); return value; }
function unique(ids: string[]): void { need(new Set(ids).size === ids.length, "duplicate_transfer_entry"); }
function meta(entry: TransferEntry) { const { jpeg_base64: _bytes, ...result } = entry; return result; }
const ref = (entry: TransferEntry): EntryAck => ({ entry_id: entry.entry_id, sha256: entry.sha256, entry_revision: entry.entry_revision });
function guarded(error: unknown): never { if (error instanceof ApiError) throw error; throw new ApiError(503, "transfer_storage_unavailable"); }

/** Admission is contacted at start/erasure only. Expiry never blindly frees a reservation. */
export class PhotoTransferBudget extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) { super(ctx, env); ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS reservations (owner TEXT PRIMARY KEY, token TEXT NOT NULL, check_at INTEGER NOT NULL, last_start TEXT NOT NULL)"); ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS admissions (id INTEGER PRIMARY KEY CHECK(id=1), day TEXT NOT NULL, count INTEGER NOT NULL)"); }
  private fixed(): void { need(this.ctx.id.equals(this.env.PHOTO_TRANSFER_BUDGET.idFromName("photo-transfer-budget-v1")), "invalid_transfer_budget", 409); }
  async reserve(owner: string, token: string, startKey: string): Promise<Outcome<string>> {
    try {
    this.fixed(); text(owner, ID_PATTERN); text(token, IDEMPOTENCY_PATTERN); text(startKey, IDEMPOTENCY_PATTERN);
    return await this.ctx.storage.transaction(async () => {
      const old = this.ctx.storage.sql.exec<{ token: string; last_start: string }>("SELECT token,last_start FROM reservations WHERE owner=?", owner).toArray()[0];
      if (old?.last_start === startKey) return { ok: true, value: old.token } as const;
      const day = iso(Date.now()).slice(0, 10), admission = this.ctx.storage.sql.exec<{ day: string; count: number }>("SELECT day,count FROM admissions WHERE id=1").toArray()[0];
      const count = admission?.day === day ? admission.count : 0;
      need(count < 24, "transfer_daily_capacity", 409);
      need(old || this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM reservations").one().n < TRANSFER_SLOTS, "transfer_service_full", 409);
      this.ctx.storage.sql.exec("INSERT OR REPLACE INTO admissions VALUES (1,?,?)", day, count + 1);
      this.ctx.storage.sql.exec("INSERT OR REPLACE INTO reservations VALUES (?,?,?,?)", owner, old?.token ?? token, Date.now() + TRANSFER_TTL, startKey);
      const next = this.ctx.storage.sql.exec<{ n: number }>("SELECT MIN(check_at) AS n FROM reservations").one().n;
      await this.ctx.storage.setAlarm(next); return { ok: true, value: old?.token ?? token } as const;
    });
    } catch (error) { return error instanceof ApiError ? { ok: false, status: error.status, code: error.code } : { ok: false, status: 503, code: "transfer_storage_unavailable" }; }
  }
  async release(owner: string, token: string): Promise<void> {
    this.fixed();
    await this.ctx.storage.transaction(async () => {
      this.ctx.storage.sql.exec("DELETE FROM reservations WHERE owner=? AND token=?", owner, token);
      const next = this.ctx.storage.sql.exec<{ n: number | null }>("SELECT MIN(check_at) AS n FROM reservations").one().n;
      if (next === null) await this.ctx.storage.deleteAlarm(); else await this.ctx.storage.setAlarm(next);
    });
  }
  async alarm(): Promise<void> {
    this.fixed();
    const due = this.ctx.storage.sql.exec<{ owner: string; token: string }>("SELECT owner,token FROM reservations WHERE check_at<=? LIMIT 64", Date.now()).toArray();
    for (const row of due) {
      // Same owner object serializes this cleanup against starting/resuming uploads.
      const empty = await this.env.PHOTO_TRANSFERS.getByName(row.owner).expireReservation(row.owner, row.token);
      if (!empty) this.ctx.storage.sql.exec("UPDATE reservations SET check_at=? WHERE owner=? AND token=?", Date.now() + TRANSFER_COOLDOWN, row.owner, row.token);
    }
    const next = this.ctx.storage.sql.exec<{ n: number | null }>("SELECT MIN(check_at) AS n FROM reservations").one().n;
    if (next !== null) await this.ctx.storage.setAlarm(Math.max(Date.now() + 1000, next));
  }
}

/** Temporary account transfer data, explicitly excluded from portable gameplay archives. */
export class PhotoTransfer extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ensureSchema();
  }
  private ensureSchema(): void {
    const ctx = this.ctx;
    ctx.storage.transactionSync(() => {
      ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS transfer_control (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)");
      ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS transfer_entries (entry_id TEXT PRIMARY KEY, data TEXT NOT NULL)");
      ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS transfer_operations (request_key TEXT PRIMARY KEY, expires_at INTEGER NOT NULL, data TEXT NOT NULL)");
    });
  }
  private async result<T>(action: () => Promise<T>): Promise<Outcome<T>> {
    try { return { ok: true, value: await action() }; }
    catch (error) { return error instanceof ApiError ? { ok: false, status: error.status, code: error.code } : { ok: false, status: 503, code: "transfer_storage_unavailable" }; }
  }
  start(owner: string, device: string, value: unknown) { return this.result(() => this.startInternal(owner, device, value)); }
  inventory(owner: string, device: string) { return this.result(() => this.inventoryInternal(owner, device)); }
  operation(owner: string, device: string, key: string) { return this.result(() => this.operationInternal(owner, device, key)); }
  upload(owner: string, device: string, session: string, value: unknown) { return this.result(() => this.uploadInternal(owner, device, session, value)); }
  read(owner: string, device: string, value: unknown) { return this.result(() => this.readInternal(owner, device, value)); }
  acknowledge(owner: string, device: string, value: unknown) { return this.result(() => this.acknowledgeInternal(owner, device, value)); }
  private fixed(owner: string): void { text(owner, ID_PATTERN); need(this.ctx.id.equals(this.env.PHOTO_TRANSFERS.idFromName(owner)), "transfer_owner_mismatch", 403); }
  private control(owner: string): Control {
    this.fixed(owner); this.ensureSchema();
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM transfer_control WHERE id=1").toArray()[0];
    const value: Control = row ? JSON.parse(row.data) : { owner, session: null, session_history: [], accepted_writes: 0, upload_operations: 0, next_revision: 1, next_session_at: 0, reservation: null, deleted: false };
    need(value.owner === owner, "transfer_owner_mismatch", 403); return value;
  }
  private save(value: Control): void { this.ctx.storage.sql.exec("INSERT OR REPLACE INTO transfer_control VALUES (1,?)", JSON.stringify(value)); }
  private async authorize(owner: string, device: string): Promise<void> {
    this.fixed(owner); need(await this.env.PLAYERS.getByName(owner).authorize(device), "invalid_auth", 401);
    need(!this.control(owner).deleted, "invalid_auth", 401);
  }
  private prune(): void {
    const now = Date.now();
    this.ctx.storage.sql.exec("DELETE FROM transfer_entries WHERE json_extract(data,'$.expires_at')<=?", iso(now));
    this.ctx.storage.sql.exec("DELETE FROM transfer_operations WHERE expires_at<=?", now);
  }
  private entry(id: string): TransferEntry | null {
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM transfer_entries WHERE entry_id=?", id).toArray()[0];
    return row ? JSON.parse(row.data) as TransferEntry : null;
  }
  private count(): number { return this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM transfer_entries").one().n; }
  private bytes(): number {
    return this.ctx.storage.sql.exec<{ n: number }>("SELECT COALESCE((SELECT SUM(LENGTH(CAST(data AS BLOB))) FROM transfer_entries),0)+COALESCE((SELECT SUM(LENGTH(CAST(data AS BLOB))) FROM transfer_operations),0)+COALESCE((SELECT SUM(LENGTH(CAST(data AS BLOB))) FROM transfer_control),0) AS n").one().n;
  }
  private prior(key: string, hash?: string): Receipt | null {
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM transfer_operations WHERE request_key=? AND expires_at>?", key, Date.now()).toArray()[0];
    if (!row) return null;
    const receipt = JSON.parse(row.data) as Receipt;
    if (hash !== undefined) need(receipt.request_hash === hash, "idempotency_key_reused", 409);
    return receipt;
  }
  private remember(receipt: Receipt): void {
    this.ctx.storage.sql.exec("INSERT INTO transfer_operations VALUES (?,?,?)", receipt.idempotency_key, Date.now() + TRANSFER_TTL, JSON.stringify(receipt));
    // Reserve one small receipt per retained entry so even single-item ACKs can clear it.
    const ops = this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM transfer_operations").one().n;
    need(ops + this.count() <= TRANSFER_MAX_OPERATIONS, "transfer_history_full", 409);
    need(this.bytes() + this.count() * 512 <= TRANSFER_MAX_BYTES, "transfer_storage_full", 409);
  }
  private async schedule(): Promise<void> {
    const entry = this.ctx.storage.sql.exec<{ n: string | null }>("SELECT MIN(json_extract(data,'$.expires_at')) AS n FROM transfer_entries").one().n;
    const operation = this.ctx.storage.sql.exec<{ n: number | null }>("SELECT MIN(expires_at) AS n FROM transfer_operations").one().n;
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM transfer_control WHERE id=1").toArray()[0];
    const control = row ? JSON.parse(row.data) as Control : null;
    const times = [entry ? Date.parse(entry) : Infinity, operation ?? Infinity, control?.session ? Date.parse(control.session.expires_at) : Infinity].filter(n => n > Date.now());
    if (times.length) await this.ctx.storage.setAlarm(Math.min(...times)); else await this.ctx.storage.deleteAlarm();
  }
  private async startInternal(owner: string, device: string, value: unknown) {
    await this.authorize(owner, device);
    const input = object(value); exact(input, ["schema_version", "idempotency_key"]); version(input);
    const key = text(input.idempotency_key, IDEMPOTENCY_PATTERN), observed = this.control(owner);
    const previous = observed.session_history.find(s => s.session_id === key && Date.parse(s.expires_at) > Date.now());
    if (previous) return { schema_version: 1, session: previous };
    need(Date.now() >= observed.next_session_at, "transfer_cooldown", 429);
    const admitted = await this.env.PHOTO_TRANSFER_BUDGET.getByName("photo-transfer-budget-v1").reserve(owner, crypto.randomUUID(), key);
    if (!admitted.ok) throw new ApiError(admitted.status, admitted.code);
    const reservation = admitted.value;
    await this.authorize(owner, device);
    return this.ctx.storage.transaction(async () => {
      const current = this.control(owner);
      const priorSession = current.session_history.find(s => s.session_id === key && Date.parse(s.expires_at) > Date.now());
      if (priorSession) return { schema_version: 1, session: priorSession };
      need(Date.now() >= current.next_session_at, "transfer_cooldown", 429);
      this.prune(); const now = Date.now();
      current.session = { session_id: key, created_at: iso(now), expires_at: iso(now + TRANSFER_TTL), next_session_at: iso(now + TRANSFER_COOLDOWN) };
      current.session_history = [...current.session_history.filter(s => Date.parse(s.expires_at) > now), current.session]; current.accepted_writes = 0; current.upload_operations = 0;
      current.next_session_at = now + TRANSFER_COOLDOWN; current.reservation = reservation; this.save(current);
      await this.schedule(); return { schema_version: 1, session: current.session };
    });
  }
  private async inventoryInternal(owner: string, device: string) {
    await this.authorize(owner, device); this.prune(); const current = this.control(owner);
    const entries = this.ctx.storage.sql.exec<{ data: string }>("SELECT json_remove(data,'$.jpeg_base64') AS data FROM transfer_entries ORDER BY json_extract(data,'$.created_at') DESC,entry_id LIMIT 1001").toArray().map(row => meta(JSON.parse(row.data) as TransferEntry));
    need(entries.length <= TRANSFER_MAX_ENTRIES, "transfer_storage_unavailable", 503);
    return { schema_version: 1, session: current.session, entry_count: entries.length, bytes_used: this.bytes(), max_entries: TRANSFER_MAX_ENTRIES, max_bytes: TRANSFER_MAX_BYTES, entries };
  }
  private async operationInternal(owner: string, device: string, key: string) {
    await this.authorize(owner, device); text(key, IDEMPOTENCY_PATTERN);
    const receipt = this.prior(key); need(receipt, "transfer_operation_not_found", 404); return { schema_version: 1, receipt };
  }
  private async uploadInternal(owner: string, device: string, sessionId: string, value: unknown) {
    try {
      await this.authorize(owner, device);
      const input = object(value); exact(input, ["schema_version", "idempotency_key", "entries"]); version(input);
      const key = text(input.idempotency_key, IDEMPOTENCY_PATTERN); text(sessionId, IDEMPOTENCY_PATTERN);
      need(new TextEncoder().encode(canonicalJson(input)).byteLength <= TRANSFER_BODY_BYTES, "body_too_large", 413);
      const hash = await digest(canonicalJson({ operation: "upload", session_id: sessionId, ...input }));
      const prior = this.prior(key, hash); if (prior) { await this.authorize(owner, device); return { schema_version: 1, receipt: prior }; }
      const state = this.control(owner); need(state.session?.session_id === sessionId && Date.parse(state.session.expires_at) > Date.now() && state.reservation, "transfer_session_unavailable", 409);
      const entries: TransferEntry[] = [];
      for (const raw of list(input.entries)) {
        const e = object(raw); exact(e, ["entry_id", "room_id", "turn_id", "recording_hash", "photo_revision", "photo_owner", "local_only", "sha256", "width", "height", "byte_length", "created_at", "jpeg_base64", "deleted"]);
        text(e.entry_id, HASH_PATTERN); text(e.room_id, ID_PATTERN); text(e.turn_id, PHOTO_TURN_PATTERN); text(e.recording_hash, HASH_PATTERN); text(e.photo_owner, ID_PATTERN);
        need(typeof e.local_only === "boolean" && typeof e.deleted === "boolean", "invalid_transfer_entry");
        const revision = integer(e.photo_revision, 0, 256); need(e.local_only ? revision === 0 && e.photo_owner === owner : revision > 0, "invalid_transfer_entry");
        need(typeof e.created_at === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(e.created_at) && Number.isFinite(Date.parse(e.created_at)) && iso(Date.parse(e.created_at)) === e.created_at && Date.parse(e.created_at) <= Date.now() + 300000, "invalid_transfer_date");
        const image = await checkPhoto(e.jpeg_base64, e.sha256);
        need(e.width === image.width && e.height === image.height && e.byte_length === image.byte_length, "transfer_image_metadata_mismatch");
        entries.push({ ...e, ...image, entry_revision: 0, expires_at: "" } as TransferEntry);
      }
      unique(entries.map(e => e.entry_id)); await this.authorize(owner, device);
      return await this.ctx.storage.transaction(async () => {
        this.prune(); const current = this.control(owner), retry = this.prior(key, hash);
        if (retry) return { schema_version: 1, receipt: retry };
        need(!current.deleted && current.session?.session_id === sessionId && Date.parse(current.session.expires_at) > Date.now() && current.reservation, "transfer_session_unavailable", 409);
        need(current.upload_operations < 256, "transfer_session_request_limit", 409); current.upload_operations++;
        for (const e of entries) {
          const old = this.entry(e.entry_id);
          if (old) {
            const { entry_revision: _revision, expires_at: _expiry, ...oldValue } = old;
            const { entry_revision: _newRevision, expires_at: _newExpiry, ...newValue } = e;
            if (canonicalJson(oldValue) === canonicalJson(newValue)) { e.entry_revision = old.entry_revision; e.expires_at = old.expires_at; continue; }
          }
          need(current.accepted_writes < 1000, "transfer_session_full", 409); current.accepted_writes++;
          e.entry_revision = current.next_revision++; e.expires_at = iso(Date.now() + TRANSFER_TTL);
          this.ctx.storage.sql.exec("INSERT OR REPLACE INTO transfer_entries VALUES (?,?)", e.entry_id, JSON.stringify(e));
        }
        const evicted = this.ctx.storage.sql.exec<{ entry_id: string }>("SELECT entry_id FROM transfer_entries ORDER BY json_extract(data,'$.created_at') DESC,entry_id LIMIT 16 OFFSET 1000").toArray().map(row => row.entry_id);
        for (const id of evicted) this.ctx.storage.sql.exec("DELETE FROM transfer_entries WHERE entry_id=?", id);
        const receipt: Receipt = { idempotency_key: key, request_hash: hash, operation: "upload", session_id: sessionId, entries: entries.map(ref), evicted_entry_ids: evicted };
        this.save(current); this.remember(receipt); await this.schedule(); return { schema_version: 1, receipt };
      });
    } catch (error) { guarded(error); }
  }
  private async readInternal(owner: string, device: string, value: unknown) {
    await this.authorize(owner, device);
    const input = object(value); exact(input, ["schema_version", "entry_ids"]); version(input);
    const ids = list(input.entry_ids).map(id => text(id, HASH_PATTERN)); unique(ids); this.prune();
    const entries = ids.map(id => { const entry = this.entry(id); need(entry, "transfer_entry_not_found", 404); return entry; });
    const response = { schema_version: 1, entries };
    need(new TextEncoder().encode(JSON.stringify(response)).byteLength <= TRANSFER_BODY_BYTES, "transfer_read_too_large", 413);
    return response;
  }
  private async acknowledgeInternal(owner: string, device: string, value: unknown) {
    try {
      await this.authorize(owner, device);
      const input = object(value); exact(input, ["schema_version", "idempotency_key", "entries"]); version(input);
      const key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
      const entries = list(input.entries).map(raw => { const e = object(raw); exact(e, ["entry_id", "sha256", "entry_revision"]); return { entry_id: text(e.entry_id, HASH_PATTERN), sha256: text(e.sha256, HASH_PATTERN), entry_revision: integer(e.entry_revision, 1, Number.MAX_SAFE_INTEGER) }; });
      unique(entries.map(e => e.entry_id)); const hash = await digest(canonicalJson({ operation: "restore_ack", session_id: null, ...input }));
      await this.authorize(owner, device);
      return await this.ctx.storage.transaction(async () => {
        this.prune(); const prior = this.prior(key, hash); if (prior) return { schema_version: 1, receipt: prior };
        for (const e of entries) { const current = this.entry(e.entry_id); need(current && current.sha256 === e.sha256 && current.entry_revision === e.entry_revision, "stale_transfer_ack", 409); }
        for (const e of entries) this.ctx.storage.sql.exec("DELETE FROM transfer_entries WHERE entry_id=?", e.entry_id);
        const receipt: Receipt = { idempotency_key: key, request_hash: hash, operation: "restore_ack", session_id: null, entries, evicted_entry_ids: [] };
        this.remember(receipt); await this.schedule(); return { schema_version: 1, receipt };
      });
    } catch (error) { guarded(error); }
  }
  /** Binding-only erasure, called while Player is in its durable deleting state. */
  async eraseOwner(owner: string, playerObjectId: string): Promise<void> {
    this.fixed(owner);
    text(playerObjectId, HASH_PATTERN);
    need(await this.env.PLAYERS.get(this.env.PLAYERS.idFromString(playerObjectId)).deletionInProgress(owner), "deletion_not_ready", 409);
    await this.ctx.blockConcurrencyWhile(async () => {
      const current = this.control(owner), token = current.reservation;
      // deleteAll deallocates SQLite pages, unlike row DELETE alone. Keep only a
      // tiny retry marker until the reservation release has been acknowledged.
      await this.ctx.storage.deleteAlarm(); await this.ctx.storage.deleteAll(); this.ensureSchema();
      current.deleted = true; current.session = null; current.session_history = []; this.save(current);
      if (token) await this.env.PHOTO_TRANSFER_BUDGET.getByName("photo-transfer-budget-v1").release(owner, token);
      await this.ctx.storage.deleteAll();
    });
  }
  async expireReservation(owner: string, token: string): Promise<boolean> {
    this.fixed(owner);
    return this.ctx.blockConcurrencyWhile(async () => {
      const current = this.control(owner); this.prune();
      if (current.reservation && current.reservation !== token) return false;
      if (this.count() || this.ctx.storage.sql.exec("SELECT request_key FROM transfer_operations LIMIT 1").toArray().length || (current.session && Date.parse(current.session.expires_at) > Date.now())) return false;
      await this.ctx.storage.deleteAlarm(); await this.ctx.storage.deleteAll();
      await this.env.PHOTO_TRANSFER_BUDGET.getByName("photo-transfer-budget-v1").release(owner, token);
      return true;
    });
  }
  async alarm(): Promise<void> {
    // A consumed alarm can be retried after deleteAll succeeded but its reply
    // was lost. Do not recreate a deallocated database just to process it.
    if (!this.ctx.storage.sql.exec("SELECT name FROM sqlite_master WHERE name='transfer_control'").toArray().length) return;
    const row = this.ctx.storage.sql.exec<{ data: string }>("SELECT data FROM transfer_control WHERE id=1").toArray()[0];
    if (!row) return;
    const old = JSON.parse(row.data) as Control;
    if (old.reservation && await this.expireReservation(old.owner, old.reservation)) return;
    await this.schedule();
  }
}
