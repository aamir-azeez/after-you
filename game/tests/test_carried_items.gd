extends SceneTree
## Rules 20's carried items and currents (core/physical/carried_items.gd) on
## the witness level (tests/carried_items_level.gd), through the real journey
## engine and its proof:
## - the rules number, the shapes, the predicate terms, and published
##   checkpoints that keep their four mechanisms;
## - pick up, put down, and a carrier refused at the both-hands ladder while an
##   empty pip climbs it;
## - stage 1 over four turns on the shared timeline: the friend's replay
##   carries what it carried, turn 3 takes over at the ladder's foot still
##   carrying it and hands it up, turn 4 takes it from turn 3's replay at the
##   top and the stage closes with it carried; the closing checkpoint verifies
##   again (and fails with the holder changed);
## - the replay sees it gone (the live pip took it first), a same tick tie (p0
##   goes first), a replay's give in reach and out of reach, a replay handed
##   the item that never climbs the ladder loaded, and a take on a replay's
##   last tick never repeated after it ends;
## - every turn replays exactly, and plays the same from its kept start world
##   as with the turns before it played again;
## - the item rides into the next stage unless the stage places it;
## - the current: a live wheel turn moves each float one leg (the raft opens
##   the ferry), a held board stops a leg, the replay's turn moves it in the
##   live world, and an item set down on a leg's start with the wheel right
##   moves at once;
## - items ride platforms (tests/item_ride_witness.gd): put down on a raft by
##   the replay, the live pip's pull carries it over the water and it is picked
##   up at the far stop; put down in the lift's pan it alone sends the lift
##   up; put down on the lift, the pan sends it up (it weighs no pan itself),
##   it is picked up at the top, put back and rides down again;
##   both turns replay exactly, from a kept start world or played again, and the stage's
##   checkpoint (the pipsport resting on the lift) derives and verifies;
## - the server's witness files (tests/fixtures/carried_items/ and
##   tests/fixtures/item_rides/, read by backend/test/carried-items.test.ts) are
##   what this suite derives; `-- --write` writes them again.
const Simulation = preload("res://core/journey/simulation.gd")
const Proof = preload("res://core/physical/two_pair_proof.gd")
const CarriedItems = preload("res://core/physical/carried_items.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const MemoryTrace = preload("res://core/physical/memory_trace.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Level = preload("res://tests/carried_items_level.gd")
const RideWitness = preload("res://tests/item_ride_witness.gd")
const RULES := OpenControls.PIECES_RULES_VERSION
const SERVER_FIXTURES := "res://tests/fixtures/carried_items/"
const RIDE_FIXTURES := "res://tests/fixtures/item_rides/"
const POST := [-350, 60]
const FOOT := [-130, 0]
const TOP := [30, 0]
var checks := 0
var failures := 0
var level: Dictionary
var start: Dictionary
var proof: RefCounted

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	level = Level.definition()
	start = Level.initial_checkpoint(level)
	proof = Proof.new(Level, Simulation, RULES, Simulation.CURRENT_SIMULATION_VERSION)
	_rules()
	_hands()
	var stage_one := _hand_up()
	_gone_and_tie()
	_ladder_drop()
	_last_tick()
	if not stage_one.is_empty():
		_next_stage(stage_one)
		_current(stage_one)
		_server_files(stage_one)
	_raft_ride()
	_lift_ride()
	print("CARRIED ITEMS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

# --- Rules and shapes -------------------------------------------------------------

func _rules() -> void:
	_check(CarriedItems.on(RULES) and OpenTurns.rules(RULES) and OpenControls.pinned(level) and RULES in OpenControls.TIDE_RULES, "Rules 20 play the new pieces on open turns, open controls and the tide")
	_check(Simulation._record_version({"simulation_version": RULES}) == RULES and Simulation.rules_allowed(level, RULES) and not Simulation.rules_allowed(level, 19), "A rules 20 record reads as 20, and the witness plays only 20")
	_check(CarriedItems.problems(level).is_empty(), "The witness level is sound (%s)" % str(CarriedItems.problems(level)))
	var bad := level.duplicate(true)
	bad.items[0].at = "nowhere"
	bad.stages[1].current_legs[0].value = "east"
	bad.simulation_version = 19
	var found := CarriedItems.problems(bad)
	_check(found.size() == 3, "Problems name a start at no spot, a leg on a value no selector shows, and items off rules 20 (%s)" % str(found))
	_check(start.mechanisms.items.pipsport == {"holder": "", "spot": "post", "x": -350, "z": 80, "height": 0, "surface_id": "dock"} and start.mechanisms.items.raft.spot == "mooring", "The first checkpoint holds each item where it starts")
	for key: String in ["long-way-home@3", "turn-of-the-tide@3"]:
		_check(not Registry.initial_checkpoint(key).mechanisms.has("items"), "%s keeps its four mechanisms" % key)
	var mechanisms := {"items": {"pipsport": CarriedItems.held("p1"), "raft": CarriedItems.at_spot(CarriedItems.spot(level, "berth"))}}
	_check(Seven.predicate({"item_id": "pipsport", "carried": true}, {}, {}, mechanisms) and not Seven.predicate({"item_id": "pipsport", "spot_id": "post"}, {}, {}, mechanisms), "Carried holds while a pip has it, not a spot")
	_check(Seven.predicate({"item_id": "raft", "spot_id": "berth"}, {}, {}, mechanisms) and not Seven.predicate({"item_id": "raft", "carried": true}, {}, {}, mechanisms) and not Seven.predicate({"item_id": "lost", "carried": true}, {}, {}, mechanisms), "A float at its spot holds; an unknown item never does")
	# A rules 19 level that lists items plays without them.
	var older := level.duplicate(true)
	older.simulation_version = 19
	var sim := _sim(older, "hand-up", start)
	_go(sim, POST)
	_check(str(sim.context_action().id) == "", "On rules 19 an item offers nothing")

func _hands() -> void:
	var sim := _sim(level, "hand-up", start)
	_go(sim, POST)
	_check(sim.context_action().id == "take" and sim.context_action().label == "Pick up", "By the post box the pip may pick the pipsport up")
	_tap(sim)
	_check(sim.snapshot().players.p0.carrying == "pipsport" and "item_taken:pipsport" in sim.snapshot().events, "Picked up, it rides on the pip's back")
	_go(sim, [-250, 0])
	_check(sim.context_action().id == "put", "Away from the other pip, a carrier may put it down")
	_tap(sim)
	var state: Dictionary = sim._mechanisms.items.pipsport
	_check(state.holder == "" and state.spot == "" and state.surface_id == "dock" and state.x == -250, "Put down loose, it rests at the pip's feet")
	_tap(sim)
	_check(sim._mechanisms.items.pipsport.holder == "p0", "And is picked up again")
	_go(sim, FOOT)
	_go(sim, TOP)
	_check(str(sim._players.p0.surface_id) == "dock" and int(sim._players.p0.x) < -90, "A carrier never climbs the both-hands ladder (stopped at %s)" % sim._players.p0.x)
	var empty := _sim(level, "hand-up", start)
	_go(empty, FOOT)
	_go(empty, TOP)
	_check(str(empty._players.p0.surface_id) == "loft", "An empty pip climbs the same ladder")

# --- Stage 1 over four turns ---------------------------------------------------------

## A: p0 fetches the pipsport and waits at the ladder's foot. B: p1 waits at
## the top and passes as A's replay ends. C takes over there: p0 at the foot,
## still carrying it, waits, hands it up to p1 standing at the top, climbs
## after it to the goal and passes. D takes over at C's start with all of C
## replaying: p1 is handed the pipsport and carries it to the goal, closing
## the stage.
func _hand_up() -> Dictionary:
	var a_sim := _sim(level, "hand-up", start)
	_go(a_sim, POST)
	var take_a := _tap(a_sim)
	_go(a_sim, [-350, 0])
	_go(a_sim, FOOT)
	_still(a_sim, 10)
	_check(a_sim.context_action().id == "put", "Turn 1 offers no hand over with the other pip far off")
	var a := _record(a_sim)
	var b_sim := _sim(level, "hand-up", start, a)
	_go(b_sim, TOP)
	_until(b_sim, take_a + 1)
	_check(b_sim._mechanisms.items.pipsport.holder == "p0" and b_sim.snapshot().players.p0.carrying == "pipsport", "The replay carries what it carried")
	_check(str(b_sim.context_action().id) == "", "The live pip cannot take the item from the replay")
	_until(b_sim, int(a.duration_ticks))
	_check(b_sim.can_pass(), "Turn 2 passes once its replay is over (%s)" % b_sim.commit_reason())
	b_sim.pass_turn()
	var b := _record(b_sim)
	var c_sim := _sim(level, "hand-up", start, b, [a])
	_check(c_sim.handoff_tick == int(a.duration_ticks) and c_sim.replay_ticks() == 0 and c_sim._mechanisms.items.pipsport.holder == "p0" and str(c_sim._players.p1.surface_id) == "loft", "Turn 3 takes over at the foot still carrying the pipsport, p1 at the top")
	_still(c_sim, 30)
	_check(c_sim.context_action().id == "give", "At the foot the carrier may hand it up to the pip at the top")
	var give_c := _tap(c_sim)
	_check(c_sim._mechanisms.items.pipsport.holder == "p1" and "item_given:pipsport" in c_sim.snapshot().events, "Handed up, p1 holds it")
	_go(c_sim, TOP)
	_go(c_sim, [220, 0])
	_check(str(c_sim._players.p0.surface_id) == "loft" and not c_sim.complete, "With empty hands the pip climbs after it; p1 still at the top, the stage goes on")
	_check(c_sim.can_pass(), "Turn 3 passes (%s)" % c_sim.commit_reason())
	c_sim.pass_turn()
	var c := _record(c_sim)
	var d_sim := _sim(level, "hand-up", start, c, [a, b])
	_check(d_sim.handoff_tick == 0 and d_sim.replay_ticks() == int(c.duration_ticks), "Turn 4 takes over at turn 3's start with all of it replaying")
	_until(d_sim, give_c + 1)
	_check(d_sim._mechanisms.items.pipsport.holder == "p1", "Turn 3's replay hands the pipsport up to p1 at the top")
	_go(d_sim, [250, 0])
	_settle(d_sim)
	_check(d_sim.complete, "Both pips at the goal with the pipsport carried close the stage (%s)" % d_sim.commit_reason())
	var d := _record(d_sim)
	for turn: Array in [[a, {}, []], [b, a, []], [c, b, [a]], [d, c, [a, b]]]:
		var checked: Dictionary = proof._verify_raw(level, turn[0], start, turn[1], turn[2])
		_check(checked.valid, "Turn %d replays exactly (%s)" % [turn[2].size() + (1 if turn[1].is_empty() else 2), checked.get("error", "")])
	# The same turn with the turns before it played again rather than from a kept start world.
	MemoryTrace.enabled = false
	var again := _sim(level, "hand-up", start, c, [a, b])
	_replay(again, d)
	MemoryTrace.enabled = true
	_check(Canonical.same(_record(again), d), "A turn plays the same from its kept start world as with the turns before played again")
	var derived: Dictionary = proof.derive_checkpoint(level, start, a, d, [b, c])
	_check(derived.valid, "The stage's checkpoint derives (%s)" % derived.get("error", ""))
	if not derived.valid: return {}
	var checkpoint: Dictionary = _json(derived.checkpoint)
	_check(checkpoint.mechanisms.items.pipsport.holder == "p1" and checkpoint.next_first_slot == "p0" and proof.verify_checkpoint(level, checkpoint).valid, "The closing checkpoint holds the pipsport on p1's back, p0 starts the next stage, and it verifies again")
	var tampered: Dictionary = checkpoint.duplicate(true)
	tampered.mechanisms.items.pipsport.holder = "p0"
	tampered.checkpoint_hash = Level.checkpoint_hash(tampered)
	_check(not proof.verify_checkpoint(level, tampered).valid, "A checkpoint with the holder changed does not verify")
	_memory_gives(a, b, c, give_c)
	return {"a": a, "b": b, "c": c, "d": d, "checkpoint": checkpoint}

## Turn 4 over C: p1 walks away from the top before C's replay gives, so the
## replay's press finds no one in reach and puts the pipsport down at its feet.
func _memory_gives(a: Dictionary, b: Dictionary, c: Dictionary, give_c: int) -> void:
	var away := _sim(level, "hand-up", start, c, [a, b])
	_go(away, [250, 0])
	_until(away, give_c + 1)
	var state: Dictionary = away._mechanisms.items.pipsport
	_check(state.holder == "" and state.surface_id == "dock" and state.spot == "", "A replay's give with nobody in reach puts the item down at its feet")

# --- The replay sees it gone --------------------------------------------------------

func _late_take() -> Dictionary:
	var sim := _sim(level, "hand-up", start)
	_still(sim, 150)
	_go(sim, POST)
	var take := _tap(sim)
	_still(sim, 20)
	return {"record": _record(sim), "take": take}

func _gone_and_tie() -> void:
	var late := _late_take()
	var a: Dictionary = late.record
	var sim := _sim(level, "hand-up", start, a)
	_go(sim, TOP)
	_go(sim, FOOT)
	_go(sim, [-350, 0])
	_go(sim, POST)
	_check(int(sim.tick) < int(late.take), "The live pip reaches the post box first (%d < %d)" % [sim.tick, late.take])
	_tap(sim)
	_until(sim, int(a.duration_ticks))
	_check(sim._mechanisms.items.pipsport.holder == "p1" and sim.snapshot().players.p0.carrying == "", "The live pip took it first, so the replay's pick up finds nothing")
	_go(sim, FOOT)
	_go(sim, TOP)
	_check(str(sim._players.p1.surface_id) == "dock", "Loaded, the live pip cannot climb back up")
	var tie := _sim(level, "hand-up", start, a)
	_go(tie, TOP)
	_go(tie, FOOT)
	_go(tie, [-350, 0])
	_go(tie, POST)
	_until(tie, int(late.take))
	tie.step({"interact": true})
	_check(tie._mechanisms.items.pipsport.holder == "p0", "On the same tick p0's (the replay's) pick up lands first")
	_until(tie, int(a.duration_ticks))
	var tied: Dictionary = proof._verify_raw(level, _record(tie), start, a)
	_check(tied.valid, "The tie replays exactly (%s)" % tied.get("error", ""))

## A: p0 waits, then climbs. B: p1 fetches the pipsport and hands it to the
## waiting replay, which then reaches the ladder loaded and never climbs it.
func _ladder_drop() -> void:
	var a_sim := _sim(level, "hand-up", start)
	_go(a_sim, [-200, 0])
	_until(a_sim, 170)
	_go(a_sim, FOOT)
	_go(a_sim, TOP)
	_check(str(a_sim._players.p0.surface_id) == "loft", "Turn 1 climbs with empty hands")
	var a := _record(a_sim)
	var sim := _sim(level, "hand-up", start, a)
	_go(sim, TOP)
	_go(sim, FOOT)
	_go(sim, [-350, 0])
	_go(sim, POST)
	_tap(sim)
	_go(sim, [-350, 0])
	_go(sim, [-240, 0])
	_check(sim.context_action().id == "give" and int(sim.tick) < 170, "The live pip may hand it to the waiting replay (tick %d)" % sim.tick)
	_tap(sim)
	_check(sim._mechanisms.items.pipsport.holder == "p0", "The replay now holds it")
	_until(sim, int(a.duration_ticks))
	var state: Dictionary = sim._mechanisms.items.pipsport
	_check(state.holder == "p0" and str(sim._players.p0.surface_id) == "dock" and int(sim._players.p0.x) < -90, "Loaded, the replay never climbs the ladder: it stops at the foot, still carrying it (%s)" % str(sim._players.p0))

## A ends with a put on its last tick. Once it is over, the live pip hands
## the item back to the still replay, which keeps it: a replay's last act
## never repeats.
func _last_tick() -> void:
	var a_sim := _sim(level, "hand-up", start)
	_still(a_sim, 150)
	_go(a_sim, POST)
	_tap(a_sim)
	_go(a_sim, [-300, 60])
	a_sim.step({})
	a_sim.step({"interact": true})
	var a := _record(a_sim)
	_check(a_sim._mechanisms.items.pipsport.holder == "", "Turn 1 ends putting the pipsport down")
	var sim := _sim(level, "hand-up", start, a)
	_go(sim, TOP)
	_go(sim, FOOT)
	_go(sim, [-250, 0])
	_until(sim, int(a.duration_ticks) + 2)
	_check(sim._mechanisms.items.pipsport.holder == "" and sim._mechanisms.items.pipsport.surface_id == "dock", "The replay's own put lands in the live world")
	_go(sim, [-300, 30])
	_tap(sim)
	_check(sim._mechanisms.items.pipsport.holder == "p1" and sim.context_action().id == "give", "The live pip picks it up beside the still replay")
	_tap(sim)
	_still(sim, 20)
	_check(sim._mechanisms.items.pipsport.holder == "p0", "Handed to the finished replay, it keeps it: a replay's last put never repeats")

# --- Stage 2: the item rides on, and the current -----------------------------------

func _next_stage(one: Dictionary) -> void:
	var checkpoint: Dictionary = one.checkpoint
	var sim := _sim(level, "drift", checkpoint)
	_check(sim._mechanisms.items.pipsport.spot == "eddy" and sim.snapshot().players.p1.carrying == "", "A stage's item_starts places the item afresh")
	var kept := level.duplicate(true)
	kept.stages[1].erase("item_starts")
	var carried := _sim(kept, "drift", checkpoint)
	_check(carried.snapshot().players.p1.carrying == "pipsport" and carried._mechanisms.items.raft.spot == "mooring", "Otherwise the item rides into the next stage as the last one left it")
	var gone := level.duplicate(true)
	gone.stages[1].item_starts = {"pipsport": "away"}
	var away := _sim(gone, "drift", checkpoint)
	_check(CarriedItems.problems(gone).is_empty() and away._mechanisms.items.pipsport == CarriedItems.away() and away.snapshot().players.p1.carrying == "", "item_starts may put an item away: out of the level, held by no one")
	var named := level.duplicate(true)
	named.item_spots[0].id = "away"
	_check(not CarriedItems.problems(named).is_empty(), "No item spot may be named away")

func _current(one: Dictionary) -> void:
	var checkpoint: Dictionary = one.checkpoint
	var a_sim := _sim(level, "drift", checkpoint)
	_check(not a_sim._routes.ferry, "The ferry stays shut while the raft is at its mooring")
	_go(a_sim, TOP)
	_go(a_sim, FOOT)
	_go(a_sim, [-350, -60])
	var turn := _tap(a_sim)
	var items: Dictionary = a_sim._mechanisms.items
	_check(a_sim._mechanisms.controls.current == "north" and items.raft.spot == "berth" and items.pipsport.spot == "landing" and a_sim._routes.ferry, "Turned north, the current takes the raft to its berth (the ferry opens) and the pipsport to the landing")
	_tap(a_sim)
	_tap(a_sim)
	_check(a_sim._mechanisms.controls.current == "north" and a_sim._mechanisms.items.pipsport.spot == "landing", "One leg per turn: nothing leaves the landing or the berth")
	var a := _record(a_sim)
	var b_sim := _sim(level, "drift", checkpoint, a)
	_until(b_sim, turn)
	_check(b_sim._mechanisms.items.pipsport.spot == "eddy", "Before the replay turns the wheel the pipsport bobs in the eddy")
	_until(b_sim, turn + 1)
	_check(b_sim._mechanisms.items.pipsport.spot == "landing" and b_sim._mechanisms.items.raft.spot == "berth", "The replay's turn of the wheel moves both in the live world")
	_check(proof._verify_raw(level, a, checkpoint, {}).valid, "The current's turn replays exactly")
	# The sluice board, held, stops the pipsport's leg; the raft still goes.
	var held: Dictionary = checkpoint.duplicate(true)
	held.players.p1 = {"x": -350, "z": 300, "height": 0, "surface_id": "quay"}
	var stop := _sim(level, "drift", held)
	_go(stop, TOP)
	_go(stop, FOOT)
	_go(stop, [-350, -60])
	_tap(stop)
	_check(stop._mechanisms.items.raft.spot == "berth" and stop._mechanisms.items.pipsport.spot == "eddy", "Someone on the sluice board stops the pipsport's leg")
	_tap(stop)
	_tap(stop)
	_check(stop._mechanisms.items.pipsport.spot == "eddy", "And keeps stopping it while held")
	# Turn 2: the live pip on the board lets go once the replay has turned the wheel north.
	var stop_a := _record(stop)
	var release := _sim(level, "drift", held, stop_a)
	_until(release, int(stop_a.duration_ticks))
	_check(release._mechanisms.controls.current == "north" and release._mechanisms.items.pipsport.spot == "eddy", "The live pip holds the board through the replay's turns")
	_go(release, [-250, 300])
	_check(release._mechanisms.items.pipsport.spot == "landing", "Let go of the board, the pipsport drifts on with the water still running north")
	# A leg that needs the raft at its berth waits for it, then goes.
	var waits := level.duplicate(true)
	waits.stages[1].current_legs[1].erase("stop")
	waits.stages[1].current_legs[1]["when"] = {"item_id": "raft", "spot_id": "berth"}
	var gate := _sim(waits, "drift", checkpoint)
	_go(gate, TOP)
	_go(gate, FOOT)
	_go(gate, [-350, -60])
	gate.step({})
	gate.step({"interact": true})
	_check(gate._mechanisms.items.raft.spot == "berth" and gate._mechanisms.items.pipsport.spot == "eddy", "The tick the wheel turns, the raft reaches its berth first")
	gate.step({})
	_check(gate._mechanisms.items.pipsport.spot == "landing", "Once the leg's need holds, the pipsport goes on without another turn")
	# Resting on a leg's start with the wheel already right, it drifts at once;
	# set down there with the wheel right, it drifts at once again.
	var back := level.duplicate(true)
	back.stages[1].item_starts = {"pipsport": "landing"}
	back.stages[1].current_legs = [{"from": "landing", "to": "eddy", "control_id": "current", "value": "north"}, {"from": "eddy", "to": "landing", "control_id": "current", "value": "north"}]
	var quay: Dictionary = checkpoint.duplicate(true)
	quay.players.p0 = {"x": -160, "z": 280, "height": 0, "surface_id": "quay"}
	quay.mechanisms.controls.current = "north"
	var lift := _sim(back, "drift", quay)
	lift.step({})
	_check(lift._mechanisms.items.pipsport.spot == "eddy", "With the wheel already north it leaves the landing on the first tick")
	_still(lift, 5)
	_check(lift._mechanisms.items.pipsport.spot == "eddy", "One leg per turn: the eddy's leg back on the same value waits for the wheel")
	back.stages[1].item_starts = {"pipsport": "p0"}
	var carried := _sim(back, "drift", quay)
	_tap(carried)
	_check(carried._mechanisms.items.pipsport.spot == "eddy" and "item_drifted:pipsport" in carried.snapshot().events, "Set down on the landing with the wheel north, it rides the current at once")
	_two_ways(checkpoint, held)
	_pan(checkpoint)
	_wound(checkpoint)
	_hatch()

## One wheel value, two ways: to the landing while someone holds the sluice
## board, else on to the berth (the reeds).
func _two_ways(checkpoint: Dictionary, held: Dictionary) -> void:
	var forked := level.duplicate(true)
	forked.stages[1].current_legs = [
		{"from": "eddy", "to": "landing", "control_id": "current", "value": "north", "when": {"pad_id": "sluice-board"}},
		{"from": "eddy", "to": "berth", "control_id": "current", "value": "north"},
	]
	for case: Array in [[checkpoint, "berth", "With nobody on the board the pipsport takes the other way"], [held, "landing", "With the board held it comes to the landing"]]:
		var sim := _sim(forked, "drift", case[0])
		_go(sim, TOP)
		_go(sim, FOOT)
		_go(sim, [-350, -60])
		_tap(sim)
		_check(sim._mechanisms.items.pipsport.spot == case[1], case[2])

## A pan (train/new-pieces-b's pan block): held by a pip on it or the
## pipsport resting in it.
func _pan(checkpoint: Dictionary) -> void:
	var panned := level.duplicate(true)
	panned.item_spots.append({"id": "pan", "surface_id": "dock", "position_cm": [-200, 60], "height_cm": 0})
	panned.stages[1].pressure_pads.append({"id": "pan", "surface_id": "dock", "position_cm": [-200, 60], "height_cm": 0, "radius_cm": 28})
	panned.stages[1].item_starts = {"pipsport": "post"}
	var weight := {"any": [{"pad_id": "pan"}, {"item_id": "pipsport", "spot_id": "pan"}]}
	var sim := _sim(panned, "drift", checkpoint)
	_go(sim, TOP)
	_go(sim, FOOT)
	_go(sim, [-350, 0])
	_go(sim, POST)
	_tap(sim)
	_go(sim, [-350, 0])
	_go(sim, [-200, 0])
	var holds := func() -> bool: return Seven.predicate(weight, sim.stage, sim._players, sim._mechanisms, {}, true)
	_check(not holds.call(), "An empty pan holds nothing")
	_go(sim, [-200, 60])
	_check(holds.call(), "A pip in the pan weighs it down")
	_tap(sim)
	_go(sim, [-200, -40])
	_check(sim._mechanisms.items.pipsport.spot == "pan" and holds.call(), "The pipsport left in the pan weighs it down by itself")

## A leg with no wheel: a sack lift wound while someone stands on the winding board.
func _wound(checkpoint: Dictionary) -> void:
	var wound := level.duplicate(true)
	wound.stages[1].item_starts = {"pipsport": "landing"}
	wound.stages[1].current_legs = [{"from": "landing", "to": "eddy", "when": {"pad_id": "sluice-board"}}]
	_check(CarriedItems.problems(wound).is_empty(), "A leg with no wheel and a when is sound")
	var free := _sim(wound, "drift", checkpoint)
	_still(free, 3)
	_check(free._mechanisms.items.pipsport.spot == "landing", "Nobody on the winding board, the lift stays down")
	var on: Dictionary = checkpoint.duplicate(true)
	on.players.p1 = {"x": -350, "z": 300, "height": 0, "surface_id": "quay"}
	var turning := _sim(wound, "drift", on)
	turning.step({})
	_check(turning._mechanisms.items.pipsport.spot == "eddy", "Someone on the winding board winds it along")
	var bad := wound.duplicate(true)
	bad.stages[1].current_legs[0].erase("when")
	_check(not CarriedItems.problems(bad).is_empty(), "A leg with neither a wheel nor a when is refused")

## A hand up needs its crossing open: a bolted trapdoor stops it.
func _hatch() -> void:
	var bolted := level.duplicate(true)
	bolted.stages[0].levers = [{"id": "bolt", "surface_id": "loft", "position_cm": [100, -80], "height_cm": 48, "radius_cm": 28}]
	bolted.stages[0].gates = [{"route_id": "ladder", "when": {"lever_id": "bolt"}}]
	bolted.stages[0].item_starts = {"pipsport": "p0"}
	var below: Dictionary = start.duplicate(true)
	below.players.p0 = {"x": FOOT[0], "z": FOOT[1], "height": 0, "surface_id": "dock"}
	below.players.p1 = {"x": TOP[0], "z": TOP[1], "height": 48, "surface_id": "loft"}
	var shut := _sim(bolted, "hand-up", below)
	shut.step({})
	_check(shut.context_action().id == "put", "With the trapdoor bolted the pipsport cannot be handed up")
	below.mechanisms.levers = {"bolt": true}
	var open := _sim(bolted, "hand-up", below)
	open.step({})
	_check(open.context_action().id == "give", "Unbolted, it can be handed up")
	_check(CarriedItems.can_hand(level, {"ladder": true}, below.players.p0, below.players.p1, {"ladder": true}) and not CarriedItems.can_hand(level, {"ladder": true}, below.players.p0, below.players.p1, {}), "can_hand asks the crossing to be open")

# --- Items ride platforms (core/journey/simulation.gd _move_platforms) -------------

## The replay puts the pipsport down on the raft; the live pip's pull carries it over.
func _raft_ride() -> void:
	var ride := RideWitness.definition()
	var shore := RideWitness.initial_checkpoint(ride)
	shore.players.p1 = {"x": 300, "z": 880, "height": 0, "surface_id": "isle"}
	var a_sim := _sim(ride, "home", shore)
	_go(a_sim, [200, 440])
	_check(a_sim._players.p0.surface_id == "raft-north" and a_sim.context_action().id == "put", "On the raft the carrier may put the pipsport down")
	var put := _tap(a_sim)
	var state: Dictionary = a_sim._mechanisms.items.pipsport
	_check(state.holder == "" and state.surface_id == "raft-north" and int(state.x) == 200 and int(state.z) == 440, "Put down on the raft, it rests at the pip's feet: %s" % [state])
	_go(a_sim, [200, 300])
	_still(a_sim, 10)
	var b_sim := _sim(ride, "home", shore, _record(a_sim))
	_until(b_sim, put + 2)
	_check(b_sim._mechanisms.items.pipsport.surface_id == "raft-north", "The replay puts it down on the raft in the live world")
	_tap(b_sim)
	state = b_sim._mechanisms.items.pipsport
	_check(b_sim._mechanisms.controls.rope == "SOUTH" and state.surface_id == "raft-south" and int(state.z) == 660 and int(state.x) == 200 and "rode:raft" in b_sim._events, "The live pip's pull carries it over the water: %s" % [state])
	_go(b_sim, [200, 690])
	_check(b_sim._players.p1.surface_id == "raft-south" and b_sim.context_action().id == "take", "At the far stop it may be picked up again")
	_tap(b_sim)
	_check(b_sim._mechanisms.items.pipsport.holder == "p1", "And it is")

## The lift witness through the real proof: the replay's put rides up, is
## taken at the top, put back, and rides down when the replay leaves the pan.
func _lift_ride() -> void:
	var ride := RideWitness.definition()
	var begin := RideWitness.initial_checkpoint(ride)
	var ride_proof := Proof.new(RideWitness, Simulation, RULES, Simulation.CURRENT_SIMULATION_VERSION)
	_check(CarriedItems.problems(ride).is_empty() and PiecesRules.problems(ride).is_empty(), "The item ride witness is sound")
	# Put down in the bottom pan, the pipsport alone is the weight that sends the lift up.
	var weighed := _sim(ride, "home", begin)
	_go(weighed, RideWitness.PAN)
	_tap(weighed)
	_go(weighed, [200, 200])
	_check(weighed._mechanisms.items.pipsport.spot == "pan" and bool(weighed._routes["lift-high"]), "The pipsport alone in the bottom pan still sends the lift up")
	# Turn 1: p0 puts the pipsport on the lift, stands in the pan, then climbs to the lamp.
	var a_sim := _sim(ride, "home", begin)
	_go(a_sim, [450, 200])
	_tap(a_sim)
	_check(a_sim._mechanisms.items.pipsport.surface_id == "lift-low", "Put down on the lift")
	_go(a_sim, RideWitness.PAN)
	var state: Dictionary = a_sim._mechanisms.items.pipsport
	_check(bool(a_sim._routes["lift-high"]) and state.surface_id == "lift-high" and int(state.height) == 96 and int(state.x) == 450, "Weight in the pan sends the lift up with the pipsport on it: %s" % [state])
	_until(a_sim, 400)
	_go(a_sim, [60, 350])
	_check(a_sim._mechanisms.items.pipsport.surface_id == "lift-low" and not bool(a_sim._routes["lift-high"]), "Out of the pan, the lift comes down with it: the pipsport on the lift weighs no pan")
	_go(a_sim, [600, 350])
	_go(a_sim, RideWitness.LAMP)
	_check(a_sim._players.p0.surface_id == "stilts", "The empty pip climbs the rope ladder")
	_still(a_sim, 10)
	var a := _record(a_sim)
	# Turn 2: p1 takes it off the lift at the top, puts it back, and it rides down.
	var b_sim := _sim(ride, "home", begin, a)
	_go(b_sim, [700, 200])
	_until(b_sim, 150)
	_go(b_sim, [460, 200])
	_check(b_sim._players.p1.surface_id == "lift-high" and b_sim.context_action().id == "take", "The replay's put rode up: the live pip may pick it up at the top")
	_tap(b_sim)
	_check(b_sim._mechanisms.items.pipsport.holder == "p1", "And takes it")
	_go(b_sim, [600, 200])
	_go(b_sim, [460, 200])
	_check(b_sim.context_action().id == "put", "Back on the lift it may put it down again")
	_tap(b_sim)
	_go(b_sim, RideWitness.LAMP)
	_until(b_sim, 420)
	state = b_sim._mechanisms.items.pipsport
	_check(state.surface_id == "lift-low" and int(state.height) == 0 and int(state.x) == 460 and int(state.z) == 200, "The replay leaves the pan and the lift takes the pipsport down: %s" % [state])
	_settle(b_sim)
	_check(b_sim.complete, "Both pips at the lamp close the stage (%s)" % b_sim.commit_reason())
	var b := _record(b_sim)
	for pair: Array in [[a, {}], [b, a]]:
		var checked: Dictionary = ride_proof._verify_raw(ride, pair[0], begin, pair[1])
		_check(checked.valid, "Item ride turn %s replays exactly (%s)" % [pair[0].role, checked.get("error", "")])
	MemoryTrace.enabled = false
	var again := _sim(ride, "home", begin, a)
	_replay(again, b)
	MemoryTrace.enabled = true
	_check(Canonical.same(_record(again), b), "Item ride turn 2 plays the same from its kept start world as with turn 1 played again")
	var derived: Dictionary = ride_proof.derive_checkpoint(ride, begin, a, b, [])
	_check(derived.valid, "The item ride checkpoint derives (%s)" % derived.get("error", ""))
	if not derived.valid: return
	var checkpoint: Dictionary = _json(derived.checkpoint)
	_check(checkpoint.mechanisms.items.pipsport.surface_id == "lift-low" and ride_proof.verify_checkpoint(ride, checkpoint).valid, "It rests on the lift in the closing checkpoint, which verifies again")
	_write_files(RIDE_FIXTURES, {"definition.json": ride, "initial.json": begin, "a.json": a, "b.json": b, "checkpoint.json": checkpoint})

# --- The server's witness ----------------------------------------------------------

func _server_files(one: Dictionary) -> void:
	_write_files(SERVER_FIXTURES, {"definition.json": level, "initial.json": start, "a.json": one.a, "b.json": one.b, "c.json": one.c, "d.json": one.d, "checkpoint.json": one.checkpoint})

## Checks the server's copy in `dir` is `files`; `-- --write` writes it first.
func _write_files(dir: String, files: Dictionary) -> void:
	var write := "--write" in OS.get_cmdline_user_args()
	if write: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for name: String in files:
		var path := dir.path_join(name)
		var text := JSON.stringify(_json(files[name]), "  ", false) + "\n"
		if write:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(text)
			file.close()
		var kept := FileAccess.get_file_as_string(path)
		_check(JSON.parse_string(kept) != null and Canonical.same(JSON.parse_string(kept), _json(files[name])), "The server's witness %s is this suite's (-- --write to write it)" % name)

# --- Helpers -----------------------------------------------------------------------

func _sim(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior: Dictionary = {}, chain: Array = []) -> RefCounted:
	var sim := Simulation.new()
	sim.simulation_version = int(definition.simulation_version)
	# Open turns rooms record packed (core/v2/recording_codec.gd), as the server asks.
	sim.packed_recordings = true
	sim._reset_trusted(definition, stage_id, checkpoint, prior, "a" if prior.is_empty() else "b", chain)
	return sim

## Walks the live pip to `target`, x first then z; stops when it stops moving.
func _go(sim: RefCounted, target: Array) -> void:
	for axis: String in ["x", "z"]:
		var stuck := 0
		for _step in range(400):
			if sim.finished: return
			var player: Dictionary = sim._players[sim.active_slot]
			var distance := int(target[0 if axis == "x" else 1]) - int(player[axis])
			if absi(distance) <= 1: break
			var before := Vector2i(int(player.x), int(player.z))
			sim.step({"move_" + axis: clampf(float(distance) / 8.0, -1.0, 1.0)})
			var after: Dictionary = sim._players[sim.active_slot]
			stuck = stuck + 1 if Vector2i(int(after.x), int(after.z)) == before else 0
			if stuck >= 3: break

## A press: a still tick, then the button. Returns the tick it pressed on.
func _tap(sim: RefCounted) -> int:
	sim.step({})
	var at := int(sim.tick)
	sim.step({"interact": true})
	return at

func _still(sim: RefCounted, count: int) -> void:
	for _step in range(count):
		if sim.finished: return
		sim.step({})

func _until(sim: RefCounted, at: int) -> void:
	while int(sim.tick) < at and not sim.finished: sim.step({})

## Stands still until the stage completes or the turn ends.
func _settle(sim: RefCounted) -> void:
	for _step in range(1300):
		if sim.finished: return
		sim.step({})

func _replay(sim: RefCounted, record: Dictionary) -> void:
	for input: Dictionary in Simulation.expand_recording_inputs(record): sim.step(input)

func _record(sim: RefCounted) -> Dictionary:
	return _json(sim.export_recording())

func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)
