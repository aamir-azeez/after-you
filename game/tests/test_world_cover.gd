extends SceneTree
## Behind Friends and the room hub (opaque) and behind full pages (a 0.9
## shade), the 3D Home world is not drawn or run; a page shade shows a still
## of it instead (main._service_world_cover). It returns when they close.
## - An opaque layer (Friends, room hub, Safety, Redo requests) stops the root viewport's 3D pass and the world's
##   processing; closing it restores both.
## - A page shade asks for one still render; a renderer with no image
##   (headless) keeps the live world, and leaving the page cleans up.
## - Leaving Main never leaves the next scene without its 3D pass.
## - A chapter's own Safety and Redo requests screens stop its 3D pass the
##   same way, and closing them or leaving the chapter brings it back.
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _run() -> void:
	change_scene_to_file("res://main.tscn")
	var guard := 0
	while (current_scene == null or current_scene.get("mode") != "home") and guard < 600:
		await process_frame
		guard += 1
	var app: Node = current_scene
	_check(app != null and app.get("mode") == "home", "Main reaches Home")
	await _frames(3)
	var viewport := root.get_viewport()
	_check(not viewport.disable_3d and app.world.is_processing(), "Home draws and runs its world")
	# An opaque full-screen layer (as the room hub is).
	var layer: CanvasLayer = load("res://presentation/room_hub_screen.gd").new()
	app.room_hub_screen = layer
	await _frames(2)
	_check(viewport.disable_3d and not app.world.is_processing(), "Behind an opaque layer the world is neither drawn nor run")
	app.room_hub_screen = null
	layer.free()
	await _frames(2)
	_check(not viewport.disable_3d and app.world.is_processing(), "Closing it brings the world back")
	# Safety and Redo requests are opaque full-screen layers too.
	for script_path: String in ["res://presentation/safety_screen.gd", "res://presentation/redo_screen.gd"]:
		var screen: CanvasLayer = CanvasLayer.new()
		app.set("safety_screen" if script_path.contains("safety") else "redo_screen", screen)
		await _frames(2)
		_check(viewport.disable_3d and not app.world.is_processing(), "Behind %s the world is neither drawn nor run" % script_path.get_file())
		app.set("safety_screen" if script_path.contains("safety") else "redo_screen", null)
		screen.free()
		await _frames(2)
		_check(not viewport.disable_3d and app.world.is_processing(), "Closing %s brings the world back" % script_path.get_file())
	# A full page behind the 0.9 shade.
	app._show_journey()
	await _frames(4)
	_check(app.mode == "journey" and app._backdrop_shade_id == app.overlay_shade.get_instance_id(), "A page shade asks for one still of the world")
	_check(not is_instance_valid(app._backdrop_view), "The still's render is released once taken")
	if not app._backdrop_ready:
		_check(not viewport.disable_3d, "With no image to show (headless), the live world stays")
	app._show_home()
	await _frames(3)
	_check(app._backdrop_shade_id == 0 and not viewport.disable_3d and app.world.is_processing(), "Back on Home the live world returns")
	# Leaving Main while covered.
	var cover: CanvasLayer = load("res://presentation/room_hub_screen.gd").new()
	app.room_hub_screen = cover
	await _frames(2)
	_check(viewport.disable_3d, "Covered again")
	app.queue_free()
	await _frames(3)
	_check(not viewport.disable_3d, "Leaving Main restores the 3D pass for the next scene")
	cover.free()
	await create_timer(0.15).timeout
	await _chapter_cover()
	print("WORLD COVER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _chapter_cover() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var key := "first-steps@1"
	var path := "user://test-world-cover-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var preview: Node = load("res://relay_preview.gd").new()
	preview.chapter_key = key
	preview.journey = load("res://services/relay_journey.gd").new(path, null, key)
	preview.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	viewport.add_child(preview)
	await _frames(3)
	_check(not viewport.disable_3d, "A chapter draws its world")
	for field: String in ["_safety_screen", "_redo_screen"]:
		var screen := CanvasLayer.new()
		preview.set(field, screen)
		await _frames(2)
		_check(viewport.disable_3d, "Behind the chapter's %s its world is not drawn" % field)
		preview.set(field, null)
		screen.free()
		await _frames(2)
		_check(not viewport.disable_3d, "Closing the chapter's %s brings its world back" % field)
	var cover := CanvasLayer.new()
	preview._redo_screen = cover
	await _frames(2)
	_check(viewport.disable_3d, "Covered again in the chapter")
	preview.queue_free()
	await _frames(2)
	_check(not viewport.disable_3d, "Leaving the chapter while covered restores the 3D pass")
	cover.free()
	viewport.queue_free()
	await _frames(1)
	for file: String in [path, path + ".tmp", path + ".backup"]:
		if FileAccess.file_exists(file): DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
