extends "res://tests/test_relay_preview.gd"
## Solo "Redo my previous turn" on the real chapter screens, by tapping. The
## offer shows on the ready, review, pause, stage-complete and finished cards
## whenever there is a saved turn to take back. Cancel, Escape and Android
## Back put the card back without writing anything. Confirming takes back one
## turn, drops a next turn still being set up for the old journey, and opens
## the turn that was taken back. Online rooms, replay-only screens and a
## chapter without access get no solo redo.
const Storage = preload("res://services/local_save.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Archive = preload("res://services/attempt_archive.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const Retained = preload("res://tests/retained_chapter_fixture.gd")
const AccessTests = preload("res://tests/test_chapter_access.gd")
const SoloRedoOffer = preload("res://presentation/solo_redo_offer.gd")
const REDO := PlayerCopy.SOLO_REDO_ACTION
const SETTINGS := {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _ready_card()
	await _review_and_stage_card()
	await _paused_turn()
	await _finished_chapter()
	await _closed_contexts()
	await _refusals()
	await _shared_chapter(Registry.WISHING_WELL, "cooperative")
	await _shared_chapter(Registry.TURN_OF_THE_TIDE, "journey")
	await _premium_access(Registry.ROLLING_HOME)
	_cleanup()
	await process_frame
	await create_timer(0.15).timeout
	print("SOLO REDO UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The second turn's ready card: Cancel, a stale confirm, Escape and Back all
## leave the journal alone; Confirm clears the first turn.
func _ready_card() -> void:
	var path := _seeded("ready")
	var app := _open(Registry.RELAY, path)
	_check(app.mode == "ready" and app.role == "a" and _find_button(app.overlay, REDO) == null, "Stage one with nothing saved offers no redo")
	_check(app.journey.accept_recording(_fixture("relay-a")), "Ready fixture accepts the first turn")
	app._show_ready()
	_check(app.mode == "ready" and app.role == "b" and _find_button(app.overlay, "Restart chapter") != null, "The second turn's ready card is up, with Restart chapter for the older rules")
	var bytes := _save_bytes(path)
	await _tap(app, REDO)
	_check(app.mode == "confirm_solo_redo" and _card_text(app).contains(PlayerCopy.SOLO_REDO_FIRST_TURN_TITLE) and not _card_text(app).contains(PlayerCopy.SOLO_REDO_DROPS_DRAFT) and Canonical.same(bytes, _save_bytes(path)), "Tapping redo asks first and writes nothing")
	_check(_find_button(app.overlay, PlayerCopy.SOLO_REDO_FIRST_TURN_CONFIRM) != null and _find_button(app.overlay, REDO) == null, "The confirm button repeats the title's verb")
	var stale: Callable = _find_button(app.overlay, PlayerCopy.SOLO_REDO_FIRST_TURN_CONFIRM).get_signal_connection_list("pressed")[0].callable
	await _tap(app, "Cancel")
	_check(app.mode == "ready" and app.role == "b" and _find_button(app.overlay, REDO) != null and Canonical.same(bytes, _save_bytes(path)), "Cancel puts the ready card back unchanged")
	stale.call()
	_check(app.mode == "ready" and app.journey.role() == "b" and Canonical.same(bytes, _save_bytes(path)), "A confirm left behind by Cancel does nothing")
	await _tap(app, REDO)
	app._unhandled_key_input(_escape())
	_check(app.mode == "ready" and app.role == "b" and Canonical.same(bytes, _save_bytes(path)), "Escape cancels the redo")
	await _tap(app, REDO)
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode == "ready" and app.role == "b" and Canonical.same(bytes, _save_bytes(path)), "Android Back cancels the redo instead of leaving")
	await _tap(app, REDO)
	await _tap(app, _confirm_label(app))
	_check(app.mode == "ready" and app.role == "a" and app.stage.id == "relay" and app.journey.prior_recording().is_empty() and app.sim.role == "a" and app.journey.is_live_simulation(app.sim), "Confirm clears the first turn and opens it again on the same stage")
	_check(app.journey.simulation_version() == 2 and app.journey.archived_attempts().is_empty() and _find_button(app.overlay, REDO) == null, "The rules stay, no archive is kept, and nothing is left to redo")
	await _close(app)

## The second turn's review and the stage-complete card, then a first turn's
## review on stage two while its next turn is still being set up.
func _review_and_stage_card() -> void:
	var path := _seeded("review")
	var app := _open(Registry.RELAY, path)
	_check(app.journey.accept_recording(_fixture("relay-a")), "Review fixture accepts the first turn")
	app._show_ready()
	await _play(app, _fixture("relay-b"))
	_check(app.mode == "review" and app.role == "b" and _find_button(app.overlay, "Restart chapter") != null, "The second turn's review is up with every action")
	var review: Dictionary = app.review.duplicate(true)
	var bytes := _save_bytes(path)
	await _tap(app, REDO)
	_check(app.mode == "confirm_solo_redo" and _card_text(app).contains(PlayerCopy.SOLO_REDO_FIRST_TURN_TITLE) and _card_text(app).contains(PlayerCopy.SOLO_REDO_DROPS_DRAFT), "Redo from a review says the unsaved turn will be lost")
	await _tap(app, "Cancel")
	_check(app.mode == "review" and app.review == review and Canonical.same(bytes, _save_bytes(path)), "Cancel returns to the same review")
	await _tap(app, "Save turn")
	_check(app.mode == "checkpoint" and app.journey.pairs().size() == 1 and _find_button(app.overlay, REDO) != null, "The stage-complete card offers redo")
	bytes = _save_bytes(path)
	await _tap(app, REDO)
	_check(app.mode == "confirm_solo_redo" and _card_text(app).contains(PlayerCopy.SOLO_REDO_STAGE_TITLE % 1) and _card_text(app).contains(PlayerCopy.SOLO_REDO_STAGE_BODY), "Redo after a saved stage offers to go back to it")
	await _tap(app, "Cancel")
	_check(app.mode == "checkpoint" and Canonical.same(bytes, _save_bytes(path)), "Cancel returns to the stage-complete card")
	await _tap(app, "Continue")
	_check(app.mode == "ready" and app.role == "a" and app.stage.id == "garden" and _find_button(app.overlay, REDO) != null, "Stage two's first turn offers to go back to stage one")
	await _play(app, _fixture("garden-a"))
	_check(app.mode == "review" and app.role == "a" and str(app._prefetch_job.get("role", "")) == "b", "The first turn's review sets up the next turn on a worker")
	var gate := Semaphore.new()
	var old_job: Dictionary = app._prefetch_job.duplicate(true)
	var held := _hold_prefetch(app, old_job, gate)
	var old_sim: RefCounted = app.sim
	await _tap(app, REDO)
	_check(app.mode == "confirm_solo_redo" and _card_text(app).contains(PlayerCopy.SOLO_REDO_STAGE_TITLE % 1) and _card_text(app).contains(PlayerCopy.SOLO_REDO_DROPS_DRAFT), "Redo from the first turn's review goes back to stage one and drops the reviewed turn")
	app.set_process(true)
	_check(_find_button(app.overlay, PlayerCopy.SOLO_REDO_STAGE_CONFIRM % 1) != null, "Going back a stage is confirmed with the stage's own button")
	_press(app, PlayerCopy.SOLO_REDO_STAGE_CONFIRM % 1)
	_check(app.mode == "turn_wait" and app._prefetch_job.is_empty() and app._prefetch_thread == null and Reaper.holds(held), "Confirm shows the wait card and hands the unfinished next turn to the reaper")
	await _until(app, "ready")
	_check(app.mode == "ready" and app.role == "b" and app.stage.id == "relay" and Canonical.same(app.journey.prior_recording(), _fixture("relay-a")) and app.journey.pairs().is_empty(), "Stage one opens at its second turn with its first turn restored")
	_check(app.sim != old_sim and app.journey.is_live_simulation(app.sim) and app.sim.role == "b" and app.sim.tick == 0, "The second turn is set up fresh for the reopened stage")
	_check(app.journey.archived_attempts().size() == 1 and _find_button(app.overlay, "Replays") != null, "The replaced attempt is kept under Replays")
	app.set_process(false)
	gate.post()
	var deadline := Time.get_ticks_msec() + 20000
	while held.is_started() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not held.is_started() and Reaper.pending_count() == 0, "The reaper joins the dropped worker once it ends")
	var built := Journey.build_live(old_job)
	_check(built.get("ok", false) and app.journey.adopt_live_simulation(old_job, built) == null, "A next turn set up for the old journey is refused")
	_check(not app.journey.save_live_draft(old_sim) and not app.journey.save_live_draft(built.simulation), "Neither the reviewed turn nor the old next turn can save a draft")
	await _close(app)

## Pause in the middle of a second turn.
func _paused_turn() -> void:
	var path := _seeded("paused")
	var app := _open(Registry.RELAY, path)
	_check(app.journey.accept_recording(_fixture("relay-a")), "Pause fixture accepts the first turn")
	app._show_ready()
	app._begin()
	var inputs: Array = app._simulation.expand_recording_inputs(_fixture("relay-b"))
	for input: Dictionary in inputs.slice(0, 20): app.advance_input(input)
	app._pause()
	_check(app.mode == "paused" and app.journey.has_draft() and _find_button(app.overlay, REDO) != null, "Pause in the middle of a turn offers redo")
	var tick: int = app.sim.tick
	var paused_sim: RefCounted = app.sim
	var bytes := _save_bytes(path)
	await _tap(app, REDO)
	_check(app.mode == "confirm_solo_redo" and _card_text(app).contains(PlayerCopy.SOLO_REDO_DROPS_DRAFT), "Redo from pause says the unsaved turn will be lost")
	await _tap(app, "Cancel")
	_check(app.mode == "paused" and app.sim == paused_sim and app.sim.tick == tick and _find_button(app.overlay, "Resume") != null and _find_button(app.overlay, REDO) != null and Canonical.same(bytes, _save_bytes(path)), "Cancel returns to the same paused turn")
	await _tap(app, REDO)
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode == "paused" and app.sim.tick == tick and Canonical.same(bytes, _save_bytes(path)), "Android Back returns to the paused turn")
	await _tap(app, "Resume")
	_check(app.mode == "play" and app.running and app.sim == paused_sim and app.sim.tick == tick, "Resume goes on from the paused turn")
	app._pause()
	await _tap(app, REDO)
	await _tap(app, _confirm_label(app))
	_check(app.mode == "ready" and app.role == "a" and not app.journey.has_draft() and app.journey.prior_recording().is_empty() and not app.running, "Confirm from pause clears the first turn and the unsaved second turn")
	await _close(app)

