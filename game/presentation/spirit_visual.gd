extends Node3D
## Presentation-only gait. The world supplies rendered displacement, never input
## or recording events, so the same animation works for players and saved ghosts.

const SpiritIdle = preload("res://presentation/spirit_idle.gd")
const Badges = preload("res://presentation/kit/badges.gd")

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
const CELEBRATION_DURATION := 2.2
const HEAD_CENTER := Vector3(0,0.57,0)
const TORSO_SCALE := Vector3(1.0,0.82,0.92)
const SPROUT_REST := Vector3(-0.19,0.90,-0.035)
## How fast a new pose (set_pose) eases in: about half a second.
const POSE_BLEND_RATE := 6.0
## The startled wake (play_wake) and the moment in it when the goal rings:
## just after the hop lands (presentation/memory_wait.gd reads this).
const WAKE_DURATION := SpiritIdle.WAKE_DURATION
const WAKE_RING_AT := 0.42
## Floating z's over a dozing spirit: three, each rising and fading over one
## cycle, a third of a cycle apart.
const DOZE_Z_COUNT := 3
const DOZE_Z_CYCLE := 2.6
const DOZE_Z_BASE := Vector3(0.28,0.82,0.0)
## Each z drifts up, right and back, which reads as up the screen under the
## chapters' high oblique cameras.
const DOZE_Z_RISE := Vector3(0.30,0.45,-0.45)
# Happy eyes: open eyes squeeze shut into soft upturned arcs, then reopen.
const HAPPY_REUNION_DURATION := 1.1
const GREETING_DURATION := 1.2
const HAPPY_CLOSE_TIME := 0.10
const HAPPY_OPEN_TIME := 0.14
const HAPPY_ARC_STEPS := 10
const HAPPY_ARC_SIDES := 6
const HAPPY_ARC_RADIUS := 0.015
const HEAD_AXES := Vector3(0.34,0.34*0.88,0.34*0.94)
const EYE_COLOR := Color("24433f")
## The soft ground shadow: a thin translucent disc. It writes no depth, so an
## opaque face at its height shows through it in stripes. Its top lies over
## the floor's lines, trims, rugs, caps and zone strips (up to 2.1 cm) and
## under the bridge deck trims (2.75 cm), pads and plates, 3.25 mm from the
## nearest. The dressing lint keeps every chapter clear of it wherever a
## spirit stands (test_dressing_lint.gd).
const SHADOW_RADIUS := 0.30
const SHADOW_TOP := 0.02425
const SHADOW_THICKNESS := 0.004

var facing := Node3D.new()
var upper_body := Node3D.new()
var face := Node3D.new()
var torso: MeshInstance3D
var head: MeshInstance3D
var eyes: Array[Node3D] = []
var happy_eyes: Array[MeshInstance3D] = []
var cheeks: Array[MeshInstance3D] = []
var happy_age := 0.0
var happy_duration := 0.0
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
var celebration_age := CELEBRATION_DURATION
var _celebration_complete := false
## The resting pose layer (spirit_idle.gd): breath, leaf sway and, alone, a
## glance; other poses come in through set_pose.
var _pose: StringName = SpiritIdle.REST
var _pose_from: StringName = SpiritIdle.REST
var _pose_blend := 1.0
var _pose_params: Dictionary = {}
var _pose_context: Dictionary = {}
var _pose_frame := SpiritIdle.Frame.new()
var _pose_frame_from := SpiritIdle.Frame.new()
var _pose_frame_to := SpiritIdle.Frame.new()
var _wake_age := SpiritIdle.WAKE_DURATION
var _wake_frame := SpiritIdle.Frame.new()
## Built on the first doze only, so a spirit that never dozes has no extra nodes.
var _doze_zs: Array[Label3D] = []

