extends "res://tests/test_main_story.gd"
## Real Main/Owner/Coordinator/Preview composition with synthetic transport.
## Retained native recordings keep their original simulation pins throughout.
const ComfortPreview = preload("res://relay_preview.gd")
const ComfortJourney = preload("res://services/relay_journey.gd")
const ComfortSave = preload("res://services/local_save.gd")
const ComfortRelay = preload("res://core/v2/simulation_v2.gd")
const ComfortRedo = preload("res://tests/test_redo_client.gd")
const LEGACY_RECENT := "LLLLLLLLLLLLLLLLLLLLLL"
var comfort_paths: Array[String] = []

class ComfortHarness:
	extends UiHarness
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if path.ends_with("/redo"):
			calls.append({"method":method,"path":path,"body":body.duplicate(true)})
			await get_tree().process_frame
			if method != HTTPClient.METHOD_GET: return {"ok":false,"status":409,"code":"unexpected_redo_mutation"}
			var room: Dictionary = rooms.get(path.get_slice("/",3),{})
			var source := ComfortRedo.Client.source_for("relay",room)
			return {"ok":true,"status":200,"data":{"schema_version":1,"source":null if source.is_empty() else source,"request":null}}
		return await super.request_json(method,path,body)

func _run() -> void:
	_make_story_fixture()
	await _recent_admission_hold()
	await _recent_control_hold()
	await _recent_ordinary_hold()
	await _legacy_redo_story_hold(false)
	await _legacy_redo_story_hold(true)
	await _receiver_redo_boundary(true)
	await _receiver_redo_boundary(false)
	await _picker_and_story_back()
	await _completed_local_back()
	for path: String in comfort_paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("Story comfort composition: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _comfort_path(label: String) -> String:
	var path := "user://story-comfort-"+label+"-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	comfort_paths.append(path)
	return path

func _main_for(c: Dictionary) -> Dictionary:
	var result := super._main_for(c)
	result.viewport.handle_input_locally = true
	result.app.saves.path = _comfort_path("main")
	result.app.legacy_redo = ComfortRedo.Client.new(c.h,c.h.identity,ComfortRedo.MemoryStore.new())
	return result

func _recent_admission_hold() -> void:
	var c := await _lobby_setup()
	c.h.fail_post = true
	await c.app._story_lobby_action("create",Protocol.key(fixture.definition))
	var pending: Dictionary = c.owner.pending_lobby()
	_check(not pending.is_empty(),"Lost Create has a durable exact admission before cached Recent navigation")
	await _tap_recent_and_assert_hold(c,"unknown Story admission")
	_check(Canonical.same(c.owner.pending_lobby(),pending),"Cached legacy acceptance cannot replace the original Story admission key/body")
	await _dispose_ui(c)

func _recent_control_hold() -> void:
	var c := await _setup(true)
	_check(not await c.owner.continue_current() and not c.owner.pending().is_empty(),"Actual completed native source has an uncertain Continue")
	var pending: Dictionary = c.owner.pending()
	var cold := _cold(c)
	c.online = cold.online
	c.owner = cold.owner
	c.merge(_main_for(c))
	await _tap_recent_and_assert_hold(c,"cold Story Continue recovery")
	_check(Canonical.same(c.owner.pending(),pending) and c.owner.bound_campaign().campaign_room_id == c.anchor,"Cold cached Recent tap preserves exact Continue and bound anchor")
	await _dispose_ui(c)

func _recent_ordinary_hold() -> void:
	var c := await _lobby_setup()
	_check(await c.online.open_room(c.anchor),"Ordinary source opens through native verification")
	_check(not await c.online.coordinator.commit(_json("res://tests/fixtures/cooperative/upper-path-a.json")),"Ordinary A commit loses its response after durable prepare")
	var pending: Dictionary = c.online.coordinator.pending()
	_check(not pending.is_empty() and c.owner.bound_campaign().is_empty(),"Ordinary pending case does not rely on any bound Story lock")
	# Reconstruct both services, then let the actual Main guard load the saved
	# ordinary recovery itself; no direct coordinator selection is injected.
	c.online = Online.new(c.h,c.h.identity,c.h.store)
	c.online.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	c.owner = Owner.new(c.online,c.h.identity,[fixture.definition],c.app._campaign_leave_ready,c.h.store)
	c.app.relay_session = c.online
	c.app.campaign_owner = c.owner
	_check(c.owner.restore_owner(),"Empty campaign owner restores independently of ordinary pending work")
	await _tap_recent_and_assert_hold(c,"cold ordinary V2 pending turn")
	_check(c.online.coordinator != null and Canonical.same(c.online.coordinator.pending(),pending),"Legacy Recent tap keeps the exact ordinary pending recording/body")
	await _dispose_ui(c)

func _tap_recent_and_assert_hold(c: Dictionary, label: String) -> void:
	var room := {"room_id":LEGACY_RECENT,"level_id":"first-light","host_id":HOST,"guest_id":GUEST,"active_role":"a","revision":1}
	c.app.mode = "recent_rooms"
	var chapters: Array[Dictionary] = []
	c.app._draw_recent_rooms({"ok":true,"data":{"rooms":[room]}},chapters,"")
	await _settle()
	var cached: Button
	for button: Button in c.app.overlay.find_children("*","Button",true,false):
		if button.get_meta("recent_room_id","") == LEGACY_RECENT: cached = button
	var local: Dictionary = c.app.saves.data.duplicate(true)
	var scopes: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.calls.size()
	var writes: int = c.h.store.writes.size()
	var last_room: String = c.online.last_room()
	await _comfort_tap(c.viewport,cached,"cached legacy Recent row during "+label)
	_check(c.app.active_room.is_empty() and c.app.mode == "recent_rooms" and not is_instance_valid(c.app.relay_child),"Cached legacy row cannot enter or replace gameplay during "+label)
	_check(Canonical.same(local,c.app.saves.data) and Canonical.same(scopes,c.h.store.saved) and writes == c.h.store.writes.size(),"Refused cached navigation preserves local room, control, draft and photo scopes during "+label)
	_check(c.h.calls.size() == calls and c.online.last_room() == last_room,"Refused cached navigation sends no request and keeps ordinary selection during "+label)
	_check(not c.app.notices.is_empty(),"Blocked cached navigation explains its recovery hold")

func _legacy_redo_story_hold(cold: bool) -> void:
	var c := await _lobby_setup()
	_check(c.owner.bind_campaign(c.anchor,Protocol.key(fixture.definition)) and await c.owner.refresh() and await c.owner.select_current() and c.owner.adopt_selected(),"Legacy redo fixture starts with actual lobby capabilities and a native selected Story")
	_check(c.owner.can_leave(),"Selected Story has no independent control/gameplay hold before the legacy redo fixture")
	var room := {"room_id":ComfortRedo.ROOM,"level_id":"first-light","revision":2,"attempt":0,"level_index":0,"host_id":HOST,"guest_id":GUEST,"first_player_id":HOST,"active_role":"b","recordings":{"a":_json("res://tests/fixtures/first-light-a.json"),"b":null}}
	var redo_api := ComfortRedo.Api.new()
	redo_api.family = "legacy"
	redo_api.room = room.duplicate(true)
	redo_api.player_id = HOST
	redo_api.device_token = c.h.device_token
	redo_api.base_url = c.h.base_url
	root.add_child(redo_api)
	var source := ComfortRedo.Client.source_for("legacy",room)
	redo_api.requested = {"request_id":Canonical.digest(source),"source":source,"status":"pending"}
	var storage := ComfortRedo.MemoryStore.new()
	var client := ComfortRedo.Client.new(redo_api,c.h.identity,storage)
	_check(client.bind_room("legacy",room) and await client.refresh() and client.can_accept(),"Actual legacy client observes a partner's request pinned to the retained native A hash")
	redo_api.drop_next = true
	_check(not await client.accept() and redo_api.room.attempt == 1 and not client.pending().is_empty(),"Server accepts legacy redo once while the client retains its exact lost-reply request")
	var pending: Dictionary = client.pending()
	c.app.saves.data.room = room.duplicate(true)
	c.app.legacy_redo = client
	if cold:
		# New service instances load the unchanged owner/index and redo bytes.
		# No copied in-memory request or explicit bind is supplied to Main.
		var restored := _cold(c)
		c.online = restored.online
		c.owner = restored.owner
		c.app.relay_session = c.online
		c.app.campaign_owner = c.owner
		c.owner._leave_ready = c.app._campaign_leave_ready
		_check(await c.owner.load_campaign_lobby(),"Cold Owner explicitly reloads valid lobby capabilities before testing admission guards")
		c.app.legacy_redo = ComfortRedo.Client.new(c.h,c.h.identity,storage)
		c.app.legacy_redo_restore_scope = ""
		_check(c.app.legacy_redo.pending().is_empty(),"Cold Main starts with no in-memory legacy redo request")
	_check(c.owner.supports_campaign_creation(Protocol.key(fixture.definition)),"Fresh Create/Join are enabled so their refusal must exercise the pending source guard")
	var saved_redo: Dictionary = storage.values.duplicate(true)
	var saved_scopes: Dictionary = c.h.store.saved.duplicate(true)
	var local: Dictionary = c.app.saves.data.duplicate(true)
	var bound: Dictionary = c.owner.bound_campaign()
	var selected: String = c.owner.selected_room()
	var count: int = c.h.calls.size()
	var redo_count: int = redo_api.calls.size()
	for action: String in ["create","join","open","resume"]:
		c.app.mode = "story_lobby"
		var value: Dictionary = {"campaign_room_id":OTHER,"campaign_key":Protocol.key(fixture.definition)} if action == "open" else Protocol.key(fixture.definition)
		await c.app._story_lobby_action(action,value,"AB".repeat(10))
		_check(c.app.mode == "story_lobby" and not is_instance_valid(c.app.relay_child),"Uncertain legacy accept blocks Story "+action+(" after cold restore" if cold else " while warm"))
		_check(c.h.calls.size() == count and redo_api.calls.size() == redo_count,"Story refusal neither retries legacy acceptance nor sends a new campaign request")
		_check(Canonical.same(saved_redo,storage.values) and Canonical.same(pending,c.app.legacy_redo.pending()),"Story action preserves exact original legacy redo request and durable journal")
		_check(Canonical.same(saved_scopes,c.h.store.saved) and Canonical.same(local,c.app.saves.data) and Canonical.same(bound,c.owner.bound_campaign()) and selected == c.owner.selected_room(),"Story refusal preserves existing campaign selection and both save families")
	redo_api.free()
	await _dispose_ui(c)

func _receiver_context(story: bool) -> Dictionary:
	var h := ComfortHarness.new()
	root.add_child(h)
	h.player_id = GUEST
	h.identity_value.player_id = GUEST
	h.view = fixture.active_view.duplicate(true)
	h.view.player_slot = "p1"
	h.view.invite_code = null
	h.view.invite_expires_at = null
	h.capabilities = Boundaries.campaign_capabilities(fixture.definition)
	var anchor: String = h.view.campaign_room_id
	var room := _room("high-and-low",anchor,false)
	room.merge({"revision":2,"recording_a":_json("res://tests/fixtures/cooperative/upper-path-a.json"),"a_turn_id":"t0-0-a","active_role":"b","active_player_id":GUEST,"player_slot":"p1"},true)
	room.erase("invite_code")
	h.rooms[anchor] = room
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(anchor),"Real native verifier admits the guest's retained High & Low A source")
	online.capabilities = h.capabilities.duplicate(true)
	var redo_store := ComfortRedo.MemoryStore.new()
	online._redo = ComfortRedo.Client.new(h,h.identity,redo_store)
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(owner.restore_owner(),"Receiver owner restores without fabricated selection")
	if story:
		_check(owner.bind_campaign(anchor,Protocol.key(fixture.definition)),"Story receiver binds its actual campaign")
		_check(await owner.refresh() and await owner.select_current() and owner.adopt_selected(),"Story receiver is selected and adopted through the native target bridge")
	var c := {"h":h,"online":online,"owner":owner,"anchor":anchor,"redo_store":redo_store}
	c.merge(_main_for(c))
	if story:
		await c.app._story_lobby_action("resume")
	else:
		c.app.mode = "relay_rooms"
		c.app.selected_online_chapter = "high-and-low@1"
		await c.app._relay_lobby_action("open",anchor)
	return c

