extends SceneTree
## turn-of-the-tide@1 stage two ("slack-water") on the graph model of
## turn_of_the_tide_graph.gd, against real p1 recordings:
## - p0 strands at every tick of p1's real turn (natural and sea first), and
##   for every chain pulled through the reversibility of p0's moves;
## - p0's fewest presses per way and history, and with every chain pulled;
## - the lantern stays out of reach with the tide held or p0's controls frozen;
## - p1 is never trapped away from any post;
## - every surface change in the native fixture runs is a graph edge open then.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/turn_of_the_tide_witness.gd")
const Graph = preload("res://tests/turn_of_the_tide_graph.gd")
const DIRECTORY := "res://tests/fixtures/journey/"
const WAYS := ["boom", "sea-lock", "punt"]
var checks := 0
var failures := 0
var mismatches: Array[String] = []
var level: Dictionary = {}
var initial: Dictionary = {}
var graph: RefCounted
var starts: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var started := Time.get_ticks_msec()
	level = Catalog.definition(Witness.KEY)
	initial = Catalog.initial_checkpoint(level)
	graph = Graph.new(level)
	for slot: String in ["p0", "p1"]: graph.build(slot)
	for history: String in ["low", "half", "high"]:
		var pair := Witness.pair(level, Witness.SET, initial, Witness.a_routes()[history], Witness.b_routes()[history], false)
		_check(pair.error.is_empty(), history + " history: " + str(pair.error))
		if pair.error.is_empty(): starts[history] = pair.checkpoint
	print("TIDE presses: histories %d ms" % (Time.get_ticks_msec() - started))
	for history: String in starts:
		for way: String in WAYS:
			_cell(history, way, Witness.p1_home(history) + Witness.p1_way(history, way), "natural")
		_cell(history, "boom", Witness.p1_home(history) + Witness.p1_way_sea_first(history, "boom"), "sea first")
		for way: String in WAYS:
			_cell(history, way, Witness.p1_home(history) + Witness.p1_all_chains(history, way), "all chains", false)
	_reversible()
	print("TIDE presses: p0 cells %d ms" % (Time.get_ticks_msec() - started))
	for history: String in starts:
		_guarantees(history)
		_p1_traps(history)
	print("TIDE presses: guarantees and traps %d ms" % (Time.get_ticks_msec() - started))
	_cross_check()
	print("TIDE presses: cross check %d ms" % (Time.get_ticks_msec() - started))
	for line: String in mismatches: print("MODEL MISMATCH " + line)
	print("TURN OF THE TIDE PRESSES: %d checks, %d failures, %d model mismatches" % [checks, failures, mismatches.size()])
	quit(1 if failures else 0)

## One real p1 turn; p0's reachable states at every tick of it, strands under
## p1's final values, and p0's fewest presses.
func _cell(history: String, way: String, ops: Array, kind: String, every_state: bool = true) -> void:
	var label := "%s %s (%s)" % [history.to_upper(), way, kind]
	var p1 := Witness.source(level, Witness.SLACK, starts[history], ops, 0, Callable(), true)
	_check(p1.can_commit() and p1._ready_branch == way and str(p1.get_meta("route_error")) == "", "%s: p1 commits its post (%s %s)" % [label, p1.get_meta("route_error"), p1.commit_reason()])
	if not p1.can_commit(): return
	var phases := Graph.phases(level, Witness.SLACK, starts[history], p1.export_recording(), Simulation)
	var explorer: RefCounted = Graph.Explorer.new(graph, level, Witness.SLACK, "p0", starts[history])
	var step := int(graph.index[starts[history].players.p0.surface_id])
	var dropped: Dictionary = explorer.prepare(phases)
	var reached: Dictionary = {}
	if every_state:
		reached = explorer.reach_over(step, phases)
		var strands: int = explorer.strands(reached, [explorer.goal])
		_check(strands == 0, "%s: no p0 strand over %d states, %d phases of %d ticks (%d stranded)" % [label, reached.size(), phases.size(), p1.tick + 1, strands])
	explorer.set_phase(phases[-1])
	var final_min: int = explorer.min_presses(Graph.Explorer.key(step, explorer.combo_of(explorer.base_mechanisms), 0), [explorer.goal])
	var timed_min: int = explorer.min_presses_over(step, phases, [explorer.goal])
	if kind == "natural":
		var model: int = Witness.MODEL_CELLS[history][way][2]
		print("MODEL %s p0 min presses native=%d model=%d (with p1's transients %d)" % [label, final_min, model, timed_min])
		_check(final_min == model, "%s: p0 needs exactly %d presses (got %d)" % [label, model, final_min])
		if timed_min != final_min: mismatches.append("%s: p1's transients let p0 win with %d presses, not %d" % [label, timed_min, final_min])
	else:
		print("TIDE %s p0 min presses final=%d with transients=%d" % [label, final_min, timed_min])
		_check(final_min >= 1 and timed_min >= 1, "%s: p0 always needs a press (final %d, timed %d)" % [label, final_min, timed_min])
	print("TIDE %s states=%d phases=%d frozen=%s unlatched=%s" % [label, reached.size(), phases.size(), str(dropped.frozen), str(dropped.latches)])

