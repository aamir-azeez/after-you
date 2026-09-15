extends SceneTree
## Two local libraries share one fake delivery service; real JPEGs reach disk.
const Controller = preload("res://services/turn_photo_controller.gd")
const Library = preload("res://services/turn_photo_library.gd")
const PhotoFixtures = preload("res://tests/test_turn_photo.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const RECORDING := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

class Identity:
	extends RefCounted
	var player := OWNER
	func current() -> Dictionary: return {"ready": true, "player_id": player, "epoch": 1}

class DiskFailure:
	extends RefCounted
	func read_cache(_owner: String, _room: String, _target: Dictionary) -> Dictionary: return {"ok": true, "found": false}
	func store_cache(_owner: String, _room: String, _photo: Dictionary, _bytes: PackedByteArray) -> Dictionary: return {"ok": false}

class Server:
	extends RefCounted
	var photo: Dictionary = {}
	var bytes := PackedByteArray()
	var acked: Array = []
	var downloads := 0
	var acks := 0
	var available := true
	var offline := false
	var deleted := false
	var delete_on_payload := false
	func request(request: Dictionary) -> Dictionary:
		if offline: return {"ok": false, "status": 0, "code": "connection_interrupted"}
		var owner: String = request.owner_player_id
		if request.path.ends_with("/delivery"): return _ok(_delivery())
		if request.path.ends_with("/ack"):
			if request.body.sha256 != photo.sha256 or request.body.photo_revision != photo.photo_revision: return {"ok": false, "status": 409, "code": "stale_photo_revision"}
			acks += 1
			if owner not in acked: acked.append(owner)
			if acked.size() == 2: available = false
			var result := _delivery()
			result.acked = true
			return _ok(result)
		if delete_on_payload:
			delete_on_payload = false
			deleted = true
			photo.photo_revision += 1
			photo.sha256 = null
			photo.width = null
			photo.height = null
			photo.byte_length = 0
			return _ok({"photo": photo, "jpeg_base64": null})
		if not available: return {"ok": false, "status": 410, "code": "photo_payload_delivered"}
		downloads += 1
		return _ok({"photo": photo, "jpeg_base64": Marshalls.raw_to_base64(bytes)})
	func _delivery() -> Dictionary:
		return {"schema_version": 1, "photo": photo, "available": available, "removed_reason": "owner_deleted" if deleted else null if available else "delivered", "intended_player_ids": [OWNER, GUEST], "acked_player_ids": acked.duplicate()}
	func _ok(value: Dictionary) -> Dictionary: return {"ok": true, "status": 200, "data": value.duplicate(true)}

var checks := 0
var failures: Array[String] = []
func _init() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _run() -> void:
	var folder := "user://photo-delivery-tests-" + str(Time.get_ticks_usec())
	var image := Image.create(24, 24, false, Image.FORMAT_RGB8)
	image.fill(Color("a6d9c4"))
	var server := Server.new()
	server.bytes = image.save_jpg_to_buffer(0.7)
	server.photo = {"schema_version": 1, "turn_id": "t0-0-a", "owner_player_id": OWNER, "recording_hash": RECORDING, "photo_revision": 1, "sha256": Controller._digest(server.bytes), "width": 24, "height": 24, "byte_length": server.bytes.size(), "updated_at": "2026-09-15T00:00:00.000Z"}
	var first := Identity.new()
	var second := Identity.new()
	second.player = GUEST
	var first_library := Library.new(folder + "/first")
	var second_library := Library.new(folder + "/second")
	var a := Controller.new(server.request, Callable(), Callable(), first.current, Callable(), Callable(), first_library)
	var b := Controller.new(server.request, Callable(), Callable(), second.current, Callable(), Callable(), second_library)
	var photo: Dictionary = await a.read_shared(ROOM, "t0-0-a", RECORDING)
	check(photo.get("bytes") == server.bytes and server.downloads == 1 and server.acks == 1, "first player caches real JPEG before ACK")
	check(server.available, "one participant cannot remove shared payload")
	photo = await a.read_shared(ROOM, "t0-0-a", RECORDING)
	check(photo.get("bytes") == server.bytes and server.downloads == 1 and server.acks == 1, "replay skips repeated JPEG and ACK requests")
	photo = await b.read_shared(ROOM, "t0-0-a", RECORDING)
	check(photo.get("bytes") == server.bytes and server.downloads == 2 and server.acks == 2 and not server.available, "second durable receipt removes service payload")
	var restarted := Controller.new(server.request, Callable(), Callable(), first.current, Callable(), Callable(), Library.new(folder + "/first"))
	photo = await restarted.read_shared(ROOM, "t0-0-a", RECORDING)
	check(photo.get("bytes") == server.bytes and server.downloads == 2, "fresh process uses persistent cache after remote deletion")
	server.offline = true
	photo = await b.read_shared(ROOM, "t0-0-a", RECORDING)
	check(photo.get("bytes") == server.bytes, "cached replay works offline")
	server.offline = false
	server.deleted = true
	server.photo.photo_revision = 2
	server.photo.sha256 = null
	server.photo.width = null
	server.photo.height = null
	server.photo.byte_length = 0
	photo = await b.read_shared(ROOM, "t0-0-a", RECORDING)
	check(photo.get("bytes", PackedByteArray()).is_empty(), "owner deletion hides cached shared bubble")
	server.offline = true
	photo = await b.read_shared(ROOM, "t0-0-a", RECORDING)
	check(photo.is_empty(), "durable deletion tombstone also applies offline")
	var failure_server := Server.new()
	failure_server.bytes = image.save_jpg_to_buffer(0.6)
	failure_server.photo = {"schema_version": 1, "turn_id": "t0-0-a", "owner_player_id": OWNER, "recording_hash": RECORDING, "photo_revision": 1, "sha256": Controller._digest(failure_server.bytes), "width": 24, "height": 24, "byte_length": failure_server.bytes.size(), "updated_at": "2026-09-15T00:00:00.000Z"}
	var no_disk := Controller.new(failure_server.request, Callable(), Callable(), first.current, Callable(), Callable(), DiskFailure.new())
	await no_disk.read_shared(ROOM, "t0-0-a", RECORDING)
	check(failure_server.downloads == 1 and failure_server.acks == 0 and failure_server.available, "disk failure never acknowledges or deletes remote image")
	await _payload_tombstone(folder, failure_server, first)
	await _old_receipt_tombstone(folder)
	print("Photo delivery client: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _payload_tombstone(folder: String, server: RefCounted, identity: RefCounted) -> void:
	var library := Library.new(folder + "/payload-race")
	check(library.store_cache(OWNER, ROOM, server.photo, server.bytes).get("durable", false), "race starts with actual prior JPEG cached")
	server.photo.photo_revision += 1 # Delivery advertises a new version, forcing GET.
	server.delete_on_payload = true
	var client := Controller.new(server.request, Callable(), Callable(), identity.current, Callable(), Callable(), library)
	var result: Dictionary = await client.read_shared(ROOM, "t0-0-a", RECORDING)
	check(result.get("bytes", PackedByteArray()).is_empty() and server.deleted, "deletion between metadata and JPEG response hides the bubble")
	server.offline = true
	client = Controller.new(server.request, Callable(), Callable(), identity.current, Callable(), Callable(), Library.new(folder + "/payload-race"))
	check((await client.read_shared(ROOM, "t0-0-a", RECORDING)).is_empty(), "full-GET tombstone survives cold offline reopen")

func _old_receipt_tombstone(folder: String) -> void:
	var server := PhotoFixtures.Server.new()
	var local := PhotoFixtures.Local.new()
	var image := Image.create(32, 24, false, Image.FORMAT_RGB8)
	image.fill(Color("82c8bc"))
	local.bytes = image.save_jpg_to_buffer(0.7)
	var store := PhotoFixtures.Store.new()
	var identity := PhotoFixtures.Identity.new()
	var library := Library.new(folder + "/receipt-race")
	var transport := func(request: Dictionary) -> Dictionary:
		if request.path.ends_with("/delivery"): return {"ok": false, "status": 404, "code": "not_found"}
		return await server.request(request)
	var key := func() -> String: return "receipt-tombstone-request"
	var client := Controller.new(transport, store.load_scope, store.save_scope, identity.current, local.request, key, library)
	check(await client.open_owned_turn(PhotoFixtures.ROOM, PhotoFixtures.GAME_KEY) and client.choose_local(local.metadata(), client.selection_context()), "real accepted-turn controller stages a kept JPEG")
	server.drop = true
	check(not await client.upload_selected() and not client.pending().is_empty(), "actual accepted upload receipt is lost and exact pending retained")
	check(library.store_cache(OWNER, PhotoFixtures.ROOM, server.photo, local.bytes).get("durable", false), "receipt race has an older downloaded local version")
	server.photo.photo_revision += 1
	server.photo.sha256 = null
	server.photo.width = null
	server.photo.height = null
	server.photo.byte_length = 0
	server.encoded = null
	check(await client.reconcile() and client.pending().is_empty(), "old upload receipt reconciles against a newer current deletion")
	check(not library.read_cache(OWNER, PhotoFixtures.ROOM, {"turn_id": "t0-0-a", "recording_hash": PhotoFixtures.RECORDING}).get("found", false), "newer tombstone from upload receipt prevents cached photo resurrection")
