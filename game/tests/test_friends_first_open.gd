extends "res://tests/test_friends_navigation.gd"

class FreshMain:
	extends "res://main.gd"
	func _new_relay_session() -> RefCounted:
		var session := super._new_relay_session()
		session._store = preload("res://tests/test_relay_online.gd").MemoryStore.new()
		return session

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var path := "user://friends-first-open-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var app := FreshMain.new()
	app.saves = Save.new(path)
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	app.saves.flush()
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
	app._show_home()
	_check(app.relay_session == null and app.friend_share_target.is_empty(),"Cold Home has no relay session or selected room")
	await app._show_friends()
	await process_frame
	_check(is_instance_valid(app.friends_screen) and app.friends_screen._message.is_empty(),"First Friends open has no room error")
	var host := _screen_button(app.friends_screen,"Host a room")
	_check(host != null and not host.disabled,"First Friends open has a usable Host button")
	if host != null: host.pressed.emit()
	await process_frame
	await process_frame
	_check(app.mode == "rooms" and is_instance_valid(app.room_hub_screen) and not is_instance_valid(app.friends_screen),"Cold Host returns to the room hub")
	_check(app.room_hub_screen.find_children("*","OptionButton",true,false).size() == 1,"Room hub has a populated chapter selector")
	_check(app.room_hub_screen.find_children("*","Button",true,false).any(func(button: Button): return button.text == "Host a room"),"Room hub shows the host action")
	_check(api.calls.all(func(call: Dictionary): return call.method == HTTPClient.METHOD_GET),"Opening Friends and Host does not create or share any room")
	app.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("FRIENDS FIRST OPEN: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _server(request: Dictionary, api: FakeApi) -> Dictionary:
	if request.path == "/v1/friends":
		return _ok({"schema_version":1,"friend_code":request.owner,"refresh_after_seconds":60,"shared_room":null,"friends":[]})
	return super._server(request,api)
