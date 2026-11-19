extends RefCounted
## World kit: the space behind every world, and the one place a world's
## Environment is built (island_world and the GL warm-up both call
## environment(), so the warm-up compiles the programs a world draws with).
##
## It is the Environment's sky, one shader (space_backdrop.gdshader) drawn only
## where nothing in the world covers the screen, so stars can never show in
## front of a world and it adds no nodes. Its colours and accent come from the
## world's kit/look.gd preset ("sky", "stars", "far", "accent"), its detail from
## GraphicsPolicy.backdrop_detail. advance() moves it once per world frame from
## the world's own time, so it is the same at any frame rate, stops while the
## world is paused or out of the tree, and holds still under Reduce motion.

const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const SHADER := preload("res://presentation/kit/space_backdrop.gdshader")
## Accent kinds the shader draws round the view's edges.
const ACCENTS := {"none": 0, "petals": 1, "fireflies": 2, "dust": 3}
## The clock wraps here, so a world left open for hours keeps its precision.
const CLOCK_WRAP := 7200.0

const SKY := &"sky_color"
const STARS := &"star_color"
const FAR := &"far_color"
const ACCENT := &"accent_color"
const ACCENT_KIND := &"accent_kind"
const CLOCK := &"clock"
const PARALLAX := &"parallax"
const BUFFER := &"buffer_size"
const DETAIL := &"detail"
const SHOOTING := &"shooting"

## The 3D picture's size in pixels: the window's or the SubViewport's own
## pixels at the view's 3D scale. Zero without a view.
static func buffer_size(view: Viewport) -> Vector2:
	if view == null: return Vector2.ZERO
	var pixels := Vector2((view as SubViewport).size) if view is SubViewport else Vector2((view as Window).size) if view is Window else view.get_visible_rect().size
	return (pixels * minf(view.scaling_3d_scale, 1.0)).round()

## A world's Environment: flat ambient colour, linear tone mapping and this sky.
## Reflections stay off, so the sky never renders a radiance map.
static func environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(CLOCK, 0.0)
	material.set_shader_parameter(SHOOTING, 1.0)
	sky.sky_material = material
	env.sky = sky
	return env

static func _material(env: Environment) -> ShaderMaterial:
	return env.sky.sky_material as ShaderMaterial if env != null and env.sky != null else null

## Colours the backdrop from a kit/look.gd preset.
static func apply_look(env: Environment, look: Dictionary) -> void:
	var material := _material(env)
	if material == null: return
	var sky: Color = look.sky
	material.set_shader_parameter(SKY, sky)
	material.set_shader_parameter(STARS, look.stars)
	material.set_shader_parameter(FAR, look.get("far", sky.lerp(look.ambient, 0.14)))
	material.set_shader_parameter(ACCENT, look.get("accent_color", look.stars))
	material.set_shader_parameter(ACCENT_KIND, int(ACCENTS.get(str(look.get("accent", "none")), 0)))

## Low draws half the faint stars and leaves out the far islands and edge lights.
static func apply_quality(env: Environment, quality: Variant) -> void:
	var material := _material(env)
	if material != null: material.set_shader_parameter(DETAIL, 1.0 if GraphicsPolicy.backdrop_detail(quality) else 0.0)

## Whether the backdrop draws its full detail now.
static func detailed(env: Environment) -> bool:
	var material := _material(env)
	return material != null and float(material.get_shader_parameter(DETAIL)) > 0.5

## Moves the backdrop to `clock` (seconds) and shifts it with the camera. The
## view's shape and the camera are read here, so a resize, a rotation or a
## world with no camera yet are all safe. Writes only what changed.
static func advance(env: Environment, clock: float, camera: Camera3D, view: Viewport, reduced_motion: bool) -> void:
	var material := _material(env)
	if material == null: return
	if not reduced_motion: material.set_shader_parameter(CLOCK, fposmod(clock, CLOCK_WRAP))
	var shooting := 0.0 if reduced_motion else 1.0
	if material.get_shader_parameter(SHOOTING) != shooting: material.set_shader_parameter(SHOOTING, shooting)
	var size := buffer_size(view)
	if size.y > 0.0 and material.get_shader_parameter(BUFFER) != size: material.set_shader_parameter(BUFFER, size)
	if is_instance_valid(camera) and camera.is_inside_tree() and camera.size > 0.0:
		var basis := camera.global_basis
		var at := camera.global_position
		var shift := Vector2(at.dot(basis.x), at.dot(basis.y)) / camera.size
		if material.get_shader_parameter(PARALLAX) != shift: material.set_shader_parameter(PARALLAX, shift)
