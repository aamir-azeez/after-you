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
## CPU a bounded number of texels a frame and sent to the GPU at most every
## UPLOAD_GAP seconds. It is the brightest of its stamps, one a metre walked
## (each a function of its square alone), so the order they are painted in
## never matters: a new turn whose history only grew paints just what is new,
## and a retry goes back to the mask as it stood before the turn. The mask
## holds the ground each fog pixel looks down to along the camera's fixed
## view, so floors of any height clear where they are seen; a change of view,
## or a history that lost something, paints a second mask over frames while
## the first stays on screen, and swaps once it is whole.
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
const POCKET_CLEAR := 0.8
const POCKET_FULL := 2.2
## A control's thinned patch (m, at least; its own radius plus SPOT_ROOM).
const SPOT_RADIUS := 0.75
const SPOT_ROOM := 0.45
## How much fog is left where it has been opened.
const HAZE := 0.08
## How far round a pip's path the fog opens (m), and round a lit lantern,
## which pushes it back over LANTERN_GROW seconds.
const PATH_RADIUS := 1.3
const LANTERN_REACH := 5.5
const LANTERN_GROW := 1.8
## The mask: metres a texel, metres past the floors, a stamp each STAMP_STEP
## metres walked (and each RISE_STEP of height), at most TEXELS_A_FRAME texels
## painted a frame (a path stamp is about 60, a lantern's about 380; each
## history point read counts as POINT_COST) and an upload at most every
## UPLOAD_GAP seconds while it changes.
const MASK_CELL := 0.5
const MASK_MARGIN := 7.0
const STAMP_STEP := 1.0
const RISE_STEP := 0.1
const TEXELS_A_FRAME := 2400
const POINT_COST := 4
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
uniform float pocket_clear = 0.8;
uniform float pocket_full = 2.2;
uniform float haze = 0.08;
uniform sampler2D reveal_map : filter_linear, repeat_disable;
uniform vec4 reveal_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float reveal_base = 0.0;
uniform vec4 growing = vec4(0.0, -100.0, 0.0, 0.0);
// The camera is orthographic and the sheet flat, so whatever follows the world
// (the noise, the mask, the pocket's and the lantern's offsets, the place on
// screen) changes evenly across it: worked out at its corners and carried
// across exactly, it leaves each pixel plain texture reads.
varying vec2 broad_uv;
varying vec2 fine_uv;
varying vec2 deep_uv;
varying vec2 reveal_uv;
varying vec2 from_pocket;
varying vec2 from_growing;
// Offset from the screen's middle and half the screen's width, in screen heights.
varying vec3 on_screen;

void vertex() {
	vec3 world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 back = INV_VIEW_MATRIX[2].xyz;
	vec2 slope = back.xz / back.y;
	vec2 at = world_at.xz;
	float t = drift_time;
	broad_uv = at * 0.055 + vec2(t * 0.018, t * 0.007);
	fine_uv = at * 0.17 + vec2(-t * 0.011, t * 0.016);
	// A second layer a metre and a half lower, seen through the first.
	deep_uv = (at - 1.5 * slope) * 0.09 + vec2(0.37 - t * 0.009, t * 0.012);
	// The ground this point looks down to, where the cleared fog is kept.
	reveal_uv = (at - (world_at.y - reveal_base) * slope - reveal_rect.xy) * reveal_rect.zw;
	from_pocket = at - pocket.xz - (world_at.y - pocket.y) * slope;
	from_growing = at - growing.xz - (world_at.y - growing.y) * slope;
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world_at, 1.0));
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	on_screen = vec3(clip.xy / clip.w * 0.5 * vec2(aspect, 1.0), aspect * 0.5);
}

