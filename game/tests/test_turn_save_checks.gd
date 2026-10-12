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
const Preview = preload("res://relay_preview.gd")
const RelaySimulation = preload("res://core/v2/simulation_v2.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

class CountingJourney extends "res://services/relay_journey.gd":
	var replays := 0
	func _verify_on_checkpoint(recording: Dictionary) -> Dictionary:
		replays += 1
		return super(recording)

var checks := 0
var failures := 0
var directory := ""
## Which family dispatch each covered chapter used (raw static or _proof).
var modes := {}

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
	_check(modes.has("raw") and modes.has("proof"), "Both the static and the proof-engine checks are exercised: " + str(modes.keys()))
	await _visible_wait()
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
	modes["raw" if journey._has_static("_verify_raw") else ("proof" if journey._has_static("_proof") else "public")] = true
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

## On the real chapter screen with frames running: when the journey's last
## check or setup was slow, finishing a turn and Save turn first draw a card
## saying the saved progress is being checked, then continue by themselves;
## quick work goes straight on.
func _visible_wait() -> void:
	var path := directory + "/scene.json"
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := Preview.new()
	app.journey = Journey.new(path)
	app.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	viewport.add_child(app)
	app.set_physics_process(false)
	await process_frame
	app._begin()
	for input: Dictionary in RelaySimulation.expand_recording_inputs(_fixture("v2/relay-a")): app.advance_input(input)
	# As if the last replay-backed work here had taken a second.
	app.journey._last_setup_usec = 1000000
	app._finish()
	_check(app.mode == "turn_wait" and _shows(app.overlay, PlayerCopy.LIGHTHOUSE_PREVIEW_DA74C3A728FC), "A slow check first shows that saved progress is being checked")
	await _until(app, "review")
	_check(app.mode == "review" and _button(app.overlay, "Save turn") != null, "The review follows by itself once the card was drawn")
	app.journey._last_setup_usec = 1000000
	_button(app.overlay, "Save turn").pressed.emit()
	_check(app.mode == "turn_wait" and app.journey.role() == "b", "Save turn writes the turn at once, then shows the wait before setting up the next turn")
	await _until(app, "ready")
	_check(app.mode == "ready" and app.role == "b" and app.sim != null and app.sim.role == "b", "The next turn is ready by itself after the wait")
	# Quick work never shows the card.
	app.journey._last_setup_usec = 0
	app.journey._last_check_usec = 0
	var ready_sim: RefCounted = app.sim
	app._begin()
	_check(app.mode == "play" and app.sim == ready_sim and app.journey.is_live_simulation(app.sim), "Start turn plays the simulation the ready card set up instead of setting it up again")
	for input: Dictionary in RelaySimulation.expand_recording_inputs(_fixture("v2/relay-b")): app.advance_input(input)
	app._finish()
	if app.mode == "bloom": app._process(Preview.COMPLETION_DURATION)
	_check(app.mode == "review", "Quick checks go straight to the review")
	# Saving the chapter's last turn shows the finished scene from the screen's
	# own simulation; a reopened chapter rebuilds the same scene from the chain.
	_button(app.overlay, "Save turn").pressed.emit()
	await _until(app, "checkpoint")
	for name: String in ["garden-a", "garden-b"]:
		app._show_ready()
		# A simulation that has moved since the ready card is never reused.
		var shown_sim: RefCounted = app.sim
		if name == "garden-b": app.sim.step(RelaySimulation.expand_recording_inputs(_fixture("v2/garden-b"))[0])
		app._begin()
		_check(app.mode == "play" and app.sim.tick == 0 and app.journey.is_live_simulation(app.sim) and (app.sim == shown_sim) == (name == "garden-a"), "Start turn after the ready card: " + name)
		for input: Dictionary in RelaySimulation.expand_recording_inputs(_fixture("v2/" + name)): app.advance_input(input)
		app._finish()
		if app.mode == "bloom": app._process(Preview.COMPLETION_DURATION)
		await _until(app, "review")
		_button(app.overlay, "Save turn").pressed.emit()
		await _until(app, "ready" if name == "garden-a" else "complete")
	_check(app.mode == "complete" and app.journey.chapter_complete(), "Saving the last turn completes the chapter")
	var shown: Dictionary = app.sim.snapshot()
	var reopened := Preview.new()
	reopened.journey = Journey.new(path)
	reopened.settings = app.settings.duplicate()
	viewport.add_child(reopened)
	reopened.set_process(false)
	reopened.set_physics_process(false)
	await process_frame
	_check(reopened.mode == "complete" and Canonical.same(reopened.sim.snapshot(), shown), "The finished scene after Save turn equals the scene rebuilt from the saved chain")
	viewport.queue_free()
	await process_frame

func _until(app: Node, wanted: String) -> void:
	for frame in range(30):
		if app.mode == wanted: return
		await process_frame

func _shows(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text and (node as Label).is_visible_in_tree(): return true
	for child: Node in node.get_children():
		if _shows(child, text): return true
	return false

func _button(node: Node, text: String) -> Button:
	for button: Node in node.find_children("*", "Button", true, false):
		if (button as Button).text == text and not (button as Button).disabled: return button
	return null

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
