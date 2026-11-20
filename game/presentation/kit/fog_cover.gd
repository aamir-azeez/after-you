extends RefCounted
## World kit: thick fog over a whole stage, for a look preset with a "cover"
## (kit/look.gd; Fog Marsh's "fog"). One sheet of fog lies over every floor,
## one mesh and one draw: a soft blue-green body with lighter tops, a second,
## deeper layer seen through it that slides past as the camera follows, and a
## slow drift. It thins to nothing in a pocket round the pip being played, and
## it opens for good wherever the stage's pips have walked and round every
## lantern lit in it (kit/turn_paths.gd: the stage's recorded history plus the
## turn being played), so the way walked stays clear between turns while the
## way ahead is still fog. Every lever, control, pad and the goal is thinned
## from the start so no control is ever lost. It thickens toward the screen's
## edges.
##
## Only drawing: nothing reaches the simulation. The cleared fog is one small
## mask (MASK_CELL metres a texel, the floors plus MASK_MARGIN), painted on the
## CPU in bounded steps (one stamp a metre walked, MOST_STAMPS a frame) and
## sent to the GPU at most every UPLOAD_GAP seconds. The mask holds the ground
## each fog pixel looks down to along the camera's fixed view, so floors of
## any height clear where they are seen; a change of view paints it again.
## The drift runs on the world's clock (drift()), never the shader's own, so a
## replay or a memory looks the same each time and Reduce motion holds it still.
## It draws just over the water and under every other see-through thing
## (render_priority -1), so bubbles, tags and the values' chips stay on top of
## it; lamp light on the ground (a look's "glow_order") is drawn under it.
## Low quality takes one fog layer: no fine grain and no deeper layer.
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const Look = preload("res://presentation/kit/look.gd")

