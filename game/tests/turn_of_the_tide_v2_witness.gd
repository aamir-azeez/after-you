extends "res://tests/chapter_witness.gd"
## turn-of-the-tide@2 played through with real inputs on the tide rules
## (simulation.gd TIDE_RULES_VERSION): @1's routes (turn_of_the_tide_witness.gd)
## where they still hold, and new tails where @1 leaned on a kept crossing.
##
## Set the Tide plays @1's pairs unchanged, and all of them still finish: even
## high-early-sand is back over the sand bar before the memory first turns the
## tide. In Slack Water the second spirit
## first waits on its step until the memory is past its last tide crossing
## ("?" "home"), so no tide turn catches it, then plays its way: the boom over
## the high jetties onto the mole and down the steps the outer sea opens, the
## sea lock as a real lock (in at the harbour's level, out at the sea's), and
## the punt as in @1.
const KEY := "turn-of-the-tide@2"
const Tide = preload("res://tests/turn_of_the_tide_witness.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const T := ["t"]
## Stage-1 pairs that no longer finish, and why (none today).
const BROKEN_PAIRS := {}
## From the quay at high water: over the jetty run to the boom jetty's mouth,
## onto the mole once the boom holds, down the steps and to the lantern.
const BOOM_TAIL := [["d",[104,-304]],["w",[-500,-304]],["u","route:boom-jetty"],["w",[-708,-304]],["d",[-840,-236]],["w",[-840,-24]],T]
## From the quay at half water: down the ladder, over the stones to the sea
## gate, into the chamber while it matches the harbour, the chamber turned
## high then low to meet the sea, and out onto the mole.
const SEA_TAIL := [["d",[64,-236]],["w",[64,-116]],["d",[-500,-48]],["u","route:sea-gate-in"],["d",[-596,36]],T,T,["u","route:sea-gate-out"],["d",[-820,20]],T]
## How far west the memory has to be before the tide may turn: past sand-1,
## stones-1 and jetty-1 (x -128..0), its last tide crossings on the way home.
const HOME_X := -140
## Where p0 stands to reach the pin (quay step) and the key (bollard step).
const PIN_STAND := [64,-488]
const KEY_STAND := [320,-488]

func chapter() -> Dictionary:
	var level := Registry.definition(KEY)
	var checkpoint := Registry.initial_checkpoint(KEY)
	var result := {"definition": level, "checkpoints": [checkpoint], "pairs": [], "error": ""}
	var routes := [[Tide.a_routes()["low"], Tide.b_routes()["low"]], [Tide.p1_home("low") + p1_way("low", "sea-lock"), p0_way("low", "sea-lock")]]
	for index in range(level.stages.size()):
		var played := pair(level, str(level.stages[index].id), checkpoint, routes[index][0], routes[index][1])
		if not played.error.is_empty():
			result.error = "%s: %s" % [level.stages[index].id, played.error]
			return result
		result.pairs.append({"a": played.a, "b": played.b})
		checkpoint = played.checkpoint
		result.checkpoints.append(checkpoint)
	return result

## Stage 2, p1. The posts stand in one row on the west terrace's south edge
## (the v2 catalog's ROW_*); the bar catwalks, chains and basin wheel are
## @1's. Stands 2 cm inside each reach radius (levers 28, post pads 16), each
## stub entered straight from the terrace front in front of it (z -112 north,
## 116 south). The way home is @1's.
const GATE_BAR_FRONT := [-328,-112]
const POSTS := {"sea-lock": [-416,148], "boom": [-344,148], "punt": [-272,148]}

static func _sea(from: String, to: String) -> Array:
	return [["d",Tide.BASIN_STAND]] + Tide._taps(Tide.sea_presses(from, to))

static func _gate_bar() -> Array:
	return [["d",GATE_BAR_FRONT],["w",Tide.GATE_BAR],T,["w",GATE_BAR_FRONT]]

static func _sea_bar() -> Array:
	return Tide._sea_bar()

static func _post(way: String) -> Array:
	return [["d",[POSTS[way][0],116]],["w",POSTS[way]]]

## The beach chain from wherever the way comes down to the beach front, and
## back up the west steps to the terrace.
static func _beach_chain(down: Array) -> Array:
	return down + [["w",Tide.BEACH_CHAIN],T,["w",[Tide.BEACH_CHAIN[0],116]]]

## The quay chain from a stand on its lane, and back down to the terrace.
static func _quay_chain(lane: Array) -> Array:
	return lane + [["w",Tide.QUAY_CHAIN],T] + Tide.QUAY_DOWN

## p1's plan per cell, in @1's order: the shut-sea moorings before the sea
## first turns, the gate bar at slack (the sea at the history's tide), then
## the way's mark and its post.
static func p1_way(tide: String, way: String) -> Array:
	match tide + "/" + way:
		"low/boom": return _beach_chain([["w",[Tide.BEACH_CHAIN[0],388]]]) + _sea("shut","low") + _gate_bar() + _sea("low","half") + _post(way)
		"low/sea-lock": return [["w",[-164,388]],["w",[-164,116]]] + _sea_bar() + _sea("shut","low") + _gate_bar() + _post(way)
		"low/punt": return _quay_chain([["w",[Tide.QUAY_CHAIN[0],388]]]) + _sea_bar() + _sea("shut","high") + _post(way)
		"half/boom": return _beach_chain([["w",[-140,40]],["d",[Tide.BEACH_CHAIN[0],64]]]) + _sea("shut","half") + _gate_bar() + _post(way)
		"half/sea-lock": return [["w",[-140,40]]] + _sea("shut","half") + _gate_bar() + _sea("half","shut") + _sea_bar() + _sea("shut","low") + _post(way)
		"half/punt": return _quay_chain([["w",[-100,40]],["d",[Tide.QUAY_CHAIN[0],-40]]]) + _sea_bar() + _sea("shut","high") + _post(way)
		"high/boom": return _beach_chain([["w",[Tide.BEACH_CHAIN[0],-304]]]) + _sea("shut","high") + _gate_bar() + _sea("high","half") + _post(way)
		"high/sea-lock": return [["w",[-180,-304]]] + Tide.QUAY_DOWN.slice(1) + _sea_bar() + _sea("shut","high") + _gate_bar() + _sea("high","low") + _post(way)
		"high/punt": return _quay_chain([["d",[1276,-400]],["w",[Tide.QUAY_CHAIN[0],-400]]]) + _sea_bar() + _sea("shut","high") + _post(way)
	return []

## The wrong order: the sea wheel turned before any mooring (shut to the
## history's tide), then the cheapest recovery, as in @1
## (Tide.p1_way_sea_first). The probes mark where a mooring is found flooded.
static func p1_way_sea_first(tide: String, way: String) -> Array:
	var terrace: Array = {"low": [["w",[-164,388]],["w",[-164,116]]], "half": [["w",[-140,40]]], "high": [["w",[-180,-304]]] + Tide.QUAY_DOWN.slice(1)}[tide]
	match way:
		"boom": return terrace + _sea("shut",tide) + _gate_bar() + [["?","catwalk-shut"]] + _sea(tide,"shut") + _beach_chain([["d",[Tide.BEACH_CHAIN[0],116]]]) + _sea("shut","half") + _post(way)
		"sea-lock": return terrace + _sea("shut",tide) + _gate_bar() + [["?","bar-shut"]] + _sea(tide,"shut") + _sea_bar() + _sea("shut","low") + _post(way)
	return terrace + _sea("shut","low") + [["?","bar-shut"]] + _quay_chain([["d",[Tide.QUAY_CHAIN[0],-119]]]) + _sea("low","shut") + _sea_bar() + _sea("shut","high") + _post(way)

## Every mooring made fast (beach chain, quay chain and sea bar while the sea
## is shut, the gate bar at slack), then the way's mark and its post.
static func p1_all_chains(tide: String, way: String) -> Array:
	var chains: Array = [["w",Tide.BEACH_CHAIN],T,["w",[Tide.QUAY_CHAIN[0],-468]],["w",Tide.QUAY_CHAIN],T] + Tide.QUAY_DOWN
	if tide == "high": chains = [["w",Tide.QUAY_CHAIN],T,["w",[Tide.BEACH_CHAIN[0],-468]],["w",Tide.BEACH_CHAIN],T,["w",[Tide.BEACH_CHAIN[0],116]]]
	var down: Array = {"low": [["w",[Tide.BEACH_CHAIN[0],388]]], "half": [["w",[-140,40]],["d",[Tide.BEACH_CHAIN[0],64]]], "high": [["w",[Tide.QUAY_CHAIN[0],-304]]]}[tide]
	return down + chains + _sea_bar() + _sea("shut",tide) + _gate_bar() + ([] if Tide.WAY_SEA[way] == tide else _sea(tide, Tide.WAY_SEA[way])) + _post(way)

## p1's whole Slack Water turn after any stage-one end state.
static func p1_route(checkpoint: Dictionary, way: String) -> Array:
	var tide := str(checkpoint.mechanisms.controls.tide)
	return Tide.p1_home(tide) + p1_way(tide, way)

## Stage 2, p0 for one history and way: wait for the memory, then the way.
## The pin hangs on the quay step (open at low) and the key on the bollard
## step (open at half); a p0 that starts on one of them pulls it at once.
static func p0_way(history: String, way: String) -> Array:
	var lane: Array = [["w",[Tide.STEP[history][0],Tide.LANE]]]
	var home: Array = [["?","home"]]
	var pin: Array = Tide._fetch(PIN_STAND)
	var key: Array = Tide._fetch(KEY_STAND)
	match history + "/" + way:
		# Low: the pin first, then the harbour up to high for the jetties.
		"low/boom": return home + lane + pin + [["d",Tide.WHEEL_NE],T,T] + BOOM_TAIL
		# Half: the pin hangs on p0's own step.
		"half/boom": return home + [T] + lane + [["d",Tide.WHEEL_NE],T] + BOOM_TAIL
		# High: down to low for the pin, then back up to high.
		"high/boom": return home + lane + [["d",Tide.WHEEL_NE],T] + pin + [["d",Tide.WHEEL_NE],T,T] + BOOM_TAIL
		# Low: up to half for the key, then in at half.
		"low/sea-lock": return home + lane + [["d",Tide.WHEEL_NE],T] + key + SEA_TAIL
		"half/sea-lock": return home + lane + key + SEA_TAIL
		# High: the key hangs on p0's own step; then round to half.
		"high/sea-lock": return home + [T] + lane + [["d",Tide.WHEEL_NE],T,T] + SEA_TAIL
		_: return home + Tide.p0_way(history, way)

## "?" "home": steps on until the memory is past its last tide crossing.
static func home_probe() -> Callable:
	return func(name: String, sim: RefCounted) -> void:
		if name != "home": return
		while int(sim._players[sim.first_player_slot].x) >= HOME_X and not sim.finished and sim.error.is_empty(): sim.step({})

## One stage on the tide rules: the source turn, the receiver beside it (run
## out to the memory's end), and the derived checkpoint.
## {"error", "a_sim", "b_sim", "a", "b", "checkpoint"}.
static func pair(level: Dictionary, stage_id: String, checkpoint: Dictionary, a_ops: Array, b_ops: Array) -> Dictionary:
	var result := {"error": ""}
	var a := Simulation.new()
	result.a_sim = a
	if not a.reset(level, stage_id, checkpoint, {}, "a"):
		result.error = "A refused: " + a.error
		return result
	var why := Tide.play(a, a_ops, home_probe())
	if not why.is_empty() or not a.can_commit():
		result.error = "A: %s %s %s" % [why, a.error, a.commit_reason()]
		return result
	var first: Dictionary = a.export_recording()
	var b := Simulation.new()
	result.b_sim = b
	if not b.reset(level, stage_id, checkpoint, first, "b"):
		result.error = "B refused: " + b.error
		return result
	why = Tide.play(b, b_ops, home_probe())
	for _tick in range(b.duration_limit()):
		if b.finished or not b._objective: break
		b.step({})
	if not why.is_empty() or not b.complete:
		result.error = "B: %s %s complete=%s drowned=%s" % [why, b.commit_reason(), str(b.complete), str(b.snapshot().get("drowned", {}))]
		return result
	result.a = first
	result.b = b.export_recording()
	var derived := Simulation.derive_checkpoint(level, Tide.json(checkpoint), Tide.json(first), Tide.json(result.b))
	if not derived.valid:
		result.error = "derive: " + str(derived.get("error", ""))
		return result
	result.checkpoint = derived.checkpoint
	return result
