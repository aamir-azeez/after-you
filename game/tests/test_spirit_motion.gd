extends SceneTree

const Spirit = preload("res://presentation/spirit_visual.gd")
const World = preload("res://presentation/island_world.gd")
const Simulation = preload("res://core/simulation.gd")
const Levels = preload("res://core/levels.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_walk_and_settle()
	_test_render_rates_and_direction()
	_test_reduced_motion_and_reset()
	await _test_saved_ghost_integration()
	print("AFTER YOU SPIRIT MOTION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _test_walk_and_settle() -> void:
	var spirit := Spirit.new()
	root.add_child(spirit)
	spirit.position=Vector3(3,2,1)
	var root_transform := spirit.transform
	var ring_transform := spirit.ground_ring.transform
	var shadow_transform := spirit.ground_shadow.transform
	var largest_foot_difference := 0.0
	var largest_arm_swing := 0.0
	var largest_bob := 0.0
	for _frame in range(50):
		spirit.advance_motion(Vector3(0.04,0,0),1.0/60.0,false)
		largest_foot_difference=maxf(largest_foot_difference,absf(spirit.feet[0].position.z-spirit.feet[1].position.z))
		largest_arm_swing=maxf(largest_arm_swing,absf(spirit.arms[0].rotation.x))
		largest_bob=maxf(largest_bob,spirit.upper_body.position.y)
	_check(largest_foot_difference>0.07,"Walking produces distinct alternating foot placement instead of sliding rigid feet")
	_check(largest_arm_swing>0.12,"Arms counter-swing with the gait")
	_check(largest_bob>0.01 and largest_bob<0.04,"Whole upper body has a small bounded walking bounce")
	_check(spirit.upper_body.get_node("Head").get_parent()==spirit.upper_body.get_node("Torso").get_parent(),"Head and torso share the same animated body pivot")
	_check(spirit.transform==root_transform,"Gait never changes the simulation-aligned root transform")
	_check(spirit.ground_ring.transform==ring_transform and spirit.ground_shadow.transform==shadow_transform,"Ground marker and shadow do not rock or bounce with the character")
	for _frame in range(120):
		spirit.advance_motion(Vector3.ZERO,1.0/60.0,false)
	_check(spirit.motion_blend==0.0,"Walking fully settles after movement stops")
	_check(spirit.upper_body.position==Vector3.ZERO and spirit.upper_body.rotation==Vector3.ZERO,"Idle has a stable coherent silhouette without perpetual bobbing")
	_check(is_equal_approx(spirit.feet[0].position.y,spirit.feet[1].position.y) and is_equal_approx(spirit.feet[0].position.z,spirit.feet[1].position.z),"Both feet settle level at idle")
	_check(spirit.arms[0].rotation.x==0.0 and spirit.arms[1].rotation.x==0.0,"Arm swing returns to rest")
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
	_check(spirit.feet[0].rotation==Vector3.ZERO and spirit.feet[1].rotation==Vector3.ZERO and spirit.arms[0].rotation.x==0.0,"Reduced motion removes foot and arm oscillation")
	var phase := spirit.stride_phase
	for _frame in range(60):
		spirit.advance_motion(Vector3(0.04,0,0),1.0/60.0,true)
	_check(spirit.stride_phase==phase and absf(angle_difference(spirit.facing.rotation.y,PI/2.0))<0.01,"Reduced motion keeps directional readability without advancing gait")
	spirit.reset_motion()
	_check(spirit.stride_phase==0.0 and spirit.motion_blend==0.0 and spirit.facing.rotation==Vector3.ZERO,"Replay resets clear gait and facing history")
	spirit.advance_motion(Vector3(1,0,0),0.0,false)
	_check(spirit.stride_phase==0.0 and spirit.motion_blend==0.0,"Zero-time presentation cannot generate movement or invalid values")
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

func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)
