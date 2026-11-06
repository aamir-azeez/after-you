import { runInDurableObject } from "cloudflare:test";

/**
 * Quota meters in the measurement style of the server audit. Cloudflare bills Durable Object
 * requests and SQLite rows read and written; these count the same things inside the test runtime.
 */
export type Rows = { read: number; written: number };

/** Rows each object's SQL reads and writes while `work` runs (workerd's own cursor counters); `only`: just the statements it matches. */
export async function meterRows<T>(stubs: Record<string, DurableObjectStub>, work: () => Promise<T>, only?: RegExp): Promise<{ value: T; rows: Record<string, Rows> }> {
  const cursors: Record<string, SqlStorageCursor<Record<string, SqlStorageValue>>[]> = {};
  const restore: (() => Promise<void>)[] = [];
  for (const [name, stub] of Object.entries(stubs)) {
    cursors[name] = [];
    await runInDurableObject(stub, async (_, ctx) => {
      const sql = ctx.storage.sql, original = sql.exec;
      sql.exec = ((query: string, ...bindings: SqlStorageValue[]) => {
        const cursor = original.call(sql, query, ...bindings); if (!only || only.test(query)) cursors[name].push(cursor); return cursor;
      }) as typeof sql.exec;
      restore.push(() => runInDurableObject(stub, async (__, again) => { again.storage.sql.exec = original; }));
    });
  }
  try {
    const value = await work();
    const rows: Record<string, Rows> = {};
    for (const [name, list] of Object.entries(cursors)) rows[name] = { read: list.reduce((sum, c) => sum + c.rowsRead, 0), written: list.reduce((sum, c) => sum + c.rowsWritten, 0) };
    return { value, rows };
  } finally { for (const undo of restore) await undo(); }
}

const NAMESPACES = ["PLAYERS", "ROOMS", "ROOMS_V2", "SAFETY_PROFILES", "PLATFORM_LINKS", "LEADERBOARD_BOARDS", "LEADERBOARD_MEMBERS", "POLLEN_CLAIMS"] as const;
/**
 * A copy of `base` whose Durable Object stubs count every RPC the Worker makes, by method name.
 * Calls one object makes to another inside the runtime use the runtime's own bindings and are not counted.
 */
export function countingEnv(base: Env): { env: Env; calls: string[] } {
  const calls: string[] = [], counted: Env = { ...base };
  for (const name of NAMESPACES) {
    const namespace = base[name] as unknown as DurableObjectNamespace;
    (counted as unknown as Record<string, unknown>)[name] = new Proxy(namespace, { get(target, key) {
      if (key !== "getByName") { const value = Reflect.get(target, key); return typeof value === "function" ? value.bind(target) : value; }
      return (id: string) => {
        const stub = target.getByName(id);
        return new Proxy(stub, { get(inner, method) {
          const value = Reflect.get(inner, method);
          if (typeof method !== "string" || typeof value !== "function" || method === "fetch") return value;
          // An RPC method is itself a stub, so call it through the stub rather than with apply().
          return (...args: unknown[]) => { calls.push(`${name}.${method}`); return (inner as unknown as Record<string, (...a: unknown[]) => unknown>)[method](...args); };
        } });
      };
    } });
  }
  return { env: counted, calls };
}

/**
 * Rows every object in this runtime reads and writes while `work` runs, constructors included,
 * so a request that creates storage in an object nobody has opened yet is counted too.
 */
export async function meterAllRows<T>(work: () => Promise<T>): Promise<{ value: T; rows: Rows }> {
  const { env } = await import("cloudflare:workers");
  const sqlClass = await runInDurableObject(env.PLAYERS.getByName("meter-probe-player-00"), async (_, ctx) => Object.getPrototypeOf(ctx.storage.sql) as { exec: SqlStorage["exec"] });
  const original = sqlClass.exec, cursors: SqlStorageCursor<Record<string, SqlStorageValue>>[] = [];
  sqlClass.exec = function (this: SqlStorage, query: string, ...bindings: SqlStorageValue[]) {
    const cursor = original.call(this, query, ...bindings); cursors.push(cursor); return cursor;
  } as SqlStorage["exec"];
  try {
    const value = await work();
    return { value, rows: { read: cursors.reduce((sum, c) => sum + c.rowsRead, 0), written: cursors.reduce((sum, c) => sum + c.rowsWritten, 0) } };
  } finally { sqlClass.exec = original; }
}

