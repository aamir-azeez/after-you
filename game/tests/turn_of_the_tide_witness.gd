extends RefCounted
## Real input routes for turn-of-the-tide@1. No state injection.
## "w" walks x then z, "t" taps the action, "n" waits, "?" calls the probe,
## "u" waits for a condition ("route:<id>", "lever:<id>", "control:<id>=<value>").
## play() stops at the first walk that makes no progress and returns why.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Walk = preload("res://tests/cooperative_witness.gd")
const KEY := "turn-of-the-tide@1"
const SET := "set-the-tide"
const SLACK := "slack-water"
const RULES := 9
const STUCK_TICKS := 3
const T := ["t"]

## Figures from the design's scratch ports (spec sections 3, 4.5, 6). Budgets
## and presses are exact; ticks are axis-walk upper bounds at 2 ticks a press.
const PORT_STAGE_ONE := {
	"budget": {"low": 460, "half": 418, "high": 494},
	"deadline": {"low": 739, "half": 781, "high": 705},
	"a_ticks": {"low": 462, "low-half-first": 618, "half": 464, "half-via-high": 454, "high": 418},
	"b_real": {"low": 330, "half": 288, "high": 364},
}
## history -> way -> budget, deadline (latest hold_start), p0 presses, p0 real
## ticks, p1 presses and p1 optimum ticks.
const PORT_CELLS := {
	"low": {"boom": [514,685,3,384,4,435], "sea-lock": [610,589,4,478,2,366], "punt": [548,651,2,414,3,428]},
	"half": {"boom": [530,669,2,398,5,347], "sea-lock": [626,573,3,468,7,303], "punt": [564,635,4,434,4,298]},
	"high": {"boom": [530,669,1,396,4,356], "sea-lock": [626,573,5,496,6,361], "punt": [564,635,3,432,7,406]},
}

## Stage 1, A (p0). From the beach start over sand-1 at low water, up the
## mill steps and the ladder to the tide wheel on the mill quay.
const APPROACH := [["w",[-320,352]],["w",[96,352]],["w",[96,-352]],["w",[192,-352]]]

static func a_routes() -> Dictionary:
	return {
		# Raise it to reach, lower it to use: high, winch to SLIP, sluice, back, low, wheel step.
		"low": APPROACH + [T,T,["w",[624,-448]],T,["w",[720,-448]],["w",[720,96]],T,["w",[720,-352]],["w",[192,-352]],T,["w",[192,-512]]],
		# The same plan through half water first: stones, sluice, winch, stones, then high and low.
		"low-half-first": APPROACH + [T,["w",[96,-352]],["w",[96,0]],["w",[720,0]],["w",[720,96]],T,["w",[720,-352]],["w",[624,-448]],T,
			["w",[720,-448]],["w",[720,0]],["w",[96,0]],["w",[96,-352]],["w",[192,-352]],T,T,["w",[192,-512]]],
		# Keep the lock: half, down the ladder, sluice, back up to the quay step.
		"half": APPROACH + [T,["w",[96,-352]],["w",[96,0]],["w",[704,0]],["w",[704,96]],T,["w",[704,0]],["w",[96,0]],["w",[96,-352]],["w",[64,-512]]],
		# Half through high water: five presses, the sluice reached from the jetty.
		"half-via-high": APPROACH + [T,T,["w",[720,-352]],["w",[720,96]],T,["w",[720,-352]],["w",[192,-352]],T,T,["w",[64,-512]]],
		# Half with the winch-SLIP misplay.
		"half-winch": APPROACH + [T,["w",[96,-352]],["w",[96,0]],["w",[720,0]],["w",[720,96]],T,["w",[720,-352]],["w",[624,-448]],T,
			["w",[720,-448]],["w",[720,0]],["w",[96,0]],["w",[96,-352]],["w",[64,-512]]],
		# The spirit as the mooring line: high, the line, back to the bollard step.
		"high": APPROACH + [T,T,["w",[1088,-448]],T,["w",[1088,-352]],["w",[320,-512]]],
		# High with the sluice misplay.
		"high-sluice": APPROACH + [T,T,["w",[1088,-448]],T,["w",[1088,-352]],["w",[720,-352]],["w",[720,96]],T,["w",[720,-352]],["w",[320,-512]]],
	}

