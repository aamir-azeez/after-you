import { isObject } from "./protocol";
import { playEntitlement, type PlayEntitlementConfig } from "./play-entitlement";

export type Entitlement = { full_journey: boolean; status: "verified" | "unconfigured" | "unavailable"; environment: string; checked_at: string; reason?: string; access_source?: "review_grant" | "play_purchase" | "tester_grant"; entitlement?: "full_journey_play" | "full_journey"; player_id?: string };
type RevenueCatConfiguration = Pick<Env, "ENVIRONMENT" | "REVENUECAT_ENTITLEMENT"> & PlayEntitlementConfig & {
  PLAYERS?: Env["PLAYERS"];
  REVENUECAT_VERIFICATION_MODE?: string;
  REVENUECAT_SECRET_KEY?: string; REVENUECAT_API_VERSION?: string;
  REVENUECAT_PROJECT_ID?: string; REVENUECAT_ENTITLEMENT_LOOKUP_ID?: string;
};
export function makeProviderRequest(endpoint: string, key: string): Request {
  // Workers supports manual/follow, not redirect:error. Never forward the credential on a redirect.
  return new Request(endpoint, {
    headers: { Authorization: `Bearer ${key}`, Accept: "application/json" },
    signal: AbortSignal.timeout(8000), redirect: "manual"
  });
}
export async function entitlement(playerId: string, env: RevenueCatConfiguration): Promise<Entitlement> {
  const base = { full_journey: false, environment: env.ENVIRONMENT, checked_at: new Date().toISOString() };
  if (env.PLAYERS) {
    const grant = await env.PLAYERS.getByName(playerId).storedTesterGrant(playerId);
    if (grant) return { ...base, full_journey: true, status: "verified", access_source: "tester_grant", entitlement: "full_journey", player_id: playerId };
  }
  if (env.REVENUECAT_VERIFICATION_MODE === "play_store") return { ...base, ...await playEntitlement(playerId, env) };
  if (env.REVENUECAT_VERIFICATION_MODE && env.REVENUECAT_VERIFICATION_MODE !== "demo") return { ...base, status: "unconfigured" };
  if (!env.REVENUECAT_SECRET_KEY) return { ...base, status: "unconfigured" };
  const v2 = env.REVENUECAT_API_VERSION === "2";
  if (env.REVENUECAT_API_VERSION && !["1", "2"].includes(env.REVENUECAT_API_VERSION)) return { ...base, status: "unconfigured" };
  if (v2 && (!/^[a-zA-Z0-9_-]{4,100}$/.test(env.REVENUECAT_PROJECT_ID || "") || !/^entl[a-zA-Z0-9_-]+$/.test(env.REVENUECAT_ENTITLEMENT_LOOKUP_ID || ""))) return { ...base, status: "unconfigured" };
  const endpoint = v2
    ? `https://api.revenuecat.com/v2/projects/${encodeURIComponent(env.REVENUECAT_PROJECT_ID!)}/customers/${encodeURIComponent(playerId)}/active_entitlements?limit=100`
    : `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(playerId)}`;
  try {
    const response = await fetch(makeProviderRequest(endpoint, env.REVENUECAT_SECRET_KEY));
    if (response.status === 404) return { ...base, status: "verified" };
    if (!response.ok) return { ...base, status: "unavailable", reason: `provider_http_${response.status}` };
    if (!response.body) return { ...base, status: "unavailable", reason: "provider_empty_response" };
    const reader = response.body.getReader(); let size = 0; const chunks: Uint8Array[] = [];
    try {
      while (true) {
        const next = await reader.read(); if (next.done) break;
        size += next.value.byteLength;
        if (size > 262_144) { await reader.cancel(); return { ...base, status: "unavailable", reason: "provider_response_too_large" }; }
        chunks.push(next.value);
      }
    } finally { reader.releaseLock(); }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    const data: unknown = JSON.parse(new TextDecoder().decode(bytes));
    if (v2) {
      if (!isObject(data) || data.object !== "list" || !Array.isArray(data.items)) return { ...base, status: "unavailable", reason: "provider_invalid_list" };
      const entry = data.items.find(item => isObject(item) && item.entitlement_id === env.REVENUECAT_ENTITLEMENT_LOOKUP_ID);
      if (!isObject(entry)) return { ...base, status: data.next_page ? "unavailable" : "verified" };
      const expiry = entry.expires_at;
      return { ...base, full_journey: expiry === null || (typeof expiry === "number" && Number.isFinite(expiry) && expiry > Date.now()), status: "verified" };
    }
    if (!isObject(data) || !isObject(data.subscriber) || !isObject(data.subscriber.entitlements)) return { ...base, status: "unavailable", reason: "provider_invalid_subscriber" };
    const entry = data.subscriber.entitlements[env.REVENUECAT_ENTITLEMENT];
    if (!isObject(entry)) return { ...base, status: "verified" };
    const purchaseTime = typeof entry.purchase_date === "string" ? Date.parse(entry.purchase_date) : NaN;
    const expiry = entry.expires_date;
    const active = Number.isFinite(purchaseTime) && purchaseTime <= Date.now() &&
      (expiry === null || (typeof expiry === "string" && Date.parse(expiry) > Date.now()));
    return { ...base, full_journey: active, status: "verified" };
  } catch { return { ...base, status: "unavailable", reason: "provider_request_or_decode_failed" }; }
}
