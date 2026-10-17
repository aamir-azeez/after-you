extends SceneTree
const Notifications = preload("res://services/turn_notifications.gd")
const Storage = preload("res://services/local_save.gd")
const Main = preload("res://main.gd")
const LegacyRoomFlow = preload("res://presentation/legacy_room_flow.gd")
const Levels = preload("res://core/levels.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Session = preload("res://services/relay_online_session.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const WrongTypes = preload("res://tests/wrong_types.gd")
const OWNER := "AAAAAAAAAAAAAAAAAAAAAA"
const ROOM := "BBBBBBBBBBBBBBBBBBBBBB"
const EPOCH := "CCCCCCCCCCCCCCCCCCCCCC"

class Native extends Node:
	signal token_changed
	signal received(route: Dictionary)
	var turn_channel := true
	var hosting_channel := true
	var granted := true
	var opted := true
	var generation := 1
	var token := "synthetic-token-00000000000001"
	var bound := ""
	var route: Dictionary = {}
	var calls: Array = []
	func call_native(operation: String, args: Array = []) -> Dictionary:
		calls.append({"operation": operation, "args": args.duplicate(true)})
		match operation:
			"set_categories": return {"ok":true,"data":{"updated":true}}
			"request_permission": opted = true
			"disable":
				opted = false; generation += 1; bound = ""; route = {}
				return {"ok": true, "data": {"disabled": true, "token_deleted": true, "generation": generation}}
			"clear_binding":
				generation += 1; bound = ""; route = {}
				return {"ok": true, "data": {"cleared": true, "generation": generation}}
			"get_token": return {"ok": true, "data": {"token": token, "generation": generation}}
			"pending_route": return {"ok": true, "data": {"route": route.duplicate(true) if route.get("binding_epoch") == bound else {}}}
			"ack_route":
				if route.get("event_id") == args[0]: route = {}
				return {"ok": true, "data": {"acknowledged": true, "event_id": args[0]}}
			"set_binding":
				if args[1] != token or args[2] != generation: return {"ok": false}
				bound = args[0]
				return {"ok": true, "data": {"bound": true, "binding_epoch": bound, "generation": generation}}
		return {"ok": true, "data": {"supported": true, "configured": true, "opted_in": opted, "permission_granted": granted, "channel_enabled": granted and turn_channel, "hosting_channel_enabled": granted and hosting_channel, "registration_pending": bound.is_empty(), "generation": generation}}
	func count(operation: String) -> int:
		return calls.filter(func(item: Dictionary) -> bool: return item.operation == operation).size()

class Api extends Node:
	signal release
	var busy := false
	var player_id := OWNER
	var device_token := "synthetic-device-credential"
	var base_url := "https://notifications.synthetic.invalid"
	var hold := false
	var fail := false
	var room: Dictionary = {}
	var responses: Dictionary = {}
	var calls: Array = []
	var category_status := 200
	## Extra headers per request_json_with_headers call; only the iOS registration uses it.
	var headers: Array = []
	func request_json_with_headers(method: int, path: String, body: Dictionary, extra: PackedStringArray, _still: Callable = Callable()) -> Dictionary:
		headers.append({"path": path, "extra": extra})
		return await request_json(method, path, body)
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		assert(not busy)
		busy = true
		calls.append({"method": method, "path": path, "body": body.duplicate(true)})
		if hold: await release
		busy = false
		if fail: return {"ok": false, "status": 503, "data": {}, "retry_after_ms": 0}
		if path == "/v1/notifications/categories":
			if category_status != 200: return {"ok": false, "status": category_status, "data": {}, "retry_after_ms": 0}
			return {"ok": true, "status": 200, "data": {"schema_version": 1, "binding_epoch": body.binding_epoch, "redo_requests": body.redo_requests}}
		if responses.has(path): return {"ok": true, "status": 200, "data": JSON.parse_string(JSON.stringify(responses[path]))}
		if method == HTTPClient.METHOD_GET: return {"ok": true, "status": 200, "data": {"room": JSON.parse_string(JSON.stringify(room))}}
		return {"ok": true, "status": 200, "data": {"registered": true, "binding_epoch": body.binding_epoch} if method == HTTPClient.METHOD_POST else {"unregistered": true}}

class State extends RefCounted:
	var identity := {"ready": true, "settled": true, "owner": OWNER, "credential_hash": "synthetic-device-credential".sha256_text()}
	var desired := true
	var requests := false
	var request_write_ok := true
	func request_preference() -> bool: return requests
	func save_request_preference(value: bool) -> bool:
		if request_write_ok: requests = value
		return request_write_ok
	var hosting_preferences: Dictionary = {}
	func read_hosting() -> Dictionary: return hosting_preferences.duplicate(true)
	func save_hosting(value: Dictionary) -> bool: hosting_preferences = value.duplicate(true); return true
	var stored: Dictionary = {}
	var write_ok := true
	var writes := 0
	func who() -> Dictionary: return identity.duplicate(true)
	func preference() -> bool: return desired
	func save_preference(value: bool) -> bool: desired = value; return true
	func read_binding() -> Dictionary: return {"ok": true, "value": stored.duplicate(true)}
	func write_binding(value: Dictionary) -> Dictionary:
		writes += 1
		if write_ok: stored = value.duplicate(true)
		return {"ok": write_ok}

class RouteMain extends Main:
	var opened := 0
	var messages := 0
	func _ready() -> void: pass
	func _new_legacy_room_flow() -> LegacyRoomFlow: return RouteRoomFlow.new(self)
	func _enter_online_relay() -> void: opened += 1; mode = "relay_online"
	func _toast(_message: String) -> void: messages += 1
	func _process(_delta: float) -> void: pass

## Counts each time the room page opens, instead of drawing it.
class RouteRoomFlow extends LegacyRoomFlow:
	func show_room() -> void: host.opened += 1; host.mode = "room"

class RoomStub extends Node3D:
	var notes: Array[String] = []
	func notification_deferred(message: String) -> void: notes.append(message)

class MemoryStore extends RefCounted:
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = value.duplicate(true)
		return {"ok": true}

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func _fixture() -> Dictionary:
	var state := State.new()
	var native := Native.new()
	var api := Api.new()
	root.add_child(native); root.add_child(api)
	var service := Notifications.new()
	service.categories_path = _categories_path()
	service.configure(api, native, state.who, state.read_binding, state.write_binding, state.preference, state.save_preference)
	service.configure_hosting(state.read_hosting,state.save_hosting)
	root.add_child(service)
	return {"state": state, "native": native, "api": api, "service": service}

## One saved-categories file per fixture, unless a test reopens the same one.
var categories_dir := "user://turn-notification-categories-" + Crypto.new().generate_random_bytes(6).hex_encode()
var _categories_count := 0
func _categories_path() -> String:
	_categories_count += 1
	DirAccess.make_dir_recursive_absolute(categories_dir)
	return categories_dir.path_join("categories-%d.json" % _categories_count)

func _drop(f: Dictionary) -> void:
	f.service.free(); f.native.free(); f.api.free()

func _route(epoch: String = EPOCH) -> Dictionary:
	return {"schema_version": "1", "event_id": "synthetic_event_00000001", "kind": "turn_ready", "room_id": ROOM, "room_family": "legacy", "revision": "1", "binding_epoch": epoch}

func _bind_value() -> Dictionary:
	return {"schema_version": 1, "owner": OWNER, "credential_hash": "synthetic-device-credential".sha256_text(), "binding_epoch": EPOCH}

func _run() -> void:
	_test_shapes_and_old_settings()
	await _test_hosting_categories()
	await _test_hosting_cold_start()
	await _test_foreground_hosting_hint()
	await _test_reinstall_permission_once()
	await _test_permission_and_storage()
	await _test_registration_and_refresh()
	await _test_late_registration()
	await _test_cold_route_and_identity()
	await _test_actual_main_route()
	await _test_latest_tap()
	await _test_actual_chapter_route(false)
	await _test_actual_chapter_route(true)
	await _test_redo_requests()
	await _test_saved_categories()
	await _test_ios_registration_headers()
	for name: String in DirAccess.get_files_at(categories_dir): DirAccess.remove_absolute(categories_dir.path_join(name))
	DirAccess.remove_absolute(categories_dir)
	print("TURN NOTIFICATIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_shapes_and_old_settings() -> void:
	_check(Storage.defaults().settings.turn_notifications == false, "Old saves default to no notification opt-in")
	var old: Dictionary = Storage.defaults().settings.duplicate(true)
	old.erase("turn_notifications"); old.erase("photo_prompts")
	_check(Storage.default_settings_envelope_valid(old), "The old five-key inert chapter envelope remains valid")
	old.turn_notifications = true
	_check(not Storage.default_settings_envelope_valid(old), "A chapter journal cannot smuggle a nondefault notification preference")
	var event := _route()
	_check(Notifications.valid_route(event), "The exact native string-valued turn hint is accepted")
	for variant: Dictionary in WrongTypes.variants(event):
		_check(not Notifications.valid_route(variant.value), "A hint with a wrongly typed field is refused: " + variant.path)
	var binding := {"schema_version": 1, "owner": OWNER, "credential_hash": "a".repeat(64), "binding_epoch": EPOCH}
	_check(Notifications.valid_binding(binding), "An exact saved binding is accepted")
	for variant: Dictionary in WrongTypes.variants(binding):
		_check(not Notifications.valid_binding(variant.value), "A saved binding with a wrongly typed field is refused: " + variant.path)
	for field: String in event.keys():
		var missing := event.duplicate(true); missing.erase(field)
		_check(not Notifications.valid_route(missing), "Missing hint fields fail closed")
	for update: Dictionary in [{"kind": "reaction"}, {"room_family": "unknown"}, {"revision": "0"}, {"revision": "01"}, {"revision": "9007199254740992"}, {"revision": 1}, {"room_id": "../room"}, {"invite_code": "NEVER_JOIN"}]:
		var invalid := event.duplicate(true); invalid.merge(update, true)
		_check(not Notifications.valid_route(invalid), "Unsupported or malformed notification cannot become a route")

func _test_permission_and_storage() -> void:
	var f := _fixture()
	f.state.desired = false
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(f.api.calls.is_empty() and f.native.count("get_token") == 0, "Default-off never requests a token or registers")
	_check(f.service.set_enabled(true), "Explicit opt-in persists through the preference owner")
	f.native.granted = false
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(f.native.count("request_permission") == 1 and f.api.calls.is_empty(), "Denied permission does not block play or register")
	_check(not f.service.busy(), "Permission denial leaves the coordinator usable")
	f.native.granted = true; f.state.write_ok = false
	f.service.set_enabled(true)
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(f.api.calls.is_empty() and not f.service.registered(), "A failed secure binding write sends no registration")
	_drop(f)

func _test_latest_tap() -> void:
	var f := _fixture()
	f.state.stored = _bind_value(); f.native.bound = EPOCH; f.native.route = _route()
	await f.service.service(Time.get_ticks_msec(), true, true)
	var screen := RouteMain.new()
	screen.api = f.api; screen.turn_notifications = f.service
	screen.identity_read_state = screen.IdentityReadState.LOADED
	screen.saves.path = "user://notification-latest-tap-test.json"
	root.add_child(screen)
	f.api.room = {"room_id": ROOM, "host_id": OWNER, "guest_id": "D".repeat(22), "revision": 1, "level_id": Levels.all_levels()[0].id}
	f.api.hold = true
	screen.notification_flow.service_route()
	var newer := _route()
	newer.room_id = "E".repeat(22); newer.event_id = "synthetic_event_00000002"
	f.native.route = newer
	f.api.hold = false; f.api.release.emit()
	await process_frame
	_check(screen.opened == 0 and screen.saves.data.room.is_empty(), "A newer native tap prevents an older HTTP response from selecting its room")
	_check(f.service.pending_route() == newer, "The newest tap remains queued with its exact family and room")
	f.api.room.room_id = newer.room_id
	screen.notification_flow.service_route()
	await process_frame
	_check(screen.opened == 1 and screen.saves.data.room.room_id == newer.room_id, "The newer tap opens only after its own authenticated read")
	screen.free()
	for suffix: String in ["", ".tmp", ".backup"]:
		var path := "user://notification-latest-tap-test.json" + suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	_drop(f)

func _test_actual_chapter_route(tamper: bool) -> void:
	var f := _fixture()
	var event := _route()
	event.room_family = "relay"; event.revision = "3"
	f.state.stored = _bind_value(); f.native.bound = EPOCH; f.native.route = event
	await f.service.service(Time.get_ticks_msec(), true, true)
	var screen := RouteMain.new()
	screen.api = f.api; screen.turn_notifications = f.service
	screen.identity_read_state = screen.IdentityReadState.LOADED
	root.add_child(screen)
	var level := Registry.definition(Registry.FIRST_STEPS)
	var descriptor := Registry.descriptor(Registry.FIRST_STEPS)
	var checkpoint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_steps/lift-checkpoint.json"))
	if tamper: checkpoint.checkpoint_hash = "0".repeat(64)
	var guest := "DDDDDDDDDDDDDDDDDDDDDD"
	var room := {"api_version": 2, "schema_version": 2, "room_id": ROOM, "revision": 3, "branch": 0, "stage_index": 1, "level_id": level.id, "level_version": level.version, "definition_hash": descriptor.definition_hash, "host_id": OWNER, "guest_id": guest, "checkpoint": checkpoint, "a_turn_id": null, "completed_pair_ids": ["p0-0"], "invite_expires_at": "2026-09-21T12:00:00Z", "created_at": "2026-09-14T12:00:00Z", "updated_at": "2026-09-14T12:00:00Z", "active_role": "a", "first_player_id": guest, "active_player_id": guest, "player_slot": "p0", "stage_id": level.stages[1].id, "recording_a": null, "validation": "structural_client_replay_required"}
	room.invite_code = "A1".repeat(10)
	f.api.room = room
	f.api.responses["/v2/rooms/" + ROOM] = room
	f.api.responses["/v2/capabilities"] = {"api_version": 2, "simulation_version": 2, "recording_version": 2, "mutations_enabled": true, "validation": "structural_client_replay_required", "chapters": [{"level_id": descriptor.level_id, "level_version": descriptor.level_version, "definition_hash": descriptor.definition_hash, "simulation_version": descriptor.simulation_version, "recording_version": descriptor.recording_version, "premium": false}]}
	f.api.responses["/v2/rooms"] = {"rooms": [room]}
	var store := MemoryStore.new()
	screen.relay_session = Session.new(f.api, screen._relay_identity, store)
	var before: int = f.api.calls.size()
	await screen.notification_flow.service_route()
	_check(screen.opened == (0 if tamper else 1), "A First Steps notification opens only after the real coordinator verifies its exact checkpoint")
	_check(f.api.calls.slice(before).all(func(item: Dictionary) -> bool: return item.method == HTTPClient.METHOD_GET), "Chapter notification lookup, capability read and proof verification are GET-only")
	if not tamper:
		_check(screen.relay_session.coordinator.checkpoint().get("checkpoint_hash") == checkpoint.checkpoint_hash, "The displayed chapter keeps the original schema4 proof bytes and hash")
	else:
		_check(not f.service.pending_route().is_empty(), "Failed proof verification keeps the notification retryable without opening a fabricated chapter")
	screen.relay_session.invalidate_identity()
	screen.relay_session = null
	screen.free()
	_drop(f)

func _test_registration_and_refresh() -> void:
	var f := _fixture()
	await f.service.service(Time.get_ticks_msec(), true, false)
	_check(f.api.calls.is_empty(), "Room transport ownership defers registration")
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(f.state.writes == 1 and Notifications.valid_binding(f.state.stored), "A generated credential binding is secured before registration")
	_check(f.api.calls.size() == 1 and f.api.calls[0].body.binding_epoch == f.state.stored.binding_epoch, "Registration uses the exact saved epoch")
	_check(f.native.bound == f.state.stored.binding_epoch and f.service.registered(), "Only matching service and native acknowledgements enable delivery")
	var old_epoch: String = f.state.stored.binding_epoch
	f.service.queue_reconcile()
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(f.api.calls.size() == 1, "A warm status/route check does not rewrite identical registration")
	f.native.token = "synthetic-refreshed-token-000002"; f.native.token_changed.emit()
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(f.api.calls.size() == 2 and f.state.stored.binding_epoch == old_epoch, "Token refresh reconciles under the same credential epoch")
	_check(f.native.calls.back().operation == "pending_route", "Registration completion also checks a retained notification tap")
	var count := [0]
	f.service.foreground_hint.connect(func(_value: Dictionary): count[0] += 1)
	f.native.received.emit(_route(old_epoch))
	f.native.received.emit(_route(EPOCH))
	_check(count[0] == 1 and f.api.calls.size() == 2, "A matching foreground hint is emitted without fetching or mutating gameplay")
	f.native.granted = false
	f.service.queue_reconcile()
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(not f.service.registered() and f.api.calls.size() == 2, "Permission revoked outside the app stops the enabled status without another registration")
	f.native.granted = true
	f.service.queue_reconcile() # The actual main resume notification calls this.
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(f.service.registered() and f.native.count("request_permission") == 0, "Permission restored outside the app is reconciled on resume without another prompt")
	f.native.route = _route(old_epoch)
	f.service.queue_reconcile()
	var before_route: int = f.api.calls.size()
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(not f.service.pending_route().is_empty() and f.api.calls.size() == before_route, "An already registered warm resume still reads the pending native tap")
	_drop(f)

func _test_late_registration() -> void:
	var f := _fixture()
	f.api.hold = true
	f.service.service(Time.get_ticks_msec(), true, true)
	_check(f.api.busy, "The test holds a real coordinator registration await")
	var epoch: String = f.state.stored.binding_epoch
	f.service.set_enabled(false)
	_check(f.native.bound.is_empty() and not f.native.opted, "Opt-out clears native delivery while HTTP is still in flight")
	f.api.hold = false; f.api.release.emit()
	await process_frame
	_check(f.native.count("set_binding") == 0, "A late registration acknowledgement cannot re-enable an opted-out device")
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(f.api.calls.size() == 2 and f.api.calls[1].method == HTTPClient.METHOD_DELETE and f.api.calls[1].body.binding_epoch == epoch, "Opt-out reconciles exact authenticated remote removal after the transport drains")
	_check(f.state.stored.is_empty(), "Confirmed unregistration clears only binding metadata")
	_drop(f)
	var changed := _fixture()
	changed.api.hold = true
	changed.service.service(Time.get_ticks_msec(), true, true)
	var previous: String = changed.state.stored.binding_epoch
	changed.service.invalidate_identity()
	changed.state.identity.credential_hash = "replacement-credential".sha256_text()
	changed.api.hold = false; changed.api.release.emit()
	await process_frame
	_check(changed.native.count("set_binding") == 0, "Recovery invalidates an in-flight old credential acknowledgement")
	await changed.service.service(Time.get_ticks_msec(), true, true)
	_check(changed.state.stored.binding_epoch != previous and changed.native.bound == changed.state.stored.binding_epoch, "The replacement credential gets a new secured epoch")
	_drop(changed)

func _test_cold_route_and_identity() -> void:
	var f := _fixture()
	f.state.stored = _bind_value(); f.native.bound = EPOCH; f.native.route = _route()
	f.state.identity.ready = false; f.state.identity.settled = false
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(f.native.count("clear_binding") == 0 and not f.native.route.is_empty(), "Initial identity loading preserves the unopened native tap")
	_check(f.service.pending_route().is_empty(), "A cold tap is not authorized before identity is read")
	f.state.identity.ready = true; f.state.identity.settled = true
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(f.service.pending_route() == _route(), "An unchanged authenticated binding restores its exact cold-launch route")
	f.service.acknowledge_route(_route().event_id)
	_check(f.service.pending_route().is_empty() and f.native.route.is_empty(), "Acknowledgement removes only the consumed event")
	f.state.identity.credential_hash = "new-device-credential".sha256_text()
	_check(not f.service.accepts(_route()), "The old epoch cannot authorize a recovered identity even before reconciliation")
	_drop(f)

func _test_actual_main_route() -> void:
	var f := _fixture()
	f.state.stored = _bind_value(); f.native.bound = EPOCH; f.native.route = _route()
	await f.service.service(Time.get_ticks_msec(), true, true)
	var screen := RouteMain.new()
	screen.api = f.api; screen.turn_notifications = f.service
	screen.identity_read_state = screen.IdentityReadState.LOADED
	screen.saves.path = "user://notification-routing-test.json"
	root.add_child(screen)
	var level: Dictionary = Levels.all_levels()[0]
	f.api.room = {"room_id": ROOM, "host_id": OWNER, "guest_id": "DDDDDDDDDDDDDDDDDDDDDD", "revision": 1, "level_id": level.id}
	var request_count: int = f.api.calls.size()
	screen.mode = "play"; screen.running = true
	screen.notification_flow.service_route()
	_check(f.api.calls.size() == request_count and screen.opened == 0, "Actual main routing does not interrupt active recording")
	screen.running = false; screen.mode = "home"; screen.saves.data.pending_turn = {"kept": true}
	screen.notification_flow.service_route()
	_check(f.api.calls.size() == request_count, "A pending gameplay request prevents notification navigation")
	screen.saves.data.erase("pending_turn"); screen.saves.data.room_draft = {"kept": true}
	screen.notification_flow.service_route()
	_check(f.api.calls.size() == request_count and screen.saves.data.room_draft == {"kept": true}, "A notification preserves an existing legacy draft")
	screen.saves.data.erase("room_draft")
	f.api.hold = true
	screen.notification_flow.service_route()
	_check(f.api.busy and screen.opened == 0, "Actual main waits for the authenticated room GET before opening")
	screen.relay_identity_epoch += 1
	f.api.hold = false; f.api.release.emit()
	await process_frame
	_check(screen.opened == 0 and screen.saves.data.room.is_empty(), "A response for an invalidated identity context changes no room")
	# A waiting invite link is independent state; tap routing neither waits for nor consumes it.
	screen.invite_link_pending = "Z".repeat(22)
	screen.invite_link_expires_ms = Time.get_ticks_msec() + 60000
	screen.notification_flow.service_route()
	await process_frame
	_check(screen.opened == 1 and screen.saves.data.room.room_id == ROOM, "Only the checked owned room is opened after a fresh GET")
	_check(screen.invite_link_pending == "Z".repeat(22), "Notification routing leaves a pending invite link untouched")
	_check(f.api.calls.slice(request_count).all(func(item: Dictionary) -> bool: return item.method == HTTPClient.METHOD_GET and item.path == "/v1/rooms/" + ROOM), "Notification navigation never probes or submits a join endpoint")
	screen.free()
	for suffix: String in ["", ".tmp", ".backup"]:
		var path := "user://notification-routing-test.json" + suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	_drop(f)

func _test_hosting_categories() -> void:
	var f := _fixture()
	f.state.desired = false
	var peer := "DDDDDDDDDDDDDDDDDDDDDD"
	var request := "EEEEEEEEEEEEEEEEEEEEEE"
	_check(not f.service.hosting_enabled(),"Hosting consent defaults off")
	_check(f.service.set_hosting_friend(peer,true,request),"Explicit selected-friend consent is saved locally")
	_check(not f.service.enabled(),"Hosting consent never enables turn alerts")
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.native.count("request_permission") == 1 and (f.service.registered() or f.service.hosting_registered()),"Hosting opt-in uses common OS permission and registration")
	var event := {"schema_version":"1","event_id":peer+"_1","kind":"friend_room_available","room_id":ROOM,"room_family":"legacy","host_id":peer,"publication_epoch":"1","binding_epoch":f.native.bound}
	_check(Notifications.valid_route(event) and f.service.accepts(event),"Selected friend hosting hint is accepted under current binding")
	for update: Dictionary in [{"host_id":OWNER},{"publication_epoch":"01"},{"revision":"1"},{"schema_version":"2"},{"event_id":peer+"_2"}]:
		var bad := event.duplicate(true); bad.merge(update,true)
		_check(not Notifications.valid_route(bad),"Hosting schema rejects mismatched host/epoch or extra fields")
	_check(not f.service.accepts(_route(f.native.bound)),"Turn hints remain off while hosting transport is on")
	var disables: int = f.native.count("disable")
	f.service.set_enabled(false)
	_check(f.native.calls[-1].operation == "set_categories" and f.native.calls[-1].args == [false,true,false],"Turn opt-out immediately updates native categories before idle reconciliation")
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.native.count("disable") == disables and (f.service.registered() or f.service.hosting_registered()),"Turning off turns preserves hosting transport")
	f.service.set_enabled(true)
	await f.service.service(Time.get_ticks_msec(),true,true)
	f.service.set_hosting_friend(peer,false)
	_check(f.native.calls[-1].operation == "set_categories" and f.native.calls[-1].args == [true,false,false],"Hosting opt-out immediately updates native categories before idle reconciliation")
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.native.count("disable") == disables and (f.service.registered() or f.service.hosting_registered()),"Turning off hosting preserves turn transport")
	f.service.set_hosting_friend(peer,true,request)
	f.native.turn_channel = false
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(not f.service.registered() and f.service.hosting_registered(),"Blocked turn channel cannot appear ready because hosting transport is registered")
	f.service.set_enabled(false)
	f.native.granted = false
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.service.hosting_enabled() and not (f.service.registered() or f.service.hosting_registered()),"Permission denial preserves in-app subscription without promising phone delivery")
	f.state.identity.owner = ROOM
	_check(not f.service.hosting_enabled(),"Another identity cannot inherit hosting consent")
	_drop(f)

