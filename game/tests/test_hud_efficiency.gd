extends SceneTree
## CPU-only HUD comparison. Native setup, assertions and layout are not timed.
const RelayPreview = preload("res://relay_preview.gd")
const LighthousePreview = preload("res://lighthouse_preview.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Light = preload("res://core/lighthouse/borrowed_light.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const TRIALS := 7
const UPDATES := 300
var checks := 0
var failures := 0
var reports: Array = []
var coverage: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,540)
	root.add_child(viewport)
	var controls := Controls.new()
	viewport.add_child(controls)
	controls.show_play()
	for key: String in [Registry.RELAY,Registry.CONSERVATORY]:
		for role: String in ["a","b"]:
			var case := _chapter_case(key,role)
			if not case.is_empty(): await _observe(case,controls,role=="a")
	var fixture := _fixture("lighthouse/first-three-v3.json")
	if fixture.get("pairs") is Array and fixture.pairs.size()==3:
		for version: int in [Light.LEGACY_SIMULATION_VERSION,Light.CURRENT_SIMULATION_VERSION]:
			var case := _sequence_case(fixture.pairs,version)
			if not case.is_empty(): await _observe(case,controls,version==Light.CURRENT_SIMULATION_VERSION)
	else: _check(false,"Three-stage native Lighthouse fixture is present")
	_check(reports.size()==6,"Both chapter roles and Lighthouse rulesets ran")
	for label: String in ["journey_hint","journey_ready","legacy_selector","cumulative_selector"]:
		_check(coverage.has(label),"Observed native HUD branch: "+label)
	var proof: Array = []
	for report: Dictionary in reports:
		proof.append({"id":report.id,"native_snapshots":report.native_snapshots,"input_sha256":report.input_sha256,
			"visible_output_sha256":report.visible_output_sha256,"replay_output_sha256":report.replay_output_sha256})
	print("HUD_EFFICIENCY_DIGEST "+Canonical.digest(proof))
	print("HUD_EFFICIENCY_BENCHMARK "+JSON.stringify({"trials":TRIALS,"updates_per_trial":UPDATES,"cases":reports}))
	viewport.queue_free()
	await process_frame
	await process_frame
	print("HUD EFFICIENCY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _chapter_case(key: String, role: String) -> Dictionary:
	var definition := Registry.definition(key)
	var stage: Dictionary = definition.stages[0]
	var prefix := "v2/relay" if key==Registry.RELAY else "journey/"+str(stage.id)
	var record := _fixture(prefix+"-"+role+".json")
	var prior := _fixture(prefix+"-a.json") if role=="b" else {}
	var checkpoint := Registry.initial_checkpoint(key)
	var engine: Script = Registry.simulation_script(key)
	var sim: RefCounted = engine.new()
	if not _check(sim.reset(definition,stage.id,checkpoint,prior,role,int(record.get("simulation_version",-1))),"Native chapter reset: "+key+" "+role): return {}
	var states := _recorded_states(sim,engine.expand_recording_inputs(record))
	if not _check(sim.error.is_empty() and sim.state_hash()==record.get("final_state_hash") and sim.can_commit(),"Native chapter input proof: "+key+" "+role): return {}
	var preview := RelayPreview.new()
	preview.chapter_key=key
	preview.chapter=Registry.descriptor(key)
	preview.definition=definition
	preview.checkpoint=checkpoint
	preview.role=role
	preview.mode="play"
	preview.settings={"sound":false,"haptics":false}
	return {"id":key+"/"+role,"screen":preview,"states":states,"kind":"chapter","key":key,"role":role}

func _sequence_case(history: Array, version: int) -> Dictionary:
	var sim := Light.new()
	if not _check(sim.reset("a",{},history,version),"Native sequence reset for rules%d" % version): return {}
	var states: Array = [sim.snapshot()]
	states.append(sim.step({"interact":true}))
	var required := sim.sequence_budget_ticks()
	while int(states[-1].sequence.first_ticks)<int(required[0]) and sim.tick<Light.MAX_TICKS:
		states.append(sim.step())
	# A real release tick separates the two selector presses.
	states.append(sim.step())
	states.append(sim.step({"interact":true}))
	while states.size()<UPDATES and not sim.finished:
		states.append(sim.step())
	if not _check(sim.error.is_empty() and sim.can_commit() and states[-1].sequence.phase=="second","Native sequence reaches a viable second path without injected state"): return {}
	return _light_case("lighthouse/sequence/rules%d" % version,states,3,"a")

func _light_case(id: String, states: Array, index: int, role: String) -> Dictionary:
	var preview := LighthousePreview.new()
	preview.stage=LightCatalog.definition(LightCatalog.STAGE_IDS[index])
	preview.checkpoint={"stage_index":index}
	preview.role=role
	preview.mode="play"
	preview.settings={"sound":false,"haptics":false}
	return {"id":id,"screen":preview,"states":states,"kind":"lighthouse","role":role}

func _recorded_states(sim: RefCounted, inputs: Array) -> Array:
	var states: Array = [sim.snapshot()]
	var stride := maxi(1,ceili(float(inputs.size())/float(UPDATES-1)))
	for index in range(inputs.size()):
		var state: Dictionary = sim.step(inputs[index])
		if (index+1)%stride==0 or index==inputs.size()-1: states.append(state)
	return states

func _observe(case: Dictionary, controls: CanvasLayer, benchmark: bool) -> void:
	var screen: Node3D = case.screen
	var states: Array = case.states
	screen.controls=controls
	var input_hash := Canonical.digest(states)
	_check(states.size()>1 and int(states[0].tick)<int(states[-1].tick),case.id+" uses changing native snapshots")
	var outputs: Array = []
	for state: Dictionary in states:
		screen._update_hud(state)
		_check_visible(case,state,controls)
		outputs.append(_visible(controls))
	_check(Canonical.digest(states)==input_hash,case.id+" leaves every nested native snapshot unchanged")
	# Exercise replay visibility through the same owner without starting replay.
	screen.mode="replay"
	screen._update_hud(states[-1])
	var replay_output := _visible(controls)
	_check("Replay" in controls.chapter_label.text and not controls.action_button.visible and not controls.finish_button.visible and not controls.stick.visible,case.id+" replay displays no live input controls")
	screen.mode="play"
	screen._update_hud(states[-1])
	await process_frame
	await process_frame
	await process_frame
	_check(controls.chapter_label.is_visible_in_tree(),case.id+" uses actual visible ChapterControls")
	if controls.objective_panel.visible:
		_check(controls.get_viewport().get_visible_rect().encloses(controls.objective_panel.get_global_rect()),case.id+" objective fits the compact viewport after layout")
	var samples: Array[int] = []
	if benchmark:
		# Warm and flush layout before timing. No digest, simulation or file I/O
		# occurs inside the measured production _update_hud loop.
		for index in range(UPDATES): screen._update_hud(states[index%states.size()])
		await process_frame
		for trial in range(TRIALS):
			var started := Time.get_ticks_usec()
			for index in range(UPDATES): screen._update_hud(states[index%states.size()])
			samples.append(Time.get_ticks_usec()-started)
			await process_frame
	_check(Canonical.digest(states)==input_hash,case.id+" retains original inputs after repeated HUD calls")
	var sorted := samples.duplicate()
	sorted.sort()
	reports.append({"id":case.id,"native_snapshots":states.size(),"input_sha256":input_hash,
		"visible_output_sha256":Canonical.digest(outputs),"replay_output_sha256":Canonical.digest(replay_output),
		"samples_us":samples,"median_us":sorted[3] if benchmark else 0})
	screen.free()

func _check_visible(case: Dictionary, state: Dictionary, controls: CanvasLayer) -> void:
	var duration := int(state.get("duration_ticks",600))
	var expected_progress := clampf(snappedf(float(state.tick)/30.0,controls.turn_progress.step),controls.turn_progress.min_value,controls.turn_progress.max_value)
	_check(controls.timer_label.text=="%.1f" % maxf(0.0,float(duration-int(state.tick))/30.0) and is_equal_approx(controls.turn_progress.value,expected_progress),case.id+" timer and progress follow every native tick with the existing bar precision")
	_check(controls.finish_button.disabled==not bool(state.get("can_commit",false)) and controls.action_button.disabled==not bool(state.get("context_action",{}).get("enabled",false)),case.id+" action gates follow native state")
	if case.kind=="chapter" and Registry.is_journey(case.key):
		if case.role=="a" and state.get("can_commit",false):
			coverage["journey_ready"]=true
			_check(controls.hint_label.text==PlayerCopy.MAIN_1AAC5BE95E22,"Ready Journey source keeps the Finish instruction")
		else:
			coverage["journey_hint"]=true
			var expected := PlayerCopy.CONSERVATORY_ABOVE_HINT_A if case.role=="a" else PlayerCopy.CONSERVATORY_ABOVE_HINT_B
			_check(controls.hint_label.text==expected,"Native Journey stage uses its published role hint")
	if case.kind!="lighthouse": return
	if state.has("sequence") and state.sequence.phase=="second" and state.get("context_action",{}).get("id")=="select_path":
		var cumulative: bool = int(state.simulation_version)==Light.CURRENT_SIMULATION_VERSION
		coverage["cumulative_selector" if cumulative else "legacy_selector"]=true
		var expected := "Action" if cumulative else PlayerCopy.from_canonical(str(state.context_action.label))
		_check(controls.action_button.text==expected,"Selector label follows the exact Lighthouse rules without changing the native action")

func _visible(controls: CanvasLayer) -> Dictionary:
	var panel: PanelContainer = controls.objective_panel
	return {"title":controls.chapter_label.text,"timer":controls.timer_label.text,"hint":controls.hint_label.text,
		"progress":[controls.turn_progress.value,controls.turn_progress.max_value],"action":[controls.action_button.text,controls.action_button.disabled,controls.action_button.visible],
		"finish":[controls.finish_button.disabled,controls.finish_button.visible],"stick":controls.stick.visible,
		"objective":[panel.visible,panel.label.text,panel.value_label.text,panel.value_label.visible,panel.detail_label.text,panel.detail_label.visible,panel.bar.visible,panel.bar.value,panel.bar.max_value]}

func _fixture(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/"+name))
	_check(value is Dictionary,"Read bundled native fixture: "+name)
	return value if value is Dictionary else {}

func _check(value: bool, label: String) -> bool:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
	return value
