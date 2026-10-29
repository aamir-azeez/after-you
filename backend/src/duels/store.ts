import { fail, ok, type Outcome } from "../protocol";
import { encodeProof, sentProof, type EncodedProof } from "../leaderboards/proofs";
import type { ReplayWork } from "../leaderboards/board";
import { REVIEW_REASONS } from "../leaderboards/rules";
import type { ChapterKey } from "../v2/chapter-types";
import type { CheckpointV2 } from "../v2/protocol";
import { accept, claimRoom, decide, decline, forgetPlayer, isFinal, leave, progress, settle, verdict, type Duel, type ProgressNote, type SideRoom } from "./model";
import { MAX_BOARD_DUELS, MAX_DUEL_PROOFS, MAX_DUEL_PROOF_CHARS } from "./rules";

/**
 * Duels in their chapter's board object (leaderboards/board.ts): every duel
 * is pinned to one chapter version, and that version's board already holds
 * the runs waiting for the replay check, so duels need no Durable Object
 * class of their own. Their own tables, never lb_entries, which every board
 * submission scans:
 * - duels: one row per duel (model.ts), the newest MAX_BOARD_DUELS kept;
 *   settled ones go first past it.
 * - duel_proofs: a finished friend run's final checkpoint in the shared blob
 *   format (blob-codec.ts: deflate, its canonical length and SHA-256), while the
 *   replay job has not judged it (at most MAX_DUEL_PROOFS).
 * Both appear with the first duel write, never on a board nobody duels on.
 *
 * Each call is one synchronous transaction around one model call, and the
 * row is written only when the duel changed, so retries cost no rows.
 */
const TABLES = [
  "CREATE TABLE IF NOT EXISTS duels (duel_id TEXT PRIMARY KEY, status TEXT NOT NULL, updated_ms INTEGER NOT NULL, data TEXT NOT NULL) WITHOUT ROWID",
  "CREATE TABLE IF NOT EXISTS duel_proofs (entry_id TEXT PRIMARY KEY, duel_id TEXT NOT NULL, proof_hash TEXT NOT NULL, ticks INTEGER NOT NULL, chapter TEXT NOT NULL, byte_length INTEGER NOT NULL, body BLOB NOT NULL, at INTEGER NOT NULL) WITHOUT ROWID"
];
/**
 * A duel run waiting for the replay job: the board's ReplayWork facts, `duel: true` (the check then
 * allows assisted turns), and the final checkpoint as a tagged blob body in base64 with its canonical
 * length; `proof_hash` is the SHA-256 of those canonical bytes, which the job checks before replaying.
 */
export type DuelReplayWork = ReplayWork & { duel: true };
export type DuelVerdict = { entry_id: string; proof_hash: string; valid: boolean; measured_ticks: number; reason: string };
export type DuelAction =
  | { kind: "accept"; player: string; intact: boolean; eligible: boolean }
  | { kind: "decline"; player: string }
  | { kind: "leave"; player: string }
  | { kind: "claim"; player: string; room_id: string; invite_code: string; room_absent: boolean };
/** The finished run's raw final checkpoint, sent with the note of the turn that finished it. */
export type FinishProof = { checkpoint: CheckpointV2; simulation_version: number };

const known = new WeakMap<DurableObjectStorage, boolean>();

export class DuelStore {
  constructor(private readonly storage: DurableObjectStorage) {}

  /** Adds a new duel; the same id again answers the one already held. Null when the board is full of open duels. */
  create(duel: Duel, now: number): Duel | null {
    this.ensure();
    return this.storage.transactionSync(() => {
      const held = this.duel(duel.duel_id);
      if (held) { if (settle(held, now)) this.save(held); return held; }
      if (!this.makeRoom()) return null;
      this.save(duel);
      return duel;
    });
  }

  /** The duels named, settled to `now` (a changed one is saved), in the order asked; unknown ids are left out. */
  read(ids: readonly string[], now: number): Duel[] {
    if (!this.present() || !ids.length) return [];
    return this.storage.transactionSync(() => ids.map(id => this.duel(id)).filter((duel): duel is Duel => duel !== null).map(duel => {
      if (settle(duel, now)) this.save(duel);
      return duel;
    }));
  }

