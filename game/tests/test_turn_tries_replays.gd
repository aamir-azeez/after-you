extends "res://tests/test_shared_replays.gd"
## Shared Replays reads both players' try counts from the server: only with
## the capability, once per change of a room's parts, from the saved parts
## when the room's list has left the server, and quietly when the read fails.
const TurnTries = preload("res://services/turn_tries.gd")

func _run() -> void:
	await _reads()
	print("Turn tries replays: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

static func _tries_reads(api: Node) -> int:
	return api.calls.filter(func(call: Dictionary) -> bool: return str(call.path).ends_with("/tries")).size()

func _reads() -> void:
	for path: String in ["user://turn-tries.json", "user://turn-tries-open.json"]:
		for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var owner := Boundary.new()
	var api := Api.new()
	root.add_child(api)
	var collection := Collection.new(api, owner.identity, Memory.new(), OnlineMemory.new())
	var supported := {"value": false}
	collection.turn_tries_supported = func() -> bool: return supported.value
	_check(collection._ready_owner() and collection._remember_room(_snapshot(Registry.RELAY), "chapter"), "A finished Relay room is known with its parts")
	var key := "chapter:" + ROOM
	var rows: Array = collection.memories(key)
	_check(rows.size() == 2, "Both parts are saved on this phone")
	var listed: Array = []
	for row: Dictionary in rows: listed.append({"pair_id": row.id, "branch": 0, "stage_index": row.stage_index, "a_hash": row.a_hash, "b_hash": row.b_hash, "checkpoint_hash": row.checkpoint_hash})
	var list_path := "/v2/rooms/%s/collection" % ROOM
	var tries_path := "/v2/rooms/%s/tries" % ROOM
	api.replies[list_path] = _ok({"pairs": listed, "active_pair_ids": ["p0-0", "p0-1"]})
	api.replies[tries_path] = _ok({"schema_version": 1, "tries": {rows[0].a_hash: 3, rows[1].b_hash: 1}})
	await collection.refresh_memories(key)
	_check(_tries_reads(api) == 0 and TurnTries.new().tries(rows[0].a_hash) == 0, "Without the server's capability no counts are asked for")
	supported.value = true
	await collection.refresh_memories(key)
	_check(_tries_reads(api) == 1 and api.calls.back().path == tries_path, "With it, one read after the room's list")
	_check(TurnTries.new().tries(rows[0].a_hash) == 3 and TurnTries.new().tries(rows[1].b_hash) == 0, "The friend's and your counts are kept by recording; a count of one keeps nothing")
	await collection.refresh_memories(key)
	_check(_tries_reads(api) == 1, "A room whose parts did not change is not read again")
	# The room's list left the server (offloaded or moved to the phones): the saved parts still lead to a read.
	api.replies[list_path] = {"ok": false, "status": 410, "code": "replay_transferred"}
	TurnTries.new().remember({}, ROOM, "parts read before")
	api.replies[tries_path] = _ok({"schema_version": 1, "tries": {rows[1].b_hash: 4}})
	await collection.refresh_memories(key)
	_check(_tries_reads(api) == 2 and TurnTries.new().tries(rows[1].b_hash) == 4, "Counts are read from the saved parts when the room's list is gone")
	api.replies[list_path] = _ok({"pairs": listed, "active_pair_ids": ["p0-0", "p0-1"]})
	api.replies[tries_path] = {"ok": false, "status": 503, "code": "turn_tries_disabled"}
	TurnTries.new().remember({}, ROOM, "parts read before")
	collection.last_error = ""
	await collection.refresh_memories(key)
	_check(_tries_reads(api) == 3 and collection.last_error.is_empty() and TurnTries.new().tries(rows[1].b_hash) == 4, "A failed read says nothing and keeps the counts already read")
	await collection.refresh_memories(key)
	_check(_tries_reads(api) == 4, "A failed read is tried again next time")
	api.queue_free()
	await process_frame
