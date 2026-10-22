extends SceneTree
## turn-of-the-tide@2's solo scene when a spirit drowns. While the crossing
## closes, its edges flash and the water still rising slows to meet the deck
## as it shuts. The turn then ends on the world showing the spirit go under
## (camera, face, ring, bubbles), then the ending's beat (badge and line over
## the dimmed world), then the drowned card (turn_endings.gd): the line as its
## title, Retry first, Preview beside Redo my previous turn, Back, and no
## Save turn. The redo really asks to go back, Back during the beat lands on
## the card, and nothing of the drowned turn is kept.
const KEY := "turn-of-the-tide@2"
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const Journey = preload("res://services/relay_journey.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Tide = preload("res://tests/turn_of_the_tide_witness.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const World = preload("res://presentation/tide_world.gd")
const V2 = preload("res://tests/turn_of_the_tide_v2_witness.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const TurnEndings = preload("res://presentation/turn_endings.gd")
var checks := 0
var failures := 0

## Any journey the screen saves through (a room's coordinator or a solo
## journal): records which save the screen asks for.
class DraftLog extends RefCounted:
	var live := 0
	var cleared := 0
	var last_error := ""
	func save_live_draft(_simulation: RefCounted, _periodic: bool = false) -> bool:
		live += 1
		return true
	func save_draft(recording: Dictionary) -> bool:
		if recording.is_empty(): cleared += 1
		return true
var directory := ""

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_lever_words()
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
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": false, "assistance": true}
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
			# The rising harbour is slowed to reach the sand bar's deck as it shuts.
			var water: Node3D = screen.world._water.harbour
			_check(water.has_meta("rate") and float(water.get_meta("rate")) < World.WATER_RATE, "The water rising over the closing bar slows to meet its deck as it shuts")
	_check(warned, "The sand bar closes while the spirit stands on it")
	_check(screen.mode == "drowning" and not screen.running, "A drowning ends the turn on the drown beat, not straight on a card")
	var harbour: Node3D = screen.world._water.harbour
	_check(screen.world.actor_targets["p1"].y < float(harbour.get_meta("shown")) - 0.4 and is_instance_valid(screen.world._drown_ring), "The drowned spirit heads under the water and a ring spreads")
	# Bubbles rise from where it went under, the same ones every time, and the
	# face is the knocked-out one.
	var bubbles: Array = screen.world._drown_bubbles
	var harbour_level := float(screen.world._water.harbour.get_meta("shown"))
	_check(bubbles.size() == World.DROWN_BUBBLES.size() and bubbles.all(func(bubble: MeshInstance3D) -> bool: return bubble.visible and bubble.position.y > harbour_level), "Bubbles rise from the water where the spirit went under")
	var heights: Array = bubbles.map(func(bubble: MeshInstance3D) -> float: return bubble.position.y)
	screen.world._process(1.0 / 30.0)
	_check(heights != bubbles.map(func(bubble: MeshInstance3D) -> float: return bubble.position.y), "The bubbles move while motion is on")
	_check(SpiritLook.has(World.KNOCKED_OUT) and screen.world.actors["p1"]._held_expression == World.KNOCKED_OUT, "The drowned spirit wears the knocked-out face")
	# The world keeps running through the beat: the spirit goes under.
	var before: float = screen.world.actors["p1"].position.y
	for _frame in range(screen.DROWN_BEAT_FRAMES):
		screen._physics_process(1.0 / 30.0)
		screen.world._process(1.0 / 30.0)
	_check(screen.world.actors["p1"].position.y < before - 0.3, "Through the beat the drowned spirit sinks (%.2f to %.2f)" % [before, screen.world.actors["p1"].position.y])
	# Then the ending's beat: its badge and line over the dimmed world.
	var beat: Node = screen.find_child("EndingBeat", true, false)
	_check(screen.mode == "drowning" and beat != null and _label_with(screen, "Oh no, you drowned!"), "After the drowning, the beat shows the line over the dimmed world")
	for _frame in range(int(TurnEndings.KINDS.drowned.beat)): screen._physics_process(1.0 / 30.0)
	_check(screen.mode == "review", "After the beat the ending's card shows")
	# Nothing of a drowned turn is kept: no draft, no archived attempt.
	_check(not journal.has_draft() and journal.archived_attempts().is_empty(), "A drowned turn leaves no draft or saved attempt behind")
	# The screen's one save path clears the draft for any journey, a room's too.
	var drafts := DraftLog.new()
	var probe: Node = load(Index.data(KEY).scene).instantiate()
	probe.journey = drafts
	probe.sim = b
	_check(probe._persist_draft("review") and drafts.cleared == 1 and drafts.live == 0, "In a room as solo, a drowned turn's draft is cleared, never saved")
	probe.free()
	# A snapshot without the drowning (a retry, a replay seeking back) puts it away.
	var fresh := Simulation.new()
	fresh.reset(level, "set-the-tide", initial, first, "b")
	screen.world.present(fresh.snapshot(), true)
	_check(not screen.world._drown_ring.visible and screen.world._drown_bubbles.all(func(bubble: MeshInstance3D) -> bool: return not bubble.visible) and screen.world.actors["p1"]._held_expression == SpiritLook.NORMAL and screen.world.camera_focus != "p1", "A turn without the drowning shows none of it")
	var texts := _texts(screen)
	print("REVIEW CARD ", texts)
	var title: Node = screen.find_child("EndingTitle", true, false)
	_check(title is Label and (title as Label).text == PlayerCopy.JOURNEY_DROWNED_YOU and screen.find_child("EndingBand", true, false) != null, "The card's title is the line, in its band: " + PlayerCopy.JOURNEY_DROWNED_YOU)
	for want: String in ["Retry", "Preview", PlayerCopy.SOLO_REDO_ACTION, "Back"]:
		_check(texts.has(want), "The drowned turn's card offers " + want)
	var retry := _button(screen, "Retry")
	_check(retry != null and retry.get_meta("action_id", "") == "try_again", "Retry is the card's primary button")
	_check(_button(screen, "Save turn") == null and not texts.has(PlayerCopy.RELAY_PREVIEW_93772D9A4DA5), "Save turn and the usual review title are not there")
	var preview_row: Node = _button(screen, "Preview").get_parent() if _button(screen, "Preview") != null else null
	_check(preview_row is HBoxContainer and _button(screen, PlayerCopy.SOLO_REDO_ACTION) != null and _button(screen, PlayerCopy.SOLO_REDO_ACTION).get_parent() == preview_row, "Preview and Redo my previous turn sit side by side")
	var redo := _button(screen, PlayerCopy.SOLO_REDO_ACTION)
	if redo != null:
		redo.pressed.emit()
		var after := _texts(screen)
		_check(after.any(func(text: String) -> bool: return text.begins_with("Record your path again") or text.begins_with("Go back to stage") or text == PlayerCopy.SOLO_REDO_FIRST_TURN_TITLE), "Redo my previous turn asks to go back (%s)" % str(after))
	root.remove_child(screen)
	screen.free()
	await _memory_line(level, initial)
	for filename: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	_check(preload("res://presentation/kit/primitives.gd").changed_shared_looks().is_empty(), "Every kit look shared between meshes is as it was made; code that changes a mesh's material takes its own copy (Primitives.own_material): %s" % [preload("res://presentation/kit/primitives.gd").changed_shared_looks()])
	print("TURN OF THE TIDE V2 SCREEN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Solo Slack Water after LOW: turning the tide at once drowns the memory on
## the slipway, and the card names it as the player's own memory.
func _memory_line(level: Dictionary, initial: Dictionary) -> void:
	var one := V2.pair(level, "set-the-tide", initial, Tide.a_routes()["low"], Tide.b_routes()["low"])
	_check(one.error.is_empty(), "Set the Tide plays through: " + str(one.error))
	if not one.error.is_empty(): return
	var p1 := Simulation.new()
	p1.reset(level, "slack-water", one.checkpoint, {}, "a")
	Tide.play(p1, V2.p1_route(one.checkpoint, "sea-lock"))
	var second: Dictionary = p1.export_recording()
	var p0 := Simulation.new()
	p0.reset(level, "slack-water", one.checkpoint, second, "b")
	Tide.play(p0, [["w", Tide.WHEEL["low"]], ["t"]])
	while not p0.finished: p0.step({})
	var journal := Journey.new(directory.path_join("memory.json"), null, KEY)
	journal.load_data()
	for recording: Dictionary in [one.a, one.b, second]: _check(journal.accept_recording(recording), "Earlier turns are accepted: " + journal.last_error)
	var screen: Node = load(Index.data(KEY).scene).instantiate()
	screen.journey = journal
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true}
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.set_process(false)
	await process_frame
	screen.world.set_process(false)
	screen._begin()
	for frame: Dictionary in Simulation.expand_recording_inputs(p0.export_recording()):
		if screen.mode != "play": break
		screen.advance_input(frame)
	# The memory drowned off screen: the camera goes to it during the beat.
	var world: Node3D = screen.world
	var ghost: Vector3 = world.actors["p1"].position
	var live: Vector3 = world.actors["p0"].position
	screen._physics_process(1.0 / 30.0)
	world._process(1.0 / 30.0)
	_check(screen.mode == "drowning" and world._camera_slot(world._active_player) == "p1" and world._follow_center.is_equal_approx(world._camera_center()) and absf(world._follow_center.x - ghost.x) < absf(live.x - ghost.x) * 0.25, "During the beat the camera frames the drowned memory, at once under Reduce motion (%.2f, memory at %.2f, player at %.2f)" % [world._follow_center.x, ghost.x, live.x])
	# Back during the beat ends it at once on the card.
	screen.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var title: Node = screen.find_child("EndingTitle", true, false)
	_check(screen.mode == "review" and title is Label and (title as Label).text == PlayerCopy.JOURNEY_DROWNED_MEMORY, "Back during the beat lands on the card, which solo says: " + PlayerCopy.JOURNEY_DROWNED_MEMORY)
	_check(not journal.has_draft(), "The drowned memory's turn leaves no draft")
	root.remove_child(screen)
	screen.free()
	await process_frame

## The action button names what the pip pulls at Slack Water's chains and
## bars (descriptor "lever_actions"); every other lever, and every other
## action, keeps the simulation's words, which never change.
func _lever_words() -> void:
	var screen: Node = load("res://relay_preview.gd").new()
	screen.chapter_key = KEY
	var words := func(kind: String, target: String) -> String:
		var display: Dictionary = {"context_action": {"id": kind, "label": "Pull lever" if kind == "lever" else "Light lantern", "enabled": true, "target_id": target}}
		return str(screen._name_lever_action(display).context_action.label)
	_check(words.call("lever", "boom-chain") == PlayerCopy.TURN_OF_THE_TIDE_PULL_CHAIN and words.call("lever", "punt-chain") == "Pull chain", "At a chain the button says Pull chain")
	_check(words.call("lever", "gate-bar") == PlayerCopy.TURN_OF_THE_TIDE_PULL_BAR and words.call("lever", "sea-bar") == "Pull bar", "At a bar the button says Pull bar")
	_check(words.call("lever", "boom-pin") == "Pull lever" and words.call("lever", "punt-line") == "Pull lever" and words.call("ring", "harbour-lantern") == "Light lantern", "Every other lever and action keeps its words")
	screen.free()

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
