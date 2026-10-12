extends SceneTree
## turn-of-the-tide@1 stage-two limits with real inputs under rules 9 (spec
## 4.3, 4.5, 11.4, 11.6, 11.7 and the stage-2 fix 3-5): a slow p1 at 1.3x
## still commits in every cell; turning the sea before the moorings costs p1
## extra presses; the wrong order costs p0 presses and ticks; entry latches
## keep exactly what p0 touched; and p1's "not ready" reason.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/turn_of_the_tide_witness.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const T := ["t"]
const WEST := [172,-368]
## Stage-2 fix 5.6: p1's margin to the deadline at 1.3x its optimum.
const PORT_MARGIN_SLOW := {"low": {"boom": 102, "sea-lock": 27, "punt": 22}, "half": {"boom": 83, "sea-lock": 136, "punt": 120}, "high": {"boom": 8, "sea-lock": 50, "punt": 131}}
## The boom with the sea turned first (fix 3, verifier): p1's presses, natural then wrong.
const SEA_FIRST_PRESSES := {"low": [4, 8], "half": [5, 9], "high": [8, 8]}
const PORT_SEA_FIRST_RATIO := {"low": 1.35, "high": 1.04}
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

## p1 at slack with the gate bar pulled but off any post is not ready yet.
func _not_ready() -> void:
	var ops: Array = Witness.p1_home("low") + [["w",[-164,388]],["w",[-164,116]]] + Witness._sea("shut", "low") + Witness._gate_bar() + [["w",[-328,-112]], ["n", 10]]
	var p1 := Witness.source(level, Witness.SLACK, starts.low, ops, 0, Callable(), true)
	_check(p1.error.is_empty() and str(p1.get_meta("route_error")) == "" and p1._mechanisms.levers.get("gate-bar", false) and not p1.can_commit(), "The bar alone, off the post, is not ready")
	_check(p1.commit_reason() == "Keep the crossing ready for your partner.", "Not on a post shows the generic reason (%s)" % p1.commit_reason())

## Fix 3 and 11.4: the sea turned before any mooring floods the beach stub;
## the sea has to go round to shut again. p1 pays the presses, still
## commits, and p0 still wins.
func _sea_first() -> void:
	for history: String in starts:
		var probe := func(name: String, sim: RefCounted) -> void:
			if name == "catwalk-shut":
				_check(not sim._routes["beach-catwalk"] and str(sim._mechanisms.controls.basin) != "shut", history.to_upper() + ": with the sea turned first, the beach catwalk is flooded")
		var natural := Witness.source(level, Witness.SLACK, starts[history], Witness.p1_home(history) + Witness.p1_way(history, "boom"), 0, Callable(), true)
		var pair := Witness.pair(level, Witness.SLACK, starts[history], Witness.p1_home(history) + Witness.p1_way_sea_first(history, "boom"), Witness.p0_way(history, "boom"), false, probe)
		_check(pair.error.is_empty(), "%s boom sea first recovers and p0 wins: %s" % [history.to_upper(), pair.error])
		if not pair.error.is_empty(): continue
		var presses: Array = SEA_FIRST_PRESSES[history]
		_check(Witness.count_presses(natural) == presses[0] and Witness.count_presses(pair.a_sim) == presses[1], "%s boom: turning the sea first takes p1 %d presses instead of %d (got %d and %d)" % [history.to_upper(), presses[1], presses[0], Witness.count_presses(pair.a_sim), Witness.count_presses(natural)])
		var ratio := float(pair.a.duration_ticks) / float(natural.tick)
		_check(ratio >= 1.0, "%s boom: the wrong order never saves p1 time (%.2fx)" % [history.to_upper(), ratio])
		print("PORT %s boom sea-first p1 ratio native=%.2f port=%s presses %d->%d" % [history.to_upper(), ratio, str(PORT_SEA_FIRST_RATIO.get(history, "-")), presses[0], presses[1]])

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
	var at := _find(sea, ["d",[-596,36]])
	sea.insert(at + 1, ["?", "inside"])
	sea.insert(at, ["?", "high-water"])
	_receiver("sea lock latches", "sea-lock", sea, Witness.PORT_CELLS.low["sea-lock"][2], probe)
	var boom := Witness.p0_way("low", "boom")
	boom.insert(_find(boom, ["u","route:boom-jetty"]) + 1, ["?", "boom-touch"])
	_receiver("boom touch", "boom", boom, Witness.PORT_CELLS.low.boom[2], probe)
	var tow: Array = [["w",[192,-368]],["w",[96,-368]],["w",[96,404]],["w",[300,404]],["?","towpath"],["w",[96,404]],["w",[96,-368]]] + Witness.p0_way("low", "punt").slice(1)
	var towed := _receiver("towpath detour", "punt", tow, 2, probe)
	if towed != null: _check("towpath" in towed.snapshot().route_progress.entered_routes, "The towpath latch is harmless: the punt still wins with its two presses")
	# The key first, then the chamber turned high at half water before raising the harbour.
	var free: Array = Witness.p0_way("low", "sea-lock").slice(0, 7) + [["w",[132,-368]],["w",[132,26]],["w",[-500,26]],["u","route:sea-gate-in"],["w",[-600,26]],T,["w",[132,26]],["w",[132,-368]],["w",WEST],T,
		["w",[132,-368]],["w",[132,26]],["w",[-520,26]],["?","match"],["w",[-600,26]],T,["u","route:sea-gate-out"],["w",[-832,26]],T]
	_receiver("sea lock, chamber first", "sea-lock", free, 5, probe)

