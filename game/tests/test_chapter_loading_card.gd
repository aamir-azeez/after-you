extends SceneTree
## Every chapter opens behind one shared "Opening your chapter" card. It is on
## screen for two frames before the chapter scene starts building, stays above
## the scene change and leaves after the chapter's first frame. Each open is
## timed on this device; the card shows only when the last open of that
## chapter took 300 ms or more, or was never timed.
const Card = preload("res://presentation/chapter_loading_card.gd")
const RELAY_SCENE := "res://relay_preview.tscn"

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

func _run() -> void:
	Card.costs_path = "user://chapter-open-times-test-%s.json" % Crypto.new().generate_random_bytes(4).hex_encode()
	await _card_alone()
	change_scene_to_file("res://main.tscn")
	if await _wait_for_scene("res://main.tscn"):
		await _open_from_main()
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		await process_frame
		await process_frame
	await create_timer(0.15).timeout
	print("CHAPTER LOADING CARD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _card_alone() -> void:
	_check(Card.last_cost_usec("never-opened") == -1 and Card.expected_slow("never-opened"), "A chapter never opened here shows the card")
	Card._record("quick", Card.SHOW_AFTER_USEC - 1)
	Card._record("slow", Card.SHOW_AFTER_USEC)
	_check(not Card.expected_slow("quick") and Card.expected_slow("slow"), "Only an open of 300 ms or more last time shows the card")
	# A new process reads the same record from its file.
	Card._costs_from = ""
	_check(Card.last_cost_usec("quick") == Card.SHOW_AFTER_USEC - 1 and Card.last_cost_usec("slow") == Card.SHOW_AFTER_USEC, "Open times are kept on this device")
	var card := Card.new()
	card.start(self, "work", true)
	var bar: Node = card.find_child("OpeningProgress", true, false)
	_check(card.shown and card.visible and card.find_child("OpeningCard", true, false) != null and bar != null, "The card is built from the shared loading bar")
	_check(bar != null and not bar.bar.indeterminate and bar.status.text == "Loading…", "With reduced motion the bar holds still and reuses the Loading… line")
	var frames := [0]
	var counter := func(): frames[0] += 1
	process_frame.connect(counter)
	var seen := [-1]
	await card.run(func(): seen[0] = frames[0])
	process_frame.disconnect(counter)
	_check(seen[0] >= 2, "The work starts only after the card has been up for two frames (%d)" % seen[0])
	_check(not is_instance_valid(card) or not card.is_inside_tree(), "The card leaves after the work's next frame")
	_check(Card.last_cost_usec("work") >= 0, "The open is timed")
	var quick := Card.new()
	quick.start(self, "quick")
	_check(not quick.shown and not quick.visible and quick.get_child_count() == 0, "A quick chapter builds no card at all")
	var ran := [false]
	await quick.run(func(): ran[0] = true)
	_check(ran[0], "A quick chapter's work runs without waiting for the card")
	var cancelled := Card.new()
	cancelled.start(self, "cancelled")
	cancelled.cancel()
	await process_frame
	_check(not is_instance_valid(cancelled) and Card.last_cost_usec("cancelled") == -1, "A cancelled open leaves and records nothing")
	# A damaged record is ignored as a whole.
	var file := FileAccess.open(Card.costs_path, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	Card._costs_from = ""
	_check(Card.last_cost_usec("quick") == -1 and Card.expected_slow("quick"), "A damaged record shows the card again")

func _open_from_main() -> void:
	var app: Node = current_scene
	Card._record(RELAY_SCENE, Card.SHOW_AFTER_USEC)
	app._open_relay_preview()
	var card: Node = root.get_node_or_null("ChapterLoadingCard")
	# Whether the card is up when the chapter enters the tree to build.
	var over_build := [false]
	var watch := func(node: Node):
		if node.scene_file_path == RELAY_SCENE: over_build[0] = is_instance_valid(card) and card.is_inside_tree() and card.visible
	node_added.connect(watch)
	_check(card != null and card.visible and current_scene == app, "Opening a slow chapter puts the card up over the current screen first")
	app._open_relay_preview()
	_check(root.find_children("ChapterLoadingCard", "", false, false).size() == 1, "A second tap while the card is up opens nothing more")
	await process_frame
	_check(current_scene == app, "The chapter has not started building while the card is being drawn")
	app = null
	if not await _wait_for_scene(RELAY_SCENE): return
	node_added.disconnect(watch)
	_check(over_build[0], "The card stays up over the chapter's first build")
	for frame in range(4): await process_frame
	_check(not is_instance_valid(card) or not card.is_inside_tree(), "The card leaves once the chapter has drawn")
	var timed := Card.last_cost_usec(RELAY_SCENE)
	_check(timed >= 0 and timed != Card.SHOW_AFTER_USEC, "The open was timed (%d us)" % timed)
	current_scene._leave()
	if not await _wait_for_scene("res://main.tscn"): return
	# A chapter that opened quickly last time opens without a card.
	Card._record(RELAY_SCENE, 1000)
	current_scene._open_relay_preview()
	var hidden: Node = root.get_node_or_null("ChapterLoadingCard")
	_check(hidden != null and not hidden.visible, "A chapter that opened quickly last time shows no card")
	if not await _wait_for_scene(RELAY_SCENE): return
	current_scene._leave()
	await _wait_for_scene("res://main.tscn")

func _wait_for_scene(path: String) -> bool:
	for frame in range(60):
		await process_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			await process_frame
			return true
	_check(false, "Scene navigation reaches " + path)
	return false
