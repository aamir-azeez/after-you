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
const AuxiliaryContext = preload("res://services/campaign_auxiliary_context.gd")
const CampaignRoomBridge = preload("res://services/campaign_room_bridge.gd")
const RedoClient = preload("res://services/redo_client.gd")

class RedoStorage:
	extends RefCounted
	var journal: RefCounted
	func _init(storage: RefCounted) -> void: journal = storage
	func read(scope: String) -> Dictionary: return journal.load_scope(scope)
	func write(scope: String, value: Dictionary) -> bool: return journal.save_scope(scope,value).get("ok",false)
var coordinator: RefCounted
var accepted_pair_cache: Callable
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
var _campaign_bridges: Array[WeakRef] = []
var _campaign_owner: WeakRef
var _opening := false
var _retiring_selection := false
var _auxiliary_factory: RefCounted
var photo_store: RefCounted = PhotoStore.new()
var photo_library: RefCounted = PhotoLibrary.new()
var _photo_controllers: Array[WeakRef] = []
var _safety: RefCounted
var _redo: RefCounted
var _redo_read_key := ""
var _redo_read_result: Dictionary = {}
var _archived_room_evidence: Dictionary = {}
var _archived_evidence_lifetime: Dictionary = {}

func _init(api: Node, identity: Callable, storage: RefCounted = null) -> void:
	_api = api
	_identity = identity
	_store = Store.new() if storage == null else storage

func invalidate_identity() -> void:
	_archived_room_evidence.clear()
	_archived_evidence_lifetime.clear()
	_auxiliary_factory = null
	if _safety != null: _safety.invalidate()
	if _redo != null: _redo.invalidate()
	_redo_read_key = ""
	_redo_read_result = {}
	_generation += 1
	for reference: WeakRef in _campaign_bridges:
		var bridge: RefCounted = reference.get_ref()
		if bridge != null: bridge.invalidate()
	_campaign_bridges.clear()
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
	return _retiring_selection or _opening or _busy or (coordinator != null and coordinator.busy()) or (_redo != null and _redo.busy)

func redo_client() -> RefCounted:
	_ready()
	if _redo == null: _redo = RedoClient.new(_api, _identity, RedoStorage.new(_store))
	return _redo

func pending_redo_room() -> String:
	if not _ready() or _index.last_room.is_empty(): return ""
	var room_id: String = _index.last_room
	if _story_runtime_archived():
		var known := _ordinary_classification(room_id)
		if not known.get("ok",false) or known.get("campaign",false) or (not known.get("complete",false) and not standalone_room_proven(room_id)): return ""
	var loaded := _load_redo_journal(room_id)
	return room_id if loaded.get("ok",false) and not loaded.value.get("pending",{}).is_empty() else ""

func photo_request_busy() -> bool:
	# Optional editing shares the existing single-request API with replay reads.
	return busy() or not is_instance_valid(_api) or _api.busy

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
		if not room is Dictionary or room.get("api_version") != 2 or not _id(room.get("room_id")) or _owner not in [room.get("host_id"), room.get("guest_id")]:
			last_error = PlayerCopy.RELAY_ONLINE_SESSION_EDC8E84089EF
			return false
		var chapter_key := Registry.resolve(room)
		observed[room.room_id] = chapter_key
		summaries[room.room_id] = _room_summary(room, chapter_key)
		if not room.room_id in next.room_ids:
			next.room_ids.append(room.room_id)
	# Prune list hints only. Last-room and per-room pending journals remain
	# untouched, including a hidden or unreadable target needing recovery.
	next.room_ids = next.room_ids.filter(func(id: String) -> bool: return observed.has(id))
	_trim_standalone_proofs(next)
	if next.last_room in next.room_ids:
		next.room_ids.erase(next.last_room)
		next.room_ids.push_front(next.last_room)
	if not _write_index(next): return false
	_room_chapters = observed
	_room_summaries = summaries
	return true

