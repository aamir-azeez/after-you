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
##   and the fold with the alternate swaps ("1" read as "l").
## - Substrings match anywhere once spaces and punctuation are gone; words
##   match one whole word, the whole name run together, or a run of single
##   letters ("n a z i") joined.
## - A run of one letter in an entry matches that many or more ("fuuuck"),
##   never fewer, so "nigger" never matches "Niger".
## The server is the authority: a list that fails to load refuses nothing here.
const LIST_PATH := "res://content/display_name_blocklist.json"
const MAX_ANSWERS := 512

static var _loaded := false
static var _list: Dictionary = {}
static var _substrings: RegEx = null
static var _words: RegEx = null
static var _allowed: Dictionary = {}
static var _swaps: Dictionary = {}
static var _alternate: Dictionary = {}
static var _lookalikes: Dictionary = {}
static var _answers: Dictionary = {}
static var _hidden := RegEx.create_from_string("[\\p{M}\\p{Cf}]")
static var _camel := RegEx.create_from_string("(\\p{Ll})(\\p{Lu})")
static var _not_alnum := RegEx.create_from_string("[^\\p{L}\\p{N}]")
static var _not_letter := RegEx.create_from_string("[^\\p{L}]+")

## Whether the list refuses a name. Answers are kept for the names seen most
## recently, since lists and labels ask again on every refresh.
static func blocked(name: String) -> bool:
	if not _load_list(): return false
	if not _answers.has(name):
		if _answers.size() >= MAX_ANSWERS: _answers.clear()
		_answers[name] = _check(name)
	return _answers[name]

static func _check(name: String) -> bool:
	var plain := fold(name)
	for folded: String in [plain, _mapped(plain, _swaps), _mapped(plain, _alternate)]:
		var joined := _not_alnum.sub(folded, "", true)
		if _substrings.search(joined) != null or _word_hit(joined): return true
		for token: String in _tokens(folded):
			if _word_hit(token): return true
	return false

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
	if _loaded: return _substrings != null
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LIST_PATH))
	if not parsed is Dictionary or not parsed.get("categories") is Dictionary or not parsed.get("folding") is Dictionary: return false
	_list = parsed
	var folding: Dictionary = parsed.folding
	_swaps = folding.get("swaps", {})
	_alternate = _swaps.merged(folding.get("alternate_swaps", {}), true)
	_lookalikes = folding.get("lookalikes", {})
	for word: Variant in parsed.get("allowed_words", []): _allowed[str(word)] = true
	_substrings = RegEx.create_from_string("|".join(_patterns(entries("substrings"))))
	_words = RegEx.create_from_string("^(?:%s)$" % "|".join(_patterns(entries("words"))))
	return true

static func _patterns(list: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: String in list: out.append(run_pattern(entry))
	return out

static func _mapped(text: String, table: Dictionary) -> String:
	var out := ""
	for point: String in text: out += str(table.get(point, point))
	return out

static func _word_hit(word: String) -> bool:
	return _words.search(word) != null and not _allowed.has(word)

## Word tokens: letters only, with runs of single letters joined into one.
static func _tokens(folded: String) -> PackedStringArray:
	var out := PackedStringArray()
	var run := ""
	for part: String in _not_letter.sub(folded, " ", true).split(" ", false):
		if part.length() == 1:
			run += part
			continue
		if not run.is_empty():
			out.append(run)
			run = ""
		out.append(part)
	if not run.is_empty(): out.append(run)
	return out
