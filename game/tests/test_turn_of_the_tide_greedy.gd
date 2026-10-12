extends SceneTree
## turn-of-the-tide@1: how a greedy player fares. The greedy walker in
## turn_of_the_tide_witness.gd (controls first: fix each shut crossing's
## missing term at the nearest wheel, the fewest turns, before fetching a
## lever) gives its presses on the surface graph for p0 in every stage-two
## cell and for A's three stage-one plans. p0 then plays each cell's greedy
## order with real inputs beside p1's natural turn, for its ticks against the
## optimum and whether it still fits the budget p1 left it; beside a p1 who
## commits at the latest admitted tick it finishes exactly when it fits.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/turn_of_the_tide_witness.gd")
const Graph = preload("res://tests/turn_of_the_tide_graph.gd")
const WAYS := ["boom", "sea-lock", "punt"]
const STEPS := {"low": "wheel-step", "half": "quay-step", "high": "bollard-step"}
## A's fewest presses per stage-one plan, and the greedy walker's. Half and
## High are greedy-optimal: the step's gate says what to do. Low is not: the
## walker turns the tide back to low for the step before fetching the sluice,
## which then needs half, and goes round again.
const STAGE_ONE_PRESSES := {"low": 5, "half": 2, "high": 3}
const STAGE_ONE_GREEDY := {"low": 8, "half": 2, "high": 3}
var checks := 0
var failures := 0
var level: Dictionary = {}
var initial: Dictionary = {}
var graph: RefCounted
var starts: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	level = Catalog.definition(Witness.KEY)
	initial = Catalog.initial_checkpoint(level)
	graph = Graph.new(level)
	graph.build("p0")
	_stage_one()
	for history: String in ["low", "half", "high"]:
		var pair := Witness.pair(level, Witness.SET, initial, Witness.a_routes()[history], Witness.b_routes()[history], false)
		_check(pair.error.is_empty(), history + " history: " + str(pair.error))
		if pair.error.is_empty(): starts[history] = pair.checkpoint
	for history: String in starts:
		for way: String in WAYS: _cell(history, way)
	print("TURN OF THE TIDE GREEDY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Stage one: the greedy walker heading for each plan's step against A's
## fewest presses, which the real A route takes.
func _stage_one() -> void:
	var explorer: RefCounted = Graph.Explorer.new(graph, level, Witness.SET, "p0", initial)
	explorer.set_phase({"controls": {}, "levers": {}, "players": {}})
	var start: int = Graph.Explorer.key(int(graph.index[initial.players.p0.surface_id]), explorer.combo_of(initial.mechanisms), 0)
	for plan: String in STEPS:
		var greedy: RefCounted = Witness.Greedy.new(graph, level, Witness.SET, "p0", initial, {})
		var presses: int = greedy.run([STEPS[plan]])
		var optimum: int = explorer.min_presses(start, [int(graph.index[STEPS[plan]])])
		var real := Witness.source(level, Witness.SET, initial, Witness.a_routes()[plan], 0, Callable(), true)
		_check(greedy.error.is_empty() and presses == STAGE_ONE_GREEDY[plan] and optimum == STAGE_ONE_PRESSES[plan] and Witness.count_presses(real) == optimum,
			"Stage one %s: greedy %d presses (want %d), fewest %d (want %d), the real route's %d (%s %s)" % [plan, presses, STAGE_ONE_GREEDY[plan], optimum, STAGE_ONE_PRESSES[plan], Witness.count_presses(real), greedy.error, str(greedy.log)])
		print("TIDE greedy stage1 %s greedy=%d optimum=%d ticks=%d log=%s" % [plan, presses, optimum, real.tick, str(greedy.log)])

func _cell(history: String, way: String) -> void:
	var label := "%s %s" % [history.to_upper(), way]
	var start: Dictionary = starts[history]
	var ops: Array = Witness.p1_home(history) + Witness.p1_way(history, way)
	var p1 := Witness.source(level, Witness.SLACK, start, ops, 0, Callable(), true)
	if not p1.can_commit():
		_check(false, label + ": the natural p1 turn commits")
		return
	var other := {"controls": {"basin": p1._mechanisms.controls.basin, "lock": p1._mechanisms.controls.lock}, "levers": {}}
	for lever: Dictionary in level.stages[1].levers:
		if lever.owner_slot == "p1": other.levers[lever.id] = bool(p1._mechanisms.levers.get(lever.id, false))
	var greedy: RefCounted = Witness.Greedy.new(graph, level, Witness.SLACK, "p0", start, other)
	var presses: int = greedy.run(Witness.GREEDY_TARGETS[way])
	var optimum: int = Witness.MODEL_CELLS[history][way][2]
	_check(greedy.error.is_empty() and presses == Witness.MODEL_GREEDY[history][way], "%s: the greedy walker takes the model's %d presses (got %d: %s %s)" % [label, Witness.MODEL_GREEDY[history][way], presses, greedy.error, str(greedy.log)])
	_check(presses >= optimum, "%s: greedy never beats the fewest presses %d" % [label, optimum])
	# The same order with real inputs, and the optimum, beside p1's natural turn.
	var first: Dictionary = p1.export_recording()
	var probe := func(name: String, sim: RefCounted) -> void:
		match name:
			"pinless": _check(not sim._routes["mole-steps"] and not sim.walkable_at(-840, -200), label + ": without the pin the mole steps stay shut at low water")
			"keyless": _check(not sim._routes["sea-gate-out"] and str(sim._mechanisms.controls.chamber) == "low", label + ": without the key or high water the sea gate stays shut with the chamber low")
			"race-shut": _check(not sim._routes["race-stage"] and not sim.walkable_at(208, -140), label + ": at half water the race stage is flooded")
			"punt-shut": _check(not sim._routes["punt-ferry"], label + ": at low water without the line the punt stays shut")
	var b := Witness.receiver(level, Witness.SLACK, start, first, Witness.p0_greedy(history, way), probe, true)
	var best := Witness.receiver(level, Witness.SLACK, start, first, Witness.p0_way(history, way), Callable(), true)
	_check(b.complete and str(b.get_meta("route_error")) == "" and best.complete, "%s: greedy p0 completes beside the natural p1 (%s %s)" % [label, b.error, b.get_meta("route_error")])
	if not b.complete or not best.complete: return
	_check(Witness.count_presses(b) == presses, "%s: the real greedy route presses %d times (got %d)" % [label, presses, Witness.count_presses(b)])
	var ticks := Witness.active_ticks(b)
	var optimal_ticks := Witness.active_ticks(best)
	var budget: int = p1.source_budget_ticks()
	var after_ready := int(b.get_meta("ring_tick", b.tick)) - int(p1._hold_start)
	var over := after_ready > budget
	_check(ticks >= optimal_ticks, "%s: greedy is never faster than the optimum (%d vs %d)" % [label, ticks, optimal_ticks])
	# Beside the latest admitted p1, greedy finishes exactly when it fits the budget.
	var delay: int = p1.receiver_deadline() - 1 - budget - p1._hold_start
	var late := Witness.source(level, Witness.SLACK, start, ops, delay, Callable(), true)
	var late_b := Witness.receiver(level, Witness.SLACK, start, late.export_recording(), Witness.p0_greedy(history, way), Callable(), true)
	var late_after := int(late_b.get_meta("ring_tick", late_b.tick)) - int(late._hold_start)
	_check(late.can_commit() and late_b.complete == (late_after <= budget), "%s: beside the latest admitted p1, greedy %s (%d of %d)" % [label, "finishes" if late_b.complete else "runs out of time", late_after, budget])
	print("TIDE greedy %s presses=%d optimum=%d ticks=%d optimal-ticks=%d ratio=%.2f after-ready=%d budget=%d over=%s reserve=%s late-complete=%s log=%s" % [label, presses, optimum, ticks, optimal_ticks,
		float(ticks) / float(optimal_ticks), after_ready, budget, str(over), str(after_ready > budget - 130), str(late_b.complete), str(greedy.log)])

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
