extends SceneTree
## Home's Wardrobe row and Pollen chip follow what the phone knows, whatever
## order it learns it in (main.gd _refresh_home_pollen):
## - a cold start builds Home before the saved identity is read, and the
##   wardrobe file already says on, so no wardrobe change follows: the row and
##   the chip show once the identity is ready;
## - a return from a chapter builds a new Main whose wardrobe already follows
##   that player: Home's periodic refresh brings the row back;
## - a wardrobe change while another screen is up, with Home back without a
##   rebuild, is caught by the periodic refresh;
## - a failed or unreadable capabilities read keeps the row; only a read that
##   says the wardrobe is off hides it, and the next that says on shows it;
## - an idle refresh or a settled Pollen flush with nothing new keeps the same
##   chip (never a new one under a finger); a new balance makes a new one.
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const RelayOnline = preload("res://services/relay_online_session.gd")
const MemoryStore = preload("res://tests/test_relay_online.gd").MemoryStore

const SERVER := "https://home-pollen.example.test"
const ME := "pppppppppppppppppppppp"
const TOKEN := "synthetic-device-token"
const REQUEST := "probe-identity-read"

## Answers the capabilities read from a queue.
class FakeApi:
	extends Node
	var base_url := SERVER
	var player_id := ME
	var device_token := TOKEN
	var replies: Array = []
	func request_json(_method: int, _path: String, _body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		return replies.pop_front() if not replies.is_empty() else {"ok": false, "status": 0, "code": "connection_interrupted"}

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
	var path := "user://home-pollen-%s-%s.json" % [name, Crypto.new().generate_random_bytes(6).hex_encode()]
	_files.append(path)
	return path

func _frames() -> void:
	for frame in range(4): await process_frame

func _run() -> void:
	PollenSurfaces.set_shared_for_tests(true)
	var wardrobe: RefCounted = Wardrobe.new(_path("wardrobe"))
	var wallet: RefCounted = PollenWallet.new(_path("wallet"))
	Wardrobe.use_shared(wardrobe)
	PollenWallet.use_shared(wallet)
	# What an earlier run of the app kept: the wardrobe and Pollen on, and a balance.
	wardrobe.set_enabled(SERVER, ME, true)
	wallet.set_enabled(SERVER, ME, true)
	wallet.note_wallet(SERVER, ME, {"schema_version": 1, "balance": 40, "earned": 40, "bank": 0})
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1560, 720)
	root.add_child(viewport)
	var app := await _cold_home(viewport)
	await _test_cold_start(app)
	await _test_away_from_home(app, wardrobe)
	await _test_failed_reads(app, wardrobe)
	await _test_chip_kept(app, wallet)
	# A return from a chapter: the old Main leaves following this player, a new one reads the identity again.
	app.queue_free()
	await _frames()
	_check(wardrobe.active_look() is Dictionary and Wardrobe.scope_key(SERVER, ME) == wardrobe._active, "The wardrobe still follows the player once Main leaves")
	var again := await _cold_home(viewport)
	await _test_chapter_return(again)
	again.queue_free()
	await _frames()
	viewport.free()
	await process_frame
	Wardrobe.use_shared(null)
	PollenWallet.use_shared(null)
	PollenSurfaces.set_shared_for_tests(null)
	await create_timer(0.15).timeout
	for path: String in _files:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU HOME POLLEN REFRESH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A Main whose Home is built while its saved identity is still being read,
## as _ready does (_show_home, then _load_saved_identity).
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
	return is_instance_valid(app.home_menu_view) and app.home_menu_view.wardrobe_button.visible

func _chip(app: Node) -> Control:
	if not is_instance_valid(app.home_menu_view) or not app.home_menu_view.pollen_slot.visible or app.home_menu_view.pollen_slot.get_child_count() == 0: return null
	var chip := app.home_menu_view.pollen_slot.get_child(0) as Control
	return chip if not chip.is_queued_for_deletion() else null

## Home's periodic refresh, as _process runs it while Home shows.
func _tick(app: Node) -> void:
	app._service_home_keepsakes(0.2)

