extends RefCounted
## World kit: thick fog over a whole stage, for a look preset with a "cover"
## (kit/look.gd; Fog Marsh's "fog"). Two wide sheets of fog lie over every
## floor at two heights, one mesh and one draw, drifting slowly apart, so the
## far marsh and the other pip fade into it. It thins to nothing in a pocket
## round the pip being played, so the other pip and the memory come back up
## close, and it is thinned round every lever, control, pad and the goal so
## no control is ever lost, and cleared wide round a lit lantern. It thickens
## toward the screen's edges.
##
## Only drawing: it reads the snapshot's levers and the drawn spirit, never the
## camera, and writes no depth. The drift runs on the world's clock (drift()),
## never the shader's own, so a replay or a memory looks the same each time and
## reduce motion holds it still. It draws just over the water and under every
## other see-through thing (render_priority -1), so bubbles, tags, the values'
## chips and the lamps' glow stay on top of it; the spirits are solid, so the
## other pip fades.
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const Look = preload("res://presentation/kit/look.gd")

## The sheets' heights over the stage's highest floor (m), and how far past
## its floors they reach (m), past any camera's view.
const LAYERS := [1.5, 2.3]
const MARGIN := 16.0
## The pocket round the played pip: clear within POCKET_CLEAR (m), full fog
## from POCKET_FULL.
const POCKET_CLEAR := 1.2
const POCKET_FULL := 3.4
## A control's thinned patch (m, at least; its own radius plus SPOT_ROOM), and
## a lit lantern's clearing; SPOT_HAZE is the share of fog left in a patch.
const SPOT_RADIUS := 0.75
const SPOT_ROOM := 0.45
const LANTERN_RADIUS := 2.6
const SPOT_HAZE := 0.12
const MOST_SPOTS := 16

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.87, 0.89, 0.86, 1.0);
uniform float density = 0.7;
uniform float edge_wash = 0.6;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform float drift_time = 0.0;
uniform vec3 pocket = vec3(0.0, -100.0, 0.0);
uniform float pocket_clear = 1.0;
uniform float pocket_full = 3.0;
uniform float haze = 0.12;
uniform vec4 spots[16];
uniform int spot_count = 0;
varying vec3 world_at;
varying vec3 layer;

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	layer = COLOR.rgb;
}

// Where the line from `p` toward the camera crosses this sheet.
vec2 sight(vec3 p, vec3 back) {
	return p.xz + (world_at.y - p.y) * back.xz / back.y;
}

