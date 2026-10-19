extends SceneTree
## The display name prompt, its flow and where names show, driven by real input
## through a viewport (presses, drags and typing pushed into it):
## - the prompt (layout A): the question with the creature word, the 3D pip
##   that a finger spins and squeezes and that draws every frame only while it
##   moves, the tag that follows the choice, the counter and the error line;
## - the anonymous row, the platform row that reads the gamer name only when
##   picked, typing taking the choice back, Save with the server's refusal shown
##   on the card, and Not now in the quiet look;
## - the flow: the first-run prompt opens once, only while names are on, the
##   Friends header chip shows the name and where it stands, and Change opens
##   the prompt to change it;
## - Friends shows a friend's chosen name and, under a nickname, "Goes by";
## - a finished room's menu offers Add friend for a partner who is not a friend
##   and sends the ordinary request; hard mode names a friend as they are now.
const DisplayNames = preload("res://services/display_names.gd")
const DisplayNameClient = preload("res://services/display_name_client.gd")
const Prompt = preload("res://presentation/display_name_prompt.gd")
const Flow = preload("res://presentation/display_name_flow.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const Screen = preload("res://presentation/friends_screen.gd")
const FriendsClient = preload("res://services/friends_client.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const FriendRoster = preload("res://services/friend_roster.gd")
const Hub = preload("res://presentation/room_hub_screen.gd")
const Registry = preload("res://services/chapter_registry.gd")
const HardMode = preload("res://services/hard_mode.gd")
const HardModeView = preload("res://presentation/hard_mode_view.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
const Look = preload("res://presentation/spirit_look.gd")

# Synthetic ids only.
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const MAYA := "bbbbbbbbbbbbbbbbbbbbbb"
const SAM := "cccccccccccccccccccccc"
const RANDO := "dddddddddddddddddddddd"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const BASE := "https://example.test"

var checks := 0
var failures := 0
var viewport: SubViewport
var page: Control
var _paths: Array[String] = []

class Api extends Node:
	var base_url := "https://example.test"
	var player_id := "aaaaaaaaaaaaaaaaaaaaaa"
	var device_token := "synthetic-token"
	var busy := false

class Saves extends RefCounted:
	var data := {"settings": {"reduced_motion": false}}

class Host extends Node:
	var api: Node
	var saves := Saves.new()
	var toasts: Array = []
	var soundscape: Node = null
	func _relay_identity() -> Dictionary: return {"ready": true, "player_id": api.player_id, "epoch": 1}
	func _toast(text: String) -> void: toasts.append(text)

class Inbox extends RefCounted:
	var rooms: Array = []
	func view() -> Dictionary: return {"rooms": rooms, "stale": false, "error": ""}
	func unread(_room: Dictionary) -> bool: return false
	func confirmed(_room: Dictionary) -> bool: return true
	func confirm_room_rendered(_version: int, _id: String) -> bool: return false
	func refresh() -> bool: return true

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 720)
	viewport.gui_disable_input = false
	viewport.handle_input_locally = true
	root.add_child(viewport)
	page = Control.new()
	page.size = Vector2(1600, 720)
	viewport.add_child(page)
	await _prompt()
	await _platform_and_save()
	await _edit_mode()
	await _flow()
	await _friends()
	await _hub_menu()
	_hard_names()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	DisplayNames.use_shared(null)
	FriendRoster.use_shared(null)
	print("AFTER YOU DISPLAY NAME PROMPT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _path(label: String) -> String:
	var path := "user://test-display-name-prompt-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

# --- Real input --------------------------------------------------------------

func _mouse(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)

func _move(at: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(event, true)

func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	_mouse(at, true)
	_mouse(at, false)
	await _frames(2)

func _type(text: String) -> void:
	for i in range(text.length()):
		var event := InputEventKey.new()
		event.pressed = true
		event.unicode = text.unicode_at(i)
		event.keycode = KEY_A
		viewport.push_input(event, true)
		event = event.duplicate()
		event.pressed = false
		viewport.push_input(event, true)
	await _frames(1)

func _erase(count: int) -> void:
	for i in range(count):
		var event := InputEventKey.new()
		event.pressed = true
		event.keycode = KEY_BACKSPACE
		viewport.push_input(event, true)
	await _frames(1)

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _prompt_node(modal: Control) -> Node:
	return modal.find_child("DisplayNamePrompt", true, false)

func _open(context: Dictionary) -> Control:
	var modal: Control = Prompt.open(page, context)
	await _frames(3)
	return modal

# --- The prompt -----------------------------------------------------------------

func _prompt() -> void:
	var saved: Array = []
	var modal := await _open({"own": DisplayNames.new(_path("own")).own(BASE, ME), "anonymous": "Kite 41", "platform": "",
		"save": func(choice: String, name: String) -> Dictionary: saved.append([choice, name]); return {"closed": true}})
	var prompt := _prompt_node(modal)
	_check(PlayerCopy.CREATURE == "pip" and PlayerCopy.DISPLAY_NAME_ASK == "What's the name of your pip?", "The question names the creature from its one constant")
	_check(_has_label(modal, PlayerCopy.DISPLAY_NAME_ASK), "The card asks it")
	_check(prompt.platform_row == null, "No platform row when no platform is signed in")
	_check(prompt.field.has_focus(), "The first-run card puts the caret in the field")
	_check(prompt.tag.text == "Kite 41", "With nothing typed the tag shows the anonymous name")
	await _type("Robin")
	_check(prompt.field.text == "Robin" and prompt.choice() == "typed", "Typing fills the field: " + prompt.field.text)
	_check(prompt.tag.text == "Robin", "and the tag above the pip follows it")
	_check(prompt._counter.text == "5 / 18", "The counter counts: " + prompt._counter.text)
	# The pip: a real drag through the viewport spins it and squeezes it.
	var pip: Control = prompt.preview
	_check(pip.get_class() == "TextureRect" and pip.find_child("SpiritView", true, false) is SubViewport, "The pip is the real 3D preview")
	_check(pip.size.x >= 48 and pip.size.y >= 48 and pip.mouse_filter == Control.MOUSE_FILTER_STOP, "It takes a finger over a full target")
	var center := pip.get_global_rect().get_center()
	_mouse(center, true)
	await _frames(1)
	_check(pip.held() and pip._spirit.expression_target() == Look.SQUEEZE, "A press squeezes its eyes shut")
	var before: int = pip.drawn
	for step in range(1, 13):
		_move(center + Vector2(step * 8.0, 0), Vector2(8, 0))
		await _frames(1)
	_check(not is_zero_approx(pip.turn.offset), "A sideways drag spins it")
	_check(pip.drawn - before >= 10, "While it moves it draws every frame: %d" % (pip.drawn - before))
	_mouse(center + Vector2(96, 0), false)
	await _frames(1)
	_check(not pip.held(), "Let go, it lets go")
	pip.set_process(false)
	var settle := 0
	while pip.turn.busy() and settle < 600:
		pip._process(1.0 / 60.0)
		settle += 1
	var idle: int = pip.drawn
	for i in range(60): pip._process(1.0 / 60.0)
	var hz := int(IslandWorld.IDLE_CARD_HZ)
	_check(pip.drawn - idle >= hz - 2 and pip.drawn - idle <= hz + 1, "At rest it draws only at the idle rate: %d in 1 s" % (pip.drawn - idle))
	pip.set_process(true)
	# Anonymous, by a real press on its row.
	await _click(prompt.anonymous_row)
	_check(prompt.choice() == "anonymous" and prompt.tag.text == "Kite 41", "Keep me anonymous: the tag shows the anonymous name")
	_check(prompt.field.modulate.a < 1.0, "and the field steps back")
	await _click(prompt.field)
	_check(prompt.choice() == "typed" and prompt.tag.text == "Robin", "Tapping the field takes the typed name back")
	# Too long: the card says so and nothing is saved.
	await _type("abcdefghijklmnopq")
	_check(prompt._counter.text.begins_with("18") or prompt.field.text.length() > 18, "The counter keeps up: " + prompt._counter.text)
	await _click(prompt.save_button)
	_check(saved.is_empty() and prompt._error.text == PlayerCopy.DISPLAY_NAME_ERRORS.length, "Over 18 characters, Save says so and keeps the card: " + prompt._error.text)
	await _erase(prompt.field.text.length())
	await _type("Robin<3")
	await _click(prompt.save_button)
	_check(saved.is_empty() and prompt._error.text == PlayerCopy.DISPLAY_NAME_ERRORS.characters, "Symbols are refused on the card")
	await _erase(prompt.field.text.length())
	await _type("  Robin  ")
	var cancel: Button = modal.find_child("ModalCancel", true, false)
	_check(cancel.text == PlayerCopy.DISPLAY_NAME_NOT_NOW and cancel.get_theme_stylebox("normal") != null and (cancel.get_theme_stylebox("normal") as StyleBoxFlat).bg_color != ThemeRules.CORAL, "Not now is the quiet look, not the coral warning")
	await _click(prompt.save_button)
	await _frames(2)
	_check(saved == [["typed", "Robin"]], "Save sends the cleaned name: " + str(saved))
	_check(not is_instance_valid(modal), "and the card closes")

func _platform_and_save() -> void:
	var reads := [0]
	var answers: Array = [{"closed": false, "code": "display_name_refused"}, {"closed": true}]
	var saved: Array = []
	var reader := func() -> Dictionary:
		reads[0] += 1
		await process_frame
		return {"ok": true, "name": "RobinPlays"}
	var saver := func(choice: String, name: String) -> Dictionary:
		saved.append([choice, name])
		await process_frame
		return answers.pop_front()
	var modal := await _open({"own": {"choice": "", "name": ""}, "anonymous": "Kite 41", "platform": PlayerCopy.DISPLAY_NAME_PLAY_GAMES, "read_platform": reader, "save": saver})
	var prompt := _prompt_node(modal)
	_check(prompt.platform_row != null and _has_label(prompt.platform_row, PlayerCopy.DISPLAY_NAME_PLAY_GAMES), "Signed in to Play Games: its row is offered")
	_check(reads[0] == 0 and _has_label(prompt.platform_row, PlayerCopy.DISPLAY_NAME_PLATFORM_NOTE), "The gamer name is not read before it is picked")
	await _click(prompt.platform_row)
	await _frames(3)
	_check(reads[0] == 1 and prompt.choice() == "platform" and prompt.tag.text == "RobinPlays", "Picked, it is read once and shown on the tag")
	_check(_has_label(prompt.platform_row, "RobinPlays"), "and under the row")
	await _click(prompt.anonymous_row)
	await _click(prompt.platform_row)
	_check(reads[0] == 1 and prompt.choice() == "platform", "Picking it again does not read it again")
	await _click(prompt.save_button)
	await _frames(3)
	_check(saved == [["platform", "RobinPlays"]] and is_instance_valid(modal), "Save sends the platform name; a refusal keeps the card")
	_check(prompt._error.text == PlayerCopy.DISPLAY_NAME_ERRORS.display_name_refused, "and says why on it: " + prompt._error.text)
	await _click(prompt.anonymous_row)
	await _click(prompt.save_button)
	await _frames(3)
	_check(saved.back() == ["anonymous", ""] and not is_instance_valid(modal), "Anonymous saves and the card closes")
	# A gamer name the rules don't take lands in the field to edit.
	modal = await _open({"own": {"choice": "", "name": ""}, "anonymous": "Kite 41", "platform": PlayerCopy.DISPLAY_NAME_GAME_CENTER,
		"read_platform": func() -> Dictionary: return {"ok": true, "name": "xX_Robin_The_Great_Xx"}, "save": func(_c: String, _n: String) -> Dictionary: return {"closed": true}})
	prompt = _prompt_node(modal)
	await _click(prompt.platform_row)
	await _frames(2)
	_check(prompt.choice() == "typed" and prompt.field.text == "xX_Robin_The_Great", "A gamer name the rules refuse goes to the field to edit, cut to fit: " + prompt.field.text)
	modal.close()
	modal = await _open({"own": {"choice": "", "name": ""}, "anonymous": "Kite 41", "platform": PlayerCopy.DISPLAY_NAME_GAME_CENTER,
		"read_platform": func() -> Dictionary: return {"ok": false, "code": "signed_out"}, "save": func(_c: String, _n: String) -> Dictionary: return {"closed": true}})
	prompt = _prompt_node(modal)
	await _click(prompt.platform_row)
	await _frames(2)
	_check(prompt.choice() == "typed" and _has_label(prompt.platform_row, PlayerCopy.DISPLAY_NAME_PLATFORM_FAILED), "A failed read says so and changes nothing")
	await _click(modal.find_child("ModalCancel", true, false))
	_check(not is_instance_valid(modal), "Not now closes it")

func _edit_mode() -> void:
	var modal := await _open({"edit": true, "own": {"choice": "anonymous", "name": ""}, "anonymous": "Kite 41", "platform": "", "save": func(_c: String, _n: String) -> Dictionary: return {"closed": true}})
	var prompt := _prompt_node(modal)
	_check(_has_label(modal, PlayerCopy.DISPLAY_NAME_EDIT_TITLE) and not _has_label(modal, PlayerCopy.DISPLAY_NAME_ASK), "From Friends it is titled Your name")
	_check(prompt.choice() == "anonymous" and prompt.tag.text == "Kite 41", "with the choice the player made")
	modal.close()
	await _frames(1)

# --- The flow ---------------------------------------------------------------

func _flow() -> void:
	var store: RefCounted = DisplayNames.new(_path("flow"))
	DisplayNames.use_shared(store)
	var api := Api.new()
	var host := Host.new()
	host.api = api
	host.add_child(api)
	root.add_child(host)
	var flow := Flow.new(host)
	host.add_child(flow)
	var sent: Array = []
	var transport := func(_method: int, _path: String, body: Dictionary) -> Dictionary:
		sent.append(body)
		await process_frame
		return {"ok": true, "data": {"schema_version": 1, "display_name": body.display_name, "revision": body.revision}}
	flow.client = DisplayNameClient.new(api, host._relay_identity, transport, store)
	flow.client.settled.connect(flow._settled)
	_check(not flow.maybe_ask(page) and flow.chip() == null, "Names off: no prompt and no chip")
	store.set_enabled(BASE, ME, true)
	_check(flow.maybe_ask(page), "Names on: the first Friends visit opens the prompt")
	await _frames(3)
	var modal: Control = page.find_child("DisplayNameModal", true, false)
	_check(modal != null, "over the screen that opened it")
	await _click(modal.find_child("ModalCancel", true, false))
	_check(not flow.maybe_ask(page), "Once asked, it never opens by itself again")
	var chip: Control = flow.chip()
	page.add_child(chip)
	chip.position = Vector2(40, 20)
	await _frames(3)
	_check(chip.name_label.text == DisplayNames.anonymous_name(ME) and not chip.status_label.visible, "The chip shows the anonymous name until a name is chosen")
	_check(chip.preview.get_class() == "TextureRect" and chip.preview.find_child("SpiritView", true, false) != null, "and the same 3D pip")
	await _click(chip.change_button)
	await _frames(3)
	modal = page.find_child("DisplayNameModal", true, false)
	_check(modal != null and _has_label(modal, PlayerCopy.DISPLAY_NAME_EDIT_TITLE), "Change opens the prompt to change it")
	var prompt := _prompt_node(modal)
	prompt.field.grab_focus()
	await _type("Robin")
	await _click(prompt.save_button)
	await _frames(6)
	_check(sent.size() == 1 and sent[0].display_name == "Robin" and not is_instance_valid(modal), "Save sends the name and the card closes")
	_check(chip.name_label.text == "Robin" and not chip.status_label.visible, "The chip shows the saved name")
	store.choose(BASE, ME, "typed", "Offline")
	flow._refresh_chips()
	_check(chip.status_label.visible and chip.status_label.text == PlayerCopy.DISPLAY_NAME_PENDING, "A name waiting to be sent says so")
	var refused: Dictionary = store.choose(BASE, ME, "typed", "Badname")
	store.settle(BASE, ME, int(refused.revision), {"ok": false, "code": "display_name_refused"})
	flow._settled({"ok": false, "code": "display_name_refused"})
	_check(chip.status_label.text == PlayerCopy.DISPLAY_NAME_NOT_SAVED and host.toasts.back() == PlayerCopy.DISPLAY_NAME_ERRORS.display_name_refused, "A refusal after the card closed shows on the chip and is said once")
	chip.queue_free()
	host.queue_free()
	await _frames(2)
	DisplayNames.use_shared(null)

# --- Friends -----------------------------------------------------------------

func _friends() -> void:
	var store: RefCounted = DisplayNames.new(_path("friends"))
	DisplayNames.use_shared(store)
	FriendRoster.use_shared(FriendRoster.new(_path("roster")))
	var api := Api.new()
	root.add_child(api)
	var page_data := {"schema_version": 1, "friend_code": ME, "refresh_after_seconds": 30, "shared_room": null, "display_name": "Robin", "friends": [
		{"player_id": MAYA, "request_id": "eeeeeeeeeeeeeeeeeeeeee", "status": "accepted", "online": false, "expires_after_seconds": 0, "join_available": false, "display_name": "Maya"},
		{"player_id": SAM, "request_id": "ffffffffffffffffffffff", "status": "accepted", "online": false, "expires_after_seconds": 0, "join_available": false, "display_name": "Sam"}]}
	var client: RefCounted = FriendsClient.new(api, func() -> Dictionary: return {"ready": true, "player_id": ME, "epoch": 1},
		func(_m: int, _p: String, _b: Dictionary) -> Dictionary: return JSON.parse_string(JSON.stringify({"ok": true, "data": page_data})))
	var read := [0]
	client.page_read.connect(func() -> void: read[0] += 1)
	_check(await client.refresh() and read[0] == 1, "A friends read with names is kept and announced")
	_check(store.enabled(BASE, ME) and store.chosen(BASE, ME, MAYA) == "Maya" and store.own(BASE, ME).name == "Robin", "and its names reach the store")
	_check(FriendRoster.shared().status(BASE, ME, MAYA) == "accepted", "and who is a friend reaches the roster")
	var nicknames: RefCounted = FriendNicknames.new(_path("nicknames"))
	nicknames.set_nickname(BASE, ME, SAM, "Sunny")
	var screen: CanvasLayer = Screen.new()
	screen.client = client
	screen.nickname_store = nicknames
	screen.name_chip = func() -> Control:
		var chip := preload("res://presentation/display_name_chip.gd").new(true)
		chip.show_name("Robin", store.own(BASE, ME))
		return chip
	root.add_child(screen)
	await _frames(8)
	screen._render()
	await _frames(3)
	_check(_has_label(screen, "Maya"), "A friend's row shows the name they chose")
	_check(_has_label(screen, "Sunny") and _has_label(screen, PlayerCopy.DISPLAY_NAME_GOES_BY % "Sam"), "Under a nickname, Goes by and their own name")
	var chip: Control = screen.find_child("DisplayNameChip", true, false)
	_check(chip != null and chip.get_parent() == screen._title.get_parent() and chip.get_index() == screen._title.get_index() + 1, "The Display name chip sits in the header beside the title")
	screen.queue_free()
	api.queue_free()
	await _frames(2)
	DisplayNames.use_shared(null)
	FriendRoster.use_shared(null)

# --- A finished room's menu -----------------------------------------------------

func _hub_menu() -> void:
	var inbox := Inbox.new()
	var key := Registry.WISHING_WELL
	inbox.rooms = [{"api_version": 2, "room_id": ROOM, "chapter_key": key, "chapter_title": str(Registry.descriptor(key).title), "member_ids": [ME, RANDO], "status": "completed",
		"revision": 9, "remote_activity_sequence": 0, "activity_at": 0, "family": "relay"}]
	var hub: CanvasLayer = Hub.new()
	hub.client = inbox
	var state := ["addable"]
	hub.display_name = func(member: String) -> String: return "" if member == ME else "Kit"
	hub.partner_friend = func(room: Dictionary) -> Dictionary: return {"state": state[0], "partner": RANDO if RANDO in room.member_ids else ""}
	var asked: Array = []
	hub.add_friend_requested.connect(func(room: Dictionary, partner: String) -> void: asked.append([room.room_id, partner]))
	root.add_child(hub)
	await _frames(8)
	_check(hub._menu_ids(inbox.rooms[0]).has("add_friend"), "A finished room with a partner who is not a friend offers Add friend")
	hub._select_tab("Completed")
	await _frames(4)
	var button: Control = hub.find_child("RoomMenu", true, false)
	if button != null:
		hub.open_room_menu(inbox.rooms[0].duplicate(true), button)
		await _frames(2)
		var menu: CanvasLayer = hub.room_menu()
		var row: Button = menu.find_child("RoomMenu_add_friend", true, false) if menu != null else null
		_check(row != null and row.text.contains(PlayerCopy.ROOM_ADD_FRIEND) or (row != null and _has_label(row, PlayerCopy.ROOM_ADD_FRIEND)), "The menu's first row is Add friend")
		if row != null: row.pressed.emit()
		await _frames(3)
		_check(asked == [[ROOM, RANDO]], "Picking it asks for the request with the partner's id from the room: " + str(asked))
	else:
		_check(false, "The finished room card has its menu button")
	state[0] = "requested"
	_check(hub._menu_ids(inbox.rooms[0]).has("friend_requested") and not hub._menu_ids(inbox.rooms[0]).has("add_friend"), "Once sent, Request sent takes its place")
	state[0] = ""
	_check(not hub._menu_ids(inbox.rooms[0]).has("add_friend") and not hub._menu_ids(inbox.rooms[0]).has("friend_requested"), "A friend (or a blocked partner) is offered nothing")
	hub.queue_free()
	await _frames(2)

# --- Hard mode -----------------------------------------------------------------

func _hard_names() -> void:
	var run := HardMode.run_record(Registry.WISHING_WELL, HardMode.TOGETHER, HardMode.FAILED, "failed_turn", "friend", 1, "a", [], {}, "a friend", ROOM, MAYA)
	_check(run.get("friend_id") == MAYA and HardMode.valid_run(run), "A kept run keeps its friend's id")
	_check(HardMode.valid_run(HardMode.run_record(Registry.WISHING_WELL, HardMode.SOLO, HardMode.FAILED, "failed_turn", "you", 0, "a", [], {})), "A solo run has none and is still valid")
	var broken := run.duplicate(true)
	broken.friend_id = "friend-" + MAYA
	_check(not HardMode.valid_run(broken), "A friend id that is not a player id is refused")
	HardModeView.friend_name = Callable()
	_check(HardModeView.failure_line(run) == PlayerCopy.HARD_FRIEND_SLIPPED % [PlayerCopy.HARD_FRIEND_FALLBACK, 2], "With no name, the line starts with Your friend, never a lowercase a friend: " + HardModeView.failure_line(run))
	HardModeView.friend_name = func(id: String) -> String: return "Maya" if id == MAYA else FriendNicknames.FALLBACK
	_check(HardModeView.failure_line(run) == PlayerCopy.HARD_FRIEND_SLIPPED % ["Maya", 2], "A kept run names its friend as they are called now")
	var old := run.duplicate(true)
	old.erase("friend_id")
	old.friend = "Old nick"
	_check(HardModeView.failure_line(old) == PlayerCopy.HARD_FRIEND_SLIPPED % ["Old nick", 2], "An older run keeps the name it was kept with")
	HardModeView.friend_name = Callable()

func _has_label(node: Node, text: String) -> bool:
	for label: Node in node.find_children("*", "Label", true, false):
		if (label as Label).text == text: return true
	for button: Node in node.find_children("*", "Button", true, false):
		if (button as Button).text == text: return true
	return false

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
