extends RefCounted
## Pure review and network reconciliation decisions, shared by UI and tests.
const Simulation = preload("res://core/simulation.gd")
const LocalSave = preload("res://services/local_save.gd")

static func review(definition: Dictionary, recording: Dictionary, attempt: Dictionary) -> Dictionary:
	if recording.is_empty():
		return {"valid": false, "can_commit": false, "error": "No recording is ready."}
	var normalized := LocalSave.normalize_attempt(attempt)
	var check: Dictionary = Simulation.verify_recording(definition, recording, normalized.a if recording.get("role") == "b" else {})
	check["can_commit"] = bool(check.get("snapshot", {}).get("can_commit", false)) if check.valid else false
	return check

static func pending_status(pending: Dictionary, room: Dictionary) -> String:
	if pending.is_empty():
		return "none"
	if pending.get("room_id", "") != room.get("room_id", ""):
		return "other_room"
	var record: Dictionary = pending.get("recording", {})
	var attempt := LocalSave.normalize_attempt(room.get("recordings", {}))
	var saved: Dictionary = attempt.get(str(record.get("role", "")), {})
	if same_recording(record, saved):
		return "accepted"
	if int(pending.get("base_revision", -1)) != int(room.get("revision", -2)):
		return "stale"
	return "retry"

static func same_recording(first: Dictionary, second: Dictionary) -> bool:
	if first.is_empty() or second.is_empty():
		return false
	for key: String in ["schema_version", "simulation_version", "level_id", "level_version", "role", "duration_ticks", "tick_rate", "actions", "checkpoints", "final_state_hash", "completed", "outcome"]:
		if _normalized_value(first.get(key)) != _normalized_value(second.get(key)):
			return false
	return first.get("source_recording_hash", "") == second.get("source_recording_hash", "") and first.get("catch_assistance", true) == second.get("catch_assistance", true)

static func _normalized_value(value: Variant) -> Variant:
	# Godot JSON parses numbers as doubles; freshly recorded actions use ints.
	# Preserve exact meaning across that boundary without weakening comparison.
	if value is float and is_finite(value) and value==floor(value):
		return int(value)
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:
			result[key]=_normalized_value(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:
			result.append(_normalized_value(item))
		return result
	return value

static func my_turn(room: Dictionary, player_id: String) -> bool:
	if player_id.is_empty() or player_id not in [str(room.get("host_id", "")), str(room.get("guest_id", ""))]:
		return false
	var current_role := str(room.get("active_role", ""))
	if current_role not in ["a", "b"]:
		return false
	var first: bool = str(room.get("first_player_id", "")) == player_id
	return first if current_role == "a" else not first
