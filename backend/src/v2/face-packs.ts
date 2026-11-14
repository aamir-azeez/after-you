import { ApiError, isObject } from "../protocol";
import type { ServerVars } from "../flags";
import { faceSinglesOn } from "../pollen/features";
import { FACE_PACKS_VERSION, FACE_SINGLES_VERSION, facePacksVersion, facePacksWanted, isPackFace, isSingleFace, type FaceVersion } from "./end-reactions";

/**
 * Who may send a face beyond the everyday ones (end-reactions.ts PACK_FACES and SINGLE_FACES): only a player who
 * owns it, bought one at a time or in a reaction pack (pollen/wardrobe.ts ownedFaceIds). The turn's own Player call
 * brings the owned faces (Player.authorizeRoom with `faces`, asked only by phones that send FACE_PACKS_HEADER), so
 * the check costs no Durable Object request. A turn with a face not owned is refused before the room sees it, with
 * no receipt kept: the phone sends the same turn again without that face. The check is ownership only, never the
 * player's reaction slots, so a late loadout save never refuses a turn.
 */
export const FACE_PACK_NOT_OWNED = "face_pack_not_owned";

const TURN_ROUTE = /^\/v2\/rooms\/[A-Za-z0-9_-]{22}\/turns$/;
/** A turn from a phone that may carry faces beyond the everyday ones: its Player call also brings the owned faces. */
export function facePacksTurnRoute(request: Request, path: string): boolean {
  return request.method === "POST" && TURN_ROUTE.test(path) && facePacksWanted(request);
}

/**
 * The face version this server serves `request` (capabilities, room reads, turn replies, the inbox and Replays): what
 * the phone asks for, version 2 only while FACE_SINGLES is on. Version 1 answers exactly as before.
 */
export function servedFaceVersion(request: Request, env: ServerVars): FaceVersion {
  const asked = facePacksVersion(request);
  return asked >= FACE_SINGLES_VERSION && !faceSinglesOn(env) ? FACE_PACKS_VERSION : asked;
}

/** The faces a turn body needs owned: its end reaction's and each run reaction's pack and single faces. The room checks every face's shape (an unknown one is 400 there). */
export function facesNeeded(body: unknown): Set<string> {
  const needed = new Set<string>();
  if (!isObject(body)) return needed;
  const note = (face: unknown) => { if (typeof face === "string" && (isPackFace(face) || isSingleFace(face))) needed.add(face); };
  note(body.end_reaction);
  if (Array.isArray(body.run_reactions)) for (const entry of body.run_reactions) if (isObject(entry)) note(entry.id);
  return needed;
}

/** Throws 403 FACE_PACK_NOT_OWNED unless every face the body needs is in `owned` (undefined: the phone did not ask, so none). */
export function requireOwnedFaces(body: unknown, owned: readonly string[] | undefined): void {
  for (const face of facesNeeded(body)) if (!owned?.includes(face)) throw new ApiError(403, FACE_PACK_NOT_OWNED);
}
