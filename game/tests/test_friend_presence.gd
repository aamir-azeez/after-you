extends SceneTree
const Presence = preload("res://services/friend_presence.gd")
const OWNER := "AAAAAAAAAAAAAAAAAAAAAA"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const OTHER := "SSSSSSSSSSSSSSSSSSSSSS"
var checks := 0
var failures := 0

class Clock:
	extends RefCounted
	var now := 1000
	func read() -> int: return now

class Api:
	extends Node
	signal release
	var base_url := ""
	var player_id := ""
	var device_token := ""
	var busy := false
	var held := false
	var calls: Array[Dictionary] = []
	var response: Dictionary = {}
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		busy = true
		calls.append({"method": method, "path": path, "body": body.duplicate(true), "owner": player_id, "token": device_token})
		var captured := response.duplicate(true)
		if held: await release
		busy = false
		if not captured.is_empty(): return captured
		return {"ok": true, "data": {"schema_version": 1, "heartbeat_seconds": 30, "expires_after_seconds": 90}} if method == HTTPClient.METHOD_POST else {"ok": true, "data": {"schema_version": 1, "partner_joined": true, "partner_online": true, "expires_after_seconds": 90}}

func _initialize() -> void: _run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _identity(epoch: int = 1, player: String = OWNER) -> Dictionary:
	return {"ready": true, "player_id": player, "device_token": "synthetic-device-credential", "base_url": "https://presence.invalid", "epoch": epoch}

func _case() -> Dictionary:
	var service := Presence.new()
	var api := Api.new()
	var clock := Clock.new()
	service.api = api
	service.clock_ms = clock.read
	root.add_child(service)
	service.set_process(false)
	service.set_identity(_identity())
	service.monitor_room("v2", ROOM)
	return {"service": service, "api": api, "clock": clock}

