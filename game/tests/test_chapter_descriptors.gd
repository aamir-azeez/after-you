extends SceneTree
## The chapter descriptors (content/chapters/<chapter>.gd, listed by index.gd)
## and family rows (services/chapter_families.gd) are well formed: required
## fields, known optional ones, resources that exist, a definition that is the
## key's own, stage copy and keepsakes for stages the chapter has, words of its
## own, and sounds that exist. What the registry, thumbnails and keepsake
## catalog give from them is pinned by tests/fixtures/golden/registry.json;
## dressing and folding by the world fingerprints; sounds by the sound_map and
## sound_trace goldens.
##
## A released chapter fails here when it is not in GOLDEN_KEYS, when it shows
## the placeholder thumbnail or "TODO copy" text that scripts/new_chapter.py
## writes, and when an earlier version of it names no superseded_by.
##
## The menu, Home, look and sound tables also hold entries that are not
## registered chapters (the Sleeping Lighthouse @1, the earlier islands, Home,
## legacy thumbnails). They are pinned below exactly, positions included.
const Index = preload("res://content/chapters/index.gd")
const Families = preload("res://services/chapter_families.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Golden = preload("res://tests/golden_support.gd")
const Thumbnails = preload("res://services/chapter_thumbnail_catalog.gd")
const Keepsakes = preload("res://services/home_keepsake_catalog.gd")
const Dressing = preload("res://content/dressing/catalog.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
const SoundCues = preload("res://services/sound_cues.gd")
const Props = preload("res://presentation/kit/props.gd")

const LEGACY_LIGHTHOUSE := "sleeping-lighthouse@1"
## The placeholder thumbnail scripts/new_chapter.py gives a new chapter
## (scripts/chapter_templates/placeholder-thumbnail.png) and its placeholder text.
const PLACEHOLDER_THUMBNAIL_SHA256 := "95cdc9db8d5a28b39303e4fc0533f6f97f9a05e1472c967577703b9b704adb67"
const PLACEHOLDER_COPY := "TODO copy"
const EARLIER_STAGES := ["first-light", "long-way-home", "patient-garden", "rising-together", "across-the-blue", "lantern-crossing", "two-beats", "after-you"]
const LIGHTHOUSE_STAGES := ["borrowed-light", "missing-piece", "two-promises", "after-the-first-bell", "what-carried-you", "a-welcome-left-on"]
const LEGACY_THUMBNAILS := ["legacy-first-light", "legacy-long-way-home", "legacy-patient-garden", "sleeping-lighthouse",
	"legacy-rising-together", "legacy-across-the-blue", "legacy-lantern-crossing", "legacy-two-beats", "legacy-after-you"]

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
		_check(family.get("catch_assistance") is bool, "Family %s says whether catch assistance applies" % name)
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
	# Proofs check a definition with the family catalog's own known() and its
	# KEYS (core/<family>/stage_catalog.gd), not the descriptor: a chapter that
	# is not registered there too shows in the menus but fails every proof.
	var catalog: Script = load(family.initial[0])
	if catalog.has_method("known"):
		_check(catalog.known(level), "The family catalog %s knows %s's definition (add it to that catalog's definition() match)" % [family.initial[0], key])
	if catalog.get_script_constant_map().has("KEYS"):
		_check(key in catalog.KEYS, "The family catalog %s lists %s in KEYS" % [family.initial[0], key])
	var initial := Registry.initial_checkpoint(key)
	_same([initial.get("level_id"), initial.get("definition_hash")], [level.get("id"), Canonical.digest(level)], "The family's initial checkpoint starts this definition: " + key)
	_check(Registry.world_script(key) != null and Registry.simulation_script(key) != null, "The registry loaded the world and engine of " + key)
	_check(data.local_path.begins_with("user://") and data.local_path.ends_with(".json"), "Solo save path is a user:// JSON file: " + key)
	var stage_ids: Array = []
	for stage: Dictionary in level.stages: stage_ids.append(stage.id)
	_check(data.turn_intro.size() <= stage_ids.size() and data.turn_intro.all(func(text: Variant) -> bool: return text is String), "Turn intro is text for stages the chapter has: " + key)
	for stage_id: String in data.stage_copy:
		_check(stage_id in stage_ids and family.stage_hud == "stage_copy", "Stage copy names a stage its family shows: %s/%s" % [key, stage_id])
		_same(_sorted(data.stage_copy[stage_id].keys()), ["hint_a", "hint_b", "title"], "Stage copy has a title and two hints: %s/%s" % [key, stage_id])
	for field: String in data.copy:
		_check(field in ["title", "summary", "completion", "checkpoint_title", "checkpoint_text"], "Copy field %s of %s is known" % [field, key])
	for place: Dictionary in data.keepsakes:
		_same(_sorted(place.keys()), ["stage_id", "title"], "Keepsake place fields of " + key)
		_check(place.get("stage_id") in stage_ids, "Keepsake place names a stage of its chapter: %s/%s" % [key, place.get("stage_id")])
	_check(data.version_of == "" or data.keepsakes.is_empty(), "A version earns its earlier version's places, not its own: " + key)
	_sounds(key, data, level)
	_seats(key, data, level)

## The chapter's own cues and beds are sounds of services/sound_cues.gd, and each
## water control is a selector of every stage that has it, with the levels as
## its values.
func _sounds(key: String, data: Dictionary, level: Dictionary) -> void:
	for moment: String in data.sound_cues:
		_check(SoundCues.CUES.has(data.sound_cues[moment]), "Sound cue %s of %s/%s is a cue in services/sound_cues.gd" % [data.sound_cues[moment], key, moment])
	for loop: Variant in data.beds:
		_check(SoundCues.LOOPS.has(loop), "Bed %s of %s is a loop in services/sound_cues.gd" % [loop, key])
	for id: String in data.water_levels:
		var levels: Variant = data.water_levels[id]
		var found := 0
		for stage: Dictionary in level.stages:
			for control: Dictionary in stage.get("controls", []):
				if control.get("id") != id: continue
				found += 1
				_check(control.get("kind") == "selector", "Water control %s of %s/%s is a selector" % [id, key, stage.id])
				_same(_sorted(control.get("values", [])), _sorted(levels) if levels is Array else levels, "Selector values of %s/%s/%s are its water levels" % [key, stage.id, id])
		_check(found > 0, "Water control %s of %s is a control in its definition" % [id, key])

## Each seat is a pad of a stage, as a prop the kit builds.
func _seats(key: String, data: Dictionary, level: Dictionary) -> void:
	var pads: Dictionary = {}
	for stage: Dictionary in level.stages:
		for pad: Dictionary in stage.get("pressure_pads", []): pads[str(pad.id)] = true
	for id: String in data.seats:
		_check(pads.has(id), "Seat %s of %s is a pressure pad" % [id, key])
		_check(Props.extent(data.seats[id]).height > 0.05 and not data.seats[id].has("at"), "Seat %s of %s is a prop the kit builds, placed by its pad" % [id, key])

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
		if data.released: _finished(key, data)
	# home_keepsake_catalog reads UNRELEASED through load(), not a preload.
	_check(load("res://services/chapter_registry.gd").UNRELEASED is Array, "The registry's UNRELEASED is readable through load()")

## Fails a released chapter that shows the placeholder thumbnail, has "TODO
## copy" anywhere in its descriptor or hashed definition, or has an earlier
## version still offered (no superseded_by).
func _finished(key: String, data: Dictionary) -> void:
	_check(FileAccess.get_sha256(data.thumbnail) != PLACEHOLDER_THUMBNAIL_SHA256, "Released chapter %s still shows the placeholder thumbnail %s" % [key, data.thumbnail])
	var words := JSON.stringify(data) + JSON.stringify(Registry.definition(key))
	_check(PLACEHOLDER_COPY not in words, "Released chapter %s still has \"%s\" placeholder text" % [key, PLACEHOLDER_COPY])
	for earlier: String in Index.keys():
		if earlier.get_slice("@", 0) == key.get_slice("@", 0) and int(earlier.get_slice("@", 1)) < int(key.get_slice("@", 1)):
			_check(Index.data(earlier).superseded_by != "", "Released chapter %s is offered in place of %s, which names no superseded_by" % [key, earlier])

## Home's entries that are not registered chapters, exactly as before.
func _home() -> void:
	_same(Keepsakes.CHAPTERS.find(LEGACY_LIGHTHOUSE), 2, "Home browses the Sleeping Lighthouse @1 third")
	_check("sleeping-lighthouse@2" not in Keepsakes.CHAPTERS and Keepsakes.ALIASES.get("sleeping-lighthouse@2") == LEGACY_LIGHTHOUSE, "Home browses the Lighthouse @2 under @1")
	_same(Keepsakes.local_path(LEGACY_LIGHTHOUSE), "user://lighthouse-journey-v3.json", "Keepsake save path of the Lighthouse @1")
	_same(Keepsakes.local_path("sleeping-lighthouse@2"), "", "The Lighthouse @2 keeps no Home save path of its own")
	var earlier: Array = []
	var lighthouse: Array = []
	for row: Array in Keepsakes.ROWS:
		if row[0] == "earlier": earlier.append(row[1])
		if row[0] == LEGACY_LIGHTHOUSE: lighthouse.append(row[1])
	_same(earlier, EARLIER_STAGES, "The earlier islands' places")
	_same(Keepsakes.ROWS.slice(0, EARLIER_STAGES.size()).map(func(row: Array) -> String: return row[0]), _repeat("earlier", EARLIER_STAGES.size()), "The earlier islands' places come first")
	_same(lighthouse, LIGHTHOUSE_STAGES, "The Lighthouse @1's places")
	for key: String in Keepsakes.CHAPTERS:
		if key != LEGACY_LIGHTHOUSE: _same(Keepsakes.local_path(key), Index.data(key).local_path, "A browsed chapter's Home save is its solo save: " + key)

## The other tables' entries that are not registered chapters.
func _tables() -> void:
	_same(_sorted(Thumbnails.OTHER_THUMBNAILS.keys()), _sorted(LEGACY_THUMBNAILS), "Thumbnails that are not registered chapters")
	_same(Dressing.OTHER_FILES.keys(), [LEGACY_LIGHTHOUSE], "Dressing that is not a registered chapter's")
	_same(Dressing.FILES[LEGACY_LIGHTHOUSE].resource_path, "res://content/dressing/sleeping_lighthouse.gd", "Dressing of the Lighthouse @1")
	_same(IslandWorld.OTHER_STATIC_FOLD_CHAPTERS, [LEGACY_LIGHTHOUSE], "Folded keys that are not registered chapters")
	_same(SoundCues.BEDS, {LEGACY_LIGHTHOUSE: ["water_far"], "home": ["birds"]}, "Beds that are not a registered chapter's")
	for key: String in Index.keys():
		var data := Index.data(key)
		_same(Thumbnails.path(key), data.thumbnail, "Thumbnail of " + key)
		_same(Dressing.FILES[key].resource_path if Dressing.FILES.has(key) else "", data.dressing, "Dressing of " + key)
		_same(key in IslandWorld.STATIC_FOLD_CHAPTERS, data.fold_static, "Static fold of " + key)

func _repeat(value: Variant, count: int) -> Array:
	var result: Array = []
	for index in range(count): result.append(value)
	return result

func _sorted(values: Array) -> Array:
	var result := values.duplicate()
	result.sort()
	return result
