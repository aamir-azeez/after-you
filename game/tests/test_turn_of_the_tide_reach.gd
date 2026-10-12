extends SceneTree
## turn-of-the-tide@1 graph witnesses: the contact
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
## An independent axis-walk model counts the contacts reachable from each
## slot's start: 54 for p0 and 46 for p1. Natively p1 has 50, because the graph
## here also probes the four mole stair contacts, which p1 can never reach: the
## mole is reached only over p0's own crossings.
const MODEL_EDGES := {"p0": 54, "p1": 46}
const P1_UNREACHABLE := ["mole-beach|mole-slip", "mole-quay|mole-steps", "mole-slip|mole-terrace", "mole-steps|mole-terrace"]
const P1_EDGES := 50
const STAGE_TWO_ONLY := ["towpath", "boom-jetty", "sea-gate-in", "sea-gate-out", "punt-ferry", "mole-steps", "mole-slip", "race-stage", "bar-catwalk", "beach-catwalk", "quay-catwalk", "gate-catwalk", "boom-post", "gate-post", "punt-post"]
var checks := 0
var failures := 0
var mismatches: Array[String] = []
var level: Dictionary = {}
var initial: Dictionary = {}
var graph: RefCounted
var p1_mole_surfaces: Array = []

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
	for line: String in mismatches: print("MODEL MISMATCH " + line)
	print("TURN OF THE TIDE REACH: %d checks, %d failures, %d model mismatches" % [checks, failures, mismatches.size()])
	quit(1 if failures else 0)

## The contact graph equals the intended link set; the only stack is
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
		var reachable := count - (P1_UNREACHABLE.size() if slot == "p1" else 0)
		print("MODEL %s edges native=%d reachable=%d model=%d (walking %d, drops %d)" % [slot, count, reachable, MODEL_EDGES[slot], undirected.size(), drops.size()])
		if reachable != MODEL_EDGES[slot]: mismatches.append("%s reachable edges: native %d, model %d" % [slot, reachable, MODEL_EDGES[slot]])
	_check(graph.undirected("p0").size() == MODEL_EDGES.p0, "p0 has the model's 54 walking edges and no drop")
	_p1_unreachable()
	var stacks: Array = []
	var all: Array = level.islands + level.bridges + level.stairs
	for i in range(all.size()):
		for j in range(i + 1, all.size()):
			var a: Dictionary = all[i]
			var b: Dictionary = all[j]
			if not _overlap(a.rect_cm, b.rect_cm): continue
			if _heights(a).max() + 2 < _heights(b).min() or _heights(b).max() + 2 < _heights(a).min(): stacks.append([a.id, b.id])
	_check(stacks == [["aq-span", "e-beach"]], "The only stack is aq-span over e-beach (%s)" % str(stacks))

## p1's four extra contacts are the mole stairs. Even with every route open
## they lie outside p1's component from either of its starts, and the
## explorer's closures in both stages never stand on them; the rest is the
## model's 46.
func _p1_unreachable() -> void:
	var undirected: Dictionary = graph.undirected("p1")
	var drops := 0
	for key: String in graph.pairs.p1:
		if not str(graph.pairs.p1[key][1]).is_empty(): drops += 1
	_check(undirected.size() + drops == P1_EDGES, "p1 has exactly %d contacts (got %d)" % [P1_EDGES, undirected.size() + drops])
	var component := {}
	var queue: Array = [int(graph.index["r-terrace"]), int(graph.index["w-beach"])]
	for start: int in queue: component[start] = true
	var head := 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		for edge: Array in graph.edges.p1[at]:
			if not component.has(int(edge[0])):
				component[int(edge[0])] = true
				queue.append(int(edge[0]))
	var outside: Array = []
	for key: String in undirected:
		var ends := key.split("|")
		if not component.has(int(graph.index[ends[0]])) or not component.has(int(graph.index[ends[1]])): outside.append(key)
	outside.sort()
	_check(outside == P1_UNREACHABLE, "With every route open, p1's only contacts outside its reach are the mole stairs (%s)" % str(outside))
	var mole: Array = []
	for key: String in P1_UNREACHABLE:
		for id: String in key.split("|"):
			if int(graph.index[id]) not in mole: mole.append(int(graph.index[id]))
	# Stage two, from the bell, with every stage-one route kept, at each tide.
	for tide: String in ["low", "half", "high"]:
		var start := initial.duplicate(true)
		start.stage_index = 1
		start.mechanisms.controls.tide = tide
		var kept: Array = []
		for gate: Dictionary in level.stages[0].gates: kept.append(gate.route_id)
		kept.sort()
		start.mechanisms.latched_bridges = kept
		var explorer: RefCounted = Graph.Explorer.new(graph, level, Witness.SLACK, "p1", start)
		explorer.set_phase({"controls": {}, "levers": {}, "players": {}})
		var reached: Dictionary = explorer.closure({Graph.Explorer.key(int(graph.index["r-terrace"]), explorer.combo_of(start.mechanisms), 0): true})
		_check(reached.size() > 0 and _touches(reached, mole).is_empty(), "Stage two at %s water, every stage-one route kept: p1 never stands on a mole stair or island (%d states)" % [tide, reached.size()])
	p1_mole_surfaces = mole

