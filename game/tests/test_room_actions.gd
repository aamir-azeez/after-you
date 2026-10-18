extends SceneTree
## The room action table (presentation/room_actions.gd): every action has a
## label, a handler and a place; each state lists today's actions in today's
## order; and the solo chapter's cards draw exactly what the table says.
const RoomActions = preload("res://presentation/room_actions.gd")
const ActionButtons = preload("res://presentation/action_buttons.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Preview = preload("res://relay_preview.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Retained = preload("res://tests/retained_chapter_fixture.gd")
const SETTINGS := {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}

## Today's placements, copied from the hand-built panels this table replaced.
const GOLDEN := {
	"ready_panel": {
		"invite": ["copy_code", "share"],
		"turn": ["resume", "record", "redo_answer", "redo", "safety", "photo"],
		"header": ["refresh"],
	},
	"ready_card": {
		"invite": ["copy_code", "share"],
		"turn": ["resume", "record", "refresh", "local_replays", "restart", "redo_answer", "redo", "solo_redo", "safety", "photo", "back"],
	},
	"waiting_panel": {
		"invite": ["copy_code"],
		"turn": ["check_saved", "keep_held", "notify", "redo_answer", "share", "room_options", "your_rooms"],
		"options": ["refresh", "replays", "redo", "photo", "about", "safety"],
	},
	"waiting_card": {
		"invite": ["copy_code"],
		"turn": ["check_saved", "keep_held", "notify", "redo_answer", "redo", "refresh", "share"],
		"more": ["replays", "safety", "photo", "back"],
	},
	"complete": {
		"turn": ["replays", "local_replays", "checkpoints", "new_room", "redo_answer", "redo", "solo_redo", "safety", "photo", "back"],
	},
}

var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_rows()
	_layout()
	_facts()
	_labels()
	await _solo_cards()
	for path: String in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await process_frame
	print("ROOM ACTIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Every action has a label, a handler on the room screen and at least one place.
func _rows() -> void:
	var screen := Preview.new()
	var placed := {}
	for state: String in RoomActions.LAYOUT:
		for slot: String in RoomActions.LAYOUT[state]:
			for id: String in RoomActions.LAYOUT[state][slot]: placed[id] = true
	for id: String in RoomActions.ACTIONS:
		var row: Dictionary = RoomActions.ACTIONS[id]
		_check(not RoomActions.label(id).is_empty(), "Action has a label: " + id)
		_check(not row.has("button") or ActionButtons.DEFINITIONS.has(row.button), "A shared button action exists: " + id)
		_check(row.has("button") != row.has("text"), "Action is either a shared button or a plain labelled button: " + id)
		_check(screen.has_method(str(row.get("run", ""))), "Action names a handler on the room screen: " + id)
		_check(placed.has(id), "Action has at least one place: " + id)
		_check(row.has("when") and row.has("group"), "Action says when it applies and its Room options group: " + id)
	screen.free()

## Each state lists today's actions in today's order; no state shows an action
## twice; Room options rows have a group and keep each group together; header
## actions have an icon.
func _layout() -> void:
	_check(RoomActions.LAYOUT == GOLDEN, "Every state's slots are today's placements")
	for state: String in RoomActions.LAYOUT:
		var seen := {}
		for slot: String in RoomActions.LAYOUT[state]:
			for id: String in RoomActions.LAYOUT[state][slot]:
				_check(RoomActions.ACTIONS.has(id), "Placed action exists: %s in %s" % [id, state])
				_check(not seen.has(id), "A state shows an action once: %s in %s" % [id, state])
				seen[id] = true
				if slot == "header": _check(RoomActions.ACTIONS[id].has("icon"), "A header action has an icon: " + id)
		var groups: Array[String] = []
		for id: String in RoomActions.LAYOUT[state].get("options", []):
			var group := str(RoomActions.ACTIONS[id].group)
			_check(not group.is_empty(), "A Room options action has a group: " + id)
			if groups.is_empty() or groups[-1] != group:
				_check(not groups.has(group), "Room options keeps each group together: " + group)
				groups.append(group)
	_check(RoomActions.REDO_ACTIONS == ["redo_answer", "redo", "solo_redo"], "Pause and review cards add the three redo rows")

## Rows apply when their facts hold, read in order and only as far as needed;
## each state's slot filters to what the hand-built panel showed.
func _facts() -> void:
	var read: Array[String] = []
	var none := func(name: String) -> bool:
		read.append(name)
		return false
	_check(RoomActions.shown("ready_card", "turn", none) == ["record", "back"], "With no facts the ready card is Record and Back")
	_check(not read.has("pending") and not read.has("watchable"), "Facts after a failed one are not read")
	var solo := _facts_from({"solo": true, "restart": true, "solo_redo": true})
	_check(RoomActions.shown("ready_card", "turn", solo) == ["record", "restart", "solo_redo", "back"], "A solo second turn: Record, Restart chapter, Redo, Back")
	solo = _facts_from({"solo": true, "watchable": true, "solo_redo": true, "draft": true})
	_check(RoomActions.shown("ready_card", "turn", solo) == ["resume", "record", "local_replays", "solo_redo", "back"], "A solo draft with an archived attempt adds Resume and Replays")
	_check(RoomActions.shown("complete", "turn", solo) == ["local_replays", "checkpoints", "solo_redo", "back"], "A finished solo chapter: Replays, Retry, Redo, Back")
	var host := _facts_from({"online": true, "invited": true, "share": true, "redo": true, "my_turn": true, "photo": true})
	_check(RoomActions.shown("ready_panel", "invite", host) == ["copy_code", "share"], "A host before the friend joins copies the code and shares")
	_check(RoomActions.shown("ready_panel", "turn", host) == ["record", "redo", "photo"], "A host's ready panel: Record, then redo and photo")
	_check(RoomActions.shown("ready_panel", "header", host) == ["refresh"], "The ready panel keeps Refresh in its header")
	_check(RoomActions.shown("ready_card", "turn", host) == ["record", "refresh", "redo", "photo", "back"], "The narrow ready card keeps Refresh in its list")
	var waiting := _facts_from({"online": true, "joined": true, "notifications": true, "share": true, "redo": true, "watchable": true, "photo": true, "about": true, "safety": true, "options": true})
	_check(RoomActions.shown("waiting_panel", "turn", waiting) == ["notify", "share", "room_options", "your_rooms"], "A host waiting with a friend: Notify, Share, Room options, Your rooms")
	_check(RoomActions.shown("waiting_panel", "options", waiting) == ["refresh", "replays", "redo", "photo", "about", "safety"], "Room options: Refresh, Replays, Turn requests, Photo, About, Report")
	_check(RoomActions.shown("waiting_card", "turn", waiting) == ["notify", "redo", "refresh", "share"], "The narrow waiting card keeps redo and Refresh in its list")
	_check(RoomActions.shown("waiting_card", "more", waiting) == ["replays", "safety", "photo", "back"], "The narrow waiting card ends with Replays, Report, Photo and Back")
	var answer := _facts_from({"online": true, "redo": true, "redo_accept": true, "options": true})
	_check(RoomActions.shown("waiting_panel", "turn", answer) == ["redo_answer", "room_options", "your_rooms"], "A friend's redo request stays on the waiting panel")
	_check(not RoomActions.shown("waiting_panel", "options", answer).has("redo"), "An answerable redo request is not repeated in Room options")
	var pending := _facts_from({"online": true, "pending": true, "held": true, "watchable": true, "about": true, "safety": true, "options": true})
	_check(RoomActions.shown("waiting_panel", "turn", pending) == ["check_saved", "keep_held", "room_options", "your_rooms"], "A held turn: Check status, keep it, Room options, Your rooms")
	_check(RoomActions.shown("waiting_panel", "options", pending) == ["replays", "about", "safety"], "A pending turn's Room options leave out Refresh")
	var online_done := _facts_from({"online": true, "watchable": true, "safety": true})
	_check(RoomActions.shown("complete", "turn", online_done) == ["replays", "new_room", "safety", "back"], "A finished room: Replays, New room, Report, Back")
	var source := FileAccess.get_file_as_string("res://relay_preview.gd")
	var names := {}
	for id: String in RoomActions.ACTIONS:
		for name: String in RoomActions.ACTIONS[id].when: names[name.trim_prefix("!")] = true
	for name: String in names.keys() + ["my_turn"]:
		_check(source.contains("\t\t\"%s\": return " % name), "The room screen reads the fact: " + name)

## Labels come from the shared buttons or the row; redo labels are shared with
## the legacy room page.
func _labels() -> void:
	_check(RoomActions.label("record") == "Record" and RoomActions.label("refresh") == "Refresh" and RoomActions.label("checkpoints") == "Retry", "Shared buttons keep their own labels")
	_check(RoomActions.label("share") == "Share current room" and RoomActions.SHARE_SHORT == "Share room" and RoomActions.SHARE_SCOPE == "All friends", "Share keeps its labels")
	_check(RoomActions.label("solo_redo") == PlayerCopy.SOLO_REDO_ACTION, "Solo redo keeps its label")
	_check(RoomActions.label("redo", _facts_from({"my_turn": true})) == "Ask for redo" and RoomActions.label("redo", _facts_from({})) == "Turn requests", "Redo reads Ask for redo on this player's turn, else Turn requests")
	_check(RoomActions.label("redo_answer") == "Redo requested", "An answerable request reads Redo requested")
	_check(RoomActions.redo_label(true, true) == "Redo requested" and RoomActions.redo_label(false, true) == "Ask for redo" and RoomActions.redo_label(false, false) == "Turn requests", "The shared redo label")
	for path: String in ["res://presentation/friends_screen.gd", "res://presentation/legacy_room_flow.gd"]:
		var text := FileAccess.get_file_as_string(path)
		_check(not text.contains("\"Share current room\"") and not text.contains("\"All friends\"") and not text.contains("\"Ask for redo\""), "Uses the table's Share and redo labels: " + path)

## The solo relay chapter's cards draw the table's rows, in order.
func _solo_cards() -> void:
	var path := "user://room-actions-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	paths.append(path)
	_check(Retained.seed(path, Registry.RELAY), "Seed the published older journal")
	var app: Node = load(Registry.solo_scene(Registry.RELAY)).instantiate()
	app.chapter_key = Registry.RELAY
	app.journey = Journey.new(path, null, Registry.RELAY)
	app.settings = SETTINGS.duplicate()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	for frame in range(3): await process_frame
	_check(_texts(app) == ["Record", "Restart chapter", "Back"], "The older rules' first turn: Record, Restart chapter, Back: " + str(_texts(app)))
	_check(_texts(app) == _table_texts(app, "ready_card", ["turn"]), "The first ready card is exactly the table's rows")
	_check(app.journey.accept_recording(_fixture("relay-a")), "The first turn is saved")
	app._show_ready()
	_check(_texts(app) == ["Record", "Restart chapter", PlayerCopy.SOLO_REDO_ACTION, "Back"], "The second turn's card follows the table: " + str(_texts(app)))
	_check(_texts(app) == _table_texts(app, "ready_card", ["turn"]), "The ready card is exactly the table's rows")
	for name: String in ["relay-b", "garden-a", "garden-b"]: _check(app.journey.accept_recording(_fixture(name)), "Saved " + name)
	app._show_ready()
	_check(app.mode == "complete" and _texts(app) == ["Replays", "Retry", PlayerCopy.SOLO_REDO_ACTION, "Back"], "The finished card follows the table: " + str(_texts(app)))
	_check(_texts(app) == _table_texts(app, "complete", ["turn"]), "The finished card is exactly the table's rows")
	app.queue_free()
	for frame in range(3): await process_frame

func _table_texts(app: Node, state: String, slots: Array) -> Array:
	var facts: Callable = app._room_facts()
	var texts := []
	for slot: String in slots:
		for id: String in RoomActions.shown(state, slot, facts): texts.append(RoomActions.label(id, facts))
	return texts

func _texts(app: Node) -> Array:
	return app.overlay.find_children("*", "Button", true, false).filter(func(button: Button): return button.is_visible_in_tree()).map(func(button: Button): return button.text)

func _facts_from(values: Dictionary) -> Callable:
	return func(name: String) -> bool: return values.get(name, false)

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + description)
