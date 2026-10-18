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
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const IDLE_HZ := 12.0
const PEACH := Color("f4c38d")
## The view renders at twice the control's size, so it stays sharp on a phone.
const RENDER_SCALE := 2.0

var _view: SubViewport
var _spirit: SpiritVisual
var _clock := 0.0
var _reduced := false
var _settled := false

func _init(reduced: bool = false) -> void:
	name = "SettingsSpirit"
	_reduced = reduced
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	# A three-quarter view, facing a little toward the title beside it.
	_spirit.facing_target = deg_to_rad(28.0)
	_spirit.facing.rotation.y = _spirit.facing_target
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
	_settled = false
	set_process(true)

func _process(delta: float) -> void:
	if _settled:
		set_process(false)
		return
	_clock += maxf(delta, 0.0)
	if _clock < 1.0 / IDLE_HZ: return
	_step(_clock)
	_clock = 0.0

func _step(delta: float) -> void:
	# advance_motion ignores a zero step; the first frame poses it at rest.
	_spirit.advance_motion(Vector3.ZERO, maxf(delta, 0.001), _reduced)
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_settled = _reduced
