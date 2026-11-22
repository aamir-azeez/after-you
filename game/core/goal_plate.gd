extends RefCounted
## A goal's counted plate: two full pressure plates side by side, drawn as one
## squircle (|x/a|^4 + |z/b|^4 = 1, presentation/kit/squircle.gd) split down its
## middle, the first pip's half west and the second's east. A goal with
## "plate": true counts a pip as at the goal when it stands on its own half; every
## other goal keeps its radius circle. The half extents are whole centimetres,
## worked out from the goal's radius alone, so the drawing (kit/pieces/goal.gd),
## the sim, the server (backend/src/v2/protocol-journey.ts) and the level checker
## agree on one shape, and the hit test is whole-number arithmetic.

## The smallest goal radius (cm) a plate goal has: each half is a regular pressure
## plate (58 cm, what kit/pieces/pad.gd draws for a 36 cm pad) at least.
const MIN_RADIUS_CM := 60
const EXPONENT := 4.0
const SEGMENTS := 48
## The plate's proportions (x across both halves, z deep).
const UNIT := Vector2(2.0, 1.0)

## The plate's whole half extents (cm, x across both halves and z deep) for a
## goal `radius_cm` across: the squircle as big as the goal's circle allows.
static func half_cm(radius_cm: int) -> Vector2i:
	var scale := float(radius_cm) / _reach()
	return Vector2i(roundi(UNIT.x * scale), roundi(UNIT.y * scale))

## How far from its centre the unit-proportioned squircle of reach 1 scale reaches.
static func _reach() -> float:
	var reach := 0.0
	var power := 2.0 / EXPONENT
	for index in range(SEGMENTS):
		var angle := TAU * float(index) / float(SEGMENTS)
		var c := cos(angle)
		var s := sin(angle)
		var point := Vector2(UNIT.x * signf(c) * pow(absf(c), power), UNIT.y * signf(s) * pow(absf(s), power))
		reach = maxf(reach, point.length())
	return reach

## Whether `at` (cm) stands on slot `slot`'s half of the plate of a goal at
## `centre` with whole half extents `half` (cm): inside the squircle, on its own
## side of the middle line (the line itself is both pips').
static func on_half(slot: String, centre: Vector2i, half: Vector2i, at: Vector2i) -> bool:
	var dx := at.x - centre.x
	var dz := at.y - centre.y
	if (dx > 0 if slot == "p0" else dx < 0): return false
	var a4 := int(half.x) ** 4
	var b4 := int(half.y) ** 4
	return dx ** 4 * b4 + dz ** 4 * a4 <= a4 * b4
