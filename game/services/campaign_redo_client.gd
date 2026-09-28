extends RefCounted
## Story consent uses parent authority; its exact child receipt survives local adoption failure.
const Protocol = preload("res://services/campaign_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Redo = preload("res://services/redo_client.gd")
const RoomsApi = preload("res://services/rooms_api.gd")

var busy := false
var read_only := false
var accepted := false
var last_code := ""
var last_error := ""
var _owner: WeakRef
var _store: RefCounted
var _binding: Dictionary
var _definition: Dictionary
var _state: Dictionary = {}
var _target: Dictionary = {}
var _view: Dictionary = {}

func _init(owner: RefCounted, store: RefCounted, binding: Dictionary, definition: Dictionary) -> void:
	_owner = weakref(owner)
	_store = store
	_binding = binding.duplicate(true)
	_definition = definition.duplicate(true)

func load_journal() -> bool:
	if not _current(): return _fail("campaign_context_changed")
	var loaded: Variant = _store.load_scope(_scope())
	if not _current(): return false
	if not loaded is Dictionary or loaded.get("ok") != true: return _hold()
	var value: Variant = loaded.get("value",{})
	if value is Dictionary and value.is_empty():
		value = {"schema_version":1,"owner_player_id":_binding.owner,"campaign_room_id":_binding.campaign.campaign_room_id,"campaign_key":_binding.campaign.campaign_key.duplicate(true),"server_hash":_binding.server_hash,"pending":{}}
	if not _valid_state(value): return _hold()
	_state = value.duplicate(true)
	return true

func invalidate() -> void:
	_binding = {}
	_target = {}
	_view = {}
	_state = {}
	busy = false
	accepted = false

func _context() -> Dictionary:
	var owner: RefCounted = _owner.get_ref()
	return owner.redo_context(self) if owner != null else {}

func _current() -> bool: return not _binding.is_empty() and Canonical.same(_context(),_binding)
func pending() -> Dictionary: return _state.get("pending",{}).duplicate(true)
func settlement_pending() -> bool: return not pending().get("accepted_receipt",{}).is_empty()
func held() -> bool: return read_only or not pending().is_empty()
func view() -> Dictionary: return _view.duplicate(true) if _current() else {}
func request_label() -> String: return "Request redo"

func available() -> bool:
	if not _current(): return false
	if held(): return true
	var owner: RefCounted = _owner.get_ref()
	var target: Dictionary = owner.redo_target(self)
	return owner.redo_supported() and not target.is_empty() and not Redo.source_for("relay",target.room).is_empty()

func can_request() -> bool: return _can("second_player_id") and _view.get("request") == null
func can_accept() -> bool: return _can("first_player_id") and _view.get("request") is Dictionary and _view.request.status == "pending"
func can_cancel() -> bool: return _can("second_player_id") and _view.get("request") is Dictionary and _view.request.status == "pending"

func _can(role: String) -> bool:
	if busy or held() or not _current() or _target.is_empty(): return false
	var source := Redo.source_for("relay",_target.room)
	var owner: RefCounted = _owner.get_ref()
	return not source.is_empty() and source[role] == _binding.owner and Canonical.same(_view.get("source"),source) and owner.redo_can_mutate(self,_target.binding,source)

func refresh(refresh_source: bool = true) -> bool:
	if busy or read_only or not _current() or not pending().is_empty(): return false
	busy = true
	accepted = false
	var owner: RefCounted = _owner.get_ref()
	var okay := true
	if refresh_source: okay = await owner.refresh_redo_source(self)
	if not _current(): return false
	_target = owner.redo_target(self)
	_view = {}
	if not okay or _target.is_empty():
		busy = false
		return _fail("redo_source_changed")
	var response := await _net(HTTPClient.METHOD_GET,path_for(_target.binding),{})
	if not _current(): return false
	busy = false
	if response.get("ok") != true: return _fail(str(response.get("code","redo_unavailable")))
	var source := Redo.source_for("relay",_target.room)
	if not _view_response(response.get("data"),_target.binding,source): return _fail("redo_source_changed")
	_view = response.data.redo.duplicate(true)
	return _success()

func request_redo() -> bool: return await _prepare("request") if can_request() else _fail("redo_unavailable")
func decline() -> bool: return await _prepare("decline") if can_accept() else _fail("redo_unavailable")
func cancel() -> bool: return await _prepare("cancel") if can_cancel() else _fail("redo_unavailable")
func accept() -> bool: return await _prepare("accept") if can_accept() else _fail("redo_unavailable")

func _prepare(action: String) -> bool:
	var source := Redo.source_for("relay",_target.room)
	var binding: Dictionary = _target.binding.duplicate(true)
	var body := {"schema_version":1,"binding":binding,"action":action,"source":source}
	if action == "accept": body = {"schema_version":1,"binding":binding,"source":source,"request_id":Canonical.digest(source),"idempotency_key":RoomsApi.new_key()}
	var next := _state.duplicate(true)
	next.pending = {"action":action,"binding":binding,"source":source,"body":body,"checkpoint_hash":_target.room.checkpoint.checkpoint_hash,"stage_id":_target.room.stage_id,"accepted_receipt":{}}
	if not _persist(next): return false
	return await retry()

func retry(allow_mutations: bool = true) -> bool:
	if busy or read_only or not _current() or pending().is_empty(): return _fail("redo_unavailable")
	busy = true
	accepted = false
	var operation := pending()
	var path := path_for(operation.binding)
	var owner: RefCounted = _owner.get_ref()
	if operation.action == "accept":
		if not operation.accepted_receipt.is_empty(): return await _settle()
		var lookup := await _net(HTTPClient.METHOD_GET,path+"/operations/"+operation.body.idempotency_key,{})
		if not _current(): return false
		if lookup.get("ok") == true: return await _receive_accept(lookup,operation)
		if lookup.get("status") != 404 or lookup.get("code") != "operation_not_found":
			busy = false
			return _fail(str(lookup.get("code","redo_unavailable")))
		# Verify the current native snapshot before a new consent attempt. A
		# monotonic newer source followed by another absent receipt fences the
		# old request, including a concurrent B submission that won the race.
		if not await owner.refresh_redo_source(self):
			busy = false
			return _fail("redo_source_changed")
		if not _current(): return false
		if owner.redo_source_advanced(self,operation): return await _settle_obsolete_accept(operation)
	else:
		# Advisory retries first observe the same source; they never fork.
		var lookup := await _net(HTTPClient.METHOD_GET,path,{})
		if not _current(): return false
		if lookup.get("ok") != true:
			busy = false
			return _fail(str(lookup.get("code","redo_unavailable")))
		var value: Variant = lookup.get("data")
		if not _advisory_response(value,operation.binding):
			busy = false
			return _fail("redo_source_changed")
		# Advisory state can already have advanced after our lost reply. Unlike
		# consent, this intent contains no fork or immutable acceptance to recover.
		if not Canonical.same(value.redo.source,operation.source):
			if not await owner.refresh_redo_source(self):
				busy = false
				return _fail("redo_source_changed")
			if not _current(): return false
			if not owner.redo_source_advanced(self,operation):
				busy = false
				return _fail("redo_source_changed")
			return _finish_advisory(value.redo)
		var observed: Variant = lookup.data.redo.request
		var wanted: String = {"request":"pending","decline":"declined","cancel":"cancelled"}[operation.action]
		if observed is Dictionary and (observed.status == wanted or observed.status in ["declined","cancelled","accepted"]): return _finish_advisory(lookup.data.redo)
	if not allow_mutations or not owner.redo_can_mutate(self,operation.binding,operation.source):
		busy = false
		return _fail("campaign_mutations_unavailable")
	var response := await _net(HTTPClient.METHOD_POST,path+("/accept" if operation.action == "accept" else ""),operation.body)
	if not _current(): return false
	if response.get("ok") != true:
		busy = false
		# A denial/current view is not a substitute for an immutable receipt.
		return _fail(str(response.get("code","redo_unavailable")))
	if operation.action == "accept": return await _receive_accept(response,operation)
	if not _view_response(response.get("data"),operation.binding,operation.source):
		busy = false
		return _fail("redo_source_changed")
	return _finish_advisory(response.data.redo)

func _settle_obsolete_accept(operation: Dictionary) -> bool:
	# The previous 404 preceded the verified newer snapshot; recheck after it.
	var response := await _net(HTTPClient.METHOD_GET,path_for(operation.binding)+"/operations/"+operation.body.idempotency_key,{})
	if not _current(): return false
	if response.get("ok") == true: return await _receive_accept(response,operation)
	busy = false
	if response.get("status") != 404 or response.get("code") != "operation_not_found": return _fail(str(response.get("code","redo_unavailable")))
	var owner: RefCounted = _owner.get_ref()
	if not owner.redo_source_advanced(self,operation): return _fail("redo_source_changed")
	var next := _state.duplicate(true)
	next.pending = {}
	if not _persist(next): return false
	_view = {}
	return _success()

func _receive_accept(response: Dictionary, operation: Dictionary) -> bool:
	var value: Variant = response.get("data")
	if response.get("status") != 200 or not Protocol.exact(value,["schema_version","binding","receipt"]) or value.schema_version != 1 or not Canonical.same(value.binding,operation.binding) or not receipt_valid(value.receipt,operation):
		busy = false
		return _fail("unsupported_redo_response")
	var next := _state.duplicate(true)
	next.pending.accepted_receipt = value.receipt.duplicate(true)
	if not _persist(next):
		busy = false
		return false
	return await _settle()

func _settle() -> bool:
	var owner: RefCounted = _owner.get_ref()
	var okay: bool = await owner.settle_redo(self,pending())
	if not _current(): return false
	busy = false
	if not okay: return _fail("campaign_redo_settlement_pending")
	var next := _state.duplicate(true)
	next.pending = {}
	if not _persist(next): return false
	accepted = true
	_view = {}
	return _success()

func _finish_advisory(value: Dictionary) -> bool:
	busy = false
	var next := _state.duplicate(true)
	next.pending = {}
	if not _persist(next): return false
	_view = value.duplicate(true)
	return _success()

func _net(method: int, path: String, body: Dictionary) -> Dictionary:
	var owner: RefCounted = _owner.get_ref()
	if not _current() or owner == null: return {"ok":false,"code":"campaign_context_changed"}
	return await owner.dispatch_redo_request(self,_binding,{"owner_player_id":_binding.owner,"identity_epoch":_binding.epoch,"method":method,"path":path,"body":body.duplicate(true)})

func _persist(value: Dictionary) -> bool:
	if read_only or not _current() or not _valid_state(value): return _hold()
	var result: Variant = _store.save_scope(_scope(),value.duplicate(true))
	if not _current(): return false
	if not result is Dictionary or result.get("ok") != true: return _fail("redo_storage_unavailable")
	_state = value.duplicate(true)
	return true

func _scope() -> String: return "relay-campaign-redo-v1:"+str(_binding.owner)+":"+str(_binding.campaign.campaign_room_id)
func _hold() -> bool:
	read_only = true
	return _fail("redo_storage_unavailable")
func _success() -> bool:
	last_code = ""
	last_error = ""
	return true
func _fail(code: String) -> bool:
	last_code = code
	last_error = "The redo was accepted. Your saved attempt needs attention." if code == "campaign_redo_settlement_pending" else RoomsApi.error_message(code)
	return false

static func path_for(binding: Dictionary) -> String:
	return "/v2/campaigns/"+str(binding.campaign_room_id)+"/chapters/"+str(int(binding.chapter_index))+"/redo"

static func binding_valid(value: Variant, campaign: Dictionary, definition: Dictionary) -> bool:
	return Protocol.exact(value,["campaign_room_id","campaign_key","chapter_index","chapter","room_id"]) and value.campaign_room_id == campaign.campaign_room_id and Canonical.same(value.campaign_key,campaign.campaign_key) and Protocol.integer(value.chapter_index,0,definition.chapters.size()-1) and Canonical.same(value.chapter,definition.chapters[int(value.chapter_index)]) and Protocol.id_valid(value.room_id) and (value.chapter_index != 0 or value.room_id == value.campaign_room_id)

static func fork_body(operation: Dictionary) -> Dictionary:
	return {"base_revision":operation.source.revision,"branch":operation.source.branch,"stage_index":operation.source.stage_index,"idempotency_key":operation.body.idempotency_key,"redo_request_id":operation.body.request_id}

static func receipt_valid(value: Variant, operation: Dictionary) -> bool:
	return Redo.valid_fork_receipt(value,operation.source,fork_body(operation),operation.checkpoint_hash,operation.stage_id)

static func _view_response(value: Variant, binding: Dictionary, source: Dictionary) -> bool:
	return Protocol.exact(value,["schema_version","binding","redo"]) and value.schema_version == 1 and Canonical.same(value.binding,binding) and Redo.valid_view(value.redo,source)

static func _advisory_response(value: Variant, binding: Dictionary) -> bool:
	if not Protocol.exact(value,["schema_version","binding","redo"]) or not value.redo is Dictionary: return false
	var source: Variant = value.redo.get("source")
	if source != null and (not Redo._valid_source(source) or source.room_id != binding.room_id): return false
	return _view_response(value,binding,{} if source == null else source)

func _valid_state(value: Variant) -> bool:
	if not Protocol.bounded(value,8192,1024,12) or not Protocol.exact(value,["schema_version","owner_player_id","campaign_room_id","campaign_key","server_hash","pending"]): return false
	if value.schema_version != 1 or value.owner_player_id != _binding.owner or value.campaign_room_id != _binding.campaign.campaign_room_id or not Canonical.same(value.campaign_key,_binding.campaign.campaign_key) or value.server_hash != _binding.server_hash or not value.pending is Dictionary: return false
	var op: Dictionary = value.pending
	if op.is_empty(): return true
	if not Protocol.exact(op,["action","binding","source","body","checkpoint_hash","stage_id","accepted_receipt"]) or op.action not in ["request","decline","cancel","accept"] or not binding_valid(op.binding,_binding.campaign,_definition) or not Redo._valid_source(op.source): return false
	if op.source.room_id != op.binding.room_id or not Protocol.hash_valid(op.checkpoint_hash) or not Protocol.slug(op.stage_id) or not op.accepted_receipt is Dictionary: return false
	var expected_owner: String = op.source.first_player_id if op.action in ["accept","decline"] else op.source.second_player_id
	if expected_owner != _binding.owner or not op.body is Dictionary: return false
	var body: Dictionary = op.body
	if body.get("schema_version") != 1 or not Canonical.same(body.get("binding"),op.binding) or not Canonical.same(body.get("source"),op.source): return false
	if op.action != "accept": return Protocol.exact(body,["schema_version","binding","action","source"]) and body.action == op.action and op.accepted_receipt.is_empty()
	if not Protocol.exact(body,["schema_version","binding","source","request_id","idempotency_key"]) or body.request_id != Canonical.digest(op.source) or not Protocol.matches(body.idempotency_key,"^[A-Za-z0-9_-]{16,80}$"): return false
	return op.accepted_receipt.is_empty() or receipt_valid(op.accepted_receipt,op)
