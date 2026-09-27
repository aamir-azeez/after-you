extends RefCounted
## Exact admission evidence only. No network, cleanup or pending clear.
## current() and pending observers must be pure synchronous observations. The
## retained lifetime pins the original device/API context even at the same epoch.
const Protocol = preload("res://services/campaign_protocol.gd")
const Lobby = preload("res://services/campaign_lobby_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Store = preload("res://services/relay_online_store.gd")
const Terminal = preload("res://services/campaign_terminal_session.gd")
const MAX_ENTRIES := 128
const MAX_BYTES := 196608
const MAX_NODES := 12288
var last_code := ""
var read_only := false
var _identity: Callable
var _current: Callable
var _lifetime: RefCounted
var _store: RefCounted
var _state: Dictionary = {}
var _owner := ""
var _epoch := -1
var _generation := 0
var _loaded := false
var _busy := false
var _retired := false

func _init(identity: Callable, current: Callable, storage: RefCounted = null,
		lifetime: RefCounted = null) -> void:
	_identity = identity
	_current = current
	_store = Store.new() if storage == null else storage
	_lifetime = lifetime
	if _lifetime == null and current.is_valid():
		var target: Object = current.get_object()
		if target is RefCounted: _lifetime = target

static func scope_for(owner: String) -> String:
	return "relay-campaign-admission-terminal-v1:"+owner if Protocol.id_valid(owner) else ""

static func request_valid(value: Variant, owner: String) -> bool:
	if not Protocol.id_valid(owner) or not Protocol.bounded(value,Protocol.MAX_REQUEST_BYTES,96,6) or not Protocol.exact(value,["path","body","request_hash"]): return false
	if value.path == "/v2/campaigns":
		if not Protocol.exact(value.body,["schema_version","idempotency_key","campaign_key"]) or not Protocol.integer(value.body.schema_version,1,1): return false
	elif value.path == "/v2/campaigns/join":
		if not Protocol.exact(value.body,["schema_version","idempotency_key","invite_code","campaign_key","supported_simulation_versions"]) or not Protocol.integer(value.body.schema_version,2,2) or not Protocol.matches(value.body.invite_code,"^[A-F0-9]{20}$"): return false
		var versions: Variant = value.body.supported_simulation_versions
		if not versions is Array or versions.is_empty() or versions.size() > 8: return false
		var seen := {}
		for version: Variant in versions:
			if not Protocol.integer(version,1) or seen.has(int(version)): return false
			seen[int(version)] = true
	else: return false
	if not Protocol.matches(value.body.idempotency_key,"^[A-Za-z0-9_-]{16,80}$") or not Protocol.key_valid(value.body.campaign_key): return false
	return Protocol.hash_valid(value.request_hash) and value.request_hash == Lobby.request_hash(owner,value.path,value.body)

static func terminal_valid(value: Variant, request: Variant, owner: String) -> bool:
	if not request_valid(request,owner) or request.path != "/v2/campaigns" or not Protocol.bounded(value,2048,32,3) or not Protocol.exact(value,["schema_version","operation","admission","status","player_id","idempotency_key","request_hash","campaign_room_id"]): return false
	return Protocol.integer(value.schema_version,1,1) and value.operation == "campaign_terminal_admission" and value.admission == "create" and value.status == "terminal" and value.player_id == owner and value.idempotency_key == request.body.idempotency_key and value.request_hash == request.request_hash and Protocol.id_valid(value.campaign_room_id)

static func witness_valid(value: Variant, request: Variant, owner: String) -> bool:
	if not request_valid(request,owner) or not Protocol.bounded(value,4096,96,6) or not value is Dictionary: return false
	match value.get("kind"):
		"server_create":
			return Protocol.exact(value,["kind","terminal"]) and terminal_valid(value.terminal,request,owner)
		"accepted_reference":
			return Protocol.exact(value,["kind","reference","cleanup"]) and _reference_valid(value.reference,request) and Terminal.receipt_valid(value.cleanup,owner,value.reference.campaign_room_id)
		"join_invitation":
			return Protocol.exact(value,["kind","cleanup"]) and request.path == "/v2/campaigns/join" and Terminal.receipt_valid(value.cleanup,owner,_invitation_anchor(request))
	return false

static func mapped_anchor(entry: Variant, owner: String) -> String:
	return _witness_anchor(entry.witness,entry.request) if Protocol.exact(entry,["request","witness"]) and witness_valid(entry.witness,entry.request,owner) else ""

static func _reference_valid(value: Variant, request: Dictionary) -> bool:
	return Protocol.exact(value,["campaign_room_id","campaign_key"]) and Protocol.id_valid(value.campaign_room_id) and Protocol.key_valid(value.campaign_key) and Canonical.same(value.campaign_key,request.body.campaign_key) and (request.path != "/v2/campaigns/join" or value.campaign_room_id == _invitation_anchor(request))

static func _invitation_anchor(request: Dictionary) -> String:
	return ("v2:"+str(request.body.invite_code)).sha256_text().substr(0,22)

static func _witness_anchor(witness: Dictionary, request: Dictionary) -> String:
	match witness.kind:
		"server_create": return witness.terminal.campaign_room_id
		"accepted_reference": return witness.reference.campaign_room_id
		"join_invitation": return _invitation_anchor(request)
	return ""

static func journal_valid(value: Variant, owner: String) -> bool:
	if not Protocol.id_valid(owner) or not Protocol.bounded(value,MAX_BYTES,MAX_NODES,8) or not Protocol.exact(value,["schema_version","owner_player_id","mappings"]): return false
	if not Protocol.integer(value.schema_version,1,1) or value.owner_player_id != owner or not value.mappings is Array or value.mappings.size() > MAX_ENTRIES: return false
	var hashes := {}
	var keys := {}
	for entry: Variant in value.mappings:
		if not Protocol.exact(entry,["request","witness"]) or not witness_valid(entry.witness,entry.request,owner): return false
		var key: String = entry.request.body.idempotency_key
		var digest: String = entry.request.request_hash
		if hashes.has(digest) or keys.has(key): return false
		hashes[digest] = true
		keys[key] = true
	return true

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
	_retired = true
	invalidate_identity()
	last_code = "campaign_context_changed"

func restore_owner(retry: bool = false) -> bool:
	if not _guard(): return _error("campaign_context_changed")
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
	var loaded: Variant = _store.load_scope(scope_for(_owner))
	if not _same(context): return _changed(context)
	_busy = false
	if not loaded is Dictionary or loaded.get("ok") != true: return _hold("campaign_storage_unavailable")
	var value: Variant = loaded.get("value") if loaded.get("found",false) else _empty()
	if not journal_valid(value,_owner): return _hold("unsupported_campaign_terminal_admission_save")
	_state = value.duplicate(true)
	last_code = ""
	return true

func record_mapping(request: Dictionary, witness: Dictionary, pending: Callable) -> bool:
	# Only the exact current lobby intent may add evidence. The accepted-reference
	# witness also requires that same reference in the original durable pending.
	var original := request.duplicate(true)
	var proof := witness.duplicate(true)
	if not restore_owner() or read_only: return false
	if not witness_valid(proof,original,_owner): return _error("invalid_campaign_terminal_admission")
	_busy = true
	var context := _context()
	if not _record_current(context,original,proof,pending):
		_leave(context)
		return _error("campaign_context_changed")
	for entry: Dictionary in _state.mappings:
		if entry.request.request_hash == original.request_hash or entry.request.body.idempotency_key == original.body.idempotency_key:
			var same := Canonical.same(entry.request,original) and Canonical.same(entry.witness,proof)
			_leave(context)
			if not same: return _error("campaign_terminal_admission_conflict")
			last_code = ""
			return true
	if _state.mappings.size() >= MAX_ENTRIES:
		_leave(context)
		return _error("campaign_history_full")
	var next := _state.duplicate(true)
	next.mappings.append({"request":original,"witness":proof})
	if not journal_valid(next,_owner) or not _record_current(context,original,proof,pending):
		_leave(context)
		return _error("campaign_context_changed")
	var saved: Variant = _store.save_scope(scope_for(context.owner),next.duplicate(true))
	var current := _record_current(context,original,proof,pending)
	_leave(context)
	if not current: return _changed(context)
	if not saved is Dictionary or saved.get("ok") != true: return _error("campaign_storage_unavailable")
	_state = next.duplicate(true)
	last_code = ""
	return true

func mapping_for(request: Dictionary) -> Dictionary:
	if not _readable() or not request_valid(request,_owner): return {}
	for entry: Dictionary in _state.mappings:
		if Canonical.same(entry.request,request): return entry.duplicate(true)
	return {}

func mappings() -> Array:
	return _state.mappings.duplicate(true) if _readable() else []

func busy() -> bool: return _busy

func _record_current(context: Dictionary, request: Dictionary, witness: Dictionary, pending: Callable) -> bool:
	if not _same(context) or not pending.is_valid(): return false
	var observed: Variant = pending.call()
	if not Protocol.bounded(observed,8192,128,8) or (not Protocol.exact(observed,["path","body","request_hash","accepted_campaign"]) and not Protocol.exact(observed,["path","body","request_hash","accepted_campaign","cancel_requested"])): return false
	if observed.has("cancel_requested") and not observed.cancel_requested is bool: return false
	if not observed.accepted_campaign is Dictionary: return false
	var exact_request := {"path":observed.path,"body":observed.body,"request_hash":observed.request_hash}
	if not request_valid(exact_request,context.owner) or not Canonical.same(exact_request,request): return false
	var reference: Dictionary = observed.accepted_campaign
	if not reference.is_empty() and (not _reference_valid(reference,request) or reference.campaign_room_id != _witness_anchor(witness,request)): return false
	if witness.kind == "accepted_reference" and not Canonical.same(reference,witness.reference): return false
	return _same(context)

func _empty() -> Dictionary: return {"schema_version":1,"owner_player_id":_owner,"mappings":[]}

func _current_identity() -> Dictionary:
	var value: Variant = _identity.call() if _identity.is_valid() else null
	return value.duplicate(true) if value is Dictionary and value.get("ready") == true and Protocol.id_valid(value.get("player_id")) and Protocol.integer(value.get("epoch")) else {}

func _guard() -> bool:
	if _retired or _lifetime == null or not _current.is_valid(): return false
	var observed: Variant = _current.call()
	return observed is bool and observed

func _context() -> Dictionary: return {"owner":_owner,"epoch":_epoch,"generation":_generation}
func _same(context: Dictionary) -> bool:
	var identity := _current_identity()
	return _guard() and not identity.is_empty() and identity.player_id == context.owner and int(identity.epoch) == context.epoch and context.generation == _generation

func _readable() -> bool:
	return _loaded and not read_only and not _state.is_empty() and _same(_context())

func _changed(context: Dictionary) -> bool:
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
