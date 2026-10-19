extends Node
## PlatformGames: the one place After You talks to a platform games service (Play Games on
## Android, Game Center on iOS, none on desktop). Autoloaded as /root/PlatformGames; screens find
## it with PlatformGames.shared(tree) and never branch on the platform themselves.
##
## What it does, in order, all off the first frame and never in the way of play:
## 1. A few seconds after launch, a quiet sign-in check (the platform signs in by itself).
## 2. When signed in and the server offers the feature (PLAY_GAMES_ENABLED / GAME_CENTER_ENABLED,
##    read once a day with an opt-in header), it links the account to this phone's friend
##    identity, or, on a phone that has no identity yet (a reinstall), brings the linked
##    identity back. A phone that has its own identity and meets an account linked elsewhere
##    asks the player which to keep (see platform_games_flow.gd).
## 3. Cloud save: progress is joined with a Saved Games slot after meaningful moments.
## Every call is async with a timeout; every failure leaves the game as it was.
##
## Achievements and leaderboards: the provider interface has them, nothing uses them yet.
const GamesProvider = preload("res://services/platform_games/games_provider.gd")
const NativeProvider = preload("res://services/platform_games/native_games_provider.gd")
const LinkClient = preload("res://services/platform_games/platform_link_client.gd")
const State = preload("res://services/platform_games/platform_games_state.gd")
const CloudSync = preload("res://services/platform_games/cloud_save_sync.gd")
const NativeBridge = preload("res://services/native_bridge.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

## Any state a screen shows changed.
signal changed
## A one-line message worth a toast (a restore finished, a choice is waiting).
signal notice(text: String)

enum SignIn { UNAVAILABLE, CHECKING, SIGNED_OUT, SIGNED_IN }
const LINK_NONE := "none"
const LINK_CHECKING := "checking"
const LINK_LINKED := "linked"
const LINK_CONFLICT := "conflict"
const LINK_OTHER := "other_account"
const LINK_RESTORING := "restoring"
const LINK_ERROR := "error"

## The quiet check waits this long after launch, so it never touches the first frames.
const START_DELAY_MS := 4000
## How long the service waits for Main to finish loading an identity before giving up for now.
const ACCOUNT_WAIT_MS := 60000

var provider: RefCounted
var sign_in := SignIn.UNAVAILABLE
## The last sign-in failure ("cancelled", "offline", ...), "" after a success.
var sign_in_code := ""
var link_state := LINK_NONE
var link_code := ""
var busy := false
var state: RefCounted
var cloud: RefCounted
var _player_key := ""
var _account: RefCounted
var _links: RefCounted
var _poll_left := 1.0
var _autostart := true

## The service, or null (a tree without the autoload, such as a tool script).
static func shared(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("PlatformGames") if tree != null else null

func _ready() -> void:
	set_process(false)
	if provider == null: provider = _build_provider()
	if not provider.available():
		# Desktop, headless suites and builds without the plugin: inert, no files, no network.
		sign_in = SignIn.UNAVAILABLE
		return
	if state == null: _open_state(State.PATH)
	if not provider.account_changed.is_connected(_on_account_changed): provider.account_changed.connect(_on_account_changed)
	if _autostart: _start_later()

func _build_provider() -> RefCounted:
	if DisplayServer.get_name() == "headless": return GamesProvider.new()
	var native := NativeBridge.singleton("games")
	if native == null or not native.has_signal("games_result"): return GamesProvider.new()
	return NativeProvider.new(native, GamesProvider.GAME_CENTER if PlatformSupport.is_ios() else GamesProvider.PLAY_GAMES, get_tree())

func _open_state(path: String) -> void:
	state = State.new(path)
	cloud = CloudSync.new(provider, null, state)
	cloud.description = PlayerCopy.PLATFORM_GAMES_SAVE_DESCRIPTION

## Tests: a provider and a state file of their own, and no automatic start.
func configure(test_provider: RefCounted, state_path: String) -> void:
	_autostart = false
	provider = test_provider
	_open_state(state_path)
	if not provider.account_changed.is_connected(_on_account_changed): provider.account_changed.connect(_on_account_changed)

func _start_later() -> void:
	await get_tree().create_timer(START_DELAY_MS / 1000.0).timeout
	await start()

## The quiet check and everything that follows it. Safe to call again (resume, account change).
func start() -> void:
	if busy or not provider.available(): return
	set_process(true)
	await _authenticate(false)

# ---- Main's side ---------------------------------------------------------------------------

## Main hands over what the service needs from the app (see platform_games_flow.gd's account
## adapter): api, identity state, restore, cloud sources. Main is rebuilt after every solo chapter,
## so this is called on every Main start and detached when Main leaves.
func attach(account: RefCounted) -> void:
	_account = account
	_links = LinkClient.new(account.api())
	if cloud != null: cloud.set_sources(account.cloud_sources())
	changed.emit()

func detach(account: RefCounted) -> void:
	if _account != account: return
	_account = null
	_links = null
	if cloud != null: cloud.set_sources(null)

# ---- What screens read ---------------------------------------------------------------------

func kind() -> String:
	return provider.kind() if provider != null else GamesProvider.NONE

## Whether Settings shows the row: a platform service exists here and the server offers it.
func offered() -> bool:
	if provider == null or not provider.available() or state == null: return false
	var held: Dictionary = state.capability()
	return held.get(kind()) == true

func signed_in() -> bool:
	return sign_in == SignIn.SIGNED_IN

func linked() -> bool:
	return link_state == LINK_LINKED

func waiting_for_choice() -> bool:
	return link_state in [LINK_CONFLICT, LINK_OTHER]

## The platform's name as players know it.
func display_name() -> String:
	return PlayerCopy.PLATFORM_GAMES_GAME_CENTER if kind() == GamesProvider.GAME_CENTER else PlayerCopy.PLATFORM_GAMES_PLAY_GAMES

## One short line for Settings.
func status_line() -> String:
	match sign_in:
		SignIn.UNAVAILABLE: return PlayerCopy.PLATFORM_GAMES_UNAVAILABLE
		SignIn.CHECKING: return PlayerCopy.PLATFORM_GAMES_CHECKING
		SignIn.SIGNED_OUT:
			if sign_in_code == "offline": return PlayerCopy.PLATFORM_GAMES_OFFLINE
			if sign_in_code == "unavailable": return PlayerCopy.PLATFORM_GAMES_UNAVAILABLE
			return PlayerCopy.PLATFORM_GAMES_SIGNED_OUT
	match link_state:
		LINK_LINKED: return PlayerCopy.PLATFORM_GAMES_LINKED
		LINK_CONFLICT: return PlayerCopy.PLATFORM_GAMES_CONFLICT
		LINK_OTHER: return PlayerCopy.PLATFORM_GAMES_OTHER_ACCOUNT
		LINK_CHECKING, LINK_RESTORING: return PlayerCopy.PLATFORM_GAMES_CHECKING
		LINK_ERROR: return PlayerCopy.PLATFORM_GAMES_OFFLINE if link_code == "offline" else PlayerCopy.PLATFORM_GAMES_TRY_LATER
	return PlayerCopy.PLATFORM_GAMES_SIGNED_IN

# ---- Sign-in -------------------------------------------------------------------------------

## The Settings button: shows the platform's sign-in sheet.
func sign_in_now() -> void:
	if busy: return
	await _authenticate(true)

func _authenticate(interactive: bool) -> void:
	busy = true
	sign_in = SignIn.CHECKING
	changed.emit()
	var answer: Dictionary = await provider.authenticate(interactive)
	busy = false
	if answer.get("ok", false) and answer.get("signed_in", false):
		sign_in = SignIn.SIGNED_IN
		sign_in_code = ""
		_player_key = str(answer.player_key)
	else:
		sign_in = SignIn.SIGNED_OUT
		sign_in_code = "" if answer.get("ok", false) else str(answer.get("code", "failed"))
		_player_key = ""
		if link_state != LINK_NONE: link_state = LINK_NONE
	changed.emit()
	await _after_auth()

func _on_account_changed() -> void:
	# Another account signed in: nothing about the old one carries over.
	_player_key = ""
	link_state = LINK_NONE
	sign_in = SignIn.SIGNED_OUT
	changed.emit()
	if not busy: await start()

# ---- Linking ---------------------------------------------------------------------------------

func _wait_account() -> bool:
	var deadline := Time.get_ticks_msec() + ACCOUNT_WAIT_MS
	while is_inside_tree() and Time.get_ticks_msec() < deadline:
		if _account != null and _account.identity_state() != "busy": return true
		await get_tree().create_timer(0.5).timeout
	return false

## After any sign-in answer. Signed out, it still learns whether the server offers the feature,
## so Settings can show the sign-in button.
func _after_auth() -> void:
	if not await _wait_account(): return
	if _account.identity_state() == "missing":
		if signed_in(): await _restore_for_new_phone()
		return
	if _account.identity_state() != "ready": return
	var capability := await _capability()
	if capability.get(kind()) != true or not signed_in(): return
	await _reconcile_link(capability)
	if linked() and cloud != null: cloud.flush(true)

func _capability() -> Dictionary:
	var held: Dictionary = state.capability()
	if not held.is_empty() or _links == null: return held
	var answer: Dictionary = await _links.capability()
	if not answer.get("ok", false): return {}
	state.remember_capability(answer)
	changed.emit()
	return state.capability()

func _web_client_id(capability: Dictionary) -> String:
	var from_server := str(capability.get("web_client_id", ""))
	return from_server if not from_server.is_empty() else (_account.config_web_client_id() if _account != null else "")

func _credential(capability: Dictionary) -> Dictionary:
	return await provider.server_credential(_web_client_id(capability))

func _reconcile_link(capability: Dictionary) -> void:
	var held: Dictionary = state.link(kind())
	if held.get("player_key") == _player_key and held.get("player_id") == _account.player_id():
		link_state = LINK_LINKED
		changed.emit()
		return
	if not held.is_empty(): state.forget_link(kind())
	await _link(capability, false)

func _link(capability: Dictionary, replace: bool) -> void:
	busy = true
	link_state = LINK_CHECKING
	changed.emit()
	var player: String = _account.player_id() if _account != null else ""
	var credential: Dictionary = await _credential(capability)
	var answer: Dictionary = {"ok": false, "code": str(credential.get("code", "unavailable"))}
	if credential.get("ok", false) and _links != null:
		answer = await _links.link(kind(), credential.credential, replace)
	busy = false
	link_code = ""
	if answer.get("ok", false) and _account != null and _account.player_id() == player:
		match str(answer.status):
			"linked":
				link_state = LINK_LINKED
				state.remember_link(kind(), _player_key, player)
			"conflict":
				link_state = LINK_CONFLICT
				notice.emit(PlayerCopy.PLATFORM_GAMES_CONFLICT_NOTICE % display_name())
			_:
				link_state = LINK_OTHER
	elif int(answer.get("status", 0)) == 404:
		# The server turned the feature off since we last asked.
		state.forget_capability()
		link_state = LINK_NONE
	else:
		link_state = LINK_ERROR
		link_code = str(answer.get("code", "failed"))
	changed.emit()

## A phone with no friend identity yet (a reinstall): bring the linked one back, asking nothing,
## since there is nothing here to lose. Uses the build's public web client id (no identity, so
## no capability read); a server with the feature off answers 401 and is asked again tomorrow.
func _restore_for_new_phone() -> void:
	if state.restore_probed(_player_key): return
	var capability := {"web_client_id": _account.config_web_client_id()}
	if kind() == GamesProvider.PLAY_GAMES and str(capability.web_client_id).is_empty(): return
	var answer := await _restore(capability, false)
	if not answer.get("ok", false) and int(answer.get("status", 0)) in [401, 404]:
		state.remember_restore_probe(_player_key)
		link_state = LINK_NONE
		changed.emit()

func _restore(capability: Dictionary, restart: bool) -> Dictionary:
	busy = true
	link_state = LINK_RESTORING
	changed.emit()
	var account := _account
	var get_credential := func() -> Dictionary: return await _credential(capability)
	var answer: Dictionary = await account.restore_identity(kind(), get_credential, restart)
	busy = false
	if answer.get("ok", false):
		state.remember_link(kind(), _player_key, str(answer.player_id))
		link_state = LINK_LINKED
		notice.emit(PlayerCopy.PLATFORM_GAMES_RESTORED)
		if not restart and cloud != null: cloud.flush(true)
	else:
		link_state = LINK_ERROR
		link_code = str(answer.get("code", "failed"))
	changed.emit()
	return answer

## The player's choice when the account is linked to another identity: keep this phone's.
## The link moves here; the other identity stays on the server, reachable by its recovery code.
func keep_this_phone() -> void:
	if busy or not waiting_for_choice() or _account == null: return
	await _link(state.capability(), true)

## The other choice: use the linked identity. The flow shows this phone's recovery details first.
func use_linked_progress() -> void:
	if busy or link_state != LINK_CONFLICT or _account == null: return
	await _restore(state.capability(), true)

func unlink() -> void:
	if busy or not linked() or _links == null: return
	busy = true
	changed.emit()
	var answer: Dictionary = await _links.unlink(kind())
	busy = false
	if answer.get("ok", false):
		state.forget_link(kind())
		link_state = LINK_NONE
	else:
		link_code = str(answer.get("code", "failed"))
	changed.emit()

## After the identity is erased: the server already removed the link; forget it here too.
func forget_identity() -> void:
	if state != null:
		state.forget_link(kind())
		state.set_cloud({"dirty": true})
	link_state = LINK_NONE
	changed.emit()

# ---- Cloud save ------------------------------------------------------------------------------

func _cloud_allowed() -> bool:
	return cloud != null and signed_in() and offered() and linked()

## Progress may have changed (a chapter finished, Settings closed): sync after a quiet moment.
func note_progress() -> void:
	if _cloud_allowed(): cloud.note()

func _process(delta: float) -> void:
	_poll_left -= delta
	if _poll_left > 0.0: return
	_poll_left = 1.0
	if _cloud_allowed() and cloud.due(): cloud.poll()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and _cloud_allowed():
		cloud.flush()
		cloud.poll()

## Achievements and leaderboards are not used yet; these forward to the provider when they are.
func unlock_achievement(id: String) -> Dictionary:
	if provider == null: return {"ok": false, "code": "unavailable"}
	return await provider.unlock_achievement(id)

func submit_score(board: String, score: int) -> Dictionary:
	if provider == null: return {"ok": false, "code": "unavailable"}
	return await provider.submit_score(board, score)
