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
 *   the alternate swaps ("1" read as "l"). Swaps apply only to a run of letters, digits and
 *   swap symbols that holds a letter ("Room 455" keeps its number), and the alternate swaps
 *   never apply at the end of that run ("Ana1" is not read with an "l").
 * - Parts: the reading split at anything that is not a letter or digit, with runs of single
 *   characters ("n a z i", "n.a.z.i") joined into one part.
 * - `substrings` match anywhere inside one part, or exactly a run of whole parts ("pu ssy"),
 *   so a match never starts or ends inside a neighbouring word ("Rabbit Chaser").
 * - `words` match one whole word (letters only) or the whole name's letters run together.
 * - `allowed_words` are real words a part may be although an entry would catch it.
 * - A run of one letter in an entry matches that many or more ("fuuuck"), never fewer, so
 *   "nigger" never matches "Niger".
 * - Cost: the patterns are built once; a check is a few linear passes over a name of at most
 *   MAX_INPUT code points, and part runs are at most MAX_SPAN parts long. Every entry
 *   pattern is a chain of runs of different characters, so matching cannot backtrack badly.
 */
type Kind = "substrings" | "words";
type BlockList = {
  folding: { swaps: Record<string, string>; alternate_swaps: Record<string, string>; lookalikes: Record<string, string> };
  allowed_words: string[];
  categories: Record<string, Record<Kind, string[]>>;
};
const LIST = blocklist as BlockList;
/** Longer input is refused unread. Names are 18 code points and nicknames 32. */
export const MAX_INPUT = 256;
/** The most parts one substring match may span. */
export const MAX_SPAN = 8;

/** Every entry of one kind, across categories. */
export const blockEntries = (kind: Kind): string[] => Object.values(LIST.categories).flatMap(category => category[kind]);

/** An entry as a pattern: each run of one character matches that many copies or more. Entries are a to z and digits only. */
export function runPattern(entry: string): string {
  return entry.replace(/(.)\1*/g, run => run.length === 1 ? `${run[0]}+` : `${run[0]}{${run.length},}`);
}

const alternation = (kind: Kind): string => blockEntries(kind).map(runPattern).join("|");
const SUBSTRING_INSIDE = new RegExp(alternation("substrings"), "u");
const SUBSTRING_WHOLE = new RegExp(`^(?:${alternation("substrings")})$`, "u");
const WORD_WHOLE = new RegExp(`^(?:${alternation("words")})$`, "u");
const ALLOWED_WORDS = new Set(LIST.allowed_words);
const SWAPS = LIST.folding.swaps;
const ALTERNATE = { ...SWAPS, ...LIST.folding.alternate_swaps };
/** A run the swaps read: letters, digits and the swap symbols (every swap key is a digit or one of these). */
const SWAP_RUN = /[\p{L}\p{N}@$!]+/gu;
const LOOKALIKES = LIST.folding.lookalikes;

const mapped = (text: string, table: Record<string, string>): string => [...text].map(point => table[point] ?? point).join("");

/** The plain fold, before any digit or symbol swap. */
export function foldName(name: string): string {
  const bare = name.normalize("NFKD").replace(/[\p{M}\p{Cf}]/gu, "").replace(/(\p{Ll})(\p{Lu})/gu, "$1 $2").toLowerCase();
  return mapped(bare, LOOKALIKES);
}

/** A reading with swaps: only runs that hold a letter, and the alternate swaps never at a run's end. */
function swapped(folded: string, table: Record<string, string>): string {
  return folded.replace(SWAP_RUN, run => {
    if (!/\p{L}/u.test(run)) return run;
    const points = [...run];
    let end = points.length;
    while (end > 0 && Object.hasOwn(LIST.folding.alternate_swaps, points[end - 1])) end--;
    return points.map((point, i) => (i < end ? table : SWAPS)[point] ?? point).join("");
  });
}

/** The text split at `split`, with runs of single characters joined into one part. */
function parts(folded: string, split: RegExp): string[] {
  const out: string[] = [];
  let run = "";
  for (const part of folded.split(split)) {
    if (part.length === 0) continue;
    if ([...part].length === 1) { run += part; continue; }
    if (run.length > 0) { out.push(run); run = ""; }
    out.push(part);
  }
  if (run.length > 0) out.push(run);
  return out;
}

const wordHit = (word: string): boolean => WORD_WHOLE.test(word) && !ALLOWED_WORDS.has(word);

function readingBlocked(folded: string): boolean {
  const words = parts(folded, /[^\p{L}]+/u);
  if (words.some(wordHit) || wordHit(words.join(""))) return true;
  const pieces = parts(folded, /[^\p{L}\p{N}]+/u);
  for (let i = 0; i < pieces.length; i++) {
    if (!ALLOWED_WORDS.has(pieces[i]) && SUBSTRING_INSIDE.test(pieces[i])) return true;
    let span = pieces[i];
    for (let j = i + 1; j < pieces.length && j - i < MAX_SPAN; j++) {
      span += pieces[j];
      if (SUBSTRING_WHOLE.test(span)) return true;
    }
  }
  return false;
}

/** Answers kept for the names seen most recently in this isolate; a friends list asks for the same names again. */
const answers = new Map<string, boolean>();
const MAX_ANSWERS = 512;

/** Whether the list refuses a name. A reading the same as one already checked (no digits or symbols) is not checked again. */
export function blockedName(name: string): boolean {
  if ([...name].length > MAX_INPUT) return true;
  const known = answers.get(name);
  if (known !== undefined) return known;
  const plain = foldName(name);
  const answer = [...new Set([plain, swapped(plain, SWAPS), swapped(plain, ALTERNATE)])].some(readingBlocked);
  if (answers.size >= MAX_ANSWERS) answers.clear();
  answers.set(name, answer);
  return answer;
}
