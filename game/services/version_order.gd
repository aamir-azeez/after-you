extends RefCounted
## Orders the app's major.minor.patch version names, such as "0.6.2".
## One comparer for every feature that asks "is this version newer".

static var _pattern: RegEx

## The three numbers of a plain major.minor.patch name, or [] when it is not one.
static func parse(value: Variant) -> Array[int]:
	var parts: Array[int] = []
	if not value is String: return parts
	if _pattern == null:
		_pattern = RegEx.new()
		_pattern.compile("^(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})$")
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
