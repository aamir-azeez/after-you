extends Node
## PlatformGames: the one place After You talks to a platform games service (Play Games on
## Android, Game Center on iOS, none on desktop). Autoloaded as /root/PlatformGames; screens find
## it with PlatformGames.shared(tree) and never branch on the platform themselves.
##
## What it does, in order, all off the first frames and never in the way of play:
## 1. A few seconds after launch it learns whether the server offers the feature
##    (PLAY_GAMES_ENABLED / GAME_CENTER_ENABLED): the capability read once a day with an opt-in
##    header, or, on a phone with no identity yet, one cheap probe of the restore route. Until the
##    server offers it, the platform SDK is never touched (no sign-in banner, no start-up cost).
## 2. A quiet sign-in check (the platform signs in by itself).
## 3. It links the account to this phone's friend identity. On a phone that has no identity yet
##    (a reinstall, or a second phone), it checks whether the account has a friend code and asks
##    the player with one tap before bringing it back ("Not now" is not asked again this session;
##    Settings keeps a way to do it later). A phone that has its own identity and meets an account
##    linked elsewhere asks which to keep (platform_games_flow.gd).
## 4. Cloud save: progress is joined with a Saved Games slot after meaningful moments. It needs a
##    signed-in account and the server's offer, not a friend link, so solo players get it too.
## 5. The gamer name, for the name prompt only (name_offered, ensure_started, player_name): offered whenever the
##    server offers the platform and its account can be had, and signed in on the player's tap
##    when the quiet check did not (Play Games may want its own sheet on a phone).
## 6. Chapter times on the platform leaderboards (post_boards, show_board), while the server offers
##    them (PLATFORM_BOARDS, `boards` in the capability): platform_boards.gd decides what goes up,
##    platform_board_ids.gd says where, platform_board_store.gd remembers what went up per account.
##    It runs a few seconds after sign-in, a finished chapter (note_progress), the app coming back,
##    a board read or the name choice changing (services/leaderboard_client.gd LISTENERS); one post
##    at a time, every failure silent and tried again at the next of those moments.
## Every call is async with a timeout; every failure leaves the game as it was. Main is freed
## while a solo chapter is open: detach() abandons work that ran through Main, and the next
## attach() starts again from the top.
##
## Achievements: the provider interface has them, nothing uses them yet.
const GamesProvider = preload("res://services/platform_games/games_provider.gd")
const NativeProvider = preload("res://services/platform_games/native_games_provider.gd")
const LinkClient = preload("res://services/platform_games/platform_link_client.gd")
const State = preload("res://services/platform_games/platform_games_state.gd")
const CloudSync = preload("res://services/platform_games/cloud_save_sync.gd")
const NativeBridge = preload("res://services/native_bridge.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const BoardIds = preload("res://services/platform_games/platform_board_ids.gd")
## Loaded on first use, never with this autoload: they bring the chapter registry with them.
const BOARD_POLICY := "res://services/platform_games/platform_boards.gd"
const BOARD_STORE := "res://services/platform_games/platform_board_store.gd"
const LEADERBOARD_CLIENT := "res://services/leaderboard_client.gd"
const RUNS := "res://services/leaderboard_runs.gd"
## The group services/leaderboard_client.gd tells after a board read or a name choice (its LISTENERS).
const LEADERBOARD_LISTENERS := "leaderboard_listeners"

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
## The account has a friend code and this phone has none: waiting for the player's yes.
const LINK_OFFER := "offer"
const LINK_ERROR := "error"

## The first step waits this long after launch, so it never touches the first frames.
const START_DELAY_MS := 4000
## How long the service waits for Main to finish loading an identity before giving up for now.
const ACCOUNT_WAIT_MS := 60000
## A player who asked for the gamer name waits this long for a quiet check already under way
## (counted again once the check starts), and at most this long for the platform's sign-in
## sheet (each a little over the provider's own limit).
const NAME_CHECK_WAIT_MS := 16000
const NAME_SHEET_WAIT_MS := 125000
## Chapter times go up this long after the moment that asked, so they never meet a screen change.
const BOARD_POST_DELAY_S := 3.0
## After the platform's board screen opened, another tap does nothing for this long.
const BOARD_SHOW_GAP_MS := 1500

var provider: RefCounted
var sign_in := SignIn.UNAVAILABLE
## The last sign-in failure ("cancelled", "offline", ...), "" after a success.
var sign_in_code := ""
var link_state := LINK_NONE
var link_code := ""
## A link, unlink or restore request is in flight (Settings disables the row).
var busy := false
var state: RefCounted
var cloud: RefCounted
var _player_key := ""
var _account: RefCounted
var _links: RefCounted
var _poll_left := 1.0
var _autostart := true
## One start pipeline at a time.
var _running := false
## Bumped when work that ran through Main is abandoned (Main left): an older coroutine that
## wakes up later sees a different number and changes nothing.
var _generation := 0
## A pipeline was cut short by Main leaving; the next attach starts again.
var _interrupted := false
## The player said "Not now" to bringing a friend code back: not asked again this session.
var offer_declined := false
## A capability read outside the start pipeline is in flight (one at a time).
var _offer_reading := false
## Platform board posting: a pass is waiting for its delay, one is running, another was asked meanwhile.
var _boards_queued := false
var _boards_posting := false
var _boards_again := false
var _board_store: RefCounted
## The platform's board screen is opening (one at a time), and when it last opened.
var _board_showing := false
var _board_shown_at := -BOARD_SHOW_GAP_MS
var _board_store_path := "user://platform-boards-v1.json"

## The service, or null (a tree without the autoload, such as a tool script).
static func shared(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("PlatformGames") if tree != null else null

func _ready() -> void:
	set_process(false)
	add_to_group(LEADERBOARD_LISTENERS)
	# Desktop, headless suites and builds without the plugin: inert, no files, no network.
	# A phone build waits START_DELAY_MS before even asking the plugin, so the first frames pay nothing.
	if provider == null and _native_present() and _autostart: _start_later()
	elif provider != null and provider.available(): _prepare()

func _native_present() -> bool:
	return DisplayServer.get_name() != "headless" and NativeBridge.singleton("games") != null

func _prepare() -> void:
	if state == null: _open_state(State.PATH)
	if not provider.account_changed.is_connected(_on_account_changed): provider.account_changed.connect(_on_account_changed)

func _build_provider() -> RefCounted:
	var native := NativeBridge.singleton("games")
	if native == null or not native.has_signal("games_result"): return GamesProvider.new()
	return NativeProvider.new(native, GamesProvider.GAME_CENTER if PlatformSupport.is_ios() else GamesProvider.PLAY_GAMES, get_tree())

func _open_state(path: String) -> void:
	state = State.new(path)
	cloud = CloudSync.new(provider, null, state)
	cloud.description = PlayerCopy.PLATFORM_GAMES_SAVE_DESCRIPTION
	if _account != null: cloud.set_sources(_account.cloud_sources())

## Tests: a provider and a state file of their own (and a board file beside it), and no automatic start.
func configure(test_provider: RefCounted, state_path: String) -> void:
	_autostart = false
	_board_store_path = state_path.get_basename() + "-boards.json"
	_board_store = null
	provider = test_provider
	_open_state(state_path)
	if not provider.account_changed.is_connected(_on_account_changed): provider.account_changed.connect(_on_account_changed)

func _start_later() -> void:
	await get_tree().create_timer(START_DELAY_MS / 1000.0).timeout
	if provider == null: provider = _build_provider()
	if not provider.available(): return
	_prepare()
	changed.emit()
	await start()

## Offered? then quiet sign-in, link or restore, and a cloud pull. Safe to call again.
func start() -> void:
	if _running or provider == null or not provider.available() or state == null: return
	_running = true
	_interrupted = false
	var generation := _generation
	set_process(true)
	if await _wait_account() and generation == _generation:
		var capability := await _offer()
		if generation == _generation and capability.get(kind()) == true:
			await _authenticate(false, generation)
			if generation == _generation and signed_in(): await _after_sign_in(capability, generation)
	if generation == _generation:
		_running = false
		post_boards_soon()

# ---- Main's side ---------------------------------------------------------------------------

## Main hands over what the service needs from the app (see platform_games_flow.gd's account
## adapter): api, identity state, restore, cloud sources. Main is rebuilt after every solo chapter,
## so this is called on every Main start and detached when Main leaves.
func attach(account: RefCounted) -> void:
	_account = account
	_links = LinkClient.new(account.api())
	if cloud != null: cloud.set_sources(account.cloud_sources())
	changed.emit()
	if _interrupted: start.call_deferred()

func detach(account: RefCounted) -> void:
	if _account != account: return
	_account = null
	_links = null
	if cloud != null: cloud.set_sources(null)
	if _running or busy:
		# Requests that went through Main's api or secure store never answer now.
		_generation += 1
		_running = false
		_interrupted = true
		busy = false
		if link_state in [LINK_CHECKING, LINK_RESTORING]: link_state = LINK_NONE
		changed.emit()

# ---- What screens read ---------------------------------------------------------------------

func kind() -> String:
	return provider.kind() if provider != null else GamesProvider.NONE

## Whether the server offers this platform's service (and the platform exists here).
func offered() -> bool:
	if provider == null or not provider.available() or state == null: return false
	var held: Dictionary = state.capability()
	return held.get(kind()) == true

func signed_in() -> bool:
	return sign_in == SignIn.SIGNED_IN

## Whether the player's gamer name can be offered (the name prompt's "Use my Play Games name"):
## the server offers the platform and its account can be had, signed in, being checked, or one
## sign-in sheet away. Play Games often answers the quiet check "signed out" on a phone that
## needs its sheet, so a signed-out account still counts; a phone or build the platform refuses
## (unavailable, not configured) does not, and neither does Game Center once its sheet was
## turned down (Apple offers it once per launch).
func name_offered() -> bool:
	if not offered(): return false
	if sign_in != SignIn.SIGNED_OUT: return true
	if sign_in_code in ["unavailable", "not_configured"]: return false
	return not (kind() == GamesProvider.GAME_CENTER and sign_in_code == "cancelled")

## The signed-in account's one-way key ("" while signed out), so a screen holding that account's
## gamer name can tell when another account (or none) took its place.
func account_key() -> String:
	return _player_key if signed_in() else ""

## A screen that offers the platform opened (the name prompt): when this session never learned
## the server's offer (a launch read that failed or was cut short) or never ran the quiet check,
## try again now. The screen follows `changed`; nothing waits on this.
func ensure_started() -> void:
	if _running or busy or provider == null or not provider.available() or state == null or _account == null: return
	if signed_in():
		# Only the daily answer expired: read it again, as note_progress does.
		if state.capability().is_empty() and _account.identity_state() == "ready": await _refresh_offer()
		return
	if not state.capability().is_empty() and (not offered() or sign_in != SignIn.UNAVAILABLE): return
	await start()

func linked() -> bool:
	return link_state == LINK_LINKED

func waiting_for_choice() -> bool:
	return link_state in [LINK_CONFLICT, LINK_OTHER]

## A friend code is waiting to be brought back, and the player has not said "Not now" this session.
func offer_pending() -> bool:
	return link_state == LINK_OFFER and not offer_declined and not busy and _account != null and _account.identity_state() == "missing"

## The player's gamer name, read only now (the player picked "Use my Play Games name" or
## "Use my Game Center name"): {"ok", "name"} or a code. The player asked for it, so it signs in
## first when needed: a quiet check under way is waited for, and an account that is still
## signed out gets the platform's sign-in sheet once, only while `wanted` (the asking card is
## still open) holds.
func player_name(wanted: Callable = Callable()) -> Dictionary:
	if provider == null or not provider.available(): return {"ok": false, "code": "unavailable"}
	if not signed_in():
		var signed: Dictionary = await _sign_in_on_tap(wanted)
		if not signed.ok: return signed
	return await provider.player_name()

## A tap that needs the account (the gamer name, the platform's board screen) while signed out:
## waits for a quiet check under way, else shows the platform's sheet once, only while `wanted` holds.
func _sign_in_on_tap(wanted: Callable) -> Dictionary:
	if not name_offered(): return {"ok": false, "code": "unavailable"}
	await _wait_for_quiet_check()
	if signed_in(): return {"ok": true}
	# The card closed while the check ran: no sheet over a screen that no longer asks.
	if wanted.is_valid() and not wanted.call(): return {"ok": false, "code": "cancelled"}
	if _running or busy or not name_offered(): return {"ok": false, "code": "busy" if _running or busy else "unavailable"}
	# Not awaited: the sign-in's link and cloud steps go on after the name is read.
	sign_in_now()
	var deadline := Time.get_ticks_msec() + NAME_SHEET_WAIT_MS
	while is_inside_tree() and sign_in == SignIn.CHECKING and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	if signed_in(): return {"ok": true}
	return {"ok": false, "code": sign_in_code if not sign_in_code.is_empty() else "signed_out"}

## The launch's own pipeline (offer read, then the quiet check) or a sheet from Settings is under
## way: its answer comes first. The limit counts again from the moment the check itself starts,
## so a slow offer read never cuts a quiet check short.
func _wait_for_quiet_check() -> void:
	var deadline := Time.get_ticks_msec() + NAME_CHECK_WAIT_MS
	var checking := sign_in == SignIn.CHECKING
	while is_inside_tree() and not signed_in() and (sign_in == SignIn.CHECKING or _running) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
		if sign_in == SignIn.CHECKING and not checking:
			checking = true
			deadline = Time.get_ticks_msec() + NAME_CHECK_WAIT_MS

## The platform's name as players know it.
func display_name() -> String:
	return PlayerCopy.PLATFORM_GAMES_GAME_CENTER if kind() == GamesProvider.GAME_CENTER else PlayerCopy.PLATFORM_GAMES_PLAY_GAMES

## One short line for Settings.
func status_line() -> String:
	match sign_in:
		SignIn.UNAVAILABLE: return PlayerCopy.PLATFORM_GAMES_SIGNED_OUT if offered() else PlayerCopy.PLATFORM_GAMES_UNAVAILABLE
		SignIn.CHECKING: return PlayerCopy.PLATFORM_GAMES_CHECKING
		SignIn.SIGNED_OUT:
			if sign_in_code == "offline": return PlayerCopy.PLATFORM_GAMES_OFFLINE
			if sign_in_code in ["unavailable", "not_configured"]: return PlayerCopy.PLATFORM_GAMES_UNAVAILABLE
			return PlayerCopy.PLATFORM_GAMES_SIGNED_OUT
	match link_state:
		LINK_LINKED: return PlayerCopy.PLATFORM_GAMES_LINKED
		LINK_CONFLICT: return PlayerCopy.PLATFORM_GAMES_CONFLICT
		LINK_OTHER: return PlayerCopy.PLATFORM_GAMES_OTHER_ACCOUNT
		LINK_OFFER: return PlayerCopy.PLATFORM_GAMES_OFFER_NOTE
		LINK_CHECKING, LINK_RESTORING: return PlayerCopy.PLATFORM_GAMES_CHECKING
		LINK_ERROR: return PlayerCopy.PLATFORM_GAMES_OFFLINE if link_code == "offline" else PlayerCopy.PLATFORM_GAMES_TRY_LATER
	return PlayerCopy.PLATFORM_GAMES_SIGNED_IN

# ---- Offer -----------------------------------------------------------------------------------

func _wait_account() -> bool:
	var deadline := Time.get_ticks_msec() + ACCOUNT_WAIT_MS
	while is_inside_tree() and Time.get_ticks_msec() < deadline:
		if _account != null and _account.identity_state() != "busy": return true
		await get_tree().create_timer(0.5).timeout
	return false

## The server's offer: the capability with an identity, the restore probe without one.
func _offer() -> Dictionary:
	if _account == null: return {}
	match _account.identity_state():
		"ready": return await _capability()
		"missing": return await _probe()
	return {}

func _capability() -> Dictionary:
	var held: Dictionary = state.capability()
	if not held.is_empty() or _links == null: return held
	var answer: Dictionary = await _links.capability()
	if not answer.get("ok", false): return {}
	state.remember_capability(answer)
	changed.emit()
	return state.capability()

## No identity, so no capability read: the public restore route tells on from off without any
## platform proof (400 while on, 401 while off) and without a Durable Object request.
func _probe() -> Dictionary:
	var held: Dictionary = state.capability()
	if not held.is_empty() or _links == null: return held
	var on: Variant = await _links.restore_offered(kind())
	if not on is bool: return {}
	var answer := {"ok": true, "play_games": false, "game_center": false, "web_client_id": ""}
	answer[kind()] = on
	state.remember_capability(answer)
	changed.emit()
	return state.capability()

func _web_client_id(capability: Dictionary) -> String:
	var from_server := str(capability.get("web_client_id", ""))
	return from_server if not from_server.is_empty() else (_account.config_web_client_id() if _account != null else "")

func _credential(capability: Dictionary) -> Dictionary:
	return await provider.server_credential(_web_client_id(capability))

# ---- Sign-in ---------------------------------------------------------------------------------

## The Settings button: shows the platform's sign-in sheet.
func sign_in_now() -> void:
	if _running or busy or not offered(): return
	_running = true
	var generation := _generation
	await _authenticate(true, generation)
	if generation == _generation and signed_in(): await _after_sign_in(state.capability(), generation)
	if generation == _generation:
		_running = false
		post_boards_soon()

func _authenticate(interactive: bool, generation: int) -> void:
	sign_in = SignIn.CHECKING
	changed.emit()
	var answer: Dictionary = await provider.authenticate(interactive)
	if generation != _generation: return
	if answer.get("ok", false) and answer.get("signed_in", false):
		sign_in = SignIn.SIGNED_IN
		sign_in_code = ""
		_player_key = str(answer.player_key)
	else:
		sign_in = SignIn.SIGNED_OUT
		sign_in_code = "" if answer.get("ok", false) else str(answer.get("code", "failed"))
		# Game Center reports Apple's sheet turned down as a plain "not signed in"; Apple will not
		# show it again this launch, so it reads as cancelled (Play Games can show its sheet again).
		if interactive and sign_in_code.is_empty() and kind() == GamesProvider.GAME_CENTER: sign_in_code = "cancelled"
		_player_key = ""
		link_state = LINK_NONE
		if cloud != null: cloud.stop()
	changed.emit()

func _on_account_changed() -> void:
	# Another account signed in: nothing about the old one carries over.
	_player_key = ""
	link_state = LINK_NONE
	sign_in = SignIn.SIGNED_OUT
	offer_declined = false
	if cloud != null: cloud.stop()
	changed.emit()
	if not _running: await start()

# ---- Linking ---------------------------------------------------------------------------------

func _after_sign_in(capability: Dictionary, generation: int) -> void:
	if _account == null: return
	if _account.identity_state() == "missing":
		await _offer_for_new_phone(capability, generation)
		# Every launch pulls the account's saved games, before any chapter here is started.
		if generation == _generation and cloud != null: cloud.flush(true)
		return
	if _account.identity_state() != "ready": return
	await _reconcile_link(capability, generation)
	if generation == _generation and cloud != null: cloud.flush(true)

func _reconcile_link(capability: Dictionary, generation: int) -> void:
	var held: Dictionary = state.link(kind())
	if held.get("player_key") == _player_key and held.get("player_id") == _account.player_id():
		link_state = LINK_LINKED
		changed.emit()
		return
	if not held.is_empty(): state.forget_link(kind())
	await _link(capability, false, generation)

func _link(capability: Dictionary, replace: bool, generation: int) -> void:
	busy = true
	link_state = LINK_CHECKING
	changed.emit()
	var player: String = _account.player_id() if _account != null else ""
	var credential: Dictionary = await _credential(capability)
	if generation != _generation: return
	var answer: Dictionary = {"ok": false, "code": str(credential.get("code", "unavailable"))}
	if credential.get("ok", false) and _links != null and _account != null:
		answer = await _links.link(kind(), credential.credential, replace, _account.recovery_code())
		if generation != _generation: return
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
		# The server turned the feature off since the last capability read.
		state.forget_capability()
		link_state = LINK_NONE
		if cloud != null: cloud.stop()
	else:
		link_state = LINK_ERROR
		link_code = str(answer.get("code", "failed"))
	changed.emit()

## A phone with no friend identity yet: is this account linked to one? Then offer it (the player
## decides; see accept_offer). Uses the build's public web client id (no identity, so no capability
## read). "No link for this account" is remembered for a day.
func _offer_for_new_phone(capability: Dictionary, generation: int) -> void:
	if state.restore_probed(_player_key) or link_state == LINK_OFFER: return
	if kind() == GamesProvider.PLAY_GAMES and _web_client_id(capability).is_empty(): return
	busy = true
	link_state = LINK_CHECKING
	changed.emit()
	var credential: Dictionary = await _credential(capability)
	if generation != _generation: return
	var answer: Dictionary = {"ok": false, "code": str(credential.get("code", "unavailable"))}
	if credential.get("ok", false) and _links != null:
		answer = await _links.check_restore(kind(), credential.credential)
		if generation != _generation: return
	busy = false
	link_code = ""
	if answer.get("ok", false) and answer.linked:
		link_state = LINK_OFFER
		if _account == null: return
		if _account.identity_state() == "ready":
			# The player made a friend code meanwhile (opened Rooms): link it, never offer.
			link_state = LINK_NONE
			await _reconcile_link(capability, generation)
			return
		if await _account.has_pending_restore(kind()):
			# The player already said yes and the answer was lost: finish that restore.
			if generation == _generation:
				changed.emit()
				await accept_offer()
			return
	elif answer.get("ok", false) or int(answer.get("status", 0)) == 404:
		state.remember_restore_probe(_player_key)
		link_state = LINK_NONE
	else:
		link_state = LINK_ERROR
		link_code = str(answer.get("code", "failed"))
	changed.emit()

## The player's yes ("Use it", in the prompt or Settings): bring the linked friend code to this
## phone. Only this rotates the tokens. A phone that made its own identity meanwhile links instead,
## which leads to the usual "which friend code should stay" choice.
func accept_offer() -> void:
	if busy or link_state != LINK_OFFER or _account == null: return
	var generation := _generation
	var capability: Dictionary = state.capability()
	match _account.identity_state():
		"ready":
			link_state = LINK_NONE
			await _after_sign_in(capability, generation)
			return
		"missing": pass
		_:
			# A friend code is being made or read right now: keep the offer for a moment later.
			notice.emit(PlayerCopy.PLATFORM_GAMES_TRY_LATER)
			return
	var answer := await _restore(capability, false, generation)
	if generation != _generation: return
	if answer.get("ok", false):
		# The identity is ready now: read the real capability, then pull the cloud copy.
		state.forget_capability()
		await _capability()
		if generation == _generation and cloud != null: cloud.flush(true)
	elif int(answer.get("status", 0)) == 404:
		# The link went away meanwhile (unlinked or erased on the other phone).
		state.remember_restore_probe(_player_key)
		link_state = LINK_NONE
		notice.emit(PlayerCopy.PLATFORM_GAMES_NO_LINK)
		changed.emit()

## Settings' Link / Try again: start over, and check this account again even if it had no
## friend code earlier today (one may have been linked since).
func retry() -> void:
	if _running or busy: return
	if state != null and not state.data.restore_probe.is_empty():
		state.data.restore_probe = {}
		state.save()
	if link_state in [LINK_ERROR, LINK_NONE]: link_state = LINK_NONE
	await start()

## "Not now": this phone stays a fresh install, and nothing asks again until the next launch.
func decline_offer() -> void:
	if link_state != LINK_OFFER: return
	offer_declined = true
	changed.emit()

func _restore(capability: Dictionary, restart: bool, generation: int) -> Dictionary:
	busy = true
	link_state = LINK_RESTORING
	changed.emit()
	var account := _account
	var get_credential := func() -> Dictionary: return await _credential(capability)
	var answer: Dictionary = await account.restore_identity(kind(), get_credential, restart)
	if generation != _generation: return {"ok": false, "code": "abandoned"}
	busy = false
	if answer.get("ok", false):
		state.remember_link(kind(), _player_key, str(answer.player_id))
		link_state = LINK_LINKED
		notice.emit(PlayerCopy.PLATFORM_GAMES_RESTORED)
	else:
		link_state = LINK_ERROR
		link_code = str(answer.get("code", "failed"))
	changed.emit()
	return answer

## The player's choice when the account is linked to another identity: keep this phone's.
## The link moves here; the other identity stays on the server, reachable by its recovery code.
func keep_this_phone() -> void:
	if busy or not waiting_for_choice() or _account == null: return
	await _link(state.capability(), true, _generation)

## The other choice: use the linked identity. The flow asks for this phone's recovery details first.
func use_linked_progress() -> void:
	if busy or link_state != LINK_CONFLICT or _account == null: return
	await _restore(state.capability(), true, _generation)

func unlink() -> void:
	if busy or not linked() or _links == null: return
	busy = true
	changed.emit()
	var generation := _generation
	var answer: Dictionary = await _links.unlink(kind())
	if generation != _generation: return
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
	return cloud != null and signed_in() and offered()

## Progress may have changed (a chapter finished, Settings closed): sync after a quiet moment.
func note_progress() -> void:
	if _cloud_allowed(): cloud.note()
	elif signed_in() and state != null and state.capability().is_empty() and not _running and _account != null and _account.identity_state() == "ready":
		# The daily answer expired in a long session: ask again, then sync.
		_refresh_offer.call_deferred()

func _refresh_offer() -> void:
	if _offer_reading: return
	_offer_reading = true
	await _capability()
	_offer_reading = false
	if _cloud_allowed(): cloud.note()

func _process(delta: float) -> void:
	_poll_left -= delta
	if _poll_left > 0.0: return
	_poll_left = 1.0
	if _cloud_allowed() and cloud.due(): cloud.poll()

func _notification(what: int) -> void:
	# The run itself waits for frames, so it finishes on resume; the dirty flag also survives a kill.
	if what == NOTIFICATION_APPLICATION_PAUSED and _cloud_allowed(): cloud.flush()
	elif what == NOTIFICATION_APPLICATION_RESUMED: post_boards_soon()

## Achievements are not used yet; this forwards to the provider when they are.
func unlock_achievement(id: String) -> Dictionary:
	if provider == null: return {"ok": false, "code": "unavailable"}
	return await provider.unlock_achievement(id)

# ---- Chapter times on the platform leaderboards ----------------------------------------------

## Whether the server offers the platform boards (PLATFORM_BOARDS) beside this platform.
func boards_offered() -> bool:
	return offered() and state.capability().get("boards") == true

## Whether the leaderboard screen shows the "Google Play Games" / "Game Center" button for our
## board `board`: the boards are offered, the platform has that board, and its account can be
## had (signed in, or one sign-in sheet away; name_offered's rule).
func board_offered(board: String) -> bool:
	return boards_offered() and name_offered() and not BoardIds.id(board, kind()).is_empty()

## The platform's board screen is opening or just opened (the button waits).
func board_showing() -> bool:
	return _board_showing or Time.get_ticks_msec() - _board_shown_at < BOARD_SHOW_GAP_MS

## The button's tap: the platform's own screen of our board `board`, signing in first when needed.
## One at a time; every failure leaves the screen as it was. {"ok"} or a code.
func show_board(board: String, wanted: Callable = Callable()) -> Dictionary:
	if board_showing(): return {"ok": false, "code": "busy"}
	if not board_offered(board): return {"ok": false, "code": "unavailable"}
	_board_showing = true
	changed.emit()
	var answer: Dictionary = {"ok": true}
	if not signed_in(): answer = await _sign_in_on_tap(wanted)
	if answer.get("ok", false):
		answer = await provider.show_board(BoardIds.id(board, kind()))
		if answer.get("ok", false): _board_shown_at = Time.get_ticks_msec()
	_board_showing = false
	changed.emit()
	return answer

## services/leaderboard_client.gd read a board or changed the name choice for `owner`.
func leaderboard_changed(owner: String) -> void:
	if _account != null and owner == _account.player_id(): post_boards_soon()

## Posts what is owed a few seconds from now; repeated asks meanwhile make one pass.
func post_boards_soon() -> void:
	if _boards_queued or not boards_offered() or not is_inside_tree(): return
	_boards_queued = true
	await get_tree().create_timer(BOARD_POST_DELAY_S).timeout
	_boards_queued = false
	await post_boards()

## One pass: this player's runs judged against the boards this phone read, kept, and each board's
## new best posted while signed in and the player shows their name on leaderboards. One post at a
## time; a pass asked for while one runs follows it.
func post_boards() -> void:
	if _boards_posting:
		_boards_again = true
		return
	_boards_posting = true
	await _post_boards_once()
	while _boards_again and is_inside_tree():
		_boards_again = false
		await _post_boards_once()
	_boards_posting = false

func _post_boards_once() -> void:
	if not boards_offered() or _account == null or _account.identity_state() != "ready": return
	var owner: String = _account.player_id()
	if owner.is_empty(): return
	var policy: Script = load(BOARD_POLICY)
	var runs: Array = load(RUNS).runs_of(owner)
	var store := _boards_store()
	var verdicts: Dictionary = policy.judge(runs, load(LEADERBOARD_CLIENT).kept_for(owner), store.judged, Time.get_unix_time_from_system())
	store.keep_verdicts(verdicts)
	if not signed_in() or not load(LEADERBOARD_CLIENT).name_shown(owner): return
	var generation := _generation
	var platform := kind()
	var account: String = store.account(platform, _player_key)
	var due: Dictionary = policy.due(runs, verdicts, BoardIds.boards(platform), store.posted_for(account))
	var boards: Array = due.keys()
	boards.sort()
	for board: String in boards:
		# Main left, the account changed or signed out: the rest waits for the next moment.
		if generation != _generation or not signed_in() or store.account(kind(), _player_key) != account or _account == null: return
		var answer: Dictionary = await provider.submit_score(BoardIds.id(board, platform), policy.score(platform, int(due[board])))
		if answer.get("ok", false): store.remember_posted(account, board, int(due[board]))
		elif str(answer.get("code", "")) in ["signed_out", "offline", "unavailable", "not_configured", "timeout"]: return

func _boards_store() -> RefCounted:
	if _board_store == null: _board_store = load(BOARD_STORE).new(_board_store_path)
	return _board_store
