extends RefCounted
## The leaderboard replay check, run offline by the scheduled job
## (tests/leaderboard_replay_job.gd, .github/workflows/leaderboard-check.yml),
## never in the app: tests/ is left out of every export.
##
## A waiting run arrives as the server stored it (backend leaderboards/board.ts
## ReplayWork): its chapter key, its claimed ticks and the room's final
## checkpoint, whose proof nests every pair of the finishing branch. The check:
## - resolves the chapter from the bundled registry only, never from the packet;
## - needs the checkpoint to close the chapter (stage_index == stage count);
## - replays every pair with that chapter family's own verifier,
##   ChapterRegistry.simulation_script(key).verify_checkpoint, which replays
##   each recording and derives each checkpoint exactly;
## - refuses any turn with catch assistance on;
## - measures the run as the sum of every replayed turn's ticks and compares it
##   with the claimed time.
## It proves the recordings are valid and the time is real, not that no retry
## happened on the phone.
const Registry = preload("res://services/chapter_registry.gd")
const Typed = preload("res://services/typed_values.gd")

## {valid, measured_ticks, reason}; reason is "" when valid.
static func check(entry: Dictionary) -> Dictionary:
	var key := Registry.resolve(entry.get("chapter"))
	if key.is_empty(): return _result(false, 0, "unknown_chapter")
	var definition := Registry.definition(key)
	var checkpoint: Variant = entry.get("checkpoint")
	if not checkpoint is Dictionary or definition.is_empty(): return _result(false, 0, "malformed_checkpoint")
	var stages: int = definition.stages.size()
	if not Typed.equal(checkpoint.get("stage_index"), stages): return _result(false, 0, "unfinished_run")
	var engine: Script = Registry.simulation_script(key)
	if engine == null: return _result(false, 0, "unknown_chapter")
	var verified: Dictionary = engine.verify_checkpoint(definition, checkpoint)
	if not verified.get("valid", false): return _result(false, 0, "replay_failed")
	var measured := 0
	var current: Dictionary = checkpoint
	for index in range(stages, 0, -1):
		var proof: Variant = current.get("proof")
		if not Typed.equal(current.get("stage_index"), index) or not proof is Dictionary: return _result(false, measured, "broken_chain")
		for role: String in ["a", "b"]:
			var turn: Variant = proof.get(role)
			if not turn is Dictionary or not Typed.whole_number(turn.get("duration_ticks")): return _result(false, measured, "broken_chain")
			if not Typed.equal(turn.get("catch_assistance"), false): return _result(false, measured, "assisted_run")
			measured += int(turn.duration_ticks)
		current = Registry.previous_checkpoint(key, current)
	if not Typed.equal(current.get("stage_index"), 0): return _result(false, measured, "broken_chain")
	if not Typed.whole_number(entry.get("ticks")) or int(entry.ticks) != measured: return _result(false, measured, "time_mismatch")
	return _result(true, measured, "")

## The verdict the backend's verdicts route takes for one entry.
static func verdict(entry: Dictionary) -> Dictionary:
	var result := check(entry)
	return {"board": str(entry.get("board", "")), "entry_id": str(entry.get("entry_id", "")), "proof_hash": str(entry.get("proof_hash", "")),
		"valid": result.valid, "measured_ticks": result.measured_ticks, "reason": result.reason}

static func _result(valid: bool, measured: int, reason: String) -> Dictionary:
	return {"valid": valid, "measured_ticks": measured, "reason": reason}
