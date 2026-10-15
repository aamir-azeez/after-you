extends SceneTree
## The chapter manifest: one row per registered chapter with the facts the
## server must agree on, written from the registry into
## tests/fixtures/golden/chapter_manifest.json. backend/test/chapter-manifest.test.ts
## checks every server chapter against the same file, so a chapter whose game
## and server facts drift apart fails CI on both sides instead of quietly
## dropping out of Play with a friend. Regenerate like any golden
## (tests/golden_support.gd) when a chapter is added or a server fact changes.
const Golden = preload("res://tests/golden_support.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const GOLDEN := "chapter_manifest.json"
## Fixture folder per family under tests/fixtures/. A chapter's fixtures are
## named <level_id>[-v<version>]-definition.json and -initial-checkpoint.json.
const FIXTURE_DIRS := {"relay": "v2", "first-steps": "first_steps", "cooperative": "cooperative", "journey": "journey", "lighthouse-room": "lighthouse"}
## Chapters older than that naming: [definition, initial checkpoint], "" = none.
const FIXTURE_OVERRIDES := {
	"relay-isles@2": ["", "v2/initial-checkpoint.json"],
	"first-steps@1": ["first_steps/definition.json", "first_steps/initial-checkpoint.json"],
	"sleeping-lighthouse@2": ["", ""],
}
## Server facts the registry does not hold: the wrangler var gating creation
## ("" = always creatable) and the fork cap (32 = the published default).
const SERVER := {
	"first-steps@1": {"flag": "FIRST_STEPS_ENABLED", "max_branches": 32},
	"relay-isles@2": {"flag": "", "max_branches": 32},
	"high-and-low@1": {"flag": "COOP_CHAPTERS_ENABLED", "max_branches": 32},
	"rolling-home@1": {"flag": "COOP_CHAPTERS_ENABLED", "max_branches": 32},
	"a-house-for-two@1": {"flag": "HOUSE_CHAPTER_ENABLED", "max_branches": 32},
	"conservatory@1": {"flag": "JOURNEY_CHAPTERS_ENABLED", "max_branches": 32},
	"long-way-home@1": {"flag": "JOURNEY_CHAPTERS_ENABLED", "max_branches": 32},
	"the-wishing-well@1": {"flag": "WISHING_WELL_CHAPTER_ENABLED", "max_branches": 32},
	"long-way-home@2": {"flag": "LONG_WAY_HOME_V2_CHAPTER_ENABLED", "max_branches": 32},
	"turn-of-the-tide@1": {"flag": "TURN_OF_THE_TIDE_CHAPTER_ENABLED", "max_branches": 7},
	"sleeping-lighthouse@2": {"flag": "LIGHTHOUSE_V2_CHAPTER_ENABLED", "max_branches": 7},
}
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	var chapters: Dictionary = {}
	for key: String in Registry.keys():
		chapters[key] = _row(key)
	for key: String in SERVER:
		_check(key in Registry.keys(), "Server facts name a registered chapter: " + key)
	var result := Golden.check(GOLDEN, {"keys": Registry.keys(), "chapters": chapters})
	for message: String in result.messages:
		push_error(message)
	_check(result.ok, "Chapter manifest matches golden " + GOLDEN)
	print("CHAPTER MANIFEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

static func family(key: String) -> String:
	if key == Registry.RELAY: return "relay"
	if key == Registry.FIRST_STEPS: return "first-steps"
	if Registry.is_journey(key): return "journey"
	if Registry.is_cooperative(key): return "cooperative"
	if Registry.is_lighthouse(key): return "lighthouse-room"
	return ""

func _row(key: String) -> Dictionary:
	var level := Registry.definition(key)
	var descriptor := Registry.descriptor(key)
	var initial := Registry.initial_checkpoint(key)
	var kind := family(key)
	_check(not kind.is_empty(), "Registered chapter has a family: " + key)
	_check(SERVER.has(key), "Registered chapter has server facts (flag, max_branches) in test_chapter_manifest.gd: " + key)
	var server: Dictionary = SERVER.get(key, {"flag": "", "max_branches": 32})
	var fixtures := _fixtures(key, kind, level)
	if not fixtures[0].is_empty():
		_check(Canonical.digest(Golden.fixture(fixtures[0])) == descriptor.definition_hash, "Definition fixture %s is the registry definition of %s" % [fixtures[0], key])
	if not fixtures[1].is_empty():
		_check(Canonical.same(Golden.fixture(fixtures[1]), initial), "Initial checkpoint fixture %s is the registry's for %s" % [fixtures[1], key])
	var rules: Array = []
	for version: Variant in Registry.supported_rules(key): rules.append(int(version))
	return {
		"key": key,
		"level_id": str(descriptor.level_id),
		"level_version": int(descriptor.level_version),
		"definition_hash": str(descriptor.definition_hash),
		"premium": bool(descriptor.premium),
		"stage_count": int(descriptor.stage_count),
		"family": kind,
		"recording_version": int(descriptor.recording_version),
		"simulation_version": int(level.simulation_version),
		"supported_simulation_versions": rules,
		"initial_checkpoint_hash": str(initial.get("checkpoint_hash", "")),
		"flag": str(server.flag),
		"max_branches": int(server.max_branches),
		"definition_fixture": fixtures[0],
		"initial_fixture": fixtures[1],
	}

func _fixtures(key: String, kind: String, level: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if FIXTURE_OVERRIDES.has(key):
		result.assign(FIXTURE_OVERRIDES[key])
	else:
		var stem := "%s/%s%s" % [FIXTURE_DIRS.get(kind, ""), level.id, "" if int(level.version) == 1 else "-v%d" % int(level.version)]
		result.assign([stem + "-definition.json", stem + "-initial-checkpoint.json"])
	for path: String in result:
		if not path.is_empty():
			_check(FileAccess.file_exists("res://tests/fixtures/" + path), "Fixture named in the manifest exists: %s (%s)" % [path, key])
	return result
