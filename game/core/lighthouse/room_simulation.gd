extends RefCounted
## sleeping-lighthouse@2 facade over the unchanged schema-3 Lighthouse engine.
## It speaks the shared two-pair contract (reset/_reset_trusted with a room
## checkpoint, the shared 20 record keys, mechanisms in the snapshot) and drives
## AfterYouBorrowedLight with its current physics. borrowed_light.gd and
## stage_catalog.gd are not edited; solo @1 plays exactly as before.
const Native = preload("res://core/lighthouse/borrowed_light.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const Catalog = preload("res://core/lighthouse/room_catalog.gd")
const RoomProof = preload("res://core/lighthouse/room_proof.gd")
const Controls = preload("res://core/first_steps/simulation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
## Inner engine rules. The room record carries the chapter's pinned rules.
const PHYSICS := 5
const TICK_RATE := 30

var simulation_version := Catalog.RULES
var catch_assistance := false
var level: Dictionary = {}
var stage: Dictionary = {}
var role := "a"
var error := ""
var finished := false
var _checkpoint: Dictionary = {}
var _prior: Dictionary = {}
var _inner: RefCounted

static func _proof(_version: int = Catalog.RULES) -> RefCounted:
	return RoomProof.new(load("res://core/lighthouse/room_simulation.gd"))

static func _record_version(_record: Dictionary) -> int:
	return Catalog.RULES

func reset(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior_a: Dictionary = {}, current_role: String = "a", _rules: int = 0) -> bool:
	error = ""
	var check: Dictionary = _proof().verify_checkpoint(definition, checkpoint)
	if not check.valid:
		error = check.error
		return false
	if current_role == "b":
		var first: Dictionary = _proof()._verify_raw(definition, prior_a, checkpoint, {})
		if not first.valid or not first.snapshot.can_commit:
			error = "The partner recording is not ready."
			return false
	_reset_trusted(definition, stage_id, checkpoint, prior_a, current_role)
	return error.is_empty()

func _reset_trusted(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior_a: Dictionary, current_role: String) -> void:
	level = definition
	stage = _proof().stage_by_id(definition, stage_id)
	if stage.is_empty():
		error = "Unknown recording stage."
		return
	_checkpoint = checkpoint
	_prior = prior_a
	role = current_role
	finished = false
	var native_stage := LightCatalog.definition(stage_id)
	var view := native_checkpoint(checkpoint, LightCatalog.STAGE_IDS.find(stage_id))
	var requirement: String = Native._checkpoint_requirements(native_stage, view)
	if not requirement.is_empty():
		error = requirement
		return
	_inner = Native.new()
	_inner.simulation_version = PHYSICS
	_inner._reset_trusted(current_role, native_record(prior_a, checkpoint) if current_role == "b" else {}, view)
	error = str(_inner.error)

## The room checkpoint as the native engine reads it.
static func native_checkpoint(checkpoint: Dictionary, native_index: int) -> Dictionary:
	var players: Dictionary = {}
	for slot: String in ["p0", "p1"]:
		var p: Dictionary = checkpoint.players[slot]
		players[slot] = {"x": int(p.x), "z": int(p.z), "surface_id": str(p.surface_id)}
	return {"stage_index": native_index, "players": players, "mechanisms": checkpoint.mechanisms.duplicate(true), "checkpoint_hash": checkpoint.checkpoint_hash}

## The partner's room record in the native shape the inner ghost replays.
static func native_record(online: Dictionary, checkpoint: Dictionary) -> Dictionary:
	var actions: Array = []
	for run: Dictionary in online.actions:
		actions.append({"ticks": int(run.ticks), "x": int(run.x) / 100, "z": int(run.z) / 100, "action": bool(run.action)})
	var record := {"schema_version": 3, "simulation_version": PHYSICS, "level_id": Catalog.ID, "level_version": 1,
		"stage_id": online.stage_id, "stage_version": 1, "definition_hash": Canonical.digest(LightCatalog.definition(str(online.stage_id))),
		"role": online.role, "player_slot": online.player_slot, "tick_rate": TICK_RATE, "duration_ticks": int(online.duration_ticks), "actions": actions,
		"replay_checks": online.replay_checks.duplicate(true), "completed": online.completed, "final_state_hash": online.final_state_hash,
		"source_recording_hash": ""}
	if online.stage_id != LightCatalog.STAGE_IDS[0]: record["checkpoint_hash"] = checkpoint.checkpoint_hash
	record["recording_hash"] = Native.recording_hash(record)
	return record

func step(input: Dictionary = {}) -> Dictionary:
	if _inner == null or finished or not error.is_empty(): return snapshot()
	_inner.step(input)
	finished = bool(_inner.finished)
	error = str(_inner.error)
	return snapshot()

func context_action() -> Dictionary:
	return _inner.context_action() if _inner != null else {"enabled": false}

func state_hash() -> String:
	return _inner.state_hash() if _inner != null else ""

func snapshot() -> Dictionary:
	if _inner == null: return {"error": error, "can_commit": false, "finished": false, "complete": false}
	var state: Dictionary = _inner.snapshot()
	state["rules_version"] = simulation_version
	state["mechanisms"] = _mechanisms(state)
	state["outcome"] = _outcome(state)
	return state

func _outcome(state: Dictionary) -> Dictionary:
	return {"source_ready": true if role == "b" else bool(state.can_commit), "objective_complete": role == "b" and bool(state.complete)}

## Same accumulation as Native.checkpoint_from_pairs, applied to a room checkpoint.
func _mechanisms(state: Dictionary) -> Dictionary:
	var base: Dictionary = _checkpoint.mechanisms
	var native_stage := LightCatalog.definition(stage.id)
	var latched: Array = base.latched_bridges.duplicate()
	for bridge: Dictionary in native_stage.bridges:
		if state.bridges.get(bridge.id, false) and bridge.id not in latched: latched.append(bridge.id)
	latched.sort()
	var mirrors: Dictionary = base.mirrors.duplicate(true)
	mirrors.merge(state.mirrors, true)
	var props: Dictionary = base.props.duplicate(true)
	props.merge(state.props, true)
	var flags: Dictionary = base.get("flags", {}).duplicate(true)
	var goal: Dictionary = native_stage.get("goal_policy", {})
	if goal.has("checkpoint_flag") and bool(state.complete): flags[goal.checkpoint_flag] = true
	return {"latched_bridges": latched, "mirrors": mirrors, "props": props, "flags": flags}

func export_recording() -> Dictionary:
	if _inner == null: return {}
	var native: Dictionary = _inner.export_recording()
	if native.is_empty(): return {}
	var actions: Array = []
	for run: Dictionary in native.actions:
		actions.append({"ticks": int(run.ticks), "x": int(run.x) * 100, "z": int(run.z) * 100, "action": bool(run.action)})
	var state := snapshot()
	var record := {"schema_version": Catalog.SCHEMA, "simulation_version": simulation_version, "level_id": level.id, "level_version": level.version,
		"definition_hash": Canonical.digest(level), "stage_id": stage.id, "stage_version": 1, "checkpoint_hash": _checkpoint.checkpoint_hash,
		"role": role, "player_slot": native.player_slot, "tick_rate": TICK_RATE, "duration_ticks": native.duration_ticks, "catch_assistance": catch_assistance,
		"actions": actions, "replay_checks": native.replay_checks, "final_state_hash": native.final_state_hash, "completed": native.completed,
		"outcome": _outcome(state), "source_recording_hash": str(_prior.get("recording_hash", ""))}
	record["recording_hash"] = Controls.recording_hash(record)
	return record

static func stage_by_id(definition: Dictionary, stage_id: String) -> Dictionary:
	return _proof().stage_by_id(definition, stage_id)

static func expand_recording_inputs(recording: Dictionary) -> Array:
	return Controls.expand_recording_inputs(recording)

static func verify_recording(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary = {}) -> Dictionary:
	return _proof().verify_recording(definition, record, checkpoint, prior_a)

static func verify_checkpoint(definition: Dictionary, checkpoint: Dictionary) -> Dictionary:
	return _proof().verify_checkpoint(definition, checkpoint)

static func derive_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	return _proof().derive_checkpoint(definition, previous, first, second)

## Coordinator and local-journal surface (relay_room_coordinator, relay_journey).
static func recording_error(definition: Dictionary, record: Dictionary, checkpoint: Dictionary) -> String:
	return _proof().recording_error(definition, record, checkpoint)

static func _verify_raw(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary) -> Dictionary:
	return _proof()._verify_raw(definition, record, checkpoint, prior_a)

static func _build_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary, state: Dictionary) -> Dictionary:
	return _proof()._build_checkpoint(definition, previous, first, second, state)
