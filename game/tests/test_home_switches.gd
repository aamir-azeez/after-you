extends SceneTree
## Home's rows that follow the server's public switches (services/server_switches.gd):
## - the last answer kept on disk shows the Duels row at once on a launch, with no
##   capabilities read (the launch makes no relay session at all);
## - the app-status answer the app already asks at launch brings the switches: on
##   shows the row, off hides it, and the answer is kept for the next launch;
## - a 429 from the public limiter, a timeout, an answer without switches or with
##   malformed ones changes nothing, and a 429 never reads as offline;
## - offline the row stays, greyed;
## - an authorized capabilities read writes the same switches;
## - a tap on a row shown from the switch alone reads the capabilities first and
##   opens only on them; an answer that says off hides the row instead;
## - the leaderboard surfaces outside a room follow the same switch.
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const ServerSwitches = preload("res://services/server_switches.gd")
const Connectivity = preload("res://services/connectivity.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const ClientIdentity = preload("res://services/client_identity.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const RelayOnline = preload("res://services/relay_online_session.gd")
const DuelsFlow = preload("res://presentation/duels/duels_flow.gd")
const MemoryStore = preload("res://tests/test_relay_online.gd").MemoryStore

const SERVER := "https://home-switches.example.test"
const ME := "ssssssssssssssssssssss"
const TOKEN := "synthetic-device-token"
const REQUEST := "probe-identity-read"
const SUCCESS := HTTPRequest.RESULT_SUCCESS

## The status transport: records each call and answers with the next reply.
class Transport extends RefCounted:
	var calls: Array = []
	var replies: Array = []
	func send(url: String, headers: PackedStringArray) -> Array:
		calls.append({"url": url, "headers": headers})
		return replies.pop_front() if not replies.is_empty() else []

## Answers capabilities reads from a queue and counts them.
class FakeApi:
	extends Node
	var base_url := SERVER
	var player_id := ME
	var device_token := TOKEN
	var replies: Array = []
	var capability_reads := 0
	func request_json(_method: int, path: String, _body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		if path == "/v2/capabilities": capability_reads += 1
		await Engine.get_main_loop().process_frame
		return replies.pop_front() if not replies.is_empty() else {"ok": false, "status": 0, "code": "connection_interrupted"}

## Counts lobby opens instead of drawing the lobby.
class CountingFlow extends DuelsFlow:
	var opens := 0
	func open() -> void: opens += 1

var checks := 0
var failures := 0
var _files: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _path(name: String) -> String:
	var path := "user://home-switches-%s-%s.json" % [name, Crypto.new().generate_random_bytes(6).hex_encode()]
	_files.append(path)
	return path

func _frames() -> void:
	for frame in range(4): await process_frame

func _reply(value: Variant, status: int = 200, result: int = SUCCESS) -> Array:
	return [result, status, PackedStringArray(), JSON.stringify(value).to_utf8_buffer()]

func _status(switches: Variant) -> Dictionary:
	var answer := {"schema_version": 1, "gate": "off"}
	if switches != null: answer["switches"] = switches
	return answer

func _run() -> void:
	var state: RefCounted = Connectivity.new()
	Connectivity.use_shared(state)
	state.force(true)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1560, 720)
	root.add_child(viewport)
	_test_store()
	await _test_last_known(viewport)
	await _test_fresh_launch(viewport, state)
	viewport.free()
	await process_frame
	Connectivity.use_shared(null)
	ServerSwitches.use_shared(null)
	PlatformSupport.override_platform = ""
	ClientIdentity.override_version = ""
	ClientIdentity.override_purchase_mode = ""
	await create_timer(0.15).timeout
	for path: String in _files:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU HOME SWITCHES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The store keeps well formed switches per server, and only those.
func _test_store() -> void:
	var path := _path("store")
	var store: RefCounted = ServerSwitches.new(path)
	_check(not store.on(SERVER, "duels"), "Nothing is on before any answer")
	var heard := [0]
	store.changed.connect(func() -> void: heard[0] += 1)
	store.note(SERVER + "/", {"duels": true, "leaderboards": "yes", "later": true})
	_check(store.on(SERVER, "duels") and not store.on(SERVER, "leaderboards") and heard[0] == 1, "A well typed switch is kept, keyed without the trailing slash; others are left out")
	store.note(SERVER, {"duels": true})
	_check(heard[0] == 1, "The same answer again changes nothing and writes nothing")
	store.note(SERVER, {"leaderboards": true})
	_check(store.on(SERVER, "duels") and store.on(SERVER, "leaderboards"), "A partial answer changes only what it names")
	store.note(SERVER, {})
	store.note("", {"duels": false})
	_check(store.on(SERVER, "duels"), "An empty answer or one with no server changes nothing")
	_check(not store.on("https://other.example.test", "duels"), "Another server knows nothing")
	var again: RefCounted = ServerSwitches.new(path)
	_check(again.on(SERVER, "duels") and again.on(SERVER, "leaderboards"), "A new launch reads them back")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"schema_version\": 1, \"servers\": []}")
	file.close()
	_check(not ServerSwitches.new(path).on(SERVER, "duels"), "An unreadable file reads as nothing known")

