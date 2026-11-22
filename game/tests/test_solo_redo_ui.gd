extends "res://tests/test_relay_preview.gd"
## Solo turns on the room page (claude-20261011/solo-save board), by tapping:
## the scene beside the room's panel, its rows in the room's order. After Save
## turn the panel says Your turn is saved above Record, Play my turn again and
## Start over; Play my turn again reopens the turn (Your turn again, Record,
## Keep it as it is) and the saved turn stays until a new one is saved. A kept
## stage and the chapter end head the panel. Start over asks first, then the
## chapter goes back to its first stage. Pause and review match the room's
## cards. Narrow screens keep the centred card. Online rooms, replay-only
## screens, hard runs and a chapter without access get none of it.
const Storage = preload("res://services/local_save.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const Retained = preload("res://tests/retained_chapter_fixture.gd")
const AccessTests = preload("res://tests/test_chapter_access.gd")
const AGAIN := PlayerCopy.REDO_PLAY_AGAIN
const KEEP := PlayerCopy.REDO_KEEP
const OVER := PlayerCopy.START_OVER_ASK
const SAVED := "Your turn is saved"
const SETTINGS := {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _saved_turn()
	await _stage_kept()
	await _pause_and_review()
	await _finished_chapter()
	await _start_over()
	await _narrow_card()
	await _closed_contexts()
	await _shared_chapter(Registry.WISHING_WELL, "cooperative")
	await _shared_chapter(Registry.TURN_OF_THE_TIDE, "journey")
	await _premium_access(Registry.ROLLING_HOME)
	_cleanup()
	await process_frame
	await create_timer(0.15).timeout
	print("SOLO REDO UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The first turn's page, then Your turn is saved: Play my turn again and Keep
## it as it is write nothing; a new turn saved replaces the old one.
func _saved_turn() -> void:
	var path := _seeded("saved")
	var app := _open(Registry.RELAY, path)
	_check(app.mode == "ready" and _panel(app) != null and _texts(app) == ["Record", OVER], "An older-rules chapter's first page has the panel with Record and Start over: " + str(_texts(app)))
	_check(app.overlay.find_child("TurnNewsHeading", true, false) == null, "Nothing has happened yet, so no heading leads the panel")
	await _play(app, _fixture("relay-a"))
	_check(_texts(app).filter(func(text: String) -> bool: return text != "React") == ["Preview", "Try again", "Save turn"] and _home_corner(app), "The review card matches the room's, Retry above Save turn, Home at its top left: " + str(_texts(app)))
	await _tap(app, "Save turn")
	_check(app.mode == "ready" and app.role == "b" and _heading(app) == SAVED, "After Save turn the panel says Your turn is saved")
	_check(_texts(app) == ["Record", AGAIN, OVER], "Record, Play my turn again and Start over, in the room's order: " + str(_texts(app)))
	var bytes := _save_bytes(path)
	var saved_a: Dictionary = app.journey.prior_recording()
	await _tap(app, AGAIN)
	_check(app.mode == "ready" and app.role == "a" and app.journey.replacing() and _heading(app) == PlayerCopy.REDO_AGAIN_NOTE and _texts(app) == ["Record", KEEP], "Play my turn again reopens the turn: Your turn again, Record, Keep it as it is: " + str(_texts(app)))
	_check(app.sim.role == "a" and app.journey.is_live_simulation(app.sim) and Canonical.same(bytes, _save_bytes(path)), "The turn is set up again and nothing is written")
	await _tap(app, KEEP)
	_check(app.mode == "ready" and app.role == "b" and not app.journey.replacing() and _heading(app) == SAVED and Canonical.same(app.journey.prior_recording(), saved_a) and Canonical.same(bytes, _save_bytes(path)), "Keep it as it is goes back to the saved turn")
	await _tap(app, AGAIN)
	app.queue_free()
	await _settle()
	var reopened := Journey.new(path)
	reopened.load_data()
	_check(reopened.role() == "b" and Canonical.same(reopened.prior_recording(), saved_a), "Leaving a turn played again keeps the saved one")
	app = _open(Registry.RELAY, path)
	await _tap(app, AGAIN)
	await _play(app, _fixture("relay-a"))
	await _tap(app, "Save turn")
	_check(app.mode == "ready" and app.role == "b" and not app.journey.replacing() and _heading(app) == SAVED and not Canonical.same(bytes, _save_bytes(path)) and app.journey.archived_attempts().is_empty(), "The new turn replaces the saved one; a first turn keeps no archive")
	await _close(app)

## A kept stage heads the next stage's panel with its own line, and Replays
## sits under it; Play my turn again reopens the stage at its second turn and
## keeps the old attempt in Replays once the new one is saved.
func _stage_kept() -> void:
	var path := _seeded("stage")
	var app := _open(Registry.RELAY, path)
	_check(app.journey.accept_recording(_fixture("relay-a")), "Stage fixture accepts the first turn")
	app._show_ready()
	await _play(app, _fixture("relay-b"))
	await _tap(app, "Save turn")
	_check(app.mode == "ready" and app.role == "a" and app.stage.id == "garden" and _heading(app) == str(app.chapter.checkpoint_title) and _card_text(app).contains(str(app.chapter.checkpoint_text)), "A kept stage heads the next stage's panel, its line under it")
	_check(_texts(app) == ["Record", AGAIN, OVER, "Replays"], "Record, Play my turn again, Start over and Replays: " + str(_texts(app)))
	var bytes := _save_bytes(path)
	await _tap(app, AGAIN)
	_check(app.mode == "ready" and app.role == "b" and app.stage.id == "relay" and _heading(app) == PlayerCopy.REDO_AGAIN_NOTE and Canonical.same(app.journey.prior_recording(), _fixture("relay-a")) and Canonical.same(bytes, _save_bytes(path)), "Play my turn again reopens stage one at its second turn, writing nothing")
	await _play(app, _fixture("relay-b"))
	await _tap(app, "Save turn")
	_check(app.mode == "ready" and app.stage.id == "garden" and app.journey.pairs().size() == 1 and app.journey.archived_attempts().size() == 1, "Saving it again keeps the old attempt in Replays")
	await _close(app)

## Pause matches the room's card and offers Redo last turn after a saved turn;
## a turn played again is paused and resumed in memory, writing nothing.
func _pause_and_review() -> void:
	var path := _seeded("pause")
	var app := _open(Registry.RELAY, path)
	_check(app.journey.accept_recording(_fixture("relay-a")), "Pause fixture accepts the first turn")
	app._show_ready()
	# A turn paused after a saved one offers Redo last turn, as a turn ending's card does.
	app._begin()
	for input: Dictionary in app._simulation.expand_recording_inputs(_fixture("relay-b")).slice(0, 20): app.advance_input(input)
	app._pause()
	_check(app.mode == "paused" and _texts(app) == ["Resume", "Try again", AGAIN] and _home_corner(app), "Pause offers Redo last turn, and Home at its top left in place of Back: " + str(_texts(app)))
	var paused := _save_bytes(path)
	await _tap(app, AGAIN)
	_check(app.mode == "ready" and app.role == "a" and app.journey.replacing() and _heading(app) == PlayerCopy.REDO_AGAIN_NOTE and Canonical.same(paused, _save_bytes(path)), "Redo last turn from Pause reopens the saved turn, writing nothing")
	await _tap(app, KEEP)
	_check(app.mode == "ready" and app.role == "b" and not app.journey.replacing() and app.journey.has_draft(), "Keep it as it is goes back to the paused turn")
	var bytes := _save_bytes(path)
	await _tap(app, AGAIN)
	app._begin()
	var inputs: Array = app._simulation.expand_recording_inputs(_fixture("relay-a"))
	for input: Dictionary in inputs.slice(0, 20): app.advance_input(input)
	var tick: int = app.sim.tick
	app._pause()
	_check(app.mode == "paused" and _texts(app) == ["Resume", "Try again"] and _home_corner(app) and _card_text(app) == "Take your time.", "The pause card matches the room's, its title alone with no line under it: " + str(_texts(app)))
	_check(app.journey.has_draft() and Canonical.same(bytes, _save_bytes(path)), "A turn played again keeps its draft in memory")
	await _tap(app, "Resume")
	_check(app.mode == "play" and app.sim.tick == tick, "Resume goes on from the paused turn")
	await _close(app)

## The chapter end on the panel: its two lines, then Play my turn again, Start
## over and Replays, and nothing else.
func _finished_chapter() -> void:
	var path := _seeded("end")
	var app := _open(Registry.RELAY, path)
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b"]:
		_check(app.journey.accept_recording(_fixture(name)), "Finished fixture accepts " + name)
	app._show_ready()
	_check(app.mode == "complete" and _panel(app) != null and _heading(app) == PlayerCopy.RELAY_PREVIEW_8D42D9E99BAF and _card_text(app).contains(str(app.chapter.completion_text)), "The chapter end heads the panel with its own lines")
	_check(_texts(app) == [AGAIN, OVER, "Replays"], "Play my turn again, Start over and Replays: " + str(_texts(app)))
	await _tap(app, AGAIN)
	_check(app.mode == "ready" and app.role == "b" and app.stage.id == "garden" and not app.journey.chapter_complete() and _heading(app) == PlayerCopy.REDO_AGAIN_NOTE, "Play my turn again reopens the last stage at its second turn")
	await _tap(app, KEEP)
	_check(app.mode == "complete" and app.journey.chapter_complete() and app.journey.archived_attempts().is_empty(), "Keep it as it is goes back to the finished chapter")
	await _close(app)

## Start over asks first on the room's card with the chapter's line; Cancel
## writes nothing; confirming goes back to stage one and keeps the attempt.
func _start_over() -> void:
	var path := _seeded("over")
	var app := _open(Registry.RELAY, path)
	for name: String in ["relay-a", "relay-b", "garden-a"]:
		_check(app.journey.accept_recording(_fixture(name)), "Start over fixture accepts " + name)
	app._show_ready()
	var bytes := _save_bytes(path)
	await _tap(app, OVER)
	var card: Node = app.ui.find_child("StartOverConfirm", true, false)
	_check(card != null and _labels(card).contains(PlayerCopy.SOLO_START_OVER_BODY) and Canonical.same(bytes, _save_bytes(path)), "Start over asks first, with the chapter's line")
	_press_in(card, PlayerCopy.START_OVER_CANCEL)
	await _settle()
	_check(app.mode == "ready" and app.journey.pairs().size() == 1 and Canonical.same(bytes, _save_bytes(path)), "Cancel writes nothing")
	await _tap(app, OVER)
	card = app.ui.find_child("StartOverConfirm", true, false)
	_press_in(card, PlayerCopy.START_OVER_CONFIRM)
	await _settle()
	_check(app.mode == "ready" and app.role == "a" and app.stage.id == "relay" and app.journey.pairs().is_empty() and app.journey.archived_attempts().size() == 1, "Start over goes back to the first stage and keeps the attempt in Replays")
	_check(_texts(app) == ["Record", "Replays"], "Back at the start: Record, and the kept attempt's Replays: " + str(_texts(app)))
	await _close(app)

## Screens narrower than 880 keep the centred card, with the same rows.
func _narrow_card() -> void:
	# A phone held upright: the logical screen narrower than 880.
	var base := root.content_scale_size
	root.content_scale_size = Vector2i(800, 720)
	root.size = Vector2i(800, 720)
	var path := _seeded("narrow")
	var app := _open(Registry.RELAY, path)
	_check(app.journey.accept_recording(_fixture("relay-a")), "Narrow fixture accepts the first turn")
	await _settle()
	app._show_ready()
	_check(app.ui.size.x < 880 and app.mode == "ready" and _panel(app) == null, "A narrow screen keeps the centred card: %s" % app.ui.size)
	_check(_heading(app) == SAVED and _find_button(app.overlay, AGAIN) != null and _find_button(app.overlay, OVER) != null, "with the same heading and rows: " + str(_texts(app)))
	await _close(app)
	root.content_scale_size = base
	root.size = Vector2i(1280, 720)

## No solo rows for an online room, a replay-only screen, a hard run or a held journal.
func _closed_contexts() -> void:
	var path := _seeded("closed")
	var app := _open(Registry.RELAY, path)
	_check(app.journey.accept_recording(_fixture("relay-a")), "Closed-context fixture accepts the first turn")
	app._show_ready()
	_check(app.redo_flow.can_replace() and app.redo_flow.can_ask_start_over(), "The solo page offers both")
	var bytes := _save_bytes(path)
	app._solo_replay_only = true
	_check(not app.redo_flow.solo() and not app.redo_flow.can_replace(), "A replay-only screen offers neither")
	app._solo_replay_only = false
	app.journey.read_only = true
	_check(not app.redo_flow.solo() and not app.journey.begin_replace(app.journey.redo_plan()), "A held journal offers and takes nothing")
	app.journey.read_only = false
	app.mode = "play"
	await app._redo_self()
	app._start_over_ask()
	_check(app.mode == "play" and not app.journey.replacing() and app.ui.find_child("StartOverConfirm", true, false) == null, "A tap from a page that moved on does nothing")
	app.mode = "ready"
	_check(Canonical.same(bytes, _save_bytes(path)) and app.journey.role() == "b", "Nothing was written")
	await _close(app)

## The Well and the Tide use the shared chapter screen; it works the same.
func _shared_chapter(key: String, folder: String) -> void:
	var stage_id := str(Registry.definition(key).stages[0].id)
	var path := _new_path("solo-panel-" + key.validate_filename())
	var app := _open(key, path)
	_check(app.mode == "ready" and app.get_script().resource_path == "res://cooperative_preview.gd" and _find_button(app.overlay, AGAIN) == null, key + ": opens on the shared screen with nothing to play again")
	_check(app.journey.accept_recording(_any_fixture(folder + "/" + stage_id + "-a")), key + ": accepts the first turn")
	app._show_ready()
	var bytes := _save_bytes(path)
	await _tap(app, AGAIN)
	_check(app.mode == "ready" and app.role == "a" and app.journey.replacing() and Canonical.same(bytes, _save_bytes(path)), key + ": Play my turn again reopens the first turn")
	await _tap(app, KEEP)
	_check(app.mode == "ready" and app.role == "b" and not app.journey.replacing(), key + ": Keep it as it is goes back")
	await _close(app)

## A paid chapter whose access is withdrawn plays nothing again and starts nothing over.
func _premium_access(key: String) -> void:
	_check(Registry.descriptor(key).get("premium", false), key + " is a paid chapter")
	var stage_id := str(Registry.definition(key).stages[0].id)
	var path := _new_path("solo-panel-paid")
	# The published recordings are pinned to the chapter's first rules.
	_check(Retained.seed(path, key), "Seed the published older journal for " + key)
	var seed := Journey.new(path, null, key)
	seed.load_data()
	_check(seed.accept_recording(_any_fixture("cooperative/" + stage_id + "-a")), "Paid fixture accepts the first turn")
	var store := AccessTests.Store.new()
	store._configuration = {"purchase_mode": "google_play", "entitlement_id": "full_journey_play"}
	var app: Node = load(Registry.solo_scene(key)).instantiate()
	app.chapter_key = key
	app.journey = Journey.new(path, null, key)
	app.settings = SETTINGS.duplicate()
	app.purchase_service_factory = func(): return store
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	store.answer(store.requests[-1], true)
	_check(app._prepared and app.mode == "ready" and app.role == "b" and _find_button(app.overlay, AGAIN) != null, "With access the paid chapter offers Play my turn again")
	var bytes := _save_bytes(path)
	store.revoke()
	_check(app.mode == "access", "Withdrawn access replaces the page")
	await app._redo_self()
	app._start_over_ask()
	_check(app.mode == "access" and not app.journey.replacing() and app.journey.role() == "b" and Canonical.same(bytes, _save_bytes(path)), "Without access nothing is played again or started over")
	app.admission.check_access()
	store.answer(store.requests[-1], true)
	await _tap(app, AGAIN)
	_check(app.mode == "ready" and app.role == "a" and app.journey.replacing(), "With access back Play my turn again works")
	await _close(app)

func _open(key: String, path: String) -> Node:
	var app: Node = load(Registry.solo_scene(key)).instantiate()
	app.chapter_key = key
	app.journey = Journey.new(path, null, key)
	app.settings = SETTINGS.duplicate()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	return app

## A journal seeded with the published older rules, which the v2 fixtures play.
func _seeded(label: String) -> String:
	var path := _new_path("solo-panel-" + label)
	_check(Retained.seed(path, Registry.RELAY), "Seed the published older journal for " + label)
	return path

func _close(app: Node) -> void:
	app.queue_free()
	await _settle()

## The room page's panel, when the page is drawn on it.
func _panel(app: Node) -> Node:
	return app.overlay.find_child("RoomActionsPanel", true, false)

## What heads the page: the panel's (or card's) news heading.
func _heading(app: Node) -> String:
	var heading := app.overlay.find_child("TurnNewsHeading", true, false) as Label
	return heading.text if heading != null and heading.is_visible_in_tree() else ""

## The card's Home square: first on its title line, before the title, a full
## touch target, named Home for screen readers.
func _home_corner(app: Node) -> bool:
	var home := app.overlay.find_child("CardHome", true, false) as Button
	if home == null or home.get_parent().name != "CardTitleLine" or home.get_index() != 0: return false
	return home.is_visible_in_tree() and home.get_parent().get_child(1) is Label and home.custom_minimum_size.x >= 48.0 and home.custom_minimum_size.y >= 48.0 and home.accessibility_name == PlayerCopy.MENU_HOME

## The page's buttons that show, in order, without the panel's Back.
func _texts(app: Node) -> Array[String]:
	var texts: Array[String] = []
	for button: Button in app.overlay.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and not button.text.is_empty(): texts.append(button.text)
	return texts

## Plays a recording on the real screen up to its review.
func _play(app: Node, recording: Dictionary) -> void:
	app._begin()
	for input: Dictionary in app._simulation.expand_recording_inputs(recording): app.advance_input(input)
	app._finish()
	if app.mode == "bloom": app._process(Preview.COMPLETION_DURATION)
	await _until(app, "review")

func _until(app: Node, wanted: String, msec: int = 0) -> void:
	var deadline := Time.get_ticks_msec() + msec
	var frame := 0
	while frame < 30 or Time.get_ticks_msec() < deadline:
		if app.mode == wanted: return
		frame += 1
		await process_frame

func _card_text(app: Node) -> String:
	return _labels(app.overlay)

func _labels(node: Node) -> String:
	var parts := PackedStringArray()
	for label: Node in node.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree(): parts.append((label as Label).text)
	return "\n".join(parts)

func _any_fixture(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + name + ".json"))
	if not value is Dictionary:
		_check(false, "Fixture is readable: " + name)
		return {}
	return value

func _tap(app: Node, text: String) -> void:
	await _settle()
	var button := _find_button(app.overlay, text)
	_check(button != null and not button.disabled, "Rendered chapter action is reachable: " + text)
	if button == null or button.disabled: return
	_check(app.ui.get_global_rect().encloses(button.get_global_rect()), "Chapter action stays within the scaled safe viewport: " + text)
	var point := button.get_global_rect().get_center()
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		root.push_input(event, true)
	await _settle()

func _settle() -> void:
	await process_frame
	await process_frame

func _cleanup() -> void:
	for path: String in paths:
		var directory := DirAccess.open(path.get_base_dir())
		if directory == null: continue
		for name: String in directory.get_files():
			if name == path.get_file() or name.begins_with(path.get_file() + "."):
				DirAccess.remove_absolute(path.get_base_dir().path_join(name))
