import { isObject } from "../protocol";
import { validRoomLink, roomLinkVersion, type RoomLink } from "../room-links";
import { chapterKey, RELAY_KEY, sameChapter } from "./chapters";
import type { ChapterKey } from "./chapter-types";

/** The create body's complete variable intent is this exact chapter triple. */
export type ChapterCreation = { creation_schema: 1; link: RoomLink; chapter: ChapterKey };
export function validChapterCreation(value: unknown): value is ChapterCreation {
  if (!isObject(value) || Object.keys(value).length !== 3 || value.creation_schema !== 1 || !validRoomLink(value.link) || roomLinkVersion(value.link) !== 2 || !value.link.host || !isObject(value.chapter) || Object.keys(value.chapter).length !== 3) return false;
  try { return sameChapter(chapterKey(value.chapter), value.chapter as ChapterKey); } catch { return false; }
}
/** Old v2 rows predate chapter selection and can only denote immutable Relay2. */
export function readCreation(value: unknown): ChapterCreation | null {
  if (validChapterCreation(value)) return value;
  if (validRoomLink(value) && value.host && roomLinkVersion(value) === 2) return { creation_schema: 1, link: value, chapter: { ...RELAY_KEY } };
  return null;
}
