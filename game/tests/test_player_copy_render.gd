extends SceneTree
## Load isolated test-only scripts with visibly different copy. Runtime catalogs stay immutable.
const Copy = preload("res://presentation/player_copy.gd")
const First = preload("res://core/first_steps/stage_catalog.gd")
const Lighthouse = preload("res://core/lighthouse/stage_catalog.gd")
const LighthouseSimulation = preload("res://core/lighthouse/borrowed_light.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var temporary_files: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var original_hint: String = First.definition().stages[0].hint_a
	var original_reason: String = Lighthouse.definition().hint_b
	var original_completion: String = Lighthouse.definition("a-welcome-left-on").completion_message
	var hint := "COPY TEST: stand on the lit power pad."
	var reason := "COPY TEST: follow the beam across the bridge."
	var completion := "COPY TEST: the lighthouse is awake."
	var source := FileAccess.get_file_as_string("res://presentation/player_copy.gd")
	source = _override(source, original_hint, hint)
	source = _override(source, original_reason, reason)
	source = _override(source, original_completion, completion)
	var variant_path := _write_script("catalog", source)
	var variant: Script = load(variant_path)
	_check(variant.from_canonical(original_hint) == hint and original_hint != hint, "The isolated catalog override is deliberately different from canonical prose")
	_check(Copy.from_canonical(original_hint) != hint, "The shipped catalog is not modified by this test")
	_check(variant.from_canonical("An unknown presentation value") == "An unknown presentation value", "An unmapped value passes through without invented wording")
	var controls_script := _consumer("controls", "res://presentation/chapter_controls.gd", variant_path)
	var main_script := _consumer("main", "res://main.gd", variant_path)
	var lighthouse_script := _consumer("lighthouse", "res://lighthouse_preview.gd", variant_path)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var controls: CanvasLayer = controls_script.new()
	viewport.add_child(controls)
	var state := {"tick": 0, "message": original_hint, "progress_message": original_reason, "can_commit": false, "context_action": {"label": original_hint, "reason": original_reason, "enabled": false}}
	var before := Canonical.digest(state)
	controls.update_state("Test chapter", 20.0, state, true)
	_check(controls.hint_label.text == hint, "The actual chapter HUD displays the override instead of the canonical hint")
	_check(controls.progress_label.text == reason, "The actual chapter progress fallback displays the override")
	_check(controls.action_button.text == hint, "A displayed context action uses the presentation boundary")
	_check(Canonical.digest(state) == before, "Chapter rendering does not rewrite the simulation snapshot")
	var app: Node = main_script.new()
	app._build_theme()
	app._build_ui()
	var layer: CanvasLayer = app.get_child(0)
	app.remove_child(layer)
	viewport.add_child(layer)
	app._update_hud(state)
	_check(app.hint_label.text == hint, "The actual Earlier Islands HUD displays an overridden canonical message")
	_check(app.interact_button.text == hint and app.interact_button.tooltip_text == reason, "Action label and reason render through the same boundary")
	_check(Canonical.digest(state) == before, "Earlier Islands rendering leaves snapshot bytes unchanged")
	var screen: Node = lighthouse_script.new()
	screen.controls = controls
	screen.stage = Lighthouse.definition()
	screen.checkpoint = {"stage_index": 0}
	screen._update_hud({"tick": 0, "message": original_completion, "can_commit": true, "context_action": {}})
	_check(controls.hint_label.text == completion, "Lighthouse completion prose reaches the actual chapter HUD through the override")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/borrowed-light-v3.json"))
	var simulation := LighthouseSimulation.new()
	_check(simulation.reset("b", fixture.a), "The review case starts from the existing immutable first contribution")
	simulation.step({})
	_check(simulation.commit_reason() == original_reason, "The simulation still returns its original canonical commit reason")
	screen.review = simulation.export_recording()
	screen.prior = fixture.a
	screen._show_review()
	var found := false
	for label: Label in controls.overlay.find_children("*", "Label", true, false):
		if label.text.contains(reason): found = true
		_check(not label.text.contains(original_reason), "The review paragraph does not leak the old canonical hint")
	_check(found, "The actual Lighthouse review card renders the overridden commit reason")
	screen.free()
	app.free()
	viewport.queue_free()
	await process_frame
	for path: String in temporary_files:
		DirAccess.remove_absolute(path)
	print("AFTER YOU PLAYER COPY RENDER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _override(source: String, original: String, replacement: String) -> String:
	_check(Copy.CANONICAL_KEYS.has(original), "Every displayed canonical hint/reason/completion has an explicit copy mapping")
	if not Copy.CANONICAL_KEYS.has(original): return source
	var symbol := str(Copy.CANONICAL_KEYS[original]).replace(".", "_").to_upper()
	var pattern := RegEx.new()
	pattern.compile("(?m)^const " + symbol + " := [^\\n]+$")
	_check(pattern.search(source) != null, "The mapped presentation constant exists")
	return pattern.sub(source, "const " + symbol + " := " + JSON.stringify(replacement))

func _consumer(label: String, resource: String, variant_path: String) -> Script:
	var source := FileAccess.get_file_as_string(resource)
	var token := 'preload("res://presentation/player_copy.gd")'
	_check(source.contains(token), "The real presentation consumer explicitly imports its copy catalog")
	source = source.replace(token, 'preload("' + variant_path + '")')
	return load(_write_script(label, source))

func _write_script(label: String, source: String) -> String:
	var path := "user://copy-render-" + label + "-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".gd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(source)
	file.close()
	temporary_files.append(path)
	return path

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