## The finished chapter reopens its last stage, then the stage's first turn.
func _finished_chapter() -> void:
	var path := _seeded("finished")
	var app := _open(Registry.RELAY, path)
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b"]:
		_check(app.journey.accept_recording(_fixture(name)), "Finished fixture accepts " + name)
	app._show_ready()
	_check(app.mode == "complete" and _find_button(app.overlay, REDO) != null, "The finished chapter offers redo")
	var bytes := _save_bytes(path)
	await _tap(app, REDO)
	_check(app.mode == "confirm_solo_redo" and _card_text(app).contains(PlayerCopy.SOLO_REDO_STAGE_TITLE % 2), "It offers to go back to the last stage")
	app._unhandled_key_input(_escape())
	_check(app.mode == "complete" and Canonical.same(bytes, _save_bytes(path)), "Escape returns to the finished card")
	await _tap(app, REDO)
	await _tap(app, _confirm_label(app))
	_check(app.mode == "ready" and app.role == "b" and app.stage.id == "garden" and not app.journey.chapter_complete() and Canonical.same(app.journey.prior_recording(), _fixture("garden-a")), "Confirm reopens the last stage at its second turn")
	_check(app.journey.archived_attempts().size() == 1 and app.journey.simulation_version() == 2, "The finished attempt is archived and the rules stay")
	await _tap(app, REDO)
	_check(_card_text(app).contains(PlayerCopy.SOLO_REDO_KEEPS_EARLIER), "Clearing a later stage's first turn says the earlier stages stay")
	await _tap(app, PlayerCopy.SOLO_REDO_FIRST_TURN_CONFIRM)
	_check(app.mode == "ready" and app.role == "a" and app.stage.id == "garden" and app.journey.pairs().size() == 1, "A second redo clears the last stage's first turn")
	await _close(app)

