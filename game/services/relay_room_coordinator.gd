class_name RelayRoomCoordinator
extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Reaper = preload("res://services/worker_reaper.gd")
## Bundled RoomV2 chapters, each with its own stage count; it never reads the solo journey or stores credentials.
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
const Keepsakes = preload("res://services/home_keepsakes.gd")
const RoomStages = preload("res://services/room_stages.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const Frozen = preload("res://services/frozen_simulation.gd")
const Typed = preload("res://services/typed_values.gd")
## Whole-journal bytes, the same as RelayOnlineStore.VALUE_BYTES.
const MAX_BYTES := 8388608
## Journal values under comfort rules (8 and up), Turn of the Tide's long turns included.
const COMFORT_JOURNAL_NODES := 720000
## Journal values for any other chapter, per two of its stages: a journal holds
## up to seven copies of the chapter's proof chain, and a chain grows by one
## nested pair per stage. Two-stage chapters keep exactly the old 140k.
const JOURNAL_NODES_PER_TWO_STAGES := 140000
## One fetched or remembered pair is a single server pairs row (MAX_ROW_BYTES,
## 1.5 MiB). The widest Turn of the Tide pair is about 823 KB and 87.5k values.
const MAX_PAIR_BYTES := 2097152
const MAX_PAIR_NODES := 220000
## Highest room rules number this build understands (9 = comfort alias,
## 11 = sleeping-lighthouse@2). A room is still held to its chapter's own rules.
const MAX_SIMULATION_VERSION := 11
const MAX_HELD := 4
const STATE_KEYS := ["schema_version", "api_version", "owner_player_id", "room_id", "snapshot", "draft", "held_drafts", "pending", "last_receipt", "auth_required"]
const SNAPSHOT_KEYS := ["schema_version", "room_id", "revision", "branch", "stage_index", "level_id", "level_version", "definition_hash", "host_id", "guest_id", "checkpoint", "a_turn_id", "completed_pair_ids", "invite_expires_at", "created_at", "updated_at", "api_version", "active_role", "first_player_id", "active_player_id", "player_slot", "stage_id", "recording_a", "validation"]
const RECEIPT_KEYS := ["schema_version", "room_id", "idempotency_key", "request_hash", "operation", "accepted_revision", "branch", "stage_index", "stage_id", "turn_id", "recording_hash", "pair_id", "checkpoint_hash"]

var last_error := ""
var last_code := ""
var read_only := false
var supported_simulation_versions: Dictionary = {}
var accepted_pair_cache: Callable
var restore_replay_transfer: Callable
var recover_replay_operation: Callable
var _replay_recovering := false
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
var _gone := false
var _last_refresh_result: Dictionary = {}
var _background_save: Callable
var _draft_writer: Thread
var _draft_write_task: RefCounted
var _draft_write_next: Dictionary = {}
var _draft_write_generation := -1
## Turn replay checks already made, by their exact inputs: {key: {checked,
## derived}} (see _checked_turn). Replaying a long turn took a second or more
## on this thread, and a review, its Save, the request Save writes and the room
## the reply returns each checked the same turn again. Only valid checks are kept.
var _proven_turns: Dictionary = {}
const PROVEN_TURNS := 8
## How long the last turn check took here, per replayed tick, so a screen can
## tell ahead whether a check is worth a wait card (as RelayJourney does).
var _last_check_usec := 0
var _last_check_ticks := 0
const CHECK_USEC_PER_TICK := 1000

class DraftWrite:
	extends RefCounted
	var save: Callable
	var scope: String
	var value: Dictionary
	func _init(writer: Callable, target: String, frozen: Dictionary) -> void:
		save = writer
		scope = target
		value = frozen
	func run() -> Variant:
		# No simulation, identity callback, coordinator or scene-tree access.
		return save.call(scope, value)


func _init(transport: Callable, load_store: Callable, save_store: Callable, identity_owner: Callable, key_factory: Callable = Callable(), background_save: Callable = Callable()) -> void:
	_transport = transport
	_load = load_store
	_save = save_store
	_identity = identity_owner
	_keys = key_factory
	# Opt in only with a serialized, worker-safe storage adapter. Generic
	# injected callbacks retain the original synchronous save behavior.
	_background_save = background_save


func poll_live_draft_save() -> bool:
	return true if _draft_writer == null or _draft_writer.is_alive() else finish_live_draft_save()


func finish_live_draft_save() -> bool:
	if _draft_writer == null: return true
	var result: Variant = _draft_writer.wait_to_finish()
	var next := _draft_write_next
	var generation := _draft_write_generation
	_draft_writer = null
	_draft_write_task = null
	_draft_write_next = {}
	_draft_write_generation = -1
	if generation != _generation or not _guard(): return false
	# A periodic capture checked on its worker reports why it was refused.
	if result is Dictionary and result.has("code"): return _error(str(result.code), str(result.message))
	if not result is Dictionary or not result.get("ok", false):
		return _error("storage_write_failed", PlayerCopy.RELAY_ROOM_COORDINATOR_5DADE5ECBD15)
	if next.is_empty() and result.get("next") is Dictionary: next = result.next
	_accept_persisted(next)
	_draft_replay_verified = false
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _draft_writer != null:
		# The writer owns only its frozen value and storage adapter. Join before
		# releasing the final coordinator, even without a presentation owner.
		_draft_writer.wait_to_finish()
		_draft_writer = null
		_draft_write_task = null


func invalidate_identity() -> void:
	# Account deletion removes its namespace only after this invalidation.
	# An older writer must never recreate a file after that cleanup.
	finish_live_draft_save()
	_clear_chapter()
	_retire_live()
	_last_refresh_result = {}
	_generation += 1
	_busy = 0
	_replay_recovering = false
	_proven_turns.clear()
	_state = {}
	_owner = ""
	_epoch = -1
	_room = ""
	_scope = ""
	read_only = false
	_remote_hold = false
	_gone = false
	_error("identity_changed", PlayerCopy.RELAY_ROOM_COORDINATOR_D83FB37B5CFC)


func bind_room(room_id: String) -> bool:
	if not finish_live_draft_save(): return false
	var identity := _current_identity()
	if identity.is_empty() or not _token(room_id, 22):
		return _error("identity_unavailable", PlayerCopy.RELAY_ROOM_COORDINATOR_86B1462AD35E)
	if _owner != "" and (identity.player_id != _owner or int(identity.epoch) != _epoch):
		invalidate_identity()
	if not _state.is_empty() and not _state.pending.is_empty() and room_id != _room:
		return _error("pending_operation", PlayerCopy.RELAY_ROOM_COORDINATOR_244F104F48A5)
	if _busy != 0 or _replay_recovering:
		return _error("request_busy", PlayerCopy.RELAY_ROOM_COORDINATOR_51FA87EA6C7A)
	var keep_remote_hold: bool = _remote_hold and _owner == identity.player_id and _epoch == int(identity.epoch) and _room == room_id
	_generation += 1
	_owner = identity.player_id
	_last_refresh_result = {}
	_epoch = int(identity.epoch)
	_room = room_id
	_scope = "relay-room-v2:" + _owner + ":" + _room
	_clear_chapter()
	_state = _empty_state()
	_proven_turns.clear()
	_retire_live()
	_draft_replay_verified = true
	read_only = false
	# Reloading the same cache cannot undo a known remote rejection.
	_gone = _gone and keep_remote_hold
	_remote_hold = keep_remote_hold
	var loaded: Variant = _load.call(_scope)
	if not loaded is Dictionary or not loaded.get("ok", false):
		return _hold("storage_unavailable", PlayerCopy.RELAY_ROOM_COORDINATOR_C4AFE12FC876)
	if loaded.get("found", false):
		var value: Variant = loaded.get("value")
		if not _valid_state(value):
			return _hold("invalid_saved_room", PlayerCopy.RELAY_ROOM_COORDINATOR_604A0BACD534)
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
	# A chapter whose proof remembers verified checkpoints keeps them for restarts.
	Proofs.save_memo(_chapter_key)
	_level = Registry.definition(_chapter_key)
	_simulation = Registry.simulation_script(_chapter_key)

func busy() -> bool:
	return _replay_recovering or _busy != 0 or _draft_writer != null


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
	if not finish_live_draft_save(): return {}
	if not _guard() or _state.auth_required or _state.draft.is_empty() or _state.snapshot.is_empty():
		return {}
	if not _verify_saved_draft():
		return {}
	return _state.draft.recording.duplicate(true) if _same_context(_state.draft.origin, _state.snapshot) else {}


func save_draft(recording: Dictionary) -> bool:
	if not finish_live_draft_save(): return false
	if not my_turn() or read_only:
		return _error("draft_unavailable", PlayerCopy.RELAY_ROOM_COORDINATOR_09FED8C87561)
	if not recording.is_empty() and not _valid_recording(recording, _state.snapshot):
		return _error("invalid_recording", PlayerCopy.RELAY_ROOM_COORDINATOR_56C2B84DDCD8)
	var next := _state.duplicate(true)
	next.draft = {} if recording.is_empty() else {"origin": _state.snapshot.duplicate(true), "recording": recording.duplicate(true)}
	var saved := _persist(next)
	if saved:
		_retire_live()
		_draft_replay_verified = true
	return saved


func create_live_simulation(resume_draft: bool = false) -> RefCounted:
	if not finish_live_draft_save(): return null
	# Only this producer may skip repeated ancestor replay during autosave.
	# Recovery, another room, a replaced context or reset retires the instance.
	if not my_turn() or read_only or _busy != 0:
		_error("rehearsal_unavailable", PlayerCopy.RELAY_ROOM_COORDINATOR_D879B5A3D87C)
		return null
	var room: Dictionary = _state.snapshot
	var prior: Dictionary = room.recording_a if room.recording_a is Dictionary else {}
	var simulation: RefCounted = _simulation.new()
	var saved: Dictionary = draft() if resume_draft else {}
	if saved.is_empty():
		saved = {"simulation_version": int(room.get("simulation_version", _level.simulation_version))}
	if read_only: return null
	if not Registry.reset_simulation(simulation, _chapter_key, _level, room.stage_id, room.checkpoint, prior, room.active_role, saved):
		_error("invalid_rehearsal", PlayerCopy.RELAY_ROOM_COORDINATOR_8F47C70FEFCA)
		return null
	_live_simulation = weakref(simulation)
	_live_context = {"generation": _generation, "owner": _owner, "epoch": _epoch, "room": _room,
		"origin": room.duplicate(true), "level_ref": simulation.level,
		"checkpoint_ref": simulation.get("_checkpoint"), "prior_ref": simulation.get("_prior")}
	_clear_error()
	return simulation


func save_live_draft(simulation: RefCounted, periodic: bool = false) -> bool:
	# Keep every existing save interval. A previous transaction is joined before
	# accepting another, and pause/finish/commit still wait for durable storage.
	# A periodic save while the last one is still being written is skipped, as
	# in solo play: the next one holds everything this one would, and waiting
	# here stalled the frame once a second on a slow phone.
	if periodic and _draft_writer != null and _draft_writer.is_alive(): return true
	if not finish_live_draft_save(): return false
	# The exact internal engine exports draft-only state. Loading/resuming and
	# committing still replay it. Caller-supplied dictionaries use save_draft.
	if not my_turn() or read_only or _busy != 0 or simulation == null or _live_simulation == null or _live_simulation.get_ref() != simulation or simulation.get_script() != _simulation or _live_context.is_empty():
		return _error("unregistered_rehearsal", PlayerCopy.RELAY_ROOM_COORDINATOR_52D3BB714BCD)
	if _live_context.generation != _generation or _live_context.owner != _owner or _live_context.epoch != _epoch or _live_context.room != _room or not _same_context(_live_context.origin, _state.snapshot):
		return _error("stale_rehearsal", PlayerCopy.RELAY_ROOM_COORDINATOR_054B1FA46C85)
	# Reference equality detects resetting the same instance, even back to
	# identical values; full comparisons also catch mutations keeping old hashes.
	if not is_same(simulation.get("level"), _live_context.level_ref) or not is_same(simulation.get("_checkpoint"), _live_context.checkpoint_ref) or not is_same(simulation.get("_prior"), _live_context.prior_ref):
		return _error("reset_rehearsal", PlayerCopy.RELAY_ROOM_COORDINATOR_53B70FA2233F)
	var room: Dictionary = _state.snapshot
	var prior: Dictionary = room.recording_a if room.recording_a is Dictionary else {}
	# A periodic capture is checked, exported and written on the worker: all of
	# that grows with the turn's recording, and on the main thread it hitched
	# once a second, more as the turn went on.
	if periodic and _background_save.is_valid() and str(simulation.get("error")).is_empty() and simulation.get("role") == room.active_role:
		if not _guard() or read_only:
			return _error("storage_unavailable", PlayerCopy.RELAY_ROOM_COORDINATOR_66CFB3646B2C)
		var base: Dictionary = _state.duplicate()
		base.draft = {}
		var job := {"simulation": Frozen.of(simulation), "family": _simulation, "level": _level, "room": room, "prior": prior, "state": base, "scope": _scope, "save": _background_save}
		_draft_write_generation = _generation
		_draft_writer = Thread.new()
		# A static function and private copies: no coordinator crosses to the worker.
		if _draft_writer.start(Callable(get_script(), "_capture_draft").bind(job)) == OK: return true
		_draft_writer = null
		_draft_write_generation = -1
		return _error("storage_write_failed", PlayerCopy.RELAY_ROOM_COORDINATOR_5DADE5ECBD15)
	if not str(simulation.get("error")).is_empty() or simulation.get("role") != room.active_role or not Typed.same(simulation.get("level"), _level) or not Typed.same(simulation.get("stage"), _simulation.stage_by_id(_level, room.stage_id)) or not Typed.same(simulation.get("_checkpoint"), room.checkpoint) or not Typed.same(simulation.get("_prior"), prior):
		return _error("changed_rehearsal", PlayerCopy.RELAY_ROOM_COORDINATOR_B17841629D7A)
	var recording: Dictionary = simulation.export_recording()
	if not _bounded(recording) or not _simulation.recording_error(_level, recording, room.checkpoint).is_empty() or recording.get("role") != room.active_role or recording.get("source_recording_hash") != prior.get("recording_hash", ""):
		return _error("invalid_rehearsal", PlayerCopy.RELAY_ROOM_COORDINATOR_710CC18E05E5)
	var next := _state.duplicate(true)
	next.draft = {"origin": room.duplicate(true), "recording": recording.duplicate(true)}
	var saved := _persist(next, periodic)
	if saved:
		_draft_replay_verified = false
	return saved


## The worker of a periodic capture: the checks save_live_draft makes, the
## export, the journal bound and the write, on a still copy of the engine and
## values the coordinator only ever replaces. Reads only its job.
static func _capture_draft(job: Dictionary) -> Dictionary:
	var simulation: RefCounted = job.simulation
	var family: Script = job.family
	var level: Dictionary = job.level
	var room: Dictionary = job.room
	var prior: Dictionary = job.prior
	if not Typed.same(simulation.get("level"), level) or not Typed.same(simulation.get("stage"), family.stage_by_id(level, room.stage_id)) or not Typed.same(simulation.get("_checkpoint"), room.checkpoint) or not Typed.same(simulation.get("_prior"), prior):
		return {"ok": false, "code": "changed_rehearsal", "message": PlayerCopy.RELAY_ROOM_COORDINATOR_B17841629D7A}
	var recording: Dictionary = simulation.export_recording()
	if not _bounded(recording) or not family.recording_error(level, recording, room.checkpoint).is_empty() or recording.get("role") != room.active_role or recording.get("source_recording_hash") != prior.get("recording_hash", ""):
		return {"ok": false, "code": "invalid_rehearsal", "message": PlayerCopy.RELAY_ROOM_COORDINATOR_710CC18E05E5}
	var next: Dictionary = job.state.duplicate(true)
	next.draft = {"origin": room.duplicate(true), "recording": recording.duplicate(true)}
	if not _journal_bounded(next):
		return {"ok": false, "code": "storage_unavailable", "message": PlayerCopy.RELAY_ROOM_COORDINATOR_66CFB3646B2C}
	var written: Variant = job.save.call(job.scope, next.duplicate(true))
	if not written is Dictionary or not written.get("ok", false): return {"ok": false}
	return {"ok": true, "next": next}


func refresh() -> bool:
	if not finish_live_draft_save(): return false
	_last_refresh_result = {}
	var known := _known_room_headers()
	var response := await _request(HTTPClient.METHOD_GET, _room_path(), {}, known)
	if not known.is_empty() and response.get("ok", false) and response.get("data") is Dictionary and response.data.has("unchanged"):
		if _unchanged_reply(response.data): return _confirm_unchanged(response)
		# A small reply that does not match what this phone holds: read the whole room once.
		response = await _request(HTTPClient.METHOD_GET, _room_path())
	if response.get("ignored", false):
		return false
	var status := int(response.get("status", 0))
	_last_refresh_result = {"status": status, "retry_after_ms": clampi(int(response.get("retry_after_ms", 0)), 0, 86400000), "terminal": status in [401, 403, 404, 410]}
	if not response.get("ok", false):
		if status in [403, 404, 410]:
			# Only an exact-room lookup establishes this hold. Missing operation
			# receipts and historical pairs have separate recovery semantics.
			_remote_hold = true
			_retire_live()
			# The other member closed the room or erased their account. A phone
			# waiting in a room still in play, with nothing of its own left here
			# (no rehearsal, no unsent turn), says so instead of waiting for a turn
			# that never comes. A rehearsal keeps the recoverable hold above, and
			# a finished room keeps its finished scene and replays.
			if _ordinary_room_gone(status, str(response.get("code", ""))) and _state.draft.is_empty() and _state.pending.is_empty() and str(_state.snapshot.get("active_role", "")) != "complete": _gone = true
		return _network_error(response)
	return _accept_snapshot(response.get("data"))


## A poll names the verified revision and branch it holds, so a room that has
## not moved answers small (X-AfterYou-Known-Room). Only an ordinary room with
## a stored snapshot asks; recovering sign-in needs the full room to persist.
func _known_room_headers() -> PackedStringArray:
	if _state.is_empty() or _state.snapshot.is_empty() or _state.auth_required: return PackedStringArray()
	return PackedStringArray(["X-AfterYou-Known-Room: %d.%d" % [int(_state.snapshot.revision), int(_state.snapshot.branch)]])


## True only for the exact small reply about the very snapshot this phone holds.
func _unchanged_reply(value: Dictionary) -> bool:
	if _state.is_empty() or _state.snapshot.is_empty() or not _exact(value, ["schema_version", "unchanged", "revision", "branch", "updated_at"]): return false
	var held: Dictionary = _state.snapshot
	return _range(value.schema_version, 1, 1) and value.unchanged is bool and value.unchanged and _range(value.revision, 0, 9007199254740991) and _range(value.branch, 0, 31) and int(value.revision) == int(held.revision) and int(value.branch) == int(held.branch) and value.updated_at is String and value.updated_at == held.updated_at


## Nothing changed: the stored, already-verified snapshot stays as it is, with
## no verification, no save and no new snapshot for the screen to redraw.
func _confirm_unchanged(response: Dictionary) -> bool:
	if not finish_live_draft_save() or not _guard(): return false
	_last_refresh_result = {"status": int(response.get("status", 200)), "retry_after_ms": clampi(int(response.get("retry_after_ms", 0)), 0, 86400000), "terminal": false}
	_remote_hold = false
	_gone = false
	_clear_error()
	return true


func commit(recording: Dictionary) -> bool:
	if not finish_live_draft_save(): return false
	if not my_turn() or read_only or _busy != 0:
		return _error("commit_unavailable", PlayerCopy.RELAY_ROOM_COORDINATOR_BBE0446F0FDD)
	# The turn's replay check (and a second turn's next checkpoint) runs on a
	# worker unless the review already made it, while the room counts as busy;
	# the checks below then find it made. Nothing is decided on the worker.
	var checked: Dictionary = {}
	var job := turn_check_job(recording)
	if not job.is_empty():
		var generation := _generation
		_serial += 1
		var proving := _serial
		_busy = proving
		var result: Variant = await Reaper.run(turn_check_runner().bind(job), true)
		if _busy == proving: _busy = 0
		if generation != _generation: return false
		if not finish_live_draft_save(): return false
		if not my_turn() or read_only or _busy != 0:
			return _error("commit_unavailable", PlayerCopy.RELAY_ROOM_COORDINATOR_BBE0446F0FDD)
		# A failed check is not kept, so it is used here rather than made again.
		if result is Dictionary and adopt_turn_check(job, result): checked = result.checked
	if checked.is_empty(): checked = _verify_recording(recording, _state.snapshot)
	if not checked.valid or not checked.get("snapshot", {}).get("can_commit", false):
		return _error("incomplete_recording", PlayerCopy.RELAY_ROOM_COORDINATOR_D74CA6BA0A5A)
	var body := {"base_revision": _state.snapshot.revision, "idempotency_key": _new_key(), "branch": _state.snapshot.branch, "recording": recording.duplicate(true)}
	if recording.role == "b":
		var derived: Dictionary = _derived_checkpoint(_state.snapshot, recording)
		if not derived.valid:
			return _error("invalid_checkpoint", PlayerCopy.RELAY_ROOM_COORDINATOR_FF537A6505A8)
		body["checkpoint"] = derived.checkpoint
	if not _prepare_pending("turns", body):
		return false
	return await _send_pending()


func fork(stage_index: int) -> bool:
	if not finish_live_draft_save(): return false
	if _replay_recovering: return false
	if not _guard() or read_only or _state.auth_required or _state.snapshot.is_empty() or not _state.pending.is_empty() or _busy != 0 or (_remote_hold and last_code != "replay_transferred"):
		return _error("fork_unavailable", PlayerCopy.RELAY_ROOM_COORDINATOR_827CAA5E0407)
	if not RoomStages.within(stage_index, _level) or stage_index > int(_state.snapshot.stage_index) or (stage_index == int(_state.snapshot.stage_index) and _state.snapshot.a_turn_id == null):
		return _error("nothing_to_fork", PlayerCopy.RELAY_ROOM_COORDINATOR_CFE2D14056BD)
	if _guard() and _state.pending.is_empty() and _busy == 0 and _state.snapshot.get("active_role") == "complete" and restore_replay_transfer.is_valid():
		var generation := _generation
		_replay_recovering = true
		var restored: Dictionary = await restore_replay_transfer.call(_room)
		if generation == _generation: _replay_recovering = false
		if generation != _generation or not _guard(): return false
		if not restored.get("ok", false): return _network_error(restored)
		if not await refresh(): return false
	if not _guard() or read_only or _remote_hold or _state.auth_required or _state.snapshot.is_empty() or not _state.pending.is_empty() or _busy != 0:
		return _error("fork_unavailable", PlayerCopy.RELAY_ROOM_COORDINATOR_827CAA5E0407)
	var room: Dictionary = _state.snapshot
	if not RoomStages.within(stage_index, _level) or stage_index > int(room.stage_index) or (stage_index == int(room.stage_index) and room.a_turn_id == null):
		return _error("nothing_to_fork", PlayerCopy.RELAY_ROOM_COORDINATOR_CFE2D14056BD)
	var body := {"base_revision": room.revision, "idempotency_key": _new_key(), "branch": room.branch, "stage_index": stage_index}
	if not _prepare_pending("fork", body):
		return false
	return await _send_pending()


func reconcile() -> bool:
	if not finish_live_draft_save(): return false
	if not _guard() or read_only or _state.pending.is_empty() or _busy != 0:
		return _error("pending_unavailable", PlayerCopy.RELAY_ROOM_COORDINATOR_A65FC7EDAE81)
	var response := await _request(HTTPClient.METHOD_GET, _room_path() + "/operations/" + str(_state.pending.body.idempotency_key))
	if response.get("status") == 410 and response.get("code") == "replay_transferred": response = await _recover_transferred_pending()
	if response.get("ignored", false):
		return false
	if response.get("ok", false):
		return _accept_receipt(response.get("data"))
	if int(response.get("status", 0)) == 404 and response.get("code") == "operation_not_found" and _pending_guest_join_recovery():
		return await _recover_guest_join()
	if int(response.get("status", 0)) == 404 and response.get("code") == "operation_not_found" and not _state.pending.held:
		return await _send_pending()
	return _network_error(response)


func archive_held_submission() -> bool:
	if not finish_live_draft_save(): return false
	if not _guard() or read_only or _state.auth_required or _busy != 0 or _state.pending.is_empty() or not _state.pending.held:
		return _error("pending_unresolved", PlayerCopy.RELAY_ROOM_COORDINATOR_327B5AC5686B)
	var next := _state.duplicate(true)
	if next.pending.operation == "turns":
		if next.held_drafts.size() >= MAX_HELD:
			return _error("local_history_full", PlayerCopy.RELAY_ROOM_COORDINATOR_FAB1AD642186)
		next.held_drafts.append({"origin": next.pending.origin.duplicate(true), "recording": next.pending.body.recording.duplicate(true)})
	next.pending = {}
	next.draft = {}
	return _persist(next)


func fetch_pair(pair_id: String) -> Dictionary:
	if not _pattern(pair_id, "^p[0-9]{1,2}-" + RoomStages.DIGIT + "$") or not RoomStages.within(int(pair_id.get_slice("-", 1)), _level):
		_error("invalid_pair", PlayerCopy.RELAY_ROOM_COORDINATOR_C3C090053E04)
		return {}
	var response := await _request(HTTPClient.METHOD_GET, _room_path() + "/pairs/" + pair_id)
	if response.get("ignored", false):
		return {}
	if not response.get("ok", false):
		_network_error(response)
		return {}
	var pair: Variant = response.get("data")
	if not _pair_bounded(pair) or not pair is Dictionary or not _exact(pair, ["pair_id", "branch", "stage_index", "a", "b", "checkpoint"]) or not Typed.equal(pair.pair_id, pair_id) or not _range(pair.branch, 0, 31) or not RoomStages.within(pair.stage_index, _level) or not pair.checkpoint is Dictionary:
		_error("invalid_pair", PlayerCopy.RELAY_ROOM_COORDINATOR_E6C7811105B3)
		return {}
	var proof: Variant = pair.checkpoint.get("proof")
	if not proof is Dictionary or Registry.previous_checkpoint(_chapter_key, pair.checkpoint).is_empty() or not pair.a is Dictionary or not pair.b is Dictionary:
		_error("invalid_pair", PlayerCopy.RELAY_ROOM_COORDINATOR_806EA219BFEC)
		return {}
	var derived: Dictionary = _simulation.derive_checkpoint(_level, Registry.previous_checkpoint(_chapter_key, pair.checkpoint), pair.a, pair.b)
	if not derived.valid or not Typed.same(derived.get("checkpoint", {}), pair.checkpoint) or pair.stage_index != int(pair.checkpoint.stage_index) - 1 or pair_id != "p%d-%d" % [int(pair.branch), int(pair.stage_index)]:
		_error("invalid_pair", PlayerCopy.RELAY_ROOM_COORDINATOR_35B4466C889C)
		return {}
	_clear_error()
	return pair.duplicate(true)


func _prepare_pending(operation: String, body: Dictionary) -> bool:
	var next := _state.duplicate(true)
	next.pending = {"operation": operation, "body": body.duplicate(true), "request_hash": _request_hash(operation, body), "origin": _state.snapshot.duplicate(true), "held": false, "error_code": ""}
	if not _valid_pending(next.pending):
		return _error("invalid_pending", PlayerCopy.RELAY_ROOM_COORDINATOR_CF423F666E23)
	var saved := _persist(next)
	if saved:
		_retire_live()
	return saved


func _send_pending(recover_guest_join: bool = true) -> bool:
	if not _guard() or _state.pending.is_empty() or _state.pending.held:
		return false
	var response := await _request(HTTPClient.METHOD_POST, _room_path() + "/" + str(_state.pending.operation), _state.pending.body)
	if response.get("ignored", false):
		return false
	if not response.get("ok", false):
		if response.get("status") == 410 and response.get("code") == "replay_transferred" and recover_replay_operation.is_valid():
			var recovered := await _recover_transferred_pending()
			if recovered.get("ok", false): return _accept_receipt(recovered.get("data"))
			# The original request remains durable. Reconcile can send that exact
			# body after a definitive missing-receipt result; never rekey here.
			return _network_error(recovered)
		_network_error(response, true)
		if recover_guest_join and int(response.get("status", 0)) == 409 and response.get("code") == "stale_revision" and _pending_guest_join_recovery():
			return await _recover_guest_join()
		return false
	return _accept_receipt(response.get("data"))

func _recover_transferred_pending() -> Dictionary:
	if _replay_recovering or not _guard() or _state.pending.is_empty() or not recover_replay_operation.is_valid(): return {"ok": false, "code": "replay_transferred", "status": 410}
	var generation := _generation
	var request: Dictionary = _state.pending.duplicate(true)
	_replay_recovering = true
	var result: Dictionary = await recover_replay_operation.call(_room, str(request.body.idempotency_key), _valid_receipt.bind(request))
	if generation == _generation: _replay_recovering = false
	if generation != _generation or not _guard() or not Typed.same(request, _state.pending): return {"ok": false, "ignored": true, "code": "identity_changed"}
	return result


func _pending_guest_join_recovery() -> bool:
	# Joining changes the initial room revision even if the host is already
	# recording A. Only a definitively rejected ordinary first turn can rebase;
	# an uncertain delivery must always keep its exact request and key.
	if not _guard() or read_only or _state.auth_required or _state.pending.is_empty():
		return false
	var request: Dictionary = _state.pending
	if not request.held or request.error_code != "stale_revision" or request.operation != "turns": return false
	var origin: Dictionary = request.origin
	return request.body.base_revision == 0 and request.body.branch == 0 and request.body.recording.role == "a" and origin.revision == 0 and origin.branch == 0 and origin.stage_index == 0 and origin.host_id == _owner and origin.guest_id == null and origin.active_player_id == _owner and origin.active_role == "a" and origin.a_turn_id == null and origin.recording_a == null and origin.completed_pair_ids.is_empty()


func _recover_guest_join() -> bool:
	if not _pending_guest_join_recovery(): return false
	var rejected: Dictionary = _state.pending.duplicate(true)
	var response := await _request(HTTPClient.METHOD_GET, _room_path())
	if response.get("ignored", false) or not _pending_guest_join_recovery() or not Typed.same(_state.pending, rejected): return false
	if not response.get("ok", false): return _network_error(response)
	var room: Variant = response.get("data")
	if not _valid_snapshot(room):
		_remote_hold = true
		return _error("invalid_snapshot", PlayerCopy.RELAY_ROOM_COORDINATOR_97B931D8DEE0)
	if room.revision != 1 or room.guest_id == null: return false
	var joined: Dictionary = rejected.origin.duplicate(true)
	joined.revision = 1
	joined.guest_id = room.guest_id
	joined.updated_at = room.updated_at
	if not Typed.same(joined, room): return false
	# A later refresh may already have verified a turn or fork while the held
	# request remained recoverable. An old join projection cannot roll it back.
	if not Typed.same(_state.snapshot, rejected.origin) and not Typed.same(_state.snapshot, room): return false
	# Keep the rejected request intact until its replacement is durably written.
	# Recording bytes and gameplay context do not change; a new key binds the
	# new revision so later lost-response recovery can still retry exactly.
	var next := _state.duplicate(true)
	var body: Dictionary = rejected.body.duplicate(true)
	body.base_revision = 1
	body.idempotency_key = _new_key()
	if body.idempotency_key == rejected.body.idempotency_key: return false
	next.snapshot = room.duplicate(true)
	next.pending = {"operation":"turns", "body":body, "request_hash":_request_hash("turns", body), "origin":room.duplicate(true), "held":false, "error_code":""}
	if not _valid_pending(next.pending) or not _persist(next): return false
	_remote_hold = false
	_gone = false
	return await _send_pending(false)


func _accept_receipt(value: Variant) -> bool:
	if not finish_live_draft_save(): return false
	if not _guard() or _state.pending.is_empty() or not _bounded(value) or not value is Dictionary or not _exact(value, ["receipt", "room"]) or not _valid_receipt(value.get("receipt"), _state.pending):
		return _error("receipt_mismatch", PlayerCopy.RELAY_ROOM_COORDINATOR_F62B6C5636FD)
	if not _valid_snapshot(value.room):
		_remote_hold = true
		return _error("invalid_snapshot", PlayerCopy.RELAY_ROOM_COORDINATOR_84E284188722)
	if int(value.room.revision) < int(value.receipt.accepted_revision):
		return _error("receipt_mismatch", PlayerCopy.RELAY_ROOM_COORDINATOR_44F9E57FF773)
	var completed_chapter := ""
	var completed_count := 0
	var retired_proof: Dictionary = {}
	if _state.pending.operation == "turns" and _state.pending.body.recording.role == "b":
		# A receipt can arrive after a partner has already forked. Its exact
		# accepted native-verified B proof still earns the completed prefix.
		completed_chapter = Registry.resolve(_state.pending.origin)
		completed_count = int(_state.pending.body.checkpoint.stage_index)
		if int(value.room.branch) != int(_state.pending.origin.branch) or (not _state.snapshot.is_empty() and int(_state.snapshot.branch) != int(_state.pending.origin.branch)):
			retired_proof = {"owner": _owner, "epoch": _epoch, "origin": _state.pending.origin.duplicate(true), "receipt": value.receipt.duplicate(true),
				"pair": {"pair_id": value.receipt.pair_id, "branch": value.receipt.branch, "stage_index": value.receipt.stage_index,
					"a": _state.pending.origin.recording_a.duplicate(true), "b": _state.pending.body.recording.duplicate(true), "checkpoint": _state.pending.body.checkpoint.duplicate(true)}}
	var next := _state.duplicate(true)
	# A later response can confirm the old receipt without rolling back a newer
	# already-verified snapshot obtained by a previous refresh.
	if next.snapshot.is_empty() or int(value.room.revision) >= int(next.snapshot.revision):
		if not next.snapshot.is_empty() and int(value.room.revision) == int(next.snapshot.revision) and not Typed.same(value.room, next.snapshot):
			return _error("snapshot_conflict", PlayerCopy.RELAY_ROOM_COORDINATOR_666CD1F2C6F9)
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
		_gone = false
		if not completed_chapter.is_empty(): Keepsakes.record_friend_prefix(completed_chapter, completed_count)
		# Keep already accepted evidence when the current room moved to a fork.
		# This auxiliary cache failure can never roll back the gameplay receipt.
		if not retired_proof.is_empty() and accepted_pair_cache.is_valid(): accepted_pair_cache.call(retired_proof)
	return saved


func _accept_snapshot(value: Variant) -> bool:
	if not finish_live_draft_save(): return false
	# A waiting phone polls the same room every few seconds. The stored snapshot
	# already passed full verification when it was accepted or loaded, so an
	# identical copy skips the checkpoint and recording re-simulation.
	var guarded := _guard()
	var identical: bool = guarded and not _state.snapshot.is_empty() and Typed.same(value, _state.snapshot)
	if not guarded or (not identical and not _valid_snapshot(value)):
		_remote_hold = true
		return _error("invalid_snapshot", PlayerCopy.RELAY_ROOM_COORDINATOR_97B931D8DEE0)
	if not _state.snapshot.is_empty():
		if int(value.revision) < int(_state.snapshot.revision) or int(value.branch) < int(_state.snapshot.branch):
			return _error("stale_snapshot", PlayerCopy.RELAY_ROOM_COORDINATOR_FE7E854E465F)
		if int(value.revision) == int(_state.snapshot.revision) and not Typed.same(value, _state.snapshot):
			return _error("snapshot_conflict", PlayerCopy.RELAY_ROOM_COORDINATOR_666CD1F2C6F9)
		# An identical GET confirms availability without producing another save
		# generation. Its stored copy passed full native verification and revision checks.
		# Auth recovery must persist; a receipt must separately resolve pending.
		if Typed.same(value, _state.snapshot) and not _state.auth_required:
			_remote_hold = false
			_gone = false
			_clear_error()
			return true
	var next := _state.duplicate(true)
	if not next.draft.is_empty() and not _same_context(next.draft.origin, value):
		if not _verify_saved_draft():
			return false
		if next.held_drafts.size() >= MAX_HELD:
			return _error("local_history_full", PlayerCopy.RELAY_ROOM_COORDINATOR_AE7565BFF4DD)
		next.held_drafts.append(next.draft.duplicate(true))
		next.draft = {}
	next.snapshot = value.duplicate(true)
	next.auth_required = false
	var saved := _persist(next)
	if saved:
		_remote_hold = false
		_gone = false
	if saved and not _live_context.is_empty() and not _same_context(_live_context.origin, next.snapshot):
		_retire_live()
	return saved


func _request(method: int, path: String, body: Dictionary = {}, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not _guard() or read_only or _busy != 0:
		return {"ignored": true}
	_serial += 1
	var request_id := _serial
	var generation := _generation
	var owner := _owner
	var epoch := _epoch
	_busy = request_id
	var request := {"method": method, "path": path, "body": body.duplicate(true), "owner_player_id": owner, "identity_epoch": epoch}
	if not headers.is_empty(): request["headers"] = headers
	var response: Variant = await _transport.call(request)
	await _prove_room_ahead(response)
	if _busy == request_id:
		_busy = 0
	var identity := _current_identity()
	if generation != _generation or owner != _owner or epoch != _epoch:
		return {"ignored": true}
	if identity.is_empty() or identity.player_id != owner or int(identity.epoch) != epoch:
		invalidate_identity()
		return {"ignored": true}
	return response if response is Dictionary else {"ok": false, "status": 0, "code": "invalid_response"}


## A late joiner's first look at a long Lighthouse room proves its whole chain
## of stages once: seconds on this thread for a fresh install at stage five or
## six. Prove the room's checkpoint on a worker first; the full check that
## follows here then finds each stage in the shared proof memo
## (core/lighthouse/room_proof.gd, mutex-guarded). Never decides anything:
## the checks after it run exactly as before.
func _prove_room_ahead(response: Variant) -> void:
	if not response is Dictionary or not response.get("data") is Dictionary: return
	var data: Dictionary = response.data
	var room: Variant = data.get("room") if data.get("room") is Dictionary else data
	if not room is Dictionary or not room.get("checkpoint") is Dictionary or not _bounded(room): return
	# The stored snapshot's checkpoint was proved when it was accepted.
	if not _state.is_empty() and Typed.same(room, _state.get("snapshot", {})): return
	var stage: Variant = room.checkpoint.get("stage_index")
	if not _range(stage, 2, 64): return
	var chapter := Registry.resolve(room)
	if chapter.is_empty() or not Proofs._memo_chapter(chapter): return
	Proofs.prepare_memo(chapter)
	if Engine.get_main_loop() == null: return
	await Reaper.run(Callable(get_script(), "_prove_checkpoint").bind(Registry.simulation_script(chapter), Registry.definition(chapter), room.checkpoint.duplicate(true)))

static func _prove_checkpoint(engine: Script, level: Dictionary, checkpoint: Dictionary) -> bool:
	return engine.verify_checkpoint(level, checkpoint).get("valid", false)


func _network_error(response: Dictionary, definitive_rejection: bool = false) -> bool:
	if not finish_live_draft_save(): return false
	if not _guard():
		return false
	var status := int(response.get("status", 0))
	var code := str(response.get("code", "connection_interrupted"))
	if not _token(code, -1, 80):
		code = "connection_interrupted"
	if _ordinary_room_gone(status, code) and not _state.pending.is_empty():
		return _settle_gone_room(code)
	var next := _state.duplicate(true)
	var changed := false
	if status == 401:
		_retire_live()
		next.auth_required = true
		changed = true
	# A failed lookup or revoked credential says nothing about whether an earlier
	# POST was accepted. Only a definitive mutation rejection permits archival.
	# Restoring the host's access can admit this same exact request later.
	# Keep its durable key and rehearsal available for normal reconciliation.
	if definitive_rejection and status >= 400 and status < 500 and status not in [401, 408, 429] and code != "host_unlock_required" and not next.pending.is_empty():
		next.pending.held = true
		next.pending.error_code = code
		changed = true
	if changed and not _persist(next):
		return false
	var message := PlayerCopy.RELAY_ROOM_COORDINATOR_98C0DD025DA0
	if status == 401:
		message = PlayerCopy.RELAY_ROOM_COORDINATOR_F33051125010
	elif code == "v2_mutations_disabled":
		message = PlayerCopy.RELAY_ROOM_COORDINATOR_6B85BEE93D9C
	elif code == "host_unlock_required":
		message = PlayerCopy.ROOMS_API_93CCDC2D04DB
	elif code == "entitlement_unavailable":
		message = PlayerCopy.ROOMS_API_5E389F16D75A
	elif status == 409:
		message = PlayerCopy.RELAY_ROOM_COORDINATOR_073A691CD782
	elif status in [404, 410]:
		message = PlayerCopy.RELAY_ROOM_COORDINATOR_DEB2573FA986
	return _error(code, message)


## The server no longer has this room for this player: the other member closed
## it, an account was erased, or this player left it. Every request on the
## room answers this way from then on, so nothing sent here can be accepted.
static func _room_gone_response(status: int, code: String) -> bool:
	return (status == 404 and code == "room_not_found") or (status == 410 and code in ["room_deleted", "room_closed"])

## A gone-room answer: the room was closed, left or removed.
func _ordinary_room_gone(status: int, code: String) -> bool:
	return _room_gone_response(status, code)

## True once a turn this phone sent (or was about to send) found the room gone.
func room_gone() -> bool:
	return _guard() and _gone

## A turn sent to a gone room can never be accepted. It moves to the room's
## local history (still on this phone), so it no longer holds other rooms. The
## rehearsal draft and the rest of the journal stay exactly as they were.
func _settle_gone_room(code: String) -> bool:
	if _state.pending.is_empty(): return false
	var next := _state.duplicate(true)
	if next.pending.operation == "turns":
		if next.held_drafts.size() >= MAX_HELD: next.held_drafts.pop_front()
		next.held_drafts.append({"origin": next.pending.origin.duplicate(true), "recording": next.pending.body.recording.duplicate(true)})
	next.pending = {}
	if not _persist(next): return false
	_gone = true
	_remote_hold = true
	_retire_live()
	return _error(code, PlayerCopy.ROOMS_API_A7ACF38988EE)

func _persist(next: Dictionary, periodic: bool = false) -> bool:
	if not finish_live_draft_save(): return false
	if not _guard() or read_only or not _journal_bounded(next):
		return _error("storage_unavailable", PlayerCopy.RELAY_ROOM_COORDINATOR_66CFB3646B2C)
	if periodic and _background_save.is_valid():
		_draft_write_generation = _generation
		_draft_write_next = next.duplicate(true)
		_draft_write_task = DraftWrite.new(_background_save, _scope, _draft_write_next)
		# Joined before this coordinator is freed: polled when done, or in
		# PREDELETE from its own fields (never through a self method there).
		_draft_writer = Thread.new()
		if _draft_writer.start(_draft_write_task.run) == OK: return true
		_draft_writer = null
		_draft_write_task = null
		_draft_write_next = {}
		_draft_write_generation = -1
		return _error("storage_write_failed", PlayerCopy.RELAY_ROOM_COORDINATOR_5DADE5ECBD15)
	var generation := _generation
	var result: Variant = _save.call(_scope, next.duplicate(true))
	if generation != _generation or not _guard():
		return false
	if not result is Dictionary or not result.get("ok", false):
		return _error("storage_write_failed", PlayerCopy.RELAY_ROOM_COORDINATOR_5DADE5ECBD15)
	_accept_persisted(next)
	return true


func _accept_persisted(next: Dictionary) -> void:
	_state = next.duplicate(true)
	_sync_chapter()
	_clear_error()
	if not _state.snapshot.is_empty() and not _state.auth_required and _state.snapshot.get("guest_id") != null:
		Keepsakes.record_friend_prefix(_chapter_key, int(_state.snapshot.stage_index))


func _valid_state(value: Variant) -> bool:
	if not _journal_bounded(value) or not value is Dictionary or not _exact(value, STATE_KEYS) or not Typed.equal(value.schema_version, 1) or not Typed.equal(value.api_version, 2) or not Typed.equal(value.owner_player_id, _owner) or not Typed.equal(value.room_id, _room) or not value.auth_required is bool:
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
	Proofs.prepare_memo(chapter)
	var keys := SNAPSHOT_KEYS.duplicate()
	if value.has("invite_code"):
		keys.append("invite_code")
	if value.has("simulation_version"):
		keys.append("simulation_version")
		if not _range(value.simulation_version, 1, MAX_SIMULATION_VERSION) or int(value.simulation_version) not in Registry.supported_rules(chapter): return false
	if not _exact(value, keys) or not Typed.equal(value.api_version, 2) or not Typed.equal(value.schema_version, 2) or chapter.is_empty() or (not _chapter_key.is_empty() and chapter != _chapter_key) or not Typed.equal(value.validation, "structural_client_replay_required") or not Typed.equal(value.room_id, _room):
		return false
	if not _token(value.host_id, 22) or (value.guest_id != null and (not _token(value.guest_id, 22) or value.guest_id == value.host_id)) or _owner not in [value.host_id, value.guest_id]:
		return false
	# A room's stage index runs to its chapter's stage count, which means complete.
	var stages := RoomStages.count(level)
	if not _range(value.revision, 0, 9007199254740991) or not _range(value.branch, 0, 31) or not _range(value.stage_index, 0, stages):
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
	if not Typed.equal(value.player_slot, ("p0" if Typed.equal(value.host_id, _owner) else "p1")) or (Typed.equal(value.host_id, _owner) and (not value.has("invite_code") or not _pattern(value.invite_code, "^[A-F0-9]{20}$"))) or (not Typed.equal(value.host_id, _owner) and value.has("invite_code")):
		return false
	if index == stages:
		return Typed.equal(value.stage_id, "") and Typed.equal(value.active_role, "complete") and value.first_player_id == null and value.active_player_id == null and value.a_turn_id == null and value.recording_a == null
	var stage: Dictionary = level.stages[index]
	var first: Variant = value.host_id if stage.first_player_slot == "p0" else value.guest_id
	var second: Variant = value.guest_id if stage.first_player_slot == "p0" else value.host_id
	if not Typed.equal(value.stage_id, stage.id) or not Typed.equal(value.first_player_id, first):
		return false
	if value.recording_a == null:
		return value.a_turn_id == null and Typed.equal(value.active_role, "a") and Typed.equal(value.active_player_id, first)
	if not value.recording_a is Dictionary or not Typed.equal(value.a_turn_id, "t%d-%d-a" % [int(value.branch), index]) or not Typed.equal(value.active_role, "b") or not Typed.equal(value.active_player_id, second):
		return false
	if not Typed.equal(value.recording_a.get("simulation_version"), value.get("simulation_version", level.simulation_version)): return false
	var verified: Dictionary = _checked_turn(chapter, value.checkpoint, {}, value.recording_a)
	return Typed.equal(value.recording_a.get("role"), "a") and verified.valid and verified.get("snapshot", {}).get("can_commit", false)


func _valid_draft(value: Variant) -> bool:
	return value is Dictionary and (value.is_empty() or (_exact(value, ["origin", "recording"]) and _valid_snapshot(value.origin) and _valid_recording(value.recording, value.origin)))


func _verify_recording(recording: Variant, origin: Dictionary) -> Dictionary:
	if not _bounded(recording) or not recording is Dictionary or origin.is_empty() or not Typed.equal(origin.active_player_id, _owner) or not Typed.equal(recording.get("role"), origin.active_role) or Typed.equal(origin.active_role, "complete"):
		return {"valid": false}
	var chapter := Registry.resolve(origin)
	if chapter.is_empty(): return {"valid": false}
	if not Typed.equal(recording.get("simulation_version"), origin.get("simulation_version", Registry.definition(chapter).simulation_version)): return {"valid": false}
	return _checked_turn(chapter, origin.checkpoint, origin.recording_a if origin.recording_a is Dictionary else {}, recording)


## engine.verify_recording(level, recording, checkpoint, prior) for this
## chapter, made once per exact inputs: a check is a pure replay, so the same
## inputs give the same answer. A valid one is kept (_proven_turns).
func _checked_turn(chapter: String, checkpoint: Dictionary, prior: Dictionary, recording: Dictionary) -> Dictionary:
	var key := _turn_key(chapter, checkpoint, prior, recording)
	var known: Dictionary = _proven_turns.get(key, {})
	if not known.is_empty(): return known.checked.duplicate(true)
	var started := Time.get_ticks_usec()
	var checked: Dictionary = Registry.simulation_script(chapter).verify_recording(Registry.definition(chapter), recording, checkpoint, prior)
	_note_check_time(Time.get_ticks_usec() - started, recording, prior)
	_remember_turn(key, checked, {})
	return checked


## engine.derive_checkpoint for a second turn from `origin`, made once per
## exact inputs, like _checked_turn.
func _derived_checkpoint(origin: Dictionary, recording: Dictionary) -> Dictionary:
	var chapter := Registry.resolve(origin)
	var prior: Dictionary = origin.recording_a if origin.get("recording_a") is Dictionary else {}
	var known: Dictionary = _proven_turns.get(_turn_key(chapter, origin.checkpoint, prior, recording), {})
	if not known.get("derived", {}).is_empty(): return known.derived.duplicate(true)
	var derived: Dictionary = Registry.simulation_script(chapter).derive_checkpoint(Registry.definition(chapter), origin.checkpoint, origin.recording_a, recording)
	if not known.is_empty() and derived.get("valid", false): known.derived = derived.duplicate(true)
	return derived


## Every input a turn check reads: the chapter, its starting checkpoint, the
## partner's first turn ({} for none) and the turn, each by its whole content.
static func _turn_key(chapter: String, checkpoint: Dictionary, prior: Dictionary, recording: Dictionary) -> String:
	return "|".join(PackedStringArray([chapter, Canonical.digest(checkpoint), Canonical.digest(prior), Canonical.digest(recording)]))


func _remember_turn(key: String, checked: Dictionary, derived: Dictionary) -> void:
	if not checked.get("valid", false): return
	_proven_turns.erase(key)
	_proven_turns[key] = {"checked": checked.duplicate(true), "derived": derived.duplicate(true) if derived.get("valid", false) else {}}
	while _proven_turns.size() > PROVEN_TURNS: _proven_turns.erase(_proven_turns.keys()[0])


func _note_check_time(usec: int, recording: Dictionary, prior: Dictionary) -> void:
	_last_check_usec = usec
	_last_check_ticks = int(recording.get("duration_ticks", 0)) + int(prior.get("duration_ticks", 0))


## A turn's replay check from this room's snapshot, and for a second turn the
## checkpoint after it, for a worker (run_turn_check): relay_preview starts it
## when the turn ends, and commit() runs it when nothing has. {} when it is made
## already, or when the turn is not this player's to save here (the checks that
## follow then say why). The job holds private copies only.
func turn_check_job(recording: Dictionary) -> Dictionary:
	if not _guard() or read_only or _state.auth_required or _state.snapshot.is_empty() or recording.is_empty(): return {}
	var origin: Dictionary = _state.snapshot
	if not _bounded(recording) or not Typed.equal(origin.active_player_id, _owner) or not Typed.equal(recording.get("role"), origin.active_role) or Typed.equal(origin.active_role, "complete"): return {}
	var chapter := Registry.resolve(origin)
	if chapter.is_empty() or not Typed.equal(recording.get("simulation_version"), origin.get("simulation_version", Registry.definition(chapter).simulation_version)): return {}
	var prior: Dictionary = origin.recording_a if origin.recording_a is Dictionary else {}
	var key := _turn_key(chapter, origin.checkpoint, prior, recording)
	var second: bool = recording.role == "b"
	var known: Dictionary = _proven_turns.get(key, {})
	if not known.is_empty() and (not second or not known.derived.is_empty()): return {}
	# The checkpoint's proofs are remembered across threads (the room's proof memo).
	Proofs.prepare_memo(chapter)
	return {"key": key, "family": Registry.simulation_script(chapter), "level": Registry.definition(chapter), "checkpoint": origin.checkpoint.duplicate(true),
		"prior": prior.duplicate(true), "recording": recording.duplicate(true), "second": second}


## The static worker that runs turn_check_job()'s job.
func turn_check_runner() -> Callable:
	return Callable(get_script(), "run_turn_check")


## The worker: the same verify_recording, and derive_checkpoint for a second
## turn, that this coordinator's checks make. Reads only the job.
static func run_turn_check(job: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var family: Script = job.family
	var checked: Dictionary = family.verify_recording(job.level, job.recording, job.checkpoint, job.prior)
	var derived: Dictionary = {}
	if job.second and checked.get("valid", false) and checked.get("snapshot", {}).get("can_commit", false):
		derived = family.derive_checkpoint(job.level, job.checkpoint, job.prior, job.recording)
	return {"checked": checked, "derived": derived, "usec": Time.get_ticks_usec() - started}


## Keeps a worker's check while the room still stands where its job was made
## (a failed one is never kept). True when it does stand there.
func adopt_turn_check(job: Dictionary, result: Dictionary) -> bool:
	if job.is_empty() or not result.get("checked") is Dictionary or not _guard() or _state.snapshot.is_empty(): return false
	var origin: Dictionary = _state.snapshot
	var prior: Dictionary = origin.recording_a if origin.recording_a is Dictionary else {}
	if _turn_key(Registry.resolve(origin), origin.checkpoint, prior, job.recording) != str(job.key): return false
	_note_check_time(int(result.get("usec", 0)), job.recording, prior)
	_remember_turn(str(job.key), result.checked, result.get("derived", {}) if result.get("derived") is Dictionary else {})
	return true


## The check relay_preview's review shows for `recording` from this room's
## snapshot: the same verify_recording it made before, made once.
func verify_turn(recording: Dictionary) -> Dictionary:
	if not _guard() or _state.snapshot.is_empty() or Typed.equal(_state.snapshot.active_role, "complete"): return {"valid": false}
	var origin: Dictionary = _state.snapshot
	return _checked_turn(Registry.resolve(origin), origin.checkpoint, origin.recording_a if origin.recording_a is Dictionary else {}, recording)


## How long checking this turn should take here (the last check's time per
## replayed tick, a second turn replaying its partner's too).
func expected_check_usec(recording: Dictionary) -> int:
	var prior: Variant = _state.get("snapshot", {}).get("recording_a")
	var ticks := int(recording.get("duration_ticks", 0)) + (int(prior.get("duration_ticks", 0)) if prior is Dictionary and recording.get("role") == "b" else 0)
	if _last_check_ticks > 0: return int(float(_last_check_usec) / _last_check_ticks * ticks)
	return ticks * CHECK_USEC_PER_TICK


func _valid_recording(recording: Variant, origin: Dictionary) -> bool:
	return bool(_verify_recording(recording, origin).get("valid", false))


func _valid_pending(value: Variant) -> bool:
	if not value is Dictionary or not _exact(value, ["operation", "body", "request_hash", "origin", "held", "error_code"]) or value.operation not in ["turns", "fork"] or not value.held is bool or not value.error_code is String or value.error_code.length() > 80 or not value.body is Dictionary or not _valid_snapshot(value.origin):
		return false
	var body: Dictionary = value.body
	var keys := ["base_revision", "idempotency_key", "branch", "recording"] if value.operation == "turns" else ["base_revision", "idempotency_key", "branch", "stage_index"]
	if Typed.equal(value.operation, "turns") and body.get("recording") is Dictionary and Typed.equal(body.recording.get("role"), "b"):
		keys.append("checkpoint")
	if not _exact(body, keys) or not _token(body.idempotency_key, -1, 80) or body.idempotency_key.length() < 16 or not Typed.equal(body.base_revision, value.origin.revision) or not Typed.equal(body.branch, value.origin.branch) or not Typed.equal(value.request_hash, _request_hash(value.operation, body)):
		return false
	if value.operation == "fork":
		return RoomStages.within(body.stage_index, Registry.definition(Registry.resolve(value.origin))) and body.stage_index <= value.origin.stage_index and (body.stage_index < value.origin.stage_index or value.origin.a_turn_id != null)
	var checked := _verify_recording(body.recording, value.origin)
	if not checked.valid or not checked.get("snapshot", {}).get("can_commit", false):
		return false
	if body.recording.role == "a":
		return true
	var derived: Dictionary = _derived_checkpoint(value.origin, body.recording)
	return derived.valid and Typed.same(derived.get("checkpoint", {}), body.checkpoint)


func _valid_receipt(value: Variant, request: Dictionary) -> bool:
	if not value is Dictionary or not _exact(value, RECEIPT_KEYS) or not Typed.equal(value.schema_version, 2) or not Typed.equal(value.room_id, _room) or not Typed.equal(value.idempotency_key, request.body.idempotency_key) or not Typed.equal(value.request_hash, request.request_hash) or not Typed.equal(value.operation, request.operation) or not Typed.equal(value.accepted_revision, int(request.body.base_revision) + 1):
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
		if not Typed.equal(value.turn_id, "t%d-%d-%s" % [branch, index, recording.role]) or not Typed.equal(value.recording_hash, recording.recording_hash) or not Typed.equal(value.pair_id, ("p%d-%d" % [branch, index] if recording.role == "b" else null)):
			return false
		if recording.role == "b":
			expected_checkpoint = request.body.checkpoint.checkpoint_hash
	return Typed.equal(value.branch, branch) and Typed.equal(value.stage_index, index) and Typed.equal(value.stage_id, Registry.definition(Registry.resolve(request.origin)).stages[index].id) and Typed.equal(value.checkpoint_hash, expected_checkpoint)


func _same_context(first: Dictionary, second: Dictionary) -> bool:
	for name: String in ["room_id", "branch", "stage_id", "definition_hash", "simulation_version", "active_role", "active_player_id"]:
		if first.get(name) != second.get(name):
			return false
	return Typed.same(first.checkpoint, second.checkpoint) and Typed.same(first.recording_a, second.recording_a)


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
	finish_live_draft_save()
	_live_simulation = null
	_live_context = {}


func _verify_saved_draft() -> bool:
	if _draft_replay_verified or _state.draft.is_empty():
		return true
	if not _valid_draft(_state.draft):
		return _hold("invalid_saved_rehearsal", PlayerCopy.RELAY_ROOM_COORDINATOR_2ACABC11D0D5)
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
	return _bounded_nodes(value, bytes, 140000)


static func _pair_bounded(value: Variant) -> bool:
	return _bounded_nodes(value, MAX_PAIR_BYTES, MAX_PAIR_NODES)


static func _journal_bounded(value: Variant) -> bool:
	# Four retained drafts, one current draft and an unresolved B submission may
	# each include the same native proof. Comfort journals need more nodes; the
	# widest Turn of the Tide one is about 451k values and 4.25 MB. A chapter
	# with more stages gets its node cap from its own stage count: the widest
	# six-stage Lighthouse journal (every record in every nested proof widened
	# to 600 one-tick runs; test_lighthouse_v2_room) is about 295k values and
	# 2.85 MB, under its 420k values and the unchanged 8 MiB byte cap. Individual
	# proofs, old journals and the retained count stay fixed.
	var room: Variant = value.get("snapshot") if value is Dictionary else null
	var checkpoint: Variant = room.get("checkpoint") if room is Dictionary else null
	# A room omits its version when it plays its chapter's own pinned rules (9+).
	var chapter := Registry.resolve(room) if room is Dictionary else ""
	var level := Registry.definition(chapter)
	var rules: Variant = room.get("simulation_version", level.get("simulation_version")) if room is Dictionary else null
	var comfort: bool = _range(rules, 8, MAX_SIMULATION_VERSION) and int(rules) in Registry.supported_rules(chapter) and checkpoint is Dictionary and _range(checkpoint.get("schema_version"),6,7)
	return _bounded_nodes(value, MAX_BYTES, COMFORT_JOURNAL_NODES if comfort else journal_nodes(level))

## The node cap of a non-comfort journal for this chapter definition.
static func journal_nodes(level: Dictionary) -> int:
	return JOURNAL_NODES_PER_TWO_STAGES * maxi(2, RoomStages.count(level)) / 2


static func _bounded_nodes(value: Variant, bytes: int, maximum_nodes: int) -> bool:
	var pending: Array = [{"value": value, "depth": 0}]
	var nodes := 0
	while not pending.is_empty():
		var item: Dictionary = pending.pop_back()
		nodes += 1
		if nodes > maximum_nodes or int(item.depth) > 24:
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
		if pending.size() > maximum_nodes:
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

func observe_room_binding() -> Dictionary:
	# Identity only, including during a pending request or a read-only hold.
	# This observation never restores a journal or grants gameplay authority.
	var identity := _current_identity()
	if identity.is_empty() or identity.player_id != _owner or int(identity.epoch) != _epoch or not _token(_room,22): return {}
	return {"owner":_owner,"epoch":_epoch,"room_id":_room}

func observe_state() -> Dictionary:
	# Inspect only already-verified memory. Do not call _guard or replay a draft:
	# readiness must not invalidate, restore, write diagnostics or touch disk.
	if read_only or _busy != 0 or _draft_writer != null or _owner.is_empty() or _state.is_empty() or _state.auth_required: return {}
	var identity := _current_identity()
	if identity.is_empty() or identity.player_id != _owner or int(identity.epoch) != _epoch: return {}
	var saved_draft: Dictionary = {}
	var draft_ready: bool = _state.draft.is_empty() or _draft_replay_verified
	if draft_ready and not _state.draft.is_empty() and _same_context(_state.draft.origin,_state.snapshot):
		saved_draft = _state.draft.recording.duplicate(true)
	return {"snapshot":_state.snapshot.duplicate(true),"draft":saved_draft,
		"draft_ready":draft_ready,"pending":_state.pending.duplicate(true)}

func playback_context() -> Dictionary:
	# Pure observation of already-verified memory. Never restore a journal.
	var binding := observe_room_binding()
	if binding.is_empty() or _state.is_empty() or _state.auth_required or read_only or _remote_hold: return {}
	var room: Dictionary = _state.snapshot
	if room.is_empty(): return {}
	return {"binding":binding,"generation":_generation,
		"room":{"revision":room.revision,"branch":room.branch,"level_id":room.level_id,
			"level_version":room.level_version,"definition_hash":room.definition_hash,
			"simulation_version":room.get("simulation_version",_level.get("simulation_version")),
			"host_id":room.host_id,"guest_id":room.guest_id,"player_slot":room.player_slot,
			"checkpoint_hash":room.checkpoint.checkpoint_hash,
			"recording_hash":room.recording_a.get("recording_hash","") if room.recording_a is Dictionary else ""}}

func verify_room_snapshot(value: Variant) -> bool:
	# A navigation probe can use the complete native validator without accepting
	# a cache generation or changing the visible room.
	return _guard() and not read_only and _valid_snapshot(value)

func accept_room_snapshot(value: Variant) -> bool:
	return _accept_snapshot(value)