## Stage 1, B (p1), from (-320,416). Walkers stop as soon as a lever, wheel
## or bell is in reach and keep to the edge of each crossing's lane.
static func b_routes() -> Dictionary:
	return {
		# Sand bar early, the aqueduct, the spout once the sluice runs, the slipway at low + slip.
		"low": [["w",[-320,404]],["w",[96,404]],["w",[96,116]],["w",[320,116]],["w",[320,288]],["w",[560,288]],["u","lever:sluice"],["w",[604,288]],
			["w",[604,300]],["u","route:slipway"],["w",[1440,300]],["w",[1440,26]],T],
		# Low by the jetties in the high window, then east steps and boathouse steps to the slipway.
		"low-jetty": [["w",[-212,416]],["w",[-212,-326]],["u","route:jetty-1"],["w",[700,-326]],["w",[700,300]],["u","route:slipway"],["w",[1440,300]],["w",[1440,26]],T],
		# Stepping stones at half, B's own lock turned east, stones-3 at half + sluice.
		"half": [["w",[-212,416]],["w",[-212,52]],["u","route:stones-1"],["w",[856,52]],T,["w",[1120,52]],["u","route:stones-3"],["w",[1414,0]],T],
		# Half reached through high water: wait on the west terrace for the last half.
		"half-late": [["w",[-212,416]],["w",[-212,52]],["u","route:stones-3"],["w",[856,52]],T,["w",[1414,0]],T],
		# The sand bar at the first low water, then the stones from the mill side.
		"half-early-sand": [["w",[-320,404]],["w",[96,404]],["w",[96,52]],["u","route:stones-2"],["w",[856,52]],T,["w",[1120,52]],["u","route:stones-3"],["w",[1414,0]],T],
		# Jetties at high, B's gangway, jetty-3 while the spirit holds the bollard step.
		"high": [["w",[-212,416]],["w",[-212,-326]],["u","route:jetty-1"],["w",[1104,-326]],T,["u","route:jetty-3"],["w",[1414,-326]],["w",[1414,0]],T],
		# Over the sand bar early and back over the kept bar, then the jetties.
		"high-early-sand": [["w",[-320,404]],["w",[96,404]],["w",[-212,404]],["w",[-212,-326]],["u","route:jetty-1"],["w",[1104,-326]],T,["u","route:jetty-3"],
			["w",[1414,-326]],["w",[1414,0]],T],
		# High after the sluice misplay: the spout, boathouse and east steps, the gangway and jetty-3.
		"high-spout": [["w",[-320,404]],["w",[96,404]],["w",[96,116]],["w",[320,116]],["w",[320,288]],["w",[560,288]],["u","lever:sluice"],["w",[688,288]],
			["w",[688,-326]],["w",[1104,-326]],T,["u","route:jetty-3"],["w",[1414,-326]],["w",[1414,0]],T],
	}

## Stage-1 pairs: name -> [A route, B route, history].
const PAIRS := {
	"low": ["low","low","low"],
	"low-jetty": ["low","low-jetty","low"],
	"low-half-first": ["low-half-first","low","low"],
	"low-half-first-stones": ["low-half-first","half","low"],
	"half": ["half","half","half"],
	"half-early-sand": ["half","half-early-sand","half"],
	"half-via-high": ["half-via-high","half-late","half"],
	"half-winch": ["half-winch","half","half"],
	"high": ["high","high","high"],
	"high-early-sand": ["high","high-early-sand","high"],
	"high-sluice": ["high-sluice","high","high"],
	"high-spout": ["high-sluice","high-spout","high"],
}

