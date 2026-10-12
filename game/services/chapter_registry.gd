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
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const CooperativeSimulation = preload("res://core/cooperative/simulation.gd")
const CooperativeWorld = preload("res://presentation/cooperative_world.gd")
const HouseWorld = preload("res://presentation/house_world.gd")
const JourneyCatalog = preload("res://core/journey/stage_catalog.gd")
const JourneySimulation = preload("res://core/journey/simulation.gd")
const ConservatoryWorld = preload("res://presentation/conservatory_world.gd")
const LongWayHomeWorld = preload("res://presentation/long_way_home_world.gd")
const LongWayHomeV2World = preload("res://presentation/long_way_home_v2_world.gd")
const WishingWellWorld = preload("res://presentation/wishing_well_world.gd")
const TideWorld = preload("res://presentation/tide_world.gd")
const RELAY := "relay-isles@2"
const FIRST_STEPS := "first-steps@1"
const HIGH_AND_LOW := "high-and-low@1"
const ROLLING_HOME := "rolling-home@1"
const HOUSE := "a-house-for-two@1"
const CONSERVATORY := "conservatory@1"
const LONG_WAY_HOME := "long-way-home@1"
const WISHING_WELL := "the-wishing-well@1"
const LONG_WAY_HOME_V2 := "long-way-home@2"
const TURN_OF_THE_TIDE := "turn-of-the-tide@1"

## Superseded key -> the version offered in its place. A superseded key stays
## loadable for saves, replays, rooms and keepsakes; it is only not offered.
const SUPERSEDED := {LONG_WAY_HOME: LONG_WAY_HOME_V2}
## Registered chapters held back from the pickers until they are released. Like
## a superseded key, an unreleased key stays loadable for saves, replays, rooms
## and keepsakes; it is only not offered. Remove a key here to offer it.
const UNRELEASED: Array[String] = [TURN_OF_THE_TIDE]

static func keys() -> Array[String]:
	return [FIRST_STEPS, RELAY, HIGH_AND_LOW, ROLLING_HOME, HOUSE, CONSERVATORY, LONG_WAY_HOME, WISHING_WELL, LONG_WAY_HOME_V2, TURN_OF_THE_TIDE]

## Chapters to start or host. Use keys() for everything that loads.
static func offered_keys() -> Array[String]:
	var result: Array[String] = []
	for key: String in keys():
		if not SUPERSEDED.has(key) and key not in UNRELEASED: result.append(key)
	return result

static func offered_key(key: String) -> String:
	return str(SUPERSEDED.get(key, key))

## The version to host for an offered chapter: the newest loadable version of
## its id, no newer than `key`, that `can_create` accepts. A server that has not
## enabled a new version yet still hosts the previous one. Falls back to `key`.
static func hosting_key(key: String, can_create: Callable) -> String:
	var id := key.get_slice("@", 0)
	var newest := int(key.get_slice("@", 1))
	var best := ""
	var best_version := -1
	for candidate: String in keys():
		if candidate.get_slice("@", 0) != id: continue
		var version := int(candidate.get_slice("@", 1))
		if version > newest or version <= best_version or not can_create.call(candidate): continue
		best = candidate
		best_version = version
	return best if not best.is_empty() else key

static func is_cooperative(key: String) -> bool:
	return key in [HIGH_AND_LOW, ROLLING_HOME, HOUSE, WISHING_WELL] or is_journey(key)

static func is_journey(key: String) -> bool:
	return key in [CONSERVATORY, LONG_WAY_HOME, LONG_WAY_HOME_V2, TURN_OF_THE_TIDE]

static func solo_scene(key: String) -> String:
	match key:
		FIRST_STEPS: return "res://first_steps_preview.tscn"
		RELAY: return "res://relay_preview.tscn"
		HIGH_AND_LOW: return "res://high_and_low.tscn"
		ROLLING_HOME: return "res://rolling_home.tscn"
		HOUSE: return "res://house.tscn"
		CONSERVATORY: return "res://conservatory.tscn"
		LONG_WAY_HOME: return "res://long_way_home.tscn"
		WISHING_WELL: return "res://the_wishing_well.tscn"
		LONG_WAY_HOME_V2: return "res://long_way_home_v2.tscn"
		TURN_OF_THE_TIDE: return "res://turn_of_the_tide.tscn"
	return ""

