import type { ServerVars } from "../flags";

/**
 * Keys derived from the one server-only POLLEN_SECRET with HKDF-SHA256, so new uses need
 * no new var or secret. Each use has its own fixed label (the HKDF info); a key never
 * leaves the worker and is never the RevenueCat key.
 *
 * - HKDF salt: KEY_SALT; info: the label; output: 32 bytes, imported as an HMAC-SHA256 key.
 * - A secret shorter than MIN_SECRET_LENGTH reads as unset: nothing that needs a key runs.
 * - Keys are cached at module scope by secret and label, so a worker instance derives each once.
 */
export const KEY_LABELS = Object.freeze({
  /** Lucky blooms on bank turns (pollen/blooms.ts). */
  bloom: "pollen-bloom-v1",
  /** Item blooms (pollen/item-blooms.ts). */
  itemBloom: "item-bloom-v1",
  /** The holder of a store purchase in PollenClaims (pollen/claims.ts), so no row there names a player. */
  claims: "pollen-claims-v1",
  /** The RevenueCat webhook token (Phase 6). Reserved; nothing derives it yet. */
  webhook: "revenuecat-webhook-v1"
} as const);
export type KeyLabel = typeof KEY_LABELS[keyof typeof KEY_LABELS];
export const KEY_SALT = "after-you-pollen-keys-v1";
export const MIN_SECRET_LENGTH = 32;

/** The secret when it is long enough to use, else null. */
export function pollenSecret(env: ServerVars): string | null {
  const secret = env.POLLEN_SECRET;
  return typeof secret === "string" && secret.length >= MIN_SECRET_LENGTH ? secret : null;
}

const cache = new Map<string, Promise<CryptoKey>>();
const encoder = new TextEncoder();

/** The HMAC key for `label`, or null while the secret is unset or too short. */
export function derivedKey(env: ServerVars, label: KeyLabel): Promise<CryptoKey> | null {
  const secret = pollenSecret(env);
  if (secret === null) return null;
  const id = label + "\u0000" + secret;
  let key = cache.get(id);
  if (!key) {
    key = derive(secret, label);
    // A failed derivation is not kept, so the next call tries again.
    key.catch(() => cache.delete(id));
    // At most a few labels times a secret rotation: keep the newest handful.
    if (cache.size >= 8) cache.delete(cache.keys().next().value!);
    cache.set(id, key);
  }
  return key;
}

async function derive(secret: string, label: KeyLabel): Promise<CryptoKey> {
  const root = await crypto.subtle.importKey("raw", encoder.encode(secret), "HKDF", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: encoder.encode(KEY_SALT), info: encoder.encode(label) }, root, 256);
  return crypto.subtle.importKey("raw", bits, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
}

/** HMAC-SHA256 of `message` under `key`. */
export async function hmac(key: CryptoKey, message: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(message)));
}
