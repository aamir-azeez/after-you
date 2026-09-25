extends SceneTree

const Preview = preload("res://relay_preview.gd")
const Journey = preload("res://services/relay_journey.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const ReunionAudio = preload("res://tests/reunion_audio_checks.gd")

class FailingStorage:
	extends "res://services/local_save.gd"
	var failures_remaining := 0
	func update_values(changes: Dictionary, erase_keys: Array = []) -> bool:
		if failures_remaining > 0:
			failures_remaining -= 1
			last_error = "Synthetic transient storage failure."
			return false
		return super.update_values(changes, erase_keys)

var checks := 0
var failures := 0
var paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _handed_controls()
	var path := _new_path("full-flow")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := Preview.new()
	app.journey = Journey.new(path)
	app.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	viewport.add_child(app)
	app.set_physics_process(false)
	app.set_process(false)
	await process_frame
	_check(app.mode == "ready" and app.stage.id == "relay", "A new preview begins at the first relay stage")
	_check(app.world.bridge_visuals.size() == 2 and app.world.actors.size() == 2, "Both bridge views and stable player slots are built")
	var audio_errors := ReunionAudio.chapter(app)
	_check(audio_errors.is_empty(), "Relay reunion audio: " + str(audio_errors))
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720)]:
		viewport.size = size
		await process_frame
		await process_frame
		_check_controls(app.overlay, Rect2(Vector2.ZERO, size))
	viewport.size = Vector2i(1280, 720)
	# Asymmetric display insets are reproduced without pretending this desktop
	# viewport is Android. Content stays inset while the backdrop covers it all.
	for insets: Vector4 in [Vector4(72, 0, 0, 0), Vector4(0, 12, 48, 20)]:
		app.ui.offset_left = insets.x
		app.ui.offset_top = insets.y
		app.ui.offset_right = -insets.z
		app.ui.offset_bottom = -insets.w
		app._resize_shade()
		await process_frame
		_check(app.modal_shade.get_global_rect().is_equal_approx(Rect2(0, 0, 1280, 720)), "Modal dimming covers the viewport despite asymmetric safe insets")
	app._resize()
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b"]:
		app._begin()
		var record := _fixture(name)
		_check(app.role == record.role and app.stage.id == record.stage_id, "Ready selects the correct role and stage for " + name)
		for input: Dictionary in Simulation.expand_recording_inputs(record):
			app.advance_input(input)
		app._finish()
		if app.mode == "bloom":
			app._process(2.0)
		_check(app.mode == "review", "A completed rehearsal opens review: " + name)
		_check(app.journey.role() == record.role, "Reaching review does not commit automatically: " + name)
		var before_preview := _save_bytes(path)
		app._preview_turn()
		app._physics_process(1.0 / 30.0)
		var interrupted_tick: int = app.sim.tick
		app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		_check(app.mode == "paused" and not app.running, "Backgrounding a preview pauses replay: " + name)
		app._physics_process(1.0 / 30.0)
		_check(app.sim.tick == interrupted_tick and Canonical.same(_save_bytes(path), before_preview), "Paused replay does not advance or write primary/backup/tmp bytes: " + name)
		app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		_press(app, "Resume")
		var iterations := 0
		while app.mode == "replay" and iterations < 650:
			app._physics_process(1.0 / 30.0)
			iterations += 1
		_check(app.mode == "review", "Preview returns to the same draft's review: " + name)
		_check(Canonical.same(_save_bytes(path), before_preview), "Preview and background/return preserve every save-generation byte: " + name)
		app._accept()
		_check(app.mode != "error", "Explicit Save accepts the verified draft: " + name)
		if name == "relay-b":
			_check(app.mode == "checkpoint" and app.journey.stage_id() == "garden", "A midpoint checkpoint needs explicit Continue")
			var reopened := Journey.new(path)
			reopened.load_data()
			_check(not reopened.read_only and reopened.stage_id() == "garden", "Checkpoint is actually durable on reopening")
			app._show_ready()
	_check(app.journey.chapter_complete() and app.mode == "complete", "All four contributions complete the local chapter")
	var final_state: Dictionary = app.sim.snapshot()
	_check(app.world.bloomed and final_state.complete, "The completed view displays the verified final bloom")
	app.replay_pair_index = 0
	var before_collection := _save_bytes(path)
	app._play_collection_pair()
	var replay_ticks := 0
	while app.mode == "replay" and replay_ticks < 1250:
		app._physics_process(1.0 / 30.0)
		replay_ticks += 1
	_check(app.mode == "complete" and replay_ticks > 0 and replay_ticks < 1250, "Collection replays both pairs through their own checkpoints")
	app._show_ready()
	_check(app.mode == "complete" and app.world.bloomed, "Reopening completed progress restores the saved scene")
	_check(app.journey.pairs().size() == 2, "Watching the chapter does not append or overwrite recorded pairs")
	_check(Canonical.same(_save_bytes(path), before_collection), "Whole-chapter replay and completed view write no save-generation bytes")
	var old_state: Dictionary = app.journey._state.duplicate(true)
	_press(app, "Retry")
	_check(app.mode == "choose_checkpoint", "Completed chapters offer Retry without discarding the replay")
	app._confirm_local_checkpoint(0)
	_press(app, "Cancel")
	_check(app.mode == "complete" and Canonical.same(_save_bytes(path), before_collection), "Cancelling Retry preserves completed progress")
	app._confirm_local_checkpoint(0)
	_press(app, "Retry")
	_check(app.mode == "ready" and app.journey.pairs().is_empty() and app.journey.stage_id() == "relay", "Confirmed Retry starts a fresh playable chapter")
	var archive := path + ".attempt-" + Canonical.digest(old_state) + ".json"
	paths.append(archive)
	var after_retry := _save_bytes(path)
	_press(app, "Replays")
	_check(app.mode == "replay_collection", "Replays remains accessible before completing the first new stage")
	var saved: Dictionary = app.journey.archived_attempts()[0]
	_press(app, "%s · %d / %d" % [Time.get_datetime_string_from_unix_time(int(saved.modified)).replace("T", " "), saved.stage_count, app.definition.stages.size()])
	_check(app.mode == "replay", "Selecting an archived attempt opens its exact replay")
	replay_ticks = 0
	while app.mode == "replay" and replay_ticks < 1250:
		app._physics_process(1.0 / 30.0)
		replay_ticks += 1
	_check(app.mode == "ready" and app.journey.stage_id() == "relay", "Archived replay returns to the new attempt")
	_check(Canonical.same(_save_bytes(path), after_retry), "Archived replay never restores over the new attempt")
	_resume_and_storage_failures(app)
	viewport.queue_free()
	await process_frame
	for generated_path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(generated_path + suffix):
				DirAccess.remove_absolute(generated_path + suffix)
	print("AFTER YOU RELAY PREVIEW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _handed_controls() -> void:
	for left_handed: bool in [false, true]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1600, 720)
		root.add_child(viewport)
		var app := Preview.new()
		app.journey = Journey.new(_new_path("handed-controls"))
		app.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": left_handed}
		viewport.add_child(app)
		app.set_physics_process(false)
		app.set_process(false)
		app._begin()
		await process_frame
		await process_frame
		_check(app.stick.size.is_equal_approx(Vector2(152, 152)), "Both handedness modes preserve the full joystick hit area")
		_check(app.action_button.size.x >= 210 and app.finish_button.size.x >= 210, "Mirroring controls preserves action-button width")
		_check(Rect2(0, 0, 1600, 720).encloses(app.stick.get_global_rect()), "The active joystick is inside the viewport")
		_check((app.stick.get_global_rect().get_center().x > 800) == left_handed, "Handedness puts the joystick on the chosen side")
		_check_controls(app.hud, Rect2(0, 0, 1600, 720))
		viewport.queue_free()
		await process_frame


