extends SceneTree
## Synthetic original stage-one recordings, generated before the stage engine
## generalization. Keep their full bytes: a self-consistent new result alone
## would not detect changing an already recorded first-stage experience.
const Simulation = preload("res://core/lighthouse/borrowed_light.gd")
const Canonical = preload("res://core/v2/canonical.gd")

func _initialize() -> void:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/borrowed-light-v3.json"))
	if not value is Dictionary or not value.get("a") is Dictionary or not value.get("b") is Dictionary:
		push_error("The frozen first-stage fixture is missing or malformed.")
		quit(1)
		return
	var pair: Dictionary = value
	var failures := 0
	for role: String in ["a", "b"]:
		var prior: Dictionary = pair.a if role == "b" else {}
		var record: Dictionary = pair[role]
		var checked := Simulation.verify_recording(record, prior)
		if not checked.valid:
			push_error("Frozen first-stage recording failed for role " + role)
			failures += 1
		var replay := Simulation.new()
		replay.reset(role, prior)
		for input: Dictionary in Simulation.expand_recording_inputs(record):
			replay.step(input)
		if not Canonical.same(record, replay.export_recording()):
			push_error("Frozen first-stage output changed for role " + role)
			failures += 1
	print("AFTER YOU LIGHTHOUSE COMPATIBILITY: 4 checks, %d failures" % failures)
	quit(1 if failures else 0)
