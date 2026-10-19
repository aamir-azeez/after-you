extends SceneTree
## The room action table (presentation/room_actions.gd): every action has a
## label, a handler and a place; each panel state is one column of the owner's
## mapping (2026-10-18) and each card state lists today's actions in today's
## order; Room options groups rows by section; and the solo chapter's cards
## draw exactly what the table says.
const RoomActions = preload("res://presentation/room_actions.gd")
const ActionButtons = preload("res://presentation/action_buttons.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Preview = preload("res://relay_preview.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Retained = preload("res://tests/retained_chapter_fixture.gd")
const RedoNotice = preload("res://presentation/redo_request_notice.gd")
const SETTINGS := {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}

## The owner's mapping for the wide panel (one state per column), and the
## card placements copied from the hand-built cards this table replaced.
const GOLDEN := {
	"ready_panel": {
		"header": ["refresh"],
		"primary": ["resume", "record"],
		"turn": ["redo_answer"],
		"pair": ["room_options"],
		"options": ["share", "redo_answer", "redo", "replays", "photo", "about", "safety"],
	},
	"ready_panel_invite": {
		"header": ["refresh"],
		"invite": ["copy_code", "share"],
		"primary": ["resume", "record"],
		"pair": ["room_options"],
		"options": ["copy_code", "share", "photo", "about"],
	},
	"waiting_panel": {
		"header": ["refresh"],
		"status": ["alerts"],
		"primary": ["notify"],
		"turn": ["redo_answer"],
		"pair": ["room_options", "your_rooms"],
		"options": ["share", "notify", "redo_answer", "redo", "replays", "photo", "about", "safety"],
	},
	"waiting_panel_invite": {
		"header": ["refresh"],
		"status": ["alerts"],
		"invite": ["copy_code"],
		"primary": ["share"],
		"pair": ["room_options", "your_rooms"],
		"options": ["copy_code", "share", "notify", "photo", "about"],
	},
	"waiting_panel_pending": {
		"invite": ["copy_code"],
		"primary": ["check_saved"],
		"turn": ["keep_held"],
		"pair": ["room_options", "your_rooms"],
		"options": ["copy_code", "share", "replays", "about", "safety"],
	},
	"ready_card": {
		"invite": ["copy_code_button", "share"],
		"turn": ["resume", "record", "refresh", "local_replays", "restart", "redo_answer", "redo", "solo_redo", "safety", "photo", "back"],
	},
	"waiting_card": {
		"invite": ["copy_code"],
		"turn": ["check_saved", "keep_held", "alerts", "notify", "redo_answer", "redo", "refresh", "share"],
		"more": ["replays", "safety", "photo", "back"],
	},
	"complete": {
		"turn": ["hard_again", "replays", "local_replays", "checkpoints", "new_room", "redo_answer", "redo", "solo_redo", "safety", "photo", "back"],
	},
}
const PANEL_SLOTS := ["header", "status", "invite", "primary", "turn", "pair", "options"]
const CARD_SLOTS := ["invite", "turn", "more"]

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
	await _redo_notice()
	await _solo_cards()
	for path: String in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await process_frame
	print("ROOM ACTIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Every action has a label, at least one place, and either a handler on the
## room screen that takes exactly its bound arguments or a custom widget.
func _rows() -> void:
	var screen := Preview.new()
	var methods := {}
	for method: Dictionary in screen.get_method_list(): methods[method.name] = method
	var placed := {}
	for state: String in RoomActions.LAYOUT:
		for slot: String in RoomActions.LAYOUT[state]:
			for id: String in RoomActions.LAYOUT[state][slot]: placed[id] = true
	for id: String in RoomActions.ACTIONS:
		var row: Dictionary = RoomActions.ACTIONS[id]
		_check(not RoomActions.label(id).is_empty(), "Action has a label: " + id)
		_check(not row.has("button") or ActionButtons.DEFINITIONS.has(row.button), "A shared button action exists: " + id)
		_check(row.has("button") != row.has("text"), "Action is either a shared button or a plain labelled button: " + id)
		_check(placed.has(id), "Action has at least one place: " + id)
		_check(row.has("when"), "Action says when it applies: " + id)
		_check(not row.has("section") or RoomActions.SECTIONS.has(row.section), "A row's Room options section exists: " + id)
		if row.has("drawn"):
			var hook: Dictionary = methods.get(str(row.drawn), {})
			_check(not hook.is_empty() and hook.args.size() - hook.default_args.size() <= 1 and hook.args.size() >= 1, "A drawn hook on the room screen takes the row's button: " + id)
		if row.has("widget"):
			_check(not row.has("run") and not row.has("bind"), "A widget row is wired only by its widget: " + id)
			var widget: Dictionary = methods.get(str(row.widget), {})
			_check(not widget.is_empty() and widget.args.size() == 4, "A widget row names a room screen builder taking parent, id, facts and look: " + id)
			if row.has("option"):
				var option: Dictionary = methods.get(str(row.option), {})
				_check(not option.is_empty() and option.args.size() == 2, "An option row names a room screen method taking the sheet row and the id: " + id)
			continue
		var method: Dictionary = methods.get(str(row.get("run", "")), {})
		_check(not method.is_empty(), "Action names a handler on the room screen: " + id)
		if method.is_empty(): continue
		var takes: int = row.get("bind", []).size() + (1 if row.get("with_receipt", false) else 0)
		var most: int = method.args.size()
		var least: int = most - method.default_args.size()
		_check(takes >= least and takes <= most, "Handler %s takes the %d arguments the row gives it: %s" % [row.run, takes, id])
	_check(RoomActions.ACTIONS.photo.get("with_receipt", false) and RoomActions.ACTIONS.photo.get("bind", []).is_empty(), "The photo handler takes one argument, the receipt")
	screen.free()

## Each state lists today's actions in today's order; no state shows an action
## twice; custom actions sit only in invite or turn slots; header actions are
## plain rows with an icon.
func _layout() -> void:
	_check(RoomActions.LAYOUT == GOLDEN, "Every panel state is its mapping column and every card keeps today's placements")
	for state: String in RoomActions.LAYOUT:
		var panel := RoomActions.is_panel(state)
		var seen := {}
		for slot: String in RoomActions.LAYOUT[state]:
			_check(slot in (PANEL_SLOTS if panel else CARD_SLOTS), "A state uses only its kind's slots: %s.%s" % [state, slot])
			for id: String in RoomActions.LAYOUT[state][slot]:
				_check(RoomActions.ACTIONS.has(id), "Placed action exists: %s in %s" % [id, state])
				var row: Dictionary = RoomActions.ACTIONS[id]
				# Room options also lists rows its panel shows.
				if slot != "options":
					_check(not seen.has(id), "A state shows an action once: %s in %s" % [id, state])
					seen[id] = true
				if slot == "options":
					_check(row.has("section") and RoomActions.icon(id) != null, "A Room options row has a section and an icon: %s in %s" % [id, state])
					_check(not row.has("widget") or row.has("option"), "A widget row in Room options names how its sheet row is wired: " + id)
				elif panel:
					_check(RoomActions.LOOKS.has(slot), "A panel slot has a look: %s.%s" % [state, slot])
				if slot == "header": _check(row.has("icon"), "A header action has an icon: " + id)
		_check(panel == state.contains("_panel"), "Panel states are named as panels: " + state)
	var sections: Array = RoomActions.SECTIONS.keys()
	_check(sections == ["invite", "turns", "chapter", "safety"] and RoomActions.SECTIONS.values().all(func(section: Dictionary): return section.column in [0, 1] and not str(section.title).is_empty()), "Room options has its four sections, each in a column")
	_check([RoomActions.SECTIONS.invite.title, RoomActions.SECTIONS.turns.title, RoomActions.SECTIONS.chapter.title, RoomActions.SECTIONS.safety.title] == ["Invite", "Turns", "Chapter", "Safety"], "The owner's section headings")
	_check(RoomActions.SECTIONS.safety.get("danger", false) and RoomActions.SECTIONS.values().filter(func(section: Dictionary): return section.get("danger", false)).size() == 1, "Only Safety is drawn in the warning colour")
	_check(RoomActions.REDO_ACTIONS == ["redo_answer", "redo", "solo_redo"], "Pause and review cards add the three redo rows")
	# The looks that were screen code: the taller cream Record, the icon rows,
	# the invitation field and Share's line, and the Notifications heading.
	var record := RoomActions.look("ready_panel", "primary", false)
	_check(record.cream and record.icon and record.height == 64 and RoomActions.look("ready_panel", "primary", true).height == 54, "A panel's primary rows are cream, with an icon, 64 tall (54 on a short screen)")
	_check(RoomActions.look("waiting_panel", "pair", false).fill and RoomActions.look("ready_panel", "turn", false).height == 52 and RoomActions.look("ready_panel", "header", false).icon_only, "Outlined panel rows are 52 tall, the last line's rows share it, and the header is icon only")
	_check(RoomActions.look("ready_panel_invite", "invite", false).field == 56 and RoomActions.look("ready_panel_invite", "invite", true).field == 50 and not RoomActions.look("ready_panel_invite", "invite", false).has("line"), "The panel's invitation field is 56 tall (50 short) and Share has no line under it")
	var card := RoomActions.look("waiting_card", "turn", true)
	_check(card.height == 50 and card.field == 52 and card.line and card.heading and not card.has("icon"), "Every card slot draws plain 50 tall rows, the 52 field, Share's line and the Notifications heading")
	_check(RoomActions.look("waiting_card", "more", false) == RoomActions.look("ready_card", "invite", false), "Card slots share one look")
	_check(RoomActions.ACTIONS.alerts.get("heading", false) and RoomActions.label("alerts") == "Notifications" and RoomActions.ACTIONS.share.line == RoomActions.SHARE_SCOPE, "Turn alerts head their card rows; Share's line is its scope")
	var source := FileAccess.get_file_as_string("res://relay_preview.gd")
	var body := source.substr(source.find("func _add_room_action("), source.find("## Widget rows") - source.find("func _add_room_action("))
	_check(not body.is_empty() and not body.contains("_room_state ==") and not body.contains("match id") and not body.contains("id =="), "Drawing a row reads the table, with no per-state or per-id branches")

## Rows apply when their facts hold, read in order and only as far as needed;
## each state's slot filters to what the hand-built panel showed.
func _facts() -> void:
	var read: Array[String] = []
	var none := func(name: String, _state: String) -> bool:
		read.append(name)
		return false
	_check(RoomActions.shown("ready_card", "turn", none) == ["record", "back"], "With no facts the ready card is Record and Back")
	_check(not read.has("pending") and not read.has("watchable"), "Facts after a failed one are not read")
	var solo := _facts_from({"solo": true, "restart": true, "solo_redo": true})
	_check(RoomActions.shown("ready_card", "turn", solo) == ["record", "restart", "solo_redo", "back"], "A solo second turn: Record, Restart chapter, Redo, Back")
	solo = _facts_from({"solo": true, "watchable": true, "solo_redo": true, "draft": true})
	_check(RoomActions.shown("ready_card", "turn", solo) == ["resume", "record", "local_replays", "solo_redo", "back"], "A solo draft with an archived attempt adds Resume and Replays")
	_check(RoomActions.shown("complete", "turn", solo) == ["local_replays", "checkpoints", "solo_redo", "back"], "A finished solo chapter: Replays, Retry, Redo, Back")
	var host := _facts_from({"online": true, "invited": true, "share": true, "my_turn": true, "photo": true, "about": true, "options": true})
	_check(RoomActions.panel_state("ready", host) == "ready_panel_invite", "A host before the friend joins is on the invite column")
	_check(RoomActions.shown("ready_panel_invite", "invite", host) == ["copy_code", "share"], "A host before the friend joins copies the code and shares inline")
	_check(RoomActions.shown("ready_panel_invite", "primary", host) == ["record"] and RoomActions.shown("ready_panel_invite", "pair", host) == ["room_options"], "Then Record and Room options")
	_check(RoomActions.shown("ready_panel_invite", "header", host) == ["refresh"], "The ready panel keeps Refresh in its header")
	_check(RoomActions.shown("ready_panel_invite", "options", host) == ["copy_code", "share", "photo", "about"], "Room options before the friend joins repeats the invitation")
	var guest := _facts_from({"online": true, "joined": true, "redo": true, "my_turn": true, "watchable": true, "photo": true, "about": true, "safety": true, "options": true})
	_check(RoomActions.panel_state("ready", guest) == "ready_panel", "A guest's turn is the my turn column")
	_check(RoomActions.shown("ready_panel", "primary", guest) == ["record"] and RoomActions.shown("ready_panel", "turn", guest).is_empty() and RoomActions.shown("ready_panel", "pair", guest) == ["room_options"], "My turn shows only Record and Room options")
	_check(RoomActions.shown("ready_panel", "options", guest) == ["redo", "replays", "photo", "about", "safety"], "My turn's Room options: Ask for redo, Replays, Photo, About, Report")
	var waiting := _facts_from({"online": true, "joined": true, "notifications": true, "share": true, "redo": true, "watchable": true, "photo": true, "about": true, "safety": true, "options": true})
	_check(RoomActions.panel_state("waiting", waiting) == "waiting_panel", "A host waiting with a friend is the waiting column")
	_check(RoomActions.shown("waiting_panel", "primary", waiting) == ["notify"] and RoomActions.shown("waiting_panel", "pair", waiting) == ["room_options", "your_rooms"], "Waiting with a friend: Notify, then Room options beside Your rooms")
	_check(RoomActions.shown("waiting_panel", "options", waiting) == ["share", "notify", "redo", "replays", "photo", "about", "safety"], "Waiting Room options: Share, Notify, Turn requests, Replays, Photo, About, Report")
	var columns := RoomActions.option_columns("waiting_panel", waiting)
	_check(columns == [[{"section": "invite", "ids": ["share"]}, {"section": "chapter", "ids": ["about"]}], [{"section": "turns", "ids": ["notify", "redo", "replays", "photo"]}, {"section": "safety", "ids": ["safety"]}]], "Room options puts Invite and Chapter on the left, Turns and Safety on the right: " + str(columns))
	_check(RoomActions.shown("waiting_card", "turn", waiting) == ["notify", "redo", "refresh", "share"], "The narrow waiting card keeps redo and Refresh in its list")
	_check(RoomActions.shown("waiting_card", "more", waiting) == ["replays", "safety", "photo", "back"], "The narrow waiting card ends with Replays, Report, Photo and Back")
	var before_join := _facts_from({"online": true, "invited": true, "notifications": true, "share": true, "photo": true, "about": true, "options": true})
	_check(RoomActions.panel_state("waiting", before_join) == "waiting_panel_invite", "A host waiting before the friend joins is the waiting invite column")
	_check(RoomActions.shown("waiting_panel_invite", "invite", before_join) == ["copy_code"] and RoomActions.shown("waiting_panel_invite", "primary", before_join) == ["share"], "Before the friend joins, the code and a cream Share")
	_check(RoomActions.shown("waiting_panel_invite", "options", before_join) == ["copy_code", "share", "notify", "photo", "about"], "Notify waits in Room options until the friend joins")
	var answer := _facts_from({"online": true, "joined": true, "redo": true, "redo_accept": true, "about": true, "options": true})
	_check(RoomActions.shown("waiting_panel", "turn", answer) == ["redo_answer"] and RoomActions.shown("ready_panel", "turn", answer) == ["redo_answer"], "A friend's redo request stays on the panel while it needs an answer")
	_check(RoomActions.shown("waiting_panel", "options", answer) == ["redo_answer", "about"], "Room options lists the request too, and not Ask for redo")
	var pending_before_join := _facts_from({"online": true, "invited": true, "share": true, "pending": true, "about": true, "options": true})
	_check(RoomActions.shown("waiting_panel_pending", "invite", pending_before_join) == ["copy_code"] and RoomActions.shown("waiting_panel_pending", "options", pending_before_join) == ["copy_code", "share", "about"], "A pending turn before the friend joins keeps the code inline and lists it and Share in Room options")
	var pending := _facts_from({"online": true, "joined": true, "pending": true, "held": true, "watchable": true, "about": true, "safety": true, "options": true})
	_check(RoomActions.panel_state("waiting", pending) == "waiting_panel_pending" and RoomActions.panel_state("ready", pending) == "ready_panel", "A sent turn without a receipt is the pending column")
	_check(RoomActions.shown("waiting_panel_pending", "primary", pending) == ["check_saved"] and RoomActions.shown("waiting_panel_pending", "turn", pending) == ["keep_held"], "A held turn: Check status, then keep it")
	_check(RoomActions.shown("waiting_panel_pending", "options", pending) == ["replays", "about", "safety"] and RoomActions.shown("waiting_panel_pending", "header", pending).is_empty(), "A pending turn's Room options: Replays, About, Report; no Refresh")
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
	_check(RoomActions.label("share") == "Share current room" and RoomActions.SHARE_SCOPE == "All friends", "Share keeps its labels")
	_check(RoomActions.label("solo_redo") == PlayerCopy.SOLO_REDO_ACTION, "Solo redo keeps its label")
	_check(RoomActions.label("redo", _facts_from({"my_turn": true})) == "Ask for redo" and RoomActions.label("redo", _facts_from({})) == "Turn requests", "Redo reads Ask for redo on this player's turn, else Turn requests")
	_check(RoomActions.label("redo_answer") == "Redo requested", "An answerable request reads Redo requested")
	_check(RoomActions.redo_label(true, true) == "Redo requested" and RoomActions.redo_label(false, true) == "Ask for redo" and RoomActions.redo_label(false, false) == "Turn requests", "The shared redo label")
	for path: String in ["res://presentation/friends_screen.gd", "res://presentation/legacy_room_flow.gd"]:
		var text := FileAccess.get_file_as_string(path)
		_check(not text.contains("\"Share current room\"") and not text.contains("\"All friends\"") and not text.contains("\"Ask for redo\""), "Uses the table's Share and redo labels: " + path)

class RedoClientStub:
	extends RefCounted
	var request: Variant = {"request_id": "first", "status": "pending"}
	func can_accept() -> bool: return request is Dictionary
	func view() -> Dictionary: return {"request": request}

## A friend's redo request pops up once per request, from either room screen.
func _redo_notice() -> void:
	var parent := Control.new()
	root.add_child(parent)
	var notice = RedoNotice.new()
	var client := RedoClientStub.new()
	var reviews := [0]
	var review := func(): reviews[0] += 1
	notice.announce(parent, client, "room", review)
	_check(is_instance_valid(notice.modal) and notice.modal.name == "RedoRequestModal" and parent.get_child_count() == 1, "A new request opens the shared pop-up")
	notice.announce(parent, client, "room", review)
	_check(parent.get_child_count() == 1, "An open pop-up is not opened twice")
	var open: Button = notice.modal.find_child("ModalConfirm", true, false)
	_check(open != null and open.text == "Review request" and notice.modal.find_child("ModalCancel", true, false).text == "Not now", "The pop-up offers Review request and Not now")
	open.pressed.emit()
	await process_frame
	_check(reviews[0] == 1 and notice.modal == null and parent.get_child_count() == 0, "Review request closes the pop-up and opens the request")
	notice.announce(parent, client, "room", review)
	_check(notice.modal == null, "A request shown once is not shown again")
	notice.announce(parent, client, "other-room", review)
	_check(is_instance_valid(notice.modal), "The same request id in another room is a new request")
	notice.modal.close(false)
	await process_frame
	client.request = {"request_id": "second", "status": "pending"}
	notice.announce(parent, client, "room", review)
	_check(is_instance_valid(notice.modal), "A newer request pops up again")
	notice.modal.close(false)
	await process_frame
	client.request = null
	notice.announce(parent, client, "room", review)
	_check(not is_instance_valid(notice.modal), "Nothing pops up when no request can be answered")
	for path: String in ["res://relay_preview.gd", "res://presentation/legacy_room_flow.gd"]:
		var text := FileAccess.get_file_as_string(path)
		_check(text.contains("redo_notice.announce(") and not text.contains("InGameModal.open(ui,\"RedoRequestModal\"") and not text.contains("\"Review request\""), "Both room screens use the shared redo request pop-up: " + path)
	parent.queue_free()
	await process_frame

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
	return func(name: String, _state: String) -> bool: return values.get(name, false)

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + description)
