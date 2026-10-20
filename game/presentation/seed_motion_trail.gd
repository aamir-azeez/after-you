extends "res://presentation/object_motion_trail.gd"
## A short exposure of the rendered flight path, rather than a velocity pointer.
## The tube mesh is built once and shared; its shader places each ring from the
## recent flight history, so a frame only uploads that history.
const Cache = preload("res://presentation/motion_trail_cache.gd")
const PATH_SHADER = preload("res://presentation/seed_motion_trail.gdshader")
const MAX_POINTS := 64
const SIDES := 8
const SAMPLE_INTERVAL := 1.0 / 120.0
var _points: Array[Vector3] = []
var _ages: Array[float] = []
var _sample_elapsed := 0.0
var _material: ShaderMaterial
# Two history buffers, alternated: the material keeps the one handed over last
# frame, so writing the other never forces a copy.
var _path_a := PackedVector4Array()
var _path_b := PackedVector4Array()
var _use_b := false

## Rings of SIDES vertices for every history sample, joined into one tube.
## Faces wind clockwise seen from outside, Godot's front face.
static func tube_mesh() -> ArrayMesh:
	if Cache.tube_mesh != null: return Cache.tube_mesh
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(MAX_POINTS * SIDES)
	normals.resize(MAX_POINTS * SIDES)
	normals.fill(Vector3.UP)
	uvs.resize(MAX_POINTS * SIDES)
	for i in range(MAX_POINTS):
		for side in range(SIDES):
			uvs[i * SIDES + side] = Vector2(float(side) / SIDES, float(i))
	for i in range(MAX_POINTS - 1):
		for side in range(SIDES):
			var a := i * SIDES + side
			var b := i * SIDES + (side + 1) % SIDES
			indices.append_array([a, a + SIDES, b, b, a + SIDES, b + SIDES])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	Cache.tube_mesh = ArrayMesh.new()
	Cache.tube_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return Cache.tube_mesh

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = tube_mesh()
	# World-space vertices from the shader; the node itself never moves.
	_mesh.top_level = true
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = PATH_SHADER
	_mesh.material_override = _material
	_path_a.resize(MAX_POINTS)
	_path_b.resize(MAX_POINTS)
	add_child(_mesh)
	_mesh.global_transform = Transform3D.IDENTITY
	_mesh.hide()
	process_priority = 90

func reset() -> void:
	_points.clear()
	_ages.clear()
	_sample_elapsed = 0.0
	super.reset()

func advance(delta: float, reduced_motion: bool) -> void:
	if not _may_expose(delta, reduced_motion): return
	var point := _object.global_position
	if not _points.is_empty() and point.distance_to(_points.back()) > Profile.TELEPORT_DISTANCE:
		reset()
		return
	var exposure := float(_preset.exposure)
	_sample_elapsed += delta
	for i in range(_ages.size()): _ages[i] += delta
	while not _ages.is_empty() and (_ages.front() > exposure or _ages.size() >= MAX_POINTS):
		_ages.pop_front()
		_points.pop_front()
	if _points.is_empty() or point.distance_squared_to(_points.back()) > 0.000001:
		if _points.is_empty() or _sample_elapsed >= SAMPLE_INTERVAL:
			_points.append(point)
			_ages.append(0.0)
			_sample_elapsed = 0.0
		_idle = 0.0
	else:
		_idle += delta
	var fade := Profile.stop_fade(_idle)
	var speed := point.distance_to(_points.front()) / maxf(_ages.front(), SAMPLE_INTERVAL) if not _points.is_empty() else 0.0
	if _points.size() < 3 or fade == 0.0 or speed < Profile.MIN_SPEED:
		_hide_motion()
		return
	_draw_path(exposure, fade)

func _draw_path(exposure: float, fade: float) -> void:
	var count := _points.size()
	var width := radius * float(_preset.width)
	var low := _points[0]
	var high := low
	_use_b = not _use_b
	for i in range(count):
		var at := _points[i]
		var sample := Vector4(at.x, at.y, at.z, clampf(1.0 - _ages[i] / exposure, 0.0, 1.0))
		if _use_b: _path_b[i] = sample
		else: _path_a[i] = sample
		low = low.min(at)
		high = high.max(at)
	_material.set_shader_parameter(&"path", _path_b if _use_b else _path_a)
	_material.set_shader_parameter(&"count", count)
	_material.set_shader_parameter(&"width", width)
	_material.set_shader_parameter(&"trail_color", Color(tint.r, tint.g, tint.b, float(_preset.opacity) * fade))
	# The shader moves every vertex, so cull by the path itself.
	_mesh.custom_aabb = AABB(low, high - low).grow(width)
	_mesh.show()
