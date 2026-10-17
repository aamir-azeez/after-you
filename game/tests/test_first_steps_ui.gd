extends SceneTree
## Real shared preview and menu layout. Inputs are synthetic simulation fixtures,
## never represented as Android touches or independent-player acceptance.
const Preview = preload("res://relay_preview.gd")
const Journey = preload("res://services/relay_journey.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Simulation = preload("res://core/first_steps/simulation.gd")
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
const Session = preload("res://services/relay_online_session.gd")
const Fakes = preload("res://tests/test_relay_online.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
var checks := 0
var failures := 0
var capture_dir := ""
var paths: Array[String] = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _path(tag: String) -> String:
	var value := "user://first-steps-ui-"+tag+"-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	paths.append(value)
	return value

func _run() -> void:
	await _preview_flow()
	await _online_chooser()
	await _hub_actions_fit()
	await _visible_join_routes()
	await process_frame
	await process_frame
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("First Steps shared HUD and online chooser: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _capture(name: String, target_viewport: Viewport = null) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var path := capture_dir.path_join(name+".png")
	_check(not FileAccess.file_exists(path), "Evidence never overwrites a prior capture")
	if not FileAccess.file_exists(path):
		var source: Viewport = root if target_viewport==null else target_viewport
		_check(source.get_texture().get_image().save_png(path)==OK,"Actual shared UI frame captured")

func _preview_flow() -> void:
	var app := Preview.new()
	app.chapter_key = Registry.FIRST_STEPS
	app.journey = Journey.new(_path("preview"),null,Registry.FIRST_STEPS)
	app.settings = {"sound":false,"haptics":false,"reduced_motion":true,"assistance":true,"left_handed":false}
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	await _capture("first-steps-stage1-ready-hud")
	for name: String in ["a-little-lift-a", "a-little-lift-b", "a-place-to-grow-a", "a-place-to-grow-b"]:
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_steps/"+name+".json"))
		app._begin()
		var pictured := false
		for input: Dictionary in Simulation.expand_recording_inputs(record):
			app.advance_input(input)
			var state: Dictionary = app.sim.snapshot()
			if name=="a-little-lift-b" and not pictured and state.mechanisms.lift.phase=="rising" and state.mechanisms.lift.height_cm>=80:
				app.world.present(state,true)
				await process_frame
				_check_hud(app)
				await _capture("first-steps-stage1-riding-hud")
				pictured = true
			if name=="a-place-to-grow-a" and not pictured and app.sim.context_action().get("enabled",false):
				app.world.present(state,true)
				await process_frame
				_check_hud(app)
				_check(not app.action_button.disabled,"Authored upper-pedestal action is enabled")
				await _capture("first-steps-stage2-action-hud")
				pictured = true
		app.world.present(app.sim.snapshot(),true)
		if name=="a-place-to-grow-a": await _capture("first-steps-stage2-activated-hud")
		app._finish()
		if app.mode=="bloom": app._process(Preview.COMPLETION_DURATION)
		_check(app.mode=="review" and app.journey.role()==record.role,"Actual shared preview requires explicit acceptance for "+name)
		app._accept()
		if app.mode=="checkpoint": app._show_ready()
	_check(app.journey.chapter_complete(),"All four fixture-driven contributions reach the real final shared view")
	var old_state: Dictionary = app.journey._state.duplicate(true)
	var old_hash := FileAccess.get_sha256(app.journey._path)
	var retry := _find_button(app.overlay,"Retry")
	_check(retry != null,"Completed First Steps exposes the shared Retry control")
	if retry != null: retry.pressed.emit()
	_check(app.mode=="choose_checkpoint" and FileAccess.get_sha256(app.journey._path)==old_hash,"Choosing Retry does not immediately replace accepted turns")
	app._confirm_local_checkpoint(0)
	_find_button(app.overlay,"Retry").pressed.emit()
	_check(app.mode=="ready" and app.journey.pairs().is_empty(),"First Steps can start again from its first stage")
	var archive: String = app.journey._path+".attempt-"+Canonical.digest(old_state)+".json"
	paths.append(archive)
	_check(_find_button(app.overlay,"Replays")!=null,"The old First Steps replay remains reachable before a new contribution")
	_check(Canonical.same(app.journey.archived_pairs(Canonical.digest(old_state)),old_state.pairs),"Archived First Steps recordings remain exact and validated")
	app.queue_free()
	await process_frame
	await process_frame

func _check_hud(app: Node) -> void:
	var screen := root.get_visible_rect()
	for control: Control in [app.stick,app.action_button,app.finish_button,app.hint_label,app.timer_label]:
		_check(control.is_visible_in_tree() and screen.encloses(control.get_global_rect()),"Active touch/HUD element is visible and inside the actual viewport")
	_check(not app.stick.get_global_rect().intersects(app.action_button.get_global_rect()),"Movement and action remain distinct touch targets")

func _caps(first_steps: bool) -> Dictionary:
	var chapters: Array = []
	for key: String in Registry.keys():
		if key==Registry.FIRST_STEPS and not first_steps: continue
		var value := Registry.descriptor(key)
		chapters.append({"level_id":value.level_id,"level_version":value.level_version,"definition_hash":value.definition_hash,
			"premium":value.premium,"recording_version":value.recording_version,"simulation_version":value.simulation_version})
	return {"api_version":2,"recording_version":2,"simulation_version":2,"mutations_enabled":true,
		"validation":"structural_client_replay_required","chapters":chapters}

## A signed-in Main fed by the synthetic service, as the hub sees it.
func _hub_app(tag: String, viewport: SubViewport) -> Node:
	var app := Main.new()
	app.saves = Save.new(_path(tag))
	app.saves.data.settings.sound=false
	_check(app.saves.flush(),"The hub fixture persists mute before Main reloads its settings")
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := Fakes.FakeApi.new()
	api.player_id = Fakes.GUEST
	app.add_child(api)
	app.api = api
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id":Fakes.GUEST,"device_token":"synthetic-device-token"}
	app.relay_session = Session.new(api,app._relay_identity,Fakes.MemoryStore.new())
	return app

func _reopen_hub(app: Node) -> void:
	if is_instance_valid(app.room_hub_flow.screen): app.room_hub_flow.close()
	await process_frame
	await _open_room_hub(app)

## Hosting starts from the room hub. Once the service's chapters are known its
## picker tags a chapter the service cannot create, and picking another keeps
## Host a room available.
func _online_chooser() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var app := _hub_app("chooser",viewport)
	var api: Node = app.api
	for enabled: bool in [false,true]:
		api.responder = func(request: Dictionary) -> Dictionary:
			if request.path=="/v2/capabilities": return {"ok":true,"data":_caps(enabled)}
			if request.path=="/v2/rooms": return {"ok":true,"data":{"rooms":[]}}
			return {"ok":false,"status":404,"error":"Unexpected synthetic request"}
		_check(await app.relay_session.load_lobby(),"Online chooser uses a protocol-verified service response")
		for size: Vector2i in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(1280,960)]:
			viewport.size = size
			await _reopen_hub(app)
			var hub: CanvasLayer = app.room_hub_flow.screen
			_check(is_instance_valid(hub) and app.mode=="rooms","Play with a friend opens the room hub at "+str(size))
			if not is_instance_valid(hub): continue
			var host := _find_button(hub,"Host a room")
			_check(host!=null and Rect2(Vector2.ZERO,Vector2(size)).encloses(host.get_global_rect()),"Host a room is on screen at "+str(size))
			hub.open_chapter_picker()
			await process_frame
			var first: Control = hub._picker.card_for(Registry.FIRST_STEPS)
			var relay: Control = hub._picker.card_for(Registry.RELAY)
			var first_tag := (first.find_child("ChapterAccess",true,false) as Label).text if first != null else ""
			_check(first != null and first_tag.contains("unavailable online") != enabled,"The hub picker tags First Steps only while the service lacks it")
			_check(relay != null and not (relay.find_child("ChapterAccess",true,false) as Label).text.contains("unavailable online"),"Relay stays available when the new chapter is not enabled")
			if relay != null: (relay.find_child("ChapterOpen",true,false) as Button).pressed.emit()
			await process_frame
			_check(hub.selected_key()==Registry.RELAY and not hub._picker_page.visible and not _find_button(hub,"Host a room").disabled,"Picking Relay returns to the host panel ready to host it")
	app.room_hub_flow.close()
	api.responder = Callable()
	app.relay_session.invalidate_identity()
	app.relay_session = null
	viewport.queue_free()
	await process_frame
	await process_frame

func _find_button(node: Node, label: String) -> Button:
	for child: Node in node.find_children("*","Button",true,false):
		if child.text==label or child.tooltip_text==label: return child
	return null

func _hub_actions_fit() -> void:
	# The hub must show Host a room and the invitation Join without scrolling on
	# a phone and a wide phone, and keep them reachable on a short landscape screen.
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var app := _hub_app("hub-fit",viewport)
	app.api.responder = func(_request: Dictionary) -> Dictionary:
		return {"ok": false, "status": 404, "error": "Unexpected synthetic request"}
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(2340, 1080), Vector2i(800, 360)]:
		viewport.size = size
		await _reopen_hub(app)
		var hub: CanvasLayer = app.room_hub_flow.screen
		_check(is_instance_valid(hub), "The hub opens at " + str(size))
		if not is_instance_valid(hub): continue
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		var back := _find_button(hub, "Back")
		_check(back != null and screen.encloses(back.get_global_rect()), "Hub Back stays on screen at " + str(size))
		var column: ScrollContainer = hub._right_scroll
		for label: String in ["Host a room", "Join"]:
			var button := _find_button(hub, label)
			_check(button != null and button.is_visible_in_tree(), "The hub shows " + label + " at " + str(size))
			if button == null: continue
			if size.y >= 720:
				_check(column.scroll_vertical == 0 and column.get_global_rect().grow(0.5).encloses(button.get_global_rect()), label + " is visible without scrolling at " + str(size))
			else:
				column.ensure_control_visible(button)
				await process_frame
				await process_frame
				_check(column.get_global_rect().grow(0.5).encloses(button.get_global_rect()) and screen.encloses(button.get_global_rect()), label + " scrolls fully into view at " + str(size))
	# The short wait card while a room loads: Android Back returns to the hub.
	app.relay_lobby_flow.draw_progress(PlayerCopy.MAIN_6734074E99D4)
	await process_frame
	var progress: Control = app.overlay.find_child("RoomProgress", true, false)
	_check(app.mode == "relay_rooms" and progress != null and not is_instance_valid(app.room_hub_flow.screen) and _find_button(app.overlay, "Back") != null, "A loading room shows a small card with Back in place of the hub")
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	for _frame in 3: await process_frame
	_check(app.mode == "rooms" and is_instance_valid(app.room_hub_flow.screen), "Android Back on the loading card returns to the room hub")
	app.room_hub_flow.close()
	app.api.responder = Callable()
	app.relay_session.invalidate_identity()
	app.relay_session = null
	viewport.queue_free()
	await process_frame
	await process_frame

func _visible_join_routes() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var app := Main.new()
	app.saves = Save.new(_path("visible-join"))
	app.saves.data.settings.sound=false
	_check(app.saves.flush(),"The join-route fixture persists mute before Main reloads its settings")
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := Fakes.FakeApi.new()
	api.player_id = Fakes.GUEST
	app.add_child(api)
	app.api = api
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id":Fakes.GUEST,"device_token":"synthetic-device-token"}
	var store := Fakes.MemoryStore.new()
	app.relay_session = Session.new(api,app._relay_identity,store)
	var code := "A1".repeat(10)
	var room_id := ("v2:"+code).sha256_text().substr(0,22)
	var definition := Registry.definition(Registry.FIRST_STEPS)
	var room := {"schema_version":2,"api_version":2,"room_id":room_id,"revision":1,"branch":0,
		"stage_index":0,"level_id":definition.id,"level_version":definition.version,"definition_hash":Registry.descriptor(Registry.FIRST_STEPS).definition_hash,
		"host_id":Fakes.HOST,"guest_id":Fakes.GUEST,"checkpoint":Registry.initial_checkpoint(Registry.FIRST_STEPS),"a_turn_id":null,
		"completed_pair_ids":[],"invite_expires_at":"2026-09-21T12:00:00Z","created_at":"2026-09-14T12:00:00Z","updated_at":"2026-09-14T12:00:00Z",
		"active_role":"a","first_player_id":Fakes.HOST,"active_player_id":Fakes.HOST,"player_slot":"p1",
		"stage_id":definition.stages[0].id,"recording_a":null,"validation":"structural_client_replay_required"}
	# A legacy invitation resolves to the same bounded ID shape as the service.
	var legacy := {"schema_version":1,"room_id":code.sha256_text().substr(0,22),"revision":1,"attempt":0,"level_id":"first-light","level_index":0,
		"host_id":Fakes.HOST,"guest_id":Fakes.GUEST,"first_player_id":Fakes.HOST,"active_role":"a","recordings":{"a":null,"b":null}}
	api.responder = func(request: Dictionary) -> Dictionary:
		if request.path=="/v1/rooms/join": return {"ok":true,"data":legacy.duplicate(true)}
		if request.path=="/v2/capabilities": return {"ok":true,"data":_caps(true)}
		if request.path=="/v2/rooms": return {"ok":true,"data":{"rooms":[]}}
		if request.path=="/v2/rooms/join" or request.path=="/v2/rooms/"+room_id: return {"ok":true,"status":200,"data":room.duplicate(true)}
		return {"ok":false,"error":"Unexpected synthetic request","status":404}
	app.saves.update_values({"room":legacy.duplicate(true)})
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(1280,960)]:
		viewport.size=size
		await _open_room_hub(app)
		_check(_find_button(app.room_hub_flow.screen,"Join your friend")==null,"The hub offers no ambiguous generic join")
		_check(_invite_field(app)!=null and _find_button(app.room_hub_flow.screen,"Join")!=null,"The hub shows an invitation field with Join")
		var back := _find_button(app.room_hub_flow.screen,"Back")
		_check(back!=null and Rect2(Vector2.ZERO,Vector2(size)).encloses(back.get_global_rect()),"Hub Back stays on screen at "+str(size))
		if size==Vector2i(1280,720): await _capture("first-steps-invitation-join",viewport)
	await _open_room_hub(app)
	api.calls.clear()
	var hub_join := _find_button(app.room_hub_flow.screen,"Join")
	_check(hub_join!=null and hub_join.disabled,"Hub Join is disabled while the invitation field is empty")
	_invite_field(app).text="  "+code.to_lower().substr(0,10)+"-"+code.to_lower().substr(10)+"  "
	_invite_field(app).text_changed.emit(_invite_field(app).text)
	_check(hub_join!=null and not hub_join.disabled,"Hub Join is enabled once a code is entered")
	_find_button(app.room_hub_flow.screen,"Join").pressed.emit()
	await _settle_join(app)
	# The resolver is not deployed, so the single invitation field falls back to
	# the existing modern join and still issues exactly one durable v2 mutation.
	_check(api.calls.any(func(call: Dictionary)->bool: return call.path=="/v1/invitations/resolve"),"Hub join tries the invitation resolver before falling back")
	var room_mutations: Array = api.calls.filter(func(call: Dictionary)->bool: return call.method==HTTPClient.METHOD_POST and call.path.begins_with("/v2/rooms"))
	_check(room_mutations.size()==1 and room_mutations[0].path=="/v2/rooms/join" and room_mutations[0].body.invite_code==code,"Hub invitation join normalizes then sends only its one durable v2 mutation")
	_check(is_instance_valid(app.relay_child) and app.relay_child.chapter_key==Registry.FIRST_STEPS,"Hub invitation join opens the exact returned First Steps world")
	_check(app.saves.data.room.room_id==legacy.room_id,"Hub chapter join preserves the earlier-island saved room")
	var waiting = app.relay_child
	if is_instance_valid(waiting):
		waiting.set_process(false)
		waiting.set_physics_process(false)
		var before_room: Dictionary = waiting.journey.snapshot()
		var before_pending: Dictionary = waiting.journey.pending()
		var before_saved := Canonical.digest(store.values)
		var before_writes := store.writes
		var before_calls := api.calls.size()
		waiting._show_online_waiting()
		_check(waiting.mode=="online_waiting" and waiting.world.actor_badges.p1.text=="You" and waiting.world.actor_badges.p0.text=="Friend","Joined First Steps guest sees their own spirit as You before the host records")
		_check(not waiting.running and _find_button(waiting.overlay,"Record")==null,"Correct guest label grants no First Steps recording authority")
		_check(Canonical.same(before_room,waiting.journey.snapshot()) and Canonical.same(before_pending,waiting.journey.pending()) and Canonical.digest(store.values)==before_saved and store.writes==before_writes and api.calls.size()==before_calls,"First Steps viewer presentation leaves canonical room, pending request and storage untouched")
		await _capture("first-steps-guest-waiting-identity",viewport)
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	# Persist a real failed creation intent, then construct a fresh session to
	# prove the hub invitation field cannot bypass a durably held chapter lock.
	# The joined room stays readable: a restarted session checks it once before
	# any other room action.
	api.responder=func(request: Dictionary)->Dictionary:
		if request.method==HTTPClient.METHOD_GET and request.path=="/v2/rooms/"+room_id: return {"ok":true,"status":200,"data":room.duplicate(true)}
		return {"ok":false,"status":0,"code":"connection_interrupted","error":"Synthetic lost response"}
	_check((await app.relay_session.create_room(Registry.FIRST_STEPS)).is_empty() and not app.relay_session.pending_lobby().is_empty(),"Uncertain real chapter request is durably held")
	var pending: Dictionary = app.relay_session.pending_lobby()
	var persisted := Canonical.digest(store.values)
	app.relay_session.invalidate_identity()
	app.relay_session=Session.new(api,app._relay_identity,store)
	api.calls.clear()
	await _open_room_hub(app)
	var held := _invite_field(app)
	held.text=code
	_find_button(app.room_hub_flow.screen,"Join").pressed.emit()
	for _frame in 40: await process_frame
	_check(Canonical.same(app.relay_session.pending_lobby(),pending) and Canonical.digest(store.values)==persisted and not api.calls.any(func(call: Dictionary)->bool: return call.method==HTTPClient.METHOD_POST and call.path=="/v2/rooms/join"),"A hub invitation join cannot bypass the held chapter request or issue a conflicting join after restart")
	# The hub offers the retry the old lobby had; it resends the same saved request.
	await _reopen_hub(app)
	var held_panel: Control = app.room_hub_flow.screen.find_child("HeldRequest",true,false) if is_instance_valid(app.room_hub_flow.screen) else null
	var retry := _find_button(app.room_hub_flow.screen,"Retry saved create / join request") if is_instance_valid(app.room_hub_flow.screen) else null
	_check(held_panel != null and held_panel.visible and retry != null and retry.is_visible_in_tree(),"The hub shows a retry for the held chapter request")
	api.responder=func(request: Dictionary)->Dictionary:
		if request.path=="/v2/capabilities": return {"ok":true,"data":_caps(true)}
		if request.path=="/v2/rooms" and request.method==HTTPClient.METHOD_GET: return {"ok":true,"data":{"rooms":[]}}
		if request.method==HTTPClient.METHOD_GET and request.path=="/v2/rooms/"+room_id: return {"ok":true,"status":200,"data":room.duplicate(true)}
		return {"ok":false,"status":0,"code":"connection_interrupted","error":"Synthetic lost response"}
	api.calls.clear()
	if retry != null: retry.pressed.emit()
	for _frame in 40: await process_frame
	var resent: Array = api.calls.filter(func(call: Dictionary)->bool: return call.method==HTTPClient.METHOD_POST and call.path=="/v2/rooms")
	_check(resent.size()==1 and Canonical.same(resent[0].body,pending.body),"Retry resends the held create request unchanged")
	_check(app.mode=="rooms" and is_instance_valid(app.room_hub_flow.screen) and not app.relay_session.pending_lobby().is_empty(),"A retry that is still unanswered returns to the hub and keeps the request held")
	api.responder=Callable()
	if app.relay_session != null: app.relay_session.invalidate_identity()
	app.relay_session=null
	viewport.queue_free()
	await process_frame
	await process_frame

func _invite_field(app: Node) -> LineEdit:
	for edit: LineEdit in app.room_hub_flow.screen.find_children("*","LineEdit",true,false):
		if "Invitation" in edit.placeholder_text: return edit
	return null

func _open_room_hub(app: Node) -> void:
	app.room_hub_flow.show_rooms()
	var deadline := Time.get_ticks_msec()+6000
	while not is_instance_valid(app.room_hub_flow.screen) and Time.get_ticks_msec()<deadline: await process_frame
	await process_frame
	await process_frame

func _settle_join(app: Node) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while not is_instance_valid(app.relay_child) and Time.get_ticks_msec()<deadline: await process_frame
	await process_frame
	await process_frame