## Why every-chain turns cannot strand p0 either: each p0 move can be walked
## back (contacts work both ways and p0 has no drop), every route p0 can stand
## on stays open once entered (entry-latched, always open, kept from stage
## one, or read only from p0's own controls, none of whose wheels stands on
## that route), and p0's wheels and levers stand on surfaces it can walk back
## to. So a p0 state is stranded only if the lantern is out of reach from p0's
## own start, which the fewest-presses search above rules out for each turn.
func _reversible() -> void:
	var stage: Dictionary = level.stages[1]
	var unlatched: Array = []
	var own_reads: Array = []
	for gate: Dictionary in stage.gates:
		var route: Dictionary = {}
		for item: Dictionary in level.bridges + level.stairs:
			if item.id == gate.route_id: route = item
		if not gate.has("when") or str(route.owner_slot) not in ["", "p0"] or gate.route_id in stage.entry_latch_routes: continue
		if _reads_only_own_controls_off(gate.when, stage, gate.route_id): own_reads.append(gate.route_id)
		else: unlatched.append(gate.route_id)
	_check(unlatched.is_empty(), "Every other gated stage-2 route p0 may use is entry-latched (%s)" % str(unlatched))
	own_reads.sort()
	_check(own_reads == ["bollard-step", "quay-step"], "Only the pin and key steps stay unlatched; they read p0's tide alone (%s)" % str(own_reads))
	var one_way: Array = []
	for key: String in graph.pairs.p0:
		var ends := key.split(">")
		if not graph.pairs.p0.has(ends[1] + ">" + ends[0]): one_way.append(key)
	_check(one_way.is_empty(), "Every p0 contact works both ways and p0 has no drop (%s)" % str(one_way))

## With every mooring fast, any sea, either lock and every stage-1
## route kept, the lantern stays out of reach (a) with the tide held at any
## one value and (b) with all of p0's controls frozen at the stage-2 start.
func _guarantees(history: String) -> void:
	var kept: Array = []
	for gate: Dictionary in level.stages[0].gates: kept.append(gate.route_id)
	var start: Dictionary = starts[history].duplicate(true)
	start.mechanisms.latched_bridges = kept
	var step := int(graph.index[start.players.p0.surface_id])
	var reachable: Array = []
	for sea: String in Witness.SEA:
		for lock: String in ["west", "east"]:
			var phase := {"controls": {"basin": sea, "lock": lock}, "levers": {"boom-chain": true, "gate-bar": true, "punt-chain": true, "sea-bar": true}, "players": {}}
			var cases: Array = []
			for tide: String in Witness.TIDE: cases.append({"tide": tide})
			cases.append({"tide": history, "chamber": "half", "punt-line": false, "boom-pin": false, "sea-key": false})
			for frozen: Dictionary in cases:
				var mechanisms: Dictionary = start.mechanisms.duplicate(true)
				mechanisms.controls.tide = frozen.tide
				var held := start.duplicate(true)
				held.mechanisms = mechanisms
				var explorer: RefCounted = Graph.Explorer.new(graph, level, Witness.SLACK, "p0", held)
				explorer.freeze(frozen)
				explorer.set_phase(phase)
				var reached: Dictionary = explorer.closure({Graph.Explorer.key(step, explorer.combo_of(held.mechanisms), 0): true})
				for state: int in reached:
					if Graph.Explorer.surface_of(state) == explorer.goal:
						reachable.append("%s/%s/%s" % [sea, lock, str(frozen)])
						break
	_check(reachable.is_empty(), "%s: no held tide and no frozen start reaches the lantern (%s)" % [history.to_upper(), str(reachable)])

