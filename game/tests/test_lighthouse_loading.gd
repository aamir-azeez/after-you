extends SceneTree
const PlayerCopy = preload("res://presentation/player_copy.gd")

const Preview = preload("res://lighthouse_preview.gd")
const Journey = preload("res://services/lighthouse_journey.gd")
const Simulation = preload("res://core/lighthouse/borrowed_light.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []
var fixture_path := "res://tests/fixtures/lighthouse/complete-six-v3.json"

class GatedJourney extends "res://services/lighthouse_journey.gd":
	var entered := Semaphore.new()
	var release := Semaphore.new()
	func load_data() -> void:
		entered.post()
		release.wait()
		super.load_data()

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="): fixture_path = arg.trim_prefix("--fixture=")
	_run.call_deferred()

func _run() -> void:
	await _responsive_open()
	await _cancel_back()
	await _complete_collection()
	for path: String in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("LIGHTHOUSE LOADING UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _responsive_open() -> void:
	var path := _path("gated")
	var journal := GatedJourney.new(path)
	var screen := _open(journal)
	var entered := false
	var deadline := Time.get_ticks_msec() + 10000
	while not entered and Time.get_ticks_msec() < deadline:
		entered = journal.entered.try_wait()
		await process_frame
	_check(entered, "The real background load started")
	_check(screen.mode == "loading" and screen.journey == null and screen.controls.overlay.visible, "Loading is visible before a partially loaded journal can be read")
	for _frame in range(12): await process_frame
	_check(screen._loading_time > 0.0 and screen._loader.busy() and not screen.running, "Scene frames continue while verification owns the journal")
	screen._begin()
	screen._finish()
	screen._accept()
	_check(screen.mode == "loading" and screen.journey == null and not FileAccess.file_exists(path), "Gameplay actions cannot start or write while a load is pending")
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	journal.release.post()
	await _wait_loaded(screen)
	_check(screen.mode == "ready" and screen.backgrounded and not screen.running, "Completing a load in the background never starts a recording")
	_check(screen.journey == journal and not screen._loader.busy(), "Only the joined complete journal returns to the scene")
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check(screen.mode == "ready" and not screen.running, "Returning to the app still requires Record")
	await _close(screen)

func _cancel_back() -> void:
	var path := _path("cancel")
	var journal := GatedJourney.new(path)
	var screen := _open(journal)
	current_scene = screen
	var entered := false
	var deadline := Time.get_ticks_msec() + 10000
	while not entered and Time.get_ticks_msec() < deadline:
		entered = journal.entered.try_wait()
		await process_frame
	_check(entered, "Cancellation begins with actual pending work")
	screen._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	for _frame in range(8): await process_frame
	_check(current_scene == screen and screen._leave_after_load and screen._loader.busy(), "Back acknowledges exit and keeps ownership until the worker finishes")
	_check(screen._loading_label.text.begins_with(PlayerCopy.LIGHTHOUSE_PREVIEW_28D04CCA22A1), "The pending return is visible without blocking frames")
	journal.release.post()
	deadline = Time.get_ticks_msec() + 20000
	while current_scene == screen and Time.get_ticks_msec() < deadline: await process_frame
	_check(current_scene != screen, "Back returns through the real scene transition after join")
	_check(not FileAccess.file_exists(path), "Cancelling an empty load does not fabricate progress")
	if current_scene != null and current_scene != screen:
		var main := current_scene
		current_scene = null
		await _close(main)
	elif is_instance_valid(screen):
		current_scene = null
		await _close(screen)

func _complete_collection() -> void:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if not value is Dictionary or not value.get("pairs") is Array or value.pairs.size() != 6:
		_check(false, "Six exact pairs are available")
		return
	var path := _path("complete")
	var original := Journey.new(path)
	original.load_data()
	for pair: Dictionary in value.pairs:
		if not original.accept_recording(pair.a) or not original.accept_recording(pair.b):
			_check(false, "The independent fixture is accepted only through real replay verification")
			return
	var hashes := _hashes(path)
	Simulation._clear_verification_cache()
	var started := Time.get_ticks_usec()
	var screen := _open(Journey.new(path))
	var frames := 0
	var max_frame_gap := 0
	var previous := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + 30000
	while screen.mode == "loading" and Time.get_ticks_msec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		max_frame_gap = maxi(max_frame_gap, now - previous)
		previous = now
		frames += 1
	print("LIGHTHOUSE COLD UI: ", JSON.stringify({"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0, "loading_frames": frames, "max_frame_gap_ms": float(max_frame_gap) / 1000.0}))
	_check(screen.mode == "collection" and frames > 1, "A cold completed chapter verifies while the scene keeps processing frames")
	_check(screen.sim == null and screen.journey.chapter_complete(), "Static collection display does not reconstruct an unused live engine")
	var shown: Dictionary = screen.presentation_state()
	_check(shown.get("complete", false) and shown.get("events", []).is_empty() and screen.world._beacon.lantern.get_meta("lit", false), "Verified final state lights the lantern without replaying completion effects")
	var last: Dictionary = value.pairs[-1]
	var proof := Simulation.verify_recording(last.b, last.a, value.pairs.slice(0, 5))
	proof.snapshot.events = []
	_check(Canonical.same(shown, proof.snapshot), "Every displayed final value comes from the exact verified pair")
	shown.players.p0.x += 1234
	_check(Canonical.same(screen.presentation_state(), proof.snapshot), "Returned presentation data cannot change the verified collection")
	_check(_hashes(path) == hashes and Canonical.same(screen.journey.pairs(), value.pairs), "Cold loading preserves all exact recordings and generation bytes")
	await _close(screen)

func _open(journal: RefCounted) -> Node3D:
	var screen := Preview.new()
	screen.journey = journal
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	root.add_child(screen)
	screen.set_physics_process(false)
	return screen

func _wait_loaded(screen: Node3D) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while screen.mode == "loading" and Time.get_ticks_msec() < deadline: await process_frame
	_check(screen.mode != "loading", "The joined result arrives within the bounded load window")

func _close(screen: Node) -> void:
	if is_instance_valid(screen):
		if screen.get_parent() != null: screen.get_parent().remove_child(screen)
		screen.queue_free()
	await process_frame

func _path(label: String) -> String:
	var path := "user://test-lighthouse-loading-%d-%s.json" % [Time.get_ticks_usec(), label]
	for suffix: String in ["", ".tmp", ".backup"]: paths.append(path + suffix)
	return path

func _hashes(path: String) -> Dictionary:
	var result := {}
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): result[suffix] = FileAccess.get_sha256(path + suffix)
	return result

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
