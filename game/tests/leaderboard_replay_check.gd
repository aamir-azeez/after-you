extends RefCounted
## The leaderboard replay check, run offline by the scheduled job
## (tests/leaderboard_replay_job.gd, .github/workflows/leaderboard-check.yml),
## never in the app: tests/ is left out of every export.
##
## A waiting run arrives as the server stored it (backend leaderboards/board.ts
## ReplayWork): its chapter key, its claimed ticks and the room's final
## checkpoint, whose proof nests every pair of the finishing branch, in the
## shared blob format (`body` in base64 and its `byte_length`,
## services/blob_codec.gd), which must decode to the bytes `proof_hash` names.
## An inline `checkpoint` is still read, as the tests pass it. The check:
## - resolves the chapter from the bundled registry only, never from the packet;
## - needs the checkpoint to close the chapter (stage_index == stage count);
## - replays every pair with that chapter family's own verifier,
##   ChapterRegistry.simulation_script(key).verify_checkpoint, which replays
##   each recording and derives each checkpoint exactly;
## - refuses any turn with catch assistance on, except in a duel's run
##   (`duel: true`, backend duels/store.ts), which may have them;
## - measures the run as the sum of every replayed turn's ticks and compares it
##   with the claimed time.
## It proves the recordings are valid and the time is real, not that no retry
## happened on the phone.
const Registry = preload("res://services/chapter_registry.gd")
const Typed = preload("res://services/typed_values.gd")
const BlobCodec = preload("res://services/blob_codec.gd")
## A stored run's checkpoint is at most this long (backend board.ts MAX_PROOF_CHARS, duels/rules.ts MAX_DUEL_PROOF_CHARS).
const MAX_CHECKPOINT_BYTES := 1_900_000

## {valid, measured_ticks, reason}; reason is "" when valid.
static func check(entry: Dictionary) -> Dictionary:
	var key := Registry.resolve(entry.get("chapter"))
	if key.is_empty(): return _result(false, 0, "unknown_chapter")
	var definition := Registry.definition(key)
	# A body that does not decode to the bytes its hash names is the server's fault, not the run's: a person looks.
	if entry.has("body") and _checkpoint(entry) == null: return _result(false, 0, "replay_error")
	var checkpoint: Variant = _checkpoint(entry)
	if not checkpoint is Dictionary or definition.is_empty(): return _result(false, 0, "malformed_checkpoint")
	var stages: int = definition.stages.size()
	if not Typed.equal(checkpoint.get("stage_index"), stages): return _result(false, 0, "unfinished_run")
	var engine: Script = Registry.simulation_script(key)
	if engine == null: return _result(false, 0, "unknown_chapter")
	var verified: Dictionary = engine.verify_checkpoint(definition, checkpoint)
	if not verified.get("valid", false): return _result(false, 0, "replay_failed")
	var measured := 0
	var assisted_ok := Typed.equal(entry.get("duel"), true)
	var current: Dictionary = checkpoint
	for index in range(stages, 0, -1):
		var proof: Variant = current.get("proof")
		if not Typed.equal(current.get("stage_index"), index) or not proof is Dictionary: return _result(false, measured, "broken_chain")
		for role: String in ["a", "b"]:
			var turn: Variant = proof.get(role)
			if not turn is Dictionary or not Typed.whole_number(turn.get("duration_ticks")): return _result(false, measured, "broken_chain")
			if not assisted_ok and not Typed.equal(turn.get("catch_assistance"), false): return _result(false, measured, "assisted_run")
			measured += int(turn.duration_ticks)
		current = Registry.previous_checkpoint(key, current)
	if not Typed.equal(current.get("stage_index"), 0): return _result(false, measured, "broken_chain")
	if not Typed.whole_number(entry.get("ticks")) or int(entry.ticks) != measured: return _result(false, measured, "time_mismatch")
	return _result(true, measured, "")

## The run's final checkpoint, decoded from its blob body (or inline, as tests pass it).
static func _checkpoint(entry: Dictionary) -> Variant:
	if not entry.has("body"): return entry.get("checkpoint")
	if not entry.body is String or not Typed.whole_number(entry.get("byte_length")): return null
	var bytes := BlobCodec.verified(Marshalls.base64_to_raw(entry.body), int(entry.byte_length), str(entry.get("proof_hash", "")), MAX_CHECKPOINT_BYTES)
	return null if bytes.is_empty() else JSON.parse_string(bytes.get_string_from_utf8())

## The verdict the backend's verdicts route takes for one entry.
static func verdict(entry: Dictionary) -> Dictionary:
	var result := check(entry)
	return {"board": str(entry.get("board", "")), "entry_id": str(entry.get("entry_id", "")), "proof_hash": str(entry.get("proof_hash", "")),
		"valid": result.valid, "measured_ticks": result.measured_ticks, "reason": result.reason}

static func _result(valid: bool, measured: int, reason: String) -> Dictionary:
	return {"valid": valid, "measured_ticks": measured, "reason": reason}
