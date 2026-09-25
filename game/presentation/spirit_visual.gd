extends Node3D
## Presentation-only gait. The world supplies rendered displacement, never input
## or recording events, so the same animation works for players and saved ghosts.

signal stepped
signal reunion_started

const STRIDE_LENGTH := 0.82
const WALK_SPEED := 2.4
const FOOT_REST := Vector3(0,0.10,0.055)
const THROW_DURATION := 0.44
const RELEASE_SETTLE_DURATION := 0.38
const REUNION_DURATION := 0.48
const REUNION_NEAR := 1.55
const REUNION_FAR := 2.35
const REUNION_SPARKLE_DURATION := 0.55
const REUNION_SPARKLE_COUNT := 6
const HEAD_CENTER := Vector3(0,0.57,0)

var facing := Node3D.new()
var upper_body := Node3D.new()
var face := Node3D.new()
var head: MeshInstance3D
var eyes: Array[Node3D] = []
var feet: Array[Node3D] = []
var sprout: MeshInstance3D
var ground_ring: MeshInstance3D
var ground_shadow: MeshInstance3D
var stride_phase := 0.0
var step_phase := 0.0
var motion_blend := 0.0
var facing_target := 0.0
var carrying_seed := false
var carried_radius := 0.13
var throw_age := THROW_DURATION
var release_age := RELEASE_SETTLE_DURATION
var reunion_age := REUNION_DURATION
var reunion_sparkle_age := REUNION_SPARKLE_DURATION
var reunion_sparkles := Node3D.new()
var expression_phase := 0.0
var _expression_role := ""
var _expression_time := 0.0
var _idle_blend := 0.0
var _look := Vector2.ZERO
var _lean_direction := Vector2.ZERO
var _partner_offset := Vector3.ZERO
var _partner_available := false
var _attention_initialized := false
var _reunion_armed := false
var _reduced_motion := false

func _init(color: Color=Color("f4c38d")) -> void:
	facing.name="Facing"
	add_child(facing)
	upper_body.name="UpperBody"
	facing.add_child(upper_body)
	var torso := _sphere(0.29,color,Vector3(0,0.29,0),upper_body)
	torso.name="Torso"
	torso.scale=Vector3(1.0,0.82,0.92)
	head = _sphere(0.34,color,HEAD_CENTER,upper_body)
	head.name="Head"
	head.scale=Vector3(1.0,0.88,0.94)
	face.name="Face"
	face.position=HEAD_CENTER
	upper_body.add_child(face)
	for x: float in [-0.115,0.115]:
		var eye_group := Node3D.new()
		eye_group.name="LeftEye" if x<0 else "RightEye"
		eye_group.position=Vector3(x,0.02,0.289)
		face.add_child(eye_group)
		eyes.append(eye_group)
		var eye := _sphere(0.041,Color("24433f"),Vector3.ZERO,eye_group)
		eye.scale=Vector3(0.94,1.13,0.62)
		_sphere(0.008,Color("fff4d9"),Vector3(-0.010,0.015,0.024),eye_group)
		_sphere(0.033,Color("e8a695"),Vector3(x*1.5,-0.065,0.267),face)
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
	_build_reunion_sparkles()
	reset_motion()

func reset_motion() -> void:
	# A replay seek or level reset is a placement, not a giant walking step.
	stride_phase=0.0
	step_phase=0.0
	motion_blend=0.0
	throw_age=THROW_DURATION
	release_age=RELEASE_SETTLE_DURATION
	reunion_age=REUNION_DURATION
	_clear_reunion_sparkles()
	_expression_time=0.0
	_idle_blend=0.0
	_look=Vector2.ZERO
	_lean_direction=Vector2.ZERO
	_partner_available=false
	_attention_initialized=false
	_reunion_armed=false
	facing_target=0.0
	facing.rotation=Vector3.ZERO
	_apply_pose(0.0)

func set_expression_role(role: String) -> void:
	# Stable phases give the two spirits different timing on every device, without
	# drawing from simulation randomness or storing anything in a recording.
	if role==_expression_role: return
	_expression_role=role
	expression_phase=0.0 if role in ["a","p0"] else 1.73

func set_partner_offset(offset: Vector3, available: bool) -> void:
	# The world provides the visible partner in this root's local coordinates.
	_partner_offset=offset
	_partner_available=available and offset.is_finite()

