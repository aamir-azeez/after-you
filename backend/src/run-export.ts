import type { ServerVars } from "./flags";
import { serverConfig } from "./config";

/**
 * Export this run: the owner's own phone may hand a whole kept attempt to the system share sheet as
 * its history blob file. Only the player CONFIG's friend_aliases names as OWNER_ALIAS is told so, on
 * the capabilities read the phone makes anyway: no request, Durable Object call or row of its own.
 * An invalid alias map has no aliases (config.ts fails closed), so nobody is told.
 */
/** Sent on GET /v2/capabilities by builds that can export a run; everyone else gets the same bytes as before. */
export const RUN_EXPORT_HEADER = "X-AfterYou-Run-Export";
export const RUN_EXPORT_VERSION = 1;
/** The friend_aliases name whose player may export runs. */
export const RUN_EXPORT_ALIAS = "aamir";

/** True only for the aliased owner, on a request from a build that asked. */
export function runExportAllowed(request: Request, playerId: string, env: ServerVars): boolean {
  if (request.headers.get(RUN_EXPORT_HEADER) !== "1") return false;
  const owner = serverConfig(env).friend_aliases.byAlias.get(RUN_EXPORT_ALIAS);
  return owner !== undefined && owner === playerId;
}

/** The capability field for GET /v2/capabilities: empty unless runExportAllowed. */
export function runExportCapability(request: Request, playerId: string, env: ServerVars): { run_export_version?: number } {
  return runExportAllowed(request, playerId, env) ? { run_export_version: RUN_EXPORT_VERSION } : {};
}
