extends RefCounted
## Explicit room controls. An uncertain acceptance retains its exact fork key.
const Canonical = preload("res://core/v2/canonical.gd")
const Journal = preload("res://services/relay_online_store.gd")
const RoomsApi = preload("res://services/rooms_api.gd")

class DiskStore:
	extends RefCounted
	var journal := Journal.new()
	func read(scope: String) -> Dictionary:
		return journal.load_scope(scope)
	func write(scope: String, value: Dictionary) -> bool:
		return journal.save_scope(scope,value).get("ok",false)

var busy := false
var last_code := ""
var last_error := ""
var accepted := false
var restore_replay_transfer: Callable
var recover_replay_operation: Callable
var _api: Node
var _identity: Callable
var _store: RefCounted
var _binding: Dictionary = {}
var _family := ""
var _room: Dictionary = {}
var _source: Dictionary = {}
var _state: Dictionary = {}
var _view: Dictionary = {}
var _generation := 0
var _storage_ready := false

func _init(api: Node, identity: Callable, store: RefCounted = null) -> void:
	_api = api
	_identity = identity
	_store = DiskStore.new() if store == null else store

func invalidate() -> void:
	_generation += 1
	busy = false
	_binding = {}
	_room = {}
	_source = {}
	_state = {}
	_view = {}
	accepted = false
	_storage_ready = false

func _context() -> Dictionary:
	var value: Variant = _identity.call()
	if not value is Dictionary or value.get("ready") != true or not _id(value.get("player_id")) or not is_instance_valid(_api) or _api.player_id != value.player_id or _api.device_token.is_empty(): return {}
	return {"player_id":value.player_id,"epoch":int(value.get("epoch",0)),"credential":str(_api.device_token).sha256_text(),"base_url":str(_api.base_url)}

func bind_room(family: String, room: Dictionary) -> bool:
	if busy: return _fail("request_busy")
	var context := _context()
	if context.is_empty(): return _fail("identity_changed")
	var preserve_view: bool = _storage_ready and context == _binding and _family == family and _room.get("room_id") == room.get("room_id") and Canonical.same(_source,source_for(family,room))
	var previous_view := _view.duplicate(true)
	var previous_state := _state.duplicate(true)
	if context != _binding:
		invalidate()
		_binding = context
	if family not in ["legacy", "relay"] or not _id(room.get("room_id")) or context.player_id not in [room.get("host_id"),room.get("guest_id")]: return _fail("room_not_found")
	if not pending().is_empty() and (_room.get("room_id") != room.room_id or _family != family): return _fail("request_busy")
	_family = family
	_room = room.duplicate(true)
	_source = source_for(family, room)
	_view = {}
	_storage_ready = false
	accepted = false
	var loaded: Dictionary = _store.read(_scope())
	if not loaded.get("ok",false): return _fail("redo_storage_unavailable")
	var value: Variant = loaded.get("value",{})
	if not value is Dictionary or (not value.is_empty() and not _valid_state(value)): return _fail("redo_storage_unavailable")
	_state = {"schema_version":1,"owner_player_id":context.player_id,"family":family,"room_id":room.room_id,"server_hash":str(_api.base_url).sha256_text(),"pending":{}} if value.is_empty() else value.duplicate(true)
	if preserve_view and Canonical.same(previous_state,_state): _view = previous_view
	_storage_ready = true
	return true

func pending() -> Dictionary: return _state.get("pending",{}).duplicate(true)
func bound_room(family: String) -> Dictionary:
	return _room.duplicate(true) if family == _family and _storage_ready and _same(_generation) else {}
func bound_room_id(family: String) -> String:
	return str(_room.get("room_id","")) if family == _family and _storage_ready and _same(_generation) else ""
func observe_room_failure(room_id: String, code: String) -> bool:
	# Called only for an authenticated read of this exact room, never for an
	# omitted lobby row or a generic connectivity/authentication failure.
	if busy or not _storage_ready or not _same(_generation) or _room.get("room_id")!=room_id or code not in ["room_not_found","room_deleted","player_blocked"]: return false
	_failed_reply({"code":code})
	return pending().is_empty()
