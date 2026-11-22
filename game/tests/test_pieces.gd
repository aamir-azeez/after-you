extends SceneTree
## The new pieces (rules 20, core/physical/pieces_rules.gd) on their witness
## level (tests/pieces_witness.gd), played through the journey engine with
## kept start worlds off (a later turn plays the turns before it again):
## - 20 is a tide, open controls and open turns number, records name it, and
##   the blocks expand to the plain data the engine reads, with no problems;
## - the fog lantern: lit, its pump floods the low boards; out, they are dry;
## - the weight lift: a pip on the pan lifts the live pip riding it to the
##   stilts; one on the top pan brings it down; stops never close slowly;
## - the rope raft: the friend's replay pulls and carries the live pip over
##   the water;
## - the replay rides too, in the one world: on the lift as it rises it rides
##   up, on the raft as the live pip pulls it crosses the water, and a live pip
##   and the replay on one lift ride up together, whoever winds it; a third
##   turn takes over with the rest of the second replaying as it was played;
## - the ride witness (tests/ride_witness.gd) through the real proof: carried
##   up, the replay's walk into the stilts' edge takes it on to the lamp; both
##   turns replay exactly, from a kept start world or played again; the stage's checkpoint
##   derives and verifies; the server's copy (tests/fixtures/memory_rides/,
##   read by backend/test/pieces-rules.test.ts) is this suite's, and
##   `-- --write` writes it again;
## - the pull-up ladder: climbed to the stilts, never come down;
## - sinking stones: one pip stands on a stone, the second pushes it under,
##   the one that stepped on last (live or replayed) named;
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
const RideWitness = preload("res://tests/ride_witness.gd")
const Proof = preload("res://core/physical/two_pair_proof.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const SERVER_FIXTURES := "res://tests/fixtures/memory_rides/"
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
	_memory_rides()
	_ride_witness()
	_ladder()
	_stones()
	_crossings()
	_graph()
	print("PIECES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _numbers() -> void:
	var v := OpenControls.PIECES_RULES_VERSION
	_check(v == 20 and PiecesRules.on(20) and not PiecesRules.on(19), "The new pieces are rules 20")
	_check(v in OpenControls.TIDE_RULES and v in OpenControls.OPEN_RULES and OpenTurns.rules(v), "20 keeps the tide, open controls and open turns")
	_check(Simulation._record_version({"simulation_version": 20.0}) == 20, "A record names rules 20, JSON floats included")
	_check(level.simulation_version == 20 and PiecesRules.pinned(level) and Simulation.rules_allowed(level, 20) and not Simulation.rules_allowed(level, 19), "The witness pins 20 and plays nothing else")

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
	# Turn 2: the second pip steps onto the lift before the replay weighs the pan, and rides up.
	var b := _sim("marsh", start, record, "b")
	_check(b.active_slot == "p1" and bool(b._routes["lift-low"]), "Turn 2 is the second pip's, with the lift down")
	_walk(b, [450, 200])
	var rode := false
	for tick in range(120):
		b.step({})
		if b._players.p1.surface_id == "lift-high": rode = true
		if rode or b.finished: break
	_check(rode and int(b._players.p1.height) == 96 and int(b._players.p1.x) == 450 and b._drowned.is_empty(), "The replay weighs the pan and the live pip rides the lift up: %s" % [b._players.p1])
	_walk(b, [600, 200])
	_check(b._players.p1.surface_id == "stilts", "And steps off onto the stilts")
	_walk(b, [850, 50])
	_check(not bool(b._routes["lift-high"]) and bool(b._routes["lift-low"]), "Weight in the top pan too brings the lift back down")
	# Turn 3: the first pip takes over on the pan where turn 1 left it, in
	# turn 2's world there, and with it staying put the rest of turn 2 plays
	# out as it was played.
	var turn_two := b.export_recording()
	var e := _sim("marsh", start, turn_two, "b", {}, [record])
	_check(e.handoff_tick == int(record.duration_ticks) and e._players.p0.surface_id == a._players.p0.surface_id and bool(e._routes["lift-high"]), "Turn 3 takes over on the pan, the lift up")
	_idle(e, e.replay_ticks())
	_check(e._drowned.is_empty() and Canonical.same(e._players.p1, b._players.p1) and not bool(e._routes["lift-high"]), "The rest of turn 2 plays out as it was played: %s" % [e._players.p1])

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
	_check(rode and int(b._players.p1.z) == 660 and "rode:raft" in b._events, "The replay's pull carries the live pip over the water: %s" % [b._players.p1])
	_walk(b, [200, 800])
	_check(b._players.p1.surface_id == "isle", "And it steps off onto the isle")

## The friend's replay rides too (core/journey/simulation.gd _move_platforms).
func _memory_rides() -> void:
	# Up the lift: the first pip waits on it, the second weighs the pan.
	var start := {"p0": _at(100, 300, "landing", 0), "p1": _at(350, 200, "landing", 0)}
	var c := _sim("marsh", start)
	_walk(c, [350, 200])
	_walk(c, [450, 200])
	var boarded := int(c.tick)
	_idle(c, 10)
	var d := _sim("marsh", start, c.export_recording(), "b")
	_idle(d, boarded + 2)
	_walk(d, [100, 100])
	_idle(d, 40)
	var memory: Dictionary = d._players.p0
	_check(d._drowned.is_empty() and memory.surface_id == "lift-high" and int(memory.height) == 96 and int(memory.x) == int(c._players.p0.x) and int(memory.z) == int(c._players.p0.z), "The replay standing on the lift as it rises rides up with it: %s" % [memory])
	# Over the water: the first pip waits on the raft, the second pulls the rope.
	var shore := {"p0": _at(200, 300, "landing", 0), "p1": _at(300, 860, "isle", 0)}
	var a := _sim("marsh", shore)
	_walk(a, [200, 440])
	_check(a._players.p0.surface_id == "raft-north", "The first pip waits on the raft at the landing")
	_idle(a, 10)
	var b := _sim("marsh", shore, a.export_recording(), "b")
	_idle(b, int(a.tick))
	_walk(b, [300, 885])
	_press(b)
	memory = b._players.p0
	_check(b._mechanisms.controls.rope == "SOUTH" and b._drowned.is_empty() and memory.surface_id == "raft-south" and int(memory.z) == 660 and int(memory.x) == 200, "The live pip's pull carries the replay over the water: %s" % [memory])
	# One lift, both pips: the live pip winds the crank inside it with the replay aboard.
	var ride := RideWitness.definition()
	var begin := RideWitness.initial_checkpoint(ride)
	var waits := _witness_sim(ride, begin)
	_walk(waits, [440, 200])
	_idle(waits, 60)
	var aboard := _witness_sim(ride, begin, _json(waits.export_recording()))
	_idle(aboard, 50)
	_walk(aboard, [300, 210])
	_walk(aboard, [460, 210])
	_press(aboard)
	_check(aboard._drowned.is_empty() and aboard._players.p0.surface_id == "lift-high" and aboard._players.p1.surface_id == "lift-high" and int(aboard._players.p0.height) == 96 and int(aboard._players.p0.x) == int(waits._players.p0.x), "Wound from inside, the lift carries the live pip and the replay up together: %s" % [aboard._players])
	# And the replay winds it with the live pip aboard.
	var winds := _witness_sim(ride, begin)
	_walk(winds, [440, 200])
	_idle(winds, 120 - int(winds.tick))
	_press(winds)
	_check(winds._players.p0.surface_id == "lift-high", "Turn 1 winds the crank and rides up alone")
	_idle(winds, 10)
	var rider := _witness_sim(ride, begin, _json(winds.export_recording()))
	_walk(rider, [300, 210])
	_walk(rider, [460, 210])
	_idle(rider, 130 - int(rider.tick))
	_check(rider._drowned.is_empty() and rider._players.p1.surface_id == "lift-high" and Canonical.same(rider._players.p0, winds._players.p0), "The replay's crank carries the live pip up with it, the replay where its own turn had it: %s" % [rider._players])

## The ride witness through the real proof, and the server's copy of it.
func _ride_witness() -> void:
	var ride := RideWitness.definition()
	var begin := RideWitness.initial_checkpoint(ride)
	var proof := Proof.new(RideWitness, Simulation, OpenControls.PIECES_RULES_VERSION, Simulation.CURRENT_SIMULATION_VERSION)
	_check(PiecesRules.problems(ride).is_empty() and StageBlocks.problems(RideWitness.source()).is_empty(), "The ride witness is sound")
	# Turn 1: p0 stands on the lift, then walks east into the stilts' edge, getting nowhere.
	var a_sim := _witness_sim(ride, begin)
	_walk(a_sim, [450, 200])
	_idle(a_sim, 200 - int(a_sim.tick))
	for _step in range(19): a_sim.step({"move_x": 1.0})
	_idle(a_sim, 10)
	_check(a_sim._players.p0.surface_id == "lift-low" and int(a_sim._players.p0.x) < 500, "Alone, the first pip's walk east ends at the stilts' edge: %s" % [a_sim._players.p0])
	var a: Dictionary = _json(a_sim.export_recording())
	# Turn 2: p1 winds the winch, the lift carries the replay up, and the replay's
	# walk east now takes it onto the stilts to the lamp; p1 climbs the ladder.
	var b_sim := _witness_sim(ride, begin, a)
	_walk(b_sim, [300, 70])
	_idle(b_sim, 150 - int(b_sim.tick))
	b_sim.step({"interact": true})
	_check(b_sim._players.p0.surface_id == "lift-high" and "rode:lift" in b_sim.snapshot().events, "The winch carries the replay up the lift: %s" % [b_sim._players.p0])
	b_sim.step({})
	_walk(b_sim, [350, 70])
	_walk(b_sim, [350, 350])
	_walk(b_sim, [600, 350])
	_walk(b_sim, [600, 210])
	_idle(b_sim, 1200)
	var memory: Dictionary = b_sim._players.p0
	_check(memory.surface_id == "stilts" and int(memory.height) == 96 and absi(int(memory.x) - RideWitness.LAMP[0]) <= 40, "Carried up, the replay's walk takes it onto the stilts to the lamp: %s" % [memory])
	_check(b_sim.complete, "Both pips at the lamp close the stage (%s)" % b_sim.commit_reason())
	var b: Dictionary = _json(b_sim.export_recording())
	MemoryTrace.enabled = true
	MemoryTrace.clear()
	for pair: Array in [[a, {}], [b, a]]:
		var checked: Dictionary = proof._verify_raw(ride, pair[0], begin, pair[1])
		_check(checked.valid, "Turn %s replays exactly (%s)" % [pair[0].role, checked.get("error", "")])
	var from_kept := _witness_sim(ride, begin, a)
	_replay(from_kept, b)
	MemoryTrace.enabled = false
	var played := _witness_sim(ride, begin, a)
	_replay(played, b)
	_check(Canonical.same(_json(from_kept.export_recording()), b) and Canonical.same(_json(played.export_recording()), b), "Turn 2 plays byte for byte the same from its kept start world as with turn 1 played again")
	MemoryTrace.enabled = true
	var derived: Dictionary = proof.derive_checkpoint(ride, begin, a, b, [])
	MemoryTrace.enabled = false
	_check(derived.valid, "The stage's checkpoint derives (%s)" % derived.get("error", ""))
	if not derived.valid: return
	var checkpoint: Dictionary = _json(derived.checkpoint)
	_check(checkpoint.players.p0.surface_id == "stilts" and proof.verify_checkpoint(ride, checkpoint).valid, "It has the replayed pip on the stilts, carried there, and verifies again")
	var files := {"definition.json": ride, "initial.json": begin, "a.json": a, "b.json": b, "checkpoint.json": checkpoint}
	var write := "--write" in OS.get_cmdline_user_args()
	if write: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SERVER_FIXTURES))
	for name: String in files:
		var path := SERVER_FIXTURES.path_join(name)
		var value: Variant = _json(files[name])
		if write:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(JSON.stringify(value, "  ", false) + "\n")
			file.close()
		var kept: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_check(kept != null and Canonical.same(kept, value), "The server's ride witness %s is this suite's (-- --write to write it)" % name)

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
	# The replay steps onto the stone the live pip already stands on: the replay sank it.
	var first := _sim("falls", {"p0": _at(200, 1340, "bank", 0), "p1": _at(200, 1250, "bank", 0)}, {}, "a", low)
	_idle(first, 40)
	_walk(first, [340, 1340])
	_idle(first, 5)
	var b := _sim("falls", {"p0": _at(200, 1340, "bank", 0), "p1": _at(200, 1250, "bank", 0)}, first.export_recording(), "b", low)
	_walk(b, [200, 1330])
	_walk(b, [345, 1330])
	_idle(b, 80)
	_check(b._drowned.get("slot") == "p0" and b._drowned.get("route") == "s1" and b.commit_reason() == Simulation.DROWNED_FRIEND, "The replay stepping on last is the one that sank it: %s" % [b._drowned])

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
## the opening checkpoint (unregistered: no proof, the turns before played again).
func _sim(stage_id: String, players: Dictionary, prior: Dictionary = {}, role: String = "a", controls: Dictionary = {}, chain: Array = []) -> Simulation:
	var checkpoint := Catalog.initial_checkpoint(level)
	checkpoint.next_stage_id = stage_id
	for slot: String in players: checkpoint.players[slot] = players[slot]
	for id: String in controls: checkpoint.mechanisms.controls[id] = controls[id]
	var sim := Simulation.new()
	sim.simulation_version = 20
	sim._reset_trusted(level, stage_id, checkpoint, prior, role, chain)
	return sim

## A turn on the ride witness from `checkpoint`, packed as the server asks.
func _witness_sim(ride: Dictionary, checkpoint: Dictionary, prior: Dictionary = {}) -> Simulation:
	var sim := Simulation.new()
	sim.simulation_version = OpenControls.PIECES_RULES_VERSION
	sim.packed_recordings = true
	sim._reset_trusted(ride, "lift", checkpoint, prior, "a" if prior.is_empty() else "b")
	return sim

static func _replay(sim: Simulation, record: Dictionary) -> void:
	for input: Dictionary in Simulation.expand_recording_inputs(record): sim.step(input)

static func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

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
