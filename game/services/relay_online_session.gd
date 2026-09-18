extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
## App adapter: one API owner, durable lobby requests, and one active room.
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Store = preload("res://services/relay_online_store.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PhotoController = preload("res://services/turn_photo_controller.gd")
const PhotoStore = preload("res://services/turn_photo_store.gd")
const PhotoLibrary = preload("res://services/turn_photo_library.gd")
const Safety = preload("res://services/safety_client.gd")
var coordinator: RefCounted
var last_error := ""
var capabilities: Dictionary = {}
var _supported_chapters: Array[Dictionary] = []
var _room_chapters: Dictionary = {}
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
var photo_library: RefCounted = PhotoLibrary.new()
var _photo_controllers: Array[WeakRef] = []
var _safety: RefCounted

func _init(api: Node, identity: Callable, storage: RefCounted = null) -> void:
	_api = api
	_identity = identity
	_store = Store.new() if storage == null else storage

func invalidate_identity() -> void:
	if _safety != null: _safety.invalidate()
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
	_supported_chapters.clear()
	_room_chapters.clear()
	_busy = false

func busy() -> bool:
	return _busy or (coordinator != null and coordinator.busy())

func photo_request_busy() -> bool:
	# Optional editing shares the existing single-request API with replay reads.
	return busy() or not is_instance_valid(_api) or _api.busy

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
		_supported_chapters.clear()
		return _failure(response, PlayerCopy.RELAY_ONLINE_SESSION_268ED4C8A12F)
	var data: Variant = response.get("data")
	var checked := Registry.supported_capabilities(data)
	if not checked.valid:
		capabilities = {}
		_supported_chapters.clear()
		last_error = checked.error
		return false
	capabilities = data.duplicate(true)
	_supported_chapters.assign(checked.chapters)
	if coordinator != null: coordinator.supported_simulation_versions = _simulation_versions()
	response = await _call(HTTPClient.METHOD_GET, "/v2/rooms")
	if not response.get("ok", false):
		return _failure(response)
	var rooms: Variant = response.get("data", {}).get("rooms")
	if not rooms is Array or rooms.size() > 128:
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_58EDF3D26999
		return false
	var next := _index.duplicate(true)
	var observed: Dictionary = {}
	for room: Variant in rooms:
		if not room is Dictionary or room.get("api_version") != 2 or not _id(room.get("room_id")) or _owner not in [room.get("host_id"), room.get("guest_id")]:
			last_error = PlayerCopy.RELAY_ONLINE_SESSION_EDC8E84089EF
			return false
		observed[room.room_id] = Registry.resolve(room)
		if not room.room_id in next.room_ids:
			next.room_ids.append(room.room_id)
	if not _write_index(next): return false
	_room_chapters = observed
	return true

func _simulation_versions() -> Dictionary:
	var result: Dictionary = {}
	for item: Dictionary in _supported_chapters:
		result[item.key] = item.simulation_version
	return result

func supported_chapters() -> Array[Dictionary]:
	return _supported_chapters.duplicate(true) if _ready() else []

func supports_creation(chapter: String) -> bool:
	if not mutations_enabled(): return false
	for item: Dictionary in _supported_chapters:
		if item.key == chapter: return true
	return false

func room_title(room_id: String) -> String:
	var chapter := str(_room_chapters.get(room_id, ""))
	if chapter.is_empty() and coordinator != null and coordinator.snapshot().get("room_id") == room_id:
		chapter = coordinator.chapter_key()
	return str(Registry.descriptor(chapter).get("title", "Saved chapter"))

func chapter_key() -> String:
	return coordinator.chapter_key() if _ready() and coordinator != null else ""

func can_leave_for_legacy() -> bool:
	# A legacy join must not bypass a durable chapter request after restart.
	# This is a local scope read only; it never probes another join endpoint.
	if not _ready() or busy():
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_78B4A09B905D
		return false
	if not _index.pending.is_empty():
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_800EE194F524
		return false
	if coordinator == null and not _index.last_room.is_empty():
		coordinator = Coordinator.new(transport, _store.load_scope, _store.save_scope, _identity)
		coordinator.supported_simulation_versions = _simulation_versions()
		if not _bind_room(_index.last_room):
			last_error = coordinator.last_error
			return false
	if coordinator != null and (coordinator.read_only or not coordinator.pending().is_empty()):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_1BE2F671819A
		return false
	return true

func create_room(chapter: String = Registry.RELAY) -> String:
	if not _can_lobby_mutate():
		return ""
	if not supports_creation(chapter):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_7805B3DE8AEB
		return ""
	if not _index.pending.is_empty():
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_8C3AC7311985
		return ""
	var chosen := Registry.descriptor(chapter)
	var body := {"idempotency_key": Crypto.new().generate_random_bytes(18).hex_encode(), "level_id": chosen.level_id, "level_version": chosen.level_version, "definition_hash": chosen.definition_hash}
	if chapter == Registry.FIRST_STEPS and _simulation_versions().get(chapter) == 5:
		body["simulation_version"] = 5
	return await _start_lobby("/v2/rooms", body)

func join_room(code: String) -> String:
	if not _can_lobby_mutate():
		return ""
	var normalized := code.strip_edges().replace(" ", "").replace("-", "").to_upper()
	var pattern := RegEx.new()
	pattern.compile("^[A-F0-9]{20}$")
	if pattern.search(normalized) == null or not _index.pending.is_empty():
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_DA1FB43C8998
		return ""
	var body := {"invite_code": normalized}
	if _simulation_versions().get(Registry.FIRST_STEPS) == 5:
		body["supported_simulation_versions"] = [2, 4, 5]
	return await _start_lobby("/v2/rooms/join", body)

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
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_C0AD24FCB05A
		return ""
	if request.path == "/v2/rooms" and Registry.resolve(room) != Registry.resolve(request.body):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_A992AB428735
		return ""
	if request.path == "/v2/rooms/join" and room.room_id != ("v2:" + str(request.body.invite_code)).sha256_text().substr(0,22):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_22A1E8B58248
		return ""
	# Creation/join acceptance alone cannot bypass the coordinator's full
	# native checkpoint validation. Keep the pending key until that read passes.
	if not await open_room(room.room_id):
		return ""
	if request.path == "/v2/rooms" and (coordinator.chapter_key() != Registry.resolve(request.body) or coordinator.snapshot().get("simulation_version") != request.body.get("simulation_version")):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_DD6B81F86F45
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
		coordinator.supported_simulation_versions = _simulation_versions()
		if not _bind_room(_index.last_room):
			last_error = coordinator.last_error
			return false
	if coordinator != null and coordinator.read_only and room_id != _bound_room:
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_28632F597E2A
		return false
	if coordinator != null and not coordinator.pending().is_empty() and room_id != _index.last_room:
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_9584CB32FD17
		return false
	if coordinator == null:
		coordinator = Coordinator.new(transport, _store.load_scope, _store.save_scope, _identity)
		coordinator.supported_simulation_versions = _simulation_versions()
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
		checkpoint = Registry.previous_checkpoint(coordinator.chapter_key(), checkpoint)
	return pairs

func create_photo_controller(local_io: Callable) -> RefCounted:
	# Photo state is deliberately outside lobby/gameplay journals.
	# Bind before registering: the initial identity bind invalidates old controllers
	# and must not cancel this controller during its first photo request.
	_ready()
	var controller := PhotoController.new(transport, photo_store.load_scope, photo_store.save_scope, _identity, local_io, Callable(), photo_library)
	_photo_controllers = _photo_controllers.filter(func(reference: WeakRef) -> bool: return reference.get_ref() != null)
	_photo_controllers.append(weakref(controller))
	return controller

func photo_identity() -> Dictionary:
	var identity: Dictionary = _identity.call()
	return {"ready": bool(identity.get("ready", false)), "player_id": str(identity.get("player_id", "")), "epoch": int(identity.get("epoch", -1))}

func remember_photo_receipt(reference: Dictionary) -> bool:
	# Persist the already accepted gameplay receipt before cancellable photo I/O.
	# This is only a lookup hint: the controller still fetches the authenticated
	# caller-scoped receipt before it can offer an upload or deletion.
	if not _ready() or not PhotoController._id(reference.get("room_id")) or not PhotoController._turn(reference.get("turn_id")) or not PhotoController._hash(reference.get("recording_hash")) or not PhotoController._key(reference.get("idempotency_key")):
		return _photo_hint_error()
	var room: String = reference.room_id
	var turn: String = reference.turn_id
	var key: String = reference.idempotency_key
	var accepted: Dictionary = coordinator.last_receipt() if coordinator != null else {}
	if not Canonical.same(reference, accepted):
		# Historical replay references can reuse an existing scoped hint, but
		# cannot manufacture a new one from an arbitrary offer/reference object.
		if local_photo_key(room, turn, reference.recording_hash) == key:
			return true
		return _photo_hint_error()
	var snapshot: Dictionary = coordinator.snapshot()
	var target := _photo_hint_target(accepted, snapshot)
	if target.is_empty():
		return _photo_hint_error()
	var scope := "turn-photo-v1:" + _owner + ":" + room + ":" + turn
	var loaded: Dictionary = photo_store.load_scope(scope)
	if not loaded.get("ok", false):
		return _photo_hint_error()
	if loaded.get("found", false):
		var existing: Variant = loaded.get("value")
		# Never replace a selection, cleanup queue, uncertain request or unknown
		# journal. An already matching hint needs no write at all.
		if existing is Dictionary and existing.get("schema_version") == 1 and Canonical.same(existing.get("target"), target):
			return true
		return _photo_hint_error()
	var value := {"schema_version": 1, "target": target, "selection": {}, "pending": {}, "cleanup": [], "last_receipt": {}}
	var saved: Dictionary = photo_store.save_scope(scope, value)
	if not saved.get("ok", false):
		return _photo_hint_error()
	return true

func _photo_hint_target(receipt: Dictionary, room: Dictionary) -> Dictionary:
	# The reference must equal the coordinator's accepted receipt above. Keep
	# the owner/chapter/turn checks explicit even for restored local receipts.
	if not PhotoController._exact(receipt, Coordinator.RECEIPT_KEYS) or receipt.schema_version != 2 or receipt.operation != "turns" or not PhotoController._hash(receipt.request_hash) or not PhotoController._hash(receipt.checkpoint_hash) or not PhotoController._range(receipt.branch, 0, 31) or not PhotoController._range(receipt.stage_index, 0, 1) or not PhotoController._range(receipt.accepted_revision, 1, 256):
		return {}
	var chapter := Registry.resolve(room)
	if chapter.is_empty() or room.get("api_version") != 2 or room.get("schema_version") != 2 or room.get("room_id") != receipt.room_id or not PhotoController._range(room.get("revision"), int(receipt.accepted_revision), 256) or _owner not in [room.get("host_id"), room.get("guest_id")]:
		return {}
	var level := Registry.definition(chapter)
	var index := int(receipt.stage_index)
	var role: String = str(receipt.turn_id).right(1)
	if receipt.turn_id != "t%d-%d-%s" % [int(receipt.branch), index, role] or receipt.stage_id != level.stages[index].id or receipt.pair_id != ("p%d-%d" % [int(receipt.branch), index] if role == "b" else null):
		return {}
	var first: Variant = room.get("host_id") if level.stages[index].first_player_slot == "p0" else room.get("guest_id")
	var second: Variant = room.get("guest_id") if level.stages[index].first_player_slot == "p0" else room.get("host_id")
	if _owner != (first if role == "a" else second):
		return {}
	return {"room_id": receipt.room_id, "turn_id": receipt.turn_id, "recording_hash": receipt.recording_hash, "owner_player_id": _owner, "branch": receipt.branch, "stage_index": index, "stage_id": receipt.stage_id, "role": role, "gameplay_key": receipt.idempotency_key}

func _photo_hint_error() -> bool:
	last_error = PlayerCopy.RELAY_ONLINE_SESSION_E8DD10D9AA25
	return false

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
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_96B0DAE51346
		return false
	if _owner != identity.player_id or _epoch != int(identity.epoch):
		invalidate_identity()
		_owner = identity.player_id
		_epoch = int(identity.epoch)
	if not _index_loaded:
		var loaded: Dictionary = _store.load_scope("relay-lobby-v2:" + _owner)
		if not loaded.get("ok", false):
			last_error = PlayerCopy.RELAY_ONLINE_SESSION_89150FD11B4C
			return false
		var value: Variant = loaded.get("value", {}) if loaded.get("found", false) else {"schema_version": 1, "owner_player_id": _owner, "room_ids": [], "last_room": "", "pending": {}}
		if not value is Dictionary or not _valid_index(value):
			last_error = PlayerCopy.RELAY_ONLINE_SESSION_A9B9B58DCC87
			return false
		_index = value.duplicate(true)
		_index_loaded = true
	if not _valid_index(_index):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_A9B9B58DCC87
		return false
	return true

func _can_lobby_mutate() -> bool:
	if not _ready() or busy() or not mutations_enabled():
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_D8B61E4543F4
		return false
	if coordinator == null and not _index.last_room.is_empty():
		coordinator = Coordinator.new(transport, _store.load_scope, _store.save_scope, _identity)
		coordinator.supported_simulation_versions = _simulation_versions()
		if not _bind_room(_index.last_room):
			last_error = coordinator.last_error
			return false
	if coordinator != null and coordinator.read_only:
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_93A87697D639
		return false
	if coordinator != null and not coordinator.pending().is_empty():
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_D442C4316FCF
		return false
	return true

func _write_index(next: Dictionary) -> bool:
	if not _ready() or not _valid_index(next):
		return false
	var generation := _generation
	if not _store.save_scope("relay-lobby-v2:" + _owner, next).get("ok", false):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_E491F4F0F93A
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
		var optional_pin: bool = body.has("simulation_version")
		return body.size() == (5 if optional_pin else 4) and body.get("idempotency_key") is String and body.idempotency_key.length() == 36 and not Registry.resolve(body).is_empty() and (not optional_pin or (Registry.resolve(body) == Registry.FIRST_STEPS and body.simulation_version == 5))
	var optional_versions: bool = body.has("supported_simulation_versions")
	return body.size() == (2 if optional_versions else 1) and body.get("invite_code") is String and body.invite_code.length() == 20 and (not optional_versions or Canonical.same(body.supported_simulation_versions, [2, 4, 5]))

func _failure(response: Dictionary, fallback: String = "") -> bool:
	last_error = fallback if fallback != "" else str(response.get("error", PlayerCopy.RELAY_ONLINE_SESSION_9C59ACB8FC3A))
	return false

static func _id(value: Variant) -> bool:
	if not value is String or value.length() != 22:
		return false
	for character: String in value:
		if character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true

func safety_client() -> RefCounted:
	_ready()
	if _safety == null: _safety = Safety.new(_api, _identity)
	return _safety

func safety_context() -> Dictionary:
	if not _ready() or coordinator == null: return {}
	var room: Dictionary = coordinator.snapshot()
	var peer: Variant = room.get("guest_id") if room.get("host_id") == _owner else room.get("host_id")
	return {"room_family": "relay", "room_id": room.get("room_id"), "peer_id": peer} if Safety.Store.id(peer) else {}

func partner_photos_allowed(reference: Dictionary) -> bool:
	if reference.get("own", false): return true
	if not _ready(): return false
	return Safety.Store.new().partner_allowed(_owner, "relay", str(reference.get("room_id", "")), str(reference.get("owner_player_id", "")))
