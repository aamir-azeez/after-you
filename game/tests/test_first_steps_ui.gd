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
	await _lobby_actions_fit_without_scrolling()
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

func _online_chooser() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves = Save.new(_path("main"))
	app.saves.data.settings.sound=false
	_check(app.saves.flush(),"The online chooser persists mute before Main reloads its settings")
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
			await _check_lobby_bounds(app.overlay, Rect2(Vector2.ZERO, size))
			var choices: OptionButton = app.overlay.find_children("*","OptionButton",true,false)[0]
			choices.item_selected.emit(1)
			_check(app.selected_online_chapter==Registry.RELAY,"Actual chooser signal selects the exact Relay descriptor")
			_check(not _find_button(app.overlay,"Create this chapter").disabled,"Relay stays available when the new chapter is not enabled")
		if enabled:
			viewport.size = Vector2i(960, 540)
			app.selected_online_chapter = Registry.ROLLING_HOME
			app._draw_relay_lobby()
			await process_frame
			await process_frame
			await _check_lobby_bounds(app.overlay, Rect2(Vector2.ZERO, Vector2(viewport.size)))
			for label: String in ["Create this chapter", "Join", "Refresh availability and rooms", "Practice this chapter solo", "Back"]:
				_check(_find_button(app.overlay, label) != null, "Premium chapter lobby keeps the expected action: " + label)
			# A retained room adds a real list; an empty lobby alone cannot prove fit.
			var selected := Registry.descriptor(Registry.ROLLING_HOME)
			var retained := {"api_version": 2, "room_id": "R".repeat(22), "host_id": Fakes.HOST, "guest_id": Fakes.GUEST,
				"level_id": selected.level_id, "level_version": selected.level_version, "definition_hash": selected.definition_hash}
			api.responder = func(request: Dictionary) -> Dictionary:
				return {"ok": true, "data": _caps(true) if request.path == "/v2/capabilities" else {"rooms": [retained]}}
			_check(await app.relay_session.load_lobby() and app.relay_session.room_ids().size() == 1, "Premium lobby reads one participant-owned retained room through the actual session")
			app._draw_relay_lobby()
			await process_frame
			await process_frame
			await _check_lobby_bounds(app.overlay, Rect2(Vector2.ZERO, Vector2(viewport.size)))
			await _capture("rolling-home-lobby-with-room-small", viewport)
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

func _check_bounds(node: Node, rect: Rect2) -> void:
	if node is ScrollContainer:
		_check(rect.encloses(node.get_global_rect()), "Online chooser scrolling body fits the viewport")
		return
	if node is Button or node is Label or node is LineEdit or node is PanelContainer:
		_check(rect.encloses(node.get_global_rect()),"Online chooser content fits "+str(rect.size)+": "+str(node.get_class()) + " " + str(node.get_global_rect()))
	for child: Node in node.get_children(): _check_bounds(child,rect)

func _check_lobby_bounds(node: Node, rect: Rect2) -> void:
	_check_bounds(node, rect)
	var lists := node.find_children("*", "ScrollContainer", true, false).filter(func(item: Node): return item.is_visible_in_tree())
	_check(lists.size() == 1, "The chapter lobby has one visible bounded scrolling body")
	if lists.size() != 1: return
	var scroll := lists[0] as ScrollContainer
	var back := _find_button(node, "Back")
	_check(back != null and not scroll.is_ancestor_of(back) and rect.encloses(back.get_global_rect()), "Back stays visible outside the scrolling lobby")
	for child: Node in scroll.find_children("*", "Control", true, false):
		if not (child is Button or child is Label or child is LineEdit): continue
		if not child.is_visible_in_tree(): continue
		scroll.ensure_control_visible(child)
		await process_frame
		await process_frame
		_check(scroll.get_global_rect().grow(0.5).encloses(child.get_global_rect()), "Each lobby paragraph, chooser, room, and action can be brought fully into view: " + child.get_class())

func _lobby_scroll(node: Node) -> ScrollContainer:
	for item: Node in node.find_children("*", "ScrollContainer", true, false):
		if item.is_visible_in_tree(): return item
	return null

