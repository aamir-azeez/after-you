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
const InGameModal = preload("res://presentation/in_game_modal.gd")
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
	await _check_explore()
	await _check_explore_bridge()
	await _check_explore_arrows()
	for size: Vector2i in [Vector2i(1560, 720), Vector2i(1280, 720), Vector2i(1600, 720)]:
		for state: String in ["none", "few", "pair", "all"]:
			await _box_state(size, state)
		var heights: Array = box_heights.values()
		_check(heights.size() == 4 and heights.all(func(height: float) -> bool: return absf(height - heights[0]) <= 0.5), "The keepsake box keeps one height in every state at %s: %s" % [size, box_heights])
		box_heights.clear()
	var lift := Catalog.chapter_place("first-steps@1", "a-little-lift")
	var light := Catalog.chapter_place(Catalog.LIGHTHOUSE, "borrowed-light")
	_check(Catalog.variant_count([{"id": lift, "solo": true, "friend": true}]) == 2, "Earning solo and together on one place counts two variants")
	_check(Catalog.variant_count([{"id": light, "solo": true, "friend": true}, {"id": "unknown/place", "solo": true}]) == (2 if Catalog.lighthouse_together() else 1), "Lighthouse places have a together variant once its six-stage chapter is released; unknown places never count")
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
	# Each Home here starts from the default view, never one kept from the last.
	Stage._retained_view.clear()
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
	# Started chapters (First Steps, Relay, Lighthouse) plus the next untouched one.
	var shown_expected := {}
	for chapter: String in ["first-steps@1", "relay-isles@2", Catalog.LIGHTHOUSE, "high-and-low@1"]:
		for id: String in Catalog.chapter_places(chapter): shown_expected[id] = true
	_check(display.slot_ids().size() == Catalog.all().size(), "Every catalog place has a slot")
	_check(display.shown_slot_ids().size() == shown_expected.size() and display.shown_slot_ids().all(func(id: String) -> bool: return shown_expected.has(id)) and display.builds == shown_expected.size(), "Only started chapters and the next one show, each built once: %s" % [display.shown_slot_ids()])
	for id: String in display.slot_ids():
		if not shown_expected.has(id): _check(display.slot_node(id) == null, "A later chapter's slot stays empty: " + id)
	_check(display.island("behind_left") != null and display.island("behind_left").visible and display.island("behind_right") == null and display.island("beside_right") == null, "The Lighthouse island shows once a Lighthouse keepsake is shown, and the others wait")
	_check(stage.find_children("*", "SubViewport", true, false).is_empty() and display.find_children("*Shelf*", "", true, false).is_empty(), "No shelf or keepsake strip remains")
	# Finished solo, a Lighthouse place is complete only while it has no together variant.
	var expect := {lift: "complete", grow: "solo", relay: "friend", light: "solo" if Catalog.lighthouse_together() else "complete"}
	for id: String in display.shown_slot_ids():
		var slot: Node3D = display.slot_node(id)
		var state: String = expect.get(id, "none")
		var place := Catalog.by_id(id)
		_check(slot.get_meta("state") == state, "Slot %s shows state %s" % [id, state])
		var prop := slot.get_node_or_null("Keepsake")
		var outline := slot.get_node_or_null("Outline")
		var solo := slot.get_node_or_null("SoloMark")
		var together := slot.get_node_or_null("TogetherMark")
		_check_state(slot, state, place)
	var ghosts := []
	var plain_shared := true
	var outline_meshes := 0
	var prop_meshes := 0
	var prop_materials := []
	for id: String in display.shown_slot_ids():
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
	_check(outline_meshes == display.shown_slot_ids().size() - 4, "Every untouched shown place draws one outline")
	_check(ghosts.size() == 1 and ghosts.all(func(mat: StandardMaterial3D) -> bool: return mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED), "All %d outlines share one transparent material: %d" % [outline_meshes, ghosts.size()])
	var upgrade_materials := {}
	for node: Node in display.find_children("Upgrade", "Node3D", true, false):
		for part: Node in node.find_children("*", "MeshInstance3D", true, false): upgrade_materials[(part as MeshInstance3D).material_override] = true
	_check(upgrade_materials.size() == 3 and upgrade_materials.keys().all(func(mat: Material) -> bool: return Primitives.is_shared(mat)), "Every upgrade shares the same three kit materials: %d" % upgrade_materials.size())
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
	for id: String in display.shown_slot_ids(): nodes[id] = display.slot_node(id).get_instance_id()
	var builds: int = display.builds
	for repeat in range(5):
		stage.set_keepsakes(items.duplicate(true))
		display.set_items(items.duplicate(true))
	_check(display.builds == builds and display.shown_slot_ids().all(func(id: String) -> bool: return display.slot_node(id).get_instance_id() == nodes[id]), "Unchanged keepsake state rebuilds no slot")
	var garden := Catalog.chapter_place("relay-isles@2", "garden")
	var upper := Catalog.chapter_place("high-and-low@1", "upper-path")
	var upper_mesh: Mesh = (display.slot_node(upper).get_node("Outline") as MeshInstance3D).mesh
	# Solo to both, together to both, and nothing to solo, in one update.
	var changed := items.duplicate(true)
	changed.append(_earned(garden, true, false))
	changed[1].friend = true
	changed[2].solo = true
	stage.set_keepsakes(changed)
	_check(display.builds == builds + 3, "Only the three changed slots rebuild")
	for id: String in display.shown_slot_ids():
		if id in [grow, relay, garden]: _check(display.slot_node(id).get_instance_id() != nodes[id], "A changed slot is rebuilt: " + id)
		else: _check(display.slot_node(id).get_instance_id() == nodes[id], "An unchanged slot keeps its nodes: " + id)
	_check_state(display.slot_node(grow), "complete", Catalog.by_id(grow))
	_check_state(display.slot_node(relay), "complete", Catalog.by_id(relay))
	_check_state(display.slot_node(garden), "solo", Catalog.by_id(garden))
	_check(display.selected_item().id in [grow, relay, garden] and stage._keepsake_title.text == display.selected_item().title, "New progress is selected and named in the box")
	var outline_again := items.duplicate(true)
	stage.set_keepsakes(outline_again)
	_check((display.slot_node(upper).get_node("Outline") as MeshInstance3D).mesh == upper_mesh and display.slot_node(garden).get_node_or_null("Outline") != null, "A rebuilt outline reuses its cached merged mesh")
	# Browsing reaches every slot and wraps.
	var seen := {}
	var start: int = display.selected_index
	for index in range(display.shown_slot_ids().size()):
		seen[display.selected_item().id] = true
		display.select_offset(1)
	_check(seen.size() == display.shown_slot_ids().size() and display.selected_index == start, "Browsing reaches every shown keepsake and wraps")
	display.select_id(light)
	stage._update_keepsake_labels()
	var together: Control = stage._keepsake_controls.find_child("KeepsakeTogether", true, false)
	if Catalog.lighthouse_together(): _check(together.visible and stage._keepsake_status.text == PlayerCopy.KEEPSAKE_NEEDS_FRIEND, "A Lighthouse keepsake finished solo now waits for a friend")
	else: _check(not together.visible and stage._keepsake_status.text == PlayerCopy.KEEPSAKE_FINISHED_SOLO, "A solo-only keepsake hides the together icon")
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

