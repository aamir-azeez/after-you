extends RefCounted
## Explicit intent/receipt journal only. Never retires gameplay or lobby state.
## The retained context's current() guard must compare the original API object,
## backend, credentials and lifetime; connectivity/capability policy lives above.
const Protocol = preload("res://services/campaign_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Store = preload("res://services/relay_online_store.gd")
const MAX_ENTRIES := 128
const MAX_BYTES := 49152
const MAX_NODES := 4096
const HINT_CODE := "campaign_terminal_reconciliation_required"
var last_code := ""
var read_only := false
var _transport: Callable
var _transport_current: Callable
var _transport_lifetime: RefCounted
var _identity: Callable
var _store: RefCounted
var _state: Dictionary = {}
var _owner := ""
var _epoch := -1
var _generation := 0
var _loaded := false
var _busy := false
var _retired := false

func _init(transport: Callable, identity: Callable, transport_current: Callable,
		storage: RefCounted = null, transport_lifetime: RefCounted = null) -> void:
	_transport = transport
	_identity = identity
	_transport_current = transport_current
	_store = Store.new() if storage == null else storage
	_transport_lifetime = transport_lifetime
	if _transport_lifetime == null and transport.is_valid():
		var target: Object = transport.get_object()
		if target is RefCounted: _transport_lifetime = target

static func path_for(anchor: String) -> String:
	return "/v2/campaigns/"+anchor+"/reconcile-deletion" if Protocol.id_valid(anchor) else ""

static func parse_hint(response: Variant) -> String:
	# Pure parsing of an authenticated explicit list result. This is discovery,
	# never evidence sufficient to retire a local lock or clear a saved intent.
	if not Protocol.bounded(response,4096,64,5) or not response is Dictionary: return ""
	if not response.get("ok") is bool or response.ok != false or not Protocol.integer(response.get("status")) or response.status != 409 or response.get("code") != HINT_CODE: return ""
	var data: Variant = response.get("data")
	if not Protocol.exact(data,["error"]): return ""
	var error: Variant = data.error
	if not Protocol.exact(error,["code","campaign_room_id"]) and not Protocol.exact(error,["code","campaign_room_id","retryable"]): return ""
	if error.has("retryable") and (not error.retryable is bool or error.retryable != false): return ""
	return str(error.campaign_room_id) if error.code == HINT_CODE and Protocol.id_valid(error.campaign_room_id) else ""

static func receipt_valid(value: Variant, owner: String, anchor: String) -> bool:
	return Protocol.id_valid(owner) and Protocol.id_valid(anchor) and Protocol.bounded(value,1024,24,3) and Protocol.exact(value,["schema_version","operation","status","player_id","campaign_room_id"]) and Protocol.integer(value.schema_version,1,1) and value.operation == "campaign_terminal_cleanup" and value.status == "released" and value.player_id == owner and value.campaign_room_id == anchor

func invalidate_identity() -> void:
	_generation += 1
	_busy = false
	_loaded = false
	_state = {}
	_owner = ""
	_epoch = -1
	read_only = false
	last_code = "identity_changed"

func retire() -> void:
	# Same-owner/epoch retirement also invalidates all draining callbacks.
	_retired = true
	invalidate_identity()
	last_code = "campaign_context_changed"

func restore_owner(retry: bool = false) -> bool:
	if _retired or not _guard(): return _error("campaign_context_changed")
	var identity := _current_identity()
	if identity.is_empty():
		invalidate_identity()
		return _error("identity_unavailable")
	if identity.player_id != _owner or int(identity.epoch) != _epoch:
		invalidate_identity()
		_owner = identity.player_id
		_epoch = int(identity.epoch)
	if _busy: return _error("request_busy")
	if _loaded and not retry: return not read_only
	_generation += 1
	_busy = true
	_loaded = true
	read_only = false
	var context := _context()
	var loaded: Variant = _store.load_scope(_scope())
	if not _same(context): return _changed(context)
	_busy = false
	if not loaded is Dictionary or loaded.get("ok") != true: return _hold("campaign_storage_unavailable")
	var value: Variant = loaded.get("value") if loaded.get("found",false) else _empty()
	if not _valid_state(value): return _hold("unsupported_campaign_terminal_save")
	_state = value.duplicate(true)
	last_code = ""
	return true

func begin(anchor: String) -> bool:
	# Staging and sending are deliberately separate explicit operations.
	if not restore_owner() or read_only: return false
	if not Protocol.id_valid(anchor): return _error("invalid_campaign_terminal_request")
	if not _state.pending.is_empty():
		return true if _state.pending.campaign_room_id == anchor else _error("campaign_terminal_pending")
	if _state.released.size() >= MAX_ENTRIES and _find_receipt(anchor).is_empty(): return _error("campaign_history_full")
	_busy = true
	var context := _context()
	var next := _state.duplicate(true)
	next.pending = {"campaign_room_id":anchor,"path":path_for(anchor),"body":{"schema_version":1}}
	var saved := _persist(context,next)
	_leave(context)
	return saved

func reconcile() -> bool:
	if not restore_owner() or read_only: return false
	if _state.pending.is_empty(): return _error("operation_not_pending")
	_busy = true
	var context := _context()
	var intent: Dictionary = _state.pending.duplicate(true)
	# The original exact request is durable before the transport can observe it.
	if not _same(context): return _changed(context)
	var response: Variant = await _transport.call({"method":HTTPClient.METHOD_POST,"path":intent.path,
		"body":intent.body.duplicate(true),"owner_player_id":_owner,"identity_epoch":_epoch})
	if not _same(context): return _changed(context)
	var okay := _receive(context,intent,response)
	_leave(context)
	return okay

func pending() -> Dictionary:
	return _state.pending.duplicate(true) if _readable() else {}

func terminal_receipt(anchor: String) -> Dictionary:
	# Permanent terminal proof remains available during another link-cleanup
	# attempt. It must never restore authority to an old active gameplay journal.
	return _find_receipt(anchor).duplicate(true) if _readable() else {}

func released_receipts() -> Array:
	return _state.released.duplicate(true) if _readable() else []

func cleanup_settled(anchor: String) -> bool:
	return _readable() and not _find_receipt(anchor).is_empty() and (_state.pending.is_empty() or _state.pending.campaign_room_id != anchor)

func busy() -> bool: return _busy

func _receive(context: Dictionary, intent: Dictionary, response: Variant) -> bool:
	if not Protocol.bounded(response,4096,64,5) or not response is Dictionary: return _error("invalid_campaign_terminal_reply")
	if not response.get("ok") is bool or response.ok != true: return _error(str(response.get("code","connection_interrupted")))
	if not Protocol.integer(response.get("status")) or response.status != 200 or not receipt_valid(response.get("data"),context.owner,intent.campaign_room_id): return _error("invalid_campaign_terminal_reply")
	if not Canonical.same(_state.pending,intent): return _error("campaign_context_changed")
	var next := _state.duplicate(true)
	if _find_receipt(intent.campaign_room_id).is_empty(): next.released.append(response.data.duplicate(true))
	next.pending = {}
	return _persist(context,next)

func _persist(context: Dictionary, next: Dictionary) -> bool:
	if read_only or not _same(context): return _changed(context)
	if not _valid_state(next): return _error("unsupported_campaign_terminal_save")
	var saved: Variant = _store.save_scope("relay-campaign-terminal-v1:"+str(context.owner),next.duplicate(true))
	if not _same(context): return _changed(context)
	if not saved is Dictionary or saved.get("ok") != true: return _error("campaign_storage_unavailable")
	_state = next.duplicate(true)
	last_code = ""
	return true

func _valid_state(value: Variant) -> bool:
	if not Protocol.bounded(value,MAX_BYTES,MAX_NODES,7) or not Protocol.exact(value,["schema_version","owner_player_id","pending","released"]): return false
	if not Protocol.integer(value.schema_version,1,1) or value.owner_player_id != _owner or not value.pending is Dictionary or not value.released is Array or value.released.size() > MAX_ENTRIES: return false
	var anchors := {}
	for receipt: Variant in value.released:
		if not receipt is Dictionary or not receipt_valid(receipt,_owner,str(receipt.get("campaign_room_id",""))) or anchors.has(receipt.campaign_room_id): return false
		anchors[receipt.campaign_room_id] = true
	if not value.pending.is_empty():
		var item: Dictionary = value.pending
		if not Protocol.exact(item,["campaign_room_id","path","body"]) or not Protocol.id_valid(item.campaign_room_id) or item.path != path_for(item.campaign_room_id) or not Protocol.exact(item.body,["schema_version"]) or not Protocol.integer(item.body.schema_version,1,1): return false
		anchors[item.campaign_room_id] = true
	return anchors.size() <= MAX_ENTRIES

func _empty() -> Dictionary:
	return {"schema_version":1,"owner_player_id":_owner,"pending":{},"released":[]}

func _find_receipt(anchor: String) -> Dictionary:
	for receipt: Dictionary in _state.get("released",[]):
		if receipt.campaign_room_id == anchor: return receipt
	return {}

func _current_identity() -> Dictionary:
	var value: Variant = _identity.call() if _identity.is_valid() else null
	return value.duplicate(true) if value is Dictionary and value.get("ready") == true and Protocol.id_valid(value.get("player_id")) and Protocol.integer(value.get("epoch")) else {}

func _guard() -> bool:
	if _retired or _transport_lifetime == null or not _transport.is_valid() or not _transport_current.is_valid(): return false
	var guarded: Variant = _transport_current.call()
	return guarded is bool and guarded

func _scope() -> String: return "relay-campaign-terminal-v1:"+_owner
func _context() -> Dictionary: return {"owner":_owner,"epoch":_epoch,"generation":_generation}
func _same(context: Dictionary) -> bool:
	var identity := _current_identity()
	return _guard() and not identity.is_empty() and identity.player_id == context.owner and int(identity.epoch) == context.epoch and context.generation == _generation

func _readable() -> bool:
	return _loaded and not read_only and not _state.is_empty() and _same(_context())

func _changed(context: Dictionary) -> bool:
	# A draining callback must not invalidate a newer restored owner/session.
	if context.generation == _generation: invalidate_identity()
	return false

func _leave(context: Dictionary) -> void:
	if context.generation == _generation: _busy = false

func _error(code: String) -> bool:
	last_code = code
	return false

func _hold(code: String) -> bool:
	read_only = true
	return _error(code)
