extends SceneTree
## A paid chapter's replay from Your replays, with the app sent to the
## background and back: the chapter checks access again, then the replay waits
## on its pause card. Before, the granted check drew the chapter's ready card
## from a journal the replay never opened.
const Registry = preload("res://services/chapter_registry.gd")
const SoloReplayLaunch = preload("res://services/solo_replay_launch.gd")
const AccessTests = preload("res://tests/test_chapter_access.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var key := Registry.ROLLING_HOME
	var stage: String = Registry.definition(key).stages[0].id
	var folder := "journey" if Registry.is_journey(key) else "cooperative"
	var pair := {"a": _fixture(stage + "-a", folder), "b": _fixture(stage + "-b", folder)}
	_check(not pair.a.is_empty() and not pair.b.is_empty(), "The chapter's first stage has fixture turns")
	_check(SoloReplayLaunch.write({"schema_version": 1, "chapter_key": key, "selected_stage_index": 0, "accepted_pairs": [pair], "visibility_key": "paid:away-test"}), "A replay hand-off is written")
	var store := AccessTests.Store.new()
	store._configuration = {"purchase_mode": "google_play", "entitlement_id": "full_journey_play"}
	var screen: Node = load(Registry.solo_scene(key)).instantiate()
	screen.chapter_key = key
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	screen.purchase_service_factory = func(): return store
	root.add_child(screen)
	screen.set_physics_process(false)
	store.answer(store.requests[-1], true)
	await _frames(3)
	_check(screen._solo_replay_only and screen.mode == "replay" and screen.running, "With access, the replay plays: " + str(screen.mode))
	screen.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await process_frame
	screen.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame
	if not store.requests.is_empty(): store.answer(store.requests[-1], true)
	await _frames(3)
	_check(screen.mode == "paused" and screen._solo_replay_only and screen.replay_pair_index == 0, "Back with access, the replay waits on its pause card: " + str(screen.mode))
	var resume := _button(screen, "Resume")
	if resume != null: resume.pressed.emit()
	_check(screen.mode == "replay" and screen.running, "Resume plays it on")
	# Sent away while it holds at its end: back with access, it ends as it
	# would have (this one part done, the replay leaves) instead of waiting
	# on a Resume that has nothing left to play.
	screen.replay_cursor = screen.replay_frames.size()
	screen._hold_replay_end(30.0)
	screen.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await process_frame
	screen.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame
	if not store.requests.is_empty(): store.answer(store.requests[-1], true)
	await process_frame
	_check(not is_instance_valid(screen) or screen._leaving, "A replay held at its end goes on when access returns: " + (str(screen.mode) if is_instance_valid(screen) else "left"))
	if not is_instance_valid(screen):
		print("PAID REPLAY AFTER BACKGROUND: %d checks, %d failures" % [checks, failures])
		quit(1 if failures else 0)
		return
	screen._leaving = true
	screen.queue_free()
	await process_frame
	print("PAID REPLAY AFTER BACKGROUND: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _button(node: Node, text: String) -> Button:
	for child: Node in node.find_children("*", "Button", true, false):
		if child.text == text and child.is_visible_in_tree(): return child
	return null

func _frames(count: int) -> void:
	for frame in range(count): await process_frame

func _fixture(name: String, folder: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/%s/%s.json" % [folder, name]))
	return value if value is Dictionary else {}

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
