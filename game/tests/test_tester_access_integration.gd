extends SceneTree

const Main = preload("res://main.gd")
const Preview = preload("res://lighthouse_preview.gd")
const Purchases = preload("res://services/purchases.gd")
const Storage = preload("res://services/local_save.gd")
const Journal = preload("res://services/lighthouse_journey.gd")
const OWNER := "TTTTTTTTTTTTTTTTTTTTTT"
const TOKEN := "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"
var checks := 0
var failures := 0
var paths: Array[String] = []

class Access extends Node:
	var grant := true
	var loaded := false
	var reads := 0
	var redemptions := 0
	var restores := 0
	var erased := 0
	var erase_ok := true
	var account :=  "TTTTTTTTTTTTTTTTTTTTTT"
	var token := "D".repeat(43)
	var bound := ""
	var pause_read := false
	var read_failure := false
	func load_cached(base: String, expected: String = "") -> Dictionary:
		reads += 1
		await get_tree().process_frame
		while pause_read: await get_tree().process_frame
		if read_failure: return {"ok": false, "granted": false, "durable": false}
		loaded = expected.is_empty() or expected == account
		bound = JSON.stringify([base, account, token])
		return {"ok": true, "granted": loaded and grant, "durable": true}
	func active(base: String, who: String, credential: String) -> bool:
		return loaded and grant and bound == JSON.stringify([base, who, credential])
	func cache_loaded_for(base: String, who: String, credential: String) -> bool:
		return loaded and bound == JSON.stringify([base, who, credential])
	func invalidate() -> void: loaded = false
	func erase_binding(_base: String, _owner: String, _credential: String) -> Dictionary:
		erased += 1
		loaded = false
		return {"ok": erase_ok, "granted": false, "durable": erase_ok}
	func redeem(base: String, who: String, _code: String) -> Dictionary:
		redemptions += 1
		grant = true
		return await load_cached(base, who)
	func restore(base: String, who: String) -> Dictionary:
		restores += 1
		grant = true
		return await load_cached(base, who)

class Store extends Purchases:
	var configure_calls := 0
	var fetch_calls := 0
	var refresh_calls := 0
	var restore_calls := 0
	func _connect_native() -> bool: return true
	func configure_store(_key: String, _player: String, _mode: String) -> String:
		configure_calls += 1
		return "configure-%d" % configure_calls
	func fetch_offerings() -> String:
		fetch_calls += 1
		return "offer-%d" % fetch_calls
	func refresh_customer_info() -> String:
		refresh_calls += 1
		return "refresh-%d" % refresh_calls
	func restore() -> String:
		restore_calls += 1
		return "restore-%d" % restore_calls

class MainProbe extends Main:
	var opened := ""
	func _open_chapter_preview(scene: String) -> void: opened = scene

class TrackedJournal extends Journal:
	var loads := 0
	func _init(path: String) -> void: super(path)
	func load_data() -> void:
		loads += 1
		super.load_data()

class PhotoCleanup extends Node:
	func clear_owner(_who: String) -> Dictionary: return {"ok": true}

class CacheCleanup extends RefCounted:
	func erase_owner(_who: String) -> Dictionary: return {"ok": true}

class CleanupApi extends Node:
	var player_id := "TTTTTTTTTTTTTTTTTTTTTT"
	var device_token := "D".repeat(43)
	var base_url := "https://test.example.invalid"
	var busy := false
	var calls := 0
	var local_done: Callable
	var ack_after_local := false
	func request_json(_method: int, _path: String, _body: Dictionary = {}) -> Dictionary:
		calls += 1
		ack_after_local = local_done.call()
		await get_tree().process_frame
		return {"ok": true, "data": {"schema_version": 1, "acknowledged": true}}

