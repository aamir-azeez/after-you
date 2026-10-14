extends SceneTree
## Behind Friends and the room hub (opaque) and behind full pages (a 0.9
## shade), the 3D Home world is not drawn or run; a page shade shows a still
## of it instead (main._service_world_cover). It returns when they close.
## - An opaque layer stops the root viewport's 3D pass and the world's
##   processing; closing it restores both.
## - A page shade asks for one still render; a renderer with no image
##   (headless) keeps the live world, and leaving the page cleans up.
## - Leaving Main never leaves the next scene without its 3D pass.
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
	print("WORLD COVER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
