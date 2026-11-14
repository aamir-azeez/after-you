extends RefCounted
## Exact, bounded two-pair proof machinery. Each public facade supplies its own
## immutable code identity; packet metadata never selects a factory or catalog.
const Controls = preload("res://core/first_steps/simulation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Runtime = preload("res://core/physical/runtime.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const TICK_RATE := 30
const MAX_TICKS := 900
const COMFORT_VERSION := 8
## A definition declaring rules at or above this number accepts only those rules.
const FIRST_PINNED_VERSION := 9
## A chapter may have more than two stages. A checkpoint nests one proof per
## completed stage, so its depth is bounded by the bundled definition, never by
## the packet. Two-stage chapters keep exactly the old bound of 2.
const MAX_STAGES := 8
const RECORD_KEYS := Controls.RECORD_KEYS
const OUTCOME_KEYS := ["source_ready", "objective_complete"]
const CHECKPOINT_KEYS := ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "mechanisms", "previous_checkpoint_hash", "a_recording_hash", "b_recording_hash", "checkpoint_hash", "proof"]
var _catalog: Script
var _factory: Script
var _version: int
var _schema: int
## Open turns: the turns this proof already replayed, by recording hash, so a
## stage's chain replays each turn once however deep it nests.
var _replayed: Dictionary = {}

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

## `chain`: open turns only, the stage's turns before `prior_a`, oldest first.
func verify_recording(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary = {}, chain: Array = []) -> Dictionary:
	var check := verify_checkpoint(definition, checkpoint)
	return _verify_raw(definition, record, checkpoint, prior_a, chain) if check.valid else check

## A turn replayed over its memory (`prior_a`, which replays over `chain`).
## "ready": whether it may be a memory: a first turn that can be saved, or an
## open turns pass that waited out its own memory and did not finish the stage.
func _verify_raw(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary, chain: Array = []) -> Dictionary:
	var reason := recording_error(definition, record, checkpoint)
	if not reason.is_empty(): return _invalid(reason)
	var open := OpenTurns.rules(_version)
	if record.role == "b":
		if prior_a.get("role") != ("a" if chain.is_empty() else "b") or (not chain.is_empty() and not open) or record.source_recording_hash != prior_a.get("recording_hash", ""): return _invalid("The partner recording does not match.")
		var turn := chain.size() + 2
		var selected := stage_by_id(definition, str(record.stage_id))
		if open and (record.player_slot != OpenTurns.slot(str(selected.first_player_slot), turn) or turn > OpenTurns.cap(selected) or int(record.duration_ticks) < int(prior_a.get("duration_ticks", 0))): return _invalid("Incorrect player identity.")
		var first_check := _replayed_turn(definition, prior_a, checkpoint, chain)
		if not first_check.valid or not first_check.ready: return _invalid("The partner recording is not ready.")
	elif not prior_a.is_empty() or not chain.is_empty() or not str(record.source_recording_hash).is_empty(): return _invalid("Unexpected partner recording.")
	var simulation: RefCounted = _factory.new()
	simulation.simulation_version = _version
	simulation.catch_assistance = record.catch_assistance
	# Only open turns pass a chain: other facades (the Lighthouse room's) keep five arguments.
	if chain.is_empty(): simulation._reset_trusted(definition, record.stage_id, checkpoint, prior_a, record.role)
	else: simulation._reset_trusted(definition, record.stage_id, checkpoint, prior_a, record.role, chain)
	for input: Dictionary in expand_recording_inputs(record):
		if simulation.finished: return _invalid("The recording continues after the turn ended.")
		simulation.step(input)
	if not Canonical.same(simulation.export_recording(), record): return _invalid("The recording did not replay exactly.")
	var state: Dictionary = simulation.snapshot()
	var ready: bool = state.can_commit if record.role == "a" else open and not state.complete and int(record.duration_ticks) >= int(prior_a.get("duration_ticks", 0))
	return {"valid":true,"error":"","snapshot":state,"ready":ready}

