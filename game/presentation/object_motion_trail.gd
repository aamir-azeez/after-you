extends Node3D
## The shared motion blur for a moving object: when to expose it, how fast it
## moves, and how the exposure eases in and fades out. Every blur (rolling
## ball, thrown seed, any other object) extends this and takes its look from
## motion_blur_profile.gd. Presentation only; no particles. This base draws a
## soft capsule behind the object, with one material shared by every capsule.
const Profile = preload("res://presentation/motion_blur_profile.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const SOFT_SHADER = preload("res://presentation/object_motion_trail.gdshader")
const TRAIL_COLOR := &"trail_color"
var quality := "balanced"
var radius := 0.13
var tint := Color("e9edd6")
var permitted := false
var _world: Node3D
var _object: Node3D
var _mesh: MeshInstance3D
var _preset: Dictionary = Profile.preset("balanced")
var _last := Vector3.ZERO
var _velocity := Vector3.ZERO
var _idle := 0.0
var _elapsed := 0.0
var _engaged := 0.0
var _initialized := false
static var _capsule_mesh: CapsuleMesh
static var _capsule_material: ShaderMaterial

func configure(world: Node3D, object: Node3D, object_radius: float) -> void:
	_world = world
	_object = object
	radius = object_radius

func _ready() -> void:
	if _capsule_mesh == null:
		_capsule_mesh = CapsuleMesh.new()
		_capsule_mesh.radius = 0.5
		_capsule_mesh.height = 2.0
		_capsule_mesh.radial_segments = 12
		_capsule_mesh.rings = 3
		_capsule_material = ShaderMaterial.new()
		_capsule_material.shader = SOFT_SHADER
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _capsule_mesh
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.material_override = _capsule_material
	add_child(_mesh)
	_mesh.hide()
	process_priority = 90

func set_quality(value: String) -> void:
	quality = value
	_preset = Profile.preset(value)
	if not GraphicsPolicy.motion_trails(quality): reset()

func set_motion_allowed(value: bool, immediate: bool = false) -> void:
	if immediate or not value or value != permitted: reset()
	permitted = value

func reset() -> void:
	_initialized = false
	_velocity = Vector3.ZERO
	_elapsed = 0.0
	_idle = 0.0
	_engaged = 0.0
	_hide_motion()

func _hide_motion() -> void:
	if is_instance_valid(_mesh): _mesh.hide()

func _process(_delta: float) -> void:
	# The child still runs when its owning view suspends world animation.
	if not is_instance_valid(_world) or not _world.is_processing() or not _world.is_visible_in_tree() or not is_instance_valid(_object) or not _object.is_visible_in_tree(): reset()

## False (and reset) whenever this frame must show no exposure at all.
func _may_expose(delta: float, reduced_motion: bool) -> bool:
	if not permitted or not GraphicsPolicy.motion_trails(quality) or reduced_motion or not is_instance_valid(_object) or not _object.is_visible_in_tree() or not is_finite(delta) or delta <= 0.0 or delta > Profile.MAX_SAMPLE_GAP or not _object.global_position.is_finite():
		reset()
		return false
	return true

func advance(delta: float, reduced_motion: bool) -> void:
	if not _may_expose(delta, reduced_motion): return
	var point := _object.global_position
	if not _initialized:
		_last = point
		_initialized = true
		return
	_elapsed += delta
	var displacement := point - _last
	if displacement.length() > Profile.TELEPORT_DISTANCE:
		reset()
		return
	if displacement.length_squared() > 0.000001:
		# Fixed 30 Hz objects may stand still for several rendering frames.
		# Measure time since the last movement, rather than the latest frame.
		var next_velocity := displacement / _elapsed
		_velocity = _velocity.lerp(next_velocity, 1.0 - exp(-Profile.VELOCITY_RESPONSE * _elapsed))
		_last = point
		_elapsed = 0.0
		_idle = 0.0
	else:
		_idle += delta
	var speed := _velocity.length()
	var fade := Profile.stop_fade(_idle)
	if speed < Profile.MIN_SPEED or fade == 0.0:
		_hide_motion()
		_engaged = 0.0
		if fade == 0.0: _velocity = Vector3.ZERO
		return
	_engaged += delta
	_draw_motion(point, speed, fade * Profile.ramp(_engaged))

## `strength` is 0..1: the start ramp times the stop fade.
func _draw_motion(point: Vector3, speed: float, strength: float) -> void:
	var length := minf(speed * float(_preset.exposure), 2.0) * strength
	var width := radius * float(_preset.width)
	var axis := _velocity / speed
	var across := axis.cross(Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	# Stop beneath the sharp leading object and taper the soft exposure behind it.
	var end := point - axis * radius * 0.45
	_mesh.global_transform = Transform3D(Basis(across, axis, across.cross(axis)), end - axis * length * 0.5)
	_mesh.scale = Vector3(width * 2.0, maxf(width, length * 0.5), width * 2.0)
	_mesh.set_instance_shader_parameter(TRAIL_COLOR, Color(tint.r, tint.g, tint.b, float(_preset.opacity) * strength))
	_mesh.show()
