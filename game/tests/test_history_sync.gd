extends SceneTree
## Room history sync against a scripted server: download, check, durable save and
## ACK; nothing is confirmed while work is pending or offload is off; a friend's
## request sends the exact bytes back; a finished room's last attempt is restored
## before a fork; parts play from this phone's copy.

const Sync = preload("res://services/history_sync.gd")
const Store = preload("res://services/history_store.gd")
const Canonical = preload("res://core/v2/canonical.gd")

const SERVER := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

class Server:
	var view: Dictionary = {}
	var blobs: Dictionary = {}
	var calls: Array = []
	var uploads: Array = []
	var fail_get := ""
	func call_api(method: int, path: String, body: Variant, raw: bool) -> Dictionary:
		calls.append("%s %s" % ["GET" if method == HTTPClient.METHOD_GET else "POST", path])
		if fail_get == path: return {"ok": false, "status": 503, "code": "unavailable"}
		if path.ends_with("/history"): return {"ok": true, "status": 200, "data": view.duplicate(true)}
		var position := int(path.get_slice("/history/", 1).get_slice("/", 0))
		if path.ends_with("/ack"):
			view.attempts[position].acked_by_you = true
			return {"ok": true, "status": 200, "data": view}
		if path.ends_with("/want"): return {"ok": true, "status": 200, "data": view}
		if raw and method == HTTPClient.METHOD_POST:
			uploads.append(body)
			view.attempts[position].state = "held"
			return {"ok": true, "status": 200, "data": view}
		if view.attempts[position].state == "offloaded": return {"ok": false, "status": 410, "code": "history_offloaded"}
		return {"ok": true, "status": 200, "bytes": blobs[position]}

class Scope:
	var value := {"ok": true, "owner": OWNER, "server_key": SERVER, "offload_enabled": true, "gameplay_pending": false, "photo_pending": false, "redo_pending": false, "standalone": true}
	func read(_room_id: String) -> Dictionary: return value.duplicate()

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _attempt(vectors: Dictionary, position: int, state: String) -> Dictionary:
	return {"position": position, "branch": position, "digest": vectors.digest, "link": vectors.links[0], "byte_length": vectors.byte_length, "last_stage": 2,
		"state": state, "acked_by_you": false, "partner_acked": false, "wanted_by_partner": false, "pair_ids": ["p0-0", "p0-1"]}

