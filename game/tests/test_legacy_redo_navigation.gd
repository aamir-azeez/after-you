extends "res://tests/test_redo_client.gd"
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
const Session = preload("res://services/relay_online_session.gd")
const LobbyFixture = preload("res://tests/test_relay_online.gd")

class CountingStore extends MemoryStore:
	var reads := 0
	func read(scope: String) -> Dictionary:
		reads += 1
		return super.read(scope)

class MainApi extends Api:
	var room_failure := ""
	func configured() -> bool: return true
	func _reply(owner: String, method: int, path: String, body: Dictionary) -> Dictionary:
		if method == HTTPClient.METHOD_GET and path == "/v1/rooms/" + str(room.room_id):
			if not room_failure.is_empty(): return {"ok":false,"status":404,"code":room_failure,"error":"Synthetic room read failed."}
			return {"ok":true,"data":room.duplicate(true)}
		return JSON.parse_string(JSON.stringify(super._reply(owner,method,path,body)))

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var path := "user://legacy-redo-navigation-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var api := MainApi.new()
	api.family = "legacy"
	api.player_id = HOST
	api.room = _room("legacy")
	api.room.level_id = "first-light"
	api.room.invite_code = "A1".repeat(10)
	var source := Client.source_for("legacy",api.room)
	api.requested = {"request_id":Canonical.digest(source),"source":source,"status":"pending"}
	var store := CountingStore.new()
	var app := _make_app(viewport,path,api,store)
	app._accept_room({"ok":true,"data":api.room})
	await _settle()
	_check(_button(app.overlay,"Redo requested") != null,"Fetched partner request survives Main's same-room menu rebuild")
	app._open_legacy_redo()
	await _settle()
	var screen: CanvasLayer = app.redo_screen
	_check(is_instance_valid(screen) and _button(screen,"Redo my turn") != null,"Actual Main panel offers first-player consent")
	api.drop_next = true
	await _tap(viewport,_button(screen,"Redo my turn"))
	var pending: Dictionary = app.legacy_redo.pending()
	_check(api.room.attempt == 1 and pending.get("action") == "accept","Lost consent reply retains its exact legacy fork operation")
	screen.close()
	await _settle()
	_check(app.active_room.active_role == "a" and _button(app.overlay,"Play your turn") == null and _button(app.overlay,"Retry request") != null,"Refreshed A stays behind the unresolved acceptance and exposes recovery")
	# Recreate the actual Main instance and reload its save. Only the durable
	# journal fixture and the server survive this simulated cold application.
	app.remove_child(api)
	root.add_child(api)
	viewport.remove_child(app)
	app.queue_free()
	await _settle()
	app = _make_app(viewport,path,api,store)
	_check(app.active_room.is_empty() and app.legacy_redo.pending().is_empty(),"Cold Main starts without a bound runtime redo client")
	var before := api.calls.size()
	await app._create_room()
	_check(api.calls.size() == before and app.active_room.room_id == ROOM and app.mode == "room","Cold create restores the saved room's acceptance before any new-room POST")
	_check(Canonical.same(app.legacy_redo.pending(),pending),"Cold recovery preserves the original fork key and source")
	await app._join_room("B1".repeat(10))
	await app._join_chapter_room("B1".repeat(10))
	app.relay_session = Session.new(api,app._relay_identity,LobbyFixture.MemoryStore.new())
	await app._relay_lobby_action("create","relay-isles@2")
	await app._relay_lobby_action("join","B1".repeat(10))
	await app._relay_lobby_action("open","S".repeat(22))
	await app._fork_room()
	await app._advance_room()
	_check(api.calls.size() == before,"Both protocols, generic fork and advance cannot hide the unresolved acceptance")
	var other := api.room.duplicate(true)
	other.room_id = "S".repeat(22)
	app._accept_room({"ok":true,"data":other})
	app._apply_foreground_response({"ok":true,"data":other},other.room_id)
	_check(app.active_room.room_id == ROOM and app.saves.data.room.room_id == ROOM,"An incoming different room cannot replace either the visible or durable recovery target")
	var reads := store.reads
	var route := {"room_family":"legacy","room_id":other.room_id,"event_id":"E".repeat(22)}
	for index in range(20): _check(not app._notification_route_safe(route),"A notification cannot navigate away from the unresolved legacy acceptance")
	_check(store.reads == reads,"Repeated notification guards do not reread the redo journal")
	before = api.calls.size()
	await app._refresh_room()
	var calls: Array = api.calls.slice(before)
	_check(calls.size() == 2 and calls.all(func(call: Dictionary) -> bool: return call.method == HTTPClient.METHOD_GET),"Same-room recovery refresh remains available and only reads the room and request")
	for size: Vector2i in [Vector2i(1280,720),Vector2i(960,540)]:
		viewport.size = size
		app._show_room_detail()
		await _settle()
		for label: String in ["Home","Refresh"]:
			var button := _button(app.overlay,label)
			_check(button != null and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()),"Legacy room navigation remains outside the scrolling card at both landscape sizes")
	app._open_legacy_redo()
	await _settle()
	screen = app.redo_screen
	var back := _button(screen,"Back")
	_check(back != null and Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(back.get_global_rect()),"Request panel's fixed Back remains visible on the short viewport")
	await _tap(viewport,_button(screen,"Retry request"))
	_check(screen.accepted and app.legacy_redo.pending().is_empty() and api.receipts.size() == 1,"Visible cold retry resolves the original legacy key without another attempt")
	screen.close()
	await _settle()
	_check(app.active_room.attempt == 1 and _button(app.overlay,"Play your turn") != null,"Recovered acceptance restores the ordinary recordable A menu")
	# A second handoff provides a genuinely pending request while the owner
	# changes during the asynchronous acceptance response.
	api.room.active_role = "b"
	api.room.revision += 1
	api.room.recordings = {"a":{"final_state_hash":"b".repeat(64)},"b":null}
	source = Client.source_for("legacy",api.room)
	api.requested = {"request_id":Canonical.digest(source),"source":source,"status":"pending"}
	app._accept_room({"ok":true,"data":api.room})
	app._open_legacy_redo()
	await _settle()
	screen = app.redo_screen
	api.hold_next = true
	screen._act("accept")
	_check(api.busy,"Owner invalidation holds a real acceptance callback")
	app._invalidate_relay_identity()
	api.player_id = GUEST
	api.device_token = "replacement-synthetic-token"
	app.identity_data = {"player_id":GUEST,"device_token":api.device_token}
	api.release.emit()
	await _settle()
	_check(not is_instance_valid(app.redo_screen) and app.ui.visible and app.mode == "home" and app.legacy_redo.view().is_empty(),"Late acceptance from the old identity cannot reopen its room or panel")
	# An advisory request may remain uncertain, but B can still take their turn.
	api.room.active_role = "b"
	api.room.revision += 1
	api.room.recordings = {"a":{"final_state_hash":"c".repeat(64)},"b":null}
	api.requested = null
	app.legacy_redo = Client.new(api,app._relay_identity,store)
	app.legacy_redo_restore_scope = ""
	app._accept_room({"ok":true,"data":api.room})
	app._open_legacy_redo()
	await _settle()
	screen = app.redo_screen
	api.drop_next = true
	await _tap(viewport,_button(screen,"Ask for redo"))
	_check(app.legacy_redo.pending().get("action") == "request","B's uncertain advisory request is retained")
	screen.close()
	await _settle()
	_check(_button(app.overlay,"Play your turn") != null,"Advisory redo uncertainty does not block B's ordinary turn")
	# The terminal room response, rather than omission from any list, is the
	# authority that can clear this room's stale pending operation.
	api.room_failure = "connection_interrupted"
	await app._refresh_room()
	_check(not app.legacy_redo.pending().is_empty(),"Transient room failure retains pending recovery")
	api.room_failure = "room_not_found"
	await app._refresh_room()
	_check(app.legacy_redo.pending().is_empty() and app.mode == "rooms","Definitive same-room GET removes a vanished room's recovery dead end")
	viewport.queue_free()
	await _settle()
	await create_timer(0.3).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("LEGACY REDO NAVIGATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _make_app(viewport: SubViewport, path: String, api: MainApi, store: CountingStore) -> Node:
	var app := Main.new()
	app.saves = Save.new(path)
	app.saves.load_data()
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	_check(app.saves.flush(),"Prepare an isolated muted Main save")
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	if api.get_parent() != null: api.get_parent().remove_child(api)
	app.add_child(api)
	app.api = api
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id":api.player_id,"device_token":api.device_token}
	app.legacy_redo = Client.new(api,app._relay_identity,store)
	return app

func _button(node: Node, label: String) -> Button:
	if node is Button and node.text == label: return node
	for child: Node in node.get_children():
		var found := _button(child,label)
		if found != null: return found
	return null

func _tap(viewport: SubViewport, button: Button) -> void:
	_check(button != null,"Expected actual room-control button exists")
	if button == null: return
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		viewport.push_input(event,true)
	await _settle()

func _settle() -> void:
	await process_frame
	await process_frame