/** Every Durable Object namespace the Worker binds (wrangler.jsonc). */
/** Marks a binding countAllRequests wrapped, so a binding two env objects share is wrapped once, even after a run that never finished. */
const WRAPPED = Symbol.for("after-you-meter-counted");
const ALL_NAMESPACES = ["PLAYERS", "ROOMS", "ROOMS_V2", "SAFETY_PROFILES", "SAFETY_INBOX", "FRIEND_ROOM_EVENTS", "PHOTO_TRANSFERS", "PHOTO_TRANSFER_BUDGET",
  "PLATFORM_LINKS", "LEADERBOARD_BOARDS", "LEADERBOARD_MEMBERS", "POLLEN_CLAIMS", "PUBLIC_DUEL_DIRECTORY"] as const;
/**
 * Every Durable Object request while `work` runs, by `NAMESPACE.method`, the way the daily quota counts them: the
 * Worker's own (made through the `counted` env handed to `work`) and the ones objects make to each other (their shared
 * env is wrapped for the call and put back after, so other tests see it untouched). `settle_ms` lets requests sent
 * after the reply (waitUntil) land first. Unlike countingEnv, an object's own calls to a peer are counted too, which is
 * what a pin on a request's full cost needs. Stubs for runInDurableObject are made before the call (a counted stub is
 * not one).
 */
export async function countAllRequests<T>(base: Env, work: (counted: Env) => Promise<T>, settle_ms = 50): Promise<{ value: T; calls: string[] }> {
  const { runInDurableObject } = await import("cloudflare:test");
  const calls: string[] = [];
  let on = true;
  const wrap = (name: string, namespace: DurableObjectNamespace): DurableObjectNamespace => new Proxy(namespace, { get(target, key) {
    if (key === WRAPPED) return true;
    const value = Reflect.get(target, key);
    if (key !== "getByName" && key !== "get") return typeof value === "function" ? value.bind(target) : value;
    return (...args: unknown[]) => {
      const stub = Reflect.apply(value as (...a: unknown[]) => object, target, args);
      return new Proxy(stub, { get(inner, method) {
        const member = Reflect.get(inner, method);
        if (typeof method !== "string" || typeof member !== "function") return member;
        // An RPC method is itself a stub, so call it through the stub rather than with apply().
        return (...rest: unknown[]) => { if (on) calls.push(`${name}.${method}`); return (inner as unknown as Record<string, (...a: unknown[]) => unknown>)[method](...rest); };
      } });
    };
  } });
  const objects = new Set<Record<string, unknown>>([base as unknown as Record<string, unknown>]);
  for (const name of ALL_NAMESPACES) {
    const namespace = (base as unknown as Record<string, DurableObjectNamespace>)[name];
    if (namespace) await runInDurableObject(namespace.getByName("meter-probe-" + name), async instance => { objects.add(Reflect.get(instance, "env") as Record<string, unknown>); });
  }
  const restore: (() => void)[] = [];
  for (const target of objects) for (const name of ALL_NAMESPACES) {
    const original = target[name] as DurableObjectNamespace | undefined;
    // Two env objects may share one binding (the runtime's env and the objects'): it is wrapped once.
    if (!original || (original as unknown as Record<symbol, unknown>)[WRAPPED]) continue;
    target[name] = wrap(name, original); restore.push(() => { target[name] = original; });
  }
  const counted = { ...base } as Env;
  try {
    const value = await work(counted);
    if (settle_ms > 0) await new Promise(resolve => setTimeout(resolve, settle_ms));
    return { value, calls };
  } finally { on = false; for (const undo of restore.reverse()) undo(); }
}