  /** One player action on one duel. Answers the duel (with the side's room for a claim), or the model's refusal. */
  act(duelId: string, action: DuelAction, now: number): Outcome<{ duel: Duel; room?: SideRoom }> {
    if (!this.present()) return fail(404, "duel_not_found");
    return this.storage.transactionSync(() => {
      const duel = this.duel(duelId);
      if (!duel) return fail(404, "duel_not_found");
      const before = JSON.stringify(duel);
      let answer: Outcome<unknown>;
      if (action.kind === "accept") answer = accept(duel, action.player, now, action.intact, action.eligible);
      else if (action.kind === "decline") answer = decline(duel, action.player, now);
      else if (action.kind === "leave") answer = leave(duel, action.player, now);
      else answer = claimRoom(duel, action.player, { room_id: action.room_id, invite_code: action.invite_code }, now, action.room_absent);
      if (JSON.stringify(duel) !== before) this.save(duel);
      if (!answer.ok) return answer;
      return ok({ duel, ...(action.kind === "claim" ? { room: answer.value as SideRoom } : {}) });
    });
  }

  /**
   * A turn accepted in a duel room. On the turn that finishes a friend run,
   * its final checkpoint waits here for the replay job. Answers the duel.
   */
  async progress(duelId: string, note: ProgressNote, now: number, proof?: FinishProof): Promise<Outcome<Duel>> {
    if (!this.present()) return fail(404, "duel_not_found");
    // Encoded before the transaction: compression is async.
    const encoded = proof && note.complete ? await encodeProof(proof.checkpoint) : null;
    const kept = encoded && encoded.byte_length <= MAX_DUEL_PROOF_CHARS ? encoded : null;
    return this.storage.transactionSync(() => {
      const duel = this.duel(duelId);
      if (!duel) return fail(404, "duel_not_found");
      const before = JSON.stringify(duel);
      const answer = progress(duel, note, now);
      if (answer.ok && answer.value.finished && duel.kind === "friend" && note.entry_id) {
        const side = duel.sides.find(item => item?.entry_id === note.entry_id);
        if (side && !kept) side.check = "error";
        else if (side && kept) this.keepProof(duel, note.entry_id, kept, side.ticks, proof!.simulation_version, now);
        if (side?.check === "error") decide(duel, now);
      }
      if (JSON.stringify(duel) !== before) this.save(duel);
      return answer.ok ? ok(duel) : answer;
    });
  }

  /** Duel runs for the replay job, at most `maxChars` of canonical bytes, skipping entries the board already hands out. */
  pending(maxChars: number, skip: ReadonlySet<string>): DuelReplayWork[] {
    if (!this.present()) return [];
    const work: DuelReplayWork[] = [];
    let chars = 0;
    // Lengths first: a body is read only once it fits.
    for (const head of this.storage.sql.exec<{ entry_id: string; byte_length: number }>("SELECT entry_id,byte_length FROM duel_proofs ORDER BY at").toArray()) {
      if (skip.has(head.entry_id) || chars + head.byte_length > maxChars) continue;
      const row = this.storage.sql.exec<{ entry_id: string; proof_hash: string; ticks: number; chapter: string; byte_length: number; body: ArrayBuffer }>("SELECT entry_id,proof_hash,ticks,chapter,byte_length,body FROM duel_proofs WHERE entry_id=?", head.entry_id).toArray()[0];
      if (!row) continue;
      chars += row.byte_length;
      const chapter = JSON.parse(row.chapter) as ChapterKey & { simulation_version: number };
      const { simulation_version, ...key } = chapter;
      work.push({ entry_id: row.entry_id, chapter: key, simulation_version, ticks: row.ticks, ...sentProof({ proof_hash: row.proof_hash, byte_length: row.byte_length, body: new Uint8Array(row.body) }), duel: true });
    }
    return work;
  }