## Hosting alerts alone (turn notifications off) survive a cold start, and an
## opt-in an older build cleared is restored without asking again.
func _test_hosting_cold_start() -> void:
	var f := _fixture()
	f.state.desired = false
	var peer := "DDDDDDDDDDDDDDDDDDDDDD"
	_check(f.service.set_hosting_friend(peer,true,"EEEEEEEEEEEEEEEEEEEEEE",false),"A saved hosting alert from an earlier session")
	var loaded: Dictionary = f.state.identity.duplicate(true)
	f.state.identity = {"ready": false, "settled": false, "owner": "", "credential_hash": ""}
	for _i in 3: await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.native.count("disable") == 0 and f.native.opted,"A cold start does not switch phone notifications off while the identity is still loading")
	f.state.identity = loaded
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.native.count("disable") == 0 and f.service.hosting_registered(),"Once the identity loads, hosting alerts alone keep the phone registered")
	_drop(f)
	var g := _fixture()
	g.state.desired = false
	g.service.set_hosting_friend(peer,true,"EEEEEEEEEEEEEEEEEEEEEE",false)
	g.native.opted = false
	await g.service.service(Time.get_ticks_msec(),true,true)
	_check(g.native.count("request_permission") == 1 and g.native.opted and g.service.hosting_registered(),"A saved hosting alert whose phone opt-in was cleared is restored when permission is still granted")
	_drop(g)
	var h := _fixture()
	h.state.desired = false
	h.service.set_hosting_friend(peer,true,"EEEEEEEEEEEEEEEEEEEEEE",false)
	h.native.opted = false
	h.native.granted = false
	await h.service.service(Time.get_ticks_msec(),true,true)
	_check(h.native.count("request_permission") == 0 and not h.service.hosting_registered(),"Without Android permission the restore never prompts on its own")
	_drop(h)
	var off := _fixture()
	off.state.desired = false
	off.state.identity = {"ready": false, "settled": true, "owner": "", "credential_hash": ""}
	await off.service.service(Time.get_ticks_msec(),true,true)
	_check(off.native.count("disable") == 1,"A settled missing identity with nothing enabled still clears the phone once")
	_drop(off)

