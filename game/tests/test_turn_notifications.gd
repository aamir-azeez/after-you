extends SceneTree
const Notifications = preload("res://services/turn_notifications.gd")
const Storage = preload("res://services/local_save.gd")
const Main = preload("res://main.gd")
const Levels = preload("res://core/levels.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Session = preload("res://services/relay_online_session.gd")
const OWNER := "AAAAAAAAAAAAAAAAAAAAAA"
const ROOM := "BBBBBBBBBBBBBBBBBBBBBB"
const EPOCH := "CCCCCCCCCCCCCCCCCCCCCC"

class Native extends Node:
	signal token_changed
	signal received(route: Dictionary)
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
		return {"ok": true, "data": {"supported": true, "configured": true, "opted_in": opted, "permission_granted": granted, "channel_enabled": granted, "registration_pending": bound.is_empty(), "generation": generation}}
	func count(operation: String) -> int:
		return calls.filter(func(item: Dictionary) -> bool: return item.operation == operation).size()

class Api extends Node:
	signal release
	var busy := false
	var player_id := OWNER
	var device_token := "synthetic-device-credential"
	var hold := false
	var fail := false
	var room: Dictionary = {}
	var responses: Dictionary = {}
	var calls: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		assert(not busy)
		busy = true
		calls.append({"method": method, "path": path, "body": body.duplicate(true)})
		if hold: await release
		busy = false
		if fail: return {"ok": false, "status": 503, "data": {}, "retry_after_ms": 0}
		if responses.has(path): return {"ok": true, "status": 200, "data": JSON.parse_string(JSON.stringify(responses[path]))}
		if method == HTTPClient.METHOD_GET: return {"ok": true, "status": 200, "data": {"room": JSON.parse_string(JSON.stringify(room))}}
		return {"ok": true, "status": 200, "data": {"registered": true, "binding_epoch": body.binding_epoch} if method == HTTPClient.METHOD_POST else {"unregistered": true}}

class State extends RefCounted:
	var identity := {"ready": true, "settled": true, "owner": OWNER, "credential_hash": "synthetic-device-credential".sha256_text()}
	var desired := true
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
	func _show_room_detail() -> void: opened += 1; mode = "room"
	func _enter_online_relay() -> void: opened += 1; mode = "relay_online"
	func _toast(_message: String) -> void: messages += 1
	func _process(_delta: float) -> void: pass

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
	service.configure(api, native, state.who, state.read_binding, state.write_binding, state.preference, state.save_preference)
	root.add_child(service)
	return {"state": state, "native": native, "api": api, "service": service}

func _drop(f: Dictionary) -> void:
	f.service.free(); f.native.free(); f.api.free()

func _route(epoch: String = EPOCH) -> Dictionary:
	return {"schema_version": "1", "event_id": "synthetic_event_00000001", "kind": "turn_ready", "room_id": ROOM, "room_family": "legacy", "revision": "1", "binding_epoch": epoch}

func _bind_value() -> Dictionary:
	return {"schema_version": 1, "owner": OWNER, "credential_hash": "synthetic-device-credential".sha256_text(), "binding_epoch": EPOCH}

func _run() -> void:
	_test_shapes_and_old_settings()
	await _test_permission_and_storage()
	await _test_registration_and_refresh()
	await _test_late_registration()
	await _test_cold_route_and_identity()
	await _test_actual_main_route()
	await _test_latest_tap()
	await _test_actual_chapter_route(false)
	await _test_actual_chapter_route(true)
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
	screen._service_notification_route()
	var newer := _route()
	newer.room_id = "E".repeat(22); newer.event_id = "synthetic_event_00000002"
	f.native.route = newer
	f.api.hold = false; f.api.release.emit()
	await process_frame
	_check(screen.opened == 0 and screen.saves.data.room.is_empty(), "A newer native tap prevents an older HTTP response from selecting its room")
	_check(f.service.pending_route() == newer, "The newest tap remains queued with its exact family and room")
	f.api.room.room_id = newer.room_id
	screen._service_notification_route()
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
	await screen._service_notification_route()
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
	screen._service_notification_route()
	_check(f.api.calls.size() == request_count and screen.opened == 0, "Actual main routing does not interrupt active recording")
	screen.running = false; screen.mode = "home"; screen.saves.data.pending_turn = {"kept": true}
	screen._service_notification_route()
	_check(f.api.calls.size() == request_count, "A pending gameplay request prevents notification navigation")
	screen.saves.data.erase("pending_turn"); screen.saves.data.room_draft = {"kept": true}
	screen._service_notification_route()
	_check(f.api.calls.size() == request_count and screen.saves.data.room_draft == {"kept": true}, "A notification preserves an existing legacy draft")
	screen.saves.data.erase("room_draft")
	f.api.hold = true
	screen._service_notification_route()
	_check(f.api.busy and screen.opened == 0, "Actual main waits for the authenticated room GET before opening")
	screen.relay_identity_epoch += 1
	f.api.hold = false; f.api.release.emit()
	await process_frame
	_check(screen.opened == 0 and screen.saves.data.room.is_empty(), "A response for an invalidated identity context changes no room")
	screen._service_notification_route()
	await process_frame
	_check(screen.opened == 1 and screen.saves.data.room.room_id == ROOM, "Only the checked owned room is opened after a fresh GET")
	_check(f.api.calls.slice(request_count).all(func(item: Dictionary) -> bool: return item.method == HTTPClient.METHOD_GET and item.path == "/v1/rooms/" + ROOM), "Notification navigation never probes or submits a join endpoint")
	screen.free()
	for suffix: String in ["", ".tmp", ".backup"]:
		var path := "user://notification-routing-test.json" + suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	_drop(f)
