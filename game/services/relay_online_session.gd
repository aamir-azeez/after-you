extends RefCounted
## App adapter: one API owner, durable lobby requests, and one active room.
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Store = preload("res://services/relay_online_store.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PhotoController = preload("res://services/turn_photo_controller.gd")
const PhotoStore = preload("res://services/turn_photo_store.gd")
var coordinator: RefCounted
var last_error := ""
var capabilities: Dictionary = {}
var _api: Node
var _identity: Callable
var _store: RefCounted
var _index: Dictionary = {}
var _index_loaded := false
var _bound_room := ""
var _owner := ""
var _epoch := -1
var _busy := false
var _generation := 0
var photo_store: RefCounted = PhotoStore.new()
var _photo_controllers: Array[WeakRef] = []

func _init(api: Node, identity: Callable, storage: RefCounted = null) -> void:
	_api = api
	_identity = identity
	_store = Store.new() if storage == null else storage

func invalidate_identity() -> void:
	_generation += 1
	for reference: WeakRef in _photo_controllers:
		var controller: RefCounted = reference.get_ref()
		if controller != null:
			controller.invalidate_identity()
	_photo_controllers.clear()
	if coordinator != null:
		coordinator.invalidate_identity()
	coordinator = null
	_index = {}
	_index_loaded = false
	_bound_room = ""
	_owner = ""
	_epoch = -1
	capabilities = {}
	_busy = false

func busy() -> bool:
	return _busy or (coordinator != null and coordinator.busy())

func mutations_enabled() -> bool:
	return _ready() and capabilities.get("mutations_enabled") == true

func room_ids() -> Array:
	return _index.get("room_ids", []).duplicate() if _ready() else []

func last_room() -> String:
	return str(_index.get("last_room", "")) if _ready() else ""

func pending_lobby() -> Dictionary:
	return _index.get("pending", {}).duplicate(true) if _ready() else {}

func invitation_code() -> String:
	if not _ready() or coordinator == null:
		return ""
	return verified_invitation(coordinator.snapshot(), _owner)

static func verified_invitation(room: Dictionary, owner: String) -> String:
	if room.get("api_version") != 2 or room.get("host_id") != owner or not room.get("invite_code") is String:
		return ""
	var code: String = room.invite_code
	var pattern := RegEx.new()
	pattern.compile("^[A-F0-9]{20}$")
	if pattern.search(code) == null or room.get("room_id") != ("v2:"+code).sha256_text().substr(0,22):
		return ""
	return code

func load_lobby() -> bool:
	if not _ready():
		return false
	var response := await _call(HTTPClient.METHOD_GET, "/v2/capabilities")
	if not response.get("ok", false):
		capabilities = {}
		return _failure(response, "Online Relay is not available from this service yet. Local chapter practice is still available.")
	var data: Variant = response.get("data")
	var supported := false
	if data is Dictionary and data.get("api_version") == 2 and data.get("simulation_version") == 2 and data.get("recording_version") == 2 and data.get("mutations_enabled") is bool and data.get("chapters") is Array and data.chapters.size() <= 16 and data.get("validation") == "structural_client_replay_required":
		for chapter: Variant in data.chapters:
			if chapter is Dictionary and chapter.get("level_id") == "relay-isles" and chapter.get("level_version") == 2 and chapter.get("definition_hash") == Canonical.digest(Catalog.relay_isles()):
				supported = true
	if not supported:
		capabilities = {}
		last_error = "This service needs a compatible Relay chapter. Your saved rooms are kept."
		return false
	capabilities = data.duplicate(true)
	response = await _call(HTTPClient.METHOD_GET, "/v2/rooms")
	if not response.get("ok", false):
		return _failure(response)
	var rooms: Variant = response.get("data", {}).get("rooms")
	if not rooms is Array or rooms.size() > 128:
		last_error = "The room list could not be verified. Saved rooms remain available."
		return false
	var next := _index.duplicate(true)
	for room: Variant in rooms:
		if not room is Dictionary or room.get("api_version") != 2 or not _id(room.get("room_id")) or _owner not in [room.get("host_id"), room.get("guest_id")]:
			last_error = "The room list contains unsupported data. Saved rooms are kept."
			return false
		if not room.room_id in next.room_ids:
			next.room_ids.append(room.room_id)
	return _write_index(next)

func create_room() -> String:
	if not _can_lobby_mutate():
		return ""
	if not _index.pending.is_empty():
		last_error = "Finish the saved create or join request first."
		return ""
	var body := {"idempotency_key": Crypto.new().generate_random_bytes(18).hex_encode(), "level_id": "relay-isles", "level_version": 2, "definition_hash": Canonical.digest(Catalog.relay_isles())}
	return await _start_lobby("/v2/rooms", body)

func join_room(code: String) -> String:
	if not _can_lobby_mutate():
		return ""
	var normalized := code.strip_edges().replace(" ", "").replace("-", "").to_upper()
	var pattern := RegEx.new()
	pattern.compile("^[A-F0-9]{20}$")
	if pattern.search(normalized) == null or not _index.pending.is_empty():
		last_error = "Check the invitation code, or finish your saved create/join request first."
		return ""
	return await _start_lobby("/v2/rooms/join", {"invite_code": normalized})

func _start_lobby(path: String, body: Dictionary) -> String:
	var next := _index.duplicate(true)
	next.pending = {"path": path, "body": body.duplicate(true), "request_hash": Canonical.digest({"path": path, "body": body})}
	if not _write_index(next):
		return ""
	return await retry_lobby()

func retry_lobby() -> String:
	if not _can_lobby_mutate() or _index.pending.is_empty():
		return ""
	var request: Dictionary = _index.pending.duplicate(true)
	var response := await _call(HTTPClient.METHOD_POST, request.path, request.body)
	if not response.get("ok", false):
		_failure(response)
		return ""
	var room: Variant = response.get("data")
	if not room is Dictionary or not _id(room.get("room_id")):
		last_error = "The service did not confirm a valid room. Retry this same saved request."
		return ""
	if request.path == "/v2/rooms/join" and room.room_id != ("v2:" + str(request.body.invite_code)).sha256_text().substr(0,22):
		last_error = "The returned room does not match your invitation. The saved request is kept."
		return ""
	# Creation/join acceptance alone cannot bypass the coordinator's full
	# native checkpoint validation. Keep the pending key until that read passes.
	if not await open_room(room.room_id):
		return ""
	var next := _index.duplicate(true)
	next.pending = {}
	return str(room.room_id) if _write_index(next) else ""

func open_room(room_id: String) -> bool:
	if not _ready() or busy() or not _id(room_id):
		return false
	# On restart restore the last room's lock before permitting a room switch.
	if coordinator == null and not _index.last_room.is_empty():
		coordinator = Coordinator.new(transport, _store.load_scope, _store.save_scope, _identity)
		if not _bind_room(_index.last_room):
			last_error = coordinator.last_error
			return false
	if coordinator != null and coordinator.read_only and room_id != _bound_room:
		last_error = "The current room's save could not be read. Reopen that same room to check it before switching."
		return false
	if coordinator != null and not coordinator.pending().is_empty() and room_id != _index.last_room:
		last_error = "Check the saved submission in your current Relay room before switching."
		return false
	if coordinator == null:
		coordinator = Coordinator.new(transport, _store.load_scope, _store.save_scope, _identity)
	# Remember the selected target before reading it: an unreadable target may
	# contain a pending request, so the same unknown-state hold must survive exit.
	var next := _index.duplicate(true)
	next.last_room = room_id
	if not room_id in next.room_ids:
		next.room_ids.append(room_id)
	if not _write_index(next):
		return false
	if not _bind_room(room_id):
		last_error = coordinator.last_error
		return false
	var success: bool = await coordinator.refresh()
	last_error = coordinator.last_error
	return success

func _bind_room(room_id: String) -> bool:
	_bound_room = room_id
	return coordinator.bind_room(room_id)

func transport(request: Dictionary) -> Dictionary:
	if not _ready() or request.get("owner_player_id") != _owner or request.get("identity_epoch") != _epoch:
		return {"ok": false, "status": 401, "code": "identity_changed"}
	if request.method == HTTPClient.METHOD_POST and not mutations_enabled():
		return {"ok": false, "status": 503, "code": "v2_mutations_disabled"}
	return await _call(request.method, request.path, request.body)

func chapter_pairs() -> Array:
	if not _ready() or coordinator == null:
		return []
	var checkpoint: Dictionary = coordinator.checkpoint()
	var pairs: Array = []
	# The coordinator already replay-verifies this exact bounded proof chain.
	for _index_value in range(2):
		if checkpoint.get("stage_index", 0) == 0:
			break
		var proof: Dictionary = checkpoint.proof
		pairs.push_front({"a": proof.a.duplicate(true), "b": proof.b.duplicate(true)})
		checkpoint = proof.previous_checkpoint
	return pairs

func create_photo_controller(local_io: Callable) -> RefCounted:
	# Photo state is deliberately outside lobby/gameplay journals.
	var controller := PhotoController.new(transport, photo_store.load_scope, photo_store.save_scope, _identity, local_io)
	_photo_controllers = _photo_controllers.filter(func(reference: WeakRef) -> bool: return reference.get_ref() != null)
	_photo_controllers.append(weakref(controller))
	return controller

func photo_identity() -> Dictionary:
	var identity: Dictionary = _identity.call()
	return {"ready": bool(identity.get("ready", false)), "player_id": str(identity.get("player_id", "")), "epoch": int(identity.get("epoch", -1))}

func local_photo_key(room: String, turn: String, recording_hash: String) -> String:
	if not _ready() or not PhotoController._id(room) or not PhotoController._turn(turn) or not PhotoController._hash(recording_hash):
		return ""
	var scope := "turn-photo-v1:" + _owner + ":" + room + ":" + turn
	var loaded: Dictionary = photo_store.load_scope(scope)
	var value: Variant = loaded.get("value", {})
	if not loaded.get("ok", false) or not loaded.get("found", false) or not value is Dictionary or value.get("schema_version") != 1 or not value.get("target") is Dictionary:
		return ""
	var target: Dictionary = value.target
	if target.get("room_id") != room or target.get("owner_player_id") != _owner or target.get("turn_id") != turn or target.get("recording_hash") != recording_hash or not PhotoController._key(target.get("gameplay_key")):
		return ""
	# This is only a lookup hint. open_owned_turn re-fetches the authoritative
	# caller-scoped gameplay receipt before granting photo mutation access.
	return target.gameplay_key

func replay_photo_turns(index: int, pair: Dictionary) -> Array:
	if not _ready() or coordinator == null:
		return []
	var room: Dictionary = coordinator.snapshot()
	var pairs: Array = chapter_pairs()
	if index < 0 or index >= pairs.size() or not Canonical.same(pair, pairs[index]) or index >= room.get("completed_pair_ids", []).size():
		return []
	var pair_id: String = room.completed_pair_ids[index]
	if not PhotoController._turn("t" + pair_id.substr(1) + "-a") or int(pair_id.get_slice("-", 1)) != index:
		return []
	var result: Array = []
	for role: String in ["a", "b"]:
		var recording: Dictionary = pair[role]
		var player: String = str(room.host_id if recording.player_slot == "p0" else room.guest_id)
		result.append({"room_id": room.room_id, "turn_id": "t" + pair_id.substr(1) + "-" + role, "recording_hash": recording.recording_hash, "owner_player_id": player, "own": player == _owner, "role": role, "player_slot": recording.player_slot})
	return result

func _call(method: int, path: String, body: Dictionary = {}) -> Dictionary:
	if not _ready() or _busy or _api.busy or _api.player_id != _owner or str(_api.device_token).is_empty():
		return {"ok": false, "status": 0, "code": "request_busy"}
	var generation := _generation
	var owner := _owner
	var epoch := _epoch
	_busy = true
	# request_json captures these verified headers synchronously before await.
	var response: Dictionary = await _api.request_json(method, path, body)
	if generation == _generation:
		_busy = false
	var identity: Dictionary = _identity.call()
	if generation != _generation or not identity.get("ready", false) or identity.get("player_id") != owner or identity.get("epoch") != epoch:
		return {"ok": false, "ignored": true, "status": 0, "code": "identity_changed"}
	return response

func _ready() -> bool:
	var identity: Dictionary = _identity.call()
	if not identity.get("ready", false) or not _id(identity.get("player_id")):
		last_error = "Load or recover your identity before opening online Relay."
		return false
	if _owner != identity.player_id or _epoch != int(identity.epoch):
		invalidate_identity()
		_owner = identity.player_id
		_epoch = int(identity.epoch)
	if not _index_loaded:
		var loaded: Dictionary = _store.load_scope("relay-lobby-v2:" + _owner)
		if not loaded.get("ok", false):
			last_error = "The saved Relay room list could not be read. It has not been replaced."
			return false
		var value: Variant = loaded.get("value", {}) if loaded.get("found", false) else {"schema_version": 1, "owner_player_id": _owner, "room_ids": [], "last_room": "", "pending": {}}
		if not value is Dictionary or not _valid_index(value):
			last_error = "This saved room list needs a compatible app. Its data is kept unchanged."
			return false
		_index = value.duplicate(true)
		_index_loaded = true
	if not _valid_index(_index):
		last_error = "This saved room list needs a compatible app. Its data is kept unchanged."
		return false
	return true

func _can_lobby_mutate() -> bool:
	if not _ready() or busy() or not mutations_enabled():
		last_error = "Online Relay creation and submissions are currently unavailable. Existing rooms and solo practice are kept."
		return false
	if coordinator == null and not _index.last_room.is_empty():
		coordinator = Coordinator.new(transport, _store.load_scope, _store.save_scope, _identity)
		if not _bind_room(_index.last_room):
			last_error = coordinator.last_error
			return false
	if coordinator != null and coordinator.read_only:
		last_error = "The current room's save could not be read. Reopen that same room before creating or joining another."
		return false
	if coordinator != null and not coordinator.pending().is_empty():
		last_error = "Check the current room's saved submission first."
		return false
	return true

func _write_index(next: Dictionary) -> bool:
	if not _ready() or not _valid_index(next):
		return false
	var generation := _generation
	if not _store.save_scope("relay-lobby-v2:" + _owner, next).get("ok", false):
		last_error = "Could not save the room request on this device. No saved request was discarded."
		return false
	if generation != _generation or not _ready():
		return false
	_index = next.duplicate(true)
	last_error = ""
	return true

func _valid_index(value: Dictionary) -> bool:
	if not Coordinator._bounded(value, 32768) or value.size() != 5 or value.get("schema_version") != 1 or value.get("owner_player_id") != _owner or not value.get("room_ids") is Array or value.room_ids.size() > 128 or not value.get("last_room") is String or (value.last_room != "" and not _id(value.last_room)) or not value.get("pending") is Dictionary:
		return false
	for room: Variant in value.room_ids:
		if not _id(room):
			return false
	var pending: Dictionary = value.pending
	if pending.is_empty():
		return true
	if pending.size() != 3 or pending.get("path") not in ["/v2/rooms", "/v2/rooms/join"] or not pending.get("body") is Dictionary or pending.get("request_hash") != Canonical.digest({"path": pending.path, "body": pending.body}):
		return false
	var body: Dictionary = pending.body
	if pending.path == "/v2/rooms":
		return body.size() == 4 and body.get("idempotency_key") is String and body.idempotency_key.length() == 36 and body.get("level_id") == "relay-isles" and body.get("level_version") == 2 and body.get("definition_hash") == Canonical.digest(Catalog.relay_isles())
	return body.size() == 1 and body.get("invite_code") is String and body.invite_code.length() == 20

func _failure(response: Dictionary, fallback: String = "") -> bool:
	last_error = fallback if fallback != "" else str(response.get("error", "The connection was interrupted. Retry the saved request; no recording was discarded."))
	return false

static func _id(value: Variant) -> bool:
	if not value is String or value.length() != 22:
		return false
	for character: String in value:
		if character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true