## With the app open Android posts no banner, so Main shows the hosting alert.
func _test_foreground_hosting_hint() -> void:
	var f := _fixture()
	f.state.desired = false
	var peer := "DDDDDDDDDDDDDDDDDDDDDD"
	f.service.set_hosting_friend(peer,true,"EEEEEEEEEEEEEEEEEEEEEE")
	await f.service.service(Time.get_ticks_msec(),true,true)
	var screen := RouteMain.new()
	screen.api = f.api; screen.turn_notifications = f.service
	screen.identity_read_state = screen.IdentityReadState.LOADED
	screen.saves.path = "user://notification-hint-test.json"
	root.add_child(screen)
	var event := {"schema_version":"1","event_id":peer+"_1","kind":"friend_room_available","room_id":ROOM,"room_family":"relay","host_id":peer,"publication_epoch":"1","binding_epoch":f.native.bound}
	var requests: int = f.api.calls.size()
	screen.notification_flow.foreground_hint(event)
	_check(screen.messages == 1 and screen.opened == 0 and f.api.calls.size() == requests,"A hosting alert received while the app is open shows a message and opens nothing")
	var other := event.duplicate(true); other.host_id = OWNER; other.event_id = OWNER+"_1"
	screen.notification_flow.foreground_hint(other)
	_check(screen.messages == 1,"A hosting hint for a friend without alerts shows nothing")
	# In a room the main UI (and its toast) is hidden, so the room card shows it.
	var room := RoomStub.new()
	screen.add_child(room)
	screen.relay_child = room
	screen.notification_flow.foreground_hint(event)
	_check(screen.messages == 1 and room.notes.size() == 1 and room.notes[0].ends_with("has a room ready"),"A hosting alert during a room shows on the room card, not the hidden toast")
	screen.relay_child = null
	room.free()
	screen.free()
	for suffix: String in ["", ".tmp", ".backup"]:
		var path := "user://notification-hint-test.json" + suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	_drop(f)

