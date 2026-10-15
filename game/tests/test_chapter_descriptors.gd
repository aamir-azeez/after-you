extends SceneTree
## Each chapter descriptor (content/chapters/<chapter>.gd) and family row
## (services/chapter_families.gd) equals what today's scattered tables give:
## the registry, the thumbnail, keepsake, Home slot, dressing and fold tables,
## and the golden suite splits. Until the readers move over, a chapter added or
## changed in one place but not the other fails here.
##
## The tables also hold entries that are not registered chapters (the Sleeping
## Lighthouse @1, the earlier islands, legacy thumbnails). They are pinned below
## exactly, positions included, so moving a reader to the descriptors keeps them.
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
const FIELDS := ["key", "family", "definition", "world", "scene", "local_path", "released", "superseded_by", "version_of", "copy",
	"stage_copy", "thumbnail", "keepsake_scale", "keepsakes", "dressing", "fold_static", "server", "golden"]
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
	_same(Index.KEYS, Registry.keys(), "Descriptor index lists the registry's keys in order")
	_same(Index.FILES.keys(), Index.KEYS, "Every indexed key has a descriptor file, in index order")
	for key: String in Index.KEYS:
		_chapter(key, Index.data(key))
	_own_words()
	_offering()
	_home()
	_tables()
	print("CHAPTER DESCRIPTORS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _chapter(key: String, data: Dictionary) -> void:
	var fields := data.keys()
	fields.sort()
	var expected_fields := FIELDS.duplicate()
	expected_fields.sort()
	_same(fields, expected_fields, "Descriptor fields of " + key)
	_same(data.get("key"), key, "Descriptor key")
	var family := Families.row(str(data.get("family")))
	if not _check(not family.is_empty(), "Descriptor names a known family: " + key): return
	for path: String in [data.definition[0], data.world, data.scene, data.thumbnail, family.simulation, family.initial[0]] + ([data.dressing] if data.dressing != "" else []):
		_check(ResourceLoader.exists(path), "%s names a resource that exists: %s" % [key, path])
	# Loading and rules.
	var level: Dictionary = load(data.definition[0]).callv(data.definition[1], data.definition.slice(2))
	var registered := Registry.definition(key)
	_check(Golden.typed_digest(level) == Golden.typed_digest(registered) and Canonical.digest(level) == Canonical.digest(registered), "Descriptor definition call gives the registry's definition: " + key)
	var initial: Dictionary = load(family.initial[0]).initial_checkpoint(level) if family.initial[1] else load(family.initial[0]).initial_checkpoint()
	_check(Golden.typed_digest(initial) == Golden.typed_digest(Registry.initial_checkpoint(key)), "Family initial checkpoint is the registry's: " + key)
	_same(data.scene, Registry.solo_scene(key), "Solo scene of " + key)
	_same(data.world, Registry.world_script(key).resource_path, "World script of " + key)
	_same(family.simulation, Registry.simulation_script(key).resource_path, "Simulation of " + key)
	var rules: Array = family.rules
	if family.pinned_rules:
		var pinned := int(load(family.simulation).pinned_rules(level))
		if pinned > 0: rules = [pinned]
	_same(rules, Registry.supported_rules(key), "Supported rules of " + key)
	_same(family.cooperative, Registry.is_cooperative(key), "is_cooperative of " + key)
	_same(data.family == "journey", Registry.is_journey(key), "is_journey of " + key)
	_same(data.family == "lighthouse-room", Registry.is_lighthouse(key), "is_lighthouse of " + key)
	var proof := {"proof": {"previous_checkpoint": {"field": "previous_checkpoint"}, "checkpoint": {"field": "checkpoint"}}}
	_same(Registry.previous_checkpoint(key, proof).get("field", ""), family.checkpoint_field, "previous_checkpoint field of " + key)
	# Words.
	var shown := Registry.descriptor(key)
	var copy: Dictionary = family.checkpoint_copy.duplicate()
	copy.merge(data.copy, true)
	_same(shown.title, copy.get("title", level.title), "Title of " + key)
	_same(shown.summary, copy.get("summary"), "Summary of " + key)
	_same(shown.completion_text, copy.get("completion"), "Completion text of " + key)
	_same(shown.checkpoint_title, copy.get("checkpoint_title"), "Checkpoint title of " + key)
	_same(shown.checkpoint_text, copy.get("checkpoint_text"), "Checkpoint text of " + key)
	_same(shown.local_path, data.local_path, "Solo save path of " + key)
	var stage_ids: Array = []
	for stage: Dictionary in level.stages:
		stage_ids.append(stage.id)
		var hud := Registry.stage_presentation(key, stage)
		match str(family.stage_hud):
			"native": _same(hud, {"title": str(stage.native.title), "hint_a": str(stage.native.hint_a), "hint_b": str(stage.native.hint_b)}, "Native stage words of %s/%s" % [key, stage.id])
			"stage_copy": _same(hud, data.stage_copy.get(stage.id, stage), "Stage words of %s/%s" % [key, stage.id])
			_: _check(Canonical.same(hud, stage), "Stage words are the authored stage for %s/%s" % [key, stage.id])
	for stage_id: String in data.stage_copy:
		_check(stage_id in stage_ids and family.stage_hud == "stage_copy", "Stage copy names a stage its family shows: %s/%s" % [key, stage_id])
	# Menus and look.
	_same(Thumbnails.path(key), data.thumbnail, "Thumbnail of " + key)
	_same(Dressing.FILES[key].resource_path if Dressing.FILES.has(key) else "", data.dressing, "Dressing of " + key)
	_same(key in IslandWorld.STATIC_FOLD_CHAPTERS, data.fold_static, "Static fold of " + key)
	# Server and goldens.
	_same(data.server.flag is String and data.server.max_branches is int, true, "Server facts are a flag name and a branch cap: " + key)
	_check(key in ReplayGolden.SUITES.get(data.golden.replay, []), "%s is pinned in replay golden suite %s" % [key, data.golden.replay])
	_check(key in FingerprintGolden.SUITES.get(data.golden.fingerprint, []), "%s is pinned in world fingerprint suite %s" % [key, data.golden.fingerprint])

## Read from the registry alone: every chapter shows its own summary. Versions of
## one chapter id may share theirs. A chapter missing from the registry's copy
## table must not quietly show another chapter's words.
func _own_words() -> void:
	var seen: Dictionary = {}
	for key: String in Registry.keys():
		var summary := str(Registry.descriptor(key).get("summary", ""))
		_check(not summary.is_empty(), "Chapter has its own summary: " + key)
		var other: String = seen.get(summary, key)
		_check(other.get_slice("@", 0) == key.get_slice("@", 0), "Chapters %s and %s show the same summary" % [other, key])
		seen[summary] = key

func _offering() -> void:
	var superseded: Dictionary = {}
	var offered: Array[String] = []
	var unreleased: Array[String] = []
	for key: String in Index.KEYS:
		var data := Index.data(key)
		if data.superseded_by != "": superseded[key] = data.superseded_by
		if not data.released: unreleased.append(key)
		if data.released and data.superseded_by == "": offered.append(key)
		_same(key in Golden.GOLDEN_KEYS, data.released, "A released chapter is pinned by the goldens, an unreleased one is not: " + key)
		if data.version_of != "": _check(data.version_of.get_slice("@", 0) == key.get_slice("@", 0), "A version is of the same chapter id: " + key)
	_same_map(Registry.SUPERSEDED, superseded, "SUPERSEDED")
	_same(Registry.UNRELEASED, unreleased, "UNRELEASED")
	_same(Registry.offered_keys(), offered, "Offered keys")

## Home: browse order, places, aliases, save paths, slots, sizes and tweaks.
func _home() -> void:
	var chapters: Array = []
	var aliases: Dictionary = {}
	for key: String in Index.KEYS:
		var data := Index.data(key)
		if data.version_of != "": aliases[key] = data.version_of
		# A version of a chapter Home knows only by its legacy key is browsed under it.
		if data.version_of == "" or data.version_of in Index.KEYS: chapters.append(key)
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
	for key: String in Index.KEYS:
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
