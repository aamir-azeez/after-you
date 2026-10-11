extends SceneTree
## long-way-home@1 keeps loading and verifying exactly as published.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HASH_V1 := "bce3ddd36386ebb32f011b8d6afe95316992809030ea828b473bbbc3e1c6bb7f"
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

func _fixture(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + name + ".json"))
	return parsed if parsed is Dictionary else {}

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
