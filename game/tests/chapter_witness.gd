extends RefCounted
## A chapter played through with real inputs, one stage at a time: the source
## turn, then the receiver turn against it, then the checkpoint the proof
## derives. Not a state injection or a solver.
##
## A chapter's witness (tests/<chapter>_witness.gd) extends this file and
## declares KEY. Its routes are data in tests/routes/<KEY>.json:
## {stage id: {"a": steps, "b": steps}}, where a step is ["walk", [x cm, z cm]],
## ["tap"], ["wait", ticks] (cooperative_witness.gd's walk, tap and wait_ticks)
## or ["input", ticks, x, z, action]: one run of a recording's actions, held
## for exactly that many ticks. scripts/chapter_recording.py writes the input
## runs of a real run. A stage may also name the "rules" it was played on and
## the turns played with Forgiving catches off ("no_catch_assistance": ["a"]).
## On open turns (core/physical/open_turns.gd) a stage may instead list every
## turn in order, {"turns": [steps, steps, ...]}: the first turn, then each
## later one over the turn before it (which nests the rest); every later turn
## but the last passes once its memory is over, and the last finishes the
## stage. {"a", "b"} is the same as two turns.
## A witness may instead override chapter().
const Registry = preload("res://services/chapter_registry.gd")
const Walk = preload("res://tests/cooperative_witness.gd")
const ROUTES_DIR := "res://tests/routes/"
const STEP_KINDS := ["walk", "tap", "wait", "input"]

func key() -> String:
	return str(get_script().get_script_constant_map().get("KEY", ""))

static func routes_path(chapter_key: String) -> String:
	return ROUTES_DIR + chapter_key + ".json"

## The chapter's routes by stage id, or {} when its file is missing or unreadable.
static func routes(chapter_key: String) -> Dictionary:
	var path := routes_path(chapter_key)
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

## {"definition", "checkpoints" (initial first), "pairs": [{"a", "b"}], "error", "stages"}.
func chapter() -> Dictionary:
	var chapter_key := key()
	if routes(chapter_key).is_empty():
		var empty := {"definition": Registry.definition(chapter_key), "checkpoints": [], "pairs": [], "stages": []}
		empty.error = "%s has no routes: %s is missing or unreadable" % [chapter_key, routes_path(chapter_key)]
		return empty
	return play(chapter_key, routes(chapter_key))

## Plays `stage_routes` ({stage id: {"a", "b"}}) through every stage of the
## chapter, each from the checkpoint the stage before derived. "stages" has one
## row per stage: {"id", "ok", "error", "turns", "a_ticks", "b_ticks", "msec"}; after a
## stage fails, the later ones are "not reached". "error" is the first failure,
## naming the chapter and stage.
static func play(chapter_key: String, stage_routes: Dictionary) -> Dictionary:
	var level := Registry.definition(chapter_key)
	var checkpoint := Registry.initial_checkpoint(chapter_key)
	var result := {"definition": level, "checkpoints": [checkpoint], "pairs": [], "error": "", "stages": []}
	if level.is_empty():
		result.error = "%s is not a registered chapter" % chapter_key
		return result
	for stage: Dictionary in level.stages:
		var stage_id: String = stage.id
		if not result.error.is_empty():
			result.stages.append({"id": stage_id, "ok": false, "error": "not reached", "turns": 0, "a_ticks": 0, "b_ticks": 0, "msec": 0})
			continue
		var started := Time.get_ticks_msec()
		var played := _stage(chapter_key, level, stage_id, checkpoint, stage_routes.get(stage_id))
		var row := {"id": stage_id, "ok": played.error.is_empty(), "error": played.error, "turns": played.get("turns", []).size(), "a_ticks": played.a_ticks, "b_ticks": played.b_ticks, "msec": Time.get_ticks_msec() - started}
		result.stages.append(row)
		if not played.error.is_empty():
			result.error = "%s/%s: %s" % [chapter_key, stage_id, played.error]
			continue
		result.pairs.append({"a": played.a, "b": played.b, "turns": played.turns})
		checkpoint = played.checkpoint
		result.checkpoints.append(checkpoint)
	return result

