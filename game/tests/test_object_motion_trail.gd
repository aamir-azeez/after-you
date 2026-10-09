extends SceneTree
const Trail = preload("res://presentation/object_motion_trail.gd")
const SeedTrail = preload("res://presentation/seed_motion_trail.gd")
const FirstWorld = preload("res://presentation/first_steps_world.gd")
const First = preload("res://core/first_steps/simulation.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PhysicalWorld = preload("res://presentation/cooperative_world.gd")
const Physical = preload("res://core/cooperative/simulation.gd")
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func fixture(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + path + ".json"))
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	world.set_process(true)
	var object := Node3D.new()
	world.add_child(object)
	var trail := Trail.new()
	trail.configure(world, object, 0.13)
	world.add_child(trail)
	trail.set_process(false)
	trail.set_quality("high")
	trail.set_motion_allowed(true)
	var lengths: Array[float] = []
	for fps in [30, 60, 120]:
		trail.reset()
		object.position = Vector3.ZERO
		trail.advance(1.0/fps,false)
		for frame in range(1,fps+1):
			# The actual object moves at 30 Hz, even when rendering faster.
			object.position.x = float(floori(float(frame)*30.0/fps)) * 0.08
			trail.advance(1.0/fps,false)
		check(trail._mesh.visible,"Moving 30 Hz object produces exposure at %d fps" % fps)
		lengths.append(trail._mesh.scale.y)
	check(absf(lengths.max()-lengths.min()) < 0.015,"Exposure duration is independent of render rate")
	var original_transform := trail._mesh.global_transform
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(500,100,30)
	trail.advance(1.0/120,false)
	check(trail._mesh.global_transform.is_equal_approx(original_transform),"Camera movement cannot move an object wake")
	for frame in range(24): trail.advance(1.0/120,false)
	check(not trail._mesh.visible,"Stationary object fades without leaving a duplicate")
	object.position.x += 0.08
	trail.advance(1.0/30,false)
	trail.set_motion_allowed(false)
	check(not trail._mesh.visible,"Held/socketed objects clear immediately")
	trail.set_motion_allowed(true)
	trail.advance(1.0/30,false)
	object.position.x += 0.08
	trail.advance(1.0/30,false)
	check(trail._mesh.visible,"Exposure returns after release and actual motion")
	trail.advance(1.0/30,true)
	check(not trail._mesh.visible,"Reduced motion removes exposure")
	trail.set_quality("low")
	object.position.x += 0.08
	trail.advance(1.0/30,false)
	check(not trail._mesh.visible,"Low graphics removes exposure")
	trail.set_quality("high")
	trail.advance(1.0/30,false)
	object.position.x += 20.0
	trail.advance(1.0/30,false)
	check(not trail._mesh.visible,"Teleport never streaks across the level")
	trail.advance(1.0/30,false)
	object.position.x += 0.08
	trail.advance(1.0/30,false)
	world.set_process(false)
	trail._process(0.0)
	check(not trail._mesh.visible,"Suspended world clears exposure before pause rendering")
	world.queue_free()
	await process_frame
	await curved_seed()
	await recorded_seed()
	await recorded_ball()
	print("OBJECT MOTION TRAIL: %d failures" % failures)
	quit(1 if failures else 0)
func curved_seed() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var object := Node3D.new()
	world.add_child(object)
	var trail := SeedTrail.new()
	trail.configure(world, object, 0.13)
	world.add_child(trail)
	trail.set_process(false)
	trail.set_quality("high")
	trail.set_motion_allowed(true)
	for frame in range(24):
		var t := float(frame) / 60.0
		object.position=Vector3(t * 2.4, 4.0 * t * (1.0-t), 0)
		trail.advance(1.0/60.0, false)
	check(trail._mesh.visible and trail._path_mesh.get_surface_count() == 1,"Curved seed exposure builds one bounded mesh")
	var middle: Vector3 = trail._points[trail._points.size()/2]
	var chord_middle: Vector3 = trail._points.front().lerp(trail._points.back(),0.5)
	check(middle.y > chord_middle.y + 0.08,"Seed history follows an arc instead of a straight velocity bar")
	var retained: Vector3 = trail._points[10]
	var transform: Transform3D = trail._mesh.global_transform
	object.position += Vector3(0.04,-0.01,0)
	trail.advance(1.0/60.0,false)
	check(trail._points[10] == retained and trail._mesh.global_transform == transform,"Turning seed cannot pivot or move the older exposure")
	for frame in range(100):
		object.position.x += 0.01
		trail.advance(1.0/120.0,false)
	check(trail._points.size() <= SeedTrail.MAX_POINTS,"Curved exposure has a fixed history budget")
	for fps in [30, 60, 120, 240]:
		trail.reset()
		for frame in range(fps):
			object.position=Vector3(float(frame) / fps * 2.4,0,0)
			trail.advance(1.0/fps,false)
		check(trail._ages.front() >= 0.35 and trail._ages.front() <= 0.401,"Seed exposure preserves time window at %d fps" % fps)
		check(trail._points.size() <= SeedTrail.MAX_POINTS,"Sample ceiling bounds geometry at %d fps" % fps)
	trail.advance(1.0/60.0,true)
	check(trail._points.is_empty() and not trail._mesh.visible,"Reduced motion removes all seed history")
	trail.set_motion_allowed(false)
	check(trail._points.is_empty(),"Catch clears the curved seed history")
	world.queue_free()
	await process_frame
