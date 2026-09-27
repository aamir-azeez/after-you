extends RefCounted
## An unenabled composition seam: read a child room in isolation, then adopt it
## only after CampaignSession has durably selected that exact publication.
## The future owner must restore its durable campaign anchor before allowing
## any ordinary/campaign navigation. This object does not discover anchors.
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Campaign = preload("res://services/campaign_session.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")

var last_code := ""
var _definition: Dictionary = {}
var _transport: Callable
var _load: Callable
var _save: Callable
var _identity: Callable
var _source_lease: Callable
var _observe_source_lease: Callable
var _adopt: Callable
var _leave_ready: Callable
var _accepted_pair_cache: Callable
var _campaign: WeakRef
var _generation := 0
var _busy := false
var _candidate: RefCounted
var _candidate_context: Dictionary = {}

func _init(definition: Dictionary, transport: Callable, load_store: Callable, save_store: Callable,
		identity: Callable, source_lease: Callable, adopt: Callable, leave_ready: Callable,
		accepted_pair_cache: Callable = Callable(), observe_source_lease: Callable = Callable()) -> void:
	# identity, leave_ready and observe_source_lease are synchronous, pure
	# observers. In particular leave_ready must not restore/save owner state.
	if Protocol.definition_valid(definition): _definition = definition.duplicate(true)
	_transport = transport
	_load = load_store
	_save = save_store
	_identity = identity
	_source_lease = source_lease
	_observe_source_lease = observe_source_lease
	_adopt = adopt
	_leave_ready = leave_ready
	_accepted_pair_cache = accepted_pair_cache

func bind_campaign(campaign: RefCounted) -> bool:
	invalidate()
	_campaign = null
	if campaign == null or campaign.get_script() != Campaign or _definition.is_empty(): return _error("campaign_unavailable")
	_campaign = weakref(campaign)
	return true

func invalidate() -> void:
	_generation += 1
	_busy = false
	_candidate = null
	_candidate_context = {}

func busy() -> bool:
	return _busy

func selection_ready() -> bool:
	return not _busy and not _definition.is_empty() and not _lease().is_empty()

func validate_target(room_id: String, pin: Dictionary, owner: String, epoch: int) -> Dictionary:
	# A second probe retires even a successful previous candidate. A running
	# request may finish, but its generation can no longer publish a candidate.
	var was_busy := _busy
	invalidate()
	if was_busy: return _failed("request_busy")
	var generation := _generation
	var publication := _publication(owner, epoch)
	var lease := _lease()
	if lease.is_empty() or publication.is_empty() or not _target_matches(publication, room_id, pin): return _failed("selection_unavailable")
	var target := Coordinator.new(_transport, _load, _save, _identity)
	target.accepted_pair_cache = _accepted_pair_cache
	# This preference affects legacy First Steps reads only. Exact admission
	# still belongs to the registered native coordinator and pin comparison.
	target.supported_simulation_versions = {Registry.resolve(pin):int(pin.simulation_version)}
	if not target.bind_room(room_id) or target.read_only: return _failed("target_cache_unavailable")
	_busy = true
	var verified: bool = await target.refresh()
	if generation != _generation: return {"ok":false,"code":"selection_changed"}
	_busy = false
	if not verified or target.read_only: return _failed("target_unverified")
	var current := _publication(owner, epoch)
	if current.is_empty() or not Canonical.same(current, publication) or not Canonical.same(_lease(), lease): return _failed("selection_changed")
	if not _room_matches(target.snapshot(), publication, room_id, pin): return _failed("target_mismatch")
	_candidate = target
	_candidate_context = {"generation":generation,"owner":owner,"epoch":epoch,"room_id":room_id,
		"pin":pin.duplicate(true),"publication":Canonical.digest(publication),"lease":lease.duplicate(true)}
	last_code = ""
	return {"ok":true,"room_id":room_id}

func adoption_ready() -> bool:
	# Usability preflight only; the authoritative adoption repeats its guards.
	return _adoption_error(true).is_empty()

func _adoption_error(observe_only: bool) -> String:
	if _busy or _candidate == null or _candidate_context.is_empty(): return "target_not_verified"
	var context := _candidate_context
	var campaign := _campaign_ref()
	var publication := _publication(context.owner, context.epoch)
	if context.generation != _generation or campaign == null or campaign.read_only or campaign.busy() or not campaign.pending().is_empty() or campaign.selected_room() != context.room_id:
		return "selection_not_saved"
	if publication.is_empty() or Canonical.digest(publication) != context.publication or not _target_matches(publication, context.room_id, context.pin): return "selection_changed"
	if _candidate.read_only or _candidate.busy(): return "target_unverified"
	var room: Dictionary
	if observe_only:
		var observed: Dictionary = _candidate.observe_campaign_state()
		if observed.is_empty(): return "target_unverified"
		room = observed.snapshot
	else: room = _candidate.snapshot()
	if not _room_matches(room, publication, context.room_id, context.pin): return "target_unverified"
	var lease: Dictionary
	if observe_only:
		if not _leave_ready.is_valid() or _leave_ready.call() != true or not _observe_source_lease.is_valid(): return "adoption_unavailable"
		var observed: Variant = _observe_source_lease.call()
		if not observed is Dictionary: return "adoption_unavailable"
		lease = observed
	else: lease = _lease()
	if not Canonical.same(lease,context.lease) or not _adopt.is_valid(): return "adoption_unavailable"
	return ""