func _init(color: Color=Color("f4c38d")) -> void:
	facing.name="Facing"
	add_child(facing)
	upper_body.name="UpperBody"
	facing.add_child(upper_body)
	torso = _sphere(0.29,color,Vector3(0,0.29,0),upper_body)
	torso.name="Torso"
	torso.scale=TORSO_SCALE
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
		var eye := _sphere(0.041,EYE_COLOR,Vector3.ZERO,eye_group)
		eye.scale=Vector3(0.94,1.13,0.62)
		_sphere(0.008,Color("fff4d9"),Vector3(-0.010,0.015,0.024),eye_group)
		var arc := _mesh(_happy_eye_mesh(x),EYE_COLOR,eye_group.position,face)
		arc.name="LeftHappyEye" if x<0 else "RightHappyEye"
		arc.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arc.visible=false
		happy_eyes.append(arc)
		cheeks.append(_sphere(0.033,Color("e8a695"),Vector3(x*1.5,-0.065,0.267),face))
	# The sprout leans aside so a carried seed sits clearly above the head.
	sprout=_sphere(0.12,Color("abd1a2"),SPROUT_REST,upper_body)
	sprout.scale=Vector3(0.6,1,0.28)
	for side: float in [-1.0,1.0]:
		var foot := Node3D.new()
		foot.name="LeftFoot" if side<0 else "RightFoot"
		facing.add_child(foot)
		var shoe := _sphere(0.095,color.darkened(0.12),Vector3.ZERO,foot)
		shoe.scale=Vector3(1,0.6,1.5)
		feet.append(foot)
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius=SHADOW_RADIUS
	shadow_mesh.bottom_radius=SHADOW_RADIUS
	shadow_mesh.height=SHADOW_THICKNESS
	shadow_mesh.radial_segments=24
	ground_shadow=_mesh(shadow_mesh,Color(0.12,0.23,0.21,0.2),Vector3(0,SHADOW_TOP-SHADOW_THICKNESS*0.5,0),self)
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
	celebration_age=CELEBRATION_DURATION
	_celebration_complete=false
	_clear_reunion_sparkles()
	_clear_happy()
	_expression_time=0.0
	_idle_blend=0.0
	_look=Vector2.ZERO
	_lean_direction=Vector2.ZERO
	_partner_available=false
	_attention_initialized=false
	_reunion_armed=false
	# The pose stays; a seek places it at full strength from time zero.
	_pose_from=_pose
	_pose_blend=1.0
	_wake_age=SpiritIdle.WAKE_DURATION
	facing_target=0.0
	facing.rotation=Vector3.ZERO
	_apply_pose(0.0)

func set_expression_role(role: String) -> void:
	# Stable phases give the two spirits different timing on every device, without
	# drawing from simulation randomness or storing anything in a recording.
	if role==_expression_role: return
	_expression_role=role
	expression_phase=0.0 if role in ["a","p0"] else 1.73

## Switches the resting pose layer (spirit_idle.gd), easing in over about half
## a second, or at once with `immediate`. &"rest" is the default. Calling it
## again with the same pose and params does nothing, so a world may assert it
## every frame. params: pose-specific, e.g. {"toward": a global point}.
func set_pose(pose: StringName, params: Dictionary = {}, immediate: bool = false) -> void:
	if not SpiritIdle.has_pose(pose):
		push_warning("Unknown spirit pose %s" % pose)
		return
	if pose==_pose and params==_pose_params:
		if immediate: _pose_blend=1.0
		return
	if pose!=_pose:
		_pose_from=_pose
		_pose=pose
		_pose_blend=1.0 if immediate else 0.0
	_pose_params=params.duplicate()
	_pose_context.clear()
	if pose==SpiritIdle.DOZE and _doze_zs.is_empty(): _build_doze_zs()

func pose() -> StringName:
	return _pose

## Wakes a dozing spirit with a start: back to rest at once, eyes open, and a
## quick hop. Reduce motion opens the eyes without the hop.
func play_wake(reduced: bool) -> void:
	set_pose(SpiritIdle.REST, {}, true)
	_wake_age=SpiritIdle.WAKE_DURATION if reduced else 0.0
	_apply_pose(motion_blend)

func waking() -> bool:
	return _wake_age<SpiritIdle.WAKE_DURATION

func set_partner_offset(offset: Vector3, available: bool) -> void:
	# The world provides the visible partner in this root's local coordinates.
	_partner_offset=offset
	_partner_available=available and offset.is_finite()

func set_celebration(completed: bool, immediate: bool = false, reduced: bool = false) -> void:
	var newly_completed := completed and not _celebration_complete
	_celebration_complete = completed
	# A seek into a finished state is placement; only a live completion smiles.
	# Reduced Motion keeps the still smile and drops the dance.
	if newly_completed and not immediate:
		show_happy(CELEBRATION_DURATION)
	if not completed or immediate or reduced:
		celebration_age = CELEBRATION_DURATION
	elif newly_completed:
		celebration_age = 0.0
		reunion_age = REUNION_DURATION
		_clear_reunion_sparkles()

func show_happy(duration: float) -> void:
	# Extending an active smile keeps the eyes closed instead of blinking open.
	if is_happy():
		happy_duration=maxf(happy_duration,happy_age+duration)
	else:
		happy_age=0.0
		happy_duration=maxf(0.0,duration)

