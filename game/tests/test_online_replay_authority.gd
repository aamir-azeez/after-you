extends "res://tests/test_relay_online.gd"
## A replay of an online room plays only while the room it was captured from is
## still the one on screen. Any change to the identity, the room coordinator or
## its members retires it before another tick, and replay never sends, writes
## or hides a pending turn.

func _run() -> void:
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	await _authority_changes()
	await _pending_turn()
	await create_timer(0.5).timeout
	print("Online replay authority: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

## The host's room after the first stage: one finished pair to replay.
func _room_case(index: int) -> Dictionary:
	var api := _api()
	api.exists = true
	api.joined = true
	api.index = index
	api.revision = 1 + 2 * index
	var identity := Identity.new()
	var store := MemoryStore.new()
	var session := Session.new(api,identity.get_value,store)
	_check(await session.load_lobby() and await session.open_room(ROOM),"The room opens")
	var preview := Preview.new()
	preview.online_session = session
	preview.settings = {"sound":false,"haptics":false,"reduced_motion":true}
	root.add_child(preview)
	preview.set_process(false)
	preview.set_physics_process(false)
	return {"api":api,"identity":identity,"store":store,"session":session,"preview":preview}

func _dispose(c: Dictionary) -> void:
	c.preview.queue_free()
	c.api.queue_free()
	await process_frame

func _authority_changes() -> void:
	for change: String in ["identity","coordinator","coordinator_generation","members"]:
		var c := await _room_case(1)
		var preview: Node = c.preview
		var coordinator: RefCounted = c.session.coordinator
		_check(preview._pairs().size() == 1,"The finished first stage can be replayed")
		preview.replay_pair_index = 0
		preview._play_collection_pair()
		for _frame in range(8): preview._physics_process(1.0/30.0)
		preview._pause()
		var cursor: int = preview.replay_cursor
		var native: String = preview.sim.state_hash()
		var writes: int = c.store.writes
		var calls: int = c.api.calls.size()
		match change:
			"identity": c.identity.epoch += 1
			"coordinator": c.session.coordinator = null
			"coordinator_generation": _check(coordinator.bind_room(ROOM),"Binding the same room again starts a new coordinator generation")
			"members": coordinator._state.snapshot.guest_id = null
		preview._resume_replay()
		preview._physics_process(1.0/30.0)
		_check(preview.replay_cursor == cursor and preview.sim.state_hash() == native and not preview.running,"The paused replay plays no further frame after a "+change+" change")
		_check(c.api.calls.size() == calls and c.store.writes == writes,"Noticing a "+change+" change sends and writes nothing")
		_check(preview._room_context_lost and preview._replay_context.is_empty(),"A "+change+" change retires the replay before another tick")
		await _dispose(c)

func _pending_turn() -> void:
	var c := await _room_case(0)
	var preview: Node = c.preview
	c.api.drop_next = true
	_check(c.session.coordinator.save_draft(fixtures["relay-a"]) and not await c.session.coordinator.commit(fixtures["relay-a"]) and not c.session.coordinator.pending().is_empty(),"The room holds a turn whose reply was lost")
	var pending: Dictionary = c.session.coordinator.pending()
	var saved := Canonical.digest(c.store.values)
	var calls: int = c.api.calls.size()
	preview._start_replay(fixtures["relay-a"],fixtures["initial-checkpoint"],{})
	for _frame in range(8): preview._physics_process(1.0/30.0)
	_check(c.api.calls.size() == calls and Canonical.digest(c.store.values) == saved,"Replay sends nothing and writes nothing")
	_check(Canonical.same(c.session.coordinator.pending(),pending),"Replay never retries, rewrites or clears the pending turn")
	await _dispose(c)
