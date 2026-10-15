extends RefCounted
## Orders the app's major.minor.patch version names, such as "0.6.2".
## One comparer for every feature that asks "is this version newer".
##
## parse/valid/compare read plain names only (the changelog's entries).
## parse_release/compare_release also read a pre-release (0.6.2-rc.1), the way the
## required-update gate and the server (backend/src/app-status.ts) do; the vectors
## both sides check are in tests/fixtures/update_gate/versions.json.

const NUMBER := "(0|[1-9][0-9]{0,3})"
## Longest version name parse_release accepts.
const MAX_RELEASE_LENGTH := 40

static var _pattern: RegEx
static var _release_pattern: RegEx

## The three numbers of a plain major.minor.patch name, or [] when it is not one.
static func parse(value: Variant) -> Array[int]:
	var parts: Array[int] = []
	if not value is String: return parts
	if _pattern == null:
		_pattern = RegEx.new()
		_pattern.compile("^%s\\.%s\\.%s$" % [NUMBER, NUMBER, NUMBER])
	var found := _pattern.search(value)
	if found == null: return parts
	for index: int in range(1, 4):
		parts.append(int(found.get_string(index)))
	return parts

static func valid(value: Variant) -> bool:
	return not parse(value).is_empty()

## -1 when a is older than b, 0 when equal, 1 when newer. Callers check valid()
## first; an invalid name compares equal so it never reads as an update.
static func compare(a: String, b: String) -> int:
	var left := parse(a)
	var right := parse(b)
	if left.is_empty() or right.is_empty(): return 0
	for index: int in range(3):
		if left[index] != right[index]: return -1 if left[index] < right[index] else 1
	return 0

## A semantic version without build metadata: {"core": [major, minor, patch],
## "pre": [identifiers]}, or {} for anything else. A numeric pre-release identifier
## has no leading zeros (semver 9) and at most 6 digits.
static func parse_release(value: Variant) -> Dictionary:
	if not value is String or value.length() > MAX_RELEASE_LENGTH: return {}
	if _release_pattern == null:
		_release_pattern = RegEx.create_from_string("^%s\\.%s\\.%s(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?$" % [NUMBER, NUMBER, NUMBER])
	var found := _release_pattern.search(value)
	if found == null: return {}
	var pre: PackedStringArray = PackedStringArray() if found.get_string(4).is_empty() else found.get_string(4).split(".")
	for part: String in pre:
		if _digits(part) and ((part.length() > 1 and part.begins_with("0")) or part.length() > 6): return {}
	return {"core": [int(found.get_string(1)), int(found.get_string(2)), int(found.get_string(3))], "pre": Array(pre)}

static func _digits(part: String) -> bool:
	if part.is_empty(): return false
	for character: String in part:
		if character < "0" or character > "9": return false
	return true

## Semantic version precedence of two parse_release results: -1 older, 0 equal, 1 newer.
## A pre-release is older than its release; identifiers compare numerically when both
## are numbers, a number sorts before text, and text compares by character.
static func compare_release(a: Dictionary, b: Dictionary) -> int:
	for i in range(3):
		if a.core[i] != b.core[i]: return -1 if a.core[i] < b.core[i] else 1
	var ap: Array = a.pre
	var bp: Array = b.pre
	if ap.is_empty() or bp.is_empty():
		if ap.size() == bp.size(): return 0
		return 1 if ap.is_empty() else -1
	for i in range(mini(ap.size(), bp.size())):
		var x: String = ap[i]
		var y: String = bp[i]
		if x == y: continue
		var xn := _digits(x)
		var yn := _digits(y)
		if xn and yn: return -1 if int(x) < int(y) else 1
		if xn != yn: return -1 if xn else 1
		return -1 if x < y else 1
	if ap.size() == bp.size(): return 0
	return -1 if ap.size() < bp.size() else 1
