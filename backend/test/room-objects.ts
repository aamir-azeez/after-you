import { runInDurableObject as openObject } from "cloudflare:test";
import { ensureTables } from "../src/lazy-storage";

type Callback = (instance: object, state: DurableObjectState) => unknown;
/**
 * runInDurableObject for tests that write an object's storage directly, as campaign setup does.
 * Rooms, Players and SafetyProfiles create their tables on their first write, so the tables are created first here.
 */
export const runInDurableObject = ((stub: DurableObjectStub, callback: Callback) =>
  (openObject as unknown as (stub: DurableObjectStub, callback: Callback) => Promise<unknown>)(stub, (instance, state) => { ensureTables(instance); return callback(instance, state); })) as unknown as typeof openObject;
