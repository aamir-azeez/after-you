extends SceneTree

const StoryPanel = preload("res://presentation/story_panel.gd")
var checks := 0
var failures := 0
var requests: Array = []
var dismissals: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	root.add_child(viewport)
	var old_focus := Button.new()
	old_focus.text = "Play"
	old_focus.position = Vector2(20,20)
	old_focus.size = Vector2(140,52)
	var play_clicks := [0]
	old_focus.pressed.connect(func(): play_clicks[0] += 1)
	viewport.add_child(old_focus)
	old_focus.grab_focus()
	var panel := StoryPanel.new()
	viewport.add_child(panel)
	panel.dismissal_requested.connect(func(id: int, skipped: bool): requests.append({"id": id, "skipped": skipped}))
	panel.dismissed.connect(func(skipped: bool, saved: bool): dismissals.append({"skipped": skipped, "saved": saved}))
	var lines := [{"speaker": "p0", "text": "First line."}, {"speaker": "p1", "text": "Second line."}]
	_check(not panel.present("Chapter", lines, false), "Story refuses an active-turn presentation")
	_check(not panel.present("Chapter", [], true), "Empty story cannot trap modal input")
	_check(not panel.present("Chapter", [{"speaker":"p9", "text":"Unknown"}], true), "Unknown speakers are rejected")
	_check(not panel.present("Chapter", [{"speaker":"p0", "text":"x".repeat(281)}], true), "Oversized dialogue is rejected")
	_check(panel.present("Chapter", lines, true), "Bounded interlude opens between turns")
	await _settle()
	_check(Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(panel.card.get_global_rect()), "First opening settles inside the viewport")
	_check(panel.card.get_global_rect().encloses(panel.next_button.get_global_rect()), "First opening keeps Continue on screen")
	_check(panel.next_button.get_theme_color("font_color") == Color("193d39") and panel.next_button.get_theme_color("font_focus_color") == Color("193d39"), "Primary button text stays dark on its cream surface, including focus")
	lines[0].text = "Caller changed its draft"
	_check(panel.dialogue.text == "First line." and panel.speaker.text == "Gold", "Panel owns a copy and exposes a readable speaker name")
	_check(panel.back_button.disabled and panel.progress.text == "1 / 2", "First line cannot go backward")
	_check(viewport.gui_get_focus_owner() == panel.next_button, "Focus enters the modal")
	await _click(viewport, Vector2(40,40))
	_check(play_clicks[0] == 0 and panel.is_open(), "Clicking outside the card cannot activate the underlying Play button")
	panel._advance()
	_check(requests.is_empty() and panel.dialogue.text == "Second line." and panel.speaker.text == "Blue", "Reading changes no shared or local progress")
	panel._back()
	_check(panel.dialogue.text == "First line." and panel.back_button.disabled, "Back revisits the previous complete line")
	panel._advance()
	panel._advance()
	panel._advance()
	_check(requests.size() == 1 and not requests[-1].skipped, "Final Continue creates only one pending dismissal")
	_check(panel.is_open() and panel.next_button.disabled and panel.skip_button.disabled, "Read marker remains unresolved until owner acknowledges it")
	var first_request: int = requests[-1].id
	panel.resolve_dismissal(first_request, false, "Test storage error")
	_check(panel.is_open() and panel.next_button.text == "Retry" and panel.skip_button.text == "Close", "Local save failure offers retry and an exit")
	panel._advance()
	var retry_request: int = requests[-1].id
	_check(retry_request > first_request and requests.size() == 2, "Deliberate retry receives a new acknowledgement token")
	panel.resolve_dismissal(first_request, true)
	_check(panel.is_open() and dismissals.is_empty(), "Old acknowledgement cannot settle a newer dismissal")
	panel.resolve_dismissal(retry_request, true)
	panel.resolve_dismissal(retry_request, true)
	_check(not panel.is_open() and dismissals == [{"skipped":false,"saved":true}], "Successful acknowledgement closes exactly once")
	_check(viewport.gui_get_focus_owner() == old_focus, "Prior focus is restored after dismissal")
	_check(panel.present("Chapter", lines, true) and not panel.next_button.disabled and not panel.skip_button.disabled, "Reopening clears disabled controls")
	panel._skip()
	var cancelled_request: int = requests[-1].id
	panel.cancel()
	_check(dismissals[-1] == {"skipped":true,"saved":false}, "Identity/navigation cancellation does not mark the story seen")
	_check(panel.present("Next chapter", lines, true), "New owner can present after cancellation")
	panel._skip()
	var current_request: int = requests[-1].id
	panel.resolve_dismissal(cancelled_request, true)
	_check(panel.is_open(), "Late acknowledgement from cancelled presentation is ignored")
	panel.resolve_dismissal(current_request, false)
	panel._skip()
	_check(not panel.is_open() and dismissals[-1] == {"skipped":true,"saved":false}, "Close after a save error unblocks play without a false seen marker")
	for dimensions: Vector2i in [Vector2i(960,540), Vector2i(1280,720)]:
		viewport.size = dimensions
		panel.text_scale = 1.5
		panel.safe_rect_override = Rect2(38, 20, dimensions.x - 90, dimensions.y - 36)
		var long_line := [{"speaker":"p1", "text":"Readable dialogue stays available at a larger text size, with room for the full line and all three actions."}]
		_check(panel.present("A chapter with a longer title", long_line, true), "Large text interlude opens")
		await _settle()
		_check(panel.safe_rect_override.encloses(panel.card.get_global_rect()), "Card respects cutouts at %s" % dimensions)
		for button: Button in [panel.back_button,panel.skip_button,panel.next_button]:
			_check(panel.card.get_global_rect().encloses(button.get_global_rect()) and button.size.y >= 48, "Every touch target stays reachable inside the card")
		_check(panel.scroll.size.y >= panel.dialogue.get_theme_font_size("font_size"), "Long dialogue has at least one visible text line")
		panel._cycle_focus(1)
		_check(viewport.gui_get_focus_owner() == panel.skip_button, "Modal focus cycles to enabled controls only")
		panel.cancel()
	viewport.size = Vector2i(960,540)
	panel.safe_rect_override = Rect2(90,60,780,340)
	var overflow := [{"speaker":"p1","text":"A long line must stay readable with keyboard or gamepad controls. ".repeat(4)}]
	_check(panel.present("Chapter", overflow, true), "Long bounded text opens with a shallow safe area")
	await _settle()
	_check(panel.dialogue.size.y > panel.scroll.size.y, "Test establishes actual overflowing dialogue")
	var down := InputEventKey.new()
	down.keycode = KEY_PAGEDOWN
	down.pressed = true
	viewport.push_input(down, true)
	await _settle()
	_check(panel.scroll.scroll_vertical > 0 and requests[-1].id == current_request, "Page Down reaches overflow without advancing or dismissing the story")
	var up := InputEventKey.new()
	up.keycode = KEY_PAGEUP
	up.pressed = true
	viewport.push_input(up, true)
	await _settle()
	_check(panel.scroll.scroll_vertical == 0, "Page Up returns to the beginning")
	var pad_down := InputEventJoypadButton.new()
	pad_down.button_index = JOY_BUTTON_DPAD_DOWN
	pad_down.pressed = true
	viewport.push_input(pad_down, true)
	await _settle()
	_check(panel.scroll.scroll_vertical > 0, "Directional scroll remains available beside button focus")
	panel.cancel()
	await _click(viewport, Vector2(40,40))
	_check(play_clicks[0] == 1, "Closing the story restores underlying pointer input")
	viewport.queue_free()
	await _settle()
	print("STORY PANEL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _settle() -> void:
	for frame in range(4): await process_frame

func _click(viewport: Viewport, position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	viewport.push_input(motion, true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame
	await _settle()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
