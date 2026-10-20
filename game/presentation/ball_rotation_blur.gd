extends "res://presentation/object_motion_trail.gd"
## The rolling stripe is exposed around the spin axis; the silhouette stays sharp.
## The ball shows its band smeared across the exposure, and the raised band
## fades by how much of the exposure it still covers. Every ball and band share
## one material each; each instance sets its own colour, axis and angle.
const Cache = preload("res://presentation/motion_trail_cache.gd")
const SPIN_SHADER = preload("res://presentation/ball_rotation_blur.gdshader")
const BAND_SHADER = preload("res://presentation/ball_band_blur.gdshader")
const BALL_COLOR := &"ball_color"
const BAND_COLOR := &"band_color"
const SPIN_AXIS := &"spin_axis"
const EXPOSURE_ANGLE := &"exposure_angle"
const BAND_HALF_WIDTH := &"band_half_width"
const BALL_CENTER := &"ball_center"
const BAND_NORMAL := &"band_normal"
var _band: MeshInstance3D
var _ball: GeometryInstance3D
var _original_material: Material
var _original_band_material: Material
var _spinning := false

static func spin_material() -> ShaderMaterial:
	if Cache.spin_material == null: Cache.spin_material = _shared(SPIN_SHADER)
	return Cache.spin_material

static func band_material() -> ShaderMaterial:
	if Cache.band_material == null: Cache.band_material = _shared(BAND_SHADER)
	return Cache.band_material

static func _shared(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"taps", Profile.SPIN_TAPS)
	material.set_shader_parameter(&"tail_weight", Profile.SPIN_TAIL_WEIGHT)
	return material

## Half the band's width on the unit sphere: the sine of the angle the band's
## tube (stretched along the band's axis) spans either side of its plane.
static func band_half_width(band: MeshInstance3D, ball_radius: float) -> float:
	var torus := band.mesh as TorusMesh
	if torus == null or ball_radius <= 0.0: return 0.29
	var half := (torus.outer_radius - torus.inner_radius) * 0.5 * band.scale.y
	return half / sqrt(ball_radius * ball_radius + half * half)

# No capsule: the base _ready is deliberately not called.
func _ready() -> void:
	_ball = _object as GeometryInstance3D
	_band = _object.get_child(0) as MeshInstance3D
	_original_material = _ball.material_override
	_original_band_material = _band.material_override
	var width := band_half_width(_band, radius)
	_ball.set_instance_shader_parameter(BAND_HALF_WIDTH, width)
	_band.set_instance_shader_parameter(BAND_HALF_WIDTH, width)
	var sharp_band := _original_band_material as BaseMaterial3D
	if sharp_band != null:
		_ball.set_instance_shader_parameter(BAND_COLOR, sharp_band.albedo_color)
		_band.set_instance_shader_parameter(BAND_COLOR, sharp_band.albedo_color)
	process_priority = 90

func _hide_motion() -> void:
	if not _spinning: return
	_spinning = false
	if is_instance_valid(_ball): _ball.material_override = _original_material
	if is_instance_valid(_band): _band.material_override = _original_band_material

func _draw_motion(_point: Vector3, speed: float, strength: float) -> void:
	var axis := Vector3(_velocity.z, 0.0, -_velocity.x)
	if axis.length_squared() < 0.00001:
		_hide_motion()
		return
	axis = axis.normalized()
	var angle := minf(speed / radius * float(_preset.spin), float(_preset.max_spin)) * strength
	var basis := _ball.global_basis
	_ball.set_instance_shader_parameter(BALL_COLOR, tint)
	_ball.set_instance_shader_parameter(SPIN_AXIS, (basis.inverse() * axis).normalized())
	_ball.set_instance_shader_parameter(EXPOSURE_ANGLE, angle)
	_band.set_instance_shader_parameter(BALL_CENTER, _ball.global_position)
	_band.set_instance_shader_parameter(BAND_NORMAL, basis.x.normalized())
	_band.set_instance_shader_parameter(SPIN_AXIS, axis)
	_band.set_instance_shader_parameter(EXPOSURE_ANGLE, angle)
	if not _spinning:
		_spinning = true
		_ball.material_override = spin_material()
		_band.material_override = band_material()
