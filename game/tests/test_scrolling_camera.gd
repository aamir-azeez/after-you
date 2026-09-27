extends SceneTree
const Registry = preload("res://services/chapter_registry.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for key: String in [Registry.ROLLING_HOME, Registry.HOUSE, Registry.CONSERVATORY, Registry.LONG_WAY_HOME]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280,720)
		root.add_child(viewport)
		var world: Node3D = Registry.world_script(key).new()
		viewport.add_child(world)
		world.set_process(false)
		world.camera_exploration.set_process(false)
		world.configure_camera_exploration(func(): return true,func(_point): return true)
		var level := Registry.definition(key)
		world.load_level(level)
		var sim: RefCounted = Registry.simulation_script(key).new()
		_check(Registry.reset_simulation(sim,key,level,str(level.stages[0].id),Registry.initial_checkpoint(key),{},"a"),"Open native initial state: "+key)
		var state: Dictionary = sim.snapshot()
		world.present(state,true)
		var resting_size: float = world.camera.size
		var resting_frame: Transform3D = world.camera.transform
		for rate in [30,60,120]:
			var largest_deviation := 0.0
			for frame in range(rate*2):
				if frame % (rate/30) == 0: world.present(state)
				world._process(1.0/rate)
				world.camera_exploration._process(1.0/rate)
				largest_deviation = maxf(largest_deviation,absf(world.camera.size-resting_size))
			_check(largest_deviation < 0.0001 and world.camera.transform.is_equal_approx(resting_frame),"Standing still stays steady at %d Hz: %s"%[rate,key])
		world.camera_exploration.zoom(0.65)
		world.camera_exploration.pan_pixels(Vector2(80,40))
		world._process(0.0)
		world.camera_exploration._process(0.0)
		var explored_frame: Transform3D = world.camera.transform
		for frame in range(180):
			world.present(state)
			world._process(1.0/60)
			world.camera_exploration._process(1.0/60)
		_check(is_equal_approx(world.camera.size,resting_size*0.65) and world.camera.transform.is_equal_approx(explored_frame),"Snapshots cannot amplify or undo exploration: "+key)
		for frame in range(180):
			world._process(1.0/60)
			world.camera_exploration._process(1.0/60)
		_check(is_equal_approx(world.camera.size,resting_size) and world.camera.transform.is_equal_approx(resting_frame),"Exploration returns without residual zoom: "+key)
		var steady_movement := true
		for tick in range(60):
			sim.step({"move_x":1.0})
			world.present(sim.snapshot())
			for frame in range(2):
				var before: Vector3 = world.camera.position
				world._process(1.0/60)
				world.camera_exploration._process(1.0/60)
				steady_movement = steady_movement and is_equal_approx(world.camera.size,resting_size) and before.distance_to(world.camera.position) < 0.4
		_check(steady_movement,"Native movement at30 Hz follows smoothly when rendered at60 Hz: "+key)
		world.present(state,true)
		var completed := state.duplicate(true)
		completed.complete = true
		world.present(completed)
		var previous: float = world.camera.size
		var monotonic := true
		for frame in range(180):
			if frame % 2 == 0: world.present(completed)
			world._process(1.0/60)
			world.camera_exploration._process(1.0/60)
			monotonic = monotonic and world.camera.size >= previous-0.0001 and world.camera.size <= 10.6001
			previous = world.camera.size
		_check(monotonic and is_equal_approx(world.camera.size,10.6),"Completion zoom settles without pulsing: "+key)
		world.reduced_motion = true
		world.present(state,true)
		world._process(1.0/60)
		_check(is_equal_approx(world.camera.size,resting_size),"Replay reset restores the normal frame with reduced motion: "+key)
		viewport.free()
		await process_frame
	print("SCROLLING CAMERA: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
