extends "res://tests/test_world_fingerprint.gd"
## A chapter opened from Main builds its world over several frames behind the
## chapter card (relay_preview.request_staged_build, lighthouse_world
## _build_step), instead of in one frame that froze the card.
## - Built staged, every staged chapter's world is the same world, node for
##   node (the world fingerprint), as built in one call; it took more than one
##   frame, no step of it added more than a few hundred nodes, and the build
##   does not run the world before it is whole. That
##   holds for every chapter, opened on its first stage and on its second: a
##   staged build builds the stage it opens on, and the screen showing that
##   stage then builds nothing more in one frame.
## - Only Main's one request stages a build: a screen made any other way (every
##   harness and test) builds at once, as before.
## - The chapter screen waits in "loading" while it builds, then shows its
##   ready card with the same world (once both have folded their scenery),
##   fresh or opened on a saved later stage, and with a journal loading on its
##   worker (the Lighthouse); Back during the build waits for it, and a screen
##   freed mid-build stops cleanly.
## - The ready card's first turn (set up on a worker during the build when it
##   replays its partner's turn) is the same turn, in the same state, as one
##   set up at once.
## - The chapter card waits for a building screen, never past its bound.
const Preview = preload("res://relay_preview.gd")
const Journey = preload("res://services/relay_journey.gd")
const Card = preload("res://presentation/chapter_loading_card.gd")
const Canonical = preload("res://core/v2/canonical.gd")

var directory := ""
## The most nodes one step of a staged build may add (one frame here, where
## every _build_step yields). Chapters add up to about 260; the Wishing Well's
## dressing in one step added 840 and held a desktop frame for 25 ms behind
## the card. It bounds node work only: a step that makes few nodes with a lot
## of geometry (Turn of the Tide's water) is not bounded by it.
const MOST_NODES_PER_STEP := 300

class Builder:
	extends RefCounted
	var left := 0
	func building() -> bool:
		left -= 1
		return left >= 0

func _suite() -> String:
	return "staged_build"

