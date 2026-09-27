extends SceneTree
const World = preload("res://presentation/island_world.gd")
const Stage = preload("res://presentation/home_stage.gd")
const Display = preload("res://presentation/home_keepsake_display.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Levels = preload("res://core/levels.gd")
const Main = preload("res://main.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	root.add_child(viewport)
	var world := World.new()
	viewport.add_child(world)
	world.load_level(Levels.get_level("first-light"))
	world.set_process(false)
	var definition_before := JSON.stringify(world.current_level)
	var items := Catalog.all()
	for index in range(items.size()):
		items[index].solo = index % 3 != 1
		items[index].friend = items[index].friend_available and index % 3 != 0
		if not items[index].solo and not items[index].friend: items[index].solo = true
	var descriptors_before := JSON.stringify(items)
	var stage := Stage.new()
	var theme_source := Main.new()
	theme_source._build_theme()
	stage.theme = theme_source.ui_theme
	theme_source.free()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var active := func() -> bool: return true
	stage.configure(world,active,items)
	viewport.add_child(stage)
	stage.set_process(false)
	for frame in range(12):
		await process_frame
		stage._process(0)
	var display: Node3D = stage._keepsake_display
	_check(is_instance_valid(display) and display.visible, "Earned items visibly add furniture to the actual home island")
	var shown := {}
	for prop: Node in display._shelf.get_children():
		if prop.has_meta("keepsake_id"):
			shown[prop.get_meta("keepsake_id")] = true
			_check(prop.position.y < 2.0 and absf(prop.position.x) < 1.5, "Complete collection stays within four shelf rows and its original width")
	_check(shown.size() == items.size(), "The full shelf displays every earned place once")
	var seen := {}
	for index in range(items.size()):
		var item: Dictionary = display.selected_item()
		seen[item.id] = true
		var solos := 0
		var friends := 0
		for child: Node in display._selected.get_children():
			if child.name.ends_with("_solo"): solos += 1
			if child.name.ends_with("_friend"): friends += 1
		_check(solos == int(item.solo) and friends == int(item.friend), "Only earned full-size variants appear for " + item.id)
		display.select_offset(1)
	_check(seen.size() == items.size() and display.selected_index == 0, "Browsing reaches every earned stage and wraps without dropping an item")
	stage._update_keepsake_labels()
	var control_point: Vector2 = stage._keepsake_controls.get_global_rect().get_center()
	_check(not stage._allowed(control_point), "Keepsake buttons never start a home camera gesture")
	_check(stage._keepsake_controls.get_global_rect().end.x <= 960 and stage._keepsake_controls.get_global_rect().end.y <= 540, "Keepsake controls fit the small landscape view")
	_check(stage._keepsake_controls.get_child(0).size.y <= 64 and stage._keepsake_controls.get_child(2).size.y <= 64 and stage._keepsake_title.size.x >= 100, "Actual home theme leaves bounded buttons and readable title width after layout settles")
	_check(JSON.stringify(items) == descriptors_before and JSON.stringify(world.current_level) == definition_before, "Looking at keepsakes changes neither awards nor authored gameplay")
	var garden: Node3D = world.garden
	_check(not garden.visible, "Home display clears the gameplay garden while it owns the island")
	stage.free()
	await process_frame
	_check(garden.visible and world.home_presentation_owner == 0, "Leaving home restores gameplay props and releases scenery ownership")
	viewport.free()
	print("HOME KEEPSAKE DISPLAY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
