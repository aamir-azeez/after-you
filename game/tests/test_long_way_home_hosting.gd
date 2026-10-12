extends SceneTree
## Hosting follows what the server can create: the newest offered version of a
## chapter id, else the previous one, else "unavailable online". Solo always
## plays the offered version.
const Registry = preload("res://services/chapter_registry.gd")
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
const Session = preload("res://services/relay_online_session.gd")
const Fakes = preload("res://tests/test_relay_online.gd")
const Hub = preload("res://presentation/room_hub_screen.gd")
const Picker = preload("res://presentation/chapter_picker.gd")
const Purchases = preload("res://services/purchases.gd")
const V1 := "long-way-home@1"
const V2 := "long-way-home@2"
var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_rule()
	await _chooser()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("LONG WAY HOME HOSTING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _rule() -> void:
	var none := func(_key: String) -> bool: return false
	var only_v1 := func(key: String) -> bool: return key == V1
	var both := func(key: String) -> bool: return key in [V1, V2]
	var only_v2 := func(key: String) -> bool: return key == V2
	_check(Registry.hosting_key(V2, none) == V2, "Neither listed: hosting stays on @2 (shown as unavailable)")
	_check(Registry.hosting_key(V2, only_v1) == V1, "Only @1 listed: hosting falls back to @1")
	_check(Registry.hosting_key(V2, both) == V2 and Registry.hosting_key(V2, only_v2) == V2, "@2 listed: hosting uses @2")
	_check(Registry.hosting_key(V1, both) == V1, "Never hosts a version newer than asked for")
	_check(Registry.hosting_key(Registry.CONSERVATORY, both) == Registry.CONSERVATORY and Registry.hosting_key(Registry.CONSERVATORY, none) == Registry.CONSERVATORY, "Other chapters are unaffected")
	_check(V1 not in Registry.offered_keys() and V2 in Registry.offered_keys(), "Solo pickers still offer only @2")

func _caps(listed: Array) -> Dictionary:
	var chapters: Array = []
	for key: String in Registry.keys():
		if key.begins_with("long-way-home@") and key not in listed: continue
		var value := Registry.descriptor(key)
		chapters.append({"level_id": value.level_id, "level_version": value.level_version, "definition_hash": value.definition_hash,
			"premium": value.premium, "recording_version": value.recording_version, "simulation_version": value.simulation_version})
	return {"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true,
		"validation": "structural_client_replay_required", "chapters": chapters}

## The lobby's chapter picker hosts what the server can create; the room hub
## picks the offered chapter and hosts its fallback through the same rule.
class FakeStore extends Purchases:
	var entitled := false
	func _connect_native() -> bool: return true
	func is_available() -> bool: return true
	func has_entitlement(_entitlement_id: String = "") -> bool: return entitled

class HostApp extends Main:
	var actions: Array = []
	var tester := true
	func _relay_identity() -> Dictionary: return {"ready": true, "player_id": Fakes.HOST, "epoch": 1}
	func _tester_active() -> bool: return tester
	func _show_relay_rooms(_chapter: String = "") -> void:
		mode = "relay_rooms"
		await relay_session.load_lobby()
	func _relay_lobby_action(action: String, value: String = "") -> void: actions.append([action, value])
	func _draw_relay_lobby(_message: String = "", _loading: bool = false) -> void: actions.append(["lobby", selected_online_chapter])

func _chooser() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var app := Main.new()
	var path := "user://lwh-hosting-%s.json" % Crypto.new().generate_random_bytes(8).hex_encode()
	paths.append(path)
	app.saves = Save.new(path)
	app.saves.data.settings.sound = false
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var api := Fakes.FakeApi.new()
	app.add_child(api)
	app.api = api
	var identity := Fakes.Identity.new()
	app.relay_session = Session.new(api, identity.get_value, Fakes.MemoryStore.new())
	for state: Array in [[[], V2, false], [[V1], V1, true], [[V1, V2], V2, true], [[V2], V2, true]]:
		var listed: Array = state[0]
		api.responder = func(request: Dictionary) -> Dictionary:
			return {"ok": true, "data": _caps(listed) if request.path == "/v2/capabilities" else {"rooms": []}}
		_check(await app.relay_session.load_lobby(), "Lobby loads with Long Way Home listed as %s" % str(listed))
		app.selected_online_chapter = V2
		app._draw_relay_lobby()
		await process_frame
		_check(app.selected_online_chapter == state[1], "The selected chapter follows the server: " + str(listed))
		var choice := app.overlay.find_child("ChapterChoice", true, false) as Button
		_check(choice != null and choice.text.begins_with("Long Way Home") and choice.text.contains("unavailable online") != state[2], "The lobby's chapter button names the hosted version's availability: " + str(listed))
		if choice == null: continue
		choice.pressed.emit()
		await process_frame
		var picker: Picker = app.overlay.find_children("*", "ScrollContainer", true, false)[0]
		var found: Array = []
		for card: Control in picker.grid.get_children():
			if str(card.get_meta("chapter_key")).begins_with("long-way-home@"): found.append(card)
		_check(found.size() == 1, "Exactly one Long Way Home card: " + str(listed))
		if found.size() != 1: continue
		var card: Control = found[0]
		var access := card.find_child("ChapterAccess", true, false) as Label
		var title := card.find_child("LevelTitle", true, false) as Label
		_check(card.get_meta("chapter_key") == state[1] and title.text == "Long Way Home" and access.text.contains("unavailable online") != state[2], "The card hosts %s and is %s: %s" % [state[1], "available" if state[2] else "unavailable", str(listed)])
		var unavailable := 0
		for other: Control in picker.grid.get_children():
			if (other.find_child("ChapterAccess", true, false) as Label).text.contains("unavailable online"): unavailable += 1
		_check(unavailable == (0 if state[2] else 1), "Only chapters the server lacks are tagged unavailable online: " + str(listed))
		var open := card.find_child("ChapterOpen", true, false) as Button
		_check(open.get_meta("completion_variant") == "friend", "The lobby picker shows Together completion")
		open.pressed.emit()
		await process_frame
		_check(app.selected_online_chapter == state[1] and app.overlay.find_child("RelayLobbyLayout", true, false) != null, "Picking the card returns to the lobby with it selected: " + str(listed))
		var create: Button = null
		for button: Button in app.overlay.find_children("*", "Button", true, false):
			if button.text == "Create this chapter": create = button
		_check(create != null and create.disabled != state[2], "Create follows the hosted version: " + str(listed))
		# Back and Android Back return to the lobby without changing the choice.
		app.selected_online_chapter = state[1]
		(app.overlay.find_child("ChapterChoice", true, false) as Button).pressed.emit()
		await process_frame
		root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		await process_frame
		await process_frame
		_check(app.mode == "relay_rooms" and app.overlay.find_child("RelayLobbyLayout", true, false) != null and app.selected_online_chapter == state[1], "Android Back closes the lobby picker: " + str(listed))
		(app.overlay.find_child("ChapterChoice", true, false) as Button).pressed.emit()
		await process_frame
		_escape(viewport)
		await process_frame
		_check(app.mode == "relay_rooms" and app.overlay.find_child("RelayLobbyLayout", true, false) != null, "Escape closes the lobby picker back to the lobby, not Home: " + str(listed))
	api.responder = Callable()
	app.relay_session.invalidate_identity()
	app.relay_session = null
	viewport.queue_free()
	await process_frame
	await _hub()

func _hub() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var app := HostApp.new()
	var path := "user://lwh-hub-%s.json" % Crypto.new().generate_random_bytes(8).hex_encode()
	paths.append(path)
	app.saves = Save.new(path)
	app.saves.data.settings.sound = false
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var api := Fakes.FakeApi.new()
	app.add_child(api)
	app.api = api
	var identity := Fakes.Identity.new()
	app.relay_session = Session.new(api, identity.get_value, Fakes.MemoryStore.new())
	for state: Array in [[[], V2, false], [[V1], V1, true], [[V1, V2], V2, true], [[V2], V2, true]]:
		var listed: Array = state[0]
		api.responder = func(request: Dictionary) -> Dictionary:
			return {"ok": true, "data": _caps(listed) if request.path == "/v2/capabilities" else {"rooms": []}}
		app.actions.clear()
		app.mode = "rooms"
		var hub := Hub.new()
		hub.set_chapters(app._together_chapters())
		hub.host_requested.connect(app._host_from_room_hub)
		app.room_hub_screen = hub
		viewport.add_child(hub)
		await process_frame
		hub.open_chapter_picker()
		await process_frame
		_escape(viewport)
		await process_frame
		_check(app.mode == "rooms" and is_instance_valid(hub) and not hub._picker_page.visible and hub._layout.visible, "Escape closes the hub picker and keeps the hub: " + str(listed))
		hub.open_chapter_picker()
		await process_frame
		var card: Control = hub._picker.card_for(V2)
		_check(card != null and hub._picker.card_for(V1) == null, "The hub offers Long Way Home once, as the offered version: " + str(listed))
		if card == null: continue
		(card.find_child("ChapterOpen", true, false) as Button).pressed.emit()
		_check(hub.selected_key() == V2 and not hub._picker_page.visible, "Picking it returns to the host panel with it selected")
		for button: Button in hub._right_column.find_children("*", "Button", true, false):
			if button.text == "Host a room": button.pressed.emit()
		for i in range(4): await process_frame
		var expected: Array = [["create", state[1]]] if state[2] else [["lobby", state[1]]]
		_check(app.actions == expected, "Host a room hosts %s: %s (got %s)" % [state[1], str(listed), str(app.actions)])
		_check(not is_instance_valid(app.room_hub_screen), "Hosting leaves the hub")
	await _locked(app, viewport)
	api.responder = Callable()
	app.relay_session.invalidate_identity()
	app.relay_session = null
	viewport.queue_free()
	await process_frame

## Without hosting access a Full Journey chapter is locked in the friend picker,
## can still be chosen, and Host a room opens the locked hosting page instead of
## creating a room. A Test Store purchase alone does not unlock hosting; a
## tester code does.
func _locked(app: Node, viewport: SubViewport) -> void:
	var store := FakeStore.new()
	app.purchases.queue_free()
	app.purchases = store
	app.add_child(store)
	app.config.purchase_mode = "test_store"
	store.entitled = true
	app.tester = false
	var premium := ""
	for key: String in Registry.offered_keys():
		if Registry.descriptor(key).premium: premium = key; break
	app.actions.clear()
	app.mode = "rooms"
	var hub := Hub.new()
	hub.set_chapters(app._together_chapters())
	hub.host_requested.connect(app._host_from_room_hub)
	app.room_hub_screen = hub
	viewport.add_child(hub)
	await process_frame
	hub.open_chapter_picker()
	await process_frame
	var card: Control = hub._picker.card_for(premium)
	var open: Button = card.find_child("ChapterOpen", true, false) if card != null else null
	var free_open := hub._picker.card_for(Registry.FIRST_STEPS).find_child("ChapterOpen", true, false) as Button
	_check(open != null and open.locked and card.get_meta("full_journey_locked") and (card.find_child("LevelPicture", true, false) as CanvasItem).self_modulate == Picker.LOCKED_PICTURE_TINT and (card.find_child("ChapterAccess", true, false) as Label).get_theme_color("font_color") == Picker.GOLD, "A Full Journey chapter is locked for hosting after a Test Store purchase")
	_check(not free_open.locked, "Free chapters stay open to host")
	if open == null: return
	open.pressed.emit()
	_check(hub.selected_key() == premium and not hub._picker_page.visible, "A locked chapter can still be chosen")
	for button: Button in hub._right_column.find_children("*", "Button", true, false):
		if button.text == "Host a room": button.pressed.emit()
	for i in range(3): await process_frame
	_check(app.mode == "paywall" and app.overlay.find_child("HostingLocked", true, false) != null and app.actions.is_empty() and not is_instance_valid(app.room_hub_screen), "Host a room on a locked chapter opens the locked hosting page and creates nothing")
	app.tester = true
	var unlocked := false
	for item: Dictionary in app._together_chapters():
		if item.key == premium: unlocked = not item.locked
	_check(unlocked, "A tester code unlocks hosting the Full Journey chapter")

func _escape(viewport: SubViewport) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.physical_keycode = KEY_ESCAPE
		key.pressed = pressed
		viewport.push_input(key)

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
