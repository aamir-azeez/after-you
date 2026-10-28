extends SceneTree
## Home's keepsakes on the islands (presentation/home_keepsake_layer.gd): one
## per chapter card, each on its own island, off the spirits' start spots and
## clear of the trees, the header buttons, the card and each other; still parts
## folded and moving parts kept; a burst of changes rebuilt once; taps, repeat
## taps, Reduce motion, leaving Home mid tap and Explore walk ups; the card's
## lines, marks and count; the Home bridge in Explore.
const World = preload("res://presentation/island_world.gd")
const Stage = preload("res://presentation/home_stage.gd")
const Layer = preload("res://presentation/home_keepsake_layer.gd")
const States = preload("res://services/home_keepsake_states.gd")
const Card = preload("res://presentation/keepsakes/keepsake_card.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const Levels = preload("res://core/levels.gd")
const Main = preload("res://main.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const HardMode = preload("res://services/hard_mode.gd")
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
	await _check_states_and_updates()
	await _check_layout_clearance()
	await _check_fold()
	await _check_tap()
	await _check_play()
	await _check_explore()
	await _check_explore_bridge()
	await _check_explore_arrows()
	for size: Vector2i in [Vector2i(1560, 720), Vector2i(1280, 720), Vector2i(1600, 720)]:
		for state: String in ["none", "few", "pair", "all"]:
			await _box_state(size, state)
		var heights: Array = box_heights.values()
		_check(heights.size() == 4 and heights.all(func(height: float) -> bool: return absf(height - heights[0]) <= 0.5), "The keepsake box keeps one height in every state at %s: %s" % [size, box_heights])
		box_heights.clear()
	print("HOME KEEPSAKE LAYER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A world, a Home stage over it and the stage's layer.
func _home(size: Vector2i, items: Array[Dictionary], hard: Dictionary = {}, together_hard: bool = true) -> Dictionary:
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
	stage.set_hard(hard, together_hard)
	viewport.add_child(stage)
	stage.set_process(false)
	for frame in range(6):
		await process_frame
		stage._process(0)
	return {"viewport": viewport, "world": world, "stage": stage, "layer": stage._keepsake_layer}

func _close(home: Dictionary) -> void:
	if is_instance_valid(home.stage): home.stage.free()
	home.viewport.free()
	await process_frame

## The ledger marks for every stage of a chapter (or an earlier island).
func _cleared(level: String, solo: bool, friend: bool, into: Array[Dictionary] = []) -> Array[Dictionary]:
	for item: Dictionary in Catalog.all():
		if item.family != level: continue
		var earned := item.duplicate(true)
		earned.solo = solo
		earned.friend = friend and item.friend_available
		into.append(earned)
	return into

func _everything() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for item: Dictionary in Catalog.all():
		var earned := item.duplicate(true)
		earned.solo = true
		earned.friend = item.friend_available
		all.append(earned)
	return all

func _all_hard() -> Dictionary:
	var hard := {}
	for key: String in HardMode.eligible_keys(): hard[key] = {"solo": true, "together": true}
	return hard

## Waits for the layer's pending rebuild and fold.
func _settle(layer: Node3D) -> void:
	var until := Time.get_ticks_msec() + 8000
	while layer.settling() and Time.get_ticks_msec() < until: await process_frame

func _check_states_and_updates() -> void:
	var items: Array[Dictionary] = _cleared("first-steps", true, false)
	_cleared("relay-isles", true, true, items)
	var home := await _home(Vector2i(960, 540), items, {"first-steps@1": {"solo": true, "together": false}})
	var world: Node3D = home.world
	var stage: Control = home.stage
	var layer: Node3D = home.layer
	await _settle(layer)
	_check(is_instance_valid(layer) and layer.get_parent() == world.terrain and layer.name == "HomeKeepsakes", "Keepsakes stand on the Home island itself")
	_check(layer.shown_ids() == ["first-steps", "relay-isles", "high-and-low"], "Two keepsakes and the next outline show: %s" % [layer.shown_ids()])
	var lift: Node3D = layer.prop_node("first-steps")
	var next: Node3D = layer.prop_node("high-and-low")
	_check(lift != null and lift.find_child("Footing", true, false) != null and layer.parts_of("first-steps").has("lift"), "The Bell Lift stands on its Hard footing with its moving lift")
	_check(next != null and next.get_node_or_null("Outline") != null and layer.parts_of("high-and-low").is_empty(), "The next keepsake is an outline with nothing to move")
	var veil := next.get_node("Outline") as MeshInstance3D
	_check(veil.mesh.get_surface_count() == 1 and veil.material_override.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and veil.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "An outline is one merged mesh with the see-through veil")
	_check(stage._keepsake_count.text == "Keepsakes 2 / %d · Upgrades 2 / %d · Hard 1 / 10" % [States.entries().size(), States.states(States.entries(), [], {}, true).upgrades[1]], "The count line: %s" % stage._keepsake_count.text)
	# Unchanged marks rebuild nothing, even as fresh copies, and a burst rebuilds once.
	var builds: int = layer.builds
	for repeat in range(4): stage.set_keepsakes(items.duplicate(true))
	await _settle(layer)
	_check(layer.builds == builds and layer.prop_node("first-steps") == lift, "Unchanged marks rebuild nothing")
	var more := items.duplicate(true)
	_cleared("high-and-low", true, false, more)
	stage.set_keepsakes(more)
	var most := more.duplicate(true)
	_cleared("the-wishing-well", false, true, most)
	stage.set_keepsakes(most)
	_check(layer.builds == builds and layer.prop_node("first-steps") == lift, "The props wait while a burst of awards arrives")
	await _settle(layer)
	_check(layer.builds == builds + 1, "A burst of changes rebuilds the set once: %d" % (layer.builds - builds))
	_check(layer.prop_node("the-wishing-well") != null and layer.parts_of("the-wishing-well").has("bucket"), "The new keepsake stands once the set swaps in")
	_check(not is_instance_valid(lift), "The old set goes with the swap")
	_check(layer.find_children("Props", "Node3D", false, false).size() == 1, "Only one set of props stays")
	_check(stage._keepsake_title.text == PlayerCopy.KEEPSAKE_WISHING_WELL_NAME, "New progress is selected and named on the card")
	_check(stage._keepsake_status.text == PlayerCopy.KEEPSAKE_WANTS_HARD_TOGETHER % PlayerCopy.KEEPSAKE_WISHING_WELL_HARD, "Cleared with a friend, the card names the Hard piece next: " + stage._keepsake_status.text)
	# Browsing reaches every shown keepsake and wraps.
	var seen := {}
	var start: int = layer.selected_index
	for index in range(layer.shown_ids().size()):
		seen[layer.selected_item().id] = true
		layer.select_offset(1)
	_check(seen.size() == layer.shown_ids().size() and layer.selected_index == start, "Browsing reaches every shown keepsake and wraps")
	var highlight: Node3D = layer.get_node("SelectedSlot")
	layer.select_id("relay-isles")
	_check(is_equal_approx(highlight.position.x, layer.slot_transform("relay-isles").origin.x), "The selected keepsake is marked on the island")
	var glass: Dictionary = States.entries().filter(func(entry: Dictionary) -> bool: return entry.id == "conservatory")[0]
	_check(Card.line(glass, {"look": "started", "stages": [[true, false], [false, true]]}, true) == PlayerCopy.KEEPSAKE_MIXED and Card.line(glass, {"look": "started", "stages": [[true, false], [false, false]]}, true) == PlayerCopy.KEEPSAKE_STARTED % [1, 2, "Conservatory"], "Every stage done in mixed modes says how to earn it")
	var definition_before := JSON.stringify(world.current_level)
	_check(JSON.stringify(world.current_level) == definition_before and not world.garden.visible, "Home clears the gameplay garden while it owns the island")
	var garden: Node3D = world.garden
	stage.free()
	await process_frame
	_check(garden.visible and world.home_presentation_owner == 0, "Leaving Home restores gameplay props")
	home.viewport.free()
	await process_frame

func _screen_rect(camera: Camera3D, corners: Array) -> Rect2:
	var rect := Rect2(camera.unproject_position(corners[0]), Vector2.ZERO)
	for corner: Vector3 in corners: rect = rect.expand(camera.unproject_position(corner))
	return rect

## A keepsake's screen area: its ground, up to its tallest part.
func _screen_area(layer: Node3D, camera: Camera3D, id: String) -> Rect2:
	var corners := []
	for corner: Vector2 in layer.ground(id):
		for height: float in [0.0, 1.75]: corners.append(layer.to_global(Vector3(corner.x, height, corner.y)))
	return _screen_rect(camera, corners)

func _polygons_meet(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return not Geometry2D.intersect_polygons(a, b).is_empty()

func _check_layout_clearance() -> void:
	for size: Vector2i in [Vector2i(1560, 720), Vector2i(1280, 720), Vector2i(1600, 720)]:
		var home := await _home(size, _everything(), _all_hard())
		var stage: Control = home.stage
		var layer: Node3D = home.layer
		var camera: Camera3D = home.world.camera
		var context := " at %s" % size
		_check(layer.shown_ids().size() == States.entries().size(), "Everything earned shows every keepsake" + context)
		var trees: Array[PackedVector2Array] = []
		for tree_x: float in [2.45, 3.95, -4.15, -2.65]:
			trees.append(PackedVector2Array([Vector2(tree_x - 0.5, -3.02), Vector2(tree_x + 0.5, -3.02), Vector2(tree_x + 0.5, -2.22), Vector2(tree_x - 0.5, -2.22)]))
		var header := Rect2(size.x - 310, 0, 310, 92)
		var box: Rect2 = stage._keepsake_box.get_global_rect()
		var floor: Rect2 = stage._floor
		var spots: Array[Vector2] = [floor.get_center() + Vector2(-0.68, 0.42), floor.get_center() + Vector2(0.68, -0.42)]
		var grounds := {}
		for id: String in layer.shown_ids():
			var entry: Dictionary = States.entries()[States.entries().map(func(item: Dictionary) -> String: return item.id).find(id)]
			var ground: PackedVector2Array = layer.ground(id)
			var island: Rect2 = layer.island_floor(str(entry.keepsake.island))
			_check(Array(ground).all(func(corner: Vector2) -> bool: return island.grow(0.2).has_point(corner)), "%s stands on the %s island" % [id, entry.keepsake.island])
			for tree: PackedVector2Array in trees: _check(not _polygons_meet(ground, tree), "%s stays clear of the Home trees" % id)
			for spot: Vector2 in spots: _check(layer.distance(id, Vector3(spot.x, 0, spot.y)) >= Stage.SPIRIT_CLEARANCE, "%s stays off the spirits' start spot %s" % [id, spot])
			for other: String in grounds: _check(not _polygons_meet(ground, grounds[other]), "%s stands apart from %s at full size" % [id, other])
			grounds[id] = ground
			var area := _screen_area(layer, camera, id)
			_check(not area.intersects(header), "%s stays clear of the header buttons%s" % [id, context])
			_check(not area.intersects(box), "%s is not hidden by the card%s (%s vs %s)" % [id, context, area, box])
			_check(stage._stage_rect().encloses(area), "%s stays in the Home stage%s (%s in %s)" % [id, context, area, stage._stage_rect()])
		await _close(home)

## Still parts fold into a few shared batches; moving parts keep their own
## nodes; the budget holds with every upgrade on every keepsake.
func _check_fold() -> void:
	var home := await _home(Vector2i(1560, 720), _everything(), _all_hard())
	var layer: Node3D = home.layer
	await _settle(layer)
	var props: Node3D = layer.find_children("Props", "Node3D", false, false)[0]
	var batches := props.find_children("StaticBatch*", "MeshInstance3D", true, false)
	_check(batches.size() > 5, "Still parts fold into shared batches: %d" % batches.size())
	var draws := 0
	var triangles := 0
	for node: Node in props.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		draws += mesh.mesh.get_surface_count()
		triangles += mesh.mesh.get_faces().size() / 3
	print("HOME KEEPSAKE LAYER: every upgrade on every keepsake folds to %d meshes and %d triangles" % [draws, triangles])
	_check(draws <= 130 and triangles <= 32000, "All eleven with every upgrade stay in budget: %d draws, %d triangles" % [draws, triangles])
	for id: String in layer.shown_ids():
		for part: Variant in layer.parts_of(id).values():
			if not part is Node3D: continue
			_check(is_instance_valid(part) and (part as Node).is_inside_tree() and props.is_ancestor_of(part), "%s keeps its moving part %s" % [id, (part as Node).name])
			for batch: Node in batches: _check(not (batch as Node).is_ancestor_of(part), "A moving part is never inside a batch")
	await _close(home)

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

func _point(layer: Node3D, camera: Camera3D, id: String) -> Vector2:
	return camera.unproject_position(layer.to_global(layer.slot_transform(id) * Vector3(0, 0.45, 0)))

func _check_tap() -> void:
	var items: Array[Dictionary] = _cleared("first-steps", true, false)
	var home := await _home(Vector2i(1280, 720), items)
	var stage: Control = home.stage
	var layer: Node3D = home.layer
	var camera: Camera3D = home.world.camera
	await _settle(layer)
	var point := _point(layer, camera, "first-steps")
	_check(layer.pick(camera, point) == "first-steps", "A keepsake's own point picks it")
	layer.select_id("relay-isles")
	_stage_tap(stage, point)
	_check(layer.selected_item().id == "first-steps" and stage._keepsake_title.text == PlayerCopy.KEEPSAKE_BELL_LIFT_NAME and stage._greeting_left == 0.0, "Tapping a keepsake names it on the card without greeting the spirits")
	_check(stage.keepsake_playing(), "Tapping an earned keepsake plays it")
	layer.stop_play()
	var outline := _point(layer, camera, "relay-isles")
	_stage_tap(stage, outline)
	_check(layer.selected_item().id == "relay-isles" and not stage.keepsake_playing(), "Tapping an outline names it and plays nothing")
	_check(stage._keepsake_status.text == PlayerCopy.KEEPSAKE_NEXT % "The Relay Isles", "The next outline says which chapter earns it: " + stage._keepsake_status.text)
	_stage_touch(stage, 0, point, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = point + Vector2(60, 0)
	stage._input(drag)
	_stage_touch(stage, 0, point + Vector2(60, 0), false)
	_check(layer.selected_item().id == "relay-isles" and not stage.keepsake_playing(), "Dragging from a keepsake stays a camera gesture")
	var spirit: Vector2 = camera.unproject_position(home.world.actors.a.to_global(Vector3(0, 0.55, 0)))
	_check(layer.pick(camera, spirit).is_empty(), "No keepsake sits under a spirit, so spirit taps still greet")
	_check(layer.pick(camera, stage._stage_rect().position + Vector2(8, 8)).is_empty(), "Empty sky picks nothing")
	await _close(home)

## The rest pose of every moving part, to compare after a tap.
func _pose(layer: Node3D, id: String) -> Array:
	var pose: Array = []
	for part: Variant in layer.parts_of(id).values():
		if part is Node3D:
			pose.append([(part as Node3D).transform, (part as Node3D).visible])
			for child: Node in (part as Node).get_children():
				if child is MeshInstance3D: pose.append((child as MeshInstance3D).material_override)
			if part is MeshInstance3D: pose.append((part as MeshInstance3D).material_override)
	return pose

func _tweens() -> int:
	return get_processed_tweens().size()

func _check_play() -> void:
	var home := await _home(Vector2i(1280, 720), _everything(), _all_hard())
	var stage: Control = home.stage
	var world: Node3D = home.world
	var layer: Node3D = home.layer
	await _settle(layer)
	var cues: Array = []
	stage.play_cue = func(cue: String) -> void: cues.append(cue)
	for id: String in layer.shown_ids():
		var rest := _pose(layer, id)
		var tap_start := Time.get_ticks_msec()
		cues.clear()
		_check(stage.play_keepsake(id) and stage.keepsake_playing(), "%s plays" % id)
		_check(not stage.play_keepsake(id), "A second tap while %s plays is ignored" % id)
		var moved := false
		var asked := false
		while stage.keepsake_playing() and Time.get_ticks_msec() - tap_start < 6000:
			await process_frame
			moved = moved or _pose(layer, id) != rest
			if not asked and Time.get_ticks_msec() - tap_start > 1000:
				asked = true
				_check(not stage.play_keepsake(id), "A tap halfway through %s neither stacks nor restarts it" % id)
		_check(moved, "%s moves its parts while it plays" % id)
		_check(not stage.keepsake_playing() and Time.get_ticks_msec() - tap_start <= 4700, "%s finishes within four and a half seconds" % id)
		await process_frame
		_check(_pose(layer, id) == rest, "%s ends in exactly its rest pose" % id)
		var keepsake: Dictionary = States.entries()[States.entries().map(func(entry: Dictionary) -> String: return entry.id).find(id)].keepsake
		_check(cues.size() == keepsake.sounds.size() and cues == keepsake.sounds.values(), "%s plays one fixed cue per beat: %s" % [id, cues])
		_check(layer.prop_node(id).get_node_or_null("Tap") == null, "%s frees what it made for the tap" % id)
	# Reduce motion: parts jump to the lit pose, hold, and go back; nothing slides.
	world.reduced_motion = true
	var well_rest := _pose(layer, "the-wishing-well")
	stage.play_keepsake("the-wishing-well")
	var lit := _pose(layer, "the-wishing-well")
	await create_timer(0.3).timeout
	_check(_pose(layer, "the-wishing-well") == lit, "With Reduce motion nothing slides: the lit pose holds")
	await create_timer(0.9).timeout
	_check(not stage.keepsake_playing() and _pose(layer, "the-wishing-well") == well_rest, "and after a moment everything is back at rest")
	world.reduced_motion = false
	# A tap on another keepsake ends the first in its rest pose and plays the new one.
	var well_pose := _pose(layer, "the-wishing-well")
	stage.play_keepsake("the-wishing-well")
	await create_timer(1.0).timeout
	_check(stage.play_keepsake("first-steps") and _pose(layer, "the-wishing-well") == well_pose, "A tap on another keepsake while one plays puts the first at rest and plays the new one")
	layer.stop_play()
	# A keepsake earned while Home is open plays once its set is drawn, never as an outline.
	var partial: Array[Dictionary] = _cleared("first-steps", true, false)
	stage.set_hard({}, true)
	stage.set_keepsakes(partial)
	await _settle(layer)
	var earned: Array[Dictionary] = partial.duplicate(true)
	_cleared("relay-isles", true, false, earned)
	stage.set_keepsakes(earned)
	layer.select_id("relay-isles")
	_check(not layer.playable("relay-isles"), "A keepsake still drawn as an outline is not playable")
	_check(not stage.play_keepsake("relay-isles"), "A keepsake still drawn as an outline does not play: %s" % [layer.selected_item()])
	_check(not layer.selected_item().playable and layer.selected_item().id == "relay-isles", "and offers no action: %s" % [layer.selected_item()])
	await _settle(layer)
	_check(layer.playable("relay-isles") and stage.play_keepsake("relay-isles"), "and plays once its rebuilt set is drawn")
	layer.stop_play()
	stage.set_hard(_all_hard(), true)
	stage.set_keepsakes(_everything())
	await _settle(layer)
	# A state change during a tap waits for it to end.
	var builds: int = layer.builds
	stage.play_keepsake("the-wishing-well")
	var some: Array[Dictionary] = _cleared("first-steps", true, false)
	stage.set_keepsakes(some)
	await create_timer(1.0).timeout
	_check(layer.builds == builds and stage.keepsake_playing(), "A rebuild waits while a keepsake plays")
	await _settle(layer)
	_check(layer.builds == builds + 1 and not stage.keepsake_playing(), "and comes once the tap has ended")
	# Leaving Home mid tap leaves no Tween behind.
	stage.set_keepsakes(_everything())
	await _settle(layer)
	stage.play_keepsake("sleeping-lighthouse")
	await create_timer(0.3).timeout
	_check(_tweens() > 0, "A tap runs a Tween")
	stage.free()
	await process_frame
	await process_frame
	_check(_tweens() == 0, "Leaving Home mid tap leaves no Tween")
	home.viewport.free()
	await process_frame

## The box holds the browser, a status line and the count, at one height.
func _box_state(size: Vector2i, state: String) -> void:
	var items: Array[Dictionary] = []
	var hard := {}
	match state:
		"few": _cleared("first-steps", true, false, items)
		"pair":
			_cleared("first-steps", true, true, items)
			hard = {"first-steps@1": {"solo": true, "together": false}}
		"all":
			items = _everything()
			hard = _all_hard()
	var home := await _home(size, items, hard)
	var stage: Control = home.stage
	var layer: Node3D = home.layer
	var context := " (%s, %s)" % [state, size]
	var box: Control = stage._keepsake_box
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	var box_rect := box.get_global_rect()
	var hint_rect: Rect2 = stage._hint.get_global_rect()
	_check(box.is_visible_in_tree() and screen.encloses(box_rect) and screen.encloses(hint_rect), "Box and hint stay on screen" + context)
	_check(not box_rect.intersects(hint_rect), "The box never meets the bottom-right hint" + context)
	_check(box_rect.position.x >= stage._stage_rect().position.x - 0.5 and absf(box_rect.get_center().x - stage._stage_rect().get_center().x) <= 1.0, "The box is centred in the island stage" + context)
	box_heights[state] = box_rect.size.y
	var count: Label = stage._keepsake_count
	var status: Label = stage._keepsake_status
	_check(count.is_visible_in_tree() and count.get_global_rect().size.x <= box_rect.size.x, "The count fits the box" + context)
	var font := count.get_theme_font("font")
	_check(font.get_string_size(layer.widest_count(), HORIZONTAL_ALIGNMENT_LEFT, -1, count.get_theme_font_size("font_size")).x <= stage._keepsake_count.custom_minimum_size.x + 0.5, "The widest count line fits on one line" + context)
	_check(status.is_visible_in_tree() and status.text in layer.every_line() and status.get_global_rect().end.y <= count.get_global_rect().position.y + 0.5, "A status line sits above the count: %s%s" % [status.text, context])
	match state:
		"none":
			_check(count.text == PlayerCopy.KEEPSAKE_COUNT % [0, States.entries().size()] and status.text == PlayerCopy.KEEPSAKE_NEXT % "First Steps", "With nothing earned the card points at the first chapter" + context)
		"pair":
			stage.select_keepsake("first-steps")
			_check(status.text == PlayerCopy.KEEPSAKE_WANTS_TOP % PlayerCopy.KEEPSAKE_BELL_LIFT_TOP, "Cleared together and on Hard, the card asks for Hard with a friend: %s%s" % [status.text, context])
		"all":
			_check(status.text == PlayerCopy.KEEPSAKE_DONE % PlayerCopy.KEEPSAKE_BELL_LIFT_ACTION.to_lower() or status.text.begins_with(PlayerCopy.KEEPSAKE_DONE.get_slice("%", 0)), "Everything earned invites a tap" + context)
	var item: Dictionary = layer.selected_item()
	var marks: Control = stage._keepsake_variant_icons
	var together := marks.get_node("KeepsakeTogether") as TextureRect
	var hard_mark: Control = marks.get_node("KeepsakeHard")
	_check(stage._keepsake_title.text == str(item.name) and together.self_modulate == (Card.TOGETHER_LIT if item.together else Card.DIM) and hard_mark.look == (HardMode.DONE if item.hard else HardMode.OPEN), "The card names the keepsake with lit or faint upgrade marks" + context)
	var title_rect: Rect2 = stage._keepsake_title.get_global_rect()
	for mark: Node in marks.get_children():
		if (mark as Control).visible: _check((mark as Control).get_global_rect().position.x >= title_rect.end.x - 0.5, "Upgrade marks follow the title without overlapping it" + context)
	for child: Control in [stage._keepsake_controls.get_child(0), stage._keepsake_controls.get_child(2)]:
		_check(box_rect.encloses(child.get_global_rect()), "Browser buttons stay inside the box" + context)
		_check(not child.get_global_rect().intersects(title_rect), "The title stays clear of the paging buttons" + context)
	_check(not stage._allowed(box_rect.get_center()), "The box never starts a camera gesture" + context)
	await _close(home)

## Explore walks the gold spirit with the joystick, the camera follows, a
## keepsake walked up to is named and its action offered, and Back restores Home.
func _check_explore() -> void:
	for size: Vector2i in [Vector2i(1560, 720), Vector2i(1280, 720)]:
		var home := await _home(size, _everything(), _all_hard())
		var stage: Control = home.stage
		var world: Node3D = home.world
		var layer: Node3D = home.layer
		await _settle(layer)
		var context := " at %s" % size
		var menu := Control.new()
		home.viewport.add_child(menu)
		var button: Button = stage._explore_button
		var spirit: Node3D = world.actors.a
		var start := spirit.position
		button.pressed.emit()
		var stick: Control = stage._stick
		_check(stage.is_exploring() and not menu.visible and stick.is_visible_in_tree(), "Explore hides the menu and shows the joystick" + context)
		stick.value = Vector2(1, 0)
		for frame in range(45): stage._process(1.0 / 30.0)
		_check(spirit.position.distance_to(start) > 0.5 and layer.walkable(spirit.position), "The joystick walks the spirit on solid ground" + context)
		stick.value = Vector2(-1, 1)
		var always_solid := true
		var never_inside := true
		for frame in range(240):
			stage._process(1.0 / 30.0)
			always_solid = always_solid and layer.walkable(spirit.position)
			never_inside = never_inside and not layer.blocks(spirit.position, 0.0)
		_check(always_solid and never_inside, "The spirit never walks off the islands or into a keepsake" + context)
		stick.value = Vector2.ZERO
		var well: Transform3D = layer.slot_transform("the-wishing-well")
		spirit.position = well * Vector3(0, 0, 0.75)
		stage._process(1.0 / 30.0)
		var action: Button = stage._explore_action
		_check(layer.selected_item().id == "the-wishing-well" and stage._keepsake_title.text == PlayerCopy.KEEPSAKE_WISHING_WELL_NAME, "Walking up to a keepsake names it" + context)
		_check(action.is_visible_in_tree() and action.text == PlayerCopy.KEEPSAKE_WISHING_WELL_ACTION and Rect2(Vector2.ZERO, Vector2(size)).encloses(action.get_global_rect()) and not action.get_global_rect().intersects(stick.get_global_rect()), "The action button offers its action, on screen, clear of the joystick" + context)
		_check(not stage._allowed(action.get_global_rect().get_center()), "The action button never starts a camera gesture" + context)
		action.pressed.emit()
		_check(stage.keepsake_playing(), "Pressing the action plays the keepsake" + context)
		action.pressed.emit()
		_check(stage.keepsake_playing(), "A second press while it plays changes nothing" + context)
		layer.stop_play()
		spirit.position = layer.slot_transform("the-wishing-well") * Vector3(0, 0, 3.0)
		stage._process(1.0 / 30.0)
		_check(not action.visible, "Walking away hides the action" + context)
		stage._explore_back.pressed.emit()
		_check(not stage.is_exploring() and menu.visible and spirit.position == start and not action.visible, "Back returns to the normal Home" + context)
		await _close(home)

## Spirits wandering at Home never walk into a keepsake.
func _frames(stage: Control, world: Node3D, count: int, step: float = 1.0 / 30.0) -> void:
	for frame in range(count):
		stage._process(step)
		world._process(step)

func _push_toward(direction: Vector3) -> Vector2:
	var across := Vector3(0.832, 0, -0.555)
	var away := Vector3(-0.555, 0, -0.832)
	return Vector2(direction.dot(across), -direction.dot(away))

func _bridge_below(world: Node3D, height: float) -> bool:
	return world.bridge_parts.all(func(plank: Node3D) -> bool: return plank.position.y < height)

## The Home bridge rests lowered and carries nobody; exploring raises it as the
## spirit comes near, and each plank carries the spirit only once drawn up.
func _check_explore_bridge() -> void:
	var home := await _home(Vector2i(1560, 720), _everything(), _all_hard())
	var stage: Control = home.stage
	var world: Node3D = home.world
	var layer: Node3D = home.layer
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
	_check(not layer.walkable(middle) and layer.walkable(Vector3(left - 0.6, 0, bridge_z)) and layer.walkable(Vector3(right + 0.6, 0, bridge_z)), "A lowered bridge carries nobody, while both shores stay ground")
	# Wandering spirits keep clear of every keepsake.
	var clear := true
	for frame in range(600):
		_frames(stage, world, 1, 0.1)
		for role: String in world.actors: clear = clear and not layer.blocks(world.actors[role].position, 0.0)
	_check(clear, "Wandering spirits never walk into a keepsake")
	# A spirit a keepsake appeared beside can always walk away.
	var inside: Vector3 = layer.slot_transform("rolling-home") * Vector3(0, 0, 0.55)
	_check(layer.blocks(inside, Stage.SPIRIT_CLEARANCE) and not layer.blocks_step(inside, inside + (inside - layer.slot_transform("rolling-home").origin).normalized() * 0.05, Stage.SPIRIT_CLEARANCE), "A spirit beside a keepsake may always step away from it")
	_check(layer.blocks_step(inside, layer.slot_transform("rolling-home").origin.lerp(inside, 0.9), Stage.SPIRIT_CLEARANCE), "but never nearer")
	var spirit: Node3D = world.actors.a
	stage._explore_button.pressed.emit()
	spirit.position = Vector3(left - 3.2, 0, bridge_z)
	_frames(stage, world, 20)
	_check(not world.home_bridge_raised, "Exploring leaves the bridge down while the spirit is far from it")
	stage._stick.value = _push_toward(Vector3.RIGHT)
	var matches := true
	var raised_at := -1
	var crossed_at := -1
	for frame in range(200):
		_frames(stage, world, 1)
		if raised_at < 0 and world.home_bridge_raised: raised_at = frame
		for index in range(planks.size()):
			var over := Vector3(lerpf(left, right, (index + 0.5) / planks.size()), 0, bridge_z)
			var up: bool = planks[index].position.y >= deck - Layer.DECK_TOLERANCE
			matches = matches and layer.walkable(over) == up
		if spirit.position.x > right + 0.3:
			crossed_at = frame
			break
	stage._stick.value = Vector2.ZERO
	_check(matches, "Every frame each bridge plank carries the spirit exactly when it is drawn up")
	_check(raised_at >= 0 and crossed_at > raised_at and layer.walkable(spirit.position), "The bridge rises and carries the spirit to the other island")
	stage._explore_back.pressed.emit()
	_frames(stage, world, 30)
	_check(not world.home_bridge_raised and _bridge_below(world, -0.5), "Leaving Explore lets the bridge back down")
	await _close(home)

## The paging arrows show on the normal Home only, through every way in and out of Explore.
func _check_explore_arrows() -> void:
	var all := _everything()
	var home := await _home(Vector2i(1560, 720), all, _all_hard())
	var stage: Control = home.stage
	var world: Node3D = home.world
	var menu := Control.new()
	home.viewport.add_child(menu)
	var previous: Button = stage._keepsake_controls.get_node("KeepsakePrevious")
	var next: Button = stage._keepsake_controls.get_node("KeepsakeNext")
	var arrows := func() -> bool: return previous.is_visible_in_tree() and next.is_visible_in_tree()
	var hidden := func() -> bool: return not previous.is_visible_in_tree() and not next.is_visible_in_tree()
	_check(arrows.call(), "The normal Home shows the keepsake arrows")
	stage._explore_button.pressed.emit()
	_check(stage.is_exploring() and hidden.call() and stage._keepsake_title.is_visible_in_tree(), "Explore hides the arrows and keeps the keepsake name")
	var some: Array[Dictionary] = [all[0]]
	stage.set_keepsakes(some)
	_frames(stage, world, 2)
	_check(hidden.call(), "New progress while exploring keeps the arrows hidden")
	stage._stick.value = Vector2(1, 0)
	stage._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	stage._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_frames(stage, world, 2)
	_check(stage.is_exploring() and hidden.call() and stage._stick.value == Vector2.ZERO, "A pause and resume keeps Explore and lets go of the joystick")
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home.viewport.add_child(host)
	var popup: Control = InGameModal.open(host, "TestPopup", "Pop-up")
	_frames(stage, world, 2)
	_check(stage.is_exploring() and hidden.call() and popup.is_visible_in_tree(), "A pop-up over Explore keeps the arrows hidden")
	popup.free()
	host.free()
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(not stage.is_exploring() and arrows.call() and menu.visible, "The system Back leaves Explore and brings the arrows back")
	stage._explore_button.pressed.emit()
	world.home_bridge_raised = true
	home.viewport.remove_child(stage)
	_check(menu.visible and not world.home_bridge_raised and is_equal_approx(float(Stage._retained_view.get("zoom_target", 0.0)), Stage.DEFAULT_SIZE), "Home closing mid-Explore restores the menu, the bridge and the zoom")
	stage.free()
	home.viewport.free()
	await process_frame