func _test_cold_start(app: Node) -> void:
	_check(not _row(app) and _chip(app) == null, "Home built before the identity is read shows no Wardrobe row and no Pollen chip")
	app._secret_completed(REQUEST, "get", {"found": true, "value": JSON.stringify({"player_id": ME, "device_token": TOKEN})})
	_check(app._relay_identity().ready, "The saved identity is ready")
	_check(_row(app), "The Wardrobe row shows as soon as the identity is ready, with no wardrobe change after it")
	_check(_chip(app) != null, "The Pollen chip shows as soon as the identity is ready, with no wallet read after it")

## A wardrobe change while another screen is up reaches Home's row once Home
## is back, even when Home is not built again.
func _test_away_from_home(app: Node, wardrobe: RefCounted) -> void:
	app.mode = "rooms"
	wardrobe.set_enabled(SERVER, ME, false)
	app.mode = "home"
	_tick(app)
	_check(not _row(app), "The server said off while Home was away: the row hides on Home's next refresh")
	app.mode = "rooms"
	wardrobe.set_enabled(SERVER, ME, true)
	app.mode = "home"
	_tick(app)
	_check(_row(app), "The server said on again while Home was away: the row shows on Home's next refresh")

## Only an answer that says the wardrobe is off hides the row.
func _test_failed_reads(app: Node, wardrobe: RefCounted) -> void:
	var api := FakeApi.new()
	root.add_child(api)
	var session: RefCounted = RelayOnline.new(api, app._relay_identity, MemoryStore.new())
	var on := {"api_version": 2, "simulation_version": 2, "recording_version": 2, "mutations_enabled": true, "validation": "structural_client_replay_required", "chapters": [], "pollen_version": 1, "pollen_wardrobe_version": 1}
	var off := on.duplicate()
	off.erase("pollen_wardrobe_version")
	api.replies = [{"ok": false, "status": 503, "code": "server_unavailable"}]
	_check(not await session.load_capabilities(), "A failed capabilities read fails")
	_tick(app)
	_check(wardrobe.enabled(SERVER, ME) and _row(app), "A failed capabilities read keeps the row")
	api.replies = [{"ok": true, "status": 200, "data": {"api_version": 1}}]
	_check(not await session.load_capabilities(), "An unreadable capabilities answer fails")
	_tick(app)
	_check(wardrobe.enabled(SERVER, ME) and _row(app), "An unreadable capabilities answer keeps the row")
	api.replies = [{"ok": true, "status": 200, "data": off}]
	_check(await session.load_capabilities(), "A capabilities answer without the wardrobe reads")
	_check(not _row(app), "The server says the wardrobe is off: the row hides at once")
	api.replies = [{"ok": true, "status": 200, "data": on}]
	_check(await session.load_capabilities(), "A capabilities answer with the wardrobe reads")
	_check(_row(app), "The server says the wardrobe is on again: the row shows at once")
	api.free()

## An idle refresh never replaces the chip; a new balance does.
func _test_chip_kept(app: Node, wallet: RefCounted) -> void:
	var chip := _chip(app)
	_check(chip != null, "The chip shows")
	_tick(app)
	app.pollen_client.settled.emit()
	await process_frame
	_check(chip != null and _chip(app) == chip, "An idle refresh and a flush with nothing new keep the same chip")
	wallet.note_wallet(SERVER, ME, {"schema_version": 1, "balance": 45, "earned": 45, "bank": 0})
	app.pollen_client.settled.emit()
	await process_frame
	_check(_chip(app) != null and _chip(app) != chip, "A new balance makes a new chip")

## The new Main's Home was built before its identity was ready; nothing in the
## wardrobe changes when it is, and Home's periodic refresh brings the row back.
func _test_chapter_return(app: Node) -> void:
	_check(not _row(app), "The new Home is built before the identity is read")
	app.api.player_id = ME
	app.api.device_token = TOKEN
	app.identity_loading = false
	app.identity_read_state = Main.IdentityReadState.LOADED
	_tick(app)
	_check(_row(app) and _chip(app) != null, "Home's periodic refresh shows the row and the chip once the identity is ready")