static func definition(key: String) -> Dictionary:
	match key:
		RELAY: return RelayCatalog.relay_isles()
		FIRST_STEPS: return FirstCatalog.definition()
		HIGH_AND_LOW: return CooperativeCatalog.definition("high-and-low")
		ROLLING_HOME: return CooperativeCatalog.definition("rolling-home")
		HOUSE: return CooperativeCatalog.definition("a-house-for-two")
		WISHING_WELL: return CooperativeCatalog.definition("the-wishing-well")
		CONSERVATORY, LONG_WAY_HOME, LONG_WAY_HOME_V2, TURN_OF_THE_TIDE: return JourneyCatalog.definition(key)
	return {}

static func descriptor(key: String) -> Dictionary:
	var level := definition(key)
	if level.is_empty(): return {}
	if is_cooperative(key):
		var presentation := _physical_presentation(key)
		return {"key": key, "level_id": level.id, "level_version": level.version,
			"definition_hash": Canonical.digest(level), "title": presentation.get("title",level.title), "premium": level.premium,
			"simulation_version": preferred_rules(key), "recording_version": level.schema_version,
			"stage_count": level.stages.size(), "local_path": "user://%s-journey-v%d.json" % [level.id, int(level.version)],
			"summary": presentation.summary,
			"checkpoint_title": "A path kept", "checkpoint_text": PlayerCopy.COOPERATIVE_CHECKPOINT,
			"completion_text": presentation.completion}
	return {"key": key, "level_id": level.id, "level_version": level.version,
		"definition_hash": Canonical.digest(level), "title": level.title, "premium": false,
		"simulation_version": preferred_rules(key), "recording_version": level.schema_version,
		"stage_count": level.stages.size(), "local_path": "user://relay-journey-v2.json" if key == RELAY else "user://first-steps-journey-v1.json",
		"summary": PlayerCopy.CHAPTER_REGISTRY_49A82D1B1B0C if key == FIRST_STEPS else PlayerCopy.CHAPTER_REGISTRY_F78F85CE3DE5,
		"checkpoint_title": PlayerCopy.CHAPTER_REGISTRY_6C521D717CA5 if key == FIRST_STEPS else PlayerCopy.CHAPTER_REGISTRY_94722E207A11,
		"checkpoint_text": PlayerCopy.CHAPTER_REGISTRY_DA6530899780 if key == FIRST_STEPS else PlayerCopy.CHAPTER_REGISTRY_2ED96CFB54FE,
		"completion_text": PlayerCopy.CHAPTER_REGISTRY_6DF48F693FD6 if key == FIRST_STEPS else PlayerCopy.CHAPTER_REGISTRY_E73948E6FDBC}

static func resolve(value: Variant) -> String:
	if not value is Dictionary or not value.get("level_id") is String or not value.get("definition_hash") is String or not _integer(value.get("level_version")):
		return ""
	for key: String in keys():
		if value.level_id != key.get_slice("@", 0):
			continue
		var known := descriptor(key)
		if value.level_id == known.level_id and value.level_version == known.level_version and value.definition_hash == known.definition_hash:
			return key
	return ""

static func simulation_script(key: String) -> Script:
	match key:
		RELAY: return RelaySimulation
		FIRST_STEPS: return FirstSimulation
		HIGH_AND_LOW, ROLLING_HOME, HOUSE, WISHING_WELL: return CooperativeSimulation
		CONSERVATORY, LONG_WAY_HOME, LONG_WAY_HOME_V2, TURN_OF_THE_TIDE: return JourneySimulation
	return null

static func reset_simulation(simulation: RefCounted, key: String, level: Dictionary, stage_id: String, checkpoint: Dictionary, prior: Dictionary, role: String, recording: Dictionary = {}) -> bool:
	if key == FIRST_STEPS or key == RELAY or is_cooperative(key):
		var rules := int(recording.get("simulation_version", prior.get("simulation_version", preferred_rules(key))))
		return simulation.reset(level, stage_id, checkpoint, prior, role, rules)
	return simulation.reset(level, stage_id, checkpoint, prior, role)