func _run() -> void:
	await _timing()
	await _stale_contexts()
	await _failures_and_optout()
	await _reenable()
	_validate()
	print("FRIEND PRESENCE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _timing() -> void:
	var c := _case()
	var service: Node = c.service
	var api: Api = c.api
	var clock: Clock = c.clock
	await service.service()
	_check(api.calls.size() == 1 and api.calls[0].path == "/v1/presence" and api.calls[0].body.online, "A ready foreground identity publishes one heartbeat")
	var session: String = api.calls[0].body.session_id
	_check(service.view("v2", ROOM).state == "checking", "An own heartbeat never claims the friend is online")
	service.set_identity(_identity())
	await service.service()
	_check(service._session_id == session and api.calls.size() == 2 and api.calls.back().method == HTTPClient.METHOD_GET, "Repeated matching identity synchronization retains one lease and does not restart publishing")
	_check(session.length() == 36 and session.is_valid_hex_number() and session == session.to_lower(), "Session identifier is exactly 18 random bytes as lowercase hex")
	_check(api.calls[0].body.size() == 3 and api.calls[0].owner == OWNER and api.player_id.is_empty() and api.device_token.is_empty(), "Only protocol fields are sent with the matching credential; transport clears idle credentials")
	_check(api.calls.size() == 2 and api.calls[1].method == HTTPClient.METHOD_GET and api.calls[1].path.ends_with("/presence"), "Room presence uses its own read, with no gameplay request")
	_check(service.view("v2", ROOM).state == "online", "Only a valid room reply establishes online status")
	clock.now += 29999
	await service.service()
	_check(api.calls.size() == 2, "No repeated heartbeat or read before thirty seconds")
	clock.now += 1
	await service.service()
	await service.service()
	_check(api.calls.size() == 4 and api.calls[2].body.session_id == session, "Thirty-second refresh reuses the foreground lease and reads once")
	service._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(api.calls.size() == 5 and not api.calls[4].body.online and api.calls[4].body.session_id == session, "Backgrounding sends best-effort offline for precisely the old lease")
	clock.now += 120000
	await service.service()
	service._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(api.calls.size() == 5 and service.view("v2", ROOM).state == "checking", "Background suspends publishing and reads; duplicate focus-out does not repeat offline")
	service._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	service._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await service.service()
	_check(api.calls.size() == 6 and api.calls[5].body.online and api.calls[5].body.session_id != session, "Resume coalesces paired events and uses a new session")
	await service.service()
	service.set_enabled(false)
	await service.service()
	_check(api.calls.size() == 8 and not api.calls[7].body.online, "Opt-out retires the exact current lease")
	clock.now += 30000
	await service.service()
	_check(api.calls.size() == 9 and api.calls[8].method == HTTPClient.METHOD_GET, "Opt-out can still read a sharing partner without publishing")
	service.queue_free()
	await process_frame

func _stale_contexts() -> void:
	var c := _case()
	var service: Node = c.service
	var api: Api = c.api
	var clock: Clock = c.clock
	service.set_enabled(false)
	api.held = true
	service.service()
	_check(api.busy, "Delayed GET is genuinely in flight")
	service.monitor_room("v1", OTHER)
	await service.service()
	_check(api.calls.size() == 1 and service.view("v1", OTHER).state == "checking", "Changing rooms clears the badge without overlapping HTTP")
	api.release.emit()
	await process_frame
	_check(service.view("v1", OTHER).state == "checking", "Late reply for the departed room is ignored")
	api.held = false
	await service.service()
	_check(api.calls.back().path == "/v1/rooms/" + OTHER + "/presence" and service.view("v1", OTHER).state == "online", "The new room gets its own authenticated result")
	clock.now += 30000
	api.held = true
	service.service()
	clock.now += 20000
	api.release.emit()
	await process_frame
	_check(service._fresh_until == clock.now + 70000, "Response transit time is subtracted from server TTL, never added")
	clock.now += 70000
	_check(service.view("v1", OTHER).state == "checking", "Expired lease cannot continue to claim online before another response")
	service.service()
	service.set_identity(_identity(2, "B".repeat(22)))
	api.release.emit()
	await process_frame
	_check(service.view("v1", OTHER).state == "checking", "A recovered identity rejects an in-flight old-owner result")
	api.held = false
	await service.service()
	_check(api.calls.back().owner == "B".repeat(22), "The replacement identity owns the next lookup")
	service.set_identity({"ready": false})
	var before := api.calls.size()
	await service.service()
	_check(api.calls.size() == before and service.view("v1", OTHER).state == "checking", "Missing or unreadable identity cannot read or publish")
	service.queue_free()
	await process_frame

func _failures_and_optout() -> void:
	var c := _case()
	var service: Node = c.service
	var api: Api = c.api
	var clock: Clock = c.clock
	await service.service()
	api.held = true
	service.service()
	service.set_enabled(false)
	api.release.emit()
	await process_frame
	_check(service.view("v2", ROOM).state == "checking", "Opt-out invalidates a delayed status result")
	api.held = false
	api.response = {"ok": false, "status": 503, "retry_after_ms": 90000}
	await service.service() # Best-effort offline failure is not retried in a loop.
	var before := api.calls.size()
	await service.service()
	_check(api.calls.size() == before, "Failed offline cleanup does not cause a repeat storm")
	clock.now += 30000
	await service.service()
	_check(service.view("v2", ROOM).state == "unknown", "Unavailable service is unknown, never a false offline claim")
	before = api.calls.size()
	clock.now += 89999
	await service.service()
	_check(api.calls.size() == before, "Room reads respect Retry-After")
	clock.now += 1
	api.response = {"ok": true, "data": {"schema_version": 1, "partner_joined": true, "partner_online": false, "expires_after_seconds": 0}}
	await service.service()
	_check(service.view("v2", ROOM).text == "Friend offline", "A successful negative read may say offline")
	clock.now += 30000
	api.response.data.partner_joined = false
	await service.service()
	_check(service.view("v2", ROOM).text == "Waiting for friend", "A room without a partner shows waiting")
	clock.now += 30000
	api.response.data.partner_online = true
	await service.service()
	_check(service.view("v2", ROOM).state == "unknown", "Malformed contradictory status cannot render online")
	service.queue_free()
	await process_frame

func _reenable() -> void:
	var c := _case()
	var service: Node = c.service
	var api: Api = c.api
	await service.service()
	var old_session: String = api.calls.back().body.session_id
	service.set_enabled(false)
	api.held = true
	service.service()
	_check(api.busy and not api.calls.back().body.online, "Opt-out request is genuinely pending")
	service.set_enabled(true)
	await service.service()
	_check(api.calls.size() == 2 and service._session_id != old_session, "Re-enable rotates session without overlapping old offline request")
	api.release.emit()
	await process_frame
	api.held = false
	await service.service()
	_check(api.calls.size() == 3 and api.calls.back().body.online and api.calls.back().body.session_id != old_session, "A delayed old offline request cannot target the newly enabled lease")
	service.queue_free()
	await process_frame

func _validate() -> void:
	for value: Variant in [{}, null, {"schema_version": 1, "partner_joined": true, "partner_online": true, "expires_after_seconds": 91}, {"schema_version": 1, "partner_joined": true, "partner_online": true, "expires_after_seconds": 0}, {"schema_version": true, "partner_joined": true, "partner_online": false, "expires_after_seconds": 0}, {"schema_version": 1, "partner_joined": true, "partner_online": false, "expires_after_seconds": 1}, {"schema_version": 1, "partner_joined": true, "partner_online": true, "expires_after_seconds": 0.5}]:
		_check(not Presence.valid_room_response(value), "Invalid schema, type and lease combinations fail closed")