## Fix 4 and 11.4: p0 in the wrong order recovers, at a real cost in presses
## and ticks. The boom raised before the pin finds the mole steps shut and
## cycles back to half (greedy's 7 presses); the sea lock without the key
## finds the exit shut and goes back for it at low (8); the punt raised first
## floods the race stage (5).
func _wrong_order() -> void:
	var probe := func(name: String, sim: RefCounted) -> void:
		match name:
			"pinless": _check(not sim._routes["mole-steps"] and not sim.walkable_at(-840, -200), "Without the pin the mole steps stay shut at low water")
			"keyless": _check(not sim._routes["sea-gate-out"] and str(sim._mechanisms.controls.chamber) == "low", "Without the key the sea gate stays shut with the chamber low")
			"race-shut": _check(not sim._routes["race-stage"] and not sim.walkable_at(208, -140), "Raised first, the race stage floods")
	var optimal := {}
	for way: String in ["boom", "sea-lock", "punt"]:
		var b := _receiver("optimal " + way, way, Witness.p0_way("low", way), Witness.PORT_CELLS.low[way][2], probe)
		if b != null: optimal[way] = int(b.get_meta("ring_tick", b.tick)) - int(b.get_meta("waited", 0))
	var boom: Array = [["w",[192,-378]],T,T,["d",[-500,-368]],["u","route:boom-jetty"],["w",WEST],T,["d",[104,-304]],["w",[-708,-304]],["d",[-840,-236]],["?","pinless"],
		["d",[-708,-304]],["w",[104,-304]],["d",Witness.WHEEL_LADDER],T,["d",[Witness.PIN_STAND[0],Witness.LANE]]] + Witness._fetch(Witness.PIN_STAND).slice(1) + [["d",Witness.WHEEL_NE],T,T] + Witness.MOLE_FROM_QUAY
	var sea: Array = [["w",[192,-378]],T] + Witness.LADDER_DOWN + [["d",[-500,-48]],["u","route:sea-gate-in"],["w",[12,-48]],["d",[64,-116]]] + Witness.LADDER_UP + [T] + Witness.LADDER_DOWN + \
		[["d",[-596,36]],T,T,["?","keyless"],["w",[12,36]],["d",[64,-116]]] + Witness.LADDER_UP + [T,["d",[Witness.KEY_STAND[0],Witness.LANE]]] + Witness._fetch(Witness.KEY_STAND).slice(1) + \
		[["d",Witness.WHEEL_NW],T,T] + Witness.LADDER_DOWN + [["d",[-596,36]],["u","route:sea-gate-out"],["d",[-820,20]],T]
	var punt: Array = [["w",[192,-368]],T,["w",[132,-368]],["w",[132,-116]],["w",[208,-116]],["?","race-shut"],["w",[132,-116]],["w",[132,-368]],["w",WEST],T,T,
		["w",[132,-368]],["w",[132,-116]],["w",[208,-116]],["w",[208,-140]],T,["w",[208,-116]],["w",[132,-116]],["w",[132,-368]],["w",WEST],T,
		["w",[132,-368]],["w",[132,52]],["w",[-212,52]],["w",[-212,300]],["w",[-500,300]],["u","route:punt-ferry"],["w",[-828,300]],["w",[-828,26]],T]
	for item: Array in [["boom", boom, 7], ["sea-lock", sea, 8], ["punt", punt, 5]]:
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
