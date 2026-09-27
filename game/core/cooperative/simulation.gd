class_name AfterYouCooperativeSimulation
extends "res://core/physical/runtime.gd"
## Published simulation6 facade. Catalog, version, errors and serialized state
## remain pinned here while the implementation is shared with later facades.
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const Proof = preload("res://core/physical/two_pair_proof.gd")
const CURRENT_SIMULATION_VERSION := 6
const COMFORT_VERSION := 8

func reset(definition: Dictionary, stage_id: String, checkpoint: Dictionary, prior_a: Dictionary = {}, current_role: String = "a", rules_version: int = 0) -> bool:
	if rules_version == 0:
		rules_version = _record_version(prior_a) if current_role == "b" else _checkpoint_version(checkpoint)
	if rules_version not in [CURRENT_SIMULATION_VERSION, COMFORT_VERSION]:
		error = "Unsupported recording version."
		return false
	simulation_version = rules_version
	if current_role == "b" and prior_a.get("simulation_version") != rules_version:
		error = "Unsupported recording version."
		return false
	return super.reset(definition, stage_id, checkpoint, prior_a, current_role)

func _new_simulation() -> RefCounted:
	return AfterYouCooperativeSimulation.new()

func _proof_engine() -> RefCounted:
	return _proof(simulation_version)

static func _proof(version: int = CURRENT_SIMULATION_VERSION) -> RefCounted:
	return Proof.new(Catalog, AfterYouCooperativeSimulation, version, CURRENT_SIMULATION_VERSION)

static func _record_version(record: Dictionary) -> int:
	return COMFORT_VERSION if record.get("simulation_version") == COMFORT_VERSION else CURRENT_SIMULATION_VERSION

static func _checkpoint_version(checkpoint: Dictionary) -> int:
	var proof: Variant = checkpoint.get("proof", {})
	return _record_version(proof.get("a", {})) if proof is Dictionary and proof.get("a", {}) is Dictionary else CURRENT_SIMULATION_VERSION

static func verify_recording(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary = {}) -> Dictionary:
	return _proof(_record_version(record)).verify_recording(definition, record, checkpoint, prior_a)

static func _verify_raw(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary) -> Dictionary:
	return _proof(_record_version(record))._verify_raw(definition, record, checkpoint, prior_a)

static func recording_error(definition: Dictionary, record: Dictionary, checkpoint: Dictionary) -> String:
	return _proof(_record_version(record)).recording_error(definition, record, checkpoint)

static func verify_checkpoint(definition: Dictionary, checkpoint: Dictionary) -> Dictionary:
	return _proof(_checkpoint_version(checkpoint)).verify_checkpoint(definition, checkpoint)

static func _verify_checkpoint(definition: Dictionary, checkpoint: Dictionary, depth: int) -> Dictionary:
	return _proof(_checkpoint_version(checkpoint))._verify_checkpoint(definition, checkpoint, depth)

static func derive_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	return _proof(_record_version(first)).derive_checkpoint(definition, previous, first, second)

static func _verify_pair(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	return _proof(_record_version(first))._verify_pair(definition, previous, first, second)

static func _build_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary, state: Dictionary) -> Dictionary:
	return _proof(_record_version(first))._build_checkpoint(definition, previous, first, second, state)

static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	return _proof()._exact_keys(value, expected)

static func _integer(value: Variant) -> bool:
	return _proof()._integer(value)

static func _hash(value: Variant) -> bool:
	return _proof()._hash(value)

static func _invalid(reason: String) -> Dictionary:
	return _proof()._invalid(reason)
