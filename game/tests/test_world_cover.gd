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
	app.room_hub_flow.screen = layer
	await _frames(2)
	_check(viewport.disable_3d and not app.world.is_processing(), "Behind an opaque layer the world is neither drawn nor run")
	app.room_hub_flow.screen = null
	layer.free()
	await _frames(2)
	_check(not viewport.disable_3d and app.world.is_processing(), "Closing it brings the world back")
	# Safety and Redo requests are opaque full-screen layers too.
	for script_path: String in ["res://presentation/safety_screen.gd", "res://presentation/redo_screen.gd"]:
		var screen: CanvasLayer = CanvasLayer.new()
		# Main holds the Safety screen; LegacyRoomFlow holds the Redo requests screen.
		var holder: Object = app if script_path.contains("safety") else app.legacy_room_flow
		holder.set("safety_screen" if script_path.contains("safety") else "redo_screen", screen)
		await _frames(2)
		_check(viewport.disable_3d and not app.world.is_processing(), "Behind %s the world is neither drawn nor run" % script_path.get_file())
		holder.set("safety_screen" if script_path.contains("safety") else "redo_screen", null)
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
	await _redrawn_pages(app, viewport)
	# Leaving Main while covered.
	var cover: CanvasLayer = load("res://presentation/room_hub_screen.gd").new()
	app.room_hub_flow.screen = cover
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

## A page redrawn behind a new shade reuses the still: one render for three
## redraws, at the live world's render scale, and the 3D pass never comes back
## on in between. A moved camera takes a new still.
func _redrawn_pages(app: Node, viewport: Viewport) -> void:
	var scale := viewport.scaling_3d_scale
	var msaa := viewport.msaa_3d
	viewport.scaling_3d_scale = 0.6
	viewport.msaa_3d = Viewport.MSAA_2X
	var views: Array = []
	var smoothing: Array = []
	var count_views := func(node: Node) -> void:
		if node is SubViewport:
			views.append(node.scaling_3d_scale)
			smoothing.append(node.msaa_3d)
	app.child_entered_tree.connect(count_views)
	# Headless renders no image; stand in a small one for the readback.
	app.backdrop_reader = func(_view: SubViewport) -> Image: return Image.create(8, 8, false, Image.FORMAT_RGBA8)
	app._show_journey()
	await _frames(4)
	_check(app._backdrop_ready and viewport.disable_3d and not app.world.is_processing() and app.overlay.find_child("FrozenWorld", true, false) != null, "A page shows the still and stops the live world")
	var stayed := true
	for redraw in range(2):
		app._show_journey()
		for frame in range(4):
			await process_frame
			stayed = stayed and viewport.disable_3d and app._backdrop_ready
	_check(stayed, "The 3D pass stays off through every redraw of the page")
	_check(views.size() == 1, "Three draws of a page render the world once (%d renders)" % views.size())
	_check(views.size() == 1 and is_equal_approx(float(views[0]), 0.6) and smoothing[0] == Viewport.MSAA_2X, "The still renders at the live world's 3D scale and antialiasing")
	_check(app.overlay.find_children("FrozenWorld", "", true, false).size() == 1 and not is_instance_valid(app._backdrop_view), "The redrawn page has one still and no render left behind")
	app.world.camera.global_position += Vector3(0.5, 0, 0)
	app._show_journey()
	await _frames(4)
	_check(views.size() == 2 and app._backdrop_ready, "A moved camera takes a new still")
	# High to Balanced keeps the 3D scale on most phones; only antialiasing changes.
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	app._show_journey()
	await _frames(4)
	_check(views.size() == 3 and smoothing[2] == Viewport.MSAA_DISABLED, "A changed antialiasing takes a new still")
	app._show_home()
	await _frames(3)
	_check(not viewport.disable_3d and app.world.is_processing() and app._backdrop_still == null, "Home after the redrawn pages runs the live world and lets the still go")
	app.child_entered_tree.disconnect(count_views)
	app.backdrop_reader = Callable()
	viewport.scaling_3d_scale = scale
	viewport.msaa_3d = msaa

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
