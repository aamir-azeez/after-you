extends SceneTree

const Preview = preload("res://lighthouse_preview.gd")
const Journey = preload("res://services/lighthouse_journey.gd")
const Sim = preload("res://core/lighthouse/borrowed_light.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var screen: Node3D
var path := "user://test-lighthouse-finale-%d.json" % Time.get_ticks_usec()
var capture_dir := ""
var fixture_path := "res://tests/fixtures/lighthouse/complete-six-v3.json"
var seen: Dictionary = {}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
		if argument.begins_with("--fixture="): fixture_path = argument.trim_prefix("--fixture=")
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if not fixture is Dictionary or not fixture.get("pairs") is Array or fixture.pairs.size() != 6:
		_check(false, "Six complete pairs of independent recorded inputs are required")
		_done()
		return
	var saved := Journey.new(path)
	saved.load_data()
	for pair: Dictionary in fixture.pairs.slice(0, 4):
		for role: String in ["a", "b"]:
			_check(saved.accept_recording(pair[role]), "Each preceding contribution is replay-verified before testing the final stages")
	await _open(saved)
	_check(screen.stage.stage_id == "what-carried-you" and screen.world._decks.size() == 5, "The transfer begins on the real six-island map")
	await _capture("05-transfer-ready")
	for index in [4, 5]:
		for role: String in ["a", "b"]:
			var recording: Dictionary = fixture.pairs[index][role]
			_check(screen.role == role and screen.stage.stage_id == recording.stage_id, "Screen progression selects the correct next stage and role")
			screen._begin()
			for input: Dictionary in Sim.expand_recording_inputs(recording):
				screen.advance_input(input)
				var state: Dictionary = screen.sim.snapshot()
				if index == 4 and role == "a" and state.get("handoff", {}).get("authority", "") == "offered" and not seen.has("offered"):
					seen.offered = true
					var lens: Node3D = screen.world._prop_nodes["portable-lens"]
					_check(lens.visible and lens.get_meta("prop_status") == "offered" and lens.get_meta("holder_slot") == "", "The released lens visibly rests at the perch instead of disappearing or following its old holder")
					_check("Rest Rock" in screen.controls.progress_label.text, "The release location is named in the visible handoff guidance")
					await _capture("06-lens-left-at-rest-rock")
				if index == 4 and role == "b" and state.props["portable-lens"].status == "fitted" and not seen.has("fitted"):
					seen.fitted = true
					_check(screen.world._prop_nodes["portable-lens"].visible and screen.world._prop_nodes["portable-lens"].get_meta("prop_status") == "fitted", "The exact transferred lens is visible in the new projector")
					await _capture("07-projector-loaded")
				if index == 5 and role == "a" and state.hold_pads["beacon-hold"] and state.optics.signals["beacon-upper"] and not seen.has("held"):
					seen.held = true
					_check(screen.world._hold_pad_nodes["beacon-hold"].base.get_meta("occupied", false), "The final source pad visibly follows actual source occupancy")
					_check(not screen.world._beacon.lantern.get_meta("lit", false), "One held branch does not light the final lantern")
					await _capture("08-final-source-held")
				if index == 5 and role == "b" and state.beacon.ready and not state.beacon.lit and not seen.has("ready"):
					seen.ready = true
					_check(not screen.world._beacon.halo.visible and not screen.world._beacon.lantern.get_meta("lit", false), "Both beams display readiness without pretending the player activated the crest")
					_check("Two lights: 2 / 2" in screen.controls.progress_label.text, "Both independent receiver signals appear in the HUD")
					await _capture("09-two-lights-before-activation")
				if index == 5 and role == "b" and state.beacon.lit and not seen.has("lit"):
					seen.lit = true
					_check(screen.world._beacon.halo.visible and screen.world._beacon.lantern.get_meta("lit", false), "Only the explicit physical activation lights the lantern and halo")
					await _capture("10-welcome-left-on")
			if screen.mode == "moment":
				_check(not screen.running and not screen.controls.overlay.visible and screen.controls.finish_button.text == "Review this turn", "The complete beacon stays visible without covering it or auto-accepting the turn")
				_check(screen.journey.pairs().size() == 5 and not screen.journey.draft().is_empty(), "The finale moment preserves an uncommitted draft before the review decision")
				var tick: int = screen.sim.tick
				screen.advance_input({"move_x": 1})
				_check(screen.sim.tick == tick, "The completion moment cannot continue movement or modify the finished recording")
				var moment_hash := FileAccess.get_sha256(path)
				screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
				screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
				_check(screen.mode == "moment" and not screen.running and FileAccess.get_sha256(path) == moment_hash, "Background and return preserve the visible finale and exact uncommitted draft")
				screen.controls.finish_button.pressed.emit()
			if screen.mode == "play": screen._finish()
			_check(screen.mode == "review" and Canonical.same(screen.review, recording), "The actual input path reaches review with the original complete recording")
			_check(screen.journey.pairs().size() == index, "An objective never bypasses explicit acceptance")
			screen._accept()
			if role == "b":
				_check(screen.mode == "checkpoint" and screen.journey.pairs().size() == index + 1, "Acceptance creates exactly one durable checkpoint")
				screen._show_ready()
			if index == 4 and role == "b":
				await _close()
				await _open(Journey.new(path))
				_check(screen.stage.stage_id == "a-welcome-left-on" and screen.sim.snapshot().props["portable-lens"].socket_id == "tower-projector", "Reopening the last checkpoint keeps the transferred lens and exact next stage")
	_check(seen.size() == 5, "Every real handoff and beacon observation was reached")
	_check(screen.mode == "collection" and screen.journey.chapter_complete() and screen.journey.pairs().size() == 6, "Only six verified pairs expose the complete chapter collection")
	var before := FileAccess.get_sha256(path)
	await _close()
	await _open(Journey.new(path))
	_check(screen.mode == "collection" and screen.world._beacon.lantern.get_meta("lit", false), "A cold journal read recreates the completed beacon from its verified recordings")
	await _capture("11-lighthouse-collection")
	screen._watch_collection()
	for _tick in range(5): screen._physics_process(1.0 / 30.0)
	var paused_tick: int = screen.sim.tick
	var paused_cursor: int = screen.replay_cursor
	screen._pause()
	_check(screen.mode == "paused" and not screen.running, "A combined replay can be paused before the finale")
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	for button: Button in screen.controls.overlay.find_children("*", "Button", true, false):
		if button.text == "Continue replay":
			button.pressed.emit()
			break
	_check(screen.mode == "replay" and screen.running and screen.sim.tick == paused_tick and screen.replay_cursor == paused_cursor, "Resuming a paused chapter replay retains its exact input cursor")
	var count := 0
	while screen.running and count < 4000:
		screen._physics_process(1.0 / 30.0)
		count += 1
	_check(screen.mode == "moment" and screen.controls.finish_button.text == "Back to your chapter", "The combined replay also leaves its last light visible")
	if screen.mode == "moment": screen.controls.finish_button.pressed.emit()
	_check(not screen.running and screen.mode == "collection" and count < 4000, "The complete six-pair collection reaches its real ending")
	_check(FileAccess.get_sha256(path) == before and Canonical.same(screen.journey.pairs(), fixture.pairs), "Combined playback neither changes a saved checkpoint nor rewrites either player's input")
	var broken := Sim.new()
	_check(broken.reset("a", {}, fixture.pairs.slice(0, 5)), "A rejection-guidance check uses the actual final-stage checkpoint")
	for input: Dictionary in Sim.expand_recording_inputs(fixture.pairs[5].a): broken.step(input)
	for _tick in range(8): broken.step({"move_x": 1})
	for _tick in range(8): broken.step({"move_x": -1})
	var invalid_state: Dictionary = broken.snapshot()
	screen._update_hud(invalid_state)
	_check(not broken.can_commit() and not invalid_state.commit_reason.is_empty() and screen.controls.hint_label.text == invalid_state.commit_reason, "An interrupted source displays the exact rejection reason instead of an impossible hold instruction")
	await _close()
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	_done()

func _open(saved: RefCounted) -> void:
	screen = Preview.new()
	screen.journey = saved
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.world.set_process(false)
	await process_frame
	screen.backgrounded = false

func _close() -> void:
	root.remove_child(screen)
	screen.queue_free()
	await process_frame

func _capture(label: String) -> void:
	var tick: int = screen.sim.tick
	var expected_mode: String = screen.mode
	var expected_running: bool = screen.running
	var cursor: int = screen.replay_cursor
	screen.world.present(screen.sim.snapshot(), true)
	# A real desktop focus change may pause a recording during frame capture.
	# Detect it and exercise the same explicit Continue action as the player;
	# never silently keep feeding inputs to a paused scene or bypass its handler.
	var observation_ready := false
	for _attempt in range(3):
		await process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		if screen.backgrounded or screen.mode != expected_mode:
			var legitimate_pause: bool = screen.mode == "paused" and expected_running and not screen.running
			var unchanged: bool = screen.mode == expected_mode and screen.running == expected_running
			_check((legitimate_pause or unchanged) and screen.sim.tick == tick and screen.replay_cursor == cursor, "A focus interruption preserves the exact observed input boundary")
			if not legitimate_pause and not unchanged: break
			screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
			if legitimate_pause:
				var caption := "Continue replay" if expected_mode == "replay" else "Continue recording"
				for button: Button in screen.controls.overlay.find_children("*", "Button", true, false):
					if button.text == caption:
						button.pressed.emit()
						break
			_check(screen.mode == expected_mode and screen.running == expected_running and screen.sim.tick == tick and screen.replay_cursor == cursor, "The normal Continue action restores the exact capture state")
			print("RENDER OBSERVATION: resumed a focus interruption at ", label)
			continue
		observation_ready = true
		break
	_check(observation_ready, "Rendered observation reaches a stable visible state within three frames")
	if not observation_ready:
		_done()
		return
	screen.world._frame_camera()
	_check(screen.sim.tick == tick, "Observing a rendered frame does not insert an extra input")
	for point: Vector3 in screen.world._frame_points:
		var uv: Vector2 = screen.world.camera.unproject_position(screen.world.to_global(point)) / root.get_visible_rect().size
		if uv.x < 0.05 or uv.x > 0.95 or uv.y < 0.14 or uv.y > 0.87:
			_check(false, "The authored world must fit outside the caption and header")
			break
	if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		_check(root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png")) == OK, "An actual rendered frame was saved for visual inspection")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _done() -> void:
	print("LIGHTHOUSE FINALE UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
