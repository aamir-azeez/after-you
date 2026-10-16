extends SceneTree
## long-way-home@1 keeps loading and verifying exactly as published, beside @2.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Copy = preload("res://presentation/player_copy.gd")
const Keepsakes = preload("res://services/home_keepsake_catalog.gd")
const Completion = preload("res://presentation/chapter_completion.gd")
const Thumbnails = preload("res://services/chapter_thumbnail_catalog.gd")
const HASH_V1 := "bce3ddd36386ebb32f011b8d6afe95316992809030ea828b473bbbc3e1c6bb7f"
const HASH_V2 := "4541bd920062e244f202fbe6ee95363a1f53ae5afc490ad600112af9f01a8c77"
const STAGES := ["the-path-you-leave", "a-place-beside-you"]
var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_v1_identity()
	_v1_fixtures()
	_v1_comfort()
	_v1_journal()
	_version_guard()
	_v2_registry()
	_cross_version()
	_v2_journal()
	_v2_keepsakes()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("LONG WAY HOME VERSIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _v1_identity() -> void:
	var level := Catalog.definition("long-way-home@1")
	_check(Canonical.digest(level) == HASH_V1, "@1 definition hash is unchanged")
	_check(Canonical.same(Catalog.definition("long-way-home"), level) and Canonical.same(Registry.definition(Registry.LONG_WAY_HOME), level), "A bare id still names @1")
	_check(Canonical.same(_fixture("journey/long-way-home-definition"), level), "Published @1 definition fixture still matches")
	_check(Canonical.same(_fixture("journey/long-way-home-initial-checkpoint"), Catalog.initial_checkpoint(level)), "Published @1 initial checkpoint still matches")
	var descriptor := Registry.descriptor(Registry.LONG_WAY_HOME)
	_check(Registry.supported_rules(Registry.LONG_WAY_HOME) == [7, 8] and descriptor.simulation_version == 8 and descriptor.level_version == 1, "@1 keeps rules 7 and 8")
	_check(descriptor.local_path == "user://long-way-home-journey-v1.json", "@1 journal path is unchanged")
	_check(Catalog.known(level) and Simulation.pinned_rules(level) == 0, "@1 is known and unpinned")

func _v1_fixtures() -> void:
	var level := Catalog.definition("long-way-home@1")
	var previous := _fixture("journey/long-way-home-initial-checkpoint")
	for stage_id: String in STAGES:
		var a := _fixture("journey/" + stage_id + "-a")
		var b := _fixture("journey/" + stage_id + "-b")
		var expected := _fixture("journey/" + stage_id + "-checkpoint")
		_check(a.simulation_version == 7 and Simulation.verify_recording(level, a, previous).valid, "Published @1 rules 7 source verifies: " + stage_id)
		_check(Simulation.verify_recording(level, b, previous, a).valid, "Published @1 rules 7 receiver verifies: " + stage_id)
		var derived := Simulation.derive_checkpoint(level, previous, a, b)
		_check(derived.valid and Canonical.same(derived.checkpoint, expected), "Published @1 checkpoint derives exactly: " + stage_id)
		_check(Simulation.verify_checkpoint(level, expected).valid, "Published @1 checkpoint verifies: " + stage_id)
		previous = expected
	_check(Canonical.same(previous, _fixture("journey/long-way-home-final-checkpoint")), "Published @1 final checkpoint is the derived chain")
	for name: String in ["changed-window", "corrected-selector", "garden-ending", "closed-return-shutter"]:
		var checkpoint := _fixture("journey/validation/" + name)
		var definition := Catalog.definition(str(checkpoint.level_id))
		_check(Simulation.verify_checkpoint(definition, checkpoint).valid, "Retained validation checkpoint still verifies: " + name)

func _v1_comfort() -> void:
	var level := Catalog.definition("long-way-home@1")
	var bundle: Dictionary = _fixture("comfort8/recordings").get("long-way-home", {})
	var checkpoints: Array = bundle.get("checkpoints", [])
	var pairs: Array = bundle.get("pairs", [])
	_check(checkpoints.size() == 3 and pairs.size() == 2, "Rules 8 @1 evidence is present")
	for index in range(mini(pairs.size(), checkpoints.size() - 1)):
		var pair: Dictionary = pairs[index]
		_check(pair.a.simulation_version == 8 and Simulation.verify_recording(level, pair.b, checkpoints[index], pair.a).valid, "Rules 8 @1 pair verifies: %d" % index)
		var derived := Simulation.derive_checkpoint(level, checkpoints[index], pair.a, pair.b)
		_check(derived.valid and Canonical.same(derived.checkpoint, checkpoints[index + 1]), "Rules 8 @1 checkpoint derives exactly: %d" % index)
	if checkpoints.size() == 3: _check(Simulation.verify_checkpoint(level, checkpoints[2]).valid, "Rules 8 @1 final checkpoint verifies")

func _v1_journal() -> void:
	var bundle: Dictionary = _fixture("comfort8/recordings").get("long-way-home", {})
	var path := "user://lwh-versions-%d.json" % Time.get_ticks_usec()
	paths.append(path)
	var journal := Journey.new(path, null, Registry.LONG_WAY_HOME)
	journal.load_data()
	_check(not journal.read_only and journal.simulation_version() == 8, "A fresh @1 journal still opens under rules 8")
	for pair: Dictionary in bundle.get("pairs", []):
		_check(journal.accept_recording(pair.a) and journal.accept_recording(pair.b), "@1 journal accepts its rules 8 pair " + journal.last_error)
	var reopened := Journey.new(path, null, Registry.LONG_WAY_HOME)
	reopened.load_data()
	_check(not reopened.read_only and reopened.pairs().size() == 2, "A saved @1 journal reloads with both pairs")

func _version_guard() -> void:
	var level := Catalog.definition("long-way-home@1")
	var initial := Catalog.initial_checkpoint(level)
	var renumbered := level.duplicate(true)
	renumbered.version = 2
	_check(not Catalog.known(renumbered) and not Simulation.verify_checkpoint(renumbered, initial).valid, "An @1 body under another version number is unknown")
	var a := _fixture("journey/the-path-you-leave-a")
	var relabelled := a.duplicate(true)
	relabelled.level_version = 2
	relabelled.recording_hash = Simulation.recording_hash(relabelled)
	_check(Simulation.recording_error(level, relabelled, initial) == "Unsupported recording version.", "A record naming another level version is refused")
	var nine := a.duplicate(true)
	nine.simulation_version = 9
	nine.recording_hash = Simulation.recording_hash(nine)
	_check(not Simulation.verify_recording(level, nine, initial).valid, "@1 refuses rules 9 records")
	_check(not Simulation.new().reset(level, STAGES[0], initial, {}, "a", 9), "@1 refuses a rules 9 turn")
	_check(Simulation.new().reset(level, STAGES[0], initial, {}, "a", 7) and Simulation.new().reset(level, STAGES[0], initial, {}, "a", 8), "@1 still starts rules 7 and 8 turns")

func _v2_registry() -> void:
	var v1 := Registry.descriptor(Registry.LONG_WAY_HOME)
	var v2 := Registry.descriptor(Registry.LONG_WAY_HOME_V2)
	_check(Registry.keys().has(Registry.LONG_WAY_HOME) and Registry.keys().has(Registry.LONG_WAY_HOME_V2), "Both versions stay loadable")
	_check(not Registry.offered_keys().has(Registry.LONG_WAY_HOME) and Registry.offered_keys().has(Registry.LONG_WAY_HOME_V2) and Registry.offered_key(Registry.LONG_WAY_HOME) == Registry.LONG_WAY_HOME_V2, "Only @2 is offered; @1 maps to it")
	_check(v2.level_id == "long-way-home" and v2.level_version == 2 and v2.simulation_version == 9 and Registry.supported_rules(Registry.LONG_WAY_HOME_V2) == [9], "@2 is version 2 and plays only rules 9")
	_check(v2.local_path == "user://long-way-home-journey-v2.json" and v2.local_path != v1.local_path, "@2 keeps its own journal")
	_check(v2.premium and v2.title == v1.title and v2.stage_count == 2 and v2.definition_hash == HASH_V2, "@2 is the same paid chapter under its own pinned hash")
	_check(Canonical.same(_fixture("journey/long-way-home-v2-definition"), Catalog.definition("long-way-home@2")) and Canonical.same(_fixture("journey/long-way-home-v2-initial-checkpoint"), Registry.initial_checkpoint(Registry.LONG_WAY_HOME_V2)), "@2 contract fixtures match the bundled definition")
	_check(Registry.resolve(v1) == Registry.LONG_WAY_HOME and Registry.resolve(v2) == Registry.LONG_WAY_HOME_V2, "Each version resolves to its own key")
	_check(Registry.is_journey(Registry.LONG_WAY_HOME_V2) and Registry.simulation_script(Registry.LONG_WAY_HOME_V2) == Simulation and Registry.world_script(Registry.LONG_WAY_HOME_V2) != Registry.world_script(Registry.LONG_WAY_HOME), "@2 shares the engine and has its own world")
	_check(ResourceLoader.exists(Registry.solo_scene(Registry.LONG_WAY_HOME_V2)) and Registry.solo_scene(Registry.LONG_WAY_HOME_V2) != Registry.solo_scene(Registry.LONG_WAY_HOME), "@2 has its own scene")
	var level := Catalog.definition("long-way-home@2")
	var old := Catalog.definition("long-way-home@1")
	_check(Canonical.same(level.stages[0], old.stages[0]) and Canonical.same(level.islands, old.islands) and Canonical.same(level.bridges, old.bridges) and Canonical.same(level.stairs, old.stairs) and Canonical.same(level.drops, old.drops) and Canonical.same(level.starts, old.starts), "@2 keeps the house and stage one")
	_check(Canonical.same(Registry.stage_presentation(Registry.LONG_WAY_HOME_V2, level.stages[0]), Registry.stage_presentation(Registry.LONG_WAY_HOME, old.stages[0])), "Stage one reads the same in both versions")
	var place := Registry.stage_presentation(Registry.LONG_WAY_HOME_V2, level.stages[1])
	_check(place.hint_a == Copy.LONG_WAY_HOME_V2_PLACE_HINT_A and place.hint_b == Copy.LONG_WAY_HOME_V2_PLACE_HINT_B and place.hint_a == level.stages[1].hint_a and place.hint_b == level.stages[1].hint_b, "@2 finale shows its own hints")

func _cross_version() -> void:
	var v1 := Catalog.definition("long-way-home@1")
	var v2 := Catalog.definition("long-way-home@2")
	var initial_v2 := Catalog.initial_checkpoint(v2)
	_check(Simulation.recording_error(v2, _fixture("journey/the-path-you-leave-a"), initial_v2) != "", "An @1 record is refused by @2")
	var renumbered := v2.duplicate(true)
	renumbered.version = 1
	_check(not Catalog.known(renumbered), "The @2 body under version 1 is unknown")
	var a := Simulation.new()
	_check(a.reset(v2, STAGES[0], initial_v2, {}, "a", 9), "@2 starts a rules 9 turn")
	for _tick in range(20): a.step({"move_x": 1.0})
	var record: Dictionary = a.export_recording()
	_check(record.level_version == 2 and record.simulation_version == 9 and Simulation.recording_error(v2, record, initial_v2) == "", "@2 records name level 2 and rules 9")
	_check(Simulation.recording_error(v1, record, Catalog.initial_checkpoint(v1)) != "", "An @2 record is refused by @1")

func _v2_journal() -> void:
	var path := "user://lwh-versions-v2-%d.json" % Time.get_ticks_usec()
	paths.append(path)
	var journal := Journey.new(path, null, Registry.LONG_WAY_HOME_V2)
	journal.load_data()
	_check(not journal.read_only and journal.simulation_version() == 9, "A fresh @2 journal opens under rules 9")
	var shared := Journey.new(Registry.descriptor(Registry.LONG_WAY_HOME).local_path, null, Registry.LONG_WAY_HOME_V2)
	shared.load_data()
	_check(shared.read_only, "@2 never writes into the @1 journal")

func _v2_keepsakes() -> void:
	var places := Keepsakes.chapter_places(Registry.LONG_WAY_HOME_V2)
	_check(places == Keepsakes.chapter_places(Registry.LONG_WAY_HOME) and places == ["long-way-home/the-path-you-leave", "long-way-home/a-place-beside-you"], "@2 earns the same two places as @1")
	_check(Keepsakes.chapter_place(Registry.LONG_WAY_HOME_V2, "a-place-beside-you") == "long-way-home/a-place-beside-you" and Keepsakes.all().all(func(item: Dictionary) -> bool: return item.chapter_key != Registry.LONG_WAY_HOME_V2), "@2 earns @1's places and adds none of its own")
	_check(Registry.LONG_WAY_HOME_V2 in Keepsakes.CHAPTERS and Keepsakes.local_path(Registry.LONG_WAY_HOME_V2) == Registry.descriptor(Registry.LONG_WAY_HOME_V2).local_path, "Keepsake backfill reads the @2 journal")
	var earned: Array[Dictionary] = []
	for id: String in places: earned.append({"id": id, "solo": true, "friend": false})
	var marks := Completion.chapters(earned)
	_check(marks.get(Registry.LONG_WAY_HOME_V2, {}).get("solo", false) and marks.get(Registry.LONG_WAY_HOME, {}).get("solo", false), "Completing either version marks both cards")
	_check(not Thumbnails.path(Registry.LONG_WAY_HOME_V2).is_empty() and Thumbnails.path(Registry.LONG_WAY_HOME_V2) == Thumbnails.path(Registry.LONG_WAY_HOME), "@2 reuses the chapter thumbnail")

func _fixture(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + name + ".json"))
	return parsed if parsed is Dictionary else {}

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