## A Main whose Home is built while its saved identity is still being read, as _ready does.
func _cold_home(viewport: SubViewport) -> Node:
	var app := Main.new()
	app.saves = Storage.new(_path("saves"))
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.base_url = SERVER
	app.identity_request = REQUEST
	app.identity_loading = true
	app.identity_read_state = Main.IdentityReadState.LOADING
	app._show_home()
	await _frames()
	return app

func _row(app: Node) -> bool:
	return is_instance_valid(app.home_menu_view) and app.home_menu_view.duels_button.visible

## Answers the app-status check the app already makes at launch and on a resume,
## as a Play build. The launch itself runs as a desktop build, which asks nothing,
## so no real request goes out and no check is still running here.
func _answer_status(app: Node, transport: Transport, reply: Array) -> void:
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	ClientIdentity.override_purchase_mode = "google_play"
	ClientIdentity.override_version = "0.7.9"
	app.app_status.configured = true
	app.app_status.base_url = SERVER
	app.app_status.transport = transport.send
	transport.replies = [reply]
	var before := transport.calls.size()
	await app._check_app_status()
	_check(transport.calls.size() == before + 1, "The check asked once")
	PlatformSupport.override_platform = ""
	ClientIdentity.override_version = ""
	ClientIdentity.override_purchase_mode = ""

## What an earlier launch kept shows at once, and the launch reads no capabilities.
func _test_last_known(viewport: SubViewport) -> void:
	var store: RefCounted = ServerSwitches.new(_path("kept"))
	store.note(SERVER, {"duels": true, "leaderboards": true})
	ServerSwitches.use_shared(store)
	var app := await _cold_home(viewport)
	_check(_row(app), "The Duels row shows at once from the last answer kept")
	_check(app._leaderboards_offered(), "So do the leaderboard surfaces")
	_check(app.relay_session == null, "The launch makes no relay session, so no capabilities read")
	var transport := Transport.new()
	for reply: Array in [_reply({"error": {"code": "rate_limited", "retryable": true}}, 429), _reply(_status(null), 0, HTTPRequest.RESULT_TIMEOUT), [],
		_reply(_status(null)), _reply(_status("off")), _reply(_status({"duels": "no"})), _reply({"schema_version": 2, "gate": "off", "switches": {"duels": false}})]:
		await _answer_status(app, transport, reply)
		_check(_row(app) and store.on(SERVER, "duels"), "An app-status answer without usable switches keeps the row: %s" % [reply.slice(0, 2)])
	# A 429 alone, while the app reads as offline: it is an answer, so the app is online again.
	Connectivity.shared().force(false)
	await _answer_status(app, transport, _reply({"error": {"code": "rate_limited", "retryable": true}}, 429))
	_check(Connectivity.shared().online() and _row(app), "A 429 reads as the server reached, never as offline, and keeps the row")
	_check(transport.calls.size() == 8 and transport.calls.all(func(call: Dictionary) -> bool: return "X-AfterYou-Switches: 1" in call.headers), "Every check asks for the switches")
	await _answer_status(app, transport, _reply(_status({"duels": false, "leaderboards": true})))
	_check(not _row(app) and not store.on(SERVER, "duels"), "An answer that says duels are off hides the row at once")
	await _answer_status(app, transport, _reply(_status({"duels": true, "leaderboards": true})))
	_check(_row(app), "An answer that says on shows it again")
	_check(app.relay_session == null, "Still no capabilities read")
	# Offline the row keeps its last known value, greyed.
	Connectivity.shared().force(false)
	_check(_row(app) and app.home_menu_view.duels_button.disabled and OfflineHold.held(app.home_menu_view.duels_button), "Offline the row stays, greyed")
	await _answer_status(app, transport, [])
	_check(_row(app), "An offline check keeps it")
	Connectivity.shared().force(true)
	_check(_row(app) and not app.home_menu_view.duels_button.disabled, "Online again it is a live row")
	app.queue_free()
	await _frames()

