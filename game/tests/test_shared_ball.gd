extends SceneTree
## The shared ball (core/physical/runtime.gd _shared_ball, rules 21): one ball
## in the one world that both pips push.
## - 21 is 18 with the ball: a level with a ball pins it, one without keeps 18,
##   and published Rolling Home keeps its own rules and its hand-off;
## - the friend's replay pushes the ball as it pushed it in its own turn: with
##   the live pip idle the ball takes the same path, tick by tick;
## - a third turn starts with the ball where the second left it, and the first
##   turn's pushes never act again;
## - on a tick both push, p0's push lands first and p1 pushes from there;
## - the ball fits its cradle in any turn, and a ball home stage ends only with
##   it in and both pips on the cradle's floor;
## - a turn plays the same from its kept start world and from the turn before
##   played again.
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
	_replay_pushes_as_it_pushed()
	_carried_over()
	_same_tick()
	_ball_home()
	_kept_under_the_ball()
	_kept_or_played()
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
	_check(OpenControls.SHARED_BALL_RULES == [21] and 21 in OpenControls.OPEN_TURNS_RULES and 21 not in OpenControls.TIDE_RULES and OpenTurns.rules(21), "21 is open turns with the shared ball, without the tide")
	_check(int(level.simulation_version) == 21 and int(Registry.definition("a-house-for-two@2").simulation_version) == 21 and int(Registry.definition("high-and-low@2").simulation_version) == 18, "A level with a ball pins 21 on open turns, one without keeps 18")
	_check(Registry.supported_rules("rolling-home@1") == [6, 8] and not Cooperative.rules_allowed(Registry.definition("rolling-home@1"), 21) and not Cooperative.rules_allowed(level, 18), "Published Rolling Home keeps its rules, and the shared ball plays only on its own")
	_check(Cooperative._record_version({"simulation_version": 21.0}) == 21, "A record names the shared ball rules, JSON floats included")
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
	sim.simulation_version = 21
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

## With the live pip standing still, the friend's replay pushes the ball
## exactly as it did when it was the live pip.
func _replay_pushes_as_it_pushed() -> void:
	var opening := _placed({"p0": [-540, 0, "shore"], "p1": [-528, 160, "shore"]}, [-500, 0, "shore"])
	var first := _turn(opening, _repeat(EAST, 20) + _repeat(IDLE, 5))
	var moved: Array = first.path
	_check(int(moved[-1][0]) > -500 + 100, "The first turn rolled the ball east (%s)" % [moved[-1]])
	var second := _turn(opening, _repeat(IDLE, 25), first.record)
	_check(Canonical.same(second.path, moved), "With the live pip still, the replay rolls the ball on the same path, tick by tick")
	_check(Vector2i(second.sim._players.p0.x, second.sim._players.p0.z) == Vector2i(first.sim._players.p0.x, first.sim._players.p0.z), "The replay walks where it walked")

## A third turn takes over where the first ended, in the second turn's world:
## the ball stays where the first turn's replay rolled it, and with both
## turns as long the replay is over, so nobody pushes it again.
func _carried_over() -> void:
	var opening := _placed({"p0": [-540, 0, "shore"], "p1": [-528, 160, "shore"]}, [-500, 0, "shore"])
	var first := _turn(opening, _repeat(EAST, 20))
	var second := _turn(opening, _repeat(IDLE, 20), first.record)
	var third := _turn(opening, _repeat(IDLE, 20), second.record, [first.record])
	var rolled: Array = second.path[-1]
	_check(int(rolled[0]) > -500, "In the second turn the first turn's replay rolls the ball")
	_check(third.sim.handoff_tick == 20 and third.sim.replay_ticks() == 0 and third.path.all(func(at: Array) -> bool: return Canonical.same(at, rolled)), "The third turn starts with the ball where the second left it, and nobody pushes it again")

## Both push on one tick: p0 (the friend's replay here) rolls the ball east
## first, into p1's reach, and p1 (live) then pushes it south from there. Had
## p1 gone first it would not have touched the ball (32 cm off to the east).
func _same_tick() -> void:
	var opening := _placed({"p0": [-433, 0, "shore"], "p1": [-368, 26, "shore"]}, [-400, 0, "shore"])
	var first := _turn(opening, [EAST])
	_check(Canonical.same(first.path[0], [-393, 0, "free"]), "p0 alone rolls the ball 7 cm east (%s)" % [first.path[0]])
	var alone := _turn(opening, [SOUTH], _turn(opening, [IDLE]).record)
	_check(Canonical.same(alone.path[0], [-400, 0, "free"]), "The live pip alone, 32 cm east of it, does not touch the ball")
	var both := _turn(opening, [SOUTH], first.record)
	_check(Canonical.same(both.path[0], [-393, -2, "free"]), "On one tick p0's push lands first and p1 pushes from there (%s)" % [both.path[0]])

## Bring It Home: the ball fits its cradle in a first turn too, and the stage
## ends only with it in and both pips on the cradle's floor.
func _ball_home() -> void:
	var level := Registry.definition(KEY)
	var cradle: Dictionary = level.stages[1].goal
	var at := int(cradle.position_cm[0])
	var near := _placed({"p0": [at - 100, 0, "home"], "p1": [at - 160, 160, "home"]}, [at - 60, 0, "home"], 1)
	var first := _turn(near, _repeat(EAST, 10))
	_check(str(first.path[-1][2]) == "fitted" and int(first.path[-1][0]) == at and not first.sim._objective and not first.sim.complete, "A first turn rolls the ball into its cradle, where it snaps in, and cannot end the stage")
	var second := _turn(near, _repeat(IDLE, 12), first.record)
	_check(second.sim.complete and str(second.sim._mechanisms.props[BALL].socket_id) == str(cradle.id), "The next turn ends the stage: the ball is in and both pips are home")
	var away := near.duplicate(true)
	away.players.p1 = {"x": 900, "z": 160, "height": 0, "surface_id": "far-bank"}
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

## A later turn plays the same from the start world kept when the turn
## before it was checked as from that turn played again.
func _kept_or_played() -> void:
	var opening := _placed({"p0": [-540, 0, "shore"], "p1": [-528, 150, "shore"]}, [-500, 0, "shore"])
	var first := _turn(opening, _repeat(EAST, 15) + _repeat(SOUTH, 5))
	MemoryTrace.clear()
	var proof: RefCounted = Cooperative._proof(21)
	var start: Dictionary = proof.turn_start(Registry.definition(KEY), opening, first.record, [])
	_check(not start.is_empty() and int(start.handoff_tick) == 0, "The first turn hands the second its start world")
	# The live pip comes down beside the ball's path and pushes it on east.
	var live := _repeat(SOUTH, 16) + _repeat(EAST, 20)
	var kept := _turn(opening, live, first.record)
	MemoryTrace.enabled = false
	var played := _turn(opening, live, first.record)
	MemoryTrace.enabled = true
	_check(int(kept.path[-1][0]) > int(first.path[-1][0]), "The live pip pushed the ball on after the replay did")
	_check(Canonical.same(kept.record, played.record) and Canonical.same(kept.path, played.path), "A turn plays the same from its kept start world and from the turn before played again")
