import { runInDurableObject } from "cloudflare:test";

/**
 * Quota meters in the measurement style of the server audit. Cloudflare bills Durable Object
 * requests and SQLite rows read and written; these count the same things inside the test runtime.
 */
export type Rows = { read: number; written: number };

/** Rows each object's SQL reads and writes while `work` runs (workerd's own cursor counters). */
export async function meterRows<T>(stubs: Record<string, DurableObjectStub>, work: () => Promise<T>): Promise<{ value: T; rows: Record<string, Rows> }> {
  const cursors: Record<string, SqlStorageCursor<Record<string, SqlStorageValue>>[]> = {};
  const restore: (() => Promise<void>)[] = [];
  for (const [name, stub] of Object.entries(stubs)) {
    cursors[name] = [];
    await runInDurableObject(stub, async (_, ctx) => {
      const sql = ctx.storage.sql, original = sql.exec;
      sql.exec = ((query: string, ...bindings: SqlStorageValue[]) => {
        const cursor = original.call(sql, query, ...bindings); cursors[name].push(cursor); return cursor;
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

const NAMESPACES = ["PLAYERS", "ROOMS", "ROOMS_V2", "SAFETY_PROFILES", "PLATFORM_LINKS"] as const;
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