func _lobby_actions_fit_without_scrolling() -> void:
	# Play together must show "Create this chapter" and the invitation "Join"
	# without scrolling on a phone and a wide phone, and keep them reachable
	# (through the bounded scroll, never clipped) on a short landscape screen.
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var app := Main.new()
	app.saves = Save.new(_path("lobby-fit"))
	app.saves.data.settings.sound = false
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var identity := Fakes.Identity.new()
	var api := Fakes.FakeApi.new()
	app.add_child(api)
	app.api = api
	var store := Fakes.MemoryStore.new()
	app.relay_session = Session.new(api, identity.get_value, store)
	api.responder = func(request: Dictionary) -> Dictionary:
		return {"ok": true, "data": _caps(true) if request.path == "/v2/capabilities" else {"rooms": []}}
	_check(await app.relay_session.load_lobby(), "Lobby fit check reads a protocol-verified capability response")
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(2340, 1080)]:
		viewport.size = size
		app.selected_online_chapter = Registry.RELAY
		app._draw_relay_lobby()
		await process_frame
		await process_frame
		var scroll := _lobby_scroll(app.overlay)
		_check(scroll != null, "Play together keeps its one bounded scrolling body at " + str(size))
		if scroll == null: continue
		# A fresh draw starts unscrolled; the primary create and invitation join
		# are already within the visible scroll viewport at these sizes.
		_check(scroll.scroll_vertical == 0, "The lobby opens unscrolled at " + str(size))
		var visible := scroll.get_global_rect()
		for label: String in ["Create this chapter", "Join"]:
			var button := _find_button(app.overlay, label)
			_check(button != null and button.is_visible_in_tree(), "Lobby shows " + label + " at " + str(size))
			if button != null:
				_check(visible.encloses(button.get_global_rect()), label + " is visible without scrolling at " + str(size))
	# Short landscape: columns stack, so the actions ride the scroll but stay reachable.
	viewport.size = Vector2i(800, 360)
	app.selected_online_chapter = Registry.RELAY
	app._draw_relay_lobby()
	await process_frame
	await process_frame
	var short_scroll := _lobby_scroll(app.overlay)
	_check(short_scroll != null, "Play together keeps a bounded scrolling body at 800x360")
	var back := _find_button(app.overlay, "Back")
	_check(back != null and short_scroll != null and not short_scroll.is_ancestor_of(back)
		and Rect2(Vector2.ZERO, Vector2(800, 360)).encloses(back.get_global_rect()),
		"Back stays visible outside the scroll at 800x360")
	if short_scroll != null:
		for label: String in ["Create this chapter", "Join"]:
			var button := _find_button(app.overlay, label)
			_check(button != null, "Short landscape lobby still offers " + label)
			if button != null:
				short_scroll.ensure_control_visible(button)
				await process_frame
				await process_frame
				_check(short_scroll.get_global_rect().grow(0.5).encloses(button.get_global_rect()),
					label + " scrolls fully into view at 800x360")
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
		if request.path=="/v2/rooms/join" or request.path=="/v2/rooms/"+room_id: return {"ok":true,"data":room.duplicate(true)}
		return {"ok":false,"error":"Unexpected synthetic request","status":404}
	app.saves.update_values({"room":legacy.duplicate(true)})
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(1280,960)]:
		viewport.size=size
		await _open_room_hub(app)
		_check(_find_button(app.room_hub_screen,"Join your friend")==null,"The hub offers no ambiguous generic join")
		_check(_invite_field(app)!=null and _find_button(app.room_hub_screen,"Join")!=null,"The hub shows an invitation field with Join")
		var back := _find_button(app.room_hub_screen,"Back")
		_check(back!=null and Rect2(Vector2.ZERO,Vector2(size)).encloses(back.get_global_rect()),"Hub Back stays on screen at "+str(size))
		if size==Vector2i(1280,720): await _capture("first-steps-invitation-join",viewport)
	await _open_room_hub(app)
	api.calls.clear()
	var hub_join := _find_button(app.room_hub_screen,"Join")
	_check(hub_join!=null and hub_join.disabled,"Hub Join is disabled while the invitation field is empty")
	_invite_field(app).text="  "+code.to_lower().substr(0,10)+"-"+code.to_lower().substr(10)+"  "
	_invite_field(app).text_changed.emit(_invite_field(app).text)
	_check(hub_join!=null and not hub_join.disabled,"Hub Join is enabled once a code is entered")
	_find_button(app.room_hub_screen,"Join").pressed.emit()
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
	api.responder=func(_request: Dictionary)->Dictionary: return {"ok":false,"status":0,"code":"connection_interrupted","error":"Synthetic lost response"}
	_check((await app.relay_session.create_room(Registry.FIRST_STEPS)).is_empty() and not app.relay_session.pending_lobby().is_empty(),"Uncertain real chapter request is durably held")
	var pending: Dictionary = app.relay_session.pending_lobby()
	var persisted := Canonical.digest(store.values)
	app.relay_session.invalidate_identity()
	app.relay_session=Session.new(api,app._relay_identity,store)
	api.calls.clear()
	await _open_room_hub(app)
	var held := _invite_field(app)
	held.text=code
	_find_button(app.room_hub_screen,"Join").pressed.emit()
	for _frame in 40: await process_frame
	_check(Canonical.same(app.relay_session.pending_lobby(),pending) and Canonical.digest(store.values)==persisted and not api.calls.any(func(call: Dictionary)->bool: return call.method==HTTPClient.METHOD_POST and call.path=="/v2/rooms/join"),"A hub invitation join cannot bypass the held chapter request or issue a conflicting join after restart")
	api.responder=Callable()
	if app.relay_session != null: app.relay_session.invalidate_identity()
	app.relay_session=null
	viewport.queue_free()
	await process_frame
	await process_frame

func _invite_field(app: Node) -> LineEdit:
	for edit: LineEdit in app.room_hub_screen.find_children("*","LineEdit",true,false):
		if "Invitation" in edit.placeholder_text: return edit
	return null

func _open_room_hub(app: Node) -> void:
	app._show_rooms()
	var deadline := Time.get_ticks_msec()+6000
	while not is_instance_valid(app.room_hub_screen) and Time.get_ticks_msec()<deadline: await process_frame
	await process_frame
	await process_frame

func _settle_join(app: Node) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while not is_instance_valid(app.relay_child) and Time.get_ticks_msec()<deadline: await process_frame
	await process_frame
	await process_frame
