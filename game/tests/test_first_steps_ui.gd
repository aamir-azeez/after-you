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
		if app.mode=="bloom": app._process(2.0)
		_check(app.mode=="review" and app.journey.role()==record.role,"Actual shared preview requires explicit acceptance for "+name)
		app._accept()
		if app.mode=="checkpoint": app._show_ready()
	_check(app.journey.chapter_complete(),"All four fixture-driven contributions reach the real final shared view")
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
			"premium":false,"recording_version":value.recording_version,"simulation_version":value.simulation_version})
	return {"api_version":2,"recording_version":2,"simulation_version":2,"mutations_enabled":true,
		"validation":"structural_client_replay_required","chapters":chapters}

func _online_chooser() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves = Save.new(_path("main"))
	app.saves.data.settings.sound=false
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var identity := Fakes.Identity.new()
	var api := Fakes.FakeApi.new()
	app.add_child(api)
	app.api = api
	var store := Fakes.MemoryStore.new()
	app.relay_session = Session.new(api,identity.get_value,store)
	for enabled: bool in [false,true]:
		api.responder = func(request: Dictionary) -> Dictionary:
			return {"ok":true,"data":_caps(enabled) if request.path=="/v2/capabilities" else {"rooms":[]}}
		_check(await app.relay_session.load_lobby(),"Online chooser uses a protocol-verified service response")
		for size: Vector2i in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(1280,960)]:
			viewport.size = size
			app.selected_online_chapter = Registry.FIRST_STEPS
			app._draw_relay_lobby()
			await process_frame
			await process_frame
			var create := _find_button(app.overlay,"Create this chapter")
			_check(create!=null and create.disabled==not enabled,"Creation gate follows this chapter's verified availability")
			_check_bounds(app.overlay,Rect2(Vector2.ZERO,size))
			var choices: OptionButton = app.overlay.find_children("*","OptionButton",true,false)[0]
			choices.item_selected.emit(1)
			_check(app.selected_online_chapter==Registry.RELAY,"Actual chooser signal selects the exact Relay descriptor")
			_check(not _find_button(app.overlay,"Create this chapter").disabled,"Relay stays available when the new chapter is not enabled")
	api.responder = Callable()
	app.relay_session.invalidate_identity()
	app.relay_session = null
	viewport.queue_free()
	await process_frame
	await process_frame

func _find_button(node: Node, label: String) -> Button:
	for child: Node in node.find_children("*","Button",true,false):
		if child.text==label: return child
	return null

func _check_bounds(node: Node, rect: Rect2) -> void:
	if node is Button or node is Label or node is LineEdit or node is PanelContainer:
		_check(rect.encloses(node.get_global_rect()),"Online chooser content fits "+str(rect.size)+": "+str(node.get_class()))
	for child: Node in node.get_children(): _check_bounds(child,rect)

func _visible_join_routes() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var app := Main.new()
	app.saves = Save.new(_path("visible-join"))
	app.saves.data.settings.sound=false
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
	var legacy := {"schema_version":1,"room_id":"legacy-test-room","revision":1,"attempt":0,"level_id":"first-light","level_index":0,
		"host_id":Fakes.HOST,"guest_id":Fakes.GUEST,"first_player_id":Fakes.HOST,"active_role":"a","recordings":{"a":null,"b":null}}
	api.responder = func(request: Dictionary) -> Dictionary:
		if request.path=="/v1/rooms/join": return {"ok":true,"data":legacy.duplicate(true)}
		if request.path=="/v2/capabilities": return {"ok":true,"data":_caps(true)}
		if request.path=="/v2/rooms": return {"ok":true,"data":{"rooms":[]}}
		if request.path=="/v2/rooms/join" or request.path=="/v2/rooms/"+room_id: return {"ok":true,"data":room.duplicate(true)}
		return {"ok":false,"error":"Unexpected synthetic request","status":404}
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(1280,960)]:
		viewport.size=size
		app._show_rooms()
		await process_frame
		await process_frame
		_check(_find_button(app.overlay,"Join your friend")==null,"Ambiguous generic join is absent")
		_check_bounds(app.overlay,Rect2(Vector2.ZERO,size))
		if size==Vector2i(1280,720): await _capture("first-steps-explicit-invitation-routes",viewport)
	var fields := app.overlay.find_children("*","LineEdit",true,false)
	fields[0].text=code
	_find_button(app.overlay,"Join an earlier island").pressed.emit()
	await process_frame
	_check(api.calls.size()==1 and api.calls[0].path=="/v1/rooms/join" and api.calls[0].body.invite_code==code,"Visible earlier-island join sends exactly one legacy mutation")
	_check(app.mode=="room" and app.active_room.room_id==legacy.room_id,"Visible legacy join accepts its real earlier-island response")
	api.calls.clear()
	app._show_rooms()
	fields=app.overlay.find_children("*","LineEdit",true,false)
	fields[0].text="  "+code.to_lower().substr(0,10)+"-"+code.to_lower().substr(10)+"  "
	_find_button(app.overlay,"Join a chapter").pressed.emit()
	await process_frame
	_check(is_instance_valid(app.relay_child) and app.relay_child.chapter_key==Registry.FIRST_STEPS,"Visible chapter join opens the exact returned First Steps world")
	var mutations: Array = api.calls.filter(func(call: Dictionary)->bool: return call.method==HTTPClient.METHOD_POST)
	_check(mutations.size()==1 and mutations[0].path=="/v2/rooms/join" and mutations[0].body.invite_code==code,"Chapter join normalizes then sends only its one durable v2 mutation")
	_check(app.saves.data.room.room_id==legacy.room_id,"Chapter join preserves the earlier-island saved room")
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	# Persist a real failed creation intent, then construct a fresh session to
	# prove that the legacy route cannot bypass a chapter lock after restart.
	api.responder=func(_request: Dictionary)->Dictionary: return {"ok":false,"status":0,"code":"connection_interrupted","error":"Synthetic lost response"}
	_check((await app.relay_session.create_room(Registry.FIRST_STEPS)).is_empty() and not app.relay_session.pending_lobby().is_empty(),"Uncertain real chapter request is durably held")
	var pending: Dictionary = app.relay_session.pending_lobby()
	var persisted := Canonical.digest(store.values)
	app.relay_session.invalidate_identity()
	app.relay_session=Session.new(api,app._relay_identity,store)
	api.calls.clear()
	app._show_rooms()
	fields=app.overlay.find_children("*","LineEdit",true,false)
	fields[0].text=code
	_find_button(app.overlay,"Join an earlier island").pressed.emit()
	await process_frame
	_check(api.calls.is_empty() and Canonical.same(app.relay_session.pending_lobby(),pending) and Canonical.digest(store.values)==persisted,"Visible legacy join restores and preserves the exact saved chapter key/body and persisted state without any POST")
	app.saves.update_values({"pending_turn":{"synthetic_unresolved":true}})
	app._show_rooms()
	fields=app.overlay.find_children("*","LineEdit",true,false)
	fields[0].text=code
	_find_button(app.overlay,"Join a chapter").pressed.emit()
	await process_frame
	_check(api.calls.is_empty() and not app.saves.data.pending_turn.is_empty(),"Visible chapter join preserves an unresolved legacy submission before any API request")
	api.responder=Callable()
	app.relay_session.invalidate_identity()
	app.relay_session=null
	viewport.queue_free()
	await process_frame
	await process_frame
