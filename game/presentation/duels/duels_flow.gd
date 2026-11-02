extends Node
## Duels and their glue: the lobby (duels_screen.gd) and the pages over it
## (party, start a duel, race a recorded run, a duel, a result), every request
## through services/duels_client.gd, and Play, which hands the pair's room to
## the room flow like any room: it opens your pair's room, joins the one your
## partner made, or makes it (relay_lobby_flow.gd "duel"). When both of you
## made one at once, the server keeps the first and this phone joins it.
##
## Every duel entry hides while the server says duels are off
## (relay_online_session.gd duels_supported): Home's row, the lobby, the Duel
## tag in Your rooms.
##
## Main hosts it as a child and reads it through is_open(), close(),
## offer(menu) and room_kind(). A duel's clear needs nothing here: its room is
## an ordinary room, so the chapter chain already counts it as a finished room. It reads Main only through
## this host contract (read at call time):
## - services: api, config, relay_session, ensure_relay_session,
##   _friends_client, _friend_display_name
## - screen: mode, ui, application_backgrounded, _toast, _online_gated,
##   _relay_available, _ensure_identity
## - chapters: _chapter_unlocks, _full_journey_access, _paid_content_hidden
## - rooms: relay_lobby_flow (open_lobby, lobby_action, join_room)
## - node: add_child
## - sound: soundscape when Main has it (play_fixed_cue), for a won result's bell, once per duel
## - live: live_connection when Main has it (duels_changed, missed_hints, healthy)
##
## Reads on their own (services/refresh_schedule.gd keeps the pace): the lobby
## once a minute while a challenge or running duel can change without this
## player, an open duel every 30 s (a ghost race waiting for its check once a
## minute). Nothing reads while the app is in the background or has lost focus,
## or while the lobby is hidden (the other pair's run playing over it); coming
## back reads the screen in front once, at once. Opening, a page closing and
## this player's own actions read at once. A failed read keeps the same pace.
##
## Hints (services/live_connection.gd duels_changed): while the live socket is
## healthy and the latest duel read said the server sends hints (duel_hints_version), a
## change reads only the screen it touches, once however many arrive, and the
## timed reads drop to a backup pace (DUELS_LOBBY_BACKUP_MS, DUEL_BACKUP_MS).
## A hint for the open duel reads that duel; any other reads the lobby, unless
## a page other than Party is over it (closing that page reads it anyway). A
## socket that comes back after dropping reads both once (missed_hints), and
## the moment it drops the pace goes back to the one above.
const DuelsScreen = preload("res://presentation/duels/duels_screen.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const ResultPage = preload("res://presentation/duels/duel_result_page.gd")
const PartyPage = preload("res://presentation/duels/duel_party_page.gd")
const ChallengePage = preload("res://presentation/duels/duel_challenge_page.gd")
const GhostPage = preload("res://presentation/duels/duel_ghost_page.gd")
const DuelsClient = preload("res://services/duels_client.gd")
const DuelModel = preload("res://services/duel_model.gd")
const PollenBreakdown = preload("res://presentation/pollen_breakdown.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SharedReplayLaunch = preload("res://presentation/shared_replay_launch.gd")
const Soundscape = preload("res://services/soundscape.gd")
const RefreshClock = preload("res://services/refresh_schedule.gd")
## Main's mode while Duels is up.
const MODE_DUELS := "duels"

signal home_requested

var host: Node
var screen: CanvasLayer
## The lobby's and the open duel page's reads, one at a time each.
var _lobby_reads := RefreshClock.new()
var _duel_reads := RefreshClock.new()
## A lobby read was asked for (open, a page closed, an own action): it runs
## even when nothing on the lobby waits on others or a page is over it.
var _lobby_asked := false
## False while the app is paused or has lost focus.
var _in_front := true
## True for the moment a page closes right after a fresh lobby read (_already_open): that close reads nothing more.
var _lobby_fresh := false
## True while the other pair's run is fetched for one tap.
var _their_loading := false
## The idempotency key of each challenge or ghost race sent with no answer yet,
## by what it asked for. A tap again sends the same key, so after a reply lost
## on the way the server answers the duel the first tap made, never a second one.
## A server's answer (a duel, or a refusal) settles it; the next tap is a new duel.
var _unanswered: Dictionary = {}

func _init(main: Node = null) -> void:
	host = main

func _ready() -> void:
	set_process(is_open())
	var live: Node = host.get("live_connection") if host != null else null
	if not is_instance_valid(live): return
	live.duels_changed.connect(_hinted)
	live.missed_hints.connect(_caught_up)

## Whether duel changes reach this phone as hints now: a healthy socket to a server that sends them.
func _hints_live() -> bool:
	var live: Node = host.get("live_connection")
	return is_instance_valid(live) and live.healthy() and client().hints_sent()

## A duel this player is in changed at `at_ms` (`duel_id` empty: the party or the list of duels).
## The read starts on the next frame, so hints arriving together read once.
func _hinted(duel_id: String, at_ms: int) -> void:
	if not _reading(): return
	var now := Time.get_ticks_msec()
	var page := _bind(now)
	if page != null and page.view.duel_id == duel_id:
		if int(page.view.get("updated_ms", 0)) < at_ms: _duel_reads.hint(now)
		return
	if not duel_id.is_empty() and _lobby_holds(duel_id, at_ms): return
	_ask_lobby(now)

## Hints were lost while the socket was down since `since_ms`: each screen in front reads once, unless a read begun after that covers it.
func _caught_up(since_ms: int) -> void:
	if not _reading(): return
	var now := Time.get_ticks_msec()
	_bind(now)
	_duel_reads.hint(now, since_ms)
	_ask_lobby(now, since_ms)

## One lobby read for a hint, while nothing but Party is over it (closing any other page reads it anyway).
func _ask_lobby(now: int, covered_since: int = -1) -> void:
	var overlay: CanvasLayer = screen.overlay()
	if overlay != null and not overlay is PartyPage: return
	if _lobby_reads.hint(now, covered_since): _lobby_asked = true

## Whether the kept lobby already has `duel_id` as of `at_ms` or later.
func _lobby_holds(duel_id: String, at_ms: int) -> bool:
	for view: Dictionary in client().last_lobby().get("duels", []):
		if view.duel_id == duel_id: return int(view.updated_ms) >= at_ms
	return false

func _process(_delta: float) -> void:
	_tick(Time.get_ticks_msec())

## Starts the lobby's or the open duel's read when it is due and may run.
func _tick(now: int) -> void:
	if not _reading():
		_lobby_reads.bind("", now)
		_duel_reads.bind("", now)
		set_process(false)
		return
	var page := _bind(now)
	var shown: bool = _in_front and not host.application_backgrounded and screen.visible
	if page != null:
		var duel_ticket: Dictionary = _duel_reads.begin_if_due(now, shown and page.visible, false)
		if not duel_ticket.is_empty(): _read_duel(page, duel_ticket)
	# Whether the lobby waits on others is looked at only once its read is due.
	var wanted: bool = _lobby_asked or (now >= _lobby_reads.next_due_ms() and not _lobby_reads.busy() and screen.overlay() == null and screen.wants_refresh())
	var lobby_ticket: Dictionary = _lobby_reads.begin_if_due(now, shown and wanted, false)
	if not lobby_ticket.is_empty(): _read_lobby(lobby_ticket)

## Binds both clocks to what is open now and returns the duel page being read, or null.
func _bind(now: int) -> CanvasLayer:
	var hinted := _hints_live()
	_lobby_reads.bind("lobby/%d" % screen.get_instance_id(), now, RefreshClock.DUELS_LOBBY_BACKUP_MS if hinted else RefreshClock.DUELS_LOBBY_INTERVAL_MS)
	var page: CanvasLayer = screen.overlay()
	if not page is DuelPage or not page.alive() or page.view.is_empty():
		_duel_reads.bind("", now)
		return null
	_duel_reads.bind("duel/%d/%s" % [page.get_instance_id(), page.view.duel_id], now, refresh_ms(page.view, hinted))
	return page

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_in_front = false
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN] and not _in_front:
		# Android sends more than one of these: only the first after a pause reads, once.
		_in_front = true
		if not _reading(): return
		var now := Time.get_ticks_msec()
		_bind(now)
		_duel_reads.request_now(now)
		_lobby_reads.request_now(now)
		_tick(now)

func is_open() -> bool:
	return is_instance_valid(screen) and not screen.is_queued_for_deletion()

## Shows Home's row when the capabilities this session already read say duels
## are on. Home asks the server nothing for it: the next Home after any online
## screen read them shows the row.
func offer(menu: Control) -> void:
	if menu != null and is_instance_valid(menu) and menu.has_method("show_duels"): menu.show_duels(supported())

func supported() -> bool:
	return host.relay_session != null and host.relay_session.duels_supported()

func client() -> RefCounted:
	return DuelsClient.shared(host.api, str(host.api.player_id))

## The room's duel kind ("friend", "ghost") for the Duel tag, or "" (also while duels are off).
func room_kind(room_id: String) -> String:
	return client().room_kind(room_id) if supported() else ""

## The lobby, full screen over Home.
func open() -> void:
	if is_open() or not supported(): return
	host.mode = MODE_DUELS
	host.ui.visible = false
	screen = DuelsScreen.new()
	screen.me = str(host.api.player_id)
	screen.name_of = _name_of
	screen.boost_percent = PollenBreakdown.BOOST_PERCENT_EACH if host._full_journey_access() and _surfaces().full_journey_visible() else 0
	screen.closed.connect(_left)
	screen.notice.connect(func(text: String, _news: bool) -> void: host._toast(text))
	screen.start_requested.connect(_open_challenge)
	screen.party_requested.connect(_open_party)
	screen.ghosts_requested.connect(_open_ghosts)
	screen.duel_action.connect(_on_duel_action)
	screen.refresh_requested.connect(_refresh)
	host.add_child(screen)
	var kept: Dictionary = client().last_lobby()
	if not kept.is_empty(): screen.show_lobby(kept)
	set_process(true)
	_refresh()

## Closes Duels for a screen Main shows instead; Main sets its mode first.
func close() -> void:
	if not is_open(): return
	var page := screen
	screen = null
	page.close()

func _left() -> void:
	screen = null
	_unanswered.clear()
	if host.mode == MODE_DUELS:
		host.ui.visible = true
		home_requested.emit()

## Whether a lobby this flow opened is up, so its reads may run.
func _reading() -> bool:
	return is_open() and screen is DuelsScreen

## Reads the lobby at once; a read already out, which may predate an action, is followed by one more.
func _refresh() -> void:
	if not _reading() or _lobby_fresh: return
	var now := Time.get_ticks_msec()
	_bind(now)
	_lobby_asked = true
	_lobby_reads.hint(now)
	_tick(now)

func _read_lobby(ticket: Dictionary) -> void:
	_lobby_asked = false
	var answer: Dictionary = await client().lobby()
	# A failed read waits the same minute: the schedule's quicker failure retries would cost more.
	_lobby_reads.complete(ticket, Time.get_ticks_msec(), true)
	if not is_open(): return
	screen.show_lobby(answer.get("lobby", {}), not answer.get("ok", false))
	var overlay: CanvasLayer = screen.overlay()
	if answer.get("ok", false) and overlay is PartyPage: overlay.show_party(answer.lobby.party)

## A player's name for the duel pages: "You", a friend's or partner's name, or "".
func _name_of(id: Variant) -> String:
	if id == null: return ""
	if str(id) == str(host.api.player_id): return PlayerCopy.DUEL_YOU
	return FriendNicknames.sentence_start(host._friend_display_name(str(id)))

func _surfaces() -> RefCounted:
	return PollenSurfaces.for_configuration(host.config)

## Accepted friends: [{id, name}], read again when the list was never read.
func _friends(except: Variant = null) -> Array:
	var friends_client: RefCounted = host._friends_client(true)
	if friends_client == null: return []
	if friends_client.view().is_empty(): await friends_client.refresh()
	var result: Array = []
	for row: Dictionary in friends_client.view().get("friends", []):
		if row.get("status") != "accepted" or row.player_id == except: continue
		result.append({"id": row.player_id, "name": _name_of(row.player_id)})
	return result

## Chapters open to this player that have a board, in the Chapters order.
func _open_chapters() -> Array:
	var state: Dictionary = host._chapter_unlocks()
	var result: Array = []
	for key: String in ChapterUnlocks.chain():
		if Runs.board_key(key).is_empty() or not ChapterUnlocks.open(key, state): continue
		if host._paid_content_hidden() and bool(Registry.descriptor(key).get("premium", false)): continue
		result.append(key)
	return result

func _toast_failure(answer: Dictionary) -> void:
	var code := str(answer.get("code", ""))
	host._toast(PlayerCopy.DUELS_LIMIT if code == "duel_limit_reached" else PlayerCopy.DUELS_FRIEND_NO_PARTNER if code == "opponent_party_required" else PlayerCopy.DUELS_NO_PARTY if code == "party_required" else PlayerCopy.DUELS_ACTION_FAILED)

func _open_party() -> void:
	if not is_open(): return
	var page := PartyPage.new()
	page.name_of = _name_of
	page.show_boost = _surfaces().full_journey_visible()
	page.party = client().last_lobby().get("party", {})
	page.party_action.connect(func(action: String, friend: String, control: Control) -> void: page.tap(control, func() -> void: await _party(page, action, friend)))
	screen.open_overlay(page)
	var friends := await _friends()
	# Back may close the page while the friends list loads.
	if is_instance_valid(page): page.set_friends(friends)

func _party(page: CanvasLayer, action: String, friend: String) -> void:
	var duels: RefCounted = client()
	var answer: Dictionary
	match action:
		"invite": answer = await duels.invite(friend)
		"accept": answer = await duels.accept_party(friend)
		"dismiss": answer = await duels.dismiss_party(friend)
		"cancel": answer = await duels.cancel_invite()
		_: answer = await duels.leave_party()
	if not is_instance_valid(page): return
	if answer.get("ok", false):
		page.show_party(answer.lobby.party)
		if is_open(): screen.show_lobby(answer.lobby)
	else: _toast_failure(answer)

func _open_challenge() -> void:
	if not is_open(): return
	var page := ChallengePage.new()
	page.chapters = _open_chapters()
	var partner: Variant = client().last_lobby().get("party", {}).get("partner")
	page.send_requested.connect(func(friend: String, chapter: String, control: Control) -> void: page.tap(control, func() -> void: await _challenge(page, friend, chapter)))
	screen.open_overlay(page)
	var friends := await _friends(partner)
	if not is_instance_valid(page): return
	page.friends = friends
	if page.is_inside_tree(): page._render()

func _challenge(page: CanvasLayer, friend: String, chapter: String) -> void:
	var board := Runs.board_key(chapter)
	var answer: Dictionary = await _send_once("challenge|%s|%s" % [friend, board], func(key: String) -> Dictionary: return await client().challenge(friend, board, key))
	if not is_instance_valid(page): return
	if answer.get("code") == "duel_already_open":
		await _already_open(page, friend, board)
		return
	if not answer.get("ok", false):
		_toast_failure(answer)
		return
	host._toast(PlayerCopy.DUELS_SENT)
	page.close()

## The server already has a friend duel between the two pairs on `board`: a
## fresh lobby finds it. A running one opens; one still waiting for an answer
## shows on the lobby, with a short line saying why. Not found: only the line.
func _already_open(page: CanvasLayer, friend: String, board: String) -> void:
	var answer: Dictionary = await client().lobby()
	if not is_open(): return
	if answer.get("ok", false): screen.show_lobby(answer.lobby)
	var found := _open_with(friend, board)
	if not is_instance_valid(page): return
	if found.is_empty():
		host._toast(PlayerCopy.DUELS_ALREADY_OPEN)
		return
	# The lobby was just read: closing the page reads it no second time.
	_lobby_fresh = true
	page.close()
	_lobby_fresh = false
	if found.status == "running": _open_duel(found)
	else: host._toast(PlayerCopy.DUELS_ALREADY_OPEN)

## The open friend duel on `board` whose other pair has `friend`, from the kept lobby, or {}.
func _open_with(friend: String, board: String) -> Dictionary:
	for view: Dictionary in client().last_lobby().get("duels", []):
		var other: Variant = view.sides[1 - int(view.mine)]
		if view.kind == "friend" and view.board == board and view.status in ["challenged", "running"] and other is Dictionary and friend in other.members: return view
	return {}

## Sends `request` with the key kept for `asked` (_unanswered), made on its
## first tap, and drops that key once the server answers it.
func _send_once(asked: String, request: Callable) -> Dictionary:
	if not _unanswered.has(asked): _unanswered[asked] = DuelsClient.new_key()
	var answer: Dictionary = await request.call(_unanswered[asked])
	var status := int(answer.get("status", 0))
	if answer.get("ok", false) or (status >= 400 and status < 500): _unanswered.erase(asked)
	return answer

func _open_ghosts() -> void:
	if not is_open(): return
	var page := GhostPage.new()
	page.chapters = _open_chapters()
	page.race_requested.connect(func(chapter: String, source: String, entry_id: Variant, control: Control) -> void: page.tap(control, func() -> void: await _race(page, chapter, source, entry_id)))
	screen.open_overlay(page)
	var answer: Dictionary = await client().ghosts()
	if is_instance_valid(page): page.show_ghosts(answer.get("boards", []), not answer.get("ok", false))

func _race(page: CanvasLayer, chapter: String, source: String, entry_id: Variant) -> void:
	var board := Runs.board_key(chapter)
	var answer: Dictionary = await _send_once("ghost|%s|%s|%s" % [board, source, entry_id], func(key: String) -> Dictionary: return await client().race_ghost(board, source, entry_id, key))
	if not is_instance_valid(page): return
	if not answer.get("ok", false):
		_toast_failure(answer)
		return
	page.close()
	_open_duel(answer.duel)

func _on_duel_action(view: Dictionary, action: String, control: Control) -> void:
	if not is_open(): return
	match action:
		"accept", "decline":
			if action == "accept" and not ChapterUnlocks.open(view.chapter, host._chapter_unlocks()):
				host._toast(PlayerCopy.DUELS_CHAPTER_CLOSED)
				return
			screen.tap(control, func() -> void:
				var answer: Dictionary = await client().act(view.board, view.duel_id, action)
				if not answer.get("ok", false): _toast_failure(answer)
				_refresh())
		"play": screen.tap(control, func() -> void: await _play(_latest(view)))
		"result": _open_result(view)
		_: _open_duel(view)

## The newest copy of a duel this phone has.
func _latest(view: Dictionary) -> Dictionary:
	for item: Dictionary in client().last_lobby().get("duels", []):
		if item.duel_id == view.duel_id: return item
	return view

func _open_duel(view: Dictionary) -> void:
	if not is_open(): return
	var page := DuelPage.new()
	page.me = str(host.api.player_id)
	page.name_of = _name_of
	page.view = view
	page.play_requested.connect(func(next: Dictionary, control: Control) -> void: _play(next))
	page.leave_requested.connect(func(next: Dictionary) -> void:
		var answer: Dictionary = await client().act(next.board, next.duel_id, "leave")
		if not answer.get("ok", false):
			_toast_failure(answer)
			return
		# The lobby under the page shows the duel as left too (services/duels_client.gd keeps the answer).
		if is_open(): screen.show_lobby(client().last_lobby())
		_show_duel(page, answer.duel))
	screen.open_overlay(page)
	# The phone's room may be ahead of the duel (a lost note): ask the server to look once.
	var own: Dictionary = view.sides[view.mine]
	if view.status == "running" and not own.finished and not str(own.get("room_id", "")).is_empty():
		var synced: Dictionary = await client().act(view.board, view.duel_id, "sync")
		if synced.get("ok", false): _show_duel(page, synced.duel)

## One timed read of the open duel; a result swaps in the result page.
func _read_duel(page: CanvasLayer, ticket: Dictionary) -> void:
	var answer: Dictionary = await client().duel(page.view.board, page.view.duel_id)
	# A failed read waits the same pace, as the lobby's does.
	_duel_reads.complete(ticket, Time.get_ticks_msec(), true)
	if answer.get("ok", false): _show_duel(page, answer.duel)

## A newer copy of the open duel, from a read or this player's own action
## (Leave shows at once): a running duel redraws its page, an ended one swaps in
## the result page. A copy older than the page's, such as a read that went out
## before Leave, changes nothing.
func _show_duel(page: CanvasLayer, duel: Dictionary) -> void:
	if not is_instance_valid(page) or not page.alive() or int(duel.updated_ms) < int(page.view.get("updated_ms", 0)): return
	if duel.status == "running":
		page.show_duel(duel)
	else:
		page.close()
		_open_result(duel)

## How often an open duel reads again: DUEL_BACKUP_MS while hints come (`hinted`, the check result is one),
## else DUEL_CHECK_INTERVAL_MS while your ghost race run waits for its check, else DUEL_INTERVAL_MS.
static func refresh_ms(view: Dictionary, hinted: bool = false) -> int:
	if hinted: return RefreshClock.DUEL_BACKUP_MS
	var waiting: bool = view.kind == "ghost" and view.sides[view.mine].check == "waiting"
	return RefreshClock.DUEL_CHECK_INTERVAL_MS if waiting else RefreshClock.DUEL_INTERVAL_MS

func _open_result(view: Dictionary) -> void:
	if not is_open(): return
	var page := ResultPage.new()
	page.me = str(host.api.player_id)
	page.name_of = _name_of
	page.show_boost = _surfaces().full_journey_visible()
	page.show_pollen = _surfaces().earning_visible() and host.relay_session != null and host.relay_session.pollen_supported()
	page.view = view
	page.watch_requested.connect(func(next: Dictionary, control: Control) -> void: _play(next))
	page.their_run_requested.connect(func(next: Dictionary, _control: Control) -> void: _watch_theirs(page, next))
	screen.open_overlay(page)
	var answer: Dictionary = await client().duel(view.board, view.duel_id)
	if not is_instance_valid(page) or not answer.get("ok", false): return
	page.show_result(answer.duel, answer.get("pay", {}), answer.get("win_bonus", {}))
	# A win rings once, the first time its result opens on this phone, as a leaderboard celebration shows once.
	var cue := DuelModel.result_cue(answer.duel)
	if cue.is_empty() or not client().bell_due(answer.duel): return
	client().mark_rung(str(answer.duel.duel_id))
	Soundscape.play_on(host, cue)

## Plays the other pair's run in the shared replay viewer, from this phone's
## copy or fetched once (services/duels_client.gd their_run); the result page
## hides while it plays and comes back as it was. One tap at a time.
func _watch_theirs(page: Node, view: Dictionary) -> void:
	if _their_loading or not is_open() or host.application_backgrounded or is_instance_valid(host.shared_replay_child): return
	_their_loading = true
	host._toast(PlayerCopy.DUEL_THEIRS_LOADING)
	var chapter := _chapter_key(view)
	var answer: Dictionary = await client().their_run(view, chapter)
	_their_loading = false
	if not is_open() or not is_instance_valid(page) or host.application_backgrounded or is_instance_valid(host.shared_replay_child): return
	if not answer.get("ok", false):
		host._toast(PlayerCopy.DUEL_THEIRS_GONE if answer.get("code") == "their_run_gone" else PlayerCopy.DUEL_THEIRS_FAILED)
		return
	var replay := SharedReplayLaunch.make(host, answer.parts)
	replay.leaderboard_chapter = chapter
	replay.closed.connect(func() -> void:
		if host.shared_replay_child != replay: return
		SharedReplayLaunch.close(host)
		if is_open(): screen.visible = true
		if is_instance_valid(page): page.visible = true)
	# The lobby and the result page each draw on their own layer: both step aside while it plays.
	screen.visible = false
	page.visible = false
	SharedReplayLaunch.show(host, replay)

## Opens the pair's room: your own, the one your partner made (joined), or a
## new one made for the duel. Duels closes first; the room flow takes over.
func _play(view: Dictionary) -> void:
	if not is_open() or host.application_backgrounded: return
	if not ChapterUnlocks.open(view.chapter, host._chapter_unlocks()):
		host._toast(PlayerCopy.DUELS_CHAPTER_CLOSED)
		return
	var own: Dictionary = view.sides[view.mine]
	var chapter := _chapter_key(view)
	host.mode = "relay_rooms"
	close()
	host.ui.visible = true
	if not str(own.get("room_id", "")).is_empty() and own.get("hosting", false):
		if await host.relay_lobby_flow.open_lobby(chapter): await host.relay_lobby_flow.lobby_action("open", own.room_id)
		return
	if not str(own.get("invite_code", "")).is_empty():
		await host.relay_lobby_flow.join_room(own.invite_code)
		# A room your partner claimed but never made: make it here instead (the server lets the claim pass after a while).
		if host.relay_session == null or not host.relay_session.last_lobby_code in ["invite_not_found", "room_deleted"]: return
	if not await host.relay_lobby_flow.open_lobby(chapter): return
	await host.relay_lobby_flow.lobby_action("duel", chapter, false, {"duel_id": view.duel_id, "board": view.board})
	if host.relay_session != null and host.relay_session.last_lobby_code == "duel_room_taken":
		# Your partner's room came first: join it.
		var fresh: Dictionary = await client().duel(view.board, view.duel_id)
		var invite := str(fresh.get("duel", {}).get("sides", [{}, {}])[view.mine].get("invite_code", "")) if fresh.get("ok", false) else ""
		if not invite.is_empty(): await host.relay_lobby_flow.join_room(invite)

## The bundled chapter key for the duel's board (its own version).
func _chapter_key(view: Dictionary) -> String:
	var key := Runs.chapter_of(str(view.board))
	return key if not key.is_empty() else str(view.chapter)
