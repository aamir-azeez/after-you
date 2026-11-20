extends SceneTree
## The shared ball (core/physical/runtime.gd _shared_ball, rules 17): one ball
## in each turn's world that the live pip and its memory both push.
## - 17 is 14 with the ball: a level with a ball pins it, one without keeps 14,
##   and published Rolling Home keeps its own rules and its hand-off;
## - a memory pushes the ball as it pushed it in its own turn: with the live
##   pip idle the ball takes the same path, tick by tick;
## - a memory hands over only its own pip's pushes: a third turn never sees
##   the first turn's;
## - on a tick both push, the memory's push lands first and the live pip
##   pushes from there;
## - the ball fits its cradle in any turn, and a ball home stage ends only with
##   it in and both pips on the cradle's floor;
## - a turn plays the same with its memory's trace and with it simulated.
const Registry = preload("res://services/chapter_registry.gd")
const Cooperative = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const MemoryTrace = preload("res://core/physical/memory_trace.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const KEY := "rolling-home@2"
const BALL := "round-ball"
const EAST := {"move_x": 1.0, "move_z": 0.0}
const SOUTH := {"move_x": 0.0, "move_z": -1.0}
const IDLE := {}
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_numbers()
	_memory_pushes_as_it_pushed()
	_only_its_own_pushes()
	_same_tick()
	_ball_home()
	_kept_under_the_ball()
	_trace_or_simulated()
	print("SHARED BALL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)
	return ok

func _numbers() -> void:
	var level := Registry.definition(KEY)
	_check(OpenControls.SHARED_BALL_RULES == [17] and 17 in OpenControls.OPEN_TURNS_RULES and 17 not in OpenControls.TIDE_RULES and OpenTurns.rules(17), "17 is open turns with the shared ball, without the tide")
	_check(int(level.simulation_version) == 17 and int(Registry.definition("a-house-for-two@2").simulation_version) == 17 and int(Registry.definition("high-and-low@2").simulation_version) == 14, "A level with a ball pins 17 on open turns, one without keeps 14")
	_check(Registry.supported_rules("rolling-home@1") == [6, 8] and not Cooperative.rules_allowed(Registry.definition("rolling-home@1"), 17) and not Cooperative.rules_allowed(level, 14), "Published Rolling Home keeps its rules, and the shared ball plays only on its own")
	_check(Cooperative._record_version({"simulation_version": 17.0}) == 17, "A record names the shared ball rules, JSON floats included")
	var published := Cooperative.new()
	var first: Dictionary = Catalog.initial_checkpoint(Registry.definition("rolling-home@1"))
	_check(published.reset(Registry.definition("rolling-home@1"), "weight-of-a-friend", first, {}, "a", 6) and not published._shared_ball(), "Published rules have no shared ball")

## The first stage's opening with the pips and the ball placed for a test.
## Turns played from it are checked by the engine itself (_reset_trusted).
func _placed(players: Dictionary, ball: Array, stage_index: int = 0) -> Dictionary:
	var level := Registry.definition(KEY)
	var checkpoint: Dictionary = Catalog.initial_checkpoint(level)
	checkpoint.stage_index = stage_index
	checkpoint.next_stage_id = level.stages[stage_index].id
	for slot: String in players:
		checkpoint.players[slot] = {"x": players[slot][0], "z": players[slot][1], "height": 0, "surface_id": players[slot][2]}
	checkpoint.mechanisms.props[BALL].merge({"x": ball[0], "z": ball[1], "surface_id": ball[2]}, true)
	checkpoint.checkpoint_hash = Catalog.checkpoint_hash(checkpoint)
	return checkpoint

## One turn from `checkpoint` playing `inputs`, over `memory` (a turn) and
## `chain` (the turns before it); returns {sim, path (the ball each tick), record}.
func _turn(checkpoint: Dictionary, inputs: Array, memory: Dictionary = {}, chain: Array = []) -> Dictionary:
	var level := Registry.definition(KEY)
	var sim := Cooperative.new()
	sim.simulation_version = 17
	var stage_id := str(checkpoint.next_stage_id)
	sim._reset_trusted(level, stage_id, checkpoint, memory, "a" if memory.is_empty() else "b", chain)
	var path: Array = []
	for input: Dictionary in inputs:
		sim._tick(input)
		var ball: Dictionary = sim._mechanisms.props[BALL]
		path.append([int(ball.x), int(ball.z), str(ball.status)])
	return {"sim": sim, "path": path, "record": sim.export_recording()}

func _repeat(input: Dictionary, count: int) -> Array:
	var result: Array = []
	for _i in range(count): result.append(input)
	return result

## With the live pip standing still, the memory pushes the ball exactly as it
## did when it was the live pip.
func _memory_pushes_as_it_pushed() -> void:
	var opening := _placed({"p0": [-540, 0, "shore"], "p1": [-528, 160, "shore"]}, [-500, 0, "shore"])
	var first := _turn(opening, _repeat(EAST, 20) + _repeat(IDLE, 5))
	var moved: Array = first.path
	_check(int(moved[-1][0]) > -500 + 100, "The first turn rolled the ball east (%s)" % [moved[-1]])
	var second := _turn(opening, _repeat(IDLE, 25), first.record)
	_check(Canonical.same(second.path, moved), "With the live pip still, the memory rolls the ball on the same path, tick by tick")
	_check(Vector2i(second.sim._players.p0.x, second.sim._players.p0.z) == Vector2i(first.sim._players.p0.x, first.sim._players.p0.z), "The memory walks where it walked")

## A third turn's memory is the second turn, whose pip did nothing: the first
## turn's pushes act in the second turn's world only.
func _only_its_own_pushes() -> void:
	var opening := _placed({"p0": [-540, 0, "shore"], "p1": [-528, 160, "shore"]}, [-500, 0, "shore"])
	var first := _turn(opening, _repeat(EAST, 20))
	var second := _turn(opening, _repeat(IDLE, 20), first.record)
	var third := _turn(opening, _repeat(IDLE, 20), second.record, [first.record])
	_check(int(second.path[-1][0]) > -500, "In the second turn the first turn's memory rolls the ball")
	_check(third.path.all(func(at: Array) -> bool: return int(at[0]) == -500 and int(at[1]) == 0), "In the third turn nobody pushes: the first turn's pushes never act again")

## Both push on one tick: the memory rolls the ball east first, into the live
## pip's reach, and the live pip then pushes it south from there. Had the live
## pip gone first it would not have touched the ball (32 cm off to the east).
func _same_tick() -> void:
	var opening := _placed({"p0": [-433, 0, "shore"], "p1": [-368, 26, "shore"]}, [-400, 0, "shore"])
	var first := _turn(opening, [EAST])
	_check(Canonical.same(first.path[0], [-393, 0, "free"]), "The memory alone rolls the ball 7 cm east (%s)" % [first.path[0]])
	var alone := _turn(opening, [SOUTH], _turn(opening, [IDLE]).record)
	_check(Canonical.same(alone.path[0], [-400, 0, "free"]), "The live pip alone, 32 cm east of it, does not touch the ball")
	var both := _turn(opening, [SOUTH], first.record)
	_check(Canonical.same(both.path[0], [-393, -2, "free"]), "On one tick the memory's push lands first and the live pip pushes from there (%s)" % [both.path[0]])

## Bring It Home: the ball fits its cradle in a first turn too, and the stage
## ends only with it in and both pips on the cradle's floor.
func _ball_home() -> void:
	var level := Registry.definition(KEY)
	var cradle: Dictionary = level.stages[1].goal
	var at := int(cradle.position_cm[0])
	var near := _placed({"p0": [at - 100, 0, "home"], "p1": [at - 160, 160, "home"]}, [at - 60, 0, "home"], 1)
	# Bring It Home's first pip is p1; p0's turn is the second.
	near.players.p1 = {"x": at - 100, "z": 0, "height": 0, "surface_id": "home"}
	near.players.p0 = {"x": at - 160, "z": 160, "height": 0, "surface_id": "home"}
	near.checkpoint_hash = Catalog.checkpoint_hash(near)
	var first := _turn(near, _repeat(EAST, 10))
	_check(str(first.path[-1][2]) == "fitted" and int(first.path[-1][0]) == at and not first.sim._objective and not first.sim.complete, "A first turn rolls the ball into its cradle, where it snaps in, and cannot end the stage")
	var second := _turn(near, _repeat(IDLE, 12), first.record)
	_check(second.sim.complete and str(second.sim._mechanisms.props[BALL].socket_id) == str(cradle.id), "The next turn ends the stage: the ball is in and both pips are home")
	var away := near.duplicate(true)
	away.players.p0 = {"x": 900, "z": 160, "height": 0, "surface_id": "far-bank"}
	away.checkpoint_hash = Catalog.checkpoint_hash(away)
	var lone := _turn(away, _repeat(EAST, 10))
	var waiting := _turn(away, _repeat(IDLE, 12), lone.record)
	_check(str(waiting.path[-1][2]) == "fitted" and not waiting.sim.complete, "With one pip off the cradle's floor the ball home does not end the stage")

## A stage's end keeps a crossing the ball rests on, though nothing holds it
## any more, so the next stage never opens with the ball on a crossing that is
## down (the server refuses a ball on a crossing it does not keep).
func _kept_under_the_ball() -> void:
	var bell: Dictionary = Registry.definition(KEY).stages[0].goal
	var at: Array = [int(bell.position_cm[0]), int(bell.position_cm[1]), "far-bank"]
	var opening := _placed({"p0": at, "p1": at}, [-160, 0, "shore-middle"])
	var first := _turn(opening, _repeat(IDLE, 3))
	var closing := _turn(opening, _repeat(IDLE, 5), first.record)
	var kept: Array = closing.sim._mechanisms.latched_bridges
	_check(closing.sim.complete and not bool(closing.sim._routes.get("shore-middle", true)), "The stage ends with both pips at the bell and the shore bridge down under the ball")
	_check("shore-middle" in kept and "middle-far" not in kept, "Its end keeps the crossing under the ball, and only that one (%s)" % [kept])

## A later turn plays the same with its memory's kept trace as with the memory
## simulated again.
func _trace_or_simulated() -> void:
	var opening := _placed({"p0": [-540, 0, "shore"], "p1": [-528, 150, "shore"]}, [-500, 0, "shore"])
	var first := _turn(opening, _repeat(EAST, 15) + _repeat(SOUTH, 5))
	MemoryTrace.clear()
	var proof: RefCounted = Cooperative._proof(17)
	var trace: Dictionary = proof.memory_trace(Registry.definition(KEY), first.record, opening, [])
	_check(not trace.is_empty(), "The first turn's trace is kept")
	# The live pip comes down beside the ball's path and pushes it on east.
	var live := _repeat(SOUTH, 16) + _repeat(EAST, 20)
	var traced := _turn(opening, live, first.record)
	MemoryTrace.enabled = false
	var simulated := _turn(opening, live, first.record)
	MemoryTrace.enabled = true
	_check(int(traced.path[-1][0]) > int(first.path[-1][0]), "The live pip pushed the ball on after the memory did")
	_check(Canonical.same(traced.record, simulated.record) and Canonical.same(traced.path, simulated.path), "A turn plays the same over its memory's trace and over the memory simulated")