func view() -> Dictionary: return _view.duplicate(true) if _same(_generation) else {}
func can_request() -> bool: return _can("second_player_id") and _view.get("request") == null
func can_accept() -> bool: return _can("first_player_id") and _view.get("request") is Dictionary and _view.request.status == "pending"
func can_cancel() -> bool: return _can("second_player_id") and _view.get("request") is Dictionary and _view.request.status == "pending"
func _can(role: String) -> bool:
	return _storage_ready and not busy and pending().is_empty() and _same(_generation) and not _source.is_empty() and _source.get(role) == _binding.player_id and Canonical.same(_view.get("source"), _source)

func refresh() -> bool:
	if busy or not _storage_ready or not _same(_generation) or _room.is_empty(): return _fail("request_busy")
	var generation := _generation
	busy = true
	_view = {}
	var response := await _net(HTTPClient.METHOD_GET, _path()+"/redo", {}, generation)
	if not _same(generation): return false
	busy = false
	if not response.get("ok",false): return _fail(str(response.get("code","redo_unavailable")))
	if not _valid_view(response.get("data")): return _fail("redo_source_changed")
	_view = response.data.duplicate(true)
	last_code = ""
	last_error = ""
	return true

func request_redo() -> bool: return await _prepare("request") if can_request() else _fail("redo_unavailable")
func decline() -> bool: return await _prepare("decline") if can_accept() else _fail("redo_unavailable")
func cancel() -> bool: return await _prepare("cancel") if can_cancel() else _fail("redo_unavailable")
func accept() -> bool: return await _prepare("accept") if can_accept() else _fail("redo_unavailable")

func _prepare(action: String) -> bool:
	var body := {"action":action,"source":_source.duplicate(true)}
	if action == "accept":
		body = {"base_revision":_source.revision,"idempotency_key":RoomsApi.new_key(),"redo_request_id":_view.request.request_id}
		if _family == "relay": body.merge({"branch":_source.branch,"stage_index":_source.stage_index})
	var next := _state.duplicate(true)
	next.pending = {"action":action,"body":body,"source":_source.duplicate(true),"checkpoint_hash":str(_room.get("checkpoint",{}).get("checkpoint_hash","")),"stage_id":str(_room.get("stage_id",""))}
	if not _persist(next): return false
	return await retry()

func retry(allow_mutations: bool = true) -> bool:
	if busy or not _storage_ready or not _same(_generation) or pending().is_empty(): return _fail("redo_unavailable")
	var operation := pending()
	var generation := _generation
	busy = true
	accepted = false
	var response: Dictionary = {}
	if operation.action == "accept" and _family == "relay":
		response = await _net(HTTPClient.METHOD_GET, _path()+"/operations/"+str(operation.body.idempotency_key), {}, generation)
		if response.get("status") == 410 and response.get("code") == "replay_transferred" and recover_replay_operation.is_valid():
			response = await recover_replay_operation.call(str(_room.room_id), str(operation.body.idempotency_key), _transfer_receipt_valid.bind(operation))
		if not _same(generation): return false
		if not response.get("ok",false) and not (response.get("status")==404 and response.get("code")=="operation_not_found"):
			busy = false
			return _failed_reply(response)
	if not response.get("ok",false):
		if not allow_mutations:
			busy = false
			return _fail("v2_mutations_disabled")
		response = await _net(HTTPClient.METHOD_POST, _path() + ("/fork" if operation.action == "accept" else "/redo"), operation.body, generation)
		if _family == "relay" and operation.action != "accept" and response.get("status") == 410 and response.get("code") == "replay_transferred" and restore_replay_transfer.is_valid():
			var restored: Dictionary = await restore_replay_transfer.call(str(_room.room_id))
			if not _same(generation): return false
			response = await _net(HTTPClient.METHOD_POST, _path()+"/redo", operation.body, generation) if restored.get("ok", false) else restored
	if not _same(generation): return false
	busy = false
	if not response.get("ok",false):
		return _failed_reply(response)
	if operation.action == "accept":
		if not _accepted_response(response.get("data"),operation): return _fail("unsupported_redo_response")
	else:
		if not _valid_view(response.get("data")): return _fail("redo_source_changed")
		_view = response.data.duplicate(true)
	var next := _state.duplicate(true)
	next.pending = {}
	if not _persist(next): return false
	accepted = operation.action == "accept"
	if accepted: _view = {}
	last_code = ""
	last_error = ""
	return true

