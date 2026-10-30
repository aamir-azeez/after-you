extends SceneTree
## Home's keepsakes on the islands (presentation/home_keepsake_layer.gd): one
## per chapter card, each on its own island or isle, off the spirits' start
## spots and clear of the trees and each other, the Home islands' ones in the
## opening view clear of the header and the card, the isles' ones a pan from
## the card away; the isles and their plank bridges; still parts folded and
## moving parts kept within budget; a burst of changes rebuilt once; taps,
## repeat taps, Reduce motion, leaving Home mid tap and Explore walk ups;
## triggers, rides and stays in Explore, and everything settling back to rest;
## the card's lines, marks and count; the Home bridge in Explore.
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
const Isles = preload("res://presentation/keepsakes/home_isles.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
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
	await _check_isles()
	await _check_fold()
	await _check_triggers()
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
func _home(size: Vector2i, items: Array[Dictionary], hard: Dictionary = {}, together_hard: bool = true, free_only: bool = false) -> Dictionary:
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
	stage.configure(world, func() -> bool: return true, items, free_only)
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
	_check(lift != null and lift.find_child("Footing", true, false) != null and layer.parts_of("first-steps").has("lift"), "The Bell Arch stands on its Hard plinths with its moving lift")
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
	for size: Vector2i in [Vector2i(1560, 720), Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(1600, 738)]:
		var home := await _home(size, _everything(), _all_hard())
		var stage: Control = home.stage
		var layer: Node3D = home.layer
		var world: Node3D = home.world
		var camera: Camera3D = world.camera
		var context := " at %s" % size
		_check(layer.shown_ids().size() == States.entries().size(), "Everything earned shows every keepsake" + context)
		var trees: Array[PackedVector2Array] = []
		for tree_x: float in [2.45, 3.95, -4.15, -2.65]:
			trees.append(PackedVector2Array([Vector2(tree_x - 0.25, -2.87), Vector2(tree_x + 0.25, -2.87), Vector2(tree_x + 0.25, -2.37), Vector2(tree_x - 0.25, -2.37)]))
		var header := Rect2(size.x - 310, 0, 310, 92)
		var box: Rect2 = stage._keepsake_box.get_global_rect()
		var floor: Rect2 = stage._floor
		var spots: Array[Vector2] = [floor.get_center() + Vector2(-0.68, 0.42), floor.get_center() + Vector2(0.68, -0.42)]
		var solids := {}
		for id: String in layer.shown_ids():
			var entry: Dictionary = States.entries()[States.entries().map(func(item: Dictionary) -> String: return item.id).find(id)]
			var island_id := str(entry.keepsake.island)
			var island: Rect2 = layer.island_floor(island_id)
			var own: Array = layer.solid_grounds(id)
			_check(island.has_area() and own.all(func(ground: PackedVector2Array) -> bool: return Array(ground).all(func(corner: Vector2) -> bool: return island.grow(0.2).has_point(corner))), "%s stands on the %s island" % [id, island_id])
			var apart := true
			for ground: PackedVector2Array in own:
				for tree: PackedVector2Array in trees: _check(not _polygons_meet(ground, tree), "%s stays clear of the Home trees" % id)
				for other: String in solids:
					for theirs: PackedVector2Array in solids[other]: apart = apart and not _polygons_meet(ground, theirs)
			_check(apart, "%s stands apart from the others at full size" % id)
			solids[id] = own
			for spot: Vector2 in spots: _check(layer.distance(id, Vector3(spot.x, 0, spot.y)) >= Stage.SPIRIT_CLEARANCE, "%s stays off the spirits' start spot %s" % [id, spot])
			if island_id in ["left", "right"]:
				# The keepsakes on the Home islands show in the opening view.
				var at := camera.unproject_position(layer.to_global(layer.point_of(id)))
				_check(stage._stage_rect().has_point(at) and not header.has_point(at) and not box.has_point(at), "%s shows in the opening view, clear of the header and the card%s (%s)" % [id, context, at])
		# Picking a keepsake on an isle from the card pans the view to show it.
		world.reduced_motion = true
		for id: String in layer.shown_ids():
			layer.select_id(id)
			stage.frame_selected()
			stage._process(0.0)
			var at := camera.unproject_position(layer.to_global(layer.selected_point()))
			_check(stage._stage_rect().has_point(at), "Picking %s on the card brings it into the stage%s (%s in %s)" % [id, context, at, stage._stage_rect()])
		world.reduced_motion = false
		await _close(home)

## The isles a build stands keepsakes on, their plank bridges and their ground.
func _check_isles() -> void:
	var home := await _home(Vector2i(1560, 720), _everything(), _all_hard())
	var layer: Node3D = home.layer
	var world: Node3D = home.world
	var isles: Node3D = world.terrain.get_node_or_null(Isles.NODE_NAME)
	_check(isles != null and not layer.is_ancestor_of(isles) and isles.get_script() == null, "The keepsake isles are plain Home terrain, folded with Home")
	for id: String in ["tide", "journey_left", "journey_right"]:
		_check(isles.get_node_or_null("Isle_" + id) != null and layer.island_floor(id).has_area(), "Home stands the %s isle" % id)
		var ends: Array = Isles.ISLES[id].bridge
		var middle: Vector2 = (ends[0] as Vector2).lerp(ends[1], 0.5)
		var across := ((ends[1] as Vector2) - (ends[0] as Vector2)).normalized().orthogonal()
		_check(layer.walkable(Vector3(middle.x, 0, middle.y)), "The %s bridge carries the pip" % id)
		_check(not layer.walkable(Vector3(middle.x + across.x * 0.9, 0, middle.y + across.y * 0.9)), "Off the side of the %s bridge is water" % id)
		_check(not layer.near_lowering_crossing(Vector3(middle.x, 0, middle.y), Stage.BRIDGE_NOTICE), "Walking the %s bridge never raises the Home bridge" % id)
		var center: Vector2 = Isles.ISLES[id].center
		_check(layer.walkable(Vector3(center.x, 0, center.y)) or layer.blocks(Vector3(center.x, 0, center.y), Layer.WALK_CLEARANCE), "The %s isle is ground" % id)
	# The lighthouse jetty is ground past the isle's edge.
	var jetty: Vector3 = layer.trigger_point("sleeping-lighthouse")
	_check(not layer.island_floor("journey_left").has_point(Vector2(jetty.x, jetty.z)) and layer.walkable(jetty), "The jetty's end is past the isle's edge and still ground")
	# The stick walks the pip from a Home island over each plank bridge onto its isle.
	var stage: Control = home.stage
	var spirit: Node3D = world.actors.a
	stage._explore_button.pressed.emit()
	for walk: Array in [["journey_left", Vector3(-3.0, 0, -2.4), Vector3(0, 0, -1)], ["journey_right", Vector3(3.2, 0, -2.4), Vector3(0, 0, -1)], ["tide", Vector3(5.3, 0, -0.1), Vector3(1, 0, 0)]]:
		var start: Vector3 = walk[1]
		spirit.position = start
		_frames(stage, world, 1)
		var solid: bool = layer.walkable(spirit.position)
		var arrived := -1
		stage._stick.value = _push_toward(walk[2])
		for frame in range(150):
			_frames(stage, world, 1)
			solid = solid and layer.walkable(spirit.position)
			if layer.island_floor(walk[0]).has_point(Vector2(spirit.position.x, spirit.position.z)) and spirit.position.distance_to(start) > 1.5:
				arrived = frame
				break
		stage._stick.value = Vector2.ZERO
		_check(solid and arrived >= 0, "The stick walks the pip over the bridge onto the %s isle on solid ground (arrived at frame %d, at %s)" % [walk[0], arrived, spirit.position])
	stage._explore_back.pressed.emit()
	await _close(home)
	# A build that sells nothing has the tide isle and no journey isles.
	var free := await _home(Vector2i(1560, 720), _everything(), _all_hard(), true, true)
	var free_isles: Node3D = free.world.terrain.get_node_or_null(Isles.NODE_NAME)
	_check(free_isles != null and free_isles.get_node_or_null("Isle_tide") != null and free_isles.get_node_or_null("Isle_journey_left") == null and free_isles.get_node_or_null("Isle_journey_right") == null, "A build that sells nothing has the tide isle and no journey isles")
	_check(not free.layer.island_floor("journey_left").has_area(), "and walks no journey isle")
	await _close(free)

## In Explore a step sets a keepsake off: walking into its trigger plays it
## once (again only after walking out), walking through the arch rings it, a
## ride carries the pip and lands it on open ground, the house and the lantern
## path are walked in and out of; a still pip, a wandering pip and an unearned
## keepsake set nothing off; and every keepsake settles back to rest with
## nothing left running.
func _check_triggers() -> void:
	var home := await _home(Vector2i(1560, 720), _everything(), _all_hard())
	var stage: Control = home.stage
	var world: Node3D = home.world
	var layer: Node3D = home.layer
	await _settle(layer)
	await process_frame
	var spirit: Node3D = world.actors.a
	var steps: int = layer.steps
	_frames(stage, world, 60)
	_check(layer.steps == steps and not layer.playing(), "Wandering spirits set nothing off")
	_check(not layer.is_processing(), "The keepsakes run nothing per frame at rest")
	stage._explore_button.pressed.emit()
	_frames(stage, world, 2)
	steps = layer.steps
	_frames(stage, world, 30)
	_check(layer.steps == steps, "A pip standing still in Explore asks the keepsakes nothing")
	var far := Vector3(-4.3, 0, 0.6)
	for id: String in layer.shown_ids():
		var trigger: Dictionary = layer._frames[id].trigger
		if trigger.is_empty(): continue
		layer.end_explore()
		var inside: Vector3
		if trigger.has("line"):
			var placed: Transform3D = layer.slot_transform(id)
			spirit.position = placed * Vector3(0, 0, -0.7)
			inside = placed * Vector3(0, 0, 0.7)
			layer.walked(spirit.position, inside, spirit)
			_check(str(layer._play.get("id", "")) == id, "Walking through %s sets it off, and the next step into another trigger leaves it playing (%s)" % [id, layer._play.get("id", "-")])
			layer.stop_play()
			layer.walked(inside, inside + Vector3(0.05, 0, 0), spirit)
			_check(not layer.playing(), "A step that crosses nothing sets %s off no more" % id)
			continue
		inside = layer.trigger_point(id)
		# Walk in from straight in front, so no other keepsake's line is crossed.
		far = inside + Vector3(0, 0, 4.0)
		spirit.position = inside
		layer.walked(far, inside, spirit)
		_check(str(layer._play.get("id", "")) == id, "Walking into %s's trigger sets it off" % id)
		var tween: Variant = layer._play.get("tween")
		layer.walked(inside, inside + Vector3(0.02, 0, 0), spirit)
		_check(layer._play.get("tween") == tween, "Another step inside %s's trigger neither stacks nor restarts it" % id)
		if layer.riding():
			# A ride: the stick waits, the pip is carried and lands on open ground.
			stage._stick.value = Vector2(1, 0)
			var until := Time.get_ticks_msec() + 6000
			var moved := false
			var start := spirit.position
			while layer.riding() and Time.get_ticks_msec() < until:
				await process_frame
				stage._process(1.0 / 60.0)
				moved = moved or spirit.position.distance_to(start) > 0.3
			stage._stick.value = Vector2.ZERO
			_check(moved and not layer.riding(), "%s carries the pip on its ride" % id)
			_check(layer.playing(), "%s gives the pip back the moment it lands, while its upgrades still play" % id)
			_check(spirit.position.y == 0.0 and layer.walkable(spirit.position), "%s lands the pip on open ground: %s" % [id, spirit.position])
		layer.stop_play()
		var after := spirit.position
		layer.walked(after, after + Vector3(0.01, 0, 0), spirit)
		if after.distance_to(inside) < 0.05: _check(not layer.playing(), "Standing on in %s's trigger sets it off no more" % id)
		layer.walked(after, far, spirit)
		spirit.position = inside
		layer.walked(far, inside, spirit)
		_check(str(layer._play.get("id", "")) == id, "Walking out and back into %s's trigger sets it off again" % id)
		layer.stop_play()
		await process_frame
	# The house: walked into, the roof and front wall fade and the inside is there.
	far = Vector3(-4.3, 0, 0.6)
	layer.end_explore()
	var house: Dictionary = layer.parts_of("a-house-for-two")
	var cut: Node3D = house.cutaway
	var faded := func() -> bool: return cut.find_children("*", "MeshInstance3D", true, false).all(func(mesh: Node) -> bool: return mesh.get_meta("cutaway", false))
	var room: Vector3 = layer.slot_transform("a-house-for-two") * Vector3(0.3, 0, -0.3)
	layer.walked(far, room, spirit)
	var prop: Node3D = layer.prop_node("a-house-for-two")
	_check(layer.staying() == "a-house-for-two" and faded.call() and prop.get_node_or_null("Visit") != null, "Walking into the house fades its roof and front wall and makes its inside")
	_check(layer.ground_height(room) > 0.5, "On Hard the pip stands on the house's raised floor: %.2f" % layer.ground_height(room))
	# New marks while the pip is inside: the rebuilt house is walked on into, quietly.
	var heard: Array = []
	stage.play_cue = func(cue: String) -> void: heard.append(cue)
	var fewer := _everything()
	fewer = fewer.filter(func(item: Dictionary) -> bool: return item.family != "earlier")
	stage.set_keepsakes(fewer)
	await _settle(layer)
	var rebuilt: Dictionary = layer.parts_of("a-house-for-two")
	var rebuilt_cut: Node3D = rebuilt.cutaway
	_check(rebuilt_cut != cut and layer.staying() == "a-house-for-two" and rebuilt_cut.find_children("*", "MeshInstance3D", true, false).all(func(mesh: Node) -> bool: return mesh.get_meta("cutaway", false)), "A rebuild while the pip is inside keeps it inside the new house")
	_check(heard.is_empty(), "and plays no sound again: %s" % [heard])
	stage.set_keepsakes(_everything())
	await _settle(layer)
	house = layer.parts_of("a-house-for-two")
	cut = house.cutaway
	prop = layer.prop_node("a-house-for-two")
	layer.walked(room, far, spirit)
	await process_frame
	_check(layer.staying().is_empty() and not cut.find_children("*", "MeshInstance3D", true, false).any(func(mesh: Node) -> bool: return mesh.get_meta("cutaway", false)) and prop.get_node_or_null("Visit") == null, "Walking out puts the house back and its inside goes")
	layer.walked(far, room, spirit)
	stage._explore_back.pressed.emit()
	await process_frame
	_check(layer.staying().is_empty() and prop.get_node_or_null("Visit") == null and not cut.find_children("*", "MeshInstance3D", true, false).any(func(mesh: Node) -> bool: return mesh.get_meta("cutaway", false)), "Leaving Explore inside the house puts it back")
	stage._explore_button.pressed.emit()
	# The Lantern Walk: a lit lantern glows over the pip on the stones.
	var walk: Transform3D = layer.slot_transform("earlier")
	layer.walked(far, walk * Vector3(-1.2, 0, 0), spirit)
	var visit: Node3D = layer.prop_node("earlier").get_node_or_null("Visit")
	_check(layer.staying() == "earlier" and visit != null and (visit.get_node("Glow") as Node3D).visible, "Walking the stones lights the lantern over the pip")
	layer.walked(walk * Vector3(-1.2, 0, 0), walk * Vector3(1.2, 0, 0), spirit)
	_check((visit.get_node("Glow") as Node3D).position.x > 0.5, "and the glow follows the pip along the line")
	layer.walked(walk * Vector3(1.2, 0, 0), far, spirit)
	_check(layer.staying().is_empty(), "Walking off the stones leaves the Lantern Walk")
	# Settled: nothing left made, moving or running.
	var until := Time.get_ticks_msec() + 3000
	while layer.playing() and Time.get_ticks_msec() < until: await process_frame
	await process_frame
	_check(not layer.playing() and not layer.is_processing() and layer.find_children("Tap", "", true, false).is_empty() and layer.find_children("Visit", "", true, false).is_empty(), "Every keepsake settles back to rest with nothing left running")
	await _close(home)
	# Leaving Home mid ride: the ride ends at once and the pip is put back.
	var riders := await _home(Vector2i(1560, 720), _everything(), _all_hard())
	await _settle(riders.layer)
	riders.stage._explore_button.pressed.emit()
	var step: Vector3 = riders.layer.trigger_point("high-and-low")
	riders.world.actors.a.position = step
	riders.layer.walked(step + Vector3(0, 0, 4.0), step, riders.world.actors.a)
	_check(riders.layer.riding(), "The Giant Steps ride starts")
	await create_timer(0.3).timeout
	riders.stage.free()
	var put_back: Vector3 = riders.world.actors.a.position
	await process_frame
	await process_frame
	_check(_tweens() == 0 and riders.world.actors.a.position == put_back and put_back.y == 0.0 and put_back != step, "Leaving Home mid ride stops it, and nothing moves the pip after Home has put it back: %s" % riders.world.actors.a.position)
	riders.viewport.free()
	await process_frame
	# An unearned keepsake sets nothing off.
	var empty := await _home(Vector2i(1560, 720), [])
	await _settle(empty.layer)
	empty.stage._explore_button.pressed.emit()
	var relay: Variant = empty.layer.trigger_point("relay-isles")
	empty.layer.walked(far, relay, empty.world.actors.a)
	_check(not empty.layer.playing(), "A keepsake not earned sets nothing off")
	await _close(empty)

## Still parts fold into a few shared batches; moving parts keep their own
## nodes; the budget holds with every upgrade on every keepsake.
func _check_fold() -> void:
	var home := await _home(Vector2i(1560, 720), _everything(), _all_hard())
	var layer: Node3D = home.layer
	var stage: Control = home.stage
	await _settle(layer)
	while stage.folding(): stage._process(0.0)
	var props: Node3D = layer.find_children("Props", "Node3D", false, false)[0]
	var isles: Node3D = home.world.terrain.get_node(Isles.NODE_NAME)
	var batches := props.find_children("StaticBatch*", "MeshInstance3D", true, false)
	_check(batches.size() > 5, "Still parts fold into shared batches: %d" % batches.size())
	var draws := 0
	var triangles := 0
	for node: Node in props.find_children("*", "MeshInstance3D", true, false) + isles.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		draws += mesh.mesh.get_surface_count()
		triangles += mesh.mesh.get_faces().size() / 3
	print("HOME KEEPSAKE LAYER: every upgrade on every keepsake, with the isles, folds to %d meshes and %d triangles" % [draws, triangles])
	_check(draws <= 180 and triangles <= 45000, "All eleven with every upgrade and the isles stay in the README budget (180 draws, 45,000 triangles): %d draws, %d triangles" % [draws, triangles])
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
	_check(layer.selected_item().id == "first-steps" and stage._keepsake_title.text == PlayerCopy.KEEPSAKE_BELL_ARCH_NAME and stage._greeting_left == 0.0, "Tapping a keepsake names it on the card without greeting the spirits")
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
	_check(stage.play_keepsake("first-steps"), "A tap on another keepsake while one plays plays the new one (%s)" % [layer._play.get("id", "-")])
	_check(_pose(layer, "the-wishing-well") == well_pose, "and puts the first at rest")
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
			_check(status.text == PlayerCopy.KEEPSAKE_WANTS_TOP % PlayerCopy.KEEPSAKE_BELL_ARCH_TOP, "Cleared together and on Hard, the card asks for Hard with a friend: %s%s" % [status.text, context])
		"all":
			_check(status.text == PlayerCopy.KEEPSAKE_DONE % PlayerCopy.KEEPSAKE_BELL_ARCH_ACTION.to_lower() or status.text.begins_with(PlayerCopy.KEEPSAKE_DONE.get_slice("%", 0)), "Everything earned invites a tap" + context)
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
			never_inside = never_inside and not layer.blocks(spirit.position, 0.01)
		_check(always_solid and never_inside, "The spirit never walks off the islands or into a keepsake" + context)
		stick.value = Vector2.ZERO
		var well: Transform3D = layer.slot_transform("the-wishing-well")
		spirit.position = well * Vector3(0.0, 0, 1.05)
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
		spirit.position = Vector3(-3.3, 0, 1.6)
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
		for role: String in world.actors: clear = clear and not layer.blocks(world.actors[role].position, 0.01)
	_check(clear, "Wandering spirits never walk into a keepsake")
	# A spirit a keepsake appeared beside can always walk away.
	var inside: Vector3 = layer.slot_transform("the-wishing-well") * Vector3(0, 0, 0.95)
	_check(layer.blocks(inside, Stage.SPIRIT_CLEARANCE) and not layer.blocks_step(inside, inside + (inside - layer.slot_transform("the-wishing-well").origin).normalized() * 0.05, Stage.SPIRIT_CLEARANCE), "A spirit beside a keepsake may always step away from it")
	_check(layer.blocks_step(inside, layer.slot_transform("the-wishing-well").origin.lerp(inside, 0.95), Stage.SPIRIT_CLEARANCE), "but never nearer")
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
