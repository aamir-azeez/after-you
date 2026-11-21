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
## - the falls: the rope bridge, the stones and the path behind the falls in
##   their deck styles, the falls' water over the path while it is shut, the
##   wheel ride turning while its board is held, boards and crank boards;
## - every snapshot the engine makes shows: the raft eases to the stop its
##   rope opens, the lift to its height;
## - one rider rule (kit/new_pieces.gd ride_offset): whatever stands or rests on
##   a platform's stop is drawn on its deck frame by frame while the deck eases
##   between stops, never at the stop the simulation already moved it to: a
##   memory or the live pip riding the lift up and down or the raft over the
##   water, a carried item over a memory's head, an item put down on the lift;
##   a memory that walks off the lift before its deck is up waits on the deck,
##   which hurries there, and never hops.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/pieces_witness.gd")
const BlockDefaults = preload("res://content/blocks/defaults.gd")
const JourneyWorld = preload("res://presentation/journey_world.gd")
const Fog = preload("res://presentation/kit/fog.gd")
const MemoryTrace = preload("res://core/physical/memory_trace.gd")
const ItemWitness = preload("res://tests/item_ride_witness.gd")
## A frame a tick at 30 Hz, in two steps, as a 60 Hz phone draws them.
const FRAME := 1.0 / 60.0
## How far (m) a drawn rider may sit from where its deck has it.
const ON_DECK := 0.002
## The most a riding pip may move in one frame (m): up or down on a lift, a
## hurried lift's pace; on a raft, a hurried raft's (kit/new_pieces.gd HURRY).
## A hop to the far stop moves far more.
const STEP := {true: 0.06, false: 0.12}
var checks := 0
var failures := 0
var level: Dictionary

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	MemoryTrace.enabled = false
	level = Witness.definition()
	await _marsh()
	await _falls()
	await _riders()
	await _item_riders()
	print("PIECES WORLD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _world(stage_id: String, shown: Dictionary = level, source: Dictionary = Witness.source()) -> Node3D:
	var world: Node3D = JourneyWorld.new()
	world.descriptor_override = {"piece_styles": BlockDefaults.styles(source)}
	root.add_child(world)
	world.reduced_motion = true
	world.load_level(shown)
	for stage: Dictionary in shown.stages:
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

## Memories and the live pip ride the lift up and down and the raft over the
## water on its deck, frame by frame.
func _riders() -> void:
	var world := await _world("marsh")
	world.reduced_motion = false
	# Turn 1: the first pip waits on the lift.
	var start := {"p0": {"x": 100, "z": 300, "surface_id": "landing", "height": 0}, "p1": {"x": 350, "z": 200, "surface_id": "landing", "height": 0}}
	var first := _sim("marsh", start)
	_walk(first, [350, 200])
	_walk(first, [450, 200])
	var boarded := int(first.tick)
	_idle(first, 10)
	# Turn 2: the live pip weighs the pan, the lift takes the memory up; off the
	# pan, it brings it down again.
	var second := _sim("marsh", start, _json(first.export_recording()), "b")
	var ride := _ride(world, second, "p0", 0)
	world.present(second.snapshot(), true)
	_idle(second, boarded + 2, world, ride)
	_walk(second, [100, 100], world, ride)
	_idle(second, 60, world, ride)
	_check(str(second._players.p0.surface_id) == "lift-high", "The memory rode the lift up in the simulation: %s" % [second._players.p0])
	_riding(ride, "A memory riding the lift up is drawn on its deck every frame", true)
	ride = _ride(world, second, "p0", 0)
	_walk(second, [100, 260], world, ride)
	_idle(second, 60, world, ride)
	_check(str(second._players.p0.surface_id) == "lift-low", "Off the pan, the lift brought the memory down: %s" % [second._players.p0])
	_riding(ride, "A memory riding the lift down is drawn on its deck every frame", true)
	# The live pip rides too: the memory weighs the pan with the live pip aboard.
	var weigh := _sim("marsh", start)
	_idle(weigh, 90)
	_walk(weigh, [100, 100])
	_idle(weigh, 80)
	var aboard := _sim("marsh", start, _json(weigh.export_recording()), "b")
	world.present(aboard.snapshot(), true)
	ride = _ride(world, aboard, "p1", 0)
	_walk(aboard, [450, 200], world, ride)
	_idle(aboard, 140, world, ride)
	_check(str(aboard._players.p1.surface_id) == "lift-high", "The memory's weight took the live pip up: %s" % [aboard._players.p1])
	_riding(ride, "The live pip riding the lift is drawn on its deck the same way", true)
	# Off before the deck is up: the memory walks east onto the stilts a moment
	# after the lift starts up (as the simulation lets it), so it waits on the
	# deck, which hurries to the top.
	var leaves := _sim("marsh", start)
	_walk(leaves, [350, 200])
	_walk(leaves, [450, 200])
	_idle(leaves, 200 - int(leaves.tick))
	for step in range(30): leaves.step({"move_x": 1.0})
	_idle(leaves, 10)
	var early := {"p0": start.p0, "p1": {"x": 100, "z": 150, "surface_id": "landing", "height": 0}}
	var sends := _sim("marsh", early, _json(leaves.export_recording()), "b")
	world.present(sends.snapshot(), true)
	ride = _ride(world, sends, "p0", 0)
	_idle(sends, 194, world, ride)
	_walk(sends, [100, 100], world, ride)
	_idle(sends, 80, world, ride)
	_check(str(sends._players.p0.surface_id) == "stilts", "The memory walked off the lift onto the stilts: %s" % [sends._players.p0])
	_riding(ride, "A memory stepping off before the lift is up waits on it and never hops", true)
	# The raft: the memory waits on it, the live pip's pull carries it over the water.
	var shore := {"p0": {"x": 200, "z": 300, "surface_id": "landing", "height": 0}, "p1": {"x": 300, "z": 860, "surface_id": "isle", "height": 0}}
	var waits := _sim("marsh", shore)
	_walk(waits, [200, 440])
	_idle(waits, 10)
	var pulls := _sim("marsh", shore, _json(waits.export_recording()), "b")
	world.present(pulls.snapshot(), true)
	ride = _ride(world, pulls, "p0", 1)
	_idle(pulls, int(waits.tick), world, ride)
	_walk(pulls, [300, 885], world, ride)
	_tick(world, pulls, {"interact": true}, ride)
	_idle(pulls, 200, world, ride)
	_check(str(pulls._players.p0.surface_id) == "raft-south", "The live pip's pull carried the memory over in the simulation: %s" % [pulls._players.p0])
	_riding(ride, "A memory riding the raft is drawn on its deck every frame", false)
	world.queue_free()
	await process_frame

## Items ride the one way too: over a memory's head, and put down on the lift.
func _item_riders() -> void:
	var shown := ItemWitness.definition()
	var world := await _world("home", shown, ItemWitness.source())
	world.reduced_motion = false
	var start := Catalog.initial_checkpoint(shown)
	start.players.p1 = {"x": 300, "z": 300, "surface_id": "landing", "height": 0}
	# Turn 1: the first pip waits on the lift holding the pipsport.
	var first := _item_sim(shown, start)
	_walk(first, [450, 200])
	var boarded := int(first.tick)
	_idle(first, 10)
	var second := _item_sim(shown, start, _json(first.export_recording()))
	var ride := _ride(world, second, "p0", 0)
	var held := _ride(world, second, "p0", 0, "pipsport")
	var both := [ride, held]
	world.present(second.snapshot(), true)
	_idle(second, boarded + 2, world, both)
	_walk(second, [60, 60], world, both)
	_idle(second, 60, world, both)
	_check(str(second._players.p0.surface_id) == "lift-high" and str(second._mechanisms.items.pipsport.holder) == "p0", "The memory rode up holding the pipsport: %s" % [second._players.p0])
	_riding(ride, "A memory holding the pipsport rides the lift on its deck", true)
	_riding(held, "And the pipsport over its head rides with it", true)
	# Turn 1 again: the first pip puts the pipsport down on the lift and weighs the pan.
	var puts := _item_sim(shown, start)
	_walk(puts, [450, 200])
	_idle(puts, 1)
	puts.step({"interact": true})
	_walk(puts, [60, 60])
	_idle(puts, 60)
	_check(str(puts._mechanisms.items.pipsport.surface_id) == "lift-high", "Put down on the lift, it rode up in the simulation: %s" % [puts._mechanisms.items.pipsport])
	var watches := _item_sim(shown, start, _json(puts.export_recording()))
	world.present(watches.snapshot(), true)
	var resting := _ride(world, watches, "", 0, "pipsport")
	_idle(watches, int(puts.tick), world, resting)
	_riding(resting, "An item put down on the lift rides on its deck", true)
	world.queue_free()
	await process_frame

## What one ride watches: a pip (`slot`), or an item (`item`; over `slot`'s head
## while that pip holds it), on platform `index`.
func _ride(world: Node3D, sim: Simulation, slot: String, index: int, item: String = "") -> Dictionary:
	return {"world": world, "sim": sim, "slot": slot, "item": item, "index": index, "frames": 0, "between": 0, "worst": 0.0, "where": "", "step": 0.0}

## Steps `sim` one tick with `input`, shows its snapshot and draws the tick's
## two frames, measuring each ride in `rides` (one or a list) every frame.
func _tick(world: Node3D, sim: Simulation, input: Dictionary, rides: Variant) -> void:
	sim.step(input)
	world.present(sim.snapshot(), false)
	for frame in range(2):
		world._process(FRAME)
		for ride: Dictionary in (rides if rides is Array else [rides]): _measure(ride)

## One frame of a ride: while what it watches stands or rests on one of its
## platform's stops and the deck is on its way, how far it is drawn from where
## the deck carries it. An item held overhead must keep its place on the pip.
func _measure(ride: Dictionary) -> void:
	var world: Node3D = ride.world
	var sim: Simulation = ride.sim
	var entry: Dictionary = world.new_pieces._platforms[int(ride.index)]
	if not str(ride.slot).is_empty():
		var now: Vector3 = world.actors[ride.slot].position
		if ride.has("last"): ride.step = maxf(float(ride.step), absf(now.y - ride.last.y) if entry.lift else now.distance_to(ride.last))
		ride["last"] = now
	var item: String = ride.item
	var state: Dictionary = sim._players[ride.slot] if item.is_empty() else sim._mechanisms.items[item]
	var held: bool = not item.is_empty() and not str(ride.slot).is_empty() and str(state.get("holder", "")) == ride.slot
	if held: state = sim._players[ride.slot]
	var surface := str(state.get("surface_id", ""))
	var stop: int = entry.stops.find(surface)
	if stop < 0:
		# Stepped off while the deck is on its way: drawn waiting on the deck.
		var root: Node3D = entry.piece.root
		if item.is_empty() and entry.lift and ride.has("aboard") and _count_frame(ride, entry, root, Vector3.ZERO):
			# On the deck's height, and still over the deck (never in the floor's edge).
			var at: Vector3 = world.actors[ride.slot].position
			var gap := maxf(absf(at.y - root.position.y), maxf(absf(at.x - root.position.x), absf(at.z - root.position.z)) - 0.5)
			if gap > ride.worst:
				ride.worst = gap
				ride.where = "tick %d: stepped off, drawn %.3f m from the deck" % [sim.tick, gap]
		return
	ride["aboard"] = true
	var deck: Node3D = entry.piece.root
	var bridge: Dictionary = {}
	for each: Dictionary in world.chapter_definition.bridges:
		if str(each.id) == surface: bridge = each
	var rect: Array = bridge.rect_cm
	var anchor := Vector3(float(rect[0] + rect[2]) / 200.0, float(bridge.height_cm) / 100.0, float(rect[1] + rect[3]) / 200.0)
	var expected := Vector3(float(state.x), float(state.height), float(state.z)) / 100.0 + deck.position - anchor
	var drawn: Vector3 = world.actors[ride.slot].position if item.is_empty() or held else world._item_pieces[item].root.position
	if held:
		# Measured while the deck is on its way: its middle stays on the pip's
		# carry point, which bobs with the walk as the seed does.
		if not _count_frame(ride, entry, deck, anchor): return
		var piece: RefCounted = world._item_pieces[item]
		var slip: float = (piece.root.position + piece.root.basis * piece.middle).distance_to(world.actors[ride.slot].carry_point())
		if slip > ride.worst:
			ride.worst = slip
			ride.where = "tick %d: the item slipped %.3f m off the pip's head" % [sim.tick, slip]
		return
	# Its own walk on and off the deck eases; the ride itself must not.
	if not _count_frame(ride, entry, deck, anchor): return
	# On a lift a pip may walk across the deck as it goes (its walk eases): its height is the ride.
	var off: float = absf(drawn.y - expected.y) if entry.lift else (drawn - expected).length()
	if off > ride.worst:
		ride.worst = off
		ride.where = "tick %d: drawn %s, deck %s, expected %s" % [sim.tick, drawn, deck.position, expected]

## Counts a frame of a ride, and whether its deck was on its way then (returned).
static func _count_frame(ride: Dictionary, entry: Dictionary, deck: Node3D, anchor: Vector3) -> bool:
	ride.frames += 1
	var lowest: float = entry.heights.min()
	var highest: float = entry.heights.max()
	var between: bool = deck.position.y > lowest + 0.01 and deck.position.y < highest - 0.01 if entry.lift else deck.position.distance_to(anchor) > 0.01
	if between: ride.between += 1
	return between

## A finished ride: its deck was on its way for some frames, and every frame
## drew what it watched on the deck.
func _riding(ride: Dictionary, label: String, lift: bool) -> void:
	_check(int(ride.between) >= (20 if lift else 10) and float(ride.worst) <= ON_DECK and float(ride.step) <= float(STEP[lift]), "%s (%d frames on its way, worst %.3f m, biggest step %.3f m; %s)" % [label, ride.between, ride.worst, ride.step, ride.where])

## Walks the live pip to `to`, x first then z; with a world, each tick drawn.
func _walk(sim: Simulation, to: Array, world: Node3D = null, rides: Variant = []) -> void:
	for axis in range(2):
		var key := "x" if axis == 0 else "z"
		for tick in range(300):
			var gap := int(to[axis]) - int(sim._players[sim.active_slot][key])
			if absi(gap) <= 1 or sim.finished: break
			var before := int(sim._players[sim.active_slot][key])
			var input := {"move_x": 0.0, "move_z": 0.0}
			input["move_" + key] = clampf(float(gap) / 8.0, -1.0, 1.0)
			if world != null: _tick(world, sim, input, rides)
			else: sim.step(input)
			if int(sim._players[sim.active_slot][key]) == before and tick > 3: break

func _idle(sim: Simulation, ticks: int, world: Node3D = null, rides: Variant = []) -> void:
	for tick in range(ticks):
		if sim.finished: return
		if world != null: _tick(world, sim, {}, rides)
		else: sim.step({})

static func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _item_sim(shown: Dictionary, checkpoint: Dictionary, prior: Dictionary = {}) -> Simulation:
	var sim := Simulation.new()
	sim.simulation_version = int(shown.simulation_version)
	sim._reset_trusted(shown, "home", checkpoint, prior, "a" if prior.is_empty() else "b")
	return sim

func _shown_near(fog: RefCounted, at: Vector2) -> int:
	return fog.shown().filter(func(puff: Vector3) -> bool: return Vector2(puff.x, puff.z).distance_to(at) < Fog.CLEAR - 0.1).size()

func _sim(stage_id: String, players: Dictionary, prior: Dictionary = {}, role: String = "a") -> Simulation:
	var checkpoint := Catalog.initial_checkpoint(level)
	checkpoint.next_stage_id = stage_id
	for slot: String in players: checkpoint.players[slot] = players[slot]
	var sim := Simulation.new()
	sim.simulation_version = 16
	sim._reset_trusted(level, stage_id, checkpoint, prior, role)
	return sim

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
		print("FAIL: " + label)
