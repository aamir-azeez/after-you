extends SceneTree
## Save turn on a solo chapter replays the finished turn once. The journey
## checks it from its own proven checkpoint, keeps a successful result for the
## Save that follows, and builds the next checkpoint from that same check.
## Every verdict, snapshot and checkpoint must equal what the public
## verify_recording / derive_checkpoint produce, and the saved journal must
## load back through the full chain check unchanged.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Canonical = preload("res://core/v2/canonical.gd")

class CountingJourney extends "res://services/relay_journey.gd":
	var replays := 0
	func _verify_on_checkpoint(recording: Dictionary) -> Dictionary:
		replays += 1
		return super(recording)

var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = "user://turn-save-checks-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	var covered := 0
	# One chapter per simulation family, each with every stage in fixtures.
	for spec: Dictionary in [
		{"chapter": Registry.FIRST_STEPS, "folder": "first_steps", "rules": 0},
		{"chapter": Registry.RELAY, "folder": "v2", "rules": 2, "names": ["relay", "garden"]},
		{"chapter": Registry.WISHING_WELL, "folder": "cooperative", "rules": 0},
		{"chapter": Registry.TURN_OF_THE_TIDE, "folder": "journey", "rules": 0},
	]:
		if not Registry.keys().has(str(spec.chapter)): continue
		if _chapter(spec): covered += 1
	_check(covered >= 3, "At least three simulation families are covered (%d)" % covered)
	print("TURN SAVE CHECKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _chapter(spec: Dictionary) -> bool:
	var chapter := str(spec.chapter)
	var level := Registry.definition(chapter)
	var family: Script = Registry.simulation_script(chapter)
	var path := directory + "/" + chapter.validate_filename() + ".json"
	var journey := CountingJourney.new(path, null, chapter)
	journey.load_data()
	if int(spec.rules) > 0: journey._state.simulation_version = int(spec.rules)
	var names: Array = spec.get("names", level.stages.map(func(stage: Dictionary) -> String: return str(stage.id)))
	for index in range(names.size()):
		for role: String in ["a", "b"]:
			var recording := _fixture(str(spec.folder) + "/" + str(names[index]) + "-" + role)
			if recording.is_empty():
				_check(false, "%s: fixture %s-%s exists" % [chapter, names[index], role])
				return false
			var start := journey.checkpoint()
			var prior := journey.prior_recording()
			var label := "%s %s/%s" % [chapter, names[index], role]
			var public: Dictionary = family.verify_recording(level, recording, start, prior)
			var trusted: Dictionary = journey._verify_on_checkpoint(recording)
			_check(public.get("valid", false) and trusted.get("valid", false) and Canonical.same(public.snapshot, trusted.snapshot), label + ": the check from the proven checkpoint equals the public check")
			if role == "b":
				var derived: Dictionary = family.derive_checkpoint(level, start, prior, recording)
				var built: Dictionary = journey._next_checkpoint(prior, recording, trusted)
				_check(derived.get("valid", false) and built.get("valid", false) and Canonical.same(derived.checkpoint, built.checkpoint), label + ": the next checkpoint equals derive_checkpoint")
			# A tampered turn fails and is never kept.
			var tampered := recording.duplicate(true)
			tampered.final_state_hash = "0".repeat(64)
			var kept: int = journey._verified_turns.size()
			var before := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
			_check(not journey.verify_turn(tampered).get("valid", true) and journey._verified_turns.size() == kept, label + ": a tampered turn fails and is not remembered")
			_check(not journey.accept_recording(tampered) and (FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()) == before, label + ": a tampered turn is never saved")
			# The real flow: review, then Save turn, replays the turn once.
			journey.replays = 0
			var reviewed: Dictionary = journey.verify_turn(recording)
			var saved: bool = journey.accept_recording(recording)
			_check(reviewed.get("valid", false) and Canonical.same(reviewed.snapshot, public.snapshot), label + ": the review check is the public verdict")
			_check(saved and journey.replays == 1, label + ": review and Save turn replay the turn once (%d)" % journey.replays)
			var full: Dictionary = journey._validate_state(journey._state)
			_check(full.get("valid", false) and Canonical.same(full.checkpoint, journey._checkpoint), label + ": the saved state passes the full chain check with the same checkpoint")
			var reopened := Journey.new(path, null, chapter)
			reopened.load_data()
			_check(not reopened.read_only and Canonical.same(reopened._state, journey._state) and Canonical.same(reopened.checkpoint(), journey.checkpoint()), label + ": the journal loads back through the full check unchanged")
	_check(journey.chapter_complete(), chapter + ": every stage was saved")
	return true

func _fixture(name: String) -> Dictionary:
	var path := "res://tests/fixtures/" + name + ".json"
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)