void fragment() {
	float broad = texture(noise, broad_uv).r;
	float body = broad;
	float deep = broad;
	if (detail) {
		float fine = texture(noise, fine_uv).r;
		deep = texture(noise, deep_uv).r;
		body = broad * 0.6 + fine * 0.25 + deep * 0.15;
	}
	float thick = density * (0.52 + 0.62 * body);
	// The mask's outer texels are never painted, so past its edge reads as fog.
	float open = mix(1.0, haze, texture(reveal_map, reveal_uv).r);
	open = min(open, smoothstep(pocket_clear, pocket_full, length(from_pocket)));
	if (growing.w > 0.0) {
		open = min(open, mix(haze, 1.0, smoothstep(growing.w * 0.5, growing.w + 0.01, length(from_growing))));
	}
	vec2 room = vec2(on_screen.z, 0.5) - abs(on_screen.xy);
	float wash = (1.0 - smoothstep(0.0, 0.22, min(room.x, room.y))) * edge_wash;
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
## The terrain's metres to global, fixed once built.
var _ground := Transform3D()
## The mask: its rect (m, x and z), size, the bytes on screen and their
## texture; the ground height it is painted at, and the view slope
## (back.xz / back.y) it is painted for.
var _rect := Rect2()
var _size := Vector2i.ZERO
var _bytes := PackedByteArray()
var _image: Image
var _texture: ImageTexture
var _base := 0.0
var _slope := Vector2.ZERO
var _kernels: Dictionary = {}
var _dirty := false
var _since_upload := 0.0
var _paths: RefCounted
## The paint being made: into _next while the mask on screen waits for it
## (_swapping), else straight onto _bytes. The keys of its stamps, the stamps
## still to paint, and the live turn's stamps also put on screen meanwhile.
var _next := PackedByteArray()
var _swapping := false
var _stamped: Dictionary = {}
var _queue: Array = []
var _also_shown: Array = []
## The history being read (points, x z height cm, read up to _read) and its
## levers; whether the live turn is read yet, and its stamps' keys.
var _history := PackedInt32Array()
var _history_levers: Dictionary = {}
var _read := 0
var _live_read := false
var _live_keys: Array = []
## The last turn's live keys a grown history must hold, and the paint and its
## keys as they stood with the history alone (a retry goes back to them).
var _owed: Array = []
var _before_live := PackedByteArray()
var _before_live_keys: Dictionary = {}
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

## Opens the fog where `paths` (kit/turn_paths.gd) says the stage has been: a
## new turn's history (only what it added, when it still holds all it had),
## or this cover built again.
func show_paths(paths: RefCounted) -> void:
	_paths = paths
	if not _growing.is_empty() and not paths.levers_lit().has(_growing.id): _stop_growing()
	if _swapping or not _grew(paths):
		_start(true)
		return
	# The live turn's stamps stay on the mask if the new history holds them.
	_owed.append_array(_live_keys)
	for key: Variant in _live_keys: _stamped.erase(key)
	_live_keys = []
	_live_read = false
	_before_live = PackedByteArray()
	_history = paths.history_points
	_history_levers = paths.history_levers.duplicate()
	_want_history_lanterns()

## What the turn being played added (turn_paths note()'s result): its new
## squares queued, a lantern lit now growing its clearing.
func paths_changed(change: Dictionary) -> void:
	if _paths == null: return
	if change.rewound:
		_rewind()
		return
	for index in range(int(change.from_points), _paths.live_points.size()):
		var entry: Array = _paths.live_points[index]
		var key := _point_key(int(entry[1]), int(entry[2]), int(entry[3]))
		_want_live(_key_at(key), PATH_RADIUS, key)
	for index in range(int(change.from_levers), _paths.live_levers.size()):
		var id: String = _paths.live_levers[index][1]
		if not _lanterns.has(id): continue
		_finish_growing()
		_growing = {"id": id, "at": _lanterns[id], "since": _clock}

## Each frame: the mask painted a bounded share, the lantern's clearing grows,
## and the mask goes up when it changed (at most every UPLOAD_GAP).
func advance(delta: float, clock: float) -> void:
	_clock = clock
	_last_delta = maxf(delta, 0.0)
	_watch_view()
	_paint_some()
	if not _growing.is_empty():
		var grown := clampf((clock - float(_growing.since)) / LANTERN_GROW, 0.0, 1.0)
		var at: Vector3 = _growing.at
		_material.set_shader_parameter("growing", Vector4(at.x, at.y, at.z, lerpf(SPOT_RADIUS, LANTERN_REACH, smoothstep(0.0, 1.0, grown))))
		# Held full grown until its stamp can go on the mask.
		if grown >= 1.0 and (_live_read or _swapping or _stamped.has(_lantern_key(str(_growing.id)))): _finish_growing()
	_since_upload += _last_delta
	if _dirty and _since_upload >= UPLOAD_GAP: _upload()

## The mask on screen and the stamps on it (tests: the same history paints the same).
func mask_bytes() -> PackedByteArray:
	return _bytes

func stamp_count() -> int:
	return _stamped.size()

## Whether paint is still owed or not yet sent up (tests and captures wait on it).
func painting() -> bool:
	return _swapping or not _live_read or _dirty or not _queue.is_empty() or not _also_shown.is_empty()

func _finish_growing() -> void:
	if _growing.is_empty(): return
	var id := str(_growing.id)
	_stop_growing()
	_want_live(_lanterns[id], LANTERN_REACH, _lantern_key(id))

func _stop_growing() -> void:
	_growing = {}
	_material.set_shader_parameter("growing", Vector4(0, -100, 0, 0))

## Whether `paths`' history is the one read with more after it (a turn added:
## TurnPaths.of appends each turn's new squares in order).
func _grew(paths: RefCounted) -> bool:
	var points: PackedInt32Array = paths.history_points
	if points.size() < _history.size() or points.slice(0, _history.size()) != _history: return false
	for id: String in _history_levers:
		if not paths.history_levers.has(id): return false
	return true

## The whole mask again from the spots, the history and the live turn: into a
## second mask while this one stays on screen (`swap`), or straight onto this
## one when nothing is open yet.
func _start(swap: bool) -> void:
	_swapping = swap
	if swap:
		_next.resize(_bytes.size())
		_next.fill(0)
	_stamped.clear()
	_queue.clear()
	_also_shown.clear()
	_live_keys = []
	_owed = []
	_live_read = false
	_before_live = PackedByteArray()
	_read = 0
	_history = _paths.history_points if _paths != null else PackedInt32Array()
	_history_levers = _paths.history_levers.duplicate() if _paths != null else {}
	for spot: Array in _spots: _want(spot[0], float(spot[1]), "spot|%s" % [spot[0]], false)
	_want_history_lanterns()

func _want_history_lanterns() -> void:
	for id: String in _history_levers:
		if _lanterns.has(id): _want(_lanterns[id], LANTERN_REACH, _lantern_key(id), false)

## A retry or a reset dropped the live turn's later stamps: back to the paint
## as it stood with the history alone, and what the turn kept again.
func _rewind() -> void:
	if not _growing.is_empty() and not _paths.levers_lit().has(_growing.id): _stop_growing()
	_also_shown.clear()
	# Before the live turn is read nothing of it is on the paint yet.
	if not _live_read: return
	if _swapping:
		_next = _before_live.duplicate()
	else:
		_bytes = _before_live.duplicate()
		_upload()
	_stamped = _before_live_keys.duplicate()
	_queue.clear()
	_live_keys = []
	_read_live()

## The history is painted: a key the last turn opened that the new history
## lacks means painting again; else keep the paint so far (a retry comes back
## to it) and read the live turn.
func _reach_live() -> void:
	for key: Variant in _owed:
		if not _stamped.has(key):
			_start(true)
			return
	_owed = []
	_before_live = (_next if _swapping else _bytes).duplicate()
	_before_live_keys = _stamped.duplicate()
	_live_read = true
	_read_live()

func _read_live() -> void:
	if _paths == null: return
	for entry: Array in _paths.live_points:
		var key := _point_key(int(entry[1]), int(entry[2]), int(entry[3]))
		_want(_key_at(key), PATH_RADIUS, key, true)
	for entry: Array in _paths.live_levers:
		var id: String = entry[1]
		if _lanterns.has(id) and not (not _growing.is_empty() and str(_growing.id) == id): _want(_lanterns[id], LANTERN_REACH, _lantern_key(id), true)

## This frame's share, at most TEXELS_A_FRAME texels: the live turn's stamps
## onto the mask on screen, the queued stamps, then more of the history;
## a finished second mask goes on screen.
func _paint_some() -> void:
	var budget := TEXELS_A_FRAME
	while budget > 0:
		if not _also_shown.is_empty():
			budget -= _paint(_also_shown.pop_front(), false)
		elif not _queue.is_empty():
			budget -= _paint(_queue.pop_front(), _swapping)
		elif _read < _history.size():
			budget -= POINT_COST
			var key := _point_key(_history[_read], _history[_read + 1], _history[_read + 2])
			_read += 3
			if not _stamped.has(key): _want(_key_at(key), PATH_RADIUS, key, false)
		elif not _live_read:
			_reach_live()
		elif _swapping:
			_swap()
			return
		else:
			return

func _swap() -> void:
	var shown := _bytes
	_bytes = _next
	_next = shown
	_swapping = false
	_upload()

## A stamp a STAMP_STEP square of floor and RISE_STEP of height (terrain
## metres, which are global here), painted at the square's middle and the
## step's foot (a floor's own height): the same square always paints the same.
func _point_key(x_cm: int, z_cm: int, h_cm: int) -> Vector3i:
	var at := _ground * Vector3(x_cm / 100.0, h_cm / 100.0, z_cm / 100.0)
	return Vector3i(floori(at.x / STAMP_STEP), floori(at.z / STAMP_STEP), floori(at.y / RISE_STEP + 0.001))

func _key_at(key: Vector3i) -> Vector3:
	return Vector3((key.x + 0.5) * STAMP_STEP, key.z * RISE_STEP, (key.y + 0.5) * STAMP_STEP)

func _lantern_key(id: String) -> String:
	return "l|" + id

func _want(at: Vector3, radius: float, key: Variant, live: bool) -> void:
	if _stamped.has(key): return
	_stamped[key] = true
	_queue.append([at, radius])
	if live: _live_keys.append(key)

## A stamp of the turn being played: on screen now while a second mask is
## painted, and with the rest once the live turn is read.
func _want_live(at: Vector3, radius: float, key: Variant) -> void:
	if _swapping: _also_shown.append([at, radius])
	if _live_read: _want(at, radius, key, true)

## One soft disc of open fog (it only ever opens more), at the ground its spot
## is seen at along the view, onto the second mask or the one on screen. Its
## cost in texels.
func _paint(stamp: Array, into_next: bool) -> int:
	var at: Vector3 = stamp[0]
	var seen := Vector2(at.x, at.z) - (at.y - _base) * _slope
	var cell := Vector2i(((seen - _rect.position) / MASK_CELL).floor())
	var kernel: Array = _kernel(float(stamp[1]))
	var offsets: PackedInt32Array = kernel[0]
	var values: PackedByteArray = kernel[1]
	var reach: int = kernel[2]
	if cell.x - reach < 0 or cell.y - reach < 0 or cell.x + reach >= _size.x or cell.y + reach >= _size.y: return 1
	var origin := cell.y * _size.x + cell.x
	if into_next:
		for index in range(offsets.size()):
			var texel := origin + offsets[index]
			if values[index] > _next[texel]: _next[texel] = values[index]
		return offsets.size()
	for index in range(offsets.size()):
		var texel := origin + offsets[index]
		if values[index] > _bytes[texel]:
			_bytes[texel] = values[index]
			_dirty = true
	return offsets.size()

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
	# paints again only once it has held still.
	if _pending_slope != Vector2.INF and _pending_slope.distance_to(slope) >= 0.002:
		_pending_slope = slope
		_view_still = 0.0
		return
	_view_still += _last_delta
	if _pending_slope != Vector2.INF and _view_still < VIEW_SETTLE: return
	_pending_slope = slope
	_slope = slope
	_start(true)

func _make(cover: Dictionary, floors: Array, spots: Array, lanterns: Dictionary, parent: Node3D) -> void:
	_ground = parent.global_transform
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
	_start(false)

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
