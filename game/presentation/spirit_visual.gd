extends Node3D
## Presentation-only gait. The world supplies rendered displacement, never input
## or recording events, so the same animation works for players and saved ghosts.

signal stepped

const STRIDE_LENGTH := 0.82
const WALK_SPEED := 2.4
const FOOT_REST := Vector3(0,0.10,0.055)
const THROW_DURATION := 0.44

var facing := Node3D.new()
var upper_body := Node3D.new()
var feet: Array[Node3D] = []
var sprout: MeshInstance3D
var ground_ring: MeshInstance3D
var ground_shadow: MeshInstance3D
var stride_phase := 0.0
var step_phase := 0.0
var motion_blend := 0.0
var facing_target := 0.0
var carrying_seed := false
var throw_age := THROW_DURATION
var _reduced_motion := false

func _init(color: Color=Color("f4c38d")) -> void:
	facing.name="Facing"
	add_child(facing)
	upper_body.name="UpperBody"
	facing.add_child(upper_body)
	var torso := _sphere(0.29,color,Vector3(0,0.29,0),upper_body)
	torso.name="Torso"
	torso.scale=Vector3(1.0,0.82,0.92)
	var head := _sphere(0.34,color,Vector3(0,0.57,0),upper_body)
	head.name="Head"
	head.scale=Vector3(1.0,0.88,0.94)
	for x: float in [-0.115,0.115]:
		var eye := _sphere(0.041,Color("24433f"),Vector3(x,0.59,0.289),upper_body)
		eye.name="LeftEye" if x<0 else "RightEye"
		eye.scale=Vector3(0.94,1.13,0.62)
		_sphere(0.008,Color("fff4d9"),Vector3(x-0.010,0.605,0.313),upper_body)
		_sphere(0.033,Color("e8a695"),Vector3(x*1.5,0.505,0.267),upper_body)
	# The sprout leans aside so a carried seed sits clearly above the head.
	sprout=_sphere(0.12,Color("abd1a2"),Vector3(-0.19,0.90,-0.035),upper_body)
	sprout.scale=Vector3(0.6,1,0.28)
	for side: float in [-1.0,1.0]:
		var foot := Node3D.new()
		foot.name="LeftFoot" if side<0 else "RightFoot"
		facing.add_child(foot)
		var shoe := _sphere(0.095,color.darkened(0.12),Vector3.ZERO,foot)
		shoe.scale=Vector3(1,0.6,1.5)
		feet.append(foot)
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
	step_phase=0.0
	motion_blend=0.0
	throw_age=THROW_DURATION
	facing_target=0.0
	facing.rotation=Vector3.ZERO
	_apply_pose(0.0)

func advance_motion(displacement: Vector3, delta: float, reduced_motion: bool) -> void:
	if delta<=0.0:
		return
	_reduced_motion=reduced_motion
	throw_age=minf(THROW_DURATION,throw_age+delta)
	var planar := Vector2(displacement.x,displacement.z)
	var distance := planar.length()
	var speed := distance/delta
	if speed>0.025:
		# Spirit meshes face +Z; only their visual pivot turns, not the root.
		facing_target=atan2(planar.x,planar.y)
	facing.rotation.y=lerp_angle(facing.rotation.y,facing_target,1.0-exp(-14.0*delta))
	# One quiet contact per half-stride. Distance, rather than frame count, keeps
	# footsteps in time at every render rate. Lifts and idle poses stay silent.
	var contacts := 0
	if speed>0.025:
		var next_phase := step_phase+distance*TAU/STRIDE_LENGTH
		contacts=floori(next_phase/PI)-floori(step_phase/PI)
		step_phase=fposmod(next_phase,TAU)
	if reduced_motion:
		motion_blend=0.0
		_apply_pose(0.0)
		# Reduced motion changes the pose, not the player's sound preference.
		if contacts>0: stepped.emit()
		return
	var target_blend := clampf(speed/WALK_SPEED,0.0,1.0) if speed>0.025 else 0.0
	motion_blend=lerpf(motion_blend,target_blend,1.0-exp(-12.0*delta))
	if target_blend==0.0 and motion_blend<0.001:
		motion_blend=0.0
	if speed>0.025:
		stride_phase=step_phase
	_apply_pose(motion_blend)
	# A stalled render frame must not release a burst of queued sounds.
	if contacts>0: stepped.emit()

func _apply_pose(amount: float) -> void:
	var step := sin(stride_phase)
	# Short spirits travel in little hops. Feet still counter-travel on contact.
	var hop := absf(step)*amount
	var throw_phase := throw_age/THROW_DURATION
	var compression := sin(throw_phase/0.18*PI) if throw_phase<0.18 else 0.0
	var launch := sin((throw_phase-0.18)/0.82*PI) if throw_phase>=0.18 and throw_phase<1.0 else 0.0
	if _reduced_motion:
		compression=0.0
		launch=0.0
	upper_body.position.y=hop*0.072+launch*0.27
	upper_body.rotation=Vector3(0.035*amount,0,cos(stride_phase)*0.032*amount)
	var squash := compression*0.18-hop*0.035-launch*0.065
	upper_body.scale=Vector3(1.0+squash*0.45,1.0-squash,1.0+squash*0.45)
	sprout.rotation.z=-0.5+step*0.05*amount
	for index in range(2):
		var side := -1.0 if index==0 else 1.0
		var foot_phase := fposmod(stride_phase+(PI if index==1 else 0.0),TAU)
		var swinging := foot_phase<PI
		# During contact, travel backwards by precisely the distance the body
		# advances. The planted foot no longer skates across the island.
		var reach := STRIDE_LENGTH/4.0
		var along := -cos(foot_phase)*reach if swinging else reach-(foot_phase-PI)/PI*reach*2.0
		var lift := sin(foot_phase)*0.075 if swinging else 0.0
		feet[index].position=FOOT_REST+Vector3(side*0.14,lift*amount+launch*0.23,along*amount)
		feet[index].rotation.x=sin(foot_phase)*0.22*amount if swinging else 0.0

func play_throw() -> void:
	# Called only for an observed held -> flying transition, never from a button.
	throw_age=0.0

func carry_anchor_position() -> Vector3:
	var seed_hop := absf(sin(stride_phase))*0.08*motion_blend if not _reduced_motion else 0.0
	return facing.transform*(upper_body.transform*Vector3(0,1.035,0))+Vector3(0,seed_hop,0)

func photo_anchor_height() -> float:
	# Clear the sprout, carried seed and the highest point of the throw hop.
	return carry_anchor_position().y+0.21 if carrying_seed else upper_body.position.y+upper_body.scale.y*1.10

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
