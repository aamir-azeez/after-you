extends Node
## How often the app draws. Without a cap a 120 Hz phone drew the whole 3D
## scene up to 120 times a second on every screen, menus and waiting cards
## included, and ran hot. The current scene (Main or a chapter) says what it
## needs through frame_demand():
##   ACTIVE   play, replays, the completion moment, moving the camera: the
##            player's frame rate, 60 a second unless they chose otherwise
##   CALM     menus, cards, waiting: at most 30 a second, and a frame is drawn
##            only when something on screen changed
##   LOADING  a chapter's world being built a step per frame: no cap, so the
##            build finishes sooner
## A scene without frame_demand() counts as ACTIVE. Any touch, key or mouse
## input brings full rate back at once and keeps it while a finger is down and
## for a moment after, and every change of demand does the same for a shorter
## moment, so taps, scrolls and page changes stay smooth.
##
## The player's frame rate (Settings > Graphics: 30, 60 or Unlimited) sets
## play's rate and the rate for the moments after a touch; Unlimited is the
## screen's refresh, 120 on many phones. A menu left alone keeps its own cap
## of 30 and still draws only when something changes.
##
## Presentation only. Physics stays at 30 ticks a second, and the simulation,
## its input and its recordings never depend on how many frames are drawn.
const ACTIVE := "active"
const CALM := "calm"
const LOADING := "loading"
const ACTIVE_FPS := 60
const CALM_FPS := 30
## A phone app that lost focus but is still on screen (notification shade,
## split screen). Backgrounded apps are not drawn by Android at all.
const AWAY_FPS := 10
const INPUT_WAKE_MSEC := 2000
const CHANGE_WAKE_MSEC := 1000

## Headless runs (tests, tools) are left alone: a cap there would only slow
## every suite that waits on frames.
var enabled := DisplayServer.get_name() != "headless"
## Play's frames a second (0 = no cap), set from the saved frame rate by
## GraphicsPolicy.apply.
var play_fps := ACTIVE_FPS
var _mobile := OS.has_feature("mobile")
var _focused := true
var _touches: Dictionary = {}
var _wake_until := 0
var _demand := ""

## Frame cap (0 = none) and whether to draw only on change, for a demand.
static func target(demand: String, waking: bool, focused: bool = true, mobile: bool = false, play: int = ACTIVE_FPS) -> Dictionary:
	if demand == LOADING: return {"fps": 0, "low": false}
	if mobile and not focused: return {"fps": AWAY_FPS, "low": true}
	if demand == CALM and not waking: return {"fps": CALM_FPS, "low": true}
	return {"fps": play, "low": false}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	get_tree().root.window_input.connect(_on_input)

## Every input event the window receives, before any Control can handle it.
func _on_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed: _touches[event.index] = true
		else: _touches.erase(event.index)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: _touches[-1] = true
		else: _touches.erase(-1)
	wake(INPUT_WAKE_MSEC)

func wake(msec: int) -> void:
	_wake_until = maxi(_wake_until, Time.get_ticks_msec() + msec)

func waking() -> bool:
	return not _touches.is_empty() or Time.get_ticks_msec() < _wake_until

func current() -> Dictionary:
	return {"demand": _demand, "fps": Engine.max_fps, "low": OS.low_processor_usage_mode}

func _process(_delta: float) -> void:
	if not enabled: return
	_apply()

func _apply() -> void:
	var scene := get_tree().current_scene
	var demand := str(scene.frame_demand()) if is_instance_valid(scene) and scene.has_method("frame_demand") else ACTIVE
	if demand != _demand:
		_demand = demand
		_wake_until = maxi(_wake_until, Time.get_ticks_msec() + CHANGE_WAKE_MSEC)
	var next := target(demand, waking(), _focused, _mobile, play_fps)
	if Engine.max_fps != next.fps: Engine.max_fps = next.fps
	if OS.low_processor_usage_mode != next.low: OS.low_processor_usage_mode = next.low

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_focused = false
		_touches.clear()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_focused = true
		wake(CHANGE_WAKE_MSEC)
