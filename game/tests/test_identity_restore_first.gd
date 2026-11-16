extends SceneTree
## A fresh install never makes a new friend code while its Play Games or Game Center account
## already has one: the first online tap (Main._ensure_identity, which Rooms, Restore purchases,
## Buy and room links all go through) offers it first. "Not now" makes nothing and the next tap
## asks again, except Restore purchases, which always goes on; an account with no friend code, or a server without the feature, makes one as
## before; a check that cannot reach the server makes nothing yet; two taps at once make one.
## Recover identity on a phone that has a friend code asks to keep its recovery details first, a
## restored friend code's purchases are read again once the store is set up for it, and a friend
## code an iPhone reinstall kept is checked with the server once before it is used.
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Service = preload("res://services/platform_games/platform_games.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const AccountFlow = preload("res://presentation/account_flow.gd")
const StoreFlow = preload("res://presentation/store_flow.gd")
const PollenClient = preload("res://services/pollen_client.gd")
const RESTORED := "RRRRRRRRRRRRRRRRRRRRRR"
const NEW_PLAYER := "NNNNNNNNNNNNNNNNNNNNNN"
const OWN_PLAYER := "OOOOOOOOOOOOOOOOOOOOOO"
const OWN_CODE := "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"
const WEB_CLIENT := "123456789012-syntheticclientabc.apps.googleusercontent.com"

## Answers by path, in order; anything unanswered reads as offline.
class Api extends "res://tests/fake_rooms_api.gd":
	var answers: Dictionary = {}
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		calls.append({"method": method, "path": path, "body": body.duplicate(true)})
		await Engine.get_main_loop().process_frame
		var queue: Array = answers.get(path, [])
		return queue.pop_front() if not queue.is_empty() else {"ok": false, "status": 0, "code": "connection_interrupted", "error": "offline"}
	func request_json_with_headers(method: int, path: String, body: Dictionary, _extra: PackedStringArray, still: Callable = Callable()) -> Dictionary:
		return await request_json(method, path, body, still)
	func posts(path: String) -> int:
		return calls.filter(func(call: Dictionary) -> bool: return call.path == path and call.method == HTTPClient.METHOD_POST).size()

class Provider extends "res://services/platform_games/games_provider.gd":
	func kind() -> String: return PLAY_GAMES
	func available() -> bool: return true
	func authenticate(_interactive: bool) -> Dictionary: return {"ok": true, "signed_in": true, "player_key": "a".repeat(64)}
	func server_credential(_web_client_id: String) -> Dictionary: return {"ok": true, "credential": {"server_auth_code": "4/0Asynthetic-code"}}

## Secure storage that remembers what was written.
class Secrets extends Node:
	signal completed(id: String, operation: String, payload: Dictionary)
	signal failed(id: String, operation: String, code: String)
	var values: Dictionary = {}
	## Names an earlier install left (the iPhone Keychain reads them "kept" after a reinstall).
	var kept: Array = []
	var count := 0
	func is_available() -> bool: return true
	func get_secret(name: String) -> String:
		count += 1
		var id := "s-%d" % count
		var payload := {"found": true, "value": values[name]} if values.has(name) else {"found": false, "value": null}
		if values.has(name) and name in kept: payload.kept = true
		_emit.call_deferred(id, "get", payload)
		return id
	func put_secret(name: String, value: String) -> String:
		count += 1
		values[name] = value
		_emit.call_deferred("s-%d" % count, "put", {"stored": true})
		return "s-%d" % count
	func remove_secret(name: String) -> String:
		count += 1
		values.erase(name)
		kept.erase(name)
		_emit.call_deferred("s-%d" % count, "remove", {"removed": true})
		return "s-%d" % count
	func _emit(id: String, operation: String, payload: Dictionary) -> void: completed.emit(id, operation, payload)

var checks := 0
var failures := 0
var _dir := ""

func _initialize() -> void: _run.call_deferred()

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _probe_on() -> Dictionary: return {"ok": false, "status": 400, "code": "invalid_platform_request", "data": {}}
func _linked(linked: bool) -> Dictionary: return {"ok": true, "status": 200, "data": {"provider": "play_games", "linked": linked}}
func _restored() -> Dictionary: return {"ok": true, "status": 200, "data": {"restored": true, "player_id": RESTORED}}
func _new_identity() -> Dictionary: return {"ok": true, "status": 201, "data": {"player_id": NEW_PLAYER, "device_token": "synthetic-device-token", "recovery_code": "synthetic-recovery-code"}}

## A fresh install: no identity in secure storage, and a new platform service that has not run yet.
func _fresh(app: Node, api: Api, secrets: Secrets, name: String) -> Node:
	var flow: Node = app.platform_games_flow
	if flow.service != null:
		flow.detach()
		flow.service.queue_free()
		flow.service = null
	secrets.values = {}
	app.identity_busy = false
	app.identity_restart_required = false
	app.identity_data = {}
	app.identity_read_state = Main.IdentityReadState.UNCHECKED
	api.player_id = ""
	api.device_token = ""
	api.calls.clear()
	api.answers = {}
	app.saves.update_values({}, [StoreFlow.RESTORE_SYNC_KEY])
	app._load_saved_identity()
	while app.identity_loading: await process_frame
	var service: Node = Service.new()
	service.configure(Provider.new(), _dir.path_join(name + ".json"))
	root.add_child(service)
	flow.service = service
	flow.attach()
	return service

## An online tap that runs on its own, as a button's would; the test answers its pop-up meanwhile.
func _tap(app: Node, result: Array, reports: Array) -> void:
	result.append(await app._ensure_identity(func(text: String) -> void: reports.append(text)))

func _modal(app: Node) -> Node:
	for _frame in range(400):
		var modal: Node = app.ui.get_node_or_null("PlatformRestoreModal")
		if modal != null and not modal.is_queued_for_deletion(): return modal
		await process_frame
	return null

func _until(done: Callable) -> void:
	for _frame in range(600):
		if done.call(): return
		await process_frame

func _run() -> void:
	_dir = "user://identity-restore-first-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	var app := Main.new()
	app.saves = Storage.new(_dir.path_join("journey.json"))
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.config["revenuecat_public_key"] = ""
	app.config["play_games_web_client_id"] = WEB_CLIENT
	var api := Api.new()
	app.add_child(api)
	app.api = api
	var secrets := Secrets.new()
	app.add_child(secrets)
	app.secrets = secrets
	secrets.completed.connect(app._secret_completed)
	await process_frame

	await _restore_on_first_tap(app, api, secrets)
	await _not_now_asks_again(app, api, secrets)
	await _no_link_creates_once(app, api, secrets)
	await _unreachable_check_makes_nothing(app, api, secrets)
	await _feature_off_creates(app, api, secrets)
	await _recover_asks_to_keep_code(app)
	await _purchase_sync_after_restore()
	await _restore_purchases_after_not_now(app, api, secrets)
	await _kept_identity_after_reinstall(app, api, secrets)

	var flow: Node = app.platform_games_flow
	if flow.service != null:
		flow.detach()
		flow.service.queue_free()
	app.queue_free()
	await process_frame
	for name: String in DirAccess.get_files_at(_dir): DirAccess.remove_absolute(_dir.path_join(name))
	DirAccess.remove_absolute(_dir)
	print("IDENTITY RESTORE FIRST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The very first tap, before the launch timer ran the check: the check runs now, the pop-up asks,
## and "Use it" brings the account's friend code back. No new one is made.
func _restore_on_first_tap(app: Node, api: Api, secrets: Secrets) -> void:
	var service := await _fresh(app, api, secrets, "first-tap")
	api.answers = {"/v1/platform/restore": [_probe_on(), _linked(true), _restored()], "/v1/identity": [_new_identity()]}
	_check(service.sign_in == Service.SignIn.UNAVAILABLE, "The launch check has not run yet")
	var result: Array = []
	var reports: Array = []
	_tap(app, result, reports)
	var modal := await _modal(app)
	_check(modal != null and api.posts("/v1/identity") == 0, "The tap asks to bring the friend code back before making one")
	if modal == null: return
	modal.find_child("ModalConfirm", true, false).pressed.emit()
	await _until(func() -> bool: return not result.is_empty())
	_check(result == [true] and api.posts("/v1/identity") == 0 and api.player_id == RESTORED, "Use it brings the account's friend code here and the tap goes on with it")
	_check(app.saves.data.get(StoreFlow.RESTORE_SYNC_KEY) == RESTORED, "Its purchases are marked to be read again once the store is set up")
	var stored: Variant = JSON.parse_string(str(secrets.values.get("player_identity", "")))
	_check(stored is Dictionary and stored.player_id == RESTORED, "The restored friend code is kept in secure storage")
	var again: Array = []
	_tap(app, again, reports)
	await _until(func() -> bool: return not again.is_empty())
	_check(again == [true] and api.posts("/v1/identity") == 0 and reports.is_empty(), "Later taps use it without asking")

## "Not now" makes nothing, says why, and the next tap asks again (Home's own prompt stays quiet).
func _not_now_asks_again(app: Node, api: Api, secrets: Secrets) -> void:
	var service := await _fresh(app, api, secrets, "not-now")
	api.answers = {"/v1/platform/restore": [_probe_on(), _linked(true), _restored()], "/v1/identity": [_new_identity()]}
	var result: Array = []
	var reports: Array = []
	_tap(app, result, reports)
	var modal := await _modal(app)
	if modal == null:
		_check(false, "The pop-up shows")
		return
	modal.find_child("ModalCancel", true, false).pressed.emit()
	await _until(func() -> bool: return not result.is_empty())
	_check(result == [false] and api.posts("/v1/identity") == 0 and api.player_id.is_empty(), "Not now makes no new friend code")
	_check(reports == [PlayerCopy.PLATFORM_GAMES_BRING_BACK_FIRST % "Play Games"], "and says how to play online")
	_check(service.offer_declined and not service.offer_pending() and service.offer_waiting(), "Home stops asking, but the friend code still waits")
	_check(not _create_row_visible(app), "Settings offers no new friend code while it waits")
	for _frame in range(5): await process_frame
	var second: Array = []
	_tap(app, second, reports)
	modal = await _modal(app)
	_check(modal != null, "The next online tap asks again")
	if modal == null: return
	modal.find_child("ModalConfirm", true, false).pressed.emit()
	await _until(func() -> bool: return not second.is_empty())
	_check(second == [true] and api.posts("/v1/identity") == 0 and api.player_id == RESTORED, "and Use it then brings it back")

func _create_row_visible(app: Node) -> bool:
	for row: Dictionary in preload("res://presentation/settings_rows.gd").rows(app):
		if row.id == "create_identity": return row.visible_if.call()
	return false

## An account with no friend code: one new friend code, even for two taps at once.
func _no_link_creates_once(app: Node, api: Api, secrets: Secrets) -> void:
	await _fresh(app, api, secrets, "no-link")
	api.answers = {"/v1/platform/restore": [_probe_on(), _linked(false)], "/v1/identity": [_new_identity(), _new_identity()]}
	var first: Array = []
	var second: Array = []
	var reports: Array = []
	_tap(app, first, reports)
	_tap(app, second, reports)
	await _until(func() -> bool: return not first.is_empty() and not second.is_empty())
	_check(first == [true] and second == [true], "Both taps go on")
	_check(api.posts("/v1/identity") == 1 and api.player_id == NEW_PLAYER, "and exactly one new friend code is made")
	_check(app.ui.get_node_or_null("PlatformRestoreModal") == null, "Nothing to bring back, so nothing is asked")

## The check cannot reach the server: nothing is made now, and the next tap checks again.
func _unreachable_check_makes_nothing(app: Node, api: Api, secrets: Secrets) -> void:
	await _fresh(app, api, secrets, "offline")
	api.answers = {"/v1/identity": [_new_identity()]}
	var result: Array = []
	var reports: Array = []
	_tap(app, result, reports)
	await _until(func() -> bool: return not result.is_empty())
	_check(result == [false] and api.posts("/v1/identity") == 0 and reports == [PlayerCopy.PLATFORM_GAMES_TRY_LATER], "An unanswered check makes no friend code and says to try again")
	api.answers["/v1/platform/restore"] = [_probe_on(), _linked(false)]
	var again: Array = []
	_tap(app, again, reports)
	await _until(func() -> bool: return not again.is_empty())
	_check(again == [true] and api.posts("/v1/identity") == 1, "The next tap checks again, then makes one")

## A server without the feature: the platform is never asked, and the tap makes a friend code.
func _feature_off_creates(app: Node, api: Api, secrets: Secrets) -> void:
	await _fresh(app, api, secrets, "off")
	api.answers = {"/v1/platform/restore": [{"ok": false, "status": 401, "code": "invalid_auth", "data": {}}], "/v1/identity": [_new_identity()]}
	var result: Array = []
	_tap(app, result, [])
	await _until(func() -> bool: return not result.is_empty())
	_check(result == [true] and api.posts("/v1/identity") == 1, "Feature off: a new friend code as before")

## Recover identity on a phone with a friend code: its recovery details first, then the form.
func _recover_asks_to_keep_code(app: Node) -> void:
	var account: Node = app.account_flow
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id": OWN_PLAYER, "device_token": "synthetic-device-token", "recovery_code": OWN_CODE}
	app.api.player_id = OWN_PLAYER
	app.api.device_token = "synthetic-device-token"
	app.api.calls.clear()
	account.show_recovery_form()
	_check(app.mode == AccountFlow.MODE_RECOVERY_KEEP, "Recover identity first asks to keep this phone's recovery code")
	var kept: Button = app.overlay.find_child("RecoveryKept", true, false)
	_check(kept != null and kept.disabled, "I kept it waits until the details were shown or copied")
	await account.recover_identity(RESTORED, OWN_CODE.replace("C", "D"))
	_check(app.mode == AccountFlow.MODE_RECOVERY_KEEP and app.api.calls.is_empty() and app.pending_recovery.is_empty(), "A recovery cannot skip the step")
	await account._show_kept_code()
	kept = app.overlay.find_child("RecoveryKept", true, false)
	_check(kept != null and not kept.disabled and _shows(app.overlay, OWN_CODE), "The details show behind the screen lock, and I kept it opens")
	account._keep_card(false)
	kept = app.overlay.find_child("RecoveryKept", true, false)
	_check(kept != null and not kept.disabled and not _shows(app.overlay, OWN_CODE), "Going to the background hides them again without losing the step")
	kept.pressed.emit()
	_check(app.mode == AccountFlow.MODE_RECOVERY_FORM and account.recovery_kept(), "I kept it opens the recovery form")
	account.show_recovery_form()
	_check(app.mode == AccountFlow.MODE_RECOVERY_FORM, "Once kept, the form opens directly this session")
	app.api.player_id = ""
	app.identity_data = {}
	account.show_recovery_form()
	_check(app.mode == AccountFlow.MODE_RECOVERY_FORM, "A phone with no friend code goes straight to the form")

## A launch whose secure storage holds an identity from before a reinstall (the iPhone Keychain).
func _launch_with_kept(app: Node, api: Api, secrets: Secrets, kept: bool, answer: Dictionary) -> void:
	var flow: Node = app.platform_games_flow
	if flow.service != null:
		flow.detach()
		flow.service.queue_free()
		flow.service = null
	secrets.values = {"player_identity": JSON.stringify({"player_id": OWN_PLAYER, "device_token": "synthetic-device-token", "recovery_code": OWN_CODE})}
	secrets.kept = ["player_identity"] if kept else []
	app.identity_busy = false
	app.identity_restart_required = false
	app.deleted_identity_owner = ""
	app.identity_data = {}
	app.identity_read_state = Main.IdentityReadState.UNCHECKED
	api.player_id = ""
	api.device_token = ""
	api.calls.clear()
	api.answers = {"/v1/identity": [answer, _new_identity()]}
	app._load_saved_identity()
	await _until(func() -> bool: return not app.identity_loading)

func _gets(api: Api) -> int:
	return api.calls.filter(func(call: Dictionary) -> bool: return call.path == "/v1/identity" and call.method == HTTPClient.METHOD_GET).size()

## A reinstall keeps its friend code (iPhone Keychain): the server confirms it once, then it is used.
## One erased elsewhere is forgotten and the phone starts fresh; an unanswered check is used and asked
## again next launch. Deleting the identity removes it from secure storage, so no reinstall brings it back.
func _kept_identity_after_reinstall(app: Node, api: Api, secrets: Secrets) -> void:
	await _launch_with_kept(app, api, secrets, true, {"ok": true, "status": 200, "data": {"player_id": OWN_PLAYER}})
	_check(app.identity_read_state == Main.IdentityReadState.LOADED and api.player_id == OWN_PLAYER and _gets(api) == 1, "A kept friend code is checked once with the server, then used")
	var result: Array = []
	_tap(app, result, [])
	await _until(func() -> bool: return not result.is_empty())
	_check(result == [true] and api.posts("/v1/identity") == 0 and _gets(api) == 1, "and online taps use it with no new friend code and no second check")
	await _launch_with_kept(app, api, secrets, false, {"ok": true, "status": 200, "data": {"player_id": OWN_PLAYER}})
	_check(app.identity_read_state == Main.IdentityReadState.LOADED and _gets(api) == 0, "An ordinary launch never checks it")

	await _launch_with_kept(app, api, secrets, true, {"ok": false, "status": 401, "code": "invalid_auth", "data": {}})
	_check(app.identity_read_state == Main.IdentityReadState.MISSING and api.player_id.is_empty() and not secrets.values.has("player_identity"), "One erased elsewhere is forgotten, so the phone starts as a fresh install")

	await _launch_with_kept(app, api, secrets, true, {"ok": false, "status": 0, "code": "connection_interrupted"})
	_check(app.identity_read_state == Main.IdentityReadState.LOADED and api.player_id == OWN_PLAYER and app.saves.data.get(Main.KEPT_IDENTITY_UNCHECKED) == OWN_PLAYER, "No answer: it is used, and noted to be checked again")
	await _launch_with_kept(app, api, secrets, false, {"ok": true, "status": 200, "data": {"player_id": OWN_PLAYER}})
	_check(_gets(api) == 1 and not app.saves.data.has(Main.KEPT_IDENTITY_UNCHECKED), "The next launch checks it and clears the note")

	api.answers["/v1/identity"] = [{"ok": true, "status": 200, "data": {"deleted": true}}]
	api.answers["/v1/identity/deletion-ack"] = [{"ok": true, "status": 200, "data": {"schema_version": 1, "acknowledged": true}}]
	await app.account_flow.delete_identity()
	await _until(func() -> bool: return not secrets.values.has("player_identity"))
	_check(not secrets.values.has("player_identity") and not "player_identity" in secrets.kept, "Deleting the identity removes it from secure storage, so a reinstall never brings it back")

func _shows(node: Node, text: String) -> bool:
	if node is LineEdit and node.text == text: return true
	for child: Node in node.get_children():
		if _shows(child, text): return true
	return false

## The store a Restore purchases tap drives: set up once for a player, then one restore.
class RestoreStore extends Node:
	var configured_for := ""
	var restores := 0
	func configure_store(_key: String, player: String, _mode: String) -> String:
		configured_for = player
		return "configure-1"
	func restore() -> String:
		restores += 1
		return "restore-%d" % restores
	func has_entitlement(_id: String = "") -> bool: return false

## Restore purchases must always work (App Review 3.1.1): on a fresh install it offers the friend
## code first, and after "Not now" it makes one, quietly, then restores and reads purchases.
func _restore_purchases_after_not_now(app: Node, api: Api, secrets: Secrets) -> void:
	await _fresh(app, api, secrets, "restore-not-now")
	api.answers = {"/v1/platform/restore": [_probe_on(), _linked(true), _restored()], "/v1/identity": [_new_identity()]}
	var config: Dictionary = app.config.duplicate(true)
	app.config["revenuecat_public_key"] = "test_synthetic_key"
	app.config["purchase_mode"] = "google_play"
	app.config["entitlement_id"] = "full_journey_play"
	var real_store: Node = app.purchases
	var store := RestoreStore.new()
	app.add_child(store)
	app.purchases = store
	var flow: Node = app.store_flow
	flow.store_configured = false
	flow.store_configure_request = ""
	flow.store_action_pending = false
	app.toast.dismiss()
	flow.restore_purchases()
	var modal := await _modal(app)
	_check(modal != null and api.posts("/v1/identity") == 0, "Restore purchases offers the Play Games friend code first")
	if modal != null:
		modal.find_child("ModalCancel", true, false).pressed.emit()
		await _until(func() -> bool: return flow.restore_requested or not flow.store_action_pending)
		_check(api.posts("/v1/identity") == 1 and api.player_id == NEW_PLAYER and store.configured_for == NEW_PLAYER, "Not now still makes a friend code and sets the store up for it")
		_check(app.toast.take_plain() != PlayerCopy.PLATFORM_GAMES_BRING_BACK_FIRST % "Play Games", "with no word about bringing the friend code back first")
		flow.purchase_completed("configure-1", "configure", {})
		_check(store.restores == 1 and flow.store_action_pending, "and the restore runs")
		flow.purchase_completed("restore-1", "restore_purchases", {})
		_check(not flow.store_action_pending, "then finishes")
	app.purchases = real_store
	store.queue_free()
	app.config = config
	flow.store_configured = false
	flow.store_configure_request = ""
	flow.store_action_pending = false
	flow.restore_requested = false

class FakePurchases extends Node:
	var restores := 0
	var reads := 0
	var entitled := true
	func restore() -> String:
		restores += 1
		return "sync-%d" % restores
	func refresh_customer_info_fresh() -> String:
		reads += 1
		return "read-%d" % reads
	func has_entitlement(_id: String = "") -> bool: return entitled

## The real Pollen client with requests that only count: after a restore it reads the wallet
## saying "bought", then sends one bundle claim.
class FakeClaims extends RefCounted:
	var once := 0
	func flush() -> void: pass
	func claim_once() -> Dictionary:
		once += 1
		return {"ok": true, "credited": [], "refunded": []}

class StoreHost extends Node:
	var api := {"player_id": RESTORED}
	var config := {"purchase_mode": "google_play", "entitlement_id": "full_journey_play"}
	var saves: RefCounted
	var purchases := FakePurchases.new()
	var pollen_client: RefCounted
	var toasts: Array = []
	var mode := "home"
	func _store_identity_settled() -> bool: return true
	func _toast(text: String) -> void: toasts.append(text)

## A restored friend code's purchases: once the store is set up for it, one quiet read, then the
## wallet with Full Journey's word, then one bundle claim; a failed read stays quiet and keeps the mark.
func _purchase_sync_after_restore() -> void:
	var host := StoreHost.new()
	host.saves = Storage.new(_dir.path_join("store.json"))
	root.add_child(host)
	var store: Node = StoreFlow.new(host)
	host.add_child(store)
	var claims := FakeClaims.new()
	var wallet_reads: Array = []
	host.pollen_client = PollenClient.new(null, func() -> Dictionary: return {}, func(method: int, path: String, _body: Dictionary) -> Dictionary:
		wallet_reads.append(path)
		return {"ok": false, "status": 0})
	host.pollen_client.bundle_claims = claims
	store.sync_after_restore(RESTORED)
	store.store_configured = true
	store.store_owner = RESTORED
	store._start_restore_sync()
	var request: String = store.restore_sync_request
	_check(not request.is_empty() and host.purchases.restores + host.purchases.reads == 1, "The store set up for the restored friend code reads its purchases once")
	store.purchase_failed(request, "restore_purchases", "network_error", "Offline", false)
	_check(host.toasts.is_empty() and host.saves.data.get(StoreFlow.RESTORE_SYNC_KEY) == RESTORED and claims.once == 0, "A failed quiet read says nothing and tries again on the next launch")
	store._start_restore_sync()
	request = store.restore_sync_request
	store.purchase_completed(request, "restore_purchases" if host.purchases.restores == 2 else "get_customer_info", {})
	await _until(func() -> bool: return claims.once > 0)
	_check(not host.saves.data.has(StoreFlow.RESTORE_SYNC_KEY) and store.restore_sync_request.is_empty(), "The answered read clears the mark")
	_check(claims.once == 1 and host.toasts.is_empty(), "Any Pollen or Fruit pack moved to it is claimed at once, quietly")
	store._start_restore_sync()
	_check(store.restore_sync_request.is_empty(), "and it runs once")
	host.queue_free()
