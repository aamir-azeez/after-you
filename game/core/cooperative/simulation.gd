class_name AfterYouCooperativeSimulation
extends "res://core/physical/runtime.gd"
## Published simulation6 facade. Catalog, version, errors and serialized state
## remain pinned here while the implementation is shared with later facades.
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const Proof = preload("res://core/physical/two_pair_proof.gd")
const CURRENT_SIMULATION_VERSION := 6

func _new_simulation() -> RefCounted:
	return AfterYouCooperativeSimulation.new()

func _proof_engine() -> RefCounted:
	return _proof()

static func _proof() -> RefCounted:
	return Proof.new(Catalog, AfterYouCooperativeSimulation, CURRENT_SIMULATION_VERSION)

static func verify_recording(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary = {}) -> Dictionary:
	return _proof().verify_recording(definition, record, checkpoint, prior_a)

static func _verify_raw(definition: Dictionary, record: Dictionary, checkpoint: Dictionary, prior_a: Dictionary) -> Dictionary:
	return _proof()._verify_raw(definition, record, checkpoint, prior_a)

static func recording_error(definition: Dictionary, record: Dictionary, checkpoint: Dictionary) -> String:
	return _proof().recording_error(definition, record, checkpoint)

static func verify_checkpoint(definition: Dictionary, checkpoint: Dictionary) -> Dictionary:
	return _proof().verify_checkpoint(definition, checkpoint)

static func _verify_checkpoint(definition: Dictionary, checkpoint: Dictionary, depth: int) -> Dictionary:
	return _proof()._verify_checkpoint(definition, checkpoint, depth)

static func derive_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	return _proof().derive_checkpoint(definition, previous, first, second)

static func _verify_pair(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary) -> Dictionary:
	return _proof()._verify_pair(definition, previous, first, second)

static func _build_checkpoint(definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary, state: Dictionary) -> Dictionary:
	return _proof()._build_checkpoint(definition, previous, first, second, state)

static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	return _proof()._exact_keys(value, expected)

static func _integer(value: Variant) -> bool:
	return _proof()._integer(value)

static func _hash(value: Variant) -> bool:
	return _proof()._hash(value)

static func _invalid(reason: String) -> Dictionary:
	return _proof()._invalid(reason)