  /** Replay verdicts on duel runs. A verdict counts only for a waiting run whose stored proof it checked. Returns the duels that changed. */
  verdicts(list: readonly DuelVerdict[], now: number): string[] {
    if (!this.present() || !list.length) return [];
    return this.storage.transactionSync(() => {
      const changed: string[] = [];
      for (const item of list) {
        const proof = this.storage.sql.exec<{ duel_id: string; proof_hash: string; ticks: number }>("SELECT duel_id,proof_hash,ticks FROM duel_proofs WHERE entry_id=?", item.entry_id).toArray()[0];
        if (!proof || proof.proof_hash !== item.proof_hash) continue;
        this.storage.sql.exec("DELETE FROM duel_proofs WHERE entry_id=?", item.entry_id);
        const duel = this.duel(proof.duel_id);
        if (!duel) continue;
        const check = item.valid && item.measured_ticks === proof.ticks ? "passed" : !item.valid && REVIEW_REASONS.includes(item.reason) ? "error" : "failed";
        if (verdict(duel, item.entry_id, check, now)) { this.save(duel); changed.push(duel.duel_id); }
      }
      return changed;
    });
  }

  /** Account erasure: the player leaves every duel here; their waiting runs' proofs go. Returns how many duels changed. */
  forgetPlayer(player: string, now: number): number {
    if (!this.present()) return 0;
    return this.storage.transactionSync(() => {
      let count = 0;
      const rows = this.storage.sql.exec<{ data: string }>("SELECT data FROM duels WHERE instr(data, ?) > 0", player).toArray();
      for (const row of rows) {
        const duel = JSON.parse(row.data) as Duel;
        if (!forgetPlayer(duel, player, now)) continue;
        this.storage.sql.exec("DELETE FROM duel_proofs WHERE duel_id=?", duel.duel_id);
        this.save(duel);
        count++;
      }
      return count;
    });
  }

  private keepProof(duel: Duel, entryId: string, kept: EncodedProof, ticks: number, simulationVersion: number, now: number): void {
    const held = this.storage.sql.exec<{ entry_id: string; duel_id: string }>("SELECT entry_id,duel_id FROM duel_proofs ORDER BY at").toArray();
    if (held.length >= MAX_DUEL_PROOFS) {
      // Full: the oldest waiting run can no longer be checked, so its duel ends unchecked.
      const oldest = held[0];
      this.storage.sql.exec("DELETE FROM duel_proofs WHERE entry_id=?", oldest.entry_id);
      const other = oldest.duel_id === duel.duel_id ? duel : this.duel(oldest.duel_id);
      if (other && verdict(other, oldest.entry_id, "error", now) && other !== duel) this.save(other);
    }
    this.storage.sql.exec("INSERT OR REPLACE INTO duel_proofs VALUES (?,?,?,?,?,?,?,?)", entryId, duel.duel_id, kept.proof_hash, ticks,
      JSON.stringify({ ...duel.chapter, simulation_version: simulationVersion }), kept.byte_length, kept.body, now);
  }

  /** Keeps the duel table within MAX_BOARD_DUELS: settled duels go first, oldest first. False when every row is still open. */
  private makeRoom(): boolean {
    const count = this.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM duels").one().n;
    if (count < MAX_BOARD_DUELS) return true;
    const oldest = this.storage.sql.exec<{ duel_id: string }>("SELECT duel_id FROM duels WHERE status NOT IN ('challenged','running') ORDER BY updated_ms LIMIT 1").toArray()[0];
    if (!oldest) return false;
    this.storage.sql.exec("DELETE FROM duels WHERE duel_id=?", oldest.duel_id);
    this.storage.sql.exec("DELETE FROM duel_proofs WHERE duel_id=?", oldest.duel_id);
    return true;
  }

  private duel(id: string): Duel | null {
    const row = this.storage.sql.exec<{ data: string }>("SELECT data FROM duels WHERE duel_id=?", id).toArray()[0];
    return row ? JSON.parse(row.data) as Duel : null;
  }
  private save(duel: Duel): void {
    this.storage.sql.exec("INSERT OR REPLACE INTO duels VALUES (?,?,?,?)", duel.duel_id, duel.status, duel.updated_ms, JSON.stringify(duel));
    if (isFinal(duel)) this.storage.sql.exec("DELETE FROM duel_proofs WHERE duel_id=?", duel.duel_id);
  }
  private present(): boolean {
    let found = known.get(this.storage);
    if (found === undefined) {
      found = this.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type='table' AND name='duels'").toArray().length > 0;
      if (found) known.set(this.storage, true);
    }
    return found;
  }
  private ensure(): void {
    if (this.present()) return;
    for (const sql of TABLES) this.storage.sql.exec(sql);
    known.set(this.storage, true);
  }
}