func _resume_and_storage_failures(app: Node3D) -> void:
	var path := _new_path("retry-resume")
	var storage := FailingStorage.new(path)
	app.journey = Journey.new(path, storage)
	app.journey.load_data()
	app._show_ready()
	app._begin()
	# Keep one durable interval, then force the next pause save to fail. The
	# failure is injected before any write and is consumed only once.
	for tick in range(31):
		app.advance_input({})
	var before_failure := _save_bytes(path)
	var unsaved_tick: int = app.sim.tick
	var unsaved_record: Dictionary = app.sim.export_recording()
	storage.failures_remaining = 1
	app._pause()
	_check(app.mode == "save_error" and not app.running, "A failed pause save visibly offers retry instead of discarding the live turn")
	_check(app.sim.tick == unsaved_tick and Canonical.same(app.sim.export_recording(), unsaved_record), "Transient write failure retains the exact unsaved live interval")
	_check(Canonical.same(_save_bytes(path), before_failure), "Transient write failure leaves all existing generation bytes unchanged")
	_check(app.journey.role() == "a" and app.journey.pairs().is_empty(), "A failed draft save cannot advance accepted progress")
	_press(app, "Retry save")
	_check(app.mode == "play" and app.running and app.sim.tick == unsaved_tick, "The actual retry control saves then resumes at the same live tick")
	var reopened := Journey.new(path)
	reopened.load_data()
	_check(not reopened.read_only and Canonical.same(reopened.draft(), unsaved_record), "Successful retry is durable and replay-verifiable on a fresh coordinator")
	# A commit failure is separate from draft durability. The review stays
	# present and the earlier role must not change until its own retry wins.
	app._begin()
	var first := _fixture("relay-a")
	for input: Dictionary in Simulation.expand_recording_inputs(first):
		app.advance_input(input)
	app._finish()
	_check(app.mode == "review", "A viable recorded turn reaches review before commit-failure injection")
	var reviewed: Dictionary = app.review.duplicate(true)
	var before_commit := _save_bytes(path)
	storage.failures_remaining = 1
	_press(app, "Save turn")
	_check(app.mode == "save_error" and app.journey.role() == "a" and app.journey.prior_recording().is_empty(), "A failed explicit commit keeps the earlier role unaccepted")
	_check(Canonical.same(app.review, reviewed) and Canonical.same(_save_bytes(path), before_commit), "Commit failure preserves the exact review and existing generation bytes")
	_press(app, "Retry save")
	_check(app.mode == "ready" and app.journey.role() == "b" and Canonical.same(app.journey.prior_recording(), reviewed), "The commit retry control accepts the same contribution exactly once")
	reopened = Journey.new(path)
	reopened.load_data()
	_check(not reopened.read_only and reopened.role() == "b" and reopened.pairs().is_empty(), "The committed earlier turn remains durable without fabricating a completed pair")
	# Resume a later player's partially recorded turn using a new coordinator
	# reading the real local file, with the exact accepted A still attached.
	app._begin()
	var receiver_inputs := Simulation.expand_recording_inputs(_fixture("relay-b"))
	var partial_ticks := mini(47, receiver_inputs.size() - 1)
	for index in range(partial_ticks):
		app.advance_input(receiver_inputs[index])
	app._pause()
	var partial: Dictionary = app.sim.export_recording()
	var partial_state: Dictionary = app.sim.snapshot()
	var old_instance: int = app.sim.get_instance_id()
	var resume_bytes := _save_bytes(path)
	app.journey = Journey.new(path)
	app.journey.load_data()
	app._show_ready()
	_press(app, "Resume")
	_check(app.mode == "play" and app.running and app.sim.tick == partial_ticks, "Resume rehearsal restores the exact mid-stage tick from disk")
	_check(app.sim.get_instance_id() != old_instance and Canonical.same(app.sim.export_recording(), partial) and Canonical.same(app.sim.snapshot(), partial_state), "Resume recreates a registered engine by replaying the saved actions rather than reusing its old object")
	_check(app.journey.role() == "b" and Canonical.same(app.journey.prior_recording(), reviewed), "Resuming a later turn retains the exact accepted earlier contribution")
	_check(Canonical.same(_save_bytes(path), resume_bytes), "Opening and resuming a rehearsal do not rewrite save generations")
	app.advance_input(receiver_inputs[partial_ticks])
	app._pause()
	_check(app.mode == "paused" and app.journey.draft().duration_ticks == partial_ticks + 1, "A resumed engine remains eligible for live autosave after one more real input")


func _press(app: Node3D, text: String) -> void:
	var button := _find_button(app.overlay, text)
	_check(button != null and not button.disabled, "The visible UI offers an enabled " + text + " control")
	if button != null and not button.disabled:
		# Exercise the actual connected button callable; do not substitute its
		# internal operation directly. Touch geometry belongs to native QA.
		button.pressed.emit()


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _save_bytes(path: String) -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".tmp", ".backup"]:
		result[suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	return result


func _new_path(label: String) -> String:
	var path := "user://relay-preview-" + label + "-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	paths.append(path)
	return path


func _check_controls(node: Node, bounds: Rect2) -> void:
	if node is Button and node.is_visible_in_tree():
		_check(bounds.encloses(node.get_global_rect()), "Visible preview button fits the viewport: " + str(node.text))
	for child in node.get_children():
		_check_controls(child, bounds)


func _fixture(name: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json")) != OK:
		_check(false, "Fixture is readable: " + name)
		return {}
	return json.data


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