## No solo redo for an online room, a replay-only screen, a held journal or a
## card that is not one of the offer's cards.
func _closed_contexts() -> void:
	var path := _seeded("closed")
	var app := _open(Registry.RELAY, path)
	_check(app.journey.accept_recording(_fixture("relay-a")), "Closed-context fixture accepts the first turn")
	app._show_ready()
	var plan: Dictionary = app._solo_redo_plan()
	var bytes := _save_bytes(path)
	_check(not plan.is_empty(), "The solo ready card has a plan")
	app.online_session = RefCounted.new()
	_check(app._solo_redo_plan().is_empty(), "An online screen has no solo plan")
	app._confirm_solo_redo()
	app._run_solo_redo(plan)
	_check(app.mode == "ready" and app.journey.role() == "b" and Canonical.same(bytes, _save_bytes(path)), "The solo handlers do nothing on an online screen")
	app.online_session = null
	app._solo_replay_only = true
	_check(app._solo_redo_plan().is_empty(), "A replay-only screen has no solo plan")
	app._confirm_solo_redo()
	_check(app.mode == "ready", "A replay-only screen opens no confirm")
	app._solo_replay_only = false
	for held_mode: String in ["play", "turn_wait", "bloom", "replay", "error", "save_error", "confirm_retry"]:
		app.mode = held_mode
		_check(app._solo_redo_plan().is_empty(), "No plan while the screen is in " + held_mode)
	app.mode = "ready"
	app.journey.read_only = true
	_check(app._solo_redo_plan().is_empty() and app.journey.redo_plan().is_empty() and not app.journey.redo_previous(plan), "A held journal offers and takes nothing")
	app.journey.read_only = false
	_check(Canonical.same(bytes, _save_bytes(path)) and app.journey.role() == "b", "Nothing was written")
	await _close(app)

