extends RefCounted
## Drag to turn: a sideways drag across a spirit preview turns the spirit
## around its vertical axis. The finger maps straight to the turn, about one
## full turn across the preview's width plus a margin; a release lets the
## spin coast and slow to a stop, and after RETURN_DELAY with no touch the
## spirit eases back to its rest facing along the short way round. Under
## Reduce motion it turns with the finger only and snaps back on release.
##
## Logic only, so any preview can use it: the preview forwards its
## _gui_input (handle_event), calls advance() every frame while busy(), and
## writes `offset` on top of its own rest facing. advance() says whether the
## offset changed, so a preview draws every frame only while the spirit turns
## and keeps its own calm rate otherwise. `grabbed` fires once per drag, when
## the finger has really moved, for a light haptic tick.
signal grabbed

## Finger travel for one full turn, as a share of the preview's width.
const SPAN := 1.3
## Sideways travel before a press counts as a drag (and ticks once).
const SLOP := 4.0
## How fast a released spin slows (per second), its cap, and when it stops.
const FRICTION := 3.0
const MAX_SPIN := 5.0 * PI
const STOP_SPIN := 0.15
## Seconds with no touch before the spirit turns back, how quickly it eases
## home, and how close counts as home.
const RETURN_DELAY := 2.0
const RETURN_RATE := 6.0
const HOME := 0.002
## A stalled frame never flings the spirit.
const MAX_STEP := 0.1

## Radians added to the preview's rest facing.
var offset := 0.0
var reduced := false:
	set(value):
		if value == reduced: return
		reduced = value
		if reduced and not _dragging: _home()
var _dragging := false
var _moved := false
var _press_x := 0.0
var _press_offset := 0.0
var _sampled := 0.0
var _velocity := 0.0
var _idle := 0.0
var _changed := false

## Feeds one GUI event (local positions). True when the event belongs to the
## drag, so the preview accepts it and nothing behind scrolls or acts. Mouse
## and touch streams may both arrive for one finger; the turn comes from the
## finger's position, so a repeated event changes nothing.
func handle_event(event: InputEvent, width: float) -> bool:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT: return false
		if button.pressed and not button.canceled: _press(button.position.x)
		else: release()
		return true
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index != 0: return true
		if touch.pressed and not touch.canceled: _press(touch.position.x)
		else: release()
		return true
	if event is InputEventMouseMotion:
		if _dragging: _follow((event as InputEventMouseMotion).position.x, width)
		return _dragging
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _dragging and drag.index == 0: _follow(drag.position.x, width)
		return true
	return false

## Ends a drag: the spin coasts (or snaps home under Reduce motion). Also for
## a lost finger: the preview left the screen or the app lost focus.
func release() -> void:
	if not _dragging: return
	_dragging = false
	_idle = 0.0
	if reduced: _home()
	else: _velocity = clampf(_velocity, -MAX_SPIN, MAX_SPIN)

func dragging() -> bool:
	return _dragging

## True while a finger holds it, it spins, or it is still away from home.
func busy() -> bool:
	return _dragging or offset != 0.0

## One frame. True when the offset changed since the last call (by the
## finger or by the coast and return).
func advance(delta: float) -> bool:
	var step := clampf(delta, 0.0, MAX_STEP)
	if _dragging:
		if step > 0.0:
			var sample := (offset - _sampled) / step
			_velocity = lerpf(_velocity, sample, 1.0 - exp(-25.0 * step))
		_sampled = offset
	elif offset != 0.0 and step > 0.0:
		_idle += step
		if _velocity != 0.0:
			# Exact decay over the step, so the coast is the same at any frame rate.
			var decay := exp(-FRICTION * step)
			offset += _velocity * (1.0 - decay) / FRICTION
			_velocity *= decay
			if absf(_velocity) < STOP_SPIN: _velocity = 0.0
			_changed = true
		if _idle >= RETURN_DELAY:
			_velocity = 0.0
			offset = wrapf(offset, -PI, PI)
			offset *= exp(-RETURN_RATE * step)
			if absf(offset) < HOME: offset = 0.0
			_changed = true
	var changed := _changed
	_changed = false
	return changed

func _press(x: float) -> void:
	_dragging = true
	_moved = false
	_press_x = x
	_press_offset = offset
	_sampled = offset
	_velocity = 0.0
	_idle = 0.0

func _follow(x: float, width: float) -> void:
	var travel := x - _press_x
	if not _moved and absf(travel) >= SLOP:
		_moved = true
		grabbed.emit()
	var turned := _press_offset + travel * TAU / maxf(width * SPAN, 1.0)
	if turned != offset:
		offset = turned
		_changed = true

func _home() -> void:
	_velocity = 0.0
	_idle = 0.0
	if offset != 0.0:
		offset = 0.0
		_changed = true
