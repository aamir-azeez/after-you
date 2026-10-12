extends SceneTree
## turn-of-the-tide@1 graph witnesses (spec 11.2, 11.3, 11.5): the contact
## graph built from the real Navigation against the intended link set, marker
## and spout geometry, and B strands at every tick of seven real stage-1 A
## timelines. Stage-2 strands, traps and press guarantees:
## test_turn_of_the_tide_presses. See turn_of_the_tide_graph.gd for the model.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Navigation = preload("res://core/cooperative/navigation.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const Witness = preload("res://tests/turn_of_the_tide_witness.gd")
const Graph = preload("res://tests/turn_of_the_tide_graph.gd")
## Spec 2.2 [port] (V1): 54 p0 edges and 45 p1 edges.
const PORT_EDGES := {"p0": 54, "p1": 45}
const STAGE_TWO_ONLY := ["towpath", "boom-jetty", "sea-gate-in", "sea-gate-out", "punt-ferry", "mole-steps", "mole-slip", "race-stage", "boom-catwalk", "gate-catwalk", "punt-catwalk", "boom-post", "gate-post", "punt-post"]
var checks := 0
var failures := 0
var mismatches: Array[String] = []
var level: Dictionary = {}
var initial: Dictionary = {}
var graph: RefCounted

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var started := Time.get_ticks_msec()
	level = Catalog.definition(Witness.KEY)
	initial = Catalog.initial_checkpoint(level)
	graph = Graph.new(level)
	_contacts()
	print("TIDE reach: contacts %d ms" % (Time.get_ticks_msec() - started))
	_markers()
	_spout()
	_stage_lists()
	print("TIDE reach: geometry %d ms" % (Time.get_ticks_msec() - started))
	_stage_one_strands()
	print("TIDE reach: stage one %d ms" % (Time.get_ticks_msec() - started))
	for line: String in mismatches: print("PORT MISMATCH " + line)
	print("TURN OF THE TIDE REACH: %d checks, %d failures, %d port mismatches" % [checks, failures, mismatches.size()])
	quit(1 if failures else 0)

## 11.2-1: the contact graph equals the intended link set; the only stack is
## the aqueduct span over the east beach.
func _contacts() -> void:
	for slot: String in ["p0", "p1"]:
		var found: Dictionary = graph.build(slot)
		var undirected: Dictionary = graph.undirected(slot)
		var intended: Dictionary = graph.intended(slot)
		var extra: Array = []
		var missing: Array = []
		for key: String in undirected:
			if not intended.has(key): extra.append(key)
		for key: String in intended:
			if not undirected.has(key): missing.append(key)
		_check(extra.is_empty() and missing.is_empty(), "%s contact graph is exactly the intended link set (extra %s, missing %s)" % [slot, str(extra), str(missing)])
		var one_way: Array = []
		for key: String in found:
			var ends := key.split(">")
			if str(found[key][1]).is_empty() and not found.has(ends[1] + ">" + ends[0]): one_way.append(key)
		_check(one_way.is_empty(), "%s: every walking contact works both ways (%s)" % [slot, str(one_way)])
		var drops: Array = []
		for key: String in found:
			if not str(found[key][1]).is_empty(): drops.append(key)
		_check(drops == (["aq-span>e-beach"] if slot == "p1" else []), "%s drops: %s" % [slot, str(drops)])
		var wide: Dictionary = graph.build(slot, true)
		_check(wide.keys().size() == found.keys().size(), "%s: opening every other route adds no contact (%d vs %d)" % [slot, wide.size(), found.size()])
		var count := undirected.size() + drops.size()
		print("PORT %s edges native=%d port=%d (walking %d, drops %d)" % [slot, count, PORT_EDGES[slot], undirected.size(), drops.size()])
		if count != PORT_EDGES[slot]: mismatches.append("%s edges: native %d, port %d" % [slot, count, PORT_EDGES[slot]])
	_check(graph.undirected("p0").size() == PORT_EDGES.p0, "p0 has the port's 54 walking edges and no drop")
	var stacks: Array = []
	var all: Array = level.islands + level.bridges + level.stairs
	for i in range(all.size()):
		for j in range(i + 1, all.size()):
			var a: Dictionary = all[i]
			var b: Dictionary = all[j]
			if not _overlap(a.rect_cm, b.rect_cm): continue
			if _heights(a).max() + 2 < _heights(b).min() or _heights(b).max() + 2 < _heights(a).min(): stacks.append([a.id, b.id])
	_check(stacks == [["aq-span", "e-beach"]], "The only stack is aq-span over e-beach (%s)" % str(stacks))