## _verify_raw once per recording hash in this proof (open turns chains).
func _replayed_turn(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, chain: Array) -> Dictionary:
	var key := "%s|%s|%d" % [str(record.get("recording_hash", "")), str(checkpoint.get("checkpoint_hash", "")), chain.size()]
	if not _replayed.has(key): _replayed[key] = _verify_raw(definition, record, checkpoint, chain.back() if not chain.is_empty() else {}, chain.slice(0, maxi(0, chain.size() - 1)))
	return _replayed[key]

func recording_error(definition: Dictionary, record: Dictionary, checkpoint: Dictionary) -> String:
	if not _exact_keys(record, RECORD_KEYS): return "Malformed recording."
	for key: String in ["schema_version", "simulation_version", "level_version", "stage_version"]:
		var expected := _version if key == "simulation_version" else _schema if key == "schema_version" else _level_version(definition) if key == "level_version" else 1
		if not _integer(record[key]) or int(record[key]) != expected: return "Unsupported recording version."
	if not _rules_fit(definition): return "Unsupported recording version."
	if record.level_id != definition.get("id") or record.definition_hash != Canonical.digest(definition) or record.checkpoint_hash != checkpoint.get("checkpoint_hash") or record.stage_id != checkpoint.get("next_stage_id"): return "Recording checkpoint mismatch."
	var selected: Dictionary = stage_by_id(definition, str(record.stage_id))
	if selected.is_empty() or record.role not in ["a", "b"]: return "Unknown recording stage."
	# Open turns: a later turn is either pip's, as its place in the stage says (_verify_raw checks it).
	var open := OpenTurns.rules(_version)
	if record.player_slot != (selected.first_player_slot if record.role == "a" else _other(selected.first_player_slot)) and not (open and record.role == "b" and record.player_slot in ["p0", "p1"]): return "Incorrect player identity."
	var limit: int = Runtime.turn_ticks(definition, _version, "b" if open else str(record.role))
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

## A chapter id can carry more than one version; a record names exactly one.
func _level_version(definition: Dictionary) -> int:
	var declared: Variant = definition.get("version")
	return int(declared) if _integer(declared) and int(declared) >= 1 else -1

func _rules_fit(definition: Dictionary) -> bool:
	var declared: Variant = definition.get("simulation_version")
	var pinned := int(declared) if (declared is int or declared is float) and int(declared) >= FIRST_PINNED_VERSION else 0
	return (_version == pinned if pinned > 0 else _version < FIRST_PINNED_VERSION) and Runtime.turn_limits_valid(definition, _version)

func verify_checkpoint(definition: Dictionary, checkpoint: Dictionary) -> Dictionary:
	if not _catalog.known(definition): return _invalid("Unknown chapter definition.")
	return _verify_checkpoint(definition, checkpoint, 0)

func _verify_checkpoint(definition: Dictionary, checkpoint: Dictionary, depth: int) -> Dictionary:
	# Open turns nest every turn of a stage (schema 8, open_turns.gd); published checkpoints nest a and b.
	var open := OpenTurns.rules(_version)
	if depth > clampi(definition.stages.size(), 2, MAX_STAGES) or not _integer(checkpoint.get("stage_index")) or int(checkpoint.stage_index) < 0 or int(checkpoint.stage_index) > definition.stages.size(): return _invalid("Malformed stage checkpoint.")
	if checkpoint.stage_index == 0: return {"valid":true,"error":""} if Canonical.same(checkpoint, _catalog.initial_checkpoint(definition)) else _invalid("The initial checkpoint does not match.")
	if not _exact_keys(checkpoint, OpenTurns.CHECKPOINT_KEYS if open else CHECKPOINT_KEYS): return _invalid("Malformed stage checkpoint.")
	if not checkpoint.proof is Dictionary or not _exact_keys(checkpoint.proof, ["checkpoint", "turns"] if open else ["checkpoint", "a", "b"]): return _invalid("Missing checkpoint proof.")
	var proof: Dictionary = checkpoint.proof
	var turns: Array = proof.turns if open and proof.turns is Array else [proof.get("a"), proof.get("b")]
	if not proof.checkpoint is Dictionary or turns.size() < 2 or turns.any(func(turn: Variant) -> bool: return not turn is Dictionary) or not _integer(proof.checkpoint.get("stage_index")) or int(proof.checkpoint.stage_index) != int(checkpoint.stage_index) - 1: return _invalid("Invalid checkpoint chain.")
	var prior_check := _verify_checkpoint(definition, proof.checkpoint, depth + 1)
	if not prior_check.valid: return prior_check
	var pair := _verify_turns(definition, proof.checkpoint, turns)
	if not pair.valid: return pair
	var derived: Dictionary = _build_checkpoint(definition, proof.checkpoint, turns[0], turns[-1], pair.snapshot, turns.slice(1, turns.size() - 1))
	return {"valid":true,"error":""} if Canonical.same(checkpoint, derived) else _invalid("The checkpoint does not match its proof.")