## Surfaces among `surfaces` that any state of `reached` stands on.
func _touches(reached: Dictionary, surfaces: Array) -> Array:
	var found: Array = []
	for state: int in reached:
		var surface := Graph.Explorer.surface_of(state)
		if surface in surfaces and surface not in found: found.append(surface)
	return found

## Every marker stands on its own surface at its height; pads
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

## The spout lands from every centre in its rect and from a west
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
	_check(total == 2009 and landed == total, "The spout lands all %d of %d centres (model 2009/2009)" % [landed, total])
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

## Stage-2 routes are absent from stage one; the lock gates latch only in stage two.
func _stage_lists() -> void:
	var listed: Array = []
	for gate: Dictionary in level.stages[0].gates: listed.append(gate.route_id)
	for id: String in STAGE_TWO_ONLY:
		_check(id not in listed and id not in level.stages[0].entry_latch_routes, id + " is absent from stage one")
	for id: String in ["lock-west", "lock-east"]:
		_check(id not in level.stages[0].entry_latch_routes and id in level.stages[1].entry_latch_routes, id + " is entry-latched only in stage two")
	for id: String in ["slipway", "stones-3", "jetty-3", "wheel-step"]:
		var relisted := false
		for gate: Dictionary in level.stages[1].gates: relisted = relisted or gate.route_id == id
		_check(not relisted, id + " is open in stage two only if stage one kept it")
	# The boom pin's and the sea key's steps open on their own tide in stage
	# two, and are never kept by an entry latch.
	for item: Array in [["bollard-step", "half"], ["quay-step", "low"]]:
		var when: Variant = null
		for gate: Dictionary in level.stages[1].gates:
			if gate.route_id == item[0]: when = gate.get("when", {})
		_check(when is Dictionary and when == {"control_id": "tide", "value": item[1]} and item[0] not in level.stages[1].entry_latch_routes, "%s opens at %s water in stage two and is not entry-latched" % item)

## No B strand at any tick of seven real A timelines; and A,
## alone in its own world, can always still reach each of its three steps.
func _stage_one_strands() -> void:
	var total := 0
	for name: String in ["low", "low-half-first", "half", "half-via-high", "half-winch", "high", "high-sluice"]:
		var a := Witness.source(level, Witness.SET, initial, Witness.a_routes()[name], 0, Callable(), true)
		_check(a.can_commit(), name + ": the A timeline commits")
		if not a.can_commit(): continue
		var phases := Graph.phases(level, Witness.SET, initial, a.export_recording(), Simulation)
		var explorer: RefCounted = Graph.Explorer.new(graph, level, Witness.SET, "p1", initial)
		var reached: Dictionary = explorer.reach_over(int(graph.index["w-beach"]), phases)
		var strands: int = explorer.strands(reached, [explorer.goal])
		_check(_touches(reached, p1_mole_surfaces).is_empty(), name + ": stage-one B never stands on a mole stair or island")
		total += reached.size()
		_check(strands == 0, "%s: no B strand over %d states and %d phases of %d ticks (%d stranded)" % [name, reached.size(), phases.size(), a.tick + 1, strands])
	print("MODEL stage 1 B states native=%d model=15304" % total)
	_check(total == 15304, "Seven A timelines give the model's 15,304 B states (got %d)" % total)
	var explorer: RefCounted = Graph.Explorer.new(graph, level, Witness.SET, "p0", initial)
	explorer.set_phase({"controls": {}, "levers": {}, "players": {}})
	var start: int = Graph.Explorer.key(int(graph.index["w-beach"]), explorer.combo_of(initial.mechanisms), 0)
	var reached: Dictionary = explorer.closure({start: true})
	for step: String in ["wheel-step", "quay-step", "bollard-step"]:
		var good: Dictionary = explorer.good(reached, [int(graph.index[step])])
		_check(good.size() == reached.size(), "A can always still reach %s (%d of %d states)" % [step, good.size(), reached.size()])

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
