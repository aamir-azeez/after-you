extends RefCounted
## Unenabled owner adapter. The lobby is the sole durable writer of its bound
## campaign pointer; every eventual navigation entry must use its leave guard.
const Protocol = preload("res://services/campaign_protocol.gd")
const Campaign = preload("res://services/campaign_session.gd")
const Store = preload("res://services/relay_online_store.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const LobbyProtocol = preload("res://services/campaign_lobby_protocol.gd")
const CampaignCapabilities = preload("res://services/campaign_capabilities.gd")
const RequestContext = preload("res://services/campaign_request_context.gd")
const Terminal = preload("res://services/campaign_terminal_session.gd")
const TerminalContext = preload("res://services/campaign_terminal_context.gd")
const TerminalAdmission = preload("res://services/campaign_terminal_admission.gd")
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
var _control_context: RefCounted
var _bridge: RefCounted
var _owner := ""
var _epoch := -1
var _generation := 0
var _auxiliary_retirement := 0
var _loaded := false
var _busy := false
var _lobby_capabilities: Dictionary = {}
var _server_campaigns: Array = []
var _ordinary_scan_signature := ""
var _ordinary_scan: Dictionary = {}
var _terminal: RefCounted
var _terminal_context: RefCounted
var _terminal_admission: RefCounted
var _terminal_hint := ""
var _terminal_retiring := ""
var _terminal_scan: Dictionary = {}
var _terminal_scan_signature := ""
var _terminal_scan_digest := ""

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
	_online.register_campaign_owner(self)

func invalidate_identity() -> void:
	if _terminal != null: _terminal.retire()
	if _terminal_admission != null: _terminal_admission.retire()
	_terminal = null
	_terminal_admission = null
	_terminal_context = null
	_terminal_hint = ""
	_terminal_retiring = ""
	_terminal_scan = {}
	_terminal_scan_signature = ""
	_terminal_scan_digest = ""
	_auxiliary_retirement += 1
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
	if _loaded and not retry and _terminal_current(): return not read_only
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
	if not _restore_terminal(context): return false
	if not _discover_terminal_retirement(): return _identity_changed(context)
	return _load_bound()

func bind_campaign(anchor: String, campaign_key: Dictionary) -> bool:
	if _busy or not restore_owner(): return false
	var reference := {"campaign_room_id":anchor,"campaign_key":campaign_key.duplicate(true)}
	if not _reference_valid(reference) or _definition(reference).is_empty(): return _error("campaign_unavailable")
	if terminal_anchor_released(anchor): return _error("campaign_terminal_reconciliation_required")
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
	if _busy or not restore_owner(): return false
	if not _terminal_recovery().is_empty(): return _error("campaign_terminal_reconciliation_required")
	if not _source_ready(): return false
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
	var recovered := _new_child(room_id,pin,"selected")
	if recovered == null: return _error("campaign_context_changed")
	recovered.accepted_pair_cache = _online.accepted_pair_cache
	recovered.supported_simulation_versions = {Registry.resolve(pin):int(pin.simulation_version)}
	if not recovered.bind_room(room_id) or recovered.read_only: return _error("target_cache_unavailable")
	var room: Dictionary = recovered.snapshot()
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
	if not _lobby.bound_campaign.is_empty() and terminal_anchor_released(_lobby.bound_campaign.campaign_room_id):
		_terminal_retiring = _lobby.bound_campaign.campaign_room_id
		last_code = "campaign_terminal_reconciliation_required"
		return true
	if _lobby.bound_campaign.is_empty():
		last_code = ""
		return true
	var bundled := _definition(_lobby.bound_campaign)
	if bundled.is_empty(): return _hold("bound_campaign_unavailable")
	_bridge = _online.campaign_room_bridge(bundled,_leave_ready,_new_child)
	var binding := _context()
	binding["campaign"] = _lobby.bound_campaign.duplicate(true)
	_control_context = RequestContext.new(self,binding)
	_campaign = Campaign.new(_control_context.request,_store.load_scope,_store.save_scope,_identity,_bridge.validate_target,_bridge.selection_ready,_control_context,_bridge)
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
	_control_context = null

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
	if not restore_owner(): return []
	var active: Array = []
	for publication: Dictionary in _server_campaigns:
		if not terminal_anchor_released(publication.campaign_room_id): active.append(publication.duplicate(true))
	return active

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
	if not _lobby_capabilities.valid and not _terminal_capabilities().get("valid",false):
		_busy = false
		return _error("campaign_capabilities_unavailable")
	var response := await _lobby_call(context,HTTPClient.METHOD_GET,"/v2/campaigns")
	if not _same(context): return _identity_changed(context)
	var terminal_hint := Terminal.parse_hint(response)
	if not terminal_hint.is_empty():
		_terminal_hint = terminal_hint
		_busy = false
		return _error(Terminal.HINT_CODE)
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
	if terminal_anchor_released(_pending_terminal_anchor()):
		_error(Terminal.HINT_CODE)
		return ""
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
	if terminal_anchor_released(_pending_terminal_anchor()): return _error(Terminal.HINT_CODE)
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
	if not _mapped_terminal_anchor().is_empty(): return _error(Terminal.HINT_CODE)
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
	var original := _admission_request(pending)
	if response.get("ok") == true and response.get("status") == 200 and TerminalAdmission.terminal_valid(response.get("data"),original,_owner):
		if not _online.terminal_index_ready():
			_lobby_failure(context,"campaign_terminal_retirement_pending")
			return false
		# The server correlates only this exact Create key/body to the permanent
		# root. Archive that real result before exposing a separate cleanup action.
		var mapper: RefCounted = _terminal_admission
		var saved: bool = mapper.record_mapping(original,{"kind":"server_create","terminal":response.data.duplicate(true)},_observe_terminal_pending)
		if not _same(context) or mapper != _terminal_admission or not _terminal_current():
			_lobby_failure(context,"campaign_context_changed")
			return false
		if not saved:
			_lobby_failure(context,mapper.last_code)
			return false
		_busy = false
		return _error(Terminal.HINT_CODE)
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
	return await dispatch_campaign_request(context,"lobby",{"owner_player_id":context.owner,"identity_epoch":context.epoch,"method":method,"path":path,"body":body.duplicate(true)})

func dispatch_campaign_request(context: Dictionary, purpose: String, request: Dictionary) -> Dictionary:
	# Contexts are created explicitly by this owner. The negotiation header is
	# separate from server authority and from the unchanged saved request body.
	var fields := ["owner","epoch","generation"]
	if purpose == "control": fields.append("campaign")
	if purpose not in ["lobby","control"] or not Protocol.exact(context,fields): return _transport_hold("campaign_context_changed")
	if not _same(context) or read_only or not _loaded or not Protocol.exact(request,["owner_player_id","identity_epoch","method","path","body"]): return _transport_hold("campaign_context_changed")
	if request.owner_player_id != context.owner or request.identity_epoch != context.epoch or not request.path is String or not request.body is Dictionary: return _transport_hold("campaign_context_changed")
	if not Protocol.integer(request.method,0,8): return _transport_hold("campaign_route_unavailable")
	var path: String = request.path
	var method: int = request.method
	var publication := {}
	var campaign: RefCounted
	if purpose == "lobby":
		if method == HTTPClient.METHOD_GET:
			if path != "/v2/campaigns" or not request.body.is_empty(): return _transport_hold("campaign_route_unavailable")
		elif method == HTTPClient.METHOD_POST:
			if _lobby.pending.is_empty() or not _lobby.pending.accepted_campaign.is_empty() or not _lobby_capabilities.get("lobby_retry",false): return _transport_hold("campaign_mutations_unavailable")
			var capabilities := CampaignCapabilities.read(_online.capabilities,_definitions.values())
			if not capabilities.lobby_retry: return _transport_hold("campaign_mutations_unavailable")
			var pending: Dictionary = _lobby.pending
			var expected: String = LobbyProtocol.cancel_path(pending.path) if pending.get("cancel_requested",false) else pending.path
			if path != expected or not Canonical.same(request.body,pending.body): return _transport_hold("campaign_request_changed")
		else: return _transport_hold("campaign_route_unavailable")
	elif purpose == "control":
		if _campaign == null or not context.has("campaign") or not Canonical.same(context.campaign,_lobby.bound_campaign): return _transport_hold("campaign_context_changed")
		if terminal_anchor_released(context.campaign.campaign_room_id): return _transport_hold(Terminal.HINT_CODE)
		campaign = _campaign
		publication = campaign.view()
		var root_path: String = "/v2/campaigns/"+context.campaign.campaign_room_id
		var pending: Dictionary = campaign.pending()
		if method == HTTPClient.METHOD_GET:
			if not request.body.is_empty(): return _transport_hold("campaign_route_unavailable")
			if path != root_path and (pending.is_empty() or path != root_path+"/operations/"+pending.body.idempotency_key): return _transport_hold("campaign_route_unavailable")
		elif method == HTTPClient.METHOD_POST:
			var capabilities := CampaignCapabilities.read(_online.capabilities,_definitions.values())
			if not capabilities.mutations: return _transport_hold("campaign_mutations_unavailable")
			if path == root_path+"/continue":
				if pending.is_empty() or not Canonical.same(request.body,pending.body): return _transport_hold("campaign_request_changed")
			elif path == root_path+"/resume":
				if publication.is_empty() or publication.activation == null or not Protocol.resume_activation_valid(request.body,_definition(context.campaign)) or request.body.transition_id != publication.activation.transition_id: return _transport_hold("campaign_request_changed")
			else: return _transport_hold("campaign_route_unavailable")
		else: return _transport_hold("campaign_route_unavailable")
	else: return _transport_hold("campaign_route_unavailable")
	var response: Dictionary = await _online.campaign_transport(request)
	if not _same(context): return _transport_hold("campaign_context_changed")
	if purpose == "control" and (terminal_anchor_released(context.campaign.campaign_room_id) or _campaign != campaign or not Canonical.same(context.campaign,_lobby.bound_campaign) or not Canonical.same(campaign.view(),publication)): return _transport_hold("campaign_context_changed")
	return response

func _transport_hold(code: String) -> Dictionary:
	return {"ok":false,"status":0,"code":code}

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

func _new_child(room_id: String, pin: Dictionary, purpose: String) -> RefCounted:
	var binding := _context()
	binding["campaign"] = _lobby.get("bound_campaign",{}).duplicate(true)
	binding["room_id"] = room_id
	binding["pin"] = pin.duplicate(true)
	binding["selection_generation"] = _online.campaign_selection_generation()
	if _child_publication(binding,purpose).is_empty(): return null
	var context := RequestContext.new(self,binding,purpose)
	var child := Coordinator.new(context.request,_store.load_scope,_store.save_scope,_identity,Callable(),context,context.permits_live,context.recovery_only)
	context.bind_coordinator(child)
	return child

func _child_publication(binding: Dictionary, purpose: String) -> Dictionary:
	if purpose not in ["target","selected","continuation"] or not Protocol.exact(binding,["owner","epoch","generation","campaign","room_id","pin","selection_generation"]): return {}
	if not _loaded or read_only or not _same(binding) or _campaign == null or _campaign.read_only or not Canonical.same(binding.campaign,_lobby.bound_campaign): return {}
	if terminal_anchor_released(binding.campaign.campaign_room_id): return {}
	var publication: Dictionary = _campaign.view()
	if not Protocol.view_valid(publication,_definition(binding.campaign),_owner) or publication.state == "deleting": return {}
	var index := -1
	for candidate in range(int(publication.current_index)+1):
		var entry: Dictionary = publication.chapters[candidate]
		if entry.room_id == binding.room_id and Canonical.same(entry.chapter,binding.pin): index = candidate
	if index < 0 or (index == int(publication.current_index) and publication.activation != null): return {}
	if purpose == "continuation" and (publication.state != "continuing" or index != int(publication.current_index) or publication.transition == null or publication.transition.origin.source.room_id != binding.room_id): return {}
	return publication

func child_live_allowed(binding: Dictionary, purpose: String, child: RefCounted, include_transient_holds: bool = true) -> bool:
	if child == null or child.get_script() != Coordinator or purpose == "continuation": return false
	# A running control read or separate lobby intent pauses fresh input, but
	# does not replace an otherwise current chapter with a recovery-only screen.
	# Its same-context History remains read-only and explicitly available.
	var publication := _child_publication(binding,purpose)
	if publication.is_empty() or publication.state not in ["waiting","active"] or not _campaign.pending().is_empty(): return false
	if include_transient_holds and (_busy or not _lobby.pending.is_empty()): return false
	if _online.coordinator != child or _campaign.selected_room() != binding.room_id or publication.chapters[int(publication.current_index)].room_id != binding.room_id: return false
	var room: Dictionary = child.snapshot()
	return _child_room_matches(room,binding,publication)

func _child_room_matches(room: Variant, binding: Dictionary, publication: Dictionary) -> bool:
	if not room is Dictionary or room.get("room_id") != binding.room_id or room.get("host_id") != publication.host_id or room.get("guest_id") != publication.guest_id or room.get("player_slot") != publication.player_slot: return false
	for field: String in ["level_id","level_version","definition_hash"]:
		if room.get(field) != binding.pin[field]: return false
	return room.get("simulation_version",Registry.definition(Registry.resolve(binding.pin)).get("simulation_version")) == binding.pin.simulation_version

func dispatch_child_request(binding: Dictionary, purpose: String, child: RefCounted, request: Dictionary) -> Dictionary:
	var publication := _child_publication(binding,purpose)
	if publication.is_empty() or child == null or child.get_script() != Coordinator or not Protocol.exact(request,["owner_player_id","identity_epoch","method","path","body"]): return _transport_hold("campaign_context_changed")
	if request.owner_player_id != binding.owner or request.identity_epoch != binding.epoch or not request.path is String or not request.body is Dictionary or not Protocol.integer(request.method,0,8): return _transport_hold("campaign_context_changed")
	var selected: String = _campaign.selected_room()
	var adopted: bool = _online.coordinator == child and selected == binding.room_id
	var root_path: String = "/v2/rooms/"+binding.room_id
	var pending: Dictionary = child.pending()
	if not adopted:
		if purpose == "selected" or _online.campaign_selection_generation() != binding.selection_generation: return _transport_hold("campaign_context_changed")
		if purpose == "target" and (publication.state not in ["waiting","active","complete"] or publication.chapters[int(publication.current_index)].room_id != binding.room_id): return _transport_hold("campaign_context_changed")
		if request.method != HTTPClient.METHOD_GET or request.path != root_path or not request.body.is_empty(): return _transport_hold("campaign_route_unavailable")
	elif request.method == HTTPClient.METHOD_GET:
		if not request.body.is_empty(): return _transport_hold("campaign_route_unavailable")
		var receipt: bool = not pending.is_empty() and request.path == root_path+"/operations/"+pending.body.idempotency_key
		var pair: bool = request.path.begins_with(root_path+"/pairs/") and RegEx.create_from_string("^p[0-9]{1,2}-[01]$").search(request.path.trim_prefix(root_path+"/pairs/")) != null
		if request.path != root_path and not receipt and not pair: return _transport_hold("campaign_route_unavailable")
	elif request.method == HTTPClient.METHOD_POST:
		# Both new native commits and retained recovery have an exact durable
		# pending body before transport. Historical sources cannot create a new one.
		if pending.is_empty() or pending.operation not in ["turns","fork"] or request.path != root_path+"/"+pending.operation or not Canonical.same(request.body,pending.body): return _transport_hold("campaign_request_changed")
	else: return _transport_hold("campaign_route_unavailable")
	var selection_generation: int = _online.campaign_selection_generation()
	var response: Dictionary = await _online.campaign_transport(request)
	if not Canonical.same(_child_publication(binding,purpose),publication) or _campaign == null or _campaign.selected_room() != selected or _online.campaign_selection_generation() != selection_generation: return _transport_hold("campaign_context_changed")
	if adopted and _online.coordinator != child: return _transport_hold("campaign_context_changed")
	if response.get("ok") == true and not request.path.begins_with(root_path+"/pairs/"):
		var data: Variant = response.get("data")
		var room: Variant = data if request.path == root_path else (data.get("room") if data is Dictionary else null)
		if not _child_room_matches(room,binding,publication): return _transport_hold("campaign_room_mismatch")
	return response

func classification_context() -> Dictionary:
	return {"owner":_owner,"epoch":_epoch,"generation":_generation,"lobby":Canonical.digest(_lobby),
		"journal":_campaign.journal_revision() if _campaign != null else -1,"terminal":_terminal_scan_digest}

func ordinary_entry_allowed() -> bool:
	return restore_owner() and not _busy and _terminal_recovery().is_empty() and _lobby.bound_campaign.is_empty() and _lobby.pending.is_empty()

func classify_room(room_id: String) -> Dictionary:
	# Detached reads never bind another story or write/repair its journal. List
	# entries may legitimately have no journal until the player opens them.
	if not Protocol.id_valid(room_id) or not restore_owner(): return {"ok":false}
	var signature := Canonical.digest({"owner":_owner,"epoch":_epoch,"generation":_generation,
		"lobby":_lobby,"journal":_campaign.journal_revision() if _campaign != null else -1})
	if signature != _ordinary_scan_signature:
		var context := _context()
		var found := {}
		for reference: Dictionary in _lobby.campaigns:
			var anchor: String = reference.campaign_room_id
			_classify_add(found,anchor,{"kind":"anchor","reference":reference.duplicate(true)})
			var definition := _definition(reference)
			if definition.is_empty(): continue
			var loaded: Variant = _store.load_scope("relay-campaign-v1:"+_owner+":"+anchor)
			if not _same(context): return {"ok":false}
			if not loaded is Dictionary or loaded.get("ok") != true or loaded.get("found") != true: continue
			var value: Variant = loaded.get("value")
			if not Campaign.saved_state_valid(value,anchor,_owner,definition) or value.view.is_empty(): continue
			for entry: Dictionary in value.view.chapters:
				if entry.room_id == null: continue
				var room: String = entry.room_id
				_classify_add(found,room,{"kind":"child","reference":reference.duplicate(true),"publication":value.view.duplicate(true),"pin":entry.chapter.duplicate(true)})
		_ordinary_scan = found
		_ordinary_scan_signature = signature
	return {"ok":true,"campaign":_ordinary_scan.has(room_id),"entry_allowed":not _busy and _lobby.bound_campaign.is_empty() and _lobby.pending.is_empty(),"detail":_ordinary_scan.get(room_id,{}).duplicate(true)}

func _classify_add(found: Dictionary, room_id: String, detail: Dictionary) -> void:
	if not found.has(room_id):
		found[room_id] = detail
	elif not Canonical.same(found[room_id].get("reference",{}),detail.reference):
		found[room_id] = {"kind":"ambiguous"}
	elif detail.kind == "child":
		found[room_id] = detail

func auxiliary_retirement() -> int: return _auxiliary_retirement

func auxiliary_room_binding(room_id: String) -> Dictionary:
	# Cached discovery is bounded by lobby/control revisions. Fresh authority
	# comes from the exact target journal, without reparsing unrelated history.
	if not _loaded or read_only: return {"kind":"held"}
	var identity := _current_identity()
	if identity.is_empty() or identity.player_id != _owner or int(identity.epoch) != _epoch: return {"kind":"held"}
	if terminal_anchor_released(room_id): return {"kind":"held"}
	var classified := classify_room(room_id)
	if classified.get("ok") != true: return {"kind":"held"}
	if not classified.campaign: return {"kind":"ordinary"}
	var detail: Dictionary = classified.detail
	if detail.get("kind") != "child": return {"kind":"held"}
	var reference: Dictionary = detail.reference
	if terminal_anchor_released(reference.campaign_room_id): return {"kind":"held"}
	var definition := _definition(reference)
	var context := _context()
	var loaded: Variant = _store.load_scope("relay-campaign-v1:"+_owner+":"+str(reference.campaign_room_id))
	if not _same(context) or not loaded is Dictionary or loaded.get("ok") != true or loaded.get("found") != true: return {"kind":"held"}
	var value: Variant = loaded.get("value")
	if definition.is_empty() or not Campaign.saved_state_valid(value,reference.campaign_room_id,_owner,definition) or value.view.is_empty(): return {"kind":"held"}
	var publication: Dictionary = value.view
	if publication.state == "deleting": return {"kind":"held"}
	var index := -1
	for candidate in range(int(publication.current_index)+1):
		if publication.chapters[candidate].room_id == room_id: index = candidate
	if index < 0 or not Canonical.same(publication.chapters[index].chapter,detail.pin) or (index == int(publication.current_index) and publication.activation != null): return {"kind":"held"}
	return {"kind":"campaign","reference":detail.reference.duplicate(true),"pin":detail.pin.duplicate(true),"publication":publication.duplicate(true)}

func auxiliary_room_matches(room: Variant, binding: Dictionary, publication: Dictionary) -> bool:
	return _child_room_matches(room,binding,publication)

func _terminal_current() -> bool:
	return _terminal != null and _terminal_context != null and _terminal_context.current()

func _restore_terminal(context: Dictionary) -> bool:
	if _terminal != null: _terminal.retire()
	if _terminal_admission != null: _terminal_admission.retire()
	_terminal = null
	_terminal_admission = null
	_terminal_context = null
	_terminal_hint = ""
	_terminal_retiring = ""
	var lifetime: Dictionary = _online.terminal_lifetime(self)
	if not _same(context): return _identity_changed(context)
	if lifetime.is_empty(): return _hold("campaign_context_changed")
	_terminal_context = TerminalContext.new(self,_online,lifetime)
	_terminal = Terminal.new(_terminal_context.request,_identity,_terminal_context.current,_store,_terminal_context)
	var terminal: RefCounted = _terminal
	if not terminal.restore_owner():
		if not _same(context): return _identity_changed(context)
		return _hold(terminal.last_code)
	if not _same(context) or terminal != _terminal or not _terminal_current(): return _identity_changed(context)
	_terminal_admission = TerminalAdmission.new(_identity,_terminal_context.current,_store,_terminal_context)
	var mapper: RefCounted = _terminal_admission
	if not mapper.restore_owner():
		if not _same(context): return _identity_changed(context)
		return _hold(mapper.last_code)
	return _same(context) and _terminal_current()

func terminal_anchor_released(anchor: String) -> bool:
	# Pure authority observation; an in-flight repeat never hides old evidence.
	if not _loaded or read_only or not Protocol.id_valid(anchor) or not _terminal_current(): return false
	var identity := _current_identity()
	return not identity.is_empty() and identity.player_id == _owner and int(identity.epoch) == _epoch and not _terminal.terminal_receipt(anchor).is_empty()

func _terminal_signature() -> String:
	return Canonical.digest({"owner":_owner,"epoch":_epoch,"generation":_generation,"lobby":_lobby,
		"journal":_campaign.journal_revision() if _campaign != null else -1,
		"receipts":_terminal.released_receipts() if _terminal_current() else []})

func refresh_terminal_classification() -> bool:
	# One detached pass per restore/retirement boundary, not one scan per receipt
	# or per pointer. Online rechecks this after a synchronous pointer save.
	if not _loaded or read_only or not _terminal_current(): return false
	var context := _context()
	var signature := _terminal_signature()
	var found := {}
	var captures := {}
	var valid := true
	for receipt: Dictionary in _terminal.released_receipts():
		_classify_add(found,receipt.campaign_room_id,{"kind":"anchor","reference":{"campaign_room_id":receipt.campaign_room_id}})
	for reference: Dictionary in _lobby.campaigns:
		var anchor: String = reference.campaign_room_id
		if found.has(anchor) and found[anchor].get("kind") == "anchor" and found[anchor].reference.size() == 1: found.erase(anchor)
		_classify_add(found,anchor,{"kind":"anchor","reference":reference.duplicate(true)})
		var loaded: Variant = _store.load_scope("relay-campaign-v1:"+_owner+":"+anchor)
		if not _same(context) or not _terminal_current(): return false
		if not Protocol.bounded(loaded,65536,8192,18) or not loaded is Dictionary:
			valid = false
			captures[anchor] = "unsupported"
			continue
		captures[anchor] = Canonical.digest(loaded)
		if loaded.get("ok") != true:
			valid = false
			continue
		if loaded.get("found") != true: continue
		var definition := _definition(reference)
		var value: Variant = loaded.get("value")
		if definition.is_empty() or not Campaign.saved_state_valid(value,anchor,_owner,definition):
			valid = false
			continue
		if value.view.is_empty(): continue
		for entry: Dictionary in value.view.chapters:
			if entry.room_id != null: _classify_add(found,entry.room_id,{"kind":"child","reference":reference.duplicate(true)})
	if not _same(context) or not _terminal_current() or signature != _terminal_signature(): return false
	_terminal_scan = {"valid":valid,"found":found}
	_terminal_scan_signature = signature
	_terminal_scan_digest = Canonical.digest({"sources":captures,"classification":_terminal_scan})
	return valid

func terminal_room_status(anchor: String, room_id: String) -> String:
	# Pure cached classification. The caller owns the bounded fresh-pass fence.
	if not terminal_anchor_released(anchor): return "held"
	if room_id.is_empty(): return "unrelated"
	if not Protocol.id_valid(room_id) or _terminal_scan_signature != _terminal_signature() or not _terminal_scan.get("valid",false): return "held"
	return _terminal_cached_room_status(anchor,room_id)

func _terminal_cached_room_status(anchor: String, room_id: String) -> String:
	if room_id.is_empty(): return "unrelated"
	if not _terminal_scan.get("valid",false): return "held"
	var found: Dictionary = _terminal_scan.found
	var ordinary: bool = _online.standalone_room_proven(room_id)
	if found.has(room_id):
		var detail: Dictionary = found[room_id]
		if detail.get("kind") == "ambiguous" or ordinary: return "held"
		return "released" if detail.reference.campaign_room_id == anchor else "unrelated"
	return "unrelated" if ordinary else "held"

func auxiliary_target_current(binding: Dictionary) -> bool:
	# Called by retained targets, so never restore or parse journals here.
	if not _loaded or read_only or not _terminal_current(): return false
	var identity := _current_identity()
	if identity.is_empty() or identity.player_id != _owner or int(identity.epoch) != _epoch: return false
	if terminal_anchor_released(str(binding.get("room_id",""))): return false
	if binding.get("kind") == "ordinary": return true
	if binding.get("kind") != "campaign" or not _reference_valid(binding.get("reference")): return false
	return not terminal_anchor_released(binding.reference.campaign_room_id)

func terminal_recovery() -> Dictionary:
	return _terminal_recovery() if restore_owner() else {}

func _terminal_recovery() -> Dictionary:
	if not _terminal_current(): return {}
	var pending: Dictionary = _terminal.pending()
	if not pending.is_empty(): return {"campaign_room_id":pending.campaign_room_id,"phase":"pending"}
	if not _terminal_hint.is_empty(): return {"campaign_room_id":_terminal_hint,"phase":"available"}
	if not _terminal_retiring.is_empty(): return {"campaign_room_id":_terminal_retiring,"phase":"retiring"}
	var mapped := _mapped_terminal_anchor()
	if not mapped.is_empty(): return {"campaign_room_id":mapped,"phase":"retiring" if terminal_anchor_released(mapped) else "available"}
	return {}

func _mapped_terminal_anchor() -> String:
	var pending: Dictionary = _lobby.get("pending",{})
	if pending.is_empty() or _terminal_admission == null: return ""
	var mapped: String = TerminalAdmission.mapped_anchor(_terminal_admission.mapping_for(_admission_request(pending)),_owner)
	if not pending.accepted_campaign.is_empty() and pending.accepted_campaign.campaign_room_id != mapped: return ""
	return mapped

func _pending_terminal_anchor() -> String:
	var pending: Dictionary = _lobby.get("pending",{})
	if pending.is_empty(): return ""
	var mapped := _mapped_terminal_anchor()
	if not mapped.is_empty(): return mapped
	if not pending.accepted_campaign.is_empty(): return pending.accepted_campaign.campaign_room_id
	# This is the exact already-validated Join2 body. A Create's key alone is
	# never enough to correlate an unknown acceptance to a terminal anchor.
	if pending.path == "/v2/campaigns/join" and pending.body.schema_version == 2:
		return ("v2:"+str(pending.body.invite_code)).sha256_text().substr(0,22)
	return ""

func _discover_terminal_retirement() -> bool:
	var context := _context()
	var terminal: RefCounted = _terminal
	if not _terminal_current(): return false
	var receipts: Array = terminal.released_receipts()
	if not receipts.is_empty():
		refresh_terminal_classification()
		if not _same(context) or terminal != _terminal or not _terminal_current() or _terminal_scan_signature != _terminal_signature(): return false
	var retiring := ""
	var bound: String = str(_lobby.bound_campaign.get("campaign_room_id",""))
	var admission := _pending_terminal_anchor()
	var last_room: String = _online.last_room()
	var displayed := ""
	if _online.coordinator != null:
		var observed: Dictionary = _online.coordinator.observe_room_binding()
		displayed = str(observed.get("room_id",""))
	if not _same(context) or terminal != _terminal or not _terminal_current(): return false
	for receipt: Dictionary in receipts:
		var anchor: String = receipt.campaign_room_id
		if not _online.terminal_index_ready() or bound == anchor or admission == anchor or _terminal_cached_room_status(anchor,last_room) != "unrelated" or _terminal_cached_room_status(anchor,displayed) != "unrelated":
			retiring = anchor
			break
	if not _same(context) or terminal != _terminal or not _terminal_current(): return false
	_terminal_retiring = retiring
	return true

func _terminal_capabilities() -> Dictionary:
	# Cleanup only requires a valid control2/global envelope, not executability
	# of whichever finite definition fresh admission currently advertises.
	var value: Variant = _online.capabilities
	if not value is Dictionary or not value.get("campaign_definitions") is Array: return {"valid":false,"lobby_retry":false}
	return CampaignCapabilities.read(value,value.campaign_definitions)

func dispatch_terminal_request(transport: RefCounted, request: Dictionary) -> Dictionary:
	if transport != _terminal_context or not _terminal_current() or read_only or not _loaded: return _transport_hold("campaign_context_changed")
	if not _online.terminal_index_ready(): return _transport_hold("campaign_terminal_retirement_pending")
	if not Protocol.exact(request,["owner_player_id","identity_epoch","method","path","body"]) or request.owner_player_id != _owner or request.identity_epoch != _epoch or request.method != HTTPClient.METHOD_POST: return _transport_hold("campaign_context_changed")
	var pending: Dictionary = _terminal.pending()
	if pending.is_empty() or request.path != pending.path or not Canonical.same(request.body,pending.body): return _transport_hold("campaign_request_changed")
	if not _terminal_capabilities().get("lobby_retry",false): return _transport_hold("campaign_mutations_unavailable")
	var context := _context()
	var response: Dictionary = await _online.campaign_transport(request)
	if not _same(context) or transport != _terminal_context or not _terminal_current() or not Canonical.same(_terminal.pending(),pending): return _transport_hold("campaign_context_changed")
	if not _online.terminal_index_ready(): return _transport_hold("campaign_terminal_retirement_pending")
	return response

func reconcile_terminal() -> bool:
	if _busy or not restore_owner(): return false
	if not _prepare_terminal_write(): return false
	var recovery := _terminal_recovery()
	if recovery.is_empty(): return _error("campaign_terminal_unavailable")
	var anchor: String = recovery.campaign_room_id
	var context := _context()
	var transport: RefCounted = _terminal_context
	var terminal: RefCounted = _terminal
	_busy = true
	if recovery.phase != "retiring":
		if not _terminal_capabilities().get("lobby_retry",false):
			_busy = false
			return _error("campaign_mutations_unavailable")
		if not terminal.begin(anchor):
			if _same(context):
				_busy = false
				last_code = terminal.last_code
			return false
		if not await terminal.reconcile():
			if _same(context):
				_busy = false
				last_code = terminal.last_code
			return false
		if not _same(context) or transport != _terminal_context or not _terminal_current(): return _identity_changed(context)
		if _terminal_hint == anchor: _terminal_hint = ""
	_terminal_retiring = anchor
	_busy = false
	return _retire_terminal(anchor)

func _retire_terminal(anchor: String) -> bool:
	if not terminal_anchor_released(anchor): return _error("campaign_terminal_unavailable")
	if not _online.terminal_index_ready(): return _error("campaign_terminal_retirement_pending")
	if not _preserve_terminal_admission(anchor): return false
	# Invalidate matching control callbacks first. Auxiliary callbacks consult
	# the permanent receipt directly, leaving unrelated historical targets live.
	if _lobby.bound_campaign.get("campaign_room_id") == anchor and (_campaign != null or _bridge != null):
		_generation += 1
		_drop_bound()
	var context := _context()
	var transport: RefCounted = _terminal_context
	if not _online.retire_campaign_selection(anchor): return _error("campaign_terminal_retirement_pending")
	if not _same(context) or transport != _terminal_context or not _terminal_current(): return _identity_changed(context)
	var next := _lobby.duplicate(true)
	if next.bound_campaign.get("campaign_room_id") == anchor: next.bound_campaign = {}
	if _pending_terminal_anchor() == anchor: next.pending = {}
	if not Canonical.same(next,_lobby):
		# Unlike the ordinary writer, this path additionally pins terminal API
		# lifetime through synchronous Store callbacks before adopting saved data.
		var saved: Variant = _store.save_scope(_scope(),next.duplicate(true))
		if not _same(context) or transport != _terminal_context or not _terminal_current(): return _identity_changed(context)
		if not saved is Dictionary or saved.get("ok") != true: return _error("campaign_terminal_retirement_pending")
		_lobby = next
	_terminal_retiring = ""
	if not _discover_terminal_retirement(): return _identity_changed(context)
	last_code = ""
	return true

func _admission_request(pending: Dictionary) -> Dictionary:
	return {"path":pending.path,"body":pending.body.duplicate(true),"request_hash":pending.request_hash}

func _observe_terminal_pending() -> Dictionary:
	# Pure observer for the exact evidence writer, including after its save.
	return _lobby.get("pending",{}).duplicate(true) if _loaded and not read_only and _terminal_current() else {}

func _preserve_terminal_admission(anchor: String) -> bool:
	if _pending_terminal_anchor() != anchor: return true
	if not _online.terminal_index_ready(): return _error("campaign_terminal_retirement_pending")
	var context := _context()
	var pending: Dictionary = _lobby.pending.duplicate(true)
	var request := _admission_request(pending)
	var mapper: RefCounted = _terminal_admission
	var existing: Dictionary = mapper.mapping_for(request)
	if not existing.is_empty():
		return true if TerminalAdmission.mapped_anchor(existing,_owner) == anchor else _error("campaign_terminal_admission_conflict")
	var cleanup: Dictionary = _terminal.terminal_receipt(anchor)
	var witness := {}
	if not pending.accepted_campaign.is_empty():
		witness = {"kind":"accepted_reference","reference":pending.accepted_campaign.duplicate(true),"cleanup":cleanup}
	elif pending.path == "/v2/campaigns/join" and pending.body.schema_version == 2:
		witness = {"kind":"join_invitation","cleanup":cleanup}
	else: return _error("campaign_terminal_admission_unavailable")
	var saved: bool = mapper.record_mapping(request,witness,_observe_terminal_pending)
	if not _same(context) or mapper != _terminal_admission or not _terminal_current(): return _identity_changed(context)
	return true if saved else _error(mapper.last_code)

func _prepare_terminal_write() -> bool:
	# Explicit local retry may re-read a previously unavailable index. Its
	# readiness is separate from the lifetime used to read permanent evidence.
	var context := _context()
	var transport: RefCounted = _terminal_context
	var lifetime: Dictionary = _online.terminal_lifetime(self)
	if not _same(context) or transport != _terminal_context or not _terminal_current(): return _identity_changed(context)
	return true if not lifetime.is_empty() and _online.terminal_index_ready() else _error("campaign_terminal_retirement_pending")
