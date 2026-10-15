extends SceneTree
## The chapter descriptors (content/chapters/<chapter>.gd, listed by index.gd)
## and family rows (services/chapter_families.gd) are well formed: required
## fields, known optional ones, resources that exist, a definition that is the
## key's own, stage copy for stages the family shows, and words of its own.
## What the registry gives from them is pinned by tests/fixtures/golden/registry.json.
##
## Until the menu, Home and look tables read the descriptors too, each
## descriptor must also equal what those tables give. The tables also hold
## entries that are not registered chapters (the Sleeping Lighthouse @1, the
## earlier islands, legacy thumbnails). They are pinned below exactly,
## positions included, so moving a reader to the descriptors keeps them.
const Index = preload("res://content/chapters/index.gd")
const Families = preload("res://services/chapter_families.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Golden = preload("res://tests/golden_support.gd")
const Thumbnails = preload("res://services/chapter_thumbnail_catalog.gd")
const Keepsakes = preload("res://services/home_keepsake_catalog.gd")
const Slots = preload("res://presentation/home_keepsake_slots.gd")
const Dressing = preload("res://content/dressing/catalog.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
const ReplayGolden = preload("res://tests/test_replay_golden.gd")
const FingerprintGolden = preload("res://tests/test_world_fingerprint.gd")

## Non-registry entries each table keeps, exactly as today.
const LEGACY_LIGHTHOUSE := "sleeping-lighthouse@1"
## Home's browse order puts the Sleeping Lighthouse @1 third; its @2 is browsed
## under it, so @2 (a version of an unregistered chapter) is not listed itself.
const HOME_LEGACY_POSITION := {LEGACY_LIGHTHOUSE: 2}
const HOME_LEGACY_LOCAL_PATH := {LEGACY_LIGHTHOUSE: "user://lighthouse-journey-v3.json"}
const EARLIER_STAGES := ["first-light", "long-way-home", "patient-garden", "rising-together", "across-the-blue", "lantern-crossing", "two-beats", "after-you"]
const LIGHTHOUSE_STAGES := ["borrowed-light", "missing-piece", "two-promises", "after-the-first-bell", "what-carried-you", "a-welcome-left-on"]
const LEGACY_SCALES := {"earlier": "small", "sleeping-lighthouse": "big"}
const LEGACY_TWEAKS := {"earlier/after-you": {"plinth": 0.56}, "earlier/long-way-home": {"plinth": 0.56}}
const LEGACY_THUMBNAILS := ["legacy-first-light", "legacy-long-way-home", "legacy-patient-garden", "sleeping-lighthouse",
	"legacy-rising-together", "legacy-across-the-blue", "legacy-lantern-crossing", "legacy-two-beats", "legacy-after-you"]
const LEGACY_DRESSING := {LEGACY_LIGHTHOUSE: "res://content/dressing/sleeping_lighthouse.gd"}
const LEGACY_FOLD := [LEGACY_LIGHTHOUSE]
const LEGACY_GOLDEN := {"replay_golden": [LEGACY_LIGHTHOUSE], "world_fingerprint_lighthouse": [LEGACY_LIGHTHOUSE]}
const SCALES := {"small": Slots.SMALL, "big": Slots.BIG}

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

func _same(actual: Variant, expected: Variant, message: String) -> bool:
	return _check(actual == expected, "%s: got %s, descriptor says %s" % [message, JSON.stringify(actual), JSON.stringify(expected)])

## Dictionaries compared by content, whatever their insertion order.
func _same_map(actual: Dictionary, expected: Dictionary, message: String) -> bool:
	return _same(_sorted(actual.keys()), _sorted(expected.keys()), message + " (keys)") and _same(_values(actual), _values(expected), message)

func _values(map: Dictionary) -> Array:
	var result: Array = []
	for key: Variant in _sorted(map.keys()): result.append(map[key])
	return result

func _run() -> void:
	var seen: Dictionary = {}
	for file: Script in Index.CHAPTERS:
		var key := str(file.DATA.get("key", ""))
		_check(not key.is_empty() and not seen.has(key), "Each descriptor has its own key: %s (%s)" % [key, file.resource_path])
		seen[key] = true
		_fields(key, file.DATA)
	_families()
	for key: String in Index.keys():
		_chapter(key, Index.data(key))
	_own_words()
	_offering()
	_home()
	_tables()
	print("CHAPTER DESCRIPTORS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A descriptor file names every required field and only known optional ones
## (index.gd lists both); an optional field it leaves out takes the default.
func _fields(key: String, raw: Dictionary) -> void:
	for field: String in Index.REQUIRED:
		_check(raw.has(field), "Descriptor %s names its required field %s" % [key, field])
	for field: Variant in raw:
		_check(field in Index.REQUIRED or Index.OPTIONAL.has(field), "Descriptor %s has an unknown field %s (a typo, or add it to content/chapters/index.gd)" % [key, field])
		if Index.OPTIONAL.has(field):
			_check(typeof(raw[field]) == typeof(Index.OPTIONAL[field]), "Descriptor %s field %s has the type of its default" % [key, field])

## Every family row names scripts that exist and values the registry knows.
func _families() -> void:
	for name: String in Families.ROWS:
		var family: Dictionary = Families.ROWS[name]
		for path: String in [family.simulation, family.initial[0]]:
			_check(ResourceLoader.exists(path), "Family %s names a script that exists: %s" % [name, path])
		_check(family.checkpoint_field in ["checkpoint", "previous_checkpoint"], "Family %s keeps a known previous checkpoint field" % name)
		_check(family.stage_hud in ["authored", "stage_copy", "native"], "Family %s has a known stage HUD source" % name)
		if family.pinned_rules: _check(load(family.simulation).has_method("pinned_rules"), "Family %s's engine reads pinned rules" % name)
		for field: String in family.checkpoint_copy:
			_check(field in ["checkpoint_title", "checkpoint_text"], "Family %s's copy is checkpoint copy only" % name)
	_same(Families.ROWS["lighthouse-room"].rules, [load("res://core/lighthouse/room_catalog.gd").RULES], "The Lighthouse room family plays its catalog's rules")

func _chapter(key: String, data: Dictionary) -> void:
	var family := Families.row(str(data.get("family")))
	if not _check(not family.is_empty(), "Descriptor names a known family: " + key): return
	for path: String in [data.definition[0], data.world, data.scene, data.thumbnail] + ([data.dressing] if data.dressing != "" else []):
		_check(ResourceLoader.exists(path), "%s names a resource that exists: %s" % [key, path])
	var level := Registry.definition(key)
	_same("%s@%d" % [level.get("id"), int(level.get("version", 0))], key, "The descriptor's definition call gives its own chapter")
	var initial := Registry.initial_checkpoint(key)
	_same([initial.get("level_id"), initial.get("definition_hash")], [level.get("id"), Canonical.digest(level)], "The family's initial checkpoint starts this definition: " + key)
	_check(Registry.world_script(key) != null and Registry.simulation_script(key) != null, "The registry loaded the world and engine of " + key)
	_check(data.local_path.begins_with("user://") and data.local_path.ends_with(".json"), "Solo save path is a user:// JSON file: " + key)
	var stage_ids: Array = []
	for stage: Dictionary in level.stages: stage_ids.append(stage.id)
	for stage_id: String in data.stage_copy:
		_check(stage_id in stage_ids and family.stage_hud == "stage_copy", "Stage copy names a stage its family shows: %s/%s" % [key, stage_id])
		_same(_sorted(data.stage_copy[stage_id].keys()), ["hint_a", "hint_b", "title"], "Stage copy has a title and two hints: %s/%s" % [key, stage_id])
	for field: String in data.copy:
		_check(field in ["title", "summary", "completion", "checkpoint_title", "checkpoint_text"], "Copy field %s of %s is known" % [field, key])
	# Menus and look.
	_same(Thumbnails.path(key), data.thumbnail, "Thumbnail of " + key)
	_same(Dressing.FILES[key].resource_path if Dressing.FILES.has(key) else "", data.dressing, "Dressing of " + key)
	_same(key in IslandWorld.STATIC_FOLD_CHAPTERS, data.fold_static, "Static fold of " + key)
	# Server and goldens.
	_same(data.server.flag is String and data.server.max_branches is int, true, "Server facts are a flag name and a branch cap: " + key)
	_check(key in ReplayGolden.SUITES.get(data.golden.replay, []), "%s is pinned in replay golden suite %s" % [key, data.golden.replay])
	_check(key in FingerprintGolden.SUITES.get(data.golden.fingerprint, []), "%s is pinned in world fingerprint suite %s" % [key, data.golden.fingerprint])

## Read from the registry alone: every chapter shows its own summary. Versions of
## one chapter id may share theirs. A chapter must never quietly show another
## chapter's words.
func _own_words() -> void:
	var seen: Dictionary = {}
	for key: String in Registry.keys():
		var summary := str(Registry.descriptor(key).get("summary", ""))
		_check(not summary.is_empty(), "Chapter has its own summary: " + key)
		var other: String = seen.get(summary, key)
		_check(other.get_slice("@", 0) == key.get_slice("@", 0), "Chapters %s and %s show the same summary" % [other, key])
		seen[summary] = key

func _offering() -> void:
	for key: String in Index.keys():
		var data := Index.data(key)
		_same(key in Golden.GOLDEN_KEYS, data.released, "A released chapter is pinned by the goldens, an unreleased one is not: " + key)
		var version := int(key.get_slice("@", 1))
		if data.version_of != "":
			_check(data.version_of.get_slice("@", 0) == key.get_slice("@", 0) and int(data.version_of.get_slice("@", 1)) < version, "A version is of an earlier version of the same chapter: " + key)
		if data.superseded_by != "":
			_check(data.superseded_by in Index.keys() and data.superseded_by.get_slice("@", 0) == key.get_slice("@", 0) and int(data.superseded_by.get_slice("@", 1)) > version, "A chapter is superseded by a later registered version of itself: " + key)
	# home_keepsake_catalog reads UNRELEASED through load(), not a preload.
	_check(load("res://services/chapter_registry.gd").UNRELEASED is Array, "The registry's UNRELEASED is readable through load()")

## Home: browse order, places, aliases, save paths, slots, sizes and tweaks.
func _home() -> void:
	var chapters: Array = []
	var aliases: Dictionary = {}
	for key: String in Index.keys():
		var data := Index.data(key)
		if data.version_of != "": aliases[key] = data.version_of
		# A version of a chapter Home knows only by its legacy key is browsed under it.
		if data.version_of == "" or data.version_of in Index.keys(): chapters.append(key)
	for legacy: String in HOME_LEGACY_POSITION: chapters.insert(HOME_LEGACY_POSITION[legacy], legacy)
	_same(Keepsakes.CHAPTERS, chapters, "Home browse order (home_keepsake_catalog CHAPTERS)")
	_same_map(Keepsakes.ALIASES, aliases, "Keepsake aliases")
	var rows: Array = []
	var slots: Dictionary = {}
	var scales: Dictionary = {}
	var tweaks: Dictionary = {}
	for stage: String in EARLIER_STAGES: rows.append(["earlier", stage])
	for key: String in chapters:
		if key == LEGACY_LIGHTHOUSE:
			for stage: String in LIGHTHOUSE_STAGES: rows.append([key, stage])
			continue
		var data := Index.data(key)
		var id := key.get_slice("@", 0)
		_same(Keepsakes.local_path(key), data.local_path, "Keepsake save path of " + key)
		if data.keepsake_scale != "": scales[id] = SCALES[data.keepsake_scale]
		_check(data.keepsake_scale != "" or data.keepsakes.is_empty(), "A chapter with its own places has a keepsake size: " + key)
		for place: Dictionary in data.keepsakes:
			rows.append([key, place.stage_id])
			_same(Keepsakes.by_id(id + "/" + place.stage_id).get("title"), place.title, "Keepsake title of %s/%s" % [key, place.stage_id])
			slots[id + "/" + place.stage_id] = place.slot
			if place.has("tweak"): tweaks[id + "/" + place.stage_id] = place.tweak
	for legacy: String in HOME_LEGACY_LOCAL_PATH: _same(Keepsakes.local_path(legacy), HOME_LEGACY_LOCAL_PATH[legacy], "Keepsake save path of " + legacy)
	# A version browsed under a legacy key keeps no save path of its own at Home.
	for key: String in aliases:
		if key not in chapters: _same(Keepsakes.local_path(key), "", "Keepsake save path of " + key)
	var catalog_rows: Array = []
	for row: Array in Keepsakes.ROWS: catalog_rows.append([row[0], row[1]])
	_same(catalog_rows, rows, "Keepsake places in browse order (home_keepsake_catalog ROWS)")
	for legacy: String in LEGACY_SCALES: scales[legacy] = SCALES[LEGACY_SCALES[legacy]]
	_same_map(Slots.CHAPTER_SCALE, scales, "Keepsake sizes (home_keepsake_slots CHAPTER_SCALE)")
	tweaks.merge(LEGACY_TWEAKS)
	_same_map(Slots.TWEAKS, tweaks, "Keepsake tweaks (home_keepsake_slots TWEAKS)")
	for id: String in Slots.SLOTS:
		var family := id.get_slice("/", 0)
		if family == "earlier" or family == "sleeping-lighthouse":
			_check(id.get_slice("/", 1) in (EARLIER_STAGES if family == "earlier" else LIGHTHOUSE_STAGES), "Legacy Home slot is pinned: " + id)
		else:
			_same(Slots.SLOTS[id], slots.get(id), "Home slot " + id)
	_same(Slots.SLOTS.size(), slots.size() + EARLIER_STAGES.size() + LIGHTHOUSE_STAGES.size(), "Home slot count")

## Whole tables: registry keys from descriptors plus the pinned legacy entries.
func _tables() -> void:
	var thumbnails: Array = []
	var dressing: Array = []
	var fold: Array = []
	var replay: Dictionary = {}
	var fingerprint: Dictionary = {}
	for key: String in Index.keys():
		var data := Index.data(key)
		thumbnails.append(key)
		if data.dressing != "": dressing.append(key)
		if data.fold_static: fold.append(key)
		replay[data.golden.replay] = replay.get(data.golden.replay, []) + [key]
		fingerprint[data.golden.fingerprint] = fingerprint.get(data.golden.fingerprint, []) + [key]
	_same(_sorted(Thumbnails.THUMBNAILS.keys()), _sorted(thumbnails + LEGACY_THUMBNAILS), "Thumbnail keys")
	for legacy: String in LEGACY_DRESSING:
		dressing.append(legacy)
		_same(Dressing.FILES[legacy].resource_path, LEGACY_DRESSING[legacy], "Dressing of " + legacy)
	_same(_sorted(Dressing.FILES.keys()), _sorted(dressing), "Dressing keys")
	_same(_sorted(IslandWorld.STATIC_FOLD_CHAPTERS), _sorted(fold + LEGACY_FOLD), "Static fold chapters")
	for suites: Array in [[ReplayGolden.SUITES, replay], [FingerprintGolden.SUITES, fingerprint]]:
		for suite: String in suites[0]:
			var expected: Array = suites[1].get(suite, []) + LEGACY_GOLDEN.get(suite, [])
			_same(_sorted(suites[0][suite]), _sorted(expected), "Golden suite " + suite)

func _sorted(values: Array) -> Array:
	var result := values.duplicate()
	result.sort()
	return result