## With 32 attempts kept, going back a stage is not offered. A redo or a
## checkpoint retry refused anyway leaves the journal alone and puts the card
## the player came from back, with the reason on it.
func _refusals() -> void:
	var path := _seeded("refusals")
	var app := _open(Registry.RELAY, path)
	for name: String in ["relay-a", "relay-b"]:
		_check(app.journey.accept_recording(_fixture(name)), "Refusal fixture accepts " + name)
	app._show_ready()
	var plan: Dictionary = app._solo_redo_plan()
	_check(app.mode == "ready" and plan.get("kind") == "stage" and _find_button(app.overlay, REDO) != null, "Stage two's ready card offers to go back a stage")
	for index in range(Journey.MAX_ARCHIVED_ATTEMPTS):
		var file := FileAccess.open(path + ".attempt-" + Crypto.new().generate_random_bytes(32).hex_encode() + ".json", FileAccess.WRITE)
		file.store_string("{}")
		file.close()
	app._show_ready()
	_check(app.mode == "ready" and _find_button(app.overlay, REDO) == null, "With 32 attempts kept the ready card offers no stage redo")
	var bytes := _save_bytes(path)
	app._run_solo_redo(plan, "ready")
	_check(app.mode == "ready" and app.journey.pairs().size() == 1 and app.overlay.find_child("RefusalNote", true, false) != null and _card_text(app).contains(PlayerCopy.LIGHTHOUSE_JOURNEY_66C3BEF32753) and Canonical.same(bytes, _save_bytes(path)), "A redo refused on confirm puts the ready card back with the reason")
	app._confirm_local_checkpoint(0)
	await _tap(app, "Retry")
	_check(app.mode == "ready" and app.journey.pairs().size() == 1 and _card_text(app).contains(PlayerCopy.LIGHTHOUSE_JOURNEY_28364B9E3ABB) and Canonical.same(bytes, _save_bytes(path)), "A checkpoint retry refused at the limit returns to the ready card with the reason")
	await _close(app)

## The Well and the Tide use the shared chapter screen; redo works the same.
func _shared_chapter(key: String, folder: String) -> void:
	var stage_id := str(Registry.definition(key).stages[0].id)
	var path := _new_path("solo-redo-" + key.validate_filename())
	var app := _open(key, path)
	_check(app.mode == "ready" and app.get_script().resource_path == "res://cooperative_preview.gd" and _find_button(app.overlay, REDO) == null, key + ": opens on the shared screen with nothing to redo")
	var version: int = app.journey.simulation_version()
	_check(app.journey.accept_recording(_any_fixture(folder + "/" + stage_id + "-a")), key + ": accepts the first turn")
	app._show_ready()
	_check(app.mode == "ready" and app.role == "b" and _find_button(app.overlay, REDO) != null, key + ": the second turn offers redo")
	var bytes := _save_bytes(path)
	await _tap(app, REDO)
	await _tap(app, "Cancel")
	_check(app.mode == "ready" and app.role == "b" and Canonical.same(bytes, _save_bytes(path)), key + ": Cancel changes nothing")
	await _tap(app, REDO)
	await _tap(app, _confirm_label(app))
	_check(app.mode == "ready" and app.role == "a" and app.journey.prior_recording().is_empty() and app.journey.simulation_version() == version and app.journey.archived_attempts().is_empty(), key + ": Confirm clears the first turn and keeps the rules")
	await _close(app)

