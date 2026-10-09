extends "res://presentation/object_motion_trail.gd"
## A short exposure of the rendered flight path, rather than a velocity pointer.
const MAX_POINTS := 64
const SIDES := 8
const SAMPLE_INTERVAL := 1.0 / 120.0
var _points: Array[Vector3] = []
var _ages: Array[float] = []
var _path_mesh := ArrayMesh.new()
var _sample_elapsed := 0.0
var _indices := PackedInt32Array()

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _path_mesh
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = SOFT_SHADER
	_mesh.material_override = _material
	add_child(_mesh)
	_mesh.hide()
	process_priority = 90

func reset() -> void:
	_points.clear()
	_ages.clear()
	_sample_elapsed = 0.0
	super.reset()

func advance(delta: float, reduced_motion: bool) -> void:
	if not permitted or quality == "low" or reduced_motion or not is_instance_valid(_object) or not _object.is_visible_in_tree() or not is_finite(delta) or delta <= 0.0 or delta > MAX_SAMPLE_GAP:
		reset()
		return
	var point := _object.global_position
	if not point.is_finite(): reset(); return
	if not _points.is_empty() and point.distance_to(_points.back()) > TELEPORT_DISTANCE:
		reset()
		return
	var exposure := 0.40 if quality == "high" else 0.30
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
	var fade := clampf(1.0 - maxf(0.0, _idle - 0.04) / STOP_FADE, 0.0, 1.0)
	var speed := point.distance_to(_points.front()) / maxf(_ages.front(), SAMPLE_INTERVAL) if not _points.is_empty() else 0.0
	if _points.size() < 3 or fade == 0.0 or speed < MIN_SPEED:
		_hide_motion()
		return
	_draw_path(exposure, fade)

func _draw_path(exposure: float, fade: float) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var count := _points.size()
	vertices.resize(count * SIDES)
	normals.resize(count * SIDES)
	uvs.resize(count * SIDES)
	if _indices.size() != (count - 1) * SIDES * 6:
		_indices.resize((count - 1) * SIDES * 6)
		for i in range(count - 1):
			for side in range(SIDES):
				var a := i * SIDES + side
				var b := i * SIDES + (side + 1) % SIDES
				var index := (i * SIDES + side) * 6
				_indices[index] = a
				_indices[index+1] = a + SIDES
				_indices[index+2] = b
				_indices[index+3] = b
				_indices[index+4] = a + SIDES
				_indices[index+5] = b + SIDES
	var inverse_basis := _mesh.global_basis.inverse()
	var inverse_transform := _mesh.global_transform.affine_inverse()
	var previous_across := Vector3.ZERO
	for i in range(count):
		var previous := _points[maxi(0, i - 1)]
		var following := _points[mini(count - 1, i + 1)]
		var tangent := (following - previous).normalized()
		var across := previous_across - tangent * previous_across.dot(tangent)
		if across.length_squared() < 0.000001:
			across = tangent.cross(Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT)
		across = across.normalized()
		previous_across = across
		var vertical := tangent.cross(across).normalized()
		var freshness := clampf(1.0 - _ages[i] / exposure, 0.0, 1.0)
		# A tapered tail stays at its historic world position while the head moves.
		var width := radius * (0.80 if quality == "high" else 0.65) * sqrt(freshness)
		for side in range(SIDES):
			var angle := TAU * side / SIDES
			var normal := across * cos(angle) + vertical * sin(angle)
			var index := i * SIDES + side
			vertices[index] = inverse_transform * (_points[i] + normal * width)
			normals[index] = inverse_basis * normal
			uvs[index] = Vector2(float(side) / SIDES, 1.0 - freshness)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	_path_mesh.clear_surfaces()
	_path_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_material.set_shader_parameter("trail_color", Color(tint.r, tint.g, tint.b, (0.72 if quality == "high" else 0.60) * fade))
	_mesh.show()
