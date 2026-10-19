extends SceneTree
## A solo hard run on the chapter screen (relay_preview.gd with
## services/hard_run.gd): no way to play a turn again is offered; a second
## start, a turn that cannot be kept or a drowning ends the run, keeps it up
## to the slip and starts again from stage 1; pause and an app kill resume the
## same try (a turn's first tick is saved at once); a finished run marks the
## chapter and shows its end card hook; a kept run plays back from its slip,
## its earlier stages too.
const Preview = preload("res://relay_preview.gd")
const Journey = preload("res://services/relay_journey.gd")
const TurnTries = preload("res://services/turn_tries.gd")
const HardMode = preload("res://services/hard_mode.gd")
const HardRun = preload("res://services/hard_run.gd")
const HardModeView = preload("res://presentation/hard_mode_view.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const TideSimulation = preload("res://core/journey/simulation.gd")
const Tide = preload("res://tests/turn_of_the_tide_witness.gd")
const KEY := "relay-isles@2"
const TIDE := "turn-of-the-tide@2"
var checks := 0
var failures := 0
var fixtures: Dictionary = {}
var _paths: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	await _nothing_to_retry_and_second_start()
	await _failed_turn()
	await _pause_and_kill()
	await _whole_run()
	await _watch_a_slip()
	await _drowning()
	_clear(KEY)
	_clear(TIDE)
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("Hard mode solo: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _path(label: String) -> String:
	var path := "user://hard-solo-test-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	_paths.append(path.get_basename() + "-open.json")
	return path

func _clear(key: String) -> void:
	HardMode.wait_writes()
	for path: String in [HardMode.journal_path(key), HardMode.runs_path(key), HardMode.INDEX_PATH]:
		for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

var _marks := ""
var _counts := ""

func _fresh() -> void:
	_clear(KEY)
	_marks = _path("marks")
	_counts = _path("counts")

func _screen(provider: Callable = Callable()) -> Node3D:
	var app := Preview.new()
	app.hard = HardRun.solo(KEY, _marks)
	app.turn_tries = TurnTries.new(_counts)
	app.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	HardModeView.ending_extras_provider = provider
	root.add_child(app)
	app.set_physics_process(false)
	app.set_process(false)
	return app

func _close(app: Node3D) -> void:
	app.queue_free()
	await process_frame
	HardModeView.ending_extras_provider = Callable()

func _play(app: Node3D, name: String, ticks: int = -1) -> void:
	var inputs: Array = Simulation.expand_recording_inputs(fixtures[name])
	for index in range(inputs.size() if ticks < 0 else mini(ticks, inputs.size())): app.advance_input(inputs[index])

func _visible_texts(node: Node, texts: Array = []) -> Array:
	if node is Button and node.is_visible_in_tree(): texts.append(node.text)
	for child: Node in node.get_children(): _visible_texts(child, texts)
	return texts

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree(): return node
	for child: Node in node.get_children():
		var found := _button(child, text)
		if found != null: return found
	return null

func _label_text(app: Node3D, name: String) -> String:
	var label: Variant = app.overlay.find_child(name, true, false)
	return str(label.text) if label is Label else ""

func _no_retry(app: Node3D, where: String) -> void:
	var texts := _visible_texts(app.overlay)
	for banned: String in ["Retry", "Restart chapter", PlayerCopy.SOLO_REDO_ACTION, "Ask for redo"]:
		_check(banned not in texts, "%s offers no %s (%s)" % [where, banned, ", ".join(texts)])

func _nothing_to_retry_and_second_start() -> void:
	_fresh()
	var app := _screen()
	await process_frame
	_check(app._hard_on() and str(app.journey._path) == HardMode.journal_path(KEY), "A hard open plays on the hard journal")
	_check(_label_text(app, "Body").contains(PlayerCopy.HARD_READY_NOTE) or _visible_body(app).contains(PlayerCopy.HARD_READY_NOTE), "The ready card says it is a hard run")
	_no_retry(app, "The ready card")
	app._begin()
	await process_frame
	_check(app.mode == "play" and app._live_tries == 1, "The first start is try 1")
	_play(app, "relay-a", 12)
	_check(app.controls.try_pill.visible and app.controls.try_pill.label.text == PlayerCopy.HARD_IN_PLAY % [1, 2], "In play the pill says Hard and the stage, never a try")
	app._pause()
	_check(app.mode == "paused" and _button(app.overlay, "Resume") != null and _button(app.overlay, "Back") != null, "Pause offers Resume and Back")
	_no_retry(app, "The pause card")
	# Any second start ends the run, however it is reached.
	app._begin()
	await process_frame
	_check(app.mode == "hard_failed" and app.hard.last_run.reason == "retry", "A second start of a turn ends the run")
	_check(app.overlay.find_child("HardBand", true, false) != null and _button(app.overlay, PlayerCopy.HARD_START_AGAIN) != null and _button(app.overlay, "Back") != null, "The failure card offers Start again and Back")
	_check(_label_text(app, "HardLine") == PlayerCopy.HARD_YOU_STARTED_OVER % 1, "The card says who slipped where")
	_no_retry(app, "The failure card")
	_check(app.journey.pairs().is_empty() and app.journey.role() == "a" and not app.journey.has_draft(), "The run starts again from stage 1")
	_check(app.turn_tries.count(app._tries_slot()) == 0, "The run's open try counts start again")
	_check(_runs(KEY).size() == 1 and _runs(KEY)[0].by == "you", "The failed run is kept")
	_button(app.overlay, PlayerCopy.HARD_START_AGAIN).pressed.emit()
	await process_frame
	_check(app.mode == "ready", "Start again goes back to the first turn")
	app._begin()
	await process_frame
	_check(app.mode == "play" and app._live_tries == 1, "The new run's first turn is try 1")
	await _close(app)

## The chapter's kept runs once every write in flight has landed.
func _runs(key: String) -> Array[Dictionary]:
	HardMode.wait_writes()
	return HardMode.runs(key)

func _visible_body(app: Node3D) -> String:
	var text := ""
	for node: Node in app.overlay.find_children("*", "Label", true, false):
		if (node as Label).is_visible_in_tree(): text += (node as Label).text + "\n"
	return text

func _failed_turn() -> void:
	_fresh()
	var app := _screen()
	await process_frame
	app._begin()
	await process_frame
	_play(app, "relay-a", 3)
	app._finish()
	await process_frame
	_check(app.mode == "hard_failed" and app.hard.last_run.reason == "failed_turn", "A turn that cannot be kept ends the run at once, with no review")
	var run: Dictionary = _runs(KEY)[0] if not _runs(KEY).is_empty() else {}
	_check(not run.is_empty() and not run.slip.is_empty() and run.slip.recording.stage_id == "relay" and run.slip.checkpoint.stage_index == 0, "The slipped turn is kept up to the slip")
	_check(HardMode.watchable(run), "The failed run can be watched")
	await _close(app)

func _pause_and_kill() -> void:
	_fresh()
	var app := _screen()
	await process_frame
	app._begin()
	_play(app, "relay-a", 40)
	app._pause()
	_check(app.journey.has_draft(), "Pause keeps the turn's draft")
	await _close(app)
	app = _screen()
	await process_frame
	var texts := _visible_texts(app.overlay)
	_check("Resume" in texts and "Record" not in texts, "After the app closed, a hard run offers only Resume (%s)" % ", ".join(texts))
	app._resume_draft()
	await process_frame
	_check(app.mode == "play" and app._live_tries == 1, "Resuming the draft is the same try")
	var inputs: Array = Simulation.expand_recording_inputs(fixtures["relay-a"])
	for index in range(40, inputs.size()): app.advance_input(inputs[index])
	app._finish()
	_check(app.mode == "review" and _button(app.overlay, "Save turn") != null, "The resumed turn reaches its review")
	_check(_visible_body(app).contains(PlayerCopy.HARD_REVIEW_BODY) and not _visible_body(app).contains(PlayerCopy.RELAY_PREVIEW_B9074234FC11), "The review says this turn stays, with no promise of another attempt")
	_no_retry(app, "The review card")
	app._accept()
	_check(app.journey.role() == "b" and _runs(KEY).is_empty(), "The turn is kept and the run goes on")
	# A turn closed in its first second: its first tick was saved, so it resumes.
	app._show_ready()
	app._begin()
	_play(app, "relay-b", 5)
	await _close(app)
	app = _screen()
	await process_frame
	texts = _visible_texts(app.overlay)
	_check(app.journey.has_draft() and "Resume" in texts and "Record" not in texts, "A turn's first tick is saved at once, so a closed app offers Resume (%s)" % ", ".join(texts))
	app._resume_draft()
	await process_frame
	_check(app.mode == "play" and app._live_tries == 1, "The early turn resumes as the same try")
	await _close(app)
	# Closed before its first tick: nothing was saved, so starting it again is a retry.
	_fresh()
	app = _screen()
	await process_frame
	app._begin()
	await _close(app)
	app = _screen()
	await process_frame
	_check(not app.journey.has_draft(), "Nothing of a turn closed before its first tick was saved")
	app._begin()
	await process_frame
	_check(app.mode == "hard_failed" and app.hard.last_run.reason == "retry" and app.journey.pairs().is_empty() and app.journey.role() == "a", "Starting that turn again ends the run")
	await _close(app)

func _whole_run() -> void:
	_fresh()
	var seen: Array = []
	var app := _screen(func(extras: VBoxContainer, context: Dictionary) -> void: seen.append([str(extras.name), str(context.kind), bool(context.together)]))
	await process_frame
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b"]:
		app._show_ready()
		app._begin()
		_play(app, name)
		app._finish()
		if app.mode == "bloom": app._show_review()
		_check(app.mode == "review", name + " reaches its review")
		app._accept()
		_check(app.mode != "error" and app.mode != "save_error", name + " is kept: " + str(app.journey.last_error))
	app._show_ready()
	_check(app.journey.chapter_complete() and app.mode == "complete", "The whole chapter in one go finishes the run")
	_check(HardMode.new(_marks).completed(KEY, HardMode.SOLO) and not HardMode.new(_marks).completed(KEY, HardMode.TOGETHER), "A finished solo run marks Hard solo")
	_check(app.overlay.find_child("HardBand", true, false) != null and _label_text(app, "HardTitle") == PlayerCopy.HARD_COMPLETE_TITLE, "The finished run has its own card")
	_check(not seen.is_empty() and seen.all(func(call: Array) -> bool: return call == ["EndingExtras", "complete", false]), "Each finished card hosts the end card hook once (%s)" % str(seen))
	_check(_runs(KEY).filter(func(run: Dictionary) -> bool: return run.kind == HardMode.COMPLETE).size() == 1, "The finished run is kept for Replays")
	_no_retry(app, "The finished card")
	app._show_ready()
	_check(_runs(KEY).size() == 1, "Showing the finished card again keeps the run once")
	var again := _button(app.overlay, PlayerCopy.HARD_AGAIN)
	_check(again != null, "The finished card offers Play Hard again")
	if again != null: again.pressed.emit()
	await process_frame
	_check(app.mode == "ready" and app.journey.pairs().is_empty() and HardMode.new(_marks).completed(KEY, HardMode.SOLO), "Play Hard again starts a new run and keeps the mark")
	var normal := Journey.new("", null, KEY)
	normal.load_data()
	_check(normal.pairs().is_empty(), "The chapter's own journal never saw the hard run")
	await _close(app)

func _watch_a_slip() -> void:
	_fresh()
	var app := _screen()
	await process_frame
	app._begin()
	_play(app, "relay-a")
	app._finish()
	app._accept()
	app._show_ready()
	app._begin()
	_play(app, "relay-b", 20)
	app._finish()
	_check(app.mode == "hard_failed" and app.hard.last_run.role == "b", "A slip on the second turn ends the run")
	var run: Dictionary = _runs(KEY)[0]
	await _close(app)
	HardMode.hand_over({"chapter_key": KEY, "kind": "watch", "run": run})
	var viewer := Preview.new()
	viewer.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	root.add_child(viewer)
	viewer.set_physics_process(false)
	viewer.set_process(false)
	await process_frame
	_check(viewer._solo_replay_only and viewer.hard == null and viewer.mode == "replay", "A kept run opens straight into its replay")
	_check(viewer._replay_collection.size() == 1 and viewer.checkpoint == run.slip.checkpoint and viewer.sim.get("role") == "b", "It plays the slip from its own checkpoint, beside its first turn's memory")
	var frames := 0
	while viewer.mode == "replay" and frames < 2000 and viewer.replay_cursor < viewer.replay_frames.size():
		viewer.advance_input({})
		frames += 1
	_check(viewer.replay_cursor == viewer.replay_frames.size(), "The replay runs up to the slip")
	viewer.set_block_signals(true)
	viewer._leaving = true
	viewer.queue_free()
	await process_frame
	await _watch_later_stage()
	await _watch_first_turn()
	HardMode.hand_over({"chapter_key": KEY, "kind": "watch", "run": {"pairs": [], "slip": {}}})
	viewer = Preview.new()
	viewer.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	root.add_child(viewer)
	await process_frame
	_check(viewer.mode == "error", "A run with nothing to watch says so")
	viewer._leaving = true
	viewer.queue_free()
	await process_frame

func _viewer(request: Dictionary) -> Node3D:
	HardMode.hand_over(request)
	var viewer := Preview.new()
	viewer.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	root.add_child(viewer)
	viewer.set_physics_process(false)
	viewer.set_process(false)
	await process_frame
	return viewer

func _close_viewer(viewer: Node3D) -> void:
	viewer.set_block_signals(true)
	viewer._leaving = true
	viewer.queue_free()
	await process_frame

## A slip on stage 2: Watch starts at the slip, and the stage before it is
## still there as an earlier part.
func _watch_later_stage() -> void:
	_fresh()
	var app := _screen()
	await process_frame
	for name: String in ["relay-a", "relay-b"]:
		app._show_ready()
		app._begin()
		_play(app, name)
		app._finish()
		if app.mode == "bloom": app._show_review()
		app._accept()
	app._show_ready()
	app._begin()
	_play(app, "garden-a", 3)
	app._finish()
	_check(app.mode == "hard_failed" and int(app.hard.last_run.stage_index) == 1, "A slip on stage 2 ends the run: %s %s" % [app.mode, str(app.hard.last_run.get("stage_index", -1))])
	var run: Dictionary = _runs(KEY)[0] if not _runs(KEY).is_empty() else {}
	var summary := HardMode.summaries()[0] if not HardMode.summaries().is_empty() else {}
	_check(int(summary.get("parts", 0)) == 2, "The run lists two parts: stage 1, then the slip")
	await _close(app)
	var viewer := await _viewer({"chapter_key": KEY, "kind": "watch", "id": str(run.get("id", ""))})
	_check(viewer.mode == "replay" and viewer._replay_collection.size() == 2 and viewer.replay_pair_index == 1 and viewer.checkpoint == run.slip.checkpoint, "Watch reads the run by its id and starts at the slip")
	await _close_viewer(viewer)
	viewer = await _viewer({"chapter_key": KEY, "kind": "watch", "id": str(run.get("id", "")), "part": 0})
	_check(viewer.mode == "replay" and viewer.replay_pair_index == 0 and viewer.sim.get("role") == "b", "An earlier part plays from stage 1")
	await _close_viewer(viewer)

## A slip on the very first turn has no memory beside it, and still plays.
func _watch_first_turn() -> void:
	_fresh()
	var app := _screen()
	await process_frame
	app._begin()
	_play(app, "relay-a", 3)
	app._finish()
	var run: Dictionary = _runs(KEY)[0] if not _runs(KEY).is_empty() else {}
	_check(app.mode == "hard_failed" and not run.is_empty() and run.slip.prior.is_empty(), "A first-turn slip is kept with no memory")
	_check(_button(app.overlay, PlayerCopy.HARD_WATCH_SLIP) != null, "The failure card offers Watch the slip")
	_button(app.overlay, PlayerCopy.HARD_WATCH_SLIP).pressed.emit()
	await process_frame
	_check(app.mode == "replay" and app.sim.get("role") == "a", "Watch the slip plays it on the spot")
	await _close(app)
	var viewer := await _viewer({"chapter_key": KEY, "kind": "watch", "run": run})
	_check(viewer.mode == "replay" and viewer.sim.get("role") == "a", "A first-turn slip opens from Replays")
	var frames := 0
	while viewer.mode == "replay" and frames < 400 and viewer.replay_cursor < viewer.replay_frames.size():
		viewer.advance_input({})
		frames += 1
	_check(viewer.replay_cursor == viewer.replay_frames.size(), "It plays up to the slip")
	await _close_viewer(viewer)

func _drowning() -> void:
	_clear(TIDE)
	_marks = _path("tide-marks")
	_counts = _path("tide-counts")
	var level := Registry.definition(TIDE)
	var initial := Registry.initial_checkpoint(TIDE)
	var a := TideSimulation.new()
	a.reset(level, "set-the-tide", initial, {}, "a")
	Tide.play(a, Tide.a_routes()["low"])
	var first: Dictionary = a.export_recording()
	var b := TideSimulation.new()
	b.reset(level, "set-the-tide", initial, first, "b")
	Tide.play(b, [["w", [-320, 352]], ["w", [-60, 352]]])
	while not b.finished: b.step({})
	var frames: Array = TideSimulation.expand_recording_inputs(b.export_recording())
	var journal := Journey.new(HardMode.journal_path(TIDE), null, TIDE)
	journal.load_data()
	_check(journal.accept_recording(first), "The memory's turn is kept in the hard run: " + journal.last_error)
	var screen: Node = load(Index.data(TIDE).scene).instantiate()
	screen.hard = HardRun.solo(TIDE, _marks)
	screen.turn_tries = TurnTries.new(_counts)
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.set_process(false)
	await process_frame
	_check(screen._hard_on() and screen.journey.role() == "b", "The hard Tide run waits on its second turn")
	screen._begin()
	for input: Dictionary in frames:
		if screen.mode != "play": break
		screen.advance_input(input)
	_check(screen.mode == "drowning", "A drowning still shows its beat")
	screen._end_drown_beat()
	await process_frame
	_check(screen.mode == "hard_failed" and screen.hard.last_run.reason == "drowned", "The drowning ends the hard run")
	_check(_label_text(screen, "HardLine") == PlayerCopy.HARD_YOU_WENT_UNDER % 1, "The card says you went under")
	var run: Dictionary = _runs(TIDE)[0] if not _runs(TIDE).is_empty() else {}
	_check(not run.is_empty() and run.slip.recording.role == "b" and run.slip.prior.recording_hash == first.recording_hash, "The drowned turn is kept only inside the failed run, beside its memory")
	_check(screen.journey.pairs().is_empty() and screen.journey.role() == "a" and not screen.journey.has_draft(), "The run starts again and no draft of the drowned turn remains")
	screen.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
