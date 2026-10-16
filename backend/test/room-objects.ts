import { runInDurableObject as openObject } from "cloudflare:test";
import { ensureRoomTables } from "../src/room-storage";

type Callback = (instance: object, state: DurableObjectState) => unknown;
/**
 * runInDurableObject for tests that write a room's storage directly, as campaign setup does.
 * A room object creates its tables on its first write, so the tables are created first here.
 */
export const runInDurableObject = ((stub: DurableObjectStub, callback: Callback) =>
  (openObject as unknown as (stub: DurableObjectStub, callback: Callback) => Promise<unknown>)(stub, (instance, state) => { ensureRoomTables(instance); return callback(instance, state); })) as unknown as typeof openObject;
