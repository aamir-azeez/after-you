extends Node3D
## Presentation-only gait. The world supplies rendered displacement, never input
## or recording events, so the same animation works for players and saved ghosts.

const STRIDE_LENGTH := 0.82
const WALK_SPEED := 2.4
const FOOT_REST := Vector3(0,0.10,0.055)

var facing := Node3D.new()
var upper_body := Node3D.new()
var feet: Array[Node3D] = []
var arms: Array[Node3D] = []
var sprout: MeshInstance3D
var ground_ring: MeshInstance3D
var ground_shadow: MeshInstance3D
var stride_phase := 0.0
var motion_blend := 0.0
var facing_target := 0.0

func _init(color: Color=Color("f4c38d")) -> void:
	facing.name="Facing"
	add_child(facing)
	upper_body.name="UpperBody"
	facing.add_child(upper_body)
	var torso := _sphere(0.27,color,Vector3(0,0.42,0),upper_body)
	torso.name="Torso"
	torso.scale=Vector3(1.0,1.3,0.9)
	var head := _sphere(0.24,color,Vector3(0,0.74,0),upper_body)
	head.name="Head"
	for x: float in [-0.09,0.09]:
		_sphere(0.034,Color("24433f"),Vector3(x,0.76,0.208),upper_body)
		_sphere(0.026,Color("e8a695"),Vector3(x*1.45,0.66,0.187),upper_body)
	sprout=_sphere(0.12,Color("abd1a2"),Vector3(0.05,1.01,0),upper_body)
	sprout.scale=Vector3(0.6,1,0.28)
	for side: float in [-1.0,1.0]:
		var foot := Node3D.new()
		foot.name="LeftFoot" if side<0 else "RightFoot"
		facing.add_child(foot)
		var shoe := _sphere(0.095,color.darkened(0.12),Vector3.ZERO,foot)
		shoe.scale=Vector3(1,0.6,1.5)
		feet.append(foot)
		var arm := Node3D.new()
		arm.name="LeftArm" if side<0 else "RightArm"
		arm.position=Vector3(side*0.25,0.51,0)
		upper_body.add_child(arm)
		var hand := _sphere(0.085,color,Vector3(0,-0.08,0),arm)
		hand.scale=Vector3(0.72,1.32,0.75)
		arms.append(arm)
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius=0.30
	shadow_mesh.bottom_radius=0.30
	shadow_mesh.height=0.012
	shadow_mesh.radial_segments=24
	ground_shadow=_mesh(shadow_mesh,Color(0.12,0.23,0.21,0.2),Vector3(0,0.006,0),self)
	ground_shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius=0.315
	ring_mesh.outer_radius=0.365
	ring_mesh.rings=24
	ring_mesh.ring_segments=8
	ground_ring=_mesh(ring_mesh,color,Vector3(0,0.035,0),self)
	reset_motion()

func reset_motion() -> void:
	# A replay seek or level reset is a placement, not a giant walking step.
	stride_phase=0.0
	motion_blend=0.0
	facing_target=0.0
	facing.rotation=Vector3.ZERO
	_apply_pose(0.0)

func advance_motion(displacement: Vector3, delta: float, reduced_motion: bool) -> void:
	if delta<=0.0:
		return
	var planar := Vector2(displacement.x,displacement.z)
	var distance := planar.length()
	var speed := distance/delta
	if speed>0.025:
		# Spirit meshes face +Z; only their visual pivot turns, not the root.
		facing_target=atan2(planar.x,planar.y)
	facing.rotation.y=lerp_angle(facing.rotation.y,facing_target,1.0-exp(-14.0*delta))
	if reduced_motion:
		motion_blend=0.0
		_apply_pose(0.0)
		return
	var target_blend := clampf(speed/WALK_SPEED,0.0,1.0) if speed>0.025 else 0.0
	motion_blend=lerpf(motion_blend,target_blend,1.0-exp(-12.0*delta))
	if target_blend==0.0 and motion_blend<0.001:
		motion_blend=0.0
	if speed>0.025:
		stride_phase=fposmod(stride_phase+distance*TAU/STRIDE_LENGTH,TAU)
	_apply_pose(motion_blend)

func _apply_pose(amount: float) -> void:
	var step := sin(stride_phase)
	# Torso, face and sprout move as one silhouette. Feet stay near the floor.
	upper_body.position.y=absf(step)*0.026*amount
	upper_body.rotation=Vector3(0.035*amount,0,cos(stride_phase)*0.024*amount)
	sprout.rotation.z=-0.5+step*0.05*amount
	for index in range(2):
		var side := -1.0 if index==0 else 1.0
		var stride := step*side
		feet[index].position=FOOT_REST+Vector3(side*0.14,maxf(stride,0.0)*0.052*amount,stride*0.075*amount)
		feet[index].rotation.x=stride*0.18*amount
		arms[index].rotation=Vector3(-stride*0.24*amount,0,-side*0.13)

func _sphere(radius: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius=radius
	shape.height=radius*2.0
	shape.radial_segments=16
	shape.rings=8
	return _mesh(shape,color,at,parent)

func _mesh(shape: Mesh, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh=shape
	var mat := StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=0.9
	if color.a<1.0:
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override=mat
	mesh.position=at
	parent.add_child(mesh)
	return mesh
