extends SceneTree
## "Use my Play Games name" through the real Main, the real PlatformGames service and the real
## native provider, with only the plugin and the server faked. The plugin answers like Play
## Games does on a phone: the quiet check signs in after a moment, or answers "signed out"
## when Play Games wants its own sign-in sheet. Covered orders:
## - the prompt opens before the service learns the server's offer, then the quiet sign-in lands;
## - a tap on the row while the quiet check is still running waits, then fills the name;
## - the quiet check answers signed out: the row is still offered, and a tap shows the sheet once;
## - the sheet is cancelled: the card says so and nothing changes; another tap asks again;
## - a fresh install (no friend code yet): the probe, the quiet sign-in, then the prompt;
## - the server's offer could not be read at launch: opening the prompt asks again;
## - another account signs in after the name was read: that name is dropped;
## - no Play Games on the phone, the server offering none, or a build Play Games refuses: no row;
## - the Friends chip's Change shows the same row from the same source.
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
const Service = preload("res://services/platform_games/platform_games.gd")
const NativeProvider = preload("res://services/platform_games/native_games_provider.gd")
const GamesProvider = preload("res://services/platform_games/games_provider.gd")
const DisplayNames = preload("res://services/display_names.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Connectivity = preload("res://services/connectivity.gd")

# Synthetic ids and keys only.
const ME := "MMMMMMMMMMMMMMMMMMMMMM"
const BASE := "https://synthetic.invalid"
const CLIENT := "123456789012-servclientabcd.apps.googleusercontent.com"

var checks := 0
var failures := 0
var _paths: Array[String] = []
var app: Node
var api: FakeApi
var page: Control

## The plugin as Play Games answers it. outcome: "in", "out" or an error code.
class FakeNative extends Node:
	signal games_result(id: String, operation: String, payload: String)
	signal games_error(id: String, operation: String, code: String)
	signal games_account_changed(payload: String)
	var present := true
	var quiet := "in"
	var sheet := "in"
	var delay := 0.0
	var signed := false
	var key := "a".repeat(64)
	var gamer := "RobinPlays"
	var calls: Array = []
	func games_available() -> bool: return present
	func games_status(id: String) -> void:
		calls.append("status")
		_answer(id, "status", quiet)
	func games_sign_in(id: String) -> void:
		calls.append("sign_in")
		_answer(id, "sign_in", sheet)
	func games_player_name(id: String) -> void:
		calls.append("player_name")
		await get_tree().process_frame
		if signed: games_result.emit(id, "player_name", JSON.stringify({"name": gamer}))
		else: games_error.emit(id, "player_name", "signed_out")
	func games_credential(_client: String, id: String) -> void:
		calls.append("credential")
		await get_tree().process_frame
		games_error.emit(id, "credential", "offline")
	func _answer(id: String, operation: String, outcome: String) -> void:
		if delay > 0.0: await get_tree().create_timer(delay).timeout
		else: await get_tree().process_frame
		match outcome:
			"in":
				signed = true
				games_result.emit(id, operation, JSON.stringify({"signed_in": true, "player_key": key}))
			"out":
				signed = false
				games_result.emit(id, operation, JSON.stringify({"signed_in": false}))
			_: games_error.emit(id, operation, outcome)
	func count(operation: String) -> int:
		return calls.count(operation)

## Main's api: the capability read and the restore probe; everything else is offline.
class FakeApi extends Node:
	var player_id := ""
	var device_token := ""
	var base_url := "https://synthetic.invalid"
	var busy := false
	## "on", "off" or "offline" for both the capability read and the probe.
	var offer := "on"
	## Seconds each answer takes.
	var wait := 0.0
	var calls: Array = []
	func configured() -> bool: return true
	func request_json(_method: int, path: String, _body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		calls.append(path)
		await _answer_later()
		if path == "/v1/platform/restore":
			match offer:
				"on": return {"ok": false, "status": 400, "code": "invalid_platform_request", "data": {}}
				"off": return {"ok": false, "status": 401, "code": "unauthorized", "data": {}}
		return {"ok": false, "status": 0, "code": "connection_interrupted", "data": {}, "error": ""}
	func request_json_with_headers(_method: int, path: String, _body: Dictionary, _extra: PackedStringArray, _still: Callable = Callable()) -> Dictionary:
		calls.append(path)
		await _answer_later()
		if path == "/v2/capabilities" and offer != "offline":
			var data := {"api_version": 2}
			if offer == "on": data.merge({"play_games_version": 1, "play_games_web_client_id": "123456789012-servclientabcd.apps.googleusercontent.com"})
			return {"ok": true, "status": 200, "data": data}
		return {"ok": false, "status": 0, "code": "connection_interrupted", "data": {}, "error": ""}
	func _answer_later() -> void:
		if wait > 0.0: await get_tree().create_timer(wait).timeout
		else: await get_tree().process_frame

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _path(label: String) -> String:
	var path := "user://test-platform-name-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

func _frames(count: int) -> void:
	for _i in count: await process_frame

## Waits up to `seconds` for `done` to hold.
func _until(done: Callable, seconds: float = 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not done.call() and Time.get_ticks_msec() < deadline: await process_frame
	return done.call()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	Connectivity.shared().force(true)
	app = Main.new()
	app.saves = Save.new(_path("save"))
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	app.saves.flush()
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	api = FakeApi.new()
	app.add_child(api)
	app.api = api
	page = Control.new()
	page.size = Vector2(1280, 720)
	viewport.add_child(page)
	await _frames(2)
	await _prompt_before_offer()
	await _quiet_signed_out()
	await _sheet_cancelled()
	await _fresh_install()
	await _offer_read_failed()
	await _another_account()
	await _no_platform("absent")
	await _no_platform("server_off")
	await _no_platform("not_configured")
	await _edit_same_source()
	_service_node().queue_free()
	app.queue_free()
	await _frames(3)
	DisplayNames.use_shared(null)
	Connectivity.use_shared(null)
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU PLATFORM NAME CHOICE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

# --- Setup per order --------------------------------------------------------

func _service_node() -> Node:
	return root.get_node_or_null("PlatformGames")

## A fresh service at /root/PlatformGames (where Main finds it) with this plugin, handed to Main.
func _fresh(native: FakeNative, identity: String) -> Node:
	app.platform_games_flow.detach()
	var old := _service_node()
	if old != null:
		root.remove_child(old)
		old.free()
	var service: Node = Service.new()
	service.name = "PlatformGames"
	service.configure(NativeProvider.new(native, GamesProvider.PLAY_GAMES, self), _path("state"))
	root.add_child(service)
	app.platform_games_flow.service = null
	_identity(identity)
	app.platform_games_flow.attach()
	var names: RefCounted = DisplayNames.new(_path("names"))
	DisplayNames.use_shared(names)
	names.set_enabled(BASE, ME, true)
	return service

## "missing": a fresh install with no friend code; "ready": this phone has one.
func _identity(state: String) -> void:
	if state == "ready":
		api.player_id = ME
		api.device_token = "synthetic-device-token"
		app.identity_data = {"player_id": ME, "device_token": api.device_token}
		app.identity_read_state = Main.IdentityReadState.LOADED
	else:
		api.player_id = ""
		api.device_token = ""
		app.identity_data = {}
		app.identity_read_state = Main.IdentityReadState.MISSING

func _native() -> FakeNative:
	var native := FakeNative.new()
	root.add_child(native)
	return native

## The first-run prompt over the page, as Friends opens it.
func _ask() -> Node:
	_check(app.display_name_flow.maybe_ask(page), "The first-run prompt opens")
	await _frames(2)
	var modal: Control = page.find_child("DisplayNameModal", true, false)
	return modal.find_child("DisplayNamePrompt", true, false) if modal != null else null

func _close(prompt: Node, native: FakeNative) -> void:
	if prompt != null and is_instance_valid(prompt.modal): prompt.modal.close()
	await _frames(3)
	native.queue_free()

static func _row_label(prompt: Node) -> String:
	if prompt.platform_row == null: return ""
	return (prompt.platform_row.find_child("Title", true, false) as Label).text

static func _note(prompt: Node) -> String:
	return prompt._platform_note.text if prompt._platform_note != null else ""

# --- Orders -----------------------------------------------------------------

## A phone with a friend code: the prompt opens before the service read the server's offer
## (the launch's read has not happened yet, so opening the card starts it), and the player taps
## the row while the quiet check is still running.
func _prompt_before_offer() -> void:
	var native := _native()
	native.delay = 0.6
	api.wait = 0.4
	var service := _fresh(native, "ready")
	var prompt := await _ask()
	_check(prompt != null and prompt.platform_row == null, "Before the server's offer is known: no Play Games row")
	_check(native.calls.is_empty(), "and Play Games is not asked anything yet")
	_check(service._running and api.calls.has("/v2/capabilities"), "Opening the card started the offer read")
	_check(await _until(func() -> bool: return prompt.platform_row != null), "The offer arrives while the card is open: the row appears")
	api.wait = 0.0
	_check(_row_label(prompt) == PlayerCopy.DISPLAY_NAME_PLAY_GAMES, "labelled Use my Play Games name: " + _row_label(prompt))
	_check(not service.signed_in(), "while the quiet sign-in is still running")
	prompt.platform_row.pressed.emit()
	await _frames(1)
	_check(_note(prompt) == PlayerCopy.DISPLAY_NAME_PLATFORM_READING and prompt.choice() != "platform", "A tap during the check says it is getting the name")
	_check(await _until(func() -> bool: return prompt.choice() == "platform"), "then the name fills in once the sign-in lands")
	_check(prompt.tag.text == "RobinPlays" and _note(prompt) == "RobinPlays", "on the tag and under the row")
	_check(native.count("status") == 1 and native.count("sign_in") == 0 and native.count("player_name") == 1, "One quiet check, no sign-in sheet, one name read: " + str(native.calls))
	await _close(prompt, native)

## Play Games answers the quiet check with "signed out" (its sheet is needed). The row is still
## offered, and a tap shows the sheet once and fills the name.
func _quiet_signed_out() -> void:
	var native := _native()
	native.quiet = "out"
	var service := _fresh(native, "ready")
	await service.start()
	_check(service.offered() and not service.signed_in(), "The quiet check answered signed out")
	var prompt := await _ask()
	_check(prompt.platform_row != null and _row_label(prompt) == PlayerCopy.DISPLAY_NAME_PLAY_GAMES, "Signed out but offered: the first prompt still shows Use my Play Games name")
	prompt.platform_row.pressed.emit()
	_check(await _until(func() -> bool: return prompt.choice() == "platform"), "A tap signs in with the sheet and fills the name")
	_check(native.count("sign_in") == 1 and native.count("player_name") == 1 and prompt.tag.text == "RobinPlays", "The sheet shows once and the name is read once: " + str(native.calls))
	_check(service.signed_in(), "and the service is signed in for everything else too")
	await _close(prompt, native)

## The player closes the sheet: the card says the name did not come, nothing else changes, and
## another tap asks again.
func _sheet_cancelled() -> void:
	var native := _native()
	native.quiet = "out"
	native.sheet = "cancelled"
	var service := _fresh(native, "ready")
	await service.start()
	var prompt := await _ask()
	prompt.field.text = "Robin"
	prompt._typed("Robin")
	prompt.platform_row.pressed.emit()
	_check(await _until(func() -> bool: return _note(prompt) == PlayerCopy.DISPLAY_NAME_PLATFORM_FAILED), "A cancelled sheet says the name did not come through")
	_check(prompt.choice() == "typed" and prompt.tag.text == "Robin" and prompt.platform_row != null, "and keeps the typed name and the row")
	native.sheet = "in"
	prompt.platform_row.pressed.emit()
	_check(await _until(func() -> bool: return prompt.choice() == "platform"), "Another tap asks again and fills the name")
	_check(native.count("sign_in") == 2, "one sheet per tap: " + str(native.calls))
	await _close(prompt, native)

## A fresh install: the restore probe says the server offers Play Games, the quiet check signs
## in, and the first friend code is made before the prompt opens.
func _fresh_install() -> void:
	var native := _native()
	var service := _fresh(native, "missing")
	await service.start()
	_check(service.offered() and service.signed_in(), "No friend code yet: the probe and the quiet sign-in still run")
	_check(api.calls.has("/v1/platform/restore"), "through the restore probe")
	_identity("ready")
	var prompt := await _ask()
	_check(prompt.platform_row != null, "The first prompt after the friend code is made shows the row")
	prompt.platform_row.pressed.emit()
	_check(await _until(func() -> bool: return prompt.choice() == "platform" and prompt.tag.text == "RobinPlays"), "and fills the name")
	await _close(prompt, native)

## The server's offer could not be read at launch (offline): opening the prompt asks again,
## and the row appears without reopening the card.
func _offer_read_failed() -> void:
	var native := _native()
	api.offer = "offline"
	var service := _fresh(native, "ready")
	await service.start()
	_check(not service.offered() and native.calls.is_empty(), "A failed offer read leaves Play Games untouched")
	api.offer = "on"
	var prompt := await _ask()
	_check(await _until(func() -> bool: return prompt.platform_row != null), "Opening the prompt reads the offer again and the row appears")
	_check(await _until(func() -> bool: return service.signed_in()), "and the quiet check runs")
	await _close(prompt, native)

## Another Play Games account after the name was read: that name goes, the row stays.
func _another_account() -> void:
	var native := _native()
	var service := _fresh(native, "ready")
	await service.start()
	var prompt := await _ask()
	prompt.platform_row.pressed.emit()
	await _until(func() -> bool: return prompt.choice() == "platform")
	native.key = "b".repeat(64)
	native.gamer = "OtherPlays"
	native.games_account_changed.emit("{}")
	await _frames(2)
	_check(prompt.choice() != "platform" and prompt._platform_name.is_empty(), "Another account: the old account's name is dropped")
	_check(await _until(func() -> bool: return service.signed_in() and prompt.platform_row != null), "and the row stays for the new account")
	prompt.platform_row.pressed.emit()
	_check(await _until(func() -> bool: return prompt.choice() == "platform" and prompt.tag.text == "OtherPlays"), "A tap reads the new account's name")
	await _close(prompt, native)

## No Play Games on this phone, the server offering none, or a build Play Games refuses.
func _no_platform(why: String) -> void:
	var native := _native()
	match why:
		"absent": native.present = false
		"server_off": api.offer = "off"
		"not_configured": native.quiet = "not_configured"
	var service := _fresh(native, "ready")
	await service.start()
	var prompt := await _ask()
	await _frames(3)
	_check(prompt.platform_row == null, "No row (%s)" % why)
	if why != "not_configured": _check(not native.calls.has("status"), "and Play Games is never asked (%s)" % why)
	api.offer = "on"
	await _close(prompt, native)

## The Friends chip's Change opens the same card from the same source.
func _edit_same_source() -> void:
	var native := _native()
	native.quiet = "out"
	var service := _fresh(native, "ready")
	await service.start()
	app.display_name_flow.edit(page)
	await _frames(2)
	var modal: Control = page.find_child("DisplayNameModal", true, false)
	var prompt: Node = modal.find_child("DisplayNamePrompt", true, false) if modal != null else null
	_check(prompt != null and prompt.platform_row != null and _row_label(prompt) == PlayerCopy.DISPLAY_NAME_PLAY_GAMES, "Change shows the same row")
	if prompt != null:
		prompt.platform_row.pressed.emit()
		_check(await _until(func() -> bool: return prompt.choice() == "platform"), "and fills the name the same way")
	await _close(prompt, native)
