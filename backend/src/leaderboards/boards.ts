import { CHAPTERS } from "../v2/chapters";
import type { ChapterKey } from "../v2/chapter-types";
import { DEVELOPER_BESTS } from "./developer-bests";

/**
 * One board per chapter version: `<level_id>@<level_version>`. A new chapter
 * version is a new key, so it opens fresh boards. Only chapters this server
 * knows have a board, so no request can open a Durable Object by an arbitrary name.
 */
export function boardKey(key: Pick<ChapterKey, "level_id" | "level_version">): string {
  return `${key.level_id}@${key.level_version}`;
}

const KEYS: readonly string[] = Object.freeze([...new Set(CHAPTERS.map(row => boardKey(row.adapter.key)))]);

/** Every board this server can hold, in chapter order. */
export function boardKeys(): readonly string[] { return KEYS; }

/** `value` when it names a known board, else null. */
export function knownBoard(value: unknown): string | null {
  return typeof value === "string" && KEYS.includes(value) ? value : null;
}

/** The developers' best time on a board, in ticks, or null while it is not set. */
export function developerBest(board: string): number | null {
  const ticks = (DEVELOPER_BESTS as Record<string, number | null>)[board];
  return typeof ticks === "number" && Number.isSafeInteger(ticks) && ticks > 0 ? ticks : null;
}
