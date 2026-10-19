extends SceneTree
## turn-of-the-tide@2's solo scene when a spirit drowns: the turn ends on the
## world showing it go under for the drown beat, then the review card says
## "you drowned" and offers Retry, Redo my previous turn and Back with Save
## turn off, and the redo really asks to go back. While the crossing closes,
## its edges flash and the water still rising slows to meet the deck as it
## shuts; after the drowning the spirit heads under the water.
const KEY := "turn-of-the-tide@2"
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const Journey = preload("res://services/relay_journey.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Tide = preload("res://tests/turn_of_the_tide_witness.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const World = preload("res://presentation/tide_world.gd")
var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	directory = "user://tide-v2-screen-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	var level := Registry.definition(KEY)
	var initial := Registry.initial_checkpoint(KEY)
	var a := Simulation.new()
	a.reset(level, "set-the-tide", initial, {}, "a")
	Tide.play(a, Tide.a_routes()["low"])
	var first: Dictionary = a.export_recording()
	# The drowned second turn: onto the sand bar, and still there when it shuts.
	var b := Simulation.new()
	b.reset(level, "set-the-tide", initial, first, "b")
	Tide.play(b, [["w", [-320, 352]], ["w", [-60, 352]]])
	while not b.finished: b.step({})
	var frames: Array = Simulation.expand_recording_inputs(b.export_recording())
	var journal := Journey.new(directory.path_join("drowned.json"), null, KEY)
	journal.load_data()
	_check(journal.accept_recording(first), "The memory's turn is accepted: " + journal.last_error)
	var screen: Node = load(Index.data(KEY).scene).instantiate()
	screen.journey = journal
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true}
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.set_process(false)
	await process_frame
	screen.world.set_process(false)
	screen._begin()
	var warned := false
	for frame: Dictionary in frames:
		if screen.mode != "play": break
		screen.advance_input(frame)
		if not warned and not screen.sim.snapshot().route_progress.closing.is_empty():
			warned = true
			var edges: Array = screen.world._decks["sand-1"].get_children().filter(func(edge: Node) -> bool: return edge.has_meta("edge"))
			_check(edges.size() == 2 and edges.all(func(edge: Node) -> bool: return edge.has_meta("warned")), "A closing crossing's edges flash")
	_check(warned, "The sand bar closes while the spirit stands on it")
	_check(screen.mode == "drowning" and not screen.running, "A drowning ends the turn on the drown beat, not straight on a card")
	var harbour: Node3D = screen.world._water.harbour
	_check(screen.world.actor_targets["p1"].y < float(harbour.get_meta("shown")) - 0.4 and is_instance_valid(screen.world._drown_ring), "The drowned spirit heads under the water and a ring spreads")
	for _frame in range(screen.DROWN_BEAT_FRAMES): screen._physics_process(1.0 / 30.0)
	_check(screen.mode == "review", "After the beat the review card shows")
	var texts := _texts(screen)
	print("REVIEW CARD ", texts)
	_check(_label_with(screen, PlayerCopy.JOURNEY_DROWNED_YOU), "The card says: " + PlayerCopy.JOURNEY_DROWNED_YOU)
	for want: String in ["Retry", PlayerCopy.SOLO_REDO_ACTION, "Back"]:
		_check(texts.has(want), "The drowned turn's card offers " + want)
	var save := _button(screen, "Save turn")
	_check(save != null and save.disabled, "Save turn is off for a drowned turn")
	var redo := _button(screen, PlayerCopy.SOLO_REDO_ACTION)
	if redo != null:
		redo.pressed.emit()
		var after := _texts(screen)
		_check(after.any(func(text: String) -> bool: return text.begins_with("Record your path again") or text.begins_with("Go back to stage") or text == PlayerCopy.SOLO_REDO_FIRST_TURN_TITLE), "Redo my previous turn asks to go back (%s)" % str(after))
	root.remove_child(screen)
	screen.free()
	for filename: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("TURN OF THE TIDE V2 SCREEN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _texts(screen: Node) -> Array:
	var out: Array = []
	for node: Node in screen.find_children("*", "", true, false):
		if node is Button and (node as Button).is_visible_in_tree(): out.append((node as Button).text)
		elif node is Label and (node as Label).is_visible_in_tree(): out.append((node as Label).text)
	return out

func _label_with(screen: Node, text: String) -> bool:
	for node: Node in screen.find_children("*", "Label", true, false):
		if (node as Label).is_visible_in_tree() and (node as Label).text.contains(text): return true
	return false

func _button(screen: Node, text: String) -> Button:
	for node: Node in screen.find_children("*", "Button", true, false):
		if (node as Button).is_visible_in_tree() and (node as Button).text == text: return node
	return null

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
