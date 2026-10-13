extends RefCounted
## Real input routes for turn-of-the-tide@1. No state injection.
## "w" walks x then z, "d" walks both axes at once, "t" taps the action,
## "n" waits, "?" calls the probe,
## "u" waits for a condition ("route:<id>", "lever:<id>", "control:<id>=<value>").
## play() stops at the first walk that makes no progress and returns why.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Walk = preload("res://tests/cooperative_witness.gd")
const Graph = preload("res://tests/turn_of_the_tide_graph.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const KEY := "turn-of-the-tide@1"
const SET := "set-the-tide"
const SLACK := "slack-water"
const RULES := 9
const STUCK_TICKS := 3
const T := ["t"]

## Figures from an independent axis-walk model of the chapter. Budgets and
## presses are exact; ticks are upper bounds at 2 ticks a press. A deadline is
## the latest hold_start: the receiver's 3,000-tick turn, less one, less the
## budget. Every one is before the first turn's 2,700-tick cap.
const MODEL_STAGE_ONE := {
	"budget": {"low": 460, "half": 418, "high": 494},
	"deadline": {"low": 2539, "half": 2581, "high": 2505},
	"a_ticks": {"low": 462, "low-half-first": 618, "half": 464, "half-via-high": 454, "high": 418},
	"b_real": {"low": 330, "half": 288, "high": 364},
}
## history -> way -> budget, deadline (latest hold_start), p0 presses, p0 real
## ticks, p1 presses and p1 optimum ticks, from the same model.
const MODEL_CELLS := {
	"low": {"boom": [564,2435,4,425,4,410], "sea-lock": [644,2355,5,478,3,406], "punt": [528,2471,2,367,5,499]},
	"half": {"boom": [580,2419,3,417,5,412], "sea-lock": [628,2371,4,430,8,334], "punt": [544,2455,4,381,6,411]},
	"high": {"boom": [548,2451,2,379,8,494], "sea-lock": [660,2339,6,518,7,376], "punt": [544,2455,3,385,5,403]},
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

## Stage 2, p1 (records first), from the bell under the frozen tide: down
## the rock steps toward the beach run (LOW), the lock turned back west
## (HALF), or up the rock steps toward the jetties (HIGH). "d" legs walk both
## axes at once and only cross open floor. Runs keep 4-8 cm inside each
## crossing's walkable band (beach run z 380..404, jetty run z -404..-300).
## p1_way carries on from here.
static func p1_home(history: String) -> Array:
	match history:
		"low": return [["w",[1440,236]],["d",[1296,388]]]
		"half": return [["d",[904,40]],T]
		"high": return [["w",[1440,-236]],["d",[1376,-304]]]
	return []

## Each way needs two moorings and one sea mark:
## boom = beach chain (shut) + gate bar (slack) at half; sea lock = gate bar +
## sea bar (shut) at low; punt = quay chain (not high) + sea bar at high.
const WAY_SEA := {"boom": "half", "sea-lock": "low", "punt": "high"}
const SEA := ["shut","low","half","high"]
## The basin wheel (-312,-64) is in reach from here, beside the north stubs.
const BASIN_STAND := [-320,-88]
## Stands 2 cm inside each reach radius: levers 28, post pads 16. A walker
## between the north stubs keeps to z >= -116, so each north stub is entered
## straight from the terrace in front of it.
const BEACH_CHAIN := [-164,488]
const QUAY_CHAIN := [-180,-488]
const SEA_BAR := [-472,-138]
const SEA_BAR_FRONT := [-472,-112]
const GATE_BAR := [-328,-138]
const POSTS := {"boom": [-272,148], "sea-lock": [-272,-148], "punt": [-408,-148]}

static func sea_presses(from: String, to: String) -> int:
	return (SEA.find(to) - SEA.find(from) + SEA.size()) % SEA.size()

static func _taps(count: int) -> Array:
	var ops: Array = []
	for _i in range(count): ops.append(T)
	return ops

## Turn the sea at the basin wheel.
static func _sea(from: String, to: String) -> Array:
	return [["d",BASIN_STAND]] + _taps(sea_presses(from, to))

static func _gate_bar() -> Array:
	return [["d",GATE_BAR],T]

static func _sea_bar() -> Array:
	return [["d",SEA_BAR_FRONT],["w",SEA_BAR],T,["w",SEA_BAR_FRONT]]

## From a quay stand at x=-180 down the west quay steps onto the terrace.
## The steps' walkable lane is x -212..-140; keep 4 cm inside it.
const QUAY_DOWN := [["w",[-180,-236]],["d",[-208,-204]],["w",[-208,-119]]]

static func _post(way: String) -> Array:
	match way:
		"boom": return [["d",POSTS.boom]]
		# From the basin or the gate catwalk, along the terrace front.
		"sea-lock": return [["w",[POSTS["sea-lock"][0],-116]],["w",POSTS["sea-lock"]]]
	return [["w",[POSTS.punt[0],-116]],["w",POSTS.punt]]

## p1's optimal plan per cell. The shut moorings are made
## fast before the sea first turns; the gate bar waits for slack (the sea at
## the history's tide); the post needs its way's mark.
static func p1_way(tide: String, way: String) -> Array:
	match tide + "/" + way:
		# The beach stub is on the way in.
		"low/boom": return [["w",[BEACH_CHAIN[0],388]],["w",BEACH_CHAIN],T,["w",[BEACH_CHAIN[0],116]]] + _sea("shut","low") + _gate_bar() + _sea("low","half") + _post(way)
		"low/sea-lock": return [["w",[-164,388]],["w",[-164,116]]] + _sea_bar() + _sea("shut","low") + _gate_bar() + [["w",[GATE_BAR[0],-116]]] + _post(way)
		# Up both flights for the quay chain, then down for the sea bar.
		"low/punt": return [["w",[QUAY_CHAIN[0],388]],["w",QUAY_CHAIN],T] + QUAY_DOWN + _sea_bar() + _sea("shut","high") + _post(way)
		"half/boom": return [["w",[-140,40]],["d",[BEACH_CHAIN[0],64]],["w",BEACH_CHAIN],T,["w",[BEACH_CHAIN[0],116]]] + _sea("shut","half") + _gate_bar() + [["w",[GATE_BAR[0],-112]]] + _post(way)
		# The gate bar first, then the sea run round to shut for the sea bar.
		"half/sea-lock": return [["w",[-140,40]]] + _sea("shut","half") + _gate_bar() + _sea("half","shut") + _sea_bar() + _sea("shut","low") + _post(way)
		"half/punt": return [["w",[-100,40]],["d",[QUAY_CHAIN[0],-40]],["w",QUAY_CHAIN],T] + QUAY_DOWN + _sea_bar() + _sea("shut","high") + _post(way)
		# Down both flights for the beach chain, slack at high, then on round to half.
		"high/boom": return [["w",[BEACH_CHAIN[0],-304]],["w",BEACH_CHAIN],T,["w",[BEACH_CHAIN[0],116]]] + _sea("shut","high") + _gate_bar() + _sea("high","half") + _post(way)
		"high/sea-lock": return [["w",[-180,-304]]] + QUAY_DOWN.slice(1) + _sea_bar() + _sea("shut","high") + _gate_bar() + _sea("high","low") + _post(way)
		# The quay chain on arrival, while the sea is still shut.
		"high/punt": return [["d",[1276,-400]],["w",[QUAY_CHAIN[0],-400]],["w",QUAY_CHAIN],T] + QUAY_DOWN + _sea_bar() + _sea("shut","high") + _post(way)
	return []

## The wrong order: the sea wheel turned before any mooring (its first press
## takes the sea from shut to low), then the cheapest recovery. Every
## shut-only mooring floods as soon as the sea leaves shut, so the sea has to
## go round to shut again for it.
## Boom: slack first and the gate bar, then round to shut for the beach chain.
## Sea lock: slack first and the gate bar, then round to shut for the sea bar
## (after HALF this is the optimum itself). Punt: the quay chain is still dry
## at low, the sea bar is not.
static func p1_way_sea_first(tide: String, way: String) -> Array:
	var terrace: Array = {"low": [["w",[-164,388]],["w",[-164,116]]], "half": [["w",[-140,40]]], "high": [["w",[-180,-304]]] + QUAY_DOWN.slice(1)}[tide]
	match way:
		"boom": return terrace + _sea("shut",tide) + _gate_bar() + [["?","catwalk-shut"]] + _sea(tide,"shut") + [["d",[BEACH_CHAIN[0],116]],["w",BEACH_CHAIN],T,["w",[BEACH_CHAIN[0],116]]] + 			_sea("shut","half") + _post("boom")
		"sea-lock": return terrace + _sea("shut",tide) + _gate_bar() + [["?","bar-shut"]] + _sea(tide,"shut") + _sea_bar() + _sea("shut","low") + _post(way)
	return terrace + _sea("shut","low") + [["?","bar-shut"],["d",[QUAY_CHAIN[0],-119]],["w",QUAY_CHAIN],T] + QUAY_DOWN + _sea("low","shut") + _sea_bar() + _sea("shut","high") + _post(way)

## Every mooring made fast (beach chain, quay chain and sea bar while the sea
## is shut, the gate bar at slack), then the sea set to the way's mark and its
## post held: the other ways open while the sea passes their marks.
static func p1_all_chains(tide: String, way: String) -> Array:
	var chains: Array = [["w",BEACH_CHAIN],T,["w",[QUAY_CHAIN[0],-468]],["w",QUAY_CHAIN],T] + QUAY_DOWN
	if tide == "high": chains = [["w",QUAY_CHAIN],T,["w",[BEACH_CHAIN[0],-468]],["w",BEACH_CHAIN],T,["w",[BEACH_CHAIN[0],116]]]
	var down: Array = {"low": [["w",[BEACH_CHAIN[0],388]]], "half": [["w",[-140,40]],["d",[BEACH_CHAIN[0],64]]], "high": [["w",[QUAY_CHAIN[0],-304]]]}[tide]
	return down + chains + _sea_bar() + _sea("shut",tide) + _gate_bar() + \
		([["w",[GATE_BAR[0],-112]]] if WAY_SEA[way] == tide else _sea(tide, WAY_SEA[way])) + _post(way)

## p1's whole turn after any stage-one end state of `tide`. The home route
## only needs what every such end state keeps: after LOW the slipway is
## always kept, because A's wheel step needs the winch on slip, so the
## slipway (low + slip) is open at completion and latched; after HALF the
## stones and the lock (turned back west here); after HIGH the jetties.
static func p1_route(checkpoint: Dictionary, way: String) -> Array:
	var tide := str(checkpoint.mechanisms.controls.tide)
	return p1_home(tide) + p1_way(tide, way)

## Stage 2, p0 (plays beside the replay). Start on its stage-1 step. The tide
## wheel (192,-352) is reached from these stands; the north lane z=-466 runs
## along the quay between the waiting steps.
const STEP := {"low": [192,-512], "half": [64,-512], "high": [320,-512]}
const WHEEL := {"low": [192,-378], "half": [180,-374], "high": [200,-376]}
const WHEEL_NE := [200,-376]
const WHEEL_NW := [186,-376]
const WHEEL_WEST := [172,-368]
const WHEEL_LADDER := [172,-336]
const TIDE := ["low","half","high"]
const LANE := -466
## The boom pin on the bollard step (open at half) and the sea key on the
## quay step (open at low), each in reach 4 cm onto its step.
const PIN_STAND := [320,-488]
const KEY_STAND := [64,-488]

static func tide_presses(from: String, to: String) -> int:
	return (TIDE.find(to) - TIDE.find(from) + TIDE.size()) % TIDE.size()

static func _turn(from: String, to: String) -> Array:
	return _taps(tide_presses(from, to))

## Along the north lane to a step's lever and back to the lane.
static func _fetch(at: Array) -> Array:
	return [["w",[at[0],LANE]],["w",at],T,["w",[at[0],LANE]]]

## From the jetty run at z=-300 onto the mole and up the pinned steps.
## The mole steps' walkable lane is x -900..-828.
const MOLE_FROM_QUAY := [["d",[104,-304]],["w",[-708,-304]],["d",[-840,-236]],["w",[-840,-24]],T]
## Touch the boom at high water, drain to low, and climb to the lantern.
const BOOM_TAIL := [["d",[-500,-368]],["u","route:boom-jetty"],["w",WHEEL_WEST],T] + MOLE_FROM_QUAY

## The mill ladder's walkable lane is x 60..132 (keep to x=64): down to the
## terrace front, and up to the wheel. Stones-1's band is z -52..52.
const LADDER_DOWN := [["d",[64,-236]],["w",[64,-116]]]
const LADDER_UP := [["w",[64,-236]],["d",WHEEL_LADDER]]

## From the quay at half water: touch the sea gate, raise the harbour, and
## turn the chamber high then low inside.
const SEA_TAIL := LADDER_DOWN + [["d",[-500,-48]],["u","route:sea-gate-in"],["w",[12,-48]],["d",[64,-116]]] + LADDER_UP + [T] + LADDER_DOWN + \
	[["d",[-596,36]],T,T,["u","route:sea-gate-out"],["d",[-820,20]],T]

## From the quay at low water: the line on the race stage, half water, and
## the punt over to the mole.
const PUNT_TAIL := [["d",[128,-236]],["w",[128,-116]],["w",[212,-116]],["w",[212,-140]],T,["w",[212,-116]],["w",[128,-116]],["w",[128,-236]],["d",WHEEL_LADDER],T,
	["d",[128,-236]],["w",[128,-116]],["d",[-140,48]],["d",[-208,300]],["w",[-500,300]],["u","route:punt-ferry"],["w",[-708,300]],["d",[-840,236]],["w",[-840,24]],T]

## The scripted optimal p0 for each way after each history. Touches keep a
## crossing with a radius sample; the walker never needs to stand on it.
static func p0_way(history: String, way: String) -> Array:
	var lane: Array = [["w",[STEP[history][0],LANE]]]
	match history + "/" + way:
		# Pin the boom at half before raising the harbour.
		"low/boom": return [["w",WHEEL["low"]],T,["d",[PIN_STAND[0],LANE]]] + _fetch(PIN_STAND).slice(1) + [["d",WHEEL_NE],T] + BOOM_TAIL
		"half/boom": return lane + _fetch(PIN_STAND) + [["d",WHEEL_NE],T] + BOOM_TAIL
		# The pin hangs on p0's own step.
		"high/boom": return [T] + lane + BOOM_TAIL
		# Fetch the key at low before going west.
		"low/sea-lock": return lane + _fetch(KEY_STAND) + [["d",WHEEL_NW],T] + SEA_TAIL
		"half/sea-lock": return [T,["w",[64,-116]]] + SEA_TAIL.slice(2)
		"high/sea-lock": return lane + [["d",WHEEL_NE],T,["d",[KEY_STAND[0],LANE]]] + _fetch(KEY_STAND).slice(1) + [["d",WHEEL_NW],T] + SEA_TAIL
		"low/punt": return lane + PUNT_TAIL
		"half/punt": return lane + [["d",WHEEL["half"]],T,T] + PUNT_TAIL
		"high/punt": return lane + [["d",WHEEL_NE],T] + PUNT_TAIL
	return []

## p0 played the way the greedy walker below plays it (controls first): walk
## toward the way, and at each closed crossing fix what it is missing, turning
## the nearest wheel the fewest times before fetching a lever. Presses in the
## same order as the walker's log. The probes ("pinless", "keyless",
## "race-shut", "punt-shut") mark where the walker meets the missing term.
static func p0_greedy(history: String, way: String) -> Array:
	var lane: Array = [["w",[STEP[history][0],LANE]]]
	# Pinless: at low water the mole steps stay shut; back toward the wheel.
	var pinless: Array = [["d",[104,-304]],["w",[-708,-304]],["d",[-840,-236]],["?","pinless"],["d",[-708,-304]],["w",[104,-304]]]
	var pin: Array = [["d",[PIN_STAND[0],LANE]]] + _fetch(PIN_STAND).slice(1)
	var key: Array = [["d",[KEY_STAND[0],LANE]]] + _fetch(KEY_STAND).slice(1)
	# Into the chamber while it matches the harbour; the chamber turned to low.
	var chamber: Array = LADDER_DOWN + [["d",[-500,36]],["u","route:sea-gate-in"],["d",[-596,36]],T,T,["?","keyless"],["w",[12,36]],["d",[64,-116]]] + LADDER_UP
	var gate_out: Array = LADDER_DOWN + [["d",[-596,36]],["u","route:sea-gate-out"],["d",[-820,20]],T]
	# The race stage at low water for the line, then half for the punt.
	var line: Array = [["d",[128,-236]],["w",[128,-116]],["w",[212,-116]],["w",[212,-140]],T,["w",[212,-116]],["w",[128,-116]],["w",[128,-236]],["d",WHEEL_LADDER],T]
	var ferry: Array = PUNT_TAIL.slice(PUNT_TAIL.size() - 10)
	match history + "/" + way:
		"low/boom": return [["w",WHEEL["low"]],T,T] + BOOM_TAIL.slice(0, 4) + pinless + [["d",WHEEL_LADDER],T] + pin + [["d",WHEEL_NE],T,T] + MOLE_FROM_QUAY
		"half/boom": return lane + [["d",WHEEL["half"]],T] + BOOM_TAIL.slice(0, 4) + pinless + [["d",WHEEL_LADDER],T] + pin + [["d",WHEEL_NE],T,T] + MOLE_FROM_QUAY
		# The pin hangs on the kept bollard step: the walker meets it last.
		"high/boom": return lane + BOOM_TAIL.slice(0, 4) + pinless + pin + MOLE_FROM_QUAY
		"low/sea-lock": return [["w",WHEEL["low"]],T] + chamber + [T,T] + key + [["d",WHEEL_NW],T,T] + gate_out
		# The quay step is kept after HALF, so the key needs no tide.
		"half/sea-lock": return [["w",[64,-116]]] + chamber.slice(2) + [T] + key + gate_out
		"high/sea-lock": return lane + [["d",WHEEL_NE],T,T] + chamber + [T,T] + key + [["d",WHEEL_NW],T,T] + gate_out
		# Half water first: the race stage floods, so round to low for the line.
		"low/punt": return [["w",[192,-368]],T,["w",[132,-368]],["w",[132,-116]],["w",[208,-116]],["?","race-shut"],["w",[132,-116]],["w",[132,-368]],["w",WHEEL_WEST],T,T] + line + ferry
		"half/punt": return p0_way(history, way)
		# Low water first, over the sand bar toward the punt, which wants half and the line.
		"high/punt": return lane + [["d",WHEEL_NE],T,["d",[128,-236]],["w",[128,-116]],["w",[128,352]],["w",[-480,352]],["?","punt-shut"],["w",[128,352]],["w",[128,-116]],["w",[128,-236]],["d",WHEEL_LADDER],T,T,T] + line + ferry
	return []

## Greedy presses per cell from the independent model (controls first).
const MODEL_GREEDY := {"low": {"boom": 7, "sea-lock": 8, "punt": 5}, "half": {"boom": 6, "sea-lock": 4, "punt": 4}, "high": {"boom": 2, "sea-lock": 9, "punt": 6}}
## What the walker heads for, in order, on each way.
const GREEDY_TARGETS := {"boom": ["boom-jetty", "mole-quay", "mole-steps", "mole-terrace"], "sea-lock": ["sea-gate-in", "sea-chamber", "sea-gate-out", "mole-terrace"], "punt": ["punt-ferry", "mole-beach", "mole-terrace"]}

## A greedy walker on the surface graph (the independent model's
## controls-first policy): walk toward each target in turn; at the first shut
## crossing on the shortest path (gates ignored, centre-to-centre distance),
## fix the missing term: controls before levers, a wheel already in reach
## before one that is not, then the nearest, cycled the fewest times. A lever
## is fetched by walking to its stub, fixing that stub's gate the same way. As
## role b it entry-latches every open latch route it walks. The other
## player's values stay frozen. Counts presses (selector turns, lever pulls).
class Greedy:
	const FAR := {"x": 100000, "z": 100000, "height": -1000, "surface_id": ""}
	var graph: RefCounted
	var stage: Dictionary
	var slot: String
	var latching := false
	var controls: Dictionary = {}
	var levers: Dictionary = {}
	var kept: Array = []
	var latched: Dictionary = {}
	var region := -1
	var presses := 0
	var log: Array[String] = []
	var error := ""
	var comp: Dictionary = {}
	var centre: Array = []
	var wheels: Dictionary = {}
	var lever_stubs: Dictionary = {}
	var values: Dictionary = {}

	func _init(g: RefCounted, level: Dictionary, stage_id: String, walker: String, checkpoint: Dictionary, other: Dictionary) -> void:
		graph = g
		slot = walker
		for item: Dictionary in level.stages:
			if item.id == stage_id: stage = item
		latching = stage.first_player_slot != slot
		controls = checkpoint.mechanisms.controls.duplicate()
		levers = checkpoint.mechanisms.levers.duplicate()
		for id: String in other.get("controls", {}): controls[id] = other.controls[id]
		for id: String in other.get("levers", {}): levers[id] = other.levers[id]
		kept = checkpoint.mechanisms.latched_bridges.duplicate()
		for control: Dictionary in stage.controls:
			values[control.id] = control.values
			if control.owner_slot == slot: wheels[control.id] = int(graph.index[control.surface_id])
		for lever: Dictionary in stage.levers:
			if lever.owner_slot == slot: lever_stubs[lever.id] = int(graph.index[lever.surface_id])
		for surface: Dictionary in graph.surfaces:
			var r: Array = surface.rect
			centre.append(Vector2(float(r[0] + r[2]) * 0.5, float(r[1] + r[3]) * 0.5))
		region = int(graph.index[checkpoint.players[slot].surface_id])
		_settle()

	func run(targets: Array) -> int:
		for target: String in targets:
			if not goto(int(graph.index[target]), 0): return -1
		return presses

	func _mechanisms() -> Dictionary:
		return {"controls": controls, "levers": levers, "latched_bridges": kept, "props": {}}

	func _open() -> Dictionary:
		var open: Dictionary = {}
		for id: String in kept: open[id] = true
		for id: String in latched: open[id] = true
		for gate: Dictionary in stage.gates:
			if Seven.predicate(gate.get("when", {}), stage, {"p0": FAR, "p1": FAR}, _mechanisms()): open[gate.route_id] = true
		return open

	func _holds(when: Dictionary) -> bool:
		return Seven.predicate(when, stage, {"p0": FAR, "p1": FAR}, _mechanisms())

	func _settle() -> void:
		var mask: int = graph.bits_of(_open().keys())
		comp = {region: true}
		var queue: Array = [region]
		var head := 0
		while head < queue.size():
			var at: int = queue[head]
			head += 1
			for edge: Array in graph.edges[slot][at]:
				if (int(edge[1]) & mask) != int(edge[1]): continue
				if not str(edge[2]).is_empty() and not bool(levers.get(edge[2], false)): continue
				if not comp.has(int(edge[0])):
					comp[int(edge[0])] = true
					queue.append(int(edge[0]))

	func _distance(a: int, b: int) -> float:
		return absf(centre[a].x - centre[b].x) + absf(centre[a].y - centre[b].y)

	## Shortest path from anywhere reachable now to `target`, gates ignored.
	func _path(target: int) -> Array:
		var dist: Dictionary = {}
		var previous: Dictionary = {}
		var done: Dictionary = {}
		for at: int in comp:
			dist[at] = 0.0
			previous[at] = -1
		while true:
			var best := -1
			var best_distance := INF
			for at: int in dist:
				if not done.has(at) and float(dist[at]) < best_distance:
					best = at
					best_distance = dist[at]
			if best < 0 or best == target: break
			done[best] = true
			for edge: Array in graph.edges[slot][best]:
				var to: int = edge[0]
				var through := best_distance + _distance(best, to)
				if through < float(dist.get(to, INF)):
					dist[to] = through
					previous[to] = best
		if not previous.has(target): return []
		var path: Array = []
		var at := target
		while at != -1:
			path.push_front(at)
			at = previous[at]
		return path

	func goto(target: int, depth: int) -> bool:
		var guard := 0
		while not comp.has(target):
			guard += 1
			if guard > 30 or depth > 6:
				error = "stuck heading for " + graph.id_of(target)
				return false
			var path := _path(target)
			var shut := _open()
			var blocked := ""
			for at: int in path:
				if graph.surfaces[at].kind != "island" and not shut.has(graph.id_of(at)):
					blocked = graph.id_of(at)
					break
			if blocked.is_empty():
				error = "no shut crossing toward " + graph.id_of(target)
				return false
			if not _fix(blocked, depth): return false
		# Walk the fewest hops over open floor, latching what it crosses.
		var open := _open()
		var mask: int = graph.bits_of(open.keys())
		var previous: Dictionary = {region: -1}
		var queue: Array = [region]
		var head := 0
		while head < queue.size():
			var at: int = queue[head]
			head += 1
			if at == target: break
			for edge: Array in graph.edges[slot][at]:
				if (int(edge[1]) & mask) != int(edge[1]) or previous.has(int(edge[0])): continue
				previous[int(edge[0])] = at
				queue.append(int(edge[0]))
		if latching:
			var step := target
			while step != -1:
				var id: String = graph.id_of(step)
				if id in stage.get("entry_latch_routes", []) and open.has(id): latched[id] = true
				step = int(previous.get(step, -1))
		region = target
		_settle()
		return true

	## False leaves of a predicate; for "any", the disjunct with the fewest presses.
	func _missing(when: Dictionary) -> Array:
		if _holds(when): return []
		if when.has("all"):
			var out: Array = []
			for child: Dictionary in when.all: out.append_array(_missing(child))
			return out
		if when.has("any"):
			var best: Array = []
			var best_cost := -1
			for child: Dictionary in when.any:
				var terms := _missing(child)
				var cost := 0
				for term: Dictionary in terms:
					if term.has("control_id"): cost += _cycles(term) if _in_reach(str(term.control_id)) else 100
				if best_cost < 0 or cost < best_cost:
					best = terms
					best_cost = cost
			return best
		return [when]

	func _cycles(term: Dictionary) -> int:
		var list: Array = values[term.control_id]
		return (list.find(term.value) - list.find(controls[term.control_id]) + list.size()) % list.size()

	func _in_reach(control: String) -> bool:
		return wheels.has(control) and comp.has(int(wheels[control]))

	func _fix(route: String, depth: int) -> bool:
		var when: Variant = null
		for gate: Dictionary in stage.gates:
			if gate.route_id == route: when = gate.get("when", {})
		if when == null:
			error = route + " never opens in this stage"
			return false
		var terms := _missing(when)
		if terms.is_empty(): return true
		var wheel_terms: Array = terms.filter(func(term: Dictionary) -> bool: return term.has("control_id"))
		var lever_terms: Array = terms.filter(func(term: Dictionary) -> bool: return term.has("lever_id"))
		wheel_terms.sort_custom(_wheel_first)
		var order: Array = wheel_terms + lever_terms
		if order.is_empty():
			error = route + " waits on something no one can press"
			return false
		var term: Dictionary = order[0]
		if term.has("control_id"):
			var id := str(term.control_id)
			if not wheels.has(id) or (id == "chamber" and not _in_reach(id)):
				error = "%s needs %s, out of reach" % [route, id]
				return false
			if not goto(int(wheels[id]), depth + 1): return false
			while str(controls[id]) != str(term.value):
				var list: Array = values[id]
				controls[id] = list[(list.find(controls[id]) + 1) % list.size()]
				presses += 1
				log.append("%s->%s" % [id, controls[id]])
				_settle()
		else:
			var id := str(term.lever_id)
			if not lever_stubs.has(id):
				error = "%s needs the other player's %s" % [route, id]
				return false
			if not goto(int(lever_stubs[id]), depth + 1): return false
			levers[id] = true
			presses += 1
			log.append(id + "+")
			_settle()
		return true

	func _wheel_first(a: Dictionary, b: Dictionary) -> bool:
		var ra := _in_reach(str(a.control_id))
		var rb := _in_reach(str(b.control_id))
		if ra != rb: return ra
		return _distance(region, int(wheels.get(a.control_id, region))) < _distance(region, int(wheels.get(b.control_id, region)))

## Contract fixtures: written only on request (AFTER_YOU_WRITE_FIXTURES, see
## test_turn_of_the_tide), otherwise compared. Returns [ok, label] rows.
const FIXTURES := "res://tests/fixtures/journey/"
const WRITE_ENV := "AFTER_YOU_WRITE_FIXTURES"

static func fixtures(files: Dictionary, may_write: bool) -> Array:
	var rows: Array = []
	var target := OS.get_environment(WRITE_ENV)
	for name: String in files:
		var path: String = FIXTURES + name + ".json"
		if not target.is_empty() and may_write:
			var out := path if target == "1" else target.path_join(name + ".json")
			var file := FileAccess.open(out, FileAccess.WRITE)
			file.store_string(JSON.stringify(files[name], "\t", true) + "\n")
			file.close()
			print("WROTE " + out)
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		rows.append([parsed is Dictionary and Canonical.same(json(files[name]), parsed), "Fixture matches fresh real-input evidence: " + name])
	return rows

## A derived chain as fixture files: "<prefix>-a", "-b" and "-checkpoint".
static func chain_files(files: Dictionary, prefix: String, pair: Dictionary) -> void:
	for part: String in ["a", "b", "checkpoint"]: files["%s-%s" % [prefix, part]] = pair[part]

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
	for _tick in range(sim.duration_limit()):
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
			"d":
				if not walk_both(sim,op[1]): return "op %d: stuck walking to %s at %s" % [index, str(op[1]), _pose(sim)]
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
		for _tick in range(sim.duration_limit()):
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

## Both axes at once: full input on each moves 6 cm a tick on each, one axis
## alone 8 cm. A blocked step slides along the edge (runtime _move).
static func walk_both(sim: RefCounted, destination: Array) -> bool:
	var still := 0
	for _tick in range(sim.duration_limit()):
		if sim.finished or not sim.error.is_empty(): return false
		var player: Dictionary = sim._players[sim.active_slot]
		var dx := int(destination[0]) - int(player.x)
		var dz := int(destination[1]) - int(player.z)
		if absi(dx) <= 1 and absi(dz) <= 1: return true
		var input := {"move_x": 0.0, "move_z": 0.0}
		var both := absi(dx) > 1 and absi(dz) > 1
		if absi(dx) > 1: input.move_x = clampf(float(dx) / (6.0 if both else 8.0), -1.0, 1.0)
		if absi(dz) > 1: input.move_z = clampf(float(dz) / (6.0 if both else 8.0), -1.0, 1.0)
		var before := Vector2i(int(player.x), int(player.z))
		sim.step(input)
		var after := Vector2i(int(sim._players[sim.active_slot].x), int(sim._players[sim.active_slot].z))
		still = still + 1 if after == before else 0
		if still >= STUCK_TICKS: return false
	return true

## Ticks spent here count as waiting, not walking ("waited" meta).
static func wait_until(sim: RefCounted, condition: String) -> bool:
	for _tick in range(sim.duration_limit()):
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

## Checks for one stage-2 cell played by pair(): [[ok, label], ...]. Model
## tick figures are upper bounds; the rest are exact.
static func cell_checks(history: String, way: String, pair: Dictionary) -> Array:
	var model: Array = MODEL_CELLS[history][way]
	var a: RefCounted = pair.a_sim
	var b: RefCounted = pair.b_sim
	var label := "%s %s" % [history.to_upper(), way]
	var after_ready := int(b.get_meta("ring_tick", b.tick)) - int(a._hold_start)
	var cp: Dictionary = pair.checkpoint
	var result: Array = [
		[a._ready_branch == way and a.source_budget_ticks() == model[0], "%s commits its own branch with budget %d (got %d)" % [label, model[0], a.source_budget_ticks()]],
		[a.receiver_deadline() - 1 - a.source_budget_ticks() == model[1], "%s: the latest hold_start is %d (got %d)" % [label, model[1], a.receiver_deadline() - 1 - a.source_budget_ticks()]],
		[count_presses(b) == model[2], "%s: p0 presses %d (got %d)" % [label, model[2], count_presses(b)]],
		[count_presses(a) == model[4], "%s: p1 presses %d (got %d)" % [label, model[4], count_presses(a)]],
		[after_ready <= a.source_budget_ticks() - 130, "%s: p0 rings %d ticks after p1 is ready, inside budget-130 = %d" % [label, after_ready, a.source_budget_ticks() - 130]],
		[pair.a.simulation_version == RULES and pair.b.simulation_version == RULES, label + ": both turns record rules 9"],
		[cp.stage_index == 2 and cp.next_stage_id == "" and cp.players.p0.surface_id == "mole-terrace", label + ": the chapter completes at the lantern"],
	]
	for route: String in {"boom": ["boom-jetty", "mole-steps"], "sea-lock": ["sea-gate-in", "sea-gate-out"], "punt": ["race-stage", "punt-ferry"]}[way]:
		result.append([route in cp.mechanisms.latched_bridges, "%s keeps %s" % [label, route]])
	return result

## [label, native, model] for the cell's model tick bounds.
static func cell_ticks(history: String, way: String, pair: Dictionary) -> Array:
	var model: Array = MODEL_CELLS[history][way]
	var label := "%s %s" % [history.to_upper(), way]
	return [[label + " p1 ticks", int(pair.a.duration_ticks), model[5]], [label + " p0 real ticks", active_ticks(pair.b_sim), model[3]]]
