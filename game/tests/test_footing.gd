extends SceneTree
## A pip keeps its footing (core/physical/runtime.gd _keep_footing) on Relay
## Isles @3's west bridge, held while anyone stands on a plate, played
## through the journey engine on its open turns rules:
## - a pip at the bridge's edge as it shuts, its centre over the bank or its
##   walk radius touching it, steps back onto the bank and walks on, the live
##   pip and the friend's replay alike;
## - a pip in the middle of the bridge falls into the sky: the drowned record
##   with "fell" and "sky", the turn ends unsaved, the live pip's or the friend's;
## - the same bridge in a water chapter drowns it instead;
## - a turn with a step back plays again from its record exactly;
## - the water chapters are the ones whose descriptors name water;
## - every open turns level gives a crossing the one closing grace, off the
##   tide rules too, and shows it closing in the snapshot;
## - in every open turns journey chapter, a pip that steps off a pad never
##   reaches the far side of the crossing that pad holds before the grace runs
##   out (a walk on the real floors, every crossing open, stepping back
##   included), so the grace lets no pip cross alone.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Relay = preload("res://core/journey/relay_isles_v3_catalog.gd")
const Runtime = preload("res://core/physical/runtime.gd")
const MemoryTrace = preload("res://core/physical/memory_trace.gd")
const ChapterIndex = preload("res://content/chapters/index.gd")
const TideV3 = preload("res://core/journey/turn_of_the_tide_v3_catalog.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const Navigation = preload("res://core/cooperative/navigation.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
## The west bridge runs from x -260 (the shore's edge) to -140; the shore's
## plate is at (-500, -60).
const EDGE := -260
const PLATE := [-500, -60]
var checks := 0
var failures := 0
var level: Dictionary

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	MemoryTrace.enabled = false
	level = Relay.definition()
	_live_steps_back()
	_replay_steps_back()
	_falls_into_the_sky()
	_drowns_over_water()
	_water_chapters()
	_grace()
	_lone_crossings()
	print("FOOTING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Turn one: p0 stands on the plate a while, then walks away; turn two: p1
## stands where `at` says until the bridge has shut, then walks back west.
func _live_steps_back() -> void:
	for spot: Array in [[EDGE - 6, "centre over the bank"], [EDGE + 8, "centre on the bridge, its walk radius on the bank"]]:
		var first := _plate_then_leave(level, 100)
		var b := _turn_two(level, first)
		_to_bridge(b, int(spot[0]))
		_check(int(b._players.p1.x) == int(spot[0]) and bool(b._routes["west-relay"]), "p1 stands at %d with the bridge held (%s): %s" % [spot[0], spot[1], b._players.p1])
		_idle_until_shut(b)
		var stood: Dictionary = b._players.p1
		_check("stepped_back:p1" in b._events and not b.finished and b._drowned.is_empty() and stood.surface_id == "west" and int(stood.x) <= EDGE - Runtime.PLAYER_RADIUS, "Its floor gone, the pip steps back onto the shore (%s): %s" % [spot[1], stood])
		_check(int(stood.x) >= EDGE - Runtime.PLAYER_RADIUS - 1, "Onto the nearest spot it may stand: %s" % [stood])
		_walk(b, [-400, 0])
		_check(int(b._players.p1.x) == -400, "And walks on from there: %s" % [b._players.p1])

## Turn one: p0 walks to the bridge's edge while p1 holds the plate, waits,
## then walks back west; turn two: p1 steps off the plate, and the replayed p0
## steps back onto the shore as the bridge shuts and walks on as it did.
func _replay_steps_back() -> void:
	var a := _turn_one(level, {"p1": _at(PLATE[0], PLATE[1])})
	_to_bridge(a, EDGE - 6)
	_idle(a, 140)
	_walk(a, [-450, 0])
	var first := a.export_recording()
	var b := _turn_two(level, first)
	_idle(b, 60)
	_check(int(b._players.p0.x) == EDGE - 6, "The replay waits at the bridge's edge: %s" % [b._players.p0])
	_walk(b, [-500, 150])
	_idle_until_shut(b)
	_check("stepped_back:p0" in b._events and not b.finished and b._players.p0.surface_id == "west" and int(b._players.p0.x) <= EDGE - Runtime.PLAYER_RADIUS, "The friend's replay steps back onto the shore as the bridge shuts: %s" % [b._players.p0])
	_idle(b, 120)
	_check(int(b._players.p0.x) < -400 and b._drowned.is_empty(), "And walks on by its own inputs: %s" % [b._players.p0])
	var second := b.export_recording()
	var again := _turn_two(level, first)
	for input: Dictionary in Simulation.expand_recording_inputs(second): again.step(input)
	_check(again.state_hash() == str(second.final_state_hash) and again._players == b._players, "Played again from its record, the turn ends exactly as it did")

func _falls_into_the_sky() -> void:
	var first := _plate_then_leave(level, 100)
	var b := _turn_two(level, first)
	_to_bridge(b, -200)
	_idle_until_shut(b)
	_check(b.finished and b._drowned == {"slot": "p1", "route": "west-relay", "tick": b._drowned.get("tick"), "fell": true, "sky": true}, "A pip in the middle of the bridge falls into the sky: %s" % [b._drowned])
	_check("fell:p1" in b._events and b.commit_reason() == Runtime.FELL_YOU and not b.can_commit() and not b.can_pass() and not b.keeps_draft(), "The turn ends there, says so and keeps nothing")
	_check(b.snapshot().drowned.get("sky", false), "The snapshot shows the fall")
	# The friend's replay on the bridge as it shuts falls the same way.
	var a := _turn_one(level, {"p1": _at(PLATE[0], PLATE[1])})
	_to_bridge(a, -200)
	_idle(a, 200)
	var b2 := _turn_two(level, a.export_recording())
	_idle(b2, 60)
	_walk(b2, [-500, 150])
	_idle_until_shut(b2)
	_check(b2.finished and b2._drowned.get("slot") == "p0" and b2._drowned.has("sky") and b2.commit_reason() == Runtime.FELL_FRIEND, "The friend's replay falls too: %s" % [b2._drowned])

func _drowns_over_water() -> void:
	var wet := level.duplicate(true)
	wet.id = "fog-marsh"
	var first := _plate_then_leave(wet, 100)
	var b := _turn_two(wet, first)
	_to_bridge(b, -200)
	_idle_until_shut(b)
	_check(b.finished and b._drowned.get("slot") == "p1" and not b._drowned.has("fell") and b.commit_reason() == Runtime.DROWNED_YOU and "drowned:p1" in b._events, "Over water the same pip drowns: %s" % [b._drowned])
	var edge := _turn_two(wet, _plate_then_leave(wet, 100))
	_to_bridge(edge, EDGE + 8)
	_idle_until_shut(edge)
	_check(not edge.finished and edge._players.p1.surface_id == "west", "And at the edge it steps back there too: %s" % [edge._players.p1])

## Every chapter whose descriptor names water is a water chapter, and every
## water chapter has a version that does.
func _water_chapters() -> void:
	var wet: Dictionary = {}
	for key: String in ChapterIndex.keys():
		var id := key.get_slice("@", 0)
		if not str(ChapterIndex.data(key).get("water", "")).is_empty():
			wet[id] = true
			_check(id in Runtime.WATER_CHAPTERS, "%s has water, so a pip whose floor goes drowns there" % key)
	for id: String in Runtime.WATER_CHAPTERS: _check(wet.has(id), "%s names water in a descriptor" % id)

func _grace() -> void:
	_check(int(TideV3.definition().closing_ticks) == Runtime.CLOSING_GRACE_TICKS and Runtime.CLOSING_GRACE_TICKS == 25, "Turn of the Tide @3 closes with the shared grace, 25 ticks")
	for version: int in [int(level.simulation_version), OpenControls.OPEN_TURNS_RULES_VERSION]:
		var plain := level.duplicate(true)
		plain.simulation_version = version
		plain.erase("closing_ticks")
		var a := _turn_one(plain, {"p0": _at(PLATE[0], PLATE[1])})
		_idle(a, 5)
		var began := -1
		var shut := -1
		var shown := false
		for tick in range(80):
			a.step({"move_x": -1.0, "move_z": 0.0})
			if "closing:west-relay" in a._events: began = a.tick
			if began >= 0 and a.snapshot().route_progress.get("closing", {}).has("west-relay"): shown = true
			if not bool(a._routes["west-relay"]):
				shut = a.tick
				break
		_check(began > 0 and shut - began == Runtime.CLOSING_GRACE_TICKS and shown, "Rules %d: the bridge keeps its floor for the grace once its plate is let go, shown closing (%d to %d)" % [version, began, shut])

func _lone_crossings() -> void:
	var seen := 0
	for key: String in Registry.keys():
		if not Registry.is_journey(key): continue
		var definition := Registry.definition(key)
		if not OpenTurns.pinned(definition): continue
		var cells := Navigation.index_for(definition, Canonical.digest(definition))
		var routes: Dictionary = {}
		var crossings: Dictionary = {}
		for route: Dictionary in definition.get("bridges", []) + definition.get("stairs", []):
			routes[route.id] = true
			crossings[route.id] = route
		for stage: Dictionary in definition.stages:
			var pads: Dictionary = {}
			for pad: Dictionary in stage.get("pressure_pads", []): pads[pad.id] = pad
			for gate: Dictionary in stage.get("gates", []):
				if not crossings.has(gate.route_id): continue
				var route: Dictionary = crossings[gate.route_id]
				var side := [str(route.get("from_surface", "")), str(route.get("to_surface", ""))]
				for id: String in _pads_in(gate.get("when", {}), []):
					if not pads.has(id): continue
					var pad: Dictionary = pads[id]
					# The pad lets go the tick its pip's centre passes its radius;
					# the crossing shuts the grace after; a pip whose centre is then
					# within its walk radius of the far floor steps back onto it.
					var leave := int(pad.radius_cm) / Runtime.MOVE_PER_TICK + 1
					var reach := Runtime.MOVE_PER_TICK * (leave + Runtime.CLOSING_GRACE_TICKS) + Runtime.PLAYER_RADIUS
					var slot := str(route.get("owner_slot", "p0"))
					# A pad on its own step beside the crossing: the far side is the one
					# its pip reaches last.
					var walked := -2
					var far := ""
					for end: String in side:
						if end == str(pad.surface_id) or end.is_empty(): continue
						var to := _walk_cm(definition, cells, routes, pad, end, slot, reach + LONE_MARGIN_CM)
						if to < 0 or (walked != -1 and to > walked):
							walked = to
							far = end
					seen += 1
					print("LONE %s %s %s over %s to %s: %s cm, needs over %d" % [key, stage.id, id, gate.route_id, far, "far" if walked < 0 else str(walked), reach])
					# The grid walk is up to 3% longer than the real one.
					_check(walked < 0 or walked * 100 > reach * 103, "%s %s: a pip stepping off %s reaches %s over %s (%d cm) before the grace runs out (%d cm)" % [key, stage.id, id, far, gate.route_id, walked, reach])
	_check(seen > 5, "The probe saw the chapters' held crossings (%d)" % seen)

## How far past what the grace allows the probe looks, to print the margins.
const LONE_MARGIN_CM := 80

## The pad ids a gate's condition names, anywhere in it.
static func _pads_in(when: Variant, found: Array) -> Array:
	if when is Dictionary:
		if when.has("pad_id"): found.append(str(when.pad_id))
		for value: Variant in when.values(): _pads_in(value, found)
	elif when is Array:
		for value: Variant in when: _pads_in(value, found)
	return found

## The shortest walk (cm) a pip of `slot` from `pad`'s middle takes to stand on
## floor `far`, over the real floors with every crossing open, or -1 past
## `most`: Dijkstra on an 8 cm grid, sixteen ways round (the grid's error under 3%).
static func _walk_cm(definition: Dictionary, cells: Dictionary, routes: Dictionary, pad: Dictionary, far: String, slot: String, most: int) -> int:
	var moves := [[Vector2i(8, 0), 800], [Vector2i(-8, 0), 800], [Vector2i(0, 8), 800], [Vector2i(0, -8), 800],
		[Vector2i(8, 8), 1131], [Vector2i(-8, 8), 1131], [Vector2i(8, -8), 1131], [Vector2i(-8, -8), 1131],
		[Vector2i(16, 8), 1789], [Vector2i(-16, 8), 1789], [Vector2i(16, -8), 1789], [Vector2i(-16, -8), 1789],
		[Vector2i(8, 16), 1789], [Vector2i(-8, 16), 1789], [Vector2i(8, -16), 1789], [Vector2i(-8, -16), 1789]]
	var start := {"x": int(pad.position_cm[0]), "z": int(pad.position_cm[1]), "height": int(pad.get("height_cm", 0)), "surface_id": str(pad.surface_id)}
	var best := {_key(start): 0}
	var heap: Array = [[0, start]]
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var cost: int = top[0]
		var at: Dictionary = top[1]
		if cost > best.get(_key(at), cost): continue
		if str(at.surface_id) == far: return cost / 100
		for move: Array in moves:
			var next: int = cost + int(move[1])
			if next > most * 100: continue
			var step: Vector2i = move[0]
			var moved := Navigation.at(definition, routes, {}, at, int(at.x) + step.x, int(at.z) + step.y, slot, Runtime.PLAYER_RADIUS, true, cells)
			if moved.is_empty() or next >= int(best.get(_key(moved), next + 1)): continue
			best[_key(moved)] = next
			_push(heap, [next, moved])
	return -1

static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if int(heap[parent][0]) <= int(item[0]): break
		heap[index] = heap[parent]
		index = parent
	heap[index] = item

static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty(): return top
	var index := 0
	while true:
		var child := index * 2 + 1
		if child >= heap.size(): break
		if child + 1 < heap.size() and int(heap[child + 1][0]) < int(heap[child][0]): child += 1
		if int(heap[child][0]) >= int(last[0]): break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return top

static func _key(at: Dictionary) -> int:
	return (int(at.x) + 50000) * 100000 + (int(at.z) + 50000) + int(at.height) * 10000000000

## A first turn where p0 holds the plate `ticks` ticks, then walks off it.
func _plate_then_leave(definition: Dictionary, ticks: int) -> Dictionary:
	var a := _turn_one(definition, {"p0": _at(PLATE[0], PLATE[1]), "p1": _at(-400, 150)})
	_idle(a, ticks)
	_walk(a, [-600, 150])
	_idle(a, 60)
	return a.export_recording()

func _turn_one(definition: Dictionary, players: Dictionary) -> Simulation:
	var checkpoint := _checkpoint(definition, players)
	var sim := Simulation.new()
	sim.simulation_version = int(definition.simulation_version)
	sim._reset_trusted(definition, "relay", checkpoint, {}, "a")
	return sim

func _turn_two(definition: Dictionary, first: Dictionary) -> Simulation:
	var sim := Simulation.new()
	sim.simulation_version = int(definition.simulation_version)
	sim._reset_trusted(definition, "relay", _last_checkpoint, first, "b")
	return sim

var _last_checkpoint: Dictionary = {}

func _checkpoint(definition: Dictionary, players: Dictionary) -> Dictionary:
	var checkpoint := Catalog.initial_checkpoint(definition)
	for slot: String in players: checkpoint.players[slot] = players[slot]
	checkpoint.checkpoint_hash = Catalog.checkpoint_hash(checkpoint)
	_last_checkpoint = checkpoint
	return checkpoint

func _idle_until_shut(sim: Simulation) -> void:
	for tick in range(400):
		if sim.finished or not bool(sim._routes["west-relay"]): break
		sim.step({})

## Over the shore to the bridge's line, then along it to `x`.
static func _to_bridge(sim: Simulation, x: int) -> void:
	_walk(sim, [-300, 0])
	_walk(sim, [x, 0])

static func _at(x: int, z: int) -> Dictionary:
	return {"x": x, "z": z, "surface_id": "west", "height": 0}

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

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
		print("FAIL: " + label)
