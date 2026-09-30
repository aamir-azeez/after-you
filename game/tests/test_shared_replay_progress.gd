extends "res://tests/test_shared_replays.gd"

class PhaseTrace extends "res://services/replay_load_progress.gd":
	var phases: Array[String] = []
	func set_phase(value: String) -> void:
		super.set_phase(value)
		phases.append(value)

func _run() -> void:
	var owner := Boundary.new()
	var api := Api.new()
	root.add_child(api)
	var cache := Memory.new()
	var online := OnlineMemory.new()
	var checkpoint := _fixture("first_steps", "lift-checkpoint")
	var room := {"family": "chapter", "room_id": ROOM, "host_id": HOST, "guest_id": GUEST, "chapter_key": Registry.FIRST_STEPS, "title": "First Steps"}
	var entry := {"schema_version": 1, "room": room, "pair": {"pair_id": "p0-0", "branch": 0, "stage_index": 0, "a": checkpoint.proof.a, "b": checkpoint.proof.b, "checkpoint": checkpoint}}
	var second := entry.duplicate(true)
	second.room.room_id = OTHER
	cache.values["shared-replays:" + HOST + ":index"] = {"schema_version": 1, "owner": HOST, "rooms": {"chapter:" + ROOM: room, "chapter:" + OTHER: second.room}}
	for value: Dictionary in [entry, second]:
		cache.values["shared-replays:" + HOST + ":chapter:" + value.room.room_id] = {"schema_version": 1, "owner": HOST, "entries": {"p0-0": value}}
	online.values["relay-lobby-v2:" + HOST] = {"schema_version": 1, "owner_player_id": HOST, "room_ids": [ROOM, OTHER], "last_room": ROOM, "pending": {}}
	var collection := Collection.new(api, owner.identity, cache, online)
	_check(collection.begin_local_load(), "Two saved rooms begin bounded local checking")
	var state: Dictionary = collection.local_progress()
	_check(state.active and state.rooms_total == 2 and state.rooms_done == 0 and state.checked == 0, "Initial room totals reflect queued work, without invented progress")
	collection.advance_local_load()
	await _wait_worker(collection)
	state = collection.local_progress()
	_check(state.active and state.rooms_done == 0 and state.checked == 2 and state.total == 2 and state.phase == "ready", "Completed entry and journal checks remain pending until main-thread adoption")
	collection.advance_local_load()
	_check(collection.local_progress().rooms_done == 1, "One adopted room advances the overall room count exactly once")
	await _drain_local(collection)
	state = collection.local_progress()
	_check(not state.active and not state.failed and state.rooms_done == 2 and state.rooms_total == 2, "Only both adopted rooms report full completion")
	_check(collection.begin_local_load(), "A warm scan starts a fresh progress generation")
	await _drain_local(collection)
	_check(collection.local_progress().rooms_done == 2, "Unchanged proofs count once in the new scan rather than accumulating old progress")
	var bad := second.duplicate(true)
	bad.pair.b.final_state_hash = "0".repeat(64)
	cache.values["shared-replays:" + HOST + ":chapter:" + OTHER].entries["p0-0"] = bad
	_check(collection.begin_local_load(), "A scan can observe a newly damaged saved proof")
	await _drain_local(collection)
	state = collection.local_progress()
	_check(not state.active and state.failed and state.rooms_done == 1 and state.rooms_total == 2, "A failed proof never becomes a completed room or false full bar")
	cache.values["shared-replays:" + HOST + ":chapter:" + OTHER].entries["p0-0"] = second
	_check(collection.begin_local_load(), "Identity-retirement case starts with valid saved content")
	collection.advance_local_load()
	owner.epoch += 1
	state = collection.local_progress()
	_check(not state.active and state.rooms_done == 0 and state.rooms_total == 0, "An old identity's live worker cannot publish progress to the new identity")
	_check(collection.begin_local_load(), "New identity generation can queue while the old worker drains")
	await _drain_local(collection)
	_check(collection.local_progress().rooms_done == 2, "Retired work cannot add an extra completed room to the new generation")
	var trace := PhaseTrace.new()
	var job := {"owner": HOST, "key": "chapter:" + ROOM, "cached": {"ok": true, "found": true, "value": {"schema_version": 1, "owner": HOST, "entries": {"p0-0": entry}}}, "journal": {"ok": true, "found": false}, "legacy": {}, "verified": "", "raw": false, "online_raw": false, "progress": trace}
	var worker := Thread.new()
	var started := worker.start(Callable(Collection, "_verify_local_room").bind(job)) == OK
	_check(started, "Pure progress trace starts on its owned worker")
	if started:
		var result: Dictionary = worker.wait_to_finish()
		_check(result.ok and trace.phases == ["reading", "entries", "journal", "ready"] and trace.snapshot().checked == 2, "Progress names actual check phases and completed checks")
	_check(api.calls.is_empty(), "Progress observation and replay checking remain fully local")
	_bar_states(entry)
	api.queue_free()
	await process_frame
	print("SHARED REPLAY PROGRESS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _bar_states(entry: Dictionary) -> void:
	var tracker := preload("res://services/replay_load_progress.gd").new()
	var bar := preload("res://presentation/replay_loading_bar.gd").new()
	root.add_child(bar)
	tracker.set_total(2)
	bar.update_progress(tracker.snapshot())
	_check(bar.bar.indeterminate and bar.bar.value==0,"A running first check shows activity without inventing a percentage")
	tracker.advance()
	bar.update_progress(tracker.snapshot())
	_check(not bar.bar.indeterminate and is_equal_approx(bar.bar.value,0.5),"Completed checks advance the visible loading bar")
	bar.update_progress({"active":true,"rooms_total":2,"rooms_done":1,"checked":2,"total":2})
	_check(bar.bar.value<1.0,"Worker completion cannot show full progress before adoption")
	bar.update_progress({"active":false,"rooms_total":2,"rooms_done":2,"checked":0,"total":0})
	_check(is_equal_approx(bar.bar.value,1.0),"Adopted rooms finish the library bar")
	bar.reduced_motion=true
	bar.update_progress({"checked":0,"total":2})
	_check(not bar.bar.indeterminate,"Reduced motion keeps the loading indicator still")
	_check(View.valid_sequence([entry],HOST,tracker) and tracker.snapshot().checked==tracker.snapshot().total,"Viewer reports completed native checks through the same tracker")
	var bad := entry.duplicate(true)
	bad.pair.checkpoint.checkpoint_hash="0".repeat(64)
	_check(not View.valid_sequence([bad],HOST,tracker) and tracker.snapshot().checked==0,"Rejected replay verification cannot finish its loading bar")
	bar.queue_free()

func _wait_worker(collection: RefCounted) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while collection._local_worker != null and collection._local_worker.is_alive() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(collection._local_worker != null and not collection._local_worker.is_alive(), "Focused worker completes within its bound")
