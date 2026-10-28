import { ApiError } from "../protocol";

/**
 * Chapter unlocks (game/services/chapter_unlocks.gd). A joining phone names the
 * level ids open to it, and a room refuses a new guest whose list leaves out the
 * room's chapter, so a player never lands in a chapter they have not reached.
 * The phone works the list out from its own finishes, which the server cannot
 * check; this only stops a join the phone itself would refuse, and costs no
 * request: the room's own join reads it. Without the header nothing is checked,
 * so older builds join as before.
 */
export const OPEN_CHAPTERS_HEADER = "X-AfterYou-Open-Chapters";
export const CHAPTER_NOT_OPEN = "chapter_not_open";
const LEVEL_PATTERN = /^[a-z0-9-]{1,64}$/;
const MAX_LEVELS = 64;

/** The level ids the joining phone has open, or undefined when it does not say. */
export function openChapters(request: Request): string[] | undefined {
  const value = request.headers.get(OPEN_CHAPTERS_HEADER);
  if (value === null) return undefined;
  const levels = value.split(",").map(level => level.trim()).filter(level => level.length > 0);
  if (levels.length > MAX_LEVELS || levels.some(level => !LEVEL_PATTERN.test(level))) throw new ApiError(400, "invalid_field");
  return levels;
}

/** Whether a phone with `open` (openChapters) may join a room for `levelId`. */
export function chapterOpen(levelId: string, open: readonly string[] | undefined): boolean {
  return open === undefined || open.includes(levelId);
}
