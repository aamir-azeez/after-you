extends SceneTree
## turn-of-the-tide@1 stage-two limits with real inputs under rules 9 (spec
## 4.3, 4.5, 11.4, 11.6, 11.7): a slow p1 at 1.3x still commits in every
## cell; the wrong order costs p1 a little and p0 a lot; entry latches keep
## exactly what p0 touched; and p1's "not ready" reason.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/turn_of_the_tide_witness.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const T := ["t"]
const WEST := [172,-368]
## Spec 6.3: p1's margin to the deadline at 1.3x its optimum.
const PORT_MARGIN_SLOW := {"low": {"boom": 120, "sea-lock": 114, "punt": 95}, "half": {"boom": 218, "sea-lock": 180, "punt": 248}, "high": {"boom": 207, "sea-lock": 104, "punt": 108}}
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
		_wrong_order()
	print("TURN OF THE TIDE LIMITS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## 11.6: p1 at 1.3x its optimum (it waits 30% of its ready tick first) still commits.
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
			print("PORT %s %s margin at 1.3x native=%d port=%d" % [history.to_upper(), way, margin, PORT_MARGIN_SLOW[history][way]])

## p1 at the basin, chain pulled but off its post, is not ready yet.
func _not_ready() -> void:
	var ops: Array = Witness.p1_home("low") + [["w", Witness.BASIN_STAND], T, ["w",[-340,-134]], T, ["w",[-340,-116]], ["n", 10]]
	var p1 := Witness.source(level, Witness.SLACK, starts.low, ops, 0, Callable(), true)
	_check(p1.error.is_empty() and p1._mechanisms.levers.get("gate-bar", false) and not p1.can_commit(), "The bar alone, off the post, is not ready")
	_check(p1.commit_reason() == "Keep the crossing ready for your partner.", "Not on a post shows the generic reason (%s)" % p1.commit_reason())

## 4.3-3 and 11.4: the sea set first shuts the catwalk; recovering costs p1 a
## little and still commits, and p0 still wins.
func _sea_first() -> void:
	for history: String in starts:
		var probe := func(name: String, sim: RefCounted) -> void:
			if name == "catwalk-shut" and history != "high":
				_check(not sim._routes["boom-catwalk"] and not sim.walkable_at(-340, 134), history.to_upper() + ": with the sea at high first, the boom catwalk is shut")
		var natural := Witness.source(level, Witness.SLACK, starts[history], Witness.p1_home(history) + Witness.p1_way(history, "boom"), 0, Callable(), true)
		var pair := Witness.pair(level, Witness.SLACK, starts[history], Witness.p1_home(history) + Witness.p1_way_sea_first(history, "boom"), Witness.p0_way(history, "boom"), false, probe)
		if history == "high":
			# The HIGH history's direct way: the sea at high is already slack.
			_check(pair.error.is_empty(), "HIGH boom sea first is simply the natural order: " + str(pair.error))
			continue
		_check(pair.error.is_empty(), "%s boom sea first recovers and p0 wins: %s" % [history.to_upper(), pair.error])
		if pair.error.is_empty():
			var ratio := float(pair.a.duration_ticks) / float(natural.tick)
			_check(ratio <= 1.25, "%s boom: the wrong order costs p1 %.2fx (port 1.06-1.09x)" % [history.to_upper(), ratio])
			print("PORT %s boom sea-first p1 ratio native=%.2f port=1.06-1.09" % [history.to_upper(), ratio])

## 11.7 through the real entry latches (journey/simulation.gd _after_move).
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
	var at := _find(sea, ["w",[-600,26]])
	sea.insert(at + 1, ["?", "inside"])
	sea.insert(at, ["?", "high-water"])
	_receiver("sea lock latches", "sea-lock", sea, 4, probe)
	var boom := Witness.p0_way("low", "boom")
	boom.insert(_find(boom, ["u","route:boom-jetty"]) + 1, ["?", "boom-touch"])
	_receiver("boom touch", "boom", boom, 3, probe)
	var tow: Array = [["w",[192,-368]],["w",[96,-368]],["w",[96,404]],["w",[300,404]],["?","towpath"],["w",[96,404]],["w",[96,-368]]] + Witness.p0_way("low", "punt").slice(1)
	var towed := _receiver("towpath detour", "punt", tow, 2, probe)
	if towed != null: _check("towpath" in towed.snapshot().route_progress.entered_routes, "The towpath latch is harmless: the punt still wins with its two presses")
	var free: Array = [["w",[192,-368]],T,["w",[132,-368]],["w",[132,26]],["w",[-500,26]],["u","route:sea-gate-in"],["w",[-600,26]],T,["w",[132,26]],["w",[132,-368]],["w",WEST],T,
		["w",[132,-368]],["w",[132,26]],["w",[-520,26]],["?","match"],["w",[-600,26]],T,["u","route:sea-gate-out"],["w",[-832,26]],T]
	_receiver("sea lock, chamber first", "sea-lock", free, 4, probe)

## 4.5 and 11.4: p0 in the wrong order recovers, at a real cost in ticks.
func _wrong_order() -> void:
	var probe := func(name: String, sim: RefCounted) -> void:
		match name:
			"boom-shut": _check(not sim._routes["boom-jetty"] and not sim.walkable_at(-560, -368), "At low water the boom stays sunk")
			"gate-shut": _check(not sim._routes["sea-gate-in"] and not sim.walkable_at(-540, 0), "Raised first, the chamber never matches and the gate stays shut")
			"race-shut": _check(not sim._routes["race-stage"] and not sim.walkable_at(208, -140), "Raised first, the race stage floods")
	var optimal := {}
	for way: String in ["boom", "sea-lock", "punt"]:
		var b := _receiver("optimal " + way, way, Witness.p0_way("low", way), Witness.PORT_CELLS.low[way][2], probe)
		if b != null: optimal[way] = int(b.get_meta("ring_tick", b.tick)) - int(b.get_meta("waited", 0))
	var boom: Array = [["w",[192,-368]],["w",[96,-368]],["w",[96,352]],["w",[-212,352]],["w",[-212,-368]],["w",[-500,-368]],["?","boom-shut"],
		["w",[-212,-368]],["w",[-212,352]],["w",[96,352]],["w",[96,-368]],["w",WEST],T,T,["w",[-500,-368]],["u","route:boom-jetty"],["w",WEST],T,["w",[-828,-368]],["w",[-828,-26]],T]
	var sea: Array = [["w",[192,-368]],T,T,["w",[-212,-368]],["w",[-212,0]],["w",[-500,0]],["?","gate-shut"],["w",[-212,0]],["w",[-212,-368]],["w",WEST],T,T,
		["w",[132,-368]],["w",[132,0]],["w",[-500,0]],["u","route:sea-gate-in"],["w",[132,0]],["w",[132,-368]],["w",WEST],T,
		["w",[132,-368]],["w",[132,26]],["w",[-600,26]],T,T,["u","route:sea-gate-out"],["w",[-832,26]],T]
	var punt: Array = [["w",[192,-368]],T,["w",[132,-368]],["w",[132,-116]],["w",[208,-116]],["?","race-shut"],["w",[132,-116]],["w",[132,-368]],["w",WEST],T,T,
		["w",[132,-368]],["w",[132,-116]],["w",[208,-116]],["w",[208,-140]],T,["w",[208,-116]],["w",[132,-116]],["w",[132,-368]],["w",WEST],T,
		["w",[132,-368]],["w",[132,52]],["w",[-212,52]],["w",[-212,300]],["w",[-500,300]],["u","route:punt-ferry"],["w",[-828,300]],["w",[-828,26]],T]
	for item: Array in [["boom", boom, 3], ["sea-lock", sea, 7], ["punt", punt, 5]]:
		var b := _receiver("wrong order " + item[0], item[0], item[1], item[2], probe)
		if b == null or not optimal.has(item[0]): continue
		var ticks := int(b.get_meta("ring_tick", b.tick)) - int(b.get_meta("waited", 0))
		var ratio := float(ticks) / float(optimal[item[0]])
		_check(ratio > 1.2, "LOW %s: the wrong order costs p0 %.2fx (%d vs %d ticks)" % [item[0], ratio, ticks, optimal[item[0]]])
		print("TIDE LOW %s wrong order p0=%d optimal=%d ratio=%.2f presses=%d" % [item[0], ticks, optimal[item[0]], ratio, Witness.count_presses(b)])

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
