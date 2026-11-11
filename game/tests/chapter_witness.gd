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
## row per stage: {"id", "ok", "error", "a_ticks", "b_ticks", "msec"}; after a
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
			result.stages.append({"id": stage_id, "ok": false, "error": "not reached", "a_ticks": 0, "b_ticks": 0, "msec": 0})
			continue
		var started := Time.get_ticks_msec()
		var played := _stage(chapter_key, level, stage_id, checkpoint, stage_routes.get(stage_id))
		var row := {"id": stage_id, "ok": played.error.is_empty(), "error": played.error, "a_ticks": played.a_ticks, "b_ticks": played.b_ticks, "msec": Time.get_ticks_msec() - started}
		result.stages.append(row)
		if not played.error.is_empty():
			result.error = "%s/%s: %s" % [chapter_key, stage_id, played.error]
			continue
		result.pairs.append({"a": played.a, "b": played.b})
		checkpoint = played.checkpoint
		result.checkpoints.append(checkpoint)
	return result

static func _stage(chapter_key: String, level: Dictionary, stage_id: String, checkpoint: Dictionary, route: Variant) -> Dictionary:
	var result := {"error": "", "a_ticks": 0, "b_ticks": 0}
	if not route is Dictionary or not route.get("a") is Array or not route.get("b") is Array:
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
	var problem := _play(a, route.a)
	result.a_ticks = int(a.tick)
	if not problem.is_empty() or not a.error.is_empty() or not a.can_commit():
		result.error = "the first turn did not finish its part at tick %d: %s" % [a.tick, " ".join([problem, a.error, a.commit_reason()]).strip_edges()]
		return result
	var first: Dictionary = a.export_recording()
	var b: RefCounted = simulation.new()
	if not Registry.reset_simulation(b, chapter_key, level, stage_id, checkpoint, first, "b", rules):
		result.error = "the second turn could not start: " + str(b.error)
		return result
	b.catch_assistance = "b" not in unassisted
	problem = _play(b, route.b)
	# The receiver may finish before the recorded source does; real ticks run it out.
	for _tick in range(int(b.duration_limit()) if b.has_method("duration_limit") else Walk.Simulation.MAX_TICKS):
		if b.finished or not b.snapshot().get("objective_done", false): break
		b.step({})
	result.b_ticks = int(b.tick)
	if not problem.is_empty() or not b.error.is_empty() or not b.complete or not b.can_commit():
		result.error = "the second turn did not finish the stage at tick %d: %s" % [b.tick, " ".join([problem, b.error, b.commit_reason()]).strip_edges()]
		return result
	var second: Dictionary = b.export_recording()
	# The proof reads the pair as JSON, as a room or a save hands it over.
	var derived: Dictionary = simulation.derive_checkpoint(level, _json(checkpoint), _json(first), _json(second))
	if not derived.valid:
		result.error = "the checkpoint failed: " + str(derived.get("error", ""))
		return result
	result.merge({"a": first, "b": second, "checkpoint": derived.checkpoint})
	return result

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
