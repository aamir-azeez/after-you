extends "res://tests/test_relay_online.gd"
## Hosting a Friends room shares it and sends one hosting alert, through the
## real Main -> relay_preview path. The fake server keeps the live rule that a
## hosting alert is refused for a room that is not shared with friends.
var shared_room: Variant = null
var share_fail := false
var publication_ids: Dictionary = {}

func _run() -> void:
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var app := Main.new()
	var path := "user://room-auto-share-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	cleanup_paths.append(path)
	app.saves = Save.new(path)
	app.saves.data.settings.sound = false
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := _api()
	root.remove_child(api)
	app.add_child(api)
	app.api = api
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id":HOST,"device_token":"synthetic-device-token"}
	app.relay_session = Session.new(api,app._relay_identity,MemoryStore.new())

	# Friends room, setting on: one share, then one accepted hosting alert.
	await _host(app,api,"friends")
	_check(_count(api,"/v1/friends/share") == 1 and _sent(api).back().body.room == {"api_version":2,"room_id":ROOM},"Hosting a Friends room shares that exact room once")
	_check(_count(api,"/v1/social/publication") == 1 and publication_ids.size() == 1,"Hosting a Friends room sends exactly one hosting alert, after the share")
	_check(app.mode == "relay_online" and is_instance_valid(app.relay_child),"Hosting stays in the room while it is shared")
	_check_card(app,true,"The host's card shows the room as shared, with Stop sharing")

	# Reopening the same room never shares or alerts again.
	app.relay_child._leave()
	await _frames(4)
	await app._relay_lobby_action("open",ROOM)
	await _frames(8)
	_check(_count(api,"/v1/friends/share") == 1 and _count(api,"/v1/social/publication") == 1,"Reopening a hosted room sends no share and no second alert")
	_check_card(app,true,"A reopened shared room still shows that it is shared")

	# Stop sharing, then share again: one unshare and one share, no new alert.
	await _tap_share(app)
	_check(_count(api,"/v1/friends/share") == 2 and _sent(api).back().body.room == null and shared_room == null,"Stop sharing room sends one unshare")
	_check_card(app,false,"After Stop sharing the card offers Share again")
	await _tap_share(app)
	_check(_count(api,"/v1/friends/share") == 3 and _count(api,"/v1/social/publication") == 1,"Sharing the room again does not alert friends a second time")
	_check_card(app,true,"Sharing again shows the shared state")
	await _tap_share(app)

	# Setting off: hosting neither shares nor alerts.
	app.saves.data.settings.share_online_status = false
	var shares := _count(api,"/v1/friends/share")
	await _host(app,api,"friends")
	_check(_count(api,"/v1/friends/share") == shares and _count(api,"/v1/social/publication") == 1,"With Share online status off, hosting shares nothing and sends no alert")
	_check_card(app,false,"With sharing off the card keeps its Share button")
	app.saves.data.settings.share_online_status = true

	# Invitation only: no share and no alert either.
	await _host(app,api,"invitation_only")
	_check(_count(api,"/v1/friends/share") == shares and _count(api,"/v1/social/publication") == 1,"An Invitation only room is never shared or announced")

	# A share failure leaves the room working with Share as the retry.
	share_fail = true
	publication_ids.clear()
	var alerts := _count(api,"/v1/social/publication")
	await _host(app,api,"friends")
	_check(_count(api,"/v1/friends/share") == shares+1 and _count(api,"/v1/social/publication") == alerts,"A failed share sends no hosting alert")
	_check(app.mode == "relay_online" and is_instance_valid(app.relay_child) and app.relay_child.journey.snapshot().get("room_id") == ROOM,"A failed share leaves the hosted room open")
	_check_card(app,false,"After a failed share the card offers Share to retry")
	share_fail = false
	await _tap_share(app)
	_check(_count(api,"/v1/friends/share") == shares+2 and _count(api,"/v1/social/publication") == alerts+1,"Retrying Share shares the room and sends its one owed alert")
	_check_card(app,true,"A successful retry shows the shared state")
	await _tap_share(app)

	# Main's API busy when the automatic share starts, and a tap racing it.
	shares = _count(api,"/v1/friends/share")
	alerts = _count(api,"/v1/social/publication")
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	await _frames(4)
	await app._show_relay_rooms("relay-isles@2")
	app.room_hub_host_visibility = "friends"
	await app._relay_lobby_action("create","relay-isles@2")
	api.busy = true
	await _frames(4)
	_check(_count(api,"/v1/friends/share") == shares,"The automatic share waits while another request holds the API")
	var share: Button = _share_button(app)
	_check(share != null and share.disabled,"Share is disabled while the automatic share is pending")
	if share != null: share.pressed.emit()
	await _frames(2)
	api.busy = false
	await _frames(12)
	_check(_count(api,"/v1/friends/share") == shares+1 and _count(api,"/v1/social/publication") == alerts+1,"A tap during the automatic share still ends in one share and one alert")
	_check_card(app,true,"The raced share ends in the shared state")

	if is_instance_valid(app.relay_child): app.relay_child._leave()
	viewport.queue_free()
	await create_timer(0.5).timeout
	for cleanup: String in cleanup_paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(cleanup+suffix): DirAccess.remove_absolute(cleanup+suffix)
	print("ROOM AUTO SHARE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _host(app: Node, api: FakeApi, visibility: String) -> void:
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	await _frames(4)
	await app._show_relay_rooms("relay-isles@2")
	app.room_hub_host_visibility = visibility
	await app._relay_lobby_action("create","relay-isles@2")
	await _frames(12)

func _frames(count: int) -> void:
	for _i in count: await process_frame

func _sent(api: FakeApi) -> Array:
	return api.calls.filter(func(call: Dictionary) -> bool: return call.path == "/v1/friends/share")

func _count(api: FakeApi, path: String) -> int:
	return api.calls.filter(func(call: Dictionary) -> bool: return call.path == path).size()

func _share_button(app: Node) -> Button:
	if not is_instance_valid(app.relay_child): return null
	var found: Array = app.relay_child.overlay.find_children("ShareCurrentRoom","Button",true,false)
	return found[0] if not found.is_empty() else null

func _tap_share(app: Node) -> void:
	var share := _share_button(app)
	_check(share != null and not share.disabled,"The room card has an enabled Share control")
	if share == null or share.disabled: return
	share.pressed.emit()
	await _frames(6)

func _check_card(app: Node, shared: bool, label: String) -> void:
	var share := _share_button(app)
	var status: Variant = share.get_meta("status", null) if share != null else null
	var text_ok := share != null and (share.text == "Stop sharing room") == shared and not share.disabled
	var status_ok: bool = status is Label and ((status.text == "Shared with friends" and status.visible) == shared)
	_check(text_ok and status_ok,label)

func _server(request: Dictionary, api: FakeApi) -> Dictionary:
	if request.path == "/v1/friends/share":
		if share_fail: return {"ok":false,"status":503,"code":"unavailable","error":"Synthetic outage."}
		shared_room = request.body.room
		return _ok({"schema_version":1,"shared_room":shared_room})
	if request.path == "/v1/social/publication":
		# The live rule: 409 friend_room_not_shared unless this room is shared.
		var room: Variant = request.body.get("room")
		if shared_room == null or room != shared_room: return {"ok":false,"status":409,"code":"friend_room_not_shared","error":"Room not shared."}
		var id := str(request.body.get("publication_id",""))
		if not publication_ids.has(id): publication_ids[id] = publication_ids.size()+1
		return _ok({"schema_version":1,"publication_epoch":publication_ids[id],"queued":1})
	return super._server(request,api)
