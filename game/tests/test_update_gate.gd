extends SceneTree
## Required-update gate (services/app_status.gd, services/client_identity.gd,
## presentation/update_gate_screen.gd and main.gd's mode "update_gate").
## Covers: the version grammar shared with the server, channels per platform and
## store, the X-AfterYou-Client header on every request and on the status check,
## failing open on every kind of bad answer, no block kept across launches or after a
## later "off", the six-hour resume check, the screen itself (no Back, Update targets
## for Play, GitHub and the App Store, Play Solo), solo play, Settings and account
## screens while gated, online entry points showing the screen again, an answer that
## arrives mid-turn or under a finger, and the 426 client_update_required mapping.

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const Api = preload("res://services/rooms_api.gd")
const AppStatus = preload("res://services/app_status.gd")
const ClientIdentity = preload("res://services/client_identity.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const UpdateGate = preload("res://presentation/update_gate_screen.gd")
const Copy = preload("res://presentation/player_copy.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const WrongTypes = preload("res://tests/wrong_types.gd")
const VECTORS := "res://tests/fixtures/update_gate/versions.json"
const APP_STORE_LINK := "https://apps.apple.com/app/after-you/id0000000000"
const SUCCESS := HTTPRequest.RESULT_SUCCESS

## Records each request's headers instead of sending it, and answers with `reply`.
class HeaderCapture extends "res://services/rooms_api.gd":
	var sent: Array[PackedStringArray] = []
	var reply: Array = [HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "{}".to_utf8_buffer()]
	func _send(_method: int, _path: String, headers: PackedStringArray, _body: String) -> Array:
		sent.append(headers)
		return reply

## A status transport: records each call and answers with the next reply.
class Transport extends RefCounted:
	var calls: Array = []
	var replies: Array = []
	func send(url: String, headers: PackedStringArray) -> Array:
		calls.append({"url": url, "headers": headers})
		return replies.pop_front() if not replies.is_empty() else []

## Stands in for the Friends layer: closes like the real one.
class FakeFriends extends CanvasLayer:
	signal closed
	func close() -> void:
		closed.emit()
		queue_free()
var checks := 0
var failures := 0
var opened: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_versions()
	_channels()
	await _request_headers()
	_interpret()
	await _status_check()
	_targets()
	await _screen()
	await _ios()
	_reset_overrides()
	print("AFTER YOU UPDATE GATE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _reset_overrides() -> void:
	PlatformSupport.override_platform = ""
	ClientIdentity.override_version = ""
	ClientIdentity.override_purchase_mode = ""


## The same vectors as backend/test/app-status.test.ts.
func _versions() -> void:
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VECTORS))
	for value: String in vectors.valid: _check(not ClientIdentity.parse(value).is_empty(), "A valid version parses: " + value)
	for value: String in vectors.invalid: _check(ClientIdentity.parse(value).is_empty(), "An invalid version is refused: '%s'" % value)
	_check(ClientIdentity.parse(6).is_empty() and ClientIdentity.parse(null).is_empty(), "Only strings are versions")
	var ordered: Array = vectors.ordered
	var agree := true
	for i in range(ordered.size()):
		for j in range(ordered.size()):
			if ClientIdentity.compare(ordered[i], ordered[j]) != signi(i - j):
				agree = false
				push_error("%s vs %s" % [ordered[i], ordered[j]])
	_check(agree, "Releases and pre-releases sort by semantic version precedence, the same as the server")
	_check(ClientIdentity.compare("0.6.2-rc.1", "0.6.2") == -1 and ClientIdentity.compare("0.6.2", "0.6.2-rc.1") == 1, "A pre-release is older than its release")
	_check(ClientIdentity.compare("0.6.2", "0.6.2") == 0 and ClientIdentity.compare("0.6.10", "0.6.9") == 1 and ClientIdentity.compare("0.7.0", "0.6.99") == 1 and ClientIdentity.compare("1.0.0", "0.99.99") == 1, "Equal, patch, minor and major compare as numbers")
	_check(ClientIdentity.compare("0.6", "0.6.2") == null and ClientIdentity.compare("0.6.2", "latest") == null, "A comparison with an invalid version has no answer")


func _channels() -> void:
	var cases := [
		[PlatformSupport.ANDROID, "google_play", "play"], [PlatformSupport.ANDROID, "test_store", "github"], [PlatformSupport.ANDROID, "tester_only", "github"],
		[PlatformSupport.ANDROID, "", "dev"], [PlatformSupport.ANDROID, "app_store", "dev"],
		[PlatformSupport.IOS, "app_store", "app_store"], [PlatformSupport.IOS, "test_store", "dev"], [PlatformSupport.IOS, "tester_only", "dev"], [PlatformSupport.IOS, "google_play", "dev"],
		[PlatformSupport.DESKTOP, "google_play", "dev"], [PlatformSupport.DESKTOP, "test_store", "dev"], [PlatformSupport.DESKTOP, "app_store", "dev"]]
	for item: Array in cases:
		_check(ClientIdentity.channel_for(item[0], item[1]) == item[2], "%s with %s is channel %s" % item)
	_check(ClientIdentity.channel() == ClientIdentity.DEV, "This desktop test run is the dev channel")
	_check(ClientIdentity.header_line() == "X-AfterYou-Client: %s dev" % ProjectSettings.get_setting("application/config/version"), "The header names this build's version and channel")
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	ClientIdentity.override_purchase_mode = "google_play"
	ClientIdentity.override_version = "0.6.2-rc.1"
	_check(ClientIdentity.header_line() == "X-AfterYou-Client: 0.6.2-rc.1 play", "A Play pre-release names itself")
	ClientIdentity.override_version = "0.6"
	_check(ClientIdentity.header_line().is_empty(), "A build with an invalid version sends no header")
	_reset_overrides()


func _request_headers() -> void:
	var capture := HeaderCapture.new()
	root.add_child(capture)
	capture.base_url = "https://headers.synthetic.invalid"
	capture.player_id = "PPPPPPPPPPPPPPPPPPPPPP"
	capture.device_token = "synthetic-device-token"
	var line := ClientIdentity.header_line()
	for item: Array in [[HTTPClient.METHOD_GET, "/v1/room-inbox"], [HTTPClient.METHOD_POST, "/v1/friends"], [HTTPClient.METHOD_DELETE, "/v1/identity"], [HTTPClient.METHOD_GET, "/v2/capabilities"]]:
		await capture.request_json(item[0], item[1], {})
	await capture.request_json_with_headers(HTTPClient.METHOD_POST, "/v1/notifications/registration", {}, PackedStringArray(["X-AfterYou-Platform: ios"]))
	var every := capture.sent.size() == 5
	for headers: PackedStringArray in capture.sent:
		every = every and headers.count(line) == 1
	_check(every, "Every RoomsApi request carries X-AfterYou-Client once")
	# A route that refuses this build as too old raises the update check.
	capture.reply = [SUCCESS, 426, PackedStringArray(), JSON.stringify({"error": {"code": "client_update_required", "retryable": false}}).to_utf8_buffer()]
	var raised := [0]
	capture.update_required.connect(func(): raised[0] += 1)
	var refused: Dictionary = await capture.request_json(HTTPClient.METHOD_POST, "/v2/rooms", {})
	_check(raised[0] == 1 and not refused.ok and refused.error == Copy.UPDATE_REQUIRED_ERROR, "426 client_update_required says a newer version is needed and asks for an update check")
	capture.reply = [SUCCESS, 426, PackedStringArray(), JSON.stringify({"error": {"code": "other", "retryable": false}}).to_utf8_buffer()]
	await capture.request_json(HTTPClient.METHOD_POST, "/v2/rooms", {})
	capture.reply = [SUCCESS, 400, PackedStringArray(), JSON.stringify({"error": {"code": "client_update_required", "retryable": false}}).to_utf8_buffer()]
	await capture.request_json(HTTPClient.METHOD_POST, "/v2/rooms", {})
	_check(raised[0] == 1, "Only that exact status and code ask for a check")
	capture.free()


func _body(value: Variant) -> PackedByteArray:
	return (value if value is String else JSON.stringify(value)).to_utf8_buffer()


func _reply(value: Variant, status: int = 200, result: int = SUCCESS) -> Array:
	return [result, status, PackedStringArray(), _body(value)]


func _required(min_version: String = "0.6.2", channel: String = "play") -> Dictionary:
	return {"schema_version": 1, "gate": "required", "min_version": min_version, "channel": channel}


func _interpret() -> void:
	var good := AppStatus.interpret(_reply(_required()), "0.6.1", "play")
	for variant: Dictionary in WrongTypes.variants(_required()):
		_check(AppStatus.interpret(_reply(variant.value), "0.6.1", "play") == AppStatus.OFF, "A status with a wrongly typed field leaves the gate off: " + variant.path)
	_check(good == {"gate": "required", "min_version": "0.6.2", "channel": "play"}, "A complete answer naming a newer version for this channel blocks")
	_check(AppStatus.interpret(_reply(JSON.stringify(_required()).replace("1,", "1.0,")), "0.6.1", "play").gate == "required", "schema_version 1.0 from the JSON parser still counts as 1")
	_check(AppStatus.interpret(_reply(_required("0.6.2", "github")), "0.6.2-rc.1", "github").gate == "required", "A pre-release of the minimum is still below it")
	var extra := _required()
	extra["note"] = "x"
	var schema_two := _required()
	schema_two.schema_version = 2
	var schema_text := _required()
	schema_text.schema_version = "1"
	var no_channel := _required()
	no_channel.erase("channel")
	var number_min := _required()
	number_min.min_version = 62
	var big := " ".repeat(5000) + JSON.stringify(_required())
	var open := {
		"the request could not start": [],
		"a timeout": _reply(_required(), 0, HTTPRequest.RESULT_TIMEOUT),
		"a refused connection": _reply(_required(), 0, HTTPRequest.RESULT_CANT_CONNECT),
		"no response": _reply(_required(), 0, HTTPRequest.RESULT_NO_RESPONSE),
		"an oversized body": _reply(_required(), 200, HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED),
		"a body over 4 KiB": _reply(big),
		"garbage": _reply("<html>gate required</html>"),
		"an empty body": _reply(""),
		"a JSON array": _reply("[1]"),
		"an extra key": _reply(extra),
		"schema_version 2": _reply(schema_two),
		"schema_version as text": _reply(schema_text),
		"a missing channel": _reply(no_channel),
		"a number as min_version": _reply(number_min),
		"another channel": _reply(_required("0.6.2", "github")),
		"a minimum equal to this version": _reply(_required("0.6.1")),
		"a minimum below this version": _reply(_required("0.6.0")),
		"a malformed minimum": _reply(_required("0.6")),
		"a gate that is off": _reply({"schema_version": 1, "gate": "off"}),
		"an unknown gate": _reply({"schema_version": 1, "gate": "maybe", "min_version": "0.6.2", "channel": "play"}),
		"401 while the server's gate is off": _reply({"error": {"code": "invalid_auth", "retryable": false}}, 401),
		"429 from the public limiter": _reply({"error": {"code": "rate_limited", "retryable": true}}, 429),
		"500": _reply(_required(), 500),
		"503": _reply({"error": {"code": "service_unavailable", "retryable": true}}, 503),
		"a 204": _reply(_required(), 204),
	}
	for name: String in open:
		_check(AppStatus.interpret(open[name], "0.6.1", "play") == AppStatus.OFF, "Fails open on " + name)
	_check(AppStatus.interpret(_reply(_required()), "0.6", "play") == AppStatus.OFF, "Fails open when this build's own version is invalid")
	_check(AppStatus.interpret(_reply(_required("0.6.2", "dev")), "0.6.1", "dev") == AppStatus.OFF, "The dev channel is never gated")


func _status_check() -> void:
	var status := AppStatus.new()
	root.add_child(status)
	var transport := Transport.new()
	status.transport = transport.send
	var clock := [1_800_000_000.0]
	status.clock = func() -> float: return clock[0]
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	ClientIdentity.override_purchase_mode = "google_play"
	ClientIdentity.override_version = "0.6.1"
	status.base_url = "https://status.synthetic.invalid/"
	transport.replies = [_reply(_required())]
	await status.check()
	_check(transport.calls.is_empty() and not status.required(), "A build without a server address never asks")
	status.configured = true
	await status.check()
	_check(transport.calls.size() == 1 and status.required(), "A configured Play build asks once and reads the answer")
	if transport.calls.size() == 1:
		var call: Dictionary = transport.calls[0]
		_check(call.url == "https://status.synthetic.invalid/v1/app-status", "It asks GET /v1/app-status")
		_check(call.headers == PackedStringArray(["X-AfterYou-Client: 0.6.1 play"]), "It sends only the client header: no player ID, credentials or body")
	_check(not status.due(), "A fresh answer is not due again")
	clock[0] += AppStatus.RECHECK_SECONDS - 1
	_check(not status.due(), "Under six hours later it is not due")
	clock[0] += 1
	_check(status.due(), "Six hours later a resume asks again")
	clock[0] -= 86400
	_check(status.due(), "A clock moved backwards asks again")
	# A later error or "off" lifts the block: nothing is kept from an earlier answer.
	transport.replies = [[]]
	await status.check()
	_check(not status.required(), "A later failed check lifts the block (fail open, no cached block)")
	transport.replies = [_reply(_required()), _reply({"schema_version": 1, "gate": "off"})]
	await status.check()
	await status.check()
	_check(not status.required() and transport.calls.size() == 4, "A later off answer lifts the block")
	ClientIdentity.override_purchase_mode = ""
	PlatformSupport.override_platform = PlatformSupport.DESKTOP
	await status.check()
	_check(transport.calls.size() == 4 and not status.required(), "A desktop (dev) build never asks")
	status.free()
	_reset_overrides()


func _targets() -> void:
	_check(UpdateGate.target(ClientIdentity.PLAY, {}) == "https://play.google.com/store/apps/details?id=com.aamirazeez.afteryou", "Play builds update from the Play listing")
	_check(UpdateGate.target(ClientIdentity.GITHUB, {}) == "https://github.com/aamir-azeez/after-you/releases/latest", "Tester builds update from the latest GitHub release")
	_check(UpdateGate.target(ClientIdentity.APP_STORE, {"app_store_url": APP_STORE_LINK}) == APP_STORE_LINK, "App Store builds update from the configured App Store page")
	for bad: Variant in [null, "", "http://apps.apple.com/app/id1", "https://apps.apple.com/", "https://example.com/apps.apple.com/", "https://apps.apple.com/app/x id1", 42]:
		_check(UpdateGate.target(ClientIdentity.APP_STORE, {} if bad == null else {"app_store_url": bad}).is_empty(), "No App Store target from %s" % str(bad))
	_check(UpdateGate.target(ClientIdentity.DEV, {"app_store_url": APP_STORE_LINK}).is_empty(), "A dev build has no update target")
	_check(UpdateGate.target(ClientIdentity.PLAY, {"app_store_url": APP_STORE_LINK}) == UpdateGate.PLAY_LISTING_URL, "An Android build never opens the App Store")


## A Main in its own viewport, with a muted isolated save and a fake room API.
func _app(path: String) -> Array:
	var storage := Storage.new(path)
	storage.data.settings.sound = false
	storage.data.settings.haptics = false
	storage.flush()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var app := Main.new()
	app.saves = storage
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var api := FakeApi.new()
	app.add_child(api)
	app.api = api
	app.identity_loading = false
	app.update_gate_open_url = func(url: String) -> void: opened.append(url)
	await _settle()
	return [viewport, app]


func _gate(app: Node, transport: Transport, answer: Dictionary) -> void:
	app.app_status.configured = true
	app.app_status.base_url = "https://status.synthetic.invalid"
	app.app_status.transport = transport.send
	transport.replies = [_reply(answer)]
	await app._check_app_status()
	app._service_update_gate()
	await _settle()


func _button(app: Node, label: String) -> Button:
	for button: Button in app.overlay.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and (button.text == label or button.tooltip_text == label): return button
	return null


func _screen() -> void:
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	ClientIdentity.override_purchase_mode = "google_play"
	ClientIdentity.override_version = "0.6.1"
	var path := "user://update-gate-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var made := await _app(path)
	var viewport: SubViewport = made[0]
	var app: Node = made[1]
	_check(app.mode == "home" and not app._update_gate_active(), "Home shows at once and nothing is gated before an answer")
	var transport := Transport.new()
	# An answer arriving during a solo turn waits: the turn is never interrupted.
	app._start_practice(0)
	await _settle()
	app._begin_turn()
	await _settle()
	var in_turn: String = app.mode
	await _gate(app, transport, _required())
	_check(app._update_gate_active() and app.mode == in_turn and app.running, "An answer that arrives mid-turn leaves the turn running")
	app._show_home()
	app._service_update_gate()
	await _settle()
	_check(app.mode == "update_gate", "Back on Home, the update screen replaces it")
	_check(app.frame_demand() == "calm", "The update screen is a calm menu for the frame policy")
	var update := _button(app, Copy.UPDATE_GATE_UPDATE)
	var solo := _button(app, Copy.UPDATE_GATE_SOLO)
	var texts: Array = app.overlay.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	_check(texts.has(Copy.UPDATE_GATE_TITLE) and texts.has(Copy.UPDATE_GATE_BODY % "0.6.2"), "It says Time to update and names version 0.6.2")
	_check(update != null and solo != null and _button(app, "Back") == null and _button(app, "Close") == null, "It offers Update and Play Solo, with no Back or Close")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	_check(app.mode == "update_gate", "Android Back does nothing on the update screen")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	app._unhandled_key_input(escape)
	await _settle()
	_check(app.mode == "update_gate", "Escape does nothing on the update screen")
	if update != null:
		await _tap(viewport, update.get_global_rect().get_center())
		_check(opened == [UpdateGate.PLAY_LISTING_URL], "A tap on Update opens the Play listing once")
	if solo != null:
		await _tap(viewport, solo.get_global_rect().get_center())
		_check(app.mode == "journey", "Play Solo opens the solo chapters")
	# Solo play while gated.
	app._start_practice(0)
	await _settle()
	app._begin_turn()
	await _settle()
	_check(app.running and app.mode == "play", "A solo chapter starts while gated")
	app._show_home()
	app._service_update_gate()
	await _settle()
	_check(app.mode == "home", "After Play Solo, Home stays Home for this session")
	for item: Array in [[app.room_hub_flow.show_rooms, "Play with your friend"], [app._show_friends, "Friends"], [app._share_invite_from_home, "Invite"], [app._open_photo_transfer, "Photo transfer"], [app.relay_lobby_flow.open_lobby, "Rooms"]]:
		app._show_home()
		await _settle()
		await item[0].call()
		await _settle()
		_check(app.mode == "update_gate", "%s shows the update screen again" % item[1])
		app._play_solo_from_update_gate()
	# A tap on Home's own online button goes through the same check.
	app._show_home()
	await _settle()
	var together := _button(app, "Play with your friend")
	if together != null: await _tap(viewport, together.get_global_rect().get_center())
	_check(app.mode == "update_gate", "Tapping Play with your friend while gated shows the update screen")
	# Never drawn beneath a full-screen layer: Friends closes, a room keeps its own Back.
	app._play_solo_from_update_gate()
	var layer := FakeFriends.new()
	app.add_child(layer)
	app.friends_flow.screen = layer
	app.mode = "friends"
	await app.relay_lobby_flow.open_lobby()
	await _settle()
	var update_button := _button(app, Copy.UPDATE_GATE_UPDATE)
	_check(app.mode == "update_gate" and app.friends_flow.screen == null and not is_instance_valid(layer) and app.ui.visible and update_button != null, "From Friends, the update screen closes Friends and shows on top")
	app._play_solo_from_update_gate()
	var room := Node3D.new()
	app.add_child(room)
	app.relay_child = room
	var before_mode: String = app.mode
	await app.room_hub_flow.show_rooms()
	await _settle()
	_check(app.mode == before_mode and app.toast.visible and app.toast.text == Copy.UPDATE_REQUIRED_ERROR, "Inside a room the screen is not drawn underneath; a short line says why")
	room.free()
	app.relay_child = null
	app._show_home()
	app._service_update_gate()
	await _settle()
	_check(app.mode == "update_gate", "Back on Home, the update screen shows")
	# An invite link is dropped at once while gated, with no promise to open it later.
	app.toast.visible = false
	app.invite_link_pending = "LLLLLLLLLLLLLLLLLLLLLL"
	app.invite_link_expires_ms = Time.get_ticks_msec() + 60000
	app._service_invite_link()
	_check(app.invite_link_pending.is_empty() and not (app.toast.visible and app.toast.text == Copy.INVITE_LINK_WAITING) and app.mode == "update_gate", "An invite link while gated is dropped without saying it will open later")
	# Offline features keep working.
	for item: Array in [[app.settings_flow, "show_settings", "settings"], [app.replays_flow, "show_collection", "collection"], [app.settings_flow, "show_graphics_settings", "settings"], [app.settings_flow, "show_licenses", "settings"], [app.account_flow, "confirm_delete_identity", ""], [app, "_show_journey", "journey"]]:
		await item[0].call(item[1])
		await _settle()
		var reached: bool = app.mode != "update_gate" and (item[2] == "" or app.mode == item[2])
		_check(reached, "%s stays reachable while gated (mode %s)" % [item[1], app.mode])
	app.replays_flow.show_shared_replays()
	await _settle()
	_check(app.mode == "shared_replays", "Together replays already on the phone still open")
	app.replays_flow._refresh_shared_replay_rooms()
	await _settle()
	_check(app.toast.visible and app.toast.text == UpdateGate.notice("0.6.2") and app.api.calls.is_empty(), "A shared-replay download waits for the update and says so, sending nothing")
	# A notification or invite link while gated brings the screen back on Home.
	app._show_home()
	await _settle()
	app._request_update_gate()
	app._service_update_gate()
	await _settle()
	_check(app.mode == "update_gate", "An alert or link opened while gated shows the update screen on Home")
	# The screen waits for a finger on a Home button to lift.
	app._play_solo_from_update_gate()
	app._show_home()
	await _settle()
	var replays := _button(app, "Replays")
	if replays != null:
		var at := replays.get_global_rect().get_center()
		_touch(viewport, at, true)
		await _settle()
		app._request_update_gate()
		app._service_update_gate()
		await _settle()
		_check(app.mode == "home" and is_instance_valid(replays) and replays.is_inside_tree(), "While a finger is on a Home button the screen waits")
		_touch(viewport, at, false)
		await _settle()
		_check(app.mode == "collection", "That tap still opens Replays")
		app._show_home()
		app._service_update_gate()
		await _settle()
		_check(app.mode == "update_gate", "Then the update screen shows on Home")
	# A card already open on Home (What's new, a confirmation) is closed by the player first.
	app._play_solo_from_update_gate()
	app._show_home()
	await _settle()
	var modal := InGameModal.open(app.ui, "WhatsNewCard", "What's new") as InGameModal
	app._request_update_gate()
	app._service_update_gate()
	await _settle()
	_check(app.mode == "home" and is_instance_valid(modal), "An open card on Home holds the update screen back")
	modal.close()
	await _settle()
	app._service_update_gate()
	await _settle()
	_check(app.mode == "update_gate", "Once the card closes, the update screen shows")
	# Exploring the island holds it back too, until the player leaves Explore.
	app._play_solo_from_update_gate()
	app._show_home()
	await _settle()
	app.home_stage_view.set_exploring(true)
	await _settle()
	app._request_update_gate()
	app._service_update_gate()
	await _settle()
	_check(app.mode == "home" and app.home_stage_view.is_exploring(), "While the player explores the island the update screen waits")
	_check(app._online_gated() and app.mode == "update_gate", "...and online play is still gated: an online entry shows the update screen at once")
	app._play_solo_from_update_gate()
	app._show_home()
	await _settle()
	app.home_stage_view.set_exploring(true)
	app._request_update_gate()
	app._service_update_gate()
	await _settle()
	app.home_stage_view.set_exploring(false)
	app._service_update_gate()
	await _settle()
	_check(app.mode == "update_gate", "Leaving Explore shows the update screen")
	# A later check that says off, or fails, lifts the block.
	transport.replies = [_reply({"schema_version": 1, "gate": "off"})]
	await app._check_app_status()
	await _settle()
	_check(app.mode == "home" and not app._update_gate_active(), "A later off answer lifts the screen back to Home")
	await _gate(app, transport, _required())
	_check(app.mode == "update_gate", "Blocked again")
	transport.replies = [[]]
	await app._check_app_status()
	await _settle()
	_check(app.mode == "home" and not app._update_gate_active(), "A later failed check lifts it too")
	# The resume check runs only once six hours have passed.
	var clock := [Time.get_unix_time_from_system()]
	app.app_status.clock = func() -> float: return clock[0]
	app.app_status.checked_at = clock[0]
	var before := transport.calls.size()
	app.application_backgrounded = true
	app._resume_application()
	await _settle()
	_check(transport.calls.size() == before, "A quick resume does not ask again")
	clock[0] += AppStatus.RECHECK_SECONDS
	transport.replies = [_reply(_required())]
	app.application_backgrounded = true
	app._resume_application()
	await _settle()
	_check(transport.calls.size() == before + 1 and app._update_gate_active(), "A resume six hours later asks again")
	# No block survives into a new launch, and nothing about it is saved.
	viewport.queue_free()
	await _settle()
	await create_timer(0.15).timeout
	var saved := FileAccess.get_file_as_string(path)
	_check(not saved.contains("min_version") and not saved.contains("update_gate"), "Nothing about the gate is saved")
	var again := await _app(path)
	var next: Node = again[1]
	next._service_update_gate()
	await _settle()
	_check(next.mode == "home" and not next._update_gate_active(), "A new launch starts with no gate (no cached block)")
	(again[0] as Node).queue_free()
	await _settle()
	await create_timer(0.15).timeout
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	# A GitHub build updates from the latest release.
	ClientIdentity.override_purchase_mode = "test_store"
	var github := await _app(path)
	var tester: Node = github[1]
	opened.clear()
	await _gate(tester, transport, _required("0.6.2", "github"))
	tester._open_update_target()
	_check(tester.mode == "update_gate" and opened == [UpdateGate.GITHUB_LATEST_URL], "A GitHub tester build is sent to the latest release")
	(github[0] as Node).queue_free()
	await _settle()
	await create_timer(0.15).timeout
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	_reset_overrides()


func _ios() -> void:
	PlatformSupport.override_platform = PlatformSupport.IOS
	ClientIdentity.override_purchase_mode = "app_store"
	ClientIdentity.override_version = "0.9.0"
	var path := "user://update-gate-ios-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var made := await _app(path)
	var app: Node = made[1]
	var transport := Transport.new()
	app.config.erase("app_store_url")
	await _gate(app, transport, _required("1.0.0", "app_store"))
	_check(app.app_status.required() and not app._update_gate_active() and app.mode == "home", "An App Store build with no App Store link shows no gate")
	app.config["app_store_url"] = APP_STORE_LINK
	app._service_update_gate()
	await _settle()
	_check(app.mode == "update_gate", "With the link configured, the App Store build is gated")
	opened.clear()
	app._open_update_target()
	_check(opened == [APP_STORE_LINK], "Update opens the App Store page from the config, never Play or GitHub")
	await _gate(app, transport, _required("1.0.0", "play"))
	_check(not app._update_gate_active(), "An iOS build ignores a Play minimum")
	(made[0] as Node).queue_free()
	await _settle()
	await create_timer(0.15).timeout
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	_reset_overrides()


func _tap(target: Viewport, at: Vector2) -> void:
	_touch(target, at, true)
	_touch(target, at, false)
	await _settle()


## The engine's order inside a SubViewport: the emulated mouse, then the touch.
func _touch(target: Viewport, at: Vector2, pressed: bool) -> void:
	var mouse := InputEventMouseButton.new()
	mouse.position = at
	mouse.global_position = at
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse.pressed = pressed
	target.push_input(mouse, true)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = at
	touch.pressed = pressed
	target.push_input(touch, true)


func _settle() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
