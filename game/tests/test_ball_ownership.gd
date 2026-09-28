extends SceneTree

const World = preload("res://presentation/island_world.gd")
const Levels = preload("res://core/levels.gd")
const Simulation = preload("res://core/simulation.gd")
const Physical = preload("res://core/cooperative/simulation.gd")
const PhysicalCatalog = preload("res://core/cooperative/stage_catalog.gd")
const PhysicalWorld = preload("res://presentation/cooperative_world.gd")
const Relay = preload("res://core/v2/simulation_v2.gd")
const RelayCatalog = preload("res://core/v2/stage_catalog.gd")
const Preview = preload("res://relay_preview.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
const Registry = preload("res://services/chapter_registry.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _ownership_colors()
	await _physical_colors()
	await _extended_hud()
	print("BALL OWNERSHIP: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _fixture(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/"+path))

func _ownership_colors() -> void:
	var world := World.new()
	root.add_child(world)
	world.load_level(Levels.get_level(0))
	var first := _fixture("first-light-a.json")
	var second := _fixture("first-light-b.json")
	var simulation := Simulation.new()
	_check(simulation.reset(Levels.get_level(0),first,"b",int(second.simulation_version)),"Native saved pair establishes real seed ownership")
	var seen: Dictionary = {}
	for input: Dictionary in Simulation.expand_recording_inputs(second):
		var state: Dictionary = simulation.step(input)
		var status := str(state.seed.status)
		if seen.has(status): continue
		seen[status] = true
		var before := JSON.stringify(state)
		world.present(state,true)
		var expected: Color = World.GOLD if status == "held_a" else World.TEAL if status == "held_b" else World.CREAM
		var material := world.seed.material_override as StandardMaterial3D
		_check(material.albedo_color == expected and material.emission == expected,"Seed tint follows native ownership: "+status)
		_check(JSON.stringify(state)==before,"Seed presentation leaves native snapshot unchanged")
	_check(seen.has("held_a") and seen.has("flying") and seen.has("held_b"),"Color checks include source, free flight and actual catch")
	world.queue_free()
	await process_frame

func _comfort_fixture() -> Dictionary:
	var path := "res://tests/fixtures/comfort8/recordings.json"
	_check(FileAccess.file_exists(path), "Use the separately verified native8 recording/contact fixture")
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(value is Dictionary and value.has("controller_states") and value.has("old6_contact"), "Native fixture includes both comfort and retained contact states")
	return value if value is Dictionary else {}

func _physical_states() -> Dictionary:
	var fixture := _comfort_fixture()
	if fixture.is_empty(): return {}
	var states: Dictionary = fixture.controller_states.duplicate(true)
	states["old6_contact"] = fixture.old6_contact.duplicate(true)
	var level := PhysicalCatalog.definition("rolling-home")
	var checkpoint: Dictionary = fixture["rolling-home"].checkpoints[1]
	var pair: Dictionary = fixture["rolling-home"].pairs[1]
	var source := Physical.new()
	_check(source.reset(level, "bring-it-home", checkpoint, {}, "a", 8), "Real source recording supplies an offered neutral state")
	for input: Dictionary in Physical.expand_recording_inputs(pair.a):
		var state: Dictionary = source.step(input)
		if state.props["round-ball"].status == "offered" and not states.has("offered"):
			states["offered"] = state
	_check(source.state_hash() == pair.a.final_state_hash, "Offered presentation state comes from the exact verified source route")
	var receiver := Physical.new()
	_check(receiver.reset(level, "bring-it-home", checkpoint, pair.a, "b", 8), "Real receiver recording supplies fitted neutral state")
	for input: Dictionary in Physical.expand_recording_inputs(pair.b): receiver.step(input)
	_check(receiver.complete and receiver.state_hash() == pair.b.final_state_hash, "Receiver display is the exact successful native route")
	states["fitted"] = receiver.snapshot()
	return states

func _physical_colors() -> void:
	var states := _physical_states()
	if states.is_empty(): return
	var world := PhysicalWorld.new()
	root.add_child(world)
	world.load_level(PhysicalCatalog.definition("rolling-home"))
	var expected_slots := {"a_contact":"p0", "a_away":"", "p1_contact":"p1", "b_contact":"p0", "b_away":"", "b_recontact":"p0", "old6_contact":"p0", "offered":"", "fitted":""}
	for name: String in expected_slots:
		_check(states.has(name), "Actual input trace contains " + name)
		if not states.has(name): continue
		var state: Dictionary = states[name]
		var before := JSON.stringify(state)
		var slot: String = expected_slots[name]
		_check(state.props["round-ball"].get("controller_slot", "") == slot, "Native contact cue matches recorded role/position: " + name)
		world.present(state, true)
		var color: Color = World.GOLD if slot == "p0" else World.TEAL if slot == "p1" else World.CREAM
		var ball_material := world._physical_balls["round-ball"].material_override as StandardMaterial3D
		_check(ball_material.albedo_color == color, "Ball material follows actual controller, not viewer or claim: " + name)
		_check(JSON.stringify(state) == before, "Ball presentation changes no native state or proof fields: " + name)
	world.queue_free()
	await process_frame

func _relay_display_states() -> Dictionary:
	var fixture := _comfort_fixture()
	if fixture.is_empty(): return {}
	var level := RelayCatalog.relay_isles()
	var checkpoint := RelayCatalog.initial_checkpoint(level)
	var result: Dictionary = {}
	var source := Relay.new()
	_check(source.reset(level, "relay", checkpoint, {}, "a", 8), "Hold meter uses actual comfort source input")
	for input: Dictionary in Relay.expand_recording_inputs(fixture.relay.a):
		var state: Dictionary = source.step(input)
		var objective: Dictionary = state.get("objective_display", {})
		if not result.has("hold") and float(objective.get("current", 0.0)) >= 0.2:
			result["hold"] = state
	var receiver := Relay.new()
	_check(receiver.reset(level, "relay", checkpoint, fixture.relay.a, "b", 8), "Extended HUD uses accepted native source and actual receiver input")
	for input: Dictionary in Relay.expand_recording_inputs(fixture.relay.b):
		var state: Dictionary = receiver.step(input)
		if receiver.tick == 610: result["extra_time"] = state
	_check(result.has("hold") and result.has("extra_time"), "Capture contains measured hold and B beyond the old deadline")
	return result

func _extended_hud() -> void:
	var states := _relay_display_states()
	if not states.has("hold") or not states.has("extra_time"): return
	var controls := Controls.new()
	root.add_child(controls)
	controls.show_play()
	var preview := Preview.new()
	preview.controls = controls
	preview.chapter_key = Registry.RELAY
	preview.chapter = Registry.descriptor(Registry.RELAY)
	preview.checkpoint = RelayCatalog.initial_checkpoint(RelayCatalog.relay_isles())
	preview.mode = "play"
	for name: String in ["hold", "extra_time"]:
		var state: Dictionary = states[name]
		preview.role = str(state.role)
		preview._update_hud(state)
		await process_frame
		if name == "hold":
			_check(controls.objective_panel.visible and controls.objective_panel.bar.value > 0.0 and not controls.objective_panel.value_label.text.is_empty(), "Production ChapterControls shows actual earned hold capacity")
		else:
			_check(int(state.tick) > 600 and int(state.duration_ticks) == 900 and not state.complete, "Actual native B remains live after the former deadline")
			_check(controls.timer_label.text == "9.7" and controls.turn_progress.max_value == 30.0 and controls.turn_progress.value > 20.0, "Production preview HUD uses the new duration rather than clamping at the old timer")
	preview.free()
	controls.queue_free()
	await process_frame

func _check(okay: bool, label: String) -> void:
	checks+=1
	if not okay:
		failures+=1
		push_error(label)
