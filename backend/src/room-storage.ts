/**
 * Room objects (legacy Room and RoomV2) create their tables on first use by a method that may write,
 * not when constructed, so a request for a room that never existed stores nothing.
 *
 * - An object whose `room` table exists is set up when constructed, exactly as before.
 * - While an object has no tables, each method named in its `blank` answers is answered as an empty
 *   room always answered (pinned by test/blank-room.test.ts). Any other method first creates the
 *   tables, then runs. A new method is therefore safe by default: it creates storage as before.
 */
export type BlankAnswers<T> = { [K in keyof T]?: T[K] extends (...args: infer A) => infer R ? (...args: A) => R : never };

/** Objects that have no tables yet, with the function that creates them. */
const blankRooms = new WeakMap<object, () => void>();

/** Called from the constructor's blockConcurrencyWhile with the setup the constructor used to run. */
export function openRoomStorage(room: object, storage: DurableObjectStorage, createTables: () => void): void {
  let exists = true;
  // Both families create `room` with the rest of their tables; a missing table means nothing was ever stored.
  try { storage.sql.exec("SELECT 1 FROM room LIMIT 1").toArray(); } catch { exists = false; }
  if (exists) createTables(); else blankRooms.set(room, createTables);
}

/** Creates a blank object's tables now, as its first write does. Tests that write storage directly use it too. */
export function ensureRoomTables(room: object): void {
  const createTables = blankRooms.get(room);
  if (createTables) { createTables(); blankRooms.delete(room); }
}

/** Wraps every method of `room` once, at module load. */
export function answerWhileBlank<T extends object>(room: { prototype: T }, blank: BlankAnswers<T>): void {
  const prototype = room.prototype as Record<string, unknown>, answers = blank as Record<string, ((...args: unknown[]) => unknown) | undefined>;
  for (const name of Object.getOwnPropertyNames(prototype)) {
    const method = Object.getOwnPropertyDescriptor(prototype, name)?.value;
    if (name === "constructor" || typeof method !== "function") continue;
    const answer = answers[name];
    prototype[name] = function (this: object, ...args: unknown[]) {
      if (blankRooms.has(this)) {
        if (answer) return answer.apply(this, args);
        ensureRoomTables(this);
      }
      return method.apply(this, args);
    };
  }
}
