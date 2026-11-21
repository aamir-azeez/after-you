extends SceneTree
## The light pieces (core/physical/light_pieces.gd) on their witness level
## (tests/light_witness.gd), played through the journey engine with the memory
## trace off, read by the level graph and drawn by the journey world:
## - the light block expands to a plain optical field, mirror and selector
##   controls, the lamps' lit_when and a gate per route, with no problems, and
##   a lit_when on a mirror, one reading a signal or optics at a value the
##   selector never shows are named;
## - the server's cases (tests/fixtures/light_pieces/cases.json, also lit by
##   backend/test/light-pieces.test.ts) light the same receivers here, and
##   every receiver's signal_whens holds exactly where it is lit;
## - a light pad lights its lamp only while a pip stands on it, the mirror
##   then holds the span, and stepping off lets it close as on the tide rules;
## - a lens in its cradle lights its lamp; the selector steers the fixed
##   mirror or puts the lamp out; taking the lens away darkens the span;
## - the level graph: the pip on the light pad cannot walk the span it holds
##   (the walker probe), the walker can;
## - the journey world draws the steered mirror and turns it as the selector
##   does, a cradle where the lens lights its lamp, the lens in its own look,
##   and a cable from the light pad to its lamp, lit while it shines.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/light_witness.gd")
const LightPieces = preload("res://core/physical/light_pieces.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const MemoryTrace = preload("res://core/physical/memory_trace.gd")
const LevelGraph = preload("res://tests/level_graph.gd")
const JourneyWorld = preload("res://presentation/journey_world.gd")
const CASES := "res://tests/fixtures/light_pieces/cases.json"
var checks := 0
var failures := 0
var level: Dictionary

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	MemoryTrace.enabled = false
	level = Witness.definition()
	_blocks()
	_cases()
	_pad()
	_cradle()
	_graph()
	await _world()
	print("LIGHT PIECES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _blocks() -> void:
	var source := Witness.source()
	_check(StageBlocks.problems(source).is_empty(), "The witness's blocks have no problems: %s" % [StageBlocks.problems(source)])
	_check(PiecesRules.problems(level).is_empty() and level.simulation_version == 16, "Its light is sound on rules 16: %s" % [PiecesRules.problems(level)])
	_check(PiecesRules.uses(level) == ["light on pad", "light on cradle"], "Light is a new piece on both stages: %s" % [PiecesRules.uses(level)])
	var pad: Dictionary = level.stages[0]
	_check(pad.lit_when == {"harbour-lamp": {"pad_id": "light-pad"}} and pad.optical_field.emitters == [{"id": "harbour-lamp", "position_cm": [60, 50], "enabled": true, "direction": "east"}], "The harbour lamp shines while the light pad is held")
	_check(pad.controls.size() == 1 and pad.controls[0].kind == "mirror" and pad.controls[0].values == ["slash", "backslash"] and pad.controls[0].initial == "backslash" and not pad.controls[0].has("owner_slot"), "The quay mirror is a mirror control either pip turns")
	_check(pad.gates == [{"route_id": "span", "when": {"signal_id": "span-eye"}}], "The span is open while its receiver is lit")
	var cradle: Dictionary = level.stages[1]
	_check(cradle.optical_field.mirrors == [{"id": "steer", "position_cm": [500, 100], "enabled": true, "orientation": "backslash"}] and cradle.controls[0].optics.has("off"), "The fixed mirror has no control of its own; the selector steers it")
	var bad := level.duplicate(true)
	bad.stages[0].lit_when["quay-mirror"] = {"signal_id": "span-eye"}
	bad.stages[1].controls[0].optics["west"] = {"steer": {"orientation": "up"}}
	_check(LightPieces.problems(bad).size() == 4, "A lit_when on a mirror reading a signal, and optics at an unknown value with no orientation, are named: %s" % [LightPieces.problems(bad)])
	var twice := Witness.source()
	twice.stages[0].blocks.append({"block": "light", "bounds": [0, 0, 10, 10]})
	_check(StageBlocks.problems(twice).size() == 1, "A stage has one light: %s" % [StageBlocks.problems(twice)])

## The server's cases light the same receivers, and signal_whens agrees.
func _cases() -> void:
	var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CASES))
	var stage: Dictionary = file.stage
	var whens := LightPieces.signal_whens(stage)
	for sample: Dictionary in file.cases:
		var mechanisms := {"controls": sample.controls, "levers": {}, "items": sample.items}
		var lit: Dictionary = LightPieces.optics(stage, sample.players, mechanisms, true).signals
		_check(lit == sample.signals, "%s lights %s: %s" % [sample.name, sample.signals, lit])
		for id: String in sample.signals:
			var holds := Seven.predicate(whens.get(id, {"any": []}), stage, sample.players, mechanisms, {}, true)
			_check(holds == bool(sample.signals[id]), "%s: %s's when %s" % [sample.name, id, "holds" if holds else "fails"])

func _pad() -> void:
	var sim := _sim("pad", {"p0": _at(130, 340)}, {"quay-mirror": "slash"})
	_check(sim._optics.segments.is_empty() and not bool(sim._routes.span), "With no one on the light pad the lamp is dark and the span shut")
	_walk(sim, [60, 340])
	_check(_shines(sim, "harbour-lamp") and bool(sim._optics.signals["span-eye"]) and bool(sim._routes.span), "On the pad the lamp shines, the mirror sends it to the receiver and the span opens")
	_walk(sim, [200, 340])
	_check(not _shines(sim, "harbour-lamp") and bool(sim._routes.span) and sim._closing.has("span"), "Off the pad the lamp goes dark and the span starts to close")
	_idle(sim, int(level.closing_ticks))
	_check(not bool(sim._routes.span), "Then it is shut")
	var away := _sim("pad", {"p0": _at(60, 340)})
	_check(_shines(away, "harbour-lamp") and not bool(away._routes.span), "Turned away, the mirror sends the light nowhere near the receiver")

