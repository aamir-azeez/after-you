extends TextureRect
## A live pip on its own: the real SpiritVisual in a small world of its own
## (kit/pip_stage.gd), wearing `outfit`, resting with its idle (breath, leaf
## sway, a glance now and then; presentation/spirit_idle.gd). Screens use it
## through kit/pip_avatar.gd, which also draws still pips.
##
## Like the ready and waiting cards (island_world.advance_idle) its pose is
## written IDLE_HZ times a second and the little view is drawn only then, so a
## calm screen draws that often and no more. Under Reduce motion one step
## settles it and nothing more is drawn. It runs only while it is in the tree,
## and the screen frees it with everything else.
##
## A sideways drag on it turns it (presentation/kit/drag_turn.gd). While a
## finger turns it, or it coasts or eases back, it is drawn every frame; once
## it rests the idle rate above holds again. `turn.grabbed` fires when a drag
## starts, for a light haptic tick. While a finger holds it, it squeezes its
## eyes shut (spirit_look.gd SQUEEZE), and every frame of the eyes' swap is
## drawn so the change reads.
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const Stage = preload("res://presentation/kit/pip_stage.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
const DragTurn = preload("res://presentation/kit/drag_turn.gd")
const Look = preload("res://presentation/spirit_look.gd")
## The owner's rate for a resting spirit on a card.
const IDLE_HZ := IslandWorld.IDLE_CARD_HZ
const PEACH := Color("f4c38d")
## The view renders at twice the control's size, so it stays sharp on a phone.
const RENDER_SCALE := 2.0
## A three-quarter view: the facing a turn starts from and returns to.
const REST_YAW := deg_to_rad(28.0)
## The usual size: at least 54x75 takes the drag, past the 48 px target. A
## small preview beside a label (the Friends name chip) may ask for less.
const MIN_SIZE := Vector2(72, 100)

var turn := DragTurn.new()
## How many times the little view has been drawn.
var drawn := 0
## The facing it rests in (radians); a preview may face another way.
var rest_yaw := REST_YAW
## What the pip wears (services/outfit.gd); set before it enters the tree, or
## change it with wear().
var outfit: Dictionary = {}
var _view: SubViewport
var _spirit: SpiritVisual
var _camera: Camera3D
var _color := PEACH
var _clock := 0.0
var _reduced := false
var _settled := false
var _held := false
## A face change still to draw (under Reduce motion it swaps at once).
var _face_due := false

func _init(reduced: bool = false, color: Color = PEACH, size_at_least: Vector2 = MIN_SIZE) -> void:
	name = "SpiritPreview"
	_reduced = reduced
	_color = color
	turn.reduced = reduced
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# The whole rect takes the drag.
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = size_at_least

func _ready() -> void:
	_view = SubViewport.new()
	_view.name = "SpiritView"
	_view.size = Vector2i(custom_minimum_size * RENDER_SCALE)
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_view)
	_spirit = Stage.pip(_color, outfit)
	_face()
	_camera = Stage.build(_view, _spirit, outfit)
	texture = _view.get_texture()
	_step(0.0)

## Dresses the pip in `worn` and draws it once.
func wear(worn: Dictionary) -> void:
	outfit = worn.duplicate()
	if _spirit == null: return
	_spirit.wear(outfit)
	Stage.frame(_camera, outfit)
	_step(0.0)

func set_reduced(reduced: bool) -> void:
	if reduced == _reduced: return
	_reduced = reduced
	turn.reduced = reduced
	_settled = false
	set_process(true)

## Whether a finger holds it now.
func held() -> bool:
	return _held

func _gui_input(event: InputEvent) -> void:
	if not turn.handle_event(event, size.x): return
	accept_event()
	_hold_face()
	if turn.busy(): set_process(true)

func _notification(what: int) -> void:
	# A finger lost with the screen or the app's focus lets the spirit go.
	match what:
		NOTIFICATION_EXIT_TREE, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_let_go()
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree(): _let_go()

func _let_go() -> void:
	if not turn.dragging(): return
	turn.release()
	_hold_face()
	set_process(true)

func _process(delta: float) -> void:
	var turned := turn.advance(delta)
	if _settled and not turned and not _face_due:
		if not turn.busy(): set_process(false)
		return
	_clock += maxf(delta, 0.0)
	var face_moving := _face_due or _spirit.face_art.swapping()
	if not turned and not face_moving and _clock < 1.0 / IDLE_HZ: return
	_step(_clock)
	_clock = 0.0

func _hold_face() -> void:
	var holding := turn.dragging()
	if holding == _held: return
	_held = holding
	_spirit.set_expression(Look.SQUEEZE if holding else Look.NORMAL)
	_face_due = true
	set_process(true)

func _face() -> void:
	# advance_motion eases the facing toward its target, so both are written.
	var yaw := wrapf(rest_yaw + turn.offset, -PI, PI)
	_spirit.facing_target = yaw
	_spirit.facing.rotation.y = yaw

func _step(delta: float) -> void:
	_face()
	# advance_motion ignores a zero step; the first frame poses it at rest.
	_spirit.advance_motion(Vector3.ZERO, maxf(delta, 0.001), _reduced)
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	drawn += 1
	_settled = _reduced
	_face_due = false
