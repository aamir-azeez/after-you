extends SceneTree
## Room level 2: the client asks for chapters with more than two stages with
## one request header, accepts the longer capability list only in that answer,
## and sends the longer join list only to a server that allows it. An old
## server (no room level) keeps getting today's join list of at most 8 rules.
const Registry = preload("res://services/chapter_registry.gd")
const Session = preload("res://services/relay_online_session.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
## One room's widest Lighthouse receiver turn body is about 388 KB.
const LONG_BODY_BYTES := 400000
var checks := 0
var failures := 0
var _fired: Dictionary = {}

class FakeApi extends Node:
	var player_id := HOST
	var device_token := "synthetic-device-token"
	var busy := false
	var capabilities: Dictionary = {}
	var calls: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		calls.append({"method": method, "path": path, "body": body.duplicate(true)})
		if path == "/v2/capabilities": return {"ok": true, "status": 200, "data": JSON.parse_string(JSON.stringify(capabilities))}
		if path == "/v2/rooms": return {"ok": true, "status": 200, "data": {"rooms": []}}
		return {"ok": false, "status": 0, "code": "connection_interrupted", "error": "offline"}

class MemoryStore extends RefCounted:
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok": true}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_capabilities()
	await _join_lists()
	await _wire()
	print("LIGHTHOUSE V2 JOIN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _chapter(key: String, with_stages: bool) -> Dictionary:
	var d := Registry.descriptor(key)
	var item := {"level_id": d.level_id, "level_version": d.level_version, "definition_hash": d.definition_hash, "premium": d.premium,
		"recording_version": d.recording_version, "simulation_version": d.simulation_version}
	if with_stages: item["stage_count"] = d.stage_count
	return item

## A capability answer. Level 1 lists only two-stage chapters, as the server does.
func _caps(level: int, extra_unknown: int = 0) -> Dictionary:
	var chapters: Array = []
	for key: String in Registry.keys():
		if key == Registry.FIRST_STEPS: continue
		if level < 2 and Registry.descriptor(key).stage_count != 2: continue
		chapters.append(_chapter(key, level >= 2))
	for index in range(extra_unknown):
		chapters.append({"level_id": "future-chapter-%d" % index, "level_version": 1, "definition_hash": "f".repeat(64), "premium": false, "recording_version": 8, "simulation_version": 12})
	var value := {"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true, "validation": "structural_client_replay_required", "chapters": chapters}
	if level >= 2:
		value["room_level"] = 2
		value["max_join_versions"] = 16
		value["max_stages"] = 8
	return value

func _keys(checked: Dictionary) -> Array:
	return checked.chapters.map(func(item: Dictionary) -> String: return str(item.key))

func _capabilities() -> void:
	var old := Registry.supported_capabilities(_caps(1))
	_check(old.valid and Registry.LIGHTHOUSE_V2 not in _keys(old), "A level-1 answer is valid and has no Lighthouse")
	var level_two := Registry.supported_capabilities(_caps(2))
	_check(level_two.valid and Registry.LIGHTHOUSE_V2 in _keys(level_two), "A level-2 answer offers the six-stage Lighthouse")
	_check(not Registry.supported_capabilities(_caps(1, 8)).valid, "A level-1 answer keeps its 16-chapter cap")
	_check(Registry.supported_capabilities(_caps(2, 40)).valid, "A level-2 answer may list up to 64 chapters")
	_check(not Registry.supported_capabilities(_caps(2, 60)).valid, "...but not more")
	var wrong_count := _caps(2)
	for item: Dictionary in wrong_count.chapters:
		if item.level_id == "sleeping-lighthouse": item.stage_count = 2
	_check(not Registry.supported_capabilities(wrong_count).valid, "A chapter whose stage count differs from the bundled one is refused")
	for field: String in ["room_level", "max_join_versions", "max_stages"]:
		var broken := _caps(2)
		broken[field] = "2"
		_check(not Registry.supported_capabilities(broken).valid, "A malformed room level answer is refused: " + field)
	var short := _caps(2)
	short.max_join_versions = 4
	_check(not Registry.supported_capabilities(short).valid, "A room level answer allowing fewer than 8 join rules is refused")

func _session(capabilities: Dictionary) -> Array:
	var api := FakeApi.new()
	api.capabilities = capabilities
	root.add_child(api)
	var store := MemoryStore.new()
	var identity := func() -> Dictionary: return {"ready": true, "player_id": HOST, "epoch": 1}
	var session := Session.new(api, identity, store)
	return [session, api, store, identity]

func _join_body(capabilities: Dictionary) -> Dictionary:
	var made := _session(capabilities)
	var session: RefCounted = made[0]
	var api: FakeApi = made[1]
	_check(await session.load_capabilities(), "Capabilities load")
	await session.join_room("room-" + "AB12".repeat(5))
	var joins: Array = api.calls.filter(func(call: Dictionary) -> bool: return call.path == "/v2/rooms/join")
	var body: Dictionary = joins.back().body if not joins.is_empty() else {}
	# A restart keeps the exact saved join request.
	var reopened := Session.new(api, made[3], made[2])
	_check(reopened._ready() and Canonical.same(reopened.pending_lobby().get("body", {}), body), "The saved join request survives a restart unchanged")
	api.queue_free()
	return body

func _join_lists() -> void:
	var old: Dictionary = await _join_body(_caps(1))
	var versions: Array = old.get("supported_simulation_versions", [])
	_check(Canonical.same(versions, [2, 4, 5, 6, 7, 8, 9]) and versions.size() <= 8 and 11 not in versions, "An old server gets today's join list, at most 8 rules and no 11")
	var level_two: Dictionary = await _join_body(_caps(2))
	_check(Canonical.same(level_two.get("supported_simulation_versions"), [2, 4, 5, 6, 7, 8, 9, 11]), "A room-level-2 server gets the list with rules 11")
	var tight := _caps(2)
	tight.max_join_versions = 8
	_check(Canonical.same((await _join_body(tight)).get("supported_simulation_versions"), [2, 4, 5, 6, 7, 8, 9, 11]), "Eight allowed entries fit the longer list")
	var made := _session({})
	var session: RefCounted = made[0]
	_check(Canonical.same(session.join_versions(), [2, 4, 5, 6, 7, 8, 9]), "Before any capability answer the list stays today's")
	made[1].queue_free()

## Real HTTP on loopback: the room level header goes only with the capability
## read, and a long POST body carries its Content-Length (the Worker reads it
## to choose the chapter's larger turn body bound).
func _wire() -> void:
	var server := TCPServer.new()
	var port := 0
	for attempt in range(20):
		var candidate := 41000 + randi() % 20000
		if server.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			break
	_check(port > 0, "A loopback port is available")
	if port == 0: return
	var api := RoomsApi.new()
	root.add_child(api)
	api.base_url = "http://127.0.0.1:%d" % port
	_check(api.configured(), "Loopback is a configured debug server")
	var capabilities := await _exchange(server, api, HTTPClient.METHOD_GET, "/v2/capabilities", {})
	_check(capabilities.contains("x-afteryou-room-level: 2"), "The capability read asks for room level 2")
	var rooms := await _exchange(server, api, HTTPClient.METHOD_GET, "/v2/rooms", {})
	_check(not rooms.is_empty() and not rooms.contains("x-afteryou-room-level"), "Other reads do not")
	var body := {"padding": "x".repeat(LONG_BODY_BYTES)}
	var length := JSON.stringify(body).to_utf8_buffer().size()
	var posted := await _exchange(server, api, HTTPClient.METHOD_POST, "/v2/rooms/" + ROOM + "/turns", body)
	_check(posted.contains("content-length: %d\r\n" % length), "A long POST body carries its exact Content-Length (%d bytes)" % length)
	server.stop()
	api.queue_free()

func _fire(api: Node, method: int, path: String, body: Dictionary) -> void:
	_fired = await api.request_json(method, path, body)

## The request head (lower case) the server received for one call, after
## answering it with an empty JSON object.
func _exchange(server: TCPServer, api: Node, method: int, path: String, body: Dictionary) -> String:
	_fired = {}
	_fire(api, method, path, body)
	var deadline := Time.get_ticks_msec() + 15000
	var peer: StreamPeerTCP = null
	while peer == null and Time.get_ticks_msec() < deadline:
		if server.is_connection_available(): peer = server.take_connection()
		else: await process_frame
	if peer == null: return ""
	var raw := PackedByteArray()
	var head := ""
	var expected := -1
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk: Array = peer.get_partial_data(available)
			raw.append_array(chunk[1])
		var text := raw.get_string_from_utf8()
		var end := text.find("\r\n\r\n")
		if end >= 0 and head.is_empty():
			head = text.substr(0, end + 2).to_lower()
			var at := head.find("content-length: ")
			expected = end + 4 + (int(head.substr(at + 16, head.find("\r\n", at) - at - 16)) if at >= 0 else 0)
		if not head.is_empty() and raw.size() >= expected: break
		await process_frame
	peer.put_data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}".to_utf8_buffer())
	while _fired.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	peer.disconnect_from_host()
	return head

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
