import { describe, expect, it } from "vitest";
import { JSON_HEADERS, bearerDigest, bytes, json, result } from "../src/http";
import { ApiError, digest, fail, ok, randomToken } from "../src/protocol";

// Frozen copies of the response helpers each router had before http.ts.
const oldIndexHeaders = { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/json; charset=utf-8" };
const OLD_JSON: Record<string, (value: unknown, status?: number) => Response> = {
  index: (value, status = 200) => new Response(JSON.stringify(value), { status, headers: oldIndexHeaders }),
  campaignRoutes: (value, status = 200) => new Response(JSON.stringify(value), { status,
    headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/json; charset=utf-8" } }),
  v2Routes: value => new Response(JSON.stringify(value), { headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/json; charset=utf-8" } }),
  photoTransferRoutes: value => new Response(JSON.stringify(value), { headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/json; charset=utf-8" } }),
};
const oldBytes = (value: Uint8Array) => new Response(value, { headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/octet-stream" } });

async function parts(response: Response) {
  return { status: response.status, statusText: response.statusText, headers: [...response.headers.entries()], body: new Uint8Array(await response.arrayBuffer()) };
}
const VALUES: readonly unknown[] = [{ status: "ok", api_version: 1 }, [], null, "text", 0, { error: { code: "x", retryable: false } }, { nested: { a: [1, "é", null] } }];

describe("http helpers", () => {
  it("answer byte for byte like every old router copy", async () => {
    for (const value of VALUES) {
      for (const [name, old] of Object.entries(OLD_JSON)) expect(await parts(json(value)), name).toEqual(await parts(old(value)));
      for (const status of [200, 201, 400, 409, 503]) expect(await parts(json(value, status))).toEqual(await parts(OLD_JSON.index(value, status)));
      expect(await parts(result(ok(value)))).toEqual(await parts(OLD_JSON.index(value)));
    }
    for (const value of [new Uint8Array(), new Uint8Array([0, 1, 255]), new TextEncoder().encode("attempt")]) expect(await parts(bytes(value))).toEqual(await parts(oldBytes(value)));
    expect(await parts(new Response(null, { status: 405, headers: JSON_HEADERS }))).toEqual(await parts(new Response(null, { status: 405, headers: oldIndexHeaders })));
  });
  it("result() throws the failed outcome's ApiError", () => {
    expect(() => result(fail(409, "room_limit_reached"))).toThrow(ApiError);
    try { result(fail(409, "room_limit_reached")); } catch (error) { expect([(error as ApiError).status, (error as ApiError).code]).toEqual([409, "room_limit_reached"]); }
  });
  it("bearerDigest() hashes the token after Bearer exactly like the old inline reads", async () => {
    for (const token of [randomToken(), randomToken(), "a"]) {
      const request = new Request("https://after-you.test/v1/rooms", { headers: { Authorization: "Bearer " + token } });
      expect(await bearerDigest(request)).toBe(await digest(request.headers.get("Authorization")!.slice(7)));
      expect(await bearerDigest(request)).toBe(await digest(token));
    }
  });
});