## 11.2-2 and -3: every marker stands on its own surface at its height; pads
## and levers on stubs cannot be reached while their stub is shut.
func _markers() -> void:
	var all_open: Dictionary = {}
	for id: String in graph.route_bit: all_open[id] = true
	for stage: Dictionary in level.stages:
		for marker: Dictionary in stage.controls + stage.levers + stage.pressure_pads + [stage.goal]:
			var x := int(marker.position_cm[0])
			var z := int(marker.position_cm[1])
			var at := Navigation.at(level, all_open, {}, {"height": int(marker.height_cm), "surface_id": marker.surface_id}, x, z, marker.owner_slot, Simulation.PLAYER_RADIUS)
			_check(not at.is_empty() and at.surface_id == marker.surface_id and int(at.height) == int(marker.height_cm), "%s %s stands on %s at %d cm" % [stage.id, marker.id, marker.surface_id, int(marker.height_cm)])
			if graph.route_bit.has(marker.surface_id):
				var shut := all_open.duplicate()
				shut[marker.surface_id] = false
				_check(not _reachable_in_radius(marker, shut), "%s %s cannot be reached while %s is shut" % [stage.id, marker.id, marker.surface_id])

func _reachable_in_radius(marker: Dictionary, routes: Dictionary) -> bool:
	var r := int(marker.radius_cm)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if dx * dx + dz * dz > r * r: continue
			for height: int in [0, 48, 96]:
				var at := Navigation.at(level, routes, {}, {"height": height, "surface_id": ""}, int(marker.position_cm[0]) + dx, int(marker.position_cm[1]) + dz, marker.owner_slot, Simulation.PLAYER_RADIUS)
				if not at.is_empty() and at.surface_id == marker.surface_id: return true
	return false

## 11.2-4: the spout lands from every centre in its rect and from a west
## entry; spout-lip stops p0 at x=540.
func _spout() -> void:
	var drop: Dictionary = level.drops[0]
	var routes: Dictionary = {}
	var landed := 0
	var total := 0
	for x in range(int(drop.rect_cm[0]), int(drop.rect_cm[2]) + 1):
		for z in range(int(drop.rect_cm[1]), int(drop.rect_cm[3]) + 1):
			total += 1
			var at := Navigation.at(level, routes, {"sluice": true}, {"height": 48, "surface_id": "aq-span"}, x, z, "p1", 12)
			if not at.is_empty() and at.surface_id == "e-beach" and int(at.height) == 0: landed += 1
	_check(total == 2009 and landed == total, "The spout lands all %d of %d centres (port 2009/2009)" % [landed, total])
	var walker := {"x": 588, "z": 288, "height": 48, "surface_id": "aq-span"}
	var landing_x := -1
	for x in range(589, 610):
		walker = Navigation.at(level, routes, {"sluice": true}, walker, x, 288, "p1", 12)
		if walker.is_empty(): break
		if walker.surface_id == "e-beach":
			landing_x = x
			break
	_check(landing_x == 600, "Walking in from the west lands at x=600 (got %d)" % landing_x)
	var p0 := {"x": 500, "z": 288, "height": 48, "surface_id": "aq-span"}
	var last := 500
	for x in range(501, 620):
		var next := Navigation.at(level, routes, {"sluice": true}, p0, x, 288, "p0", 12)
		if next.is_empty(): break
		p0 = next
		last = x
	_check(last == 540, "spout-lip stops p0 at x=540 (got %d)" % last)

## 11.2-5: stage-2 routes are absent from stage one; the lock gates latch only in stage two.
func _stage_lists() -> void:
	var listed: Array = []
	for gate: Dictionary in level.stages[0].gates: listed.append(gate.route_id)
	for id: String in STAGE_TWO_ONLY:
		_check(id not in listed and id not in level.stages[0].entry_latch_routes, id + " is absent from stage one")
	for id: String in ["lock-west", "lock-east"]:
		_check(id not in level.stages[0].entry_latch_routes and id in level.stages[1].entry_latch_routes, id + " is entry-latched only in stage two")
	for id: String in ["slipway", "stones-3", "jetty-3", "quay-step", "wheel-step", "bollard-step"]:
		var relisted := false
		for gate: Dictionary in level.stages[1].gates: relisted = relisted or gate.route_id == id
		_check(not relisted, id + " is open in stage two only if stage one kept it")