static func supported_rules(key: String) -> Array:
	if key == RELAY: return [2, 8]
	if key == FIRST_STEPS: return [4, 5, 8]
	if is_cooperative(key) and not is_journey(key):
		# A chapter pinned to later comfort rules (9+) is playable only under them.
		var pinned := CooperativeSimulation.pinned_rules(definition(key))
		return [pinned] if pinned > 0 else [6, 8]
	if is_journey(key):
		var pinned_journey := JourneySimulation.pinned_rules(definition(key))
		return [pinned_journey] if pinned_journey > 0 else [7, 8]
	return []

static func preferred_rules(key: String) -> int:
	var versions := supported_rules(key)
	return int(versions[-1]) if not versions.is_empty() else -1

static func world_script(key: String) -> Script:
	match key:
		RELAY: return RelayWorld
		FIRST_STEPS: return FirstWorld
		HIGH_AND_LOW, ROLLING_HOME: return CooperativeWorld
		HOUSE: return HouseWorld
		CONSERVATORY: return ConservatoryWorld
		LONG_WAY_HOME: return LongWayHomeWorld
		LONG_WAY_HOME_V2: return LongWayHomeV2World
		WISHING_WELL: return WishingWellWorld
		TURN_OF_THE_TIDE: return TideWorld
	return null

static func initial_checkpoint(key: String) -> Dictionary:
	match key:
		RELAY: return RelayCatalog.initial_checkpoint(RelayCatalog.relay_isles())
		FIRST_STEPS: return FirstCatalog.initial_checkpoint()
		HIGH_AND_LOW, ROLLING_HOME, HOUSE, WISHING_WELL: return CooperativeCatalog.initial_checkpoint(definition(key))
		CONSERVATORY, LONG_WAY_HOME, LONG_WAY_HOME_V2, TURN_OF_THE_TIDE: return JourneyCatalog.initial_checkpoint(definition(key))
	return {}

static func _physical_presentation(key: String) -> Dictionary:
	match key:
		CONSERVATORY: return {"title":PlayerCopy.CONSERVATORY_TITLE,"summary":PlayerCopy.CONSERVATORY_SUMMARY,"completion":PlayerCopy.CONSERVATORY_COMPLETION}
		LONG_WAY_HOME, LONG_WAY_HOME_V2: return {"title":PlayerCopy.LONG_WAY_HOME_TITLE,"summary":PlayerCopy.LONG_WAY_HOME_SUMMARY,"completion":PlayerCopy.LONG_WAY_HOME_COMPLETION}
		HOUSE: return {"summary":PlayerCopy.HOUSE_SUMMARY,"completion":PlayerCopy.HOUSE_COMPLETION}
		HIGH_AND_LOW: return {"summary":PlayerCopy.COOPERATIVE_HIGH_SUMMARY,"completion":PlayerCopy.COOPERATIVE_COMPLETION}
		WISHING_WELL: return {"title":PlayerCopy.WISHING_WELL_TITLE,"summary":PlayerCopy.WISHING_WELL_SUMMARY,"completion":PlayerCopy.WISHING_WELL_COMPLETION}
		TURN_OF_THE_TIDE: return {"title":PlayerCopy.TURN_OF_THE_TIDE_TITLE,"summary":PlayerCopy.TURN_OF_THE_TIDE_SUMMARY,"completion":PlayerCopy.TURN_OF_THE_TIDE_COMPLETION}
	return {"summary":PlayerCopy.COOPERATIVE_ROLLING_SUMMARY,"completion":PlayerCopy.COOPERATIVE_COMPLETION}