void fragment() {
	vec3 back = INV_VIEW_MATRIX[2].xyz;
	vec2 at = world_at.xz;
	float t = drift_time * (0.6 + layer.g);
	float broad = texture(noise, at * 0.075 + layer.g * 0.37 + vec2(t * 0.021, t * 0.008)).r;
	float fine = texture(noise, at * 0.21 - layer.g * 0.53 + vec2(-t * 0.012, t * 0.019)).r;
	float thick = density * (0.5 + 0.65 * broad) * (0.75 + 0.45 * fine);
	float open = smoothstep(pocket_clear, pocket_full, distance(at, sight(pocket, back)));
	for (int i = 0; i < 16; i++) {
		if (i >= spot_count) break;
		float reach = spots[i].w;
		open = min(open, mix(haze, 1.0, smoothstep(reach * 0.55, reach, distance(at, sight(spots[i].xyz, back)))));
	}
	vec2 edge = min(SCREEN_UV, vec2(1.0) - SCREEN_UV);
	float wash = (1.0 - smoothstep(0.0, 0.22, min(edge.x * VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, edge.y))) * edge_wash * layer.b;
	ALBEDO = tint.rgb;
	ALPHA = clamp(thick * open + wash * (1.0 - thick * open), 0.0, 0.94);
}
"""

static var _shader: Shader
static var _noise: ImageTexture

var node: MeshInstance3D
var _material: ShaderMaterial
var _spots: Array[Vector4] = []
## Lever id -> spot index, for the lanterns.
var _lanterns: Dictionary = {}
var _lit: Dictionary = {}

## The cover for a look preset's "cover" {"color", "density", "edge"} over
## `floors` (rects in cm with height_cm) under `parent`, thinned round `spots`
## [Vector3 (global m), radius (m)] and the `lanterns` {lever id: global m};
## null when the look has no cover.
static func build(look_name: String, floors: Array, spots: Array, lanterns: Dictionary, parent: Node3D) -> RefCounted:
	var cover: Dictionary = Look.preset(look_name).get("cover", {})
	if cover.is_empty() or floors.is_empty(): return null
	var made: RefCounted = load("res://presentation/kit/fog_cover.gd").new()
	made._make(cover, floors, spots, lanterns, parent)
	return made

## Thins the fog round the lanterns the snapshot's `levers` show lit.
func present(levers: Dictionary) -> void:
	var lit: Dictionary = {}
	for id: String in _lanterns: lit[id] = bool(levers.get(id, false))
	if lit == _lit: return
	_lit = lit
	for id: String in _lanterns:
		var spot := _spots[_lanterns[id]]
		spot.w = LANTERN_RADIUS if lit[id] else SPOT_RADIUS
		_spots[_lanterns[id]] = spot
	_send_spots()

## The pocket round the played pip's drawn spirit (global m).
func follow(at: Vector3) -> void:
	_material.set_shader_parameter("pocket", at)

## The drift at `seconds` on the world's clock.
func drift(seconds: float) -> void:
	_material.set_shader_parameter("drift_time", seconds)

func _make(cover: Dictionary, floors: Array, spots: Array, lanterns: Dictionary, parent: Node3D) -> void:
	var bounds := Rect2()
	var top := 0.0
	for index in range(floors.size()):
		var r: Array = floors[index].rect_cm
		var rect := Rect2(float(r[0]) / 100.0, float(r[1]) / 100.0, float(int(r[2]) - int(r[0])) / 100.0, float(int(r[3]) - int(r[1])) / 100.0)
		bounds = rect if index == 0 else bounds.merge(rect)
		top = maxf(top, float(floors[index].get("height_cm", 0)) / 100.0)
	bounds = bounds.grow(MARGIN)
	for spot: Array in spots:
		if _spots.size() < MOST_SPOTS: _spots.append(Vector4(spot[0].x, spot[0].y, spot[0].z, maxf(SPOT_RADIUS, float(spot[1]) + SPOT_ROOM)))
	for id: String in lanterns:
		if _spots.size() >= MOST_SPOTS: break
		_lanterns[id] = _spots.size()
		_spots.append(Vector4(lanterns[id].x, lanterns[id].y, lanterns[id].z, SPOT_RADIUS))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(LAYERS.size()):
		var y: float = top + LAYERS[index]
		var corners := [Vector3(bounds.position.x, y, bounds.position.y), Vector3(bounds.end.x, y, bounds.position.y), Vector3(bounds.end.x, y, bounds.end.y), Vector3(bounds.position.x, y, bounds.end.y)]
		# r: unused, g: the layer's own drift and pattern, b: its share of the edge wash.
		var tag := Color(0, float(index) * 0.5, float(index), 1)
		for corner: int in [0, 1, 2, 0, 2, 3]:
			surface.set_color(tag)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(corners[corner])
	var mesh := surface.commit()
	_material = ShaderMaterial.new()
	_material.shader = _cover_shader()
	_material.render_priority = -1
	_material.set_shader_parameter("noise", _noise_texture())
	_material.set_shader_parameter("tint", cover.get("color", Color(0.87, 0.89, 0.86)))
	_material.set_shader_parameter("density", float(cover.get("density", 0.7)))
	_material.set_shader_parameter("edge_wash", float(cover.get("edge", 0.6)))
	_material.set_shader_parameter("pocket_clear", POCKET_CLEAR)
	_material.set_shader_parameter("pocket_full", POCKET_FULL)
	_material.set_shader_parameter("haze", SPOT_HAZE)
	_send_spots()
	node = MeshInstance3D.new()
	node.name = "FogCover"
	node.mesh = mesh
	node.material_override = _material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 4.0
	parent.add_child(node)

func _send_spots() -> void:
	var padded: Array[Vector4] = _spots.duplicate()
	padded.resize(MOST_SPOTS)
	_material.set_shader_parameter("spots", padded)
	_material.set_shader_parameter("spot_count", _spots.size())

## The shared shader, kept for the session.
static func _cover_shader() -> Shader:
	if _shader != null: return _shader
	_shader = Shader.new()
	_shader.code = SHADER
	SessionRelease.on_exit(Callable(load("res://presentation/kit/fog_cover.gd"), "release"))
	return _shader

## Lets go of the kept shader and noise (SessionRelease, at shutdown).
static func release() -> void:
	_shader = null
	_noise = null

## A small soft noise that tiles: smooth value noise on two lattices, made
## the same way every time.
static func _noise_texture() -> ImageTexture:
	if _noise != null: return _noise
	const SIZE := 64
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	for y in range(SIZE):
		for x in range(SIZE):
			var value := 0.65 * _lattice(x, y, SIZE, 8) + 0.35 * _lattice(x, y, SIZE, 16)
			image.set_pixel(x, y, Color(value, value, value))
	_noise = ImageTexture.create_from_image(image)
	return _noise

static func _lattice(x: int, y: int, size: int, cells: int) -> float:
	var step := float(size) / float(cells)
	var gx := float(x) / step
	var gy := float(y) / step
	var x0 := int(gx)
	var y0 := int(gy)
	var fx := smoothstep(0.0, 1.0, gx - x0)
	var fy := smoothstep(0.0, 1.0, gy - y0)
	var a := lerpf(_hash(x0, y0, cells), _hash(x0 + 1, y0, cells), fx)
	var b := lerpf(_hash(x0, y0 + 1, cells), _hash(x0 + 1, y0 + 1, cells), fx)
	return lerpf(a, b, fy)

static func _hash(x: int, y: int, cells: int) -> float:
	return fposmod(sin(float(posmod(x, cells)) * 12.9898 + float(posmod(y, cells)) * 78.233 + float(cells)) * 43758.5453, 1.0)