static func _stage(chapter_key: String, level: Dictionary, stage_id: String, checkpoint: Dictionary, route: Variant) -> Dictionary:
	var result := {"error": "", "a_ticks": 0, "b_ticks": 0, "turns": []}
	var steps: Array = _turn_steps(route)
	if steps.size() < 2:
		result.error = "no routes for this stage in " + routes_path(chapter_key)
		return result
	var simulation: Script = Registry.simulation_script(chapter_key)
	var rules := {"simulation_version": int(route.rules)} if route.has("rules") else {}
	var unassisted: Array = route.get("no_catch_assistance", [])
	var a: RefCounted = simulation.new()
	if not Registry.reset_simulation(a, chapter_key, level, stage_id, checkpoint, {}, "a", rules):
		result.error = "the first turn could not start: " + str(a.error)
		return result
	a.catch_assistance = "a" not in unassisted
	var problem := _play(a, steps[0])
	result.a_ticks = int(a.tick)
	if not problem.is_empty() or not a.error.is_empty() or not a.can_commit():
		result.error = "the first turn did not finish its part at tick %d: %s" % [a.tick, " ".join([problem, a.error, a.commit_reason()]).strip_edges()]
		return result
	var turns: Array = [a.export_recording()]
	for index in range(1, steps.size()):
		var last := index == steps.size() - 1
		var b: RefCounted = simulation.new()
		if not Registry.reset_simulation(b, chapter_key, level, stage_id, checkpoint, turns[-1], "b", rules, turns.slice(0, turns.size() - 1)):
			result.error = "turn %d could not start: %s" % [index + 1, b.error]
			return result
		b.catch_assistance = "b" not in unassisted
		problem = _play(b, steps[index])
		var limit: int = int(b.duration_limit()) if b.has_method("duration_limit") else Walk.Simulation.MAX_TICKS
		if last:
			# The receiver may finish before the recorded source does; real ticks run it
			# out. On open turns it may also wait at the goal for its memory to arrive.
			var waits: bool = b.has_method("_open_turns") and b._open_turns()
			for _tick in range(limit):
				if b.finished or (not waits and not b.snapshot().get("objective_done", false)): break
				b.step({})
		else:
			# A pass waits out its memory, then hands the stage back.
			for _tick in range(limit):
				if b.finished or b.can_pass(): break
				b.step({})
			if problem.is_empty() and b.error.is_empty() and b.can_pass(): b.pass_turn()
		result.b_ticks = int(b.tick)
		if not problem.is_empty() or not b.error.is_empty() or (last and (not b.complete or not b.can_commit())) or (not last and not b.passed):
			result.error = "turn %d did not %s at tick %d: %s (%s)" % [index + 1, "finish the stage" if last else "pass", b.tick, " ".join([problem, b.error, b.commit_reason()]).strip_edges(), _where(b)]
			return result
		turns.append(b.export_recording())
	# The proof reads the turns as JSON, as a room or a save hands them over.
	var passes: Array = turns.slice(1, turns.size() - 1).map(func(turn: Dictionary) -> Dictionary: return _json(turn))
	var derived: Dictionary = simulation.derive_checkpoint(level, _json(checkpoint), _json(turns[0]), _json(turns[-1]), passes) if not passes.is_empty() else simulation.derive_checkpoint(level, _json(checkpoint), _json(turns[0]), _json(turns[-1]))
	if not derived.valid:
		result.error = "the checkpoint failed: " + str(derived.get("error", ""))
		return result
	result.merge({"a": turns[0], "b": turns[-1], "turns": turns, "checkpoint": derived.checkpoint}, true)
	return result

## Where both pips stand, for a turn that went wrong.
static func _where(sim: RefCounted) -> String:
	var players: Dictionary = sim.snapshot().get("players", {})
	return ", ".join(players.keys().map(func(slot: String) -> String: return "%s at [%d, %d] on %s" % [slot, int(players[slot].x), int(players[slot].z), players[slot].surface_id]))

## A stage route's turns in order: its "turns", else its "a" and "b".
static func _turn_steps(route: Variant) -> Array:
	if not route is Dictionary: return []
	if route.get("turns") is Array:
		return route.turns if route.turns.all(func(turn: Variant) -> bool: return turn is Array) else []
	if route.get("a") is Array and route.get("b") is Array: return [route.a, route.b]
	return []

static func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

## Plays the steps; returns why a step could not be played, or "".
static func _play(sim: RefCounted, steps: Array) -> String:
	for step: Variant in steps:
		if not step is Array or step.is_empty() or str(step[0]) not in STEP_KINDS:
			return "unknown step " + JSON.stringify(step)
		match str(step[0]):
			"walk": Walk.walk(sim, step[1])
			"tap": Walk.tap(sim)
			"wait": Walk.wait_ticks(sim, int(step[1]))
			"input":
				if step.size() != 5: return "an input step is [\"input\", ticks, x, z, action]: " + JSON.stringify(step)
				# Exactly the input a recording's run replays (expand_recording_inputs).
				var input := {"move_x": float(step[2]) / 100.0, "move_z": float(step[3]) / 100.0, "interact": bool(step[4])}
				for _tick in range(int(step[1])):
					if sim.finished: break
					sim.step(input)
	return ""
