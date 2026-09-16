import { isObject } from "./protocol";

export type PlayEntitlementConfig = {
  REVENUECAT_SECRET_KEY?: string; REVENUECAT_PROJECT_ID?: string;
  REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID?: string; REVENUECAT_PLAY_PRODUCT_ID?: string;
  REVENUECAT_PLAY_ENVIRONMENT?: string;
  REVENUECAT_REVIEWER_IDS?: string;
};
export type ProviderResult = { ok: true; status: number; value: unknown } | { ok: false; reason: string };

/** Provider bodies and redirects are bounded; caller data never enters logs. */
export async function revenuecatRequest(url: string, key: string, method = "GET"): Promise<ProviderResult> {
  try {
    const response = await fetch(url, { method, redirect: "manual", signal: AbortSignal.timeout(8000), headers: { Authorization: `Bearer ${key}`, Accept: "application/json" } });
    if (method === "DELETE" && (response.status === 200 || response.status === 404)) {
      await response.body?.cancel(); return { ok: true, status: response.status, value: null };
    }
    if (response.status === 404) { await response.body?.cancel(); return { ok: true, status: 404, value: null }; }
    if (!response.ok) { await response.body?.cancel(); return { ok: false, reason: `provider_http_${response.status}` }; }
    if (!response.body) return { ok: false, reason: "provider_empty_response" };
    const reader = response.body.getReader(); const parts: Uint8Array[] = []; let length = 0;
    try {
      while (true) {
        const item = await reader.read(); if (item.done) break;
        length += item.value.byteLength;
        if (length > 262144) { await reader.cancel(); return { ok: false, reason: "provider_response_too_large" }; }
        parts.push(item.value);
      }
    } finally { reader.releaseLock(); }
    const bytes = new Uint8Array(length); let offset = 0;
    for (const part of parts) { bytes.set(part, offset); offset += part.byteLength; }
    return { ok: true, status: response.status, value: JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes)) };
  } catch { return { ok: false, reason: "provider_request_or_decode_failed" }; }
}

/** This policy is selected by server configuration, never a caller header. */
export async function playEntitlement(playerId: string, config: PlayEntitlementConfig): Promise<{ full_journey: boolean; status: "verified" | "unconfigured" | "unavailable"; reason?: string; access_source?: "review_grant" | "play_purchase"; entitlement?: "full_journey_play"; player_id?: string }> {
  const environment = config.REVENUECAT_PLAY_ENVIRONMENT ?? "production";
  if (!config.REVENUECAT_SECRET_KEY || !/^[A-Za-z0-9_-]{4,100}$/.test(config.REVENUECAT_PROJECT_ID ?? "") ||
      !/^entl[A-Za-z0-9_-]+$/.test(config.REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID ?? "") ||
      !/^prod[A-Za-z0-9_-]+$/.test(config.REVENUECAT_PLAY_PRODUCT_ID ?? "") ||
      !["production", "sandbox"].includes(environment)) return { full_journey: false, status: "unconfigured" };
  const base = `https://api.revenuecat.com/v2/projects/${encodeURIComponent(config.REVENUECAT_PROJECT_ID!)}/customers/${encodeURIComponent(playerId)}`;
  const active = await revenuecatRequest(`${base}/active_entitlements?limit=100`, config.REVENUECAT_SECRET_KEY);
  if (!active.ok) return { full_journey: false, status: "unavailable", reason: active.reason };
  if (active.status === 404) return { full_journey: false, status: "verified" };
  const list = active.value;
  if (!isObject(list) || list.object !== "list" || !Array.isArray(list.items) || list.items.length > 100) return { full_journey: false, status: "unavailable", reason: "provider_invalid_list" };
  const grant = list.items.find(entry => isObject(entry) && entry.entitlement_id === config.REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID);
  if (!isObject(grant)) return { full_journey: false, status: list.next_page ? "unavailable" : "verified", ...(list.next_page ? { reason: "provider_incomplete_list" } : {}) };
  if (!(grant.expires_at === null || (typeof grant.expires_at === "number" && Number.isFinite(grant.expires_at) && grant.expires_at > Date.now()))) return { full_journey: false, status: "verified" };
  // Review access is an actual provider entitlement plus an operator-managed
  // exact identity allowlist. The allowlist alone never grants access.
  const reviewers = (config.REVENUECAT_REVIEWER_IDS ?? "").split(",").map(value => value.trim()).filter(Boolean);
  if (reviewers.length <= 16 && reviewers.every(value => /^[A-Za-z0-9_-]{22}$/.test(value)) && reviewers.includes(playerId)) return { full_journey: true, status: "verified", access_source: "review_grant", entitlement: "full_journey_play", player_id: playerId };
  const purchases = await revenuecatRequest(`${base}/purchases?environment=${environment}&limit=100`, config.REVENUECAT_SECRET_KEY);
  if (!purchases.ok) return { full_journey: false, status: "unavailable", reason: purchases.reason };
  if (purchases.status === 404) return { full_journey: false, status: "verified" };
  const records = purchases.value;
  if (!isObject(records) || records.object !== "list" || !Array.isArray(records.items) || records.items.length > 100) return { full_journey: false, status: "unavailable", reason: "provider_invalid_list" };
  const owned = records.items.some(item => isObject(item) && item.object === "purchase" && item.product_id === config.REVENUECAT_PLAY_PRODUCT_ID &&
    item.store === "play_store" && item.environment === environment && item.status === "owned" && item.ownership === "purchased" &&
    typeof item.purchased_at === "number" && Number.isSafeInteger(item.purchased_at) && item.purchased_at > 0 && item.purchased_at <= Date.now());
  if (owned) return { full_journey: true, status: "verified", access_source: "play_purchase", entitlement: "full_journey_play", player_id: playerId };
  return { full_journey: false, status: records.next_page ? "unavailable" : "verified", ...(records.next_page ? { reason: "provider_incomplete_list" } : {}) };
}