func _run() -> void:
	_slice()
	# Stage at every step, so the screen builds over frames on any machine.
	Preview.staged_build_usec = 1
	directory = "user://staged-build-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	for key: String in Registry.keys():
		await _same_world(key, 0)
		await _same_world(key, 1)
		await _revealed_bubbles(key)
	await _screen(Registry.CONSERVATORY)
	await _screen(Registry.WISHING_WELL)
	await _screen(Registry.WISHING_WELL, true)
	await _screen(Registry.TURN_OF_THE_TIDE)
	await _screen(Registry.TURN_OF_THE_TIDE, true)
	await _screen(Registry.FIRST_STEPS, true)
	await _screen(Registry.RELAY)
	await _screen(Registry.LIGHTHOUSE_V2)
	await _finished_screen(Registry.WISHING_WELL)
	await _replay_screen(Registry.WISHING_WELL)
	await _back_mid_build(Registry.CONSERVATORY)
	await _back_mid_build(Registry.TURN_OF_THE_TIDE)
	await _back_mid_build(Registry.LIGHTHOUSE_V2)
	await _card_waits()
	print("STAGED BUILD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A build's own slice is half the screen's frame, never aiming above 60
## frames a second, and follows a lower frame cap.
func _slice() -> void:
	var World := preload("res://presentation/island_world.gd")
	_check(World.frame_budget_usec(60.0, 0) == 8333, "A 60 Hz screen gives the build half its frame")
	_check(World.frame_budget_usec(120.0, 0) == 8333 and World.frame_budget_usec(144.0, 0) == 8333, "A faster screen still gives it a 60 a second slice")
	_check(World.frame_budget_usec(-1.0, 0) == 8333, "A screen that reports no rate counts as 60 Hz")
	_check(World.frame_budget_usec(50.0, 0) == 10000, "A slower screen gives it half its longer frame")
	_check(World.frame_budget_usec(120.0, 30) == 16000, "A frame cap lengthens the slice, up to its bound")

## Built staged while hidden, as a chapter screen builds it under its card,
## with a spirit standing on a bubble's tail and a placement while hidden
## (when every mesh reads as no scenery), then shown: its bubbles lean and
## rise exactly as in a world built at once and always shown, clear of the
## scenery it gathers once it shows.
func _revealed_bubbles(key: String) -> void:
	var definition := Registry.definition(key)
	var stage: Dictionary = definition.stages[0]
	var worlds: Array = []
	for staged: bool in [false, true]:
		var viewport := _viewport()
		var world: Node3D = Registry.world_script(key).new()
		_mount(viewport, world, false)
		if not "_sceneries" in world:
			viewport.free()
			return
		if staged:
			world.process_mode = Node.PROCESS_MODE_DISABLED
			world.visible = false
			await world.build_staged(definition, 1, str(stage.id))
		else:
			world.load_level(definition)
		world.present_stage(stage)
		worlds.append([viewport, world])
		var tailed: Node3D = null
		for bubble: Node3D in world._bubbles:
			if is_instance_valid(bubble) and bubble.visible:
				tailed = bubble
				break
		if tailed == null or not world.actors.has("p0"):
			for pair: Array in worlds: pair[0].free()
			return
		var spirit: Node3D = world.actors["p0"]
		spirit.visible = true
		world.actor_targets["p0"] = (spirit.get_parent() as Node3D).to_local((tailed.get_parent() as Node3D).to_global(tailed.anchor))
		world._placement_due = true
		world._frame_camera()
		if staged:
			world.visible = true
			world.process_mode = Node.PROCESS_MODE_INHERIT
	# Real frames: a world places its bubbles from its own frame (_on_tree_frame).
	for frame in range(5): await process_frame
	var direct: Node3D = worlds[0][1]
	var revealed: Node3D = worlds[1][1]
	var scenery := _scenery_boxes(revealed)
	_check(scenery > 0 and scenery == _scenery_boxes(direct), key + ": shown, the world gathers its scenery whole (%d boxes, %d built at once)" % [scenery, _scenery_boxes(direct)])
	var same: bool = revealed._bubbles.size() == direct._bubbles.size()
	for index in range(mini(revealed._bubbles.size(), direct._bubbles.size())):
		same = same and is_equal_approx(revealed._bubbles[index].lean, direct._bubbles[index].lean) and is_equal_approx(revealed._bubbles[index].lift, direct._bubbles[index].lift)
	_check(same, key + ": its bubbles lean and rise as in a world built at once (%d)" % revealed._bubbles.size())
	for pair: Array in worlds: pair[0].free()

## Scenery boxes a journey world gathered for its bubbles, all bubbles together.
func _scenery_boxes(world: Node3D) -> int:
	var total := 0
	for boxes: Variant in world._sceneries.values(): total += (boxes as Array).size()
	return total

## A world as a chapter screen opening on stage stage_index has it: built in
## one call and then shown that stage (the screen's ready view), or built
## staged straight to that stage and then shown it.
func _built(key: String, staged: bool, stage_index: int) -> Dictionary:
	var definition := Registry.definition(key)
	var stage: Dictionary = definition.stages[stage_index]
	var viewport := _viewport()
	var world: Node3D = Registry.world_script(key).new()
	_mount(viewport, world, false)
	var frames := [0]
	# Nodes added this frame, and the most any one frame added.
	var added := [0, 0]
	var count := func() -> void:
		frames[0] += 1
		added[1] = maxi(added[1], added[0])
		added[0] = 0
	var grow := func(_node: Node) -> void: added[0] += 1
	process_frame.connect(count)
	if staged:
		world.process_mode = Node.PROCESS_MODE_DISABLED
		node_added.connect(grow)
		await world.build_staged(definition, 1, str(stage.id))
		node_added.disconnect(grow)
		added[1] = maxi(added[1], added[0])
		world.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		world.load_level(definition)
	process_frame.disconnect(count)
	var terrain_id: int = world.terrain.get_instance_id() if is_instance_valid(world.terrain) else 0
	world.present_stage(stage)
	var kept: bool = is_instance_valid(world.terrain) and world.terrain.get_instance_id() == terrain_id
	var built := _fingerprint(world, key, false, "built")
	_frames(world, 10)
	var settled := _fingerprint(world, key, false, "settled")
	viewport.free()
	return {"built": built, "settled": settled, "frames": frames[0], "kept": kept, "most_added": added[1]}

func _same_world(key: String, stage_index: int) -> void:
	var label := "%s stage %d" % [key, stage_index + 1]
	var direct: Dictionary = await _built(key, false, stage_index)
	var staged: Dictionary = await _built(key, true, stage_index)
	_check(direct.frames == 0, label + ": built in one call without a staged budget")
	_check(staged.frames > 1, label + ": the staged build took several frames (%d)" % staged.frames)
	_check(staged.most_added <= MOST_NODES_PER_STEP, label + ": no step of the build adds more than %d nodes (most %d)" % [MOST_NODES_PER_STEP, staged.most_added])
	_check(staged.kept, label + ": showing the stage it opens on builds nothing more")
	_check(staged.built.hash == direct.built.hash and staged.built.nodes == direct.built.nodes, label + ": the staged world is the same world, node for node (%d nodes)" % direct.built.nodes)
	_check(staged.settled.hash == direct.settled.hash, label + ": and stays the same once it runs")

func _screen_for(key: String, path: String, saved: bool = false) -> Node:
	var screen: Node = load(Registry.solo_scene(key)).instantiate()
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	var file := directory.path_join(path)
	if saved and not FileAccess.file_exists(file):
		# A journal on its second stage: its first stage kept.
		var journal := Journey.new(file, null, key)
		journal.load_data()
		var first := str(journal._level.stages[0].id)
		_check(journal.accept_recording(_fixture(first + "-a")) and journal.accept_recording(_fixture(first + "-b")), key + ": a saved first stage")
	screen.journey = Journey.new(file, null, key)
	return screen

func _fixture(name: String) -> Dictionary:
	for folder: String in ["cooperative", "journey", "first_steps"]:
		var file := "res://tests/fixtures/" + folder + "/" + name + ".json"
		if FileAccess.file_exists(file): return JSON.parse_string(FileAccess.get_file_as_string(file))
	return {}

func _screen(key: String, saved: bool = false) -> void:
	var label := key + (" saved" if saved else "") + " screen"
	var suffix := key.validate_filename() + ("-saved" if saved else "") + ".json"
	var direct_view := _viewport()
	var direct := _screen_for(key, "direct-" + suffix, saved)
	direct_view.add_child(direct)
	_check(not direct.building(), label + ": made without Main's request, it builds at once")
	var guard := 0
	# A journal loading on its worker (the Lighthouse) shows its card first.
	while direct.mode == "loading" and guard < 600:
		await process_frame
		guard += 1
	_check(direct.mode == "ready", label + ": the screen built at once is ready")
	var staged_view := _viewport()
	Preview.request_staged_build(Registry.solo_scene(key))
	var staged := _screen_for(key, "staged-" + suffix, saved)
	staged_view.add_child(staged)
	_check(Preview._staged_request.is_empty(), label + ": the request is used once")
	_check(staged.building() and staged.mode == "loading", label + ": it waits in loading while its world builds")
	guard = 0
	var terrain_id := 0
	var drawn_half_built := false
	while (staged.building() or staged.mode == "loading") and guard < 600:
		await process_frame
		guard += 1
		if staged.building() and is_instance_valid(staged.world.terrain): terrain_id = staged.world.terrain.get_instance_id()
		if staged.world.build_budget_usec > 0 and staged.world.visible: drawn_half_built = true
	_check(not staged.building() and staged.mode == "ready" and guard >= 1, label + ": the ready card follows the build (%d frames)" % guard)
	_check(not drawn_half_built and staged.world.visible == direct.world.visible, label + ": the half-built world is never drawn, and shows once whole")
	_check(staged.world.terrain.get_instance_id() == terrain_id, label + ": the ready card shows the world it built, not a rebuild in one frame")
	if saved: _check(str(staged.journey.stage_id()) == str(Registry.definition(key).stages[1].id), label + ": it opens on the saved second stage")
	_check(Canonical.same(staged.sim.snapshot(), direct.sim.snapshot()) and str(staged.sim.get("role")) == str(direct.sim.get("role")), label + ": the same turn, in the same state, as one set up at once")
	_check(staged.world.process_mode == direct.world.process_mode, key + " screen: the world runs again once whole")
	# Both screens fold their scenery behind the ready card, a little a frame.
	guard = 0
	while (staged.world.scenery_folding() or direct.world.scenery_folding()) and guard < 600:
		await process_frame
		guard += 1
	var expected := _fingerprint(direct.world, key, true, "screen")
	_check(_fingerprint(staged.world, key, true, "screen").hash == expected.hash, key + " screen: the same world as a screen built at once")
	staged.set_physics_process(false)
	staged._begin()
	_check(staged.mode == "play", key + " screen: a turn starts on the staged world")
	direct_view.free()
	staged_view.free()

## A finished chapter opens on its last stage: built staged straight to it,
## the completion view keeps that world and matches one built at once.
func _finished_screen(key: String) -> void:
	var label := key + " finished screen"
	var views: Array = []
	var screens: Array = []
	for staged_open: bool in [false, true]:
		var file := directory.path_join(("staged" if staged_open else "direct") + "-finished-" + key.validate_filename() + ".json")
		var journal := Journey.new(file, null, key)
		journal.load_data()
		for stage: Dictionary in journal._level.stages:
			_check(journal.accept_recording(_fixture(str(stage.id) + "-a")) and journal.accept_recording(_fixture(str(stage.id) + "-b")), label + ": a kept stage " + str(stage.id))
		_check(journal.chapter_complete(), label + ": the journal is finished")
		var view := _viewport()
		if staged_open: Preview.request_staged_build(Registry.solo_scene(key))
		var screen: Node = load(Registry.solo_scene(key)).instantiate()
		screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
		screen.journey = Journey.new(file, null, key)
		view.add_child(screen)
		var guard := 0
		var terrain_id := 0
		while screen.mode != "complete" and guard < 900:
			await process_frame
			guard += 1
			if screen.building() and is_instance_valid(screen.world.terrain): terrain_id = screen.world.terrain.get_instance_id()
		_check(screen.mode == "complete", label + ": the completion view shows (%s)" % ("staged" if staged_open else "at once"))
		if staged_open: _check(screen.world.terrain.get_instance_id() == terrain_id and str(screen.world.displayed_stage_id) == str(Registry.definition(key).stages[-1].id), label + ": the last stage is built once, staged, and kept")
		views.append(view)
		screens.append(screen)
	var guard := 0
	while (screens[0].world.scenery_folding() or screens[1].world.scenery_folding()) and guard < 600:
		await process_frame
		guard += 1
	_check(_fingerprint(screens[1].world, key, true, "finished").hash == _fingerprint(screens[0].world, key, true, "finished").hash, label + ": the same world as a screen built at once")
	for view: Node in views: view.free()

## A replay chosen from the collection opens on its stage: built staged
## straight to it, and kept when the replay starts.
func _replay_screen(key: String) -> void:
	var label := key + " replay screen"
	var stages: Array = Registry.definition(key).stages
	var pairs: Array = []
	for stage: Dictionary in stages: pairs.append({"a": _fixture(str(stage.id) + "-a"), "b": _fixture(str(stage.id) + "-b")})
	var context := {"schema_version": 1, "chapter_key": key, "selected_stage_index": pairs.size() - 1, "accepted_pairs": pairs, "visibility_key": "staged-build-test"}
	_check(Preview.SoloReplayLaunch.write(context), label + ": Main's replay hand-off is written")
	var view := _viewport()
	Preview.request_staged_build(Registry.solo_scene(key))
	var screen: Node = load(Registry.solo_scene(key)).instantiate()
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	view.add_child(screen)
	_check(screen._solo_replay_only and screen.building(), label + ": the replay opens behind a staged build")
	var guard := 0
	var terrain_id := 0
	while screen.building() and guard < 900:
		await process_frame
		guard += 1
		if is_instance_valid(screen.world.terrain): terrain_id = screen.world.terrain.get_instance_id()
	for frame in range(3): await process_frame
	_check(str(screen.world.displayed_stage_id) == str(stages[-1].id) and screen.world.terrain.get_instance_id() == terrain_id, label + ": its stage is built once, staged, and kept by the replay (%s)" % str(screen.mode))
	view.free()

func _back_mid_build(key: String) -> void:
	var view := _viewport()
	Preview.request_staged_build(Registry.solo_scene(key))
	var screen := _screen_for(key, "back-" + key.validate_filename() + ".json")
	view.add_child(screen)
	await process_frame
	_check(screen.building(), key + " back: still building")
	screen._leave()
	_check(screen.mode == "loading" and not screen._leaving and (screen._leave_after_build or screen._leave_after_load), key + " back: Back waits for the build instead of leaving a half-built world")
	# A screen freed mid-build (the app closing) stops its build cleanly.
	view.queue_free()
	for frame in range(20): await process_frame
	_check(not is_instance_valid(view), key + " back: a screen freed mid-build is gone without errors")

func _card_waits() -> void:
	var card := Card.new()
	root.add_child(card)
	var builder := Builder.new()
	builder.left = 12
	var frames := [0]
	var count := func() -> void: frames[0] += 1
	process_frame.connect(count)
	await card._while_building(builder)
	process_frame.disconnect(count)
	_check(frames[0] >= 12 and frames[0] <= 14, "The chapter card waits while the screen builds (%d frames)" % frames[0])
	frames[0] = 0
	await card._while_building(RefCounted.new())
	_check(frames[0] == 0, "A screen with no staged build is not waited for")
	card.queue_free()
	await process_frame
