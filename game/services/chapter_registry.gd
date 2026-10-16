extends RefCounted
## Executable chapter choices are bundled here, never supplied by a server.
## Each chapter is one descriptor file under content/chapters/ (listed in order
## by content/chapters/index.gd) plus its family's row in
## services/chapter_families.gd; every function here reads those.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Index = preload("res://content/chapters/index.gd")
const Families = preload("res://services/chapter_families.gd")
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
## The six Lighthouse stages as one chapter on the shared record and proof format.
const LIGHTHOUSE_V2 := "sleeping-lighthouse@2"

## Every catalog, engine and world script a chapter or family names, loaded
## once when this file loads (when its preloads used to load, so no chapter
## open pays for it) and only read afterwards, so workers need no lock.
static var _scripts: Dictionary = _load_scripts()
## Superseded key -> the version offered in its place (a descriptor's
## superseded_by). A superseded key stays loadable for saves, replays, rooms
## and keepsakes; it is only not offered.
static var SUPERSEDED: Dictionary = _superseded()
## Registered chapters held back from the pickers (a descriptor's released:
## false). Like a superseded key, an unreleased key stays loadable for saves,
## replays, rooms and keepsakes; it is only not offered.
static var UNRELEASED: Array[String] = _unreleased()

static func keys() -> Array[String]:
	return Index.keys()

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
	return bool(_family(key).get("cooperative", false))

static func is_journey(key: String) -> bool:
	return _chapter(key).get("family") == "journey"

## The Lighthouse's facade over its own engine: rules-pinned, its own catalog.
static func is_lighthouse(key: String) -> bool:
	return _chapter(key).get("family") == "lighthouse-room"

static func solo_scene(key: String) -> String:
	return str(_chapter(key).get("scene", ""))

static func definition(key: String) -> Dictionary:
	var source: Array = _chapter(key).get("definition", [])
	if source.is_empty(): return {}
	return _scripts[source[0]].callv(source[1], source.slice(2))

## descriptor() digests the whole bundled definition, up to 8 ms for the
## larger chapters, and a journey load asks for every chapter's. The bundled
## definitions never change while the game runs, so each key is worked out
## once; every caller gets its own copy. Workers call this too, hence the lock.
static var _descriptors: Dictionary = {}
static var _descriptors_lock := Mutex.new()

static func descriptor(key: String) -> Dictionary:
	_descriptors_lock.lock()
	var known: Variant = _descriptors.get(key)
	_descriptors_lock.unlock()
	if known is Dictionary: return known.duplicate(true)
	var made := _descriptor(key)
	_descriptors_lock.lock()
	_descriptors[key] = made.duplicate(true)
	_descriptors_lock.unlock()
	return made

## The descriptor worked out from the definition, never remembered.
static func _descriptor(key: String) -> Dictionary:
	var level := definition(key)
	if level.is_empty(): return {}
	var words := _words(key)
	return {"key": key, "level_id": level.id, "level_version": level.version,
		"definition_hash": Canonical.digest(level), "title": words.get("title", level.title), "premium": level.get("premium", false),
		"simulation_version": preferred_rules(key), "recording_version": level.schema_version,
		"stage_count": level.stages.size(), "local_path": _chapter(key).local_path,
		"summary": words.get("summary", ""),
		"checkpoint_title": words.get("checkpoint_title", ""), "checkpoint_text": words.get("checkpoint_text", ""),
		"completion_text": words.get("completion", "")}

## A chapter's words: its descriptor's copy over its family's checkpoint copy.
static func _words(key: String) -> Dictionary:
	var words: Dictionary = _family(key).get("checkpoint_copy", {}).duplicate()
	words.merge(_chapter(key).get("copy", {}), true)
	# A chapter without its own words must never show another chapter's: debug
	# builds stop here, players see none.
	assert(words.has("summary") and words.has("completion") and words.has("checkpoint_title") and words.has("checkpoint_text"),
		"Chapter %s needs a summary, completion and checkpoint copy in its descriptor or family" % key)
	return words

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
	return _scripts.get(_family(key).get("simulation", ""))

static func reset_simulation(simulation: RefCounted, key: String, level: Dictionary, stage_id: String, checkpoint: Dictionary, prior: Dictionary, role: String, recording: Dictionary = {}) -> bool:
	if not _chapter(key).is_empty(): # Every family's engine takes the rules to play by.
		var rules := int(recording.get("simulation_version", prior.get("simulation_version", preferred_rules(key))))
		return simulation.reset(level, stage_id, checkpoint, prior, role, rules)
	return simulation.reset(level, stage_id, checkpoint, prior, role)

