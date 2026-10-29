import { ApiError, isObject } from "../protocol";
import { packOfFace } from "../pollen/catalog";
import { facePacksWanted, isPackFace } from "./end-reactions";

/**
 * Who may send a pack face (end-reactions.ts PACK_FACES): only a player who owns its reaction pack
 * (pollen/catalog.json packs, owned in the player's wardrobe, pollen/wardrobe.ts). The turn's own
 * Player call brings the owned packs (Player.authorizeRoom with `packs`, asked only by phones that
 * send FACE_PACKS_HEADER), so the check costs no Durable Object request. A turn whose pack face is
 * not owned is refused before the room sees it, with no receipt kept: the phone sends the same
 * turn again without that face.
 */
export const FACE_PACK_NOT_OWNED = "face_pack_not_owned";

const TURN_ROUTE = /^\/v2\/rooms\/[A-Za-z0-9_-]{22}\/turns$/;
/** A turn from a phone that may carry pack faces: its Player call also brings the owned packs. */
export function facePacksTurnRoute(request: Request, path: string): boolean {
  return request.method === "POST" && TURN_ROUTE.test(path) && facePacksWanted(request);
}

/** The packs a turn body's faces need: its end reaction's and each run reaction's, pack faces only. The room checks their shape. */
export function packsNeeded(body: unknown): Set<string> {
  const needed = new Set<string>();
  if (!isObject(body)) return needed;
  const note = (face: unknown) => {
    if (typeof face !== "string" || !isPackFace(face)) return;
    const pack = packOfFace(face);
    if (pack !== undefined) needed.add(pack);
  };
  note(body.end_reaction);
  if (Array.isArray(body.run_reactions)) for (const entry of body.run_reactions) if (isObject(entry)) note(entry.id);
  return needed;
}

/** Throws 403 FACE_PACK_NOT_OWNED unless every pack the body's faces need is in `owned` (undefined: the phone did not ask, so none). */
export function requireOwnedFaces(body: unknown, owned: readonly string[] | undefined): void {
  for (const pack of packsNeeded(body)) if (!owned?.includes(pack)) throw new ApiError(403, FACE_PACK_NOT_OWNED);
}
