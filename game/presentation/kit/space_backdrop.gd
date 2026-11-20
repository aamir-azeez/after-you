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
##
## The far islands (each a tile of a small baked atlas: six shapes, mirrored or
## not, sized and hazed by how far off they are) and cloud wisps sit in the
## world: each place has its own layout (layout_seed, from the chapter's id or
## Home), and the layers shift as the camera pans, each slower than the world,
## for depth. Zoom alone moves none of them.

const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const SHADER := preload("res://presentation/kit/space_backdrop.gdshader")
## The far island shapes, baked from six island models (the shader's `islands`).
const ISLAND_ATLAS := preload("res://assets/sky/far_islands.png")
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
const LAYOUT := &"layout_seed"
const ACCENT_LIGHTS := &"accents"
const ISLANDS := &"islands"
## Edge lights the accent draws (the shader's ACCENT_LIGHTS).
const ACCENT_COUNT := 7
## Metres of camera pan that shift a layer of share 1 by one screen height. A
## fixed span, not the camera's size, so zooming never slides the sky.
const PAN_SPAN := 10.0
## Home's own layout key.
const HOME := "home"

## A place's layout, 0 to 1, from its key without any "@N" version, so a
## gameplay update to a level keeps its sky. The same key gives the same layout
## on every visit and every device (String.hash is fixed).
static func layout_seed(key: String) -> float:
	return float(key.get_slice("@", 0).hash() & 0xFFFF) / 65536.0

## The edge lights at `clock` on a view `aspect` wide: where each sits round
## the view's edge (screen heights from the centre, y down), a petal's turn and
## its brightness. Worked out here once a frame rather than for every pixel.
static func accent_lights(kind: int, clock: float, aspect: float) -> PackedVector4Array:
	var lights := PackedVector4Array()
	for i in range(ACCENT_COUNT):
		var a := i * 0.8976 + _hash(i + 1.0) * 0.5
		var home := Vector2(cos(a) * aspect * 0.44, sin(a) * 0.4)
		match kind:
			1:
				# Petals drift sideways, sway and turn.
				var x := fposmod(home.x + clock * 0.012 + aspect * 0.5, aspect) - aspect * 0.5
				lights.append(Vector4(x, home.y + 0.02 * sin(clock * 0.6 + i), clock * 0.8 + i, 0.55))
			2:
				# Fireflies wander and pulse.
				var at := home + 0.025 * Vector2(sin(clock * 0.5 + i * 1.9), sin(clock * 0.65 + i * 2.3))
				lights.append(Vector4(at.x, at.y, 0.0, 0.55 + 0.45 * sin(clock * 1.3 + i * 2.1)))
			_:
				# Dust floats slowly up.
				lights.append(Vector4(home.x + 0.01 * sin(clock * 0.3 + i), fposmod(home.y - clock * 0.006 + 0.5, 1.0) - 0.5, 0.0, 0.4))
	return lights

static func _hash(p: float) -> float:
	p = fposmod(p * 0.1031, 1.0)
	p *= p + 33.33
	p *= p + p
	return fposmod(p, 1.0)

## Lays out the far islands and wisps for a place (layout_seed).
static func set_layout(env: Environment, key: String) -> void:
	var material := _material(env)
	if material != null: material.set_shader_parameter(LAYOUT, layout_seed(key))

## The camera offset the layers shift by, in PAN_SPAN units: where the camera
## looks across and up the screen, its offsets included.
static func pan_shift(camera: Camera3D) -> Vector2:
	var basis := camera.global_basis
	var at := camera.global_position
	return Vector2(at.dot(basis.x) + camera.h_offset, at.dot(basis.y) + camera.v_offset) / PAN_SPAN

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
	material.set_shader_parameter(LAYOUT, layout_seed(HOME))
	material.set_shader_parameter(ISLANDS, ISLAND_ATLAS)
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

## Low draws half the faint stars and leaves out the far islands, cloud wisps
## and edge lights.
static func apply_quality(env: Environment, quality: Variant) -> void:
	var material := _material(env)
	if material != null: material.set_shader_parameter(DETAIL, 1.0 if GraphicsPolicy.backdrop_detail(quality) else 0.0)

## Whether the backdrop draws its full detail now.
static func detailed(env: Environment) -> bool:
	var material := _material(env)
	return material != null and float(material.get_shader_parameter(DETAIL)) > 0.5

## Moves the backdrop to `clock` (seconds) and shifts it with the camera on
## screen: the view's current camera (an ending's or a planting's own), else
## `camera`. The view's shape and the camera are read here, so a resize, a
## rotation or a world with no camera yet are all safe. Writes only what changed.
static func advance(env: Environment, clock: float, camera: Camera3D, view: Viewport, reduced_motion: bool) -> void:
	var material := _material(env)
	if material == null: return
	var wrapped := fposmod(clock, CLOCK_WRAP)
	if not reduced_motion and material.get_shader_parameter(CLOCK) != wrapped: material.set_shader_parameter(CLOCK, wrapped)
	var shooting := 0.0 if reduced_motion else 1.0
	if material.get_shader_parameter(SHOOTING) != shooting: material.set_shader_parameter(SHOOTING, shooting)
	var size := buffer_size(view)
	if size.y > 0.0 and material.get_shader_parameter(BUFFER) != size: material.set_shader_parameter(BUFFER, size)
	var kind := int(material.get_shader_parameter(ACCENT_KIND))
	var shown_size: Variant = material.get_shader_parameter(BUFFER)
	if kind > 0 and detailed(env) and shown_size is Vector2 and (shown_size as Vector2).y > 0.0:
		var lights := accent_lights(kind, float(material.get_shader_parameter(CLOCK)), (shown_size as Vector2).x / (shown_size as Vector2).y)
		if material.get_shader_parameter(ACCENT_LIGHTS) != lights: material.set_shader_parameter(ACCENT_LIGHTS, lights)
	var shown := view.get_camera_3d() if view != null else null
	if is_instance_valid(shown): camera = shown
	if is_instance_valid(camera) and camera.is_inside_tree():
		var shift := pan_shift(camera)
		if material.get_shader_parameter(PARALLAX) != shift: material.set_shader_parameter(PARALLAX, shift)