func advance_motion(displacement: Vector3, delta: float, reduced_motion: bool) -> void:
	if delta<=0.0:
		return
	_reduced_motion=reduced_motion
	throw_age=minf(THROW_DURATION,throw_age+delta)
	release_age=minf(RELEASE_SETTLE_DURATION,release_age+delta)
	reunion_age=minf(REUNION_DURATION,reunion_age+delta)
	reunion_sparkle_age=minf(REUNION_SPARKLE_DURATION,reunion_sparkle_age+delta)
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
		_idle_blend=0.0
		_look=Vector2.ZERO
		_lean_direction=Vector2.ZERO
		reunion_age=REUNION_DURATION
		_clear_reunion_sparkles()
		release_age=RELEASE_SETTLE_DURATION
		_attention_initialized=false
		_reunion_armed=false
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
	_advance_expression(delta)
	_apply_pose(motion_blend)
	_apply_reunion_sparkles()
	# A stalled render frame must not release a burst of queued sounds.
	if contacts>0: stepped.emit()

func _advance_expression(delta: float) -> void:
	_expression_time+=delta
	_idle_blend=lerpf(_idle_blend,1.0-motion_blend,1.0-exp(-3.0*delta))
	var target := Vector2.ZERO
	var lean_target := Vector2.ZERO
	if _partner_available:
		var local := facing.basis.inverse()*_partner_offset
		var distance := _partner_offset.length()
		var planar := Vector2(local.x,local.z)
		if planar.length_squared()>0.0001:
			lean_target=planar.normalized()
		# The eyes stay on the face even when a partner walks behind the spirit.
		target=Vector2(local.x/maxf(0.6,absf(local.z)),local.y/maxf(distance,0.6)).clamp(Vector2(-1,-1),Vector2.ONE)
		if not _attention_initialized:
			_attention_initialized=true
			_reunion_armed=distance>=REUNION_FAR
		elif distance>=REUNION_FAR:
			# Only separating rearms the greeting; staying close never repeats it.
			_reunion_armed=true
		elif distance<=REUNION_NEAR and _reunion_armed:
			_reunion_armed=false
			if throw_age>=THROW_DURATION:
				reunion_age=0.0
				reunion_sparkle_age=0.0
				reunion_started.emit()
	else:
		_attention_initialized=false
		_reunion_armed=false
	_look=_look.lerp(target,1.0-exp(-5.0*delta))
	_lean_direction=_lean_direction.lerp(lean_target,1.0-exp(-5.0*delta))
	if lean_target==Vector2.ZERO and _lean_direction.length_squared()<0.000001:
		_lean_direction=Vector2.ZERO

func _apply_pose(amount: float) -> void:
	var step := sin(stride_phase)
	# Short spirits travel in little hops. Feet still counter-travel on contact.
	var hop := absf(step)*amount
	var throw_phase := throw_age/THROW_DURATION
	var compression := sin(throw_phase/0.18*PI) if throw_phase<0.18 else 0.0
	var launch := sin((throw_phase-0.18)/0.82*PI) if throw_phase>=0.18 and throw_phase<1.0 else 0.0
	var reunion := sin(reunion_age/REUNION_DURATION*PI) if reunion_age<REUNION_DURATION else 0.0
	var idle := _idle_blend*(1.0-amount)
	# Phase changes the strength, never the direction, of attention to a partner.
	var lean := _lean_direction*(0.014+sin(_expression_time*0.72+expression_phase)*0.003)*idle
	if _reduced_motion:
		compression=0.0
		launch=0.0
		reunion=0.0
		lean=Vector2.ZERO
	upper_body.position.y=hop*0.072+launch*0.27+reunion*0.11
	# Positive X pitch leans +Z; negative Z roll leans +X in the facing pivot.
	upper_body.rotation=Vector3(0.035*amount+lean.y,0,cos(stride_phase+expression_phase*0.18)*0.032*amount-lean.x)
	var squash := compression*0.18-hop*0.035-launch*0.065
	upper_body.scale=Vector3(1.0+squash*0.45,1.0-squash,1.0+squash*0.45)
	var settle := 0.0
	if release_age>=0.0 and release_age<RELEASE_SETTLE_DURATION and not _reduced_motion:
		var phase := release_age/RELEASE_SETTLE_DURATION
		settle=sin(phase*TAU*1.5)*0.065*pow(1.0-phase,2.0)
	var tilt := (_look.x*0.06+sin(_expression_time*0.91+expression_phase)*0.018*idle)*(1.0-amount*0.65)+settle
	if _reduced_motion: tilt=0.0
	head.rotation.z=tilt
	face.rotation.z=tilt
	sprout.position=HEAD_CENTER+Basis(Vector3.BACK,tilt)*(Vector3(-0.19,0.90,-0.035)-HEAD_CENTER)
	sprout.rotation.z=-0.5+tilt+step*0.05*amount+settle*0.45
	var blink := 1.0
	if not _reduced_motion and _expression_time>0.0:
		var blink_time := fposmod(_expression_time+expression_phase,4.3+expression_phase*0.25)
		if blink_time>3.8 and blink_time<3.98:
			blink=1.0-sin((blink_time-3.8)/0.18*PI)*0.94
	for index in range(eyes.size()):
		var x := -0.115 if index==0 else 0.115
		eyes[index].position=Vector3(x+_look.x*0.018,0.02+_look.y*0.009,0.289)
		eyes[index].scale.y=blink
	for index in range(2):
		var side := -1.0 if index==0 else 1.0
		var foot_phase := fposmod(stride_phase+(PI if index==1 else 0.0),TAU)
		var swinging := foot_phase<PI
		# During contact, travel backwards by precisely the distance the body
		# advances. The planted foot no longer skates across the island.
		var reach := STRIDE_LENGTH/4.0
		var along := -cos(foot_phase)*reach if swinging else reach-(foot_phase-PI)/PI*reach*2.0
		var lift := sin(foot_phase)*0.075 if swinging else 0.0
		feet[index].position=FOOT_REST+Vector3(side*0.14,lift*amount+launch*0.23+reunion*0.095,along*amount)
		feet[index].rotation.x=sin(foot_phase)*0.22*amount if swinging else 0.0

