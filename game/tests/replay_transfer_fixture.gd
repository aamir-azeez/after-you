extends RefCounted
## Shared immutable native archive fixtures; no test-runner lifecycle.
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const OTHER := "SSSSSSSSSSSSSSSSSSSSSS"

class Memory extends RefCounted:
	var values: Dictionary = {}
	var writes := 0
	var reads := 0
	var fail_save := false
	var corrupt_readback := false
	func load_scope(scope: String) -> Dictionary:
		reads += 1
		var value: Dictionary = values.get(scope, {}).duplicate(true)
		if corrupt_readback and not value.is_empty(): value.archive.turns[0].recording.final_state_hash = "0".repeat(64)
		return {"ok": true, "found": values.has(scope), "value": value}
	func save_scope(scope: String, value: Dictionary) -> bool:
		writes += 1
		if fail_save: return false
		values[scope] = JSON.parse_string(JSON.stringify(value))
		return true

static func fixture(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + path + ".json"))

## One branch of a complete room: every stage's pair, walked back from the
## final checkpoint through its nested proofs.
static func archive(chapter: String, final_checkpoint: Dictionary) -> Dictionary:
	var level := Registry.definition(chapter)
	var stages: int = level.stages.size()
	var checkpoints: Array = [final_checkpoint]
	while checkpoints.size() < stages: checkpoints.push_front(Registry.previous_checkpoint(chapter, checkpoints[0]))
	var pairs: Array = []
	var turns: Array = []
	var completed: Array = []
	for index in range(stages):
		var checkpoint: Dictionary = checkpoints[index]
		completed.append("p0-%d" % index)
		var pair := {"pair_id": "p0-%d" % index, "branch": 0, "stage_index": index, "a": checkpoint.proof.a, "b": checkpoint.proof.b, "checkpoint": checkpoint}
		pairs.append(pair)
		for role: String in ["a", "b"]:
			var record: Dictionary = pair[role]
			turns.append({"turn_id": "t0-%d-%s" % [index, role], "player_id": HOST if record.player_slot == "p0" else GUEST, "accepted_revision": turns.size() + 2, "recording": record})
	var room := {"schema_version": 2, "room_id": ROOM, "revision": turns.size() + 1, "branch": 0, "stage_index": stages, "level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level), "host_id": HOST, "guest_id": GUEST, "checkpoint": final_checkpoint, "a_turn_id": null, "completed_pair_ids": completed, "invite_expires_at": "2026-09-30T00:00:00.000Z", "created_at": "2026-09-29T00:00:00.000Z", "updated_at": "2026-09-29T00:01:00.000Z", "simulation_version": pairs[0].a.simulation_version}
	return JSON.parse_string(JSON.stringify({"schema_version": 1, "room": room, "turns": turns, "pairs": pairs}))

static func manifest(value: Dictionary, epoch: int = 1) -> Dictionary:
	var room: Dictionary = value.room.duplicate(true)
	room.erase("checkpoint")
	room["checkpoint_hash"] = value.room.checkpoint.checkpoint_hash
	var turns: Array = []
	for item: Dictionary in value.turns:
		turns.append({"turn_id": item.turn_id, "player_id": item.player_id, "accepted_revision": item.accepted_revision, "recording_hash": item.recording.recording_hash})
	var pairs: Array = []
	for item: Dictionary in value.pairs:
		pairs.append({"pair_id": item.pair_id, "branch": item.branch, "stage_index": item.stage_index, "a_hash": item.a.recording_hash, "b_hash": item.b.recording_hash, "checkpoint_hash": item.checkpoint.checkpoint_hash})
	return JSON.parse_string(JSON.stringify({"schema_version": 1, "epoch": epoch, "archive_hash": Canonical.digest(value), "room": room, "turns": turns, "pairs": pairs}))
