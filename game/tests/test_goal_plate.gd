extends SceneTree
## A plate goal (core/goal_plate.gd, "plate": true on a ring_bell block) counts a pip
## at the goal on its own half of the squircle plate: p0 west, p1 east, the middle
## line both pips'. The plate is two regular pressure plates (a 58 cm board each)
## at least, in whole centimetres from the goal's radius alone, and what the goal
## draws is the area it counts (kit/pieces/goal.gd plate_extent).
const GoalPlate = preload("res://core/goal_plate.gd")
const GoalKit = preload("res://presentation/kit/pieces/goal.gd")
const PadKit = preload("res://presentation/kit/pieces/pad.gd")
const Blocks = preload("res://core/blocks/stage_blocks.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _run() -> void:
	var half := GoalPlate.half_cm(GoalPlate.MIN_RADIUS_CM)
	_check(half.y * 2 >= 58 and absi(half.x - half.y * 2) <= 1, "A 60 cm plate goal's halves are whole regular plates (%s)" % half)
	_check(Vector2(half) / 100.0 == GoalKit.plate_extent(0.6), "The drawn plate is the counted one")
	var centre := Vector2i(1000, -200)
	_check(GoalPlate.on_half("p0", centre, half, centre + Vector2i(-half.x + 2, 0)), "p0 stands on the west edge")
	_check(not GoalPlate.on_half("p1", centre, half, centre + Vector2i(-half.x + 2, 0)), "p1 does not count on the west half")
	_check(GoalPlate.on_half("p1", centre, half, centre + Vector2i(half.x - 2, 0)), "p1 stands on the east edge")
	_check(not GoalPlate.on_half("p0", centre, half, centre + Vector2i(half.x - 2, 0)), "p0 does not count on the east half")
	_check(GoalPlate.on_half("p0", centre, half, centre) and GoalPlate.on_half("p1", centre, half, centre), "The middle line is both pips'")
	_check(not GoalPlate.on_half("p0", centre, half, centre + Vector2i(-half.x - 1, 0)), "Past the plate's edge is off it")
	_check(not GoalPlate.on_half("p0", centre, half, centre + Vector2i(-half.x + 2, half.y - 2)), "A squircle's corner is cut")
	_check(GoalPlate.on_half("p1", centre, half, centre + Vector2i(1, half.y - 1)), "A pip's own half reaches the plate's front")
	var stage := {"blocks": [{"block": "ring_bell", "id": "g", "at": [0, 0], "surface": "s", "owner": "p1", "height": 0, "radius": 60, "plate": true}]}
	var goal: Dictionary = Blocks.expand({"schema_version": 7, "stages": [stage]}).stages[0].get("goal", {})
	_check(goal.get("plate", false) and goal.get("plate_cm") == [half.x, half.y], "A plate block makes a plate goal with the counted extents")
	print("GOAL PLATE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
