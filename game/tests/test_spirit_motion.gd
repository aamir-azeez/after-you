extends SceneTree

const Spirit = preload("res://presentation/spirit_visual.gd")
const World = preload("res://presentation/island_world.gd")
const Simulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")
const LighthouseWorld = preload("res://presentation/lighthouse_world.gd")
const LighthouseStages = preload("res://core/lighthouse/stage_catalog.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_walk_and_settle()
	_test_render_rates_and_direction()
	_test_reduced_motion_and_reset()
	_test_foot_contacts()
	_test_throw_and_head_carry()
	_test_expressions()
	_test_partner_lean()
	_test_reunion()
	_test_reunion_sparkles()
	_test_completion_dance()
	_test_happy_eyes()
	_test_lighthouse_carry()
	await _test_saved_ghost_integration()
	print("AFTER YOU SPIRIT MOTION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _test_completion_dance() -> void:
	var spirit := Spirit.new()
	root.add_child(spirit)
	spirit.position = Vector3(4, 1, -2)
	var placed := spirit.transform
	var ring := spirit.ground_ring.transform
	var shadow := spirit.ground_shadow.transform
	var highest := 0.0
	var sideways := 0.0
	for _frame in range(180):
		# A completed snapshot may be presented repeatedly without restarting it.
		spirit.set_celebration(true)
		spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
		highest = maxf(highest, spirit.upper_body.position.y)
		sideways = maxf(sideways, absf(spirit.upper_body.position.x))
	_check(highest > 0.03 and sideways > 0.02, "A fresh completion produces a celebratory hop and sideways dance")
	_check(spirit.upper_body.position == Vector3.ZERO and spirit.upper_body.scale == Vector3.ONE, "Repeated completed snapshots let the finite dance settle instead of looping")
	_check(spirit.transform == placed and spirit.ground_ring.transform == ring and spirit.ground_shadow.transform == shadow, "Celebration never moves the gameplay root, ground marker, or shadow")
	spirit.set_celebration(false)
	spirit.set_celebration(true)
	var rearmed := false
	for _frame in range(45):
		spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
		rearmed = rearmed or spirit.upper_body.position.y > 0.03
	_check(rearmed, "Returning to an unfinished state rearms the next real completion")
	spirit.reset_motion()
	_check(spirit.upper_body.position == Vector3.ZERO and spirit.upper_body.scale == Vector3.ONE, "A replay reset clears an in-progress dance")
	for reduced: bool in [false, true]:
		spirit.reset_motion()
		spirit.set_celebration(true, not reduced, reduced)
		var still := true
		for _frame in range(180):
			spirit.set_celebration(true, false, reduced)
			spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, reduced)
			still = still and spirit.upper_body.position == Vector3.ZERO and spirit.upper_body.scale == Vector3.ONE
		_check(still, "Immediate seeks and reduced motion latch completion without a delayed celebration")
	spirit.free()

func _happy_shown(spirit: Node3D) -> bool:
	return spirit.happy_eyes[0].visible and spirit.happy_eyes[1].visible and not spirit.eyes[0].visible and not spirit.eyes[1].visible

func _eyes_normal(spirit: Node3D) -> bool:
	return not spirit.happy_eyes[0].visible and not spirit.happy_eyes[1].visible and spirit.eyes[0].visible and spirit.eyes[1].visible and not spirit.is_happy()

func _test_happy_eyes() -> void:
	var spirit := Spirit.new()
	root.add_child(spirit)
	spirit.set_expression_role("a")
	_check(_eyes_normal(spirit) and spirit.happy_eyes.size()==2 and spirit.cheeks.size()==2,"A new spirit starts with open eyes and hidden happy arcs")
	# Brand: expression lives in the eyes only. Arcs sit on the eye line, outside the head.
	var outside := true
	var on_eye_line := true
	for arc: MeshInstance3D in spirit.happy_eyes:
		var arrays: Array=arc.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		for index in range(vertices.size()):
			var point: Vector3=arc.position+vertices[index]
			on_eye_line=on_eye_line and point.y>-0.02 and point.y<0.07
			if normals[index].z>0.5:
				outside=outside and pow(point.x/Spirit.HEAD_AXES.x,2.0)+pow(point.y/Spirit.HEAD_AXES.y,2.0)+pow(point.z/Spirit.HEAD_AXES.z,2.0)>1.0
	_check(outside and on_eye_line,"Happy arcs stay on the eye line and in front of the head surface")
	_check(not spirit.face.has_node("Mouth") and spirit.face.get_child_count()==6,"The face holds only eyes, happy arcs and cheeks: no mouth")
	# A reunion closes the eyes into arcs, then they reopen.
	spirit.set_partner_offset(Vector3(3,0,0),true)
	spirit.advance_motion(Vector3.ZERO,1.0/60.0,false)
	spirit.set_partner_offset(Vector3(1,0,0),true)
	spirit.advance_motion(Vector3.ZERO,1.0/60.0,false)
	_check(spirit.reunion_age==0.0 and spirit.is_happy(),"Meeting a partner starts happy eyes with the reunion hop")
	for _frame in range(15): spirit.advance_motion(Vector3.ZERO,1.0/60.0,false)
	_check(_happy_shown(spirit) and spirit.cheeks[0].scale.x>1.1,"Mid-reunion the eyes are closed into happy arcs")
	for _frame in range(ceili(Spirit.HAPPY_REUNION_DURATION*60.0)): spirit.advance_motion(Vector3.ZERO,1.0/60.0,false)
	_check(_eyes_normal(spirit) and spirit.cheeks[0].scale==Vector3.ONE,"Happy eyes return to normal after the reunion")
	# Completion keeps its existing dance and adds happy eyes for its length.
	spirit.set_celebration(true)
	for _frame in range(30):
		spirit.set_celebration(true)
		spirit.advance_motion(Vector3.ZERO,1.0/60.0,false)
	_check(_happy_shown(spirit),"A live completion shows happy eyes during the dance")
	for _frame in range(ceili(Spirit.CELEBRATION_DURATION*60.0)):
		spirit.set_celebration(true)
		spirit.advance_motion(Vector3.ZERO,1.0/60.0,false)
	_check(_eyes_normal(spirit) and spirit.upper_body.position==Vector3.ZERO,"Completion happy eyes end with the dance")
	spirit.reset_motion()
	spirit.set_celebration(true,true)
	spirit.advance_motion(Vector3.ZERO,0.2,false)
	_check(_eyes_normal(spirit),"Seeking into a completed state places the spirit without a smile")
	spirit.reset_motion()
	spirit.set_celebration(true,false,true)
	spirit.advance_motion(Vector3.ZERO,1.0/60.0,true)
	_check(_happy_shown(spirit) and spirit.happy_eyes[0].scale.is_equal_approx(Vector3.ONE) and spirit.upper_body.position==Vector3.ZERO,"Reduced Motion shows a still smile without the dance")
	spirit.reset_motion()
	_check(_eyes_normal(spirit),"A replay reset clears happy eyes immediately")
	# Home greeting: hop, sparkles and happy eyes; Reduced Motion keeps only the eyes.
	spirit.play_greeting(false)
	var highest := 0.0
	var sparkled := false
	var happy_mid := false
	for _frame in range(20):
		spirit.advance_motion(Vector3.ZERO,1.0/60.0,false)
		highest=maxf(highest,spirit.upper_body.position.y)
		sparkled=sparkled or spirit.reunion_sparkles.visible
		happy_mid=happy_mid or _happy_shown(spirit)
	_check(highest>0.07 and sparkled and happy_mid,"A greeting hops, sparkles and smiles like a reunion")
	for _frame in range(ceili(Spirit.GREETING_DURATION*60.0)): spirit.advance_motion(Vector3.ZERO,1.0/60.0,false)
	_check(_eyes_normal(spirit) and not spirit.reunion_sparkles.visible and spirit.upper_body.position==Vector3.ZERO,"The greeting settles fully within its short duration")
	spirit.play_greeting(true)
	var still := true
	var reduced_smile := false
	for _frame in range(20):
		spirit.advance_motion(Vector3.ZERO,1.0/60.0,true)
		still=still and spirit.upper_body.position==Vector3.ZERO and not spirit.reunion_sparkles.visible
		reduced_smile=reduced_smile or _happy_shown(spirit)
	_check(still and reduced_smile,"A Reduced Motion greeting smiles without a hop or sparkles")
	spirit.end_greeting()
	_check(_eyes_normal(spirit) and spirit.reunion_age==Spirit.REUNION_DURATION,"Ending a greeting restores normal eyes immediately")
	spirit.play_greeting(false)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	var age: float=spirit.happy_age
	spirit.advance_motion(Vector3.ZERO,0.0,false)
	_check(spirit.happy_age==age,"Paused presentation holds the happy eyes")
	spirit.free()

func _test_walk_and_settle() -> void:
	var spirit := Spirit.new()
	root.add_child(spirit)
	spirit.position=Vector3(3,2,1)
	var root_transform := spirit.transform
	var ring_transform := spirit.ground_ring.transform
	var shadow_transform := spirit.ground_shadow.transform
	var largest_foot_difference := 0.0
	var largest_bob := 0.0
	for _frame in range(50):
		spirit.advance_motion(Vector3(0.04,0,0),1.0/60.0,false)
		largest_foot_difference=maxf(largest_foot_difference,absf(spirit.feet[0].position.z-spirit.feet[1].position.z))
		largest_bob=maxf(largest_bob,spirit.upper_body.position.y)
	_check(largest_foot_difference>0.07,"Walking produces distinct alternating foot placement instead of sliding rigid feet")
	_check(not spirit.upper_body.has_node("LeftArm") and not spirit.upper_body.has_node("RightArm"),"Compact spirits have no arm meshes")
	_check(largest_bob>0.05 and largest_bob<0.09,"Walking has a readable bounded hop")
	_check(spirit.upper_body.get_node("Head").get_parent()==spirit.upper_body.get_node("Torso").get_parent(),"Head and torso share the same animated body pivot")
	_check(spirit.transform==root_transform,"Gait never changes the simulation-aligned root transform")
	_check(spirit.ground_ring.transform==ring_transform and spirit.ground_shadow.transform==shadow_transform,"Ground marker and shadow do not rock or bounce with the character")
	for _frame in range(120):
		spirit.advance_motion(Vector3.ZERO,1.0/60.0,false)
	_check(spirit.motion_blend==0.0,"Walking fully settles after movement stops")
	_check(spirit.upper_body.position==Vector3.ZERO and absf(spirit.upper_body.rotation.z)<=0.018,"Idle has a slight bounded lean without perpetual bobbing")
	_check(is_equal_approx(spirit.feet[0].position.y,spirit.feet[1].position.y) and is_equal_approx(spirit.feet[0].position.z,spirit.feet[1].position.z),"Both feet settle level at idle")
	_check(spirit.upper_body.scale==Vector3.ONE,"Walking squash settles at rest")
	var phase := spirit.stride_phase
	spirit.advance_motion(Vector3(0,0.12,0),1.0/30.0,false)
	_check(spirit.stride_phase==phase and spirit.motion_blend==0.0,"Riding a vertical lift does not trigger walking")
	spirit.free()

func _test_render_rates_and_direction() -> void:
	var phases: Array[float]=[]
	for rate in [30,60,120]:
		var spirit := Spirit.new()
		root.add_child(spirit)
		for _frame in range(rate):
			spirit.advance_motion(Vector3(2.4/float(rate),0,0),1.0/float(rate),false)
		phases.append(spirit.stride_phase)
		_check(absf(angle_difference(spirit.facing.rotation.y,PI/2.0))<0.01,"Spirit faces its travel direction at %dfps" % rate)
		spirit.free()
	_check(absf(angle_difference(phases[0],phases[1]))<0.001 and absf(angle_difference(phases[1],phases[2]))<0.001,"Equal travelled distance produces equal stride phase across rendering rates")
	var spirit := Spirit.new()
	root.add_child(spirit)
	for _frame in range(60):
		spirit.advance_motion(Vector3(0.04,0,0),1.0/60.0,false)
	var previous := spirit.facing.rotation.y
	spirit.advance_motion(Vector3(-0.04,0,0),1.0/60.0,false)
	_check(absf(angle_difference(previous,spirit.facing.rotation.y))<PI/2.0,"A reversal turns smoothly rather than snapping by180 degrees")
	for _frame in range(60):
		spirit.advance_motion(Vector3(-0.04,0,0),1.0/60.0,false)
	_check(absf(angle_difference(spirit.facing.rotation.y,-PI/2.0))<0.01,"Turning completes toward the new direction")
	spirit.free()

func _test_reduced_motion_and_reset() -> void:
	var spirit := Spirit.new()
	root.add_child(spirit)
	for _frame in range(20):
		spirit.advance_motion(Vector3(0.04,0,0),1.0/60.0,false)
	spirit.advance_motion(Vector3(0.04,0,0),1.0/60.0,true)
	_check(spirit.motion_blend==0.0 and spirit.upper_body.position==Vector3.ZERO and spirit.upper_body.rotation==Vector3.ZERO,"Reduced motion removes body bounce and sway immediately")
	_check(spirit.feet[0].rotation==Vector3.ZERO and spirit.feet[1].rotation==Vector3.ZERO and spirit.upper_body.scale==Vector3.ONE,"Reduced motion removes foot oscillation and squash")
	var phase := spirit.stride_phase
	for _frame in range(60):
		spirit.advance_motion(Vector3(0.04,0,0),1.0/60.0,true)
	_check(spirit.stride_phase==phase and absf(angle_difference(spirit.facing.rotation.y,PI/2.0))<0.01,"Reduced motion keeps directional readability without advancing gait")
	spirit.reset_motion()
	_check(spirit.stride_phase==0.0 and spirit.motion_blend==0.0 and spirit.facing.rotation==Vector3.ZERO,"Replay resets clear gait and facing history")
	spirit.advance_motion(Vector3(1,0,0),0.0,false)
	_check(spirit.stride_phase==0.0 and spirit.motion_blend==0.0,"Zero-time presentation cannot generate movement or invalid values")
	spirit.free()

func _test_throw_and_head_carry() -> void:
	var spirit := Spirit.new()
	root.add_child(spirit)
	spirit.carrying_seed=true
	var root_transform := spirit.transform
	var highest_hop := 0.0
	var lowest_scale := 1.0
	var clear := true
	spirit.play_throw()
	for frame in range(40):
		spirit.advance_motion(Vector3.ZERO,1.0/60.0,false)
		highest_hop=maxf(highest_hop,spirit.upper_body.position.y)
		lowest_scale=minf(lowest_scale,spirit.upper_body.scale.y)
		var head: MeshInstance3D=spirit.upper_body.get_node("Head")
		var head_top := spirit.upper_body.position.y+(head.position.y+(head.mesh as SphereMesh).radius*head.scale.y)*spirit.upper_body.scale.y
		clear=clear and spirit.carry_anchor_position().y-0.13>head_top
		clear=clear and spirit.photo_anchor_height()>spirit.carry_anchor_position().y+0.18
	_check(highest_hop>0.25 and lowest_scale<0.85,"Throw compresses then springs higher than the walk hop")
	_check(clear,"Head-carried seed and photo anchor stay separated throughout the throw")
	_check(spirit.transform==root_transform,"Throw bounce cannot move the gameplay root")
	_check(spirit.upper_body.position==Vector3.ZERO and spirit.upper_body.scale==Vector3.ONE,"Throw returns exactly to the idle silhouette")
	spirit.play_throw()
	spirit.advance_motion(Vector3.ZERO,0.2,true)
	_check(spirit.upper_body.position==Vector3.ZERO and spirit.upper_body.scale==Vector3.ONE,"Reduced motion suppresses the larger throw bounce")
	spirit.reset_motion()
	spirit.advance_motion(Vector3.ZERO,0.01,false)
	_check(spirit.throw_age==Spirit.THROW_DURATION and spirit.upper_body.position==Vector3.ZERO,"Replay seeks cannot leave a throw animation running")
	spirit.free()

func _test_saved_ghost_integration() -> void:
	var definition: Dictionary=Levels.get_level("first-light")
	var first: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json"))
	var second: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-b.json"))
	var original_first := JSON.stringify(first)
	var original_second := JSON.stringify(second)
	var simulation := Simulation.new()
	_check(simulation.reset(definition,first,"b"),"Animation integration uses a validated saved first-player recording")
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	world.home_view=false
	world.load_level(definition)
	world.present(simulation.snapshot(),true)
	var strongest_motion := {"a":0.0,"b":0.0}
	var untouched := true
	for input: Dictionary in Simulation.expand_recording_inputs(second):
		var state := simulation.step(input)
		var before := JSON.stringify(state)
		world.present(state)
		for _frame in range(2):
			world._process(1.0/60.0)
			for role in ["a","b"]:
				strongest_motion[role]=maxf(strongest_motion[role],world.actors[role].motion_blend)
		untouched=untouched and JSON.stringify(state)==before
	_check(strongest_motion.a>0.25,"Earlier saved ghost receives locomotion from its replayed movement")
	_check(strongest_motion.b>0.25,"Active later player receives locomotion through the same world integration")
	_check(untouched and JSON.stringify(first)==original_first and JSON.stringify(second)==original_second,"Presentation never mutates snapshots or either saved recording")
	_check(simulation.complete and simulation.state_hash()==second.final_state_hash,"Animated combined replay retains the exact deterministic puzzle outcome")
	world.present(simulation.snapshot(),true)
	_check(world.actors.a.motion_blend==0.0 and world.actors.b.motion_blend==0.0,"Immediate snapshot placement clears both actors' animation history")
	world.queue_free()
	await process_frame

func _test_expressions() -> void:
	var first := Spirit.new()
	var second := Spirit.new()
	root.add_child(first)
	root.add_child(second)
	first.set_expression_role("a")
	second.set_expression_role("b")
	first.set_partner_offset(Vector3(1,0.5,2),true)
	second.set_partner_offset(Vector3(-1,0.5,2),true)
	var left_closed := false
	var right_closed := false
	var asymmetric_blink := false
	var bounded := true
	var root_transform := first.transform
	for frame in range(360):
		first.advance_motion(Vector3.ZERO,1.0/60.0,false)
		second.advance_motion(Vector3.ZERO,1.0/60.0,false)
		left_closed=left_closed or first.eyes[0].scale.y<0.2
		right_closed=right_closed or second.eyes[0].scale.y<0.2
		asymmetric_blink=asymmetric_blink or absf(first.eyes[0].scale.y-second.eyes[0].scale.y)>0.5
		bounded=bounded and absf(first.head.rotation.z)<0.1 and absf(first.upper_body.rotation.z)<=0.018 and first.upper_body.position==Vector3.ZERO
	_check(left_closed and right_closed and asymmetric_blink,"Both spirits blink with distinct stable timing")
	_check(first.eyes[0].position.x>-0.115 and second.eyes[0].position.x<-0.115,"Eyes follow partners on opposite sides without moving either body root")
	_check(bounded and first.transform==root_transform,"Curiosity and idle lean stay subtle and leave the root stationary")
	first.set_partner_offset(Vector3.ZERO,false)
	for frame in range(120): first.advance_motion(Vector3.ZERO,1.0/60.0,false)
	_check(absf(first.eyes[0].position.x+0.115)<0.00001,"An unavailable partner releases the gaze instead of leaving stale attention")
	var phase := second.expression_phase
	second.reset_motion()
	second.set_expression_role("p1")
	_check(second.expression_phase==phase and second.face.rotation==Vector3.ZERO,"Equivalent saved roles retain their phase while seeks clear facial pose")
	first.advance_motion(Vector3.ZERO,1.0/60.0,true)
	_check(first.head.rotation==Vector3.ZERO and first.face.rotation==Vector3.ZERO and first.eyes[0].scale==Vector3.ONE and first.eyes[0].position==Vector3(-0.115,0.02,0.289),"Reduced motion immediately removes blinking, attention motion and tilt")
	first.reset_motion()
	first.carrying_seed=true
	var min_x := INF
	var max_x := -INF
	for frame in range(90):
		first.advance_motion(Vector3(0,0,0.04),1.0/60.0,false)
		var local_anchor: Vector3=first.upper_body.transform.affine_inverse()*(first.facing.transform.affine_inverse()*first.carry_anchor_position())
		min_x=minf(min_x,local_anchor.x)
		max_x=maxf(max_x,local_anchor.x)
	_check(max_x-min_x>0.03 and maxf(absf(min_x),absf(max_x))<0.03,"A carried seed wobbles gently relative to the head while walking")
	first.play_throw()
	first.advance_motion(Vector3.ZERO,Spirit.THROW_DURATION+0.08,false)
	_check(first.release_age<Spirit.RELEASE_SETTLE_DURATION and absf(first.head.rotation.z)>0.005,"An observed throw leaves a short settling head reaction after landing")
	first.reset_motion()
	_check(first.release_age==Spirit.RELEASE_SETTLE_DURATION and first.face.rotation==Vector3.ZERO,"A replay seek cancels the release reaction")
	first.free()
	second.free()

func _test_partner_lean() -> void:
	var directions := [Vector3.RIGHT,Vector3.LEFT,Vector3.BACK,Vector3.FORWARD]
	var spirits: Array[Node3D]=[]
	for direction: Vector3 in directions:
		var spirit := Spirit.new()
		root.add_child(spirit)
		spirit.set_expression_role("a")
		spirit.set_partner_offset(direction*2.0,true)
		for _frame in range(120): spirit.advance_motion(Vector3.ZERO,1.0/60.0,false)
		spirits.append(spirit)
	_check(spirits[0].upper_body.rotation.z< -0.009 and spirits[1].upper_body.rotation.z>0.009,"Partners on opposite sides produce opposite rolls toward them")
	_check(spirits[2].upper_body.rotation.x>0.009 and spirits[3].upper_body.rotation.x< -0.009,"Partners ahead and behind produce opposite pitches toward them")
	for index in range(spirits.size()):
		var spirit: Node3D=spirits[index]
		var top: Vector3=spirit.facing.basis*spirit.upper_body.basis*Vector3.UP
		_check(top.dot(directions[index])>0.009 and Vector2(spirit.upper_body.rotation.x,spirit.upper_body.rotation.z).length()<0.018,"The bounded body lean points toward the partner in world space")
	var turned: Node3D=spirits[0]
	turned.reset_motion()
	turned.facing.rotation.y=PI/2.0
	turned.facing_target=PI/2.0
	turned.set_partner_offset(Vector3.RIGHT*2.0,true)
	for _frame in range(120): turned.advance_motion(Vector3.ZERO,1.0/60.0,false)
	_check(turned.upper_body.rotation.x>0.009 and absf(turned.upper_body.rotation.z)<0.00001,"Partner direction is converted into the rotated facing pivot before leaning")
	turned.set_partner_offset(Vector3.ZERO,false)
	for _frame in range(120): turned.advance_motion(Vector3.ZERO,1.0/60.0,false)
	_check(turned.upper_body.rotation==Vector3.ZERO,"An unavailable partner settles the body to neutral instead of continuing an idle sway")
	turned.set_partner_offset(Vector3(2,0,2),true)
	for _frame in range(30): turned.advance_motion(Vector3.ZERO,1.0/60.0,false)
	turned.advance_motion(Vector3.ZERO,1.0/60.0,true)
	_check(turned.upper_body.rotation==Vector3.ZERO,"Reduced Motion removes partner-directed pitch and roll immediately")
	for spirit: Node3D in spirits: spirit.free()

func _test_reunion() -> void:
	var spirit := Spirit.new()
	root.add_child(spirit)
	var contacts := [0]
	spirit.stepped.connect(func(): contacts[0]+=1)
	spirit.set_partner_offset(Vector3(1,0,0),true)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	_check(spirit.reunion_age==Spirit.REUNION_DURATION,"Initial close placement never creates a reunion")
	spirit.set_partner_offset(Vector3(3,0,0),true)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	spirit.set_partner_offset(Vector3(1,0,0),true)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	spirit.advance_motion(Vector3.ZERO,0.12,false)
	_check(spirit.upper_body.position.y>0.07 and spirit.upper_body.position.y<0.12 and contacts[0]==0,"Approaching after separation creates one small silent reunion hop")
	for frame in range(100):
		spirit.set_partner_offset(Vector3(1.5 if frame%2==0 else 1.7,0,0),true)
		spirit.advance_motion(Vector3.ZERO,0.05,false)
	_check(spirit.reunion_age==Spirit.REUNION_DURATION,"Jitter around the near boundary cannot repeatedly retrigger a reunion")
	spirit.set_partner_offset(Vector3(3,0,0),true)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	spirit.set_partner_offset(Vector3(1,0,0),true)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	_check(spirit.reunion_age==0.0,"A new approach after separation greets the partner again")
	for encounter in range(3):
		spirit.set_partner_offset(Vector3(3,0,0),true)
		spirit.advance_motion(Vector3.ZERO,0.5,false)
		spirit.set_partner_offset(Vector3(1,0,0),true)
		spirit.advance_motion(Vector3.ZERO,0.1,false)
		_check(spirit.reunion_age==0.0,"Quick departure and return %d starts a fresh reunion without a time cooldown" % encounter)
		spirit.advance_motion(Vector3.ZERO,0.1,false)
		_check(spirit.reunion_age>0.0 and spirit.reunion_age<Spirit.REUNION_DURATION,"Remaining together advances the same hop instead of restarting it")
	spirit.reset_motion()
	spirit.set_partner_offset(Vector3(1,0,0),true)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	_check(spirit.reunion_age==Spirit.REUNION_DURATION,"Seeking into a close pair suppresses reunion history")
	spirit.set_partner_offset(Vector3(3,0,0),true)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	spirit.play_throw()
	spirit.set_partner_offset(Vector3(1,0,0),true)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	_check(spirit.reunion_age==Spirit.REUNION_DURATION,"A throw takes priority over a simultaneous reunion")
	spirit.advance_motion(Vector3.ZERO,0.1,true)
	_check(spirit.upper_body.position==Vector3.ZERO and spirit.reunion_age==Spirit.REUNION_DURATION,"Reduced motion suppresses reunion and throw reactions")
	spirit.advance_motion(Vector3.ZERO,0.5,false)
	_check(spirit.reunion_age==Spirit.REUNION_DURATION,"Restoring motion near a partner does not replay a suppressed reunion")
	spirit.free()

func _test_reunion_sparkles() -> void:
	for rate in [30,60,120]:
		var pair := [Spirit.new(),Spirit.new()]
		for index in range(2):
			var spirit: Node3D=pair[index]
			root.add_child(spirit)
			spirit.set_expression_role("a" if index==0 else "b")
			spirit.set_partner_offset(Vector3(1,0,0),true)
			spirit.advance_motion(Vector3.ZERO,1.0/float(rate),false)
			_check(not spirit.reunion_sparkles.visible,"Initial near placement is sparkle-free at %dfps" % rate)
			spirit.set_partner_offset(Vector3(3,0,0),true)
			spirit.advance_motion(Vector3.ZERO,1.0/float(rate),false)
			spirit.set_partner_offset(Vector3(1,0,0),true)
			spirit.advance_motion(Vector3.ZERO,1.0/float(rate),false)
		_check(pair[0].reunion_sparkles.visible and pair[1].reunion_sparkles.visible and pair[0].reunion_sparkle_age==0.0 and pair[1].reunion_sparkle_age==0.0,"Both spirits start sparkling together despite different expression phases at %dfps" % rate)
		_check(pair[0].reunion_sparkles.get_child_count()==6 and pair[1].reunion_sparkles.get_child_count()==6,"Reunion uses a fixed small mesh pool for both spirits")
		var bounded := true
		var shapes := []
		for spirit: Node3D in pair:
			shapes.append(spirit.reunion_sparkles.get_child(0).mesh)
		for _frame in range(ceili(Spirit.REUNION_SPARKLE_DURATION*rate)+1):
			for spirit: Node3D in pair:
				spirit.advance_motion(Vector3.ZERO,1.0/float(rate),false)
				for sparkle: MeshInstance3D in spirit.reunion_sparkles.get_children():
					bounded=bounded and Vector2(sparkle.position.x,sparkle.position.z).length()<=0.53 and sparkle.scale.x<=0.055 and sparkle.position.y+sparkle.scale.y<spirit.photo_anchor_height()
		_check(bounded,"Sparkles remain small, close to the character and below its photo at %dfps" % rate)
		_check(not pair[0].reunion_sparkles.visible and not pair[1].reunion_sparkles.visible,"Both bursts finish within the short presentation lifetime at %dfps" % rate)
		for encounter in range(3):
			for spirit: Node3D in pair:
				spirit.set_partner_offset(Vector3(3,0,0),true)
				spirit.advance_motion(Vector3.ZERO,1.0/float(rate),false)
				spirit.set_partner_offset(Vector3(1,0,0),true)
				spirit.advance_motion(Vector3.ZERO,1.0/float(rate),false)
			_check(pair[0].reunion_sparkles.visible and pair[1].reunion_sparkles.visible and pair[0].reunion_sparkle_age==0.0 and pair[1].reunion_sparkle_age==0.0 and pair[0].reunion_sparkles.get_child(0).mesh==shapes[0] and pair[1].reunion_sparkles.get_child(0).mesh==shapes[1],"Quick reunion %d restarts both bursts using the same mesh pool at %dfps" % [encounter,rate])
			for spirit: Node3D in pair:
				for _frame in range(ceili(Spirit.REUNION_SPARKLE_DURATION*rate)+1): spirit.advance_motion(Vector3.ZERO,1.0/float(rate),false)
				_check(not spirit.reunion_sparkles.visible,"The new burst finishes while the spirits remain together")
		for spirit: Node3D in pair:
			for _frame in range(rate*6): spirit.advance_motion(Vector3.ZERO,1.0/float(rate),false)
			_check(not spirit.reunion_sparkles.visible,"Standing together cannot emit another burst")
		for spirit: Node3D in pair: spirit.free()
	var spirit := Spirit.new()
	root.add_child(spirit)
	spirit.set_partner_offset(Vector3(3,0,0),true)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	spirit.set_partner_offset(Vector3(1,0,0),true)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	var age: float=spirit.reunion_sparkle_age
	var transform_before: Transform3D=spirit.reunion_sparkles.get_child(0).transform
	spirit.advance_motion(Vector3.ZERO,0.0,false)
	_check(spirit.reunion_sparkle_age==age and spirit.reunion_sparkles.get_child(0).transform==transform_before,"Paused presentation does not advance a sparkle burst")
	spirit.play_throw()
	spirit.advance_motion(Vector3.ZERO,0.02,false)
	_check(spirit.reunion_sparkles.visible and spirit.reunion_sparkle_age>age,"A following throw does not abruptly cut off existing sparkles")
	spirit.reset_motion()
	_check(not spirit.reunion_sparkles.visible and spirit.reunion_sparkle_age==Spirit.REUNION_SPARKLE_DURATION,"Replay seeking clears sparkles immediately")
	spirit.set_partner_offset(Vector3(3,0,0),true)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	spirit.set_partner_offset(Vector3(1,0,0),true)
	spirit.advance_motion(Vector3.ZERO,0.1,false)
	_check(spirit.reunion_sparkles.visible,"A new approach starts a burst after a presentation reset")
	spirit.advance_motion(Vector3.ZERO,0.01,true)
	_check(not spirit.reunion_sparkles.visible and spirit.reunion_sparkle_age==Spirit.REUNION_SPARKLE_DURATION,"Reduced Motion cancels an active sparkle burst immediately")
	spirit.advance_motion(Vector3.ZERO,0.01,false)
	_check(not spirit.reunion_sparkles.visible,"Restoring motion while close does not replay a suppressed burst")
	spirit.free()

func _test_lighthouse_carry() -> void:
	var world := LighthouseWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.home_view=false
	world.load_level(LighthouseStages.definition("missing-piece"))
	var carried := {"props":{"portable-lens":{"status":"carried","holder_slot":"p0","socket_id":"","x":40,"z":-360}}}
	var original := JSON.stringify(carried)
	world._present_props(carried,true)
	var actor: Node3D=world.actors.p0
	var lens: Node3D=world._prop_nodes["portable-lens"]
	world._process(0.05)
	_check(actor.carrying_seed and lens.position.is_equal_approx(actor.position+actor.carry_anchor_position()),"Lighthouse lenses use the shared animated head carry anchor")
	_check(actor.carry_anchor_position().y-0.25>0.87 and actor.photo_anchor_height()>actor.carry_anchor_position().y+0.25,"The larger carried lens clears the head and photo anchor")
	var offered: Dictionary=carried.duplicate(true)
	offered.props["portable-lens"].status="offered"
	offered.props["portable-lens"].holder_slot=""
	world._present_props(offered)
	_check(not actor.carrying_seed and actor.release_age==0.0 and actor.throw_age==Spirit.THROW_DURATION,"A successful lens offer settles the head without creating a throw")
	actor.advance_motion(Vector3.ZERO,0.1,false)
	var age: float=actor.release_age
	world._present_props(offered)
	_check(actor.release_age==age,"Repeated identical offer snapshots cannot restart the reaction")
	world._present_props(carried,true)
	actor.reset_motion()
	world._present_props(offered,true)
	_check(actor.release_age==Spirit.RELEASE_SETTLE_DURATION and JSON.stringify(carried)==original,"Immediate lens placement skips release animation and leaves snapshots untouched")
	world.free()

func _test_foot_contacts() -> void:
	for rate in [30,60,120]:
		var spirit := Spirit.new()
		root.add_child(spirit)
		var contacts := [0]
		spirit.stepped.connect(func(): contacts[0]+=1)
		for frame in range(rate):
			spirit.advance_motion(Vector3(2.4/float(rate),0,0),1.0/float(rate),false)
		_check(contacts[0]==5,"Foot contacts follow the same travelled distance at %dfps" % rate)
		for frame in range(rate):
			spirit.advance_motion(Vector3(0,0.01,0),1.0/float(rate),false)
		_check(contacts[0]==5,"Idle and lift travel produce no extra footsteps at %dfps" % rate)
		spirit.reset_motion()
		_check(contacts[0]==5,"Replay placement is silent")
		spirit.advance_motion(Vector3(0.42,0,0),0.2,true)
		_check(contacts[0]==6 and spirit.motion_blend==0.0,"Reduced visual motion retains quiet walking audio")
		spirit.advance_motion(Vector3(2.4,0,0),1.0,false)
		_check(contacts[0]==7,"A delayed render frame does not play a burst of old footsteps")
		spirit.free()

func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)
