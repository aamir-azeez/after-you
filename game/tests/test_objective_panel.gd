extends SceneTree

const Controls = preload("res://presentation/chapter_controls.gd")
const Objective = preload("res://presentation/objective_panel.gd")
const Lighthouse = preload("res://lighthouse_preview.gd")
const LightSimulation = preload("res://core/lighthouse/borrowed_light.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for dimensions: Vector2i in [Vector2i(960, 540), Vector2i(1600, 720)]:
		for left_handed: bool in [false, true]:
			var viewport := SubViewport.new()
			viewport.size = dimensions
			root.add_child(viewport)
			var controls := Controls.new()
			controls.settings = {"left_handed": left_handed}
			viewport.add_child(controls)
			controls.show_play()
			var snapshot := {"tick": 120, "objective_display": {"label": "First path", "current": 2.5, "required": 4.0, "unit": "seconds", "detail": "Keep the path lit"}}
			var original := snapshot.duplicate(true)
			controls.update_state("A long Lighthouse chapter title", 16.0, snapshot, true)
			await _settle()
			var panel: PanelContainer = controls.objective_panel
			var bounds := panel.get_global_rect()
			_check(panel.visible and panel.value_label.text == "2.5 / 4.0 s", "Hold duration is visible in its own numeric line")
			_check(panel.detail_label.text == "Keep the path lit" and panel.bar.value == 2.5 and panel.bar.max_value == 4.0, "The numeric state controls the bar while guidance stays separate")
			_check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(bounds), "Objective panel stays inside the landscape viewport")
			_check(bounds.position.x > dimensions.x * 0.5 and bounds.position.y >= 124, "Objective appears on the right below Pause and presence")
			for other: Control in [controls.timer_label, controls.turn_progress, controls.pause_button, controls.stick, controls.action_button, controls.finish_button]:
				_check(not bounds.intersects(other.get_global_rect()), "The right objective does not overlap timer or controls")
			_check(snapshot == original, "HUD formatting does not change the simulation snapshot")
			controls.update_state("Replay", 9.0, {"progress_message": "The lens is waiting for you on Rest Rock"}, false)
			await _settle()
			_check(panel.visible and not panel.bar.visible and not panel.value_label.visible and not panel.detail_label.visible, "Untimed guidance clears old numbers and progress")
			_check("Rest Rock" in panel.label.text, "Untimed objective keeps its route guidance")
			_check(panel.get_global_rect().size.y < bounds.size.y, "A shorter objective releases the previous panel height")
			controls.update_state("First Steps", 20.0, {}, true)
			_check(not panel.visible, "No objective leaves the playfield clear")
			controls.update_state("Earlier island", 19.0, {"bridge_charge": 15, "bridge_charge_required": 60}, true)
			_check(panel.visible and panel.value_label.text == "0.5 / 2.0 s", "Earlier-island charge uses the same objective component")
			controls.update_state("Earlier island", 19.0, {"bridge_charge": 1, "bridge_charge_required": 1}, true)
			_check(not panel.visible, "Instant bridges do not show a meaningless hold timer")
			controls.card("Paused", "Your progress is kept.")
			_check(not panel.is_visible_in_tree(), "A modal hides the objective with the rest of the HUD")
			viewport.queue_free()
			await _settle()
	var untouched := {"bridge_charge": 30, "bridge_charge_required": 90}
	_check(Objective.legacy_progress(untouched, 30.0).required == 3.0 and untouched.size() == 2, "Legacy presentation uses supplied numeric state without modifying it")
	await _test_invalid_hold()
	print("OBJECTIVE PANEL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_invalid_hold() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	root.add_child(viewport)
	var controls := Controls.new()
	viewport.add_child(controls)
	controls.show_play()
	var screen := Lighthouse.new()
	screen.controls = controls
	screen.stage = LightCatalog.definition("borrowed-light")
	screen.checkpoint = {"stage_index": 0}
	screen.mode = "play"
	for late: bool in [false, true]:
		var sim := LightSimulation.new()
		sim.reset()
		if late:
			var delay := LightSimulation.MAX_TICKS - LightSimulation.receiver_budget_ticks() - 3
			for _i in range(delay): sim.step({})
		for _i in range(4): sim.step({"move_x": 1})
		for _i in range(30): sim.step({})
		if not late:
			for _i in range(10): sim.step({"move_x": -1})
			for _i in range(10): sim.step({"move_x": 1})
		var state: Dictionary = sim.snapshot()
		_check(not state.can_commit and state.hold_ticks >= LightSimulation.MIN_HOLD_TICKS, "Real invalid source retains a completed hold duration")
		screen._update_hud(state)
		await _settle()
		_check(controls.finish_button.disabled and controls.objective_panel.detail_label.text == sim.commit_reason(), "A completed hold cannot hide the actual recovery instruction")
		_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(controls.objective_panel.get_global_rect()), "Long hold recovery guidance remains inside a narrow screen")
		_check(not controls.objective_panel.get_global_rect().intersects(controls.action_button.get_global_rect()), "Long objective guidance does not cover Action")
	screen.free()
	viewport.queue_free()
	await _settle()

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
