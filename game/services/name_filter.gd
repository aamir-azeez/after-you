extends RefCounted
## The word filter for display names and friend nicknames, the same one the
## server runs (backend/src/name-filter.ts). Both read one list,
## res://content/display_name_blocklist.json, and both test suites check
## res://tests/fixtures/display_names/name_filter_vectors.json.
##
## - The fold: compatibility decomposition with marks and format characters
##   removed, a space where a lowercase letter meets a capital ("BigName"),
##   lowercase, then lookalike letters made Latin. Step for step the server's.
## - Three readings: the fold, the fold with digit and symbol swaps ("sh1t"),
##   and the fold with the alternate swaps ("1" read as "l"). Swaps apply only
##   to a run of letters, digits and swap symbols that holds a letter ("Room
##   455" keeps its number), and the alternate swaps never apply at the end of
##   that run ("Ana1" is not read with an "l").
## - Parts: the reading split at anything that is not a letter or digit, with
##   runs of single characters ("n a z i", "n.a.z.i") joined into one part.
## - Substrings match anywhere inside one part, or exactly a run of whole parts
##   ("pu ssy"), so a match never starts or ends inside a neighbouring word.
## - Words match one whole word (letters only) or the whole name's letters.
## - allowed_words are real words a part may be although an entry catches it.
## - A run of one letter in an entry matches that many or more ("fuuuck"),
##   never fewer, so "nigger" never matches "Niger".
## - Cost: the patterns are built once, answers are kept for recent names, and
##   input longer than MAX_INPUT is refused unread.
## The server is the authority: a list that fails to load refuses nothing here.
const LIST_PATH := "res://content/display_name_blocklist.json"
## Longer input is refused unread. Names are 18 characters and nicknames 32.
const MAX_INPUT := 256
## The most parts one substring match may span.
const MAX_SPAN := 8
const MAX_ANSWERS := 512

static var _loaded := false
static var _list: Dictionary = {}
static var _substring_inside: RegEx = null
static var _substring_whole: RegEx = null
static var _word_whole: RegEx = null
static var _allowed: Dictionary = {}
static var _swaps: Dictionary = {}
static var _alternate_only: Dictionary = {}
static var _alternate: Dictionary = {}
static var _lookalikes: Dictionary = {}
static var _answers: Dictionary = {}
static var _hidden := RegEx.create_from_string("[\\p{M}\\p{Cf}]")
static var _camel := RegEx.create_from_string("(\\p{Ll})(\\p{Lu})")
static var _swap_run := RegEx.create_from_string("[\\p{L}\\p{N}@$!]+")
static var _letter := RegEx.create_from_string("\\p{L}")
static var _not_alnum := RegEx.create_from_string("[^\\p{L}\\p{N}]+")
static var _not_letter := RegEx.create_from_string("[^\\p{L}]+")

## Whether the list refuses a name. Answers are kept for the names seen most
## recently, since lists and labels ask again on every refresh.
static func blocked(name: String) -> bool:
	if not _load_list(): return false
	if name.length() > MAX_INPUT: return true
	if not _answers.has(name):
		if _answers.size() >= MAX_ANSWERS: _answers.clear()
		var plain := fold(name)
		var swapped := _swapped(plain, _swaps)
		var alternate := _swapped(plain, _alternate)
		# A reading the same as one already checked (no digits or symbols) is not checked again.
		_answers[name] = _reading_blocked(plain) or (swapped != plain and _reading_blocked(swapped)) or (alternate != plain and alternate != swapped and _reading_blocked(alternate))
	return _answers[name]

## The plain fold, before any digit or symbol swap.
static func fold(name: String) -> String:
	_load_list()
	# ICU warns on an empty string.
	if name.is_empty(): return ""
	var text_server := TextServerManager.get_primary_interface()
	var bare := text_server.strip_diacritics(name) if text_server != null else name
	bare = _camel.sub(_hidden.sub(bare, "", true), "$1 $2", true).to_lower()
	return _mapped(bare, _lookalikes)

## Every entry of one kind ("substrings" or "words"), across categories.
static func entries(kind: String) -> PackedStringArray:
	_load_list()
	var out := PackedStringArray()
	for category: Variant in (_list.get("categories", {}) as Dictionary).values():
		if category is Dictionary:
			for entry: Variant in category.get(kind, []): out.append(str(entry))
	return out

## An entry as a pattern: each run of one character matches that many copies
## or more. Entries are a to z and digits only.
static func run_pattern(entry: String) -> String:
	var out := ""
	var i := 0
	while i < entry.length():
		var count := 1
		while i + count < entry.length() and entry[i + count] == entry[i]: count += 1
		out += entry[i] + ("+" if count == 1 else "{%d,}" % count)
		i += count
	return out

static func _load_list() -> bool:
	if _loaded: return _word_whole != null
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LIST_PATH))
	if not parsed is Dictionary or not parsed.get("categories") is Dictionary or not parsed.get("folding") is Dictionary: return false
	_list = parsed
	var folding: Dictionary = parsed.folding
	_swaps = folding.get("swaps", {})
	_alternate_only = folding.get("alternate_swaps", {})
	_alternate = _swaps.merged(_alternate_only, true)
	_lookalikes = folding.get("lookalikes", {})
	for word: Variant in parsed.get("allowed_words", []): _allowed[str(word)] = true
	var substrings := "|".join(_patterns(entries("substrings")))
	_substring_inside = RegEx.create_from_string(substrings)
	_substring_whole = RegEx.create_from_string("^(?:%s)$" % substrings)
	_word_whole = RegEx.create_from_string("^(?:%s)$" % "|".join(_patterns(entries("words"))))
	return true

static func _patterns(list: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: String in list: out.append(run_pattern(entry))
	return out

static func _mapped(text: String, table: Dictionary) -> String:
	var out := ""
	for point: String in text: out += str(table.get(point, point))
	return out

## A reading with swaps: only runs that hold a letter, and the alternate swaps
## never at a run's end.
static func _swapped(folded: String, table: Dictionary) -> String:
	var out := ""
	var at := 0
	for found: RegExMatch in _swap_run.search_all(folded):
		out += folded.substr(at, found.get_start() - at)
		var run := found.get_string()
		at = found.get_end()
		if _letter.search(run) == null:
			out += run
			continue
		var end := run.length()
		while end > 0 and _alternate_only.has(run[end - 1]): end -= 1
		for i in range(run.length()): out += str((table if i < end else _swaps).get(run[i], run[i]))
	return out + folded.substr(at)

## The text split at `split`, with runs of single characters joined into one.
static func _parts(folded: String, split: RegEx) -> PackedStringArray:
	var out := PackedStringArray()
	var run := ""
	for part: String in split.sub(folded, " ", true).split(" ", false):
		if part.length() == 1:
			run += part
			continue
		if not run.is_empty():
			out.append(run)
			run = ""
		out.append(part)
	if not run.is_empty(): out.append(run)
	return out

static func _word_hit(word: String) -> bool:
	return _word_whole.search(word) != null and not _allowed.has(word)

static func _reading_blocked(folded: String) -> bool:
	var words := _parts(folded, _not_letter)
	for word: String in words:
		if _word_hit(word): return true
	if _word_hit("".join(words)): return true
	var pieces := _parts(folded, _not_alnum)
	for i in range(pieces.size()):
		if not _allowed.has(pieces[i]) and _substring_inside.search(pieces[i]) != null: return true
		var span := pieces[i]
		var j := i + 1
		while j < pieces.size() and j - i < MAX_SPAN:
			span += pieces[j]
			if _substring_whole.search(span) != null: return true
			j += 1
	return false
