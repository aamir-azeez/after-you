import blocklist from "../../game/content/display_name_blocklist.json";

/**
 * The word filter for display names, the same one the game runs on names and nicknames
 * (game/services/name_filter.gd). Both read one list, game/content/display_name_blocklist.json,
 * and both test suites check game/tests/fixtures/display_names/name_filter_vectors.json.
 *
 * - The fold: compatibility decomposition, marks and format characters removed, a space put
 *   where a lowercase letter meets a capital ("BigName"), lowercase, then lookalike letters
 *   made Latin. The game folds the same way, step for step.
 * - Three readings: the fold, the fold with digit and symbol swaps ("sh1t"), and the fold with
 *   the alternate swaps ("1" read as "l").
 * - `substrings` match anywhere once spaces and punctuation are gone; `words` match one whole
 *   word, the whole name run together, or a run of single letters ("n a z i") joined.
 * - A run of one letter in an entry matches that many or more ("fuuuck"), never fewer, so
 *   "nigger" never matches "Niger".
 */
type Kind = "substrings" | "words";
type BlockList = {
  folding: { swaps: Record<string, string>; alternate_swaps: Record<string, string>; lookalikes: Record<string, string> };
  allowed_words: string[];
  categories: Record<string, Record<Kind, string[]>>;
};
const LIST = blocklist as BlockList;

/** Every entry of one kind, across categories. */
export const blockEntries = (kind: Kind): string[] => Object.values(LIST.categories).flatMap(category => category[kind]);

/** An entry as a pattern: each run of one character matches that many copies or more. Entries are a to z and digits only. */
export function runPattern(entry: string): string {
  return entry.replace(/(.)\1*/g, run => run.length === 1 ? `${run[0]}+` : `${run[0]}{${run.length},}`);
}

const SUBSTRINGS = new RegExp(blockEntries("substrings").map(runPattern).join("|"), "u");
const WORDS = new RegExp(`^(?:${blockEntries("words").map(runPattern).join("|")})$`, "u");
const ALLOWED_WORDS = new Set(LIST.allowed_words);
const SWAPS = LIST.folding.swaps;
const ALTERNATE = { ...SWAPS, ...LIST.folding.alternate_swaps };
const LOOKALIKES = LIST.folding.lookalikes;

const mapped = (text: string, table: Record<string, string>): string => [...text].map(point => table[point] ?? point).join("");

/** The plain fold, before any digit or symbol swap. */
export function foldName(name: string): string {
  const bare = name.normalize("NFKD").replace(/[\p{M}\p{Cf}]/gu, "").replace(/(\p{Ll})(\p{Lu})/gu, "$1 $2").toLowerCase();
  return mapped(bare, LOOKALIKES);
}

/** Word tokens: letters only, with runs of single letters ("n a z i", "n.a.z.i") joined into one. */
function tokens(folded: string): string[] {
  const out: string[] = [];
  let run = "";
  for (const part of folded.split(/[^\p{L}]+/u)) {
    if (part.length === 0) continue;
    if ([...part].length === 1) { run += part; continue; }
    if (run.length > 0) { out.push(run); run = ""; }
    out.push(part);
  }
  if (run.length > 0) out.push(run);
  return out;
}

const wordHit = (word: string): boolean => WORDS.test(word) && !ALLOWED_WORDS.has(word);

/** Whether the list refuses a name. */
export function blockedName(name: string): boolean {
  const plain = foldName(name);
  for (const folded of [plain, mapped(plain, SWAPS), mapped(plain, ALTERNATE)]) {
    const joined = folded.replace(/[^\p{L}\p{N}]/gu, "");
    if (SUBSTRINGS.test(joined) || wordHit(joined) || tokens(folded).some(wordHit)) return true;
  }
  return false;
}
