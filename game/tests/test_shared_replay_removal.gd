extends "res://tests/test_shared_replays.gd"

class RemovalStore extends Memory:
	var reject_write := false
	var omit_write := false
	var switch_owner: Boundary
	func save_scope(scope: String, value: Dictionary) -> bool:
		if scope.contains(":removed:"):
			if reject_write: return false
			if omit_write: return true
			if switch_owner != null:
				switch_owner.player = OTHER
				switch_owner.epoch += 1
		return super.save_scope(scope, value)

func _run() -> void:
	var owner := Boundary.new()
	var api := Api.new()
	root.add_child(api)
	var cache := RemovalStore.new()
	var online := OnlineMemory.new()
	var source := Coordinator.new(_offline, online.load_scope, online.save_game, owner.identity)
	_check(source.bind_room(ROOM) and source._accept_snapshot(_snapshot(Registry.FIRST_STEPS)), "Removal starts from a genuine verified completed room")
	var pending := Coordinator.new(_offline, online.load_scope, online.save_game, owner.identity)
	_check(pending.bind_room(OTHER) and pending._accept_snapshot(_snapshot(Registry.FIRST_STEPS, OTHER, 0)), "An independent active room is retained")
	_check(not await pending.commit(_fixture("first_steps", "a-little-lift-a")) and not pending.pending().is_empty(), "An interrupted request is durably pending before replay deletion")
	online.values["relay-lobby-v2:" + HOST] = {"schema_version": 1, "owner_player_id": HOST, "room_ids": [ROOM, OTHER], "last_room": OTHER, "pending": {}}
	var collection := Collection.new(api, owner.identity, cache, online)
	_check(collection.load_saved(), "Accepted local rooms populate Shared Replays")
	var key := "chapter:" + ROOM
	var scope := "shared-replays:" + HOST + ":removed:" + key
	var entries: Array = collection.local_entries(key)
	var selected: Dictionary = await collection.open_memory(key, "p0-0")
	_check(entries.size() == 2 and not selected.is_empty(), "The selected replay is an exact verified local pair")
	var wrong := selected.duplicate(true)
	wrong.room.title = "Another saved label"
	var before := Canonical.digest(cache.values)
	_check(not collection.remove_memory(key, "p0-0", wrong) and Canonical.digest(cache.values) == before, "A stale expected entry cannot remove a different local value")
	_check(not collection.remove_memory("chapter:" + OTHER, "p0-0", selected), "Room binding cannot be substituted at deletion")
	cache.reject_write = true
	_check(not collection.remove_memory(key, "p0-0", selected) and collection.memories(key).size() == 2, "A rejected marker write keeps the replay visible")
	cache.reject_write = false
	cache.omit_write = true
	_check(not collection.remove_memory(key, "p0-0", selected) and collection.memories(key).size() == 2, "A successful write return without durable readback is not reported as deletion")
	cache.omit_write = false
	# These independent namespaces model bytes already owned by other services.
	cache.values["shared-replays:" + HOST + ":transfer:" + ROOM + ":1"] = {"archive": "retained recovery data"}
	cache.values["photo-library:" + HOST] = {"photo": "retained photo bytes"}
	var protected_values := cache.values.duplicate(true)
	protected_values["shared-replays:" + HOST + ":" + key].entries.erase("p0-0")
	var journal_before := Canonical.digest(online.values)
	var journal_writes: int = online.writes
	_check(collection.remove_memory(key, "p0-0", selected), "Exact replay removal is confirmed by persisted marker readback")
	var remainder := cache.values.duplicate(true)
	remainder.erase(scope)
	_check(Canonical.same(remainder, protected_values) and cache.values.has(scope), "Only the removal marker and selected browsing-cache pair change; photos and full recovery archive remain intact")
	_check(Canonical.digest(online.values) == journal_before and online.writes == journal_writes and api.calls.is_empty(), "Deletion leaves active progress, pending requests and lobby bytes unchanged and sends no network request")
	_check(collection.memories(key).size() == 1 and collection.local_sequence(key).is_empty(), "The deleted part disappears and cannot be stitched into Watch all parts")
	_check((await collection.open_memory(key, "p0-0")).is_empty() and api.calls.is_empty(), "Opening a removed ID cannot redownload it")
	_check(not (await collection.open_memory(key, "p0-1")).is_empty(), "The other saved part remains playable")
	var reopened := Collection.new(api, owner.identity, cache, online)
	_check(reopened.load_saved() and reopened.memories(key).size() == 1, "A fresh collection honors removal despite the unchanged complete room journal")
	_check(reopened._cache(selected) and reopened.memories(key).size() == 1, "Accepted receipt recaching does not resurrect the removed pair")
	var renamed := selected.duplicate(true)
	renamed.room.title = "Updated chapter title"
	_check(reopened._cache(renamed) and reopened.memories(key).size() == 1, "A display-label change cannot restore the same removed proof")
	var manifest := {"room": _snapshot(Registry.FIRST_STEPS), "pairs": []}
	for entry: Dictionary in entries:
		var pair: Dictionary = entry.pair
		manifest.pairs.append({"pair_id": pair.pair_id, "branch": pair.branch, "stage_index": pair.stage_index, "a_hash": pair.a.recording_hash, "b_hash": pair.b.recording_hash, "checkpoint_hash": pair.checkpoint.checkpoint_hash})
	_check(reopened.cache_transferred_entries(ROOM, entries, manifest) and reopened.memories(key).size() == 1, "Complete transfer adoption remains valid while respecting the phone's prior removal")
	api.replies["/v2/rooms/" + ROOM + "/collection"] = _ok({"pairs": manifest.pairs})
	var remote_rows: Array = await reopened.refresh_memories(key)
	_check(remote_rows.size() == 1 and remote_rows[0].id == "p0-1", "Remote immutable summaries cannot reintroduce the removed pair")
	var fork := selected.duplicate(true)
	fork.pair.pair_id = "p1-0"
	fork.pair.branch = 1
	_check(reopened._cache(fork) and reopened.memories(key).size() == 2, "A distinct accepted fork remains eligible for the local collection")
	await _worker_removal(owner, api, online, selected)
	_disk_removal(owner, api, selected)
	_invalid_marker(owner, api, selected)
	_identity_during_removal(api, selected)
	await _legacy_removal(owner, api)
	api.queue_free()
	await process_frame
	print("SHARED REPLAY REMOVAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _worker_removal(owner: Boundary, api: Node, online: RefCounted, selected: Dictionary) -> void:
	var cache := Memory.new()
	var writer := Collection.new(api, owner.identity, cache, online)
	_check(writer.load_saved(), "Concurrent removal fixture has verified local history")
	var reader := Collection.new(api, owner.identity, cache, online)
	_check(reader.begin_local_load(), "A separate collection captures the earlier local replay state")
	reader.advance_local_load()
	_check(writer.remove_memory("chapter:" + ROOM, "p0-0", selected), "A second collection removes the exact replay while its earlier scan is outstanding")
	await _drain_local(reader)
	var rows: Array = reader.memories("chapter:" + ROOM, true)
	_check(rows.size() == 1 and rows[0].id == "p0-1", "Worker adoption consults the durable removal marker before publishing its stale captured pair")
	_check(reader.begin_local_load(), "The current collection can start another local scan")
	reader.advance_local_load()
	var remaining: Dictionary = await reader.open_memory("chapter:" + ROOM, "p0-1")
	_check(reader.remove_memory("chapter:" + ROOM, "p0-1", remaining), "Same-instance removal retires the outstanding worker generation")
	await _drain_local(reader)
	_check(reader.memories("chapter:" + ROOM, true).is_empty(), "A retired worker cannot restore the last removed replay")

func _disk_removal(owner: Boundary, api: Node, selected: Dictionary) -> void:
	var directory := "user://shared-replay-removal-%d" % Time.get_ticks_usec()
	var disk := Disk.new(directory)
	var writer := Collection.new(api, owner.identity, disk, OnlineMemory.new())
	writer.rooms()
	_check(writer._remember_room(_snapshot(Registry.FIRST_STEPS), "chapter"), "The first disk collection retains the original accepted pair cache")
	var other_writer := Collection.new(api, owner.identity, Disk.new(directory), OnlineMemory.new())
	other_writer.rooms()
	var fork := selected.duplicate(true)
	fork.pair.pair_id = "p1-0"
	fork.pair.branch = 1
	_check(other_writer._cache(fork), "Another live collection persists a newer fork after the first collection's read")
	_check(writer.remove_memory("chapter:" + ROOM, "p0-0", selected), "The real flushed store accepts and reads back the bounded removal scope")
	var reopened := Collection.new(api, owner.identity, Disk.new(directory), OnlineMemory.new())
	var rows: Array = reopened.memories("chapter:" + ROOM)
	_check(rows.size() == 2 and rows[0].id == "p0-1" and rows[1].id == "p1-0", "Fresh disk pruning preserves another writer's newer fork and only removes the selected pair")

func _invalid_marker(owner: Boundary, api: Node, selected: Dictionary) -> void:
	for corruption: Variant in [{"schema_version": 1, "owner": OTHER, "entries": {}}, {"schema_version": 2, "owner": HOST, "entries": {}}, {"schema_version": 1, "owner": HOST, "entries": {"p0-0": {"entry_hash": "bad"}}}]:
		var cache := Memory.new()
		var collection := Collection.new(api, owner.identity, cache, OnlineMemory.new())
		collection.rooms()
		_check(collection._remember_room(_snapshot(Registry.FIRST_STEPS), "chapter"), "Corrupt-marker fixture begins with accepted replay data")
		cache.values["shared-replays:" + HOST + ":removed:chapter:" + ROOM] = corruption
		var before := Canonical.digest(cache.values)
		_check(not collection.remove_memory("chapter:" + ROOM, "p0-0", selected) and collection.memories("chapter:" + ROOM).is_empty() and Canonical.digest(cache.values) == before, "Foreign, future or malformed removal metadata holds the collection without overwriting it")

func _identity_during_removal(api: Node, selected: Dictionary) -> void:
	var owner := Boundary.new()
	var cache := RemovalStore.new()
	var collection := Collection.new(api, owner.identity, cache, OnlineMemory.new())
	collection.rooms()
	_check(collection._remember_room(_snapshot(Registry.FIRST_STEPS), "chapter"), "Identity-race removal has a real accepted source")
	cache.switch_owner = owner
	_check(not collection.remove_memory("chapter:" + ROOM, "p0-0", selected), "Identity change during persistence prevents stale deletion success")
	_check(collection.rooms().is_empty() and cache.values.keys().all(func(scope: String): return not scope.begins_with("shared-replays:" + OTHER + ":")), "Old-owner work never adopts entries or writes markers into the new owner's namespace")

func _legacy_removal(owner: Boundary, api: Node) -> void:
	var cache := Memory.new()
	var collection := Collection.new(api, owner.identity, cache, OnlineMemory.new())
	var legacy := {"room_id": "L".repeat(22), "host_id": HOST, "guest_id": GUEST, "level_id": "first-light", "attempt": 3, "first_player_id": GUEST, "active_role": "complete", "recordings": {"a": _fixture("", "first-light-a"), "b": _fixture("", "first-light-b")}}
	var key := "legacy:" + str(legacy.room_id)
	_check(collection.load_saved(legacy), "Legacy island replay remains available before removal")
	var selected: Dictionary = await collection.open_memory(key, "a3")
	_check(collection.remove_memory(key, "a3", selected), "Legacy attempt removal uses its exact verified contents")
	var reopened := Collection.new(api, owner.identity, cache, OnlineMemory.new())
	_check(reopened.load_saved(legacy) and reopened.memories(key).is_empty(), "Legacy saved-room backfill cannot resurrect the removed attempt")
