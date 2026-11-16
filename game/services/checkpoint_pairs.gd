extends RefCounted
## The completed pairs nested in a chapter checkpoint. A checkpoint's proof holds
## the stage's two recordings and the checkpoint before it, so the last
## checkpoint of a run nests every stage once. Room history (history_sync.gd)
## and leaderboard replays (leaderboard_replay.gd) rebuild their pairs here.
## Only structure is read; the viewer replay-checks every pair before it plays.
const Registry = preload("res://services/chapter_registry.gd")
const RoomStages = preload("res://services/room_stages.gd")
const Typed = preload("res://services/typed_values.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")

## Stage `stage`'s pair (0-based) as the replay viewer takes it, or {} when the chain does not hold it.
static func pair(chapter_key: String, checkpoint: Dictionary, stage: int, branch: int) -> Dictionary:
	var current := checkpoint
	while Typed.as_int(current.get("stage_index"), -1) > stage + 1:
		current = Registry.previous_checkpoint(chapter_key, current)
		if current.is_empty(): return {}
	return _pair_at(current, stage, branch)

## Every pair from the first stage up to the checkpoint's own, or [] when any link is missing.
static func pairs(chapter_key: String, checkpoint: Dictionary, branch: int) -> Array:
	var stages := Typed.as_int(checkpoint.get("stage_index"), -1)
	if stages < 1 or stages > RoomStages.MAX_STAGES: return []
	var result: Array = []
	var current := checkpoint
	for stage in range(stages - 1, -1, -1):
		var found := _pair_at(current, stage, branch)
		if found.is_empty(): return []
		result.push_front(found)
		if stage > 0:
			current = Registry.previous_checkpoint(chapter_key, current)
			if current.is_empty(): return []
	return result

static func _pair_at(checkpoint: Dictionary, stage: int, branch: int) -> Dictionary:
	if Typed.as_int(checkpoint.get("stage_index"), -1) != stage + 1 or not checkpoint.get("proof") is Dictionary: return {}
	# Open turns nest every turn of the stage; the pair keeps its first and closing turn, the passes stay in its checkpoint.
	var turns := OpenTurns.proof_turns(checkpoint.proof)
	if turns.is_empty(): return {}
	return {"pair_id": "p%d-%d" % [branch, stage], "branch": branch, "stage_index": stage, "a": turns[0].duplicate(true), "b": turns[-1].duplicate(true), "checkpoint": checkpoint.duplicate(true)}

## `engine` (a facade script or proof) derives the checkpoint after `pair`'s
## stage from `previous`, its passes included (OpenTurns.pair_turns). Engines
## without open turns take four arguments.
static func derive(engine: Variant, definition: Dictionary, previous: Dictionary, pair: Dictionary) -> Dictionary:
	var turns := OpenTurns.pair_turns(pair)
	if turns.size() <= 2: return engine.derive_checkpoint(definition, previous, pair.a, pair.b)
	return engine.derive_checkpoint(definition, previous, pair.a, pair.b, turns.slice(1, turns.size() - 1))
