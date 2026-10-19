extends SceneTree
## PlatformGames with a fake provider, a fake server and a fake account: every sign-in outcome,
## the link rules (first link, held link, conflict, other account, restore on a new phone,
## the player's choice), the server turning the feature off, Main leaving mid-request, and the
## inert desktop service. The platform is never asked anything until the server offers it.
const Service = preload("res://services/platform_games/platform_games.gd")
const GamesProvider = preload("res://services/platform_games/games_provider.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Flow = preload("res://presentation/platform_games_flow.gd")

class FakeSettings extends Node:
	signal closed
	var refreshes := 0
	func refresh() -> void: refreshes += 1

## Just what the flow's prompt needs from Main.
class FakeHost extends Node:
	var ui := Control.new()
	var mode := "home"
	var settings_flow := FakeSettings.new()
	var identity_data := {}
	var toasts: Array = []
	func _init() -> void:
		ui.name = "UI"
		ui.size = Vector2(1280, 720)
		add_child(ui)
		add_child(settings_flow)
	func _toast(text: String) -> void: toasts.append(text)

class FakeProvider extends "res://services/platform_games/games_provider.gd":
	var auth: Dictionary = {"ok": true, "signed_in": true, "player_key": "a".repeat(64)}
	var credential: Dictionary = {"ok": true, "credential": {"server_auth_code": "4/0Asynthetic-code"}}
	var auth_calls: Array = []
	var credential_calls: Array = []
	func kind() -> String: return PLAY_GAMES
	func available() -> bool: return true
	func authenticate(interactive: bool) -> Dictionary:
		auth_calls.append(interactive)
		return auth.duplicate(true)
	func server_credential(web_client_id: String) -> Dictionary:
		credential_calls.append(web_client_id)
		return credential.duplicate(true)

class FakeApi extends Node:
	signal never
	var player_id := "p".repeat(22)
	var answers: Dictionary = {}
	var calls: Array = []
	var hang_path := ""
	func request_json(_method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		calls.append({"path": path, "body": body.duplicate(true)})
		return await _answer(path)
	func request_json_with_headers(_method: int, path: String, _body: Dictionary, extra: PackedStringArray, _still: Callable = Callable()) -> Dictionary:
		calls.append({"path": path, "headers": extra})
		return await _answer(path)
	func _answer(path: String) -> Dictionary:
		await Engine.get_main_loop().process_frame
		# Main's api freed mid-request: the request never answers.
		if path == hang_path: await never
		var queue: Array = answers.get(path, [])
		return queue.pop_front() if not queue.is_empty() else {"ok": false, "status": 0, "code": "connection_interrupted"}

class FakeAccount extends RefCounted:
	var api_node: Node
	var identity := "ready"
	var player := "p".repeat(22)
	var web_client := "123456789012-syntheticclientabc.apps.googleusercontent.com"
	var restores: Array = []
	var restore_answer: Dictionary = {"ok": true, "player_id": "q".repeat(22)}
	func api() -> Node: return api_node
	func identity_state() -> String: return identity
	func player_id() -> String: return player
	func recovery_code() -> String: return "r".repeat(43)
	func config_web_client_id() -> String: return web_client
	func cloud_sources() -> RefCounted: return null
	func restore_identity(provider: String, get_credential: Callable, restart: bool) -> Dictionary:
		var credential: Dictionary = await get_credential.call()
		restores.append({"provider": provider, "restart": restart, "credential": credential})
		if restore_answer.get("ok", false) and not restart: identity = "ready"
		return restore_answer.duplicate(true)

var checks := 0
var failures := 0
var _root_dir := ""

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _ok(data: Dictionary) -> Dictionary: return {"ok": true, "status": 200, "data": data}
## The restore route's answer to a proof-less probe while the provider is on.
func _on() -> Dictionary: return {"ok": false, "status": 400, "code": "invalid_platform_request", "data": {}}
func _fail(status: int, code: String) -> Dictionary: return {"ok": false, "status": status, "code": code, "data": {}}
const CAPABILITY := {"api_version": 2, "play_games_version": 1, "play_games_web_client_id": "123456789012-servclientabcd.apps.googleusercontent.com"}

func _service(provider: RefCounted, api: Node, account: RefCounted, name: String) -> Node:
	var service: Node = Service.new()
	service.configure(provider, _root_dir.path_join(name + ".json"))
	root.add_child(service)
	service.attach(account)
	return service

func _account(api: Node) -> FakeAccount:
	var account := FakeAccount.new()
	account.api_node = api
	return account

## The one-tap prompt as players see it: only at Home, once a session, Not now by any close.
func _prompt_flow() -> void:
	var linked := _ok({"schema_version": 1, "provider": "play_games", "linked": true})
	for answer: String in ["not_now", "use_it"]:
		var host := FakeHost.new()
		host.mode = "play"
		root.add_child(host)
		var flow: Node = Flow.new(host)
		host.add_child(flow)
		var api := FakeApi.new()
		root.add_child(api)
		api.answers = {"/v1/platform/restore": [_on(), linked]}
		var phone := _account(api)
		phone.identity = "missing"
		var service := _service(FakeProvider.new(), api, phone, "prompt-" + answer)
		flow.service = service
		service.changed.connect(flow._on_changed)
		await service.start()
		_check(service.offer_pending() and host.ui.get_node_or_null("PlatformRestoreModal") == null, "No prompt while a chapter or room is on screen")
		host.mode = "home"
		await create_timer(1.3).timeout
		var modal: Node = host.ui.get_node_or_null("PlatformRestoreModal")
		_check(modal != null, "The prompt appears once Home shows")
		if modal == null: continue
		var buttons := [modal.find_child("ModalCancel", true, false), modal.find_child("ModalConfirm", true, false)]
		_check(buttons[0] is Button and buttons[0].text == PlayerCopy.PLATFORM_GAMES_NOT_NOW and buttons[1].text == PlayerCopy.PLATFORM_GAMES_USE_IT, "It offers Use it and Not now")
		(buttons[0] if answer == "not_now" else buttons[1]).pressed.emit()
		for _frame in range(20): await process_frame
		if answer == "not_now":
			_check(service.offer_declined and phone.restores.is_empty(), "Not now restores nothing")
			service.changed.emit()
			await create_timer(1.3).timeout
			_check(host.ui.get_node_or_null("PlatformRestoreModal") == null, "and the prompt does not come back this session")
		else:
			_check(phone.restores.size() == 1 and service.linked() and not service.offer_declined, "Use it brings the friend code back")
		service.queue_free()
		api.queue_free()
		host.queue_free()
		await process_frame

func _run() -> void:
	_root_dir = "user://platform-games-service-test-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_root_dir)

	# Desktop: the base provider is inert, writes nothing and offers nothing.
	var inert: Node = Service.new()
	inert.provider = GamesProvider.new()
	root.add_child(inert)
	_check(inert.sign_in == Service.SignIn.UNAVAILABLE and inert.state == null and not inert.offered(), "Without a platform service the autoload stays inert")
	_check(not FileAccess.file_exists("user://platform-games-v1.json"), "The inert service writes no file")
	_check((await inert.unlock_achievement("any")).code == "not_enabled" and (await inert.submit_score("any", 1)).code == "not_enabled", "Achievements and leaderboards exist only as an interface")
	inert.queue_free()

	# First link on a phone with its own identity.
	var api := FakeApi.new()
	root.add_child(api)
	api.answers = {"/v2/capabilities": [_ok(CAPABILITY)], "/v1/platform/link": [_ok({"schema_version": 1, "provider": "play_games", "status": "linked", "changed": true})]}
	var provider := FakeProvider.new()
	var account := _account(api)
	var service := _service(provider, api, account, "first")
	await service.start()
	_check(provider.auth_calls == [false], "Launch checks sign-in quietly, once")
	_check(service.signed_in() and service.offered() and service.linked(), "Signed in, offered and linked")
	_check(api.calls[0].path == "/v2/capabilities" and "X-AfterYou-Platform-Games: 1" in api.calls[0].headers, "The capability is asked for with the opt-in header")
	_check(provider.credential_calls == [CAPABILITY.play_games_web_client_id], "The server's web client id is used for the auth code")
	_check(api.calls[1].body == {"schema_version": 1, "provider": "play_games", "credential": {"server_auth_code": "4/0Asynthetic-code"}, "recovery_code": "r".repeat(43)}, "Link sends the provider, the platform proof and the recovery code that allows a later restore")
	_check(service.status_line() == PlayerCopy.PLATFORM_GAMES_LINKED, "Settings says linked")
	# Next launch: the link held on this phone answers without the server.
	var calls_before := api.calls.size()
	var again := _service(FakeProvider.new(), api, account, "first")
	await again.start()
	_check(again.linked() and api.calls.size() == calls_before, "A held link and a fresh capability need no server call")
	again.queue_free()
	# Unlink.
	api.answers["/v1/platform/unlink"] = [_ok({"schema_version": 1, "provider": "play_games", "unlinked": true})]
	await service.unlink()
	_check(not service.linked() and service.state.link("play_games").is_empty(), "Unlink forgets the link here too")
	service.queue_free()

	# Sign-in outcomes.
	var cases := [[{"ok": true, "signed_in": false}, PlayerCopy.PLATFORM_GAMES_SIGNED_OUT], [{"ok": false, "code": "cancelled"}, PlayerCopy.PLATFORM_GAMES_SIGNED_OUT],
		[{"ok": false, "code": "offline"}, PlayerCopy.PLATFORM_GAMES_OFFLINE], [{"ok": false, "code": "unavailable"}, PlayerCopy.PLATFORM_GAMES_UNAVAILABLE], [{"ok": false, "code": "timeout"}, PlayerCopy.PLATFORM_GAMES_SIGNED_OUT]]
	for row: Array in cases:
		api.calls.clear()
		api.answers = {"/v2/capabilities": [_ok(CAPABILITY)]}
		var signed_out := FakeProvider.new()
		signed_out.auth = row[0]
		var quiet := _service(signed_out, api, _account(api), "signed-out-%d" % checks)
		await quiet.start()
		_check(not quiet.signed_in() and quiet.status_line() == row[1], "Sign-in answer %s shows its own line" % str(row[0]))
		_check(quiet.offered() and api.calls.size() == 1 and api.calls[0].path == "/v2/capabilities", "Signed out, the row still learns it is offered and nothing is linked")
		quiet.queue_free()
	# Manual sign-in from Settings uses the interactive sheet.
	api.answers = {"/v2/capabilities": [_ok(CAPABILITY)], "/v1/platform/link": [_ok({"schema_version": 1, "provider": "play_games", "status": "linked", "changed": true})]}
	var manual_provider := FakeProvider.new()
	manual_provider.auth = {"ok": false, "code": "cancelled"}
	var manual := _service(manual_provider, api, _account(api), "manual")
	await manual.start()
	manual_provider.auth = {"ok": true, "signed_in": true, "player_key": "b".repeat(64)}
	await manual.sign_in_now()
	_check(manual_provider.auth_calls == [false, true] and manual.linked(), "Sign in from Settings shows the sheet and links")
	manual.queue_free()

	# Conflict: the account belongs to another identity and this phone has its own.
	api.calls.clear()
	api.answers = {"/v2/capabilities": [_ok(CAPABILITY)], "/v1/platform/link": [_ok({"schema_version": 1, "provider": "play_games", "status": "conflict", "changed": false}), _ok({"schema_version": 1, "provider": "play_games", "status": "linked", "changed": true})]}
	var notices: Array = []
	var conflicted := _service(FakeProvider.new(), api, _account(api), "conflict")
	conflicted.notice.connect(func(text: String): notices.append(text))
	await conflicted.start()
	_check(conflicted.link_state == Service.LINK_CONFLICT and conflicted.waiting_for_choice(), "A conflict waits for the player")
	_check(notices == [PlayerCopy.PLATFORM_GAMES_CONFLICT_NOTICE % "Play Games"], "The player hears about the choice once")
	await conflicted.keep_this_phone()
	_check(conflicted.linked() and api.calls[-1].body.get("replace") == true, "Keeping this phone's moves the link only with replace")
	conflicted.queue_free()
	# Conflict, other choice: use the linked identity (a restart like recovery).
	api.answers = {"/v2/capabilities": [_ok(CAPABILITY)], "/v1/platform/link": [_ok({"schema_version": 1, "provider": "play_games", "status": "conflict", "changed": false})]}
	var switching_account := _account(api)
	var switching := _service(FakeProvider.new(), api, switching_account, "switch")
	await switching.start()
	await switching.use_linked_progress()
	_check(switching_account.restores.size() == 1 and switching_account.restores[0].restart == true and switching_account.restores[0].credential.ok, "Using the linked identity restores with a restart and a fresh proof")
	_check(switching.linked() and switching.state.link("play_games").player_id == "q".repeat(22), "The restored identity is remembered as linked")
	switching.queue_free()
	# Other account: this identity is linked to a different account.
	api.answers = {"/v2/capabilities": [_ok(CAPABILITY)], "/v1/platform/link": [_ok({"schema_version": 1, "provider": "play_games", "status": "other_account", "changed": false})]}
	var other := _service(FakeProvider.new(), api, _account(api), "other")
	await other.start()
	_check(other.link_state == Service.LINK_OTHER and other.status_line() == PlayerCopy.PLATFORM_GAMES_OTHER_ACCOUNT, "Another account on this identity is shown, not changed")
	await other.use_linked_progress()
	_check(other.link_state == Service.LINK_OTHER, "Restore is only offered for a conflict")
	other.queue_free()
	# The server turned the feature off since the capability was read.
	api.answers = {"/v2/capabilities": [_ok(CAPABILITY)], "/v1/platform/link": [_fail(404, "not_found")]}
	var switched_off := _service(FakeProvider.new(), api, _account(api), "off")
	await switched_off.start()
	_check(not switched_off.offered() and switched_off.link_state == Service.LINK_NONE, "A 404 hides the row until the next capability read")
	switched_off.queue_free()
	# The server never offered it.
	api.calls.clear()
	api.answers = {"/v2/capabilities": [_ok({"api_version": 2})]}
	var unoffered_provider := FakeProvider.new()
	var unoffered := _service(unoffered_provider, api, _account(api), "unoffered")
	await unoffered.start()
	_check(not unoffered.offered() and api.calls.size() == 1, "Not offered: nothing is linked and no proof is asked for")
	_check(unoffered_provider.auth_calls.is_empty() and unoffered.status_line() == PlayerCopy.PLATFORM_GAMES_UNAVAILABLE, "Not offered: the platform is never asked to sign in, so no Play Games banner appears")
	unoffered.queue_free()
	# Offline link attempt.
	api.answers = {"/v2/capabilities": [_ok(CAPABILITY)]}
	var offline := _service(FakeProvider.new(), api, _account(api), "offline")
	await offline.start()
	_check(offline.link_state == Service.LINK_ERROR and offline.status_line() == PlayerCopy.PLATFORM_GAMES_OFFLINE, "Offline linking says so and changes nothing")
	offline.queue_free()

	# A new phone (no identity yet): it checks, then asks with one tap; only "Use it" restores.
	api.calls.clear()
	var linked_answer := _ok({"schema_version": 1, "provider": "play_games", "linked": true})
	api.answers = {"/v1/platform/restore": [_on(), linked_answer], "/v2/capabilities": [_ok(CAPABILITY)]}
	var new_phone := _account(api)
	new_phone.identity = "missing"
	var reinstall := _service(FakeProvider.new(), api, new_phone, "reinstall")
	await reinstall.start()
	_check(api.calls[0].path == "/v1/platform/restore" and api.calls[0].body == {"provider": "play_games"}, "Without an identity, one proof-less probe tells whether the server offers it")
	_check(api.calls[1].body == {"schema_version": 1, "provider": "play_games", "credential": {"server_auth_code": "4/0Asynthetic-code"}, "check": true}, "Then it only checks whether the account has a friend code")
	_check(reinstall.offer_pending() and new_phone.restores.is_empty() and reinstall.status_line() == PlayerCopy.PLATFORM_GAMES_OFFER_NOTE, "Nothing is restored before the player says yes")
	await reinstall.accept_offer()
	_check(new_phone.restores.size() == 1 and new_phone.restores[0].restart == false, "Use it restores in place")
	_check(reinstall.linked(), "The restored identity counts as linked")
	_check(api.calls.size() == 3 and api.calls[2].path == "/v2/capabilities", "Once restored, the real capability is read")
	_check(reinstall._cloud_allowed() and reinstall.cloud.due(), "and a cloud pull is due in the same session")
	reinstall.queue_free()
	# "Not now": stays a fresh install, not asked again this session, asked again on a later launch.
	api.answers = {"/v1/platform/restore": [_on(), linked_answer, linked_answer, linked_answer]}
	var second_phone := _account(api)
	second_phone.identity = "missing"
	var second := _service(FakeProvider.new(), api, second_phone, "second-phone")
	await second.start()
	second.decline_offer()
	_check(not second.offer_pending() and second.link_state == Service.LINK_OFFER and second_phone.restores.is_empty(), "Not now leaves the phone as it is and keeps the offer for Settings")
	await second.start()
	_check(not second.offer_pending(), "and the same session does not ask again")
	await second.accept_offer()
	_check(second_phone.restores.size() == 1 and second.linked(), "Settings can still bring the friend code back later")
	second.queue_free()
	api.answers = {"/v1/platform/restore": [_on(), linked_answer]}
	var next_launch_phone := _account(api)
	next_launch_phone.identity = "missing"
	var next_launch := _service(FakeProvider.new(), api, next_launch_phone, "second-phone")
	await next_launch.start()
	_check(next_launch.offer_pending(), "A later launch may ask again")
	next_launch.queue_free()
	# Probe says off: nothing is asked of the platform.
	api.answers = {"/v1/platform/restore": [_fail(401, "invalid_auth")]}
	var off_phone := _account(api)
	off_phone.identity = "missing"
	var off_provider := FakeProvider.new()
	var off_service := _service(off_provider, api, off_phone, "probe-off")
	await off_service.start()
	_check(off_provider.auth_calls.is_empty() and off_phone.restores.is_empty() and not off_service.offered(), "A server with the feature off keeps the platform untouched")
	off_service.queue_free()
	# No link for this account: checked once, then not again for a day; no prompt.
	api.answers = {"/v1/platform/restore": [_on(), _ok({"schema_version": 1, "provider": "play_games", "linked": false})]}
	var none_phone := _account(api)
	none_phone.identity = "missing"
	var nothing := _service(FakeProvider.new(), api, none_phone, "nothing")
	await nothing.start()
	_check(not nothing.offer_pending() and none_phone.restores.is_empty(), "No friend code on the account: no prompt")
	_check(nothing._cloud_allowed() and nothing.cloud.due(), "No link to bring back, but the account's saved games still sync (solo progress)")
	nothing.cloud.stop()
	var checks_before := api.calls.size()
	await nothing.start()
	_check(api.calls.size() == checks_before and nothing.link_state == Service.LINK_NONE, "A missing link is remembered so launches do not keep asking")
	_check(nothing.cloud.due(), "and later launches still pull the saved games")
	nothing.queue_free()
	# Without the build's web client id, a new phone does not try.
	api.answers = {"/v1/platform/restore": [_on()]}
	var bare := _account(api)
	bare.identity = "missing"
	bare.web_client = ""
	var bare_service := _service(FakeProvider.new(), api, bare, "bare")
	await bare_service.start()
	_check(bare.restores.is_empty() and not bare_service.offer_pending(), "No web client id, no check and no prompt")
	_check(bare_service.cloud.due(), "but the saved games are still pulled")
	bare_service.queue_free()
	# An identity this phone cannot read is never replaced.
	var blocked := _account(api)
	blocked.identity = "blocked"
	api.calls.clear()
	var blocked_service := _service(FakeProvider.new(), api, blocked, "blocked")
	await blocked_service.start()
	_check(blocked.restores.is_empty() and api.calls.is_empty(), "An unreadable identity blocks link and restore")
	blocked_service.queue_free()

	# Main leaves while the link request is in flight (a solo chapter opened): nothing stays stuck.
	api.answers = {"/v2/capabilities": [_ok(CAPABILITY)]}
	api.hang_path = "/v1/platform/link"
	var leaving_account := _account(api)
	var leaving := _service(FakeProvider.new(), api, leaving_account, "leaving")
	leaving.start()
	for _frame in range(10): await process_frame
	_check(leaving.busy and leaving.link_state == Service.LINK_CHECKING, "The link request is waiting on Main's api")
	leaving.detach(leaving_account)
	_check(not leaving.busy and leaving.link_state == Service.LINK_NONE and not leaving._running, "Main leaving releases the service at once")
	api.hang_path = ""
	api.answers = {"/v1/platform/link": [_ok({"schema_version": 1, "provider": "play_games", "status": "linked", "changed": true})]}
	leaving.attach(leaving_account)
	for _frame in range(30): await process_frame
	_check(leaving.linked(), "The next Main start picks the link up again")
	leaving.queue_free()
	# Cloud save does not need a friend link: a conflict still syncs the account's saved games.
	api.answers = {"/v2/capabilities": [_ok(CAPABILITY)], "/v1/platform/link": [_ok({"schema_version": 1, "provider": "play_games", "status": "conflict", "changed": false})]}
	var unlinked := _service(FakeProvider.new(), api, _account(api), "cloud-unlinked")
	await unlinked.start()
	_check(unlinked.link_state == Service.LINK_CONFLICT and unlinked._cloud_allowed(), "Cloud save follows sign-in and the server's offer, not the friend link")
	unlinked.queue_free()

	# The platform account changes: nothing about the old one carries over.
	api.answers = {"/v2/capabilities": [_ok(CAPABILITY)], "/v1/platform/link": [_ok({"schema_version": 1, "provider": "play_games", "status": "linked", "changed": true}), _ok({"schema_version": 1, "provider": "play_games", "status": "other_account", "changed": false})]}
	var changing_provider := FakeProvider.new()
	var changing := _service(changing_provider, api, _account(api), "changing")
	await changing.start()
	_check(changing.linked(), "Linked before the change")
	changing_provider.auth = {"ok": true, "signed_in": true, "player_key": "c".repeat(64)}
	changing_provider.account_changed.emit()
	for _frame in range(30): await process_frame
	_check(changing.link_state == Service.LINK_OTHER, "A different account is checked again and not treated as linked")
	changing.queue_free()

	await _prompt_flow()

	await process_frame
	api.queue_free()
	for name: String in DirAccess.get_files_at(_root_dir): DirAccess.remove_absolute(_root_dir.path_join(name))
	DirAccess.remove_absolute(_root_dir)
	print("PLATFORM GAMES SERVICE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
