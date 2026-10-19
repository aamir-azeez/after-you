extends "res://tests/test_world_fingerprint.gd"
## What the frame of a screen change and the Begin tap still do, locked as
## work, not milliseconds (performance audit 4): the old screen's nodes are
## freed over the frames after a change, never in its frame; going back to
## Home reuses Home's loaded scene; Begin on the Lighthouse ready card keeps
## the stage the card shows instead of building it again, and the kept world
## is the world a rebuild makes.
const ScreenSwitch = preload("res://services/screen_switch.gd")
const Journey = preload("res://services/relay_journey.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const LIGHTHOUSE_V2 := "sleeping-lighthouse@2"
const OpeningCard = preload("res://presentation/chapter_loading_card.gd")
const Preview = preload("res://relay_preview.gd")

## Switches the screen from a key press, as a tap on Back does: input runs
## before the engine counts the next frame.
class Tapper extends Node:
	var packed: PackedScene
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_F13 and packed != null:
			var scene := packed
			packed = null
			ScreenSwitch.to_packed(get_tree(), scene)

func _suite() -> String:
	return "screen_frames"

func _run() -> void:
	await _switch()
	await _switch_from_input()
	await _staged_controls()
	await _back_home()
	await _lighthouse_begin()
	print("SCREEN FRAMES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A plain old screen with a few levels of nodes.
func _old_screen(count: int) -> Node:
	var screen := Node3D.new()
	screen.name = "OldScreen"
	for index in range(count):
		var part := Node3D.new()
		screen.add_child(part)
		for leaf in range(4): part.add_child(MeshInstance3D.new())
	return screen

func _switch() -> void:
	# Inside a frame's processing, where a screen changes in the game.
	await process_frame
	var old := _old_screen(60)
	root.add_child(old)
	current_scene = old
	var parts: Array = old.get_children()
	var leaf: Node = parts[0].get_child(0)
	var service := Node.new()
	old.add_child(service)
	service.add_child(Timer.new())
	var next := Node.new()
	next.name = "NextScreen"
	var packed := PackedScene.new()
	packed.pack(next)
	next.free()
	var exited := [false]
	old.tree_exited.connect(func(): exited[0] = true)
	_check(ScreenSwitch.to_packed(self, packed) == OK, "A switch changes the scene as the engine does")
	_check(exited[0] and not old.is_inside_tree(), "The old screen leaves the tree at once, as before")
	_check(old.get_child_count() == 0 and ScreenSwitch.pending_count() == 60, "Its nodes are handed over to be freed later")
	await process_frame
	_check(current_scene != null and current_scene.name == "NextScreen", "The new screen enters at the end of the frame, as before")
	_check(not is_instance_valid(old), "The old screen itself is freed at the end of the frame, as before")
	_check(is_instance_valid(parts[0]) and is_instance_valid(leaf) and not leaf.is_inside_tree(), "None of its drawn nodes is freed in the frame of the change")
	_check(not is_instance_valid(service), "Its plain service nodes are freed at the end of that frame, as before")
	await process_frame
	_check(ScreenSwitch.pending_count() < 60, "Freeing starts in the frame after the new screen entered")
	var frames := 0
	while ScreenSwitch.pending_count() > 0 and frames < 120:
		await process_frame
		frames += 1
	_check(ScreenSwitch.pending_count() == 0 and not is_instance_valid(leaf) and parts.all(func(part: Variant) -> bool: return not is_instance_valid(part)), "They are all freed over the next frames (%d)" % frames)
	_check(ScreenSwitch.home_scene() != null and ScreenSwitch.home_scene() == ScreenSwitch.home_scene(), "Home's scene is loaded once and kept")
	current_scene.queue_free()
	await process_frame

func _switch_from_input() -> void:
	await process_frame
	var old := _old_screen(30)
	root.add_child(old)
	current_scene = old
	var leaf: Node = old.get_child(0).get_child(0)
	var next := Node.new()
	next.name = "TappedScreen"
	var packed := PackedScene.new()
	packed.pack(next)
	next.free()
	var tapper := Tapper.new()
	tapper.packed = packed
	root.add_child(tapper)
	var seen := [false, false]
	scene_changed.connect(func():
		seen[0] = true
		seen[1] = is_instance_valid(leaf), CONNECT_ONE_SHOT)
	var key := InputEventKey.new()
	key.keycode = KEY_F13
	key.pressed = true
	Input.parse_input_event(key)
	for frame in range(10):
		await process_frame
		if seen[0]: break
	_check(seen[0] and current_scene != null and current_scene.name == "TappedScreen", "A key press switches the screen")
	_check(seen[1], "A switch made from input frees none of the old screen's drawn nodes before the new screen has entered")
	var frames := 0
	while ScreenSwitch.pending_count() > 0 and frames < 120:
		await process_frame
		frames += 1
	_check(not is_instance_valid(leaf), "...and frees them over the next frames (%d)" % frames)
	tapper.queue_free()
	current_scene.queue_free()
	await process_frame

## A staged chapter screen as Main's open adds it, with or without the
## opening card over it.
func _staged_screen(covered: bool) -> Array:
	var path := Registry.solo_scene(Registry.FIRST_STEPS)
	var card: Node = null
	if covered:
		card = OpeningCard.new()
		card.start(self, "screen-frames-%d" % Time.get_ticks_usec())
	Preview.request_staged_build(path)
	var scene: Node = load(path).instantiate()
	scene.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "photo_prompts": false}
	root.add_child(scene)
	return [scene, card]

func _drop_staged(pair: Array) -> void:
	var scene: Node = pair[0]
	if is_instance_valid(pair[1]): pair[1].cancel()
	var guard := 0
	while is_instance_valid(scene) and scene.building() and guard < 600:
		await process_frame
		guard += 1
	scene.queue_free()
	await process_frame
	await process_frame

func _staged_controls() -> void:
	await process_frame
	var pair := _staged_screen(true)
	var scene: Node = pair[0]
	_check(OpeningCard.covering() and scene.controls == null and scene.mode == "loading" and scene.building(), "Under the opening card a staged screen makes no controls in the frame it enters")
	await process_frame
	_check(is_instance_valid(scene.controls) and scene.mode == "loading" and is_instance_valid(scene._loading_label), "...and makes them and its loading card at the start of the next frame")
	await _drop_staged(pair)
	pair = _staged_screen(true)
	scene = pair[0]
	scene.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(is_instance_valid(scene.controls) and (scene._leave_after_load or scene._leave_after_build), "Back before then makes them and leaves once the build is done, as the loading card's Back does")
	# This suite has no Home to go back to: the screen stays.
	scene._leave_after_load = false
	scene._leave_after_build = false
	await _drop_staged(pair)
	pair = _staged_screen(false)
	scene = pair[0]
	_check(not OpeningCard.covering() and is_instance_valid(scene.controls) and scene.mode == "loading", "With no opening card over it, a staged screen makes its controls and loading card at once")
	await _drop_staged(pair)

func _back_home() -> void:
	var scene: Node = load(Registry.solo_scene(Registry.FIRST_STEPS)).instantiate()
	scene.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "photo_prompts": false}
	root.add_child(scene)
	current_scene = scene
	var guard := 0
	while scene.mode != "ready" and guard < 600:
		await process_frame
		guard += 1
	_check(scene.mode == "ready", "A chapter screen opens")
	var world: Node3D = scene.world
	var home := ScreenSwitch.home_scene()
	scene._leave()
	_check(not world.is_inside_tree() and is_instance_valid(world), "Back leaves the chapter's world out of the tree, not freed in the frame of the tap")
	await process_frame
	_check(current_scene != null and current_scene.scene_file_path == ScreenSwitch.HOME_SCENE and ScreenSwitch.home_scene() == home, "Back opens Home from its kept scene")
	_check(is_instance_valid(world) and ScreenSwitch.pending_count() > 0, "The chapter's nodes are freed over the frames after Back")
	var app: Node = current_scene
	_check(app.home_stage_view.folding(), "Home's island folds over the frames after it opens")
	guard = 0
	while (ScreenSwitch.pending_count() > 0 or app.home_stage_view.folding()) and guard < 240:
		await process_frame
		guard += 1
	_check(not is_instance_valid(world) and not app.home_stage_view.folding(), "Both are done within a few frames (%d)" % guard)
	app.queue_free()
	await process_frame
	await process_frame

