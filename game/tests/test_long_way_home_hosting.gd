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
const PlayerCopy = preload("res://presentation/player_copy.gd")
const RelayLobbyFlow = preload("res://presentation/relay_lobby_flow.gd")
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

## The room hub picks the offered chapter, tags it when the server cannot
## create any version, and hosts its fallback through the same rule.
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
	func _new_relay_lobby_flow() -> RelayLobbyFlow: return HostLobby.new(self)
	func _return_to_room_hub(notice: String = "", _refresh: bool = true) -> void: actions.append(["hub", notice])

## Checks the rooms without the progress card and records each lobby step instead of taking it.
class HostLobby extends RelayLobbyFlow:
	func open_lobby(_chapter: String = "") -> void:
		host.mode = "relay_rooms"
		await host.relay_session.load_lobby()
	func lobby_action(action: String, value: String = "") -> void: host.actions.append([action, value])

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
		_check(await app.relay_session.load_lobby(), "Chapters load with Long Way Home listed as %s" % str(listed))
		app.mode = "rooms"
		var hub := Hub.new()
		hub.set_chapters(app.room_hub_flow.together_chapters())
		hub.closed.connect(app.room_hub_flow.close)
		app.room_hub_flow.screen = hub
		viewport.add_child(hub)
		await process_frame
		hub.open_chapter_picker()
		await process_frame
		var found: Array = []
		for card: Control in hub._picker.grid.get_children():
			if str(card.get_meta("chapter_key")).begins_with("long-way-home@"): found.append(card)
		_check(found.size() == 1, "Exactly one Long Way Home card: " + str(listed))
		if found.size() != 1: continue
		var card: Control = found[0]
		var access := card.find_child("ChapterAccess", true, false) as Label
		var title := card.find_child("LevelTitle", true, false) as Label
		_check(card.get_meta("chapter_key") == V2 and title.text == "Long Way Home" and access.text.contains("unavailable online") != state[2], "The card offers %s and is %s: %s" % [V2, "available" if state[2] else "unavailable", str(listed)])
		var unavailable := 0
		for other: Control in hub._picker.grid.get_children():
			if (other.find_child("ChapterAccess", true, false) as Label).text.contains("unavailable online"): unavailable += 1
		_check(unavailable == (0 if state[2] else 1), "Only chapters the server lacks are tagged unavailable online: " + str(listed))
		_check((card.find_child("ChapterOpen", true, false) as Button).get_meta("completion_variant") == "friend", "The hub picker shows Together completion")
		# Android Back closes the picker first, then the hub.
		root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		await process_frame
		await process_frame
		_check(app.mode == "rooms" and is_instance_valid(hub) and not hub._picker_page.visible and hub._layout.visible, "Android Back closes the hub picker and keeps the hub: " + str(listed))
		root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		await process_frame
		await process_frame
		_check(app.mode == "home" and not is_instance_valid(app.room_hub_flow.screen), "Android Back on the hub returns Home: " + str(listed))
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
		hub.set_chapters(app.room_hub_flow.together_chapters())
		hub.host_requested.connect(app.room_hub_flow._host_room)
		app.room_hub_flow.screen = hub
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
		var expected: Array = [["create", state[1]]] if state[2] else [["hub", PlayerCopy.MAIN_73FEF220EAF1]]
		_check(app.actions == expected, "Host a room hosts %s: %s (got %s)" % [state[1], str(listed), str(app.actions)])
		_check(not is_instance_valid(app.room_hub_flow.screen), "Hosting leaves the hub")
	await _locked(app, viewport)
	api.responder = Callable()
	app.relay_session.invalidate_identity()
	app.relay_session = null
	viewport.queue_free()
	await process_frame

## Without hosting access a Full Journey chapter is locked in the friend picker,
## can still be chosen, and Host a room opens the locked hosting page instead of
## creating a room. A Test Store purchase alone does not unlock hosting; a
## tester code does. Owned through the Test Store, the card goes to Tester code.
func _locked(app: Node, viewport: SubViewport) -> void:
	var store := FakeStore.new()
	app.purchases.queue_free()
	app.purchases = store
	app.add_child(store)
	app.config.purchase_mode = "test_store"
	app.tester = false
	var premium := ""
	for key: String in Registry.offered_keys():
		if Registry.descriptor(key).premium: premium = key; break
	store.entitled = true
	await _locked_owned(app, viewport, premium)
	store.entitled = false
	app.actions.clear()
	app.mode = "rooms"
	var hub := Hub.new()
	hub.set_chapters(app.room_hub_flow.together_chapters())
	hub.host_requested.connect(app.room_hub_flow._host_room)
	app.room_hub_flow.screen = hub
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
	_check(app.mode == "paywall" and app.overlay.find_child("HostingLocked", true, false) != null and app.actions.is_empty() and not is_instance_valid(app.room_hub_flow.screen), "Host a room on a locked chapter opens the locked hosting page and creates nothing")
	app.tester = true
	var unlocked := false
	for item: Dictionary in app.room_hub_flow.together_chapters():
		if item.key == premium: unlocked = not item.locked
	_check(unlocked, "A tester code unlocks hosting the Full Journey chapter")
	app.tester = false

## A Test Store purchase without a tester code: the locked card says so and
## its tap opens Tester code, creating nothing.
func _locked_owned(app: Node, viewport: SubViewport, premium: String) -> void:
	app.actions.clear()
	app.mode = "rooms"
	var hub := Hub.new()
	hub.set_chapters(app.room_hub_flow.together_chapters())
	hub.host_requested.connect(app.room_hub_flow._host_room)
	hub.tester_code_requested.connect(app.room_hub_flow._open_tester_code)
	app.room_hub_flow.screen = hub
	viewport.add_child(hub)
	await process_frame
	hub.open_chapter_picker()
	await process_frame
	var card: Control = hub._picker.card_for(premium)
	var open: Button = card.find_child("ChapterOpen", true, false) if card != null else null
	var access: Label = card.find_child("ChapterAccess", true, false) if card != null else null
	_check(open != null and open.locked and (card.find_child("LevelPicture", true, false) as CanvasItem).self_modulate == Picker.LOCKED_PICTURE_TINT and access.get_theme_color("font_color") == Picker.GOLD and access.text == PlayerCopy.HOSTING_NEEDS_TESTER_CODE, "Owned through the Test Store, the locked card says hosting needs a tester code")
	if open == null: return
	open.pressed.emit()
	for i in range(2): await process_frame
	_check(app.mode == "tester_access" and app.actions.is_empty() and not is_instance_valid(app.room_hub_flow.screen), "The locked card opens Tester code and creates nothing")

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
