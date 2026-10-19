extends SceneTree
## Wait hints (presentation/wait_hints.gd), through the journey world: in
## the live spirit's turn of a friend's room, a crossing it has done its part
## for says why it is still shut while the memory's part is not there yet.
## - A chapter turns them on with descriptor data alone (a made-up stage and
##   descriptor here).
## - Stage two's boom jetty: the live spirit's part may be a wheel it turned.
## - Turn of the Tide, stage one: the gangway pulled at t331 before the HIGH
##   memory holds the bollard step names the step, and the hint is gone at
##   t416 when jetty-3 opens. Against the LOW memory, t445 still says why;
##   once that memory has ended the crossing stays shut this turn, and it
##   never opens.
## - "Stays shut" is never said while a later memory tick could still open the
##   crossing, across the scripted first turns of both stages.
## - Never in the first turn, nor with hints off; the chapter screen turns
##   them on only for a friend's room's second turn being played.
## - Built hidden once hints are on (never in solo play or replays), not
##   processing while hidden, and never folded into the static scenery: a
##   folded world still shows its hint.
## - Worked out again only when what it reads changes: idle frames and
##   position-only ticks cost nothing.
const Registry = preload("res://services/chapter_registry.gd")
const ChapterIndex = preload("res://content/chapters/index.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Tide = preload("res://tests/turn_of_the_tide_witness.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const WaitHints = preload("res://presentation/wait_hints.gd")
const MemoryWait = preload("res://presentation/memory_wait.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const KEY := "turn-of-the-tide@1"
## B over the jetties in the high window to the gangway, and the pull.
const B_GANGWAY := [["w",[-212,416]],["w",[-212,-326]],["u","route:jetty-1"],["w",[1104,-326]],["t"]]
const PULL_TICK := 331
const OPEN_TICK := 416
const LOW_TICK := 445
var checks := 0
var failures := 0

## The chapter screen with everything but the wait's start left out.
class Preview extends "res://relay_preview.gd":
	pass

## Records what the screen asks of the world's hints.
class HintWorld extends Node3D:
	var calls: Array = []
	func set_wait_hints(on: bool, ticks: int = -1) -> void: calls.append([on, ticks])

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var digest := Canonical.digest(Registry.definition(KEY))
	_data_alone()
	_turned_wheel()
	_high_memory()
	_low_memory()
	_never_only_when_final()
	_first_turn_and_off()
	_hint_after_fold()
	_screen_wiring()
	_solo_wording()
	_idle_costs_nothing()
	_check(Canonical.digest(Registry.definition(KEY)) == digest, "Hints never change the definition")
	print("WAIT HINTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A made-up stage and descriptor: the hints come from the data alone.
func _data_alone() -> void:
	var stage := {"id": "made-up", "first_player_slot": "p0",
		"controls": [{"id": "water", "owner_slot": "p0", "values": ["low", "high"], "initial": "low"}, {"id": "dial", "owner_slot": "p1", "values": ["a", "b"], "initial": "a"}],
		"levers": [{"id": "pull", "owner_slot": "p1"}, {"id": "own", "owner_slot": "p0"}],
		"pressure_pads": [{"id": "perch", "owner_slot": "p0", "surface_id": "deck", "height_cm": 0, "position_cm": [0, 0], "radius_cm": 20}],
		"gates": [
			{"route_id": "bridge", "when": {"all": [{"lever_id": "pull"}, {"control_id": "water", "value": "high"}, {"pad_id": "perch"}]}},
			{"route_id": "either", "when": {"any": [{"lever_id": "pull"}, {"lever_id": "own"}]}},
			{"route_id": "theirs", "when": {"all": [{"lever_id": "own"}, {"control_id": "water", "value": "high"}]}},
			{"route_id": "dialled", "when": {"all": [{"control_id": "dial", "value": "b"}, {"lever_id": "own"}]}}]}
	var descriptor := {"water_levels": {"water": ["low", "high"]},
		"wait_hints": {"reasons": {"water": {"too_low": "Lift the water for the {crossing}"}, "perch": "Sit on the perch", "own": "Their lever"},
			"fallback": "Not yet", "never": "Shut for good", "crossings": {"bridge": "rope bridge"}}}
	var hints := WaitHints.new()
	hints.setup(stage, descriptor, "crossing")
	hints.set_memory_ticks(100)
	var away := {"surface_id": "deck", "height": 0, "x": 300, "z": 0}
	var on_perch := {"surface_id": "deck", "height": 0, "x": 0, "z": 0}
	var state := {"role": "b", "tick": 10, "players": {"p0": away, "p1": away}, "mechanisms": {"levers": {"pull": false, "own": false}, "controls": {"water": "low", "dial": "a"}}, "bridges": {}}
	hints.update(state)
	_check(hints.shown.is_empty(), "Data alone: nothing while the live spirit has not done its part")
	state.mechanisms = {"levers": {"pull": true, "own": false}, "controls": {"water": "low", "dial": "a"}}
	hints.update(state)
	_check(_texts(hints) == ["Lift the water for the rope bridge"], "Data alone: the memory's first unmet term, its side of the water level and the crossing's name (%s)" % str(_texts(hints)))
	_check(hints.shown.size() == 1 and hints.shown[0].anchor == "pull", "Data alone: the hint stands over the live spirit's lever; an \"any\" gate and gates without its part give none")
	_check(hints.candidates().map(func(candidate: Dictionary) -> String: return candidate.route) == ["bridge", "dialled"] and hints.reachable().reasons == {"water": ["too_low"], "perch": [""], "own": [""]}, "Data alone: the crossings it can hint about and what it can say (%s)" % str(hints.reachable()))
	state.mechanisms = {"levers": {"pull": true, "own": false}, "controls": {"water": "high", "dial": "a"}}
	hints.update(state)
	_check(_texts(hints) == ["Sit on the perch"], "Data alone: the next unmet term in the gate's order")
	state.players = {"p0": on_perch, "p1": away}
	hints.update(state)
	_check(hints.shown.is_empty(), "Data alone: none once the memory's part is there")
	state.players = {"p0": away, "p1": away}
	state.tick = 99
	hints.update(state)
	_check(_texts(hints) == ["Sit on the perch"], "Data alone: while the memory still plays it says why, as a wait")
	state.tick = 100
	hints.update(state)
	_check(_texts(hints) == ["Shut for good"], "Data alone: the never phrase once the memory has ended without its part")
	state.bridges = {"bridge": true}
	hints.update(state)
	_check(hints.shown.is_empty(), "Data alone: none once the crossing is open")
	var none := WaitHints.new()
	none.setup(stage, {"water_levels": descriptor.water_levels}, "crossing")
	_check(none.candidates().is_empty(), "A chapter without wait_hints data has no hints")

## Stage two's boom jetty: the live spirit's part is the tide wheel. Turned
## to high from where the turn began, the hint stands over the wheel; left
## where it began, the wheel is not its doing and nothing shows.
func _turned_wheel() -> void:
	var level := Registry.definition(KEY)
	var stage: Dictionary = level.stages[1]
	var hints := WaitHints.new()
	hints.setup(stage, ChapterIndex.data(KEY), PlayerCopy.WAIT_HINT_CROSSING)
	var controls := {"tide": "high", "basin": "shut", "chamber": "half", "lock": "west"}
	var state := {"role": "b", "players": {}, "mechanisms": {"levers": {}, "controls": controls}, "bridges": {}}
	hints.set_start({"mechanisms": {"controls": {"tide": "low"}}})
	hints.update(state)
	_check(hints.shown.size() == 1 and hints.shown[0].route == "boom-jetty" and hints.shown[0].anchor == "tide" and _texts(hints) == [PlayerCopy.TURN_OF_THE_TIDE_WAIT_BOOM_CHAIN], "Stage two: the tide wheel turned to high, the boom jetty waits on the boom chain (%s)" % str(hints.shown))
	hints.set_start({"mechanisms": {"controls": {"tide": "high"}}})
	hints.update(state)
	_check(hints.shown.is_empty(), "Stage two: a wheel still where the turn began gives no hint")

## The HIGH memory: the step at the pull, nothing once jetty-3 opens.
func _high_memory() -> void:
	var b := _pair("high")
	var world := _world(b)
	var mark: Dictionary = world._wait_marks.get("jetty-3", {})
	_check(not mark.is_empty() and not mark.bubble.visible and not mark.bubble.is_processing() and not mark.dashes.visible, "With hints on, jetty-3's mark is built hidden, not processing")
	var bubble: Node3D = mark.get("bubble")
	_play_to(world, b, PULL_TICK)
	var hints: Array = world.wait_hints()
	_check(b.tick == PULL_TICK, "B pulls the gangway at t%d (t%d)" % [PULL_TICK, b.tick])
	_check(hints.size() == 1 and hints[0].route == "jetty-3" and hints[0].anchor == "gangway", "At the pull the hint names jetty-3 over B's gangway (%s)" % str(hints))
	_check(_texts_of(hints) == [PlayerCopy.TURN_OF_THE_TIDE_WAIT_BOLLARD_STEP.replace("{crossing}", PlayerCopy.TURN_OF_THE_TIDE_CROSSING_JETTY)], "The reason is the bollard step (%s)" % str(_texts_of(hints)))
	_check(bubble.visible and bubble.is_processing() and mark.dashes.visible, "Its bubble and dashes show")
	world.hush_wait_hints(true)
	_check(world.wait_hints().is_empty() and not bubble.visible and not mark.dashes.visible, "Under the fast-forward mark the hint steps aside")
	world.hush_wait_hints(false)
	_check(_texts_of(world.wait_hints()) == _texts_of(hints) and bubble.visible and mark.dashes.visible, "And it comes back as the mark goes")
	_check("\n" in bubble.labels[0].text and bubble.labels[0].text.replace("\n", " ") == _texts_of(hints)[0], "The sentence keeps its own case on two lines")
	while not bool(b._routes.get("jetty-3", false)) and not b.finished: world.present(b.step({}), false)
	_check(b.tick == OPEN_TICK, "jetty-3 opens at t%d (t%d)" % [OPEN_TICK, b.tick])
	_check(world.wait_hints().is_empty() and not bubble.visible and not bubble.is_processing() and not mark.dashes.visible, "At t%d the hint is gone" % b.tick)
	_check(world._wait_marks["jetty-3"].bubble == bubble, "Its mark is kept hidden, not freed")
	world.free()

## The LOW memory never holds the bollard step at high water. At t445 it
## still plays, so the hint says why; once it has ended, the crossing stays
## shut this turn, and it never opens.
func _low_memory() -> void:
	var b := _pair("low")
	var world := _world(b)
	_play_to(world, b, LOW_TICK)
	var why := PlayerCopy.TURN_OF_THE_TIDE_WAIT_TIDE_LOW.replace("{crossing}", PlayerCopy.TURN_OF_THE_TIDE_CROSSING_JETTY)
	_check(_texts_of(world.wait_hints()) == [why], "At t%d on the LOW memory the tide is too low for jetty-3 (%s)" % [b.tick, str(world.wait_hints())])
	var length := MemoryWait.prior_ticks(b._prior)
	while b.tick < length and not b.finished: world.present(b.step({}), false)
	var shut := PlayerCopy.TURN_OF_THE_TIDE_WAIT_STAYS_SHUT.replace("{crossing}", PlayerCopy.TURN_OF_THE_TIDE_CROSSING_JETTY)
	_check(_texts_of(world.wait_hints()) == [shut], "Once the LOW memory ends at t%d, jetty-3 stays shut this turn (%s)" % [length, str(world.wait_hints())])
	var opened := false
	while not b.finished:
		b.step({})
		opened = opened or bool(b._routes.get("jetty-3", false))
	_check(not opened, "And it never opens")
	world.free()

## Across every scripted first turn of both stages, with the live spirit's
## part of each crossing done: "stays shut" is never said while the memory
## could still meet its part at a later tick, and is said once it cannot.
func _never_only_when_final() -> void:
	var level := Registry.definition(KEY)
	var initial := Catalog.initial_checkpoint(level)
	var turns: Array = []
	for route: String in Tide.a_routes(): turns.append([Tide.SET, initial, Tide.a_routes()[route], "set-the-tide " + route])
	for history: String in ["low", "half", "high"]:
		var pair := Tide.pair(level, Tide.SET, initial, Tide.a_routes()[history], Tide.b_routes()[history], false)
		if not _check(pair.error.is_empty(), "The %s history plays (%s)" % [history, pair.error]): continue
		for way: String in ["boom", "sea-lock", "punt"]:
			turns.append([Tide.SLACK, pair.checkpoint, Tide.p1_home(history) + Tide.p1_way(history, way), "%s %s" % [history, way]])
			turns.append([Tide.SLACK, pair.checkpoint, Tide.p1_home(history) + Tide.p1_all_chains(history, way), "%s %s all chains" % [history, way]])
		turns.append([Tide.SLACK, pair.checkpoint, Tide.p1_home(history) + Tide.p1_way_sea_first(history, "boom"), "%s boom sea first" % history])
	var never := 0
	var false_never := 0
	for turn: Array in turns:
		var states := _memory_states(level, turn[0], turn[1], turn[2], turn[3])
		if states.is_empty(): continue
		var stage := Simulation.stage_by_id(level, turn[0])
		var probe := WaitHints.new()
		probe.setup(stage, ChapterIndex.data(KEY), PlayerCopy.WAIT_HINT_CROSSING)
		for candidate: Dictionary in probe.candidates():
			var counts := _never_for(stage, turn[1], states, candidate)
			never += counts[0]
			false_never += counts[1]
	_check(false_never == 0, "\"Stays shut\" is never said while a later memory tick could still open the crossing (%d times)" % false_never)
	_check(never > 0, "\"Stays shut\" is said once the memory has ended short (%d ticks across %d turns)" % [never, turns.size()])

## The memory's state at every tick of `ops`, as a second turn sees it.
func _memory_states(level: Dictionary, stage_id: String, checkpoint: Dictionary, ops: Array, label: String) -> Array:
	var a := Tide.source(level, stage_id, checkpoint, ops, 0, Callable(), true)
	if not _check(a.can_commit(), "The %s first turn commits (%s)" % [label, a.get_meta("route_error")]): return []
	var recording: Dictionary = a.export_recording()
	var replay := Simulation.new()
	replay.simulation_version = Tide.RULES
	replay._reset_trusted(level, stage_id, checkpoint, {}, "a")
	var states: Array = [replay.snapshot()]
	for frame: Dictionary in Simulation.expand_recording_inputs(recording): states.append(replay.step(frame))
	return states

## One crossing over one memory: [ticks "stays shut" is said, of those, ticks
## where the memory's part still holds at that or a later tick].
func _never_for(stage: Dictionary, checkpoint: Dictionary, states: Array, candidate: Dictionary) -> Array:
	var gate: Dictionary = {}
	for item: Dictionary in stage.gates:
		if item.route_id == candidate.route: gate = item
	var terms: Array = gate.when.all if gate.when.has("all") else [gate.when]
	var owners: Dictionary = {}
	for key: String in ["controls", "levers", "pressure_pads"]:
		for item: Dictionary in stage.get(key, []): owners[str(item.id)] = str(item.owner_slot)
	var memory: Array = terms.filter(func(term: Dictionary) -> bool: return owners[WaitHints.term_id(term)] == stage.first_player_slot)
	var live: Array = terms.filter(func(term: Dictionary) -> bool: return owners[WaitHints.term_id(term)] != stage.first_player_slot)
	var held: Array = states.map(func(state: Dictionary) -> bool: return memory.all(func(term: Dictionary) -> bool: return Seven.predicate(term, stage, state.players, state.mechanisms)))
	var later: Array = held.duplicate()
	for index in range(later.size() - 2, -1, -1): later[index] = later[index] or later[index + 1]
	var hints := WaitHints.new()
	hints.setup(stage, ChapterIndex.data(KEY), PlayerCopy.WAIT_HINT_CROSSING)
	hints.set_start(checkpoint)
	hints.set_memory_ticks(states.size() - 1)
	var crossing := str(ChapterIndex.data(KEY).wait_hints.crossings.get(candidate.route, PlayerCopy.WAIT_HINT_CROSSING))
	var shut := PlayerCopy.TURN_OF_THE_TIDE_WAIT_STAYS_SHUT.replace("{crossing}", crossing)
	var said := 0
	var wrong := 0
	for tick in range(states.size() + 30):
		var at := mini(tick, states.size() - 1)
		hints.update(_live_part_done(states[at], tick, candidate.route, live, held[at]))
		for hint: Dictionary in hints.shown:
			if hint.route != candidate.route or hint.text != shut: continue
			said += 1
			if later[at]: wrong += 1
	return [said, wrong]

## A second turn's snapshot at `tick` over the memory's `state`, with the live
## spirit's part of `route` done: its levers pulled, its selectors set.
static func _live_part_done(state: Dictionary, tick: int, route: String, live: Array, open: bool) -> Dictionary:
	var mechanisms: Dictionary = state.mechanisms.duplicate(true)
	for term: Dictionary in live:
		if term.has("lever_id"): mechanisms.levers[term.lever_id] = true
		elif term.has("control_id"): mechanisms.controls[term.control_id] = term.value
	return {"role": "b", "tick": tick, "players": state.players, "mechanisms": mechanisms, "bridges": {route: open}, "finished": false}

## The first turn never hints, and hints that are off (a replay) show
## nothing.
func _first_turn_and_off() -> void:
	var level := Registry.definition(KEY)
	var checkpoint := Catalog.initial_checkpoint(level)
	var a := Tide.source(level, Tide.SET, checkpoint, Tide.a_routes()["high"], 0, Callable(), true)
	var world_a := _world(a)
	world_a.set_wait_hints(true, MemoryWait.prior_ticks({}))
	world_a.present(a.snapshot(), true)
	for _tick in range(3): world_a.present(a.step({}), false)
	_check(world_a.wait_hint_evaluations() > 0 and world_a.wait_hints().is_empty() and not world_a._wait_marks["jetty-3"].bubble.visible, "Hints on, the first turn still shows none")
	world_a.free()
	var b := _pair("high")
	var world := _world(b, false)
	_play_to(world, b, PULL_TICK)
	_check(world.wait_hints().is_empty() and world._wait_marks.is_empty(), "Hints off (replays): none show, and none are built")
	world.set_wait_hints(true, MemoryWait.prior_ticks(b._prior))
	_check(world._wait_marks.has("jetty-3") and world._bubbles.has(world._wait_marks["jetty-3"].bubble), "Turned on for a stage already shown, the marks are built and placed with the rest")
	world.free()

## A world whose scenery is folded keeps its hint's dashes whole and shows
## them with the bubble.
func _hint_after_fold() -> void:
	var b := _pair("high")
	var world := _world(b)
	var dashes: MeshInstance3D = world._wait_marks["jetty-3"].dashes
	var faces := dashes.mesh.get_faces().size()
	world._bubbles_placed = true
	world.fold_over_frames = false
	world._fold_static_scenery()
	_check(world.terrain.has_meta(StaticBatch.FOLDED_META), "The scenery folds")
	_play_to(world, b, PULL_TICK)
	_check(is_instance_valid(dashes) and dashes.get_parent() == world.terrain and dashes.mesh.get_faces().size() == faces and dashes.visible and world._wait_marks["jetty-3"].bubble.visible, "After the fold the hint shows with its dashes whole")
	world.free()

## The chapter screen turns hints on, with the memory's length, for a second
## turn being played beside a memory: a friend's room or solo play alike
## (WaitHints.wanted), never a first turn or a replay.
func _screen_wiring() -> void:
	var prior := {"duration_ticks": 418}
	var cases := [["a friend's room, second turn", RefCounted.new(), "b", true, [true, 418]],
		["a friend's room, first turn", RefCounted.new(), "a", true, [false, -1]],
		["a friend's room, a memory with no length", RefCounted.new(), "b", true, [true, -1]],
		["a friend's room, a replay", RefCounted.new(), "b", false, [false, 418]],
		["solo play, second turn", null, "b", true, [true, 418]],
		["solo play, first turn", null, "a", true, [false, -1]],
		["solo play, a replay", null, "b", false, [false, 418]]]
	for item: Array in cases:
		var preview := Preview.new()
		var world := HintWorld.new()
		preview.world = world
		preview.settings = {}
		preview.online_session = item[1]
		preview._begin_memory_wait(item[2], prior if item[0].ends_with("second turn") or item[0].ends_with("replay") else {}, item[3])
		var asked: Array = world.calls[-1] if not world.calls.is_empty() else []
		_check(asked.size() == 2 and asked[0] == item[4][0] and (not asked[0] or asked[1] == item[4][1]), "The screen asks for hints %s in %s (%s)" % ["on" if item[4][0] else "off", item[0], str(asked)])
		preview.online_session = null
		world.free()
		preview.free()

## Hints show beside the player's own ghost in solo play too, so no chapter's
## hint names a friend: every phrase reads right whoever left the memory.
func _solo_wording() -> void:
	for key: String in ChapterIndex.keys():
		var hints: Dictionary = ChapterIndex.data(key).get("wait_hints", {})
		var phrases: Array = [hints.get("fallback", ""), hints.get("never", "")] + hints.get("crossings", {}).values()
		for reason: Variant in hints.get("reasons", {}).values():
			phrases.append_array(reason.values() if reason is Dictionary else [reason])
		for phrase: Variant in phrases:
			_check(not str(phrase).to_lower().contains("friend"), "%s: a wait hint reads right beside your own ghost (%s)" % [key, str(phrase)])

## Worked out once per change: idle frames, the same snapshot again and ticks
## where only the spirits walk cost no evaluation.
func _idle_costs_nothing() -> void:
	var b := _pair("high")
	var world := _world(b)
	_play_to(world, b, PULL_TICK)
	var before: int = world.wait_hint_evaluations()
	var state: Dictionary = b.snapshot()
	for _frame in range(30):
		world.present(state, false)
		world._process(1.0 / 60.0)
	_check(world.wait_hint_evaluations() == before, "Idle frames and repeated snapshots re-evaluate nothing (%d)" % (world.wait_hint_evaluations() - before))
	# The memory walks on towards the bollard step; nothing the gate reads moves.
	var walked := 0
	while walked < 8:
		var next: Dictionary = b.step({})
		if next.mechanisms != state.mechanisms or next.hold_pads != state.hold_pads or next.bridges != state.bridges: break
		world.present(next, false)
		walked += 1
	_check(walked > 0 and world.wait_hint_evaluations() == before, "Ticks where only positions change re-evaluate nothing (%d ticks)" % walked)
	world.free()

## A and B of stage one: A's route as a recording, B reset from it.
func _pair(a_route: String) -> Simulation:
	var level := Registry.definition(KEY)
	var checkpoint := Catalog.initial_checkpoint(level)
	var a := Tide.source(level, Tide.SET, checkpoint, Tide.a_routes()[a_route], 0, Callable(), true)
	var b := Simulation.new()
	_check(b.reset(level, Tide.SET, checkpoint, a.export_recording(), "b"), "B's turn starts on the %s memory" % a_route)
	return b

func _world(sim: Simulation, hints: bool = true) -> Node3D:
	var level := Registry.definition(KEY)
	var world: Node3D = Registry.world_script(KEY).new()
	root.add_child(world)
	world.reduced_motion = true
	world.set_process(false)
	world.load_level(level)
	world.show_stage(level.stages[0])
	world.present_history(Catalog.initial_checkpoint(level))
	world.set_wait_hints(hints and sim.role == "b", MemoryWait.prior_ticks(sim._prior))
	return world

## B's gangway route, shown tick by tick, then idle until `tick`.
func _play_to(world: Node3D, b: Simulation, tick: int) -> void:
	world.present(b.snapshot(), true)
	Tide.play(b, B_GANGWAY, func(_label: String, _sim: RefCounted) -> void: pass)
	world.present(b.snapshot(), false)
	while b.tick < tick and not b.finished: world.present(b.step({}), false)

static func _texts(hints: WaitHints) -> Array:
	return _texts_of(hints.shown)

static func _texts_of(shown: Array) -> Array:
	return shown.map(func(hint: Dictionary) -> String: return str(hint.text))

func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	return value
