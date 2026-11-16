extends SceneTree
## core/solid_footprint.gd: a solid entity keeps pips out of its footprint and
## lets them reach it from its edge; an entity without one stays a plain spot.
const Solid = preload("res://core/solid_footprint.gd")
const BODY := 12
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var plain := {"id": "seed-pedestal", "position_cm": [230, -90], "radius_cm": 36}
	var solid := plain.duplicate(true)
	solid["solid"] = {"radius_cm": 28, "reach_cm": 20}
	_check(Solid.of(plain).is_empty() and Solid.of({"solid": "yes"}).is_empty(), "An entity without a solid footprint has none")
	_check(not Solid.blocked([plain], Vector2i(230, -90), BODY), "A plain spot never blocks, even at its centre")
	_check(Solid.within_reach(plain, Vector2i(230 + 36, -90), BODY) and not Solid.within_reach(plain, Vector2i(230 + 37, -90), BODY), "A plain spot is reached inside its own radius only")
	_check(Solid.blocked([plain, solid], Vector2i(230, -90), BODY), "A solid footprint blocks its centre")
	_check(Solid.blocked([solid], Vector2i(230 + 39, -90), BODY) and not Solid.blocked([solid], Vector2i(230 + 40, -90), BODY), "A pip's centre keeps its own body radius off the footprint's edge")
	_check(Solid.within_reach(solid, Vector2i(230, -90 - 60), BODY) and not Solid.within_reach(solid, Vector2i(230, -90 - 61), BODY), "A solid entity is reached from within reach_cm of its edge, from any side")
	_check(Solid.within_reach(solid, Vector2i(230 + 40, -90), BODY), "The closest a pip can stand reaches the solid entity")
	print("SOLID FOOTPRINT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
