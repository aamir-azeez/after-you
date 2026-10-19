extends SceneTree
## Drag to turn (presentation/kit/drag_turn.gd) and the Settings header spirit
## that uses it (presentation/settings_spirit.gd):
## - A sideways drag turns it with the finger, about a turn across the
##   preview's width plus a margin; a tap does not, and one drag ticks once.
## - Mouse and touch copies of one finger turn it once, not twice.
## - A release coasts and slows to a stop the same at any frame rate; a
##   stalled frame never flings it; about 2 s after the release it eases back
##   the short way to its rest facing and stops.
## - Reduce motion: it turns with the finger only and snaps back on release.
## - The spirit draws every frame only while it turns, and at its idle rate
##   (or not at all under Reduce motion) when it rests; it takes the drag over
##   its whole rect, past a 48 px target, and lets go when hidden.
const DragTurn = preload("res://presentation/kit/drag_turn.gd")
const SettingsSpirit = preload("res://presentation/settings_spirit.gd")
const IslandWorld = preload("res://presentation/island_world.gd")

const DT := 1.0 / 60.0
const WIDTH := 72.0
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_follows_finger()
	_coast_and_return()
	_reduced()
	await _spirit_draws()
	await _spirit_reduced()
	print("AFTER YOU SPIRIT DRAG TURN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _press(turn: DragTurn, x: float, pressed: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(x, 40)
	event.pressed = pressed
	turn.handle_event(event, WIDTH)

func _move(turn: DragTurn, x: float) -> bool:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(x, 40)
	return turn.handle_event(event, WIDTH)

## Presses at 10, then moves `distance` in `frames` equal steps, a frame each.
func _drag(turn: DragTurn, distance: float, frames: int = 10, delta: float = DT) -> void:
	_press(turn, 10.0)
	for frame in range(1, frames + 1):
		_move(turn, 10.0 + distance * frame / frames)
		turn.advance(delta)

func _follows_finger() -> void:
	var turn := DragTurn.new()
	var ticks := [0]
	turn.grabbed.connect(func() -> void: ticks[0] += 1)
	_press(turn, 10.0)
	_move(turn, 12.0)
	_move(turn, 11.0)
	_press(turn, 11.0, false)
	_check(ticks[0] == 0 and not turn.dragging(), "A tap with a wobble does not tick")
	turn.offset = 0.0
	_press(turn, 10.0)
	_check(turn.dragging() and turn.busy(), "A press holds it")
	_check(_move(turn, 10.0 + WIDTH * DragTurn.SPAN * 0.5), "A move of a held drag is the drag's")
	_check(is_equal_approx(turn.offset, PI), "Half the span turns it half a turn: %.3f" % turn.offset)
	_check(turn.advance(DT), "The frame after a move reports the change")
	_check(not turn.advance(DT), "A still finger changes nothing")
	_move(turn, 10.0 + WIDTH * DragTurn.SPAN)
	_check(is_equal_approx(turn.offset, TAU), "The full span is one full turn")
	_move(turn, 10.0 - WIDTH * DragTurn.SPAN * 0.25)
	_check(is_equal_approx(turn.offset, -PI * 0.5), "Back the other way turns it back past where it started")
	_check(ticks[0] == 1, "One drag ticks once")
	# The touch copy of the same finger at the same place changes nothing.
	var before := turn.offset
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(10.0 - WIDTH * DragTurn.SPAN * 0.25, 40)
	drag.relative = Vector2(-30, 0)
	_check(turn.handle_event(drag, WIDTH) and turn.offset == before, "A touch copy of the finger turns it once, not twice")
	var second := InputEventScreenDrag.new()
	second.index = 1
	second.position = Vector2(300, 40)
	turn.handle_event(second, WIDTH)
	_check(turn.offset == before, "A second finger does not turn it")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = false
	_check(not turn.handle_event(right, WIDTH) and turn.dragging(), "Another mouse button is not the drag's")
	var cancel := InputEventScreenTouch.new()
	cancel.index = 0
	cancel.pressed = true
	cancel.canceled = true
	turn.handle_event(cancel, WIDTH)
	_check(not turn.dragging(), "A cancelled touch lets go")
	var hover := DragTurn.new()
	_check(not _move(hover, 30.0) and hover.offset == 0.0 and not hover.busy(), "A hover without a press is not a drag")

func _coast_and_return() -> void:
	var turn := DragTurn.new()
	_drag(turn, WIDTH * DragTurn.SPAN * 0.5)
	var released := turn.offset
	_press(turn, 0.0, false)
	_check(not turn.dragging() and turn.busy(), "A release lets go but it is not home yet")
	turn.advance(DT)
	var after := turn.offset
	_check(after > released, "A release keeps the spin going the same way")
	var steps := 0
	while turn._velocity != 0.0 and steps < 600:
		turn.advance(DT)
		steps += 1
	var coasted := turn.offset
	_check(steps > 10 and steps * DT < DragTurn.RETURN_DELAY, "The spin slows to a stop before the return: %.2f s" % (steps * DT))
	_check(coasted - after < DragTurn.MAX_SPIN / DragTurn.FRICTION + 0.01, "It coasts a gentle way")
	_check(not turn.advance(DT) and turn.offset == coasted, "Stopped, it waits")
	# The same coast at 30 frames a second ends at the same place.
	var slow := DragTurn.new()
	_drag(slow, WIDTH * DragTurn.SPAN * 0.5, 5, DT * 2.0)
	_press(slow, 0.0, false)
	var fast := DragTurn.new()
	fast.offset = slow.offset
	fast._velocity = slow._velocity
	for _frame in range(30): slow.advance(DT * 2.0)
	for _frame in range(60): fast.advance(DT)
	_check(fast._velocity > 0.0 and absf(slow.offset - fast.offset) < 0.0001, "A coast covers the same turn at 30 and at 60 frames a second")
	# Then, about 2 s after the release, it eases back the short way.
	var held := DragTurn.new()
	held.offset = TAU + 0.8
	held._idle = 0.0
	var waited := 0.0
	while held.offset == TAU + 0.8 and waited < 5.0:
		held.advance(DT)
		waited += DT
	_check(absf(waited - DragTurn.RETURN_DELAY) < DT * 1.5, "It starts back about 2 s after the release: %.2f s" % waited)
	_check(held.offset > 0.0 and held.offset < 0.8, "It goes back the short way, not round the turns it made")
	var last := held.offset
	var smooth := true
	var homing := 0.0
	while held.busy() and homing < 5.0:
		held.advance(DT)
		homing += DT
		smooth = smooth and held.offset <= last
		last = held.offset
	_check(smooth and held.offset == 0.0 and not held.busy(), "It eases home and stops there")
	_check(homing < 1.5, "The ease back takes about a second: %.2f s" % homing)
	_check(not held.advance(DT), "Home, nothing changes")
	# A stalled frame does not fling it.
	var stall := DragTurn.new()
	_drag(stall, WIDTH * DragTurn.SPAN * 0.5)
	_press(stall, 0.0, false)
	var at := stall.offset
	stall.advance(5.0)
	_check(stall.offset - at <= DragTurn.MAX_SPIN * DragTurn.MAX_STEP, "A stalled frame turns it no more than a short step")
	# A press catches a coasting or returning spin where it is.
	var caught := DragTurn.new()
	_drag(caught, WIDTH * DragTurn.SPAN * 0.5)
	_press(caught, 0.0, false)
	caught.advance(DT)
	_press(caught, 50.0)
	var where := caught.offset
	caught.advance(DT)
	_check(caught.offset == where and caught._velocity == 0.0, "A press catches the spin")

func _reduced() -> void:
	var turn := DragTurn.new()
	turn.reduced = true
	_drag(turn, WIDTH * DragTurn.SPAN * 0.25)
	_check(is_equal_approx(turn.offset, PI * 0.5), "Under Reduce motion it still turns with the finger")
	_press(turn, 0.0, false)
	_check(turn.offset == 0.0 and not turn.busy(), "and snaps back on release")
	_check(turn.advance(DT) and not turn.advance(DT), "The snap is one change, with no coast after it")
	var coasting := DragTurn.new()
	_drag(coasting, WIDTH * DragTurn.SPAN * 0.5)
	_press(coasting, 0.0, false)
	coasting.advance(DT)
	coasting.reduced = true
	_check(coasting.offset == 0.0 and not coasting.busy(), "Turning Reduce motion on mid spin sends it home")

func _spirit(reduced: bool) -> Control:
	var spirit: Control = SettingsSpirit.new(reduced)
	root.add_child(spirit)
	spirit.size = spirit.custom_minimum_size
	return spirit

func _yaw(spirit: Control) -> float:
	return spirit._spirit.facing.rotation.y

func _gui(spirit: Control, event: InputEvent) -> void:
	spirit._gui_input(event)

func _mouse(spirit: Control, x: float, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(x, 50)
	event.pressed = pressed
	_gui(spirit, event)

func _motion(spirit: Control, x: float) -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(x, 50)
	_gui(spirit, event)

## Draws over `frames` frames of `delta`.
func _frames(spirit: Control, frames: int, delta: float = DT) -> int:
	var before: int = spirit.drawn
	for _frame in range(frames): spirit._process(delta)
	return spirit.drawn - before

func _spirit_draws() -> void:
	var spirit := _spirit(false)
	await process_frame
	spirit.set_process(false)
	var hz := int(IslandWorld.IDLE_CARD_HZ)
	_check(spirit.mouse_filter == Control.MOUSE_FILTER_STOP and spirit.size.x >= 48 and spirit.size.y >= 48, "The spirit takes the drag over a full target")
	var compact := _spirit(false)
	compact.custom_minimum_size = Vector2(54, 75)
	compact.size = compact.custom_minimum_size
	_check(compact.size.x >= 48 and compact.size.y >= 48, "The phone header's smaller spirit is still a full target")
	compact.queue_free()
	var rest := _yaw(spirit)
	_check(is_equal_approx(rest, SettingsSpirit.REST_YAW), "It rests in its three-quarter view")
	var idle := _frames(spirit, 60)
	_check(idle >= hz - 2 and idle <= hz + 1, "Still, it draws at its idle rate: %d in 1 s" % idle)
	_mouse(spirit, 20.0, true)
	_check(_frames(spirit, 10) <= 2, "A finger held still draws no more than the idle rate")
	_motion(spirit, 20.0 + spirit.size.x * 0.3)
	_check(_frames(spirit, 1) == 1, "A move draws on the next frame")
	_check(not is_equal_approx(_yaw(spirit), rest), "and turns it")
	var follows := true
	var each := 0
	for step in range(1, 21):
		_motion(spirit, 20.0 + spirit.size.x * 0.3 + step * 3.0)
		each += _frames(spirit, 1)
		follows = follows and is_equal_approx(_yaw(spirit), wrapf(SettingsSpirit.REST_YAW + spirit.turn.offset, -PI, PI))
	_check(each == 20, "Dragging, it draws every frame: %d of 20" % each)
	_check(follows, "Its facing follows the finger exactly, every frame")
	_mouse(spirit, 100.0, false)
	var coast := _frames(spirit, 30)
	_check(coast == 30, "Coasting, it draws every frame: %d of 30" % coast)
	var settle := 0
	while spirit.turn.busy() and settle < 600:
		spirit._process(DT)
		settle += 1
	_check(not spirit.turn.busy() and is_equal_approx(_yaw(spirit), rest), "After the coast and about 2 s it is back at its rest facing")
	_check((settle + 30) * DT > DragTurn.RETURN_DELAY and (settle + 30) * DT < DragTurn.RETURN_DELAY + 2.0, "It got home %.2f s after the release" % ((settle + 30) * DT))
	idle = _frames(spirit, 60)
	_check(idle >= hz - 2 and idle <= hz + 1, "Home again, it is back at its idle rate: %d in 1 s" % idle)
	# Hidden mid drag (the page went away), it lets go.
	_mouse(spirit, 20.0, true)
	_motion(spirit, 40.0)
	spirit.hide()
	_check(not spirit.turn.dragging(), "Hidden mid drag, it lets go")
	spirit.queue_free()
	await process_frame

func _spirit_reduced() -> void:
	var spirit := _spirit(true)
	await process_frame
	var rest := _yaw(spirit)
	spirit._process(DT)
	_check(not spirit.is_processing(), "Under Reduce motion a resting spirit does not even run")
	_check(_frames(spirit, 60) == 0, "and draws nothing")
	_mouse(spirit, 20.0, true)
	_check(spirit.is_processing(), "A press wakes it")
	_check(_frames(spirit, 5) == 0, "A held finger draws nothing")
	_motion(spirit, 50.0)
	_check(_frames(spirit, 5) == 1 and not is_equal_approx(_yaw(spirit), rest), "A move draws once and turns it")
	_mouse(spirit, 50.0, false)
	_check(_frames(spirit, 5) == 1 and is_equal_approx(_yaw(spirit), rest), "A release draws once, back at its rest facing")
	_check(not spirit.is_processing() and _frames(spirit, 60) == 0, "Then it rests and draws nothing")
	# Reduce motion turned on mid spin sends it home at once.
	spirit.set_reduced(false)
	_frames(spirit, 2)
	_mouse(spirit, 20.0, true)
	for step in range(1, 6):
		_motion(spirit, 20.0 + step * 8.0)
		_frames(spirit, 1)
	_mouse(spirit, 60.0, false)
	_frames(spirit, 2)
	spirit.set_reduced(true)
	_frames(spirit, 2)
	_check(not spirit.turn.busy() and is_equal_approx(_yaw(spirit), rest), "Reduce motion turned on mid spin snaps it home")
	spirit.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
