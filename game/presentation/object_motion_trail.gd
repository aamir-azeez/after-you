extends Node3D
## Presentation-only object exposure. One reusable mesh; no particles or history.
const SOFT_SHADER = preload("res://presentation/object_motion_trail.gdshader")
const MIN_SPEED := 0.45
const TELEPORT_DISTANCE := 1.8
const MAX_SAMPLE_GAP := 0.20
const STOP_FADE := 0.10
var quality := "balanced"
var radius := 0.13
var tint := Color("e9edd6")
var permitted := false
var _world: Node3D
var _object: Node3D
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _last := Vector3.ZERO
var _velocity := Vector3.ZERO
var _idle := 0.0
var _elapsed := 0.0
var _initialized := false
func configure(world: Node3D, object: Node3D, object_radius: float) -> void:
	_world = world
	_object = object
	radius = object_radius
func _ready() -> void:
	var shape := CapsuleMesh.new()
	shape.radius = 0.5
	shape.height = 2.0
	shape.radial_segments = 12
	shape.rings = 3
	_mesh = MeshInstance3D.new()
	_mesh.mesh = shape
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = SOFT_SHADER
	_mesh.material_override = _material
	add_child(_mesh)
	_mesh.hide()
	process_priority = 90
func set_quality(value: String) -> void:
	quality = value
	if quality == "low": reset()
func set_motion_allowed(value: bool, immediate: bool = false) -> void:
	if immediate or not value or value != permitted: reset()
	permitted = value
func reset() -> void:
	_initialized = false
	_velocity = Vector3.ZERO
	_elapsed = 0.0
	_idle = 0.0
	if is_instance_valid(_mesh): _mesh.hide()
func _process(_delta: float) -> void:
	# The child still runs when its owning view suspends world animation.
	if not is_instance_valid(_world) or not _world.is_processing() or not _world.is_visible_in_tree() or not is_instance_valid(_object) or not _object.is_visible_in_tree(): reset()
func advance(delta: float, reduced_motion: bool) -> void:
	if not permitted or quality == "low" or reduced_motion or not is_instance_valid(_object) or not _object.is_visible_in_tree() or not is_finite(delta) or delta <= 0.0 or delta > MAX_SAMPLE_GAP:
		reset()
		return
	var point := _object.global_position
	if not point.is_finite(): reset(); return
	if not _initialized:
		_last = point
		_initialized = true
		return
	_elapsed += delta
	var displacement := point - _last
	if displacement.length() > TELEPORT_DISTANCE:
		reset()
		return
	if displacement.length_squared() > 0.000001:
		# Fixed 30 Hz objects may stand still for several rendering frames.
		# Measure time since the last movement, rather than the latest frame.
		var next_velocity := displacement / _elapsed
		_velocity = _velocity.lerp(next_velocity, 1.0 - exp(-28.0 * _elapsed))
		_last = point
		_elapsed = 0.0
		_idle = 0.0
	else:
		_idle += delta
	var speed := _velocity.length()
	var fade := clampf(1.0 - maxf(0.0, _idle - 0.04) / STOP_FADE, 0.0, 1.0)
	if speed < MIN_SPEED or fade == 0.0:
		_mesh.hide()
		if fade == 0.0: _velocity = Vector3.ZERO
		return
	var exposure := 0.14 if quality == "high" else 0.09
	var length := minf(speed * exposure, 1.10) * fade
	var width := radius * 0.42
	var axis := _velocity / speed
	var across := axis.cross(Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	# Stop beneath the sharp leading object and taper the soft exposure behind it.
	var end := point - axis * radius * 0.45
	_mesh.global_transform = Transform3D(Basis(across, axis, across.cross(axis)), end - axis * length * 0.5)
	_mesh.scale = Vector3(width * 2.0, maxf(width, length * 0.5), width * 2.0)
	_material.set_shader_parameter("trail_color", Color(tint.r, tint.g, tint.b, 0.32 * fade))
	_mesh.show()
