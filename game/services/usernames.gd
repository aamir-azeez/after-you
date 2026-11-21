extends RefCounted
## Username rules on this phone, the same ones the server runs (backend
## src/usernames.ts; both read content/username_rules.json and both test
## suites check tests/fixtures/display_names/username_vectors.json).
##
## A username is 3 to 18 of A-Z a-z 0-9 . _ -, starts and ends with a letter
## or digit, never has two symbols in a row, passes the word list
## (services/name_filter.gd) and is not one the game keeps for itself. It is
## shown with its capitals; the friend code is friend-<the name in lowercase>.
## The server is the authority: it also says when a name is taken.
const NameFilter = preload("res://services/name_filter.gd")

const RULES_PATH := "res://content/username_rules.json"
const MIN_LENGTH := 3
const MAX_LENGTH := 18
## The request header that asks the server for usernames (capabilities, the
## friends list, the username routes).
const HEADER := "X-AfterYou-Usernames: 1"
const PATH := "/v1/profile/username"

static var _rules: Dictionary = {}
static var _shape: RegEx = null
static var _allowed: RegEx = null

## What is wrong with a name: "" when nothing, "length", "characters",
## "symbols", "username_refused" (the word list) or "username_reserved".
## `own_alias`: the player's own short name (friend_alias), which they may take
## although the game keeps it.
static func problem(name: String, own_alias: String = "") -> String:
	if name.length() < MIN_LENGTH or name.length() > MAX_LENGTH: return "length"
	_compile()
	if _allowed.search(name) == null: return "characters"
	if _shape.search(name) == null: return "symbols"
	if NameFilter.blocked(name): return "username_refused"
	if reserved(name) and not (not own_alias.is_empty() and name.to_lower() == own_alias): return "username_reserved"
	return ""

## The shape alone, for a name another player or the server sent.
static func shaped(value: Variant) -> bool:
	if not value is String or value.length() < MIN_LENGTH or value.length() > MAX_LENGTH: return false
	_compile()
	return _shape.search(value) != null

## A username from the server or a friends row, shown only when it still passes
## the shape and the word list.
static func valid_remote(value: Variant) -> bool:
	return shaped(value) and not NameFilter.blocked(value)

## Kept for the game (username_rules.json): the fold (lowercase, symbols and
## trailing digits removed), the names inside, and the share code prefixes.
static func reserved(name: String) -> bool:
	var rules := _load()
	var lower := name.to_lower()
	var bare := lower.replace(".", "").replace("_", "").replace("-", "")
	var folded := bare
	while not folded.is_empty() and folded.unicode_at(folded.length() - 1) >= 48 and folded.unicode_at(folded.length() - 1) <= 57: folded = folded.left(-1)
	if folded in rules.get("reserved", []): return true
	for word: String in rules.get("reserved_inside", []):
		if bare.contains(word): return true
	for prefix: String in rules.get("type_prefixes", []):
		for symbol: String in [".", "_", "-"]:
			if lower.begins_with(prefix + symbol): return true
	return false

## The friend code's name part: always lowercase.
static func key(name: String) -> String:
	return name.to_lower()

static func _load() -> Dictionary:
	if _rules.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
		_rules = parsed if parsed is Dictionary else {"reserved": []}
	return _rules

static func _compile() -> void:
	if _shape != null: return
	_shape = RegEx.create_from_string("\\A[A-Za-z0-9](?:[._-]?[A-Za-z0-9])*\\z")
	_allowed = RegEx.create_from_string("\\A[A-Za-z0-9._-]*\\z")