static func stage_presentation(key: String, stage: Dictionary) -> Dictionary:
	if key == CONSERVATORY:
		if stage.id == "a-light-above": return {"title":PlayerCopy.CONSERVATORY_ABOVE_TITLE,"hint_a":PlayerCopy.CONSERVATORY_ABOVE_HINT_A,"hint_b":PlayerCopy.CONSERVATORY_ABOVE_HINT_B}
		if stage.id == "the-way-light-returns": return {"title":PlayerCopy.CONSERVATORY_RETURNS_TITLE,"hint_a":PlayerCopy.CONSERVATORY_RETURNS_HINT_A,"hint_b":PlayerCopy.CONSERVATORY_RETURNS_HINT_B}
	elif key in [LONG_WAY_HOME, LONG_WAY_HOME_V2]:
		if stage.id == "the-path-you-leave": return {"title":PlayerCopy.LONG_WAY_HOME_PATH_TITLE,"hint_a":PlayerCopy.LONG_WAY_HOME_PATH_HINT_A,"hint_b":PlayerCopy.LONG_WAY_HOME_PATH_HINT_B}
		if stage.id == "a-place-beside-you" and key == LONG_WAY_HOME_V2: return {"title":PlayerCopy.LONG_WAY_HOME_PLACE_TITLE,"hint_a":PlayerCopy.LONG_WAY_HOME_V2_PLACE_HINT_A,"hint_b":PlayerCopy.LONG_WAY_HOME_V2_PLACE_HINT_B}
		if stage.id == "a-place-beside-you": return {"title":PlayerCopy.LONG_WAY_HOME_PLACE_TITLE,"hint_a":PlayerCopy.LONG_WAY_HOME_PLACE_HINT_A,"hint_b":PlayerCopy.LONG_WAY_HOME_PLACE_HINT_B}
	elif key == TURN_OF_THE_TIDE:
		if stage.id == "set-the-tide": return {"title":PlayerCopy.TURN_OF_THE_TIDE_SET_TITLE,"hint_a":PlayerCopy.TURN_OF_THE_TIDE_SET_HINT_A,"hint_b":PlayerCopy.TURN_OF_THE_TIDE_SET_HINT_B}
		if stage.id == "slack-water": return {"title":PlayerCopy.TURN_OF_THE_TIDE_SLACK_TITLE,"hint_a":PlayerCopy.TURN_OF_THE_TIDE_SLACK_HINT_A,"hint_b":PlayerCopy.TURN_OF_THE_TIDE_SLACK_HINT_B}
	return stage

static func previous_checkpoint(key: String, checkpoint: Dictionary) -> Dictionary:
	# The caller must first replay-verify the checkpoint with this exact engine.
	var proof: Variant = checkpoint.get("proof")
	if not proof is Dictionary: return {}
	var field := "previous_checkpoint" if key == RELAY else "checkpoint" if key == FIRST_STEPS or is_cooperative(key) else ""
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
		var supported_version: bool = _integer(item.get("simulation_version")) and int(item.simulation_version) in supported_rules(key)
		if item.get("premium") != known.premium or (not old_relay and (not supported_version or item.get("recording_version") != known.recording_version)):
			return {"valid": false, "chapters": [], "error": PlayerCopy.CHAPTER_REGISTRY_6FD55BE1E08F}
		# Older clients retain their legacy capability and reject unsupported records.
		# New clients opt into cumulative rules only when this server advertises them.
		known.simulation_version = item.simulation_version if item.has("simulation_version") else definition(key).simulation_version
		if item.has("supported_simulation_versions"):
			var versions: Variant = item.supported_simulation_versions
			if not versions is Array or versions.is_empty() or versions.size() > 8:
				return {"valid": false, "chapters": [], "error": PlayerCopy.CHAPTER_REGISTRY_6FD55BE1E08F}
			var unique: Array = []
			for version: Variant in versions:
				if not _integer(version) or int(version) in unique:
					return {"valid": false, "chapters": [], "error": PlayerCopy.CHAPTER_REGISTRY_6FD55BE1E08F}
				unique.append(int(version))
			if not int(known.simulation_version) in unique:
				return {"valid": false, "chapters": [], "error": PlayerCopy.CHAPTER_REGISTRY_6FD55BE1E08F}
			for version: int in supported_rules(key):
				if version in unique: known.simulation_version = version
		found[key] = known
	var supported: Array[Dictionary] = []
	for key: String in keys():
		if found.has(key): supported.append(found[key].duplicate(true))
	return {"valid": true, "chapters": supported, "error": ""}

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