## A reinstall brings hosting alerts back from the server without Android
## permission: ask once, through the usual flow, and never again.
func _test_reinstall_permission_once() -> void:
	var f := _fixture()
	f.state.desired = false
	f.service.permission_asked_path = categories_dir.path_join("permission-asked.cfg")
	f.native.granted = false
	f.native.opted = false
	var server := [{"player_id":"DDDDDDDDDDDDDDDDDDDDDD","request_id":"EEEEEEEEEEEEEEEEEEEEEE","enabled":true}]
	f.service.sync_hosting_preferences(server)
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.native.count("request_permission") == 1,"Hosting alerts restored after a reinstall ask for phone permission once")
	f.service.sync_hosting_preferences(server)
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.native.count("request_permission") == 1,"Opening Friends again does not ask again")
	f.service.set_hosting_friend("DDDDDDDDDDDDDDDDDDDDDD",false,"",false)
	f.service.sync_hosting_preferences(server)
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.native.count("request_permission") == 1,"The same identity is never asked twice, even after another restore")
	_drop(f)
	var g := _fixture()
	g.state.desired = false
	g.service.permission_asked_path = categories_dir.path_join("permission-asked-2.cfg")
	g.service.set_hosting_friend("DDDDDDDDDDDDDDDDDDDDDD",true,"EEEEEEEEEEEEEEEEEEEEEE",false)
	g.service.sync_hosting_preferences(server)
	await g.service.service(Time.get_ticks_msec(),true,true)
	_check(g.native.count("request_permission") == 0,"An alert this phone already had never triggers the ask")
	_drop(g)

