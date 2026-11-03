import { env } from "cloudflare:workers";
import { reset, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { canonicalJson, digest, type Outcome } from "../src/protocol";
import { ERASED_REPORTER, OPEN_REPORT_CAP, REPORT_INBOX_ROWS, REPORTS_PER_ROOM, REPORTS_PER_TARGET, type ReportBody, type SafetyReport } from "../src/safety";

const DEVICE = "d".repeat(64);
let serial = 0;
const value = <T>(result: Outcome<T>): T => { if (!result.ok) throw new Error(result.code); return result.value; };
const id = (prefix: string) => (prefix + (++serial).toString(36)).padEnd(22, "x").slice(0, 22);
async function reporter(): Promise<string> {
  const owner = id("rep"); value(await env.PLAYERS.getByName(owner).create(owner, DEVICE, "e".repeat(64))); return owner;
}
async function report(owner: string, options: { target?: string; room?: string; reason?: ReportBody["reason"]; created_at?: number } = {}): Promise<SafetyReport> {
  const key = crypto.randomUUID();
  const body: ReportBody = { schema_version: 1, idempotency_key: key, room_family: "relay", room_id: options.room ?? id("room"), reason: options.reason ?? "harassment", photo: null };
  return { ...body, reporter_id: owner, target_id: options.target ?? id("tgt"), request_hash: await digest(canonicalJson({ operation: "safety_report", reporter_id: owner, ...body })),
    report_id: await digest(owner + ":" + key), created_at: options.created_at ?? Date.now(), resolved_at: null };
}
const inbox = () => env.SAFETY_INBOX.getByName("moderation-v1");
/** Fills the inbox with `count` rows straight into its table, `resolved` of them resolved. */
async function fill(count: number, resolved: number, reason: ReportBody["reason"] = "harassment") {
  const now = Date.now();
  await runInDurableObject(inbox(), async (_, ctx) => {
    for (let i = 0; i < count; i++) {
      const row = { ...await report(id("fill"), { reason, created_at: now - 1000 - i }), resolved_at: i < resolved ? now : null };
      ctx.storage.sql.exec("INSERT INTO safety_reports VALUES (?,?,?,?)", row.report_id, row.reporter_id, row.created_at, JSON.stringify(row));
    }
  });
}
async function operator(path: string, body?: unknown) {
  return worker.fetch(new Request("https://reports.test/operator/safety/" + path, { method: body === undefined ? "GET" : "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "198.21.9." + (++serial % 250), Authorization: "Bearer " + "o".repeat(43) }, body: body === undefined ? undefined : JSON.stringify(body) }), { ...env, SAFETY_OPERATOR_TOKEN: "o".repeat(43) } as Env);
}
afterEach(async () => { vi.restoreAllMocks(); await reset(); });

describe("the report inbox stays open for real reports", () => {
  it("counts only open reports: a report that needs room pushes out the oldest resolved one", async () => {
    await fill(REPORT_INBOX_ROWS, 200);
    const fresh = await report(await reporter());
    expect((await inbox().submit(fresh, DEVICE)).ok).toBe(true);
    const all = await inbox().listReports();
    expect(all.length).toBe(REPORT_INBOX_ROWS);
    expect(all.filter(row => row.resolved_at !== null).length).toBe(199);
  });

  it("keeps room for child safety reports past the cap on other reasons, and logs a full inbox once", async () => {
    await fill(OPEN_REPORT_CAP, 0);
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    for (let i = 0; i < 2; i++) expect(await inbox().submit(await report(await reporter()), DEVICE)).toMatchObject({ ok: false, status: 503, code: "report_inbox_full" });
    expect(warn.mock.calls.filter(args => String(args[0]).includes("report_inbox_full")).length).toBe(1);
    expect((await inbox().submit(await report(await reporter(), { reason: "child_safety" }), DEVICE)).ok).toBe(true);
  });

  it("receives the same report again without a second row, and keeps a different one", async () => {
    const owner = await reporter(), target = id("tgt"), room = id("room");
    const first = await report(owner, { target, room });
    value(await inbox().submit(first, DEVICE));
    // The same player, room and photo again: its own receipt (the phone checks it against its request), no new row.
    const again = await report(owner, { target, room });
    expect(await inbox().submit(again, DEVICE)).toEqual({ ok: true, value: { schema_version: 1, report_id: again.report_id, request_hash: again.request_hash, received: true } });
    expect((await inbox().listReports()).map(row => row.report_id)).toEqual([first.report_id]);
    // A child safety report is never folded into another kind; another kind is folded into an open child safety one.
    const child = await report(owner, { target, room, reason: "child_safety" });
    value(await inbox().submit(child, DEVICE));
    value(await inbox().submit(await report(owner, { target, room, reason: "privacy" }), DEVICE));
    // Another room or photo of the same player is its own report.
    value(await inbox().submit(await report(owner, { target }), DEVICE));
    expect((await inbox().listReports()).map(row => row.report_id).sort()).toHaveLength(3);
  });

  it("caps open reports per player and per room a day, except child safety ones", async () => {
    const target = id("tgt");
    for (let i = 0; i < REPORTS_PER_TARGET; i++) value(await inbox().submit(await report(await reporter(), { target }), DEVICE));
    expect(await inbox().submit(await report(await reporter(), { target }), DEVICE)).toMatchObject({ ok: false, status: 429, code: "report_rate_limited" });
    expect((await inbox().submit(await report(await reporter(), { target, reason: "child_safety" }), DEVICE)).ok).toBe(true);
    const room = id("room");
    for (let i = 0; i < REPORTS_PER_ROOM; i++) value(await inbox().submit(await report(await reporter(), { room }), DEVICE));
    expect(await inbox().submit(await report(await reporter(), { room }), DEVICE)).toMatchObject({ ok: false, status: 429 });
    // Resolving them opens the room again.
    for (const row of await inbox().listReports()) if (row.room_id === room) value(await inbox().resolveReport(row.report_id));
    expect((await inbox().submit(await report(await reporter(), { room }), DEVICE)).ok).toBe(true);
  });
});

describe("a deleted reporter's reports", () => {
  it("stay for review without the reporter's id, and still pass a snapshot round trip", async () => {
    const owner = await reporter(), other = await reporter(), kept = await report(owner, { reason: "child_safety" }), second = await report(other);
    value(await inbox().submit(kept, DEVICE)); value(await inbox().submit(second, DEVICE));
    expect((await inbox().eraseReporter(owner)).ok).toBe(true);
    const rows = await inbox().listReports(), erased = rows.find(row => row.report_id === kept.report_id)!;
    expect(rows.length).toBe(2);
    expect(erased.reporter_id).toBe(ERASED_REPORTER);
    expect(JSON.stringify(erased)).not.toContain(owner);
    expect(await inbox().reportReceipt(owner, kept.idempotency_key)).toMatchObject({ ok: false, status: 404 });
    const restored = env.SAFETY_INBOX.get(env.SAFETY_INBOX.newUniqueId());
    expect((await restored.restoreSnapshot(await inbox().exportSnapshot())).ok).toBe(true);
    expect((await restored.listReports()).length).toBe(2);
    // The operator cannot block on behalf of a reporter who is gone.
    expect((await operator("reports/" + kept.report_id + "/block", { schema_version: 1 })).status).toBe(409);
  });
});

describe("operator purge", () => {
  it("removes one report, or every report resolved long enough ago", async () => {
    const a = await report(await reporter()), b = await report(await reporter()), c = await report(await reporter());
    for (const item of [a, b, c]) value(await inbox().submit(item, DEVICE));
    value(await inbox().resolveReport(b.report_id)); value(await inbox().resolveReport(c.report_id));
    expect(await (await operator("reports/" + a.report_id + "/purge", { schema_version: 1 })).json()).toEqual({ schema_version: 1, purged: 1 });
    expect(await (await operator("reports/purge-resolved", { schema_version: 1, resolved_days_ago: 1 })).json()).toEqual({ schema_version: 1, purged: 0 });
    expect(await (await operator("reports/purge-resolved", { schema_version: 1, resolved_days_ago: 0 })).json()).toEqual({ schema_version: 1, purged: 2 });
    expect(await inbox().listReports()).toEqual([]);
    expect((await operator("reports/purge-resolved", { schema_version: 1, resolved_days_ago: 91 })).status).toBe(400);
    expect((await operator("reports/purge-resolved", { schema_version: 1 })).status).toBe(400);
  });
});
