extends RefCounted
## Stable JSON for versioned local records; no clocks, floats or scene objects.

static func normalized(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key: String in keys:
			result[key] = normalized(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(normalized(item))
		return result
	return value

static func digest(value: Variant) -> String:
	return JSON.stringify(normalized(value)).sha256_text()

static func same(first: Variant, second: Variant) -> bool:
	return normalized(first) == normalized(second)