## One place's look in each state: outline with dim marks, gold keepsake with
## the solo mark, teal keepsake with the together mark, or the upgraded keepsake.
func _check_state(slot: Node3D, state: String, place: Dictionary) -> void:
	var id: String = place.id
	_check(slot.get_meta("state") == state, "Slot %s shows state %s" % [id, state])
	var prop := slot.get_node_or_null("Keepsake")
	var outline := slot.get_node_or_null("Outline")
	var upgrade := slot.get_node_or_null("Upgrade")
	var solo := slot.get_node_or_null("SoloMark")
	var together := slot.get_node_or_null("TogetherMark")
	match state:
		"none":
			_check(prop == null and outline != null and upgrade == null, "An untouched place shows only its outline: " + id)
			_check(solo != null and not solo.get_meta("lit"), "An outline shows a dim solo mark: " + id)
			if place.friend_available: _check(together != null and not together.get_meta("lit"), "An outline shows a dim together mark: " + id)
			else: _check(together == null, "A solo-only outline has no together mark: " + id)
		"solo":
			_check(prop != null and outline == null and upgrade == null and prop.get_meta("variant") == "solo", "Done solo shows the gold keepsake: " + id)
			_check(solo != null and solo.get_meta("lit") and together == null, "Done solo shows only the lit solo mark: " + id)
		"friend":
			_check(prop != null and outline == null and upgrade == null and prop.get_meta("variant") == "friend", "Done together shows the teal keepsake: " + id)
			_check(together != null and together.get_meta("lit") and solo == null, "Done together shows only the lit together mark: " + id)
		"complete":
			_check(prop != null and outline == null and solo == null and together == null, "A finished place shows its keepsake with no marks: " + id)
			_check(prop.get_meta("variant") == ("friend" if place.friend_available else "solo"), "A finished place keeps its together keepsake where one exists: " + id)
			_check(upgrade != null and upgrade.get_node_or_null("Plinth") != null and upgrade.get_node_or_null("Rim") != null and prop.position.y > 0.0, "A finished keepsake stands raised on the upgrade plinth with its gold rim: " + id)
			_check(slot.get_node_or_null("Planting") != null, "A finished keepsake has a little planting at its foot: " + id)

