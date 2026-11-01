extends RefCounted
## Comparisons and reads for values from a file, a server reply, a native
## result or a config, where any field may hold any JSON kind. A value of the
## wrong kind reads as a wrong value (not equal, a fallback, an empty
## container) instead of a script error. Well-typed values behave exactly as
## ==, Canonical.same, int(), Dictionary and Array do.
const Canonical = preload("res://core/v2/canonical.gd")
## The server's 22 character ids (players, rooms, requests): base64url of 16
## bytes. Compiled once. The length check matters: $ also matches before a final newline.
static var _id := RegEx.create_from_string("^[A-Za-z0-9_-]{22}$")

## True when == can compare the two values: the same kind, two numbers, String
## with StringName, or null on either side.
static func comparable(a: Variant, b: Variant) -> bool:
	if a == null or b == null or typeof(a) == typeof(b):
		return true
	if (a is int or a is float) and (b is int or b is float):
		return true
	return (a is String or a is StringName) and (b is String or b is StringName)

## a == b, false for kinds Godot cannot compare (a list against a number, a
## string against a bool).
static func equal(a: Variant, b: Variant) -> bool:
	return comparable(a, b) and a == b

## Canonical.same, false for kinds Godot cannot compare.
static func same(a: Variant, b: Variant) -> bool:
	return comparable(a, b) and Canonical.same(a, b)

## A whole, finite number. JSON reads every number as a float.
static func whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

## A save generation: a whole number that is not negative.
static func valid_generation(value: Variant) -> bool:
	return whole_number(value) and value >= 0

## int(value) for a whole number JSON carries exactly (at most 2^53 - 1 from
## zero), otherwise `fallback`.
static func as_int(value: Variant, fallback: int = 0) -> int:
	if not whole_number(value) or absf(float(value)) > 9007199254740991.0: return fallback
	return int(value)

## The value when it is a Dictionary, otherwise an empty one.
static func as_dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

## A 22 character server id: a player, room, request or publication id.
static func valid_id(value: Variant) -> bool:
	return value is String and value.length() == 22 and _id.search(value) != null

## A new random id of that form (16 random bytes as base64url, no padding).
static func new_id() -> String:
	return Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(16)).replace("+", "-").replace("/", "_").trim_suffix("==")
