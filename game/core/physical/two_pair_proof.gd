extends RefCounted
## Exact, bounded two-pair proof machinery. Each public facade supplies its own
## immutable code identity; packet metadata never selects a factory or catalog.
const Controls = preload("res://core/first_steps/simulation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const TICK_RATE := 30
const MAX_TICKS := 900
const RECORD_KEYS := Controls.RECORD_KEYS
const OUTCOME_KEYS := ["source_ready", "objective_complete"]
const CHECKPOINT_KEYS := ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "mechanisms", "previous_checkpoint_hash", "a_recording_hash", "b_recording_hash", "checkpoint_hash", "proof"]
var _catalog: Script
var _factory: Script
var _version: int
var _schema: int

func _init(catalog: Script, factory: Script, version: int, schema: int = -1) -> void:
	_catalog = catalog
	_factory = factory
	_version = version
	_schema = version if schema < 0 else schema

func stage_by_id(definition: Dictionary, stage_id: String) -> Dictionary:
	for stage: Dictionary in definition.get("stages", []):
		if stage.id == stage_id: return stage.duplicate(true)
	return {}

func expand_recording_inputs(recording: Dictionary) -> Array:
	return Controls.expand_recording_inputs(recording)

func recording_hash(recording: Dictionary) -> String:
	return Controls.recording_hash(recording)

func _other(slot: String) -> String:
	return "p1" if slot == "p0" else "p0"

func verify_recording(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary = {}) -> Dictionary:
	var check := verify_checkpoint(definition, checkpoint)
	return _verify_raw(definition, record, checkpoint, prior_a) if check.valid else check

func _verify_raw(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary) -> Dictionary:
	var reason := recording_error(definition, record, checkpoint)
	if not reason.is_empty(): return _invalid(reason)
	if record.role == "b":
		if prior_a.get("role") != "a" or record.source_recording_hash != prior_a.get("recording_hash", ""): return _invalid("The partner recording does not match.")
		var first_check := _verify_raw(definition, prior_a, checkpoint, {})
		if not first_check.valid or not first_check.snapshot.can_commit: return _invalid("The partner recording is not ready.")
	elif not prior_a.is_empty() or not str(record.source_recording_hash).is_empty(): return _invalid("Unexpected partner recording.")
	var simulation: RefCounted = _factory.new()
	simulation.simulation_version = _version
	simulation.catch_assistance = record.catch_assistance
	simulation._reset_trusted(definition, record.stage_id, checkpoint, prior_a, record.role)
	for input: Dictionary in expand_recording_inputs(record):
		if simulation.finished: return _invalid("The recording continues after the turn ended.")
		simulation.step(input)
	if not Canonical.same(simulation.export_recording(), record): return _invalid("The recording did not replay exactly.")
	return {"valid":true,"error":"","snapshot":simulation.snapshot()}

func recording_error(definition: Dictionary, record: Dictionary, checkpoint: Dictionary) -> String:
	if not _exact_keys(record, RECORD_KEYS): return "Malformed recording."
	for key: String in ["schema_version", "simulation_version", "level_version", "stage_version"]:
		var expected := _version if key == "simulation_version" else _schema if key == "schema_version" else 1
		if not _integer(record[key]) or int(record[key]) != expected: return "Unsupported recording version."
	if record.level_id != definition.get("id") or record.definition_hash != Canonical.digest(definition) or record.checkpoint_hash != checkpoint.get("checkpoint_hash") or record.stage_id != checkpoint.get("next_stage_id"): return "Recording checkpoint mismatch."
	var selected: Dictionary = stage_by_id(definition, str(record.stage_id))
	if selected.is_empty() or record.role not in ["a", "b"]: return "Unknown recording stage."
	if record.player_slot != (selected.first_player_slot if record.role == "a" else _other(selected.first_player_slot)): return "Incorrect player identity."
	var limit := MAX_TICKS + 300 if _version == 8 and record.role == "b" else MAX_TICKS
	if not _integer(record.tick_rate) or int(record.tick_rate) != TICK_RATE or not _integer(record.duration_ticks) or int(record.duration_ticks) < 1 or int(record.duration_ticks) > limit: return "Invalid recording duration."
	if not record.catch_assistance is bool or not record.completed is bool or not record.outcome is Dictionary or not _exact_keys(record.outcome, OUTCOME_KEYS): return "Invalid recording outcome."
	for key: String in OUTCOME_KEYS:
		if not record.outcome[key] is bool: return "Invalid recording outcome."
	if not record.source_recording_hash is String or not _hash(record.final_state_hash) or not _hash(record.recording_hash) or (record.role == "b" and not _hash(record.source_recording_hash)): return "Invalid recording hashes."
	if not record.actions is Array or record.actions.is_empty() or record.actions.size() > limit: return "Invalid action list."
	var total := 0
	for item: Variant in record.actions:
		if not item is Dictionary or not _exact_keys(item, ["ticks", "x", "z", "action"]): return "Unknown action fields."
		if not _integer(item.ticks) or int(item.ticks) < 1 or int(item.ticks) > limit or not _integer(item.x) or not _integer(item.z) or absi(int(item.x)) > 100 or absi(int(item.z)) > 100 or not item.action is bool: return "Invalid action values."
		total += int(item.ticks)
		if total > limit: return "Action duration exceeds the turn."
	if total != int(record.duration_ticks): return "Action duration mismatch."
	if not record.replay_checks is Array or record.replay_checks.is_empty() or record.replay_checks.size() > limit / TICK_RATE + 1: return "Invalid replay checks."
	var last := 0
	for item: Variant in record.replay_checks:
		if not item is Dictionary or not _exact_keys(item, ["tick", "state_hash"]) or not _integer(item.tick) or int(item.tick) <= last or int(item.tick) > total or not _hash(item.state_hash): return "Invalid replay check."
		last = int(item.tick)
	if last != total or recording_hash(record) != record.recording_hash: return "Recording hash mismatch."
	return ""