## `passes`: open turns only, the stage's turns between `first` and `second`.
func derive_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary, passes: Array = []) -> Dictionary:
	var check := verify_checkpoint(definition, previous)
	if not check.valid: return check
	var turns: Array = [first] + passes + [second]
	var pair := _verify_turns(definition, previous, turns)
	if not pair.valid: return pair
	return {"valid":true,"error":"","checkpoint":_build_checkpoint(definition, previous, first, second, pair.snapshot, passes)}

## A published stage's two turns (_verify_turns).
func _verify_pair(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	return _verify_turns(definition, previous, [first, second])

## A stage's turns in order: a first turn, then later turns that each replay
## over the one before, the last one completing the stage (only open turns
## have passes between).
func _verify_turns(definition: Dictionary, previous: Dictionary, turns: Array) -> Dictionary:
	if turns.size() < 2 or turns[0].get("role") != "a" or turns.slice(1).any(func(turn: Dictionary) -> bool: return turn.get("role") != "b") or (turns.size() > 2 and not OpenTurns.rules(_version)): return _invalid("A stage needs both turns in order.")
	var check := _verify_raw(definition, turns[-1], previous, turns[-2], turns.slice(0, turns.size() - 2))
	if not check.valid or not check.get("snapshot", {}).get("complete", false): return _invalid("The pair has not completed this stage.")
	return check

## `passes`: open turns only, the stage's turns between `first` and `second`.
func _build_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary, state: Dictionary, passes: Array = []) -> Dictionary:
	var turns: Array = [first] + passes + [second]
	var index := int(previous.stage_index) + 1
	var players: Dictionary = {}
	for slot: String in ["p0", "p1"]:
		players[slot] = {"x":int(state.players[slot].x),"z":int(state.players[slot].z),"height":int(state.players[slot].height),"surface_id":str(state.players[slot].surface_id)}
	var checkpoint := {"schema_version":_schema,"level_id":definition.id,"level_version":definition.version,"definition_hash":Canonical.digest(definition),"stage_index":index,
		"completed_stage_id":str(second.stage_id),"next_stage_id":str(definition.stages[index].id) if index < definition.stages.size() else "","players":players,
		"mechanisms":state.mechanisms.duplicate(true),"previous_checkpoint_hash":previous.checkpoint_hash,"a_recording_hash":first.recording_hash,"b_recording_hash":second.recording_hash,
		"proof":{"checkpoint":previous.duplicate(true),"a":first.duplicate(true),"b":second.duplicate(true)}}
	if OpenTurns.rules(_version):
		# Open turns: every turn of the stage, in order, in place of a and b.
		checkpoint.erase("a_recording_hash")
		checkpoint.erase("b_recording_hash")
		checkpoint.schema_version = OpenTurns.CHECKPOINT_SCHEMA
		checkpoint["turn_hashes"] = turns.map(func(turn: Dictionary) -> String: return str(turn.recording_hash))
		checkpoint.proof = {"checkpoint":previous.duplicate(true),"turns":turns.duplicate(true)}
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
