extends SceneTree
## A solo replay due to start while the app is away (notification shade,
## another app) starts paused, so the player comes back to the pause card.
## Before, the start was dropped: a replay opened from Your replays stayed on
## its loading card for good, and a replay moving on to its next part froze.
const Preview = preload("res://relay_preview.gd")
const Registry = preload("res://services/chapter_registry.gd")
const SoloReplayLaunch = preload("res://services/solo_replay_launch.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var level := Registry.definition(Registry.RELAY)
	var pairs: Array = []
	for stage: Dictionary in level.stages:
		pairs.append({"a": _fixture("v2/" + str(stage.id) + "-a"), "b": _fixture("v2/" + str(stage.id) + "-b")})
	var context := {"schema_version": 1, "chapter_key": Registry.RELAY, "selected_stage_index": 0, "accepted_pairs": [pairs[0]], "visibility_key": "relay:away-test"}
	_check(SoloReplayLaunch.write(context), "A replay hand-off is written")
	Preview.staged_build_usec = 1500
	var scene: Node = load(Registry.solo_scene(Registry.RELAY)).instantiate()
	scene.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "photo_prompts": false}
	Preview.request_staged_build(scene.scene_file_path)
	root.add_child(scene)
	await process_frame
	_check(scene._solo_replay_only and scene._world_building, "The replay opens behind its loading card")
	scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var deadline := Time.get_ticks_msec() + 60000
	while scene._world_building and Time.get_ticks_msec() < deadline: await process_frame
	await _frames(3)
	scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames(3)
	_check(scene.mode == "paused", "Back from away, the replay waits on its pause card, not the loading card: " + str(scene.mode))
	var resume := _button(scene, "Resume")
	if resume != null: resume.pressed.emit()
	_check(scene.mode == "replay" and scene.running, "Resume plays it")
	# The next part starting while away (after a part's end hold).
	scene._watch_local_pairs(pairs)
	_check(scene.mode == "replay" and scene.running and scene.replay_pair_index == 0, "Two parts play in turn")
	scene._hold_replay_end(0.05)
	scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	deadline = Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < deadline: await process_frame
	scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames(2)
	_check(scene.replay_pair_index == 1 and scene.mode == "paused", "The next part waits on the pause card instead of freezing: %s, running %s" % [scene.mode, scene.running])
	resume = _button(scene, "Resume")
	if resume != null: resume.pressed.emit()
	_check(scene.mode == "replay" and scene.running and scene.replay_pair_index == 1, "Resume plays the next part")
	Preview.staged_build_usec = 0
	scene._leaving = true
	scene.queue_free()
	await process_frame
	print("REPLAY START WHILE AWAY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _button(node: Node, text: String) -> Button:
	for child: Node in node.find_children("*", "Button", true, false):
		if child.text == text and child.is_visible_in_tree(): return child
	return null

func _frames(count: int) -> void:
	for frame in range(count): await process_frame

func _fixture(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + name + ".json"))
	return value if value is Dictionary else {}

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
