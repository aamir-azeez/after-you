import { CHAPTERS } from "../v2/chapters";
import { LEGACY_CHAPTERS } from "../v2/legacy-chapters";
import type { ChapterAdapter, ChapterKey } from "../v2/chapter-types";
import { DEVELOPER_BESTS } from "./developer-bests";
import openings from "../../../game/content/board_openings.json";

/**
 * One board per chapter definition: `<level_id>@<level_version>`, so a new
 * chapter version is a new key and opens fresh boards. A board whose chapter
 * changed after it opened (game/content/board_openings.json names the
 * definition it opened on; the app's services/leaderboard_runs.gd board_key
 * reads the same file) keeps that key for the definition it opened on, which
 * older apps still play (v2/legacy-chapters.ts), and the chapter's current
 * definition ranks on `<level_id>-<first 8 of its hash>@<level_version>`: a
 * fresh board with its own top 10, Our run, replays and duels, while the old
 * one keeps everything it holds. Only released chapters this server knows
 * have a board (an unreleased one, still behind its own flag, gets its board
 * when it ships), so no request can open a Durable Object by an arbitrary name.
 */
const OPENED: Readonly<Record<string, string>> = Object.freeze({ ...(openings as { boards: Record<string, string> }).boards });

export function boardKey(key: ChapterKey): string {
  const plain = `${key.level_id}@${key.level_version}`, opened = OPENED[plain];
  return opened === undefined || opened === key.definition_hash ? plain : `${key.level_id}-${key.definition_hash.slice(0, 8)}@${key.level_version}`;
}

const RELEASED = CHAPTERS.filter(row => row.flag === "").map(row => row.adapter);
/** The released chapters' current boards, in chapter order. */
const CURRENT: readonly string[] = Object.freeze([...new Set(RELEASED.map(adapter => boardKey(adapter.key)))]);
/** The same chapters' boards as an app from before boards named a changed definition reads them. */
const PLAIN: readonly string[] = Object.freeze([...new Set(RELEASED.map(adapter => `${adapter.key.level_id}@${adapter.key.level_version}`))]);
const KEYS: readonly string[] = Object.freeze([...new Set([...CURRENT, ...PLAIN])]);
/** Board -> the chapter definition that ranks there: the current one, or the one an earlier board opened on. */
const CHAPTER_OF: ReadonlyMap<string, ChapterAdapter> = new Map([...LEGACY_CHAPTERS, ...RELEASED].map(adapter => [boardKey(adapter.key), adapter]));

/** Every board this server can hold, current and earlier, in chapter order. */
export function boardKeys(): readonly string[] { return KEYS; }

/**
 * Sent by an app whose board keys name a changed chapter's definition (game/services/rooms_api.gd), on GET
 * /v1/duels/ghosts: its race list then names the current boards; an older app's names the boards it knows.
 */
export const DEFINITION_BOARDS_HEADER = "X-AfterYou-Definition-Boards";

/** The boards an app reads: each released chapter's current board when it sent DEFINITION_BOARDS_HEADER, else the boards it knows. */
export function boardsFor(request: Request): readonly string[] {
  return request.headers.get(DEFINITION_BOARDS_HEADER) === "1" ? CURRENT : PLAIN;
}

/** `value` when it names a known board, else null. */
export function knownBoard(value: unknown): string | null {
  return typeof value === "string" && KEYS.includes(value) ? value : null;
}

/** The chapter definition a known board ranks, or null. */
export function boardChapter(board: string): ChapterAdapter | null {
  return CHAPTER_OF.get(board) ?? null;
}

/** The developers' best time on a board, in ticks, or null while it is not set. */
export function developerBest(board: string): number | null {
  const ticks = (DEVELOPER_BESTS as Record<string, number | null>)[board];
  return typeof ticks === "number" && Number.isSafeInteger(ticks) && ticks > 0 ? ticks : null;
}
