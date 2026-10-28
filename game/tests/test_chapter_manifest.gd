extends SceneTree
## The chapter manifest: one row per registered chapter with the facts the
## server must agree on, written from the registry and the chapter descriptors into
## tests/fixtures/golden/chapter_manifest.json. backend/test/chapter-manifest.test.ts
## checks every server chapter against the same file, so a chapter whose game
## and server facts drift apart fails CI on both sides instead of quietly
## dropping out of Play with a friend. Regenerate like any golden
## (tests/golden_support.gd) when a chapter is added or a server fact changes.
const Golden = preload("res://tests/golden_support.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Index = preload("res://content/chapters/index.gd")
const Families = preload("res://services/chapter_families.gd")
const HardMode = preload("res://services/hard_mode.gd")
const GOLDEN := "chapter_manifest.json"
## A chapter's fixtures are <family fixture_dir>/<level_id>[-v<version>]-definition.json
## and -initial-checkpoint.json; these chapters predate that naming.
const FIXTURE_OVERRIDES := {
	"relay-isles@2": ["v2/definition.json", "v2/initial-checkpoint.json"],
	"first-steps@1": ["first_steps/definition.json", "first_steps/initial-checkpoint.json"],
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
	var result := Golden.check(GOLDEN, {"keys": Registry.keys(), "chapters": chapters})
	for message: String in result.messages:
		push_error(message)
	_check(result.ok, "Chapter manifest matches golden " + GOLDEN)
	print("CHAPTER MANIFEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _row(key: String) -> Dictionary:
	var level := Registry.definition(key)
	var descriptor := Registry.descriptor(key)
	var initial := Registry.initial_checkpoint(key)
	# The chapter's descriptor holds its family and server facts.
	var data := Index.data(key)
	_check(not data.is_empty(), "Registered chapter has a descriptor in content/chapters/index.gd: " + key)
	var kind := str(data.get("family", ""))
	# No default: a chapter without server facts must fail here, never fall back
	# to "" (always creatable) and go live on the next deploy.
	var server: Variant = data.get("server")
	if not _check(server is Dictionary and server.get("flag") is String and server.get("max_branches") is int, "Descriptor names its server flag and branch cap: " + key):
		server = {"flag": "<missing>", "max_branches": -1}
	_check((server.flag == "") == (key == Registry.RELAY), "Only Relay is always creatable; give %s its own server flag (default \"false\"), got \"%s\"" % [key, server.flag])
	var fixtures := _fixtures(key, kind, level)
	_check(Canonical.digest(Golden.fixture(fixtures[0])) == descriptor.definition_hash, "Definition fixture %s is the registry definition of %s" % [fixtures[0], key])
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
		## Whether the game offers Hard on it: the server's Every Hard list (backend/src/pollen/earned.ts) is pinned to these.
		"hard": HardMode.eligible(key),
		"definition_fixture": fixtures[0],
		"initial_fixture": fixtures[1],
	}

func _fixtures(key: String, kind: String, level: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if FIXTURE_OVERRIDES.has(key):
		result.assign(FIXTURE_OVERRIDES[key])
	else:
		var stem := "%s/%s%s" % [Families.row(kind).get("fixture_dir", ""), level.id, "" if int(level.version) == 1 else "-v%d" % int(level.version)]
		result.assign([stem + "-definition.json", stem + "-initial-checkpoint.json"])
	for path: String in result:
		_check(FileAccess.file_exists("res://tests/fixtures/" + path), "Fixture named in the manifest exists: %s (%s)" % [path, key])
	return result