## No answer kept: the row shows once app-status says duels are on, and a tap reads
## the capabilities before it opens anything.
func _test_fresh_launch(viewport: SubViewport, state: RefCounted) -> void:
	var path := _path("fresh")
	var store: RefCounted = ServerSwitches.new(path)
	ServerSwitches.use_shared(store)
	var app := await _cold_home(viewport)
	_check(not _row(app) and not app._leaderboards_offered(), "A first launch knows no switch: no Duels row")
	var transport := Transport.new()
	await _answer_status(app, transport, _reply(_status({"duels": true, "leaderboards": true})))
	_check(_row(app), "The launch's app-status answer shows the row")
	_check(ServerSwitches.new(path).on(SERVER, "duels"), "And is kept for the next launch")
	_check(app.relay_session == null, "With no capabilities read")
	app._secret_completed(REQUEST, "get", {"found": true, "value": JSON.stringify({"player_id": ME, "device_token": TOKEN})})
	_check(app._relay_identity().ready, "The saved identity is ready")
	# A tap on the row: the capabilities are read first, once, and the lobby opens on them.
	var api := FakeApi.new()
	root.add_child(api)
	app.relay_session = RelayOnline.new(api, app._relay_identity, MemoryStore.new())
	var flow := CountingFlow.new(app)
	app.add_child(flow)
	app.duels_flow = flow
	var on := {"api_version": 2, "simulation_version": 2, "recording_version": 2, "mutations_enabled": true, "validation": "structural_client_replay_required", "chapters": [], "duels_version": 1, "leaderboards_version": 1, "hard_mode_version": 1}
	api.replies = [{"ok": false, "status": 503, "code": "server_unavailable"}]
	var toasts: Array = []
	var report := func(text: String) -> void: toasts.append(text)
	await app._show_duels(report)
	_check(api.capability_reads == 1 and flow.opens == 0 and toasts.size() == 1, "A failed read opens nothing and says why")
	_check(_row(app), "A failed read keeps the row")
	api.replies = [{"ok": true, "status": 200, "data": on}]
	await app._show_duels(report)
	_check(api.capability_reads == 2 and flow.opens == 1, "The tap reads the capabilities, then opens the lobby")
	_check(app.hard_together() and ServerSwitches.new(path).on(SERVER, "hard_mode"), "Together Hard is kept from the capabilities read for the next launch")
	await app._show_duels(report)
	_check(api.capability_reads == 2 and flow.opens == 2, "A later tap reuses this session's answer")
	# The server turned duels off: an authorized read says so and the row hides.
	var off := on.duplicate()
	off.erase("duels_version")
	off.erase("leaderboards_version")
	off.erase("hard_mode_version")
	api.replies = [{"ok": true, "status": 200, "data": off}]
	_check(await app.relay_session.load_capabilities(), "A capabilities answer without duels reads")
	_check(not store.on(SERVER, "duels") and not _row(app), "It writes the switch too, and the row hides at once")
	_check(not app._leaderboards_offered() and not app.hard_together(), "The leaderboard surfaces and together Hard follow it")
	# A newer public answer says on while this session's capabilities still say off:
	# the tap reads them again and opens only when they say on too.
	await _answer_status(app, transport, _reply(_status({"duels": true, "leaderboards": true})))
	_check(_row(app), "A newer public answer shows the row over a session that said off")
	api.replies = [{"ok": true, "status": 200, "data": on}]
	await app._show_duels(report)
	_check(api.capability_reads == 4 and flow.opens == 3, "The tap reads the stale capabilities again and opens the lobby")
	api.replies = [{"ok": true, "status": 200, "data": off}]
	_check(await app.relay_session.load_capabilities() and not _row(app), "Off again")
	await _answer_status(app, transport, _reply(_status({"duels": true, "leaderboards": true})))
	api.replies = [{"ok": true, "status": 200, "data": off}]
	await app._show_duels(report)
	_check(api.capability_reads == 6 and flow.opens == 3 and not _row(app), "A tap whose capabilities answer says off opens nothing and hides the row")
	_check(state.online(), "Nothing here read as offline")
	app.queue_free()
	api.queue_free()
	await _frames()
