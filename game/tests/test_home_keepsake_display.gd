extends SceneTree
const World = preload("res://presentation/island_world.gd")
const Stage = preload("res://presentation/home_stage.gd")
const Display = preload("res://presentation/home_keepsake_display.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Levels = preload("res://core/levels.gd")
const Main = preload("res://main.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
var checks := 0
var failures := 0
var box_heights := {}

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
	var title_font: Font = stage._keepsake_title.get_theme_font("font")
	var title_text := title_font.get_string_size(stage._keepsake_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, stage._keepsake_title.get_theme_font_size("font_size")).x
	_check(stage._keepsake_controls.get_child(0).size.y <= 64 and stage._keepsake_controls.get_child(2).size.y <= 64 and stage._keepsake_title.size.x >= minf(title_text, 100.0), "Actual home theme leaves bounded buttons and readable title width after layout settles")
	_check(JSON.stringify(items) == descriptors_before and JSON.stringify(world.current_level) == definition_before, "Looking at keepsakes changes neither awards nor authored gameplay")
	var garden: Node3D = world.garden
	_check(not garden.visible, "Home display clears the gameplay garden while it owns the island")
	stage.free()
	await process_frame
	_check(garden.visible and world.home_presentation_owner == 0, "Leaving home restores gameplay props and releases scenery ownership")
	viewport.free()
	for size: Vector2i in [Vector2i(1560, 720), Vector2i(1280, 720), Vector2i(1600, 720)]:
		for state: String in ["none", "few", "pair", "all"]:
			await _box_state(size, state)
		var heights: Array = box_heights.values()
		_check(heights.size() == 4 and heights.all(func(height: float) -> bool: return absf(height - heights[0]) <= 0.5), "The keepsake box keeps one height in every state at %s: %s" % [size, box_heights])
		box_heights.clear()
	var lift := Catalog.chapter_place("first-steps@1", "a-little-lift")
	var light := Catalog.chapter_place(Catalog.LIGHTHOUSE, "borrowed-light")
	_check(Catalog.variant_count([{"id": lift, "solo": true, "friend": true}]) == 2, "Earning solo and together on one place counts two variants")
	_check(Catalog.variant_count([{"id": light, "solo": true, "friend": true}, {"id": "unknown/place", "solo": true}]) == 1, "Lighthouse places have no together variant and unknown places never count")
	print("HOME KEEPSAKE DISPLAY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The keepsake box holds only keepsake content: a teaser of real catalog items
## when nothing is earned, the browser plus remaining teasers otherwise.
func _box_state(size: Vector2i, state: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var world := World.new()
	viewport.add_child(world)
	world.load_level(Levels.get_level("first-light"))
	world.set_process(false)
	var items: Array[Dictionary] = []
	for item: Dictionary in Catalog.all():
		if state == "all" or (state in ["few", "pair"] and item.chapter_key == "first-steps@1"):
			var earned := item.duplicate(true)
			earned.solo = true
			earned.friend = state == "all" and item.friend_available
			if state == "pair" and not items.is_empty(): continue
			if state == "pair": earned.friend = true
			items.append(earned)
	var stage := Stage.new()
	var theme_source := Main.new()
	theme_source._build_theme()
	stage.theme = theme_source.ui_theme
	theme_source.free()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var active := func() -> bool: return true
	stage.configure(world, active, items)
	viewport.add_child(stage)
	stage.set_process(false)
	for frame in range(6):
		await process_frame
		stage._layout()
	var context := " (%s, %s)" % [state, size]
	# Progress counts variants: every place solo, plus together where it exists.
	var total := 0
	for place: Dictionary in Catalog.all(): total += 1 + int(place.friend_available)
	_check(total == Catalog.variant_total() and total == 50 and Catalog.all().size() == 28, "The collection total is 28 solo plus 22 together variants" + context)
	var expected_count := 0
	for item: Dictionary in items: expected_count += int(item.solo) + int(item.friend)
	var box: Control = stage._keepsake_box
	_check(is_instance_valid(box) and box.is_visible_in_tree() and box.find_children("*", "Label", true, false).any(func(label: Label) -> bool: return label.is_visible_in_tree() and not label.text.is_empty()), "The keepsake box always shows keepsake content" + context)
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	var box_rect := box.get_global_rect()
	var hint_rect: Rect2 = stage._hint.get_global_rect()
	_check(screen.encloses(box_rect) and screen.encloses(hint_rect), "Box and hint stay on screen" + context)
	_check(not box_rect.intersects(hint_rect), "The box never meets the bottom-right hint" + context)
	_check(absf(hint_rect.end.x - (size.x - 30.0)) <= 1.0 and stage._hint.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and hint_rect.end.y <= size.y - 10.0, "The hint sits right-aligned in the footer band" + context)
	_check(box_rect.position.x >= stage._stage_rect().position.x - 0.5 and absf(box_rect.get_center().x - stage._stage_rect().get_center().x) <= 1.0, "The box is centred in the island stage, clear of the menu column" + context)
	box_heights[state] = box_rect.size.y
	var labels := {}
	for label: Label in box.find_children("*", "Label", true, false):
		if label.is_visible_in_tree(): labels[label.text] = true
	var strip: TextureRect = stage._keepsake_strip
	var count: Label = stage._keepsake_count
	_check(labels.has("Keepsakes · %d / %d" % [expected_count, total]) and count.is_visible_in_tree(), "The collection count reads Keepsakes · earned / total in every state" + context)
	_check(strip != null and strip.is_visible_in_tree() and strip.get_global_rect().size.y >= 36.0 and strip.get_global_rect().end.y <= count.get_global_rect().position.y + 0.5, "Keepsakes sit on their own row, at least 36 tall, above the count" + context)
	_check(strip != null and absf(strip.get_global_rect().get_center().x - box_rect.get_center().x) <= 1.0, "The keepsake strip is centred in the box" + context)
	_check(not labels.has("Solo") and not labels.has("With a friend") and not labels.has("Solo   ·   With a friend"), "Variant words never sit beside the count" + context)
	if state == "none":
		var expected: Array = stage.next_unearned(4).map(func(item: Dictionary) -> String: return item.id)
		_check(not stage._keepsake_controls.is_visible_in_tree() and stage._keepsake_invite.is_visible_in_tree(), "With nothing earned the box shows the teaser and invitation, no browser" + context)
		_check(labels.has(PlayerCopy.KEEPSAKE_TEASER), "The teaser shows one invitation line" + context)
		_check(strip != null and strip.silhouette and strip.items.map(func(item: Dictionary) -> String: return item.id) == expected and expected.size() == 4, "The teaser shows the next four real catalog keepsakes as silhouettes" + context)
		_check(strip != null and expected.all(func(id: String) -> bool: return not Catalog.by_id(id).is_empty()), "Every teased keepsake is a real catalog item" + context)
		_check(not is_instance_valid(stage._keepsake_display), "No furniture appears before anything is earned" + context)
	else:
		_check(stage._keepsake_controls.is_visible_in_tree() and not stage._keepsake_invite.is_visible_in_tree(), "Earned keepsakes show the browser" + context)
		if state == "pair": _check(expected_count == 2 and labels.has("Keepsakes · 2 / %d" % total), "Solo and together on one place count as two" + context)
		_check(is_instance_valid(stage._keepsake_display) and stage._keepsake_display.visible and stage._keepsake_display._shelf.get_children().filter(func(prop: Node) -> bool: return prop.has_meta("keepsake_id")).size() == items.size(), "Earned items render on the island shelf" + context)
		var earned_ids := items.map(func(item: Dictionary) -> String: return item.id)
		if state == "all":
			_check(strip != null and not strip.silhouette and strip.items.size() == 3 and strip.items.all(func(item: Dictionary) -> bool: return earned_ids.has(item.id)), "A complete collection shows earned keepsakes in colour, not text only" + context)
		else:
			_check(strip != null and strip.silhouette and strip.items.size() == 3 and strip.items.all(func(item: Dictionary) -> bool: return not earned_ids.has(item.id)), "Remaining keepsakes are teased as silhouettes above the count" + context)
		var selected: Dictionary = stage._keepsake_display.selected_item()
		var solo: Control = stage._keepsake_controls.find_child("KeepsakeSolo", true, false)
		var together: Control = stage._keepsake_controls.find_child("KeepsakeTogether", true, false)
		_check(stage._keepsake_title.text == str(selected.title) and solo.visible == bool(selected.solo) and together.visible == bool(selected.friend), "The browser names the keepsake with person / two-person icons for its earned variants" + context)
		var title_rect: Rect2 = stage._keepsake_title.get_global_rect()
		for icon: Control in [solo, together]:
			if icon.visible: _check(icon.get_global_rect().size.x >= 20.0 and not icon.get_global_rect().intersects(title_rect) and icon.get_global_rect().position.x >= title_rect.end.x, "Variant icons follow the title without overlapping it" + context)
		for child: Control in [stage._keepsake_controls.get_child(0), stage._keepsake_controls.get_child(2)]:
			_check(box_rect.encloses(child.get_global_rect()), "Browser buttons stay inside the box" + context)
			var page := child as Button
			var fill := page.get_theme_stylebox("normal") as StyleBoxFlat
			_check(page.text.is_empty() and page.size.x >= 48.0 and page.size.y >= 48.0 and fill != null and fill.bg_color == Color("2f5d52") and fill.border_color == Color("466e63") and fill.border_width_left >= 1 and not page.accessibility_name.is_empty(), "Paging buttons are teal secondary controls with a 48+ hit area" + context)
			_check(not page.get_global_rect().intersects(title_rect) and (not solo.visible or not page.get_global_rect().intersects(solo.get_global_rect())) and (not together.visible or not page.get_global_rect().intersects(together.get_global_rect())), "The title group stays clear of the paging buttons" + context)
		_check(stage.PAGE_CHEVRON_HEIGHT >= 22.0 and stage.PAGE_CHEVRON_HEIGHT <= 24.0, "The paging chevron is 22 to 24 units tall" + context)
	_check(not stage._allowed(box_rect.get_center()), "The box never starts a camera gesture" + context)
	stage.free()
	viewport.free()
	await process_frame
