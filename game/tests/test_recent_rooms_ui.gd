extends "res://tests/test_relay_online.gd"

func _run() -> void:
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name]=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.handle_input_locally=true
	root.add_child(viewport)
	var path := "user://recent-rooms-ui-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var app := Main.new()
	app.saves=Save.new(path)
	app.saves.data.settings.sound=false
	app.saves.data.settings.haptics=false
	_check(app.saves.flush(),"Prepare isolated muted profile")
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := _api()
	root.remove_child(api)
	app.add_child(api)
	app.api=api
	api.player_id=GUEST
	api.exists=true
	api.joined=true
	app.identity_read_state=Main.IdentityReadState.LOADED
	app.identity_data={"player_id":GUEST,"device_token":"synthetic-device-token"}
	var store := MemoryStore.new()
	app.relay_session=Session.new(api,app._relay_identity,store)
	var saved := FileAccess.get_file_as_string(path)
	for size: Vector2i in [Vector2i(1280,720),Vector2i(960,540)]:
		viewport.size=size
		await app._show_saved_rooms()
		await process_frame
		await process_frame
		var rows := _recent_rows(app)
		_check(rows.size()==2,"Recent rooms combines a joined chapter with earlier islands")
		_check(rows[0].text=="The Relay Isles · Joined" and rows[0].get_meta("recent_room_id")==ROOM,"A guest sees the chapter title and Joined label without an invitation")
		_check(rows[1].get_meta("recent_room_family")=="v1","Earlier rooms retain their separate route")
		for button: Button in rows:
			_check(Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()),"Room entry fits the small landscape menu")
		for label: String in ["Back","Refresh"]:
			_check(Rect2(Vector2.ZERO,Vector2(size)).encloses(_button_named(app,label).get_global_rect()),"Recent room navigation stays visible")
	_check(FileAccess.get_file_as_string(path)==saved,"Reading both room families never overwrites gameplay saves")
	var before: int=api.calls.size()
	var joined: Button=_recent_rows(app)[0]
	_pointer(viewport,joined.get_global_rect().get_center(),true)
	_pointer(viewport,joined.get_global_rect().get_center(),false)
	await process_frame
	_check(is_instance_valid(app.relay_child) and app.relay_child.chapter_key=="relay-isles@2","Actual guest row tap reopens the correct native chapter")
	_check(api.calls.size()==before+1 and api.calls[-1].method==HTTPClient.METHOD_GET and api.calls[-1].path=="/v2/rooms/"+ROOM,"Rejoining needs one room GET and no join-code mutation")
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	api.hold_next=true
	app._show_saved_rooms()
	await process_frame
	app._show_home()
	api.release.emit()
	await process_frame
	_check(app.mode=="home" and app.overlay.has_node("HomeFullJourney"),"A delayed recent-room reply cannot reopen the menu after Back")
	app._show_rooms()
	api.hold_next=true
	app._show_saved_rooms()
	await process_frame
	app._invalidate_relay_identity()
	api.player_id=HOST
	app.identity_data.player_id=HOST
	api.release.emit()
	await process_frame
	_check(_recent_rows(app).is_empty(),"A room response from the prior account cannot display old guest rows")
	api.responder=func(request: Dictionary) -> Dictionary:
		if request.path=="/v1/rooms": return _ok({"rooms":[]})
		return {"ok":false,"status":0,"error":"Synthetic offline response"}
	await app._show_saved_rooms()
	await process_frame
	_check(_recent_rows(app).is_empty() and _button_named(app,"Refresh")!=null,"Failed refresh retains a retry control without stale chapter rooms")
	viewport.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("RECENT ROOMS UI: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _server(request: Dictionary, api: FakeApi) -> Dictionary:
	if request.path=="/v1/rooms":
		return _ok({"rooms":[{"room_id":"L".repeat(22),"level_id":"first-light","host_id":HOST,"guest_id":GUEST,"active_role":"complete"}]})
	return super._server(request,api)

func _recent_rows(app: Node) -> Array[Button]:
	var result: Array[Button]=[]
	for button: Button in app.overlay.find_children("*","Button",true,false):
		if button.has_meta("recent_room_family"): result.append(button)
	return result

func _pointer(viewport: SubViewport, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position=point
	event.global_position=point
	event.button_index=MOUSE_BUTTON_LEFT
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed=pressed
	viewport.push_input(event,true)