func _receiver_redo_boundary(story: bool) -> void:
	var c := await _receiver_context(story)
	var child: Node = c.app.relay_child
	_check(is_instance_valid(child),"Main opens an actual "+("Story" if story else "ordinary")+" receiver Preview")
	if not is_instance_valid(child): await _dispose_ui(c); return
	if story:
		_check(c.app.campaign_flow.busy() and child._story_hold >= 0,"Story arrival owns input before Ready")
		child._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		await _settle()
		_check(not c.app.campaign_flow.busy() and child._story_hold < 0 and c.app.mode == "relay_online","Android Back dismisses arrival without leaving the Story child")
	_check(child.mode == "ready" and child.role == "b" and not child.running and child.journey.my_turn(),"Actual second player has a native-verified ready turn")
	var room_before: Dictionary = child.journey.snapshot()
	var flow: Node = child.story_flow
	# Scoped authority must remain enough even during a detached presentation
	# hook. This does not grant a new room context or replace its coordinator.
	for detached: bool in ([false,true] if story else [false]):
		if detached: child.story_flow = null; child._show_ready()
		var calls: int = c.h.calls.size()
		child.online_refresh_queued = true
		await child._service_online_refresh()
		var reads: Array = c.h.calls.slice(calls)
		_check(reads.any(func(call: Dictionary): return call.method == HTTPClient.METHOD_GET and call.path == "/v2/rooms/"+c.anchor),"The ordinary refresh timer really reads the native room during redo boundary coverage")
		_check(reads.all(func(call: Dictionary): return call.method == HTTPClient.METHOD_GET),"Automatic receiver refresh remains read-only")
		var redo_reads: Array = reads.filter(func(call: Dictionary): return call.path.ends_with("/redo"))
		if story:
			_check(redo_reads.is_empty() and _button(child.overlay,"Ask for redo") == null and _button(child.overlay,"Turn requests") == null and _button(child.overlay,"Redo requested") == null,"Story receiver neither polls nor offers ordinary redo, including a detached Flow hook")
			calls = c.h.calls.size()
			child._open_redo()
			await _settle()
			_check(not is_instance_valid(child._redo_screen) and child.mode == "ready" and c.h.calls.size() == calls,"A stale ordinary redo callback cannot open or dispatch on Story authority")
		else:
			_check(redo_reads.size() == 1 and _button(child.overlay,"Ask for redo") != null,"Ordinary receiver retains its real redo action and one scheduled request GET")
			await _comfort_tap(c.viewport,_button(child.overlay,"Ask for redo"),"ordinary Ask for redo")
			_check(is_instance_valid(child._redo_screen) and child.mode == "redo_requests" and _button(child._redo_screen,"Ask for redo") != null,"Ordinary viewport click opens the functioning advisory panel")
			if is_instance_valid(child._redo_screen): child._redo_screen.close()
			for i in range(8): await process_frame
	child.story_flow = flow
	_check(Canonical.same(room_before,child.journey.snapshot()) and child.journey.pending().is_empty() and c.redo_store.values.is_empty(),"Observing redo boundaries does not fork, submit or persist a gameplay/request intent")
	if story:
		child._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		await _settle()
		_check(c.app.mode == "story_lobby" and c.owner.bound_campaign().campaign_room_id == c.anchor,"Back after arrival returns to Story while preserving its bound owner")
	await _dispose_ui(c)

