extends SceneTree
## The level checker understands rules 20's carried items and currents
## (tests/level_graph.gd _reach_items and with_items, used by
## tests/test_level_checker.gd) on the witness level (tests/carried_items_level.gd):
## - stage 1 is solvable with the pipsport handed up the both-hands ladder, and
##   no pip finishes it alone. With the ladder plain, the first pip could carry
##   it up alone while the other waits at the goal, and the probe says so;
## - in the strict one-pip probe (presses_alone) picking up, putting down and
##   handing over are work: the walker never takes the pipsport up the ladder,
##   so neither pip does it all alone; with a plain ladder, or the walker
##   starting with it at the goal, the probe says one pip could;
## - stage 2 is solvable only through the current: the raft's leg opens the
##   ferry and the pipsport's leg brings it to the quay. Without the pipsport's
##   leg it stays in the eddy, without the raft's the ferry never opens.
const LevelGraph = preload("res://tests/level_graph.gd")
const Checker = preload("res://tests/test_level_checker.gd")
const Layout = preload("res://core/cooperative/layout.gd")
const Level = preload("res://tests/carried_items_level.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var level := Level.definition()
	var start := Level.initial_checkpoint(level)
	var second: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/carried_items/checkpoint.json"))
	var plan := Layout.plan(level, "hand-up")
	var graph := _graph(plan)
	_check(Checker.solvable(graph, plan, start, true), "Stage 1 is solvable: the pipsport handed up reaches the loft's goal")
	for slot: String in ["p0", "p1"]:
		_check(not Checker.solo_finish(graph, plan, start, true, slot), "Stage 1: %s never finishes it alone" % slot)
	var alone: Dictionary = graph.reach(plan, start, true, "p1")
	_check(alone.settable["item:pipsport"].carried == ["dock"] and alone.settable["item:pipsport"].spots == ["post"], "Alone, the first pip holds the pipsport only on the dock (%s)" % str(alone.settable.get("item:pipsport")))
	var both: Dictionary = graph.reach(plan, start, true)
	_check(both.settable["item:pipsport"].carried == ["dock", "loft"] and "desk" in both.settable["item:pipsport"].spots, "Together, it is handed up to the loft and may rest at the desk")
	var plain := level.duplicate(true)
	plain.stairs[0].erase("hands")
	var plain_plan := Layout.plan(plain, "hand-up")
	_check(Checker.solo_finish(_graph(plain_plan), plain_plan, start, true, "p0"), "With a plain ladder the first pip carries it up alone while the other waits at the goal, and the probe says so")
	# The strict one-pip probe: picking up, putting down and handing over are
	# work, so the walker never takes the pipsport at the top of the ladder.
	for slot: String in ["p0", "p1"]:
		_check(not Checker.presses_alone(graph, plan, start, true, slot), "Stage 1: %s cannot do every press and pipsport move while the other only walks" % slot)
	_check(Checker.presses_alone(_graph(plain_plan), plain_plan, start, true, "p0"), "With a plain ladder the first pip carries it up while the other only walks, and the strict probe says so")
	var held := level.duplicate(true)
	held.stages[0]["item_starts"] = {"pipsport": "p1"}
	var held_plan := Layout.plan(held, "hand-up")
	_check(Checker.presses_alone(_graph(held_plan), held_plan, start, true, "p0"), "A walker that starts holding the pipsport at the goal needs no one to handle it, and the probe says so")
	var walked: Dictionary = graph.reach(plan, start, true, "", "p1")
	_check(walked.settable["item:pipsport"].carried == ["dock"], "With p1 only walking, the pipsport is held only on the dock (%s)" % str(walked.settable.get("item:pipsport")))
	var drift := Layout.plan(level, "drift")
	var found: Dictionary = _graph(drift).reach(drift, second, true)
	_check(found.open.has("ferry") and "berth" in found.settable["item:raft"].spots and "landing" in found.settable["item:pipsport"].spots and "post" in found.settable["item:pipsport"].spots, "Stage 2: the current takes the raft to its berth (the ferry opens) and the pipsport to the landing, then home to the post box")
	_check(Checker.solvable(_graph(drift), drift, second, true), "Stage 2 is solvable through the current")
	var stuck := level.duplicate(true)
	stuck.stages[1].current_legs.pop_back()
	var stuck_plan := Layout.plan(stuck, "drift")
	_check(not Checker.solvable(_graph(stuck_plan), stuck_plan, second, true), "Without the pipsport's leg it stays in the eddy and the stage cannot finish")
	var moored := level.duplicate(true)
	moored.stages[1].current_legs.pop_front()
	var moored_plan := Layout.plan(moored, "drift")
	var shut: Dictionary = _graph(moored_plan).reach(moored_plan, second, true)
	_check(not shut.open.has("ferry") and not Checker.solvable(_graph(moored_plan), moored_plan, second, true), "Without the raft's leg the ferry never opens")
	print("CARRIED ITEMS CHECKER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The level graph of a plan's floors and crossings, as the checker builds it.
func _graph(plan: Dictionary) -> RefCounted:
	var floors: Dictionary = {"simulation_version": plan.simulation_version}
	for field: String in ["islands", "bridges", "stairs", "drops", "obstacles", "access_zones"]:
		floors[field] = plan.get(field, []).duplicate(true)
	return LevelGraph.new(floors)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)
