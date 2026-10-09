extends "res://presentation/object_motion_trail.gd"
## The rolling stripe is exposed around the spin axis; the silhouette stays sharp.
const SPIN_SHADER = preload("res://presentation/ball_rotation_blur.gdshader")
var _band: Node3D
var _original_material: Material
var _spin_material: ShaderMaterial

func _ready() -> void:
	_band = _object.get_child(0)
	_original_material = _object.material_override
	_spin_material = ShaderMaterial.new()
	_spin_material.shader = SPIN_SHADER
	process_priority = 90

func _hide_motion() -> void:
	if is_instance_valid(_object) and _original_material != null:
		_object.material_override = _original_material
	if is_instance_valid(_band): _band.show()

func _draw_motion(_point: Vector3, speed: float, fade: float) -> void:
	var axis := Vector3(_velocity.z, 0.0, -_velocity.x)
	if axis.length_squared() < 0.00001:
		_hide_motion()
		return
	var angle := minf(speed / radius * (0.0542 if quality == "high" else 0.045), 0.90) * fade
	_spin_material.set_shader_parameter("ball_color", tint)
	_spin_material.set_shader_parameter("spin_axis", (_object.global_basis.inverse() * axis).normalized())
	_spin_material.set_shader_parameter("exposure_angle", angle)
	_object.material_override = _spin_material
	_band.hide()
