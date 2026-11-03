extends SceneTree
## The one online/offline answer (services/connectivity.gd), how it learns
## (Main's RoomsApi, the live socket, the probe in services/connectivity_probe.gd)
## and the controls it greys (presentation/offline_hold.gd):
## - unknown at launch reads as online, so a first tap registers;
## - going offline takes two failures in a row with no answer between them
##   (one dropped request, or failures between answers, never grey anything);
## - any answer, of any status, or the live socket opening reads as online at once;
## - only real transport failures count: a request that could not start, a
##   cancelled or refused one, and an API that is not Main's say nothing;
## - the probe runs no frames while online, in the background or without a
##   server; offline in front it asks on RefreshSchedule's pace, at once on a
##   resume or a tap, and stops on the first answer;
## - a held button greys while offline, says why on a tap and asks the server,
##   comes back by itself, and never enables what its screen disabled;
## - Home greys Play with your friend and Duels and keeps Solo, Friends,
##   Replays, Invite, the Wardrobe, What's new and Settings; the Pollen chip's
##   plus greys; a name change and the Pollen store say why instead of opening;
## - Settings greys exactly the rows that need the server.
const Connectivity = preload("res://services/connectivity.gd")
const Probe = preload("res://services/connectivity_probe.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const SettingsRows = preload("res://presentation/settings_rows.gd")
const PollenStoreFlow = preload("res://presentation/pollen_store_flow.gd")
const DisplayNameFlow = preload("res://presentation/display_name_flow.gd")

## The Pollen store as if it sold here, to see that offline it still does not open.
class OpenStore extends "res://presentation/pollen_store_flow.gd":
	func available() -> bool: return true

## The Wardrobe as Main sees it: shown while `on`, and what Main tells it.
class WardrobeStub extends "res://presentation/wardrobe_flow.gd":
	var on := true
	var told: Array = []
	var synced := 0
	func available() -> bool: return on
	func connectivity_changed(online: bool) -> void: told.append(online)
	func sync_pending() -> void: synced += 1

## Names as if on, to see that offline a change does not open.
class NamesOn extends "res://presentation/display_name_flow.gd":
	var opened := 0
	func enabled() -> bool: return true
	func _open(_parent: Control, _editing: bool, _opener: Control, _hint_later: bool = false) -> void: opened += 1

## Answers every request with `reply` ([result, status, headers, body], or []).
class ScriptedApi extends "res://services/rooms_api.gd":
	var reply: Array = []
	func _send(_method: int, _path: String, _headers: PackedStringArray, _body: String) -> Array:
		await Engine.get_main_loop().process_frame
		return reply

class Fake extends RefCounted:
	var asked := 0
	var replies: Array = []
	func call_it(_url: String) -> Array:
		asked += 1
		await Engine.get_main_loop().process_frame
		return replies.pop_front() if not replies.is_empty() else [HTTPRequest.RESULT_CANT_RESOLVE, 0, PackedStringArray(), PackedByteArray()]

var CANT := [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
var OK_200 := [HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), PackedByteArray()]

var checks := 0
var failures := 0
var clock_ms := 100000

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _frames(count: int = 4) -> void:
	for i in range(count): await process_frame

func _fresh() -> RefCounted:
	var state: RefCounted = Connectivity.new()
	Connectivity.use_shared(state)
	return state

func _run() -> void:
	_states()
	await _rooms_api()
	await _probe()
	await _holds()
	await _home()
	_settings_rows()
	Connectivity.use_shared(null)
	OfflineHold.say_default = Callable()
	print("AFTER YOU CONNECTIVITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _states() -> void:
	var state := _fresh()
	var heard: Array = []
	state.changed.connect(func(online: bool) -> void: heard.append(online))
	_check(state.state == Connectivity.State.UNKNOWN and state.online(), "Unknown at launch reads as online")
	state.note_response(CANT)
	_check(state.online() and heard.is_empty(), "One failure greys nothing")
	state.note_response(CANT)
	_check(not state.online() and heard == [false], "A second failure in a row reads as offline, said once")
	state.note_response(CANT)
	_check(heard == [false], "More failures say nothing new")
	state.note_response([HTTPRequest.RESULT_SUCCESS, 503, PackedStringArray(), PackedByteArray()])
	_check(state.online() and heard == [false, true], "Any answer, even a server error, is online at once")
	# A flaky line: failures between answers never flip it.
	for i in range(6):
		state.note_response(CANT)
		state.note_response(OK_200)
	_check(state.online() and heard == [false, true], "Failures between answers never flicker the state")
	state.note_response([])
	state.note_response([])
	state.note_response([HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, 0, PackedStringArray(), PackedByteArray()])
	state.note_response([HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray()])
	_check(state.online(), "A request that could not start, an oversized body or a failed request call say nothing")
	for code: int in [HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_TIMEOUT]:
		state.note_reached()
		state.note_response([code, 0, PackedStringArray(), PackedByteArray()])
		state.note_response([code, 0, PackedStringArray(), PackedByteArray()])
		_check(not state.online(), "Result %d twice reads as offline" % code)
	state.note_reached()
	_check(state.online() and state.state == Connectivity.State.ONLINE, "The live socket opening (note_reached) is online at once")
	var probes := [0]
	state.probe = func() -> void: probes[0] += 1
	state.check_now()
	_check(probes[0] == 0, "Online, a check asks nothing")
	state.force(false)
	state.check_now()
	_check(probes[0] == 1 and not state.online(), "Offline, a check asks the probe once")
	Connectivity.use_shared(null)
	_check(Connectivity.shared() != state and Connectivity.shared().online(), "A fresh shared answer starts unknown")

func _rooms_api() -> void:
	var state := _fresh()
	var api := ScriptedApi.new()
	api.base_url = "https://connectivity.example.test"
	api.connectivity = state
	root.add_child(api)
	var other := ScriptedApi.new()
	other.base_url = api.base_url
	root.add_child(other)
	other.reply = CANT.duplicate()
	await other.request_json(HTTPClient.METHOD_GET, "/v1/friends")
	await other.request_json(HTTPClient.METHOD_GET, "/v1/friends")
	_check(state.online(), "An API that is not Main's says nothing")
	api.reply = []
	await api.request_json(HTTPClient.METHOD_GET, "/v1/friends")
	await api.request_json(HTTPClient.METHOD_GET, "/v1/friends")
	_check(state.online(), "A request that could not start says nothing")
	api.reply = CANT.duplicate()
	await api.request_json(HTTPClient.METHOD_GET, "/v1/friends")
	_check(state.online(), "One failed request leaves it online")
	await api.request_json(HTTPClient.METHOD_POST, "/v1/pollen/equip", {})
	_check(not state.online(), "Two failed requests read as offline")
	api.reply = [HTTPRequest.RESULT_SUCCESS, 409, PackedStringArray(), JSON.stringify({"error": {"code": "room_full"}}).to_utf8_buffer()]
	await api.request_json(HTTPClient.METHOD_POST, "/v2/rooms/join", {})
	_check(state.online(), "A refusal is still an answer: online")
	var unconfigured := ScriptedApi.new()
	unconfigured.connectivity = state
	root.add_child(unconfigured)
	state.force(true)
	unconfigured.reply = CANT.duplicate()
	await unconfigured.request_json(HTTPClient.METHOD_GET, "/v1/friends")
	await unconfigured.request_json(HTTPClient.METHOD_GET, "/v1/friends")
	_check(state.online(), "A build with no server never reads as offline")
	for node: Node in [api, other, unconfigured]: node.queue_free()
	await _frames(2)

func _probe() -> void:
	var state := _fresh()
	var fake := Fake.new()
	var probe := Probe.new()
	probe.transport = fake.call_it
	probe.clock = func() -> int: return clock_ms
	probe.base_url = "https://connectivity.example.test"
	probe.configured = true
	root.add_child(probe)
	await _frames()
	_check(not probe.active() and fake.asked == 0, "Online, the probe runs no frames and asks nothing")
	state.force(false)
	_check(probe.active(), "Offline in front, the probe runs")
	await _frames()
	_check(fake.asked == 0, "It waits its first pace before asking")
	clock_ms += Probe.FIRST_MS
	await _frames()
	_check(fake.asked == 1 and not state.online() and probe.active(), "Then it asks once; a failure keeps it offline and running")
	clock_ms += 4000
	await _frames()
	_check(fake.asked == 1, "After a failure it waits its pace again (RefreshSchedule's failure delays)")
	probe.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(not probe.active(), "In the background it runs no frames")
	clock_ms += 60000
	await _frames()
	_check(fake.asked == 1, "And asks nothing")
	fake.replies = [OK_200.duplicate()]
	probe.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check(probe.active(), "Back in front it runs again")
	await _frames()
	_check(fake.asked == 2 and state.online() and not probe.active(), "And asks at once; an answer reads as online and it stops")
	state.force(false)
	state.check_now()
	await _frames()
	_check(fake.asked == 3, "A tap on something greyed asks at once")
	var idle := Probe.new()
	idle.transport = fake.call_it
	root.add_child(idle)
	await _frames()
	_check(not idle.active(), "Without a server the probe never runs")
	idle.queue_free()
	probe.queue_free()
	await _frames(2)
	_check(not state.probe.is_valid(), "A probe that leaves stops being the one that asks")

func _holds() -> void:
	var state := _fresh()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var box := Control.new()
	box.size = Vector2(400, 300)
	viewport.add_child(box)
	var button := Button.new()
	button.text = "Join"
	button.position = Vector2(20, 20)
	button.size = Vector2(160, 60)
	var icon := TextureRect.new()
	button.add_child(icon)
	box.add_child(button)
	var busy := Button.new()
	busy.disabled = true
	box.add_child(busy)
	var said: Array = []
	OfflineHold.hold(button, func(text: String) -> void: said.append(text))
	OfflineHold.hold(busy)
	_check(not button.disabled and not OfflineHold.held(button), "Online a held button works as before")
	state.force(false)
	_check(button.disabled and OfflineHold.held(button) and button.visible, "Offline it greys and stays where it is")
	_check(is_equal_approx(icon.modulate.a, OfflineHold.DIM), "What it draws as children fades with it")
	_check(busy.disabled and not OfflineHold.held(busy), "One its screen disabled is left alone")
	var probes := [0]
	state.probe = func() -> void: probes[0] += 1
	await _frames(2)
	_tap(viewport, Vector2(60, 50))
	await _frames(2)
	_check(said == [PlayerCopy.OFFLINE_NEEDS_CONNECTION] and probes[0] == 1, "A tap on it says why and asks the server once: %s" % [said])
	_tap(viewport, Vector2(60, 50))
	await _frames(2)
	_check(said.size() == 1, "A second touch of the same tap says nothing more")
	var pressed := [0]
	button.pressed.connect(func() -> void: pressed[0] += 1)
	OfflineHold.set_enabled(button, true)
	_check(button.disabled and OfflineHold.held(button), "The screen enabling it while offline keeps it greyed")
	state.note_reached()
	_check(not button.disabled and not OfflineHold.held(button) and is_equal_approx(icon.modulate.a, 1.0), "Online again it comes back by itself, nothing built again")
	_check(busy.disabled, "And one its screen disabled stays disabled")
	await _frames(2)
	_tap(viewport, Vector2(60, 50))
	await _frames(2)
	_check(pressed[0] == 1 and said.size() == 1, "The first tap online registers")
	OfflineHold.set_enabled(button, false)
	state.force(false)
	state.note_reached()
	_check(button.disabled, "Disabled by its screen before going offline: still disabled after")
	OfflineHold.set_enabled(button, true)
	_check(not button.disabled, "And the screen enabling it online works")
	var bare := Button.new()
	OfflineHold.set_enabled(bare, false)
	_check(bare.disabled, "set_enabled on a button with no hold just sets it")
	bare.free()
	var sunk: Array = []
	OfflineHold.say_default = func(text: String) -> void: sunk.append(text)
	var plain := Button.new()
	plain.position = Vector2(220, 20)
	plain.size = Vector2(120, 60)
	box.add_child(plain)
	OfflineHold.hold(plain)
	state.force(false)
	await _frames(2)
	_tap(viewport, Vector2(260, 50))
	await _frames(2)
	_check(sunk == [PlayerCopy.OFFLINE_NEEDS_CONNECTION], "A hold with no sink of its own says why through the default (Main's toast)")
	# A drag through a list that starts on a greyed button is a scroll: it says nothing.
	await create_timer(0.5).timeout
	for step: Array in [[true, Vector2(260, 50)], [false, Vector2(260, 130)]]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = step[0]
		event.position = step[1]
		event.global_position = step[1]
		viewport.push_input(event)
	await _frames(2)
	_check(sunk.size() == 1, "A drag that starts on a greyed button says nothing")
	# The one refusal every entry point uses.
	var heard: Array = []
	var asked := [0]
	state.probe = func() -> void: asked[0] += 1
	_check(OfflineHold.refuse(func(text: String) -> void: heard.append(text)) and heard == [PlayerCopy.OFFLINE_NEEDS_CONNECTION] and asked[0] == 1, "Offline the refusal says why and asks the server once")
	state.note_reached()
	_check(not OfflineHold.refuse(func(text: String) -> void: heard.append(text)) and heard.size() == 1, "Online it lets the caller go on")
	viewport.queue_free()
	await _frames(2)

func _tap(viewport: SubViewport, at: Vector2) -> void:
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = at
		event.global_position = at
		viewport.push_input(event)

func _home() -> void:
	var state := _fresh()
	var path := "user://connectivity-home-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1560, 720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves = Storage.new(path)
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	app.saves.flush()
	viewport.add_child(app)
	app.set_process(false)
	await _frames()
	_check(app.api.connectivity == state, "Main's API tells the shared answer")
	var menu: Control = app.home_menu_view
	var greyed: Array = [menu.play_button, menu.duels_button]
	var kept: Array = [menu.solo_button, menu.friends_button, menu.replays_button, menu.invite_button, menu.whats_new_button, menu.settings_button, menu.wardrobe_button]
	state.force(false)
	for button: Button in greyed: _check(button.disabled and OfflineHold.held(button), "Offline Home greys %s" % button.name)
	for button: Button in kept: _check(not button.disabled, "Offline Home keeps %s" % button.name)
	state.note_reached()
	_check(app.home_menu_view == menu and not menu.play_button.disabled and not menu.duels_button.disabled, "Online again Home's buttons come back, Home not built again")
	state.force(false)
	app._show_home()
	await _frames()
	_check(app.home_menu_view.play_button.disabled, "A Home built offline starts greyed")
	state.note_reached()
	_check(not app.home_menu_view.play_button.disabled, "And comes back too")
	# The Wardrobe hears each flip, and Home's row follows what it can show then.
	var real_wardrobe: Node = app.wardrobe_flow
	var stub := WardrobeStub.new(app)
	app.add_child(stub)
	app.wardrobe_flow = stub
	app._refresh_home_pollen()
	_check(app.home_menu_view.wardrobe_button.visible, "The Wardrobe row shows while the Wardrobe has something to show")
	stub.on = false
	state.force(false)
	_check(stub.told == [false] and not app.home_menu_view.wardrobe_button.visible, "Offline the Wardrobe hears it and the row follows (hidden with nothing saved)")
	stub.on = true
	state.note_reached()
	_check(stub.told == [false, true] and app.home_menu_view.wardrobe_button.visible, "Online again the Wardrobe hears it and the row comes back")
	app._follow_identity()
	_check(stub.synced == 1, "The identity read sends a look put on offline")
	app.pollen_client.settled.emit()
	_check(stub.synced == 2, "So does each Pollen flush")
	app.wardrobe_flow = real_wardrobe
	stub.queue_free()
	# Routes with no button say why instead of trying.
	var toasts: Array = []
	state.force(false)
	_check(app._offline_blocked(func(text: String) -> void: toasts.append(text)) and toasts == [PlayerCopy.OFFLINE_NEEDS_CONNECTION], "Offline an entry point says why")
	state.note_reached()
	_check(not app._offline_blocked(), "Online it lets the entry through")
	app._live_health_changed(false)
	state.force(false)
	app._live_health_changed(true)
	_check(state.online(), "The live socket opening reads as online")
	# The Pollen chip's plus (the store) greys; its balance stays.
	var chip: Control = PollenChip.make(1200, true)
	viewport.add_child(chip)
	state.force(false)
	_check(chip.plus_button.disabled and not chip.amount_button.disabled, "Offline the chip's plus greys and its balance stays")
	state.note_reached()
	_check(not chip.plus_button.disabled, "And the plus comes back")
	chip.queue_free()
	# The Pollen store and a name change say why instead of opening.
	state.force(false)
	var before: String = app.mode
	var store := OpenStore.new(app)
	app.add_child(store)
	store.show_store("home")
	_check(app.mode == before and not store.is_open(), "Offline the Pollen store does not open")
	var names := NamesOn.new(app)
	app.add_child(names)
	names.edit(app.overlay)
	_check(names.opened == 0, "Offline a name change does not open")
	state.note_reached()
	names.edit(app.overlay)
	_check(names.opened == 1, "Online it opens")
	store.queue_free()
	names.queue_free()
	viewport.queue_free()
	await _frames(2)
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _settings_rows() -> void:
	var expected := ["public_duels", "leaderboard_name", "retry_cleanup", "finish_recovery", "hosting_access", "photo_transfer", "safety_reports", "create_identity", "recover_identity", "delete_identity"]
	var source := FileAccess.get_file_as_string("res://presentation/settings_rows.gd")
	var marked: Array = []
	var pattern := RegEx.create_from_string("\\{\"id\": \"([a-z_]+)\", \"online\": true")
	for found: RegExMatch in pattern.search_all(source): marked.append(found.get_string(1))
	marked.sort()
	expected.sort()
	_check(marked == expected, "Settings greys exactly the rows that need the server: %s" % [marked])
	for kept: String in ["sound", "pollen", "whats_new", "licenses", "share_online_status", "community"]:
		_check(not kept in marked, "Settings keeps %s offline" % kept)