func is_happy() -> bool:
	return happy_age<happy_duration

func play_greeting(reduced: bool) -> void:
	# Home-only flourish: the reunion hop and sparkles with happy eyes. Reduced
	# Motion keeps only the still expression. Gameplay never calls this.
	show_happy(GREETING_DURATION)
	if reduced: return
	reunion_age=0.0
	reunion_sparkle_age=0.0

func end_greeting() -> void:
	reunion_age=REUNION_DURATION
	_clear_reunion_sparkles()
	_clear_happy()
	_apply_pose(motion_blend)

func _clear_happy() -> void:
	happy_age=0.0
	happy_duration=0.0

func advance_motion(displacement: Vector3, delta: float, reduced_motion: bool) -> void:
	if delta<=0.0:
		return
	_reduced_motion=reduced_motion
	happy_age=minf(happy_duration,happy_age+delta)
	throw_age=minf(THROW_DURATION,throw_age+delta)
	release_age=minf(RELEASE_SETTLE_DURATION,release_age+delta)
	reunion_age=minf(REUNION_DURATION,reunion_age+delta)
	reunion_sparkle_age=minf(REUNION_SPARKLE_DURATION,reunion_sparkle_age+delta)
	celebration_age=minf(CELEBRATION_DURATION,celebration_age+delta)
	_wake_age=minf(SpiritIdle.WAKE_DURATION,_wake_age+delta)
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
		celebration_age=CELEBRATION_DURATION
		release_age=RELEASE_SETTLE_DURATION
		_attention_initialized=false
		_reunion_armed=false
		_pose_blend=1.0
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
	if _pose_blend<1.0:
		_pose_blend=1.0-(1.0-_pose_blend)*exp(-POSE_BLEND_RATE*delta)
		if _pose_blend>0.999: _pose_blend=1.0
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
			if throw_age>=THROW_DURATION and celebration_age>=CELEBRATION_DURATION:
				reunion_age=0.0
				reunion_sparkle_age=0.0
				show_happy(HAPPY_REUNION_DURATION)
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
	var dance_progress := clampf(celebration_age / CELEBRATION_DURATION, 0.0, 1.0)
	var dance := sin(PI * dance_progress) * (1.0 - amount) if celebration_age < CELEBRATION_DURATION and not _reduced_motion else 0.0
	var dance_phase := dance_progress * TAU * 3.0 + (0.0 if expression_phase == 0.0 else PI)
	var sway := sin(dance_phase) * dance
	# Phase changes the strength, never the direction, of attention to a partner.
	var lean := _lean_direction*(0.014+sin(_expression_time*0.72+expression_phase)*0.003)*idle
	if _reduced_motion:
		compression=0.0
		launch=0.0
		reunion=0.0
		lean=Vector2.ZERO
	upper_body.position=Vector3(sway*0.055,hop*0.072+launch*0.27+reunion*0.11+absf(sin(dance_phase))*dance*0.10,0)
	# Positive X pitch leans +Z; negative Z roll leans +X in the facing pivot.
	upper_body.rotation=Vector3(0.035*amount+lean.y,sway*0.14,cos(stride_phase+expression_phase*0.18)*0.032*amount-lean.x+sway*0.24)
	var squash := compression*0.18-hop*0.035-launch*0.065
	upper_body.scale=Vector3(1.0+squash*0.45,1.0-squash,1.0+squash*0.45)
	var settle := 0.0
	if release_age>=0.0 and release_age<RELEASE_SETTLE_DURATION and not _reduced_motion:
		var phase := release_age/RELEASE_SETTLE_DURATION
		settle=sin(phase*TAU*1.5)*0.065*pow(1.0-phase,2.0)
	var tilt := (_look.x*0.06+sin(_expression_time*0.91+expression_phase)*0.018*idle)*(1.0-amount*0.65)+settle-sway*0.08
	if _reduced_motion: tilt=0.0
	var rest := _sample_pose(idle)
	# Only a pose other than rest moves the body that carried props hang from.
	if rest.body_lean!=Vector3.ZERO: upper_body.rotation+=rest.body_lean
	if rest.body_drop!=0.0: upper_body.position.y-=rest.body_drop
	torso.scale=TORSO_SCALE*rest.torso_scale
	# Face and sprout are the head's siblings: they lift and turn with it.
	var rise := Vector3(0,rest.head_lift,0)
	head.position=HEAD_CENTER+rise
	face.position=HEAD_CENTER+rise
	head.rotation=Vector3(0,rest.head_yaw,tilt)
	face.rotation=Vector3(0,rest.head_yaw,tilt)
	sprout.position=HEAD_CENTER+rise+Basis(Vector3.UP,rest.head_yaw)*Basis(Vector3.BACK,tilt)*(SPROUT_REST-HEAD_CENTER)
	sprout.rotation=Vector3(0,rest.head_yaw,-0.5+tilt+step*0.05*amount+settle*0.45+rest.sprout_roll)
	var look := _look+rest.look
	var blink := 1.0
	if not _reduced_motion and _expression_time>0.0:
		var blink_time := fposmod(_expression_time+expression_phase,4.3+expression_phase*0.25)
		if blink_time>3.8 and blink_time<3.98:
			blink=1.0-sin((blink_time-3.8)/0.18*PI)*0.94
	var happy := _happy_blend()
	# Open eyes squeeze shut first and the arcs pop in as they close, so the
	# two shapes overlap only briefly. Cheeks lift a little with the smile.
	var closed := smoothstep(0.0,0.6,happy)
	var arc := smoothstep(0.45,1.0,happy)
	var shut := maxf(closed,rest.eyes_closed)
	for index in range(eyes.size()):
		var x := -0.115 if index==0 else 0.115
		var at := Vector3(x+look.x*0.018,0.02+look.y*0.009,0.289)
		eyes[index].position=at
		eyes[index].scale.y=blink*lerpf(1.0,0.06,shut)*(1.0+rest.eyes_wide)
		eyes[index].visible=closed<1.0
		happy_eyes[index].position=at
		happy_eyes[index].visible=arc>0.0
		happy_eyes[index].scale=Vector3.ONE*(lerpf(0.55,1.0,arc)+sin(arc*PI)*0.08)
		cheeks[index].scale=Vector3.ONE*(1.0+happy*0.2)
		cheeks[index].position=Vector3(x*1.5,-0.065+happy*0.006,0.267)
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
		var tap := maxf(0.0, sin(dance_phase + (PI if index == 1 else 0.0))) * dance
		feet[index].position += Vector3(side*tap*0.075,tap*0.11,tap*0.075)
		feet[index].rotation.x=sin(foot_phase)*0.22*amount if swinging else 0.0
		feet[index].rotation.x -= tap*0.22
	if not _doze_zs.is_empty(): _apply_doze_zs(idle)

