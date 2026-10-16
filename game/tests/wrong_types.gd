extends RefCounted
## Copies of a parsed JSON value with one field swapped for a value of another
## kind (a string, a list, a dictionary or a bool), for checking that a reader
## refuses wrongly typed data without a script error.

const SWAPS: Array = ["1", [1], {"x": 1}, true]

## [{"path": "a.b", "value": copy}, ...] for every field of `value` down to
## `depth` levels of dictionaries. A swap of the field's own kind is skipped,
## and numbers count as one kind.
static func variants(value: Dictionary, depth: int = 2) -> Array:
	var result: Array = []
	_collect(value, value, [], depth, result)
	return result

static func _collect(root: Dictionary, node: Dictionary, path: Array, depth: int, result: Array) -> void:
	for key: Variant in node:
		var here: Array = path + [key]
		for swap: Variant in SWAPS:
			if _same_kind(node[key], swap): continue
			var copy: Dictionary = root.duplicate(true)
			_at(copy, path)[key] = swap.duplicate(true) if swap is Array or swap is Dictionary else swap
			result.append({"path": ".".join(here.map(func(part: Variant) -> String: return str(part))), "value": copy})
		if depth > 1 and node[key] is Dictionary:
			_collect(root, node[key], here, depth - 1, result)

static func _at(root: Dictionary, path: Array) -> Dictionary:
	var node: Dictionary = root
	for key: Variant in path: node = node[key]
	return node

static func _same_kind(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return true
	return typeof(a) == typeof(b)