func adopt_selected() -> bool:
	var code := _adoption_error(false)
	if not code.is_empty(): return _error(code)
	var context := _candidate_context
	# No await from the final owner/source checks through index save and swap.
	# A target's own pending request is deliberately retained for recovery UI.
	if _adopt.call(_candidate, context.lease) != true: return _error("adoption_unavailable")
	invalidate()
	last_code = ""
	return true

func reopen_selected() -> bool:
	# Recovery after an accepted selection but failed local index save. This is
	# GET + native verification + local adoption; it never sends Continue.
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	if not identity is Dictionary or identity.get("ready") != true: return _error("identity_unavailable")
	var publication := _publication(str(identity.get("player_id", "")), int(identity.get("epoch", -1)))
	var campaign := _campaign_ref()
	if publication.is_empty() or campaign == null or campaign.read_only or not campaign.pending().is_empty(): return _error("selection_unavailable")
	var entry: Dictionary = publication.chapters[int(publication.current_index)]
	if campaign.selected_room() != entry.room_id: return _error("selection_not_saved")
	var checked := await validate_target(entry.room_id, entry.chapter, identity.player_id, int(identity.epoch))
	return checked.get("ok", false) and adopt_selected()

func continuation_source() -> RefCounted:
	# Explicit recovery probes a completed source without making it playable.
	var was_busy := _busy
	invalidate()
	if was_busy:
		_error("request_busy")
		return null
	var generation := _generation
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	if not identity is Dictionary or identity.get("ready") != true:
		_error("identity_unavailable")
		return null
	var publication := _publication(str(identity.get("player_id", "")), int(identity.get("epoch", -1)), true)
	var lease := _lease()
	if publication.is_empty() or publication.state != "continuing" or publication.transition == null or lease.is_empty():
		_error("continuation_unavailable")
		return null
	var entry: Dictionary = publication.chapters[int(publication.current_index)]
	var origin: Dictionary = publication.transition.origin.source
	var source := Coordinator.new(_transport, _load, _save, _identity)
	source.accepted_pair_cache = _accepted_pair_cache
	source.supported_simulation_versions = {Registry.resolve(entry.chapter):int(entry.chapter.simulation_version)}
	if not source.bind_room(entry.room_id) or source.read_only:
		_error("source_cache_unavailable")
		return null
	_busy = true
	var verified: bool = await source.refresh()
	if generation != _generation:
		_error("selection_changed")
		return null
	_busy = false
	var current := _publication(identity.player_id, int(identity.epoch), true)
	if not verified or source.read_only or not source.chapter_complete() or not source.pending().is_empty():
		_error("source_unverified")
		return null
	if current.is_empty() or not Canonical.same(current,publication) or not Canonical.same(_lease(),lease):
		_error("selection_changed")
		return null
	var room := source.snapshot()
	if not _room_matches(room,publication,entry.room_id,entry.chapter) or room.get("active_role") != "complete" or room.get("room_id") != origin.room_id or room.get("revision") != origin.revision or room.get("branch") != origin.branch or room.get("checkpoint",{}).get("checkpoint_hash") != origin.checkpoint_hash:
		_error("source_mismatch")
		return null
	last_code = ""
	return source

func _lease() -> Dictionary:
	# The owner knows about unsaved scene input and photo capture/transfer. An
	# omitted predicate fails closed; this layer cannot infer those UI states.
	if not _leave_ready.is_valid() or _leave_ready.call() != true or not _source_lease.is_valid(): return {}
	var value: Variant = _source_lease.call()
	return value.duplicate(true) if value is Dictionary else {}

func _publication(owner: String, epoch: int, continuing_source: bool = false) -> Dictionary:
	var identity: Variant = _identity.call() if _identity.is_valid() else null
	if not identity is Dictionary or identity.get("ready") != true or identity.get("player_id") != owner or identity.get("epoch") != epoch: return {}
	var campaign := _campaign_ref()
	if campaign == null or campaign.read_only: return {}
	var value: Dictionary = campaign.view()
	if not Protocol.view_valid(value, _definition, owner) or value.activation != null: return {}
	if value.state not in ["waiting", "active", "complete"] and not (continuing_source and value.state == "continuing"): return {}
	return value

func _campaign_ref() -> RefCounted:
	return _campaign.get_ref() if _campaign != null else null

func _target_matches(publication: Dictionary, room_id: String, pin: Dictionary) -> bool:
	var entry: Dictionary = publication.chapters[int(publication.current_index)]
	return entry.room_id == room_id and Canonical.same(entry.chapter, pin)

func _room_matches(room: Dictionary, publication: Dictionary, room_id: String, pin: Dictionary) -> bool:
	if room.get("room_id") != room_id or room.get("host_id") != publication.host_id or room.get("guest_id") != publication.guest_id or room.get("player_slot") != publication.player_slot: return false
	for field: String in ["level_id", "level_version", "definition_hash"]:
		if room.get(field) != pin[field]: return false
	return room.get("simulation_version", Registry.definition(Registry.resolve(pin)).get("simulation_version")) == pin.simulation_version

func _error(code: String) -> bool:
	last_code = code
	return false

func _failed(code: String) -> Dictionary:
	_error(code)
	return {"ok":false,"code":code}
