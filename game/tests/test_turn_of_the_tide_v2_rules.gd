extends SceneTree
## turn-of-the-tide@2 on the tide rules (core/journey/simulation.gd
## TIDE_RULES_VERSION), played with real inputs:
## - the definition pins rules 10, keeps no crossing on entry and closes in
##   `closing_ticks`; @1 still plays rules 9 with none of it;
## - every Set the Tide pair of @1 still finishes (V2.BROKEN_PAIRS lists any that do not);
## - all nine Slack Water cells finish from the three stage-one ends, and no
##   checkpoint keeps a route;
## - every Slack Water start pose stands on open floor at its first tick;
## - a crossing closes 45 ticks after its gate stops holding, a spirit still on
##   it drowns (the live one or the memory), one that steps off in time does
##   not, a gate that holds again inside the window never shuts, and a memory
##   walking onto a crossing already shut drowns at once;
## - the drowned lines read "you", "your friend", or solo "your memory";
## - the removed settled-source @2 is retired.
const KEY := "turn-of-the-tide@2"
const Registry = preload("res://services/chapter_registry.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Tide = preload("res://tests/turn_of_the_tide_witness.gd")
const V2 = preload("res://tests/turn_of_the_tide_v2_witness.gd")
const Journey = preload("res://services/relay_journey.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SET := "set-the-tide"
const SLACK := "slack-water"
## From the beach start to the middle of the sand bar (x -128..0, z 288..416).
const ON_THE_BAR := [["w", [-320, 352]], ["w", [-60, 352]]]
const REMOVED_V2 := "df0c4209c74b93d547cc5cdc8ca049944f810fbce42dccc6e57e305122de390c"
var checks := 0
var failures := 0
var level: Dictionary = {}
var initial: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	level = Registry.definition(KEY)
	initial = Registry.initial_checkpoint(KEY)
	var digest := Canonical.digest(level)
	_definition()
	var ends := _stage_one()
	_starts(ends)
	_stage_two(ends)
	_closing_and_drowning()
	_memory_drowns(ends.get("low", {}))
	_lines()
	_check(Canonical.digest(Registry.definition(KEY)) == digest, "Playing never changes the definition")
	print("TURN OF THE TIDE V2 RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _definition() -> void:
	var earlier := Registry.definition("turn-of-the-tide@1")
	_check(int(level.simulation_version) == Simulation.TIDE_RULES_VERSION and Registry.supported_rules(KEY) == [10], "@2 pins the tide rules (10) and plays nothing else")
	_check(int(earlier.simulation_version) == 9 and Registry.supported_rules("turn-of-the-tide@1") == [9], "@1 still pins rules 9")
	_check(int(level.closing_ticks) == 45 and not earlier.has("closing_ticks"), "A closing crossing keeps its floor 45 ticks in @2 only")
	for stage: Dictionary in level.stages:
		_check(stage.entry_latch_routes.is_empty(), "No crossing in %s is kept on entry" % stage.id)
	_check(REMOVED_V2 in Journey.RETIRED_DEFINITIONS.get(KEY, []) and Canonical.digest(level) not in Journey.RETIRED_DEFINITIONS.get(KEY, []), "The removed settled-source @2 is retired and this one is not")
	# @1 on rules 9: no closing state, no drowning, kept routes as published.
	var old := Simulation.new()
	old.reset(earlier, SET, Registry.initial_checkpoint("turn-of-the-tide@1"), {}, "a")
	old.step({})
	var snap: Dictionary = old.snapshot()
	_check(not snap.has("drowned") and not snap.route_progress.has("closing") and not old._state_body().has("closing"), "@1 snapshots and state carry nothing of the tide rules")

## Every @1 stage-one pair; returns the three main ends' checkpoints by history.
func _stage_one() -> Dictionary:
	var ends: Dictionary = {}
	for name: String in Tide.PAIRS:
		var spec: Array = Tide.PAIRS[name]
		var played := V2.pair(level, SET, initial, Tide.a_routes()[spec[0]], Tide.b_routes()[spec[1]])
		if V2.BROKEN_PAIRS.has(name):
			_check(not played.error.is_empty(), "%s no longer finishes: it %s (%s)" % [name, V2.BROKEN_PAIRS[name], played.error])
			continue
		_check(played.error.is_empty(), "Set the Tide %s still finishes on the tide rules: %s" % [name, played.error])
		if not played.error.is_empty(): continue
		_check(played.checkpoint.mechanisms.latched_bridges.is_empty(), "%s keeps no route for Slack Water" % name)
		if name in ["low", "half", "high"]: ends[name] = played.checkpoint
	return ends

## Each stage-one end's Slack Water start: both spirits stand on open floor,
## and a first tick of either turn drowns nobody.
func _starts(ends: Dictionary) -> void:
	for history: String in ends:
		var a := Simulation.new()
		_check(a.reset(level, SLACK, ends[history], {}, "a"), "Slack Water starts after %s" % history)
		for slot: String in ["p0", "p1"]:
			var surface := str(a._players[slot].surface_id)
			_check(not a._routes.has(surface) or bool(a._routes[surface]), "After %s, %s starts on open floor (%s)" % [history, slot, surface])
		a.step({})
		_check(a.snapshot().drowned.is_empty() and not a.finished, "After %s, the first tick drowns nobody" % history)

func _stage_two(ends: Dictionary) -> void:
	for history: String in ends:
		for way: String in ["boom", "sea-lock", "punt"]:
			var played := V2.pair(level, SLACK, ends[history], Tide.p1_route(ends[history], way), V2.p0_way(history, way))
			_check(played.error.is_empty(), "Slack Water %s/%s finishes on the tide rules: %s" % [history, way, played.error])
			if played.error.is_empty():
				_check(played.checkpoint.mechanisms.latched_bridges.is_empty() and played.checkpoint.stage_index == 2, "%s/%s ends the chapter keeping no route" % [history, way])

## Stage one, the LOW memory turning the tide while the second spirit stands
## on the sand bar.
func _closing_and_drowning() -> void:
	var a := _source(Tide.a_routes()["low"])
	var first: Dictionary = a.export_recording()
	# Stays on sand-1: the memory's first turn closes it, 45 ticks later it shuts.
	var b := _receiver(first)
	Tide.play(b, ON_THE_BAR)
	var closed_at := -1
	while not b.finished:
		b.step({})
		if b._events.has("closing:sand-1") and closed_at < 0: closed_at = int(b.tick) - 1
	var drowned: Dictionary = b.snapshot().drowned
	_check(closed_at > 0 and drowned.get("slot") == "p1" and drowned.get("route") == "sand-1" and int(drowned.tick) == closed_at + 45, "Left on the sand bar, the second spirit drowns 45 ticks after it starts closing (%s, closing at %d)" % [str(drowned), closed_at])
	_check(not b.can_commit() and not b.complete and b.commit_reason() == Simulation.DROWNED_YOU and b.export_recording().outcome.keys() == ["source_ready", "objective_complete"], "A drowned turn cannot be saved, says so, and records the usual outcome")
	_check(Simulation.verify_recording(level, Tide.json(b.export_recording()), Tide.json(initial), Tide.json(first)).valid, "The drowned turn replays exactly (Retry and Preview see the same ending)")
	# Steps off as soon as it starts closing.
	var c := _receiver(first)
	Tide.play(c, ON_THE_BAR)
	while not c.finished and not c._events.has("closing:sand-1"): c.step({})
	for _tick in range(30): c.step({"move_x": -1.0})
	for _tick in range(60): c.step({})
	_check(c.snapshot().drowned.is_empty() and str(c._players.p1.surface_id) == "w-beach", "Stepping off inside the 45 ticks is safe")
	# The memory turns low -> half -> high -> low at once, then waits: the bar
	# holds again inside the window and never shuts.
	var quick: Array = Tide.a_routes()["low"].slice(0, Tide.APPROACH.size()) + [Tide.T, Tide.T, Tide.T, ["n", 90]] + Tide.a_routes()["low"].slice(Tide.APPROACH.size())
	var d := _receiver(_source(quick).export_recording())
	Tide.play(d, ON_THE_BAR)
	var first_close := -1
	while not d.finished and (first_close < 0 or int(d.tick) <= first_close + 60):
		d.step({})
		if first_close < 0 and d._events.has("closing:sand-1"): first_close = int(d.tick) - 1
	_check(first_close > 0 and d.snapshot().drowned.is_empty() and bool(d._routes["sand-1"]) and not d._closing.has("sand-1"), "A gate that holds again inside the window keeps the crossing open (closing at %d)" % first_close)

## Stage two after LOW: p0 turns the tide while its memory walks home over
## the slipway and the sand bar.
func _memory_drowns(low_end: Dictionary) -> void:
	if low_end.is_empty():
		_check(false, "Slack Water after LOW is reachable")
		return
	var a := Simulation.new()
	a.reset(level, SLACK, low_end, {}, "a")
	Tide.play(a, Tide.p1_route(low_end, "sea-lock"))
	_check(a.can_commit(), "The memory's Slack Water turn commits")
	var first: Dictionary = a.export_recording()
	var b := Simulation.new()
	b.reset(level, SLACK, low_end, first, "b")
	Tide.play(b, [["w", Tide.WHEEL["low"]], Tide.T])
	while not b.finished: b.step({})
	var drowned: Dictionary = b.snapshot().drowned
	_check(drowned.get("slot") == "p1" and drowned.get("route") in ["slipway", "sand-1"] and b.commit_reason() == Simulation.DROWNED_FRIEND, "Turning the tide under the memory drowns it on its crossing (%s)" % str(drowned))

func _lines() -> void:
	_check(PlayerCopy.from_canonical(Simulation.DROWNED_YOU) == PlayerCopy.JOURNEY_DROWNED_YOU and PlayerCopy.from_canonical(Simulation.DROWNED_YOU, true) == PlayerCopy.JOURNEY_DROWNED_YOU, "The player's own drowning reads the same online and solo")
	_check(PlayerCopy.from_canonical(Simulation.DROWNED_FRIEND) == PlayerCopy.JOURNEY_DROWNED_FRIEND and PlayerCopy.from_canonical(Simulation.DROWNED_FRIEND, true) == PlayerCopy.JOURNEY_DROWNED_MEMORY, "The memory's drowning says your friend online and your memory solo")
	var hint: String = level.stages[1].hint_b
	_check(PlayerCopy.from_canonical(hint) == PlayerCopy.TURN_OF_THE_TIDE_V2_SLACK_HINT_B and PlayerCopy.from_canonical(hint, true) == PlayerCopy.TURN_OF_THE_TIDE_V2_SLACK_HINT_B_SOLO, "Slack Water's hint names your friend online and your memory solo")

func _source(ops: Array) -> Simulation:
	var a := Simulation.new()
	a.reset(level, SET, initial, {}, "a")
	Tide.play(a, ops)
	_check(a.can_commit(), "The stage-one memory commits")
	return a

func _receiver(first: Dictionary) -> Simulation:
	var b := Simulation.new()
	_check(b.reset(level, SET, initial, first, "b"), "The second turn starts beside the memory")
	return b

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
