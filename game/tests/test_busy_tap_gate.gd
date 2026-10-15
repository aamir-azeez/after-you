extends SceneTree
## presentation/busy_tap_gate.gd: the one gate a tap waits in while earlier
## work on its screen runs (the room hub's taps, the ready card's Begin).
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const TouchInput = preload("res://presentation/touch_input.gd")

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _frames(count: int) -> void:
	for frame in range(count): await process_frame

func _button(parent: Node, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.size = Vector2(120, 50)
	parent.add_child(button)
	return button

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var screen := Control.new()
	screen.size = Vector2(400, 300)
	viewport.add_child(screen)
	await _immediate(screen)
	await _latest_wins(screen)
	await _still_and_expiry(screen)
	await _finger_lift(screen, viewport)
	await _expiry_after_lift(screen, viewport)
	await _running_and_follow(screen)
	viewport.queue_free()
	await process_frame
	print("BUSY TAP GATE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _immediate(screen: Control) -> void:
	var gate := BusyTapGate.new(screen)
	var button := _button(screen, "Begin")
	var ran: Array = []
	gate.tap(button, "Checking room…", Callable(), func() -> void: ran.append(button.text))
	_check(ran == ["Checking room…"], "A tap with nothing to wait for runs at once, with its label up while it runs")
	_check(button.text == "Begin" and not gate.running, "The control gets its own text back after the tap ran")
	button.queue_free()

func _latest_wins(screen: Control) -> void:
	var gate := BusyTapGate.new(screen)
	var first := _button(screen, "Open")
	var second := _button(screen, "Join")
	var busy := [true]
	var ran: Array = []
	gate.tap(first, "Opening room…", func() -> bool: return not busy[0], func() -> void: ran.append("open"))
	_check(first.text == "Opening room…" and gate.waiting(), "A tap made while work runs waits, and its control says so")
	await _frames(2)
	_check(ran.is_empty(), "Nothing runs while the work runs")
	gate.tap(second, "Joining…", func() -> bool: return not busy[0], func() -> void: ran.append("join"))
	_check(first.text == "Open" and second.text == "Joining…", "A later tap replaces the earlier one, which gives its control back")
	busy[0] = false
	await _frames(2)
	_check(ran == ["join"], "Only the latest tap runs once the work ends: %s" % [ran])
	_check(second.text == "Join" and not gate.waiting(), "Both controls read as usual afterwards")
	first.queue_free()
	second.queue_free()

func _still_and_expiry(screen: Control) -> void:
	var gate := BusyTapGate.new(screen)
	var button := _button(screen, "Friends")
	var busy := [true]
	var open := [true]
	var ran: Array = []
	gate.tap(button, "Opening…", func() -> bool: return not busy[0], func() -> void: ran.append("friends"), func() -> bool: return open[0])
	open[0] = false
	await _frames(2)
	busy[0] = false
	await _frames(2)
	_check(ran.is_empty() and button.text == "Friends" and not gate.waiting(), "A tap whose screen moved on while it waited is dropped and gives its control back")
	gate.wait_ms = 200
	busy[0] = true
	var expired: Array = []
	gate.tap(button, "Opening…", func() -> bool: return not busy[0], func() -> void: ran.append("late"), Callable(), func() -> void: expired.append(button.text))
	await create_timer(0.4).timeout
	_check(expired == ["Friends"] and ran.is_empty(), "A wait past the limit gives the control back first, then says why")
	busy[0] = false
	await _frames(2)
	_check(ran.is_empty(), "An expired tap never runs later")
	button.queue_free()

func _finger_lift(screen: Control, viewport: SubViewport) -> void:
	var gate := BusyTapGate.new(screen)
	var row := _button(screen, "Row")
	row.position = Vector2(20, 120)
	var tapped := _button(screen, "Begin")
	await process_frame
	_pointer(viewport, row.position + row.size / 2.0, true)
	await process_frame
	_check(TouchInput.press_held(screen), "A finger is down on another button of the screen")
	var ran: Array = []
	gate.tap(tapped, "Checking room…", Callable(), func() -> void: ran.append("begin"))
	await _frames(3)
	_check(ran.is_empty(), "A ready tap waits while a finger is still down on the screen")
	_pointer(viewport, row.position + row.size / 2.0, false)
	await _frames(3)
	_check(ran == ["begin"], "It runs once the finger lifts")
	row.queue_free()
	tapped.queue_free()

## A wait that runs out under a finger lets the owner redraw only once the finger lifts.
func _expiry_after_lift(screen: Control, viewport: SubViewport) -> void:
	var gate := BusyTapGate.new(screen)
	gate.wait_ms = 100
	var row := _button(screen, "Row")
	row.position = Vector2(20, 200)
	var tapped := _button(screen, "Friends")
	await process_frame
	_pointer(viewport, row.position + row.size / 2.0, true)
	await process_frame
	var expired: Array = []
	gate.tap(tapped, "Opening…", func() -> bool: return false, func() -> void: pass, Callable(), func() -> void: expired.append(tapped.text))
	await create_timer(0.3).timeout
	_check(expired.is_empty() and tapped.text == "Opening…", "An expired wait holds its redraw while a finger is down on the screen")
	_pointer(viewport, row.position + row.size / 2.0, false)
	await _frames(3)
	_check(expired == ["Friends"], "It gives the control back and lets the owner redraw once the finger lifts")
	row.queue_free()
	tapped.queue_free()

func _running_and_follow(screen: Control) -> void:
	var gate := BusyTapGate.new(screen)
	var button := _button(screen, "Begin")
	var release := [false]
	var ran := [0]
	var slow := func() -> void:
		ran[0] += 1
		while not release[0]: await process_frame
	gate.tap(button, "Checking room…", Callable(), slow)
	await process_frame
	gate.tap(button, "Checking room…", Callable(), slow)
	_check(ran[0] == 1 and gate.running, "A tap while the last one still runs does nothing")
	release[0] = true
	await _frames(2)
	_check(not gate.running and button.text == "Begin", "The gate is free again once the run ends")
	# A screen that redraws while a tap waits hands over the new copy of the control.
	var busy := [true]
	gate.tap(button, "Checking room…", func() -> bool: return not busy[0], func() -> void: pass)
	var redrawn := _button(screen, "Begin")
	button.queue_free()
	gate.follow(redrawn)
	_check(redrawn.text == "Checking room…", "The redrawn control carries the waiting label")
	gate.cancel()
	_check(redrawn.text == "Begin" and not gate.waiting(), "Cancelling gives the redrawn control its own text back")
	redrawn.queue_free()

func _pointer(viewport: SubViewport, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)