## A paid chapter whose access is withdrawn takes back nothing, from the offer
## or from a confirm already on screen.
func _premium_access(key: String) -> void:
	_check(Registry.descriptor(key).get("premium", false), key + " is a paid chapter")
	var stage_id := str(Registry.definition(key).stages[0].id)
	var path := _new_path("solo-redo-paid")
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
	_check(app._prepared and app.mode == "ready" and app.role == "b" and _find_button(app.overlay, REDO) != null, "With access the paid chapter offers redo")
	var bytes := _save_bytes(path)
	await _tap(app, REDO)
	var confirm_button := _find_button(app.overlay, _confirm_label(app))
	_check(app.mode == "confirm_solo_redo" and confirm_button != null, "The paid chapter asks before taking back a turn")
	if confirm_button == null:
		await _close(app)
		return
	var confirm: Callable = confirm_button.get_signal_connection_list("pressed")[0].callable
	var plan: Dictionary = app.journey.redo_plan()
	store.revoke()
	_check(app.mode == "access", "Withdrawn access replaces the confirm card")
	confirm.call()
	app._confirm_solo_redo()
	app._run_solo_redo(plan)
	_check(app.mode == "access" and app.journey.role() == "b" and Canonical.same(bytes, _save_bytes(path)), "Without access neither the offer nor the confirm takes back a turn")
	app.admission.check_access()
	store.answer(store.requests[-1], true)
	_check(app.mode == "ready" and _find_button(app.overlay, REDO) != null, "With access back the offer returns")
	await _tap(app, REDO)
	await _tap(app, _confirm_label(app))
	_check(app.mode == "ready" and app.role == "a" and app.journey.prior_recording().is_empty(), "With access back redo clears the first turn")
	await _close(app)

## The confirm card's button for the plan on screen.
func _confirm_label(app: Node) -> String:
	return str(SoloRedoOffer.confirm_copy(app.journey.redo_plan()).get("confirm", "?"))

func _open(key: String, path: String) -> Node:
	var app: Node = load(Registry.solo_scene(key)).instantiate()
	app.chapter_key = key
	app.journey = Journey.new(path, null, key)
	app.settings = SETTINGS.duplicate()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	return app

func _close(app: Node) -> void:
	app.queue_free()
	await _settle()

func _seeded(label: String) -> String:
	var path := _new_path("solo-redo-" + label)
	_check(Retained.seed(path, Registry.RELAY), "Seed the published older journal for " + label)
	return path

## Plays a recording on the real screen up to its review.
func _play(app: Node, recording: Dictionary) -> void:
	app._begin()
	for input: Dictionary in app._simulation.expand_recording_inputs(recording): app.advance_input(input)
	app._finish()
	if app.mode == "bloom": app._process(Preview.COMPLETION_DURATION)
	await _until(app, "review")

## Swaps the screen's prefetch for one that waits on gate before building the
## same job, so the test decides when it ends.
func _hold_prefetch(app: Node, job: Dictionary, gate: Semaphore) -> Thread:
	app._drop_prefetch()
	var thread := Thread.new()
	thread.start(Callable(get_script(), "_gated_build").bind(gate, job))
	app._prefetch_thread = thread
	app._prefetch_job = job
	return thread

static func _gated_build(gate: Semaphore, job: Dictionary) -> Dictionary:
	gate.wait()
	return Journey.build_live(job)

func _until(app: Node, wanted: String, msec: int = 0) -> void:
	var deadline := Time.get_ticks_msec() + msec
	var frame := 0
	while frame < 30 or Time.get_ticks_msec() < deadline:
		if app.mode == wanted: return
		frame += 1
		await process_frame

func _card_text(app: Node) -> String:
	var parts := PackedStringArray()
	for label: Node in app.overlay.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree(): parts.append((label as Label).text)
	return "\n".join(parts)

func _escape() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	return event

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