func _transfer_receipt_valid(receipt: Variant, operation: Dictionary) -> bool:
	return _same(_generation) and Canonical.same(pending(), operation) and valid_fork_receipt(receipt, operation.source, operation.body, operation.checkpoint_hash, operation.stage_id)

func _failed_reply(response: Dictionary) -> bool:
	var code := str(response.get("code","redo_unavailable"))
	if code in ["redo_source_changed","redo_request_missing","stale_revision","room_not_found","room_deleted","player_blocked"]:
		var cleared := _state.duplicate(true)
		cleared.pending = {}
		if not _persist(cleared): return false
		_view = {}
	return _fail(code)

func _net(method: int, path: String, body: Dictionary, generation: int) -> Dictionary:
	if not _same(generation) or _api.busy: return {"ok":false,"code":"request_busy"}
	var response: Dictionary = await _api.request_json(method,path,body)
	if generation == _generation and not _same(generation): invalidate()
	return response if _same(generation) else {"ok":false,"code":"identity_changed"}
func _same(generation: int) -> bool: return generation == _generation and not _binding.is_empty() and _binding == _context()
func _path() -> String: return ("/v2/rooms/" if _family == "relay" else "/v1/rooms/") + str(_room.room_id)
func _scope() -> String: return "relay-redo-" + _family + "-v1:" + str(_binding.player_id) + ":" + str(_room.room_id)
func _persist(value: Dictionary) -> bool:
	if not _storage_ready or not _same(_generation) or not _valid_state(value) or not _store.write(_scope(),value): return _fail("redo_storage_unavailable")
	if not _same(_generation): return false
	_state = value.duplicate(true)
	return true
func _fail(code: String) -> bool:
	last_code = code
	last_error = RoomsApi.error_message(code)
	return false

func _valid_view(value: Variant) -> bool:
	return valid_view(value, _source)

static func valid_view(value: Variant, source: Dictionary) -> bool:
	if not value is Dictionary or value.size()!=3 or value.get("schema_version")!=1 or not value.has("source") or not value.has("request"): return false
	if source.is_empty(): return value.source == null and value.request == null
	if not Canonical.same(value.source,source): return false
	if value.request == null: return true
	var request: Variant = value.request
	return request is Dictionary and request.size()==3 and request.get("request_id")==Canonical.digest(source) and Canonical.same(request.get("source"),source) and request.get("status") in ["pending","declined","cancelled","accepted"]

func _accepted_response(value: Variant, operation: Dictionary) -> bool:
	if not value is Dictionary: return false
	var room: Variant = value.get("room") if _family == "relay" else value
	if not room is Dictionary or room.get("room_id")!=_room.room_id or room.get("host_id")!=_room.host_id or room.get("guest_id")!=_room.guest_id or int(room.get("revision",-1))<=int(operation.source.revision): return false
	if _family == "legacy": return int(room.get("attempt",-1)) > int(operation.source.branch)
	return valid_fork_receipt(value.get("receipt"),operation.source,operation.body,operation.checkpoint_hash,operation.stage_id)

