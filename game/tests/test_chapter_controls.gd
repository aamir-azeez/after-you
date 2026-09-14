extends SceneTree

const ChapterControls = preload("res://presentation/chapter_controls.gd")

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
	root.remove_child(viewport)
	viewport.queue_free()
	await _settle()
	print("CHAPTER CONTROLS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


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
