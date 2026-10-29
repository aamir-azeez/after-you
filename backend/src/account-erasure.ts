import { ApiError, HASH_PATTERN, ID_PATTERN, equalHash, isObject } from "./protocol";
import type { ServerVars } from "./flags";
import { PROJECT_PATTERN, serverConfig } from "./config";
import { revenuecatRequest } from "./play-entitlement";

export const ERASURE_SCHEMA = "CREATE TABLE safety_erasure (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)";
export type ErasureJob = { schema_version: 1; owner: string; device_hash: string; player_object_id: string; state: "pending" | "accepted" | "complete"; created_at: number; attempts: number; cleanup_attempts: number; next_at: number | null };
export function readErasure(storage: DurableObjectStorage): ErasureJob | null {
  const raw = storage.sql.exec<{ data: string }>("SELECT data FROM safety_erasure WHERE id=1").toArray()[0]; if (!raw) return null;
  return checkedErasure(JSON.parse(raw.data));
}
export function checkedErasure(v: unknown): ErasureJob {
  if (!isObject(v) || Object.keys(v).sort().join() !== ["schema_version", "owner", "device_hash", "player_object_id", "state", "created_at", "attempts", "cleanup_attempts", "next_at"].sort().join() || v.schema_version !== 1 || typeof v.owner !== "string" || !ID_PATTERN.test(v.owner) || typeof v.device_hash !== "string" || !HASH_PATTERN.test(v.device_hash) || typeof v.player_object_id !== "string" || !HASH_PATTERN.test(v.player_object_id) ||
    !["pending", "accepted", "complete"].includes(String(v.state)) || typeof v.created_at !== "number" || !Number.isSafeInteger(v.created_at) || v.created_at <= 0 || typeof v.attempts !== "number" || !Number.isInteger(v.attempts) || v.attempts < 0 || v.attempts > 8 ||
    typeof v.cleanup_attempts !== "number" || !Number.isInteger(v.cleanup_attempts) || v.cleanup_attempts < 0 || v.cleanup_attempts > 8 ||
    !(v.next_at === null || typeof v.next_at === "number" && Number.isSafeInteger(v.next_at) && v.next_at >= v.created_at) ||
    v.state === "complete" && v.next_at !== null) throw new ApiError(409, "unsupported_erasure_state");
  return v as ErasureJob;
}
export function writeErasure(storage: DurableObjectStorage, job: ErasureJob): void { storage.sql.exec("INSERT OR REPLACE INTO safety_erasure VALUES (1,?)", JSON.stringify(job)); }
export function erasureReceipt(storage: DurableObjectStorage, owner: string, deviceHash: string): boolean {
  const job = readErasure(storage); return !!job && job.owner === owner && job.state === "complete" && equalHash(job.device_hash, deviceHash);
}
/**
 * Asks RevenueCat to delete the customer before the identity is forgotten; false holds the erasure for a retry.
 * A deployment with neither REVENUECAT_SECRET_KEY nor a RevenueCat project (local development, tests) has no
 * customers there, so it has nothing to delete. Any half configuration holds, so a lost key or a bad CONFIG never
 * skips a real deletion.
 */
export async function requestProviderErasure(owner: string, env: ServerVars): Promise<boolean> {
  const project = serverConfig(env).revenuecat.project_id;
  if (!env.REVENUECAT_SECRET_KEY && project === undefined) return true;
  if (!env.REVENUECAT_SECRET_KEY || !PROJECT_PATTERN.test(project ?? "")) return false;
  const result = await revenuecatRequest(`https://api.revenuecat.com/v2/projects/${encodeURIComponent(project!)}/customers/${encodeURIComponent(owner)}`, env.REVENUECAT_SECRET_KEY, "DELETE");
  return result.ok && (result.status === 200 || result.status === 404);
}