## p1 is never trapped. Alone in its own world (tide frozen at the
## history's value), from the bell, under any sea, lock and chains, every
## reachable state can still reach every post.
func _p1_traps(history: String) -> void:
	var explorer: RefCounted = Graph.Explorer.new(graph, level, Witness.SLACK, "p1", starts[history])
	explorer.set_phase({"controls": {}, "levers": {}, "players": {}})
	var start: int = Graph.Explorer.key(int(graph.index[starts[history].players.p1.surface_id]), explorer.combo_of(starts[history].mechanisms), 0)
	var reached: Dictionary = explorer.closure({start: true})
	var traps := 0
	for post: String in ["boom-post", "gate-post", "punt-post"]:
		traps += explorer.strands(reached, [int(graph.index[post])])
	_check(traps == 0 and reached.size() > 0, "%s: p1 traps 0 over %d states (got %d)" % [history.to_upper(), reached.size(), traps])
	var mole := false
	for state: int in reached: mole = mole or graph.id_of(Graph.Explorer.surface_of(state)).begins_with("mole")
	_check(not mole, history.to_upper() + ": p1 never reaches the mole")

## Every surface change in the native fixture runs (stage-1 B, and p1 and p0
## in each LOW way) is a graph edge whose routes were open on that tick.
func _cross_check() -> void:
	var start := _load("set-the-tide-checkpoint")
	_replay("stage 1 A", Witness.SET, initial, {}, _load("set-the-tide-a"), "p0")
	_replay("stage 1 B", Witness.SET, initial, _load("set-the-tide-a"), _load("set-the-tide-b"), "p1")
	for name: String in ["slack-water", "slack-water-boom", "slack-water-punt"]:
		_replay(name + " p1", Witness.SLACK, start, {}, _load(name + "-a"), "p1")
		_replay(name + " p0", Witness.SLACK, start, _load(name + "-a"), _load(name + "-b"), "p0")

func _replay(label: String, stage_id: String, checkpoint: Dictionary, first: Dictionary, record: Dictionary, slot: String) -> void:
	var sim := Simulation.new()
	sim.simulation_version = Witness.RULES
	sim._reset_trusted(level, stage_id, checkpoint, first, "a" if first.is_empty() else "b")
	var previous := str(sim._players[slot].surface_id)
	var changes := 0
	var bad: Array = []
	for input: Dictionary in Simulation.expand_recording_inputs(record):
		var before: Dictionary = sim._routes.duplicate()
		sim.step(input)
		var now := str(sim._players[slot].surface_id)
		if now == previous: continue
		changes += 1
		var edge: Variant = graph.pairs[slot].get(previous + ">" + now)
		var open := edge != null
		for id: String in [previous, now]:
			if graph.route_bit.has(id): open = open and (bool(before.get(id, false)) or bool(sim._routes.get(id, false)))
		if not open: bad.append("%s>%s@%d" % [previous, now, sim.tick])
		previous = now
	_check(changes > 0 and bad.is_empty(), "%s: %d surface changes, all graph edges open at the time (%s)" % [label, changes, str(bad)])

## True when every leaf reads a p0 control whose wheel does not stand on the
## route itself, so p0 cannot change the route while standing on it.
func _reads_only_own_controls_off(when: Dictionary, stage: Dictionary, route_id: String) -> bool:
	if when.has("all") or when.has("any"):
		for child: Dictionary in when.get("all", when.get("any", [])):
			if not _reads_only_own_controls_off(child, stage, route_id): return false
		return true
	if not when.has("control_id"): return false
	for control: Dictionary in stage.controls:
		if control.id == when.control_id: return control.owner_slot == "p0" and control.surface_id != route_id
	return false

func _load(name: String) -> Dictionary:
	var path := DIRECTORY + name + ".json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return parsed if parsed is Dictionary else {}

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