## The sheet's height over the stage's highest floor (m): tall landmarks stand
## up out of it, everything lower is under it. MARGIN: how far past the floors
## it reaches (m), past any camera's view.
const LIFT := 1.4
const MARGIN := 40.0
## The pocket round the played pip: clear within POCKET_CLEAR (m), full fog
## from POCKET_FULL.
const POCKET_CLEAR := 1.2
const POCKET_FULL := 3.4
## A control's thinned patch (m, at least; its own radius plus SPOT_ROOM).
const SPOT_RADIUS := 0.75
const SPOT_ROOM := 0.45
## How much fog is left where it has been opened.
const HAZE := 0.16
## How far round a pip's path the fog opens (m), and round a lit lantern,
## which pushes it back over LANTERN_GROW seconds.
const PATH_RADIUS := 2.2
const LANTERN_REACH := 5.5
const LANTERN_GROW := 1.8
## The mask: metres a texel, metres past the floors, a stamp each STAMP_STEP
## metres walked, at most MOST_STAMPS stamps a frame and an upload at most every
## UPLOAD_GAP seconds while it changes.
const MASK_CELL := 0.5
const MASK_MARGIN := 7.0
const STAMP_STEP := 1.0
const MOST_STAMPS := 48
const UPLOAD_GAP := 0.1
## How long a new camera view holds before the mask is painted for it (s).
const VIEW_SETTLE := 0.25

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 lit_tint : source_color = vec4(0.84, 0.90, 0.88, 1.0);
uniform vec4 deep_tint : source_color = vec4(0.55, 0.69, 0.68, 1.0);
uniform float density = 0.78;
uniform float edge_wash = 0.6;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform float drift_time = 0.0;
uniform bool detail = true;
uniform vec3 pocket = vec3(0.0, -100.0, 0.0);
uniform float pocket_clear = 1.2;
uniform float pocket_full = 3.4;
uniform float haze = 0.16;
uniform sampler2D reveal_map : filter_linear, repeat_disable;
uniform vec4 reveal_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float reveal_base = 0.0;
uniform vec4 growing = vec4(0.0, -100.0, 0.0, 0.0);
varying vec3 world_at;

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 back = INV_VIEW_MATRIX[2].xyz;
	vec2 slope = back.xz / back.y;
	vec2 at = world_at.xz;
	float t = drift_time;
	float broad = texture(noise, at * 0.055 + vec2(t * 0.018, t * 0.007)).r;
	float body = broad;
	float deep = broad;
	if (detail) {
		float fine = texture(noise, at * 0.17 + vec2(-t * 0.011, t * 0.016)).r;
		// A second layer a metre and a half lower, seen through the first.
		deep = texture(noise, (at - 1.5 * slope) * 0.09 + vec2(0.37 - t * 0.009, t * 0.012)).r;
		body = broad * 0.6 + fine * 0.25 + deep * 0.15;
	}
	float thick = density * (0.52 + 0.62 * body);
	// The ground this pixel looks down to, where the cleared fog is kept.
	vec2 ground = at - (world_at.y - reveal_base) * slope;
	vec2 uv = (ground - reveal_rect.xy) * reveal_rect.zw;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float open = mix(1.0, haze, texture(reveal_map, uv).r * inside);
	open = min(open, smoothstep(pocket_clear, pocket_full, distance(at, pocket.xz + (world_at.y - pocket.y) * slope)));
	open = min(open, mix(haze, 1.0, smoothstep(growing.w * 0.5, growing.w + 0.01, distance(at, growing.xz + (world_at.y - growing.y) * slope))));
	vec2 edge = min(SCREEN_UV, vec2(1.0) - SCREEN_UV);
	float wash = (1.0 - smoothstep(0.0, 0.22, min(edge.x * VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, edge.y))) * edge_wash;
	float fog = thick * open;
	// Lighter tops over a deeper blue-green body: the fog has depth.
	ALBEDO = mix(deep_tint.rgb, lit_tint.rgb, smoothstep(0.18, 0.8, broad * 0.75 + (1.0 - deep) * 0.25));
	ALPHA = clamp(fog + wash * (1.0 - fog), 0.0, 0.95);
}
"""

static var _shader: Shader
static var _noise: ImageTexture

var node: MeshInstance3D
var _material: ShaderMaterial
## Fixed thinned spots [Vector3 (global m), radius (m)] and the lanterns {lever id: global m}.
var _spots: Array = []
var _lanterns: Dictionary = {}
var _root: Node3D
## The mask: its rect (m, x and z), size, bytes and texture; the ground height
## it is painted at, and the view slope (back.xz / back.y) it was painted for.
var _rect := Rect2()
var _size := Vector2i.ZERO
var _bytes := PackedByteArray()
var _image: Image
var _texture: ImageTexture
var _base := 0.0
var _slope := Vector2.ZERO
var _kernels: Dictionary = {}
## Every stamp so far [x, z, height (m), radius], each once, and those still to paint.
var _stamps: Array = []
var _stamped: Dictionary = {}
var _queue: Array = []
var _dirty := false
var _since_upload := 0.0
var _paths: RefCounted
## A lantern's clearing growing now: lever id, where, and the world's clock it was lit at.
var _growing := {}
var _clock := 0.0
var _pending_slope := Vector2.INF
var _view_still := 0.0
var _last_delta := 0.0

## The cover for a look preset's "cover" {"color", "deep", "density", "edge"}
## over `floors` (rects in cm with height_cm) under `parent`, thinned round
## `spots` [Vector3 (global m), radius (m)] and the `lanterns` {lever id: global
## m}; null when the look has no cover.
static func build(look_name: String, floors: Array, spots: Array, lanterns: Dictionary, parent: Node3D) -> RefCounted:
	var cover: Dictionary = Look.preset(look_name).get("cover", {})
	if cover.is_empty() or floors.is_empty(): return null
	var made: RefCounted = load("res://presentation/kit/fog_cover.gd").new()
	made._make(cover, floors, spots, lanterns, parent)
	return made


## The pocket round the played pip's drawn spirit (global m).
func follow(at: Vector3) -> void:
	_material.set_shader_parameter("pocket", at)

## The drift at `seconds` on the world's clock.
func drift(seconds: float) -> void:
	_material.set_shader_parameter("drift_time", seconds)

## Low quality: one layer.
func set_quality(quality: String) -> void:
	_material.set_shader_parameter("detail", quality != "low")

## Opens the fog where `paths` (kit/turn_paths.gd) says the stage has been,
## all of it now: a new turn's history, or this cover built again.
func show_paths(paths: RefCounted) -> void:
	_paths = paths
	_repaint()

## What the turn being played added (turn_paths note()'s result): its new
## squares queued, a lantern lit now growing its clearing.
func paths_changed(change: Dictionary) -> void:
	if _paths == null: return
	if change.rewound:
		_repaint()
		return
	for index in range(int(change.from_points), _paths.live_points.size()):
		var entry: Array = _paths.live_points[index]
		_queue_point(int(entry[1]), int(entry[2]), int(entry[3]))
	for index in range(int(change.from_levers), _paths.live_levers.size()):
		var id: String = _paths.live_levers[index][1]
		if not _lanterns.has(id): continue
		_finish_growing()
		_growing = {"id": id, "at": _lanterns[id], "since": _clock}

## Each frame: the lantern's clearing grows, the queued stamps are painted a
## few at a time, and the mask goes up when it changed (at most every UPLOAD_GAP).
func advance(delta: float, clock: float) -> void:
	_clock = clock
	_last_delta = maxf(delta, 0.0)
	_watch_view()
	if not _growing.is_empty():
		var grown := clampf((clock - float(_growing.since)) / LANTERN_GROW, 0.0, 1.0)
		var at: Vector3 = _growing.at
		_material.set_shader_parameter("growing", Vector4(at.x, at.y, at.z, lerpf(SPOT_RADIUS, LANTERN_REACH, smoothstep(0.0, 1.0, grown))))
		if grown >= 1.0: _finish_growing()
	var painted := 0
	while not _queue.is_empty() and painted < MOST_STAMPS:
		_paint(_queue.pop_front())
		painted += 1
	_since_upload += maxf(delta, 0.0)
	if _dirty and _since_upload >= UPLOAD_GAP: _upload()

## The mask's bytes and the stamps painted (tests: the same history paints the same).
func mask_bytes() -> PackedByteArray:
	return _bytes

func stamp_count() -> int:
	return _stamps.size()

func _finish_growing() -> void:
	if _growing.is_empty(): return
	_queue_lantern(str(_growing.id))
	_growing = {}
	_material.set_shader_parameter("growing", Vector4(0, -100, 0, 0))

## The whole mask again from the fixed spots, the history and the live turn.
func _repaint() -> void:
	_growing = {}
	_material.set_shader_parameter("growing", Vector4(0, -100, 0, 0))
	_bytes.fill(0)
	_stamps.clear()
	_stamped.clear()
	_queue.clear()
	for spot: Array in _spots: _queue_stamp(spot[0], float(spot[1]), "spot|%s" % [spot[0]])
	if _paths != null:
		var points: PackedInt32Array = _paths.history_points
		for at in range(0, points.size(), 3): _queue_point(points[at], points[at + 1], points[at + 2])
		for entry: Array in _paths.live_points: _queue_point(int(entry[1]), int(entry[2]), int(entry[3]))
		for id: String in _paths.levers_lit():
			if _lanterns.has(id): _queue_lantern(id)
	while not _queue.is_empty(): _paint(_queue.pop_front())
	_upload()

func _queue_point(x_cm: int, z_cm: int, h_cm: int) -> void:
	# One stamp a STAMP_STEP square of floor (terrain metres, which are global here).
	var at := _root.to_global(Vector3(x_cm / 100.0, h_cm / 100.0, z_cm / 100.0))
	var key := "p|%d|%d|%d" % [floori(at.x / STAMP_STEP), floori(at.z / STAMP_STEP), floori(at.y / STAMP_STEP)]
	_queue_stamp(Vector3((floori(at.x / STAMP_STEP) + 0.5) * STAMP_STEP, at.y, (floori(at.z / STAMP_STEP) + 0.5) * STAMP_STEP), PATH_RADIUS, key)

func _queue_lantern(id: String) -> void:
	_queue_stamp(_lanterns[id], LANTERN_REACH, _lantern_key(id))

func _lantern_key(id: String) -> String:
	return "l|" + id

func _queue_stamp(at: Vector3, radius: float, key: String) -> void:
	if _stamped.has(key): return
	_stamped[key] = true
	var stamp := [at, radius]
	_stamps.append(stamp)
	_queue.append(stamp)

## One soft disc of open fog (it only ever opens more), at the ground its
## spot is seen at along the view.
func _paint(stamp: Array) -> void:
	var at: Vector3 = stamp[0]
	var seen := Vector2(at.x, at.z) - (at.y - _base) * _slope
	var cell := Vector2i(((seen - _rect.position) / MASK_CELL).floor())
	var kernel: Array = _kernel(float(stamp[1]))
	var offsets: PackedInt32Array = kernel[0]
	var values: PackedByteArray = kernel[1]
	var reach: int = kernel[2]
	if cell.x - reach < 0 or cell.y - reach < 0 or cell.x + reach >= _size.x or cell.y + reach >= _size.y: return
	var origin := cell.y * _size.x + cell.x
	for index in range(offsets.size()):
		var texel := origin + offsets[index]
		if values[index] > _bytes[texel]:
			_bytes[texel] = values[index]
			_dirty = true

## A disc's texels as offsets from its middle texel and their openness, made
## once per radius for this mask's width.
func _kernel(radius: float) -> Array:
	if _kernels.has(radius): return _kernels[radius]
	var r := radius / MASK_CELL
	var reach := ceili(r)
	var offsets := PackedInt32Array()
	var values := PackedByteArray()
	for y in range(-reach, reach + 1):
		for x in range(-reach, reach + 1):
			var d := Vector2(x, y).length() / r
			if d >= 1.0: continue
			offsets.append(y * _size.x + x)
			values.append(int(round(255.0 * (1.0 - smoothstep(0.5, 1.0, d)))))
	_kernels[radius] = [offsets, values, reach]
	return _kernels[radius]

func _upload() -> void:
	_image.set_data(_size.x, _size.y, false, Image.FORMAT_L8, _bytes)
	_texture.update(_image)
	_dirty = false
	_since_upload = 0.0

## The camera's view sets where each spot is seen; a new view paints again.
func _watch_view() -> void:
	if not is_instance_valid(node) or not node.is_inside_tree(): return
	var camera := node.get_viewport().get_camera_3d()
	if camera == null: return
	var back := camera.global_basis.z
	if absf(back.y) < 0.05: return
	var slope := Vector2(back.x, back.z) / back.y
	if slope.distance_to(_slope) < 0.002:
		_view_still = 0.0
		return
	# The first view paints at once; a turning camera (an ending's circle)
	# repaints only once it has held still.
	if _pending_slope != Vector2.INF and _pending_slope.distance_to(slope) >= 0.002:
		_pending_slope = slope
		_view_still = 0.0
		return
	_view_still += _last_delta
	if _pending_slope != Vector2.INF and _view_still < VIEW_SETTLE: return
	_pending_slope = slope
	_slope = slope
	_repaint()

func _make(cover: Dictionary, floors: Array, spots: Array, lanterns: Dictionary, parent: Node3D) -> void:
	_root = parent
	var bounds := Rect2()
	var top := -INF
	var low := INF
	for index in range(floors.size()):
		var r: Array = floors[index].rect_cm
		var rect := Rect2(float(r[0]) / 100.0, float(r[1]) / 100.0, float(int(r[2]) - int(r[0])) / 100.0, float(int(r[3]) - int(r[1])) / 100.0)
		bounds = rect if index == 0 else bounds.merge(rect)
		var height := float(floors[index].get("height_cm", 0)) / 100.0
		top = maxf(top, height)
		low = minf(low, height)
	for spot: Array in spots: _spots.append([spot[0], maxf(SPOT_RADIUS, float(spot[1]) + SPOT_ROOM)])
	for id: String in lanterns:
		_lanterns[id] = lanterns[id]
		_spots.append([lanterns[id], SPOT_RADIUS])
	var sheet := bounds.grow(MARGIN)
	var y := top + LIFT
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector3(sheet.position.x, y, sheet.position.y), Vector3(sheet.end.x, y, sheet.position.y), Vector3(sheet.end.x, y, sheet.end.y), Vector3(sheet.position.x, y, sheet.end.y)]
	for corner: int in [0, 1, 2, 0, 2, 3]:
		surface.set_normal(Vector3.UP)
		surface.add_vertex(corners[corner])
	_material = ShaderMaterial.new()
	_material.shader = _cover_shader()
	_material.render_priority = -1
	_material.set_shader_parameter("noise", _noise_texture())
	_material.set_shader_parameter("lit_tint", cover.get("color", Color("d6e6e2")))
	_material.set_shader_parameter("deep_tint", cover.get("deep", Color("8db0ae")))
	_material.set_shader_parameter("density", float(cover.get("density", 0.78)))
	_material.set_shader_parameter("edge_wash", float(cover.get("edge", 0.6)))
	_material.set_shader_parameter("pocket_clear", POCKET_CLEAR)
	_material.set_shader_parameter("pocket_full", POCKET_FULL)
	_material.set_shader_parameter("haze", HAZE)
	node = MeshInstance3D.new()
	node.name = "FogCover"
	node.mesh = surface.commit()
	node.material_override = _material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 4.0
	parent.add_child(node)
	# The mask over the floors (global m; the terrain sits at the origin).
	var origin := parent.global_position
	_base = origin.y + low
	_rect = Rect2(bounds.position + Vector2(origin.x, origin.z), bounds.size).grow(MASK_MARGIN)
	_size = Vector2i(ceili(_rect.size.x / MASK_CELL), ceili(_rect.size.y / MASK_CELL))
	_bytes.resize(_size.x * _size.y)
	_image = Image.create_from_data(_size.x, _size.y, false, Image.FORMAT_L8, _bytes)
	_texture = ImageTexture.create_from_image(_image)
	_material.set_shader_parameter("reveal_map", _texture)
	_material.set_shader_parameter("reveal_rect", Vector4(_rect.position.x, _rect.position.y, 1.0 / (_size.x * MASK_CELL), 1.0 / (_size.y * MASK_CELL)))
	_material.set_shader_parameter("reveal_base", _base)
	# Until the camera is known, the game's own view (ViewFit.CAMERA_FROM's slope).
	var ViewFit: Script = load("res://presentation/kit/view_fit.gd")
	var from: Vector3 = ViewFit.CAMERA_FROM
	_slope = Vector2(from.x, from.z) / from.y
	_repaint()

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
