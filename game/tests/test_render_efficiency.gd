extends SceneTree

const Catalog = preload("res://core/journey/stage_catalog.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const World = preload("res://presentation/conservatory_world.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var definition := Catalog.definition("conservatory")
	var simulation := Simulation.new()
	_check(simulation.reset(definition,definition.stages[0].id,Catalog.initial_checkpoint(definition)),"Benchmark uses a native chapter snapshot")
	var state: Dictionary = simulation.snapshot()
	var before := Canonical.digest(state)
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	world.load_level(definition)
	world.present(state,true)
	var samples: Array[int] = []
	for trial in range(7):
		var started := Time.get_ticks_usec()
		for iteration in range(300): world.present(state)
		samples.append(Time.get_ticks_usec()-started)
	samples.sort()
	print("RENDER BENCHMARK: median %dus / 300 unchanged snapshots" % samples[3])
	_check(Canonical.digest(state)==before,"Presentation adapters leave the complete native snapshot unchanged")
	var roots: Array = world._beam_roots.duplicate()
	var transforms: Array = []
	for beam: Node3D in roots: transforms.append(beam.transform)
	world.present(state)
	_check(roots==world._beam_roots,"Repeated snapshots reuse optical geometry")
	for index in range(roots.size()):
		_check(roots[index].transform==transforms[index],"Repeated snapshots retain exact optical poses")
	var segments := [{"from_cm":[0,0],"to_cm":[100,0]}]
	world._present_beams(segments)
	var beam: Node3D = world._beam_roots[0]
	var core := beam.get_child(1) as MeshInstance3D
	_check(is_equal_approx(core.mesh.size.z,1.0),"A changed endpoint updates the existing beam length")
	var geometry_changes := [0]
	core.mesh.changed.connect(func(): geometry_changes[0] += 1)
	for repeat in range(20): world._present_beams(segments)
	_check(geometry_changes[0]==0,"Unchanged segments do not resubmit mesh geometry")
	var material_changes := [0]
	core.material_override.changed.connect(func(): material_changes[0] += 1)
	for repeat in range(20): world._glow(core,world.LIGHT_COLOR,1.3)
	_check(material_changes[0]==0,"Unchanged light energy does not resend material properties")
	segments[0].to_cm[0]=200
	world._present_beams(segments)
	_check(is_equal_approx(core.mesh.size.z,2.0) and beam.get_meta("to_cm")==[200,0],"In-place source changes are detected independently of the previous snapshot")
	world._present_beams([])
	_check(not beam.visible,"Removing a segment hides its pooled geometry")
	world._present_beams(segments)
	_check(beam.visible and is_equal_approx(core.mesh.size.z,2.0),"Restoring a cached segment makes it visible at the correct length")
	world.queue_free()
	await process_frame
	print("RENDER EFFICIENCY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
