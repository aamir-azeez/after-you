extends "res://tests/test_redo_navigation.gd"
## A redo accepted while the server has asked this phone to wait before its
## next room read (a 429 or 503 with Retry-After) leaves a room screen that
## still reads the room once the wait is over, never one stuck behind the
## closed request panel.

func _run() -> void:
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name]=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.handle_input_locally=true
	root.add_child(viewport)
	var app := Main.new()
	var path := "user://redo-cooldown-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	app.saves=Save.new(path)
	app.saves.data.settings.sound=false
	app.saves.data.settings.haptics=false
	_check(app.saves.flush(),"Use an isolated muted profile")
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := _api()
	root.remove_child(api)
	app.add_child(api)
	app.api=api
	api.exists=true
	api.joined=true
	api.index=1
	api.has_a=true
	api.revision=4
	# On the second stage the guest is A: the one who answers a redo request.
	api.player_id=GUEST
	app.identity_read_state=Main.IdentityReadState.LOADED
	app.identity_data={"player_id":GUEST,"device_token":"synthetic-device-token"}
	app.relay_session=Session.new(api,app._relay_identity,MemoryStore.new())
	app.relay_session._redo=Redo.new(api,app._relay_identity,RedoFixture.MemoryStore.new())
	var source := Redo.source_for("relay",_snapshot(api,GUEST))
	server_request={"request_id":Canonical.digest(source),"source":source,"status":"pending"}
	await app.relay_lobby_flow.open_lobby("relay-isles@2")
	await app.relay_lobby_flow.lobby_action("open",ROOM)
	var preview: Node=app.relay_child
	_check(is_instance_valid(preview),"The room opens")
	if not is_instance_valid(preview): quit(1); return
	preview.set_process(false)
	preview.set_physics_process(false)
	preview.refresh_schedule.bind(preview._online_refresh_context(),Time.get_ticks_msec())
	preview.refresh_schedule.request_now(Time.get_ticks_msec())
	await preview._service_online_refresh()
	_check(_find_button(preview.overlay,"Redo requested")!=null,"The friend's redo request shows")
	# The server asks for a two-minute pause before the next room read.
	api.responder=func(request: Dictionary) -> Dictionary:
		if request.method==HTTPClient.METHOD_GET and request.path=="/v2/rooms/"+ROOM: return {"ok":false,"status":429,"code":"rate_limited","retry_after_ms":120000}
		return _server(request,api)
	preview.online_refresh_queued=true
	await preview._service_online_refresh()
	_check(preview.refresh_schedule.next_due_ms()>Time.get_ticks_msec()+60000,"The room read waits for the server's Retry-After")
	api.responder=_server.bind(api)
	preview._open_redo()
	await _settle()
	var screen: CanvasLayer=preview._redo_screen
	_check(is_instance_valid(screen) and _find_button(screen,"Redo my turn")!=null,"The redo request can be answered")
	await screen._act("accept")
	await _settle()
	_check(screen.accepted and server_branch==1,"The redo is accepted and the room starts again on a new branch")
	screen.close()
	await _settle()
	_check(preview.mode!="redo_requests" and preview.ui.visible,"Closing the panel during the wait leaves a room card, not the closed panel's mode (at %s)" % preview.mode)
	# The wait passes; the room is read again and offers the new turn.
	preview.refresh_schedule._cooldown_until=0
	preview.refresh_schedule._due=0
	preview.online_refresh_queued=true
	await preview._service_online_refresh()
	await _settle()
	_check(preview.journey.snapshot().get("branch")==1 and preview.mode=="ready" and preview.role=="a","After the wait the room shows the new turn (at %s, branch %s)" % [preview.mode,str(preview.journey.snapshot().get("branch"))])
	preview._leave()
	viewport.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("REDO COOLDOWN: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
