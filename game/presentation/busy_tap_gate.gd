extends RefCounted
## The one way a tap waits for earlier work on its screen (the room hub's taps,
## the ready card's Begin and Resume). Requests themselves wait their turn in
## the app's request queue; this gate waits for the screen's own flow, such as a
## room poll whose reply decides what the tap may do.
##
## A tap:
## - shows `label` on the tapped control while it waits and while it runs,
##   then gives the control its own text back if it is still there;
## - is replaced by a later tap, whose control then takes the label;
## - runs once `ready` holds, after any finger on `area` lifts, and only if
##   `still` (the owner's re-check of its screen) holds then;
## - gives the control back and calls `expired` when wait_ms passes first,
##   after any finger on `area` lifts.
## While a tap runs, further taps on this gate do nothing.

const TouchInput = preload("res://presentation/touch_input.gd")
const WAIT_MS := 10000

## The limit for this gate; tests may shorten it.
var wait_ms := WAIT_MS
var _area: Node
var _serial := 0
var _waiting: Dictionary = {}
var running := false

## `area` is the screen whose buttons a finger may still be pressing.
func _init(area: Node) -> void:
	_area = area

## The screen this gate watches for a finger.
func area() -> Node:
	return _area

## True while a tap waits for its turn.
func waiting() -> bool:
	return not _waiting.is_empty()

## `ready` and `still` may be empty Callables, which always hold.
func tap(control: Control, label: String, ready: Callable, run: Callable, still: Callable = Callable(), expired: Callable = Callable()) -> void:
	if running: return
	_serial += 1
	var serial := _serial
	_give_back()
	_hold(control, label)
	var deadline := Time.get_ticks_msec() + wait_ms
	var tree := Engine.get_main_loop() as SceneTree
	while true:
		while ready.is_valid() and not ready.call():
			if Time.get_ticks_msec() >= deadline:
				# Its owner may redraw the screen now, so a finger on it lifts first.
				if is_instance_valid(_area): await TouchInput.until_released(_area)
				if serial != _serial: return
				_give_back()
				if expired.is_valid(): expired.call()
				return
			await tree.process_frame
			if serial != _serial: return
			if still.is_valid() and not still.call():
				_give_back()
				return
		# A finger still down on the screen lifts first, so nothing is rebuilt under it.
		if is_instance_valid(_area): await TouchInput.until_released(_area)
		if serial != _serial: return
		if still.is_valid() and not still.call():
			_give_back()
			return
		if not ready.is_valid() or ready.call(): break
	# The control keeps its label while the tap runs, and gets its text back if it is still there after.
	var held := _waiting
	_waiting = {}
	running = true
	await run.call()
	running = false
	if serial == _serial and _waiting.is_empty():
		_waiting = held
		_give_back()

## A screen that redrew while a tap waits hands over the new copy of the
## tapped control, which then carries the label.
func follow(control: Control) -> void:
	if _waiting.is_empty() or not is_instance_valid(control) or control == _waiting.get("control"): return
	_hold(control, str(_waiting.get("label", "")))

## Drops a waiting tap and gives its control its own text back.
func cancel() -> void:
	_serial += 1
	_give_back()

func _hold(control: Control, label: String) -> void:
	_waiting = {"control": control, "label": label, "text": control.get("text") if is_instance_valid(control) else null}
	if is_instance_valid(control) and control.get("text") != null and not label.is_empty(): control.set("text", label)

func _give_back() -> void:
	var control: Variant = _waiting.get("control")
	if is_instance_valid(control) and _waiting.get("text") != null: control.set("text", _waiting.text)
	_waiting = {}
