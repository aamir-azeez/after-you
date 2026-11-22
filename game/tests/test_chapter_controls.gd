extends SceneTree
const Exploration = preload("res://presentation/camera_exploration.gd")

const ChapterControls = preload("res://presentation/chapter_controls.gd")
const Cooperative = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var controls := ChapterControls.new()
	viewport.add_child(controls)
	var stack: VBoxContainer = controls.card("Revisit a checkpoint", "Choose an earlier place to rehearse. The saved contributions remain unchanged until you confirm a new attempt.")
	var activations: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	var rows: Array[Button] = []
	for index in range(activations.size()):
		var row_index: int = index
		var row: Button = controls.button("Checkpoint %d" % (index + 1) if index < 6 else "Keep the current journey", func(): activations[row_index] += 1)
		stack.add_child(row)
		rows.append(row)
	await _settle()
	var scroll: ScrollContainer = controls.modal_scroll
	var area := Rect2(Vector2.ZERO, Vector2(viewport.size))
	_check(area.grow(0.5).encloses(scroll.get_global_rect()), "The long chapter card keeps its scrolling area inside a small landscape viewport")
	_check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "Six checkpoints and Back actually overflow the bounded card")
	for row: Button in rows:
		_check(row.mouse_filter == Control.MOUSE_FILTER_PASS, "Chapter buttons let the parent recognize drag gestures")
	var received := {"presses": 0, "motions": 0, "starts": 0}
	scroll.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			received.presses += 1
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			received.motions += 1)
	scroll.scroll_started.connect(func(): received.starts += 1)
	var original_touch_emulation := Input.emulate_touch_from_mouse
	# Headless Godot 4.7.2 uses this supported flag for touchscreen availability.
	# Exercise ScrollContainer's real gesture handling through viewport input;
	# do not call its handlers or emit its signals to manufacture a scroll.
	Input.emulate_touch_from_mouse = true
	var can_drag := DisplayServer.is_touchscreen_available()
	_check(can_drag, "The runtime exposes the native touchscreen drag path; missing coverage is a failure")
	var point := rows[0].get_global_rect().get_center()
	_check(scroll.get_global_rect().has_point(point), "The initial tap targets a visible chapter button")
	_pointer(viewport, point, true)
	_pointer(viewport, point, false)
	_check(activations[0] == 1 and received.presses == 1, "A viewport tap reaches the chapter callback once and bubbles to its scroll parent")
	if can_drag:
		var start := rows[2].get_global_rect().get_center()
		_check(scroll.get_global_rect().has_point(start), "The drag starts on a visible button rather than empty card space")
		await _drag(viewport, start, Vector2(0, -120))
		_check(received.motions > 0 and received.starts == 1 and scroll.scroll_vertical > 0, "Dragging a chapter button moves the real scrolling card")
		_check(activations == [1, 0, 0, 0, 0, 0, 0], "A recognized drag cancels its button press without selecting a checkpoint")
		# The former setting must fail through the exact same input route.
		scroll.scroll_vertical = 0
		await _settle()
		var blocker := rows[2]
		var original_filter := blocker.mouse_filter
		blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		var before_starts: int = received.starts
		var before_presses: int = received.presses
		await _drag(viewport, blocker.get_global_rect().get_center(), Vector2(0, -120))
		_check(received.starts == before_starts and received.presses == before_presses and scroll.scroll_vertical == 0, "STOP reproduces the old blocked button-drag regression")
		_check(activations == [1, 0, 0, 0, 0, 0, 0], "The blocked negative-control drag does not accidentally activate another row")
		blocker.mouse_filter = original_filter
	for row: Button in rows:
		scroll.ensure_control_visible(row)
		await _settle()
		_check(scroll.get_global_rect().grow(0.5).encloses(row.get_global_rect()), "Each checkpoint and the final Back action can be brought completely into view")
		point = row.get_global_rect().get_center()
		_pointer(viewport, point, true)
		_pointer(viewport, point, false)
	_check(activations == [2, 1, 1, 1, 1, 1, 1], "Every chapter button remains tappable exactly once after scrolling")
	Input.emulate_touch_from_mouse = original_touch_emulation
	_check(Input.emulate_touch_from_mouse == original_touch_emulation, "Restore the process input setting after the gesture test")
	await _long_hint_layout()
	await _reset_view_chip()
	for left_handed: bool in [false, true]:
		for reduced: bool in [false, true]: await _watching_spot(left_handed, reduced)
	await _replay_mark()
	root.remove_child(viewport)
	viewport.queue_free()
	await _settle()
	print("CHAPTER CONTROLS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


class ViewWorld extends Node:
	var camera_exploration := Exploration.new()
	var resets := 0
	func _init() -> void:
		add_child(camera_exploration)
	func reset_camera_exploration() -> void:
		resets += 1
		camera_exploration.zoom_ratio = 1.0
		camera_exploration.pan = Vector2.ZERO

## Chapters offer Home's Reset view chip once the view has been pinched or panned.
func _reset_view_chip() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1560, 720)
	root.add_child(viewport)
	var controls := ChapterControls.new()
	viewport.add_child(controls)
	var world := ViewWorld.new()
	viewport.add_child(world)
	controls.watch_view(world)
	controls.show_play()
	await _settle()
	_check(not controls.reset_view_button.visible, "Reset view stays hidden at the authored view")
	world.camera_exploration.zoom_ratio = 0.7
	await _settle()
	_check(controls.reset_view_button.is_visible_in_tree() and controls.reset_view_button.text == "Reset view", "Zooming a chapter reveals Reset view")
	_check(not controls.reset_view_button.get_global_rect().intersects(controls.pause_button.get_global_rect()) and not controls.reset_view_button.get_global_rect().intersects(controls.chapter_label.get_global_rect()), "Reset view clears the title and Pause")
	controls.reset_view_button.pressed.emit()
	await _settle()
	_check(world.resets == 1 and not controls.reset_view_button.visible, "Reset view restores the chapter's authored view")
	viewport.queue_free()
	await _settle()