func _run() -> void:
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/history/vectors.json"))
	var tagged := Marshalls.base64_to_raw(vectors.deflate_base64.godot)
	var root := "user://history-sync-test-%d" % Time.get_ticks_usec()
	var store := Store.new(root)
	var server := Server.new()
	var scope := Scope.new()
	var sync := Sync.new(server.call_api, scope.read, store)
	server.blobs[0] = tagged
	var facts := {"room_id": ROOM, "level_id": vectors.room.level_id, "level_version": vectors.room.level_version, "definition_hash": vectors.room.definition_hash, "host_id": OWNER, "guest_id": "GGGGGGGGGGGGGGGGGGGGGG"}
	server.view = {"schema_version": 1, "mode": "attempts", "head": vectors.links[0], "room": facts, "attempts": [_attempt(vectors, 0, "held")]}
	_check(Sync.valid_view(server.view), "The server's list shape is accepted")
	var broken: Dictionary = server.view.duplicate(true)
	broken.head = "c".repeat(64)
	_check(not Sync.valid_view(broken), "A head that is not the last link is refused")

	# Pending gameplay: download and keep, but do not confirm.
	scope.value.gameplay_pending = true
	var result: Dictionary = await sync.sync_room(ROOM)
	_check(result.get("ok", false) and result.acknowledged.is_empty() and store.has(SERVER, OWNER, ROOM, 0, vectors.links[0]), "With a turn pending the attempt is saved but not confirmed")
	_check(not server.calls.has("POST /v2/rooms/%s/history/0/ack" % ROOM), "No ACK is sent while gameplay is pending")
	scope.value.gameplay_pending = false
	scope.value.offload_enabled = false
	server.calls.clear()
	result = await sync.sync_room(ROOM)
	_check(result.get("ok", false) and result.acknowledged.is_empty() and server.calls == ["GET /v2/rooms/%s/history" % ROOM], "With offload off nothing is downloaded again and nothing is confirmed")
	scope.value.offload_enabled = true
	result = await sync.sync_room(ROOM)
	_check(result.get("ok", false) and result.acknowledged == [0], "Once quiet and enabled, the saved attempt is confirmed")

	# A bad download is never saved or confirmed.
	var other := Store.new(root + "-b")
	var fresh := Sync.new(server.call_api, scope.read, other)
	server.view.attempts[0].acked_by_you = false
	var cut := tagged.slice(0, tagged.size() - 7)
	server.blobs[0] = cut
	result = await fresh.sync_room(ROOM)
	_check(not result.get("ok", false) and result.code == "history_mismatch" and not other.has(SERVER, OWNER, ROOM, 0, vectors.links[0]), "A cut-off download is refused and nothing is saved")
	server.blobs[0] = tagged
	var wrong_room := Sync.new(server.call_api, scope.read, other)
	result = await wrong_room.sync_room("SSSSSSSSSSSSSSSSSSSSSS")
	_check(not result.get("ok", false) and result.code == "history_mismatch", "An attempt from another room is refused")
	server.fail_get = "/v2/rooms/%s/history/0" % ROOM
	result = await fresh.sync_room(ROOM)
	_check(not result.get("ok", false) and result.status == 503, "A failed download stops the pass for a later retry")
	server.fail_get = ""

	# Offloaded: the friend's phone asks; this phone sends its exact bytes.
	server.view.attempts[0].state = "offloaded"
	server.view.attempts[0].wanted_by_partner = true
	result = await sync.sync_room(ROOM)
	_check(result.get("ok", false) and server.uploads.size() == 1 and server.uploads[0] == tagged, "A wanted attempt goes back as the exact bytes received")
	server.view.attempts[0].state = "offloaded"
	server.view.attempts[0].wanted_by_partner = false
	result = await fresh.sync_room(ROOM)
	_check(result.get("ok", false) and result.missing == [0] and server.calls.back() == "POST /v2/rooms/%s/history/0/want" % ROOM, "An offloaded attempt this phone lacks is reported and asked for")
	_check((await fresh.want(ROOM, 0)).get("ok", false) and server.calls.back() == "POST /v2/rooms/%s/history/0/want" % ROOM, "Asking for it posts to want")

	# Restore before a fork on a finished room.
	server.uploads.clear()
	result = await sync.restore_final(ROOM)
	_check(result.get("ok", false) and result.get("restored", false) and server.uploads.size() == 1, "The last attempt is sent back before a fork")
	server.view.attempts[0].state = "offloaded"
	result = await fresh.restore_final(ROOM)
	_check(not result.get("ok", false) and result.code == "history_missing", "A phone without the last attempt says so")
	server.view = {"schema_version": 1, "mode": "v1_transferred", "head": Store.ZERO_LINK, "room": facts, "attempts": []}
	_check((await sync.restore_final(ROOM)).get("mode") == "v1_transferred", "A v1 room is left to replay transfer")

	# Parts play from the saved copy.
	var a1: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/relay-a.json"))
	var b2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/garden-b.json"))
	var middle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/relay-checkpoint.json"))
	var first := sync.local_pair(SERVER, OWNER, ROOM, "relay-isles@2", "p0-0")
	var second := sync.local_pair(SERVER, OWNER, ROOM, "relay-isles@2", "p0-1")
	_check(Canonical.same(first.get("a"), a1) and Canonical.same(first.get("checkpoint"), middle) and first.get("stage_index") == 0, "The first part rebuilds from the nested checkpoint")
	_check(Canonical.same(second.get("b"), b2) and second.get("checkpoint", {}).get("stage_index") == 2.0, "The last part is the attempt's own checkpoint")
	_check(sync.local_pair(SERVER, OWNER, ROOM, "relay-isles@2", "p1-0").is_empty() and fresh.local_pair(SERVER, OWNER, ROOM, "relay-isles@2", "p0-0").is_empty(), "A part this phone lacks is empty")
	store.erase_owner(OWNER)
	other.erase_owner(OWNER)
	for path: String in [root, root + "-b"]:
		DirAccess.remove_absolute(path.path_join(SERVER.left(16)))
		DirAccess.remove_absolute(path)
	print("History sync: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