func _picker_and_story_back() -> void:
	var c := await _lobby_setup()
	c.app._show_journey()
	await _settle()
	var expected: Array[String] = [Registry.FIRST_STEPS,Registry.RELAY]
	for key: String in Registry.keys():
		if Registry.is_cooperative(key): expected.append(key)
	for key: String in expected:
		var variants: Dictionary = {}
		for button: Button in c.app.overlay.find_children("*","Button",true,false):
			if button.get_meta("completion_chapter","") == key: variants[button.get_meta("completion_variant","")] = button
		_check(variants.has("solo") and variants.has("friend"),"Merged picker retains Solo and Together for "+key)
		if variants.has("solo") and variants.has("friend"):
			_check(variants.solo.get_parent() == variants.friend.get_parent() and str(variants.solo.text).contains("Solo") and str(variants.friend.text).begins_with("Together"),"Solo and Together remain paired in the same actual chapter row")
	await _comfort_tap(c.viewport,_button(c.app.overlay,"Story"),"Story entry beside paired chapters")
	for i in range(12): await process_frame
	_check(c.app.mode == "story_lobby" and _button(c.app.overlay,"Start") != null,"The merged picker still opens the actual Story lobby")
	c.app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	_check(c.app.mode == "journey" and _button(c.app.overlay,"Story") != null,"Main Android Back returns from Story to the paired chapter picker")
	await _dispose_ui(c)