## Watching (a friend's turn before the hand-off, a replay): the stick's spot
## shows the camera in a ring filling toward the hand-off, inside the screen
## for either hand, and takes no movement; the hand-off turns it back into
## the stick, popping unless Reduce motion, and a finger held through it
## steers at once. A replay's watch leaves no stick behind.
func _watching_spot(left_handed: bool, reduced: bool) -> void:
	var way := "%s hand%s" % ["left" if left_handed else "right", ", Reduce motion" if reduced else ""]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	root.add_child(viewport)
	var controls := ChapterControls.new()
	controls.settings = {"left_handed": left_handed, "reduced_motion": reduced}
	viewport.add_child(controls)
	controls.show_play()
	var stick: Control = controls.stick
	var home := stick.get_global_rect()
	controls.show_playback("Waiting for Sam", 0.75)
	controls.update_state("Watch", 20.0, {}, true)
	await _settle()
	_check(controls.watching() and stick.is_visible_in_tree() and stick.watching and is_equal_approx(stick.watch_progress, 0.25), way + ": watching shows the ring a quarter full in the stick's spot")
	_check(stick.get_global_rect() == home and Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(home), way + ": the watch sits in the stick's own place, inside the screen")
	var shown: float = stick.watch_progress
	controls.show_playback("Waiting for Sam", 0.7499)
	_check(stick.watch_progress == shown, way + ": a tick that moves the ring by nothing visible changes nothing")
	_touch(viewport, home.get_center() + Vector2(48.0, 0.0), true)
	_check(stick.value == Vector2.ZERO, way + ": a finger on the watch moves nothing")
	controls.hide_memory_wait()
	controls.update_state("Play", 20.0, {}, true)
	_check(not controls.watching() and stick.visible and not stick.watching, way + ": the hand-off turns the watch back into the stick")
	_check(stick.value.x > 0.5, way + ": the finger held through the hand-off steers at once")
	_check((stick.scale.x < 1.0) != reduced, way + ": the stick pops back, except with Reduce motion")
	_touch(viewport, home.get_center(), false)
	controls.show_watching(0.5)
	controls.update_state("Replay", 20.0, {}, false)
	_check(stick.visible and stick.watching and not controls.action_button.visible and not controls.finish_button.visible, way + ": a replay shows the watch and no live controls")
	controls.hide_watching()
	controls.update_state("Replay", 20.0, {}, false)
	_check(not stick.visible, way + ": after a replay's watch no stick is left")
	viewport.queue_free()
	await _settle()

