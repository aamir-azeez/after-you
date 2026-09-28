extends "res://tests/test_recent_rooms_ui.gd"
var friend_family := 2
var shared_friend_room: Variant = null
var friend_clock := 1000
const LEGACY_CODE := "B1B1B1B1B1B1B1B1B1B1"

func _run() -> void:
	_check(not quit_on_go_back,"Android Back belongs to the active screen instead of automatically quitting")
	# Fail before dispatch if the project regresses: the engine's automatic quit
	# otherwise exits with code zero before the remaining assertions can run.
	if quit_on_go_back:
		quit(1)
		return
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name]=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.handle_input_locally=true
	root.add_child(viewport)
	var path := "user://friends-navigation-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var app := Main.new()
	app.saves=Save.new(path)
	app.saves.data.settings.sound=false
	app.saves.data.settings.haptics=false
	_check(app.saves.flush(),"Prepare isolated friend-navigation save")
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
	api.joined=false
	app.identity_read_state=Main.IdentityReadState.LOADED
	app.identity_data={"player_id":GUEST,"device_token":"synthetic-device-token"}
	app.relay_session=Session.new(api,app._relay_identity,MemoryStore.new())
	app.friends_client=Main.FriendsClient.new(api,app._relay_identity)
	app.friends_client.clock_ms=func(): return friend_clock
	app._show_rooms()
	await app._show_friends()
	await process_frame
	await process_frame
	_check(is_instance_valid(app.friends_screen) and app.mode=="friends" and not app.ui.visible,"Friends uses a single active screen above the retained parent")
	var joined: Button=_screen_button(app.friends_screen,"Join")
	_check(joined!=null and not joined.disabled,"A shared room from an offline accepted friend offers Join")
	if joined!=null:
		_pointer(viewport,joined.get_global_rect().get_center(),true)
		_pointer(viewport,joined.get_global_rect().get_center(),false)
		await process_frame
	_check(is_instance_valid(app.relay_child) and app.mode=="relay_online" and not app.ui.visible and not is_instance_valid(app.friends_screen),"Closing Friends after Join preserves the native chapter destination")
	var joins := api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v2/rooms/join")
	_check(joins.size()==1 and joins[0].body.invite_code=="A1".repeat(10),"Friend chapter entry uses the existing durable join exactly once")
	if is_instance_valid(app.relay_child):
		var relay_closes := [0]
		app.relay_child.closed.connect(func(): relay_closes[0] += 1)
		await _system_back()
		_check(relay_closes[0]==1 and not is_instance_valid(app.relay_child) and app.ui.visible,"System Back leaves the Relay child once while its retained Main yields")
	friend_clock += 3000
	await app._show_friends()
	await process_frame
	var reads_before: int=api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v2/rooms/"+ROOM).size()
	await app.friends_screen._act("join",app.friends_client.view().friends[0])
	_check(is_instance_valid(app.relay_child) and api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v2/rooms/join").size()==1,"A known friend chapter reopens without consuming its invitation again")
	_check(api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v2/rooms/"+ROOM).size()==reads_before+1,"Known chapter reentry performs one authoritative room GET")
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	friend_family=1
	friend_clock += 3000
	app._show_rooms()
	await app._show_friends()
	await process_frame
	await process_frame
	joined=_screen_button(app.friends_screen,"Join")
	if joined!=null:
		_pointer(viewport,joined.get_global_rect().get_center(),true)
		_pointer(viewport,joined.get_global_rect().get_center(),false)
		await process_frame
	_check(app.mode=="room" and app.active_room.room_id==LEGACY_CODE.sha256_text().substr(0,22) and app.ui.visible,"Friend earlier-island entry retains its legacy room destination after screen close")
	joins=api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v1/rooms/join")
	_check(joins.size()==1 and joins[0].body.invite_code==LEGACY_CODE,"Friend earlier-island entry uses its original join exactly once")
	friend_clock += 3000
	await app._show_friends()
	await process_frame
	await app.friends_screen._act("join",app.friends_client.view().friends[0])
	_check(app.mode=="room" and api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v1/rooms/join").size()==1,"A known earlier island reopens through GET rather than another join")
	# Start a room GET, then leave the route before the reply arrives.
	app._show_rooms()
	await app._show_friends()
	await process_frame
	api.hold_next=true
	app.friends_screen._open()
	await process_frame
	app._show_home()
	api.release.emit()
	await process_frame
	_check(app.mode=="home" and not is_instance_valid(app.friends_screen),"A delayed Return reply cannot reopen a room after Home")
	app._show_rooms()
	await app._show_friends()
	await process_frame
	await _system_back()
	_check(app.mode=="rooms" and app.ui.visible and not is_instance_valid(app.friends_screen),"Android Back from Friends restores the parent's room chooser")
	app._show_home()
	await app._show_friends()
	await process_frame
	var friend_closes := [0]
	app.friends_screen.closed.connect(func(): friend_closes[0] += 1)
	await _system_back()
	_check(friend_closes[0]==1 and app.mode=="home" and app.ui.visible and not is_instance_valid(app.friends_screen),"System Back from Home Friends closes once and survives the engine quit-request signal")
	app._draw_story_lobby()
	var story_generation: int=app._campaign_generation
	await _system_back()
	_check(app.mode=="home" and app._campaign_generation==story_generation,"The retired Story lobby cannot replace Home or claim its Back action")
	app._show_home()
	var home_stage: Node=app.home_stage_view
	await _system_back()
	_check(app.mode=="home" and app.home_stage_view==home_stage and app.is_inside_tree(),"Home keeps its existing Back fallback without an automatic process exit")
	app._show_rooms()
	await app._show_friends()
	await process_frame
	app._invalidate_relay_identity()
	await process_frame
	_check(app.friends_client.view().is_empty() and not is_instance_valid(app.friends_screen) and app.ui.visible,"Identity invalidation closes Friends and clears its visible account state")
	api.player_id=HOST
	app.identity_data.player_id=HOST
	app.relay_session=Session.new(api,app._relay_identity,MemoryStore.new())
	_check(await app.relay_session.load_lobby(),"Share selection fixture loads the host lobby")
	_check(await app.relay_session.open_room(ROOM),"Share selection fixture restores a verified hosted chapter")
	app._show_rooms()
	await app._show_friends()
	await process_frame
	_check(app.friends_screen.shareable_room.is_empty() and _screen_button(app.friends_screen,"Share current room")==null,"A retained room after account change is not silently chosen for sharing")
	app.friends_screen.close()
	await process_frame
	app._enter_online_relay()
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	app._accept_room(_ok({"room_id":LEGACY_CODE.sha256_text().substr(0,22),"revision":1,"host_id":HOST,"guest_id":GUEST,"level_index":0,"level_id":"first-light","active_role":"a","first_player_id":HOST,"recordings":{},"attempt":0}))
	await _share_current_room(viewport,app,api,{"api_version":1,"room_id":LEGACY_CODE.sha256_text().substr(0,22)},"Opening an earlier island after a chapter shares the latest earlier island")
	app._enter_online_relay()
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	await _share_current_room(viewport,app,api,{"api_version":2,"room_id":ROOM},"Opening the chapter after an earlier island shares the latest chapter")
	await _host_from_friends(viewport,app,api)
	viewport.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("FRIENDS NAVIGATION: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _system_back() -> void:
	# Match Window's parent-first platform notification, then its actual signal
	# connected to SceneTree's independent quit_on_go_back handler. Calling only
	# a screen's _notification cannot catch the native automatic-exit regression.
	_window_back_notification(root)
	root.go_back_requested.emit()
	await process_frame

func _window_back_notification(node: Node) -> void:
	node.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var index := 0
	while index < node.get_child_count():
		var child: Node=node.get_child(index)
		if not child is Window: _window_back_notification(child)
		index += 1

func _server(request: Dictionary, api: FakeApi) -> Dictionary:
	if request.path=="/v1/friends":
		return _ok({"schema_version":1,"friend_code":request.owner,"refresh_after_seconds":60,"shared_room":shared_friend_room,"friends":[{"player_id":GUEST if request.owner==HOST else HOST,"request_id":"F".repeat(22),"status":"accepted","online":false,"join_available":true,"expires_after_seconds":0}]})
	if request.path=="/v1/friends/share":
		shared_friend_room=request.body.room
		return _ok({"schema_version":1,"shared_room":shared_friend_room})
	if request.path=="/v1/friends/"+HOST+"/join":
		return _ok({"schema_version":1,"api_version":friend_family,"room_id":ROOM if friend_family==2 else LEGACY_CODE.sha256_text().substr(0,22),"invite_code":"A1".repeat(10) if friend_family==2 else LEGACY_CODE})
	if request.path=="/v1/rooms/join":
		return _ok({"room_id":LEGACY_CODE.sha256_text().substr(0,22),"revision":1,"host_id":HOST,"guest_id":GUEST,"level_index":0,"level_id":"first-light","active_role":"a","first_player_id":HOST,"recordings":{},"attempt":0})
	if request.path=="/v1/rooms/"+LEGACY_CODE.sha256_text().substr(0,22) or (request.path=="/v1/rooms" and request.method==HTTPClient.METHOD_POST):
		return _ok({"room_id":LEGACY_CODE.sha256_text().substr(0,22),"revision":1,"host_id":HOST,"guest_id":GUEST,"level_index":0,"level_id":"first-light","active_role":"a","first_player_id":HOST,"recordings":{},"attempt":0})
	return super._server(request,api)

func _share_current_room(viewport: SubViewport, app: Node, api: FakeApi, expected: Dictionary, label: String) -> void:
	app._show_rooms()
	await app._show_friends()
	await process_frame
	await process_frame
	_check(app.friends_screen.shareable_room==expected,label)
	var share: Button=_screen_button(app.friends_screen,"Share current room")
	var before: int=api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v1/friends/share").size()
	_check(share!=null,"The selected hosted room has a visible share action")
	if share!=null:
		var parent: Node=share.get_parent()
		while parent!=null and not parent is ScrollContainer: parent=parent.get_parent()
		if parent is ScrollContainer:
			parent.ensure_control_visible(share)
			await process_frame
		_pointer(viewport,share.get_global_rect().get_center(),true)
		_pointer(viewport,share.get_global_rect().get_center(),false)
		await process_frame
	var requests: Array=api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v1/friends/share")
	_check(requests.size()==before+1 and requests.back().body.room==expected,"The actual share button sends exactly the selected room descriptor")
	app.friends_screen.close()
	await process_frame

func _screen_button(screen: CanvasLayer, label: String) -> Button:
	for button: Button in screen._root.find_children("*","Button",true,false):
		if button.text==label: return button
	return null

func _host_from_friends(viewport: SubViewport, app: Node, api: FakeApi) -> void:
	app._show_home()
	await app._show_friends()
	await process_frame
	var shared_before: int=api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v1/friends/share").size()
	var creates_before: int=api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v2/rooms" and call.method==HTTPClient.METHOD_POST).size()
	var host := _screen_button(app.friends_screen,"Host a room")
	_check(host!=null,"Home Friends has a visible Host a room control")
	if host!=null: host.pressed.emit()
	await process_frame
	_check(app.mode=="relay_rooms" and not is_instance_valid(app.friends_screen) and app._friends_hosting,"Host opens the ordinary chapter chooser without the close callback replacing it")
	_check(_button_named(app,"Host an earlier island")!=null,"The Friends host chooser also offers earlier islands")
	app.selected_online_chapter="relay-isles@2"
	app._draw_relay_lobby()
	api.drop_next=true
	await app._relay_lobby_action("create","relay-isles@2")
	_check(app.mode=="relay_rooms" and not app.relay_session.pending_lobby().is_empty(),"A lost host reply retains the existing durable create request")
	var key: String=app.relay_session.pending_lobby().body.idempotency_key
	await app._relay_lobby_action("retry")
	await process_frame
	_check(app.mode=="friends" and is_instance_valid(app.friends_screen) and app.friends_screen.room_title=="The Relay Isles","Confirmed host creation returns to Friends with the named room")
	_check(app.friends_screen.shareable_room=={"api_version":2,"room_id":ROOM} and app.friends_screen.openable_room,"The created room is selected for explicit sharing and Return")
	var creates: Array=api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v2/rooms" and call.method==HTTPClient.METHOD_POST)
	_check(creates.size()==creates_before+2 and creates[-1].body.idempotency_key==key and creates[-2].body.idempotency_key==key,"Host retry preserves one creation key")
	_check(api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v1/friends/share").size()==shared_before,"Hosting does not automatically share with friends")
	var create_count: int=creates.size()
	# Sharing (including a lost-response retry) must never restart hosting.
	api.drop_next=true
	await app.friends_screen._act("share")
	await app.friends_screen._act("share")
	_check(api.calls.filter(func(call: Dictionary) -> bool: return call.path=="/v2/rooms" and call.method==HTTPClient.METHOD_POST).size()==create_count,"Share retry never creates another room")
	app.friends_screen._open()
	await process_frame
	_check(app.mode=="relay_online" and is_instance_valid(app.relay_child),"Return opens the hosted native chapter and survives Friends closing")
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	await app._show_friends()
	await process_frame
	app.friends_screen._host()
	await process_frame
	await app._create_room()
	await process_frame
	_check(app.mode=="friends" and app.friends_screen.shareable_room=={"api_version":1,"room_id":LEGACY_CODE.sha256_text().substr(0,22)},"Hosting an earlier island returns to explicit Friends sharing through the same flow")
	app.friends_screen.close()
	await process_frame
	# A new friend's delayed join must not navigate after Back or backgrounding.
	app.saves.data.erase("room")
	app.active_room={}
	app._show_rooms()
	await app._show_friends()
	await process_frame
	api.hold_next=true
	app._join_friend_room({"api_version":1,"room_id":LEGACY_CODE.sha256_text().substr(0,22),"invite_code":LEGACY_CODE})
	app.friends_screen.close()
	await process_frame
	app._show_home()
	api.release.emit()
	await process_frame
	_check(app.mode=="home","A late new-friend join cannot replace Home")
	app._show_rooms()
	await app._show_friends()
	await process_frame
	api.hold_next=true
	app._join_friend_room({"api_version":1,"room_id":LEGACY_CODE.sha256_text().substr(0,22),"invite_code":LEGACY_CODE})
	app.friends_screen.close()
	app._background_application()
	api.release.emit()
	await process_frame
	_check(app.mode=="rooms","A join completing in the background does not open gameplay")
	app._resume_application()
