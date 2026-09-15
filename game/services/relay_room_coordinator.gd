class_name RelayRoomCoordinator
extends RefCounted
## Bundled two-stage RoomV2 chapters only; it never reads the solo journey or stores credentials.
## Inject synchronous identity()->{ready,player_id,epoch}, load(scope)->
## {ok,found,value?,error?}, save(scope,value)->{ok,error?}; save must be atomic.
## Async transport(request)->RoomsApi-shaped response. Request has method/path/
## body/owner_player_id/identity_epoch. Its adapter must check that owner+epoch
## before dispatch and capture that identity's headers, never use another owner.
## The caller must invalidate_identity() before recovery/deletion/account change.

const Registry = preload("res://services/chapter_registry.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const MAX_BYTES := 3145728
const MAX_HELD := 4
const STATE_KEYS := ["schema_version", "api_version", "owner_player_id", "room_id", "snapshot", "draft", "held_drafts", "pending", "last_receipt", "auth_required"]
const SNAPSHOT_KEYS := ["schema_version", "room_id", "revision", "branch", "stage_index", "level_id", "level_version", "definition_hash", "host_id", "guest_id", "checkpoint", "a_turn_id", "completed_pair_ids", "invite_expires_at", "created_at", "updated_at", "api_version", "active_role", "first_player_id", "active_player_id", "player_slot", "stage_id", "recording_a", "validation"]
const RECEIPT_KEYS := ["schema_version", "room_id", "idempotency_key", "request_hash", "operation", "accepted_revision", "branch", "stage_index", "stage_id", "turn_id", "recording_hash", "pair_id", "checkpoint_hash"]

var last_error := ""
var last_code := ""
var read_only := false
var _transport: Callable
var _load: Callable
var _save: Callable
var _identity: Callable
var _keys: Callable
var _chapter_key := ""
var _level: Dictionary = {}
var _simulation: Script
var _state: Dictionary = {}
var _owner := ""
var _epoch := -1
var _room := ""
var _scope := ""
var _generation := 0
var _serial := 0
var _busy := 0
var _live_simulation: WeakRef
var _live_context: Dictionary = {}
var _draft_replay_verified := true
var _remote_hold := false
var _last_refresh_result: Dictionary = {}


func _init(transport: Callable, load_store: Callable, save_store: Callable, identity_owner: Callable, key_factory: Callable = Callable()) -> void:
	_transport = transport
	_load = load_store
	_save = save_store
	_identity = identity_owner
	_keys = key_factory


func invalidate_identity() -> void:
	_clear_chapter()
	_retire_live()
	_last_refresh_result = {}
	_generation += 1
	_busy = 0
	_state = {}
	_owner = ""
	_epoch = -1
	_room = ""
	_scope = ""
	read_only = false
	_remote_hold = false
	_error("identity_changed", "Finish loading or recovering your identity before opening the room.")


func bind_room(room_id: String) -> bool:
	var identity := _current_identity()
	if identity.is_empty() or not _token(room_id, 22):
		return _error("identity_unavailable", "A ready identity and valid room are required.")
	if _owner != "" and (identity.player_id != _owner or int(identity.epoch) != _epoch):
		invalidate_identity()
	if not _state.is_empty() and not _state.pending.is_empty() and room_id != _room:
		return _error("pending_operation", "Check the saved submission before switching rooms.")
	if _busy != 0:
		return _error("request_busy", "Wait for the current room request.")
	_generation += 1
	_owner = identity.player_id
	_last_refresh_result = {}
	_epoch = int(identity.epoch)
	_room = room_id
	_scope = "relay-room-v2:" + _owner + ":" + _room
	_clear_chapter()
	_state = _empty_state()
	_retire_live()
	_draft_replay_verified = true
	read_only = false
	_remote_hold = false
	var loaded: Variant = _load.call(_scope)
	if not loaded is Dictionary or not loaded.get("ok", false):
		return _hold("storage_unavailable", "This room's local save could not be read. It has not been replaced.")
	if loaded.get("found", false):
		var value: Variant = loaded.get("value")
		if not _valid_state(value):
			return _hold("invalid_saved_room", "This room save is unsupported or cannot be verified. It has been kept unchanged.")
		_state = value.duplicate(true)
		_sync_chapter()
	_clear_error()
	return true


func chapter_key() -> String:
	return _chapter_key if _guard() else ""

func _clear_chapter() -> void:
	_chapter_key = ""
	_level = {}
	_simulation = null

func _sync_chapter() -> void:
	# Only called after full loaded-state validation or an accepted persisted
	# snapshot. Candidate verifiers use local descriptors and never mutate this.
	_chapter_key = Registry.resolve(_state.get("snapshot"))
	_level = Registry.definition(_chapter_key)
	_simulation = Registry.simulation_script(_chapter_key)

func busy() -> bool:
	return _busy != 0


func snapshot() -> Dictionary:
	return _state.snapshot.duplicate(true) if _guard() and not _state.auth_required else {}


func pending() -> Dictionary:
	return _state.pending.duplicate(true) if _guard() else {}


func last_receipt() -> Dictionary:
	# Optional post-turn features can identify the accepted operation without
	# reaching into mutable gameplay storage or treating a draft as accepted.
	return _state.last_receipt.duplicate(true) if _guard() and not _state.auth_required else {}


func last_refresh_result() -> Dictionary:
	# Transport scheduling metadata only; never retain response bodies or secrets.
	return _last_refresh_result.duplicate() if _guard() else {}


func held_drafts() -> Array:
	return _state.held_drafts.duplicate(true) if _guard() else []


func checkpoint() -> Dictionary:
	return snapshot().get("checkpoint", {}).duplicate(true)


func role() -> String:
	return str(snapshot().get("active_role", ""))


func stage_id() -> String:
	return str(snapshot().get("stage_id", ""))


func prior_recording() -> Dictionary:
	var first: Variant = snapshot().get("recording_a")
	return first.duplicate(true) if first is Dictionary else {}


func chapter_complete() -> bool:
	return role() == "complete"


func my_turn() -> bool:
	var room := snapshot()
	return not _remote_hold and not room.is_empty() and room.active_player_id == _owner and _state.pending.is_empty()


func draft() -> Dictionary:
	if not _guard() or _state.auth_required or _state.draft.is_empty() or _state.snapshot.is_empty():
		return {}
	if not _verify_saved_draft():
		return {}
	return _state.draft.recording.duplicate(true) if _same_context(_state.draft.origin, _state.snapshot) else {}


func save_draft(recording: Dictionary) -> bool:
	if not my_turn() or read_only:
		return _error("draft_unavailable", "Refresh your turn or reconcile its saved submission first.")
	if not recording.is_empty() and not _valid_recording(recording, _state.snapshot):
		return _error("invalid_recording", "The rehearsal does not match this verified room context.")
	var next := _state.duplicate(true)
	next.draft = {} if recording.is_empty() else {"origin": _state.snapshot.duplicate(true), "recording": recording.duplicate(true)}
	var saved := _persist(next)
	if saved:
		_retire_live()
		_draft_replay_verified = true
	return saved


func create_live_simulation() -> RefCounted:
	# Only this producer may skip repeated ancestor replay during autosave.
	# Recovery, another room, a replaced context or reset retires the instance.
	if not my_turn() or read_only or _busy != 0:
		_error("rehearsal_unavailable", "Refresh your own turn before starting a rehearsal.")
		return null
	var room: Dictionary = _state.snapshot
	var prior: Dictionary = room.recording_a if room.recording_a is Dictionary else {}
	var simulation: RefCounted = _simulation.new()
	if not simulation.reset(_level, room.stage_id, room.checkpoint, prior, room.active_role):
		_error("invalid_rehearsal", "This room's rehearsal could not be replay-verified.")
		return null
	_live_simulation = weakref(simulation)
	_live_context = {"generation": _generation, "owner": _owner, "epoch": _epoch, "room": _room,
		"origin": room.duplicate(true), "level_ref": simulation.level,
		"checkpoint_ref": simulation.get("_checkpoint"), "prior_ref": simulation.get("_prior")}
	_clear_error()
	return simulation


func save_live_draft(simulation: RefCounted) -> bool:
	# The exact internal engine exports draft-only state. Loading/resuming and
	# committing still replay it. Caller-supplied dictionaries use save_draft.
	if not my_turn() or read_only or _busy != 0 or simulation == null or _live_simulation == null or _live_simulation.get_ref() != simulation or simulation.get_script() != _simulation or _live_context.is_empty():
		return _error("unregistered_rehearsal", "Only this room's active rehearsal can use live autosave.")
	if _live_context.generation != _generation or _live_context.owner != _owner or _live_context.epoch != _epoch or _live_context.room != _room or not _same_context(_live_context.origin, _state.snapshot):
		return _error("stale_rehearsal", "This rehearsal belongs to a different identity, room or checkpoint.")
	# Reference equality detects resetting the same instance, even back to
	# identical values; full comparisons also catch mutations keeping old hashes.
	if not is_same(simulation.get("level"), _live_context.level_ref) or not is_same(simulation.get("_checkpoint"), _live_context.checkpoint_ref) or not is_same(simulation.get("_prior"), _live_context.prior_ref):
		return _error("reset_rehearsal", "Start a new rehearsal after resetting its engine.")
	var room: Dictionary = _state.snapshot
	var prior: Dictionary = room.recording_a if room.recording_a is Dictionary else {}
	if not str(simulation.get("error")).is_empty() or simulation.get("role") != room.active_role or not Canonical.same(simulation.get("level"), _level) or not Canonical.same(simulation.get("stage"), _simulation.stage_by_id(_level, room.stage_id)) or not Canonical.same(simulation.get("_checkpoint"), room.checkpoint) or not Canonical.same(simulation.get("_prior"), prior):
		return _error("changed_rehearsal", "The active rehearsal's controls or source changed.")
	var recording: Dictionary = simulation.export_recording()
	if not _bounded(recording) or not _simulation.recording_error(_level, recording, room.checkpoint).is_empty() or recording.get("role") != room.active_role or recording.get("source_recording_hash") != prior.get("recording_hash", ""):
		return _error("invalid_rehearsal", "The live recording no longer matches its verified source.")
	var next := _state.duplicate(true)
	next.draft = {"origin": room.duplicate(true), "recording": recording.duplicate(true)}
	var saved := _persist(next)
	if saved:
		_draft_replay_verified = false
	return saved


func refresh() -> bool:
	_last_refresh_result = {}
	var response := await _request(HTTPClient.METHOD_GET, _room_path())
	if response.get("ignored", false):
		return false
	var status := int(response.get("status", 0))
	_last_refresh_result = {"status": status, "retry_after_ms": clampi(int(response.get("retry_after_ms", 0)), 0, 86400000), "terminal": status in [401, 403, 404, 410]}
	if not response.get("ok", false):
		return _network_error(response)
	return _accept_snapshot(response.get("data"))


func commit(recording: Dictionary) -> bool:
	if not my_turn() or read_only or _busy != 0:
		return _error("commit_unavailable", "It is not an available turn, or a saved submission still needs checking.")
	var checked := _verify_recording(recording, _state.snapshot)
	if not checked.valid or not checked.get("snapshot", {}).get("can_commit", false):
		return _error("incomplete_recording", "This contribution has not completed its verified goal.")
	var body := {"base_revision": _state.snapshot.revision, "idempotency_key": _new_key(), "branch": _state.snapshot.branch, "recording": recording.duplicate(true)}
	if recording.role == "b":
		var derived: Dictionary = _simulation.derive_checkpoint(_level, _state.snapshot.checkpoint, _state.snapshot.recording_a, recording)
		if not derived.valid:
			return _error("invalid_checkpoint", "The completed pair could not be verified.")
		body["checkpoint"] = derived.checkpoint
	if not _prepare_pending("turns", body):
		return false
	return await _send_pending()


func fork(stage_index: int) -> bool:
	if not _guard() or read_only or _remote_hold or _state.auth_required or _state.snapshot.is_empty() or not _state.pending.is_empty() or _busy != 0:
		return _error("fork_unavailable", "Refresh the room and check any saved submission before restarting a stage.")
	var room: Dictionary = _state.snapshot
	if stage_index < 0 or stage_index > 1 or stage_index > int(room.stage_index) or (stage_index == int(room.stage_index) and room.a_turn_id == null):
		return _error("nothing_to_fork", "There is no saved contribution to restart at that checkpoint.")
	var body := {"base_revision": room.revision, "idempotency_key": _new_key(), "branch": room.branch, "stage_index": stage_index}
	if not _prepare_pending("fork", body):
		return false
	return await _send_pending()


func reconcile() -> bool:
	if not _guard() or read_only or _state.pending.is_empty() or _busy != 0:
		return _error("pending_unavailable", "No saved submission can be checked right now.")
	var response := await _request(HTTPClient.METHOD_GET, _room_path() + "/operations/" + str(_state.pending.body.idempotency_key))
	if response.get("ignored", false):
		return false
	if response.get("ok", false):
		return _accept_receipt(response.get("data"))
	if int(response.get("status", 0)) == 404 and response.get("code") == "operation_not_found" and not _state.pending.held:
		return await _send_pending()
	return _network_error(response)


func archive_held_submission() -> bool:
	if not _guard() or read_only or _state.auth_required or _busy != 0 or _state.pending.is_empty() or not _state.pending.held:
		return _error("pending_unresolved", "Only a definitively held submission can be archived. Check uncertain receipts first.")
	var next := _state.duplicate(true)
	if next.pending.operation == "turns":
		if next.held_drafts.size() >= MAX_HELD:
			return _error("local_history_full", "Your held rehearsal collection is full. No recording was removed.")
		next.held_drafts.append({"origin": next.pending.origin.duplicate(true), "recording": next.pending.body.recording.duplicate(true)})
	next.pending = {}
	next.draft = {}
	return _persist(next)


func fetch_pair(pair_id: String) -> Dictionary:
	if not _pattern(pair_id, "^p[0-9]{1,2}-[01]$"):
		_error("invalid_pair", "That memory identifier is invalid.")
		return {}
	var response := await _request(HTTPClient.METHOD_GET, _room_path() + "/pairs/" + pair_id)
	if response.get("ignored", false):
		return {}
	if not response.get("ok", false):
		_network_error(response)
		return {}
	var pair: Variant = response.get("data")
	if not _bounded(pair) or not pair is Dictionary or not _exact(pair, ["pair_id", "branch", "stage_index", "a", "b", "checkpoint"]) or pair.pair_id != pair_id or not _range(pair.branch, 0, 31) or not _range(pair.stage_index, 0, 1) or not pair.checkpoint is Dictionary:
		_error("invalid_pair", "The saved memory has an unsupported format.")
		return {}
	var proof: Variant = pair.checkpoint.get("proof")
	if not proof is Dictionary or Registry.previous_checkpoint(_chapter_key, pair.checkpoint).is_empty() or not pair.a is Dictionary or not pair.b is Dictionary:
		_error("invalid_pair", "The saved memory is missing its source proof.")
		return {}
	var derived: Dictionary = _simulation.derive_checkpoint(_level, Registry.previous_checkpoint(_chapter_key, pair.checkpoint), pair.a, pair.b)
	if not derived.valid or not Canonical.same(derived.get("checkpoint", {}), pair.checkpoint) or pair.stage_index != int(pair.checkpoint.stage_index) - 1 or pair_id != "p%d-%d" % [int(pair.branch), int(pair.stage_index)]:
		_error("invalid_pair", "The memory failed native replay verification.")
		return {}
	_clear_error()
	return pair.duplicate(true)


func _prepare_pending(operation: String, body: Dictionary) -> bool:
	var next := _state.duplicate(true)
	next.pending = {"operation": operation, "body": body.duplicate(true), "request_hash": _request_hash(operation, body), "origin": _state.snapshot.duplicate(true), "held": false, "error_code": ""}
	if not _valid_pending(next.pending):
		return _error("invalid_pending", "The submission could not be safely prepared.")
	var saved := _persist(next)
	if saved:
		_retire_live()
	return saved


func _send_pending() -> bool:
	if not _guard() or _state.pending.is_empty() or _state.pending.held:
		return false
	var response := await _request(HTTPClient.METHOD_POST, _room_path() + "/" + str(_state.pending.operation), _state.pending.body)
	if response.get("ignored", false):
		return false
	if not response.get("ok", false):
		return _network_error(response, true)
	return _accept_receipt(response.get("data"))


func _accept_receipt(value: Variant) -> bool:
	if not _guard() or _state.pending.is_empty() or not _bounded(value) or not value is Dictionary or not _exact(value, ["receipt", "room"]) or not _valid_receipt(value.get("receipt"), _state.pending):
		return _error("receipt_mismatch", "The reply did not identify this exact saved submission. Its request has been kept.")
	if not _valid_snapshot(value.room):
		_remote_hold = true
		return _error("invalid_snapshot", "The returned room failed native verification. The saved submission remains pending.")
	if int(value.room.revision) < int(value.receipt.accepted_revision):
		return _error("receipt_mismatch", "The returned room predates the accepted contribution.")
	var next := _state.duplicate(true)
	# A later response can confirm the old receipt without rolling back a newer
	# already-verified snapshot obtained by a previous refresh.
	if next.snapshot.is_empty() or int(value.room.revision) >= int(next.snapshot.revision):
		if not next.snapshot.is_empty() and int(value.room.revision) == int(next.snapshot.revision) and not Canonical.same(value.room, next.snapshot):
			return _error("snapshot_conflict", "Two different states used the same room revision.")
		next.snapshot = value.room.duplicate(true)
	next.last_receipt = value.receipt.duplicate(true)
	next.pending = {}
	next.draft = {}
	next.auth_required = false
	var saved := _persist(next)
	if saved:
		_retire_live()
		_draft_replay_verified = true
		_remote_hold = false
	return saved


func _accept_snapshot(value: Variant) -> bool:
	if not _guard() or not _valid_snapshot(value):
		_remote_hold = true
		return _error("invalid_snapshot", "The room has an unsupported format or failed native replay verification.")
	if not _state.snapshot.is_empty():
		if int(value.revision) < int(_state.snapshot.revision) or int(value.branch) < int(_state.snapshot.branch):
			return _error("stale_snapshot", "An older room response was ignored.")
		if int(value.revision) == int(_state.snapshot.revision) and not Canonical.same(value, _state.snapshot):
			return _error("snapshot_conflict", "Two different states used the same room revision.")
		# An identical GET confirms availability without producing another save
		# generation. It still passed full native verification and revision checks.
		# Auth recovery must persist; a receipt must separately resolve pending.
		if Canonical.same(value, _state.snapshot) and not _state.auth_required:
			_remote_hold = false
			_clear_error()
			return true
	var next := _state.duplicate(true)
	if not next.draft.is_empty() and not _same_context(next.draft.origin, value):
		if not _verify_saved_draft():
			return false
		if next.held_drafts.size() >= MAX_HELD:
			return _error("local_history_full", "Your old rehearsal is kept; the local held collection is full.")
		next.held_drafts.append(next.draft.duplicate(true))
		next.draft = {}
	next.snapshot = value.duplicate(true)
	next.auth_required = false
	var saved := _persist(next)
	if saved:
		_remote_hold = false
	if saved and not _live_context.is_empty() and not _same_context(_live_context.origin, next.snapshot):
		_retire_live()
	return saved


func _request(method: int, path: String, body: Dictionary = {}) -> Dictionary:
	if not _guard() or read_only or _busy != 0:
		return {"ignored": true}
	_serial += 1
	var request_id := _serial
	var generation := _generation
	var owner := _owner
	var epoch := _epoch
	_busy = request_id
	var response: Variant = await _transport.call({"method": method, "path": path, "body": body.duplicate(true), "owner_player_id": owner, "identity_epoch": epoch})
	if _busy == request_id:
		_busy = 0
	var identity := _current_identity()
	if generation != _generation or owner != _owner or epoch != _epoch:
		return {"ignored": true}
	if identity.is_empty() or identity.player_id != owner or int(identity.epoch) != epoch:
		invalidate_identity()
		return {"ignored": true}
	return response if response is Dictionary else {"ok": false, "status": 0, "code": "invalid_response"}


func _network_error(response: Dictionary, definitive_rejection: bool = false) -> bool:
	if not _guard():
		return false
	var status := int(response.get("status", 0))
	var code := str(response.get("code", "connection_interrupted"))
	if not _token(code, -1, 80):
		code = "connection_interrupted"
	var next := _state.duplicate(true)
	var changed := false
	if status == 401:
		_retire_live()
		next.auth_required = true
		changed = true
	# A failed lookup or revoked credential says nothing about whether an earlier
	# POST was accepted. Only a definitive mutation rejection permits archival.
	if definitive_rejection and status >= 400 and status < 500 and status not in [401, 408, 429] and not next.pending.is_empty():
		next.pending.held = true
		next.pending.error_code = code
		changed = true
	if changed and not _persist(next):
		return false
	var message := "The request did not finish. Your exact saved submission and rehearsal are kept."
	if status == 401:
		message = "Recover or reload your identity before checking this room again."
	elif code == "v2_mutations_disabled":
		message = "New chapter submissions are paused. Existing receipts can still be checked."
	elif status == 409:
		message = "The room changed or the request conflicts. Check its receipt before reviewing the held rehearsal."
	elif status in [404, 410]:
		message = "This room or receipt is unavailable. The local rehearsal has been kept."
	return _error(code, message)


func _persist(next: Dictionary) -> bool:
	if not _guard() or read_only or not _bounded(next, MAX_BYTES):
		return _error("storage_unavailable", "The local room state cannot be safely written.")
	var generation := _generation
	var result: Variant = _save.call(_scope, next.duplicate(true))
	if generation != _generation or not _guard():
		return false
	if not result is Dictionary or not result.get("ok", false):
		return _error("storage_write_failed", "The local save failed. Nothing pending was discarded.")
	_state = next.duplicate(true)
	_sync_chapter()
	_clear_error()
	return true


func _valid_state(value: Variant) -> bool:
	if not _bounded(value, MAX_BYTES) or not value is Dictionary or not _exact(value, STATE_KEYS) or value.schema_version != 1 or value.api_version != 2 or value.owner_player_id != _owner or value.room_id != _room or not value.auth_required is bool:
		return false
	if not value.snapshot is Dictionary or (not value.snapshot.is_empty() and not _valid_snapshot(value.snapshot)) or not value.pending is Dictionary or (not value.pending.is_empty() and not _valid_pending(value.pending)):
		return false
	var candidate_chapter := Registry.resolve(value.snapshot)
	for evidence: Variant in [value.draft, value.pending]:
		if evidence is Dictionary and not evidence.is_empty() and Registry.resolve(evidence.get("origin")) != candidate_chapter:
			return false
	if not _valid_draft(value.draft) or not value.held_drafts is Array or value.held_drafts.size() > MAX_HELD:
		return false
	for held: Variant in value.held_drafts:
		if not _valid_draft(held) or held.is_empty() or Registry.resolve(held.origin) != candidate_chapter:
			return false
	return value.last_receipt is Dictionary and (value.last_receipt.is_empty() or _exact(value.last_receipt, RECEIPT_KEYS))


func _valid_snapshot(value: Variant) -> bool:
	if not _bounded(value) or not value is Dictionary:
		return false
	var chapter := Registry.resolve(value)
	var level := Registry.definition(chapter)
	var engine := Registry.simulation_script(chapter)
	var keys := SNAPSHOT_KEYS.duplicate()
	if value.has("invite_code"):
		keys.append("invite_code")
	if not _exact(value, keys) or value.api_version != 2 or value.schema_version != 2 or chapter.is_empty() or (not _chapter_key.is_empty() and chapter != _chapter_key) or value.validation != "structural_client_replay_required" or value.room_id != _room:
		return false
	if not _token(value.host_id, 22) or (value.guest_id != null and (not _token(value.guest_id, 22) or value.guest_id == value.host_id)) or _owner not in [value.host_id, value.guest_id]:
		return false
	if not _range(value.revision, 0, 9007199254740991) or not _range(value.branch, 0, 31) or not _range(value.stage_index, 0, 2):
		return false
	var index := int(value.stage_index)
	if not value.checkpoint is Dictionary or not engine.verify_checkpoint(level, value.checkpoint).valid or value.checkpoint.stage_index != index:
		return false
	if not value.completed_pair_ids is Array or value.completed_pair_ids.size() != index or (index > 0 and value.guest_id == null):
		return false
	for offset in range(index):
		if not _pattern(value.completed_pair_ids[offset], "^p[0-9]{1,2}-%d$" % offset) or int(str(value.completed_pair_ids[offset]).substr(1).get_slice("-", 0)) > int(value.branch):
			return false
	for name: String in ["created_at", "updated_at", "invite_expires_at"]:
		if not value[name] is String or value[name].length() < 10 or value[name].length() > 40:
			return false
	if value.player_slot != ("p0" if value.host_id == _owner else "p1") or (value.host_id == _owner and (not value.has("invite_code") or not _pattern(value.invite_code, "^[A-F0-9]{20}$"))) or (value.host_id != _owner and value.has("invite_code")):
		return false
	if index == 2:
		return value.stage_id == "" and value.active_role == "complete" and value.first_player_id == null and value.active_player_id == null and value.a_turn_id == null and value.recording_a == null
	var stage: Dictionary = level.stages[index]
	var first: Variant = value.host_id if stage.first_player_slot == "p0" else value.guest_id
	var second: Variant = value.guest_id if stage.first_player_slot == "p0" else value.host_id
	if value.stage_id != stage.id or value.first_player_id != first:
		return false
	if value.recording_a == null:
		return value.a_turn_id == null and value.active_role == "a" and value.active_player_id == first
	if not value.recording_a is Dictionary or value.a_turn_id != "t%d-%d-a" % [int(value.branch), index] or value.active_role != "b" or value.active_player_id != second:
		return false
	var verified: Dictionary = engine.verify_recording(level, value.recording_a, value.checkpoint)
	return value.recording_a.get("role") == "a" and verified.valid and verified.get("snapshot", {}).get("can_commit", false)


func _valid_draft(value: Variant) -> bool:
	return value is Dictionary and (value.is_empty() or (_exact(value, ["origin", "recording"]) and _valid_snapshot(value.origin) and _valid_recording(value.recording, value.origin)))


func _verify_recording(recording: Variant, origin: Dictionary) -> Dictionary:
	if not _bounded(recording) or not recording is Dictionary or origin.is_empty() or origin.active_player_id != _owner or recording.get("role") != origin.active_role or origin.active_role == "complete":
		return {"valid": false}
	var chapter := Registry.resolve(origin)
	if chapter.is_empty(): return {"valid": false}
	var engine := Registry.simulation_script(chapter)
	return engine.verify_recording(Registry.definition(chapter), recording, origin.checkpoint, origin.recording_a if origin.recording_a is Dictionary else {})


func _valid_recording(recording: Variant, origin: Dictionary) -> bool:
	return bool(_verify_recording(recording, origin).get("valid", false))


func _valid_pending(value: Variant) -> bool:
	if not value is Dictionary or not _exact(value, ["operation", "body", "request_hash", "origin", "held", "error_code"]) or value.operation not in ["turns", "fork"] or not value.held is bool or not value.error_code is String or value.error_code.length() > 80 or not value.body is Dictionary or not _valid_snapshot(value.origin):
		return false
	var body: Dictionary = value.body
	var keys := ["base_revision", "idempotency_key", "branch", "recording"] if value.operation == "turns" else ["base_revision", "idempotency_key", "branch", "stage_index"]
	if value.operation == "turns" and body.get("recording") is Dictionary and body.recording.get("role") == "b":
		keys.append("checkpoint")
	if not _exact(body, keys) or not _token(body.idempotency_key, -1, 80) or body.idempotency_key.length() < 16 or body.base_revision != value.origin.revision or body.branch != value.origin.branch or value.request_hash != _request_hash(value.operation, body):
		return false
	if value.operation == "fork":
		return _range(body.stage_index, 0, 1) and body.stage_index <= value.origin.stage_index and (body.stage_index < value.origin.stage_index or value.origin.a_turn_id != null)
	var checked := _verify_recording(body.recording, value.origin)
	if not checked.valid or not checked.get("snapshot", {}).get("can_commit", false):
		return false
	if body.recording.role == "a":
		return true
	var engine := Registry.simulation_script(Registry.resolve(value.origin))
	var derived: Dictionary = engine.derive_checkpoint(Registry.definition(Registry.resolve(value.origin)), value.origin.checkpoint, value.origin.recording_a, body.recording)
	return derived.valid and Canonical.same(derived.get("checkpoint", {}), body.checkpoint)


func _valid_receipt(value: Variant, request: Dictionary) -> bool:
	if not value is Dictionary or not _exact(value, RECEIPT_KEYS) or value.schema_version != 2 or value.room_id != _room or value.idempotency_key != request.body.idempotency_key or value.request_hash != request.request_hash or value.operation != request.operation or value.accepted_revision != int(request.body.base_revision) + 1:
		return false
	var branch := int(request.body.branch)
	var index := int(request.origin.stage_index)
	var expected_checkpoint: String = request.origin.checkpoint.checkpoint_hash
	if request.operation == "fork":
		branch += 1
		index = int(request.body.stage_index)
		var source: Dictionary = request.origin.checkpoint
		while int(source.stage_index) > index:
			source = Registry.previous_checkpoint(Registry.resolve(request.origin), source)
		expected_checkpoint = source.checkpoint_hash
		if value.turn_id != null or value.recording_hash != null or value.pair_id != null:
			return false
	else:
		var recording: Dictionary = request.body.recording
		if value.turn_id != "t%d-%d-%s" % [branch, index, recording.role] or value.recording_hash != recording.recording_hash or value.pair_id != ("p%d-%d" % [branch, index] if recording.role == "b" else null):
			return false
		if recording.role == "b":
			expected_checkpoint = request.body.checkpoint.checkpoint_hash
	return value.branch == branch and value.stage_index == index and value.stage_id == Registry.definition(Registry.resolve(request.origin)).stages[index].id and value.checkpoint_hash == expected_checkpoint


func _same_context(first: Dictionary, second: Dictionary) -> bool:
	for name: String in ["room_id", "branch", "stage_id", "definition_hash", "active_role", "active_player_id"]:
		if first.get(name) != second.get(name):
			return false
	return Canonical.same(first.checkpoint, second.checkpoint) and Canonical.same(first.recording_a, second.recording_a)


func _guard() -> bool:
	if _owner == "" or _state.is_empty():
		return false
	var identity := _current_identity()
	if identity.is_empty() or identity.player_id != _owner or int(identity.epoch) != _epoch:
		invalidate_identity()
		return false
	return true


func _current_identity() -> Dictionary:
	var value: Variant = _identity.call()
	if not value is Dictionary or value.get("ready") != true or not _token(value.get("player_id"), 22) or not _range(value.get("epoch"), 0, 9007199254740991):
		return {}
	return {"player_id": value.player_id, "epoch": int(value.epoch)}


func _empty_state() -> Dictionary:
	return {"schema_version": 1, "api_version": 2, "owner_player_id": _owner, "room_id": _room, "snapshot": {}, "draft": {}, "held_drafts": [], "pending": {}, "last_receipt": {}, "auth_required": false}


func _retire_live() -> void:
	_live_simulation = null
	_live_context = {}


func _verify_saved_draft() -> bool:
	if _draft_replay_verified or _state.draft.is_empty():
		return true
	if not _valid_draft(_state.draft):
		return _hold("invalid_saved_rehearsal", "The saved rehearsal failed native replay verification. Its data has been kept.")
	_draft_replay_verified = true
	return true


func _room_path() -> String:
	return "/v2/rooms/" + _room


func _new_key() -> String:
	return str(_keys.call()) if _keys.is_valid() else Crypto.new().generate_random_bytes(18).hex_encode()


static func _request_hash(operation: String, body: Dictionary) -> String:
	var value := body.duplicate(true)
	value["operation"] = operation
	return Canonical.digest(value)


static func _bounded(value: Variant, bytes: int = 1048576) -> bool:
	var pending: Array = [{"value": value, "depth": 0}]
	var nodes := 0
	while not pending.is_empty():
		var item: Dictionary = pending.pop_back()
		nodes += 1
		if nodes > 140000 or int(item.depth) > 24:
			return false
		var v: Variant = item.value
		if v is Dictionary:
			for key: Variant in v:
				if not key is String or key.length() > 80:
					return false
				pending.append({"value": v[key], "depth": int(item.depth) + 1})
		elif v is Array:
			for child: Variant in v:
				pending.append({"value": child, "depth": int(item.depth) + 1})
		elif v is String:
			if v.length() > 512:
				return false
		elif not (v == null or v is bool or _range(v, -9007199254740991, 9007199254740991)):
			return false
		if pending.size() > 140000:
			return false
	return JSON.stringify(value).to_utf8_buffer().size() <= bytes


static func _range(value: Variant, low: int, high: int) -> bool:
	return (value is int or (value is float and is_finite(value) and value == floor(value))) and value >= low and value <= high


static func _token(value: Variant, length: int = -1, maximum: int = 80) -> bool:
	if not value is String or value.is_empty() or value.length() > maximum or (length >= 0 and value.length() != length):
		return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true


static func _pattern(value: Variant, expression: String) -> bool:
	if not value is String or value.length() > 80:
		return false
	var pattern := RegEx.new()
	return pattern.compile(expression) == OK and pattern.search(value) != null


static func _exact(value: Dictionary, keys: Array) -> bool:
	return value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))


func _error(code: String, message: String) -> bool:
	last_code = code
	last_error = message
	return false


func _hold(code: String, message: String) -> bool:
	read_only = true
	return _error(code, message)


func _clear_error() -> void:
	last_error = ""
	last_code = ""