## Open turns: the timer marks where the friend's replay ends in this turn
## (replay_ticks), a notch in the friend's pip colour under the track that
## fills once passed, clear of a ghost race's tick and pip above it, and gone
## with no replay.
func _replay_mark() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	root.add_child(viewport)
	var controls := ChapterControls.new()
	viewport.add_child(controls)
	controls.show_play()
	var bar: Control = controls.turn_progress
	var state := {"tick": 100, "duration_ticks": 600, "replay_ticks": 200, "players": {"p0": {"ghost": true}, "p1": {"ghost": false}}}
	controls.update_state("Turn", 500.0 / 30.0, state, true)
	await _settle()
	_check(is_equal_approx(bar.replay_ratio, 1.0 / 3.0) and bar.replay_color == SpiritLook.PEACH and not bar.replay_passed, "The replay's end is marked at its tick in the friend's colour, not yet passed")
	_check(absf(bar.replay_mark_rect().get_center().x - bar.track_x(1.0 / 3.0)) < 0.01, "The notch sits on the track where the seed will be at that tick")
	var draws: int = bar.draw_count
	controls.update_state("Turn", 500.0 / 30.0, state, true)
	await _settle()
	_check(bar.draw_count == draws, "An unchanged mark redraws nothing")
	state.tick = 200
	controls.update_state("Turn", 400.0 / 30.0, state, true)
	_check(bar.replay_passed, "The notch fills once the replay has ended")
	var pip := Control.new()
	pip.custom_minimum_size = Vector2(24, 28)
	bar.set_race_mark(1.0 / 3.0, pip)
	for rect: Rect2 in bar.race_mark_rects(): _check(not rect.intersects(bar.replay_mark_rect()), "The notch keeps clear of a ghost race's mark at the same moment")
	_check(bar.race_mark_rects().size() == 2, "The ghost race's tick and pip are both checked")
	state.players = {"p0": {"ghost": false}, "p1": {"ghost": true}}
	controls.update_state("Turn", 400.0 / 30.0, state, true)
	_check(bar.replay_color == SpiritLook.MINT, "A guest friend's notch is mint")
	state.replay_ticks = 0
	controls.update_state("Turn", 400.0 / 30.0, state, true)
	_check(bar.replay_ratio < 0.0 and bar.replay_mark_rect().size == Vector2.ZERO, "No replay, no notch")
	viewport.queue_free()
	await _settle()

func _touch(viewport: SubViewport, position: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = position
	touch.pressed = pressed
	viewport.push_input(touch, true)

func _long_hint_layout() -> void:
	var level := Catalog.definition("rolling-home@1")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cooperative/weight-of-a-friend-a.json"))
	var verified := Cooperative.verify_recording(level, record, Catalog.initial_checkpoint(level))
	_check(verified.get("valid", false) and verified.get("snapshot", {}).get("can_commit", false), "The long hint comes from the actual accepted Rolling Home source recording")
	if not verified.get("valid", false): return
	for left_handed: bool in [false, true]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(960, 540)
		root.add_child(viewport)
		var controls := ChapterControls.new()
		controls.settings = {"left_handed": left_handed}
		viewport.add_child(controls)
		controls.show_play()
		controls.update_state("Rolling Home · 1 / 2 · Your first turn", 20.0, verified.snapshot, true)
		await _settle()
		var hint: Label = controls.hint_label
		var rect := hint.get_global_rect()
		_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(rect), "The wrapped source instruction stays inside a small landscape viewport for either hand")
		for control: Control in [controls.stick, controls.finish_button, controls.action_button]:
			_check(not rect.intersects(control.get_global_rect()), "The full hint leaves the movement, Finish, and interaction targets unobstructed for either hand")
		_check(hint.get_line_count() > 1 and hint.get_visible_line_count() == hint.get_line_count(), "The actual long instruction wraps and keeps every line visible")
		viewport.queue_free()
		await _settle()


func _pointer(viewport: SubViewport, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)


func _drag(viewport: SubViewport, start: Vector2, distance: Vector2) -> void:
	_pointer(viewport, start, true)
	for step in range(1, 9):
		var event := InputEventMouseMotion.new()
		event.position = start + distance * float(step) / 8.0
		event.global_position = event.position
		event.relative = distance / 8.0
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(event, true)
	_pointer(viewport, start + distance, false)
	await _settle()


func _settle() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
