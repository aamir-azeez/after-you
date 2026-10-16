import { describe, expect, it } from "vitest";
import { JSON_HEADERS, bearerDigest, bytes, json, result } from "../src/http";
import { ApiError, boundedJson, digest, fail, inviteRoomId, newInvite, ok, parseInvite, randomToken, readBounded } from "../src/protocol";

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

function chunked(parts: Uint8Array[], onCancel = () => {}, fail?: Error): ReadableStream<Uint8Array> {
  let index = 0;
  return new ReadableStream({ pull(controller) {
    if (index < parts.length) controller.enqueue(parts[index++]); else if (fail) controller.error(fail); else controller.close();
  }, cancel: onCancel });
}
function jsonRequest(body: BodyInit, headers: Record<string, string> = {}): Request {
  return new Request("https://afteryou.test/x", { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body });
}
async function code(promise: Promise<unknown>): Promise<string> {
  try { await promise; return "ok"; } catch (error) { return error instanceof ApiError ? `${error.status} ${error.code}` : "threw"; }
}

describe("readBounded", () => {
  it("joins every chunk up to the cap and cancels the stream past it", async () => {
    const parts = () => [new Uint8Array([1, 2]), new Uint8Array([3]), new Uint8Array([4, 5])];
    expect([...(await readBounded(chunked(parts()), 5))!]).toEqual([1, 2, 3, 4, 5]);
    let cancelled = false;
    expect(await readBounded(chunked(parts(), () => { cancelled = true; }), 4)).toBeNull();
    expect(cancelled).toBe(true);
    expect([...(await readBounded(chunked([]), 0))!]).toEqual([]);
  });
  it("passes a read error to the caller", async () => {
    await expect(readBounded(chunked([new Uint8Array([1])], undefined, new TypeError("reset")), 10)).rejects.toThrow("reset");
  });
  it("keeps boundedJson's answers: a BOM is skipped, bad UTF-8 and oversize bodies are refused", async () => {
    expect(await boundedJson(jsonRequest(new Uint8Array([0xef, 0xbb, 0xbf, ...new TextEncoder().encode('{"a":1}')])))).toEqual({ a: 1 });
    expect(await code(boundedJson(jsonRequest(new Uint8Array([0x22, 0xff, 0x22]))))).toBe("400 invalid_json");
    expect(await code(boundedJson(jsonRequest(chunked([new TextEncoder().encode('"12345'), new TextEncoder().encode('6789"')])), 8))).toBe("413 body_too_large");
    expect(await code(boundedJson(jsonRequest("{}", { "Content-Type": "text/plain" })))).toBe("415 json_required");
  });
});

describe("invite codes", () => {
  it("reads a typed code the way every join route did", () => {
    expect(parseInvite("abcd-ef01 2345 6789 ABCD")).toBe("ABCDEF0123456789ABCD");
    for (const value of [undefined, 7, "ABCDEF0123456789ABC", "ABCDEF0123456789ABCG", "A".repeat(20) + " ".repeat(21)]) expect(() => parseInvite(value)).toThrow("invalid_invite");
  });
  it("makes 20 hex digits and names one room per family", async () => {
    const code = newInvite();
    expect(code).toMatch(/^[A-F0-9]{20}$/);
    expect(await inviteRoomId(code, 1)).toBe((await digest(code)).slice(0, 22));
    expect(await inviteRoomId(code, 2)).toBe((await digest("v2:" + code)).slice(0, 22));
  });
});