## 11.3 and 3.7: no B strand at any tick of seven real A timelines; and A,
## alone in its own world, can always still reach each of its three steps.
func _stage_one_strands() -> void:
	var total := 0
	for name: String in ["low", "low-half-first", "half", "half-via-high", "half-winch", "high", "high-sluice"]:
		var a := Witness.source(level, Witness.SET, initial, Witness.a_routes()[name], 0, Callable(), true)
		_check(a.can_commit(), name + ": the A timeline commits")
		if not a.can_commit(): continue
		var phases := _phases(Witness.SET, initial, a.export_recording())
		var explorer: RefCounted = Graph.Explorer.new(graph, level, Witness.SET, "p1", initial)
		var reached := _reach(explorer, int(graph.index["w-beach"]), phases)
		var good: Dictionary = explorer.good(reached, [explorer.goal])
		var strands := 0
		for state: int in reached:
			if not good.has(state): strands += 1
		total += reached.size()
		_check(strands == 0, "%s: no B strand over %d states and %d phases of %d ticks (%d stranded)" % [name, reached.size(), phases.size(), a.tick + 1, strands])
	print("PORT stage 1 B states native=%d port=15304" % total)
	_check(total == 15304, "Seven A timelines give the port's 15,304 B states (got %d)" % total)
	var explorer: RefCounted = Graph.Explorer.new(graph, level, Witness.SET, "p0", initial)
	explorer.set_phase({"controls": {}, "levers": {}, "players": {}})
	var start: int = Graph.Explorer.key(int(graph.index["w-beach"]), explorer.combo_of(initial.mechanisms), 0)
	var reached: Dictionary = explorer.closure({start: true})
	for step: String in ["wheel-step", "quay-step", "bollard-step"]:
		var good: Dictionary = explorer.good(reached, [int(graph.index[step])])
		_check(good.size() == reached.size(), "A can always still reach %s (%d of %d states)" % [step, good.size(), reached.size()])

## The other player's values at every tick of a recording, as the explorer's
## world sees them; consecutive identical ticks merge into one phase.
func _phases(stage_id: String, checkpoint: Dictionary, first: Dictionary) -> Array:
	var sim := Simulation.new()
	sim.simulation_version = Witness.RULES
	sim._reset_trusted(level, stage_id, checkpoint, first, "b")
	var source: String = sim.first_player_slot
	var result: Array = []
	var last := ""
	for tick in range(int(first.duration_ticks) + 1):
		var phase := {"controls": {}, "levers": {}, "players": {}}
		for control: Dictionary in sim.stage.controls:
			if control.owner_slot == source: phase.controls[control.id] = str(sim._mechanisms.controls[control.id])
		for lever: Dictionary in sim.stage.levers:
			if lever.owner_slot == source: phase.levers[lever.id] = bool(sim._mechanisms.levers.get(lever.id, false))
		for pad: Dictionary in sim.stage.pressure_pads:
			if pad.owner_slot == source and Seven.near(sim._players[source], pad):
				phase.players[source] = {"x": pad.position_cm[0], "z": pad.position_cm[1], "height": int(pad.height_cm), "surface_id": pad.surface_id}
		var key := JSON.stringify(phase)
		if key != last: result.append(phase)
		last = key
		if tick < int(first.duration_ticks): sim.step({})
	return result

func _reach(explorer: RefCounted, surface: int, phases: Array) -> Dictionary:
	explorer.set_phase(phases[0])
	var start: int = Graph.Explorer.key(surface, explorer.combo_of(explorer.base_mechanisms), 0)
	var reached: Dictionary = {start: true}
	for phase: Dictionary in phases:
		explorer.set_phase(phase)
		reached = explorer.closure(reached)
	return reached

func _overlap(a: Array, b: Array) -> bool:
	return int(a[0]) < int(b[2]) and int(b[0]) < int(a[2]) and int(a[1]) < int(b[3]) and int(b[1]) < int(a[3])

func _heights(item: Dictionary) -> Array:
	if item.has("axis"): return [int(item.from_height_cm), int(item.to_height_cm)]
	return [int(item.height_cm), int(item.height_cm)]

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
