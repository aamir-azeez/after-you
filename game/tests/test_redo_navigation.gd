extends "res://tests/test_relay_online.gd"
const Redo = preload("res://services/redo_client.gd")
const RedoFixture = preload("res://tests/test_redo_client.gd")
const RoomReadyPanel = preload("res://presentation/room_ready_panel.gd")
var server_branch := 0
var server_request: Variant = null
var fork_responses: Dictionary = {}

func _run() -> void:
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name]=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.handle_input_locally=true
	root.add_child(viewport)
	var app := Main.new()
	var path := "user://redo-navigation-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	app.saves=Save.new(path)
	app.saves.data.settings.sound=false
	app.saves.data.settings.haptics=false
	_check(app.saves.flush(),"Use isolated muted profile for room controls")
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
	# On the second stage, the guest is A and the host is B.
	api.player_id=HOST
	app.identity_read_state=Main.IdentityReadState.LOADED
	app.identity_data={"player_id":HOST,"device_token":"synthetic-device-token"}
	var journals := MemoryStore.new()
	var redo_journals := RedoFixture.MemoryStore.new()
	app.relay_session=Session.new(api,app._relay_identity,journals)
	app.relay_session._redo=Redo.new(api,app._relay_identity,redo_journals)
	await app._show_relay_rooms("relay-isles@2")
	await app._relay_lobby_action("open",ROOM)
	var preview: Node=app.relay_child
	_check(is_instance_valid(preview),"Open a real online chapter with the first stage already verified")
	if not is_instance_valid(preview): quit(1); return
	preview.set_process(false)
	preview.set_physics_process(false)
	var initial: Dictionary=preview.journey.snapshot()
	var checkpoint_hash := Canonical.digest(initial.checkpoint)
	var accepted_pairs: Array=initial.completed_pair_ids.duplicate()
	_check(preview.journey.my_turn() and preview.role=="b" and initial.first_player_id==GUEST,"The actual second player receives the handoff control after role alternation")
	_check(_find_button(preview.overlay,"Ask for redo")!=null,"The ready menu exposes the second player's request action")
	preview._open_redo()
	await _settle()
	var screen: CanvasLayer=preview._redo_screen
	_check(is_instance_valid(screen) and not preview.ui.visible and preview.mode=="redo_requests","Room controls own the visible UI")
	var key := InputEventKey.new()
	key.physical_keycode=KEY_SPACE
	key.pressed=true
	preview._unhandled_key_input(key)
	preview._physics_process(1.0/30.0)
	_check(not preview.running and preview.mode=="redo_requests" and not preview.action_pressed,"Gameplay input and time do not advance under the request panel")
	await _tap(viewport,_find_button(screen,"Ask for redo"))
	_check(server_request is Dictionary and server_request.status=="pending","The visible request sends an advisory request pinned to the current A")
	_check(_find_button(screen,"Cancel request")!=null and _find_button(screen,"Redo my turn")==null,"B can cancel but cannot accept their own request")
	screen.close()
	await _settle()
	preview._begin()
	preview.advance_input({"move_x":0.0,"move_z":0.0,"interact":false})
	preview._pause()
	var paused_draft: Dictionary=preview.journey.draft()
	_check(_find_button(preview.overlay,"Ask for redo")!=null and paused_draft.duration_ticks>0,"A saved mid-attempt rehearsal exposes the same ordinary redo action in Pause")
	preview._open_redo()
	await _settle()
	screen=preview._redo_screen
	screen.close()
	await _settle()
	_check(preview.mode=="paused" and preview.journey.draft()==paused_draft and _find_button(preview.overlay,"Resume")!=null,"Closing an unchanged request restores the paused rehearsal from its retained draft")
	preview.review={}
	preview._show_review()
	_check(_find_button(preview.overlay,"Ask for redo")!=null,"Ordinary redo remains available from the failed recording review")
	preview._open_redo()
	await _settle()
	screen=preview._redo_screen
	screen.close()
	await _settle()
	_check(preview.mode=="review" and _find_button(preview.overlay,"Save turn")!=null,"Closing redo controls without acceptance returns to the same recording review")
	preview._show_ready()
	preview._leave()
	app._invalidate_relay_identity()
	api.player_id=GUEST
	app.identity_data.player_id=GUEST
	app.relay_session=Session.new(api,app._relay_identity,journals)
	app.relay_session._redo=Redo.new(api,app._relay_identity,redo_journals)
	await app._show_relay_rooms("relay-isles@2")
	await app._relay_lobby_action("open",ROOM)
	preview=app.relay_child
	preview.set_process(false)
	preview.set_physics_process(false)
	var before: int=api.calls.size()
	preview.refresh_schedule.bind(preview._online_refresh_context(),Time.get_ticks_msec())
	preview.refresh_schedule.request_now(Time.get_ticks_msec())
	await preview._service_online_refresh()
	var reads: Array=api.calls.slice(before)
	_check(reads.size()==2 and reads.all(func(call: Dictionary) -> bool: return call.method==HTTPClient.METHOD_GET),"Existing waiting-room poll reads the room and its request without sending a mutation")
	_check(_find_button(preview.overlay,"Redo requested")!=null,"A's ordinary waiting view displays the partner request")
	before=api.calls.size()
	await preview._service_online_refresh()
	_check(api.calls.size()==before,"No second request poll occurs before the current room timer is due")
	preview._open_redo()
	await _settle()
	screen=preview._redo_screen
	_check(_find_button(screen,"Redo my turn")!=null and _find_button(screen,"Keep this turn")!=null,"The first player has explicit consent and decline actions")
	api.hold_next=true
	var accept := _find_button(screen,"Redo my turn")
	_pointer(viewport,accept.get_global_rect().get_center(),true)
	_pointer(viewport,accept.get_global_rect().get_center(),false)
	_check(api.busy,"Acceptance holds an actual asynchronous callback")
	preview._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	api.release.emit()
	await _settle()
	_check(server_branch==1 and screen.accepted and preview.mode=="redo_requests" and not preview.running,"An accepted reply while backgrounded never starts recording or dismisses the controls")
	preview._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	screen.close()
	await _settle()
	var forked: Dictionary=preview.journey.snapshot()
	_check(forked.branch==1 and forked.active_role=="a" and preview.role=="a" and preview.mode=="ready" and not preview.running,"Closing accepted controls refreshes through the native coordinator to a new A turn")
	_check(Canonical.digest(forked.checkpoint)==checkpoint_hash and forked.completed_pair_ids==accepted_pairs and forked.stage_index==1,"Redo preserves the prior accepted chapter history and current checkpoint")
	# The same native-verified A fixture supplies a second handoff on the new
	# branch. Lose the next consent reply to exercise the real pending UI.
	api.has_a=true
	api.revision+=1
	server_request=null
	await preview._online_refresh()
	var source := Redo.source_for("relay",_snapshot(api,GUEST))
	server_request={"request_id":Canonical.digest(source),"source":source,"status":"pending"}
	await preview._online_refresh()
	preview._open_redo()
	await _settle()
	screen=preview._redo_screen
	api.drop_next=true
	await _tap(viewport,_find_button(screen,"Redo my turn"))
	var pending: Dictionary=app.relay_session.redo_client().pending()
	_check(server_branch==2 and not pending.is_empty() and _find_button(screen,"Retry request")!=null,"Lost acceptance reply retains the exact request and exposes recovery")
	screen.close()
	await _settle()
	_check(not preview.running and preview.mode=="online_waiting","Leaving an uncertain acceptance keeps the room in recovery instead of offering A recording")
	preview._open_redo()
	await _settle()
	screen=preview._redo_screen
	await _tap(viewport,_find_button(screen,"Retry request"))
	_check(app.relay_session.redo_client().pending().is_empty() and screen.accepted and server_branch==2 and fork_responses.size()==2,"Visible retry resolves the original acceptance without another fork")
	screen.close()
	await _settle()
	forked=preview.journey.snapshot()
	_check(forked.branch==2 and preview.role=="a" and Canonical.digest(forked.checkpoint)==checkpoint_hash,"Recovered acceptance reaches a recordable A with accepted history intact")
	api.has_a=true
	api.revision+=1
	server_request=null
	await preview._online_refresh()
	source=Redo.source_for("relay",_snapshot(api,GUEST))
	server_request={"request_id":Canonical.digest(source),"source":source,"status":"pending"}
	await preview._online_refresh()
	preview._open_redo()
	await _settle()
	screen=preview._redo_screen
	api.hold_next=true
	screen._act("accept")
	_check(api.busy,"Preview identity invalidation holds the actual receipt callback")
	app._invalidate_relay_identity()
	api.player_id=HOST
	api.device_token="replacement-synthetic-token"
	app.identity_data={"player_id":HOST,"device_token":api.device_token}
	api.release.emit()
	await _settle()
	_check(not is_instance_valid(preview._redo_screen) and preview.ui.visible and preview.mode=="error" and not preview.running and server_branch==2,"Late old-identity callback neither forks nor reopens the invalidated Preview panel (panel=%s, ui=%s, mode=%s, running=%s, branch=%d)" % [is_instance_valid(preview._redo_screen),preview.ui.visible,preview.mode,preview.running,server_branch])
	preview._leave()
	viewport.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	await _room_panel_clip_test()
	print("REDO NAVIGATION: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _room_panel_clip_test() -> void:
	var small_viewport := SubViewport.new()
	small_viewport.size=Vector2i(1170,540)
	root.add_child(small_viewport)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	small_viewport.add_child(host)
	var panel := RoomReadyPanel.new()
	host.add_child(panel)
	var actions := panel.build("Long Way Home","2 / 2 · Follow the recording","Follow the open path.",ThemeDB.fallback_font,func(): pass,func(): pass)
	for index in range(12):
		var button := Button.new()
		button.text="Room action %d"%index
		button.custom_minimum_size.y=48
		actions.add_child(button)
	await process_frame
	await process_frame
	var viewport_rect := Rect2(Vector2.ZERO,Vector2(small_viewport.size))
	var room_panel := panel.find_child("RoomActionsPanel",true,false) as PanelContainer
	var scroll := panel.find_child("RoomActionsScroll",true,false) as ScrollContainer
	_check(room_panel!=null and viewport_rect.encloses(room_panel.get_global_rect()),"A long ordinary room menu keeps its panel inside a short viewport")
	_check(scroll!=null and room_panel.get_global_rect().encloses(scroll.get_global_rect()) and scroll.size.y<actions.get_combined_minimum_size().y,"The ordinary room panel scrolls overflowing actions within its visible bounds")
	small_viewport.queue_free()
	await process_frame

func _snapshot(api: FakeApi, owner: String) -> Dictionary:
	var value := super._snapshot(api,owner)
	value.branch=server_branch
	if api.has_a: value.a_turn_id="t%d-%d-a"%[server_branch,api.index]
	return value

func _server(request: Dictionary, api: FakeApi) -> Dictionary:
	var source := Redo.source_for("relay",_snapshot(api,request.owner))
	var body: Dictionary=request.body
	if request.path.ends_with("/redo"):
		if request.method==HTTPClient.METHOD_POST:
			if not Canonical.same(body.source,source): return {"ok":false,"status":409,"code":"redo_source_changed"}
			if body.action=="request":
				server_request={"request_id":Canonical.digest(source),"source":source,"status":"pending"}
			elif body.action in ["cancel","decline"]: server_request.status="cancelled" if body.action=="cancel" else "declined"
		return _ok({"schema_version":1,"source":null if source.is_empty() else source,"request":server_request if not source.is_empty() else null})
	if request.path.ends_with("/fork"):
		if fork_responses.has(body.idempotency_key): return _ok(fork_responses[body.idempotency_key].duplicate(true))
		if source.is_empty() or body.base_revision!=api.revision or request.owner!=source.first_player_id or server_request==null or server_request.status!="pending": return {"ok":false,"status":409,"code":"redo_source_changed"}
		api.revision+=1
		server_branch+=1
		api.has_a=false
		var hashed := body.duplicate(true)
		hashed.operation="fork"
		var room := _snapshot(api,request.owner)
		var receipt := {"schema_version":2,"room_id":ROOM,"idempotency_key":body.idempotency_key,"request_hash":Canonical.digest(hashed),"operation":"fork","accepted_revision":api.revision,"branch":server_branch,"stage_index":api.index,"stage_id":room.stage_id,"checkpoint_hash":room.checkpoint.checkpoint_hash,"turn_id":null,"recording_hash":null,"pair_id":null}
		fork_responses[body.idempotency_key]={"room":room,"receipt":receipt}
		server_request=null
		return _ok(fork_responses[body.idempotency_key].duplicate(true))
	if "/operations/" in request.path and fork_responses.has(request.path.get_file()):
		return _ok(fork_responses[request.path.get_file()].duplicate(true))
	return super._server(request,api)

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text==text: return node
	for child: Node in node.get_children():
		var found := _find_button(child,text)
		if found!=null: return found
	return null

func _tap(viewport: SubViewport, button: Button) -> void:
	_check(button!=null,"Expected visible room-control action exists")
	if button==null: return
	_pointer(viewport,button.get_global_rect().get_center(),true)
	_pointer(viewport,button.get_global_rect().get_center(),false)
	await _settle()

func _pointer(viewport: SubViewport, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position=point
	event.global_position=point
	event.button_index=MOUSE_BUTTON_LEFT
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed=pressed
	viewport.push_input(event,true)

func _settle() -> void:
	await process_frame
	await process_frame