func play_throw() -> void:
	# Called only for an observed held -> flying transition, never from a button.
	throw_age=0.0
	release_age=-THROW_DURATION
	reunion_age=REUNION_DURATION

func play_carry_release() -> void:
	# A Lighthouse offer is a successful release, not an invented throw arc.
	release_age=0.0

func carry_anchor_position() -> Vector3:
	var seed_hop := absf(sin(stride_phase))*0.08*motion_blend if not _reduced_motion else 0.0
	var wobble := Vector3.ZERO
	if carrying_seed and not _reduced_motion:
		wobble=Vector3(sin(stride_phase+expression_phase)*0.022*motion_blend+sin(_expression_time*1.8+expression_phase)*0.004*_idle_blend,0,cos(stride_phase+expression_phase)*0.012*motion_blend)
	# The wider Lighthouse lens also clears the sprout beside the head.
	var carry_height := 0.925+carried_radius+maxf(0.0,carried_radius-0.13)*0.5
	return facing.transform*(upper_body.transform*(Vector3(0,carry_height,0)+wobble))+Vector3(0,seed_hop,0)

func photo_anchor_height() -> float:
	# Clear the sprout, carried seed and the highest point of the throw hop.
	return carry_anchor_position().y+carried_radius+0.08 if carrying_seed else upper_body.position.y+upper_body.scale.y*1.10

func _build_reunion_sparkles() -> void:
	reunion_sparkles.name="ReunionSparkles"
	add_child(reunion_sparkles)
	var points := PackedVector3Array([
		Vector3(0,1,0),Vector3(0.22,0.22,0),Vector3(1,0,0),Vector3(0.22,-0.22,0),
		Vector3(0,-1,0),Vector3(-0.22,-0.22,0),Vector3(-1,0,0),Vector3(-0.22,0.22,0)
	])
	var vertices := PackedVector3Array()
	for index in range(points.size()):
		vertices.append_array(PackedVector3Array([Vector3.ZERO,points[index],points[(index+1)%points.size()]]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	var shape := ArrayMesh.new()
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("fff0bc")
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale=true
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	for index in range(REUNION_SPARKLE_COUNT):
		var sparkle := MeshInstance3D.new()
		sparkle.name="Sparkle%d" % index
		sparkle.mesh=shape
		sparkle.material_override=material
		sparkle.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		reunion_sparkles.add_child(sparkle)

func _clear_reunion_sparkles() -> void:
	reunion_sparkle_age=REUNION_SPARKLE_DURATION
	reunion_sparkles.hide()

func _apply_reunion_sparkles() -> void:
	# Advance with the character clock, so pause and replay placement need no timers.
	if reunion_sparkle_age>=REUNION_SPARKLE_DURATION or _reduced_motion:
		reunion_sparkles.hide()
		return
	reunion_sparkles.show()
	var progress := reunion_sparkle_age/REUNION_SPARKLE_DURATION
	var spread := 0.22+0.30*(1.0-pow(1.0-progress,2.0))
	var size := 0.055*minf(1.0,0.2+progress*10.0)*pow(1.0-progress,0.7)
	for index in range(REUNION_SPARKLE_COUNT):
		var sparkle: MeshInstance3D=reunion_sparkles.get_child(index)
		var angle := float(index)*TAU/REUNION_SPARKLE_COUNT+expression_phase*0.31
		sparkle.position=Vector3(cos(angle)*spread,0.43+float(index%3)*0.13+progress*0.30,sin(angle)*spread)
		sparkle.scale=Vector3.ONE*size

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
