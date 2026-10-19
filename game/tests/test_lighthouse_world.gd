extends SceneTree

const Preview = preload("res://lighthouse_preview.gd")
const Journey = preload("res://services/lighthouse_journey.gd")
const Sim = preload("res://core/lighthouse/borrowed_light.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const World = preload("res://presentation/lighthouse_world.gd")
const StageCatalog = preload("res://core/lighthouse/stage_catalog.gd")
var checks := 0
var failures := 0
var screen: Node3D
var path := "user://test-lighthouse-world-%d.json" % Time.get_ticks_usec()
var capture_dir := ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	_remembered_fixtures()
	var saved := Journey.new(path)
	saved.load_data()
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/first-three-v3.json"))
	for pair: Dictionary in fixture.pairs:
		for role: String in ["a", "b"]:
			_check(saved.accept_recording(pair[role]), "Earlier input evidence is fully verified before presenting the next stage")
	screen = Preview.new()
	screen.journey = saved
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.world.set_process(false)
	# Keep UI polling active while the real loader owns the journal. A frame
	# boundary alone does not mean replay verification has finished on every OS.
	var deadline := Time.get_ticks_msec() + 30000
	while screen.mode == "loading" and Time.get_ticks_msec() < deadline:
		await process_frame
	var loaded: bool = screen.mode == "ready" and screen.journey != null and screen.sim != null
	_check(loaded, "The real chapter loader joins and presents the ready stage within a bounded deadline")
	if not loaded:
		await _finish_test()
		return
	screen.backgrounded = false
	_check(screen.stage.stage_id == "after-the-first-bell" and screen.world._decks.size() == 5, "Stage four presents five real connections")
	_check(screen.world._selector_nodes.size() == 1 and screen.world._mirror_nodes.size() == 1, "A selector has one real optical mirror, not duplicated controls")
	var overlapping_old_mirror := false
	for landmark: Node in screen.world._history_root.get_children():
		if landmark.get_meta("mirror_id", "") == "south-mirror": overlapping_old_mirror = true
	_check(not overlapping_old_mirror, "An old mirror replaced at the same authored position is not drawn over its selector")
	_check(screen.world._receiver_cables["first-path"].is_empty() and screen.world._receiver_cables["second-path"].is_empty(), "Distant control signals do not draw fake surface cables across the void")
	_check(not screen.world._decks["court-rest"].visible and not screen.world._decks["rest-tower"].visible, "Earlier checkpoints never pre-open either timed path")
	await _frame("00-first-bell-ready")
	var card_bounds: Rect2 = screen.controls.modal_scroll.get_parent().get_parent().get_global_rect()
	_check(root.get_visible_rect().encloses(card_bounds), "The complete story card stays inside the display")
	screen._begin()
	await _frame("01-first-bell-off")
	_check(screen.controls.progress_label.text == PlayerCopy.LIGHTHOUSE_PREVIEW_8BD43A5CB9A6, "The sequence has visible text before either path is lit")
	_check(screen.sim.snapshot().context_action.id == "select_path", "The exact inherited player can operate the selector")
	screen.advance_input({"interact": true})
	var required: Array = screen.sim.snapshot().sequence.required_ticks
	while screen.sim.snapshot().sequence.first_ticks < required[0] and not screen.sim.finished: screen.advance_input({})
	_check(screen.world._selector_nodes["south-selector"].root.get_meta("selected_state") == 1, "First choice updates its physical selector marker")
	_check(screen.controls.objective_panel.detail_label.text == PlayerCopy.LIGHTHOUSE_PREVIEW_6EB851761E97, "Only a sufficiently long first recording shows first-light readiness")
	await _frame("02-first-bell-first-path")
	screen.advance_input({"interact": true})
	while screen.sim.snapshot().sequence.second_ticks < required[1] and not screen.sim.finished: screen.advance_input({})
	_check(screen.world._selector_nodes["south-selector"].root.get_meta("selected_state") == 2 and "Ready to finish" in screen.controls.objective_panel.detail_label.text, "Second marker and readiness use the actual second duration")
	screen._finish()
	_check(screen.mode == "review", "Finishing a sequence still requires review")
	screen._accept()
	_check(screen.role == "b" and screen.mode == "ready", "Explicit sequence acceptance changes roles")
	screen._begin()
	for _i in range(10): screen.advance_input({})
	var player: Dictionary = screen.sim.snapshot().players[screen.sim.snapshot().active_slot]
	if player.surface_id in ["north", "court-north", "south", "court-south"]:
		_move([-48, player.z])
		_move([-48, 0])
	else:
		_move([player.x, 0])
	_move([288, 0])
	_check(screen.sim.snapshot().route_progress.step == 2 and screen.controls.progress_label.text == PlayerCopy.LIGHTHOUSE_PREVIEW_C2AC8F270DB6, "The safe intermediate island shows that the next route is not yet lit")
	await _frame("03-first-bell-rest-rock")
	while screen.sim.snapshot().sequence.phase != "second" and not screen.sim.finished: screen.advance_input({})
	_check(screen.world._memory_markers["court-rest"].visible and screen.world._decks["court-rest"].visible, "An occupied route remains visibly remembered after its light changes")
	_check(not screen.world._memory_markers["rest-tower"].visible, "A newly powered but unvisited route has no invented footsteps")
	_check(screen.controls.progress_label.text == PlayerCopy.LIGHTHOUSE_PREVIEW_D7AE1ED2893C, "Crossing guidance changes only when the second window is active")
	var receiver_snapshot: Dictionary = screen.sim.snapshot()
	# A combined replay can be opened while the screen's live journal waits on
	# A. Presentation must follow the replay's role, not that live journal role.
	screen.role = "a"
	screen._update_hud(receiver_snapshot)
	_check(screen.controls.progress_label.text == PlayerCopy.LIGHTHOUSE_PREVIEW_D7AE1ED2893C, "Recorded B progress is independent of the saved live role")
	screen.role = "b"
	_move([552, 0])
	_check("Tower reached" in screen.controls.progress_label.text, "The tower milestone follows the player's actual route")
	screen.advance_input({"interact": true})
	_check(screen.sim.snapshot().objective_done, "Actual bell interaction completes the crossing objective")
	await _frame("04-first-bell-tower")
	while screen.mode == "play" and not screen.sim.finished: screen.advance_input({})
	_check(screen.sim.can_commit(), "Acceptance waits for the full earlier recording to finish after the bell")
	screen._finish()
	screen._accept()
	_check(screen.journey.pairs().size() == 4 and not screen.journey.chapter_complete(), "Four accepted stages do not claim the six-stage finale")
	var evidence := FileAccess.get_sha256(path)
	screen._watch_collection()
	var limit := 0
	while screen.running and limit < 5000:
		screen._physics_process(1.0 / 30.0)
		limit += 1
	_check(not screen.running and FileAccess.get_sha256(path) == evidence, "The full four-stage collection plays without rewriting accepted evidence")
	var failed_source := Sim.new()
	_check(failed_source.reset("a", {}, fixture.pairs), "Negative presentation case uses an actual inherited simulation")
	failed_source.step({"interact": true})
	failed_source.step({})
	failed_source.step({"interact": true})
	while failed_source.snapshot().sequence.second_ticks < failed_source.sequence_budget_ticks()[1] and not failed_source.finished: failed_source.step({})
	screen._update_hud(failed_source.snapshot())
	_check(not failed_source.can_commit() and "Ready to finish" not in screen.controls.objective_panel.detail_label.text and screen.controls.finish_button.disabled, "A long second window never conceals a too-short first one")
	await _finish_test()

## Later stages with every earlier mirror remembered, turned both ways in turn:
## a remembered light, receiver or mirror is left out only where a later one of
## its kind stands (lighthouse_world._superseded), never for another kind.
func _remembered_fixtures() -> void:
	var world: Node3D = World.new()
	root.add_child(world)
	world.set_process(false)
	for stage_id: String in ["after-the-first-bell", "what-carried-you", "a-welcome-left-on"]:
		var index := StageCatalog.STAGE_IDS.find(stage_id)
		world.load_level(StageCatalog.definition(stage_id))
		var mirrors: Dictionary = {}
		for earlier in range(index):
			for control: Dictionary in StageCatalog.controls(StageCatalog.STAGE_IDS[earlier]):
				mirrors[str(control.get("optical_id", control.id))] = "slash" if mirrors.size() % 2 == 0 else "backslash"
		world.present_history({"level_id": "sleeping-lighthouse", "stage_index": index, "mechanisms": {"latched_bridges": [], "mirrors": mirrors}})
		var shown: Dictionary = {}
		var spots: Array[Vector2] = []
		for landmark: Node in world._history_root.get_children():
			var at := Vector2((landmark as Node3D).position.x, (landmark as Node3D).position.z)
			if landmark.has_meta("mirror_id"):
				shown[landmark.get_meta("mirror_id")] = landmark.get_meta("orientation")
				spots.append(at)
		var crowded := false
		for i in range(spots.size()):
			for j in range(i + 1, spots.size()):
				if spots[i].distance_to(spots[j]) < World.FIXTURE_CLEARANCE_CM / 100.0: crowded = true
			for control: Dictionary in StageCatalog.controls(stage_id):
				if spots[i].distance_to(Vector2(control.position_cm[0], control.position_cm[1]) / 100.0) < World.FIXTURE_CLEARANCE_CM / 100.0: crowded = true
		_check(not crowded, "No remembered mirror stands on another mirror or on the stage's own control: " + stage_id)
		# The south selector replaced the south mirror at (56, 350).
		var expected: Dictionary = mirrors.duplicate()
		expected.erase("south-mirror")
		for control: Dictionary in StageCatalog.controls(stage_id): expected.erase(str(control.get("optical_id", control.id)))
		_check(shown == expected, "Every other remembered mirror is drawn with its kept orientation: %s %s" % [stage_id, shown])
		if stage_id != "what-carried-you": continue
		var near := func(cm: Array) -> bool:
			for landmark: Node in world._history_root.get_children():
				var at := Vector2((landmark as Node3D).position.x, (landmark as Node3D).position.z)
				if at.distance_to(Vector2(cm[0], cm[1]) / 100.0) < 0.05: return true
			return false
		_check(not near.call([24, 60]) and not near.call([56, 60]), "The Court's own lens light stands in for both remembered lens lights")
		_check(not near.call([-80, -360]), "The stage's own north receiver stands in for the remembered one at its place")
		_check(near.call([120, 350]) and near.call([-80, 60]) and near.call([-80, 0]), "The south receiver and the remembered mirrors still stand")
	world.free()

func _finish_test() -> void:
	root.remove_child(screen)
	screen.queue_free()
	await process_frame
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	_check(preload("res://presentation/kit/primitives.gd").changed_shared_materials().is_empty(), "Every kit look shared between meshes is as it was made; code that changes a mesh's material takes its own copy (Primitives.own_material): %s" % [preload("res://presentation/kit/primitives.gd").changed_shared_materials()])
	print("LIGHTHOUSE WORLD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _frame(label: String) -> void:
	var tick: int = screen.sim.tick
	screen.world.present(screen.sim.snapshot(), true)
	await process_frame
	_check(screen.sim.tick == tick, "A rendering frame never inserts an extra puzzle input")
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(2400, 1080)]:
		root.size = size
		await process_frame
		screen.world._frame_camera()
		var viewport: Vector2 = root.get_visible_rect().size
		var fits := true
		# From the third stage the camera follows the active spirit (same angle,
		# so the stick maps the same) until the stage is solved; it must keep
		# that spirit clear of the header and caption. Otherwise the whole
		# authored archipelago fits.
		var following: bool = screen.world._follows_view()
		var points: Array = [screen.world.actors[screen.world._follow_slot].position] if following else screen.world._frame_points
		for point: Vector3 in points:
			var pixel: Vector2 = screen.world.camera.unproject_position(screen.world.to_global(point))
			var uv := pixel / viewport
			if uv.x < 0.05 or uv.x > 0.95 or uv.y < 0.14 or uv.y > 0.87: fits = false
		_check(fits, "The framed %s fits outside header and bottom caption at %dx%d" % ["active spirit" if following else "archipelago", size.x, size.y])
	root.size = Vector2i(1920, 1080)
	await process_frame
	screen.world._frame_camera()
	if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png")) == OK, "The actual frame is saved for visual inspection")

func _move(destination: Array) -> void:
	for _i in range(200):
		if not screen.running or screen.sim.finished: return
		var player: Dictionary = screen.sim.snapshot().players[screen.sim.snapshot().active_slot]
		var dx := int(destination[0]) - int(player.x)
		var dz := int(destination[1]) - int(player.z)
		if absi(dx) <= 4 and absi(dz) <= 4: return
		screen.advance_input({"move_x": signi(dx) if absi(dx) > 4 else 0, "move_z": 0 if absi(dx) > 4 else signi(dz)})

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