func _cradle() -> void:
	var dark := _sim("cradle", {})
	_check(dark._mechanisms.items.lens.spot == "cradle" and dark._optics.segments.is_empty(), "The selector starts off: the lens rests in its cradle and its lamp is out")
	var south := _sim("cradle", {"p1": _at(200, 340)}, {"path": "south"})
	_check(_shines(south, "lens-lamp") and bool(south._optics.signals["south-eye"]) and bool(south._routes.span), "Set south, the fixed mirror sends the lens's light to the span's receiver")
	_check(LightPieces.orientations(south.stage, south._mechanisms.controls) == {"steer": "backslash"}, "The steered mirror stands as the selector sets it")
	_walk(south, [200, 280])
	_press(south)
	_check(south._mechanisms.items.lens.holder == "p1" and not _shines(south, "lens-lamp") and south._closing.has("span"), "Taken from its cradle, the lens lights nothing and the span starts to close: %s" % [south._mechanisms.items.lens])
	var north := _sim("cradle", {}, {"path": "north"})
	_check(bool(north._optics.signals["north-eye"]) and Seven.predicate(north.stage.goal_policy.when, north.stage, north._players, north._mechanisms, north._optics.signals, true), "Set north, it lights the goal")
	_check(LightPieces.orientations(north.stage, north._mechanisms.controls) == {"steer": "slash"}, "And the steered mirror turns north")

func _graph() -> void:
	var graph := LevelGraph.new(level)
	var pad: Dictionary = level.stages[0]
	var start := Catalog.initial_checkpoint(level)
	var both := graph.reach(pad, start, true)
	_check(both.open.has("span") and both.floors.p0.has("isle") and both.floors.p1.has("isle"), "The span can be lit, so both pips reach the isle")
	var walking := graph.reach(pad, start, true, "", "p1")
	_check(walking.open.has("span") and not walking.own.has("span") and walking.floors.p1.has("isle") and not walking.floors.p0.has("isle"), "The pip on the light pad cannot walk the span it holds; the walker can")

func _world() -> void:
	var world: Node3D = JourneyWorld.new()
	world.descriptor_override = {"piece_styles": {"lens": "lens"}}
	root.add_child(world)
	world.reduced_motion = true
	world.load_level(level)
	await world.show_stage(level.stages[0])
	world.set_process(false)
	var cables: Array = world._lamp_cables.get("harbour-lamp", [])
	_check(not cables.is_empty(), "A cable runs from the light pad to its lamp")
	var lit := _sim("pad", {"p0": _at(60, 340)}, {"quay-mirror": "slash"})
	world.present(lit.snapshot(), true)
	_check(cables.all(func(cable: MeshInstance3D) -> bool: return _glows(cable)), "It glows while the lamp shines")
	await world.show_stage(level.stages[1])
	_check(world._mirror_nodes.has("steer") and world._cradles.has("cradle"), "The steered mirror and the lens's cradle are drawn")
	_check(world._item_pieces.has("lens") and world._item_pieces.lens.style == "lens", "The lens comes in its own look")
	var north := _sim("cradle", {}, {"path": "north"})
	world.present(north.snapshot(), true)
	_check(is_equal_approx(world._mirror_nodes.steer.rotation.y, PI / 4.0), "The steered mirror turns north with the selector")
	var south := _sim("cradle", {}, {"path": "south"})
	world.present(south.snapshot(), true)
	_check(is_equal_approx(world._mirror_nodes.steer.rotation.y, -PI / 4.0), "And south")
	world.queue_free()

static func _glows(node: MeshInstance3D) -> bool:
	var material := node.material_override as StandardMaterial3D
	return material != null and material.emission_enabled and material.emission_energy_multiplier > 0.0

# ---------------------------------------------------------------- helpers

func _sim(stage_id: String, players: Dictionary, controls: Dictionary = {}) -> Simulation:
	var checkpoint := Catalog.initial_checkpoint(level)
	checkpoint.next_stage_id = stage_id
	for slot: String in players: checkpoint.players[slot] = players[slot]
	for id: String in controls: checkpoint.mechanisms.controls[id] = controls[id]
	var sim := Simulation.new()
	sim.simulation_version = 16
	sim._reset_trusted(level, stage_id, checkpoint, {}, "a", [])
	return sim

static func _shines(sim: Simulation, lamp: String) -> bool:
	return sim._optics.segments.any(func(segment: Dictionary) -> bool: return segment.emitter_id == lamp)

static func _at(x: int, z: int, surface: String = "quay") -> Dictionary:
	return {"x": x, "z": z, "surface_id": surface, "height": 0}

static func _walk(sim: Simulation, to: Array) -> void:
	for axis in range(2):
		var key := "x" if axis == 0 else "z"
		for tick in range(300):
			var gap := int(to[axis]) - int(sim._players[sim.active_slot][key])
			if absi(gap) <= 1 or sim.finished: break
			var before := int(sim._players[sim.active_slot][key])
			var input := {"move_x": 0.0, "move_z": 0.0}
			input["move_" + key] = clampf(float(gap) / 8.0, -1.0, 1.0)
			sim.step(input)
			if int(sim._players[sim.active_slot][key]) == before and tick > 3: break

static func _idle(sim: Simulation, ticks: int) -> void:
	for tick in range(ticks):
		if sim.finished: return
		sim.step({})

static func _press(sim: Simulation) -> void:
	sim.step({"interact": true})
	sim.step({})

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
		print("FAIL: " + label)
