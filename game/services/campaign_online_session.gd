extends RefCounted
## Unenabled owner adapter. The lobby is the sole durable writer of its bound
## campaign pointer; every eventual navigation entry must use its leave guard.
const Protocol = preload("res://services/campaign_protocol.gd")
const Campaign = preload("res://services/campaign_session.gd")
const Store = preload("res://services/relay_online_store.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const MAX_HISTORY := 128 # Local archival references, not server active capacity.
var last_code := ""
var read_only := false
var _online: RefCounted
var _identity: Callable
var _leave_ready: Callable
var _store: RefCounted
var _definitions: Dictionary = {}
var _catalog_valid := true
var _lobby: Dictionary = {}
var _campaign: RefCounted
var _bridge: RefCounted
var _owner := ""
var _epoch := -1
var _generation := 0
var _loaded := false
var _busy := false

func _init(online: RefCounted, identity: Callable, bundled_definitions: Array, leave_ready: Callable,
		storage: RefCounted = null) -> void:
	_online = online
	_identity = identity
	_leave_ready = leave_ready
	_store = Store.new() if storage == null else storage
	for value: Variant in bundled_definitions:
		if not Protocol.definition_valid(value):
			_catalog_valid = false
			break
		var pin := Canonical.digest(Protocol.key(value))
		if _definitions.has(pin):
			_catalog_valid = false
			break
		_definitions[pin] = value.duplicate(true)

func invalidate_identity() -> void:
	_generation += 1
	_drop_bound()
	_lobby = {}
	_owner = ""
	_epoch = -1
	_loaded = false
	_busy = false
	read_only = false
	last_code = "identity_changed"

func restore_owner(retry: bool = false) -> bool:
	var identity := _current_identity()
	if identity.is_empty():
		invalidate_identity()
		return _error("identity_unavailable")
	if identity.player_id != _owner or int(identity.epoch) != _epoch:
		invalidate_identity()
		_owner = identity.player_id
		_epoch = int(identity.epoch)
	if _loaded and not retry: return not read_only
	if _busy: return _error("request_busy")
	if not _catalog_valid: return _hold("unsupported_campaign_catalog")
	_generation += 1
	_drop_bound()
	_loaded = true
	read_only = false
	var context := _context()
	var loaded: Variant = _store.load_scope(_scope())
	if not _same(context): return _identity_changed(context)
	if not loaded is Dictionary or loaded.get("ok") != true: return _hold("campaign_storage_unavailable")
	var value: Variant = loaded.get("value") if loaded.get("found",false) else _empty_lobby()
	if not _valid_lobby(value): return _hold("unsupported_campaign_lobby")
	_lobby = value.duplicate(true)
	return _load_bound()

func bind_campaign(anchor: String, campaign_key: Dictionary) -> bool:
	if _busy or not restore_owner(): return false
	var reference := {"campaign_room_id":anchor,"campaign_key":campaign_key.duplicate(true)}
	if not _reference_valid(reference) or _definition(reference).is_empty(): return _error("campaign_unavailable")
	if Canonical.same(_lobby.bound_campaign,reference): return true
	if not can_leave(): return false
	var next := _lobby.duplicate(true)
	var found := false
	for existing: Dictionary in next.campaigns:
		if existing.campaign_room_id == anchor:
			if not Canonical.same(existing,reference): return _error("campaign_pin_conflict")
			found = true
	if not found:
		if next.campaigns.size() >= MAX_HISTORY: return _error("campaign_history_full")
		next.campaigns.append(reference)
	next.bound_campaign = reference
	# The pointer is durable before any new journal read or Continue request.
	if not _persist_lobby(next): return false
	_generation += 1
	_drop_bound()
	return _load_bound()

func can_leave() -> bool:
	# Local reads only. Never lookup a receipt, refresh, submit or select here.
	if _busy or not restore_owner() or not _source_ready(): return false
	if _campaign != null:
		if _campaign.read_only or _campaign.busy() or not _campaign.pending().is_empty(): return _error("campaign_pending")
		if _campaign.view().get("activation") != null: return _error("campaign_activation_pending")
		if _needs_adoption(): return _error("campaign_adoption_pending")
	last_code = ""
	return true

func release_for_ordinary() -> bool:
	if not can_leave(): return false
	if _lobby.bound_campaign.is_empty(): return true
	var next := _lobby.duplicate(true)
	next.bound_campaign = {}
	if not _persist_lobby(next): return false
	_generation += 1
	_drop_bound()
	last_code = ""
	return true

func busy() -> bool: return _busy
func bound_campaign() -> Dictionary: return _lobby.get("bound_campaign",{}).duplicate(true) if restore_owner() else {}
func campaign_references() -> Array: return _lobby.get("campaigns",[]).duplicate(true) if restore_owner() else []
func view() -> Dictionary: return _campaign.view() if restore_owner() and _campaign != null else {}
func pending() -> Dictionary: return _campaign.pending() if restore_owner() and _campaign != null else {}
func selected_room() -> String: return _campaign.selected_room() if restore_owner() and _campaign != null else ""
func definition() -> Dictionary: return _definition(_lobby.bound_campaign) if restore_owner() else {}

func refresh() -> bool:
	return await _run_control("refresh")

func select_current() -> bool:
	return await _run_control("select_current")

func continue_current() -> bool:
	if _busy or not restore_owner() or _campaign == null or _needs_adoption() or not _source_ready(): return _error("source_not_ready")
	return await _run_control("continue_from")

func retry_continue() -> bool:
	return await _run_control("retry")

func adopt_selected() -> bool:
	if _busy or not restore_owner() or _bridge == null: return _error("campaign_unavailable")
	var okay: bool = _bridge.adopt_selected()
	last_code = "" if okay else _bridge.last_code
	return okay

func reopen_selected() -> bool:
	if _busy or not restore_owner() or _bridge == null: return _error("campaign_unavailable")
	_busy = true
	var context := _context()
	var bridge: RefCounted = _bridge
	var okay: bool = await bridge.reopen_selected()
	if not _same(context): return _identity_changed(context)
	_busy = false
	last_code = "" if okay else bridge.last_code
	return okay

func story_seen(index: int, phase: String) -> bool:
	return restore_owner() and _campaign != null and _campaign.story_seen(index,phase)

func mark_story_seen(index: int, phase: String) -> bool:
	if _busy or not restore_owner() or _campaign == null: return _error("campaign_unavailable")
	var context := _context()
	var okay: bool = _campaign.mark_story_seen(index,phase)
	if not _same(context): return _identity_changed(context)
	last_code = "" if okay else _campaign.last_code
	return okay

func _run_control(method: String) -> bool:
	if _busy or not restore_owner() or _campaign == null: return _error("campaign_unavailable")
	_busy = true
	var context := _context()
	var campaign: RefCounted = _campaign
	var okay: bool
	if method == "continue_from": okay = await campaign.continue_from(_online.coordinator)
	else: okay = await campaign.call(method)
	if not _same(context): return _identity_changed(context)
	_busy = false
	last_code = "" if okay else campaign.last_code
	return okay

func _load_bound() -> bool:
	if _lobby.bound_campaign.is_empty():
		last_code = ""
		return true
	var bundled := _definition(_lobby.bound_campaign)
	if bundled.is_empty(): return _hold("bound_campaign_unavailable")
	_bridge = _online.campaign_room_bridge(bundled,_leave_ready)
	_campaign = Campaign.new(_online.transport,_store.load_scope,_store.save_scope,_identity,_bridge.validate_target,_bridge.selection_ready)
	var context := _context()
	var loaded: bool = _campaign.bind(_lobby.bound_campaign.campaign_room_id,bundled)
	if not _same(context): return _identity_changed(context)
	if not loaded: return _hold(_campaign.last_code)
	if not _bridge.bind_campaign(_campaign): return _hold("campaign_bridge_unavailable")
	last_code = ""
	return true

func _drop_bound() -> void:
	if _bridge != null: _bridge.invalidate()
	if _campaign != null: _campaign.invalidate_identity()
	_bridge = null
	_campaign = null

func _source_ready() -> bool:
	if not _leave_ready.is_valid() or _leave_ready.call() != true: return _error("previous_room_busy")
	if _online == null or _online.photo_request_busy() or not _online.can_leave_for_legacy(): return _error("previous_room_pending")
	return true

func _needs_adoption() -> bool:
	var publication: Dictionary = _campaign.view()
	if publication.is_empty(): return false
	# Matching room pointers do not prove that the published child was activated.
	# Only a validated later publication may discharge this control2 debt.
	if publication.activation != null: return true
	if publication.state in ["continuing","deleting"]: return true
	var room: String = publication.chapters[int(publication.current_index)].room_id
	return _campaign.selected_room() != room or _online.last_room() != room

func _definition(reference: Dictionary) -> Dictionary:
	if not _reference_valid(reference): return {}
	return _definitions.get(Canonical.digest(reference.campaign_key),{}).duplicate(true)

func _reference_valid(value: Variant) -> bool:
	return Protocol.exact(value,["campaign_room_id","campaign_key"]) and Protocol.id_valid(value.campaign_room_id) and Protocol.key_valid(value.campaign_key)

func _valid_lobby(value: Variant) -> bool:
	if not Protocol.bounded(value,49152,6144,12) or not Protocol.exact(value,["schema_version","owner_player_id","campaigns","bound_campaign","pending"]): return false
	if value.schema_version != 1 or value.owner_player_id != _owner or not value.campaigns is Array or value.campaigns.size() > MAX_HISTORY or not value.bound_campaign is Dictionary or not value.pending is Dictionary or not value.pending.is_empty(): return false
	var anchors := {}
	var has_bound: bool = value.bound_campaign.is_empty()
	for reference: Variant in value.campaigns:
		if not _reference_valid(reference) or anchors.has(reference.campaign_room_id): return false
		anchors[reference.campaign_room_id] = true
		if Canonical.same(reference,value.bound_campaign): has_bound = true
	return has_bound

func _empty_lobby() -> Dictionary:
	return {"schema_version":1,"owner_player_id":_owner,"campaigns":[],"bound_campaign":{},"pending":{}}

func _persist_lobby(next: Dictionary) -> bool:
	if read_only or not _valid_lobby(next): return _error("unsupported_campaign_lobby")
	var context := _context()
	var result: Variant = _store.save_scope(_scope(),next.duplicate(true))
	if not _same(context): return _identity_changed(context)
	if not result is Dictionary or result.get("ok") != true: return _error("campaign_storage_unavailable")
	_lobby = next
	last_code = ""
	return true

func _scope() -> String: return "relay-campaign-lobby-v1:"+_owner
func _context() -> Dictionary: return {"owner":_owner,"epoch":_epoch,"generation":_generation}
func _same(context: Dictionary) -> bool:
	var identity := _current_identity()
	return not identity.is_empty() and identity.player_id == context.owner and int(identity.epoch) == context.epoch and _generation == context.generation
func _current_identity() -> Dictionary:
	var value: Variant = _identity.call() if _identity.is_valid() else null
	return value.duplicate(true) if value is Dictionary and value.get("ready") == true and Protocol.id_valid(value.get("player_id")) and Protocol.integer(value.get("epoch")) else {}
func _identity_changed(context: Dictionary) -> bool:
	# A superseded request cannot discard a newer owner already restored by UI.
	if context.generation != _generation: return false
	invalidate_identity()
	return false
func _error(code: String) -> bool:
	last_code = code
	return false
func _hold(code: String) -> bool:
	read_only = true
	return _error(code)