## The three main histories for stage 2.
const HISTORIES := {"low": "low", "half": "half", "high": "high"}

## Stage 2, p1 (records first). Walk home under the frozen tide onto the
## west terrace.
static func p1_home(history: String) -> Array:
	match history:
		"low": return [["w",[1440,380]],["w",[-212,380]],["w",[-212,116]]]
		"half": return [["w",[1414,40]],["w",[904,40]],T]
		"high": return [["w",[1414,-300]],["w",[-212,-300]],["w",[-212,-116]]]
	return []

## Catwalk lever x, post pad x, and the side of w-terrace (-1 north, 1 south).
const WAY_STUBS := {"boom": [-340,-268,1], "sea-lock": [-340,-268,-1], "punt": [-484,-412,-1]}
const WAY_SEA := {"boom": "high", "sea-lock": "low", "punt": "half"}
const SEA := ["shut","low","half","high"]
## The basin wheel (-312,-64) is in reach from here.
const BASIN_STAND := [-296,-48]

static func sea_presses(from: String, to: String) -> int:
	return (SEA.find(to) - SEA.find(from) + SEA.size()) % SEA.size()

static func _taps(count: int) -> Array:
	var ops: Array = []
	for _i in range(count): ops.append(T)
	return ops

## Make slack, walk the way's catwalk and pull its chain, set the sea to the
## way's value, and stand on its post. `tide` is the history's frozen tide.
## The lever is in reach 6 cm onto its catwalk, the pad 18 cm onto its post;
## walking along the stubs keeps 116 cm from the terrace centre line.
static func p1_way(tide: String, way: String) -> Array:
	return [["w",BASIN_STAND]] + _taps(sea_presses("shut", tide)) + _chain_and_post(tide, way)

static func _chain_and_post(tide: String, way: String) -> Array:
	var stub: Array = WAY_STUBS[way]
	var side: int = stub[2]
	var ops: Array = [["w",[stub[0],134*side]],T,["w",[stub[0],116*side]]]
	if sea_presses(tide, WAY_SEA[way]) > 0: ops.append_array([["w",BASIN_STAND]] + _taps(sea_presses(tide, WAY_SEA[way])))
	ops.append(["w",[stub[1],146*side]])
	return ops

## The wrong order: set the sea first and find the catwalk shut, then make
## slack again, pull the chain and set the sea once more.
static func p1_way_sea_first(tide: String, way: String) -> Array:
	var stub: Array = WAY_STUBS[way]
	var ops: Array = [["w",BASIN_STAND]] + _taps(sea_presses("shut", WAY_SEA[way]))
	ops.append_array([["w",[stub[0],116*int(stub[2])]],["?","catwalk-shut"],["w",BASIN_STAND]] + _taps(sea_presses(WAY_SEA[way], tide)))
	return ops + _chain_and_post(tide, way)

## Every chain pulled (punt, gate, boom), then the sea set to the way's value
## and its post held: the other ways open while the sea passes their values.
static func p1_all_chains(tide: String, way: String) -> Array:
	var ops: Array = [["w",BASIN_STAND]] + _taps(sea_presses("shut", tide))
	ops.append_array([["w",[-484,-134]],T,["w",[-484,-116]],["w",[-340,-134]],T,["w",[-340,-116]],["w",[-340,134]],T,["w",[-340,116]]])
	var stub: Array = WAY_STUBS[way]
	if sea_presses(tide, WAY_SEA[way]) > 0: ops.append_array([["w",BASIN_STAND]] + _taps(sea_presses(tide, WAY_SEA[way])))
	ops.append(["w",[stub[1],146*int(stub[2])]])
	return ops

