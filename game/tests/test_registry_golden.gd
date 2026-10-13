extends SceneTree
## Golden G1: every persisted or transmitted chapter registry output, per pinned
## chapter, plus the consumers that keep their own copy of the same facts. A
## registry refactor must leave tests/fixtures/golden/registry.json unchanged.
## Regenerate only for an intended change; see tests/golden_support.gd.
const Golden = preload("res://tests/golden_support.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const KeepsakeCatalog = preload("res://services/home_keepsake_catalog.gd")
const ThumbnailCatalog = preload("res://services/chapter_thumbnail_catalog.gd")
const PaidCatalog = preload("res://services/paid_level_catalog.gd")
const SoloReplays = preload("res://services/solo_replay_collection.gd")
const StoryWorld = preload("res://presentation/story_memory_world.gd")
const GOLDEN := "registry.json"
const LIGHTHOUSE := "sleeping-lighthouse@1"
## One mid-chapter and one final checkpoint per chapter, for previous_checkpoint.
const CHECKPOINTS := {
	"first-steps@1": ["first_steps/lift-checkpoint.json", "first_steps/final-checkpoint.json"],
	"relay-isles@2": ["v2/relay-checkpoint.json", "v2/final-checkpoint.json"],
	"high-and-low@1": ["cooperative/upper-path-checkpoint.json", "cooperative/high-and-low-final-checkpoint.json"],
	"rolling-home@1": ["cooperative/weight-of-a-friend-checkpoint.json", "cooperative/rolling-home-final-checkpoint.json"],
	"a-house-for-two@1": ["cooperative/open-the-house-checkpoint.json", "cooperative/a-house-for-two-final-checkpoint.json"],
	"conservatory@1": ["journey/a-light-above-checkpoint.json", "journey/conservatory-final-checkpoint.json"],
	"long-way-home@1": ["journey/the-path-you-leave-checkpoint.json", "journey/long-way-home-final-checkpoint.json"],
	"the-wishing-well@1": ["cooperative/go-on-ahead-checkpoint.json", "cooperative/the-wishing-well-final-checkpoint.json"],
	"long-way-home@2": ["journey/long-way-home-v2-the-path-you-leave-checkpoint.json", "journey/long-way-home-v2-final-checkpoint.json"],
	"turn-of-the-tide@1": ["journey/set-the-tide-checkpoint.json", "journey/turn-of-the-tide-final-checkpoint.json"],
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
	for problem: String in Golden.coverage_problems():
		_check(false, problem)
	_check(Golden.coverage_problems().is_empty(), "Every registered chapter is pinned or explicitly new")
	var value := {"chapters": {}, "shared": _shared()}
	for key: String in Golden.GOLDEN_KEYS:
		if not _check(key in Registry.keys(), "Pinned chapter is registered: " + key): continue
		value.chapters[key] = _chapter(key)
	var result := Golden.check(GOLDEN, value)
	for message: String in result.messages:
		push_error(message)
	_check(result.ok, "Registry outputs match golden " + GOLDEN)
	var repeat := Golden.check(GOLDEN, {"chapters": _repeat_chapters(), "shared": _shared()}) if not Golden.write_mode() else result
	_check(repeat.ok, "A second pass over the registry gives the same golden")
	print("REGISTRY GOLDEN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _repeat_chapters() -> Dictionary:
	var chapters: Dictionary = {}
	for key: String in Golden.GOLDEN_KEYS:
		if key in Registry.keys(): chapters[key] = _chapter(key)
	return chapters

func _chapter(key: String) -> Dictionary:
	var level := Registry.definition(key)
	var descriptor := Registry.descriptor(key)
	_check(not level.is_empty() and not descriptor.is_empty(), "Pinned chapter has a definition and descriptor: " + key)
	var stages: Dictionary = {}
	for stage: Dictionary in level.get("stages", []):
		var shown := Registry.stage_presentation(key, stage)
		stages[str(stage.id)] = {"title": shown.get("title", null), "hint_a": shown.get("hint_a", null), "hint_b": shown.get("hint_b", null),
			"is_authored_stage": Canonical.same(shown, stage), "typed_digest": Golden.typed_digest(shown)}
	var rules: Array = []
	for version: Variant in Registry.supported_rules(key):
		rules.append([version, type_string(typeof(version))])
	var initial := Registry.initial_checkpoint(key)
	var entry := {
		"descriptor": descriptor,
		"definition_digest": Canonical.digest(level),
		"definition_typed_digest": Golden.typed_digest(level),
		"stage_ids": _stage_ids(level),
		"offered_key": Registry.offered_key(key),
		"solo_scene": Registry.solo_scene(key),
		"scene": _scene(Registry.solo_scene(key)),
		"simulation_script": _path(Registry.simulation_script(key)),
		"world_script": _path(Registry.world_script(key)),
		"supported_rules": rules,
		"supported_rules_text": str(Registry.supported_rules(key)),
		"preferred_rules": [Registry.preferred_rules(key), type_string(typeof(Registry.preferred_rules(key)))],
		"initial_checkpoint_hash": str(initial.get("checkpoint_hash", "")),
		"initial_checkpoint_typed_digest": Golden.typed_digest(initial),
		"stage_presentation": stages,
		"is_cooperative": Registry.is_cooperative(key),
		"is_journey": Registry.is_journey(key),
		"previous_checkpoint": _previous(key, initial),
		"resolve": _resolve(key, descriptor),
		"reset_simulation": _reset(key, level, initial),
		"keepsake_local_path": KeepsakeCatalog.local_path(key),
		"keepsake_places": KeepsakeCatalog.chapter_places(key),
		"thumbnail": ThumbnailCatalog.entry(key),
		"solo_replay_stamp": SoloReplays._chapter_stamp(key),
		"story_illustration": key in StoryWorld.KEYS,
		"paid_entry": PaidCatalog.entry(key.get_slice("@", 0)),
	}
	_check(entry.descriptor.get("definition_hash") == entry.definition_digest, "Descriptor hash is the definition digest: " + key)
	_check(Registry.resolve(descriptor) == key, "Exact descriptor resolves to its chapter: " + key)
	return entry

func _stage_ids(level: Dictionary) -> Array:
	var ids: Array = []
	for stage: Dictionary in level.get("stages", []): ids.append(str(stage.id))
	return ids

func _path(script: Script) -> String:
	return script.resource_path if script != null else ""

## The solo scene's root script and chapter key, read without instancing it.
func _scene(path: String) -> Dictionary:
	if path.is_empty() or not ResourceLoader.exists(path): return {"exists": false}
	var packed := load(path) as PackedScene
	if packed == null: return {"exists": true, "packed": false}
	var state := packed.get_state()
	var properties: Dictionary = {}
	for index in range(state.get_node_property_count(0)):
		var value: Variant = state.get_node_property_value(0, index)
		properties[str(state.get_node_property_name(0, index))] = value.resource_path if value is Resource else value
	return {"exists": true, "packed": true, "root_name": str(state.get_node_name(0)), "root_type": str(state.get_node_type(0)), "properties": properties}

func _previous(key: String, initial: Dictionary) -> Dictionary:
	var result := {"initial": Registry.previous_checkpoint(key, initial)}
	var names: Array = CHECKPOINTS.get(key, [])
	_check(names.size() == 2, "Checkpoint fixtures are listed for " + key)
	for index in range(names.size()):
		var checkpoint := Golden.fixture(names[index])
		_check(not checkpoint.is_empty(), "Checkpoint fixture loads: " + str(names[index]))
		var previous := Registry.previous_checkpoint(key, checkpoint)
		result[["mid", "final"][index]] = {"fixture": names[index], "fixture_hash": str(checkpoint.get("checkpoint_hash", "")),
			"previous_hash": str(previous.get("checkpoint_hash", "")), "previous_stage_index": previous.get("stage_index", null),
			"previous_typed_digest": Golden.typed_digest(previous) if not previous.is_empty() else ""}
		_check(not previous.is_empty(), "A real proof names its previous checkpoint: " + key)
	var wrong := {"proof": {"previous_checkpoint": initial, "checkpoint": initial}}
	result["both_fields"] = Golden.typed_digest(Registry.previous_checkpoint(key, wrong))
	result["no_proof"] = Registry.previous_checkpoint(key, {"proof": "x"})
	return result

func _resolve(key: String, descriptor: Dictionary) -> Dictionary:
	var triple := {"level_id": descriptor.get("level_id"), "level_version": descriptor.get("level_version"), "definition_hash": descriptor.get("definition_hash")}
	var floated := triple.duplicate()
	floated.level_version = float(floated.level_version) if floated.level_version != null else null
	var tampered := triple.duplicate()
	tampered.definition_hash = "f".repeat(64)
	var bumped := triple.duplicate()
	bumped.level_version = int(bumped.level_version) + 1 if bumped.level_version != null else null
	return {"descriptor": Registry.resolve(descriptor), "triple": Registry.resolve(triple), "float_version": Registry.resolve(floated),
		"tampered_hash": Registry.resolve(tampered), "other_version": Registry.resolve(bumped)}

## Which rules a fresh reset runs under, with and without a recording's version.
func _reset(key: String, level: Dictionary, initial: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var stage_id := str(level.stages[0].id) if not level.get("stages", []).is_empty() else ""
	var cases := {"default": {}}
	for version: Variant in Registry.supported_rules(key) + [1, 99]:
		cases["recording_%d" % int(version)] = {"simulation_version": version}
	for name: String in cases:
		var engine: Script = Registry.simulation_script(key)
		if engine == null:
			result[name] = "no engine"
			continue
		var sim: RefCounted = engine.new()
		var ok := Registry.reset_simulation(sim, key, level, stage_id, initial, {}, "a", cases[name])
		result[name] = {"ok": ok, "simulation_version": sim.get("simulation_version"), "error": str(sim.get("error")),
			"state_hash": sim.state_hash() if ok else ""}
	return result

func _shared() -> Dictionary:
	return {
		"keys_order": _pinned(Registry.keys()),
		"offered_keys_order": _pinned(Registry.offered_keys()),
		"capabilities": _capabilities(),
		"unknown_key": _unknown("missing-chapter@1"),
		"lighthouse_key": _unknown(LIGHTHOUSE),
		"keepsakes": _keepsakes(),
		"thumbnails": _thumbnails(),
		"paid_levels": _paid_keys(),
		"story_keys": _pinned(StoryWorld.KEYS),
		"solo_replay": {"verifier_version": SoloReplays.VERIFIER_VERSION, "legacy_chapters": SoloReplays.LEGACY_CHAPTERS,
			"legacy_group_stamp": SoloReplays._chapter_stamp(SoloReplays.LEGACY_GROUP), "lighthouse_stamp": SoloReplays._chapter_stamp(SoloReplays.LIGHTHOUSE_KEY),
			"verified_schema": SoloReplays.VERIFIED_SCHEMA, "verified_path": SoloReplays.VERIFIED_PATH},
	}

## Pinned keys in the order the given list holds them; new chapters are ignored.
func _pinned(list: Array) -> Array:
	var result: Array = []
	for key: Variant in list:
		if str(key) in Golden.GOLDEN_KEYS: result.append(str(key))
	return result

## Paid gallery ids, ignoring registered chapters that are not pinned yet. The
## Lighthouse gallery id belongs to the unregistered solo @1 screen, which stays
## pinned while its registry successor is unpinned.
func _paid_keys() -> Array:
	var result: Array = []
	for id: String in PaidCatalog.keys():
		var unpinned := false
		if id == LIGHTHOUSE.get_slice("@", 0):
			result.append(id)
			continue
		for key: String in Registry.keys():
			if key.get_slice("@", 0) == id and key not in Golden.GOLDEN_KEYS: unpinned = true
		if not unpinned: result.append(id)
	return result

func _unknown(key: String) -> Dictionary:
	return {"descriptor": Registry.descriptor(key), "definition": Registry.definition(key), "solo_scene": Registry.solo_scene(key),
		"simulation_script": _path(Registry.simulation_script(key)), "world_script": _path(Registry.world_script(key)),
		"supported_rules": Registry.supported_rules(key), "preferred_rules": Registry.preferred_rules(key),
		"initial_checkpoint": Registry.initial_checkpoint(key), "is_cooperative": Registry.is_cooperative(key), "is_journey": Registry.is_journey(key),
		"previous_checkpoint": Registry.previous_checkpoint(key, Golden.fixture("v2/final-checkpoint.json")),
		"keepsake_local_path": KeepsakeCatalog.local_path(key), "solo_replay_stamp": SoloReplays._chapter_stamp(key)}

func _keepsakes() -> Dictionary:
	var rows: Array = []
	for row: Dictionary in KeepsakeCatalog.all():
		var chapter := str(row.chapter_key)
		if chapter.is_empty() or chapter == KeepsakeCatalog.LIGHTHOUSE or chapter in Golden.GOLDEN_KEYS: rows.append(row)
	var chapters: Array = []
	for key: String in KeepsakeCatalog.CHAPTERS:
		if key == KeepsakeCatalog.LIGHTHOUSE or key in Golden.GOLDEN_KEYS: chapters.append(key)
	return {"chapters": chapters, "rows": rows, "lighthouse_local_path": KeepsakeCatalog.local_path(KeepsakeCatalog.LIGHTHOUSE)}

func _thumbnails() -> Dictionary:
	var keys: Array = []
	var entries: Dictionary = {}
	for key: String in ThumbnailCatalog.keys():
		if key in Registry.keys() and key not in Golden.GOLDEN_KEYS: continue
		keys.append(key)
		entries[key] = ThumbnailCatalog.entry(key)
	return {"keys": keys, "entries": entries}

## Canned service capability answers built only from pinned chapters.
func _capabilities() -> Dictionary:
	var base := _caps()
	var cases: Dictionary = {}
	cases["exact"] = base
	var defaults := base.duplicate(true)
	for item: Dictionary in defaults.chapters:
		item.erase("supported_simulation_versions")
		item.simulation_version = Registry.descriptor(_key_for(item)).simulation_version
	cases["preferred_versions"] = defaults
	var negotiated := base.duplicate(true)
	for item: Dictionary in negotiated.chapters:
		item.supported_simulation_versions = Registry.supported_rules(_key_for(item))
		item.simulation_version = Registry.supported_rules(_key_for(item))[0]
	cases["negotiated_lists"] = negotiated
	var reversed := base.duplicate(true)
	reversed.chapters.reverse()
	cases["reversed_input"] = reversed
	var relay := _only(base, "relay-isles@2")
	var legacy := relay.duplicate(true)
	legacy.chapters[0].erase("simulation_version")
	legacy.chapters[0].erase("recording_version")
	cases["legacy_relay"] = legacy
	var legacy_list := legacy.duplicate(true)
	legacy_list.chapters[0].supported_simulation_versions = [2, 8]
	cases["legacy_relay_negotiated"] = legacy_list
	var partial := legacy.duplicate(true)
	partial.chapters[0].simulation_version = 2
	cases["legacy_relay_partial"] = partial
	var floated := relay.duplicate(true)
	floated.chapters[0].simulation_version = 2.0
	cases["relay_float_version"] = floated
	for invalid: Variant in [null, true, "2", 2.5, 6]:
		var wrong := relay.duplicate(true)
		wrong.chapters[0].simulation_version = invalid
		cases["relay_version_%s_%s" % [type_string(typeof(invalid)), str(invalid)]] = wrong
	var unknown := base.duplicate(true)
	unknown.chapters.append({"level_id": "missing-chapter", "level_version": 1, "definition_hash": "0".repeat(64), "premium": false, "recording_version": 6, "simulation_version": 6})
	cases["unknown_chapter"] = unknown
	var duplicate := base.duplicate(true)
	duplicate.chapters.append(duplicate.chapters[0].duplicate(true))
	cases["duplicate_chapter"] = duplicate
	for key: String in Golden.GOLDEN_KEYS:
		var premium := _only(base, key)
		premium.chapters[0].premium = not premium.chapters[0].premium
		cases["flipped_premium_" + key] = premium
		var recording := _only(base, key)
		recording.chapters[0].recording_version = int(recording.chapters[0].recording_version) + 1
		cases["wrong_recording_version_" + key] = recording
		var older := _only(base, key)
		older.chapters[0].simulation_version = 5
		older.chapters[0].erase("supported_simulation_versions")
		cases["unsupported_version_" + key] = older
	var many := base.duplicate(true)
	while many.chapters.size() < 17: many.chapters.append(many.chapters[0].duplicate(true))
	cases["seventeen_chapters"] = many
	var empty := base.duplicate(true)
	empty.chapters = []
	cases["no_chapters"] = empty
	for field: String in ["api_version", "simulation_version", "recording_version"]:
		var wrong := base.duplicate(true)
		wrong[field] = 3
		cases["top_level_" + field] = wrong
	var list_cases := {"empty_list": [], "too_long": [2, 4, 5, 6, 7, 8, 9, 10, 11], "repeated": [8, 8], "missing_selected": [8], "float_entries": [4.0, 5.0]}
	for name: String in list_cases:
		var first := _only(base, "first-steps@1")
		first.chapters[0].supported_simulation_versions = list_cases[name]
		cases["first_steps_list_" + name] = first
	var outputs: Dictionary = {}
	for name: String in cases:
		outputs[name] = Registry.supported_capabilities(cases[name])
	return outputs

func _caps() -> Dictionary:
	var chapters: Array = []
	for key: String in Golden.GOLDEN_KEYS:
		var d := Registry.descriptor(key)
		var item := {"level_id": d.level_id, "level_version": d.level_version, "definition_hash": d.definition_hash,
			"premium": d.premium, "recording_version": d.recording_version, "simulation_version": d.simulation_version}
		if key == "first-steps@1":
			item.simulation_version = 4
			item["supported_simulation_versions"] = [4, 5]
		chapters.append(item)
	return {"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true,
		"validation": "structural_client_replay_required", "chapters": chapters}

func _only(base: Dictionary, key: String) -> Dictionary:
	var copy := base.duplicate(true)
	copy.chapters = []
	for item: Dictionary in base.chapters:
		if _key_for(item) == key: copy.chapters.append(item.duplicate(true))
	return copy

## Two versions of one chapter share a level id, so the version picks the key.
func _key_for(item: Dictionary) -> String:
	for key: String in Golden.GOLDEN_KEYS:
		var d := Registry.descriptor(key)
		if d.level_id == item.level_id and int(d.level_version) == int(item.level_version): return key
	return ""