func verify_checkpoint(definition: Dictionary, checkpoint: Dictionary) -> Dictionary:
	if not _catalog.known(definition): return _invalid("Unknown chapter definition.")
	return _verify_checkpoint(definition, checkpoint, 0)

func _verify_checkpoint(definition: Dictionary, checkpoint: Dictionary, depth: int) -> Dictionary:
	if depth > 2 or not _exact_keys(checkpoint, CHECKPOINT_KEYS) or not _integer(checkpoint.get("stage_index")) or int(checkpoint.stage_index) < 0 or int(checkpoint.stage_index) > definition.stages.size(): return _invalid("Malformed stage checkpoint.")
	if checkpoint.stage_index == 0: return {"valid":true,"error":""} if Canonical.same(checkpoint, _catalog.initial_checkpoint(definition)) else _invalid("The initial checkpoint does not match.")
	if not checkpoint.proof is Dictionary or not _exact_keys(checkpoint.proof, ["checkpoint", "a", "b"]): return _invalid("Missing checkpoint proof.")
	var proof: Dictionary = checkpoint.proof
	if not proof.checkpoint is Dictionary or not proof.a is Dictionary or not proof.b is Dictionary or not _integer(proof.checkpoint.get("stage_index")) or int(proof.checkpoint.stage_index) != int(checkpoint.stage_index) - 1: return _invalid("Invalid checkpoint chain.")
	var prior_check := _verify_checkpoint(definition, proof.checkpoint, depth + 1)
	if not prior_check.valid: return prior_check
	var pair := _verify_pair(definition, proof.checkpoint, proof.a, proof.b)
	if not pair.valid: return pair
	var derived: Dictionary = _build_checkpoint(definition, proof.checkpoint, proof.a, proof.b, pair.snapshot)
	return {"valid":true,"error":""} if Canonical.same(checkpoint, derived) else _invalid("The checkpoint does not match its proof.")

func derive_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	var check := verify_checkpoint(definition, previous)
	if not check.valid: return check
	var pair := _verify_pair(definition, previous, first, second)
	if not pair.valid: return pair
	return {"valid":true,"error":"","checkpoint":_build_checkpoint(definition, previous, first, second, pair.snapshot)}

func _verify_pair(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	if first.get("role") != "a" or second.get("role") != "b": return _invalid("A stage needs both turns in order.")
	var check := _verify_raw(definition, second, previous, first)
	if not check.valid or not check.get("snapshot", {}).get("complete", false): return _invalid("The pair has not completed this stage.")
	return check

func _build_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary, state: Dictionary) -> Dictionary:
	var index := int(previous.stage_index) + 1
	var players: Dictionary = {}
	for slot: String in ["p0", "p1"]:
		players[slot] = {"x":int(state.players[slot].x),"z":int(state.players[slot].z),"height":int(state.players[slot].height),"surface_id":str(state.players[slot].surface_id)}
	var checkpoint := {"schema_version":_schema,"level_id":definition.id,"level_version":definition.version,"definition_hash":Canonical.digest(definition),"stage_index":index,
		"completed_stage_id":str(second.stage_id),"next_stage_id":str(definition.stages[index].id) if index < definition.stages.size() else "","players":players,
		"mechanisms":state.mechanisms.duplicate(true),"previous_checkpoint_hash":previous.checkpoint_hash,"a_recording_hash":first.recording_hash,"b_recording_hash":second.recording_hash,
		"proof":{"checkpoint":previous.duplicate(true),"a":first.duplicate(true),"b":second.duplicate(true)}}
	checkpoint["checkpoint_hash"] = _catalog.checkpoint_hash(checkpoint)
	return checkpoint

func _exact_keys(value: Dictionary, expected: Array) -> bool:
	return Controls._exact_keys(value, expected)

func _integer(value: Variant) -> bool:
	return Controls._integer(value)

func _hash(value: Variant) -> bool:
	return Controls._hash(value)

func _invalid(reason: String) -> Dictionary:
	return {"valid":false,"error":reason}
