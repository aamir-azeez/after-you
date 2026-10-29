import { canonicalJson } from "../protocol";
import { blobBase64, bytesDigest, encodeBlob } from "../blob-codec";
import type { CheckpointV2 } from "../v2/protocol";

/**
 * Runs waiting for the replay job, in the shared blob format (blob-codec.ts):
 * the tagged body of the final checkpoint's canonical JSON, its byte length and
 * the SHA-256 of those bytes (the proof hash a verdict names). Once a run ranks
 * or waits for a person, the same body becomes its kept replay (board.ts
 * lb_replays), with nothing encoded twice.
 *
 * Boards made before this stored their waiting runs raw, in lb_proofs. No
 * migration moves them: each raw row is encoded the first time the board reads
 * it (convertLegacy, before any pending list or verdict), and only the encoded
 * form is ever handed out. A raw row that is checked and dropped first simply
 * goes. lb_proofs keeps its old shape and is only read and emptied now.
 */
export const PROOF_TABLE = "CREATE TABLE IF NOT EXISTS lb_proof_blobs (entry_id TEXT PRIMARY KEY, proof_hash TEXT NOT NULL, byte_length INTEGER NOT NULL, body BLOB NOT NULL) WITHOUT ROWID";
export const LEGACY_PROOF_TABLE = "CREATE TABLE IF NOT EXISTS lb_proofs (entry_id TEXT PRIMARY KEY, proof_hash TEXT NOT NULL, checkpoint TEXT NOT NULL)";
export type EncodedProof = { proof_hash: string; byte_length: number; body: Uint8Array };

/** A final checkpoint as a stored proof: canonical bytes, their hash and the tagged body. Async (compression), so outside any transaction. */
export async function encodeProof(checkpoint: CheckpointV2): Promise<EncodedProof> {
  const bytes = new TextEncoder().encode(canonicalJson(checkpoint));
  return { proof_hash: await bytesDigest(bytes), byte_length: bytes.byteLength, body: await encodeBlob(bytes) };
}

/** A stored body as the pending list sends it: base64 of the tagged body, with its canonical length. */
export function sentProof(proof: EncodedProof): { proof_hash: string; byte_length: number; body: string } {
  return { proof_hash: proof.proof_hash, byte_length: proof.byte_length, body: blobBase64(proof.body) };
}

export class BoardProofs {
  constructor(private readonly storage: DurableObjectStorage) {}

  /** Inside the caller's transaction. */
  put(entryId: string, proof: EncodedProof): void {
    this.storage.sql.exec("INSERT OR REPLACE INTO lb_proof_blobs VALUES (?,?,?,?)", entryId, proof.proof_hash, proof.byte_length, proof.body);
  }

  /** The run's proof hash in either form, or null. */
  hash(entryId: string): string | null {
    return this.storage.sql.exec<{ proof_hash: string }>("SELECT proof_hash FROM lb_proof_blobs WHERE entry_id=?", entryId).toArray()[0]?.proof_hash
      ?? this.storage.sql.exec<{ proof_hash: string }>("SELECT proof_hash FROM lb_proofs WHERE entry_id=?", entryId).toArray()[0]?.proof_hash ?? null;
  }

  /** The run's canonical length, or null; read before its body so a pending list loads only what fits. */
  size(entryId: string): number | null {
    return this.storage.sql.exec<{ byte_length: number }>("SELECT byte_length FROM lb_proof_blobs WHERE entry_id=?", entryId).toArray()[0]?.byte_length ?? null;
  }

  /** The run's encoded proof, or null. */
  get(entryId: string): EncodedProof | null {
    const row = this.storage.sql.exec<{ proof_hash: string; byte_length: number; body: ArrayBuffer }>("SELECT proof_hash,byte_length,body FROM lb_proof_blobs WHERE entry_id=?", entryId).toArray()[0];
    return row ? { proof_hash: row.proof_hash, byte_length: row.byte_length, body: new Uint8Array(row.body) } : null;
  }

  /** Inside the caller's transaction: the run's proof in either form goes. */
  remove(entryId: string): void {
    this.storage.sql.exec("DELETE FROM lb_proof_blobs WHERE entry_id=?", entryId);
    this.storage.sql.exec("DELETE FROM lb_proofs WHERE entry_id=?", entryId);
  }

  /**
   * Encodes every raw row left from before the blob format (or only those of `ids`) and moves it
   * across, once, one row in memory at a time. A row that changed or went while it was encoded is
   * left as it now is. Answers the ids of rows whose text no longer matched their hash: those are
   * gone, and the caller drops their runs.
   */
  async convertLegacy(ids?: readonly string[]): Promise<string[]> {
    const heads = ids ? this.storage.sql.exec<{ entry_id: string; proof_hash: string }>("SELECT entry_id,proof_hash FROM lb_proofs WHERE entry_id IN (SELECT value FROM json_each(?))", JSON.stringify(ids)).toArray()
      : this.storage.sql.exec<{ entry_id: string; proof_hash: string }>("SELECT entry_id,proof_hash FROM lb_proofs").toArray();
    const broken: string[] = [];
    for (const row of heads) {
      const text = this.storage.sql.exec<{ text: string }>("SELECT checkpoint AS text FROM lb_proofs WHERE entry_id=?", row.entry_id).toArray()[0]?.text;
      if (text === undefined) continue;
      const bytes = new TextEncoder().encode(text);
      // The stored hash is the one verdicts already name; a row whose text no longer matches it is dropped, never re-hashed.
      const valid = await bytesDigest(bytes) === row.proof_hash;
      const body = valid ? await encodeBlob(bytes) : null;
      this.storage.transactionSync(() => {
        const still = this.storage.sql.exec<{ proof_hash: string }>("SELECT proof_hash FROM lb_proofs WHERE entry_id=?", row.entry_id).toArray()[0];
        if (still?.proof_hash !== row.proof_hash) return;
        this.storage.sql.exec("DELETE FROM lb_proofs WHERE entry_id=?", row.entry_id);
        if (body) this.put(row.entry_id, { proof_hash: row.proof_hash, byte_length: bytes.byteLength, body });
        else broken.push(row.entry_id);
      });
    }
    return broken;
  }
}
