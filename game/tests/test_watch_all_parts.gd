extends "res://tests/test_solo_replay_remove_part.gd"
## "Watch all parts" plays an attempt from its first part to its last. Before,
## it handed over the last part as the one selected, so only that part played
## and the replay then went Home.
const Preview = preload("res://relay_preview.gd")
const SoloReplayLaunch = preload("res://services/solo_replay_launch.gd")

func _run() -> void:
	directory = "user://watch-all-parts-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	var paths := _seed()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := await _app(viewport, paths, "watch-all")
	var watch_all := _button(app.overlay, "Watch all parts")
	_check(watch_all != null and not watch_all.disabled, "A two-part attempt offers Watch all parts")
	if watch_all != null:
		watch_all.pressed.emit()
		await _frames(3)
	var context: Dictionary = app.opened[-1].context if not app.opened.is_empty() else {}
	_check(context.get("accepted_pairs", []).size() == 2 and int(context.get("selected_stage_index", -1)) == 1 and int(context.get("start_stage_index", -1)) == 0, "It hands over both parts, to play from the first")
	var bad := context.duplicate(true)
	bad.start_stage_index = 2
	_check(SoloReplayLaunch.write(bad) and SoloReplayLaunch.consume(Preview.solo_replay_rules(Registry.RELAY, Registry.definition(Registry.RELAY), Registry.simulation_script(Registry.RELAY))).get("status") == "error", "A start after the selected part is refused")
	SoloReplayLaunch.discard()
	viewport.queue_free()
	await process_frame
	# The chapter plays the parts in turn from the first.
	_check(SoloReplayLaunch.write(context), "The hand-off is written")
	var scene: Node = load(Registry.solo_scene(Registry.RELAY)).instantiate()
	scene.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "photo_prompts": false}
	root.add_child(scene)
	scene.set_physics_process(false)
	await _frames(2)
	_check(scene._solo_replay_only and scene.mode == "replay" and scene.replay_pair_index == 0, "Watch all parts starts at part 1: %s, part %d" % [scene.mode, scene.replay_pair_index + 1])
	scene._replay_ended()
	_check(scene.mode == "replay" and scene.running and scene.replay_pair_index == 1 and not scene._leaving, "...then plays part 2")
	# Watch replay on one part still plays that part alone.
	var single := context.duplicate(true)
	single.erase("start_stage_index")
	scene._leaving = true
	scene.queue_free()
	await process_frame
	_check(SoloReplayLaunch.write(single), "A one-part hand-off is written")
	scene = load(Registry.solo_scene(Registry.RELAY)).instantiate()
	scene.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "photo_prompts": false}
	root.add_child(scene)
	scene.set_physics_process(false)
	await _frames(2)
	_check(scene.mode == "replay" and scene.replay_pair_index == 1, "Watch replay on part 2 starts at part 2")
	scene._leaving = true
	scene.queue_free()
	await process_frame
	print("WATCH ALL PARTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
