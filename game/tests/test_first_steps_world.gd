extends SceneTree
const Registry = preload("res://services/chapter_registry.gd")
const Simulation = preload("res://core/first_steps/simulation.gd")
const World = preload("res://presentation/first_steps_world.gd")
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var capture_dir := ""
var world: Node3D
var level := Registry.definition(Registry.FIRST_STEPS)

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir=arg.trim_prefix("--capture-dir=")
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _record(index: int, role: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_steps/" + ["a-little-lift", "a-place-to-grow"][index] + "-" + role + ".json"))

func _capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var path := capture_dir.path_join(name+".png")
	if FileAccess.file_exists(path):
		_check(false,"Refuse to overwrite an earlier capture")
		return
	_check(root.get_texture().get_image().save_png(path)==OK,"Capture actual Compatibility renderer frame")

func _run() -> void:
	world = World.new()
	root.add_child(world)
	world.reduced_motion = true
	world.load_level(level)
	world.set_process(false)
	var initial := Registry.initial_checkpoint(Registry.FIRST_STEPS)
	var sim := Simulation.new()
	_check(sim.reset(level,level.stages[0].id,initial),"Actual first stage resets")
	world.show_stage(level.stages[0])
	world.present(sim.snapshot(),true)
	_check(not world.landing_marker.visible,"Platform stage does not falsely show a seed-throw target")
	_check(is_equal_approx(world.island_visuals.shore.position.y,0) and is_equal_approx(world.island_visuals.loft.position.y,1.6),"Floors use exact authored walking heights")
	_check(world.garden_state=="closed" and world.seed.visible and world.seed.position.y>1.6,"Seed stays on upper pedestal and garden starts closed")
	await _capture("first-steps-initial")
	var a := _record(0,"a")
	for input: Dictionary in Simulation.expand_recording_inputs(a): sim.step(input)
	world.present(sim.snapshot(),true)
	_check(sim.can_commit() and not sim.snapshot().outcome.threw_seed,"Source supplies power without inventing a throw")
	await _capture("first-steps-power")
	_check(sim.reset(level,level.stages[0].id,initial,a,"b"),"Receiver replays actual supplied power")
	var captured_midride := false
	for input: Dictionary in Simulation.expand_recording_inputs(_record(0,"b")):
		var state := sim.step(input)
		world.present(state,true)
		if not captured_midride and state.mechanisms.lift.phase=="rising" and state.mechanisms.lift.height_cm>=80:
			captured_midride=true
			_check(is_equal_approx(world.lift.position.y,float(state.mechanisms.lift.height_cm)/100.0),"Moving deck uses verified lift height")
			_check(is_equal_approx(world.actors.p1.position.y,world.lift.position.y),"Receiver visibly rides the real deck at the same height")
			await _capture("first-steps-midride")
	_check(captured_midride and sim.complete,"Actual receiver boarded and completed upper goal")
	_check(not world.bell_ring.visible and world.seed.visible and world.garden_state=="closed","Bell opens loft without blooming garden or consuming seed")
	await _capture("first-steps-loft-open")
	var derived := Simulation.derive_checkpoint(level,initial,a,_record(0,"b"))
	_check(derived.valid,"Full exact pair checkpoint is verified")
	var midpoint: Dictionary = derived.checkpoint
	_check(sim.reset(level,level.stages[1].id,midpoint,{},"a"),"Second stage starts from actual earlier endpoints")
	world.show_stage(level.stages[1])
	world.present(sim.snapshot(),true)
	_check(world.landing_marker.visible and is_equal_approx(world.landing_marker.position.y,0),"Second-stage lower landing is visible only at its exact surface")
	_check(is_equal_approx(world.actors.p1.position.y,1.6) and is_equal_approx(world.actors.p0.position.y,0),"Midpoint preserves physical player heights")
	await _capture("first-steps-swap")
	a=_record(1,"a")
	for input: Dictionary in Simulation.expand_recording_inputs(a): sim.step(input)
	world.present(sim.snapshot(),true)
	_check(sim.can_commit() and world.garden_state=="ready" and not world.bloomed,"Actual upper control opens garden leaves before completion")
	await _capture("first-steps-garden-ready")
	_check(sim.reset(level,level.stages[1].id,midpoint,a,"b"),"Final receiver uses exact seed/control source")
	for input: Dictionary in Simulation.expand_recording_inputs(_record(1,"b")): sim.step(input)
	world.present(sim.snapshot(),true)
	_check(sim.complete and world.bloomed and world.garden_state=="completed","Actual final planting blooms garden")
	await _capture("first-steps-bloom")
	world.queue_free()
	await process_frame
	await _chooser()
	print("First Steps world and chooser: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _chooser() -> void:
	var app := Main.new()
	var path := "user://first-steps-chooser-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	app.saves=Save.new(path)
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app._show_journey()
	await process_frame
	var buttons := _buttons(app.overlay)
	_check(buttons.has("Start First Steps") and buttons.has("First Steps with a friend"),"First Steps is the primary solo/together start")
	_check(buttons.has("Sleeping Lighthouse · Solo · Full Journey"),"Lighthouse remains nearby, explicitly solo and marked as Full Journey")
	_check(buttons.has("Earlier islands") and not buttons.has("01  First Light"),"Old easy grid is secondary instead of pretending the intro is merely another preview")
	for button: Button in buttons.values():
		if button.is_visible_in_tree(): _check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(button.get_global_rect()),"Primary chooser control fits the actual viewport")
	await _capture("first-steps-chapter-chooser")
	var before := Canonical.digest(app.saves.data)
	buttons["Earlier islands"].pressed.emit()
	await process_frame
	_check(_buttons(app.overlay).has("01  First Light"),"Original island access survives through the explicit secondary route")
	_check(Canonical.digest(app.saves.data)==before,"Choosing earlier islands does not migrate or alter old saves")
	await _capture("first-steps-earlier-islands")
	app.queue_free()
	await process_frame
	await process_frame
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)

func _buttons(node: Node) -> Dictionary:
	var found: Dictionary = {}
	if node is Button: found[node.text]=node
	for child: Node in node.get_children(): found.merge(_buttons(child))
	return found
