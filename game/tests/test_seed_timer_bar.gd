extends SceneTree
## Every chapter HUD shows the one shared seed timer: the remaining seconds above
## a rounded track where the icon seed rides the fill edge. It reuses one cached
## texture and its styles, never processes per frame, redraws only on a changed
## value, and keeps its place at the phone and desktop layouts.
const SeedTimerBar = preload("res://presentation/seed_timer_bar.gd")
const ChapterControls = preload("res://presentation/chapter_controls.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const RelayPreview = preload("res://relay_preview.gd")
const CoopPreview = preload("res://cooperative_preview.gd")
const Lighthouse = preload("res://lighthouse_preview.gd")
const LighthouseJourney = preload("res://services/lighthouse_journey.gd")
const SharedReplayView = preload("res://presentation/shared_replay_view.gd")
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
const Levels = preload("res://core/levels.gd")
const LegacySimulation = preload("res://core/simulation.gd")
const IDLE := {"move_x": 0.0, "move_z": 0.0, "interact": false}
const SETTINGS := {"sound": false, "haptics": false, "reduced_motion": false, "assistance": true, "left_handed": false, "graphics_quality": "low", "photo_prompts": false}
## 1560x720 and 1280x720 as laid out; 800x360 stretches to a 1600x720 layout.
const LAYOUTS := [Vector2i(1560, 720), Vector2i(1280, 720), Vector2i(1600, 720)]
var checks := 0
var failures := 0
var cleanup: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _check_component()
	await _check_layouts()
	for key: String in [Registry.RELAY, Registry.WISHING_WELL, Registry.CONSERVATORY]:
		await _check_chapter(key)
	await _check_lighthouse()
	await _check_shared_replay()
	await _check_islands()
	for path: String in cleanup:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	await process_frame
	print("AFTER YOU SEED TIMER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport

func _check_component() -> void:
	var viewport := _viewport(Vector2i(640, 200))
	var bar := SeedTimerBar.new()
	viewport.add_child(bar)
	bar.position = Vector2(20, 20)
	bar.size = Vector2(320, SeedTimerBar.MIN_SIZE.y)
	bar.set_remaining(15.0, 20.0)
	await _frames(3)
	_check(is_equal_approx(bar.value, 5.0) and is_equal_approx(bar.max_value, 20.0) and bar.label.text == "15" and is_equal_approx(bar.ratio_elapsed(), 0.25), "The timer shows the remaining whole seconds and fills with the elapsed time")
	_check(is_equal_approx(bar.step, 0.01), "The timer keeps the old bar's precision")
	_check(not bar.is_processing() and not bar.is_physics_processing(), "The timer does no per-frame work")
	var drawn := bar.draw_count
	_check(drawn >= 1, "The timer draws itself")
	for i in range(30):
		bar.set_remaining(15.0, 20.0)
		await process_frame
	_check(bar.draw_count == drawn, "Repeating the same time never redraws the timer (%d -> %d)" % [drawn, bar.draw_count])
	var resources := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in range(60):
		bar.set_remaining(15.0 - i / 30.0, 20.0)
		await process_frame
	_check(bar.draw_count > drawn and bar.label.text == "14", "Each new tick redraws the timer and updates its number")
	_check(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT) <= resources and Performance.get_monitor(Performance.OBJECT_COUNT) <= objects, "Counting down loads no textures and creates no objects")
	var other := SeedTimerBar.new()
	viewport.add_child(other)
	var texture: Texture2D = SeedTimerBar.SEED_TEXTURE
	_check(texture is Texture2D and texture == load("res://assets/ui/seed.svg") and texture.get_height() >= 60, "The seed is one cached 2D texture from the seed asset")
	_check(SeedTimerBar._style("track") == SeedTimerBar._style("track") and other.label.get_theme_font("font") == bar.label.get_theme_font("font"), "Every timer shares one set of styles and one number font")
	var calm := bar.draw_count
	bar.reduced_motion = true
	await process_frame
	_check(bar.draw_count == calm + 1, "Turning on reduced motion redraws the seed upright once")
	for item: Array in [[100.0, "100"], [99.97, "100"], [10.03, "11"], [10.0, "10.0"], [9.84, "9.8"], [-1.0, "0.0"]]:
		_check(SeedTimerBar.format_remaining(item[0]) == item[1], "%.2f s left reads %s" % [item[0], item[1]])
	bar.set_remaining(0.0, 20.0)
	_check(bar.label.text == "0.0" and is_equal_approx(bar.ratio_elapsed(), 1.0), "At the end of the turn the seed reaches the sprout")
	bar.set_remaining(25.0, 20.0)
	_check(is_equal_approx(bar.value, 0.0), "A remaining time over the turn length clamps to an empty bar")
	viewport.free()

func _check_layouts() -> void:
	for size: Vector2i in LAYOUTS:
		var viewport := _viewport(size)
		var controls := ChapterControls.new()
		controls.settings = SETTINGS.duplicate()
		viewport.add_child(controls)
		controls.show_play()
		controls.update_state("THE RELAY ISLES · 1 / 2 · Your first turn", 12.3, {"duration_ticks": 600, "message": ""}, true)
		await _frames(2)
		var bar: Control = controls.turn_progress
		var rect := bar.get_global_rect()
		var label := controls.timer_label.get_global_rect()
		var name := "%dx%d" % [size.x, size.y]
		_check(bar.get_script() == SeedTimerBar and controls.timer_label == bar.label, "The chapter HUD timer is the shared seed timer: " + name)
		_check(Rect2(Vector2.ZERO, Vector2(size)).encloses(rect) and absf(rect.get_center().x - size.x * 0.5) < 1.0, "The timer stays centred and on screen: " + name)
		_check(rect.size.x >= 300.0 and rect.size.y >= SeedTimerBar.MIN_SIZE.y and rect.encloses(label) and label.size.y >= 36.0, "The timer keeps its full width and a readable number: " + name)
		for other: Control in [controls.chapter_label, controls.pause_button, controls.objective_panel]:
			_check(not rect.intersects(other.get_global_rect()), "The timer leaves %s clear: %s" % [other.name if not other.name.is_empty() else other.get_class(), name])
		_check(controls.timer_label.text == "13" and is_equal_approx(controls.turn_progress.value, 7.7), "The HUD number and fill follow the remaining time: " + name)
		controls.settings.reduced_motion = true
		controls.update_state("THE RELAY ISLES", 12.0, {"duration_ticks": 600, "message": ""}, true)
		_check(controls.turn_progress.reduced_motion, "The HUD timer follows the reduced motion setting: " + name)
		viewport.free()

func _check_screen(screen: Node, label: String) -> void:
	var bar: Variant = screen.controls.turn_progress
	_check(bar is Control and bar.get_script() == SeedTimerBar and screen.controls.timer_label == bar.label, label + " shows the shared seed timer")
	if not (bar is Control and bar.get_script() == SeedTimerBar): return
	var before: float = bar.value
	for i in range(15): screen.advance_input(IDLE)
	await process_frame
	var remaining: float = bar.max_value - bar.value
	_check(bar.value > before and bar.label.text == SeedTimerBar.format_remaining(remaining), label + ": the seed timer's fill and number follow the turn (%s)" % bar.label.text)

func _check_chapter(key: String) -> void:
	var path := "user://seed-timer-%s-%d.json" % [key.replace("@", "-"), Time.get_ticks_usec()]
	cleanup.append(path)
	var journal := Journey.new(path, null, key)
	journal.load_data()
	var screen: Node3D = CoopPreview.new() if Registry.is_cooperative(key) else RelayPreview.new()
	screen.chapter_key = key
	screen.journey = journal
	screen.settings = SETTINGS.duplicate()
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.set_process(false)
	await process_frame
	screen.world.set_process(false)
	screen._begin()
	await _check_screen(screen, key)
	screen.free()
	await process_frame

func _check_lighthouse() -> void:
	var path := "user://seed-timer-lighthouse-%d.json" % Time.get_ticks_usec()
	cleanup.append(path)
	var screen: Node3D = Lighthouse.new()
	screen.journey = LighthouseJourney.new(path)
	screen.settings = SETTINGS.duplicate()
	root.add_child(screen)
	screen.set_physics_process(false)
	var deadline := Time.get_ticks_msec() + 30000
	while screen.mode == "loading" and Time.get_ticks_msec() < deadline: await process_frame
	screen.set_process(false)
	screen.world.set_process(false)
	screen._begin()
	await _check_screen(screen, "The Sleeping Lighthouse")
	screen.free()
	await process_frame

func _check_shared_replay() -> void:
	var view: Node = SharedReplayView.new()
	root.add_child(view)
	view.set_process(false)
	view.set_physics_process(false)
	await process_frame
	var bar: Variant = view.controls.turn_progress if is_instance_valid(view.controls) else null
	_check(bar is Control and bar.get_script() == SeedTimerBar and view.controls.timer_label == bar.label, "Shared replays show the shared seed timer")
	view.free()
	await process_frame

func _check_islands() -> void:
	var viewport := _viewport(Vector2i(1280, 720))
	var app: Node = Main.new()
	var path := "user://seed-timer-main-%d.json" % Time.get_ticks_usec()
	cleanup.append(path)
	app.saves = Save.new(path)
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	var bar: Variant = app.progress
	_check(bar is Control and bar.get_script() == SeedTimerBar and app.timer_label == bar.label, "The earlier islands show the shared seed timer")
	if bar is Control and bar.get_script() == SeedTimerBar:
		var level := Levels.get_level(0)
		var sim := LegacySimulation.new()
		sim.reset(level, {}, "a", LegacySimulation.COMFORT_SIMULATION_VERSION)
		for i in range(45): sim.step(IDLE)
		var state: Dictionary = sim.snapshot()
		app.earlier_islands_flow.update_hud(state)
		var remaining := maxi(0, int(state.duration_ticks) - int(state.tick)) / 30.0
		_check(bar.label.text == SeedTimerBar.format_remaining(remaining) and is_equal_approx(bar.max_value, int(state.duration_ticks) / 30.0) and is_equal_approx(bar.value, int(state.tick) / 30.0), "The earlier islands timer shows the remaining seconds (%s)" % bar.label.text)
	viewport.free()
	await process_frame

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
