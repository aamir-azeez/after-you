extends SceneTree
## Response and pair size caps. The room API keeps 4 MiB for every response but
## the completed replay-transfer download, checked over a local HTTP fixture.
## Turn of the Tide's widest transfer then goes through the real download path
## and every client cap. Its widened recordings are structural, not native.
const Api = preload("res://services/rooms_api.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Transfer = preload("res://services/replay_transfer.gd")
const Store = preload("res://services/shared_replay_store.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const TRANSFER := "/v2/rooms/" + ROOM + "/replay-transfer"
const WHEN := "2026-10-13T00:00:00.000Z"
## Turn of the Tide's turns: 2,700 ticks for A and 3,000 for B, on up to seven branches.
const TIDE_A_TICKS := 2700
const TIDE_B_TICKS := 3000
const TIDE_BRANCHES := 7
## backend/src/v2/replay-transfer.ts MAX_REPLAY_ARCHIVE_BYTES and snapshot.ts MAX_ROW_BYTES.
const SERVER_ARCHIVE_BYTES := 16777216
const SERVER_ROW_BYTES := 1572864
var checks := 0
var failures := 0
var api = null

## Records each request's headers instead of sending it.
class HeaderCapture extends "res://services/rooms_api.gd":
	var sent: Array[PackedStringArray] = []
	func _send(_method: int, _path: String, headers: PackedStringArray, _body: String) -> Array:
		sent.append(headers)
		return [HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"registered": true}).to_utf8_buffer()]

