extends SceneTree
## turn-of-the-tide@1 stage-two limits with real inputs under rules 9: a slow
## p1 at 1.3x still commits in every cell; what turning the sea before the
## moorings costs p1 in every cell; entry latches keep exactly what p0
## touched; and p1's "not ready" reason. p0's greedy order:
## test_turn_of_the_tide_greedy.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/turn_of_the_tide_witness.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const T := ["t"]
const WEST := [172,-368]
## p1's margin to the deadline at 1.3x its optimum, from an independent
## axis-walk model (a lower bound for the native walk).
const MODEL_MARGIN_SLOW := {"low": {"boom": 1902, "sea-lock": 1827, "punt": 1822}, "half": {"boom": 1883, "sea-lock": 1936, "punt": 1920}, "high": {"boom": 1808, "sea-lock": 1850, "punt": 1931}}
## The sea turned first: p1's presses per history and way, natural then wrong.
const SEA_FIRST_PRESSES := {
	"low": {"boom": [4, 8], "sea-lock": [3, 7], "punt": [5, 9]},
	"half": {"boom": [5, 9], "sea-lock": [8, 8], "punt": [6, 10]},
	"high": {"boom": [8, 8], "sea-lock": [7, 7], "punt": [5, 9]},
}
## The same model's tick ratios for the wrong order, where it has them.
const MODEL_SEA_FIRST_RATIO := {"low": {"boom": 1.35, "sea-lock": 1.02, "punt": 1.08}, "high": {"boom": 1.04, "sea-lock": 1.01, "punt": 1.23}}
## A wrong order that costs p1 at least this much in ticks and presses reads
## as a real mistake; the cells that miss it are listed, not failed.
const BAR_RATIO := 1.15
const BAR_PRESSES := 2
var checks := 0
var failures := 0
var level: Dictionary = {}
var initial: Dictionary = {}
var starts: Dictionary = {}
var p1_records: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	level = Catalog.definition(Witness.KEY)
	initial = Catalog.initial_checkpoint(level)
	for history: String in ["low", "half", "high"]:
		var pair := Witness.pair(level, Witness.SET, initial, Witness.a_routes()[history], Witness.b_routes()[history], false)
		_check(pair.error.is_empty(), history + " history: " + str(pair.error))
		if pair.error.is_empty(): starts[history] = pair.checkpoint
	if starts.size() == 3:
		_slow_p1()
		_not_ready()
		_sea_first()
		_latches()
	print("TURN OF THE TIDE LIMITS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## p1 at 1.3x its optimum (it waits 30% of its ready tick first) still commits.
func _slow_p1() -> void:
	for history: String in starts:
		for way: String in ["boom", "sea-lock", "punt"]:
			var ops: Array = Witness.p1_home(history) + Witness.p1_way(history, way)
			var fast := Witness.source(level, Witness.SLACK, starts[history], ops, 0, Callable(), true)
			if history == "low": p1_records[way] = fast.export_recording()
			var delay := int(ceil(fast._hold_start * 0.3))
			var slow := Witness.source(level, Witness.SLACK, starts[history], ops, delay, Callable(), true)
			var margin: int = slow.receiver_deadline() - 1 - slow.source_budget_ticks() - slow._hold_start
			_check(slow.can_commit() and margin >= 0, "%s %s: p1 at 1.3x still commits (margin %d)" % [history.to_upper(), way, margin])
			print("MODEL %s %s margin at 1.3x native=%d model=%d" % [history.to_upper(), way, margin, MODEL_MARGIN_SLOW[history][way]])

## p1 at slack with the gate bar pulled but off any post is not ready yet.
func _not_ready() -> void:
	var ops: Array = Witness.p1_home("low") + [["w",[-164,388]],["w",[-164,116]]] + Witness._sea("shut", "low") + Witness._gate_bar() + [["w",[-328,-112]], ["n", 10]]
	var p1 := Witness.source(level, Witness.SLACK, starts.low, ops, 0, Callable(), true)
	_check(p1.error.is_empty() and str(p1.get_meta("route_error")) == "" and p1._mechanisms.levers.get("gate-bar", false) and not p1.can_commit(), "The bar alone, off the post, is not ready")
	_check(p1.commit_reason() == "Keep the crossing ready for your partner.", "Not on a post shows the generic reason (%s)" % p1.commit_reason())

## The sea turned before any mooring floods the shut-only moorings (the beach
## chain for the boom, the sea bar for the sea lock and the punt); the sea has
## to go round to shut again. p1 still commits and p0 still wins. Where the
## recovery costs p1 nothing extra, the cell is listed against the bar.
func _sea_first() -> void:
	var below: Array = []
	for history: String in starts:
		for way: String in ["boom", "sea-lock", "punt"]:
			var label := "%s %s" % [history.to_upper(), way]
			var probe := func(name: String, sim: RefCounted) -> void:
				var stub: String = {"catwalk-shut": "beach-catwalk", "bar-shut": "bar-catwalk"}.get(name, "")
				if not stub.is_empty(): _check(not sim._routes[stub] and str(sim._mechanisms.controls.basin) != "shut", "%s: with the sea turned first, %s is flooded" % [label, stub])
			var natural := Witness.source(level, Witness.SLACK, starts[history], Witness.p1_home(history) + Witness.p1_way(history, way), 0, Callable(), true)
			var pair := Witness.pair(level, Witness.SLACK, starts[history], Witness.p1_home(history) + Witness.p1_way_sea_first(history, way), Witness.p0_way(history, way), false, probe)
			_check(pair.error.is_empty(), "%s sea first recovers and p0 wins: %s" % [label, pair.error])
			if not pair.error.is_empty(): continue
			var presses: Array = SEA_FIRST_PRESSES[history][way]
			_check(Witness.count_presses(natural) == presses[0] and Witness.count_presses(pair.a_sim) == presses[1], "%s: turning the sea first takes p1 %d presses instead of %d (got %d and %d)" % [label, presses[1], presses[0], Witness.count_presses(pair.a_sim), Witness.count_presses(natural)])
			var ratio := float(pair.a.duration_ticks) / float(natural.tick)
			_check(ratio >= 1.0, "%s: the wrong order never saves p1 time (%.2fx)" % [label, ratio])
			if ratio < BAR_RATIO or presses[1] - presses[0] < BAR_PRESSES: below.append("%s %.2fx +%d" % [label, ratio, presses[1] - presses[0]])
			print("MODEL %s sea-first p1 ratio native=%.2f model=%s presses %d->%d ticks %d->%d" % [label, ratio, str(MODEL_SEA_FIRST_RATIO.get(history, {}).get(way, "-")), presses[0], presses[1], natural.tick, pair.a.duration_ticks])
	print("TIDE sea-first below %.2fx or +%d presses: %d of 9 %s" % [BAR_RATIO, BAR_PRESSES, below.size(), str(below)])

## Entry latches through the real simulation (journey/simulation.gd _after_move).
func _latches() -> void:
	var probe := func(name: String, sim: RefCounted) -> void:
		var tide := str(sim._mechanisms.controls.tide)
		match name:
			"high-water":
				_check(tide == "high" and sim._routes["stones-1"] and sim._entry_latches.has("stones-1"), "At high water stones-1 stays open only because p0 crossed it at half")
				var match_now := Seven.predicate(_gate("sea-gate-in"), sim.stage, sim._players, sim._mechanisms)
				_check(not match_now and sim._routes["sea-gate-in"] and sim._entry_latches.has("sea-gate-in"), "At high water the touched sea-gate-in stays open though the chamber does not match")
			"inside": _check(sim._players.p0.surface_id == "sea-chamber", "p0 re-enters the sea chamber at high water")
			"boom-touch": _check(sim._entry_latches.has("boom-jetty") and sim._players.p0.surface_id == "w-quay", "A radius sample from the w-quay edge keeps the boom")
			"towpath": _check(sim._entry_latches.has("towpath"), "Walking the towpath latches it")
			"match": _check(Seven.predicate(_gate("sea-gate-in"), sim.stage, sim._players, sim._mechanisms), "With the chamber turned to high first, the gate opens again by its own match at high water")
	var sea := Witness.p0_way("low", "sea-lock")
	var at := _find(sea, ["d",[-596,36]])
	sea.insert(at + 1, ["?", "inside"])
	sea.insert(at, ["?", "high-water"])
	_receiver("sea lock latches", "sea-lock", sea, Witness.MODEL_CELLS.low["sea-lock"][2], probe)
	var boom := Witness.p0_way("low", "boom")
	boom.insert(_find(boom, ["u","route:boom-jetty"]) + 1, ["?", "boom-touch"])
	_receiver("boom touch", "boom", boom, Witness.MODEL_CELLS.low.boom[2], probe)
	var tow: Array = [["w",[192,-368]],["w",[96,-368]],["w",[96,404]],["w",[300,404]],["?","towpath"],["w",[96,404]],["w",[96,-368]]] + Witness.p0_way("low", "punt").slice(1)
	var towed := _receiver("towpath detour", "punt", tow, 2, probe)
	if towed != null: _check("towpath" in towed.snapshot().route_progress.entered_routes, "The towpath latch is harmless: the punt still wins with its two presses")
	# The key first, then the chamber turned high at half water before raising the harbour.
	var free: Array = Witness.p0_way("low", "sea-lock").slice(0, 7) + [["w",[132,-368]],["w",[132,26]],["w",[-500,26]],["u","route:sea-gate-in"],["w",[-600,26]],T,["w",[132,26]],["w",[132,-368]],["w",WEST],T,
		["w",[132,-368]],["w",[132,26]],["w",[-520,26]],["?","match"],["w",[-600,26]],T,["u","route:sea-gate-out"],["w",[-832,26]],T]
	_receiver("sea lock, chamber first", "sea-lock", free, 5, probe)

## p0 beside the natural LOW p1 recording for `way`; checks completion and presses.
func _receiver(label: String, way: String, ops: Array, presses: int, probe: Callable) -> RefCounted:
	var b := Witness.receiver(level, Witness.SLACK, starts.low, p1_records[way], ops, probe, true)
	_check(b.complete and str(b.get_meta("route_error")) == "", "%s: p0 completes (%s %s)" % [label, b.error, b.get_meta("route_error")])
	_check(Witness.count_presses(b) == presses, "%s: %d presses (got %d)" % [label, presses, Witness.count_presses(b)])
	return b if b.complete else null

func _gate(route: String) -> Dictionary:
	for gate: Dictionary in level.stages[1].gates:
		if gate.route_id == route: return gate.get("when", {})
	return {}

func _find(ops: Array, op: Array) -> int:
	for i in range(ops.size()):
		if str(ops[i]) == str(op): return i
	return -1

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