## The pose layer's offsets this frame, faded by `idle` (none while walking).
## Reduce motion gives each pose's still frame: nothing at all for rest.
func _sample_pose(idle: float) -> SpiritIdle.Frame:
	var alone := not _partner_available
	if _pose_params.has("toward"):
		var toward: Vector3=_pose_params.toward
		var local := to_local(toward) if is_inside_tree() else toward-position
		_pose_context["toward"]=facing.basis.inverse()*local
	if _pose_blend>=1.0 or _pose_from==_pose:
		SpiritIdle.sample(_pose,_expression_time,expression_phase,alone,_reduced_motion,_pose_context,_pose_frame)
	else:
		SpiritIdle.sample(_pose_from,_expression_time,expression_phase,alone,_reduced_motion,_pose_context,_pose_frame_from)
		SpiritIdle.sample(_pose,_expression_time,expression_phase,alone,_reduced_motion,_pose_context,_pose_frame_to)
		_pose_frame.blend(_pose_frame_from,_pose_frame_to,_pose_blend)
	if not _reduced_motion: _pose_frame.scale_by(idle)
	if _wake_age<SpiritIdle.WAKE_DURATION:
		SpiritIdle.wake(_wake_age,_reduced_motion,_wake_frame)
		_pose_frame.add(_wake_frame)
	return _pose_frame

## How much of the doze shows (0..1), through any blend into or out of it.
func _doze_weight() -> float:
	if _pose==SpiritIdle.DOZE: return _pose_blend
	if _pose_from==SpiritIdle.DOZE: return 1.0-_pose_blend
	return 0.0

