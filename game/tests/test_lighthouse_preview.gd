extends SceneTree

const Preview = preload("res://lighthouse_preview.gd")
const Journal = preload("res://services/lighthouse_journey.gd")
const Simulation = preload("res://core/lighthouse/borrowed_light.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var screen: Node3D
var path := "user://test-lighthouse-screen-%d.json" % Time.get_ticks_usec()
var fixture: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/first-two-v3.json"))
	_check(fixture.get("pairs", []).size() == 2, "Frozen independent inputs cover two consecutive stages")
	if not await _open(): return
	_check(screen.mode == "ready" and not screen.running, "Opening the chapter does not begin an unsolicited recording")
	_check(screen.controls.stick.anchor_left == 1.0 and screen.controls.action_button.anchor_left == 0.0, "Existing left-handed preference applies to new chapter controls")
	screen._begin()
	for input: Dictionary in Simulation.expand_recording_inputs(fixture.pairs[0].a):
		screen.advance_input(input)
	screen._finish()
	_check(screen.mode == "review" and not screen.running, "Finishing a valid first contribution requires review")
	_check(screen.journey.role() == "a" and not screen.journey.draft().is_empty(), "Review keeps the turn as a draft")
	var before := FileAccess.get_sha256(path)
	screen._preview_turn()
	var limit := 0
	while screen.running and limit < 620:
		screen._physics_process(1.0 / 30.0)
		limit += 1
	_check(screen.mode == "review", "Preview returns to review instead of advancing the chapter")
	_check(FileAccess.get_sha256(path) == before, "Preview never rewrites a saved rehearsal or committed checkpoint")
	screen._accept()
	_check(screen.journey.role() == "b" and screen.mode == "ready", "Only explicit acceptance unlocks the second contribution")
	_check(Canonical.same(screen.journey.prior_recording(), fixture.pairs[0].a), "The displayed earlier contribution retains its exact input evidence")
	await _close()
	if not await _open(): return
	_check(screen.role == "b" and not screen.journey.prior_recording().is_empty(), "Closing and reopening preserves the waiting earlier contribution")
	screen._begin()
	var inputs: Array = Simulation.expand_recording_inputs(fixture.pairs[0].b)
	for i in range(20): screen.advance_input(inputs[i])
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	var tick_before: int = screen.sim.tick
	screen.advance_input({"move_x": 1})
	_check(screen.mode == "paused" and screen.sim.tick == tick_before, "Backgrounding stops both ghost and player while keeping the unfinished turn")
	var draft: Dictionary = screen.journey.draft()
	_check(int(draft.duration_ticks) == tick_before, "The background boundary is durably saved, not rounded to the previous autosave")
	await _close()
	if not await _open(): return
	screen._resume_draft()
	_check(screen.mode == "play" and screen.sim.tick == tick_before, "Resume reconstructs the exact ghost/player tick")
	for i in range(tick_before, inputs.size()): screen.advance_input(inputs[i])
	if screen.mode == "play": screen._finish()
	_check(screen.mode == "review" and screen.journey.pairs().is_empty(), "A solved scene still waits for explicit acceptance")
	screen._accept()
	_check(screen.mode == "checkpoint" and screen.journey.pairs().size() == 1, "Accepting B creates the first saved checkpoint")
	screen._show_ready()
	_check(screen.stage.stage_id == "missing-piece" and screen.role == "a", "Checkpoint continues into the next authored mechanic")
	_check(screen.sim.snapshot().active_slot == "p1", "Roles alternate while retaining the actual spirit positions")
	_check(screen.world._history_root.get_meta("checkpoint_hash") == screen.checkpoint.checkpoint_hash, "The scene's remembered landmarks use the verified checkpoint")
	for recording: Dictionary in [fixture.pairs[1].a, fixture.pairs[1].b]:
		screen._begin()
		for input: Dictionary in Simulation.expand_recording_inputs(recording): screen.advance_input(input)
		if screen.mode == "play": screen._finish()
		_check(screen.mode == "review", "Second-stage input reaches review")
		screen._accept()
	_check(screen.journey.pairs().size() == 2 and not screen.journey.chapter_complete(), "Two completed stages never trigger six-stage completion")
	before = FileAccess.get_sha256(path)
	screen._watch_collection()
	limit = 0
	while screen.running and limit < 1300:
		screen._physics_process(1.0 / 30.0)
		limit += 1
	_check(not screen.running and screen.mode == "ready", "Both saved stages replay together and return to the available next stage")
	_check(FileAccess.get_sha256(path) == before, "Combined replay does not alter accepted proof or drafts")
	_check(screen.stage.stage_id == "two-promises", "The third stage is selected from actual checkpoint progression")
	var previous_state: Dictionary = screen.journey._state.duplicate(true)
	screen._choose_checkpoint()
	var second := _find_button(screen.controls.overlay, "2  ·  The Missing Piece")
	_check(second != null, "Completed checkpoints are individually selectable")
	if second != null: second.pressed.emit()
	_check(screen.mode == "confirm_checkpoint" and FileAccess.get_sha256(path) == before, "Selecting a checkpoint asks before replacing any contributions")
	var keep := _find_button(screen.controls.overlay, "Keep the current journey")
	if keep != null: keep.pressed.emit()
	_check(screen.mode == "ready" and FileAccess.get_sha256(path) == before, "Cancelling preserves the current exact journey")
	screen._choose_checkpoint()
	second = _find_button(screen.controls.overlay, "2  ·  The Missing Piece")
	if second != null: second.pressed.emit()
	var restart := _find_button(screen.controls.overlay, "Start a new attempt here")
	if restart != null: restart.pressed.emit()
	_check(screen.mode == "ready" and screen.stage.stage_id == "missing-piece" and screen.journey.role() == "a", "Confirmation starts the selected checkpoint, not the beginning of the chapter")
	_check(screen.journey.pairs().size() == 1 and Canonical.same(screen.journey.pairs()[0], fixture.pairs[0]), "Revisiting keeps the exact completed prefix")
	var archive := path + ".attempt-" + Canonical.digest(previous_state) + ".json"
	_check(FileAccess.file_exists(archive), "The old two-stage attempt is retained separately")
	await _close()
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	if FileAccess.file_exists(archive): DirAccess.remove_absolute(archive)
	print("LIGHTHOUSE PREVIEW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _open() -> bool:
	screen = Preview.new()
	screen.journey = Journal.new(path)
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": true}
	root.add_child(screen)
	# Entering the tree enables the script's physics callback. Disable it only
	# after that lifecycle step so rendered QA advances solely through its inputs.
	screen.set_physics_process(false)
	screen.world.set_process(false)
	# The real service owns its data until the asynchronous load has joined.
	# Keep UI processing active; no physics input may run while awaiting it.
	var deadline := Time.get_ticks_msec() + 30000
	while screen.mode == "loading" and Time.get_ticks_msec() < deadline:
		await process_frame
	var loaded: bool = screen.mode != "loading" and screen.journey != null
	_check(loaded, "The real chapter loader returns ownership within its bounded opening deadline")
	if not loaded:
		await _close()
		print("LIGHTHOUSE PREVIEW: %d checks, %d failures" % [checks, failures])
		quit(1)
		return false
	screen.backgrounded = false
	return true

func _close() -> void:
	root.remove_child(screen)
	screen.queue_free()
	await process_frame

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child: Node in node.get_children():
		var found := _find_button(child, text)
		if found != null: return found
	return null