func _redo_route(epoch: String = EPOCH) -> Dictionary:
	var route := _route(epoch)
	route.kind = "redo_requested"
	route.event_id = "redo_" + "a1".repeat(32)
	return route

func _category_calls(f: Dictionary) -> Array:
	return f.api.calls.filter(func(item: Dictionary) -> bool: return item.path == Notifications.CATEGORIES_PATH)

func _requests_fixture(requests: bool) -> Dictionary:
	var f := _fixture()
	f.state.requests = requests
	f.service.configure_requests(f.state.request_preference, f.state.save_request_preference)
	f.state.stored = _bind_value()
	return f

func _test_redo_requests() -> void:
	_check(Storage.defaults().settings.turn_request_notifications == false, "Redo request alerts default off")
	_check(Storage.default_settings_envelope_valid({"turn_request_notifications": false}) and not Storage.default_settings_envelope_valid({"turn_request_notifications": true}), "A chapter journal cannot carry a redo request opt-in")
	var redo := _redo_route()
	_check(Notifications.valid_route(redo), "A redo request uses the exact turn hint shape")
	for update: Dictionary in [{"event_id": "synthetic_event_00000001"}, {"event_id": "redo_" + "A1".repeat(32)}, {"event_id": "redo_" + "a1".repeat(31)}, {"publication_epoch": "1"}, {"host_id": OWNER}]:
		var invalid := redo.duplicate(true); invalid.merge(update, true)
		_check(not Notifications.valid_route(invalid), "A redo request needs its own event id and no hosting fields")
	var f := _requests_fixture(false)
	await f.service.service(Time.get_ticks_msec(), true, true)
	var registered_text: String = f.service.status_text
	_check(f.service.registered() and f.api.calls[0].path == Notifications.REGISTRATION_PATH, "Turn registration comes first and is unchanged")
	_check(f.api.calls[0].body.keys().size() == 3, "The registration body keeps its three keys")
	var sent := _category_calls(f)
	_check(sent.size() == 1 and sent[0].body == {"schema_version": 1, "binding_epoch": EPOCH, "redo_requests": false}, "The redo option is confirmed once per binding, off by default")
	_check(not f.service.accepts(_redo_route()) and f.service.accepts(_route()), "Redo request hints stay off until the option is on")
	var before: int = f.api.calls.size()
	var permissions: int = f.native.count("request_permission")
	_check(f.service.set_requests_enabled(true) and f.state.requests, "The option is saved through its owner")
	_check(f.native.calls[-1].operation == "set_categories" and f.native.calls[-1].args == [true, false, true], "Turning it on updates native categories right away")
	_check(f.service.accepts(_redo_route()) and not f.service.accepts(_redo_route("D".repeat(22))), "A redo request hint needs the option and the current binding")
	await f.service.service(Time.get_ticks_msec(), true, true)
	var after: Array = f.api.calls.slice(before)
	_check(after.size() == 1 and after[0].path == Notifications.CATEGORIES_PATH and after[0].body.redo_requests == true, "Turning it on sends only the category change, with no new registration")
	_check(f.native.count("request_permission") == permissions and f.service.status_text == registered_text, "The option asks for no permission and leaves the turn status alone")
	await f.service.service(Time.get_ticks_msec(), true, true)
	_check(f.api.calls.size() == before + 1, "A confirmed option is not sent again")
	f.service.set_enabled(false)
	_check(not f.service.accepts(_redo_route()) and f.native.calls.any(func(item: Dictionary) -> bool: return item.operation == "set_categories" and item.args == [false, false, false]), "Turning notifications off also stops redo request alerts on the device")
	f.state.request_write_ok = false
	_check(not f.service.set_requests_enabled(false) and f.state.requests, "A failed save keeps the stored option")
	_drop(f)
	var failing := _requests_fixture(true)
	failing.api.category_status = 503
	await failing.service.service(Time.get_ticks_msec(), true, true)
	_check(failing.service.registered() and failing.service.status_text == Notifications.PlayerCopy.TURN_NOTIFICATIONS_D05B75D3C933, "A failed category request leaves turn notifications registered and their status unchanged")
	var tried: int = _category_calls(failing).size()
	await failing.service.service(Time.get_ticks_msec(), true, true)
	_check(tried == 1 and _category_calls(failing).size() == 1, "A failed category request waits before trying again")
	_drop(failing)
	var old_server := _requests_fixture(false)
	old_server.api.category_status = 404
	await old_server.service.service(Time.get_ticks_msec(), true, true)
	await old_server.service.service(Time.get_ticks_msec() + 600000, true, true)
	_check(_category_calls(old_server).size() == 1 and old_server.service.registered(), "A server without the category route is asked once when the option is off")
	_drop(old_server)

