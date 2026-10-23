extends SceneTree
## Every chapter opens behind one shared "Opening your chapter" card. It is on
## screen for two frames before the chapter scene starts building, stays above
## the scene change and leaves after the chapter's first frame. Each open is
## timed on this device; the card shows only when the last open of that
## chapter took 300 ms or more, or was never timed.
const Card = preload("res://presentation/chapter_loading_card.gd")
const RELAY_SCENE := "res://relay_preview.tscn"
const Bar = preload("res://presentation/replay_loading_bar.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const TIDE := "turn-of-the-tide@1"

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
	await _bar_motion()
	await _prepare_keeps_frames()
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

## The card's bar: eased toward each new share, never back, with a shimmer
## that keeps passing while no progress arrives; reduced motion steps instead.
func _bar_motion() -> void:
	var bar := Bar.new()
	root.add_child(bar)
	bar.follow(0.0)
	var values: Array = []
	var phases: Array = []
	var feed := [0.2, 0.6, 0.3, 0.3, 0.9, 0.5]
	for index in range(feed.size() * 4):
		if index % 4 == 0: bar.follow(feed[index / 4])
		bar.advance(1.0 / 60.0)
		values.append(bar.bar.value)
		phases.append(bar.shimmer_phase)
	var forward := true
	for index in range(1, values.size()): forward = forward and values[index] >= values[index - 1]
	_check(forward, "The bar never moves back, even when a lower share arrives")
	_check(values[3] > values[0] and values[3] < 0.2, "The bar eases toward a new share over a few frames (%.3f, %.3f)" % [values[0], values[3]])
	_check(bar.target == 0.9, "The bar keeps the highest share it was given")
	var held := bar.bar.value
	var before: float = bar.shimmer_phase
	for frame in range(30): bar.advance(1.0 / 60.0)
	_check(bar.bar.value > held and bar.bar.value <= 0.9, "With no new progress the bar still closes on its share")
	_check(not is_equal_approx(bar.shimmer_phase, before) and phases.size() == feed.size() * 4 and not is_equal_approx(phases[0], phases[-1]), "The shimmer keeps moving while the bar waits")
	bar.follow(1.0)
	var gap: float = 1.0 - bar.shown
	bar.advance(5.0)
	_check(1.0 - bar.shown > gap * 0.3, "A long blocked frame moves the bar one capped step, not straight to its end")
	bar.queue_free()
	var still := Bar.new()
	still.reduced_motion = true
	root.add_child(still)
	still.follow(0.4)
	_check(is_equal_approx(still.bar.value, 0.4) and still._shimmer == null and not still.bar.indeterminate, "With reduced motion the bar steps to each share and nothing sweeps")
	still.follow(0.1)
	_check(is_equal_approx(still.bar.value, 0.4), "With reduced motion the bar still never moves back")
	var creep := [Card.creeping(0.3, 0), Card.creeping(0.3, 1000000), Card.creeping(0.3, 4000000), Card.creeping(0.3, 60000000)]
	_check(is_equal_approx(creep[0], 0.3) and creep[1] > creep[0] and creep[2] > creep[1] and creep[3] < Card.PREPARED and Card.creeping(Card.PREPARED, 9000000) == Card.PREPARED, "Waiting on a long step, the share creeps on but never reaches the end of the work (%s)" % str(creep))
	still.queue_free()
	await process_frame

## Before the scene change the card loads the chapter scene on the loader's
## threads and proves its saved journey on a worker: frames keep coming, the
## bar moves on them, and the save is remembered for the chapter's own load.
func _prepare_keeps_frames() -> void:
	var directory := "user://loading-card-test-%s" % Crypto.new().generate_random_bytes(4).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	var proofs_before: String = Proofs.directory
	Proofs.directory = directory.path_join("proofs")
	Proofs._chapters.clear()
	Proofs._stages.clear()
	Proofs._last_remembered.clear()
	var path := directory.path_join("tide.json")
	var level := Registry.definition(TIDE)
	var seed := Journey.new(path, null, TIDE)
	seed.load_data()
	var stage := str(level.stages[0].id)
	var seeded: bool = seed.accept_recording(_fixture(stage + "-a")) and seed.accept_recording(_fixture(stage + "-b")) and seed.accept_recording(_fixture(str(level.stages[1].id) + "-a"))
	_check(seeded and seed.role() == "b", "A Tide journey on its second stage is saved")
	# Opened fresh: nothing of this save is remembered yet.
	Proofs._chapters.clear()
	Proofs._stages.clear()
	Proofs._last_remembered.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Proofs.directory.path_join(Proofs._path(TIDE).get_file())))
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)).relay
	_check(Proofs.recall(Journey.new(path, null, TIDE), state).is_empty(), "The save starts unproven")
	_check(Card.chapters_for_scene(Registry.solo_scene(TIDE)).map(func(source): return source.chapter) == [TIDE], "The Tide scene proves the Tide save")
	var card := Card.new()
	card.start(self, "prepare-test", false)
	await card.drawn()
	var values: Array = []
	var phases: Array = []
	var bar: Node = card.find_child("OpeningProgress", true, false)
	var watch := func():
		values.append(bar.bar.value)
		phases.append(bar.shimmer_phase)
	process_frame.connect(watch)
	var scene := Registry.solo_scene(TIDE)
	await card._prepare(scene, [{"chapter": TIDE, "path": path}])
	process_frame.disconnect(watch)
	var forward := true
	for index in range(1, values.size()): forward = forward and values[index] >= values[index - 1]
	_check(values.size() >= 4, "Frames keep coming while the save is proved and the scene loads (%d)" % values.size())
	_check(forward and values.size() > 1 and values[-1] > values[0], "The bar moves forward over those frames (%s)" % str(values.slice(0, 6)))
	_check(phases.size() > 1 and not is_equal_approx(phases[0], phases[-1]), "The shimmer moves over those frames")
	_check(bar.target == Card.BUILDING, "Before the chapter builds the bar waits near its end")
	_check(not Proofs.recall(Journey.new(path, null, TIDE), state).is_empty(), "The save is remembered for the chapter's own load")
	_check(ResourceLoader.load_threaded_get_status(scene) == ResourceLoader.THREAD_LOAD_LOADED and card._loading == scene, "The chapter scene is loaded off the main thread")
	card.cancel()
	await process_frame
	_check(Card.last_cost_usec("prepare-test") == -1, "A cancelled prepared open records nothing")
	# A chapter that builds in place and is left (freed) while its save is
	# proved: the card leaves with it and its work never runs.
	var screen := Node.new()
	root.add_child(screen)
	var gone := Card.new()
	gone.start(self, "gone-test", false)
	gone.run(Callable(screen, "add_to_group").bind("built"), TIDE)
	screen.free()
	for frame in range(8): await process_frame
	_check(not is_instance_valid(gone) and root.get_node_or_null("ChapterLoadingCard") == null and Card.last_cost_usec("gone-test") == -1, "A chapter left while its card waits takes the card with it")
	for folder: String in [Proofs.directory, directory]:
		for name: String in DirAccess.get_files_at(folder): DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(name)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	Proofs.directory = proofs_before
	Proofs._chapters.clear()
	Proofs._stages.clear()
	Proofs._last_remembered.clear()

