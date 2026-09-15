import { ApiError, IDEMPOTENCY_PATTERN, boundedJson, digest, object, text, type Outcome } from "../protocol";
import { roomLinkVersion } from "../room-links";
import { MAX_V2_BODY_BYTES, exact } from "./protocol";
import { advertisedChapters, chapter, creatable } from "./chapters";
import type { RoomSnapshotV2 } from "./room";
import { PHOTO_TURN_PATTERN } from "./photos";
import { REACTION_PAIR_PATTERN } from "./reactions";

function unwrap<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new ApiError(outcome.status, outcome.code); return outcome.value; }
function json(value: unknown): Response {
  return new Response(JSON.stringify(value), { headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Content-Type": "application/json; charset=utf-8" } });
}
function requireEnabled(env: Env): void { if (String(env.V2_ROOMS_ENABLED) !== "true") throw new ApiError(503, "v2_mutations_disabled"); }

/** Called only after the shared Player authentication/rate limiter succeeds. */
export async function routeV2(request: Request, path: string, playerId: string, env: Env): Promise<Response> {
  const player = env.PLAYERS.getByName(playerId);
  if (path === "/v2/capabilities" && request.method === "GET") return json({ api_version: 2,
    mutations_enabled: String(env.V2_ROOMS_ENABLED) === "true", recording_version: 2, simulation_version: 2,
    photo_uploads_enabled: String(env.V2_ROOMS_ENABLED) === "true" && String(env.RELAY_PHOTOS_ENABLED) === "true",
    preset_reactions_enabled: String(env.V2_ROOMS_ENABLED) === "true" && String(env.PRESET_REACTIONS_ENABLED) === "true",
    chapters: advertisedChapters(env),
    validation: "structural_client_replay_required" });
  if (path === "/v2/rooms" && request.method === "GET") {
    const rooms: RoomSnapshotV2[] = [];
    for (const link of await player.listRooms()) {
      if (roomLinkVersion(link) !== 2) continue;
      const snapshot = await env.ROOMS_V2.getByName(link.room_id).snapshot(playerId);
      if (snapshot.ok) rooms.push(snapshot.value); else if (snapshot.status === 404) await player.removeRoom(link.room_id, 2); else unwrap(snapshot);
    }
    return json({ rooms });
  }
  if (path === "/v2/rooms" && request.method === "POST") {
    requireEnabled(env);
    const input = object(await boundedJson(request, 4096)); exact(input, ["idempotency_key", "level_id", "level_version", "definition_hash"]);
    const selected = chapter(input);
    if (!creatable(selected, env)) throw new ApiError(503, "chapter_creation_disabled");
    const key = text(input.idempotency_key, IDEMPOTENCY_PATTERN);
    const invite_code = [...crypto.getRandomValues(new Uint8Array(10))].map(value => value.toString(16).padStart(2, "0")).join("").toUpperCase();
    const intent = unwrap(await player.reserveChapterRoom(key, { room_id: (await digest("v2:" + invite_code)).slice(0, 22), invite_code, host: true, api_version: 2 }, selected.key));
    const link = intent.link;
    return json(unwrap(await env.ROOMS_V2.getByName(link.room_id).initialize(link.room_id, playerId, link.invite_code, intent.chapter)));
  }
  if (path === "/v2/rooms/join" && request.method === "POST") {
    requireEnabled(env);
    const input = object(await boundedJson(request, 4096)); exact(input, ["invite_code"]);
    if (typeof input.invite_code !== "string" || input.invite_code.length > 40) throw new ApiError(400, "invalid_invite");
    const code = text(input.invite_code.replace(/[\s-]/g, "").toUpperCase(), /^[A-F0-9]{20}$/, "invalid_invite");
    const roomId = (await digest("v2:" + code)).slice(0, 22), room = env.ROOMS_V2.getByName(roomId);
    const alreadyLinked = (await player.listRooms()).some(link => roomLinkVersion(link) === 2 && link.room_id === roomId);
    unwrap(await player.addRoom({ room_id: roomId, invite_code: "", host: false, api_version: 2 }));
    const joined = await room.join(playerId, code);
    if (!joined.ok) { if (!alreadyLinked) await player.removeRoom(roomId, 2); return json(unwrap(joined)); }
    // A deletion that ran between link reservation and joining must not leave a
    // deleted identity newly attached to someone else's room.
    if (!await player.authorize(await digest(request.headers.get("Authorization")!.slice(7)))) {
      await room.eraseForPlayer(playerId); throw new ApiError(401, "identity_unavailable");
    }
    return json(joined.value);
  }
  const match = path.match(/^\/v2\/rooms\/([a-zA-Z0-9_-]{22})(?:\/(turns|fork|collection|operations|pairs|photos|photo-operations|reactions|reaction-operations)(?:\/([a-zA-Z0-9_-]{1,80}))?)?$/);
  if (!match) throw new ApiError(404, "not_found");
  const [, id, operation, item] = match, room = env.ROOMS_V2.getByName(id);
  if (!operation && request.method === "GET") return json(unwrap(await room.snapshot(playerId)));
  if (!operation && request.method === "DELETE") {
    const deleted = unwrap(await room.eraseForPlayer(playerId)); await player.removeRoom(id, 2); return json(deleted);
  }
  if (operation === "operations" && item && request.method === "GET") return json(unwrap(await room.operation(playerId, text(item, IDEMPOTENCY_PATTERN))));
  if (operation === "pairs" && item && request.method === "GET") return json(unwrap(await room.pairRecording(playerId, text(item, /^p\d{1,2}-[01]$/))));
  if (operation === "collection" && !item && request.method === "GET") return json(unwrap(await room.collection(playerId)));
  if (operation === "photo-operations" && item && request.method === "GET") return json(unwrap(await room.photoOperation(playerId, text(item, IDEMPOTENCY_PATTERN))));
  if (operation === "reaction-operations" && item && request.method === "GET") return json(unwrap(await room.reactionOperation(playerId, text(item, IDEMPOTENCY_PATTERN))));
  if (operation === "reactions" && item) {
    const pairId = text(item, REACTION_PAIR_PATTERN, "invalid_reaction_pair");
    if (request.method === "GET") return json(unwrap(await room.reactions(playerId, pairId)));
    if (request.method === "POST") {
      requireEnabled(env);
      if (String(env.PRESET_REACTIONS_ENABLED) !== "true") throw new ApiError(503, "preset_reactions_disabled");
      return json(unwrap(await room.react(playerId, pairId, await boundedJson(request, 4096))));
    }
  }
  if (operation === "photos" && item) {
    const turnId = text(item, PHOTO_TURN_PATTERN, "invalid_photo_turn");
    if (request.method === "GET") return json(unwrap(await room.photo(playerId, turnId)));
    if (request.method === "POST" || request.method === "DELETE") {
      // Removing a photo remains possible while new gameplay/uploads are paused.
      if (request.method === "POST") {
        requireEnabled(env);
        if (String(env.RELAY_PHOTOS_ENABLED) !== "true") throw new ApiError(503, "photo_uploads_disabled");
      }
      const input = await boundedJson(request, request.method === "DELETE" ? 4096 : 224 * 1024);
      return json(unwrap(await room.updatePhoto(playerId, turnId, input, request.method === "DELETE")));
    }
  }
  if (request.method !== "POST" || item || (operation !== "turns" && operation !== "fork")) throw new ApiError(405, "method_not_allowed");
  requireEnabled(env);
  const input = await boundedJson(request, operation === "fork" ? 4096 : MAX_V2_BODY_BYTES);
  // Both pinned catalog entries are free. Future premium chapters need a separately
  // reviewed catalog and host-entitlement check; client booleans cannot add one.
  return json(unwrap(operation === "turns" ? await room.commit(playerId, input) : await room.fork(playerId, input)));
}
