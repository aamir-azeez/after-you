extends SceneTree
## core/solid_footprint.gd: a solid entity keeps pips out of its footprint and
## lets them reach it from its edge; an entity without one stays a plain spot.
const Solid = preload("res://core/solid_footprint.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Sim = preload("res://core/v2/simulation_v2.gd")
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
	_relay_nest()
	print("SOLID FOOTPRINT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The Relay engine (core/v2/simulation_v2.gd) with the nest made solid as the
## planned @3 has it (agent-docs ADDING-A-CHAPTER.md): the published relay
## stage's own turns still catch at the landing and place in the nest, a pip
## walking at the nest stops at its edge and reaches it from there, and the
## published nest is still a spot a pip walks into.
func _relay_nest() -> void:
	var plain := Catalog.relay_isles()
	var level := Catalog.relay_isles()
	level.sockets[0]["solid"] = {"radius_cm": 22, "reach_cm": 20}
	var checkpoint := Catalog.initial_checkpoint(level)
	var first := Sim.new()
	first._reset_trusted(level, "relay", checkpoint, {}, "a")
	for frame: Dictionary in Sim.expand_recording_inputs(_fixture("relay-a")): first.step(frame)
	_check(first.can_commit(), "The published first turn still throws to the landing beside the solid nest")
	var second := Sim.new()
	second._reset_trusted(level, "relay", checkpoint, first.export_recording(), "b")
	for frame: Dictionary in Sim.expand_recording_inputs(_fixture("relay-b")): second.step(frame)
	_check(second._outcome.caught_seed and second.complete, "The published second turn still catches at the landing and places in the solid nest")
	var nest := Vector2i(40, 0)
	for definition: Dictionary in [level, plain]:
		var walker := Sim.new()
		walker._reset_trusted(definition, "relay", checkpoint, {}, "a")
		walker._players.p0 = {"x": -60, "z": 0, "surface_id": "relay"}
		for _tick in 20: walker._move_slot("p0", {"x": 100, "z": 0, "action": false})
		var stood := walker._position("p0")
		if definition == level:
			_check(stood.x < nest.x and nest.distance_squared_to(stood) >= 34 * 34 and Solid.within_reach(level.sockets[0], stood, BODY), "A pip walking at the solid nest stops at its edge, within reach of it")
		else:
			_check(stood.x > nest.x, "The published nest is still walked through")

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/%s.json" % name))
