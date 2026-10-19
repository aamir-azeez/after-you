extends SceneTree
## PlatformGames with a fake provider, a fake server and a fake account: every sign-in outcome,
## the link rules (first link, held link, conflict, other account, restore on a new phone,
## the player's choice), the server turning the feature off, and the inert desktop service.
const Service = preload("res://services/platform_games/platform_games.gd")
const GamesProvider = preload("res://services/platform_games/games_provider.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

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
	var player_id := "p".repeat(22)
	var answers: Dictionary = {}
	var calls: Array = []
	func request_json(_method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		calls.append({"path": path, "body": body.duplicate(true)})
		return await _answer(path)
	func request_json_with_headers(_method: int, path: String, _body: Dictionary, extra: PackedStringArray, _still: Callable = Callable()) -> Dictionary:
		calls.append({"path": path, "headers": extra})
		return await _answer(path)
	func _answer(path: String) -> Dictionary:
		await Engine.get_main_loop().process_frame
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
	var unoffered := _service(FakeProvider.new(), api, _account(api), "unoffered")
	await unoffered.start()
	_check(not unoffered.offered() and api.calls.size() == 1, "Not offered: nothing is linked and no proof is asked for")
	unoffered.queue_free()
	# Offline link attempt.
	api.answers = {"/v2/capabilities": [_ok(CAPABILITY)]}
	var offline := _service(FakeProvider.new(), api, _account(api), "offline")
	await offline.start()
	_check(offline.link_state == Service.LINK_ERROR and offline.status_line() == PlayerCopy.PLATFORM_GAMES_OFFLINE, "Offline linking says so and changes nothing")
	offline.queue_free()

	# A new phone (no identity yet): the linked identity comes back without asking.
	api.calls.clear()
	var new_phone := _account(api)
	new_phone.identity = "missing"
	var reinstall := _service(FakeProvider.new(), api, new_phone, "reinstall")
	await reinstall.start()
	_check(new_phone.restores.size() == 1 and new_phone.restores[0].restart == false, "A phone without an identity restores in place")
	_check(api.calls.is_empty(), "No capability read is needed without an identity")
	_check(reinstall.linked(), "The restored identity counts as linked")
	reinstall.queue_free()
	# No link for this account (or the feature off): asked once, then not again for a day.
	var none_phone := _account(api)
	none_phone.identity = "missing"
	none_phone.restore_answer = {"ok": false, "status": 404, "code": "platform_link_not_found"}
	var nothing := _service(FakeProvider.new(), api, none_phone, "nothing")
	await nothing.start()
	await nothing.start()
	_check(none_phone.restores.size() == 1 and nothing.link_state == Service.LINK_NONE, "A missing link is remembered so launches do not keep asking")
	nothing.queue_free()
	# Without the build's web client id, a new phone does not try.
	var bare := _account(api)
	bare.identity = "missing"
	bare.web_client = ""
	var bare_service := _service(FakeProvider.new(), api, bare, "bare")
	await bare_service.start()
	_check(bare.restores.is_empty(), "No web client id, no restore attempt")
	bare_service.queue_free()
	# An identity this phone cannot read is never replaced.
	var blocked := _account(api)
	blocked.identity = "blocked"
	api.calls.clear()
	var blocked_service := _service(FakeProvider.new(), api, blocked, "blocked")
	await blocked_service.start()
	_check(blocked.restores.is_empty() and api.calls.is_empty(), "An unreadable identity blocks link and restore")
	blocked_service.queue_free()

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

	await process_frame
	api.queue_free()
	for name: String in DirAccess.get_files_at(_root_dir): DirAccess.remove_absolute(_root_dir.path_join(name))
	DirAccess.remove_absolute(_root_dir)
	print("PLATFORM GAMES SERVICE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
