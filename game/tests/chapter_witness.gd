extends RefCounted
## A chapter played through with real inputs, one stage at a time: the source
## turn, then the receiver turn against it, then the checkpoint the proof
## derives. Not a state injection or a solver.
##
## A chapter's witness (tests/<chapter>_witness.gd) extends this file and
## declares KEY and ROUTES: per stage {"a": steps, "b": steps}, where a step is
## ["walk", [x cm, z cm]], ["tap"] or ["wait", ticks] (cooperative_witness.gd's
## walk, tap and wait_ticks). A witness may instead override chapter().
const Registry = preload("res://services/chapter_registry.gd")
const Walk = preload("res://tests/cooperative_witness.gd")

func key() -> String:
	return str(get_script().get_script_constant_map().get("KEY", ""))

## {"definition", "checkpoints" (initial first), "pairs": [{"a", "b"}], "error"}.
func chapter() -> Dictionary:
	var chapter_key := key()
	var routes: Array = get_script().get_script_constant_map().get("ROUTES", [])
	var level := Registry.definition(chapter_key)
	var simulation: Script = Registry.simulation_script(chapter_key)
	var checkpoint := Registry.initial_checkpoint(chapter_key)
	var result := {"definition": level, "checkpoints": [checkpoint], "pairs": [], "error": ""}
	if level.is_empty() or routes.size() != level.stages.size():
		result.error = "%d routes for %d stages of %s" % [routes.size(), level.get("stages", []).size(), chapter_key]
		return result
	for index in range(level.stages.size()):
		var stage_id: String = level.stages[index].id
		var a: RefCounted = simulation.new()
		if not Registry.reset_simulation(a, chapter_key, level, stage_id, checkpoint, {}, "a"):
			result.error = "Source could not start %s: %s" % [stage_id, a.error]
			return result
		_play(a, routes[index].a)
		if not a.error.is_empty() or not a.can_commit():
			result.error = "Source route failed %s: %s %s" % [stage_id, a.error, a.commit_reason()]
			return result
		var first: Dictionary = a.export_recording()
		var b: RefCounted = simulation.new()
		if not Registry.reset_simulation(b, chapter_key, level, stage_id, checkpoint, first, "b"):
			result.error = "Receiver could not start %s: %s" % [stage_id, b.error]
			return result
		_play(b, routes[index].b)
		# The receiver may finish before the recorded source does; real ticks run it out.
		for _tick in range(Walk.Simulation.MAX_TICKS):
			if b.finished or not b.snapshot().get("objective_done", false): break
			b.step({})
		if not b.error.is_empty() or not b.complete or not b.can_commit():
			result.error = "Receiver route failed %s: %s %s" % [stage_id, b.error, b.commit_reason()]
			return result
		var second: Dictionary = b.export_recording()
		var derived: Dictionary = simulation.derive_checkpoint(level, checkpoint, first, second)
		if not derived.valid:
			result.error = "Checkpoint failed %s: %s" % [stage_id, derived.get("error", "")]
			return result
		result.pairs.append({"a": first, "b": second})
		checkpoint = derived.checkpoint
		result.checkpoints.append(checkpoint)
	return result

static func _play(sim: RefCounted, steps: Array) -> void:
	for step: Array in steps:
		match str(step[0]):
			"walk": Walk.walk(sim, step[1])
			"tap": Walk.tap(sim)
			"wait": Walk.wait_ticks(sim, int(step[1]))
