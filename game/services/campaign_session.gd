extends RefCounted
## Durable control around independently verified rooms; never stores their proofs.
## validate_target(room_id,pin,owner,epoch) verifies in isolation, without changing
## the visible room. selection_ready() reconciles the prior room's pending writes.
const Protocol = preload("res://services/campaign_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Chapters = preload("res://services/chapter_registry.gd")
var last_code := ""
var read_only := false
var _transport: Callable
var _transport_lifetime: RefCounted
var _load: Callable
var _save: Callable
var _identity: Callable
var _validate_target: Callable
var _selection_ready: Callable
var _definition: Dictionary = {}
var _state: Dictionary = {}
var _owner := ""
var _epoch := -1
var _anchor := ""
var _scope := ""
var _generation := 0
var _busy := false

func _init(transport: Callable, load_store: Callable, save_store: Callable, identity: Callable, validate_target: Callable, selection_ready: Callable, transport_lifetime: RefCounted = null) -> void:
	_transport = transport
	# A standard method Callable does not own its RefCounted target. Retain the
	# context for this session, including requests draining after owner retirement.
	_transport_lifetime = transport_lifetime
	_load = load_store
	_save = save_store
	_identity = identity
	_validate_target = validate_target
	_selection_ready = selection_ready

func invalidate_identity() -> void:
	_generation += 1
	_busy = false
	_definition = {}
	_state = {}
	_owner = ""
	_epoch = -1
	_anchor = ""
	_scope = ""
	read_only = false
	last_code = "identity_changed"

func bind(anchor: String, bundled_definition: Dictionary) -> bool:
	if _busy or (read_only and anchor != _anchor) or (not _state.is_empty() and not _state.pending.is_empty()): return _error("pending_operation")
	var identity: Variant = _identity.call()
	if not _identity_valid(identity) or not Protocol.id_valid(anchor) or not Protocol.definition_valid(bundled_definition): return _error("campaign_unavailable")
	_generation += 1
	_owner = identity.player_id
	_epoch = int(identity.epoch)
	_anchor = anchor
	_scope = "relay-campaign-v1:"+_owner+":"+anchor
	_definition = bundled_definition.duplicate(true)
	read_only = false
	_state = {"schema_version":1,"owner_player_id":_owner,"campaign_room_id":anchor,"campaign_key":Protocol.key(_definition),"view":{},"selected_room":"","pending":{},"last_receipt":{},"seen":[]}
	var loaded: Variant = _load.call(_scope)
	if not loaded is Dictionary or not loaded.get("ok",false): return _hold("storage_unavailable")
	if loaded.get("found",false):
		if not _state_valid(loaded.get("value")): return _hold("unsupported_campaign_save")
		_state = loaded.value.duplicate(true)
	last_code = ""
	return true

func view() -> Dictionary: return _state.view.duplicate(true) if _ready() else {}
func pending() -> Dictionary: return _state.pending.duplicate(true) if _ready() else {}
func selected_room() -> String: return str(_state.selected_room) if _ready() else ""
func rejected_receipt() -> Dictionary: return _state.last_receipt.duplicate(true) if _ready() and _state.last_receipt.has("reason") else {}
func busy() -> bool: return _busy

func refresh() -> bool:
	var context := _enter()
	if context.is_empty(): return false
	var okay := await _refresh(context)
	_leave(context)
	return okay

func _refresh(context: Dictionary) -> bool:
	var response := await _call(context,HTTPClient.METHOD_GET,"/v2/campaigns/"+_anchor)
	if not _okay(response): return false
	if response.get("status") != 200: return _error("invalid_campaign_reply")
	var envelope: Variant = response.get("data")
	if not Protocol.exact(envelope,["campaign"]) or not Protocol.view_valid(envelope.campaign,_definition,_owner) or envelope.campaign.campaign_room_id != _anchor: return _error("invalid_campaign_reply")
	var observed := _merge_view(envelope.campaign)
	if observed.is_empty(): return false
	var next := _state.duplicate(true)
	next.view = observed
	return _persist(next)

func continue_from(source: RefCounted) -> bool:
	if not _ready() or read_only or _busy or not _state.pending.is_empty(): return _error("pending_operation")
	if not _state.view.is_empty() and _state.view.activation != null: return _error("campaign_activation_pending")
	if _state.view.is_empty() or _state.view.state not in ["active","continuing"] or source == null or source.read_only or not source.chapter_complete() or not source.pending().is_empty(): return _error("source_not_ready")
	# RelayRoomCoordinator returns only its validated, durable room snapshot.
	var room: Dictionary = source.snapshot()
	var index := int(_state.view.current_index)
	var entry: Dictionary = _state.view.chapters[index]
	if room.get("room_id") != entry.room_id or not room.get("checkpoint") is Dictionary or room.get("active_role") != "complete": return _error("source_not_ready")
	var rejected := rejected_receipt()
	if not rejected.is_empty() and rejected.origin.from_index == index and rejected.origin.source.room_id == room.room_id and room.get("branch",-1) < rejected.closed_before_branch: return _error("source_forked")
	for field: String in ["level_id","level_version","definition_hash"]:
		if room.get(field) != entry.chapter[field]: return _error("source_not_ready")
	var chapter := Chapters.resolve(entry.chapter)
	if room.get("simulation_version",Chapters.definition(chapter).simulation_version) != entry.chapter.simulation_version or room.get("host_id") != _state.view.host_id or room.get("guest_id") != _state.view.guest_id: return _error("source_not_ready")
	var context := {"expected_revision":_state.view.revision,"from_index":index,"source":{"room_id":room.room_id,"revision":room.get("revision"),"branch":room.get("branch"),"checkpoint_hash":room.checkpoint.get("checkpoint_hash")}}
	if _state.view.state == "continuing":
		# Either member can deliberately resume a prepared handoff. Keep the
		# original origin; the new control revision is not a new transition.
		var prepared: Dictionary = _state.view.transition.origin
		if not Canonical.same(context.source,prepared.source): return _error("source_not_ready")
		context = prepared.duplicate(true)
	var body := Protocol.continue_body(_anchor,_owner,_definition,context)
	if body.is_empty(): return _error("source_not_ready")
	var next := _state.duplicate(true)
	next.pending = {"body":body,"request_hash":Protocol.request_hash(_anchor,_owner,body),"accepted_receipt":{}}
	if not _persist(next): return false
	return await retry()

func retry() -> bool:
	var context := _enter()
	if context.is_empty(): return false
	var okay := await _retry(context)
	_leave(context)
	return okay

func _retry(context: Dictionary) -> bool:
	if _state.pending.is_empty(): return _error("operation_not_pending")
	if not _state.pending.accepted_receipt.is_empty():
		if not await _refresh(context): return false
		return await _settle(context)
	var body: Dictionary = _state.pending.body.duplicate(true)
	var response := await _call(context,HTTPClient.METHOD_GET,"/v2/campaigns/"+_anchor+"/operations/"+body.idempotency_key)
	if not _same(context): return false
	var may_repost_pending := true
	if response.get("status") == 404 and response.get("code") == "operation_not_found":
		if _state.view.get("state") == "deleting": return _error("campaign_deleting")
		may_repost_pending = false
		response = await _call(context,HTTPClient.METHOD_POST,"/v2/campaigns/"+_anchor+"/continue",body)
	return await _receive_operation(context,response,may_repost_pending)

func _receive_operation(context: Dictionary, response: Dictionary, may_repost_pending: bool) -> bool:
	if not _same(context): return false
	if not _okay(response): return false
	var body: Dictionary = _state.pending.body.duplicate(true)
	var result: Variant = response.get("data")
	if not Protocol.result_valid(result,body,_anchor,_owner,_definition): return _error("invalid_campaign_receipt")
	if response.get("status") != (202 if result.status == "pending" else 200): return _error("invalid_campaign_reply")
	var rejected: Dictionary = result.receipt if result.status == "rejected" else {}
	if not rejected.is_empty() and (_state.view.state == "deleting" or result.campaign.state == "deleting"): return _error("campaign_deleting")
	var observed := _merge_view(result.campaign,rejected)
	if observed.is_empty(): return false
	# A delayed accepted response may carry an older view. Its receipt must also
	# fit the newer history already retained by this device.
	var reconciled: Dictionary = result.duplicate(true)
	reconciled.campaign = observed
	if not Protocol.result_valid(reconciled,body,_anchor,_owner,_definition): return _error("campaign_history_conflict")
	var next := _state.duplicate(true)
	next.view = observed
	if result.status == "rejected":
		# The bound terminal outcome is saved in the same write that releases
		# the pending slot. No room draft, proof or selection is changed.
		next.last_receipt = rejected.duplicate(true)
		next.pending = {}
		if not _persist(next): return false
		return _error("source_forked")
	if result.status == "accepted": next.pending.accepted_receipt = result.receipt.duplicate(true)
	if not _persist(next): return false
	if observed.state == "deleting": return _error("campaign_deleting")
	if result.status == "pending":
		# Only this deliberate Retry invocation can continue a validated pending
		# operation. Save the observed seal phase before sending the same body.
		if not may_repost_pending: return _error("campaign_continuing")
		var retried := await _call(context,HTTPClient.METHOD_POST,"/v2/campaigns/"+_anchor+"/continue",body)
		return await _receive_operation(context,retried,false)
	return await _settle(context)

func resume_activation() -> bool:
	var context := _enter()
	if context.is_empty(): return false
	var okay := await _resume_activation(context)
	_leave(context)
	return okay

func _resume_activation(context: Dictionary) -> bool:
	if _state.view.is_empty() or _state.view.state == "deleting": return _error("campaign_unavailable")
	if _state.view.activation == null: return _error("activation_not_pending")
	var token: String = _state.view.activation.transition_id
	var body := Protocol.resume_activation_body(_definition,token)
	if body.is_empty(): return _error("campaign_unavailable")
	# Activation debt is already durable in the validated view. This operation
	# needs no new Continue key, receipt alias or speculative room selection.
	var response := await _call(context,HTTPClient.METHOD_POST,"/v2/campaigns/"+_anchor+"/resume",body)
	if not _same(context) or not _okay(response): return false
	if response.get("status") not in [200,202]: return _error("invalid_campaign_reply")
	var envelope: Variant = response.get("data")
	if not Protocol.exact(envelope,["campaign"]) or not Protocol.view_valid(envelope.campaign,_definition,_owner) or envelope.campaign.campaign_room_id != _anchor: return _error("invalid_campaign_reply")
	var same_debt: bool = envelope.campaign.activation != null and envelope.campaign.activation.transition_id == token
	if (response.status == 202) != same_debt: return _error("invalid_campaign_reply")
	var observed := _merge_view(envelope.campaign)
	if observed.is_empty(): return false
	var next := _state.duplicate(true)
	next.view = observed
	if not _persist(next): return false
	if observed.state == "deleting": return _error("campaign_deleting")
	if observed.activation != null: return _error("campaign_activation_pending")
	if not _state.pending.is_empty():
		# A marker discharge cannot stand in for an operation receipt. A caller
		# with a lost Continue reply must still deliberately recover that alias.
		if _state.pending.accepted_receipt.is_empty(): return _error("campaign_receipt_pending")
		return await _settle(context)
	return true

func _settle(context: Dictionary) -> bool:
	var receipt: Dictionary = _state.pending.accepted_receipt
	if _state.view.state == "deleting": return _error("campaign_deleting")
	if _state.view.activation != null: return _error("campaign_activation_pending")
	if _state.view.state == "continuing":
		# The partner may already be handing off a later room. This earlier
		# operation is settled, so release its local lock without selecting a
		# room; either member can then resume the newer transition deliberately.
		var settled := _state.duplicate(true)
		settled.last_receipt = receipt.duplicate(true)
		settled.pending = {}
		return _persist(settled)
	var selected := str(_state.selected_room)
	if receipt.outcome == "advanced":
		if not _selection_ready.is_valid() or _selection_ready.call() != true: return _error("previous_room_pending")
		# A response can arrive after another device progressed again. Reconcile
		# its receipt, then verify the current published room without rewinding.
		var index := int(_state.view.current_index)
		selected = _state.view.chapters[index].room_id
		if not await _verify_target(context,selected,index): return false
		if _selection_ready.call() != true: return _error("previous_room_pending")
	var next := _state.duplicate(true)
	if receipt.outcome == "advanced": next.selected_room = selected
	next.last_receipt = receipt.duplicate(true)
	next.pending = {}
	return _persist(next)

func select_current() -> bool:
	var context := _enter()
	if context.is_empty(): return false
	var okay := await _select_current(context)
	_leave(context)
	return okay

func _select_current(context: Dictionary) -> bool:
	if not _state.pending.is_empty() or _state.view.is_empty() or _state.view.state not in ["waiting","active","complete"]: return _error("selection_unavailable")
	if _state.view.activation != null: return _error("campaign_activation_pending")
	if not _selection_ready.is_valid() or _selection_ready.call() != true: return _error("previous_room_pending")
	var index := int(_state.view.current_index)
	var room: String = _state.view.chapters[index].room_id
	if not await _verify_target(context,room,index): return false
	if _selection_ready.call() != true: return _error("previous_room_pending")
	var next := _state.duplicate(true)
	next.selected_room = room
	return _persist(next)

func _verify_target(context: Dictionary, room: String, index: int) -> bool:
	if not _validate_target.is_valid(): return _error("native_validation_unavailable")
	var checked: Variant = await _validate_target.call(room,_definition.chapters[index].duplicate(true),_owner,_epoch)
	if not _same(context): return _error("identity_changed")
	if not checked is Dictionary or checked.get("ok") != true or checked.get("room_id") != room: return _error("target_not_verified")
	return true

func story_seen(index: int, phase: String) -> bool:
	return _ready() and (str(index)+":"+phase) in _state.seen

func mark_story_seen(index: int, phase: String) -> bool:
	if not _ready() or read_only or _busy or _state.view.is_empty() or index < 0 or index > int(_state.view.current_index) or phase not in ["arrival","completion"]: return _error("story_unavailable")
	if _state.view.activation != null: return _error("campaign_activation_pending")
	if phase == "completion" and _state.view.chapters[index].completion == null: return _error("story_unavailable")
	var marker := str(index)+":"+phase
	if marker in _state.seen: return true
	var next := _state.duplicate(true)
	next.seen.append(marker)
	return _persist(next)

func _merge_view(observed: Dictionary, rejected: Dictionary = {}) -> Dictionary:
	if _state.view.is_empty(): return observed.duplicate(true)
	var saved: Dictionary = _state.view
	if saved.host_id != observed.host_id or (saved.guest_id != null and saved.guest_id != observed.guest_id):
		_error("campaign_members_changed")
		return {}
	if observed.revision < saved.revision: return saved.duplicate(true)
	if saved.state == "deleting" and observed.state != "deleting":
		_error("campaign_deleting")
		return {}
	if observed.revision == saved.revision and not Canonical.same(observed,saved):
		_error("campaign_revision_conflict")
		return {}
	if saved.activation == null and observed.activation != null and observed.current_index == saved.current_index:
		_error("campaign_activation_conflict")
		return {}
	if saved.transition != null and observed.state != "deleting":
		var completed := _transition_completed(saved.transition,observed)
		var same_transition: bool = observed.transition != null and saved.transition.transition_id == observed.transition.transition_id and Canonical.same(saved.transition.origin,observed.transition.origin)
		var phases := ["prepared","source_sealed","target_initialized"]
		var aborted: bool = saved.transition.phase == "prepared" and not rejected.is_empty() and Canonical.same(saved.transition.origin,rejected.origin)
		# Sealed sources cannot abort, even if a contradictory authenticated
		# response claims a fork. A prepared source needs the bound receipt.
		if (same_transition and phases.find(observed.transition.phase) < phases.find(saved.transition.phase)) or (not same_transition and not completed and not aborted):
			_error("campaign_transition_conflict")
			return {}
	for index in range(saved.chapters.size()):
		var previous: Dictionary = saved.chapters[index]
		if previous.room_id != null and previous.room_id != observed.chapters[index].room_id or previous.completion != null and not Canonical.same(previous.completion,observed.chapters[index].completion):
			_error("campaign_history_conflict")
			return {}
	return observed.duplicate(true)

func _transition_completed(transition: Dictionary, campaign: Dictionary) -> bool:
	var from: Dictionary = transition.origin
	var completion: Variant = campaign.chapters[int(from.from_index)].completion
	return completion is Dictionary and completion.transition_id == transition.transition_id and completion.from_campaign_revision == from.expected_revision and completion.source_revision == from.source.revision and completion.source_branch == from.source.branch and completion.checkpoint_hash == from.source.checkpoint_hash

func _state_valid(value: Variant) -> bool:
	if not Protocol.bounded(value,49152,6144,16) or not Protocol.exact(value,["schema_version","owner_player_id","campaign_room_id","campaign_key","view","selected_room","pending","last_receipt","seen"]): return false
	if value.schema_version != 1 or value.owner_player_id != _owner or value.campaign_room_id != _anchor or not Canonical.same(value.campaign_key,Protocol.key(_definition)): return false
	if not value.view is Dictionary or not value.pending is Dictionary or not value.last_receipt is Dictionary or not value.selected_room is String or not value.seen is Array or value.seen.size() > 16: return false
	if value.view.is_empty(): return value.selected_room.is_empty() and value.pending.is_empty() and value.last_receipt.is_empty() and value.seen.is_empty()
	if not Protocol.view_valid(value.view,_definition,_owner) or value.view.campaign_room_id != _anchor: return false
	if not value.selected_room.is_empty():
		var found := false
		for entry: Dictionary in value.view.chapters:
			if entry.room_id == value.selected_room: found = true
		if not found: return false
	if not value.pending.is_empty():
		if not Protocol.exact(value.pending,["body","request_hash","accepted_receipt"]) or not Protocol.continue_valid(value.pending.body,_anchor,_owner,_definition) or value.pending.request_hash != Protocol.request_hash(_anchor,_owner,value.pending.body) or not value.pending.accepted_receipt is Dictionary: return false
		if value.pending.body.from_index > value.view.current_index or value.pending.body.source.room_id != value.view.chapters[int(value.pending.body.from_index)].room_id or value.pending.body.expected_revision > value.view.revision: return false
		if not value.pending.accepted_receipt.is_empty() and (value.pending.accepted_receipt.has("reason") or not _receipt_valid(value.pending.accepted_receipt,value.pending.body,value.view)): return false
	if not value.last_receipt.is_empty():
		if not value.last_receipt.get("origin") is Dictionary: return false
		var body := Protocol.continue_body(_anchor,_owner,_definition,value.last_receipt.origin)
		if body.is_empty() or not _receipt_valid(value.last_receipt,body,value.view): return false
	var seen := {}
	for marker: Variant in value.seen:
		if not Protocol.matches(marker,"^[0-7]:(arrival|completion)$") or seen.has(marker): return false
		var index := int(marker.get_slice(":",0))
		if index > int(value.view.current_index) or (marker.ends_with(":completion") and value.view.chapters[index].completion == null): return false
		seen[marker] = true
	return true

func _receipt_valid(receipt: Dictionary, body: Dictionary, campaign: Dictionary) -> bool:
	return Protocol.result_valid({"schema_version":1,"operation":"campaign_continue","status":"rejected" if receipt.has("reason") else "accepted","receipt":receipt,"campaign":campaign},body,_anchor,_owner,_definition)

func _persist(next: Dictionary) -> bool:
	if not _ready() or read_only or not _state_valid(next): return _error("invalid_campaign_save")
	var result: Variant = _save.call(_scope,next.duplicate(true))
	if not result is Dictionary or result.get("ok") != true: return _error("storage_unavailable")
	_state = next
	last_code = ""
	return true

func _enter() -> Dictionary:
	if not _ready() or read_only or _busy:
		_error("campaign_unavailable")
		return {}
	_busy = true
	return {"owner":_owner,"epoch":_epoch,"generation":_generation}

func _leave(context: Dictionary) -> void:
	if context.get("generation") == _generation: _busy = false

func _same(context: Dictionary) -> bool:
	return _ready() and context.owner == _owner and context.epoch == _epoch and context.generation == _generation

func _ready() -> bool:
	var identity: Variant = _identity.call()
	return not _state.is_empty() and _identity_valid(identity) and identity.player_id == _owner and int(identity.epoch) == _epoch

func _identity_valid(identity: Variant) -> bool:
	return identity is Dictionary and identity.get("ready") == true and Protocol.id_valid(identity.get("player_id")) and Protocol.integer(identity.get("epoch"))

func _call(context: Dictionary, method: int, path: String, body: Dictionary = {}) -> Dictionary:
	if not _same(context): return {"ok":false,"code":"identity_changed"}
	var response: Variant = await _transport.call({"method":method,"path":path,"body":body.duplicate(true),"owner_player_id":_owner,"identity_epoch":_epoch})
	if not _same(context): return {"ok":false,"code":"identity_changed"}
	return response if response is Dictionary else {"ok":false,"code":"invalid_campaign_reply"}

func _okay(response: Dictionary) -> bool:
	if response.get("ok") == true: return true
	return _error(str(response.get("code","connection_interrupted")))

func _error(code: String) -> bool:
	last_code = code
	return false

func _hold(code: String) -> bool:
	read_only = true
	return _error(code)