## Stage 2, p0 (plays beside the replay). Start on its stage-1 step, then
## stand in reach of the tide wheel (192,-352) on the quay lane z=-368.
const STEP := {"low": [192,-512], "half": [64,-512], "high": [320,-512]}
const WHEEL := {"low": [192,-368], "half": [172,-368], "high": [212,-368]}
const WHEEL_WEST := [172,-368]
const TIDE := ["low","half","high"]

static func tide_presses(from: String, to: String) -> int:
	return (TIDE.find(to) - TIDE.find(from) + TIDE.size()) % TIDE.size()

static func _turn(from: String, to: String) -> Array:
	return _taps(tide_presses(from, to))

## The scripted optimal p0 for each way after each history. The wheel is
## visited first only when the way's first tide needs a press. Touches keep a
## crossing with a radius sample; the walker never needs to stand on it.
const FIRST_TIDE := {"boom": "high", "sea-lock": "half", "punt": "low"}

static func p0_way(history: String, way: String) -> Array:
	var ops: Array = [["w",[STEP[history][0],-368]]]
	var x: int = STEP[history][0]
	if tide_presses(history, FIRST_TIDE[way]) > 0:
		ops.append_array([["w",WHEEL[history]]] + _turn(history, FIRST_TIDE[way]))
		x = WHEEL[history][0]
	# The mill ladder's walkable lane is x 60..132.
	var ladder := clampi(x, 60, 132)
	match way:
		"boom":
			ops.append_array([["w",[-500,-368]],["u","route:boom-jetty"],["w",WHEEL_WEST]])
			ops.append_array(_turn("high","low"))
			ops.append_array([["w",[-828,-368]],["w",[-828,-26]],T])
		"sea-lock":
			ops.append_array([["w",[ladder,-368]],["w",[ladder,0]],["w",[-500,0]],["u","route:sea-gate-in"],["w",[132,0]],["w",[132,-368]],["w",WHEEL_WEST]])
			ops.append_array(_turn("half","high"))
			ops.append_array([["w",[132,-368]],["w",[132,26]],["w",[-600,26]],T,T,["u","route:sea-gate-out"],["w",[-832,26]],T])
		"punt":
			ops.append_array([["w",[ladder,-368]],["w",[ladder,-116]],["w",[208,-116]],["w",[208,-140]],T,["w",[208,-116]],["w",[132,-116]],["w",[132,-368]],["w",WHEEL_WEST]])
			ops.append_array(_turn("low","half"))
			ops.append_array([["w",[132,-368]],["w",[132,52]],["w",[-212,52]],["w",[-212,300]],["w",[-500,300]],["u","route:punt-ferry"],["w",[-828,300]],["w",[-828,26]],T])
	return ops

## `trusted` skips re-verifying a checkpoint and partner recording that this
## suite already derived; the turn itself still plays the real simulation.
static func source(level: Dictionary, stage_id: String, checkpoint: Dictionary, ops: Array, delay: int = 0, probe: Callable = Callable(), trusted: bool = false) -> RefCounted:
	var sim := _start(level,stage_id,checkpoint,{},"a",trusted)
	if not sim.error.is_empty(): return sim
	Walk.wait_ticks(sim,delay)
	sim.set_meta("route_error", play(sim,ops,probe))
	return sim

static func receiver(level: Dictionary, stage_id: String, checkpoint: Dictionary, first: Dictionary, ops: Array, probe: Callable = Callable(), trusted: bool = false) -> RefCounted:
	var sim := _start(level,stage_id,checkpoint,first,"b",trusted)
	if not sim.error.is_empty(): return sim
	sim.set_meta("route_error", play(sim,ops,probe))
	# A fast receiver still waits out the recorded source.
	for _tick in range(Simulation.MAX_TICKS+300):
		if sim.finished or not sim._objective: break
		sim.step({})
	return sim

