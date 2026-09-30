extends "res://tests/test_shared_replays.gd"

class LocalReplayApi extends Api:
	var base_url := "https://replay-ui.invalid"

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(960,540)
	root.add_child(viewport)
	var app := Main.new()
	app.saves=Save.new("user://replay-delete-ui-%d.json" % Time.get_ticks_usec())
	app.saves.data.settings.sound=false
	app.saves.data.settings.haptics=false
	_check(app.saves.flush(),"Isolated UI save is ready")
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := LocalReplayApi.new()
	app.add_child(api)
	app.api=api
	app.identity_read_state=Main.IdentityReadState.LOADED
	app.identity_loading=false
	app.identity_data={"player_id":HOST,"device_token":"synthetic-token"}
	var cache := Memory.new()
	app.shared_replays=Collection.new(api,app._relay_identity,cache,OnlineMemory.new())
	var legacy := {"room_id":ROOM,"host_id":HOST,"guest_id":GUEST,"level_id":"first-light","attempt":3,"first_player_id":GUEST,"active_role":"complete","recordings":{"a":_fixture("","first-light-a"),"b":_fixture("","first-light-b")}}
	_check(app.shared_replays.load_saved(legacy),"One real verified fixture replay is available")
	var key := "legacy:"+ROOM
	app._show_shared_replay_room(key)
	await process_frame
	await process_frame
	var before := Canonical.digest(cache.values)
	var remove := _button(app.overlay,"Delete")
	_check(remove != null and not remove.disabled,"Saved row exposes a usable Delete button")
	if remove == null:
		app.queue_free()
		quit(1)
		return
	_check(remove.get_global_rect().end.x <= viewport.get_visible_rect().end.x,"Delete control fits the narrow viewport")
	remove.pressed.emit()
	_check(app.mode == "confirm_delete_replay" and _has_text(app.overlay,Main.PlayerCopy.SHARED_REPLAY_DELETE_CONFIRM),"Confirmation explicitly says this phone only and the friend's copy remains")
	_check(Canonical.digest(cache.values) == before,"Opening confirmation does not delete anything")
	_button(app.overlay,"Cancel").pressed.emit()
	_check(app.mode == "shared_memories" and Canonical.digest(cache.values) == before,"Cancel returns without modifying local replays")
	_button(app.overlay,"Delete").pressed.emit()
	api.busy=true
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode == "shared_memories" and Canonical.digest(cache.values) == before,"Android Back cancels deletion even when transport becomes busy")
	api.busy=false
	app._show_shared_replay_room(key)
	_button(app.overlay,"Delete").pressed.emit()
	var stale := _button(app.overlay,"Delete")
	app._show_home()
	stale.pressed.emit()
	_check(app.mode == "home" and Canonical.digest(cache.values) == before,"A stale confirmation cannot delete after navigation")
	app._show_shared_replay_room(key)
	_button(app.overlay,"Delete").pressed.emit()
	stale=_button(app.overlay,"Delete")
	api.player_id=OTHER
	app.relay_identity_epoch+=1
	stale.pressed.emit()
	_check(Canonical.digest(cache.values) == before,"A changed identity invalidates the old confirmation")
	_button(app.overlay,"Cancel").pressed.emit()
	_check(app.mode == "shared_replays","A changed identity can still dismiss the old confirmation")
	api.player_id=HOST
	app.relay_identity_epoch+=1
	app._shared_archive_sync=true
	app._show_shared_replay_room(key)
	_check(_button(app.overlay,"Delete").disabled,"Archive delivery keeps deletion disabled")
	app._shared_archive_sync=false
	app._show_shared_replay_room(key)
	_button(app.overlay,"Delete").pressed.emit()
	var confirm := _button(app.overlay,"Delete")
	confirm.pressed.emit()
	var after := Canonical.digest(cache.values)
	confirm.pressed.emit()
	_check(app.mode == "shared_memories" and app.shared_replays.memories(key,true).is_empty(),"Confirmed deletion removes the saved row")
	_check(Canonical.digest(cache.values) == after and _button(app.overlay,"Delete") == null,"Double activation cannot repeat deletion")
	_check(api.calls.is_empty(),"Local deletion and its confirmation send no network request")
	viewport.queue_free()
	await process_frame
	print("REPLAY DELETE UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _has_text(node: Node, text: String) -> bool:
	if node is Label and node.text == text: return true
	for child: Node in node.get_children():
		if _has_text(child,text): return true
	return false