## A confirmed opt-out is kept across launches, so a launch with the option
## off asks nothing; an opt-in is still confirmed once a session. An opt-in a
## server cannot route (404) is asked once per registration, not every 5 min.
func _test_saved_categories() -> void:
	var first := _requests_fixture(false)
	await first.service.service(Time.get_ticks_msec(), true, true)
	var path: String = first.service.categories_path
	_check(_category_calls(first).size() == 1 and FileAccess.file_exists(path) and not FileAccess.get_file_as_string(path).contains(EPOCH), "The first launch confirms the opt-out and keeps only a digest of the binding")
	_drop(first)
	var again := _requests_fixture(false)
	again.service.categories_path = path
	await again.service.service(Time.get_ticks_msec(), true, true)
	_check(again.service.registered() and _category_calls(again).is_empty() and not again.service.accepts(_redo_route()), "A later launch with the option off sends no category request")
	_check(again.service.set_requests_enabled(true), "The option turns on")
	await again.service.service(Time.get_ticks_msec(), true, true)
	_check(_category_calls(again).size() == 1 and _category_calls(again)[0].body.redo_requests == true, "Turning it on is sent")
	_drop(again)
	var opted := _requests_fixture(true)
	opted.service.categories_path = path
	await opted.service.service(Time.get_ticks_msec(), true, true)
	_check(_category_calls(opted).size() == 1 and _category_calls(opted)[0].body.redo_requests == true, "An opt-in is confirmed again once a session")
	_drop(opted)
	var other := _requests_fixture(false)
	other.service.categories_path = path
	other.state.stored = _bind_value()
	other.state.stored.binding_epoch = "D".repeat(22)
	await other.service.service(Time.get_ticks_msec(), true, true)
	_check(_category_calls(other).size() == 1 and _category_calls(other)[0].body.binding_epoch == "D".repeat(22), "A kept opt-out belongs to its binding: a new binding is confirmed")
	_drop(other)
	var old_server := _requests_fixture(true)
	old_server.api.category_status = 404
	await old_server.service.service(Time.get_ticks_msec(), true, true)
	for later: int in [300000, 600000, 3600000]:
		await old_server.service.service(Time.get_ticks_msec() + later, true, true)
	_check(_category_calls(old_server).size() == 1 and old_server.service.registered() and old_server.service.status_text == Notifications.PlayerCopy.TURN_NOTIFICATIONS_D05B75D3C933, "A server without the route is asked about an opt-in once, and turn status stays")
	_check(old_server.service.set_requests_enabled(false) and old_server.service.set_requests_enabled(true), "The option is turned off and on again")
	await old_server.service.service(Time.get_ticks_msec() + 3600000, true, true)
	_check(_category_calls(old_server).size() >= 2 and _category_calls(old_server)[-1].body.redo_requests == true, "Changing the option asks again")
	var asked: int = _category_calls(old_server).size()
	old_server.native.generation += 1
	old_server.native.token_changed.emit()
	await old_server.service.service(Time.get_ticks_msec() + 7200000, true, true)
	_check(_category_calls(old_server).size() == asked + 1, "A new registration asks again")
	_drop(old_server)

