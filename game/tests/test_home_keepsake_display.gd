extends SceneTree
## Keepsakes stand on the Home island in fixed slots: real props once a place is
## finished solo and with a friend, outlines with solo / together marks before.
const World = preload("res://presentation/island_world.gd")
const Stage = preload("res://presentation/home_stage.gd")
const Display = preload("res://presentation/home_keepsake_display.gd")
const Slots = preload("res://presentation/home_keepsake_slots.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const Levels = preload("res://core/levels.gd")
const Main = preload("res://main.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Spirits stand about this tall; their screen area includes it.
const SPIRIT_HEIGHT := 1.15
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
	_check_slot_table()
	await _check_states_and_updates()
	await _check_layout_clearance()
	await _check_tap()
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

func _check_slot_table() -> void:
	for place: Dictionary in Catalog.all():
		_check(Slots.has_slot(place.id), "Keepsake %s has no Home island slot. Add a row for it to SLOTS in presentation/home_keepsake_slots.gd" % place.id)
	for id: String in Slots.ids():
		_check(not Catalog.by_id(id).is_empty(), "Home island slot %s matches no catalog keepsake. Remove or rename its row in presentation/home_keepsake_slots.gd" % id)
	for level: Dictionary in Levels.all_levels():
		_check(level.bounds == [-560, -290, 560, 290] and level.gap == [-100, 100], "Every island Home can show has the slot table's shape: " + str(level.id))
	_check(Display.state_of({"friend_available": true}, {}) == "none" and Display.state_of({"friend_available": true}, {"solo": true}) == "solo" and Display.state_of({"friend_available": true}, {"friend": true}) == "friend" and Display.state_of({"friend_available": true}, {"solo": true, "friend": true}) == "complete", "A place is complete only when finished solo and with a friend")
	_check(Display.state_of({"friend_available": false}, {"solo": true}) == "complete" and Display.state_of({"friend_available": false}, {"friend": true}) == "none", "A solo-only place is complete once finished solo")

## A world, a Home stage over it and the stage's display.
func _home(size: Vector2i, items: Array[Dictionary]) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var world := World.new()
	viewport.add_child(world)
	world.load_level(Levels.get_level("first-light"))
	world.set_process(false)
	var stage := Stage.new()
	var theme_source := Main.new()
	theme_source._build_theme()
	stage.theme = theme_source.ui_theme
	theme_source.free()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.configure(world, func() -> bool: return true, items)
	viewport.add_child(stage)
	stage.set_process(false)
	for frame in range(6):
		await process_frame
		stage._process(0)
	return {"viewport": viewport, "world": world, "stage": stage, "display": stage._keepsake_display}

func _earned(id: String, solo: bool, friend: bool) -> Dictionary:
	var item := Catalog.by_id(id)
	item.solo = solo
	item.friend = friend
	return item

func _materials(root: Node) -> Array:
	var result := []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mat: Material = (node as MeshInstance3D).material_override
		if node.visible and not result.has(mat): result.append(mat)
	return result

func _check_states_and_updates() -> void:
	var lift := Catalog.chapter_place("first-steps@1", "a-little-lift")
	var grow := Catalog.chapter_place("first-steps@1", "a-place-to-grow")
	var relay := Catalog.chapter_place("relay-isles@2", "relay")
	var light := Catalog.chapter_place(Catalog.LIGHTHOUSE, "borrowed-light")
	var items: Array[Dictionary] = [_earned(lift, true, true), _earned(grow, true, false), _earned(relay, false, true), _earned(light, true, false)]
	var descriptors_before := JSON.stringify(items)
	var home := await _home(Vector2i(960, 540), items)
	var world: Node3D = home.world
	var stage: Control = home.stage
	var display: Node3D = home.display
	var definition_before := JSON.stringify(world.current_level)
	_check(is_instance_valid(display) and display.visible and display.get_parent() == world.terrain, "Keepsakes stand on the Home island itself")
	_check(display.slot_ids().size() == Catalog.all().size() and display.builds == Catalog.all().size(), "Every catalog place gets one slot, built once")
	_check(stage.find_children("*", "SubViewport", true, false).is_empty() and display.find_children("*Shelf*", "", true, false).is_empty(), "No shelf or keepsake strip remains")
	var expect := {lift: "complete", grow: "solo", relay: "friend", light: "complete"}
	for id: String in display.slot_ids():
		var slot: Node3D = display.slot_node(id)
		var state: String = expect.get(id, "none")
		var place := Catalog.by_id(id)
		_check(slot.get_meta("state") == state, "Slot %s shows state %s" % [id, state])
		var prop := slot.get_node_or_null("Keepsake")
		var outline := slot.get_node_or_null("Outline")
		var solo := slot.get_node_or_null("SoloMark")
		var together := slot.get_node_or_null("TogetherMark")
		if state == "complete":
			_check(prop != null and outline == null and solo == null and together == null, "A finished place shows its real keepsake with no marks: " + id)
			_check(prop != null and prop.get_meta("variant") == ("friend" if place.friend_available else "solo"), "A finished place shows its together keepsake where one exists: " + id)
		else:
			_check(prop == null and outline != null, "An unfinished place shows an outline: " + id)
			_check(solo != null and solo.get_meta("lit") == (state == "solo"), "The solo mark lights only once finished solo: " + id)
			if place.friend_available: _check(together != null and together.get_meta("lit") == (state == "friend"), "The together mark lights only once finished with a friend: " + id)
			else: _check(together == null, "A solo-only place has no together mark: " + id)
	var ghosts := []
	var plain_shared := true
	var outline_meshes := 0
	var prop_meshes := 0
	var prop_materials := []
	for id: String in display.slot_ids():
		var slot: Node3D = display.slot_node(id)
		var outline := slot.get_node_or_null("Outline") as MeshInstance3D
		if outline != null:
			if not ghosts.has(outline.material_override): ghosts.append(outline.material_override)
			outline_meshes += 1
			_check(outline.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and outline.get_child_count() == 0 and outline.mesh.get_surface_count() == 1, "Each outline is one shadowless merged mesh: " + id)
		var prop := slot.get_node_or_null("Keepsake")
		if prop != null:
			for node: Node in prop.find_children("*", "MeshInstance3D", true, false):
				prop_meshes += 1
				var mat := (node as MeshInstance3D).material_override as StandardMaterial3D
				if not prop_materials.has(mat): prop_materials.append(mat)
				if mat.albedo_texture == null and not mat.emission_enabled: plain_shared = plain_shared and Primitives.is_shared(mat)
	_check(outline_meshes == display.slot_ids().size() - 2, "Every unfinished place draws one outline")
	_check(ghosts.size() == 2 and ghosts.all(func(mat: StandardMaterial3D) -> bool: return mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED), "All %d outline meshes share two transparent materials, faint and half-done: %d" % [outline_meshes, ghosts.size()])
	_check(plain_shared and prop_materials.size() < prop_meshes, "Earned keepsakes use the kit's shared materials (%d materials for %d meshes)" % [prop_materials.size(), prop_meshes])
	var marks := []
	for node: Node in display.find_children("*Mark", "MeshInstance3D", true, false):
		var mat: Material = (node as MeshInstance3D).material_override
		if not marks.has(mat): marks.append(mat)
	_check(marks.size() <= 4, "Solo and together marks share one material per lit or dim icon")
	# Selection starts at the first unfinished place in slot order.
	_check(display.selected_item().id == grow and stage._keepsake_title.text == Catalog.by_id(grow).title, "Home opens on the first unfinished keepsake")
	_check(stage._keepsake_status.text == PlayerCopy.KEEPSAKE_NEEDS_FRIEND, "A solo-only place says it still needs a friend")
	# Unchanged descriptors rebuild nothing, even as a fresh deep copy.
	var nodes := {}
	for id: String in display.slot_ids(): nodes[id] = display.slot_node(id).get_instance_id()
	var builds: int = display.builds
	for repeat in range(5):
		stage.set_keepsakes(items.duplicate(true))
		display.set_items(items.duplicate(true))
	_check(display.builds == builds and display.slot_ids().all(func(id: String) -> bool: return display.slot_node(id).get_instance_id() == nodes[id]), "Unchanged keepsake state rebuilds no slot")
	var garden := Catalog.chapter_place("relay-isles@2", "garden")
	var garden_mesh: Mesh = (display.slot_node(garden).get_node("Outline") as MeshInstance3D).mesh
	var changed := items.duplicate(true)
	changed.append(_earned(Catalog.chapter_place("relay-isles@2", "garden"), true, false))
	changed[1].friend = true
	stage.set_keepsakes(changed)
	_check((display.slot_node(garden).get_node("Outline") as MeshInstance3D).mesh == garden_mesh, "A rebuilt outline reuses its cached merged mesh")
	_check(display.builds == builds + 2, "Only the two changed slots rebuild")
	for id: String in display.slot_ids():
		if id in [grow, garden]: _check(display.slot_node(id).get_instance_id() != nodes[id], "A changed slot is rebuilt: " + id)
		else: _check(display.slot_node(id).get_instance_id() == nodes[id], "An unchanged slot keeps its nodes: " + id)
	_check(display.slot_node(grow).get_meta("state") == "complete" and display.slot_node(grow).get_node_or_null("Keepsake") != null, "Finishing the together half turns the outline into the keepsake")
	_check(display.selected_item().id in [grow, garden] and stage._keepsake_title.text == display.selected_item().title, "New progress is selected and named in the box")
	# Browsing reaches every slot and wraps.
	var seen := {}
	var start: int = display.selected_index
	for index in range(display.slot_ids().size()):
		seen[display.selected_item().id] = true
		display.select_offset(1)
	_check(seen.size() == Catalog.all().size() and display.selected_index == start, "Browsing reaches every keepsake and wraps")
	display.select_id(light)
	stage._update_keepsake_labels()
	var together: Control = stage._keepsake_controls.find_child("KeepsakeTogether", true, false)
	_check(not together.visible and stage._keepsake_status.text == PlayerCopy.KEEPSAKE_FINISHED_SOLO, "A solo-only keepsake hides the together icon")
	var highlight: Node3D = display.get_node("SelectedSlot")
	_check(highlight.position.x == display.slot_node(light).position.x and highlight.position.z == display.slot_node(light).position.z, "The selected slot is marked on the island")
	var control_point: Vector2 = stage._keepsake_controls.get_global_rect().get_center()
	_check(not stage._allowed(control_point), "Keepsake buttons never start a home camera gesture")
	_check(JSON.stringify(items) == descriptors_before and JSON.stringify(world.current_level) == definition_before, "Looking at keepsakes changes neither awards nor authored gameplay")
	var garden_prop: Node3D = world.garden
	_check(not garden_prop.visible and not world.landing_marker.visible, "Home clears the gameplay garden and landing ring while it owns the island")
	stage.free()
	await process_frame
	_check(garden_prop.visible and world.home_presentation_owner == 0, "Leaving home restores gameplay props and releases scenery ownership")
	home.viewport.free()
	await process_frame

## Island-space footprint of a slot's prop.
func _footprint(display: Node3D, prop: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node: Node in prop.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.visible: continue
		var to_display: Transform3D = display.global_transform.affine_inverse() * mesh.global_transform
		var bounds: AABB = to_display * mesh.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	return box

func _screen_rect(camera: Camera3D, corners: Array) -> Rect2:
	var rect := Rect2(camera.unproject_position(corners[0]), Vector2.ZERO)
	for corner: Vector3 in corners: rect = rect.expand(camera.unproject_position(corner))
	return rect

func _check_layout_clearance() -> void:
	var all: Array[Dictionary] = []
	for place: Dictionary in Catalog.all(): all.append(_earned(place.id, true, true))
	for size: Vector2i in [Vector2i(1560, 720), Vector2i(1280, 720), Vector2i(1600, 720)]:
		var home := await _home(size, all)
		var stage: Control = home.stage
		var display: Node3D = home.display
		var camera: Camera3D = home.world.camera
		var floor: Rect2 = stage._floor
		var right := Rect2(1.0, -2.9, 4.6, 5.8)
		var feet: Array[Rect2] = []
		var screen: Array[Rect2] = []
		var spirits := _screen_rect(camera, [Vector3(floor.position.x, 0, floor.position.y), Vector3(floor.end.x, 0, floor.position.y), Vector3(floor.position.x, 0, floor.end.y), Vector3(floor.end.x, 0, floor.end.y), Vector3(floor.position.x, SPIRIT_HEIGHT, floor.position.y), Vector3(floor.end.x, SPIRIT_HEIGHT, floor.position.y), Vector3(floor.position.x, SPIRIT_HEIGHT, floor.end.y), Vector3(floor.end.x, SPIRIT_HEIGHT, floor.end.y)])
		var box: Rect2 = stage._keepsake_box.get_global_rect()
		for id: String in display.slot_ids():
			var bounds := _footprint(display, display.slot_node(id).get_node("Keepsake"))
			var foot := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
			var corners := []
			for index in range(8): corners.append(display.to_global(bounds.get_endpoint(index)))
			var area := _screen_rect(camera, corners)
			_check(right.encloses(foot.grow(0.05)), "%s stands on the keepsake island at %s" % [id, foot])
			_check(not foot.intersects(floor.grow(0.4)), "%s stays off the spirits' walking area" % id)
			_check(not area.intersects(spirits), "%s never covers the spirits on screen at %s" % [id, size])
			_check(not area.intersects(box), "%s is not hidden by the keepsake box at %s" % [id, size])
			_check(stage._stage_rect().encloses(area), "%s stays in the Home stage at %s" % [id, size])
			for index in range(feet.size()):
				_check(not foot.intersects(feet[index]), "%s does not overlap %s" % [id, display.slot_ids()[index]])
			feet.append(foot)
			screen.append(area)
		stage.free()
		home.viewport.free()
		await process_frame

func _check_tap() -> void:
	var none: Array[Dictionary] = []
	var home := await _home(Vector2i(1280, 720), none)
	var stage: Control = home.stage
	var display: Node3D = home.display
	var camera: Camera3D = home.world.camera
	var target := Catalog.chapter_place("conservatory@1", "a-light-above")
	var point := camera.unproject_position(display.slot_node(target).to_global(Vector3(0, 0.22, 0)))
	_check(display.pick(camera, point) == target, "A keepsake's own point picks it")
	_stage_tap(stage, point)
	_check(display.selected_item().id == target and stage._keepsake_title.text == Catalog.by_id(target).title and stage._greeting_left == 0.0, "Tapping a keepsake names it in the box without greeting the spirits")
	_check(stage._keepsake_status.text == PlayerCopy.KEEPSAKE_TEASER, "An untouched outline says it needs solo and a friend")
	var other := Catalog.chapter_place("first-steps@1", "a-little-lift")
	var start := camera.unproject_position(display.slot_node(other).to_global(Vector3(0, 0.22, 0)))
	_stage_touch(stage, 0, start, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = start + Vector2(60, 0)
	stage._input(drag)
	_stage_touch(stage, 0, start + Vector2(60, 0), false)
	_check(display.selected_item().id == target, "Dragging from a keepsake stays a camera gesture")
	var spirit: Vector2 = camera.unproject_position(home.world.actors.a.to_global(Vector3(0, 0.55, 0)))
	_check(display.pick(camera, spirit).is_empty(), "No keepsake sits under a spirit, so spirit taps still greet")
	_check(display.pick(camera, stage._stage_rect().position + Vector2(8, 8)).is_empty(), "Empty sky picks nothing")
	stage.free()
	home.viewport.free()
	await process_frame

func _stage_touch(stage: Control, index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	stage._input(event)
	var local := event.duplicate()
	local.position = point - stage.global_position
	stage._gui_input(local)

func _stage_tap(stage: Control, point: Vector2) -> void:
	_stage_touch(stage, 0, point, true)
	_stage_touch(stage, 0, point, false)

## The box holds the slot browser, a status line and the count, at one height.
func _box_state(size: Vector2i, state: String) -> void:
	var items: Array[Dictionary] = []
	for item: Dictionary in Catalog.all():
		if state == "all" or (state in ["few", "pair"] and item.chapter_key == "first-steps@1"):
			var earned := item.duplicate(true)
			earned.solo = true
			earned.friend = state == "all" and item.friend_available
			if state == "pair" and not items.is_empty(): continue
			if state == "pair": earned.friend = true
			items.append(earned)
	var home := await _home(size, items)
	var stage: Control = home.stage
	var context := " (%s, %s)" % [state, size]
	var total := 0
	for place: Dictionary in Catalog.all(): total += 1 + int(place.friend_available)
	_check(total == Catalog.variant_total() and total == 58 and Catalog.all().size() == 32, "The collection total is 32 solo plus 26 together variants" + context)
	var expected_count := 0
	for item: Dictionary in items: expected_count += int(item.solo) + int(item.friend)
	var box: Control = stage._keepsake_box
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	var box_rect := box.get_global_rect()
	var hint_rect: Rect2 = stage._hint.get_global_rect()
	_check(box.is_visible_in_tree() and screen.encloses(box_rect) and screen.encloses(hint_rect), "Box and hint stay on screen" + context)
	_check(not box_rect.intersects(hint_rect), "The box never meets the bottom-right hint" + context)
	_check(absf(hint_rect.end.x - (size.x - 30.0)) <= 1.0 and stage._hint.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and hint_rect.end.y <= size.y - 10.0, "The hint sits right-aligned in the footer band" + context)
	_check(box_rect.position.x >= stage._stage_rect().position.x - 0.5 and absf(box_rect.get_center().x - stage._stage_rect().get_center().x) <= 1.0, "The box is centred in the island stage, clear of the menu column" + context)
	box_heights[state] = box_rect.size.y
	var count: Label = stage._keepsake_count
	var status: Label = stage._keepsake_status
	_check(count.text == "Keepsakes · %d / %d" % [expected_count, total] and count.is_visible_in_tree(), "The collection count reads Keepsakes · earned / total in every state" + context)
	_check(status.is_visible_in_tree() and status.text in Stage.STATUS_LINES and status.get_global_rect().end.y <= count.get_global_rect().position.y + 0.5, "A status line sits above the count" + context)
	_check(stage._keepsake_controls.is_visible_in_tree(), "The browser shows in every state, since every keepsake has a slot" + context)
	var selected: Dictionary = stage._keepsake_display.selected_item()
	var solo: TextureRect = stage._keepsake_controls.find_child("KeepsakeSolo", true, false)
	var together: TextureRect = stage._keepsake_controls.find_child("KeepsakeTogether", true, false)
	_check(stage._keepsake_title.text == str(selected.title) and solo.visible and solo.self_modulate == (Stage.SOLO_LIT if selected.solo else Stage.VARIANT_DIM) and together.self_modulate == (Stage.TOGETHER_LIT if selected.friend else Stage.VARIANT_DIM), "The browser names the keepsake with lit or dim solo and together icons" + context)
	if state == "none":
		_check(status.text == PlayerCopy.KEEPSAKE_TEASER and selected.id == Slots.ids()[0], "With nothing earned the box explains the solo and friend rule on the first keepsake" + context)
	if state == "all":
		_check(status.text in [PlayerCopy.KEEPSAKE_FINISHED, PlayerCopy.KEEPSAKE_FINISHED_SOLO], "A complete collection reads as finished" + context)
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
	home.viewport.free()
	await process_frame