static func supported_rules(key: String) -> Array:
	var family := _family(key)
	if family.is_empty(): return []
	if family.pinned_rules:
		# A chapter pinned to later rules (9+) is playable only under them.
		var pinned: int = simulation_script(key).pinned_rules(definition(key))
		if pinned > 0: return [pinned]
	return family.rules.duplicate()

static func preferred_rules(key: String) -> int:
	var versions := supported_rules(key)
	return int(versions[-1]) if not versions.is_empty() else -1

static func world_script(key: String) -> Script:
	return _scripts.get(_chapter(key).get("world", ""))

static func initial_checkpoint(key: String) -> Dictionary:
	var initial: Array = _family(key).get("initial", [])
	if initial.is_empty(): return {}
	var catalog: Script = _scripts[initial[0]]
	return catalog.initial_checkpoint(definition(key)) if initial[1] else catalog.initial_checkpoint()

static func stage_presentation(key: String, stage: Dictionary) -> Dictionary:
	match stage_hud(key):
		"stage_copy":
			var shown: Variant = _chapter(key).stage_copy.get(stage.get("id"))
			if shown is Dictionary: return shown.duplicate()
		"native":
			# The hashed native stage carries its own title and hints.
			if stage.get("native") is Dictionary:
				return {"title":str(stage.native.title),"hint_a":str(stage.native.hint_a),"hint_b":str(stage.native.hint_b)}
	return stage

static func previous_checkpoint(key: String, checkpoint: Dictionary) -> Dictionary:
	# The caller must first replay-verify the checkpoint with this exact engine.
	var proof: Variant = checkpoint.get("proof")
	if not proof is Dictionary: return {}
	var field := str(_family(key).get("checkpoint_field", ""))
	var previous: Variant = proof.get(field)
	return previous.duplicate(true) if previous is Dictionary else {}

static func supported_capabilities(value: Variant) -> Dictionary:
	# A room-level-2 answer (to X-AfterYou-Room-Level: 2) may list up to 64
	# chapters, names each one's stage count and says how long a join list may be.
	var level_two: bool = value is Dictionary and value.has("room_level")
	if level_two and (not _integer(value.get("room_level")) or int(value.room_level) < 2 or not _integer(value.get("max_join_versions")) or int(value.max_join_versions) < 8 or int(value.max_join_versions) > 64 or not _integer(value.get("max_stages")) or int(value.max_stages) < 2):
		return {"valid": false, "chapters": [], "error": PlayerCopy.CHAPTER_REGISTRY_F13B5AC3829B}
	if not value is Dictionary or value.get("api_version") != 2 or value.get("simulation_version") != 2 or value.get("recording_version") != 2 or not value.get("mutations_enabled") is bool or value.get("validation") != "structural_client_replay_required" or not value.get("chapters") is Array or value.chapters.size() > (64 if level_two else 16):
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
		if item.has("stage_count") and item.get("stage_count") != known.stage_count:
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

## One chapter's descriptor (content/chapters/), {} if it is not registered. Read-only.
static func _chapter(key: String) -> Dictionary:
	return Index.data(key)

## Where in-play stage titles and hints come from (the family's stage_hud):
## "authored", "stage_copy" or "native".
static func stage_hud(key: String) -> String:
	return str(_family(key).get("stage_hud", ""))

## Whether the catch assistance setting applies to the chapter's turns.
static func catch_assistance(key: String) -> bool:
	return bool(_family(key).get("catch_assistance", true))

## The text above a turn's hint at one stage (the descriptor's turn_intro).
static func turn_intro(key: String, stage_index: int) -> String:
	var intro: Array = _chapter(key).get("turn_intro", [])
	return str(intro[stage_index]) if stage_index >= 0 and stage_index < intro.size() else ""

## One chapter's family row (services/chapter_families.gd), {} if unknown. Read-only.
static func _family(key: String) -> Dictionary:
	return Families.row(str(Index.data(key).get("family", "")))

static func _load_scripts() -> Dictionary:
	var result: Dictionary = {}
	for key: String in Index.keys():
		var chapter := Index.data(key)
		var family := Families.row(str(chapter.get("family", "")))
		for path: String in [chapter.definition[0], chapter.world, family.simulation, family.initial[0]]:
			if not result.has(path): result[path] = load(path)
	result.make_read_only()
	return result

static func _superseded() -> Dictionary:
	var result: Dictionary = {}
	for key: String in Index.keys():
		if Index.data(key).superseded_by != "": result[key] = Index.data(key).superseded_by
	result.make_read_only()
	return result

static func _unreleased() -> Array[String]:
	var result: Array[String] = []
	for key: String in Index.keys():
		if not Index.data(key).released: result.append(key)
	result.make_read_only()
	return result