func _fixture(name: String) -> Dictionary:
	for folder: String in ["cooperative", "journey"]:
		var file := "res://tests/fixtures/" + folder + "/" + name + ".json"
		if FileAccess.file_exists(file): return JSON.parse_string(FileAccess.get_file_as_string(file))
	return {}

func _open_from_main() -> void:
	var app: Node = current_scene
	Card._record(RELAY_SCENE, Card.SHOW_AFTER_USEC)
	app.journey_flow.open_solo_chapter(Registry.RELAY)
	var card: Node = root.get_node_or_null("ChapterLoadingCard")
	# Whether the card is up when the chapter enters the tree to build.
	var over_build := [false]
	var watch := func(node: Node):
		if node.scene_file_path == RELAY_SCENE: over_build[0] = is_instance_valid(card) and card.is_inside_tree() and card.visible
	node_added.connect(watch)
	_check(card != null and card.visible and current_scene == app, "Opening a slow chapter puts the card up over the current screen first")
	app.journey_flow.open_solo_chapter(Registry.RELAY)
	_check(root.find_children("ChapterLoadingCard", "", false, false).size() == 1, "A second tap while the card is up opens nothing more")
	await process_frame
	_check(current_scene == app, "The chapter has not started building while the card is being drawn")
	app = null
	if not await _wait_for_scene(RELAY_SCENE): return
	node_added.disconnect(watch)
	_check(over_build[0], "The card stays up over the chapter's first build")
	# The chapter builds over a few frames behind the card (staged build).
	var waited := 0
	while is_instance_valid(card) and card.is_inside_tree() and waited < 600:
		await process_frame
		waited += 1
	_check(not is_instance_valid(card) or not card.is_inside_tree(), "The card leaves once the chapter has drawn (%d frames)" % waited)
	var timed := Card.last_cost_usec(RELAY_SCENE)
	_check(timed >= 0 and timed != Card.SHOW_AFTER_USEC, "The open was timed (%d us)" % timed)
	current_scene._leave()
	if not await _wait_for_scene("res://main.tscn"): return
	# A chapter that opened quickly last time opens without a card.
	Card._record(RELAY_SCENE, 1000)
	current_scene.journey_flow.open_solo_chapter(Registry.RELAY)
	var hidden: Node = root.get_node_or_null("ChapterLoadingCard")
	_check(hidden != null and not hidden.visible, "A chapter that opened quickly last time shows no card")
	if not await _wait_for_scene(RELAY_SCENE): return
	current_scene._leave()
	await _wait_for_scene("res://main.tscn")

func _wait_for_scene(path: String) -> bool:
	# The card loads the scene on the loader's threads first: wait by time too.
	var deadline := Time.get_ticks_msec() + 20000
	var frame := 0
	while frame < 60 or Time.get_ticks_msec() < deadline:
		frame += 1
		await process_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			await process_frame
			return true
	_check(false, "Scene navigation reaches " + path)
	return false
