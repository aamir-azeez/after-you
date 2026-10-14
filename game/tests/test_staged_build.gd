extends "res://tests/test_world_fingerprint.gd"
## A chapter opened from Main builds its world over several frames behind the
## chapter card (relay_preview.request_staged_build, lighthouse_world
## _build_step), instead of in one frame that froze the card.
## - Built staged, every staged chapter's world is the same world, node for
##   node (the world fingerprint), as built in one call; it took more than one
##   frame, and the build does not run the world before it is whole.
## - Only Main's one request stages a build: a screen made any other way (every
##   harness and test) builds at once, as before.
## - The chapter screen waits in "loading" while it builds, then shows its
##   ready card with the same world (once both have folded their scenery);
##   Back during the build waits for it, and a screen freed mid-build stops
##   cleanly.
## - The chapter card waits for a building screen, never past its bound.
const Preview = preload("res://relay_preview.gd")
const Journey = preload("res://services/relay_journey.gd")
const Card = preload("res://presentation/chapter_loading_card.gd")

var directory := ""

class Builder:
	extends RefCounted
	var left := 0
	func building() -> bool:
		left -= 1
		return left >= 0

func _suite() -> String:
	return "staged_build"

func _run() -> void:
	# Stage at every step, so the screen builds over frames on any machine.
	Preview.staged_build_usec = 1
	directory = "user://staged-build-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	for key: String in Preview.STAGED_CHAPTERS:
		await _same_world(key)
	await _screen(Registry.CONSERVATORY)
	await _screen(Registry.WISHING_WELL)
	await _back_mid_build(Registry.CONSERVATORY)
	await _card_waits()
	print("STAGED BUILD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _built(key: String, staged: bool) -> Dictionary:
	var viewport := _viewport()
	var world: Node3D = Registry.world_script(key).new()
	_mount(viewport, world, false)
	var frames := [0]
	var count := func() -> void: frames[0] += 1
	process_frame.connect(count)
	if staged:
		world.process_mode = Node.PROCESS_MODE_DISABLED
		world.build_budget_usec = 1
		await world.load_level(Registry.definition(key))
		world.build_budget_usec = 0
		world.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		world.load_level(Registry.definition(key))
	process_frame.disconnect(count)
	var built := _fingerprint(world, key, false, "built")
	_frames(world, 10)
	var settled := _fingerprint(world, key, false, "settled")
	viewport.free()
	return {"built": built, "settled": settled, "frames": frames[0]}

func _same_world(key: String) -> void:
	var direct: Dictionary = await _built(key, false)
	var staged: Dictionary = await _built(key, true)
	_check(direct.frames == 0, key + ": built in one call without a staged budget")
	_check(staged.frames > 1, key + ": the staged build took several frames (%d)" % staged.frames)
	_check(staged.built.hash == direct.built.hash and staged.built.nodes == direct.built.nodes, key + ": the staged world is the same world, node for node (%d nodes)" % direct.built.nodes)
	_check(staged.settled.hash == direct.settled.hash, key + ": and stays the same once it runs")

func _screen_for(key: String, path: String) -> Node:
	var screen: Node = load(Registry.solo_scene(key)).instantiate()
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	screen.journey = Journey.new(directory.path_join(path), null, key)
	return screen

func _screen(key: String) -> void:
	var direct_view := _viewport()
	var direct := _screen_for(key, "direct-" + key.validate_filename() + ".json")
	direct_view.add_child(direct)
	_check(not direct.building() and direct.mode == "ready", key + " screen: made without Main's request, it builds at once")
	var staged_view := _viewport()
	Preview.request_staged_build(Registry.solo_scene(key))
	var staged := _screen_for(key, "staged-" + key.validate_filename() + ".json")
	staged_view.add_child(staged)
	_check(Preview._staged_request.is_empty(), key + " screen: the request is used once")
	_check(staged.building() and staged.mode == "loading", key + " screen: it waits in loading while its world builds")
	var guard := 0
	while staged.building() and guard < 600:
		await process_frame
		guard += 1
	_check(not staged.building() and staged.mode == "ready" and guard >= 1, key + " screen: the ready card follows the build (%d frames)" % guard)
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

func _back_mid_build(key: String) -> void:
	var view := _viewport()
	Preview.request_staged_build(Registry.solo_scene(key))
	var screen := _screen_for(key, "back.json")
	view.add_child(screen)
	await process_frame
	_check(screen.building(), key + " back: still building")
	screen._leave()
	_check(screen.mode == "loading" and not screen._leaving and screen._leave_after_build, key + " back: Back waits for the build instead of leaving a half-built world")
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
