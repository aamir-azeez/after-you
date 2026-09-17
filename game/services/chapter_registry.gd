extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Executable chapter choices are bundled here, never supplied by a server.
const Canonical = preload("res://core/v2/canonical.gd")
const RelayCatalog = preload("res://core/v2/stage_catalog.gd")
const RelaySimulation = preload("res://core/v2/simulation_v2.gd")
const RelayWorld = preload("res://presentation/relay_world.gd")
const FirstCatalog = preload("res://core/first_steps/stage_catalog.gd")
const FirstSimulation = preload("res://core/first_steps/simulation.gd")
const FirstWorld = preload("res://presentation/first_steps_world.gd")
const RELAY := "relay-isles@2"
const FIRST_STEPS := "first-steps@1"

static func keys() -> Array[String]:
	return [FIRST_STEPS, RELAY]

static func definition(key: String) -> Dictionary:
	match key:
		RELAY: return RelayCatalog.relay_isles()
		FIRST_STEPS: return FirstCatalog.definition()
	return {}

static func descriptor(key: String) -> Dictionary:
	var level := definition(key)
	if level.is_empty(): return {}
	return {"key": key, "level_id": level.id, "level_version": level.version,
		"definition_hash": Canonical.digest(level), "title": level.title, "premium": false,
		"simulation_version": level.simulation_version, "recording_version": level.schema_version,
		"stage_count": level.stages.size(), "local_path": "user://relay-journey-v2.json" if key == RELAY else "user://first-steps-journey-v1.json",
		"summary": PlayerCopy.CHAPTER_REGISTRY_49A82D1B1B0C if key == FIRST_STEPS else PlayerCopy.CHAPTER_REGISTRY_F78F85CE3DE5,
		"checkpoint_title": PlayerCopy.CHAPTER_REGISTRY_6C521D717CA5 if key == FIRST_STEPS else PlayerCopy.CHAPTER_REGISTRY_94722E207A11,
		"checkpoint_text": PlayerCopy.CHAPTER_REGISTRY_DA6530899780 if key == FIRST_STEPS else PlayerCopy.CHAPTER_REGISTRY_2ED96CFB54FE,
		"completion_text": PlayerCopy.CHAPTER_REGISTRY_6DF48F693FD6 if key == FIRST_STEPS else PlayerCopy.CHAPTER_REGISTRY_E73948E6FDBC}

static func resolve(value: Variant) -> String:
	if not value is Dictionary or not value.get("level_id") is String or not value.get("definition_hash") is String or not _integer(value.get("level_version")):
		return ""
	for key: String in keys():
		var known := descriptor(key)
		if value.level_id == known.level_id and value.level_version == known.level_version and value.definition_hash == known.definition_hash:
			return key
	return ""

static func simulation_script(key: String) -> Script:
	match key:
		RELAY: return RelaySimulation
		FIRST_STEPS: return FirstSimulation
	return null

static func world_script(key: String) -> Script:
	match key:
		RELAY: return RelayWorld
		FIRST_STEPS: return FirstWorld
	return null

static func initial_checkpoint(key: String) -> Dictionary:
	match key:
		RELAY: return RelayCatalog.initial_checkpoint(RelayCatalog.relay_isles())
		FIRST_STEPS: return FirstCatalog.initial_checkpoint()
	return {}

static func previous_checkpoint(key: String, checkpoint: Dictionary) -> Dictionary:
	# The caller must first replay-verify the checkpoint with this exact engine.
	var proof: Variant = checkpoint.get("proof")
	if not proof is Dictionary: return {}
	var field := "previous_checkpoint" if key == RELAY else "checkpoint" if key == FIRST_STEPS else ""
	var previous: Variant = proof.get(field)
	return previous.duplicate(true) if previous is Dictionary else {}

static func supported_capabilities(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("api_version") != 2 or value.get("simulation_version") != 2 or value.get("recording_version") != 2 or not value.get("mutations_enabled") is bool or value.get("validation") != "structural_client_replay_required" or not value.get("chapters") is Array or value.chapters.size() > 16:
		return {"valid": false, "chapters": [], "error": PlayerCopy.CHAPTER_REGISTRY_F13B5AC3829B}
	var found: Dictionary = {}
	for item: Variant in value.chapters:
		var key := resolve(item)
		if key.is_empty(): continue # Unknown chapters are not executable choices.
		if found.has(key):
			return {"valid": false, "chapters": [], "error": PlayerCopy.CHAPTER_REGISTRY_11371699AFFA}
		var known := descriptor(key)
		var old_relay: bool = key == RELAY and not item.has("simulation_version") and not item.has("recording_version")
		if item.get("premium") != false or (not old_relay and (item.get("simulation_version") != known.simulation_version or item.get("recording_version") != known.recording_version)):
			return {"valid": false, "chapters": [], "error": PlayerCopy.CHAPTER_REGISTRY_6FD55BE1E08F}
		found[key] = known
	var supported: Array[Dictionary] = []
	for key: String in keys():
		if found.has(key): supported.append(found[key].duplicate(true))
	return {"valid": true, "chapters": supported, "error": ""}

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
