/**
 * Durable Objects that a request can open by any id (rooms by room id, Player and SafetyProfile by
 * player id) create their tables on first use by a method that may write, not when constructed, so a
 * request naming an object that never existed stores nothing.
 *
 * - An object whose marker table exists is set up when constructed, exactly as before.
 * - While an object has no tables, each method named in its `blank` answers is answered as the same
 *   object with empty tables answers (pinned by test/blank-storage.test.ts). Any other method first
 *   creates the tables, then runs, so a new method is safe by default: it creates storage as before.
 */
export type BlankAnswers<T> = { [K in keyof T]?: T[K] extends (...args: infer A) => infer R ? (...args: A) => R : never };

/** Objects that have no tables yet, with the function that creates them. */
const blankObjects = new WeakMap<object, () => void>();

/**
 * Called from the constructor with the setup the constructor used to run. `marker` is a table that
 * setup always creates (a fixed name, never caller input); if it is missing, nothing was ever stored.
 */
export function openLazyStorage(object: object, storage: DurableObjectStorage, marker: string, createTables: () => void): void {
  let exists = true;
  try { storage.sql.exec(`SELECT 1 FROM ${marker} LIMIT 1`).toArray(); } catch { exists = false; }
  if (exists) createTables(); else blankObjects.set(object, createTables);
}

/** Creates a blank object's tables now, as its first write does. Tests that write storage directly use it too. */
export function ensureTables(object: object): void {
  const createTables = blankObjects.get(object);
  if (createTables) { createTables(); blankObjects.delete(object); }
}

/** Wraps every method of `kind` once, at module load. */
export function answerWhileBlank<T extends object>(kind: { prototype: T }, blank: BlankAnswers<T>): void {
  const prototype = kind.prototype as Record<string, unknown>, answers = blank as Record<string, ((...args: unknown[]) => unknown) | undefined>;
  for (const name of Object.getOwnPropertyNames(prototype)) {
    const method = Object.getOwnPropertyDescriptor(prototype, name)?.value;
    if (name === "constructor" || typeof method !== "function") continue;
    const answer = answers[name];
    prototype[name] = function (this: object, ...args: unknown[]) {
      if (blankObjects.has(this)) {
        if (answer) return answer.apply(this, args);
        ensureTables(this);
      }
      return method.apply(this, args);
    };
  }
}