func recorded_seed() -> void:
	var world := FirstWorld.new()
	root.add_child(world)
	world.set_process(false)
	var definition := Registry.definition(Registry.FIRST_STEPS)
	world.load_level(definition)
	var sim := First.new()
	var a := fixture("first_steps/a-place-to-grow-a")
	check(sim.reset(definition,"a-place-to-grow",fixture("first_steps/lift-checkpoint"),a,"b",4),"Saved seed turn still resets")
	world.present(sim.snapshot(),true)
	# 30 Hz snapshots interpolate at rendering frequency without an initial jump.
	var first: Dictionary = sim.snapshot().duplicate(true)
	first.seed.status = "flying"
	first.seed.owner = ""
	world.present(first,true)
	var start: Vector3 = world.seed.position
	var next := first.duplicate(true)
	next.seed.x += 12
	world.present(next)
	check(world.seed.position.is_equal_approx(start),"New flight snapshot does not jump the rendered seed")
	world._process(1.0/60.0)
	var halfway: Vector3 = world.seed.position
	world._process(1.0/60.0)
	check(halfway.is_equal_approx(start.lerp(world.seed.position,0.5)),"60 Hz flight advances evenly between 30 Hz snapshots")
	world.present(next)
	check(world.seed.position.is_equal_approx(start + Vector3(0.12,0,0)),"Repeated snapshot does not restart interpolation")
	var caught_state := next.duplicate(true)
	caught_state.seed.status="held"
	var receiver: String = world.actors.keys()[1]
	caught_state.seed.owner=receiver
	world.present(caught_state)
	check(world.seed.position.is_equal_approx(world.actors[receiver].position + world.actors[receiver].carry_anchor_position()) and not world._seed_trail._mesh.visible,"Catch snaps to the hand and clears exposure without interpolation delay")
	world.present(sim.snapshot(),true)
	var flight := false
	var caught := false
	for input: Dictionary in First.expand_recording_inputs(fixture("first_steps/a-place-to-grow-b")):
		var state: Dictionary = sim.step(input)
		var before := JSON.stringify(state)
		world.present(state)
		world._process(1.0/30.0)
		check(before == JSON.stringify(state),"Seed effect never modifies replay state")
		if state.seed.status == "flying": flight = flight or world._seed_trail._mesh.visible
		if state.seed.status == "held":
			caught = true
			check(not world._seed_trail._mesh.visible,"Real catch clears seed exposure")
	check(flight and caught and sim.snapshot().complete,"Retained seed recording flies, catches and completes unchanged")
	world.load_level(definition)
	check(world._motion_trails.is_empty(),"Rebuilding a seed world discards prior trails")
	world.queue_free()
	await process_frame
func recorded_ball() -> void:
	var world := PhysicalWorld.new()
	root.add_child(world)
	world.set_process(false)
	var definition := Registry.definition(Registry.ROLLING_HOME)
	world.load_level(definition)
	var sim := Physical.new()
	check(sim.reset(definition,"bring-it-home",fixture("cooperative/weight-of-a-friend-checkpoint"),fixture("cooperative/bring-it-home-a"),"b"),"Saved ball turn still resets")
	world.present(sim.snapshot(),true)
	var rolling := false
	var stopped := false
	var lifecycle_checked := false
	for input: Dictionary in Physical.expand_recording_inputs(fixture("cooperative/bring-it-home-b")):
		var state: Dictionary = sim.step(input)
		var before := JSON.stringify(state)
		world.present(state)
		world._process(1.0/30.0)
		check(before == JSON.stringify(state),"Ball effect never modifies replay state")
		for id: String in world._ball_trails:
			var trail: Node3D = world._ball_trails[id]
			rolling = rolling or world._physical_balls[id].material_override is ShaderMaterial
			if not lifecycle_checked and world._physical_balls[id].material_override is ShaderMaterial:
				var ball: MeshInstance3D = world._physical_balls[id]
				var original: Material = world._ball_materials[id]
				var material := ball.material_override as ShaderMaterial
				check(not trail._band.visible and float(material.get_shader_parameter("exposure_angle")) > 0.0,"Moving ball exposes its stripe around the spin axis")
				check(material.get_shader_parameter("ball_color") == trail.tint,"Rotational blur preserves owner tint")
				trail._process(0.0)
				check(ball.material_override == original and trail._band.visible,"Pause restores original material and sharp physical band")
				trail.set_quality("low")
				trail.advance(1.0/30.0,false)
				check(ball.material_override == original and trail._band.visible,"Low graphics restores original ball appearance")
				trail.set_quality("high")
				trail.advance(1.0/30.0,true)
				check(ball.material_override == original and trail._band.visible,"Reduced motion restores original ball appearance")
				lifecycle_checked = true
			if state.props[id].status == "fitted":
				stopped = true
				check(world._physical_balls[id].material_override is StandardMaterial3D and trail._band.visible,"Fitted ball restores its sharp stripe")
	check(rolling and stopped and lifecycle_checked and sim.snapshot().complete,"Retained ball recording rolls and completes unchanged")
	world.queue_free()
	await process_frame
