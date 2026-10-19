/**
 * The signed link in the waitlist's confirm email: base64url(JSON {e: email, x: expiry in unix seconds}), a dot, and
 * base64url(HMAC-SHA256) of that payload under WAITLIST_CONFIRM_SECRET. Nothing is stored; the link itself carries
 * the address, so confirming needs no lookup and no Durable Object.
 */
export const CONFIRM_TTL_SECONDS = 7 * 24 * 60 * 60;
/** Secrets shorter than this are treated as unset. */
export const MIN_CONFIRM_SECRET_LENGTH = 32;
const CONTEXT = "after-you-waitlist-confirm-v1.";
export const TOKEN_PATTERN = /^[A-Za-z0-9_-]{8,700}\.[A-Za-z0-9_-]{43}$/;

const encoder = new TextEncoder();
function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function fromBase64url(text: string): Uint8Array | null {
  try {
    const binary = atob(text.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - text.length % 4) % 4));
    return Uint8Array.from(binary, char => char.charCodeAt(0));
  } catch { return null; }
}
function key(secret: string, use: "sign" | "verify"): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [use]);
}

export async function signConfirmToken(email: string, secret: string, nowSeconds: number): Promise<string> {
  const payload = base64url(encoder.encode(JSON.stringify({ e: email, x: nowSeconds + CONFIRM_TTL_SECONDS })));
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", await key(secret, "sign"), encoder.encode(CONTEXT + payload)));
  return payload + "." + base64url(mac);
}

export type TokenCheck = { ok: true; email: string } | { ok: false; reason: "invalid" | "expired" };
/** Checks the signature first (in constant time), then the expiry. A forged token never reveals whether it expired. */
export async function verifyConfirmToken(token: unknown, secret: string, nowSeconds: number): Promise<TokenCheck> {
  if (typeof token !== "string" || !TOKEN_PATTERN.test(token)) return { ok: false, reason: "invalid" };
  const [payload, signature] = token.split(".");
  const mac = fromBase64url(signature);
  if (!mac || mac.length !== 32 || !await crypto.subtle.verify("HMAC", await key(secret, "verify"), mac, encoder.encode(CONTEXT + payload))) return { ok: false, reason: "invalid" };
  let body: unknown;
  try { body = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(fromBase64url(payload) ?? new Uint8Array())); } catch { return { ok: false, reason: "invalid" }; }
  if (!body || typeof body !== "object") return { ok: false, reason: "invalid" };
  const { e, x } = body as Record<string, unknown>;
  if (typeof e !== "string" || typeof x !== "number" || !Number.isInteger(x)) return { ok: false, reason: "invalid" };
  if (nowSeconds > x) return { ok: false, reason: "expired" };
  return { ok: true, email: e };
}