## The z's rise and fade on their own cycle of the spirit clock; Reduce motion
## holds them still, part way up.
func _apply_doze_zs(idle: float) -> void:
	var weight := _doze_weight()*(1.0 if _reduced_motion else idle)
	for index in range(_doze_zs.size()):
		var z := _doze_zs[index]
		z.visible=weight>0.01
		if not z.visible: continue
		var u := float(index+1)/float(DOZE_Z_COUNT+1) if _reduced_motion else fposmod(_expression_time/DOZE_Z_CYCLE+float(index)/float(DOZE_Z_COUNT)+expression_phase*0.1,1.0)
		var drift := 0.0 if _reduced_motion else sin(u*TAU)*0.035
		z.position=DOZE_Z_BASE+DOZE_Z_RISE*u+Vector3(drift,0.0,0.0)
		z.scale=Vector3.ONE*(0.95+0.6*u)
		var alpha := (0.85 if _reduced_motion else sin(u*PI))*weight
		z.modulate.a=alpha
		z.outline_modulate.a=alpha*0.8

## The z's are the kit's small glyphs over a spirit (kit/badges.gd), kept
## over the bell's frame and the badge the way the badge is.
func _build_doze_zs() -> void:
	for index in range(DOZE_Z_COUNT):
		var z := Badges.glyph(self, "z", DOZE_Z_BASE, Badges.CREAM, Badges.OUTLINE)
		z.name="DozeZ%d" % index
		z.no_depth_test=true
		z.outline_render_priority=1
		z.render_priority=2
		z.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		z.visible=false
		_doze_zs.append(z)

func _happy_blend() -> float:
	if not is_happy(): return 0.0
	# Reduced Motion swaps the expression without the squeeze animation.
	if _reduced_motion: return 1.0
	return minf(smoothstep(0.0,HAPPY_CLOSE_TIME,happy_age),smoothstep(0.0,HAPPY_OPEN_TIME,happy_duration-happy_age))

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

static func head_depth(x: float, y: float) -> float:
	# Front of the head ellipsoid in face space; the face origin is the head center.
	return HEAD_AXES.z*sqrt(maxf(0.0,1.0-pow(x/HEAD_AXES.x,2.0)-pow(y/HEAD_AXES.y,2.0)))

func _happy_eye_mesh(eye_x: float) -> ArrayMesh:
	# A soft upturned arc (^) that follows the head surface across the eye.
	var path: Array[Vector3] = []
	for step in range(HAPPY_ARC_STEPS+1):
		var angle := lerpf(PI*0.94,PI*0.06,float(step)/HAPPY_ARC_STEPS)
		var x := cos(angle)*0.044
		var y := sin(angle)*0.040-0.012
		path.append(Vector3(x,y,head_depth(eye_x+x,0.02+y)+0.007-0.289))
	var rings: Array = []
	for index in range(path.size()):
		var tangent := (path[mini(index+1,path.size()-1)]-path[maxi(index-1,0)]).normalized()
		rings.append(_arc_ring(path[index],tangent,1.0,0.0))
	# Hemispherical caps keep both ends of the stroke rounded.
	var start_tangent := (path[1]-path[0]).normalized()
	var end_tangent := (path[-1]-path[-2]).normalized()
	for step in range(1,4):
		var bend := float(step)/3.0*PI*0.5
		rings.push_front(_arc_ring(path[0],start_tangent,cos(bend),-sin(bend)))
		rings.append(_arc_ring(path[-1],end_tangent,cos(bend),sin(bend)))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for index in range(rings.size()-1):
		for side in range(HAPPY_ARC_SIDES):
			var next := (side+1)%HAPPY_ARC_SIDES
			_arc_triangle(vertices,normals,rings[index][side],rings[index+1][side],rings[index][next])
			_arc_triangle(vertices,normals,rings[index][next],rings[index+1][side],rings[index+1][next])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	var shape := ArrayMesh.new()
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return shape

func _arc_ring(center: Vector3, tangent: Vector3, radial: float, axial: float) -> Array:
	# Frame: out of the face (+Z) and its binormal, both normal to the tangent.
	var outward := (Vector3.BACK-tangent*tangent.dot(Vector3.BACK)).normalized()
	var side := tangent.cross(outward)
	var ring := []
	for index in range(HAPPY_ARC_SIDES):
		var angle := TAU*float(index)/HAPPY_ARC_SIDES
		var normal := (outward*cos(angle)+side*sin(angle))*radial+tangent*axial
		ring.append([center+normal*HAPPY_ARC_RADIUS,normal.normalized()])
	return ring

func _arc_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, a: Array, b: Array, c: Array) -> void:
	# Godot front faces wind clockwise as seen from outside the surface.
	var outside: bool=(b[0]-a[0]).cross(c[0]-a[0]).dot(a[1]+b[1]+c[1])>0.0
	for corner: Array in ([a,c,b] if outside else [a,b,c]):
		vertices.append(corner[0])
		normals.append(corner[1])

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