func _room_summary(room: Dictionary, chapter_key: String) -> Dictionary:
	return {"room_id": room.room_id, "title": str(Registry.descriptor(chapter_key).get("title", "Saved chapter")),
		"hosted": room.get("host_id") == _owner, "active_role": str(room.get("active_role", "")),
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
	if not _restore_previous_room(): return false
	if coordinator != null and (coordinator.read_only or not coordinator.pending().is_empty()):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_1BE2F671819A
		return false
	return _redo_navigation_ready()

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
	var requested_rules := int(_simulation_versions().get(chapter, Registry.definition(chapter).simulation_version))
	if requested_rules != int(Registry.definition(chapter).simulation_version):
		body["simulation_version"] = requested_rules
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
	# Bundled replay support remains available when a creation gate is disabled.
	# Advertising it must not depend on currently creatable server chapters.
	body["supported_simulation_versions"] = [2, 4, 5, 6, 7, 8]
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
		# The create route checks for an admitted idempotent intent before host
		# access. This exact refusal therefore created no room. Keeping it as an
		# unresolved intent would prevent this player from joining a friend's room.
		# Lost replies, provider outages and all join failures remain recoverable.
		if not response.get("ignored", false) and request.path == "/v2/rooms" and int(response.get("status", 0)) == 402 and response.get("code") == "host_unlock_required":
			if not _ready() or not Canonical.same(_index.pending, request): return ""
			var next := _index.duplicate(true)
			next.pending = {}
			if not _write_index(next): return ""
		_failure(response)
		if request.path == "/v2/rooms" and int(response.get("status", 0)) == 402 and response.get("code") == "host_unlock_required": last_error = PlayerCopy.SHARED_HOST_CREATE_ACCESS
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
	if not _ready() or busy() or not _id(room_id): return false
	var classification := _ordinary_classification(room_id)
	if not classification.get("ok",false) or classification.get("campaign",false) or not classification.get("entry_allowed",true):
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
	var guarded: bool = classification.get("guarded",false)
	if guarded and not standalone_room_proven(room_id):
		return await _probe_standalone(room_id)
	var previous: RefCounted = coordinator
	# A scoped story transport can never be rebound as an ordinary room.
	var candidate: RefCounted = coordinator
	if candidate == null or candidate.campaign_scoped() or candidate.campaign_recovery_only():
		candidate = _ordinary_coordinator()
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
	else:
		_room_chapters.erase(room_id)
		_room_summaries.erase(room_id)
		if coordinator.last_code in ["room_not_found","room_deleted","player_blocked"]:
			_clear_terminal_redo(room_id)
	return success

func register_campaign_owner(owner: RefCounted) -> void:
	_campaign_owner = weakref(owner)

func _ordinary_classification(room_id: String) -> Dictionary:
	if _campaign_owner == null: return {"ok":true,"campaign":false,"guarded":false}
	var owner: RefCounted = _campaign_owner.get_ref()
	if owner == null: return {"ok":false}
	var result: Dictionary = owner.classify_room(room_id)
	result["guarded"] = true
	return result

func _ordinary_coordinator() -> RefCounted:
	var background_writer: Callable = _store.save_scope if _store.get_script() == Store else Callable()
	var result := Coordinator.new(transport,_store.load_scope,_store.save_scope,_identity,Callable(),null,Callable(),Callable(),background_writer)
	result.supported_simulation_versions = _simulation_versions()
	result.accepted_pair_cache = accepted_pair_cache
	return result

func _restore_previous_room() -> bool:
	if coordinator != null or _index.last_room.is_empty(): return true
	var known := _ordinary_classification(_index.last_room)
	if not known.get("ok",false): return false
	if _story_runtime_archived():
		if known.get("campaign",false): return true
		if not standalone_room_proven(_index.last_room):
			last_error = PlayerCopy.MAIN_571E92F64ED1
			return false
	coordinator = _ordinary_coordinator()
	if not _bind_room(_index.last_room):
		last_error = coordinator.last_error
		return false
	if known.get("guarded",false) and (known.get("campaign",false) or not standalone_room_proven(_index.last_room)):
		coordinator.restrict_campaign_recovery()
	return true

func _story_runtime_archived() -> bool:
	var owner: RefCounted = _campaign_owner.get_ref() if _campaign_owner != null else null
	return owner != null and owner.runtime_archived()

func _archived_lifetime() -> Dictionary:
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	if not identity is Dictionary or identity.get("ready") != true or identity.get("player_id") != _owner or identity.get("epoch") != _epoch or not is_instance_valid(_api): return {}
	return {"owner":_owner,"epoch":_epoch,"generation":_generation,"api":_api.get_instance_id(),
		"api_owner":str(_api.player_id),"device_hash":str(_api.device_token).sha256_text(),"base_url":str(_api.base_url)}

func archived_room_kind(room_id: String) -> String:
	# Server observations are only in memory and expire with this API identity.
	var lifetime := _archived_lifetime()
	if lifetime.is_empty() or not Canonical.same(lifetime,_archived_evidence_lifetime): return ""
	return str(_archived_room_evidence.get(room_id,""))

func prepare_archived_navigation() -> bool:
	if not _ready() or busy(): return false
	if not _story_runtime_archived() or _index.last_room.is_empty(): return true
	var room_id: String = _index.last_room
	var known := _ordinary_classification(room_id)
	if not known.get("ok",false): return false
	if known.get("campaign",false) or standalone_room_proven(room_id):
		var restored := _restore_previous_room()
		if restored: last_error = ""
		return restored
	# An absent standalone_ids entry is not evidence of Story ownership. Read
	# the OLD selection first; never load its pending request into the validator.
	var lease := _ordinary_lease()
	_opening = true
	var response := await _call(HTTPClient.METHOD_GET,"/v2/rooms/"+room_id)
	if lease.generation == _generation: _opening = false
	if not _ready() or not Canonical.same(lease,_ordinary_lease()): return false
	var kind := ""
	if response.get("ok") == false and response.get("status") == 409 and response.get("code") == "campaign_client_required":
		kind = "story"
	elif response.get("ok") == true and response.get("status") == 200:
		var validator := Coordinator.new(Callable(),func(_scope: String) -> Dictionary: return {"ok":true,"found":false},
			func(_scope: String,_value: Dictionary) -> Dictionary: return {"ok":false},_identity)
		validator.supported_simulation_versions = _simulation_versions()
		if validator.bind_room(room_id) and validator.verify_room_snapshot(response.get("data")): kind = "ordinary"
	if kind.is_empty():
		last_error = PlayerCopy.MAIN_571E92F64ED1
		return false
	if not _ready() or not Canonical.same(lease,_ordinary_lease()): return false
	var lifetime := _archived_lifetime()
	if not Canonical.same(lifetime,_archived_evidence_lifetime): _archived_room_evidence.clear()
	_archived_evidence_lifetime = lifetime
	_archived_room_evidence[room_id] = kind
	# Restoring an ordinary cache leaves its original draft and pending bytes
	# intact. Existing leave/create/open guards then enforce its recovery lock.
	var restored := _restore_previous_room()
	if restored: last_error = ""
	return restored

func _ordinary_lease() -> Dictionary:
	var owner: RefCounted = _campaign_owner.get_ref() if _campaign_owner != null else null
	return {"owner":_owner,"epoch":_epoch,"generation":_generation,"selection":_room_selection_generation,
		"api_owner":str(_api.player_id),"device_hash":str(_api.device_token).sha256_text(),"base_url":str(_api.base_url),
		"index":Canonical.digest(_index),"coordinator":coordinator.get_instance_id() if coordinator != null else 0,
		"state":coordinator.observe_campaign_state() if coordinator != null else {},
		"campaign_owner":owner.get_instance_id() if owner != null else 0,"campaign_context":owner.classification_context() if owner != null else {},
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
	if not _ready() or not Canonical.same(lease,_ordinary_lease()): return false
	var response := await _call(HTTPClient.METHOD_GET,"/v2/rooms/"+room_id)
	if not _ready() or not Canonical.same(lease,_ordinary_lease()): return false
	var classification := _ordinary_classification(room_id)
	if not classification.get("ok",false) or classification.get("campaign",false) or not classification.get("entry_allowed",true): return false
	if not response.get("ok",false):
		if response.get("code") in ["room_not_found","room_deleted","player_blocked"]:
			_clear_terminal_redo(room_id)
		return _failure(response)
	if not candidate.verify_room_snapshot(response.get("data")):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_C0AD24FCB05A
		return false
	# Finish the fallible native cache work before changing selection. If the
	# later index save fails, only a verified, unselected cache may remain.
	if not candidate.accept_room_snapshot(response.data):
		last_error = candidate.last_error
		return false
	if not _ready() or not Canonical.same(lease,_ordinary_lease()): return false
	classification = _ordinary_classification(room_id)
	if not classification.get("ok",false) or classification.get("campaign",false) or not classification.get("entry_allowed",true): return false
	var next := _index.duplicate(true)
	next.schema_version = 2
	next["standalone_ids"] = next.get("standalone_ids",[]).duplicate()
	_remember_recent(next,room_id)
	if room_id not in next.standalone_ids: next.standalone_ids.append(room_id)
	next.last_room = room_id
	if not _write_index(next): return false
	var saved_lease := lease.duplicate(true)
	saved_lease.index = Canonical.digest(next)
	if not Canonical.same(saved_lease,_ordinary_lease()): return false
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

func campaign_room_bridge(definition: Dictionary, leave_ready: Callable = Callable(), child_factory: Callable = Callable()) -> RefCounted:
	# No Main entry or manifest is enabled here. The composed owner must restore
	# its last bound campaign (including Continue lock) before other navigation.
	_ready()
	var bridge := CampaignRoomBridge.new(definition, transport, _store.load_scope, _store.save_scope,
		_identity, _campaign_source_lease, _adopt_campaign_room, leave_ready, accepted_pair_cache, observe_campaign_source_lease, child_factory)
	_campaign_bridges.append(weakref(bridge))
	return bridge

func _campaign_source_lease() -> Dictionary:
	if photo_request_busy() or not can_leave_for_legacy(): return {}
	var room: Dictionary = coordinator.snapshot() if coordinator != null else {}
	var draft: Dictionary = coordinator.draft() if coordinator != null else {}
	if coordinator != null and (coordinator.read_only or (not _bound_room.is_empty() and room.is_empty())): return {}
	return {"owner":_owner,"epoch":_epoch,"generation":_generation,"selection_generation":_room_selection_generation,
		"coordinator":coordinator.get_instance_id() if coordinator != null else 0,"bound_room":_bound_room,
		"last_room":_index.last_room,"snapshot":Canonical.digest(room),"draft":Canonical.digest(draft)}

func campaign_selection_generation() -> int:
	return _room_selection_generation

func capture_campaign_source_lease() -> Dictionary:
	# Mutating lobby actions call this after source readiness, then compare the
	# exact lease again before replacing their bound owner after network I/O.
	return _campaign_source_lease()

func capture_campaign_restore_lease(room_id: String) -> Dictionary:
	# Same-room restoration keeps a pending turn reachable without leaving it.
	if not _ready() or photo_request_busy() or not _index.pending.is_empty() or _index.last_room != room_id: return {}
	var state: Dictionary = coordinator.observe_campaign_state() if coordinator != null else {}
	if coordinator != null and (_bound_room != room_id or state.is_empty() or not state.draft_ready or state.snapshot.get("room_id") != room_id): return {}
	return {"owner":_owner,"epoch":_epoch,"generation":_generation,"selection_generation":_room_selection_generation,
		"room_id":room_id,"coordinator":coordinator.get_instance_id() if coordinator != null else 0,"state":state}

func restore_campaign_selected(target: RefCounted, lease: Dictionary) -> bool:
	if target == null or target.get_script() != Coordinator or target.read_only or target.busy() or lease.is_empty(): return false
	if not Canonical.same(capture_campaign_restore_lease(str(lease.get("room_id",""))),lease): return false
	var state: Dictionary = target.observe_campaign_state()
	if state.is_empty() or not state.draft_ready or state.snapshot.get("room_id") != lease.room_id: return false
	if not lease.state.is_empty() and not Canonical.same(lease.state,state): return false
	# No index save or selection change. The owner verifies publication and pin.
	if coordinator != null and coordinator != target: coordinator.invalidate_identity()
	coordinator = target
	_bound_room = lease.room_id
	_room_selection_generation += 1
	last_error = ""
	return true

func _adopt_campaign_room(target: RefCounted, lease: Dictionary) -> bool:
	if target == null or target.get_script() != Coordinator or target.read_only or target.busy() or lease.is_empty() or not Canonical.same(_campaign_source_lease(), lease): return false
	var room: Dictionary = target.snapshot()
	if room.is_empty() or not _id(room.get("room_id")) or _owner not in [room.get("host_id"),room.get("guest_id")]: return false
	var next := _index.duplicate(true)
	next.last_room = room.room_id
	# Child rooms are not appended to the ordinary room list. The existing
	# durable last-room field still restores their pending recovery after exit.
	if not _valid_index(next) or not _store.save_scope("relay-lobby-v2:"+_owner, next).get("ok",false):
		last_error = PlayerCopy.RELAY_ONLINE_SESSION_E491F4F0F93A
		return false
	# Even injected synchronous stores cannot return under a replaced owner.
	var identity: Dictionary = _identity.call()
	if _generation != lease.generation or identity.get("ready") != true or identity.get("player_id") != lease.owner or identity.get("epoch") != lease.epoch:
		invalidate_identity()
		return false
	_index = next
	coordinator = target
	_bound_room = room.room_id
	_room_selection_generation += 1
	last_error = ""
	return true

func transport(request: Dictionary) -> Dictionary:
	return await _transport(request,false)

func campaign_transport(request: Dictionary) -> Dictionary:
	return await _transport(request,true)

func _transport(request: Dictionary, campaign: bool) -> Dictionary:
	if not _ready() or request.get("owner_player_id") != _owner or request.get("identity_epoch") != _epoch:
		return {"ok": false, "status": 401, "code": "identity_changed"}
	if request.method == HTTPClient.METHOD_POST and not mutations_enabled():
		return {"ok": false, "status": 503, "code": "v2_mutations_disabled"}
	return await _call(request.method, request.path, request.body,campaign)

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

func _call(method: int, path: String, body: Dictionary = {}, campaign: bool = false) -> Dictionary:
	if not _ready() or _busy or _api.busy or _api.player_id != _owner or str(_api.device_token).is_empty():
		return {"ok": false, "status": 0, "code": "request_busy"}
	if campaign and not _api.has_method("request_campaign_json"):
		return {"ok":false,"status":0,"code":"campaign_transport_unavailable"}
	var generation := _generation
	var owner := _owner
	var epoch := _epoch
	_busy = true
	# request_json captures these verified headers synchronously before await.
	var response: Dictionary = await _api.request_campaign_json(method,path,body) if campaign else await _api.request_json(method,path,body)
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
	if _campaign_owner != null:
		var owner: RefCounted = _campaign_owner.get_ref()
		if owner == null or not owner.ordinary_entry_allowed():
			last_error = PlayerCopy.RELAY_ONLINE_SESSION_D8B61E4543F4
			return false
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
	if _story_runtime_archived():
		var known := _ordinary_classification(previous)
		if not known.get("ok",false): return false
		if known.get("campaign",false): return true
		if not standalone_room_proven(previous): return false
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
	if not Coordinator._bounded(value, 32768) or (value.get("schema_version") != 1 and value.get("schema_version") != 2) or value.size() != (6 if value.get("schema_version") == 2 else 5) or value.get("owner_player_id") != _owner or not value.get("room_ids") is Array or value.room_ids.size() > 128 or not value.get("last_room") is String or (value.last_room != "" and not _id(value.last_room)) or not value.get("pending") is Dictionary:
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
	if pending.size() != 3 or pending.get("path") not in ["/v2/rooms", "/v2/rooms/join"] or not pending.get("body") is Dictionary or pending.get("request_hash") != Canonical.digest({"path": pending.path, "body": pending.body}):
		return false
	var body: Dictionary = pending.body
	if pending.path == "/v2/rooms":
		var optional_pin: bool = body.has("simulation_version")
		return body.size() == (5 if optional_pin else 4) and body.get("idempotency_key") is String and body.idempotency_key.length() == 36 and not Registry.resolve(body).is_empty() and (not optional_pin or (Registry._integer(body.simulation_version) and int(body.simulation_version) in Registry.supported_rules(Registry.resolve(body)) and int(body.simulation_version) != int(Registry.definition(Registry.resolve(body)).simulation_version)))
	var optional_versions: bool = body.has("supported_simulation_versions")
	return body.size() == (2 if optional_versions else 1) and body.get("invite_code") is String and body.invite_code.length() == 20 and (not optional_versions or Canonical.same(body.supported_simulation_versions, [2, 4, 5]) or Canonical.same(body.supported_simulation_versions, [2, 4, 5, 6]) or Canonical.same(body.supported_simulation_versions, [2, 4, 5, 6, 7]) or Canonical.same(body.supported_simulation_versions, [2, 4, 5, 6, 7, 8]))

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

func safety_context() -> Dictionary:
	if not _ready() or coordinator == null: return {}
	var room: Dictionary = coordinator.snapshot()
	var peer: Variant = room.get("guest_id") if room.get("host_id") == _owner else room.get("host_id")
	return {"room_family": "relay", "room_id": room.get("room_id"), "peer_id": peer} if Safety.Store.id(peer) else {}

func partner_photos_allowed(reference: Dictionary) -> bool:
	if reference.get("own", false): return true
	if not _ready(): return false
	return Safety.Store.new().partner_allowed(_owner, "relay", str(reference.get("room_id", "")), str(reference.get("owner_player_id", "")))

func observe_campaign_source_lease() -> Dictionary:
	# Unlike the authoritative lease, this never restores an index/coordinator.
	if not _index_loaded or _index.is_empty() or photo_request_busy(): return {}
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	if not identity is Dictionary or identity.get("ready") != true or identity.get("player_id") != _owner or identity.get("epoch") != _epoch: return {}
	if not _index.pending.is_empty() or (coordinator == null and not _index.last_room.is_empty()): return {}
	var room: Dictionary = {}
	var draft: Dictionary = {}
	if coordinator != null:
		var observed: Dictionary = coordinator.observe_campaign_state()
		if observed.is_empty() or not observed.draft_ready or not observed.pending.is_empty(): return {}
		room = observed.snapshot
		draft = observed.draft
		if not _bound_room.is_empty() and room.is_empty(): return {}
	return {"owner":_owner,"epoch":_epoch,"generation":_generation,"selection_generation":_room_selection_generation,
		"coordinator":coordinator.get_instance_id() if coordinator != null else 0,"bound_room":_bound_room,
		"last_room":_index.last_room,"snapshot":Canonical.digest(room),"draft":Canonical.digest(draft)}

func auxiliary_context_factory() -> RefCounted:
	# Unconfigured legacy callers keep their ordinary transport. Once an owner
	# is registered, even a failed restore supplies an explicit held factory.
	if _campaign_owner == null: return null
	if not _ready(): return AuxiliaryContext.new(self,null,{})
	var owner: RefCounted = _campaign_owner.get_ref() if _campaign_owner != null else null
	if owner != null and not owner.restore_owner(): return AuxiliaryContext.new(self,owner,{})
	if _auxiliary_factory != null and _auxiliary_factory.current(): return _auxiliary_factory
	var lifetime := {"owner":_owner,"epoch":_epoch,"generation":_generation,"api_instance":_api.get_instance_id(),
		"device_hash":str(_api.device_token).sha256_text(),"base_url":str(_api.base_url),
		"campaign_owner":owner.get_instance_id() if owner != null else (0 if _campaign_owner == null else -1),
		"retirement":owner.auxiliary_retirement() if owner != null else -1}
	_auxiliary_factory = AuxiliaryContext.new(self,owner,lifetime)
	return _auxiliary_factory

func auxiliary_lifetime_current(value: Dictionary, owner: RefCounted) -> bool:
	# Pure identity observation: ordinary selection and deliberate story release
	# do not retire older photos. Explicit invalidation does, even at one epoch.
	if value.is_empty(): return false
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	if not identity is Dictionary or identity.get("ready") != true or identity.get("player_id") != value.owner or identity.get("epoch") != value.epoch or _generation != value.generation: return false
	if not is_instance_valid(_api) or _api.get_instance_id() != value.get("api_instance",-1) or str(_api.player_id) != value.owner or str(_api.device_token).sha256_text() != value.device_hash or str(_api.base_url) != value.base_url: return false
	if value.campaign_owner == 0: return _campaign_owner == null
	return owner != null and _campaign_owner != null and _campaign_owner.get_ref() == owner and owner.get_instance_id() == value.campaign_owner and owner.auxiliary_retirement() == value.retirement

func auxiliary_safety_transport(request: Dictionary, campaign: bool) -> Dictionary:
	# Safety stays available while gameplay writes are paused. This narrow
	# dispatch still requires exact identity and a typed room-bound safety POST.
	if not _ready() or request.get("owner_player_id") != _owner or request.get("identity_epoch") != _epoch: return {"ok":false,"ignored":true,"status":401,"code":"identity_changed"}
	if request.get("method") != HTTPClient.METHOD_POST or request.get("path") not in ["/v1/safety/block","/v1/safety/report"] or not request.get("body") is Dictionary or request.body.get("room_family") != "relay" or not _id(request.body.get("room_id")): return {"ok":false,"ignored":true,"status":0,"code":"campaign_route_unavailable"}
	return await _call(request.method,request.path,request.body,campaign)

func auxiliary_photo_ack_transport(request: Dictionary, campaign: bool) -> Dictionary:
	# Verified photo delivery uses its existing independent server flag. It is
	# not a new gameplay contribution, photo replacement or deletion.
	if not _ready() or request.get("owner_player_id") != _owner or request.get("identity_epoch") != _epoch: return {"ok":false,"ignored":true,"status":401,"code":"identity_changed"}
	if not AuxiliaryContext.delivery_ack(request): return {"ok":false,"ignored":true,"status":0,"code":"campaign_route_unavailable"}
	return await _call(request.method,request.path,request.body,campaign)

func terminal_lifetime(owner: RefCounted) -> Dictionary:
	# Prepare only this identity's ordinary index. No Owner callback, child
	# restoration, auxiliary factory or HTTP is involved during cold restore.
	if owner == null or _campaign_owner == null or _campaign_owner.get_ref() != owner or not _identity.is_valid(): return {}
	_ready()
	# A malformed ordinary index must not hide independently valid story saves.
	# Its readiness is checked separately before terminal writes or retirement.
	var identity: Variant = _identity.call()
	if not identity is Dictionary or identity.get("ready") != true or not _id(identity.get("player_id")) or identity.player_id != _owner or identity.get("epoch") != _epoch: return {}
	if _campaign_owner == null or _campaign_owner.get_ref() != owner or not is_instance_valid(_api) or str(_api.player_id) != _owner: return {}
	return {"owner":_owner,"epoch":_epoch,"generation":_generation,
		"device_hash":str(_api.device_token).sha256_text(),"base_url":str(_api.base_url),"api_instance":_api.get_instance_id(),
		"campaign_owner":owner.get_instance_id(),"retirement":owner.auxiliary_retirement()}

func terminal_lifetime_current(value: Dictionary, owner: RefCounted) -> bool:
	return auxiliary_lifetime_current(value,owner)

func terminal_index_ready() -> bool:
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	return identity is Dictionary and identity.get("ready") == true and identity.get("player_id") == _owner and identity.get("epoch") == _epoch and _index_loaded and _valid_index(_index)

func standalone_room_proven(room_id: String) -> bool:
	# Pure already-loaded index observation; never calls back into Owner.
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	return identity is Dictionary and identity.get("ready") == true and identity.get("player_id") == _owner and identity.get("epoch") == _epoch and _index_loaded and _valid_index(_index) and (room_id in _index.get("standalone_ids",[]) or archived_room_kind(room_id) == "ordinary")

func retire_campaign_selection(anchor: String) -> bool:
	# Durable terminal proof replaces the ordinary leave guard for this exact
	# story only. Raw pending operations, drafts and room caches remain intact.
	if not _id(anchor) or _retiring_selection or not _ready(): return false
	var owner: RefCounted = _campaign_owner.get_ref() if _campaign_owner != null else null
	if owner == null or not owner.refresh_terminal_classification(): return false
	var lease := _terminal_selection_lease(owner,anchor)
	if lease.is_empty(): return false
	var last_status: String = owner.terminal_room_status(anchor,str(_index.last_room))
	var bound_status: String = owner.terminal_room_status(anchor,_bound_room)
	if last_status not in ["released","unrelated"] or bound_status not in ["released","unrelated"]: return false
	var actual := {}
	if coordinator != null:
		if coordinator.get_script() != Coordinator: return false
		actual = coordinator.observe_room_binding()
		if actual.is_empty() or actual.owner != _owner or actual.epoch != _epoch or actual.room_id != _bound_room: return false
		if owner.terminal_room_status(anchor,str(actual.room_id)) != bound_status: return false
	if not Canonical.same(lease,_terminal_selection_lease(owner,anchor)): return false
	if last_status != "released" and bound_status != "released": return true
	_retiring_selection = true
	var next := _index.duplicate(true)
	if last_status == "released":
		next.last_room = ""
		var saved: Variant = _store.save_scope("relay-lobby-v2:"+str(lease.owner),next.duplicate(true))
		if not Canonical.same(lease,_terminal_selection_lease(owner,anchor)):
			if _generation == lease.generation: _retiring_selection = false
			return false
		if not saved is Dictionary or saved.get("ok") != true:
			if _generation == lease.generation: _retiring_selection = false
			last_error = PlayerCopy.RELAY_ONLINE_SESSION_E491F4F0F93A
			return false
		if not owner.refresh_terminal_classification():
			if _generation == lease.generation: _retiring_selection = false
			return false
		if not Canonical.same(lease,_terminal_selection_lease(owner,anchor)):
			if _generation == lease.generation: _retiring_selection = false
			return false
	# Synchronous Store callbacks cannot replace the classified pointer or its
	# original Owner while an older completion changes the in-memory selection.
	if owner.terminal_room_status(anchor,str(_index.last_room)) != last_status or owner.terminal_room_status(anchor,_bound_room) != bound_status or not Canonical.same(lease,_terminal_selection_lease(owner,anchor)):
		if _generation == lease.generation: _retiring_selection = false
		return false
	if last_status == "released": _index = next
	if bound_status == "released":
		if coordinator != null: coordinator.invalidate_identity()
		coordinator = null
		_bound_room = ""
	_room_selection_generation += 1
	_retiring_selection = false
	last_error = ""
	return true

func _terminal_selection_lease(owner: RefCounted, anchor: String) -> Dictionary:
	if owner == null or _campaign_owner == null or _campaign_owner.get_ref() != owner or _opening or _busy or not _index_loaded: return {}
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	if not identity is Dictionary or identity.get("ready") != true or identity.get("player_id") != _owner or identity.get("epoch") != _epoch or not _valid_index(_index): return {}
	if not owner.terminal_anchor_released(anchor): return {}
	return {"owner":_owner,"epoch":_epoch,"generation":_generation,"selection_generation":_room_selection_generation,
		"campaign_owner":owner.get_instance_id(),"retirement":owner.auxiliary_retirement(),"campaign_context":owner.classification_context(),
		"coordinator":coordinator.get_instance_id() if coordinator != null else 0,"coordinator_binding":coordinator.observe_room_binding() if coordinator != null and coordinator.get_script() == Coordinator else {},"bound_room":_bound_room,"index":Canonical.digest(_index)}
