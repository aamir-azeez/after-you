extends SceneTree
## The new pieces' looks (presentation/kit/new_pieces.gd and its kits) built
## by the real journey world from the witness level (tests/pieces_witness.gd),
## its descriptor's pins taken from the blocks (content/blocks/defaults.gd):
## - the marsh: a lift and a raft, each one piece riding between its stops
##   (their stop decks left empty, no pulley); the rope ladder hung while a pip
##   stands at its foot and rolled up at its head otherwise; the lantern lever
##   and the weight pans in their styles; fog lying only on floors, clear of
##   every crossing, stair, control and the goal, cleared round the lantern
##   once it is lit;
## - the falls: the rope bridge, the dam and the stones in their deck styles,
##   the sack lift as a lift;
## - every snapshot the engine makes shows: the raft eases to the stop its
##   rope opens, the lift to its height.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/pieces_witness.gd")
const BlockDefaults = preload("res://content/blocks/defaults.gd")
const JourneyWorld = preload("res://presentation/journey_world.gd")
const Fog = preload("res://presentation/kit/fog.gd")
const MemoryTrace = preload("res://core/physical/memory_trace.gd")
var checks := 0
var failures := 0
var level: Dictionary

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	MemoryTrace.enabled = false
	level = Witness.definition()
	await _marsh()
	await _falls()
	print("PIECES WORLD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _world(stage_id: String) -> Node3D:
	var world: Node3D = JourneyWorld.new()
	world.descriptor_override = {"piece_styles": BlockDefaults.styles(Witness.source())}
	root.add_child(world)
	world.reduced_motion = true
	world.load_level(level)
	for stage: Dictionary in level.stages:
		if stage.id == stage_id: await world.show_stage(stage)
	world.set_process(false)
	return world

func _marsh() -> void:
	var world := await _world("marsh")
	var pieces: RefCounted = world.new_pieces
	_check(pieces != null and pieces._platforms.size() == 2 and pieces._platforms[0].lift and not pieces._platforms[1].lift, "The lift and the raft are each one piece")
	_check(pieces.deck_style("lift-low") == "" and pieces.deck_style("raft-south") == "" and not world._hangs_pulley({"id": "raft-north"}), "Their stops lay no deck of their own and hang no pulley")
	_check(pieces.deck_style("boards") == "plank" and world._hangs_pulley({"id": "boards"}), "The lantern's low boards are plain planks")
	_check(world._lever_pieces.lantern.style == "lantern" and world.pad_pieces.pan.style == "pan" and world.pad_pieces["top-pan"].style == "pan" and world._lever_pieces.rope.style == "rope_wheel", "The lantern, the pans and the rope wheel come in their own looks")
	_check(pieces._fills.size() == 1 and not pieces._fills[0].node.visible, "The lift's pan can fill with the lantern's water, dry while it is out")
	_check(pieces._ladders.has("ladder") and world.terrain.find_child("RopeLadder_rope", true, false) != null, "The one way stair is a rope ladder")
	# Fog: on floors only, clear of crossings, stairs, controls and the goal.
	var fog: RefCounted = pieces.fog
	_check(fog != null and fog.puffs().size() > 20, "Fog lies over the marsh: %d puffs" % [fog.puffs().size() if fog != null else 0])
	var clean := true
	if fog != null:
		for puff: Transform3D in fog.puffs():
			var at := Vector2(puff.origin.x, puff.origin.z) * 100.0
			for route: Dictionary in level.bridges + level.stairs:
				var rect: Array = route.rect_cm
				if Rect2(rect[0], rect[1], rect[2] - rect[0], rect[3] - rect[1]).grow(Fog.KEEP * 100.0 - 1.0).has_point(at): clean = false
			if not level.islands.any(func(island: Dictionary) -> bool: return Rect2(island.rect_cm[0], island.rect_cm[1], island.rect_cm[2] - island.rect_cm[0], island.rect_cm[3] - island.rect_cm[1]).has_point(at)): clean = false
	_check(clean, "No puff lies on or near a crossing, a stair or water")
	# Lit, the lantern clears the fog round it.
	var sim := _sim("marsh", {"p0": {"x": 780, "z": 300, "surface_id": "stilts", "height": 96}})
	world.present(sim.snapshot(), true)
	var shown := _shown_near(fog, Vector2(8.0, 3.0))
	sim.step({"interact": true})
	sim.step({})
	world.present(sim.snapshot(), true)
	_check(shown > 0 and _shown_near(fog, Vector2(8.0, 3.0)) == 0, "Lit, the lantern clears the fog round it (%d puffs before)" % shown)
	_check(pieces._fills[0].node.visible, "Lit, its pump fills the lift's pan")
	# The ladder: hung while a pip is at its foot, rolled up otherwise.
	var ladder: RefCounted = pieces._ladders.ladder.piece
	_check(not ladder._hung.visible and ladder._rolled.visible, "With nobody at its foot the ladder is pulled up")
	var foot := _sim("marsh", {"p0": {"x": 360, "z": 350, "surface_id": "landing", "height": 0}})
	world.present(foot.snapshot(), true)
	_check(ladder._hung.visible and not ladder._rolled.visible, "A pip at its foot lets it down")
	# The raft eases to the stop its rope opens; the lift rises to its height.
	var raft: RefCounted = pieces._platforms[1].piece
	var pulled := _sim("marsh", {"p0": {"x": 300, "z": 890, "surface_id": "isle", "height": 0}})
	world.present(pulled.snapshot(), true)
	pulled.step({"interact": true})
	world.reduced_motion = false
	world.present(pulled.snapshot(), false)
	_check(raft.moving(), "Pulled, the raft sets off south")
	for frame in range(200): if raft.moving(): raft.advance(1.0 / 30.0)
	_check(is_equal_approx(raft.root.position.z, 6.6), "It comes to rest at the south stop: %s" % raft.root.position)
	var weighed := _sim("marsh", {"p0": {"x": 100, "z": 100, "surface_id": "landing", "height": 0}})
	world.present(weighed.snapshot(), true)
	_check(is_equal_approx(pieces._platforms[0].piece.root.position.y, 0.96), "Weighed, the lift stands at the stilts")
	world.queue_free()
	await process_frame

func _falls() -> void:
	var world := await _world("falls")
	var pieces: RefCounted = world.new_pieces
	_check(pieces.deck_style("span") == "rope" and pieces.deck_style("behind") == "falls_path" and pieces.deck_style("s1") == "stones", "The rope bridge, the path behind the falls and the stones lay their own decks")
	_check(not world._hangs_pulley({"id": "span"}) and pieces._platforms.size() == 1 and not pieces._platforms[0].lift, "No pulley on them; the punt is a raft")
	_check(pieces._curtains.has("behind") and pieces._curtains.behind.visible, "The falls' water hangs over the path while the water gate is shut")
	_check(pieces._ladders.wheel.wheel and world.pad_pieces["gate-board"].style == "board" and world.pad_pieces.crank.style == "crank_board", "The wheel ride, the gate board and the crank boards come in their own looks")
	var held := _sim("falls", {"p0": {"x": 250, "z": 1520, "surface_id": "bank", "height": 0}})
	world.reduced_motion = false
	world.present(held.snapshot(), false)
	_check(pieces._ladders.wheel.piece.moving(), "The board held, the wheel turns")
	var opened := _sim("falls", {"p0": {"x": 700, "z": 1250, "surface_id": "far", "height": 0}})
	opened.step({"interact": true})
	world.present(opened.snapshot(), true)
	_check(not pieces._curtains.behind.visible, "With the water gate pulled the path is dry and clear")
	_check(pieces.fog == null, "No lantern, no fog")
	world.queue_free()
	await process_frame

func _shown_near(fog: RefCounted, at: Vector2) -> int:
	return fog.shown().filter(func(puff: Vector3) -> bool: return Vector2(puff.x, puff.z).distance_to(at) < Fog.CLEAR - 0.1).size()

func _sim(stage_id: String, players: Dictionary) -> Simulation:
	var checkpoint := Catalog.initial_checkpoint(level)
	checkpoint.next_stage_id = stage_id
	for slot: String in players: checkpoint.players[slot] = players[slot]
	var sim := Simulation.new()
	sim.simulation_version = 16
	sim._reset_trusted(level, stage_id, checkpoint, {}, "a")
	return sim

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
		print("FAIL: " + label)
