extends SceneTree

const Actions = preload("res://presentation/action_buttons.gd")
const ChapterControls = preload("res://presentation/chapter_controls.gd")
const RelayPreview = preload("res://relay_preview.gd")
const LighthousePreview = preload("res://lighthouse_preview.gd")
const RelayJournal = preload("res://services/relay_journey.gd")
const LighthouseJournal = preload("res://services/lighthouse_journey.gd")
const Registry = preload("res://services/chapter_registry.gd")
const LighthouseSimulation = preload("res://core/lighthouse/borrowed_light.gd")
const Purchases = preload("res://services/purchases.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Main = preload("res://main.gd")
const LocalSave = preload("res://services/local_save.gd")
const Levels = preload("res://core/levels.gd")
const LegacySimulation = preload("res://core/simulation.gd")

# Admission is local and deterministic. This test exercises controls, not an
# SDK transaction or server entitlement, and makes no live service requests.
class LocalAccess extends Purchases:
	func _connect_native() -> bool: return true
	func refresh_customer_info() -> String: return "action-buttons-access"
	func entitled_payload(payload: Dictionary) -> bool:
		return payload == {"schema_version": 1, "entitlements": {"full_journey": {"active": true}}}
	func answer() -> void:
		customer_info = {"schema_version": 1, "entitlements": {"full_journey": {"active": true}}}
		completed.emit("action-buttons-access", "get_customer_info", customer_info)

var checks := 0
var failures := 0
var paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _shared_buttons()
	await _relay_scene(Registry.RELAY, "v2", "relay", "garden-a")
	await _relay_scene(Registry.FIRST_STEPS, "first_steps", "a-little-lift", "a-place-to-grow-a")
	await _lighthouse_scene()
	await _earlier_island()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU ACTION BUTTONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _shared_buttons() -> void:
	# These words are the public vocabulary, not a copy of icon/style internals.
	var expected := {"retry": "Retry", "resume": "Resume", "preview": "Preview", "save": "Save turn", "record": "Record", "finish": "Finish", "pause": "Pause", "continue": "Continue", "back": "Back", "retry_save": "Retry save"}
	for action_id: String in expected:
		var button: Button = Actions.create(action_id, func(): pass)
		_check(button.text == expected[action_id], "The shared action has its short text label: " + action_id)
		_check(button.icon != null and button.icon.get_width() > 0, "The action icon is a separate usable texture: " + action_id)
		_check(button.get_meta("action_id", "") == action_id, "Semantic metadata identifies the actual action: " + action_id)
		_check(button.custom_minimum_size.y >= 50 and button.mouse_filter == Control.MOUSE_FILTER_PASS and button.focus_mode == Control.FOCUS_ALL, "Touch size, card scrolling and keyboard focus remain available: " + action_id)
		button.free()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var calls := {"count": 0}
	var retry: Button = Actions.create("retry", func(): calls.count += 1)
	retry.position = Vector2(32, 32)
	retry.size = Vector2(210, 56)
	viewport.add_child(retry)
	await _settle()
	retry.disabled = true
	for _index in range(4):
		Actions.apply(retry, "resume")
		Actions.apply(retry, "retry")
	_check(retry.disabled and retry.text == "Retry", "Repeated presentation changes never re-enable an unavailable action")
	_check(retry.pressed.get_connections().size() == 1, "Repeated apply retains exactly the original callback connection")
	_click(viewport, retry.get_global_rect().get_center())
	await _settle()
	_check(calls.count == 0, "Real pointer input cannot activate the disabled Retry button")
	retry.disabled = false
	Actions.apply(retry, "retry")
	_check(not retry.disabled, "Applying presentation also preserves an enabled state")
	_click(viewport, retry.get_global_rect().get_center())
	await _settle()
	_check(calls.count == 1, "A real Retry click calls the original callback exactly once after repeated apply")
	var controls := ChapterControls.new()
	viewport.add_child(controls)
	var factory_calls := {"count": 0}
	var factory_button: Button = controls.button_for("retry", func(): factory_calls.count += 1)
	_check(factory_button.text == "Retry" and factory_button.icon != null and factory_button.get_meta("action_id", "") == "retry", "ChapterControls delegates semantic actions to the shared factory")
	factory_button.pressed.emit()
	_check(factory_calls.count == 1, "ChapterControls preserves the supplied action callback")
	factory_button.free()
	viewport.queue_free()
	await _settle()


func _relay_scene(chapter: String, fixture_directory: String, first_stage: String, next_recording: String) -> void:
	var path := _new_path(chapter.replace("@", "-"))
	var seed := RelayJournal.new(path, null, chapter)
	seed.load_data()
	var seeded := seed.accept_recording(_fixture(fixture_directory + "/" + first_stage + "-a.json"))
	seeded = seed.accept_recording(_fixture(fixture_directory + "/" + first_stage + "-b.json")) and seeded
	_check(seeded and seed.pairs().size() == 1, "The controls test begins with a real verified saved checkpoint: " + chapter)
	if not seeded: return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := RelayPreview.new()
	app.chapter_key = chapter
	app.journey = RelayJournal.new(path, null, chapter)
	app.settings = _settings()
	viewport.add_child(app)
	app.set_physics_process(false)
	app.set_process(false)
	app.world.set_process(false)
	await _settle()
	app.backgrounded = false
	_check(app.mode == "ready" and app.journey.pairs().size() == 1, "The actual scene opens at the retained checkpoint: " + chapter)
	if app.mode == "ready":
		var simulation: Script = Registry.simulation_script(chapter)
		var inputs: Array = simulation.expand_recording_inputs(_fixture(fixture_directory + "/" + next_recording + ".json"))
		_exercise_scene(app, path, inputs, chapter)
	viewport.queue_free()
	await _settle()


func _lighthouse_scene() -> void:
	var path := _new_path("lighthouse")
	var fixture := _fixture("lighthouse/first-two-v3.json")
	var seed := LighthouseJournal.new(path)
	seed.load_data()
	var seeded := seed.accept_recording(fixture.pairs[0].a)
	seeded = seed.accept_recording(fixture.pairs[0].b) and seeded
	_check(seeded and seed.pairs().size() == 1, "Lighthouse begins with an actual verified saved checkpoint")
	if not seeded: return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var access := LocalAccess.new()
	var app := LighthousePreview.new()
	app.journey = LighthouseJournal.new(path)
	app.settings = _settings()
	app.purchase_service_factory = func(): return access
	viewport.add_child(app)
	app.set_physics_process(false)
	app.world.set_process(false)
	_check(app.mode == "access_check", "Lighthouse controls do not bypass the existing admission boundary")
	access.answer()
	var deadline := Time.get_ticks_msec() + 30000
	while app.mode == "loading" and Time.get_ticks_msec() < deadline: await process_frame
	_check(app.mode == "ready" and app.journey != null, "The local admission answer and real journal loader reach ready")
	app.set_process(false)
	app.backgrounded = false
	if app.mode == "ready":
		_exercise_scene(app, path, LighthouseSimulation.expand_recording_inputs(fixture.pairs[1].a), "Lighthouse")
	viewport.queue_free()
	await _settle()


func _exercise_scene(app: Node3D, path: String, inputs: Array, chapter: String) -> void:
	var accepted_bytes := _accepted_bytes(app.journey)
	if not _press_action(app.controls.overlay, "record", chapter): return
	for index in range(20): app.advance_input(inputs[index])
	var live_tick: int = app.sim.tick
	var live_record: Dictionary = app.sim.export_recording()
	app.controls.pause_button.pressed.emit()
	_check(app.mode == "paused" and not app.running and live_tick == 20, "The actual Pause callback holds a partial recording: " + chapter)
	_check(_accepted_bytes(app.journey) == accepted_bytes, "Pause cannot alter accepted pairs or checkpoint bytes: " + chapter)
	var saved_before_resume := _save_bytes(path)
	if not _press_action(app.controls.overlay, "resume", chapter): return
	_check(app.mode == "play" and app.running and app.sim.tick == live_tick and Canonical.same(app.sim.export_recording(), live_record), "Resume retains the exact tick and recorded inputs: " + chapter)
	_check(_save_bytes(path) == saved_before_resume, "Resume rewrites no primary, backup or temporary save bytes: " + chapter)
	app.controls.pause_button.pressed.emit()
	var saved_before_retry := _save_bytes(path)
	var draft_before_retry: Dictionary = app.journey.draft()
	if not _press_action(app.controls.overlay, "retry", chapter): return
	_check(app.mode == "play" and app.running and app.sim.tick == 0, "Retry starts this current turn again from tick zero: " + chapter)
	_check(_accepted_bytes(app.journey) == accepted_bytes, "Retry preserves accepted recordings and the current checkpoint bytes: " + chapter)
	_check(_save_bytes(path) == saved_before_retry and Canonical.same(app.journey.draft(), draft_before_retry), "Starting Retry keeps the last durable draft until new input is saved: " + chapter)
	for index in range(7): app.advance_input(inputs[index])
	app.controls.pause_button.pressed.emit()
	_check(app.mode == "paused" and int(app.journey.draft().get("duration_ticks", -1)) == 7, "The new rehearsal saves only its seven new ticks, not the old twenty: " + chapter)
	_check(_accepted_bytes(app.journey) == accepted_bytes, "Saving the retried draft leaves all accepted progress unchanged: " + chapter)
	var reopened: RefCounted = LighthouseJournal.new(path) if chapter == "Lighthouse" else RelayJournal.new(path, null, app.chapter_key)
	reopened.load_data()
	_check(not reopened.read_only and int(reopened.draft().get("duration_ticks", -1)) == 7 and _accepted_bytes(reopened) == accepted_bytes, "A fresh journal reads the new draft and the exact old checkpoint: " + chapter)


func _earlier_island() -> void:
	var path := _new_path("earlier-island")
	var first := _fixture("first-light-a.json")
	var definition: Dictionary = Levels.get_level(0)
	_check(LegacySimulation.verify_recording(definition, first).get("valid", false), "Earlier Islands starts with an independently verified earlier contribution")
	var seed := LocalSave.new(path)
	seed.load_data()
	var settings: Dictionary = seed.data.settings.duplicate(true)
	settings.merge(_settings(), true)
	_check(seed.update_values({"settings": settings}) and seed.save_attempt(definition.id, {"a": first, "b": {}, "draft": {}}), "Earlier Islands stores its accepted A before the controls test")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves = LocalSave.new(path)
	viewport.add_child(app)
	app.set_physics_process(false)
	app.set_process(false)
	app.world.set_process(false)
	await _settle()
	app.application_backgrounded = false
	app._start_practice(0)
	_check(app.mode == "ready" and app.role == "b", "Earlier Islands opens the next contribution without restarting the accepted first turn")
	var accepted_bytes := _earlier_accepted_bytes(app.saves, definition.id)
	if _press_action(app.overlay, "record", "Earlier Islands"):
		for _index in range(20): app._physics_process(1.0 / 30.0)
		var live_record: Dictionary = app.sim.export_recording()
		if _press_action(app.hud, "pause", "Earlier Islands"):
			_check(app.mode == "paused" and not app.running and app.sim.tick == 20, "Earlier Islands Pause holds exactly twenty live ticks")
			var before_resume := _save_bytes(path)
			if _press_action(app.overlay, "resume", "Earlier Islands"):
				_check(app.mode == "play" and app.running and app.sim.tick == 20 and Canonical.same(app.sim.export_recording(), live_record), "Earlier Islands Resume retains the exact partial turn")
				_check(_save_bytes(path) == before_resume, "Earlier Islands Resume writes no primary, backup or temporary bytes")
				if _press_action(app.hud, "pause", "Earlier Islands"):
					var before_retry := _save_bytes(path)
					var old_draft: Dictionary = app.saves.attempt(definition.id).draft
					if _press_action(app.overlay, "retry", "Earlier Islands"):
						_check(app.mode == "ready" and not app.running and app.sim.tick == 0, "Earlier Islands Retry preserves its explicit Record boundary")
						_check(_save_bytes(path) == before_retry and Canonical.same(app.saves.attempt(definition.id).draft, old_draft), "Earlier Islands Retry keeps the last durable draft until another recording is saved")
						_check(_earlier_accepted_bytes(app.saves, definition.id) == accepted_bytes, "Earlier Islands Retry preserves accepted A and every completed replay")
						if _press_action(app.overlay, "record", "Earlier Islands"):
							for _index in range(7): app._physics_process(1.0 / 30.0)
							if _press_action(app.hud, "pause", "Earlier Islands"):
								var reopened := LocalSave.new(path)
								reopened.load_data()
								_check(not reopened.read_only and int(reopened.attempt(definition.id).draft.get("duration_ticks", -1)) == 7, "Earlier Islands persists only the seven ticks of the retried draft")
								_check(_earlier_accepted_bytes(reopened, definition.id) == accepted_bytes, "Earlier Islands accepted source and completed replay bytes survive reopening")
	viewport.queue_free()
	await _settle()


func _earlier_accepted_bytes(storage: RefCounted, level_id: String) -> PackedByteArray:
	var attempt: Dictionary = storage.attempt(level_id)
	return JSON.stringify(Canonical.normalized({"a": attempt.a, "b": attempt.b, "completed": storage.data.completed, "replays": storage.data.replays})).to_utf8_buffer()


func _press_action(node: Node, action_id: String, chapter: String) -> bool:
	var button := _find_action(node, action_id)
	var available: bool = button != null and not button.disabled
	_check(available, "The real scene exposes an enabled semantic " + action_id + " action: " + chapter)
	if available: button.pressed.emit()
	return available


func _find_action(node: Node, action_id: String) -> Button:
	if node is Button and node.is_visible_in_tree() and node.get_meta("action_id", "") == action_id: return node
	for child: Node in node.get_children():
		var found := _find_action(child, action_id)
		if found != null: return found
	return null


func _accepted_bytes(journal: RefCounted) -> PackedByteArray:
	return JSON.stringify(Canonical.normalized({"pairs": journal.pairs(), "checkpoint": journal.checkpoint(), "prior": journal.prior_recording()})).to_utf8_buffer()


func _save_bytes(path: String) -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".tmp", ".backup"]:
		result[suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	return result


func _fixture(name: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string("res://tests/fixtures/" + name)) != OK or not json.data is Dictionary:
		_check(false, "The independent recording fixture is readable: " + name)
		return {}
	return json.data


func _settings() -> Dictionary:
	return {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}


func _new_path(label: String) -> String:
	var path := "user://test-action-buttons-" + label + "-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	paths.append(path)
	return path


func _click(viewport: SubViewport, point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		viewport.push_input(event, true)


func _settle() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
