extends SceneTree
## Private rendering gate before chapter registry/admission integration.
## All poses and routes below come from real native input playback.
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Witness = preload("res://tests/journey_witness.gd")
const Walk = preload("res://tests/cooperative_witness.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const ConservatoryWorld = preload("res://presentation/conservatory_world.gd")
const HomeWorld = preload("res://presentation/long_way_home_world.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
var checks := 0
var failures := 0
var output := ""
var dimensions := Vector2i(1280,720)
var captures: Array = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): output = argument.trim_prefix("--capture-dir=")
		if argument == "--small": dimensions = Vector2i(960,540)
	_run.call_deferred()

func _run() -> void:
	root.size = dimensions
	root.content_scale_size = Vector2i(1280,720)
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	for key: String in ["conservatory","long-way-home"]:
		var definition := Catalog.definition(key)
		var initial := Catalog.initial_checkpoint(definition)
		for index in range(2):
			var stage: Dictionary = definition.stages[index]
			var previous := initial if index == 0 else _fixture(definition.stages[0].id+"-checkpoint")
			for role: String in ["a","b"]:
				await _play(definition,stage,previous,role,_fixture(stage.id+"-a"),_fixture(stage.id+"-"+role),"")
		if key == "long-way-home":
			var previous := _fixture(definition.stages[0].id+"-checkpoint")
			var stage: Dictionary = definition.stages[1]
			var a := Witness.source(definition,stage.id,previous,"garden")
			var b := Witness.receiver(definition,stage.id,previous,a.export_recording(),"garden")
			_check(a.can_commit() and b.complete,"The alternate welcome uses real accepted inputs")
			await _play(definition,stage,previous,"a",a.export_recording(),a.export_recording(),"-garden")
			await _play(definition,stage,previous,"b",a.export_recording(),b.export_recording(),"-garden")
		else:
			await _wrong_mirror(definition,initial)
			var previous := _fixture(definition.stages[0].id+"-checkpoint")
			var stage: Dictionary = definition.stages[1]
			var a := Witness.source(definition,stage.id,previous,"near",false,64)
			var b := Witness.receiver(definition,stage.id,previous,a.export_recording())
			_check(a.can_commit() and b.complete,"Off-centre garden source can complete beside the partner")
			await _play(definition,stage,previous,"b",a.export_recording(),b.export_recording(),"-off-centre")
	if not output.is_empty():
		var receipt := FileAccess.open(output.path_join("journey-world-%dx%d.json"%[dimensions.x,dimensions.y]),FileAccess.WRITE)
		receipt.store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures,"admission_scope":"native simulation and shared controls; registry not integrated"},"\t")+"\n")
		receipt.close()
	print("JOURNEY WORLD: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _make_view(definition: Dictionary, previous: Dictionary, stage: Dictionary) -> Dictionary:
	var world = ConservatoryWorld.new() if definition.id == "conservatory" else HomeWorld.new()
	root.add_child(world)
	world.reduced_motion = true
	world.load_level(definition)
	world.show_stage(stage)
	world.present_history(previous)
	world.set_process(false)
	var controls := Controls.new()
	controls.settings = {"sound":false,"haptics":false,"reduced_motion":true,"assistance":true}
	root.add_child(controls)
	controls.show_play()
	return {"world":world,"controls":controls}

func _play(definition: Dictionary, stage: Dictionary, previous: Dictionary, role: String, prior: Dictionary, record: Dictionary, suffix: String) -> void:
	var sim := Simulation.new()
	_check(sim.reset(definition,stage.id,previous,prior if role == "b" else {},role),"Native chapter opens before presentation")
	if not sim.error.is_empty(): return
	var view := _make_view(definition,previous,stage)
	var before := Canonical.digest(definition)
	var seen: Dictionary = {}
	await _capture(view,sim,stage,stage.id+"-"+role+suffix+"-start")
	for frame: Dictionary in Simulation.expand_recording_inputs(record):
		sim.step(frame)
		var state := sim.snapshot()
		var player: Dictionary = state.players[state.active_slot]
		var moment := ""
		if int(player.height) in range(68,112): moment = "stairs"
		if "drop" in state.get("events",[]): moment = "hatch-landing"
		for event: String in state.get("events",[]):
			if event.begins_with("selector:"): moment = "turn-"+event.trim_prefix("selector:")
		if "selector:return-selector" in state.get("events",[]): moment = "return-switch"
		if "lever" in state.get("events",[]) and state.levers.get("return-shutter",false): moment = "return-shutter"
		if "lever" in state.get("events",[]) and state.levers.get("porch-shutter",false): moment = "porch-shutter"
		if stage.id == "a-place-beside-you" and player.surface_id == "garden-walk": moment = "garden-walk"
		if not moment.is_empty() and not seen.has(moment):
			seen[moment] = true
			await _capture(view,sim,stage,stage.id+"-"+role+suffix+"-"+moment)
	_check(sim.can_commit(),"Visual input playback remains committable: "+stage.id+"/"+role+suffix)
	_check(Canonical.digest(definition) == before and Canonical.digest(view.world.chapter_definition) == before,"Presentation does not mutate native authored state")
	await _capture(view,sim,stage,stage.id+"-"+role+suffix+"-finished")
	if role == "b" and stage.id == "a-place-beside-you":
		_check(view.world._greeting_window.pane.get_meta("lit",false) and view.world._arrival_window.pane.get_meta("lit",false),"Both complementary house windows are lit in each accepted ending")
		_check(sim.snapshot().players.p0.surface_id == "home-room" and sim.snapshot().players.p1.surface_id == "home-room","The visual reunion uses both real carried home poses")
		_check(view.world.garden_state == "completed","Immediate/reduced motion shows the lasting full garden")
	if definition.id == "conservatory":
		for beam: Node3D in view.world._beam_roots:
			if beam.visible: _check(is_equal_approx(beam.position.y,2.4),"Rendered rays share the true common optical plane")
		for control: Dictionary in stage.controls:
			_check(is_equal_approx(view.world._journey_handles[control.id].position.y,float(control.height_cm)/100.0+0.54),"Mirror handles remain reachable at the authored floor")
	_destroy(view)
	await process_frame

func _wrong_mirror(definition: Dictionary, initial: Dictionary) -> void:
	var sim := Simulation.new()
	sim.reset(definition,definition.stages[0].id,initial)
	Walk.walk(sim,[-416,128]); Walk.tap(sim)
	Walk.walk(sim,[-416,-352]); Walk.tap(sim)
	Walk.walk(sim,[-224,-352]); Walk.tap(sim)
	_check(not sim.can_commit() and not sim.snapshot().optics.signals.get("high-light",false),"Turning the already-correct third bend visibly loses the stair signal")
	var view := _make_view(definition,initial,definition.stages[0])
	await _capture(view,sim,definition.stages[0],"a-light-above-wrong-third-mirror")
	_destroy(view)
	await process_frame

func _capture(view: Dictionary, sim: RefCounted, stage: Dictionary, name: String) -> void:
	var state: Dictionary = sim.snapshot()
	var visual := state.duplicate(true)
	visual["message"] = "Your turn is ready." if sim.role == "a" and sim.can_commit() else stage.hint_a if sim.role == "a" else stage.hint_b
	visual["duration_ticks"] = 900
	view.world.present(state,true)
	for slot: String in state.players:
		var player: Dictionary = state.players[slot]
		var actual := Vector3(float(player.x)/100,float(player.height)/100,float(player.z)/100)
		var shown: Vector3 = view.world.actors[slot].position
		_check(shown.distance_to(actual)<=0.581 if state.complete else shown.is_equal_approx(actual),"Live and replay poses stay exact; only completed reunion can use a bounded visual separation")
	view.controls.update_state(str(stage.title),float(900-sim.tick)/30.0,visual,true)
	if sim.complete: view.controls.show_moment("continue")
	for frame in range(12): await process_frame
	_check(not view.controls.overlay.visible,"Shared chapter HUD remains unobstructed during capture")
	if output.is_empty(): return
	await RenderingServer.frame_post_draw
	var filename := name+"-%dx%d.png"%[dimensions.x,dimensions.y]
	_check(root.get_texture().get_image().save_png(output.path_join(filename)) == OK,"Save native-driven chapter image")
	var visual_players: Dictionary = {}
	for slot: String in state.players:
		var shown: Vector3 = view.world.actors[slot].position
		visual_players[slot] = [shown.x,shown.y,shown.z]
	captures.append({"file":filename,"stage":state.stage_id,"role":sim.role,"tick":state.tick,"players":state.players,"visual_players_metres":visual_players,"controls":state.controls,"signals":state.optics.signals,"complete":state.complete,"can_commit":state.can_commit})

func _destroy(view: Dictionary) -> void:
	root.remove_child(view.controls)
	view.controls.free()
	root.remove_child(view.world)
	view.world.free()

func _fixture(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/journey/"+name+".json"))
	return parsed if parsed is Dictionary else {}

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