## A slot's footprint (keepsake and upgrade) in a frame: the island floor, or
## the terrace's own turned coordinates.
func _footprint(display: Node3D, slot: Node3D, frame: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	var to_frame := frame.affine_inverse() * display.global_transform.affine_inverse()
	for part: String in ["Keepsake", "Upgrade"]:
		var root := slot.get_node_or_null(part)
		if root == null: continue
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if not mesh.visible: continue
			var local := mesh.get_aabb()
			for index in range(8):
				var point: Vector3 = to_frame * mesh.global_transform * local.get_endpoint(index)
				if first: box = AABB(point, Vector3.ZERO)
				else: box = box.expand(point)
				first = false
	return box

## How far a slot's keepsake and upgrade reach across the floor from its centre.
func _reach(display: Node3D, slot: Node3D) -> float:
	var reach := 0.0
	var to_slot := slot.global_transform.affine_inverse()
	for part: String in ["Keepsake", "Upgrade"]:
		var root := slot.get_node_or_null(part)
		if root == null: continue
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			# The seed's glow is a camera-facing halo, not part of the footprint.
			if not mesh.visible or mesh.name == "SeedGlow" or not mesh.mesh is PrimitiveMesh: continue
			var to_floor := to_slot * mesh.global_transform
			for vertex: Vector3 in (mesh.mesh as PrimitiveMesh).get_mesh_arrays()[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = to_floor * vertex
				reach = maxf(reach, Vector2(point.x, point.z).length())
	return reach

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
		_check(display.shown_slot_ids().size() == Catalog.all().size() and Slots.ISLANDS.keys().all(func(name: String) -> bool: return display.island(name) != null and display.island(name).visible), "A full collection shows every keepsake and every keepsake island")
		# The two Home trees on the right island, trunk to crown, and the header buttons' corner.
		var trees: Array[Rect2] = []
		var tree_screens: Array[Rect2] = []
		for tree_x: float in [2.45, 3.95, -4.15, -2.65]:
			if tree_x > 0.0: trees.append(Rect2(tree_x - 0.5, -2.62 - 0.4, 1.0, 0.8))
			tree_screens.append(_screen_rect(camera, [Vector3(tree_x - 0.45, 0, -2.97), Vector3(tree_x + 0.45, 0, -2.27), Vector3(tree_x - 0.45, 1.65, -2.97), Vector3(tree_x + 0.45, 1.65, -2.27), Vector3(tree_x + 0.45, 1.65, -2.97), Vector3(tree_x - 0.45, 1.65, -2.27)]))
		var header := Rect2(size.x - 310, 0, 310, 92)
		var feet := {}
		var spirits := _screen_rect(camera, [Vector3(floor.position.x, 0, floor.position.y), Vector3(floor.end.x, 0, floor.position.y), Vector3(floor.position.x, 0, floor.end.y), Vector3(floor.end.x, 0, floor.end.y), Vector3(floor.position.x, SPIRIT_HEIGHT, floor.position.y), Vector3(floor.end.x, SPIRIT_HEIGHT, floor.position.y), Vector3(floor.position.x, SPIRIT_HEIGHT, floor.end.y), Vector3(floor.end.x, SPIRIT_HEIGHT, floor.end.y)])
		var box: Rect2 = stage._keepsake_box.get_global_rect()
		for id: String in display.slot_ids():
			var island := Slots.island_of(id)
			var terraced := not island.is_empty()
			var origin: Vector3 = display.slot_node(id).position
			var middle := Slots.island_local(island, origin) if terraced else Vector2(origin.x, origin.z)
			var reach := _reach(display, display.slot_node(id))
			var foot := Rect2(middle - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)
			var world_bounds := _footprint(display, display.slot_node(id), Transform3D.IDENTITY)
			var world_foot := Rect2(world_bounds.position.x, world_bounds.position.z, world_bounds.size.x, world_bounds.size.z)
			var corners := []
			for index in range(8): corners.append(display.to_global(world_bounds.get_endpoint(index)))
			var area := _screen_rect(camera, corners)
			if terraced: _check(Slots.island_rect(island).grow(-0.05).encloses(foot), "%s stands on the %s at %s" % [id, island, foot])
			else: _check(right.grow(-0.05).encloses(foot), "%s stands on the right island at %s" % [id, foot])
			for tree: Rect2 in trees:
				_check(not world_foot.grow(0.1).intersects(tree), "%s stays clear of the Home tree at x %.2f" % [id, tree.get_center().x])
			# The islands behind stand past the four Home trees: a crown may overlap a
			# keepsake's foot, never its middle.
			if island.begins_with("behind"):
				for tree_screen: Rect2 in tree_screens: _check(not tree_screen.has_point(area.get_center()), "%s is not hidden behind a Home tree at %s (%s vs %s)" % [id, size, area, tree_screen])
			if not terraced: _check(not area.intersects(header), "%s stays clear of the header buttons at %s" % [id, size])
			_check(not world_foot.intersects(floor.grow(0.4)), "%s stays off the spirits' walking area" % id)
			# Only keepsakes in front of the spirits' island can cover them on screen.
			if not island.begins_with("behind"): _check(not area.intersects(spirits), "%s never covers the spirits on screen at %s" % [id, size])
			_check(not area.intersects(box), "%s is not hidden by the keepsake box at %s" % [id, size])
			if not terraced: _check(stage._stage_rect().encloses(area), "%s stays in the Home stage at %s (%s in %s)" % [id, size, area, stage._stage_rect()])
			for other: String in feet:
				var gap: float = Vector2(origin.x, origin.z).distance_to(feet[other].at) - reach - feet[other].reach
				_check(gap >= 0.0, "%s does not overlap %s (gap %.2f)" % [id, other, gap])
			feet[id] = {"at": Vector2(origin.x, origin.z), "reach": reach}
		# Zoomed all the way out, the whole collection fits the stage, clear of the box and header.
		stage.zoom_target = Stage.MAX_SIZE
		stage.zoom_size = Stage.MAX_SIZE
		stage._frame_camera()
		for id: String in display.slot_ids():
			var bounds := _footprint(display, display.slot_node(id), Transform3D.IDENTITY)
			var corners := []
			for index in range(8): corners.append(display.to_global(bounds.get_endpoint(index)))
			var area := _screen_rect(camera, corners)
			_check(stage._stage_rect().encloses(area) and not area.intersects(box) and not area.intersects(header), "%s fits the stage at the widest zoom at %s (%s)" % [id, size, area])
		stage.free()
		home.viewport.free()
		await process_frame

func _check_tap() -> void:
	var none: Array[Dictionary] = []
	var home := await _home(Vector2i(1280, 720), none)
	var stage: Control = home.stage
	var display: Node3D = home.display
	var camera: Camera3D = home.world.camera
	_check(display.shown_slot_ids().size() == 2 and Slots.ISLANDS.keys().all(func(name: String) -> bool: return display.island(name) == null), "With nothing earned only First Steps shows its outlines")
	var target := Catalog.chapter_place("first-steps@1", "a-place-to-grow")
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
	_check(total == Catalog.variant_total() and total == 2 * Catalog.all().size(), "The collection total is every place solo plus together" + context)
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

## Explore mode walks the gold spirit with the joystick, the camera follows,
## nearby keepsakes are named, and Back restores the normal Home.
func _check_explore() -> void:
	var all: Array[Dictionary] = []
	for place: Dictionary in Catalog.all(): all.append(_earned(place.id, true, true))
	for size: Vector2i in [Vector2i(1560, 720), Vector2i(1280, 720), Vector2i(1600, 720)]:
		var home := await _home(size, all)
		var stage: Control = home.stage
		var world: Node3D = home.world
		var display: Node3D = home.display
		var context := " at %s" % size
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		var menu := Control.new()
		home.viewport.add_child(menu)
		var box: Rect2 = stage._keepsake_box.get_global_rect()
		var button: Button = stage._explore_button
		_check(button.is_visible_in_tree() and button.text == PlayerCopy.HOME_EXPLORE and screen.encloses(button.get_global_rect()) and not button.get_global_rect().intersects(box) and button.size.y >= 48.0, "The Explore button sits on screen, clear of the box" + context)
		var spirit: Node3D = world.actors.a
		var start := spirit.position
		button.pressed.emit()
		var stick: Control = stage._stick
		var back: Button = stage._explore_back
		box = stage._keepsake_box.get_global_rect()
		_check(stage.is_exploring() and not menu.visible and back.is_visible_in_tree() and stick.is_visible_in_tree() and not button.is_visible_in_tree(), "Explore hides the menu and shows Back and the joystick" + context)
		_check(screen.encloses(stick.get_global_rect()) and screen.encloses(back.get_global_rect()) and not stick.get_global_rect().intersects(box) and not back.get_global_rect().intersects(box) and back.text == PlayerCopy.HOME_EXPLORE_BACK, "Back and the joystick sit on screen, clear of the box" + context)
		stick.value = Vector2(1, 0)
		for frame in range(45): stage._process(1.0 / 30.0)
		_check(spirit.position.distance_to(start) > 1.0 and display.walkable(spirit.position), "The joystick walks the spirit on solid ground" + context)
		_check(stage._stage_rect().grow(-40).has_point(world.camera.unproject_position(spirit.global_position)), "The camera follows the spirit" + context)
		stick.value = Vector2(-1, 1)
		var always_solid := true
		for frame in range(240):
			stage._process(1.0 / 30.0)
			always_solid = always_solid and display.walkable(spirit.position)
		_check(always_solid, "The spirit never walks off the islands" + context)
		var target := Catalog.chapter_place("relay-isles@2", "relay")
		var slot: Vector3 = display.slot_node(target).position
		stick.value = Vector2.ZERO
		spirit.position = slot + (Vector3(3.35, 0, 0.35) - slot).normalized() * 0.6
		stage._process(1.0 / 30.0)
		_check(display.selected_item().id == target and stage._keepsake_title.text == Catalog.by_id(target).title and stage._keepsake_status.text == PlayerCopy.KEEPSAKE_FINISHED, "Walking up to a keepsake names it with its progress" + context)
		world.reduced_motion = true
		stick.value = Vector2(0, -1)
		stage._process(1.0 / 30.0)
		_check(stage._explore_focus == spirit.position and stage.zoom_size == stage.EXPLORE_SIZE, "With reduced motion the camera stays exactly on the spirit" + context)
		world.reduced_motion = false
		back.pressed.emit()
		_check(not stage.is_exploring() and menu.visible and spirit.position == start and stage.zoom_target == Stage.DEFAULT_SIZE and button.is_visible_in_tree() and not stick.is_visible_in_tree(), "Back returns to the normal Home, the menu and the spirit where it was" + context)
		stage.free()
		home.viewport.free()
		await process_frame

## Steps the stage and the world together, as one frame of the running app.
func _frames(stage: Control, world: Node3D, count: int, step: float = 1.0 / 30.0) -> void:
	for frame in range(count):
		stage._process(step)
		world._process(step)

## Joystick push that walks the explorer along a world direction.
func _push_toward(direction: Vector3) -> Vector2:
	var across := Vector3(0.832, 0, -0.555)
	var away := Vector3(-0.555, 0, -0.832)
	return Vector2(direction.dot(across), -direction.dot(away))

## True when every Home bridge plank is drawn lower than this.
func _bridge_below(world: Node3D, height: float) -> bool:
	return world.bridge_parts.all(func(plank: Node3D) -> bool: return plank.position.y < height)

## The Home bridge rests lowered and carries nobody; exploring raises it as the
## spirit comes near, and every frame each plank carries the spirit only once
## it is drawn up. Walking away lets it down again. A keepsake island's bridge
## is closed while its island is hidden, and never lowers.
func _check_explore_bridge() -> void:
	var all: Array[Dictionary] = []
	for place: Dictionary in Catalog.all(): all.append(_earned(place.id, true, true))
	var home := await _home(Vector2i(1560, 720), all)
	var stage: Control = home.stage
	var world: Node3D = home.world
	var display: Node3D = home.display
	var level: Dictionary = world.current_level
	var gap: Array = level.get("gap", [-100, 100])
	var left := float(gap[0]) / 100.0
	var right := float(gap[1]) / 100.0
	var bridge_z := float(level.get("bridge", {}).get("z", 0)) / 100.0
	var middle := Vector3((left + right) * 0.5, 0, bridge_z)
	var deck: float = World.BRIDGE_RAISED_Y
	var planks: Array = world.bridge_parts
	_frames(stage, world, 30)
	_check(planks.size() == 9 and _bridge_below(world, -0.5) and not world.bridge_ready, "Home shows its bridge lowered")
	_check(not display.walkable(middle) and display.walkable(Vector3(left - 0.6, 0, bridge_z)) and display.walkable(Vector3(right + 0.6, 0, bridge_z)), "A lowered bridge carries nobody, while both shores stay ground")
	var spirit: Node3D = world.actors.a
	stage._explore_button.pressed.emit()
	spirit.position = Vector3(left - 3.2, 0, bridge_z)
	_frames(stage, world, 20)
	_check(not world.home_bridge_raised and _bridge_below(world, -0.5) and not display.walkable(middle), "Exploring leaves the bridge down while the spirit is far from it")
	stage._stick.value = _push_toward(Vector3.RIGHT)
	var matches := true
	var on_air := false
	var rising_blocked := false
	var raised_at := -1
	var crossed_at := -1
	for frame in range(160):
		_frames(stage, world, 1)
		if raised_at < 0 and world.home_bridge_raised: raised_at = frame
		for index in range(planks.size()):
			var over := Vector3(lerpf(left, right, (index + 0.5) / planks.size()), 0, bridge_z)
			var up: bool = planks[index].position.y >= deck - Display.DECK_TOLERANCE
			matches = matches and display.walkable(over) == up
			if world.home_bridge_raised and not up and not display.walkable(over): rising_blocked = true
		if spirit.position.x > left and spirit.position.x < right:
			var under: Node3D = planks[mini(int((spirit.position.x - left) / (right - left) * planks.size()), planks.size() - 1)]
			if under.position.y < deck - Display.DECK_TOLERANCE: on_air = true
		if spirit.position.x > right + 0.3:
			crossed_at = frame
			break
	stage._stick.value = Vector2.ZERO
	_check(matches, "Every frame each bridge plank carries the spirit exactly when it is drawn up")
	_check(raised_at >= 0 and rising_blocked, "The bridge rises as the spirit comes near, and a rising plank carries nobody")
	_check(not on_air, "The spirit never stands over a plank that is not drawn up")
	_check(crossed_at > raised_at and display.walkable(spirit.position), "Once risen, the bridge carries the spirit to the other island")
	# Walking well away lets the bridge down; between the two distances it keeps its state.
	spirit.position = Vector3(right + 3.0, 0, bridge_z - 2.0)
	_frames(stage, world, 30)
	_check(not world.home_bridge_raised and _bridge_below(world, -0.5) and not display.walkable(middle), "Walking away lets the bridge back down")
	var notice: float = stage.BRIDGE_NOTICE
	var release: float = stage.BRIDGE_RELEASE
	var between := Vector3(left - Display.CROSSING_PAD - (notice + release) * 0.5, 0, bridge_z)
	spirit.position = between
	_frames(stage, world, 5)
	_check(not world.home_bridge_raised, "Between the notice and release distances a lowered bridge stays down")
	spirit.position = Vector3(left - Display.CROSSING_PAD - notice * 0.5, 0, bridge_z)
	_frames(stage, world, 5)
	spirit.position = between
	_frames(stage, world, 5)
	_check(world.home_bridge_raised, "Between the notice and release distances a raised bridge stays up")
	stage._explore_back.pressed.emit()
	_frames(stage, world, 30)
	_check(not world.home_bridge_raised and _bridge_below(world, -0.5) and not display.walkable(middle), "Leaving Explore lets the bridge back down")
	# A bridge already drawn up, as a chapter can leave it, stays up and carries.
	world.bridge_ready = true
	_frames(stage, world, 30)
	_check(display.walkable(middle), "A bridge the world already shows raised carries the spirit")
	world.bridge_ready = false
	stage.free()
	home.viewport.free()
	await process_frame
	# Keepsake islands: a hidden island's bridge is closed, a shown one's is open.
	var none: Array[Dictionary] = []
	home = await _home(Vector2i(1560, 720), all)
	stage = home.stage
	world = home.world
	display = home.display
	var island_name := "behind_left"
	var island: Node3D = display.island(island_name)
	var walk: Node3D = island.get_node("Bridge") if island != null else null
	if walk == null:
		_check(false, "The %s island and its bridge exist once its keepsakes show" % island_name)
	else:
		var length: float = walk.get_meta("length")
		var on_bridge: Vector3 = walk.transform * Vector3(0, 0, -length * 0.5)
		_check(island.visible and display.walkable(on_bridge), "A shown keepsake island's bridge carries the spirit")
		stage.set_keepsakes(none)
		_check(not island.visible and not display.walkable(on_bridge), "A hidden keepsake island's bridge is closed")
		stage._explore_button.pressed.emit()
		var walker: Node3D = world.actors.a
		walker.position = walk.transform * Vector3(0, 0, Display.CROSSING_PAD + 0.1)
		stage._stick.value = _push_toward(-walk.transform.basis.z)
		var stayed := true
		for frame in range(40):
			_frames(stage, world, 1)
			stayed = stayed and -(walk.transform.affine_inverse() * walker.position).z <= 0.0
		stage._stick.value = Vector2.ZERO
		var level_planks := walk.get_children().filter(func(node: Node) -> bool: return str(node.name).begins_with("Plank"))
		_check(stayed and display.walkable(walker.position), "The spirit cannot step onto a closed keepsake bridge")
		_check(not level_planks.is_empty() and level_planks.all(func(plank: Node3D) -> bool: return is_equal_approx(plank.position.y, Display.PLANK_DECK_Y)), "A keepsake island's bridge never lowers")
	stage.free()
	home.viewport.free()
	await process_frame

## The keepsake paging arrows show on the normal Home only. Every way in and
## out of Explore keeps them right: the Explore and Back buttons, the system
## Back, a pause and resume, a pop-up over Home, and Home closing mid-Explore.
func _check_explore_arrows() -> void:
	var all: Array[Dictionary] = []
	for place: Dictionary in Catalog.all(): all.append(_earned(place.id, true, true))
	for size: Vector2i in [Vector2i(1560, 720), Vector2i(1600, 720)]:
		var context := " at %s" % size
		var home := await _home(size, all)
		var stage: Control = home.stage
		var world: Node3D = home.world
		var menu := Control.new()
		home.viewport.add_child(menu)
		var previous: Button = stage._keepsake_controls.get_node("KeepsakePrevious")
		var next: Button = stage._keepsake_controls.get_node("KeepsakeNext")
		var arrows := func() -> bool: return previous.is_visible_in_tree() and next.is_visible_in_tree()
		var hidden := func() -> bool: return not previous.is_visible_in_tree() and not next.is_visible_in_tree()
		_check(arrows.call(), "The normal Home shows the keepsake arrows" + context)
		stage._explore_button.pressed.emit()
		_check(stage.is_exploring() and hidden.call() and stage._keepsake_title.is_visible_in_tree(), "Explore hides the keepsake arrows and keeps the keepsake name" + context)
		var some: Array[Dictionary] = [all[0]]
		stage.set_keepsakes(some)
		_frames(stage, world, 2)
		_check(hidden.call(), "New keepsake progress while exploring keeps the arrows hidden" + context)
		stage.set_keepsakes(all)
		# Home's own refresh turning part of the menu back on does not stick.
		menu.visible = true
		_frames(stage, world, 1)
		_check(not menu.visible, "The menu stays hidden while exploring" + context)
		# Pause and resume: still exploring, arrows hidden, a held joystick let go.
		stage._stick.value = Vector2(1, 0)
		stage._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		stage._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		_frames(stage, world, 2)
		_check(stage.is_exploring() and hidden.call() and stage._stick.value == Vector2.ZERO, "A pause and resume keeps Explore without the arrows and lets go of the joystick" + context)
		# A pop-up over Home leaves Explore as it was.
		var host := Control.new()
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		home.viewport.add_child(host)
		var popup: Control = InGameModal.open(host, "TestPopup", "Pop-up")
		_frames(stage, world, 2)
		_check(stage.is_exploring() and hidden.call() and popup.is_visible_in_tree(), "A pop-up over Explore keeps the arrows hidden" + context)
		popup.free()
		host.free()
		stage._explore_back.pressed.emit()
		_check(not stage.is_exploring() and arrows.call() and menu.visible, "Back brings the arrows and the menu back" + context)
		# The system Back leaves Explore too.
		stage._explore_button.pressed.emit()
		root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		_check(not stage.is_exploring() and arrows.call() and menu.visible and stage._explore_button.is_visible_in_tree(), "The system Back leaves Explore and brings the arrows back" + context)
		# Home closing mid-Explore (another screen replacing it) restores the
		# menu and the bridge, and the next Home opens at the earlier zoom.
		stage._explore_button.pressed.emit()
		world.home_bridge_raised = true
		home.viewport.remove_child(stage)
		_check(menu.visible and not world.home_bridge_raised and is_equal_approx(float(Stage._retained_view.get("zoom_target", 0.0)), Stage.DEFAULT_SIZE), "Home closing mid-Explore restores the menu, the bridge and the zoom" + context)
		stage.free()
		var again := Stage.new()
		again.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		again.configure(world, func() -> bool: return true, all)
		home.viewport.add_child(again)
		_check(not again.is_exploring() and again._keepsake_controls.get_node("KeepsakePrevious").is_visible_in_tree() and again._keepsake_controls.get_node("KeepsakeNext").is_visible_in_tree(), "Home opened again shows the arrows" + context)
		again.free()
		home.viewport.free()
		await process_frame