class CleanupSecrets extends Node:
	signal completed(id: String, operation: String, payload: Dictionary)
	signal failed(id: String, operation: String, code: String)
	var writes: Array = []
	var removed: Array = []
	func put_secret(key: String, value: String) -> String:
		writes.append([key, value])
		var id := "write-%d" % writes.size()
		completed.emit.call_deferred(id, "put", {"stored": true})
		return id
	func remove_secret(key: String) -> String:
		removed.append(key)
		var id := "remove-%d" % removed.size()
		completed.emit.call_deferred(id, "remove", {"removed": true})
		return id

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _main_flow()
	await _lighthouse_flow()
	await _cleanup_flow()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	await create_timer(0.05).timeout
	print("TESTER ACCESS INTEGRATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _main_flow() -> void:
	var cache := Access.new()
	var scene := MainProbe.new()
	var path := _path("main")
	scene.saves = Storage.new(path)
	scene.tester_access_factory = func(): return cache
	root.add_child(scene)
	scene.set_physics_process(false)
	scene.world.set_process(false)
	scene.purchases.queue_free()
	var store := Store.new()
	scene.purchases = store
	scene.add_child(store)
	scene.config.revenuecat_public_key = "test_public_configuration"
	scene.identity_request = "initial-identity"
	scene.identity_loading = true
	scene._secret_completed("initial-identity", "get", {"found": true, "value": JSON.stringify({"player_id": OWNER, "device_token": TOKEN})})
	_check(scene.tester_loading and store.configure_calls == 0, "Saved-identity startup waits for local tester cache before configuring RevenueCat")
	await _settle_main(scene)
	_check(scene._tester_active() and not scene.store_configured and store.configure_calls == 0 and store.refresh_calls == 0, "Valid cached tester startup grants separate access without any RevenueCat request")
	_check(cache.redemptions == 0 and cache.restores == 0 and cache.reads == 1 and not store.has_entitlement(), "Cold cache causes no server grant request and does not manufacture a paid entitlement")
	for width: int in [1280, 1600]:
		root.size = Vector2i(width, 720)
		for status: String in ["", "Tester access could not be saved or confirmed. Check the code and connection, or use Restore tester access to check an earlier redemption."]:
			scene._tester_form(status)
			await process_frame
			await process_frame
			var back := _button(scene, "Back to settings")
			_check(back != null and back.get_global_rect().position.y >= 0 and back.get_global_rect().end.y <= 720, "Tester entry/error card keeps Back reachable at %d x720" % width)
		scene._show_tester_active()
		await process_frame
		await process_frame
		var active_back := _button(scene, "Back to settings")
		_check(active_back != null and active_back.get_global_rect().end.y <= 720, "Active tester card stays within %d x720" % width)
	root.size = Vector2i(1280, 720)
	scene._show_journey()
	scene._open_lighthouse_preview()
	await process_frame
	_check(scene.opened == "res://lighthouse_preview.tscn" and store.refresh_calls == 0, "Actual Home Lighthouse action bypasses store readiness for a cached tester")
	scene._show_earlier_islands()
	_check(_button_containing(scene, "Full Journey") == null, "Earlier-island chooser removes premium locks for tester access")
	scene._start_practice(3)
	await process_frame
	_check(scene.level_index == 3 and scene.mode != "paywall", "A premium earlier island opens through the actual tester gate")
	scene._show_paywall()
	await process_frame
	_check(scene.mode == "tester_access" and _text(scene, "Tester access active"), "A cached tester sees distinct active access instead of an unnecessary purchase offer")
	scene._show_settings()
	await process_frame
	await process_frame
	var entry := _button(scene, "Tester code")
	_check(entry != null and entry.get_global_rect().end.y <= 720, "Settings Tester code is reachable at the supported small viewport")
	if entry != null: entry.pressed.emit()
	await process_frame
	await process_frame
	_check(_text(scene, "Tester access active"), "Visible Settings action opens the cached active card")
	scene.application_backgrounded = true
	scene._resume_application()
	await process_frame
	_check(store.configure_calls == 0 and store.refresh_calls == 0 and cache.redemptions == 0 and cache.restores == 0, "Foreground resume performs no grant or purchase request for cached tester access")
	store.customer_info = {"schema_version": 1, "entitlements": {}}
	scene._customer_info_changed(store.customer_info)
	_check(scene._full_journey_access() and not store.has_entitlement(), "A missing SDK entitlement cannot revoke the separate tester grant")
	cache.loaded = false
	cache.read_failure = true
	scene.tester_checked_context = ""
	await scene._load_cached_tester()
	_check(scene.tester_checked_context.is_empty(), "A transient secure cache read failure is not memoized as a completed access check")
	cache.read_failure = false
	await scene._load_cached_tester()
	_check(scene._tester_active(), "The next entry retries a failed local cache read and restores offline access")
	cache.pause_read = true
	scene.tester_checked_context = ""
	scene.opened = ""
	scene._show_journey()
	scene._open_lighthouse_preview()
	scene._show_settings()
	cache.pause_read = false
	await _settle_main(scene)
	_check(scene.opened.is_empty() and scene.mode == "settings", "Back or another view cancels a deferred Lighthouse entry intent")
	cache.pause_read = true
	scene.tester_checked_context = ""
	scene._show_earlier_islands()
	scene._start_practice(4)
	scene.application_backgrounded = true
	cache.pause_read = false
	await _settle_main(scene)
	_check(scene.level_index == 3 and not scene.running, "A deferred premium island action cannot start play after backgrounding")
	scene.application_backgrounded = false
	scene._show_paywall(true)
	await process_frame
	await process_frame
	_check(scene.mode == "paywall" and store.configure_calls == 1, "Explicit Store purchases still reaches the normal RevenueCat path")
	scene._invalidate_relay_identity()
	_check(not scene._tester_active() and cache.erased == 0, "Identity invalidation clears live tester authority without prematurely erasing a grant before server acknowledgement")
	scene.api.device_token = "N".repeat(43)
	scene.tester_checked_context = ""
	_check(not scene._tester_active(), "A recovered credential cannot reuse the old active binding")
	# A fresh ungranted identity uses explicit redemption/restore controls only.
	cache.token = scene.api.device_token
	cache.grant = false
	await scene._load_cached_tester()
	scene._show_tester_access()
	await process_frame
	await process_frame
	var code_field := scene.find_child("TesterCode", true, false) as LineEdit
	_check(code_field != null and code_field.secret and cache.redemptions == 0, "The tester form masks the code and does not redeem automatically")
	if code_field != null:
		code_field.text = "synthetic-code-only"
		var redeem := _button(scene, "Redeem tester code")
		redeem.pressed.emit()
		_check(code_field.text.is_empty(), "Submitting removes the code from the field immediately")
		await process_frame
		await process_frame
		_check(cache.redemptions == 1 and _text(scene, "Tester access active") and not store.has_entitlement(), "One explicit redemption opens tester access without changing purchase state")
	scene._tester_form()
	var restore := _button(scene, "Restore tester access")
	restore.pressed.emit()
	await process_frame
	await process_frame
	_check(cache.restores == 1 and _text(scene, "Tester access active"), "Explicit Restore tester access uses its own authenticated grant path")
	cache.pause_read = true
	scene._tester_form()
	scene._restore_tester_access()
	scene._show_settings()
	scene._show_tester_access()
	cache.pause_read = false
	await process_frame
	await process_frame
	await process_frame
	_check(not scene.tester_action_pending and _text(scene, "Tester access active"), "Back and reopen during a pending grant resolves to current active UI instead of permanently disabled buttons")
	cache.pause_read = true
	scene._tester_form()
	scene._restore_tester_access()
	scene.application_backgrounded = true
	cache.pause_read = false
	await process_frame
	await process_frame
	scene._resume_application()
	await process_frame
	_check(_text(scene, "Tester access active") and not scene.tester_action_pending, "A background grant completion refreshes the current tester screen on resume")
	root.remove_child(scene)
	scene.queue_free()
	await process_frame

func _lighthouse_flow() -> void:
	var path := _path("lighthouse")
	var cache := Access.new()
	var store := Store.new()
	var tracked := TrackedJournal.new(path)
	var scene := Preview.new()
	scene.journey = tracked
	scene.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	scene.tester_access_factory = func(): return cache
	scene.purchase_service_factory = func(): return store
	root.add_child(scene)
	scene.backgrounded = false
	scene.set_physics_process(false)
	scene.world.set_process(false)
	_check(scene._tester_checking and tracked.loads == 0 and scene._purchases == null, "Direct Lighthouse launch reads local tester access before creating the purchase service or loading saves")
	var deadline := Time.get_ticks_msec() + 30000
	while scene.mode in ["access_check", "loading"] and Time.get_ticks_msec() < deadline: await process_frame
	_check(scene.mode == "ready" and scene._tester_admitted and tracked.loads == 1, "Cold direct Lighthouse tester entry admits the actual saved journey")
	_check(scene._purchases == null and store.refresh_calls == 0 and cache.redemptions == 0 and cache.restores == 0, "Cached Lighthouse admission makes zero RevenueCat or grant HTTP requests")
	if scene.mode == "ready":
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/first-two-v3.json"))
		scene._start_replay(fixture.pairs[0].b, fixture.pairs[0].a, [])
		for i in range(3): scene._physics_process(1.0 / 30.0)
		var cursor: int = scene.replay_cursor
		scene._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		scene._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		await process_frame
		await process_frame
		_check(scene.mode == "paused" and not scene.running and scene.replay_cursor == cursor and scene._tester_admitted, "Lighthouse resume revalidates local binding and preserves the paused replay cursor")
		_check(store.refresh_calls == 0 and cache.restores == 0 and cache.redemptions == 0, "Lighthouse foreground resume never checks RevenueCat or the server for cached access")
		scene._access_changed({"schema_version": 1, "entitlements": {}})
		scene._access_failed("old", "get_customer_info", "offline", "", false)
		_check(scene._tester_admitted and scene._access_granted, "Late SDK loss/failure cannot revoke admitted tester access")
		cache.grant = false
		scene._check_access()
		await process_frame
		await process_frame
		_check(not scene._tester_admitted and not scene._access_granted and store.refresh_calls == 1, "A missing local tester binding falls back to the ordinary purchase admission rather than granting access")
	root.remove_child(scene)
	scene.queue_free()
	if store.get_parent() == null: store.free()
	await process_frame

func _cleanup_flow() -> void:
	var cache := Access.new()
	var app := MainProbe.new()
	app.saves = Storage.new(_path("cleanup"))
	app.tester_access_factory = func(): return cache
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.soundscape.set_backgrounded(true)
	var api := CleanupApi.new()
	app.add_child(api)
	app.api = api
	var secrets := CleanupSecrets.new()
	app.add_child(secrets)
	app.secrets = secrets
	secrets.completed.connect(app._secret_completed)
	secrets.failed.connect(app._secret_failed)
	app.identity_data = {"player_id": OWNER, "device_token": TOKEN}
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_loading = false
	var photos := PhotoCleanup.new()
	app.add_child(photos)
	app.deletion_photo_cleanup = photos
	app.deletion_cache_cleanup = CacheCleanup.new()
	app.deleted_identity_owner = OWNER
	cache.erase_ok = false
	await app._clear_deleted_identity()
	_check(api.calls == 0 and secrets.removed.is_empty() and not app.identity_data.is_empty(), "Failed tester-secret cleanup prevents deletion completion ACK and retains old credentials")
	cache.erase_ok = true
	api.local_done = func(): return cache.erased >= 2 and secrets.removed.is_empty()
	await app._clear_deleted_identity()
	_check(api.calls == 1 and api.ack_after_local, "Successful tester-secret removal precedes the server local-cleanup ACK")
	_check(secrets.removed == ["player_identity"] and app.identity_data.is_empty(), "Identity credentials are forgotten only after tester cleanup and the confirmed server ACK")
	api.local_done = Callable()
	# The same cleanup rule applies only after an acknowledged credential recovery.
	app.identity_restart_required = true
	api.player_id = OWNER
	api.device_token = TOKEN
	app.identity_data = {"player_id": OWNER, "device_token": "N".repeat(43), "recovery_code": "R".repeat(43)}
	cache.erase_ok = false
	await app._persist_recovered_identity()
	_check(secrets.writes.is_empty(), "Failed old tester binding cleanup holds recovered-identity persistence for an explicit retry")
	cache.erase_ok = true
	await app._persist_recovered_identity()
	_check(secrets.writes.size() == 1 and secrets.writes[0][0] == "player_identity" and secrets.removed[-1] == "recovery_pending", "Successful recovery clears the old scoped tester secret before replacing credentials")
	_check(not app._tester_active() and app.identity_restart_required, "Recovered identity remains held for cold secure reload and explicit grant restoration")
	root.remove_child(app)
	app.queue_free()
	await process_frame

func _settle_main(scene: Node) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while scene.tester_loading and Time.get_ticks_msec() < deadline: await process_frame
	await process_frame

func _path(label: String) -> String:
	var result := "user://test-tester-%s-%d.json" % [label, Time.get_ticks_usec()]
	paths.append(result)
	return result

func _text(node: Node, value: String) -> bool:
	if node is Label and node.text == value: return true
	for child: Node in node.get_children():
		if _text(child, value): return true
	return false

func _button(node: Node, value: String) -> Button:
	if node is Button and node.text == value: return node
	for child: Node in node.get_children():
		var found := _button(child, value)
		if found != null: return found
	return null

func _button_containing(node: Node, value: String) -> Button:
	if node is Button and value in node.text: return node
	for child: Node in node.get_children():
		var found := _button_containing(child, value)
		if found != null: return found
	return null

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