static func valid_fork_receipt(receipt: Variant, source: Dictionary, body: Dictionary, checkpoint_hash: String, stage_id: String) -> bool:
	if not receipt is Dictionary or receipt.size() != 13: return false
	# Validate wire types before numeric/string equality. Malformed replies must
	# fail closed, rather than raising a Variant comparison error during recovery.
	for field: String in ["schema_version","accepted_revision","branch","stage_index"]:
		var value: Variant = receipt.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or value != floor(value) or value < 0 or value > 9007199254740991: return false
	for field: String in ["room_id","idempotency_key","request_hash","operation","stage_id","checkpoint_hash"]:
		if not receipt.get(field) is String: return false
	for field: String in ["turn_id","recording_hash","pair_id"]:
		if not receipt.has(field) or receipt[field] != null: return false
	var request: Dictionary = body.duplicate(true)
	request.operation = "fork"
	return receipt.schema_version==2 and receipt.room_id==source.room_id and receipt.operation=="fork" and receipt.idempotency_key==body.idempotency_key and receipt.request_hash==Canonical.digest(request) and receipt.accepted_revision==int(source.revision)+1 and receipt.branch==int(source.branch)+1 and receipt.stage_index==source.stage_index and receipt.stage_id==stage_id and receipt.checkpoint_hash==checkpoint_hash

func _valid_state(value: Dictionary) -> bool:
	return valid_journal(value,str(_binding.get("player_id","")),_family,str(_room.get("room_id","")),str(_api.base_url))

static func valid_journal(value: Dictionary, owner: String, family: String, room_id: String, base_url: String) -> bool:
	if JSON.stringify(value).length()>8192 or value.size()!=6 or value.get("schema_version")!=1 or value.get("owner_player_id")!=owner or value.get("family")!=family or value.get("room_id")!=room_id or value.get("server_hash")!=base_url.sha256_text() or not value.get("pending") is Dictionary: return false
	var operation: Dictionary = value.pending
	if operation.is_empty(): return true
	if operation.size()!=5 or operation.get("action") not in ["request","decline","cancel","accept"] or not _valid_source(operation.get("source")) or operation.source.room_id!=value.room_id or owner not in [operation.source.first_player_id,operation.source.second_player_id] or not operation.get("body") is Dictionary or not operation.get("checkpoint_hash") is String or not operation.get("stage_id") is String: return false
	var body: Dictionary = operation.body
	var expected_owner: String = operation.source.first_player_id if operation.action in ["accept","decline"] else operation.source.second_player_id
	if owner != expected_owner: return false
	if operation.action != "accept": return body.size()==2 and body.get("action")==operation.action and Canonical.same(body.get("source"),operation.source)
	return body.size()==(5 if family=="relay" else 3) and body.get("base_revision")==operation.source.revision and body.get("redo_request_id")==Canonical.digest(operation.source) and body.get("idempotency_key") is String and body.idempotency_key.length()==36 and (family=="legacy" or (body.get("branch")==operation.source.branch and body.get("stage_index")==operation.source.stage_index))

static func source_for(family: String, room: Dictionary) -> Dictionary:
	if family not in ["legacy","relay"] or room.get("active_role")!="b" or not _id(room.get("host_id")) or not _id(room.get("guest_id")) or room.get("first_player_id") not in [room.get("host_id"),room.get("guest_id")]: return {}
	var a: Variant = room.get("recording_a") if family=="relay" else room.get("recordings",{}).get("a")
	if not a is Dictionary: return {}
	var source := {"room_id":room.get("room_id"),"revision":room.get("revision"),"branch":room.get("branch") if family=="relay" else room.get("attempt"),"stage_index":room.get("stage_index") if family=="relay" else room.get("level_index"),"a_hash":a.get("recording_hash") if family=="relay" else a.get("final_state_hash"),"first_player_id":room.first_player_id,"second_player_id":room.guest_id if room.first_player_id==room.get("host_id") else room.get("host_id")}
	return source if _valid_source(source) else {}
static func _valid_source(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=7 or not _id(value.get("room_id")) or not _id(value.get("first_player_id")) or not _id(value.get("second_player_id")) or value.first_player_id==value.second_player_id or not value.get("a_hash") is String or value.a_hash.length()!=64: return false
	for key: String in ["revision","branch","stage_index"]:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or number<0 or number>9007199254740991 or number!=floor(number): return false
	for character: String in value.a_hash:
		if character not in "0123456789abcdef": return false
	return true
static func _id(value: Variant) -> bool:
	if not value is String or value.length()!=22: return false
	for character: String in value:
		if character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true
