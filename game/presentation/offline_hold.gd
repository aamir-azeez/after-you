extends Node
## Greys out a button that needs the server while the phone is offline
## (services/connectivity.gd), and gives it back the moment the phone is online
## again, with no screen built again.
##
## One per button, an internal child of it: OfflineHold.hold(button, say).
## Without its own `say`, the reason goes to `say_default` (Main's toast).
## While offline the button takes its own disabled look (each style already
## draws one) and stays where it is; a tap on it says why through `say` (the
## screen's toast or notice) and asks the server once (Connectivity.check_now),
## so a connection that came back re-enables everything at once. Only a button
## this hold disabled is enabled again: one its screen disabled for its own
## reason (busy, nothing typed) stays as the screen left it; a screen that
## changes a held button later goes through set_enabled. A screen that makes
## its buttons again on each draw holds each new one.
const Connectivity = preload("res://services/connectivity.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PATH := "res://presentation/offline_hold.gd"
const NAME := "OfflineHold"
## Mouse emulation sends a touch twice; one reason per tap.
const TAP_GAP_MS := 400
## A press that moved further than this before it lifted was a scroll, not a tap.
const TAP_SLOP := 24.0
## How much of a held button's own drawn children shows.
const DIM := 0.45

## (text) -> void: where a reason goes when a hold has no `say` of its own (Main sets its toast).
static var say_default: Callable

var _button: BaseButton
var _say: Callable
var _held := false
var _faded := false
var _last_tap := -TAP_GAP_MS
var _pressed_at := Vector2.INF

## Holds `button` while offline; `say(text)` shows the reason on a tap. Holding
## the same button again only changes where the reason goes.
static func hold(button: BaseButton, say: Callable = Callable()) -> Node:
	if button == null: return null
	var existing := button.get_node_or_null(NodePath(NAME))
	if existing != null:
		existing._say = say
		return existing
	var made: Node = load(PATH).new()
	made.name = NAME
	made._button = button
	made._say = say
	button.add_child(made, false, Node.INTERNAL_MODE_BACK)
	return made

## A screen enables or disables a button that may be held: while offline a
## held button stays greyed and comes back enabled with the connection; one
## without a hold just takes `enabled`.
static func set_enabled(button: BaseButton, enabled: bool) -> void:
	if button == null: return
	var existing := button.get_node_or_null(NodePath(NAME))
	if existing == null or not existing.is_inside_tree():
		button.disabled = not enabled
		return
	existing._held = enabled and not Connectivity.shared().online()
	button.disabled = not enabled or existing._held
	existing._dim()

## The one refusal for anything that needs the server: while offline it says
## why through `say` (else say_default, Main's toast), asks the server once and
## returns true; online it returns false and the caller goes on.
static func refuse(say: Callable = Callable()) -> bool:
	if Connectivity.shared().online(): return false
	var sink := say if say.is_valid() else say_default
	if sink.is_valid(): sink.call(PlayerCopy.OFFLINE_NEEDS_CONNECTION)
	Connectivity.shared().check_now()
	return true

## Whether `button` is greyed out by a hold now.
static func held(button: BaseButton) -> bool:
	var existing := button.get_node_or_null(NodePath(NAME)) if button != null else null
	return existing != null and existing._held

func _enter_tree() -> void:
	var state: RefCounted = Connectivity.shared()
	if not state.changed.is_connected(_apply): state.changed.connect(_apply)
	if not _button.gui_input.is_connected(_on_input): _button.gui_input.connect(_on_input)
	_apply(state.online())

func _exit_tree() -> void:
	var state: RefCounted = Connectivity.shared()
	if state.changed.is_connected(_apply): state.changed.disconnect(_apply)

func _apply(online: bool) -> void:
	if not is_instance_valid(_button): return
	if not online and not _button.disabled:
		_button.disabled = true
		_held = true
	elif online and _held:
		_held = false
		_button.disabled = false
	_dim()

## What a button draws as its own children (an icon slot, a chevron, a content
## row) fades with it while held; its own text and fill take its disabled look.
func _dim() -> void:
	var faded := _held
	if faded == _faded: return
	_faded = faded
	for child: Node in _button.get_children():
		if child is CanvasItem: (child as CanvasItem).modulate.a = DIM if faded else 1.0

## A tap on the held button: pressed and lifted on it without moving like a
## scroll. A drag through a list that starts on it says nothing.
func _on_input(event: InputEvent) -> void:
	if not _held: return
	var touch: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) or event is InputEventScreenTouch
	if not touch: return
	var at: Vector2 = event.position
	if event.pressed:
		_pressed_at = at
		return
	var started := _pressed_at
	_pressed_at = Vector2.INF
	if started == Vector2.INF or started.distance_to(at) > TAP_SLOP or not Rect2(Vector2.ZERO, _button.size).has_point(at): return
	var now := Time.get_ticks_msec()
	if now - _last_tap < TAP_GAP_MS: return
	_last_tap = now
	refuse(_say)
