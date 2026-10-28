extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
## App adapter: one API owner, durable lobby requests, and one active room.
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Store = preload("res://services/relay_online_store.gd")
const Registry = preload("res://services/chapter_registry.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PhotoController = preload("res://services/turn_photo_controller.gd")
const PhotoStore = preload("res://services/turn_photo_store.gd")
const PhotoLibrary = preload("res://services/turn_photo_library.gd")
const Safety = preload("res://services/safety_client.gd")
const AuxiliaryContext = preload("res://services/auxiliary_room_context.gd")
const RedoClient = preload("res://services/redo_client.gd")
const HardRoomClient = preload("res://services/hard_room_client.gd")
const ReplayTransfer = preload("res://services/replay_transfer.gd")
const HistorySync = preload("res://services/history_sync.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const ShareCodes = preload("res://services/share_codes.gd")
const RoomStages = preload("res://services/room_stages.gd")
const Typed = preload("res://services/typed_values.gd")
const DisplayNames = preload("res://services/display_names.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenGrant = preload("res://services/pollen_grant.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const TurnLooks = preload("res://services/turn_looks.gd")
const OwnLook = preload("res://services/own_look.gd")
## Every rules version this build can replay, for a server that allows at most
## 8 entries (every server before room level 2): 10 = the tide rules of
## turn-of-the-tide@2. Saved joins keep their exact body: each array ever sent
## stays listed in _valid_index.
const JOIN_SIMULATION_VERSIONS := [2, 4, 5, 6, 7, 8, 9, 10]
## Rules sent only to a server that answered room level 2 and accepts the
## longer list: 11 = sleeping-lighthouse@2, and chapters with more than two stages.
const ROOM_LEVEL_JOIN_VERSIONS := [11]

class RedoStorage:
	extends RefCounted
	var journal: RefCounted
	func _init(storage: RefCounted) -> void: journal = storage
	func read(scope: String) -> Dictionary: return journal.load_scope(scope)
	func write(scope: String, value: Dictionary) -> bool: return journal.save_scope(scope,value).get("ok",false)
var coordinator: RefCounted
var accepted_pair_cache: Callable
## () -> void: sends Pollen claims that wait (Main's PollenClient.flush), once capabilities say Pollen is on.
var pollen_flush: Callable
var replay_archive_cache: Callable
## (room facts, pairs) -> bool: adds parts of attempts this phone keeps to Replays.
var replay_history_cache: Callable
## Main's unlock progress (services/chapter_unlocks.gd), read when a join is
## sent: the join carries the chapters open to this player, and a refusal for
## a chapter past them names the one to ask the friend to host instead.
var join_unlocks: Callable
var last_error := ""
var capabilities: Dictionary = {}
var _supported_chapters: Array[Dictionary] = []
var _room_chapters: Dictionary = {}
var _room_summaries: Dictionary = {}
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
var _room_selection_generation := 0
var _opening := false
var _retiring_selection := false
var _auxiliary_factory: RefCounted
var photo_store: RefCounted = PhotoStore.new()
var photo_library: RefCounted = PhotoLibrary.new()
var _photo_controllers: Array[WeakRef] = []
var _safety: RefCounted
var _redo: RefCounted
var _hard: RefCounted
var _redo_read_key := ""
var _redo_read_result: Dictionary = {}
var _archived_room_evidence: Dictionary = {}
var _archived_evidence_lifetime: Dictionary = {}
var _released_room_note := ""
var _replay_transfer: RefCounted
var _transfer_busy := false
var _transferred_rooms: Dictionary = {}
var _history: RefCounted
## Tests may give the history client its own store.
var history_store: RefCounted

func _init(api: Node, identity: Callable, storage: RefCounted = null) -> void:
	_api = api
	_identity = identity
	_store = Store.new() if storage == null else storage

func invalidate_identity() -> void:
	if _replay_transfer != null: _replay_transfer.invalidate_identity()
	_transfer_busy = false
	_transferred_rooms.clear()
	_archived_room_evidence.clear()
	_archived_evidence_lifetime.clear()
	_released_room_note = ""
	_auxiliary_factory = null
	if _safety != null: _safety.invalidate()
	if _redo != null: _redo.invalidate()
	if _hard != null: _hard.invalidate()
	_redo_read_key = ""
	_redo_read_result = {}
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
	_room_summaries.clear()
	_busy = false
	_opening = false
	_retiring_selection = false

func busy() -> bool:
	return _transfer_busy or (_history != null and _history.busy()) or _retiring_selection or _opening or _busy or (coordinator != null and coordinator.busy()) or (_redo != null and _redo.busy)

func redo_client() -> RefCounted:
	_ready()
	if _redo == null:
		_redo = RedoClient.new(_api, _identity, RedoStorage.new(_store))
		_redo.restore_replay_transfer = restore_complete_replay
		_redo.recover_replay_operation = recover_transferred_operation
	return _redo

func pending_redo_room() -> String:
	if not _ready() or _index.last_room.is_empty(): return ""
	var room_id: String = _index.last_room
	if archived_room_kind(room_id) == "story": return ""
	var loaded := _load_redo_journal(room_id)
	return room_id if loaded.get("ok",false) and not loaded.value.get("pending",{}).is_empty() else ""

func photo_request_busy() -> bool:
	# Optional editing waits for this session's own request; the API queues the rest.
	return busy() or not is_instance_valid(_api)

func _server_key() -> String:
	return str(_api.base_url).sha256_text() if is_instance_valid(_api) and not str(_api.base_url).is_empty() else ""

func _transfer_client() -> RefCounted:
	if _replay_transfer == null: _replay_transfer = ReplayTransfer.new(_transfer_transport, _identity, _transfer_eligibility)
	return _replay_transfer

## Room history (replay transfer schema 2): this phone keeps finished attempts
## durably and the server says it serves them. Otherwise replay transfer v1 runs.
func history_mode() -> bool:
	return RoomsApi.history_supported and Typed.equal(capabilities.get("history_version"), 1.0)

## The server keeps a turn's try count beside it and lists a room's counts.
func turn_tries_supported() -> bool:
	return Typed.equal(capabilities.get("turn_tries_version"), 1.0)

## The server takes an end-of-run reaction with a turn and shows it to the
## friend (services/end_reaction_store.gd). Without it, rooms show no reactions.
func end_reactions_supported() -> bool:
	return Typed.equal(capabilities.get("end_reactions_version"), 1.0)

## The server takes a turn's reactions made during the run and plays them on
## the friend's memory (services/run_reaction_track.gd). Without it, a room
## turn shows no React pill and sends no track.
func run_reactions_supported() -> bool:
	return Typed.equal(capabilities.get("run_reactions_version"), 1.0)

## The server hosts hard rooms (services/hard_mode.gd).
func hard_mode_supported() -> bool:
	return Typed.equal(capabilities.get("hard_mode_version"), 1.0)

## A hard room's reset and failures reads (services/hard_room_client.gd).
func hard_client() -> RefCounted:
	_ready()
	if _hard == null: _hard = HardRoomClient.new(_api, _identity, _store)
	return _hard

func history_client() -> RefCounted:
	if _history == null: _history = HistorySync.new(_history_transport, _history_eligibility, history_store)
	return _history

## The pending-work checks replay transfer uses before an ACK. The server
## refuses history for Story rooms, so no local standalone proof is needed, and a
## phone with no journal for the room (recovered onto a new phone) has nothing pending.
func _history_eligibility(room_id: String) -> Dictionary:
	if not _ready() or _server_key().is_empty(): return {"ok": false}
	if archived_room_kind(room_id) == "story": return {"ok": false}
	var scope := _pending_work(room_id, false)
	scope.merge({"ok": true, "server_key": _server_key(), "owner": _owner, "standalone": true, "offload_enabled": Typed.equal(capabilities.get("history_offload_enabled"), true)}, true)
	return scope

func _history_transport(method: int, path: String, body: Variant, raw: bool) -> Dictionary:
	var key := _server_key()
	var response: Dictionary = await _call_raw(method, path, body if body is PackedByteArray else PackedByteArray()) if raw else await _call(method, path, body)
	return response if key == _server_key() else {"ok": false, "status": 0, "code": "replay_transfer_context_changed"}

## Downloads this room's finished attempts, confirms them when nothing is pending,
## and sends back any the friend's phone asked for.
func sync_room_history(room_id: String) -> Dictionary:
	if not _ready() or busy() or not history_mode(): return {"ok": false, "code": "replay_transfer_unavailable"}
	var generation := _generation
	var key := _server_key()
	_transfer_busy = true
	var result: Dictionary = await history_client().sync_room(room_id)
	if generation != _generation or key != _server_key(): return _finish_transfer(generation, {"ok": false, "code": "replay_transfer_context_changed"})
	if result.get("ok", false) and result.get("mode") == "attempts" and replay_history_cache.is_valid():
		# Replays keeps playing these parts once the server lets them go.
		var pairs: Array = history_client().local_pairs(key, _owner, result.view)
		if not pairs.is_empty() and await replay_history_cache.call(result.view.room, pairs) != true: result = {"ok": false, "code": "replay_cache_unsaved"}
		if generation != _generation or key != _server_key(): return _finish_transfer(generation, {"ok": false, "code": "replay_transfer_context_changed"})
	return _finish_transfer(generation, result)

## One part of a finished attempt this phone keeps, or {}.
func history_pair(room_id: String, chapter_key: String, pair_id: String) -> Dictionary:
	if not _ready() or _server_key().is_empty(): return {}
	return history_client().local_pair(_server_key(), _owner, room_id, chapter_key, pair_id)

## Asks the friend's phone, through the server, for an attempt this phone lacks.
func want_room_attempt(room_id: String, position: int) -> Dictionary:
	if not _ready() or busy() or not history_mode(): return {"ok": false, "code": "replay_transfer_unavailable"}
	_transfer_busy = true
	var generation := _generation
	var result: Dictionary = await history_client().want(room_id, position)
	return _finish_transfer(generation, result)

func _transfer_eligibility(room_id: String) -> Dictionary:
	if not _ready() or not standalone_room_proven(room_id) or _server_key().is_empty(): return {"ok": false}
	if archived_room_kind(room_id) == "story": return {"ok": false}
	var work := _pending_work(room_id, true)
	return {"ok": true, "server_key": _server_key(), "standalone": true, "gameplay_pending": work.gameplay_pending,
		"photo_pending": work.photo_pending, "redo_pending": work.redo_pending, "enabled": Typed.equal(capabilities.get("replay_transfer_version"), 1)}

## Gameplay, redo and photo work still waiting for this room. A room this phone
## has no journal for counts as pending unless `absent_is_pending` is false.
func _pending_work(room_id: String, absent_is_pending: bool) -> Dictionary:
	var gameplay_pending := true
	if coordinator != null and _bound_room == room_id:
		gameplay_pending = coordinator.busy() or not coordinator.pending().is_empty() or coordinator.read_only
	else:
		var saved: Dictionary = _store.load_scope("relay-room-v2:" + _owner + ":" + room_id)
		var state: Variant = saved.get("value")
		gameplay_pending = not saved.get("ok", false) or not state is Dictionary or not Coordinator._exact(state, Coordinator.STATE_KEYS) or not Typed.equal(state.get("schema_version"), 1) or not Typed.equal(state.get("owner_player_id"), _owner) or not Typed.equal(state.get("room_id"), room_id) or not Typed.equal(state.get("auth_required"), false) or not state.get("pending") is Dictionary or not state.pending.is_empty()
		if not absent_is_pending and saved.get("ok", false) and not saved.get("found", false): gameplay_pending = false
	gameplay_pending = gameplay_pending or not _index.get("pending", {}).is_empty()
	var redo := _load_redo_journal(room_id, true)
	var redo_pending: bool = not redo.get("ok", false) or not redo.get("value", {}).get("pending", {}).is_empty()
	if _redo != null and _redo.bound_room_id("relay") == room_id: redo_pending = redo_pending or _redo.busy or not _redo.pending().is_empty()
	var photos: Dictionary = photo_store.list_scopes(_owner)
	var photo_pending: bool = not photos.get("ok", false)
	for item: Dictionary in photos.get("scopes", []):
		if str(item.get("scope", "")).begins_with("turn-photo-v1:" + _owner + ":" + room_id + ":"):
			var value: Variant = item.get("value")
			if not value is Dictionary or not value.get("pending") is Dictionary or not value.get("cleanup") is Array or not value.pending.is_empty() or not value.cleanup.is_empty(): photo_pending = true
	for reference: WeakRef in _photo_controllers:
		var controller: RefCounted = reference.get_ref()
		if controller != null and controller.target().get("room_id") == room_id and (controller.busy() or not controller.pending().is_empty()): photo_pending = true
	return {"gameplay_pending": gameplay_pending, "photo_pending": photo_pending, "redo_pending": redo_pending}

func _transfer_transport(request: Dictionary) -> Dictionary:
	if not _ready() or request.get("owner_player_id") != _owner or request.get("identity_epoch") != _epoch:
		return {"ok": false, "code": "identity_changed"}
	# Restore and receipt recovery remain available when compaction is disabled.
	# The transfer helper separately gates ACK against the explicit capability.
	var key := _server_key()
	var response := await _call(request.method, request.path, request.body)
	return response if key == _server_key() else {"ok": false, "code": "replay_transfer_context_changed"}

func _finish_transfer(generation: int, result: Dictionary) -> Dictionary:
	if generation == _generation: _transfer_busy = false
	return result

func sync_complete_replay(room_id: String) -> Dictionary:
	if history_mode():
		var history: Dictionary = await sync_room_history(room_id)
		if history.get("mode") != "v1": return history
	if not _ready() or busy() or not replay_archive_cache.is_valid(): return {"ok": false, "code": "replay_transfer_unavailable"}
	var generation := _generation
	var key := _server_key()
	_transfer_busy = true
	var result: Dictionary = await _transfer_client().download(room_id)
	if generation != _generation or key != _server_key(): return _finish_transfer(generation, {"ok": false, "code": "replay_transfer_context_changed"})
	if result.get("ok", false):
		var adopted: Variant = replay_archive_cache.call(room_id, result.entries, result.manifest)
		if adopted != true:
			result = {"ok": false, "code": "replay_cache_unsaved"}
		elif generation == _generation and key == _server_key():
			_transferred_rooms[room_id] = {"manifest": result.manifest.duplicate(true), "server_key": key}
			var scope := _transfer_eligibility(room_id)
			if scope.get("ok", false) and scope.enabled and not scope.gameplay_pending and not scope.photo_pending and not scope.redo_pending:
				var ack: Dictionary = await _transfer_client().acknowledge(room_id, result.manifest)
				result = {"ok": ack.get("ok", false), "acknowledged": ack.get("ok", false), "code": ack.get("code", ""), "transferred": ack.get("transfer", {}).get("transferred", false)}
			else: result = {"ok": true, "acknowledged": false, "transferred": result.transferred}
	if generation != _generation or key != _server_key(): return _finish_transfer(generation, {"ok": false, "code": "replay_transfer_context_changed"})
	return _finish_transfer(generation, result)

func restore_complete_replay(room_id: String) -> Dictionary:
	if not _ready() or _transfer_busy: return {"ok": false, "code": "replay_transfer_unavailable"}
	var generation := _generation
	var owner := _owner
	var epoch := _epoch
	var key := _server_key()
	_transfer_busy = true
	var result := await _call(HTTPClient.METHOD_GET, "/v2/rooms/" + room_id)
	if not _restore_context_current(generation, owner, epoch, key): return _finish_transfer(generation, {"ok": false, "code": "replay_transfer_context_changed"})
	if result.get("status") == 410 and result.get("code") == "replay_transferred" and history_mode():
		# The finished room's last attempt left as room history: send this phone's copy back.
		result = await history_client().restore_final(room_id)
		if not _restore_context_current(generation, owner, epoch, key): return _finish_transfer(generation, {"ok": false, "code": "replay_transfer_context_changed"})
		if result.get("mode") != "v1_transferred": return _finish_transfer(generation, result)
		result = {"status": 410, "code": "replay_transferred"}
	if result.get("status") == 410 and result.get("code") == "replay_transferred":
		result = await _transfer_client().download(room_id)
		if not _restore_context_current(generation, owner, epoch, key): return _finish_transfer(generation, {"ok": false, "code": "replay_transfer_context_changed"})
		if result.get("ok", false) and result.transferred:
			result = await _transfer_client().restore(room_id, result.manifest)
	if not _restore_context_current(generation, owner, epoch, key): return _finish_transfer(generation, {"ok": false, "code": "replay_transfer_context_changed"})
	return _finish_transfer(generation, result)

func _restore_context_current(generation: int, owner: String, epoch: int, key: String) -> bool:
	var current: Variant = _identity.call() if _identity.is_valid() else null
	return generation == _generation and owner == _owner and epoch == _epoch and key == _server_key() and current is Dictionary and current.get("ready") == true and current.get("player_id") == owner and current.get("epoch") == epoch

func recover_transferred_operation(room_id: String, key: String, validate_receipt: Callable) -> Dictionary:
	if not _ready() or _transfer_busy or not validate_receipt.is_valid() or not _transfer_eligibility(room_id).get("ok", false): return {"ok": false, "code": "replay_transfer_unavailable"}
	var generation := _generation
	var server_key := _server_key()
	var path := "/v2/rooms/" + room_id
	var response := await _call(HTTPClient.METHOD_GET, path + "/replay-transfer/operations/" + key)
	if generation != _generation or server_key != _server_key(): return {"ok": false, "code": "replay_transfer_context_changed"}
	if response.get("ok", false):
		var data: Variant = response.get("data")
		if not data is Dictionary or not Coordinator._exact(data, ["schema_version", "receipt", "transfer"]) or not Typed.equal(data.schema_version, 1) or not ReplayTransfer.valid_transfer(data.transfer, _owner, room_id) or not validate_receipt.call(data.receipt):
			return {"ok": false, "code": "invalid_receipt"}
	elif response.get("status") != 404 or response.get("code") != "operation_not_found": return response
	# Definitive absence permits only the caller's original request to retry.
	# A known receipt is likewise recovered through the ordinary full snapshot
	# path after exact archive restoration; no checkpoint is manufactured here.
	var restored := await restore_complete_replay(room_id)
	if not restored.get("ok", false): return restored
	if generation != _generation or server_key != _server_key(): return {"ok": false, "code": "replay_transfer_context_changed"}
	var recovered := await _call(HTTPClient.METHOD_GET, path + "/operations/" + key)
	return recovered if generation == _generation and server_key == _server_key() else {"ok": false, "code": "replay_transfer_context_changed"}

func mutations_enabled() -> bool:
	return _ready() and capabilities.get("mutations_enabled") == true

func room_ids() -> Array:
	if not _ready(): return []
	# The journal retains recovery targets, but only a current authenticated
	# list/read can say a room is still visible to this identity.
	return _index.get("room_ids", []).filter(func(id: String) -> bool: return _room_summaries.has(id))

func room_summaries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in room_ids():
		var summary: Dictionary = _room_summaries[id].duplicate(true)
		summary["last_opened"] = id == _index.last_room
		result.append(summary)
	return result

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

func load_capabilities() -> bool:
	if not _ready():
		return false
	_room_chapters.clear()
	_room_summaries.clear()
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
	var scope := nickname_scope()
	if not scope.is_empty(): DisplayNames.shared().set_enabled(str(scope.server), str(scope.owner), display_names_supported())
	if not scope.is_empty(): PollenWallet.shared().set_enabled(str(scope.server), str(scope.owner), pollen_supported())
	if not scope.is_empty(): Wardrobe.shared().set_enabled(str(scope.server), str(scope.owner), shop_supported())
	if not scope.is_empty(): PollenWallet.shared().set_item_blooms(str(scope.server), str(scope.owner), item_blooms_supported())
	if not scope.is_empty(): PollenGrant.shared().set_enabled(str(scope.server), str(scope.owner), grant_supported())
	if pollen_supported() and pollen_flush.is_valid(): pollen_flush.call()
	if coordinator != null: coordinator.supported_simulation_versions = _simulation_versions()
	return true

func load_lobby() -> bool:
	if not await load_capabilities(): return false
	var response := await _call(HTTPClient.METHOD_GET, "/v2/rooms")
	if not response.get("ok", false):
		return _failure(response)
	var rooms: Variant = response.get("data", {}).get("rooms")
	if not rooms is Array or rooms.size() > 128:
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_58EDF3D26999
		return false
	var next := _index.duplicate(true)
	var observed: Dictionary = {}
	var summaries: Dictionary = {}
	for room: Variant in rooms:
		if not room is Dictionary or not Typed.equal(room.get("api_version"), 2) or not _id(room.get("room_id")) or _owner not in [room.get("host_id"), room.get("guest_id")]:
			last_error = PlayerCopy.RELAY_ONLINE_SESSION_EDC8E84089EF
			return false
		var chapter_key := Registry.resolve(room)
		observed[room.room_id] = chapter_key
		summaries[room.room_id] = _room_summary(room, chapter_key)
		if not room.room_id in next.room_ids:
			next.room_ids.append(room.room_id)
	# Prune list hints only. Last-room and per-room pending journals remain
	# untouched, including a hidden or unreadable target needing recovery.
	for id: String in _transferred_rooms:
		var retained: Dictionary = _transferred_rooms[id]
		if retained.server_key != _server_key(): continue
		observed[id] = Registry.resolve(retained.manifest.room)
		summaries[id] = _room_summary(retained.manifest.room, observed[id])
		summaries[id].active_role = "complete"
	next.room_ids = next.room_ids.filter(func(id: String) -> bool: return observed.has(id))
	_trim_standalone_proofs(next)
	if next.last_room in next.room_ids:
		next.room_ids.erase(next.last_room)
		next.room_ids.push_front(next.last_room)
	if not _write_index(next): return false
	_room_chapters = observed
	_room_summaries = summaries
	# Like a standalone proof, a read that found a room ordinary counts only while
	# the list shows the room; a room the list dropped is read again before use.
	for id: String in _archived_room_evidence.keys():
		if _archived_room_evidence[id] == "ordinary" and not observed.has(id): _archived_room_evidence.erase(id)
	return true

func _room_summary(room: Dictionary, chapter_key: String) -> Dictionary:
	return {"room_id": room.room_id, "title": RoomChapterTitle.title(chapter_key),
		"hosted": Typed.equal(room.get("host_id"), _owner), "active_role": str(room.get("active_role", "")),
		"updated_at": str(room.get("updated_at", ""))}

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

func room_chapter(room_id: String) -> String:
	var chapter := str(_room_chapters.get(room_id, ""))
	if chapter.is_empty() and coordinator != null and coordinator.snapshot().get("room_id") == room_id:
		chapter = coordinator.chapter_key()
	return chapter

func room_title(room_id: String) -> String:
	return RoomChapterTitle.title(room_chapter(room_id))

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
	if not _restore_previous_room(): return false
	if coordinator != null and (coordinator.read_only or not coordinator.pending().is_empty()):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_1BE2F671819A
		return false
	return _redo_navigation_ready()

## `hard`: a hard room (services/hard_mode.gd), only where the server plays them.
func create_room(chapter: String = Registry.RELAY, hard: bool = false) -> String:
	if not _can_lobby_mutate():
		return ""
	if not supports_creation(chapter):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_7805B3DE8AEB
		return ""
	if hard and not hard_mode_supported():
		last_error = PlayerCopy.HARD_HOST_UNAVAILABLE
		return ""
	if not _index.pending.is_empty():
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_8C3AC7311985
		return ""
	var chosen := Registry.descriptor(chapter)
	var body := {"idempotency_key": Crypto.new().generate_random_bytes(18).hex_encode(), "level_id": chosen.level_id, "level_version": chosen.level_version, "definition_hash": chosen.definition_hash}
	var requested_rules := int(_simulation_versions().get(chapter, Registry.definition(chapter).simulation_version))
	if requested_rules != int(Registry.definition(chapter).simulation_version):
		body["simulation_version"] = requested_rules
	if hard: body["mode"] = "hard"
	return await _start_lobby("/v2/rooms", body)

func join_room(code: String) -> String:
	if not _can_lobby_mutate():
		return ""
	# room-<code>, legacy and hyphen/space-grouped input; the API receives the bare code.
	var parsed := ShareCodes.parse(code, ShareCodes.ROOM)
	if not parsed.ok or not _index.pending.is_empty():
		last_error = ShareCodes.error_message(parsed, PlayerCopy.RELAY_ONLINE_SESSION_DA1FB43C8998) if _index.pending.is_empty() else PlayerCopy.RELAY_ONLINE_SESSION_DA1FB43C8998
		return ""
	var normalized: String = parsed.id
	var body := {"invite_code": normalized}
	# Bundled replay support remains available when a creation gate is disabled.
	# Advertising it must not depend on currently creatable server chapters.
	body["supported_simulation_versions"] = join_versions()
	return await _start_lobby("/v2/rooms/join", body)

## The join list for the server these capabilities came from. Without a room
## level 2 answer allowing it, the list stays the one every server accepts.
func join_versions() -> Array:
	var longer: Array = JOIN_SIMULATION_VERSIONS + ROOM_LEVEL_JOIN_VERSIONS
	var allowed: Variant = capabilities.get("max_join_versions")
	if Typed.whole_number(capabilities.get("room_level")) and int(capabilities.room_level) >= 2 and Typed.whole_number(allowed) and int(allowed) >= longer.size(): return longer
	return JOIN_SIMULATION_VERSIONS.duplicate()

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
	var unlocks: Dictionary = join_unlocks.call() if request.path == "/v2/rooms/join" and join_unlocks.is_valid() else {}
	var headers := PackedStringArray() if unlocks.is_empty() else PackedStringArray([ChapterUnlocks.join_header(unlocks)])
	var response := await _call(HTTPClient.METHOD_POST, request.path, request.body, headers)
	if not response.get("ok", false):
		# A definitive refusal settles the request: the server joined or created
		# nothing for it now, and a retry of the same request cannot succeed.
		# Repeating a join or create that did succeed earlier (a lost reply)
		# answers 200, so a refusal here also means no earlier attempt landed in
		# a room still open: an expired, closed or full invitation, a room limit.
		# Keeping it would hold every other room behind a request that can never
		# succeed. The create route checks for an admitted idempotent intent
		# before host access, so host_unlock_required created no room either.
		# Lost replies, timeouts, rate limits and outages stay recoverable.
		if not response.get("ignored", false) and _definitive_refusal(response):
			if not _ready() or not Typed.same(_index.pending, request): return ""
			var next := _index.duplicate(true)
			next.pending = {}
			if not _write_index(next): return ""
		_failure(response)
		if request.path == "/v2/rooms" and int(response.get("status", 0)) == 402 and response.get("code") == "host_unlock_required": last_error = PlayerCopy.SHARED_HOST_CREATE_ACCESS
		if not unlocks.is_empty() and int(response.get("status", 0)) == 403 and response.get("code") == ChapterUnlocks.JOIN_REFUSAL: last_error = ChapterUnlocks.join_refusal(unlocks)
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

## Create and join refusals that will answer the same on every retry
## (backend v2/routes.ts and v2/room.ts): the invitation is wrong, expired,
## gone or full, the room finished or was closed, or this player cannot have
## another room. Unknown codes, credentials, rate limits and outages are not.
const DEFINITIVE_LOBBY_REFUSALS := {
	400: ["invalid_invite", "unexpected_fields", "invalid_field"],
	402: ["host_unlock_required"],
	403: ["player_blocked", ChapterUnlocks.JOIN_REFUSAL],
	404: ["invite_not_found"],
	409: ["room_full", "room_limit_reached", "room_version_conflict", "room_exists", "idempotency_chapter_mismatch", "idempotency_simulation_mismatch", "idempotency_version_mismatch"],
	410: ["invite_expired", "replay_transferred", "room_deleted"],
	422: ["unsupported_chapter", "unsupported_simulation_version"],
}

static func _definitive_refusal(response: Dictionary) -> bool:
	return str(response.get("code", "")) in DEFINITIVE_LOBBY_REFUSALS.get(int(response.get("status", 0)), [])

func open_room(room_id: String) -> bool:
	if not _ready() or busy() or not _id(room_id): return false
	if archived_room_kind(room_id) == "story":
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_28632F597E2A
		return false
	if not _restore_previous_room(): return false
	if coordinator != null and coordinator.read_only and room_id != _bound_room:
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_28632F597E2A
		return false
	if coordinator != null and not coordinator.pending().is_empty() and room_id != _index.last_room:
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_9584CB32FD17
		return false
	if not _redo_navigation_ready(room_id): return false
	# A room this phone has not proven to be an ordinary chapter room is read
	# and checked before it is selected.
	if not standalone_room_proven(room_id):
		return await _probe_standalone(room_id)
	var previous: RefCounted = coordinator
	var candidate: RefCounted = coordinator if coordinator != null else _ordinary_coordinator()
	var next := _index.duplicate(true)
	next.last_room = room_id
	_remember_recent(next,room_id)
	if not _write_index(next): return false
	coordinator = candidate
	if previous != null and previous != candidate: previous.invalidate_identity()
	if not _bind_room(room_id):
		last_error = coordinator.last_error
		return false
	var target := coordinator
	var generation := _generation
	var success: bool = await target.refresh()
	if generation != _generation or not _ready() or coordinator != target:
		return false
	last_error = coordinator.last_error
	if success:
		_room_chapters[room_id] = coordinator.chapter_key()
		var room_snapshot: Dictionary = coordinator.snapshot()
		_room_summaries[room_id] = _room_summary(room_snapshot, Registry.resolve(room_snapshot))
	elif coordinator.last_code != "replay_transferred":
		_room_chapters.erase(room_id)
		_room_summaries.erase(room_id)
		if coordinator.last_code in ["room_not_found","room_deleted","player_blocked"]:
			_clear_terminal_redo(room_id)
	return success

func _ordinary_coordinator() -> RefCounted:
	var background_writer: Callable = _store.save_scope if _store.get_script() == Store else Callable()
	var result := Coordinator.new(transport,_store.load_scope,_store.save_scope,_identity,Callable(),background_writer)
	result.supported_simulation_versions = _simulation_versions()
	result.accepted_pair_cache = accepted_pair_cache
	result.partner_name_sink = _note_partner_name
	result.pollen_sink = _note_pollen
	result.partner_look_sink = _note_partner_look
	result.own_turn_look_sink = _note_own_turn_look
	result.pollen_finished_sink = _note_finished_room
	result.restore_replay_transfer = restore_complete_replay
	result.recover_replay_operation = recover_transferred_operation
	return result

func _restore_previous_room() -> bool:
	if coordinator != null or _index.last_room.is_empty(): return true
	if archived_room_kind(_index.last_room) == "story": return true
	if not standalone_room_proven(_index.last_room):
		last_error = PlayerCopy.MAIN_571E92F64ED1
		return false
	coordinator = _ordinary_coordinator()
	if not _bind_room(_index.last_room):
		last_error = coordinator.last_error
		return false
	return true

func _archived_lifetime() -> Dictionary:
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	if not identity is Dictionary or identity.get("ready") != true or identity.get("player_id") != _owner or identity.get("epoch") != _epoch or not is_instance_valid(_api): return {}
	return {"owner":_owner,"epoch":_epoch,"generation":_generation,"api":_api.get_instance_id(),
		"api_owner":str(_api.player_id),"device_hash":str(_api.device_token).sha256_text(),"base_url":str(_api.base_url)}

## What the server said about a room this phone had not proven ordinary:
## "story" (409 campaign_client_required: a room of the withdrawn Story
## feature, kept out of all play), "ordinary", or "" when not checked.
func archived_room_kind(room_id: String) -> String:
	# Server observations are only in memory and expire with this API identity.
	var lifetime := _archived_lifetime()
	if lifetime.is_empty() or not Typed.same(lifetime,_archived_evidence_lifetime): return ""
	return str(_archived_room_evidence.get(room_id,""))

func prepare_archived_navigation() -> bool:
	if not _ready() or busy(): return false
	if _index.last_room.is_empty(): return true
	var room_id: String = _index.last_room
	if archived_room_kind(room_id) == "story" or standalone_room_proven(room_id):
		var restored := _restore_previous_room()
		if restored: last_error = ""
		return restored
	# An absent standalone_ids entry is not evidence of Story ownership. Read
	# the OLD selection first; never load its pending request into the validator.
	var lease := _ordinary_lease()
	_opening = true
	var response := await _call(HTTPClient.METHOD_GET,"/v2/rooms/"+room_id)
	if lease.generation == _generation: _opening = false
	if not _ready() or not Typed.same(lease,_ordinary_lease()): return false
	var validator := Coordinator.new(Callable(),func(_scope: String) -> Dictionary: return {"ok":true,"found":false},
		func(_scope: String,_value: Dictionary) -> Dictionary: return {"ok":false},_identity)
	validator.supported_simulation_versions = _simulation_versions()
	var kind := _classify_room_answer(room_id,response,validator) if validator.bind_room(room_id) else ""
	if kind.is_empty():
		if _room_gone(response): return _release_gone_room(room_id)
		last_error = PlayerCopy.MAIN_571E92F64ED1
		return false
	# Restoring an ordinary cache leaves its original draft and pending bytes
	# intact. Existing leave/create/open guards then enforce its recovery lock.
	var restored := _restore_previous_room()
	if restored: last_error = ""
	elif response.get("code") == "replay_transferred":
		# A finished room this phone holds no copy of has nothing to recover.
		return _forget_last_room(room_id)
	return restored

## Reads the server's answer to an ordinary read of a room this phone has not
## proven ordinary, and remembers what it proves for this identity: "story" for
## 409 campaign_client_required (a room of the withdrawn Story feature),
## "ordinary" for a snapshot `validator` verifies or a room whose replay both
## players saved, "" when it proves neither. The caller checks its lease first.
func _classify_room_answer(room_id: String, response: Dictionary, validator: RefCounted) -> String:
	var kind := ""
	if response.get("ok") == false and response.get("status") == 409 and response.get("code") == "campaign_client_required":
		kind = "story"
	elif response.get("ok") == true and response.get("status") == 200:
		if validator.verify_room_snapshot(response.get("data")): kind = "ordinary"
	elif response.get("status") == 410 and response.get("code") == "replay_transferred":
		# The server answers an unmarked read of a Story room with
		# campaign_client_required before anything else, so a room whose replay
		# both players saved is an ordinary, finished one.
		kind = "ordinary"
	var lifetime := _archived_lifetime()
	if kind.is_empty() or lifetime.is_empty(): return kind
	if not Typed.same(lifetime,_archived_evidence_lifetime): _archived_room_evidence.clear()
	_archived_evidence_lifetime = lifetime
	_archived_room_evidence[room_id] = kind
	return kind

## The server no longer has this room for the player: closed, left or removed.
static func _room_gone(response: Dictionary) -> bool:
	if response.get("ok") != false or response.get("ignored",false): return false
	return (response.get("status") == 404 and response.get("code") == "room_not_found") or (response.get("status") == 410 and response.get("code") in ["room_closed","room_deleted"])

## A checked read of this room said the server no longer has it (`_room_gone`).
## A turn or redo this phone still holds for it, whose reply was lost, can never
## be accepted now, so the room stops holding every other room: it is no longer
## the last room, its listed row and any coordinator or redo client bound to it
## are dropped, and the player gets one note when such a request was held. Its
## journals stay on disk exactly as they were. False only when the index save
## fails; the room then stays held as before.
func _release_gone_room(room_id: String) -> bool:
	var held: bool = _index.last_room == room_id and _room_recovery_pending(room_id)
	if _index.last_room == room_id and not _forget_last_room(room_id): return false
	_room_chapters.erase(room_id)
	_room_summaries.erase(room_id)
	if _redo != null and (_redo.bound_room_id("relay") == room_id or str(_redo.pending().get("source", {}).get("room_id", "")) == room_id): _redo.invalidate()
	_redo_read_key = ""
	_redo_read_result = {}
	if held: _released_room_note = PlayerCopy.ROOMS_API_A7ACF38988EE
	return true

## The note from the last release of a gone room that held a request, once; "" after.
func take_released_room_note() -> String:
	var note := _released_room_note
	_released_room_note = ""
	return note

## True when this phone still holds an uncertain turn or redo request for the
## room, or cannot tell.
func _room_recovery_pending(room_id: String) -> bool:
	var saved: Dictionary = _store.load_scope("relay-room-v2:" + _owner + ":" + room_id)
	if not saved.get("ok", false): return true
	if saved.get("found", false):
		var state: Variant = saved.get("value")
		if not state is Dictionary or not state.get("pending") is Dictionary or not state.pending.is_empty(): return true
	var redo := _load_redo_journal(room_id, true)
	return not redo.get("ok", false) or not redo.get("value", {}).get("pending", {}).is_empty()

## Drops a last-room pointer to a room that is over, so navigation goes on.
## Its saved journals stay on disk untouched.
func _forget_last_room(room_id: String) -> bool:
	if not _ready() or _index.last_room != room_id: return false
	var next := _index.duplicate(true)
	next.last_room = ""
	if not _write_index(next): return false
	if coordinator != null and _bound_room == room_id:
		coordinator.invalidate_identity()
		coordinator = null
		_bound_room = ""
	last_error = ""
	return true

func _ordinary_lease() -> Dictionary:
	return {"owner":_owner,"epoch":_epoch,"generation":_generation,"selection":_room_selection_generation,
		"api_owner":str(_api.player_id),"device_hash":str(_api.device_token).sha256_text(),"base_url":str(_api.base_url),
		"index":Canonical.digest(_index),"coordinator":coordinator.get_instance_id() if coordinator != null else 0,
		"state":coordinator.observe_state() if coordinator != null else {},
		"redo_pending":_redo.pending() if _redo != null else {},"redo_busy":_redo != null and _redo.busy}

func _probe_standalone(room_id: String) -> bool:
	var lease := _ordinary_lease()
	_opening = true
	var okay: bool = await _probe_standalone_owned(room_id,lease)
	if lease.generation == _generation: _opening = false
	return okay

func _probe_standalone_owned(room_id: String, lease: Dictionary) -> bool:
	var candidate := _ordinary_coordinator()
	if not candidate.bind_room(room_id):
		last_error = candidate.last_error
		return false
	if not _ready() or not Typed.same(lease,_ordinary_lease()): return false
	var response := await _call(HTTPClient.METHOD_GET,"/v2/rooms/"+room_id)
	if not _ready() or not Typed.same(lease,_ordinary_lease()) or archived_room_kind(room_id) == "story": return false
	var kind := _classify_room_answer(room_id,response,candidate)
	if kind == "story":
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_28632F597E2A
		return false
	if not response.get("ok",false):
		if _room_gone(response):
			if not _release_gone_room(room_id): return false
			# Shown here, as this tap's answer, and not again at the next visit.
			var note := take_released_room_note()
			_failure(response)
			if not note.is_empty(): last_error = note
			return false
		if response.get("code") == "player_blocked": _clear_terminal_redo(room_id)
		return _failure(response)
	if kind != "ordinary" and not candidate.verify_room_snapshot(response.get("data")):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_C0AD24FCB05A
		return false
	# Finish the fallible native cache work before changing selection. If the
	# later index save fails, only a verified, unselected cache may remain.
	if not candidate.accept_room_snapshot(response.data):
		last_error = candidate.last_error
		return false
	if not _ready() or not Typed.same(lease,_ordinary_lease()) or archived_room_kind(room_id) == "story": return false
	var next := _index.duplicate(true)
	next.schema_version = 2
	next["standalone_ids"] = next.get("standalone_ids",[]).duplicate()
	_remember_recent(next,room_id)
	if room_id not in next.standalone_ids: next.standalone_ids.append(room_id)
	next.last_room = room_id
	if not _write_index(next): return false
	var saved_lease := lease.duplicate(true)
	saved_lease.index = Canonical.digest(next)
	if not Typed.same(saved_lease,_ordinary_lease()): return false
	if coordinator != null: coordinator.invalidate_identity()
	coordinator = candidate
	_bound_room = room_id
	_room_selection_generation += 1
	_room_chapters[room_id] = candidate.chapter_key()
	var room_snapshot: Dictionary = candidate.snapshot()
	_room_summaries[room_id] = _room_summary(room_snapshot, Registry.resolve(room_snapshot))
	last_error = ""
	return true

func _remember_recent(value: Dictionary, room_id: String) -> void:
	value.room_ids.erase(room_id)
	value.room_ids.push_front(room_id)
	if value.room_ids.size() > 128: value.room_ids.resize(128)
	_trim_standalone_proofs(value)

func _trim_standalone_proofs(value: Dictionary) -> void:
	# List hints may be pruned, while last_room and all recovery journals stay.
	# A proof is valid only while its room is in this bounded ordinary index.
	if value.has("standalone_ids"):
		value.standalone_ids = value.standalone_ids.filter(func(id: String) -> bool: return id in value.room_ids)

func _bind_room(room_id: String) -> bool:
	_room_selection_generation += 1
	_bound_room = room_id
	coordinator.accepted_pair_cache = accepted_pair_cache
	return coordinator.bind_room(room_id)

func transport(request: Dictionary) -> Dictionary:
	if not _ready() or request.get("owner_player_id") != _owner or request.get("identity_epoch") != _epoch:
		return {"ok": false, "status": 401, "code": "identity_changed"}
	if request.method == HTTPClient.METHOD_POST and not mutations_enabled():
		return {"ok": false, "status": 503, "code": "v2_mutations_disabled"}
	var headers: Variant = request.get("headers", PackedStringArray())
	return await _call(request.method, request.path, request.body,headers if headers is PackedStringArray else PackedStringArray())

func chapter_pairs() -> Array:
	if not _ready() or coordinator == null:
		return []
	var checkpoint: Dictionary = coordinator.checkpoint()
	var pairs: Array = []
	# The coordinator already replay-verifies this exact bounded proof chain,
	# one nested proof per completed stage of its chapter.
	var chapter: String = coordinator.chapter_key()
	for _index_value in range(RoomStages.count(Registry.definition(chapter))):
		if checkpoint.get("stage_index", 0) == 0:
			break
		var proof: Dictionary = checkpoint.proof
		pairs.push_front({"a": proof.a.duplicate(true), "b": proof.b.duplicate(true)})
		checkpoint = Registry.previous_checkpoint(chapter, checkpoint)
	return pairs

func create_photo_controller(local_io: Callable, context_factory: RefCounted = null) -> RefCounted:
	# Photo state is deliberately outside lobby/gameplay journals.
	# Bind before registering: the initial identity bind invalidates old controllers
	# and must not cancel this controller during its first photo request.
	_ready()
	var factory: RefCounted = context_factory if context_factory != null else auxiliary_context_factory()
	var controller := PhotoController.new(transport, photo_store.load_scope, photo_store.save_scope, _identity, local_io, Callable(), photo_library, factory)
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
	if not Typed.same(reference, accepted):
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
		if existing is Dictionary and Typed.equal(existing.get("schema_version"), 1) and Typed.same(existing.get("target"), target):
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
	if not PhotoController._exact(receipt, Coordinator.RECEIPT_KEYS) or not Typed.equal(receipt.schema_version, 2) or not Typed.equal(receipt.operation, "turns") or not PhotoController._hash(receipt.request_hash) or not PhotoController._hash(receipt.checkpoint_hash) or not PhotoController._range(receipt.branch, 0, 31) or not PhotoController._range(receipt.stage_index, 0, RoomStages.MAX_STAGES - 1) or not PhotoController._range(receipt.accepted_revision, 1, 256):
		return {}
	var chapter := Registry.resolve(room)
	if chapter.is_empty() or room.get("api_version") != 2 or room.get("schema_version") != 2 or room.get("room_id") != receipt.room_id or not PhotoController._range(room.get("revision"), int(receipt.accepted_revision), 256) or _owner not in [room.get("host_id"), room.get("guest_id")]:
		return {}
	var level := Registry.definition(chapter)
	var index := int(receipt.stage_index)
	if not RoomStages.within(index, level): return {}
	var role: String = str(receipt.turn_id).right(1)
	if not Typed.equal(receipt.turn_id, "t%d-%d-%s" % [int(receipt.branch), index, role]) or not Typed.equal(receipt.stage_id, level.stages[index].id) or not Typed.equal(receipt.pair_id, ("p%d-%d" % [int(receipt.branch), index] if role == "b" else null)):
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
	if not loaded.get("ok", false) or not loaded.get("found", false) or not value is Dictionary or not Typed.equal(value.get("schema_version"), 1) or not value.get("target") is Dictionary:
		return ""
	var target: Dictionary = value.target
	if not Typed.equal(target.get("room_id"), room) or not Typed.equal(target.get("owner_player_id"), _owner) or not Typed.equal(target.get("turn_id"), turn) or not Typed.equal(target.get("recording_hash"), recording_hash) or not PhotoController._key(target.get("gameplay_key")):
		return ""
	# This is only a lookup hint. open_owned_turn re-fetches the authoritative
	# caller-scoped gameplay receipt before granting photo mutation access.
	return target.gameplay_key

func replay_photo_turns(index: int, pair: Dictionary) -> Array:
	if not _ready() or coordinator == null:
		return []
	var room: Dictionary = coordinator.snapshot()
	var pairs: Array = chapter_pairs()
	if index < 0 or index >= pairs.size() or not Typed.same(pair, pairs[index]) or index >= room.get("completed_pair_ids", []).size():
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

func _call(method: int, path: String, body: Dictionary = {}, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not _ready() or _busy or _api.player_id != _owner or str(_api.device_token).is_empty():
		return {"ok": false, "status": 0, "code": "request_busy"}
	var generation := _generation
	var owner := _owner
	var epoch := _epoch
	_busy = true
	# request_json captures these verified headers synchronously before await.
	var response: Dictionary
	var still := func() -> bool: return generation == _generation
	# A room poll's known-room header; an API without extra headers just reads the full room.
	if not headers.is_empty() and _api.has_method("request_json_with_headers"): response = await _api.request_json_with_headers(method,path,body,headers,still)
	else: response = await _api.request_json(method,path,body,still)
	if generation == _generation:
		_busy = false
	var identity: Dictionary = _identity.call()
	if generation != _generation or not identity.get("ready", false) or identity.get("player_id") != owner or identity.get("epoch") != epoch:
		return {"ok": false, "ignored": true, "status": 0, "code": "identity_changed"}
	return response

## _call for byte bodies and replies (room attempts).
func _call_raw(method: int, path: String, body: PackedByteArray) -> Dictionary:
	if not _ready() or _busy or _api.player_id != _owner or str(_api.device_token).is_empty() or not _api.has_method("request_raw"):
		return {"ok": false, "status": 0, "code": "request_busy"}
	var generation := _generation
	var owner := _owner
	var epoch := _epoch
	_busy = true
	var response: Dictionary = await _api.request_raw(method, path, body, func() -> bool: return generation == _generation)
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
	if not _restore_previous_room(): return false
	if coordinator != null and coordinator.read_only:
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_93A87697D639
		return false
	if coordinator != null and not coordinator.pending().is_empty():
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_D442C4316FCF
		return false
	return _redo_navigation_ready()

func _redo_navigation_ready(target_room: String = "") -> bool:
	if _redo != null and not _redo.pending().is_empty() and _redo.pending().source.room_id != target_room:
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_9584CB32FD17
		return false
	# Read the selected room's durable control journal before changing last_room.
	# Recovery of that same room remains possible even if the control save is
	# unreadable; another chapter cannot hide or replace the uncertain request.
	var previous: String = _index.last_room
	if previous.is_empty() or target_room == previous: return true
	if archived_room_kind(previous) == "story": return true
	if not standalone_room_proven(previous):
		last_error = PlayerCopy.MAIN_571E92F64ED1
		return false
	var loaded := _load_redo_journal(previous)
	if not loaded.get("ok",false) or not loaded.value.get("pending",{}).is_empty():
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_9584CB32FD17
		return false
	return true

func _load_redo_journal(room_id: String, refresh: bool = false) -> Dictionary:
	# Frequent navigation guards use the live control state or one cached read.
	# Explicit terminal-room recovery still checks the durable scope again.
	if not refresh and _redo != null and _redo.bound_room_id("relay") == room_id:
		return {"ok":true,"value":{"schema_version":1,"owner_player_id":_owner,"family":"relay","room_id":room_id,"server_hash":str(_api.base_url).sha256_text(),"pending":_redo.pending()}}
	var key := str(_generation)+":"+_owner+":"+str(_api.base_url)+":"+room_id
	if not refresh and key == _redo_read_key: return _redo_read_result.duplicate(true)
	var generation := _generation
	var loaded: Dictionary = _store.load_scope("relay-redo-relay-v1:" + _owner + ":" + room_id)
	if generation != _generation or not _ready(): return {"ok":false}
	var value: Variant = loaded.get("value",{})
	_redo_read_key = key
	_redo_read_result = {"ok":false} if not loaded.get("ok",false) or not value is Dictionary or (not value.is_empty() and not RedoClient.valid_journal(value,_owner,"relay",room_id,str(_api.base_url))) else {"ok":true,"value":value}
	return _redo_read_result.duplicate(true)

func _clear_terminal_redo(room_id: String) -> void:
	var loaded := _load_redo_journal(room_id,true)
	if not loaded.get("ok",false) or loaded.value.get("pending",{}).is_empty(): return
	var value: Dictionary = loaded.value.duplicate(true)
	value.pending = {}
	var generation := _generation
	if not _store.save_scope("relay-redo-relay-v1:"+_owner+":"+room_id,value).get("ok",false):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_E491F4F0F93A
		return
	if generation != _generation or not _ready(): return
	_redo_read_key = ""
	_redo_read_result = {}
	if _redo != null and _redo.bound_room_id("relay") == room_id: _redo.invalidate()

func _write_index(next: Dictionary) -> bool:
	if not _ready() or not _valid_index(next):
		return false
	var generation := _generation
	if not _store.save_scope("relay-lobby-v2:" + _owner, next).get("ok", false):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_E491F4F0F93A
		return false
	if not _ready() or generation != _generation:
		return false
	_index = next.duplicate(true)
	last_error = ""
	return true

func _valid_index(value: Dictionary) -> bool:
	if not Coordinator._bounded(value, 32768) or (not Typed.equal(value.get("schema_version"), 1) and not Typed.equal(value.get("schema_version"), 2)) or value.size() != (6 if Typed.equal(value.get("schema_version"), 2) else 5) or not Typed.equal(value.get("owner_player_id"), _owner) or not value.get("room_ids") is Array or value.room_ids.size() > 128 or not value.get("last_room") is String or (value.last_room != "" and not _id(value.last_room)) or not value.get("pending") is Dictionary:
		return false
	for room: Variant in value.room_ids:
		if not _id(room):
			return false
	if value.schema_version == 2:
		if not value.get("standalone_ids") is Array or value.standalone_ids.size() > value.room_ids.size(): return false
		var seen := {}
		for room: Variant in value.standalone_ids:
			if not _id(room) or room not in value.room_ids or seen.has(room): return false
			seen[room] = true
	var pending: Dictionary = value.pending
	if pending.is_empty():
		return true
	if pending.size() != 3 or pending.get("path") not in ["/v2/rooms", "/v2/rooms/join"] or not pending.get("body") is Dictionary or not Typed.equal(pending.get("request_hash"), Canonical.digest({"path": pending.path, "body": pending.body})):
		return false
	var body: Dictionary = pending.body
	if pending.path == "/v2/rooms":
		var optional_pin: bool = body.has("simulation_version")
		var hard_room: bool = body.has("mode")
		if hard_room and not Typed.equal(body.mode, "hard"): return false
		return body.size() == (5 if optional_pin else 4) + int(hard_room) and body.get("idempotency_key") is String and body.idempotency_key.length() == 36 and not Registry.resolve(body).is_empty() and (not optional_pin or (Typed.whole_number(body.simulation_version) and int(body.simulation_version) in Registry.supported_rules(Registry.resolve(body)) and int(body.simulation_version) != int(Registry.definition(Registry.resolve(body)).simulation_version)))
	var optional_versions: bool = body.has("supported_simulation_versions")
	return body.size() == (2 if optional_versions else 1) and body.get("invite_code") is String and body.invite_code.length() == 20 and (not optional_versions or Typed.same(body.supported_simulation_versions, [2, 4, 5]) or Typed.same(body.supported_simulation_versions, [2, 4, 5, 6]) or Typed.same(body.supported_simulation_versions, [2, 4, 5, 6, 7]) or Typed.same(body.supported_simulation_versions, [2, 4, 5, 6, 7, 8]) or Typed.same(body.supported_simulation_versions, [2, 4, 5, 6, 7, 8, 9]) or Typed.same(body.supported_simulation_versions, [2, 4, 5, 6, 7, 8, 9, 11]) or Typed.same(body.supported_simulation_versions, JOIN_SIMULATION_VERSIONS) or Typed.same(body.supported_simulation_versions, JOIN_SIMULATION_VERSIONS + ROOM_LEVEL_JOIN_VERSIONS))

func _failure(response: Dictionary, fallback: String = "") -> bool:
	if fallback.is_empty() and response.get("code") == "host_unlock_required":
		last_error = PlayerCopy.ROOMS_API_93CCDC2D04DB
	elif fallback.is_empty() and response.get("code") == "entitlement_unavailable":
		last_error = PlayerCopy.ROOMS_API_5E389F16D75A
	else:
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
	if _safety == null: _safety = Safety.new(_api, _identity, null, Callable(), auxiliary_context_factory())
	return _safety

## A room partner's display name from a room reply, kept for every screen.
func _note_partner_name(partner: String, name: Variant, room: String) -> void:
	var scope := nickname_scope()
	if not scope.is_empty(): DisplayNames.shared().note_partner(str(scope.server), str(scope.owner), partner, name, room)

## An accepted turn's Pollen credit: a confirmed receipt is kept for its results
## line; a turn whose credit did not come back confirmed waits to be claimed
## (services/pollen_client.gd). Nothing while the server has Pollen off.
## The turn that finished a chapter pays this player's first clears with it (its
## receipt, or its claim), so that room never needs a clear claim of its own.
func _note_pollen(room: String, recording_hash: String, pollen: Variant, finished: bool = false) -> void:
	var scope := nickname_scope()
	var store: RefCounted = PollenWallet.shared()
	if scope.is_empty() or not store.enabled(str(scope.server), str(scope.owner)): return
	if finished: store.mark_cleared(str(scope.server), str(scope.owner), "room:" + room)
	if store.note_receipt(str(scope.server), str(scope.owner), room, recording_hash, pollen): return
	store.queue_claim(str(scope.server), str(scope.owner), room, recording_hash)

## A room this player saw finished by the other player: its first clear waits to be claimed,
## so a partner credit that did not land when the chapter finished is recovered.
func _note_finished_room(room: String) -> void:
	var scope := nickname_scope()
	var store: RefCounted = PollenWallet.shared()
	if scope.is_empty() or not store.enabled(str(scope.server), str(scope.owner)): return
	if store.queue_clear(str(scope.server), str(scope.owner), "room:" + room) and pollen_flush.is_valid(): pollen_flush.call()

## The room partner's look (services/turn_looks.gd), for their pip in this room.
func _note_partner_look(partner: String, look: Variant) -> void:
	TurnLooks.shared().note_member(partner, look)

## This player's own accepted turn keeps the look it was played in, for its replays.
func _note_own_turn_look(recording_hash: String) -> void:
	TurnLooks.shared().note_turn(recording_hash, OwnLook.outfit())

## The server has the wardrobe open: spending Pollen and wearing items (services/wardrobe.gd).
func shop_supported() -> bool:
	return pollen_supported() and Typed.equal(capabilities.get("pollen_shop_version"), 1.0)

## The server pays Pollen for turns (services/pollen_wallet.gd).
func pollen_supported() -> bool:
	return Typed.equal(capabilities.get("pollen_version"), 1.0)

## Free chapter turns may drop a shop item (the receipt's item_bloom).
func item_blooms_supported() -> bool:
	return pollen_supported() and Typed.equal(capabilities.get("pollen_item_blooms_version"), 1.0)

## Full Journey pays monthly Pollen on the wallet read (services/pollen_grant.gd).
func grant_supported() -> bool:
	return pollen_supported() and Typed.equal(capabilities.get("pollen_grant_version"), 1.0)

## The server shows display names to this player (services/display_names.gd).
func display_names_supported() -> bool:
	return Typed.equal(capabilities.get("display_names_version"), 1.0)

## The server has leaderboards open for this build (backend src/leaderboards/routes.ts).
func leaderboards_supported() -> bool:
	return Typed.equal(capabilities.get("leaderboards_version"), 1.0)

func nickname_scope() -> Dictionary:
	## Server and owner that key this device's local friend nicknames and the
	## display names it keeps; {} without a server address (a test's API).
	if not _ready() or not is_instance_valid(_api): return {}
	var server: Variant = _api.get("base_url")
	if not server is String or server.is_empty(): return {}
	return {"server": server, "owner": _owner}

func safety_context() -> Dictionary:
	if not _ready() or coordinator == null: return {}
	var room: Dictionary = coordinator.snapshot()
	var peer: Variant = room.get("guest_id") if room.get("host_id") == _owner else room.get("host_id")
	return {"room_family": "relay", "room_id": room.get("room_id"), "peer_id": peer} if Safety.Store.id(peer) else {}

func partner_photos_allowed(reference: Dictionary) -> bool:
	if reference.get("own", false): return true
	if not _ready(): return false
	return Safety.Store.new().partner_allowed(_owner, "relay", str(reference.get("room_id", "")), str(reference.get("owner_player_id", "")))

func auxiliary_context_factory() -> RefCounted:
	if not _ready(): return AuxiliaryContext.new(self,{})
	if _auxiliary_factory != null and _auxiliary_factory.current(): return _auxiliary_factory
	var lifetime := {"owner":_owner,"epoch":_epoch,"generation":_generation,"api_instance":_api.get_instance_id(),
		"device_hash":str(_api.device_token).sha256_text(),"base_url":str(_api.base_url)}
	_auxiliary_factory = AuxiliaryContext.new(self,lifetime)
	return _auxiliary_factory

func auxiliary_lifetime_current(value: Dictionary) -> bool:
	# Pure identity observation: room selection does not retire older photos.
	# Explicit invalidation does, even at one epoch.
	if value.is_empty(): return false
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	if not identity is Dictionary or identity.get("ready") != true or identity.get("player_id") != value.owner or identity.get("epoch") != value.epoch or _generation != value.generation: return false
	return is_instance_valid(_api) and _api.get_instance_id() == value.get("api_instance",-1) and str(_api.player_id) == value.owner and str(_api.device_token).sha256_text() == value.device_hash and str(_api.base_url) == value.base_url

func auxiliary_safety_transport(request: Dictionary) -> Dictionary:
	# Safety stays available while gameplay writes are paused. This narrow
	# dispatch still requires exact identity and a typed room-bound safety POST.
	if not _ready() or request.get("owner_player_id") != _owner or request.get("identity_epoch") != _epoch: return {"ok":false,"ignored":true,"status":401,"code":"identity_changed"}
	if request.get("method") != HTTPClient.METHOD_POST or request.get("path") not in ["/v1/safety/block","/v1/safety/report"] or not request.get("body") is Dictionary or request.body.get("room_family") != "relay" or not _id(request.body.get("room_id")): return {"ok":false,"ignored":true,"status":0,"code":"campaign_route_unavailable"}
	return await _call(request.method,request.path,request.body)

func auxiliary_photo_ack_transport(request: Dictionary) -> Dictionary:
	# Verified photo delivery uses its existing independent server flag. It is
	# not a new gameplay contribution, photo replacement or deletion.
	if not _ready() or request.get("owner_player_id") != _owner or request.get("identity_epoch") != _epoch: return {"ok":false,"ignored":true,"status":401,"code":"identity_changed"}
	if not AuxiliaryContext.delivery_ack(request): return {"ok":false,"ignored":true,"status":0,"code":"campaign_route_unavailable"}
	return await _call(request.method,request.path,request.body)

func standalone_room_proven(room_id: String) -> bool:
	# Pure already-loaded index observation; never calls back into Owner.
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	return identity is Dictionary and identity.get("ready") == true and identity.get("player_id") == _owner and identity.get("epoch") == _epoch and _index_loaded and _valid_index(_index) and (room_id in _index.get("standalone_ids",[]) or archived_room_kind(room_id) == "ordinary")
