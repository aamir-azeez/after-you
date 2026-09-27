extends RefCounted
## Unenabled owner adapter. The lobby is the sole durable writer of its bound
## campaign pointer; every eventual navigation entry must use its leave guard.
const Protocol = preload("res://services/campaign_protocol.gd")
const Campaign = preload("res://services/campaign_session.gd")
const Store = preload("res://services/relay_online_store.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const LobbyProtocol = preload("res://services/campaign_lobby_protocol.gd")
const CampaignCapabilities = preload("res://services/campaign_capabilities.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
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
var _lobby_capabilities: Dictionary = {}
var _server_campaigns: Array = []

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
	_lobby_capabilities = {}
	_server_campaigns = []
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
	if not _lobby.pending.is_empty(): return _error("campaign_lobby_pending")
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

func resume_activation() -> bool:
	# This explicit recovery remains available while activation correctly holds
	# ordinary departure and adoption. It does not authorize a new Continue.
	return await _run_control("resume_activation")

func resume_continuation() -> bool:
	# A member without a saved Continue can recover the exact published source
	# without selecting it for play or adopting a provisional target.
	if _busy or not restore_owner() or _campaign == null or _bridge == null or not _source_ready(): return _error("source_not_ready")
	if not _lobby.pending.is_empty(): return _error("campaign_lobby_pending")
	var publication: Dictionary = _campaign.view()
	if _campaign.read_only or _campaign.busy() or not _campaign.pending().is_empty() or publication.is_empty() or publication.state != "continuing" or publication.activation != null: return _error("continuation_unavailable")
	_busy = true
	var context := _context()
	var campaign: RefCounted = _campaign
	var bridge: RefCounted = _bridge
	var source: RefCounted = await bridge.continuation_source()
	if not _same(context): return _identity_changed(context)
	if source == null:
		_busy = false
		return _error(bridge.last_code)
	if not _source_ready() or not Canonical.same(campaign.view(),publication) or not campaign.pending().is_empty():
		_busy = false
		return _error("continuation_changed")
	var okay: bool = await campaign.continue_from(source)
	if not _same(context): return _identity_changed(context)
	_busy = false
	last_code = "" if okay else campaign.last_code
	return okay

func adoption_ready() -> bool:
	# UI preflight observes the existing owner; it must not restore/unbind it.
	if not _loaded or _busy or read_only or _bridge == null or _campaign == null: return false
	# Observe the loaded lobby directly: pending_lobby() may restore the owner.
	if not _lobby.get("pending",{}).is_empty(): return false
	var identity := _current_identity()
	if identity.is_empty() or identity.player_id != _owner or int(identity.epoch) != _epoch: return false
	return _bridge.adoption_ready()

func adopt_selected() -> bool:
	if _busy or not restore_owner() or _bridge == null: return _error("campaign_unavailable")
	if not _lobby.pending.is_empty(): return _error("campaign_lobby_pending")
	var okay: bool = _bridge.adopt_selected()
	last_code = "" if okay else _bridge.last_code
	return okay

func reopen_selected() -> bool:
	if _busy or not restore_owner() or _bridge == null: return _error("campaign_unavailable")
	if not _lobby.pending.is_empty(): return _error("campaign_lobby_pending")
	_busy = true
	var context := _context()
	var bridge: RefCounted = _bridge
	var okay: bool = await bridge.reopen_selected()
	if not _same(context): return _identity_changed(context)
	_busy = false
	last_code = "" if okay else bridge.last_code
	return okay

func restore_selected_room() -> bool:
	# Cold entry into this durable owner is different from choosing another room.
	if _busy or not restore_owner() or _campaign == null or _campaign.read_only or _campaign.busy(): return _error("campaign_unavailable")
	if not _lobby.pending.is_empty(): return _error("campaign_lobby_pending")
	if not _leave_ready.is_valid() or _leave_ready.call() != true: return _error("previous_room_busy")
	var publication: Dictionary = _campaign.view()
	var room_id: String = _campaign.selected_room()
	if publication.is_empty() or room_id.is_empty() or publication.state == "deleting": return _error("selection_unavailable")
	var selected_index := -1
	for index in range(int(publication.current_index)+1):
		if publication.chapters[index].room_id == room_id: selected_index = index
	if selected_index < 0: return _error("selection_unavailable")
	var historical := selected_index < int(publication.current_index)
	if not historical and publication.activation != null: return _error("campaign_activation_pending")
	var lease: Dictionary = _online.capture_campaign_restore_lease(room_id)
	if lease.is_empty(): return _error("previous_room_changed")
	var context := _context()
	var pin: Dictionary = publication.chapters[selected_index].chapter
	var recovered := Coordinator.new(_online.transport,_store.load_scope,_store.save_scope,_identity)
	recovered.accepted_pair_cache = _online.accepted_pair_cache
	recovered.supported_simulation_versions = {Registry.resolve(pin):int(pin.simulation_version)}
	if not recovered.bind_room(room_id) or recovered.read_only: return _error("target_cache_unavailable")
	var room := recovered.snapshot()
	if room.is_empty() or room.get("host_id") != publication.host_id or room.get("player_slot") != publication.player_slot: return _error("target_mismatch")
	var member_changed: bool = room.get("guest_id") != publication.guest_id
	# Host A may predate the first Join. Reconcile it without fresh play from stale members.
	if member_changed and not (room.get("guest_id") == null and publication.guest_id != null and publication.player_slot == "p0"): return _error("target_mismatch")
	for field: String in ["level_id","level_version","definition_hash"]:
		if room.get(field) != pin[field]: return _error("target_mismatch")
	if room.get("simulation_version",Registry.definition(Registry.resolve(pin)).get("simulation_version")) != pin.simulation_version: return _error("target_mismatch")
	if historical or member_changed or publication.state in ["continuing","complete"]: recovered.restrict_campaign_recovery()
	if not _same(context) or not Canonical.same(_campaign.view(),publication) or _campaign.selected_room() != room_id: return _error("selection_changed")
	if not _leave_ready.is_valid() or _leave_ready.call() != true: return _error("previous_room_busy")
	if not _online.restore_campaign_selected(recovered,lease): return _error("previous_room_changed")
	last_code = ""
	return true

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
	if not _lobby.pending.is_empty() and method != "refresh": return _error("campaign_lobby_pending")
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
	if (value.schema_version != 1 and value.schema_version != 2 and value.schema_version != 3) or value.owner_player_id != _owner or not value.campaigns is Array or value.campaigns.size() > MAX_HISTORY or not value.bound_campaign is Dictionary or not value.pending is Dictionary: return false
	if not value.pending.is_empty():
		if value.schema_version == 1 or not _valid_lobby_pending(value.pending,int(value.schema_version)): return false
	var anchors := {}
	var has_bound: bool = value.bound_campaign.is_empty()
	for reference: Variant in value.campaigns:
		if not _reference_valid(reference) or anchors.has(reference.campaign_room_id): return false
		anchors[reference.campaign_room_id] = true
		if Canonical.same(reference,value.bound_campaign): has_bound = true
	if not value.pending.is_empty() and not value.pending.accepted_campaign.is_empty():
		var has_accepted := false
		for reference: Dictionary in value.campaigns:
			if Canonical.same(reference,value.pending.accepted_campaign): has_accepted = true
		if not has_accepted: return false
	return has_bound

func _valid_lobby_pending(value: Variant, schema: int) -> bool:
	var fields := ["path","body","request_hash","accepted_campaign"]
	if schema == 3: fields.append("cancel_requested")
	if not Protocol.exact(value,fields): return false
	if schema == 3 and not value.cancel_requested is bool: return false
	var request: Dictionary = value.duplicate(true)
	request.erase("accepted_campaign")
	request.erase("cancel_requested")
	if not LobbyProtocol.pending_valid(request,_definitions.values(),_owner) or not value.accepted_campaign is Dictionary: return false
	if value.accepted_campaign.is_empty(): return true
	if not _reference_valid(value.accepted_campaign) or not Canonical.same(value.accepted_campaign.campaign_key,value.body.campaign_key): return false
	return value.path != "/v2/campaigns/join" or value.accepted_campaign.campaign_room_id == ("v2:"+value.body.invite_code).sha256_text().substr(0,22)

func _empty_lobby() -> Dictionary:
	return {"schema_version":1,"owner_player_id":_owner,"campaigns":[],"bound_campaign":{},"pending":{}}

func pending_lobby() -> Dictionary:
	return _lobby.pending.duplicate(true) if restore_owner() else {}

func server_campaigns() -> Array:
	return _server_campaigns.duplicate(true) if restore_owner() else []

func supports_campaign_creation(campaign_key: Dictionary) -> bool:
	if not restore_owner() or not _lobby_capabilities.get("creation",false): return false
	return not LobbyProtocol.definition_for(campaign_key,_lobby_capabilities.definitions).is_empty()

func load_campaign_lobby() -> bool:
	if _busy or not restore_owner(): return false
	_busy = true
	var context := _context()
	if not await _online.load_capabilities():
		if not _same(context): return _identity_changed(context)
		_lobby_capabilities = {}
		_busy = false
		return _error("campaign_capabilities_unavailable")
	if not _same(context): return _identity_changed(context)
	_lobby_capabilities = CampaignCapabilities.read(_online.capabilities,_definitions.values())
	if not _lobby_capabilities.valid:
		_busy = false
		return _error("campaign_capabilities_unavailable")
	var response := await _lobby_call(context,HTTPClient.METHOD_GET,"/v2/campaigns")
	if not _same(context): return _identity_changed(context)
	if response.get("ok") != true or response.get("status") != 200 or not LobbyProtocol.list_valid(response.get("data"),_definitions.values(),_owner):
		_busy = false
		return _error("campaign_list_unavailable")
	var next := _lobby.duplicate(true)
	for view: Dictionary in response.data.campaigns:
		var reference := {"campaign_room_id":view.campaign_room_id,"campaign_key":view.campaign_key.duplicate(true)}
		if not _append_reference(next,reference):
			_busy = false
			return false
	if not _persist_lobby(next):
		if _same(context): _busy = false
		return false
	_server_campaigns = response.data.campaigns.duplicate(true)
	_busy = false
	return true

func create_campaign(campaign_key: Dictionary) -> String:
	if not supports_campaign_creation(campaign_key) or not can_leave(): return ""
	if _lobby.campaigns.size() >= MAX_HISTORY:
		_error("campaign_history_full")
		return ""
	var definition := LobbyProtocol.definition_for(campaign_key,_definitions.values())
	var body := LobbyProtocol.create_body(definition,Crypto.new().generate_random_bytes(18).hex_encode())
	return await _start_lobby_request("/v2/campaigns",body)

func join_campaign(campaign_key: Dictionary, invitation: String) -> String:
	if not supports_campaign_creation(campaign_key) or not can_leave(): return ""
	var definition := LobbyProtocol.definition_for(campaign_key,_definitions.values())
	var body := LobbyProtocol.join_body(definition,invitation,Crypto.new().generate_random_bytes(18).hex_encode())
	if body.is_empty():
		_error("invalid_campaign_invitation")
		return ""
	var reference := {"campaign_room_id":("v2:"+body.invite_code).sha256_text().substr(0,22),"campaign_key":campaign_key.duplicate(true)}
	var capacity_check := _lobby.duplicate(true)
	if not _append_reference(capacity_check,reference): return ""
	return await _start_lobby_request("/v2/campaigns/join",body)

func _start_lobby_request(path: String, body: Dictionary) -> String:
	if body.is_empty() or not can_leave(): return ""
	var next := _lobby.duplicate(true)
	next.schema_version = 3
	next.pending = {"path":path,"body":body.duplicate(true),"request_hash":LobbyProtocol.request_hash(_owner,path,body),"accepted_campaign":{},"cancel_requested":false}
	if not _persist_lobby(next): return ""
	return await retry_lobby_request()

func retry_lobby_request() -> String:
	if _busy or not restore_owner() or _lobby.pending.is_empty(): return ""
	if _lobby.pending.get("cancel_requested",false) and _lobby.pending.accepted_campaign.is_empty():
		await _retry_lobby_cancel()
		return ""
	if not _source_ready(): return ""
	var lease: Dictionary = _online.capture_campaign_source_lease()
	if lease.is_empty(): return ""
	_busy = true
	var context := _context()
	var pending: Dictionary = _lobby.pending.duplicate(true)
	var accepted: Dictionary = pending.accepted_campaign.duplicate(true)
	if accepted.is_empty():
		# Paused fresh creation does not discard a previously admitted request.
		# The server resolves exact accepted retries before new admission policy.
		if not _lobby_capabilities.get("lobby_retry",false): return _lobby_failure(context,"campaign_mutations_unavailable")
		var response := await _lobby_call(context,HTTPClient.METHOD_POST,pending.path,pending.body)
		if not _same(context): return _lobby_failure(context,"identity_changed")
		if response.get("ok") != true: return _lobby_failure(context,str(response.get("code","campaign_request_unavailable")))
		var allowed_status: bool = response.get("status") in [200,201] if pending.path == "/v2/campaigns" else response.get("status") == 200
		var definition := LobbyProtocol.definition_for(pending.body.campaign_key,_definitions.values())
		var anchor: String = ("v2:"+pending.body.invite_code).sha256_text().substr(0,22) if pending.path == "/v2/campaigns/join" else ""
		if not allowed_status or not LobbyProtocol.envelope_valid(response.get("data"),definition,_owner,anchor): return _lobby_failure(context,"invalid_campaign_reply")
		var view: Dictionary = response.data.campaign
		if pending.path == "/v2/campaigns" and view.host_id != _owner: return _lobby_failure(context,"invalid_campaign_reply")
		accepted = {"campaign_room_id":view.campaign_room_id,"campaign_key":view.campaign_key.duplicate(true)}
		var next := _lobby.duplicate(true)
		if not _append_reference(next,accepted): return _lobby_failure(context,last_code)
		next.pending.accepted_campaign = accepted.duplicate(true)
		if not _persist_lobby(next): return _lobby_failure(context,last_code)
	# An accepted reference is recoverable even if input or photo work began
	# while its reply was in flight. Do not replace that displayed owner yet.
	if not _source_ready() or not Canonical.same(_online.observe_campaign_source_lease(),lease): return _lobby_failure(context,"previous_room_changed")
	if not Canonical.same(_lobby.bound_campaign,accepted):
		var bound := _lobby.duplicate(true)
		bound.bound_campaign = accepted.duplicate(true)
		if not _persist_lobby(bound): return _lobby_failure(context,last_code)
		# The accepted owner is durable before any journal read. Retire all old
		# candidates and use this new local generation for the remaining reads.
		_generation += 1
		_drop_bound()
		context = _context()
		if not _load_bound(): return _lobby_failure(context,last_code)
	if not Canonical.same(_lobby.bound_campaign,accepted) or _campaign == null: return _lobby_failure(context,"campaign_owner_changed")
	var campaign: RefCounted = _campaign
	if not await campaign.refresh(): return _lobby_failure(context,campaign.last_code)
	if not _same(context) or _campaign != campaign: return _lobby_failure(context,"identity_changed")
	if not _source_ready() or not Canonical.same(_online.observe_campaign_source_lease(),lease): return _lobby_failure(context,"previous_room_changed")
	# Control can already be continuing or deleting on another device. Its
	# durable journal owns that recovery; a create/join lock must not prevent it.
	var settled := _lobby.duplicate(true)
	settled.pending = {}
	if not _persist_lobby(settled): return _lobby_failure(context,last_code)
	_busy = false
	last_code = ""
	return accepted.campaign_room_id

func cancel_lobby_request() -> bool:
	if _busy or not restore_owner() or _lobby.pending.is_empty(): return false
	# A durable acceptance is settled with GET; cancellation cannot erase it.
	if not _lobby.pending.accepted_campaign.is_empty(): return _error("campaign_already_accepted")
	if not _lobby.pending.get("cancel_requested",false):
		var next := _lobby.duplicate(true)
		next.schema_version = 3
		next.pending["cancel_requested"] = true
		if not _persist_lobby(next): return false
	return await _retry_lobby_cancel()

func _retry_lobby_cancel() -> bool:
	if _busy or not restore_owner() or _lobby.pending.is_empty() or not _lobby.pending.get("cancel_requested",false) or not _lobby.pending.accepted_campaign.is_empty(): return false
	# Cancelling never adopts or changes the displayed room, so saved input and
	# photo work may remain. Only the exact durable server fence clears intent.
	if not _lobby_capabilities.get("lobby_retry",false): return _error("campaign_mutations_unavailable")
	_busy = true
	var context := _context()
	var pending: Dictionary = _lobby.pending.duplicate(true)
	var response := await _lobby_call(context,HTTPClient.METHOD_POST,LobbyProtocol.cancel_path(pending.path),pending.body)
	if not _same(context):
		_lobby_failure(context,"identity_changed")
		return false
	if not Canonical.same(_lobby.pending,pending):
		_lobby_failure(context,"campaign_request_changed")
		return false
	if response.get("ok") != true or response.get("status") != 200 or not LobbyProtocol.cancellation_valid(response.get("data"),pending,_definitions.values(),_owner):
		_lobby_failure(context,"campaign_cancel_unavailable")
		return false
	var next := _lobby.duplicate(true)
	if response.data.status == "accepted":
		var view: Dictionary = response.data.campaign
		var accepted := {"campaign_room_id":view.campaign_room_id,"campaign_key":view.campaign_key.duplicate(true)}
		if not _append_reference(next,accepted):
			_lobby_failure(context,last_code)
			return false
		next.pending.accepted_campaign = accepted
	else:
		next.pending = {}
	if not _persist_lobby(next):
		_lobby_failure(context,last_code)
		return false
	_busy = false
	last_code = "campaign_already_accepted" if response.data.status == "accepted" else ""
	return response.data.status == "cancelled"

func _lobby_call(context: Dictionary, method: int, path: String, body: Dictionary = {}) -> Dictionary:
	return await _online.transport({"owner_player_id":context.owner,"identity_epoch":context.epoch,"method":method,"path":path,"body":body.duplicate(true)})

func _lobby_failure(context: Dictionary, code: String) -> String:
	if not _same(context):
		_identity_changed(context)
		return ""
	_busy = false
	_error(code)
	return ""

func _append_reference(value: Dictionary, reference: Dictionary) -> bool:
	for existing: Dictionary in value.campaigns:
		if existing.campaign_room_id == reference.campaign_room_id:
			return true if Canonical.same(existing,reference) else _error("campaign_pin_conflict")
	if value.campaigns.size() >= MAX_HISTORY: return _error("campaign_history_full")
	value.campaigns.append(reference.duplicate(true))
	return true

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
