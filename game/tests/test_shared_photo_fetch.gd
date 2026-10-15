extends SceneTree
## A finished room's replay plays from this phone. The friend's turn photos must
## reach the photo library on their own: after the replay is saved and when a
## Together room opens, asking only for the friend's turns not saved here.
const Controller = preload("res://services/turn_photo_controller.gd")
const SharedReplayView = preload("res://presentation/shared_replay_view.gd")
const TouchInput = preload("res://presentation/touch_input.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "WWWWWWWWWWWWWWWWWWWWWW"

class Main extends "res://main.gd":
	var test_identity := {"ready": true, "player_id": HOST, "epoch": 1}
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _exit_tree() -> void: pass
	func _relay_identity() -> Dictionary: return test_identity.duplicate(true)
	func _campaign_media_factory() -> RefCounted: return null
	func _production_replay_key_allowed(_key: String) -> bool: return true
	var draws := 0
	func _draw_shared_replay_memories(_rows: Array, _message: String = "") -> void: draws += 1

class Replays extends RefCounted:
	var entries: Array = []
	func local_entries(_key: String) -> Array: return entries.duplicate(true)
	func memories(_key: String, _cached: bool = false) -> Array: return []
	func listed(_key: String) -> Array: return []
	func busy() -> bool: return false

## Serves the guest's photo for stage one, A side; the guest took none in stage two.
class Server extends Node:
	var player_id := HOST
	var device_token := "token"
	var base_url := "https://photos.test"
	var busy := false
	var photo: Dictionary = {}
	var bytes := PackedByteArray()
	var acked: Array = [GUEST]
	var paths: Array[String] = []
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		paths.append(("POST " if method == HTTPClient.METHOD_POST else "GET ") + path)
		var turn := path.get_slice("/photos/", 1).get_slice("/", 0)
		if turn != photo.turn_id: return {"ok": false, "status": 404, "code": "not_found"}
		if path.ends_with("/delivery"): return _ok(_delivery())
		if path.ends_with("/ack"):
			if body.get("sha256") != photo.sha256: return {"ok": false, "status": 409, "code": "stale_photo_ack"}
			if player_id not in acked: acked.append(player_id)
			var result := _delivery()
			result.acked = true
			return _ok(result)
		return _ok({"photo": photo, "jpeg_base64": Marshalls.raw_to_base64(bytes)})
	func _delivery() -> Dictionary:
		var available := acked.size() < 2
		return {"schema_version": 1, "photo": photo, "available": available, "removed_reason": null if available else "delivered", "intended_player_ids": [HOST, GUEST], "acked_player_ids": acked.duplicate()}
	func _ok(value: Dictionary) -> Dictionary: return {"ok": true, "status": 200, "data": value.duplicate(true)}

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _hash(seed: String) -> String: return seed.sha256_text()

## Two stages: the host plays stage one first and the guest stage two first.
func _entries() -> Array:
	var room := {"family": "chapter", "room_id": ROOM, "host_id": HOST, "guest_id": GUEST, "chapter_key": "the-wishing-well@1", "title": "The Wishing Well"}
	return [
		{"schema_version": 1, "room": room, "pair": {"pair_id": "p0-0", "a": {"role": "a", "player_slot": "p0", "recording_hash": _hash("0a")}, "b": {"role": "b", "player_slot": "p1", "recording_hash": _hash("0b")}}},
		{"schema_version": 1, "room": room, "pair": {"pair_id": "p0-1", "a": {"role": "a", "player_slot": "p1", "recording_hash": _hash("1a")}, "b": {"role": "b", "player_slot": "p0", "recording_hash": _hash("1b")}}},
	]

func _app(server: Server) -> Main:
	var app := Main.new()
	app.api = server
	app.add_child(server)
	var replays := Replays.new()
	replays.entries = _entries()
	app.shared_replays = replays
	root.add_child(app)
	return app

func _saved(app: Main, turn: String, recording: String) -> bool:
	var session := SharedReplayView.ReadSession.new(app.api, app._relay_identity)
	var local: RefCounted = session.create_photo_controller(Callable())
	var found: Dictionary = await local.read_shared(ROOM, turn, recording)
	return not found.get("bytes", PackedByteArray()).is_empty()

## A friend photo that lands while a finger is on the Together page redraws the
## page only after the finger lifts, and not at all once the page moved on.
func _no_redraw_under_finger(app: Main, server: Server) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var overlay := Control.new()
	overlay.size = Vector2(400, 300)
	viewport.add_child(overlay)
	var row := Button.new()
	row.position = Vector2(20, 20)
	row.size = Vector2(160, 60)
	overlay.add_child(row)
	app.overlay = overlay
	app.mode = "shared_memories"
	app.shared_replay_room = "chapter:" + ROOM
	await process_frame
	var key := "chapter:" + ROOM
	# A fresh photo for the friend's other turn, not on this phone yet.
	server.acked = [GUEST]
	server.photo.turn_id = "t0-1-a"
	server.photo.recording_hash = _hash("1a")
	app._shared_photo_checked.clear()
	_pointer(viewport, row.position + row.size / 2.0, true)
	await process_frame
	_check(TouchInput.press_held(overlay), "The finger is down on a Together row")
	var draws := app.draws
	app._fetch_missing_shared_photos(key)
	for frame in range(12): await process_frame
	_check(app.draws == draws, "A photo that lands under the finger does not rebuild the page")
	_pointer(viewport, row.position + row.size / 2.0, false)
	for frame in range(4): await process_frame
	_check(app.draws == draws + 1, "The page redraws once the finger lifts")
	# The page moves on while the finger is down: nothing is redrawn after.
	_pointer(viewport, row.position + row.size / 2.0, true)
	await process_frame
	draws = app.draws
	app._redraw_shared_room(app._shared_room_context(true))
	app.mode = "home"
	_pointer(viewport, row.position + row.size / 2.0, false)
	for frame in range(4): await process_frame
	_check(app.draws == draws, "A redraw that waited is dropped when the page moved on")
	viewport.queue_free()

func _pointer(viewport: SubViewport, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)

func _run() -> void:
	var server := Server.new()
	var image := Image.create(24, 24, false, Image.FORMAT_RGB8)
	image.fill(Color("8fc7d9"))
	server.bytes = image.save_jpg_to_buffer(0.7)
	server.photo = {"schema_version": 1, "turn_id": "t0-0-b", "owner_player_id": GUEST, "recording_hash": _hash("0b"), "photo_revision": 1, "sha256": Controller._digest(server.bytes), "width": 24, "height": 24, "byte_length": server.bytes.size(), "updated_at": "2026-10-13T20:00:00.000Z"}
	var app := _app(server)
	_check(not await _saved(app, "t0-0-b", _hash("0b")), "The friend's photo starts off this phone")
	var first: Dictionary = await app._fetch_shared_room_photos("chapter:" + ROOM, true)
	_check(first.get("fetched") == 1, "One friend photo arrives: %s" % [first])
	_check(await _saved(app, "t0-0-b", _hash("0b")), "The friend's photo is saved in this phone's library for the replay")
	_check(server.paths.has("POST /v2/rooms/%s/photos/t0-0-b/ack" % ROOM) and HOST in server.acked, "The saved photo is acknowledged so the server can let it go: %s" % [server.paths])
	for own: String in ["t0-0-a", "t0-1-b"]:
		_check(not server.paths.any(func(path: String) -> bool: return path.contains("/photos/" + own)), "The player's own turn %s is never asked for" % own)
	_check(not app._shared_photo_sync, "The fetch releases its hold when it ends")
	server.paths.clear()
	await app._fetch_shared_room_photos("chapter:" + ROOM, true)
	_check(not server.paths.any(func(path: String) -> bool: return path.contains("/photos/t0-0-b")), "A photo already saved is not asked for again: %s" % [server.paths])
	_check(server.paths.any(func(path: String) -> bool: return path.contains("/photos/t0-1-a")), "A friend turn with nothing saved is still looked up")
	# Opening a Together room looks once per session, without waiting on it.
	server.paths.clear()
	await app._fetch_missing_shared_photos("chapter:" + ROOM)
	var opened := server.paths.size()
	await app._fetch_missing_shared_photos("chapter:" + ROOM)
	_check(opened > 0 and server.paths.size() == opened, "A Together room asks for missing photos once a session: %s" % [server.paths])
	# The player waits behind the API rather than breaking another request.
	server.paths.clear()
	app._shared_photo_checked.clear()
	server.busy = true
	app._fetch_missing_shared_photos("chapter:" + ROOM)
	for frame in range(20): await process_frame
	_check(server.paths.is_empty(), "No photo request starts while the API is busy")
	server.busy = false
	var deadline := Time.get_ticks_msec() + 5000
	while app._shared_photo_sync and Time.get_ticks_msec() < deadline: await process_frame
	_check(not server.paths.is_empty() and not app._shared_photo_sync, "The photo request goes once the API is free")
	await _no_redraw_under_finger(app, server)
	app.queue_free()
	await process_frame
	print("SHARED PHOTO FETCH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
