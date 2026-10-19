extends TextureRect
## The player's spirit in the Settings header: the real SpiritVisual in a
## small world of its own, resting with its idle (breath, leaf sway, a glance
## now and then; presentation/spirit_idle.gd).
##
## Like the ready and waiting cards (island_world.advance_idle) its pose is
## written IDLE_HZ times a second and the little view is drawn only then, so a
## calm Settings page draws that often and no more. Under Reduce motion one
## step settles it and nothing more is drawn. It runs only while it is in the
## tree, and the page frees it with everything else.
##
## A sideways drag on it turns it (presentation/kit/drag_turn.gd). While a
## finger turns it, or it coasts or eases back, it is drawn every frame;
## once it rests the idle rate above holds again. `turn.grabbed` fires when a
## drag starts, for the page's light haptic tick.
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
const DragTurn = preload("res://presentation/kit/drag_turn.gd")
## The owner's rate for a resting spirit on a card.
const IDLE_HZ := IslandWorld.IDLE_CARD_HZ
const PEACH := Color("f4c38d")
## The view renders at twice the control's size, so it stays sharp on a phone.
const RENDER_SCALE := 2.0
## A three-quarter view, facing a little toward the title beside it: the
## facing a turn starts from and returns to.
const REST_YAW := deg_to_rad(28.0)

var turn := DragTurn.new()
## How many times the little view has been drawn.
var drawn := 0
var _view: SubViewport
var _spirit: SpiritVisual
var _clock := 0.0
var _reduced := false
var _settled := false

func _init(reduced: bool = false) -> void:
	name = "SettingsSpirit"
	_reduced = reduced
	turn.reduced = reduced
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# The whole rect takes the drag: at least 54x75, past the 48 px target.
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(72, 100)

func _ready() -> void:
	_view = SubViewport.new()
	_view.name = "SpiritView"
	_view.size = Vector2i(custom_minimum_size * RENDER_SCALE)
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_view)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("ffe6c8")
	environment.ambient_light_energy = 0.42
	var world := WorldEnvironment.new()
	world.environment = environment
	_view.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.8
	sun.light_color = Color("ffeedd")
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(28.0), 0.0)
	_view.add_child(sun)
	_spirit = SpiritVisual.new(PEACH)
	_spirit.ground_ring.visible = false
	_spirit.ground_shadow.visible = false
	_spirit.set_expression_role("a")
	_face()
	_view.add_child(_spirit)
	var camera := Camera3D.new()
	camera.fov = 24.0
	camera.position = Vector3(0.0, 0.66, 2.45)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.53, 0.0))
	_view.add_child(camera)
	camera.current = true
	texture = _view.get_texture()
	_step(0.0)

func set_reduced(reduced: bool) -> void:
	if reduced == _reduced: return
	_reduced = reduced
	turn.reduced = reduced
	_settled = false
	set_process(true)

func _gui_input(event: InputEvent) -> void:
	if not turn.handle_event(event, size.x): return
	accept_event()
	if turn.busy(): set_process(true)

func _notification(what: int) -> void:
	# A finger lost with the page or the app's focus lets the spirit go.
	match what:
		NOTIFICATION_EXIT_TREE, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_let_go()
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree(): _let_go()

func _let_go() -> void:
	if not turn.dragging(): return
	turn.release()
	set_process(true)

func _process(delta: float) -> void:
	var turned := turn.advance(delta)
	if _settled and not turned:
		if not turn.busy(): set_process(false)
		return
	_clock += maxf(delta, 0.0)
	if not turned and _clock < 1.0 / IDLE_HZ: return
	_step(_clock)
	_clock = 0.0

func _face() -> void:
	# advance_motion eases the facing toward its target, so both are written.
	var yaw := wrapf(REST_YAW + turn.offset, -PI, PI)
	_spirit.facing_target = yaw
	_spirit.facing.rotation.y = yaw

func _step(delta: float) -> void:
	_face()
	# advance_motion ignores a zero step; the first frame poses it at rest.
	_spirit.advance_motion(Vector3.ZERO, maxf(delta, 0.001), _reduced)
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	drawn += 1
	_settled = _reduced
