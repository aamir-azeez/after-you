extends SceneTree
## The new pieces (rules 16, core/physical/pieces_rules.gd) on their witness
## level (tests/pieces_witness.gd), played through the journey engine with
## the memory trace off (an unregistered level replays its memory in its own
## world, untrusted proofs aside):
## - 16 is a tide, open controls and open turns number, records name it, and
##   the blocks expand to the plain data the engine reads, with no problems;
## - the fog lantern: lit, its pump floods the low boards; out, they are dry;
## - the weight lift: a pip on the pan lifts the live pip riding it to the
##   stilts; one on the top pan brings it down; a memory left on the lift as
##   it leaves drowns (DROWNED_FRIEND); stops never close slowly;
## - the rope raft: the memory's pull carries the live pip over the water;
## - the pull-up ladder: climbed to the stilts, never come down;
## - sinking stones: one pip stands on a stone, the second pushes it under,
##   the one that stepped on last (live or memory) named;
## - a crank board at either end holds the rope bridge; the water gate dries
##   the path behind the falls; the wheel ride carries a pip up while the gate
##   board is held, never down; a pan holds the footbridge down;
## - the level graph: rides reach the stilts, a lantern that could be out
##   leaves the boards dry, and the ladder runs one way.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/pieces_witness.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const BlockDefaults = preload("res://content/blocks/defaults.gd")
const MemoryTrace = preload("res://core/physical/memory_trace.gd")
const LevelGraph = preload("res://tests/level_graph.gd")
var checks := 0
var failures := 0
var level: Dictionary

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	MemoryTrace.enabled = false
	level = Witness.definition()
	_numbers()
	_blocks()
	_fog_lantern()
	_weight_lift()
	_raft()
	_ladder()
	_stones()
	_crossings()
	_graph()
	print("PIECES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _numbers() -> void:
	var v := OpenControls.PIECES_RULES_VERSION
	_check(v == 16 and PiecesRules.on(16) and not PiecesRules.on(15), "The new pieces are rules 16")
	_check(v in OpenControls.TIDE_RULES and v in OpenControls.OPEN_RULES and OpenTurns.rules(v), "16 keeps the tide, open controls and open turns")
	_check(Simulation._record_version({"simulation_version": 16.0}) == 16, "A record names rules 16, JSON floats included")
	_check(level.simulation_version == 16 and PiecesRules.pinned(level) and Simulation.rules_allowed(level, 16) and not Simulation.rules_allowed(level, 15), "The witness pins 16 and plays nothing else")

func _blocks() -> void:
	var source := Witness.source()
	_check(StageBlocks.problems(source).is_empty(), "The witness's blocks have no problems: %s" % [StageBlocks.problems(source)])
	_check(PiecesRules.problems(level).is_empty(), "The witness's pieces are sound: %s" % [PiecesRules.problems(level)])
	_check(PiecesRules.uses(level).size() == 7, "It uses both one way stairs, platforms and not on both stages, and stones on the falls: %s" % [PiecesRules.uses(level)])
	var marsh: Dictionary = level.stages[0]
	_check(marsh.platforms == [{"id": "lift", "stops": ["lift-low", "lift-high"]}, {"id": "raft", "stops": ["raft-north", "raft-south"]}], "The lift and the raft are the marsh's platforms: %s" % [marsh.platforms])
	var pan := {"any": [{"pad_id": "pan"}, {"item_id": "pipsport", "spot_id": "pan"}]}
	var top := {"any": [{"pad_id": "top-pan"}, {"item_id": "pipsport", "spot_id": "top-pan"}]}
	var up := {"all": [{"any": [pan, {"lever_id": "lantern"}]}, {"not": top}]}
	_check(_gate(marsh, "lift-high") == up and _gate(marsh, "lift-low") == {"not": up}, "The lift stands high while its pan holds a pip or the pipsport or the lantern's pump fills it, and the top pan is empty: %s" % [_gate(marsh, "lift-high")])
	_check(_gate(marsh, "boards") == {"not": {"lever_id": "lantern"}} and _gate(marsh, "reeds") == {"lever_id": "lantern"}, "The lantern's pump floods the boards and drains the reed stones while it burns")
	_check(_gate(marsh, "raft-south") == {"control_id": "rope", "value": "SOUTH"} and _gate(marsh, "ladder") == {}, "The raft goes where its rope sends it; the ladder always hangs")
	_check(_stair("ladder").get("one_way") == "up" and not Witness.source().stairs[0].has("one_way"), "The rope ladder block makes its stair one way up, in the expanded copy only")
	var falls: Dictionary = level.stages[1]
	_check(falls.sinking == ["s1", "s2"] and _gate(falls, "s1") == {"control_id": "pool", "value": "LOW"}, "The stones sink one at a time and stand dry at LOW")
	_check(_gate(falls, "behind") == {"lever_id": "water-gate"} and _gate(falls, "span") == {"any": [{"pad_id": "crank"}, {"pad_id": "east-crank"}]}, "The water gate dries the path behind the falls; either crank board holds the rope bridge")
	_check(_gate(falls, "wheel") == {"pad_id": "gate-board"} and _stair("wheel").get("one_way") == "up", "The wheel ride turns while the gate board is held, up only")
	_check(_stair("wheel").get("hands") == true and _stair("ladder").get("hands") == true and level.bridges.filter(func(bridge: Dictionary) -> bool: return bridge.get("hands", false)).map(func(bridge: Dictionary) -> String: return bridge.id) == ["span"], "Ladders, the wheel ride and the rope bridge need both hands")
	_check(_gate(falls, "foot") == {"any": [{"pad_id": "foot-pan"}, {"item_id": "pipsport", "spot_id": "foot-pan"}]}, "The footbridge is down while its pan holds a pip or the pipsport")
	_check(falls.platforms == [{"id": "punt", "stops": ["punt-a", "punt-b"]}], "A plain platform names its own stops")
	var styles := BlockDefaults.styles(source)
	_check(styles.get("lantern") == "lantern" and styles.get("pan") == "pan" and styles.get("top-pan") == "pan" and styles.get("rope") == "rope_wheel" and styles.get("crank") == "crank_board" and styles.get("span") == "rope" and styles.get("s1") == "stones" and styles.get("wheel") == "wheel" and styles.get("behind") == "falls_path" and styles.get("foot-pan") == "pan" and styles.get("gate-board") == "board", "Each new piece's block gives its look by default: %s" % [styles])
	var bad := Witness.source()
	bad.stages[1].blocks.append({"block": "crank_bridge", "routes": ["span"]})
	bad.stages[0].blocks.append({"block": "platform", "id": "odd", "stops": {"boards": {}}})
	_check(StageBlocks.problems(bad).size() == 2, "A crank bridge with no crank and a one stop platform are named: %s" % [StageBlocks.problems(bad)])
	var lopsided := level.duplicate(true)
	lopsided.bridges[1].rect_cm = [400, 150, 520, 250]
	_check(PiecesRules.problems(lopsided).size() == 1, "Platform stops of two sizes are named")

func _fog_lantern() -> void:
	var sim := _sim("marsh", {"p0": _at(780, 300, "stilts", 96)})
	_check(bool(sim._routes.boards), "Out, the lantern leaves the low boards dry")
	_press(sim)
	_check(bool(sim._mechanisms.levers.lantern) and bool(sim._routes.boards) and sim._closing.has("boards"), "Lit, its pump starts flooding the boards, slowly as on the tide rules")
	_idle(sim, int(level.closing_ticks))
	_check(not bool(sim._routes.boards), "Then they are under")
	_check(sim._at_goal("p0") == false and Simulation.Seven.predicate(sim.stage.goal_policy.when, sim.stage, sim._players, sim._mechanisms), "Lit, it lights the goal")
	_press(sim)
	_check(bool(sim._routes.boards), "Put out again, the boards come back")

func _weight_lift() -> void:
	var start := {"p0": _at(100, 300, "landing", 0), "p1": _at(350, 200, "landing", 0)}
	# Turn 1: the first pip walks onto the pan and stays.
	var a := _sim("marsh", start)
	_walk(a, [100, 100])
	_check(bool(a._routes["lift-high"]) and not bool(a._routes["lift-low"]), "Weight in the pan raises the lift; its low stop shuts at once")
	_idle(a, 20)
	var record := a.export_recording()
	# Turn 2: the second pip steps onto the lift before the memory weighs the pan, and rides up.
	var b := _sim("marsh", start, record, "b")
	_check(b.active_slot == "p1" and bool(b._routes["lift-low"]), "Turn 2 is the second pip's, with the lift down")
	_walk(b, [450, 200])
	var rode := false
	for tick in range(120):
		b.step({})
		if b._players.p1.surface_id == "lift-high": rode = true
		if rode or b.finished: break
	_check(rode and int(b._players.p1.height) == 96 and int(b._players.p1.x) == 450 and b._drowned.is_empty(), "The memory weighs the pan and the live pip rides the lift up: %s" % [b._players.p1])
	_walk(b, [600, 200])
	_check(b._players.p1.surface_id == "stilts", "And steps off onto the stilts")
	_walk(b, [850, 50])
	_check(not bool(b._routes["lift-high"]) and bool(b._routes["lift-low"]), "Weight in the top pan too brings the lift back down")
	# A memory left on the lift as it rises drowns.
	var c := _sim("marsh", start)
	_walk(c, [350, 200])
	_walk(c, [450, 200])
	_idle(c, 10)
	var on_lift := c.export_recording()
	var d := _sim("marsh", start, on_lift, "b")
	_walk(d, [100, 100])
	_idle(d, 40)
	_check(d._drowned.get("slot") == "p0" and d._drowned.get("route") == "lift-low" and d.commit_reason() == Simulation.DROWNED_FRIEND, "A memory standing on the lift as it leaves drowns: %s" % [d._drowned])

func _raft() -> void:
	var start := {"p0": _at(300, 890, "isle", 0), "p1": _at(200, 300, "landing", 0)}
	var a := _sim("marsh", start)
	_idle(a, 60)
	_press(a)
	_check(a._mechanisms.controls.rope == "SOUTH" and bool(a._routes["raft-south"]) and not bool(a._routes["raft-north"]), "Pulled, the raft goes south at once")
	_idle(a, 10)
	var b := _sim("marsh", start, a.export_recording(), "b")
	_walk(b, [200, 440])
	_check(b._players.p1.surface_id == "raft-north", "The live pip stands on the raft at the landing")
	var rode := false
	for tick in range(90):
		b.step({})
		if b._players.p1.surface_id == "raft-south": rode = true
		if rode or b.finished: break
	_check(rode and int(b._players.p1.z) == 660 and "rode:raft" in b._events, "The memory's pull carries the live pip over the water: %s" % [b._players.p1])
	_walk(b, [200, 800])
	_check(b._players.p1.surface_id == "isle", "And it steps off onto the isle")

func _ladder() -> void:
	var sim := _sim("marsh", {"p0": _at(300, 350, "landing", 0)})
	_walk(sim, [600, 350])
	_check(sim._players.p0.surface_id == "stilts" and int(sim._players.p0.height) == 96, "The rope ladder climbs to the stilts: %s" % [sim._players.p0])
	_walk(sim, [300, 350])
	_check(int(sim._players.p0.height) == 96 and int(sim._players.p0.x) >= 500, "Once climbed, it never takes a pip down: %s" % [sim._players.p0])

func _stones() -> void:
	var low := {"pool": "LOW"}
	var start := {"p0": _at(200, 1340, "bank", 0), "p1": _at(340, 1340, "s1", 0)}
	var a := _sim("falls", start, {}, "a", low)
	_check(bool(a._routes.s1) and bool(a._routes.s2), "The stones stand dry at LOW")
	_walk(a, [340, 1340])
	_check(a.finished and a._drowned.get("slot") == "p0" and a._drowned.get("route") == "s1" and "sank:s1" in a._events and a.commit_reason() == Simulation.DROWNED_YOU, "The second pip on a stone pushes it under: %s" % [a._drowned])
	var apart := _sim("falls", {"p0": _at(200, 1340, "bank", 0), "p1": _at(420, 1340, "s2", 0)}, {}, "a", low)
	_walk(apart, [340, 1340])
	_check(not apart.finished and apart._players.p0.surface_id == "s1", "One pip a stone holds")
	# The memory steps onto the stone the live pip already stands on: the memory sank it.
	var first := _sim("falls", {"p0": _at(200, 1340, "bank", 0), "p1": _at(200, 1250, "bank", 0)}, {}, "a", low)
	_idle(first, 40)
	_walk(first, [340, 1340])
	_idle(first, 5)
	var b := _sim("falls", {"p0": _at(200, 1340, "bank", 0), "p1": _at(200, 1250, "bank", 0)}, first.export_recording(), "b", low)
	_walk(b, [200, 1330])
	_walk(b, [345, 1330])
	_idle(b, 80)
	_check(b._drowned.get("slot") == "p0" and b._drowned.get("route") == "s1" and b.commit_reason() == Simulation.DROWNED_FRIEND, "The memory stepping on last is the one that sank it: %s" % [b._drowned])

func _crossings() -> void:
	var sim := _sim("falls", {"p0": _at(100, 1500, "bank", 0)})
	_check(not bool(sim._routes.s1), "At HIGH the stones are under")
	_walk(sim, [100, 1550])
	_press(sim)
	_check(sim._mechanisms.controls.pool == "LOW" and bool(sim._routes.s1), "At LOW the stones are dry")
	var crank := _sim("falls", {"p0": _at(700, 1450, "far", 0)})
	_check(not bool(crank._routes.span) and not bool(crank._routes.behind), "The rope bridge hangs slack and the falls cover the path behind them")
	_walk(crank, [750, 1520])
	_check(bool(crank._routes.span), "Standing on a crank board pulls the rope bridge tight")
	_walk(crank, [700, 1450])
	_idle(crank, int(level.closing_ticks))
	_check(not bool(crank._routes.span), "Stepping off lets it go slack")
	_walk(crank, [700, 1250])
	_press(crank)
	_check(bool(crank._routes.behind), "Pulling the water gate dries the path behind the falls")
	# The wheel ride: the board held, a pip rides up to the loft and never back down.
	var ride := _sim("falls", {"p0": _at(150, 1560, "bank", 0), "p1": _at(250, 1520, "bank", 0)})
	_check(bool(ride._routes.wheel), "The gate board held, the wheel turns")
	_walk(ride, [150, 1750])
	_check(ride._players.p0.surface_id == "loft" and int(ride._players.p0.height) == 96, "The wheel carries a pip up to the loft: %s" % [ride._players.p0])
	_walk(ride, [150, 1560])
	_check(int(ride._players.p0.height) == 96, "And never back down")
	var still := _sim("falls", {"p0": _at(150, 1560, "bank", 0)})
	_walk(still, [150, 1650])
	_check(still._players.p0.surface_id == "bank", "With nobody on the gate board the wheel stands still")
	var pan := _sim("falls", {"p0": _at(1100, 1550, "cliff", 0)})
	_check(not bool(pan._routes.foot), "The footbridge is up with its pan empty")
	_walk(pan, [1150, 1550])
	_check(bool(pan._routes.foot), "A pip in the pan brings it down")

func _graph() -> void:
	var graph := LevelGraph.new(level)
	var marsh: Dictionary = level.stages[0]
	var start := Catalog.initial_checkpoint(level)
	var reach := graph.reach(marsh, start, true)
	_check(reach.floors.p0.has("stilts") and reach.floors.p0.has("lift-high"), "The graph reaches the stilts by the ladder and by riding the lift")
	_check(reach.open.has("boards") and reach.floors.p1.has("jetty"), "A lantern that may be out leaves the boards walkable")
	_check(graph.pairs.p0.has("landing>ladder") and graph.pairs.p0.has("ladder>stilts") and not graph.pairs.p0.has("stilts>ladder") and not graph.pairs.p0.has("ladder>landing"), "The ladder runs up only")
	_check(graph.pairs.p0.has("lift-low>lift-high") and graph.pairs.p0.has("raft-south>raft-north"), "Every platform's stops are joined by rides")

# ---------------------------------------------------------------- helpers

## A trusted turn on `stage_id` with players and controls moved in a copy of
## the opening checkpoint (unregistered: no proof, memory replayed in its own world).
func _sim(stage_id: String, players: Dictionary, prior: Dictionary = {}, role: String = "a", controls: Dictionary = {}) -> Simulation:
	var checkpoint := Catalog.initial_checkpoint(level)
	checkpoint.next_stage_id = stage_id
	for slot: String in players: checkpoint.players[slot] = players[slot]
	for id: String in controls: checkpoint.mechanisms.controls[id] = controls[id]
	var sim := Simulation.new()
	sim.simulation_version = 16
	sim._reset_trusted(level, stage_id, checkpoint, prior, role)
	return sim

static func _at(x: int, z: int, surface: String, height: int) -> Dictionary:
	return {"x": x, "z": z, "surface_id": surface, "height": height}

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

func _gate(stage: Dictionary, route: String) -> Dictionary:
	for gate: Dictionary in stage.gates:
		if gate.route_id == route: return gate.get("when", {})
	return {"missing": true}

func _stair(id: String) -> Dictionary:
	for stair: Dictionary in level.stairs:
		if stair.id == id: return stair
	return {}

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
		print("FAIL: " + label)
