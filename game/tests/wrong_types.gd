extends RefCounted
## Copies of a parsed JSON value with one field or list element swapped for a
## value of another kind (a string, a list, a dictionary or a bool), for
## checking that a reader refuses wrongly typed data without a script error.

const SWAPS: Array = ["1", [1], {"x": 1}, true]

## [{"path": "a.b.0", "value": copy}, ...] for every field and list element of
## `value` down to `depth` levels of dictionaries and lists. A swap of the
## field's own kind is skipped, and numbers count as one kind.
static func variants(value: Dictionary, depth: int = 2) -> Array:
	var result: Array = []
	_collect(value, value, [], depth, result)
	return result

static func _collect(root: Dictionary, node: Variant, path: Array, depth: int, result: Array) -> void:
	var keys: Array = node.keys() if node is Dictionary else range(node.size())
	for key: Variant in keys:
		var here: Array = path + [key]
		var current: Variant = node[key]
		for swap: Variant in SWAPS:
			if same_kind(current, swap): continue
			var copy: Dictionary = root.duplicate(true)
			_at(copy, path)[key] = swap.duplicate(true) if swap is Array or swap is Dictionary else swap
			result.append({"path": ".".join(here.map(func(part: Variant) -> String: return str(part))), "value": copy})
		if depth > 1 and (current is Dictionary or current is Array):
			_collect(root, current, here, depth - 1, result)

static func _at(root: Dictionary, path: Array) -> Variant:
	var node: Variant = root
	for key: Variant in path: node = node[key]
	return node

static func same_kind(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return true
	return typeof(a) == typeof(b)