## A saved Lighthouse journal at stage 3, as the solo chapter suite saves it.
func _lighthouse_save(chain: Dictionary) -> String:
	var path := str(Registry.descriptor(LIGHTHOUSE_V2).local_path)
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var journey := Journey.new(path, null, LIGHTHOUSE_V2)
	journey.load_data()
	var ok := not journey.read_only
	for index in range(2): ok = ok and journey.accept_recording(chain.pairs[index].a) and journey.accept_recording(chain.pairs[index].b)
	_check(ok, "A Lighthouse journal saves two stages")
	return path

func _lighthouse_screen() -> Node:
	var scene: Node = load(Registry.solo_scene(LIGHTHOUSE_V2)).instantiate()
	scene.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "photo_prompts": false}
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 30000
	while scene.mode != "ready" and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene.mode == "ready", "The Lighthouse ready card opens")
	scene.set_physics_process(false)
	return scene

func _settled(scene: Node) -> void:
	var guard := 0
	while scene.world.scenery_folding() and guard < 240:
		await process_frame
		guard += 1
	await process_frame

func _lighthouse_begin() -> void:
	var chain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/v2-chain.json"))
	Proofs.directory = "user://screen-frames-proofs-" + Crypto.new().generate_random_bytes(6).hex_encode()
	var path := _lighthouse_save(chain)
	_collect = true
	var kept := await _lighthouse_screen()
	await _settled(kept)
	var terrain: Node3D = kept.world.terrain
	var history: Node3D = kept.world._history_root
	kept._begin()
	_check(kept.mode == "play" and kept.world.terrain == terrain and kept.world._history_root == history, "Begin on the ready card keeps the stage the card shows, and what it remembers")
	await _settled(kept)
	var a := _fingerprint(kept.world, LIGHTHOUSE_V2, true, "begin-kept")
	# A played turn changes the world: Retry builds the stage again.
	for input: Dictionary in Registry.simulation_script(LIGHTHOUSE_V2).expand_recording_inputs(chain.pairs[2].a).slice(0, 30):
		if kept.mode != "play": break
		kept.advance_input(input)
	kept._begin()
	_check(kept.world.terrain != terrain, "After play, Retry builds the stage again")
	kept.queue_free()
	await process_frame
	var built := await _lighthouse_screen()
	await _settled(built)
	# The same Begin with the stage built again, as every Begin did before.
	built.world._as_built_stage = ""
	var old_terrain: Node3D = built.world.terrain
	built._begin()
	_check(built.mode == "play" and built.world.terrain != old_terrain, "A stage no longer as built is built again")
	await _settled(built)
	var b := _fingerprint(built.world, LIGHTHOUSE_V2, true, "begin-built")
	_collect = false
	if not _check(a.nodes == b.nodes and a.hash == b.hash, "The kept world is the world a rebuild makes (%d and %d nodes)" % [a.nodes, b.nodes]):
		var left: Array = _captured["reduced begin-kept"]
		var right: Array = _captured["reduced begin-built"]
		var shown := 0
		for line: String in left:
			if not line in right and shown < 25:
				push_error("only kept: " + line.substr(0, 300))
				shown += 1
		shown = 0
		for line: String in right:
			if not line in left and shown < 25:
				push_error("only built: " + line.substr(0, 300))
				shown += 1
	built.queue_free()
	await process_frame
	await process_frame
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var directory := DirAccess.open(Proofs.directory)
	if directory != null:
		for name: String in directory.get_files(): directory.remove(name)
	DirAccess.remove_absolute(Proofs.directory)