static func _start(level: Dictionary, stage_id: String, checkpoint: Dictionary, first: Dictionary, role: String, trusted: bool) -> RefCounted:
	var sim := Simulation.new()
	sim.set_meta("route_error", "")
	if trusted:
		sim.simulation_version = RULES
		sim._reset_trusted(level,stage_id,checkpoint,first,role)
	elif not sim.reset(level,stage_id,checkpoint,first,role,RULES):
		sim.set_meta("route_error", "reset refused: " + sim.error)
	return sim

## One stage with real inputs: A records, B plays beside the replay. `verify`
## derives the checkpoint through the full proof; otherwise it is built from
## the same final state without replaying the chain again.
static func pair(level: Dictionary, stage_id: String, checkpoint: Dictionary, a_ops: Array, b_ops: Array, verify: bool, probe: Callable = Callable(), delay: int = 0) -> Dictionary:
	var result := {"error": ""}
	var a := source(level,stage_id,checkpoint,a_ops,delay,probe,true)
	result["a_sim"] = a
	if not a.error.is_empty() or str(a.get_meta("route_error")) != "" or not a.can_commit():
		result.error = "A: %s %s %s" % [a.error, a.get_meta("route_error"), a.commit_reason()]
		return result
	var first: Dictionary = a.export_recording()
	var b := receiver(level,stage_id,checkpoint,first,b_ops,probe,true)
	result["b_sim"] = b
	if not b.error.is_empty() or str(b.get_meta("route_error")) != "" or not b.complete:
		result.error = "B: %s %s complete=%s" % [b.error, b.get_meta("route_error"), str(b.complete)]
		return result
	var second: Dictionary = b.export_recording()
	result["a"] = first
	result["b"] = second
	if verify:
		var derived := Simulation.derive_checkpoint(level, json(checkpoint), json(first), json(second))
		if not derived.valid:
			result.error = "derive: " + str(derived.get("error",""))
			return result
		result["checkpoint"] = derived.checkpoint
	else:
		result["checkpoint"] = Simulation._proof(RULES)._build_checkpoint(level, checkpoint, first, second, b.snapshot())
	return result

static func json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

## Presses in a recording's own world: selector turns and lever pulls by the
## active player (the replayed partner's actions are not in its events).
static func count_presses(sim: RefCounted) -> int:
	return int(sim.get_meta("presses", 0))

static func play(sim: RefCounted, ops: Array, probe: Callable = Callable()) -> String:
	for index in range(ops.size()):
		var op: Array = ops[index]
		if sim.finished or not sim.error.is_empty(): return "op %d: the turn ended (%s)" % [index, sim.error]
		match str(op[0]):
			"w":
				if not walk(sim,op[1]): return "op %d: stuck walking to %s at %s" % [index, str(op[1]), _pose(sim)]
			"t":
				Walk.tap(sim)
				for event: String in sim._events:
					if event.begins_with("selector:") or event == "lever": sim.set_meta("presses", count_presses(sim) + 1)
					if event == "bell": sim.set_meta("ring_tick", sim.tick)
			"n": Walk.wait_ticks(sim,int(op[1]))
			"u":
				if not wait_until(sim,str(op[1])): return "op %d: %s never held (tick %d at %s)" % [index, str(op[1]), sim.tick, _pose(sim)]
			"?": if probe.is_valid(): probe.call(str(op[1]),sim)
	return ""

## Same inputs as cooperative_witness.walk; false when the walker stops short.
static func walk(sim: RefCounted, destination: Array) -> bool:
	for axis: String in ["x", "z"]:
		var index := 0 if axis == "x" else 1
		var still := 0
		for _tick in range(Simulation.MAX_TICKS+300):
			if sim.finished or not sim.error.is_empty(): return false
			var before := int(sim._players[sim.active_slot][axis])
			var distance := int(destination[index]) - before
			if absi(distance) <= 1: break
			var input := {"move_x": 0.0, "move_z": 0.0}
			input["move_" + axis] = clampf(float(distance) / 8.0, -1.0, 1.0)
			sim.step(input)
			still = still + 1 if int(sim._players[sim.active_slot][axis]) == before else 0
			if still >= STUCK_TICKS: return false
	return true