## iOS shows a push without running app code, so its registration tells the server which
## kinds are on. Android and desktop register exactly as before, with no extra headers.
func _test_ios_registration_headers() -> void:
	_check(Notifications.push_categories(true,true) == "turns,hosting" and Notifications.push_categories(true,false) == "turns" and Notifications.push_categories(false,true) == "hosting" and Notifications.push_categories(false,false) == "none","Push categories use the server's fixed spelling")
	_check(Notifications.ios_registration_headers(false,true) == PackedStringArray(["X-AfterYou-Platform: ios","X-AfterYou-Push-Categories: hosting"]),"The iOS registration headers name the platform and its categories")
	for platform: String in [PlatformSupport.ANDROID, PlatformSupport.DESKTOP]:
		PlatformSupport.override_platform = platform
		var a := _fixture()
		await a.service.service(Time.get_ticks_msec(),true,true)
		_check(a.api.calls.size() == 1 and a.api.calls[0].path == Notifications.REGISTRATION_PATH and a.api.headers.is_empty(),"%s registers through the unchanged request with no platform headers" % platform)
		_drop(a)
	PlatformSupport.override_platform = PlatformSupport.IOS
	var f := _fixture()
	var peer := "DDDDDDDDDDDDDDDDDDDDDD"
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.api.calls.size() == 1 and f.api.headers.size() == 1 and f.api.headers[0].path == Notifications.REGISTRATION_PATH and f.api.headers[0].extra == Notifications.ios_registration_headers(true,false),"An iOS registration with turns on says so")
	_check(f.api.calls[0].body.keys().size() == 3 and f.api.calls[0].body.has("token") and f.api.calls[0].body.schema_version == 1,"The registration body keeps the exact shape older servers enforce")
	_check(f.service.set_hosting_friend(peer,true,"EEEEEEEEEEEEEEEEEEEEEE"),"Hosting consent is saved")
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.api.headers.size() == 2 and f.api.headers[1].extra == Notifications.ios_registration_headers(true,true),"Turning hosting on re-registers with both categories")
	f.service.set_enabled(false)
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.api.headers.size() == 3 and f.api.headers[2].extra == Notifications.ios_registration_headers(false,true),"Turning turns off re-registers with hosting only, so the server stops turn alerts")
	f.service.queue_reconcile()
	await f.service.service(Time.get_ticks_msec(),true,true)
	_check(f.api.headers.size() == 3 and f.api.calls.filter(func(item: Dictionary) -> bool: return item.path == Notifications.REGISTRATION_PATH).size() == 3,"An unchanged iOS registration is not sent again, and each one sent carried the headers")
	_drop(f)
	PlatformSupport.override_platform = ""