func _completed_local_back() -> void:
	var path := _comfort_path("retained-relay")
	var definition := Registry.definition(Registry.RELAY)
	var envelope := ComfortSave.defaults()
	envelope.relay = {"schema_version":2,"simulation_version":2,"level_id":definition.id,"level_version":definition.version,"definition_hash":Canonical.digest(definition),"pairs":[],"a":_json("res://tests/fixtures/v2/relay-a.json"),"draft":{}}
	var file := FileAccess.open(path,FileAccess.WRITE)
	_check(file != null,"Create isolated exact old-rules Relay journal")
	if file == null: return
	file.store_string(JSON.stringify(envelope))
	file.close()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var child := ComfortPreview.new()
	child.journey = ComfortJourney.new(path)
	child.settings = {"sound":false,"music":false,"haptics":false,"reduced_motion":true,"assistance":true,"left_handed":false}
	viewport.add_child(child)
	child.set_process(false)
	child.set_physics_process(false)
	_check(child.role == "b" and child.journey.simulation_version() == 2,"Local pending receiver retains the actual old rules instead of silently upgrading")
	child._begin()
	for input: Dictionary in ComfortRelay.expand_recording_inputs(_json("res://tests/fixtures/v2/relay-b.json")): child.advance_input(input)
	child._finish()
	if child.mode == "bloom": child._process(ComfortPreview.COMPLETION_DURATION)
	_check(child.mode == "review" and child.sim.snapshot().complete,"Actual recorded B motion reaches native completion before confirmation tests")
	var record: Dictionary = child.review.duplicate(true)
	var tick: int = child.sim.tick
	var bytes := _comfort_save_bytes(path)
	for label: String in ["Retry","Restart chapter"]:
		for android: bool in [true,false]:
			await _comfort_tap(viewport,_button(child.overlay,label),"local "+label+" confirmation")
			_check(child.mode == ("confirm_retry" if label == "Retry" else "confirm_restart_chapter"),"Completed local rehearsal requires deliberate "+label+" confirmation")
			if android:
				child._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
			else:
				var escape := InputEventKey.new()
				escape.physical_keycode = KEY_ESCAPE
				escape.pressed = true
				child._unhandled_key_input(escape)
			await _settle()
			_check(child.mode == "review" and child.sim.tick == tick and Canonical.same(child.review,record),"Back/Escape cancels "+label+" and keeps the same completed rehearsal")
			_check(bytes == _comfort_save_bytes(path) and child.journey.archived_attempts().is_empty(),"Cancelled "+label+" neither rewrites nor archives the retained A/B draft")
	viewport.queue_free()
	await _settle()

func _comfort_save_bytes(path: String) -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".tmp", ".backup"]:
		result[suffix] = FileAccess.get_file_as_bytes(path+suffix) if FileAccess.file_exists(path+suffix) else PackedByteArray()
	return result

func _comfort_tap(viewport: SubViewport, button: Button, label: String) -> void:
	_check(button != null and not button.disabled,"Actual control is available: "+label)
	if button == null or button.disabled: return
	var ancestor: Node = button.get_parent()
	while ancestor != null and not ancestor is ScrollContainer: ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer: ancestor.ensure_control_visible(button)
	await _settle()
	_check(viewport.get_visible_rect().encloses(button.get_global_rect()),"Scrolled control is reachable: "+label)
	var point := button.get_global_rect().get_center()
	var clicked: Array = []
	button.pressed.connect(func(): clicked.append(true))
	_pointer(viewport,point,true)
	await process_frame
	_pointer(viewport,point,false)
	await _settle()
	_check(clicked.size() == 1,"Real viewport input activates the control once: "+label)
