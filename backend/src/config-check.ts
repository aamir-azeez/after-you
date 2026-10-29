import { ApiError, boundedJson, exactKeys, object } from "./protocol";
import { FLAG_NAMES, type ServerVars } from "./flags";
import { requireOperator } from "./operator-auth";
import { MAX_CONFIG_LENGTH, legacyConfig, parseConfig, type ServerConfig } from "./config";

/**
 * TRANSITION, removed by the cleanup commit with legacyConfig. POST /operator/config/check
 * {schema_version 1, config: "<a CONFIG value>"} answers, key by key, whether that CONFIG says exactly what the old
 * vars and secrets this Worker runs with say. It is how the deploy runner proves a CONFIG built from live vars and
 * the owner's RevenueCat ids before it writes it, without anyone reading a secret: the answer holds only booleans,
 * and nothing in the body or the comparison is logged. Retired flags are left out of the comparison, since the
 * code no longer reads them.
 */
export const CONFIG_CHECK_PATH = "/operator/config/check";

const sameList = (a: readonly string[] | null, b: readonly string[] | null) => a === null || b === null ? a === b : a.length === b.length && a.every((item, i) => item === b[i]);
const sameMap = (a: ReadonlyMap<string, string>, b: ReadonlyMap<string, string>) => a.size === b.size && [...a].every(([key, value]) => b.get(key) === value);

/** Each key of ServerConfig, and each RevenueCat id, compared. */
export function compareConfigs(candidate: ServerConfig, current: ServerConfig): Record<string, boolean> {
  const known = (features: ReadonlySet<string>) => [...features].filter(name => FLAG_NAMES.has(name)).sort();
  const a = candidate.revenuecat, b = current.revenuecat;
  return {
    features: sameList(known(candidate.features), known(current.features)),
    min_client_version: JSON.stringify(Object.entries(candidate.min_client_version).sort()) === JSON.stringify(Object.entries(current.min_client_version).sort()),
    friend_aliases: sameMap(candidate.friend_aliases.byAlias, current.friend_aliases.byAlias),
    "revenuecat.project_id": a.project_id === b.project_id,
    "revenuecat.play_entitlement_lookup_id": a.play_entitlement_lookup_id === b.play_entitlement_lookup_id,
    "revenuecat.play_product_id": a.play_product_id === b.play_product_id,
    "revenuecat.play_subscription_product_ids": sameList(a.play_subscription_product_ids, b.play_subscription_product_ids),
    "revenuecat.app_store_subscription_product_ids": sameList(a.app_store_subscription_product_ids, b.app_store_subscription_product_ids),
    "revenuecat.app_store_environment": a.app_store_environment === b.app_store_environment,
    "revenuecat.app_store_entitlement_lookup_id": a.app_store_entitlement_lookup_id === b.app_store_entitlement_lookup_id,
    "revenuecat.reviewer_ids": sameList(a.reviewer_ids, b.reviewer_ids),
  };
}

export async function routeConfigCheck(request: Request, env: ServerVars): Promise<unknown> {
  await requireOperator(request, env);
  if (request.method !== "POST") throw new ApiError(405, "method_not_allowed");
  const input = object(await boundedJson(request, MAX_CONFIG_LENGTH + 1024)); exactKeys(input, ["schema_version", "config"]);
  if (input.schema_version !== 1 || typeof input.config !== "string") throw new ApiError(400, "invalid_config_check");
  const check = parseConfig(input.config, FLAG_NAMES);
  if (check.problems.length || check.unknown.length) return { schema_version: 1, valid: false, problems: check.problems, unknown: check.unknown };
  const keys = compareConfigs(check.config, legacyConfig(env));
  return { schema_version: 1, valid: true, config_var_present: env.CONFIG !== undefined, same: Object.values(keys).every(Boolean), keys };
}
