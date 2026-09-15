import { ApiError, boundedJson, digest, IDEMPOTENCY_PATTERN, text, type Outcome } from "./protocol";
import { TRANSFER_BODY_BYTES } from "./photo-transfer";

function unwrap<T>(result: Outcome<T>): T { if (!result.ok) throw new ApiError(result.status, result.code); return result.value; }
/** Authenticated account-only transfer; no room read/share or gameplay mutation. */
export async function routePhotoTransfer(request: Request, path: string, owner: string, env: Env): Promise<Response> {
  const upload = path === "/v1/photo-transfer/sessions" || /^\/v1\/photo-transfer\/[^/]+\/entries$/.test(path);
  if (upload && String(env.PHOTO_TRANSFER_ENABLED) !== "true") throw new ApiError(503, "photo_transfer_disabled");
  const limiter = path === "/v1/photo-transfer/restore-ack" ? env.PHOTO_ACK_LIMITER : env.PHOTO_TRANSFER_LIMITER;
  if (!(await limiter.limit({ key: owner + ":transfer" })).success) throw new ApiError(429, "photo_transfer_rate_limited");
  const device = await digest(request.headers.get("Authorization")!.slice(7)), transfer = env.PHOTO_TRANSFERS.getByName(owner);
  let value: unknown;
  if (path === "/v1/photo-transfer" && request.method === "GET") value = unwrap(await transfer.inventory(owner, device));
  else if (path === "/v1/photo-transfer/sessions" && request.method === "POST") value = unwrap(await transfer.start(owner, device, await boundedJson(request, 4096)));
  else if (path === "/v1/photo-transfer/read" && request.method === "POST") value = unwrap(await transfer.read(owner, device, await boundedJson(request, 8192)));
  else if (path === "/v1/photo-transfer/restore-ack" && request.method === "POST") value = unwrap(await transfer.acknowledge(owner, device, await boundedJson(request, 8192)));
  else {
    const operation = path.match(/^\/v1\/photo-transfer\/operations\/([a-zA-Z0-9_-]{8,80})$/);
    const entries = path.match(/^\/v1\/photo-transfer\/([a-zA-Z0-9_-]{8,80})\/entries$/);
    if (operation && request.method === "GET") value = unwrap(await transfer.operation(owner, device, text(operation[1], IDEMPOTENCY_PATTERN)));
    else if (entries && request.method === "POST") value = unwrap(await transfer.upload(owner, device, text(entries[1], IDEMPOTENCY_PATTERN), await boundedJson(request, TRANSFER_BODY_BYTES)));
    else throw new ApiError(404, "not_found");
  }
  return new Response(JSON.stringify(value), { headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/json; charset=utf-8" } });
}
