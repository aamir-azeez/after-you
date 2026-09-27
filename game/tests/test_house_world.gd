extends SceneTree
## Recorded inputs cross the actual journal, chapter UI and cutaway world.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Preview = preload("res://cooperative_preview.gd")
const World = preload("res://presentation/house_world.gd")
const Simulation = preload("res://core/cooperative/simulation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Retained = preload("res://tests/retained_chapter_fixture.gd")
var checks := 0
var failures := 0
var output := ""
var dimensions := Vector2i(1280,720)
var directory := "user://house-world-"+Crypto.new().generate_random_bytes(8).hex_encode()
var captures: Array = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): output = argument.trim_prefix("--capture-dir=")
		if argument == "--small": dimensions = Vector2i(960,540)
	_run.call_deferred()

func _run() -> void:
	root.size = dimensions
	root.content_scale_size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(directory)
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	var level := Registry.definition(Registry.HOUSE)
	for index in range(level.stages.size()):
		for role: String in ["a","b"]:
			await _stage(level,index,role)
	for filename: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	if not output.is_empty():
		var receipt := FileAccess.open(output.path_join("house-world-%dx%d.json"%[dimensions.x,dimensions.y]),FileAccess.WRITE)
		receipt.store_string(JSON.stringify({"captures":captures,"checks":checks,"failures":failures},"\t")+"\n")
		receipt.close()
	print("HOUSE WORLD: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _stage(level: Dictionary, index: int, role: String) -> void:
	var id: String = level.stages[index].id
	var path := directory.path_join(id+"-"+role+".json")
	_check(Retained.seed(path,Registry.HOUSE),"Published House6 inputs begin in a genuine retained6 envelope")
	var journal := Journey.new(path,null,Registry.HOUSE)
	journal.load_data()
	for earlier in range(index):
		for prior_role: String in ["a","b"]:
			if not journal.accept_recording(_fixture(level.stages[earlier].id+"-"+prior_role)):
				_check(false,"Earlier house proof is accepted: "+journal.last_error)
				return
	if role == "b" and not journal.accept_recording(_fixture(id+"-a")):
		_check(false,"House source is accepted before receiver: "+journal.last_error)
		return
	var screen := Preview.new()
	screen.chapter_key = Registry.HOUSE
	screen.journey = journal
	screen.settings = {"sound":false,"haptics":false,"reduced_motion":true,"assistance":true}
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.set_process(false)
	screen.world.set_process(false)
	_check(screen.world.get_script() == World and screen.mode == "ready", "Real chapter admission selects the cutaway house")
	_check(screen.world._house_windows.size() == 5, "All connected rooms have their identifiable windows")
	if index > 0:
		_check(is_instance_valid(screen.world._house_memories) and screen.world._house_memories.get_child_count() > 0, "Returning through the house retains visible earlier plate and latch marks")
	screen._begin()
	_check(screen.mode == "play", "The actual chapter controls start this recorded role")
	await _capture(screen,id+"-"+role+"-start")
	var record := _fixture(id+"-"+role)
	var observed := {}
	var definition_hash := Canonical.digest(level)
	for frame: Dictionary in Simulation.expand_recording_inputs(record):
		screen.advance_input(frame)
		var state: Dictionary = screen.sim.snapshot()
		var player: Dictionary = state.players[state.active_slot]
		if id == "open-the-house" and role == "a" and state.hold_pads.get("entry-weight",false) and not state.levers.get("workshop-lever",false) and not observed.has("entry"):
			observed.entry = true
			_check(state.bridges.get("workshop-entry",false) and not state.bridges.get("workshop-return",false), "The first weight opens only the temporary workshop entry")
			await _capture(screen,id+"-first-weight")
		if id == "open-the-house" and role == "a" and state.levers.get("workshop-lever",false) and not observed.has("lever"):
			observed.lever = true
			_check(state.bridges.get("workshop-entry",false) and state.bridges.get("workshop-return",false), "Lever makes both workshop passages visibly traversable")
			await _capture(screen,id+"-latched-doors")
		if id == "open-the-house" and role == "b" and int(player.height) >= 72 and int(player.height) <= 104 and not observed.has("stairs"):
			observed.stairs = true
			await _capture(screen,id+"-stairs")
		if id == "the-room-below" and role == "a" and "drop" in state.get("events",[]) and not observed.has("drop"):
			observed.drop = true
			_check(int(player.height) == 0 and screen.world._upper_islands[0].get_child(0).get_meta("cutaway",false), "The loft cuts away on the real hatch landing")
			await _capture(screen,id+"-hatch-landing")
		if id == "the-room-below" and role == "a" and int(state.props["house-ball"].x) >= 128 and int(state.props["house-ball"].x) <= 160 and not observed.has("bench"):
			observed.bench = true
			await _capture(screen,id+"-bench-route")
		if id == "the-room-below" and role == "b" and state.hold_pads.get("sunroom-weight",false) and not observed.has("weight"):
			observed.weight = true
			await _capture(screen,id+"-sunroom-open")
	_check(screen.sim.can_commit(), "Rendered real inputs remain committable: "+id+" "+role)
	_check(Canonical.digest(screen.sim.level) == definition_hash, "Presentation never changes the authored physical chapter")
	if id == "open-the-house":
		_check(observed.has("entry") and observed.has("lever") if role == "a" else observed.has("stairs"), "The first pair traverses its intended physical decision")
	elif role == "a":
		_check(observed.has("drop") and observed.has("bench"), "The second source uses the hatch and bench route")
	else:
		_check(observed.has("weight") and screen.sim.complete, "The final receiver leaves the ball on the weight before completing")
		var pane: MeshInstance3D = screen.world._house_windows.sunroom.pane
		_check(pane.material_override.emission_enabled and is_instance_valid(screen.world.garden) and screen.world.garden_state == "completed", "Completion opens and warms the sunroom with the settled garden")
		_check(screen.world._upper_islands[0].get_child(0).get_meta("cutaway",false), "The final view keeps the recorded partner visible beneath the loft")
	await _capture(screen,id+"-"+role+"-finished")
	root.remove_child(screen)
	screen.free()
	await process_frame

func _capture(screen: Node3D, name: String) -> void:
	if output.is_empty(): return
	var state: Dictionary = screen.sim.snapshot()
	screen.world.present(state,true)
	var resumed := 0
	for frame in range(12):
		# Desktop focus can change while an automated render settles. Exercise
		# the real Resume action instead of saving a pause card as play evidence.
		if screen.mode == "paused":
			screen._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
			for control: Node in screen.overlay.find_children("*","Button",true,false):
				if control.get_meta("action_id","") == "resume":
					control.pressed.emit()
					resumed += 1
					break
		await process_frame
	await RenderingServer.frame_post_draw
	_check(screen.mode in ["play","bloom"] and not screen.overlay.visible,"Capture shows gameplay rather than an interrupted pause card")
	var filename := name+"-%dx%d.png"%[dimensions.x,dimensions.y]
	_check(root.get_texture().get_image().save_png(output.path_join(filename)) == OK,"Save house visual evidence")
	captures.append({"file":filename,"stage":state.stage_id,"tick":state.tick,"players":state.players,"props":state.props,"complete":state.get("complete",false),"mode":screen.mode,"focus_resumes":resumed})

func _fixture(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cooperative/"+name+".json"))
	return parsed if parsed is Dictionary else {}

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
