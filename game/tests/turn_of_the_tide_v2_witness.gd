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
	var routes := [[Tide.a_routes()["low"], Tide.b_routes()["low"]], [Tide.p1_home("low") + Tide.p1_way("low", "sea-lock"), p0_way("low", "sea-lock")]]
	for index in range(level.stages.size()):
		var played := pair(level, str(level.stages[index].id), checkpoint, routes[index][0], routes[index][1])
		if not played.error.is_empty():
			result.error = "%s: %s" % [level.stages[index].id, played.error]
			return result
		result.pairs.append({"a": played.a, "b": played.b})
		checkpoint = played.checkpoint
		result.checkpoints.append(checkpoint)
	return result

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