## Replies to each request in turn, writing large bodies a slice a frame so the
## client on the same thread keeps reading.
class Server:
	extends Node
	var server := TCPServer.new()
	var port := 0
	var peers: Array = []
	var replies: Array = []
	var paths: Array = []
	func start(low: int) -> bool:
		for candidate in range(low, low + 16):
			if server.listen(candidate, "127.0.0.1") == OK:
				port = candidate
				return true
		return false
	func reply(body: PackedByteArray, extra: String = "") -> void:
		var head := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n%sConnection: close\r\n\r\n" % [body.size(), extra]
		replies.append(head.to_utf8_buffer() + body)
	func _process(_delta: float) -> void:
		while server.is_connection_available():
			peers.append({"stream": server.take_connection(), "request": PackedByteArray(), "out": PackedByteArray(), "sent": 0, "ready": false})
		for index in range(peers.size() - 1, -1, -1):
			var peer: Dictionary = peers[index]
			var stream: StreamPeerTCP = peer.stream
			stream.poll()
			if stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				peers.remove_at(index)
				continue
			if not peer.ready:
				var size := stream.get_available_bytes()
				if size > 0:
					var received: Array = stream.get_data(size)
					if received[0] == OK: peer.request.append_array(received[1])
				var text: String = peer.request.get_string_from_utf8()
				if text.find("\r\n\r\n") < 0: continue
				paths.append(text.get_slice(" ", 1))
				peer.out = replies.pop_front() if not replies.is_empty() else "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_utf8_buffer()
				peer.ready = true
			while peer.sent < peer.out.size():
				var sent: Array = stream.put_partial_data(peer.out.slice(peer.sent, peer.sent + 262144))
				if sent[0] != OK or sent[1] == 0: break
				peer.sent += sent[1]
	func stop() -> void:
		for peer: Dictionary in peers: peer.stream.disconnect_from_host()
		peers.clear()
		server.stop()

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_json_numbers()
	await _extra_headers()
	_route_caps()
	_pair_caps()
	var server := Server.new()
	root.add_child(server)
	api = Api.new()
	root.add_child(api)
	if server.start(24251):
		api.base_url = "http://127.0.0.1:%d" % server.port
		api.player_id = HOST
		api.device_token = "synthetic-limit-test-only"
		await _http_caps(server)
		var wire := _tide_wire()
		await _tide_fits(server, wire)
		await _tide_download(server, wire)
	else:
		_check(false, "A local-only HTTP fixture can bind a test port")
	await process_frame
	server.stop()
	api.free()
	server.free()
	print("ROOMS API LIMITS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Every number in a parsed reply is a float; json_int reads whole ones back.
func _json_numbers() -> void:
	var parsed: Variant = JSON.parse_string('{"v":2,"e":4,"half":2.5,"big":1e300,"s":"2"}')
	_check(parsed.v is float and not (parsed.v in [1,2]),"Godot parses JSON numbers as floats")
	_check(Api.json_int(parsed.v) == 2 and Api.json_int(parsed.v) in [1,2] and str(Api.json_int(parsed.e)) == "4","json_int reads a parsed whole number as an int")
	_check(Api.json_int(parsed.half) == -1 and Api.json_int(parsed.big) == -1 and Api.json_int(parsed.s) == -1 and Api.json_int(null, 0) == 0,"json_int refuses fractions, huge values, strings and null")
	_check(Api.json_int(7) == 7,"json_int keeps a real int")
	# Only this build's hosting-event reads and push registrations say it reads hosting events.
	for path: String in ["/v1/social/inbox","/v1/notifications/registration"]:
		_check(Api.capability_headers(HTTPClient.METHOD_GET if path.ends_with("inbox") else HTTPClient.METHOD_POST,path).has("X-AfterYou-Friend-Events: 2"),"The client advertises hosting events on "+path)
	var inbox_headers := Api.capability_headers(HTTPClient.METHOD_GET,"/v1/room-inbox")
	_check(inbox_headers.has("X-AfterYou-Room-Inbox: 2") and inbox_headers.has("X-AfterYou-Room-Leave: 1"),"The inbox asks for closed rooms and for finished rooms a friend left")
	_check(not Api.capability_headers(HTTPClient.METHOD_GET,"/v1/friends").has("X-AfterYou-Friend-Events: 2") and Api.capability_headers(HTTPClient.METHOD_GET,"/v1/friends").has("X-AfterYou-Friends: 2"),"Other requests keep their own headers")
	_check(Api.capability_headers(HTTPClient.METHOD_GET,"/v2/capabilities") == PackedStringArray(["Content-Type: application/json","X-AfterYou-Room-Level: 2","X-AfterYou-Live: 1","X-AfterYou-Client: "+ProjectSettings.get_setting("application/config/version")+" dev"]),"Room-level and live headers are as sent, and the build names itself last")

## The iOS registration adds its headers after the capability ones; every other request is unchanged.
func _extra_headers() -> void:
	var capture := HeaderCapture.new()
	root.add_child(capture)
	capture.base_url = "https://headers.synthetic.invalid"
	var path := "/v1/notifications/registration"
	var extra := PackedStringArray(["X-AfterYou-Platform: ios","X-AfterYou-Push-Categories: turns"])
	await capture.request_json(HTTPClient.METHOD_POST,path,{})
	await capture.request_json_with_headers(HTTPClient.METHOD_POST,path,{},extra)
	var base := Api.capability_headers(HTTPClient.METHOD_POST,path)
	_check(capture.sent.size() == 2 and capture.sent[0] == base,"A plain request sends only the capability headers")
	_check(capture.sent[1] == base + extra,"Extra headers follow the capability headers unchanged")
	capture.free()

func _route_caps() -> void:
	_check(Api.MAX_RESPONSE_BYTES == 4194304, "Room API responses keep their 4 MiB cap")
	_check(Transfer.MAX_ARCHIVE_BYTES == SERVER_ARCHIVE_BYTES and Api.MAX_REPLAY_TRANSFER_RESPONSE_BYTES == SERVER_ARCHIVE_BYTES + 65536, "The replay-transfer download may carry the server's whole 16 MiB archive and 64 KiB more")
	var envelope := _widest_envelope()
	_check(envelope * 3 <= 65536 * 2, "...and the widest manifest around it takes under two thirds of that 64 KiB: %d bytes" % envelope)
	_check(Api.response_limit(HTTPClient.METHOD_GET, TRANSFER) == Api.MAX_REPLAY_TRANSFER_RESPONSE_BYTES, "Only the completed replay-transfer download reads past 4 MiB")
	var others := [[HTTPClient.METHOD_GET, TRANSFER + "/manifest"], [HTTPClient.METHOD_GET, TRANSFER + "/operations/" + "k".repeat(32)], [HTTPClient.METHOD_POST, TRANSFER + "/ack"],
		[HTTPClient.METHOD_POST, TRANSFER + "/restore"], [HTTPClient.METHOD_POST, TRANSFER], [HTTPClient.METHOD_DELETE, TRANSFER], [HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM],
		[HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM + "/pairs/p6-1"], [HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM.left(21) + "/replay-transfer"], [HTTPClient.METHOD_GET, TRANSFER + "/"],
		[HTTPClient.METHOD_GET, TRANSFER + "?archive=1"], [HTTPClient.METHOD_GET, "/v2/campaigns/" + ROOM + TRANSFER], [HTTPClient.METHOD_GET, "/v1/rooms/" + ROOM + "/replay-transfer"]]
	for item: Array in others:
		_check(Api.response_limit(item[0], item[1]) == Api.MAX_RESPONSE_BYTES, "Every other call keeps 4 MiB: %d %s" % item)

func _pair_caps() -> void:
	_check(Coordinator.MAX_PAIR_BYTES == 2097152 and Coordinator.MAX_PAIR_NODES == 220000, "A fetched pair is capped at 2 MiB and 220k values")
	_check(Coordinator.MAX_PAIR_BYTES >= SERVER_ROW_BYTES, "A fetched pair fits anything one server pairs row can hold")
	var heavy := _sized(Coordinator.MAX_PAIR_BYTES)
	_check(JSON.stringify(heavy).to_utf8_buffer().size() == Coordinator.MAX_PAIR_BYTES and Coordinator._pair_bounded(heavy), "A pair of exactly 2 MiB fits")
	heavy.padding[-1] += "x"
	_check(not Coordinator._pair_bounded(heavy), "One byte more is refused")
	var wide: Array = []
	wide.resize(Coordinator.MAX_PAIR_NODES - 1)
	_check(Coordinator._pair_bounded(wide), "A pair of exactly 220k values fits")
	wide.append(null)
	_check(not Coordinator._pair_bounded(wide), "One value more is refused")

func _http_caps(server: Server) -> void:
	var ordinary := "/v2/rooms/" + ROOM
	await _settle()
	server.reply(_body(Api.MAX_RESPONSE_BYTES))
	var at_cap: Dictionary = await api.request_json(HTTPClient.METHOD_GET, ordinary)
	_check(at_cap.ok and str(at_cap.data.get("p", "")).length() == Api.MAX_RESPONSE_BYTES - 8, "An ordinary response of exactly 4 MiB is read")
	server.reply(_body(Api.MAX_RESPONSE_BYTES + 1))
	var over: Dictionary = await api.request_json(HTTPClient.METHOD_GET, ordinary)
	_check(not over.ok and over.data.is_empty() and not api._queue.busy(), "An ordinary response one byte over 4 MiB is still refused")
	# The server's responses may be compressed; the cap counts the body inflated.
	server.reply(_body(Api.MAX_RESPONSE_BYTES).compress(FileAccess.COMPRESSION_GZIP), "Content-Encoding: gzip\r\n")
	var zipped: Dictionary = await api.request_json(HTTPClient.METHOD_GET, ordinary)
	_check(zipped.ok and str(zipped.data.get("p", "")).length() == Api.MAX_RESPONSE_BYTES - 8, "A compressed response that inflates to exactly 4 MiB is read")
	var packed := _body(Api.MAX_RESPONSE_BYTES + 1).compress(FileAccess.COMPRESSION_GZIP)
	server.reply(packed, "Content-Encoding: gzip\r\n")
	var zipped_over: Dictionary = await api.request_json(HTTPClient.METHOD_GET, ordinary)
	_check(packed.size() < 65536 and not zipped_over.ok and zipped_over.data.is_empty(), "...and one inflating to a byte more is refused, though only %d bytes travel" % packed.size())
	server.reply(_body(Api.MAX_REPLAY_TRANSFER_RESPONSE_BYTES))
	var transfer_cap: Dictionary = await api.request_json(HTTPClient.METHOD_GET, TRANSFER)
	_check(transfer_cap.ok and str(transfer_cap.data.get("p", "")).length() == Api.MAX_REPLAY_TRANSFER_RESPONSE_BYTES - 8, "The replay-transfer download reads exactly its own cap")
	server.reply(_body(Api.MAX_REPLAY_TRANSFER_RESPONSE_BYTES + 1))
	var transfer_over: Dictionary = await api.request_json(HTTPClient.METHOD_GET, TRANSFER)
	_check(not transfer_over.ok and transfer_over.data.is_empty() and not api._queue.busy(), "...and refuses one byte more")
	server.reply(_body(Api.MAX_RESPONSE_BYTES + 1))
	var manifest: Dictionary = await api.request_json(HTTPClient.METHOD_GET, TRANSFER + "/manifest")
	_check(not manifest.ok and server.paths.size() == 7 and server.paths[-1] == TRANSFER + "/manifest", "The manifest read beside it keeps 4 MiB")

## Seven branches, every one forked back to the start and played through both
## stages at the turn caps, as the server would send them.
func _tide_wire() -> PackedByteArray:
	var transfer := tide_transfer(tide_chain(), TIDE_BRANCHES)
	transfer.manifest.archive_hash = Canonical.digest(transfer.archive)
	return JSON.stringify(transfer).to_utf8_buffer()

## A request timer started at the end of a long frame would see that frame's
## whole time at once; let two short frames pass first.
func _settle() -> void:
	await process_frame
	await process_frame

func _tide_fits(server: Server, wire: PackedByteArray) -> void:
	_check(wire.size() > Api.MAX_RESPONSE_BYTES and wire.size() <= Api.MAX_REPLAY_TRANSFER_RESPONSE_BYTES, "The widest tide transfer needs the transfer cap and fits it: %d bytes" % wire.size())
	server.reply(wire)
	await _settle()
	var read: Dictionary = await api.request_json(HTTPClient.METHOD_GET, TRANSFER)
	_check(read.ok and read.data.archive.turns.size() == 4 * TIDE_BRANCHES and read.data.archive.pairs.size() == 2 * TIDE_BRANCHES, "The room API reads the whole widest tide transfer")
	if not read.ok: return
	# Sizes as the client counts them: JSON numbers come back as floats, written "1.0".
	var archive: Dictionary = read.data.archive
	var archive_bytes := JSON.stringify(archive).to_utf8_buffer().size()
	var manifest_bytes := JSON.stringify(read.data.manifest).to_utf8_buffer().size()
	print("TIDE TRANSFER: %d branches, %d bytes on the wire; the client counts %d for its archive" % [TIDE_BRANCHES, wire.size(), archive_bytes])
	var room := Transfer._metadata(archive.room, Registry.TURN_OF_THE_TIDE)
	var entries := {}
	var widest := [0, 0]
	for pair: Dictionary in archive.pairs:
		var entry := {"schema_version": 1, "room": room, "pair": pair}
		entries[pair.pair_id] = entry
		widest = [maxi(widest[0], JSON.stringify(entry).to_utf8_buffer().size()), maxi(widest[1], _nodes(entry))]
	print("TIDE PAIR: %d bytes, %d values" % widest)
	_check(entries.values().all(func(entry: Dictionary): return Coordinator._pair_bounded(entry)), "Every pair fits the pair cap, fetched or remembered")
	_check(widest[0] * 3 <= Coordinator.MAX_PAIR_BYTES * 2 and widest[1] * 3 <= Coordinator.MAX_PAIR_NODES * 2, "...with at least 1.5x to spare: %d of %d bytes, %d of %d values" % [widest[0], Coordinator.MAX_PAIR_BYTES, widest[1], Coordinator.MAX_PAIR_NODES])
	# The transfer store's value and a restore request wrap the same manifest and archive; "{}" stands in for each.
	var kept := JSON.stringify({"schema_version": 1, "owner": HOST, "server_key": "a".repeat(64), "manifest": {}, "archive": {}}).to_utf8_buffer().size() - 4 + manifest_bytes + archive_bytes
	var scope := "shared-replays:%s:transfer:%s:1" % [HOST, ROOM]
	_check(Store._scope_valid(scope) and kept <= Store._file_limit(scope) - 4096, "The transfer store can keep the whole archive: %d bytes" % kept)
	var cache := JSON.stringify({"schema_version": 1, "owner": HOST, "entries": entries}).to_utf8_buffer().size()
	scope = "shared-replays:%s:chapter:%s" % [HOST, ROOM]
	_check(Store._scope_valid(scope) and cache <= Store._file_limit(scope) - 4096, "The chapter replay cache can keep all fourteen pairs: %d bytes" % cache)
	var restore := JSON.stringify({"schema_version": 1, "epoch": 1, "archive_hash": "f".repeat(64), "archive": {}}).to_utf8_buffer().size() - 2 + archive_bytes
	_check(restore <= SERVER_ARCHIVE_BYTES + 4096, "Sent back by a restore, it fits the server's restore request bound: %d bytes" % restore)
	print("TIDE STORES: transfer %d, chapter cache %d, restore request %d bytes" % [kept, cache, restore])

## The real download: transport, manifest, the archive's 16 MiB / 2M value cap
## and each pair entry admit it; only native replay of its synthetic recordings
## refuses it.
func _tide_download(server: Server, wire: PackedByteArray) -> void:
	server.reply(wire)
	var service: RefCounted = Transfer.new(_transport, func(): return {"ready": true, "player_id": HOST, "epoch": 1},
		func(_room: String): return {"ok": true, "server_key": "a".repeat(64), "standalone": true, "gameplay_pending": false, "photo_pending": false, "redo_pending": false, "enabled": true}, Unsaved.new())
	await _settle()
	var downloaded: Dictionary = await service.download(ROOM)
	_check(downloaded.get("code") == "invalid_replay_pair" and server.paths.size() == 9, "The download admits it past the archive and pair caps; only native replay refuses it: %s" % downloaded.get("code"))

class Unsaved extends RefCounted:
	func load_scope(_scope: String) -> Dictionary: return {"ok": false}
	func save_scope(_scope: String, _value: Dictionary) -> bool: return false

func _transport(request: Dictionary) -> Dictionary:
	return await api.request_json(request.method, request.path)

## The widest manifest the server can send, with its transfer fields and no archive.
func _widest_envelope() -> int:
	var hash := "f".repeat(64)
	var largest := 9007199254740991
	var turns: Array = []
	for index in range(128): turns.append({"turn_id": "t31-1-b", "player_id": HOST, "accepted_revision": largest, "recording_hash": hash})
	var pairs: Array = []
	for index in range(64): pairs.append({"pair_id": "p31-1", "branch": 31, "stage_index": 1, "a_hash": hash, "b_hash": hash, "checkpoint_hash": hash})
	var level := Registry.descriptor(Registry.TURN_OF_THE_TIDE)
	var room := {"schema_version": 2, "room_id": ROOM, "revision": largest, "branch": 31, "stage_index": 2, "level_id": level.level_id, "level_version": level.level_version, "definition_hash": hash,
		"host_id": HOST, "guest_id": GUEST, "checkpoint_hash": hash, "a_turn_id": null, "completed_pair_ids": ["p31-0", "p31-1"], "invite_expires_at": WHEN, "created_at": WHEN, "updated_at": WHEN, "simulation_version": largest}
	var manifest := {"schema_version": 1, "epoch": largest, "archive_hash": hash, "room": room, "turns": turns, "pairs": pairs}
	return JSON.stringify({"schema_version": 1, "manifest": manifest, "acked_player_ids": [HOST, GUEST], "transferred": true, "archive": null}).to_utf8_buffer().size()

## Each tide stage's turns at their caps, one action entry a tick in its widest
## form, under that stage's widest checkpoint from any way through it.
static func tide_chain() -> Dictionary:
	var a1 := _widest(_fixture("set-the-tide-a"), TIDE_A_TICKS)
	var b1 := _widest(_fixture("set-the-tide-b"), TIDE_B_TICKS)
	var a2 := _widest(_fixture("slack-water-a"), TIDE_A_TICKS)
	var b2 := _widest(_fixture("slack-water-b"), TIDE_B_TICKS)
	var middle := _largest("set-the-tide")
	middle.proof = {"checkpoint": _fixture("turn-of-the-tide-initial-checkpoint"), "a": a1, "b": b1}
	var final := _largest("slack-water")
	final.proof = {"checkpoint": middle, "a": a2, "b": b2}
	return {"a1": a1, "b1": b1, "cp1": middle, "a2": a2, "b2": b2, "cp2": final}

## The complete transfer of a tide room whose every branch went back to the start.
static func tide_transfer(chain: Dictionary, branches: int) -> Dictionary:
	var level := Registry.descriptor(Registry.TURN_OF_THE_TIDE)
	var stages: Array = Registry.definition(Registry.TURN_OF_THE_TIDE).stages
	var turns: Array = []
	var pairs: Array = []
	var revision := 0
	for branch in range(branches):
		for stage in range(2):
			var first: String = HOST if stages[stage].first_player_slot == "p0" else GUEST
			var second: String = GUEST if first == HOST else HOST
			var a: Dictionary = chain.a1 if stage == 0 else chain.a2
			var b: Dictionary = chain.b1 if stage == 0 else chain.b2
			revision += 1
			turns.append({"turn_id": "t%d-%d-a" % [branch, stage], "player_id": first, "accepted_revision": revision, "recording": a})
			revision += 1
			turns.append({"turn_id": "t%d-%d-b" % [branch, stage], "player_id": second, "accepted_revision": revision, "recording": b})
			pairs.append({"pair_id": "p%d-%d" % [branch, stage], "branch": branch, "stage_index": stage, "a": a, "b": b, "checkpoint": chain.cp1 if stage == 0 else chain.cp2})
		revision += 1
	var last := branches - 1
	var room := {"schema_version": 2, "room_id": ROOM, "revision": revision, "branch": last, "stage_index": 2, "level_id": level.level_id, "level_version": level.level_version, "definition_hash": level.definition_hash,
		"host_id": HOST, "guest_id": GUEST, "checkpoint": chain.cp2, "a_turn_id": null, "completed_pair_ids": ["p%d-0" % last, "p%d-1" % last], "invite_expires_at": WHEN, "created_at": WHEN, "updated_at": WHEN}
	var facts := room.duplicate()
	facts.erase("checkpoint")
	facts["checkpoint_hash"] = chain.cp2.checkpoint_hash
	var turn_facts: Array = turns.map(func(item: Dictionary): return {"turn_id": item.turn_id, "player_id": item.player_id, "accepted_revision": item.accepted_revision, "recording_hash": item.recording.recording_hash})
	var pair_facts: Array = pairs.map(func(item: Dictionary): return {"pair_id": item.pair_id, "branch": item.branch, "stage_index": item.stage_index, "a_hash": item.a.recording_hash, "b_hash": item.b.recording_hash, "checkpoint_hash": item.checkpoint.checkpoint_hash})
	var manifest := {"schema_version": 1, "epoch": 1, "archive_hash": "f".repeat(64), "room": facts, "turns": turn_facts, "pairs": pair_facts}
	return {"schema_version": 1, "manifest": manifest, "acked_player_ids": [], "transferred": false, "archive": {"schema_version": 1, "room": room, "turns": turns, "pairs": pairs}}

static func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/journey/%s.json" % name))

static func _largest(prefix: String) -> Dictionary:
	var best: Dictionary = {}
	var size := -1
	for file: String in DirAccess.get_files_at("res://tests/fixtures/journey"):
		if not file.begins_with(prefix) or not file.ends_with("-checkpoint.json"): continue
		var value := _fixture(file.trim_suffix(".json"))
		value.erase("proof")
		var bytes := JSON.stringify(value).to_utf8_buffer().size()
		if bytes > size:
			best = value
			size = bytes
	return best

static func _widest(record: Dictionary, ticks: int) -> Dictionary:
	var actions: Array = []
	for index in range(ticks): actions.append({"action": false, "ticks": 1, "x": -100, "z": -99 if index % 2 else -100})
	var count := ticks / 30 + 1
	var replay_checks: Array = []
	for index in range(count): replay_checks.append({"tick": ticks - count + 1 + index, "state_hash": record.final_state_hash})
	record.actions = actions
	record.replay_checks = replay_checks
	record.duration_ticks = ticks
	record.catch_assistance = false
	return record

## {"p":"xx…"}, exactly `size` bytes.
static func _body(size: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(size)
	bytes.fill(120)
	var head := "{\"p\":\"".to_utf8_buffer()
	for index in range(head.size()): bytes[index] = head[index]
	bytes[size - 2] = 34
	bytes[size - 1] = 125
	return bytes

## {"padding":["xx…",…]}, exactly `size` bytes, every string short of the 512 limit.
static func _sized(size: int) -> Dictionary:
	var strings: Array = []
	# 14 bytes around the array; each string adds its length, two quotes and a comma (one fewer comma overall).
	var left := size - 14 + 1
	while left > 0:
		var length := 500
		if left <= 503: length = left - 3
		elif left - 503 < 3: length = 495
		strings.append("x".repeat(length))
		left -= length + 3
	return {"padding": strings}

static func _nodes(value: Variant) -> int:
	var count := 1
	if value is Dictionary:
		for child: Variant in value.values(): count += _nodes(child)
	elif value is Array:
		for child: Variant in value: count += _nodes(child)
	return count

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
