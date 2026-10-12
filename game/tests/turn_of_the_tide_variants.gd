extends SceneTree
## turn-of-the-tide@1 stage two after every other stage-one end state: the
## Low half-first order (with either B route), Half through high water, both
## misplays and B's hybrids. After each one, for every way: p1 commits with
## real inputs and p0 wins, derived through the full proof; p1 still commits
## at 1.3x its own pace; p0 is never stranded at any tick of p1's turn; and
## p0's fewest presses equal its main history's (never 0).
## After low-half-first-stones the lock stands east and the stones are kept,
## but the slipway is kept too (it is open at completion, as after every LOW
## end state), so p1 still walks home over the beach.
## Two chains are also contract fixtures for the backend (written as
## test_turn_of_the_tide describes): low-half-first-stones and half-winch.
## Each test_turn_of_the_tide_variants_<history> suite runs one history's
## variants, so no suite runs long.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/turn_of_the_tide_witness.gd")
const Graph = preload("res://tests/turn_of_the_tide_graph.gd")
const VARIANTS := ["low-jetty", "low-half-first", "low-half-first-stones", "half-early-sand", "half-via-high", "half-winch", "high-early-sand", "high-sluice", "high-spout"]
const EXPORTED := ["low-half-first-stones", "half-winch"]
const WAYS := ["boom", "sea-lock", "punt"]
var checks := 0
var failures := 0
var level: Dictionary = {}
var initial: Dictionary = {}
var graph: RefCounted
var files: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var started := Time.get_ticks_msec()
	level = Catalog.definition(Witness.KEY)
	initial = Catalog.initial_checkpoint(level)
	graph = Graph.new(level)
	graph.build("p0")
	var names: Array = _variants()
	for name: String in names:
		var spec: Array = Witness.PAIRS[name]
		var first := Witness.pair(level, Witness.SET, initial, Witness.a_routes()[spec[0]], Witness.b_routes()[spec[1]], name in EXPORTED)
		_check(first.error.is_empty(), "%s: stage one derives (%s)" % [name, first.error])
		if not first.error.is_empty(): continue
		if name in EXPORTED: Witness.chain_files(files, "set-the-tide-" + name, first)
		var kept: Array = first.checkpoint.mechanisms.latched_bridges
		var home: String = {"low": "slipway", "half": "stones-3", "high": "jetty-3"}[str(first.checkpoint.mechanisms.controls.tide)]
		_check(home in kept, "%s: p1's way home (%s) is kept" % [name, home])
		for way: String in WAYS: _cell(name, first.checkpoint, way)
		print("TIDE variants: %s done at %d ms" % [name, Time.get_ticks_msec() - started])
	var exported: int = names.filter(func(name: String) -> bool: return name in EXPORTED).size()
	_check(files.size() == 12 * exported, "Every variant contract fixture here has evidence (%d)" % files.size())
	for row: Array in Witness.fixtures(files, failures == 0): _check(row[0], row[1])
	print("TURN OF THE TIDE VARIANTS %s: %d checks, %d failures" % [str(names), checks, failures])
	quit(1 if failures else 0)

## The variants this suite runs; each history's suite names its own.
func _variants() -> Array:
	return VARIANTS

func _cell(name: String, start: Dictionary, way: String) -> void:
	var branch := str(start.mechanisms.controls.tide)
	var label := "%s %s" % [name, way]
	var ops: Array = Witness.p1_route(start, way)
	var pair := Witness.pair(level, Witness.SLACK, start, ops, Witness.p0_way(branch, way), true)
	_check(pair.error.is_empty(), "%s: p1 commits and p0 wins, derived through the full proof (%s)" % [label, pair.error])
	if not pair.error.is_empty(): return
	var a: RefCounted = pair.a_sim
	var cp: Dictionary = pair.checkpoint
	_check(a._ready_branch == way and a.source_budget_ticks() == Witness.MODEL_CELLS[branch][way][0], "%s: p1 commits its own branch with the %s budget %d (got %d)" % [label, branch.to_upper(), Witness.MODEL_CELLS[branch][way][0], a.source_budget_ticks()])
	_check(cp.stage_index == 2 and cp.next_stage_id == "" and cp.players.p0.surface_id == "mole-terrace", label + ": the chapter completes at the lantern")
	var delay := int(ceil(a._hold_start * 0.3))
	var slow := Witness.source(level, Witness.SLACK, start, ops, delay, Callable(), true)
	var margin: int = slow.receiver_deadline() - 1 - slow.source_budget_ticks() - slow._hold_start
	_check(slow.can_commit() and margin >= 0, "%s: p1 at 1.3x still commits (margin %d)" % [label, margin])
	var phases := Graph.phases(level, Witness.SLACK, start, pair.a, Simulation)
	var explorer: RefCounted = Graph.Explorer.new(graph, level, Witness.SLACK, "p0", start)
	var step := int(graph.index[start.players.p0.surface_id])
	explorer.prepare(phases)
	var reached: Dictionary = explorer.reach_over(step, phases)
	var strands: int = explorer.strands(reached, [explorer.goal])
	_check(strands == 0, "%s: no p0 strand over %d states and %d phases (%d stranded)" % [label, reached.size(), phases.size(), strands])
	explorer.set_phase(phases[-1])
	var final_min: int = explorer.min_presses(Graph.Explorer.key(step, explorer.combo_of(explorer.base_mechanisms), 0), [explorer.goal])
	var timed_min: int = explorer.min_presses_over(step, phases, [explorer.goal])
	var main_min: int = Witness.MODEL_CELLS[branch][way][2]
	_check(final_min == main_min and timed_min == main_min, "%s: p0 needs the main %s history's %d presses, never 0 (final %d, with p1's transients %d)" % [label, branch.to_upper(), main_min, final_min, timed_min])
	if name in EXPORTED: Witness.chain_files(files, "slack-water-%s-%s" % [name, way], pair)
	print("TIDE variant %s p1=%d ready=%d budget=%d margin=%d presses p1=%d p0=%d p0-min=%d/%d p0-real=%d" % [label, pair.a.duration_ticks, a._hold_start, a.source_budget_ticks(), margin,
		Witness.count_presses(a), Witness.count_presses(pair.b_sim), final_min, timed_min, Witness.active_ticks(pair.b_sim)])

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
