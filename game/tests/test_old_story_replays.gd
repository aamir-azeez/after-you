extends "res://tests/test_shared_replays.gd"
## Owner decision (2026-10-16): replays of an old Story chapter that this phone
## already kept still show in Together and still play, whether the server still
## refuses the room (409 campaign_client_required) or has deleted it. Its reads
## fail quietly and never remove what this phone kept.

class RoomStore:
	extends RefCounted
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok":true,"found":values.has(scope),"value":values.get(scope,{}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok":true}

func _run() -> void:
	# probed: this identity already checked the room and learned it is a Story room.
	# cold: a fresh start, the server still refuses the room.
	# deleted: the server has deleted the room.
	for state: String in ["probed","cold","deleted"]:
		await _case(state)
	print("Old Story replays: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _case(state: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves = Save.new("user://old-story-replays-%d.json" % Time.get_ticks_usec())
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	_check(app.saves.flush(),state+": isolated save is ready")
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := Api.new()
	app.add_child(api)
	app.api = api
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_loading = false
	app.identity_data = {"player_id":HOST,"device_token":"synthetic-token"}
	var gone := {"ok":false,"status":404,"code":"room_not_found"} if state == "deleted" else {"ok":false,"status":409,"code":"campaign_client_required"}
	for suffix: String in ["","/collection","/pairs/p0-0","/pairs/p0-1","/pairs/p0-2"]:
		api.replies["/v2/rooms/"+ROOM+suffix] = gone.duplicate(true)
	api.replies["/v2/rooms"] = {"ok":true,"status":200,"data":{"rooms":[]}}
	api.replies["/v1/rooms"] = {"ok":true,"status":200,"data":{"rooms":[]}}
	var online := OnlineMemory.new()
	var source := Coordinator.new(_offline,online.load_scope,online.save_game,app._relay_identity)
	_check(source.bind_room(ROOM) and source._accept_snapshot(_snapshot(Registry.FIRST_STEPS)),state+": this phone kept the finished Story chapter room")
	online.values["relay-lobby-v2:"+HOST] = {"schema_version":1,"owner_player_id":HOST,"room_ids":[ROOM],"last_room":"","pending":{}}
	var cache := Memory.new()
	app.shared_replays = Collection.new(api,app._relay_identity,cache,online)
	_check(app.shared_replays.load_saved() and app.shared_replays.rooms().size() == 1,state+": the kept room is found on this phone")
	app.relay_session = Session.new(api,app._relay_identity,RoomStore.new())
	if state == "probed":
		_check(not await app.relay_session.open_room(ROOM) and app.relay_session.archived_room_kind(ROOM) == "story",state+": the server answers the room as an old Story room")
	var key := "chapter:"+ROOM
	app.replays_flow.show_shared_replays()
	await _drain_local(app.shared_replays)
	for _frame in range(4): await process_frame
	app.replays_flow.show_shared_replay_room(key)
	for _frame in range(4): await process_frame
	var kept := Canonical.digest(cache.values)
	_check(app.mode == "shared_memories" and app.replays_flow.shared_replay_room == key,state+": Together opens the kept Story chapter")
	_check(app.shared_replays.memories(key,true).size() == 2 and app.replays_flow._listed_shared_rooms().size() == 1,state+": both kept stages are listed")
	await app.replays_flow._refresh_shared_replay_memories()
	await app.replays_flow._refresh_shared_replay_rooms()
	for _frame in range(4): await process_frame
	_check(app.mode == "shared_memories" and app.replays_flow.shared_replay_room == key,state+": refreshing keeps the room open")
	_check(app.shared_replays.memories(key,true).size() == 2 and app.replays_flow._listed_shared_rooms().size() == 1,state+": refreshing keeps both stages listed")
	var entry: Dictionary = await app.shared_replays.open_memory(key,"p0-1")
	_check(Collection.verify_entry(entry,HOST),state+": a kept stage plays from this phone")
	var missing: Dictionary = await app.shared_replays.open_memory(key,"p0-2")
	_check(missing.is_empty() and app.mode == "shared_memories",state+": a stage this phone does not have fails quietly")
	_check(Canonical.digest(cache.values) == kept and app.shared_replays.memories(key,true).size() == 2,state+": nothing this phone kept is removed")
	if state == "probed":
		_check(api.calls.filter(func(call: Dictionary) -> bool: return str(call.path).begins_with("/v2/rooms/"+ROOM) and call != api.calls[0]).is_empty(),state+": after the check no read for the Story room reaches the server")
	viewport.queue_free()
	await process_frame
	await create_timer(0.2).timeout