## Ticks spent here count as waiting, not walking ("waited" meta).
static func wait_until(sim: RefCounted, condition: String) -> bool:
	for _tick in range(Simulation.MAX_TICKS+300):
		if holds(sim, condition): return true
		if sim.finished or not sim.error.is_empty(): return false
		sim.step({})
		sim.set_meta("waited", int(sim.get_meta("waited", 0)) + 1)
	return false

## Ticks the walker spent walking and pressing up to the ring (or the end).
static func active_ticks(sim: RefCounted) -> int:
	return int(sim.get_meta("ring_tick", sim.tick)) - int(sim.get_meta("waited", 0))

static func holds(sim: RefCounted, condition: String) -> bool:
	var kind := condition.get_slice(":",0)
	var rest := condition.get_slice(":",1)
	match kind:
		"route": return bool(sim._routes.get(rest,false))
		"lever": return bool(sim._mechanisms.levers.get(rest,false))
		"control": return str(sim._mechanisms.controls.get(rest.get_slice("=",0),"")) == rest.get_slice("=",1)
	return false

static func _pose(sim: RefCounted) -> String:
	var player: Dictionary = sim._players[sim.active_slot]
	return "(%d,%d) h%d %s tick %d" % [int(player.x), int(player.z), int(player.height), str(player.surface_id), sim.tick]

## Checks for one stage-2 cell played by pair(): [[ok, label], ...]. Port
## tick figures are upper bounds; the rest are exact.
static func cell_checks(history: String, way: String, pair: Dictionary) -> Array:
	var port: Array = PORT_CELLS[history][way]
	var a: RefCounted = pair.a_sim
	var b: RefCounted = pair.b_sim
	var label := "%s %s" % [history.to_upper(), way]
	var after_ready := int(b.get_meta("ring_tick", b.tick)) - int(a._hold_start)
	var cp: Dictionary = pair.checkpoint
	var result: Array = [
		[a._ready_branch == way and a.source_budget_ticks() == port[0], "%s commits its own branch with budget %d (got %d)" % [label, port[0], a.source_budget_ticks()]],
		[a.receiver_deadline() - 1 - a.source_budget_ticks() == port[1], "%s: the latest hold_start is %d (got %d)" % [label, port[1], a.receiver_deadline() - 1 - a.source_budget_ticks()]],
		[count_presses(b) == port[2], "%s: p0 presses %d (got %d)" % [label, port[2], count_presses(b)]],
		[count_presses(a) == port[4], "%s: p1 presses %d (got %d)" % [label, port[4], count_presses(a)]],
		[after_ready <= a.source_budget_ticks() - 130, "%s: p0 rings %d ticks after p1 is ready, inside budget-130 = %d" % [label, after_ready, a.source_budget_ticks() - 130]],
		[pair.a.simulation_version == RULES and pair.b.simulation_version == RULES, label + ": both turns record rules 9"],
		[cp.stage_index == 2 and cp.next_stage_id == "" and cp.players.p0.surface_id == "mole-terrace", label + ": the chapter completes at the lantern"],
	]
	for route: String in {"boom": ["boom-jetty", "mole-steps"], "sea-lock": ["sea-gate-in", "sea-gate-out"], "punt": ["race-stage", "punt-ferry"]}[way]:
		result.append([route in cp.mechanisms.latched_bridges, "%s keeps %s" % [label, route]])
	return result

## [label, native, port] for the cell's port tick bounds.
static func cell_ticks(history: String, way: String, pair: Dictionary) -> Array:
	var port: Array = PORT_CELLS[history][way]
	var label := "%s %s" % [history.to_upper(), way]
	return [[label + " p1 ticks", int(pair.a.duration_ticks), port[5]], [label + " p0 real ticks", active_ticks(pair.b_sim), port[3]]]
