extends Node
## Duels and their glue: the lobby (duels_screen.gd) and the pages over it
## (party, start a duel, race a recorded run, a duel, a result), every request
## through services/duels_client.gd, and Play, which hands the pair's room to
## the room flow like any room: it opens your pair's room, joins the one your
## partner made, or makes it (relay_lobby_flow.gd "duel"). When both of you
## made one at once, the server keeps the first and this phone joins it.
##
## Public duels (presentation/duels/public_duels_flow.gd, public()) live on the
## same pages: the lobby's Public duels row opens their list, Start a duel's
## Anyone posts one, and a public duel's page offers a stranger's card. Every
## public entry hides while the server says public duels are off.
##
## Duel energy (presentation/duels/duel_energy_flow.gd, energy()): while the
## server charges it, the lobby shows the meter and every start and join button
## its cost; a start or join with none left opens the out-of-energy card, and
## each refusal for energy is answered there before the usual line.
##
## Every duel entry hides while the server says duels are off
## (relay_online_session.gd duels_supported): the lobby, the Duel tag in Your
## rooms, and Home's row (offer), which also follows the public switch.
##
## Main hosts it as a child and reads it through is_open(), close(),
## offer(menu) and room_kind(). A duel's clear needs nothing here: its room is
## an ordinary room, so the chapter chain already counts it as a finished room. It reads Main only through
## this host contract (read at call time):
## - services: api, config, relay_session, ensure_relay_session,
##   _friends_client, _friend_display_name, pollen_client and fruit_spend_flow
##   (duel energy's wallet read and refill)
## - screen: mode, ui, application_backgrounded, _toast, _online_gated,
##   _relay_available, _ensure_identity
## - chapters: _chapter_unlocks, _full_journey_access, _paid_content_hidden
## - rooms: relay_lobby_flow (open_lobby, lobby_action, join_room), relay_child;
##   Main._return_to_room_hub asks return_instead() first
## - node: add_child
## - sound: soundscape when Main has it (play_fixed_cue), for a won result's bell, once per duel
## - live: live_connection when Main has it (duels_changed, missed_hints, healthy)
##
## Reads on their own (services/refresh_schedule.gd keeps the pace): the lobby
## once a minute while a challenge or running duel can change without this
## player (every two minutes with 5 or more running, whose reads cost the
## most), and an open duel once a minute too. Nothing reads while the app is in
## the background or has lost focus, or while the lobby is hidden (the other
## pair's run playing over it); coming
## back reads the screen in front once, at once. Opening, a page closing and
## this player's own actions read at once. A failed read keeps the same pace.
##
## Hints (services/live_connection.gd duels_changed): while the live socket is
## healthy and the latest duel read said the server sends hints (duel_hints_version), a
## change reads only the screen it touches, once however many arrive, and the
## timed reads drop to a backup pace (DUELS_LOBBY_BACKUP_MS, DUEL_BACKUP_MS).
## A hint for the open duel reads that duel. Any other is for the lobby, unless
## a page other than Party is over it (closing that page reads it anyway): a
## hint for a duel on the lobby reads only that duel and redraws its tile, one
## duel at a time; one that changes the list (the party, a new duel, a duel
## read that came back ended or failed) reads the whole lobby, at most once
## per DUELS_LIST_HINT_GAP_MS (services/duel_hint_reads.gd has the rules). A
## socket that comes back after dropping reads both once (missed_hints), and
## the moment it drops the pace goes back to the one above.
const ServerSwitches = preload("res://services/server_switches.gd")
const DuelsScreen = preload("res://presentation/duels/duels_screen.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const ResultPage = preload("res://presentation/duels/duel_result_page.gd")
const PartyPage = preload("res://presentation/duels/duel_party_page.gd")
const ChallengePage = preload("res://presentation/duels/duel_challenge_page.gd")
const GhostPage = preload("res://presentation/duels/duel_ghost_page.gd")
const RacePicker = preload("res://presentation/duels/duel_race_picker.gd")
const Rows = preload("res://presentation/leaderboard_rows.gd")
const LeaderboardClient = preload("res://services/leaderboard_client.gd")
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
const HintReads = preload("res://services/duel_hint_reads.gd")
const RelayLobbyFlow = preload("res://presentation/relay_lobby_flow.gd")
const PublicFlow = preload("res://presentation/duels/public_duels_flow.gd")
const EnergyFlow = preload("res://presentation/duels/duel_energy_flow.gd")
## Main's mode while Duels is up.
const MODE_DUELS := "duels"
## A room claimed a moment ago is joined up to JOIN_TRIES times, this far apart.
const JOIN_TRIES := 3
const JOIN_AGAIN_S := 1.0

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
## Duels on the lobby that hints named, each waiting for a read of its own, and whether one is out now.
var _hint_reads := HintReads.new()
var _hint_read_out := false
## The lobby the unhinted pace was last worked out for, and that pace (lobby_refresh_ms).
var _paced_lobby: Dictionary = {}
var _paced_ms := RefreshClock.DUELS_LOBBY_INTERVAL_MS
## True while the other pair's run is fetched for one tap.
var _their_loading := false
## The idempotency key of each challenge or ghost race sent with no answer yet,
## by what it asked for. A tap again sends the same key, so after a reply lost
## on the way the server answers the duel the first tap made, never a second one.
## A server's answer (a duel, or a refusal) settles it; the next tap is a new duel.
var _unanswered: Dictionary = {}
## While Play opens a duel's room (_play): the duel to come back to and the
## player who tapped, the room step's failure codes Play goes on from, whether
## one came, and a token that _stop() moves on, so the step that was running stops.
var _opening: Dictionary = {}
var _opening_player := ""
var _goes_on: Array = []
var _held := false
var _open_token := 0
var _public: RefCounted
var _energy: RefCounted
## Duels just opened: its first lobby read may ask for the community rules (public_duels_flow.gd ask_rules).
var _rules_due := false

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
	var asks := HintReads.route(client().last_lobby(), duel_id, at_ms)
	if _under_page():
		# Under the list or Start a duel while the partner greys a party post or join: the lobby, spaced, redraws that page.
		if asks == HintReads.LOBBY and public().reads_under(screen.overlay()): _ask_lobby(now, -1, RefreshClock.DUELS_LIST_HINT_GAP_MS, true)
		return
	if asks == HintReads.DUEL: _hint_reads.note(duel_id, at_ms)
	elif asks == HintReads.LOBBY: _ask_lobby(now, -1, RefreshClock.DUELS_LIST_HINT_GAP_MS)

## Hints were lost while the socket was down since `since_ms`: each screen in front reads once, unless a read begun after that covers it.
func _caught_up(since_ms: int) -> void:
	if not _reading(): return
	var now := Time.get_ticks_msec()
	_bind(now)
	_duel_reads.hint(now, since_ms)
	_ask_lobby(now, since_ms)

## One lobby read for a hint, while nothing but Party is over it (closing any other page reads it anyway)
## or `under_page` says the page wants it, no sooner than `gap_ms` after the last one began.
func _ask_lobby(now: int, covered_since: int = -1, gap_ms: int = 0, under_page := false) -> void:
	if _under_page() and not under_page: return
	if _lobby_reads.hint(now, covered_since, gap_ms): _lobby_asked = true

## Whether a page other than Party is over the lobby.
func _under_page() -> bool:
	var overlay: CanvasLayer = screen.overlay()
	return overlay != null and not overlay is PartyPage

## Starts the next hinted duel's own read, one at a time, while the lobby is in
## front with no read of its own out or asked for (that read covers it). When
## the duels waiting would cost more than the lobby, the lobby reads instead.
func _next_hinted(now: int, shown: bool) -> void:
	if _hint_read_out or _hint_reads.waiting() == 0 or not shown or _under_page() or _lobby_asked or _lobby_reads.busy(): return
	var lobby: Dictionary = client().last_lobby()
	if _hint_reads.cheaper_as_lobby(lobby):
		_hint_reads.clear()
		_ask_lobby(now, -1, RefreshClock.DUELS_LIST_HINT_GAP_MS)
		return
	var view := _hint_reads.next(lobby)
	if not view.is_empty(): _read_hinted(view)

## One hinted duel's read: services/duels_client.gd puts its newer copy into the
## kept lobby, and its tile redraws. One that ended, or could not be read (gone
## from the server, or a failure), asks for the whole lobby, spaced.
func _read_hinted(view: Dictionary) -> void:
	_hint_read_out = true
	var answer: Dictionary = await client().duel(view.board, view.duel_id)
	_hint_read_out = false
	if not _reading(): return
	var ok: bool = answer.get("ok", false)
	if not ok or HintReads.ended(view, answer.duel): _ask_lobby(Time.get_ticks_msec(), -1, RefreshClock.DUELS_LIST_HINT_GAP_MS)
	if ok: screen.show_lobby(client().last_lobby())

func _process(_delta: float) -> void:
	_tick(Time.get_ticks_msec())

## Starts the lobby's or the open duel's read when it is due and may run.
func _tick(now: int) -> void:
	if not _reading():
		_lobby_reads.bind("", now)
		_duel_reads.bind("", now)
		_hint_reads.clear()
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
	else: _next_hinted(now, shown)

## Binds both clocks to what is open now and returns the duel page being read, or null.
func _bind(now: int) -> CanvasLayer:
	var hinted := _hints_live()
	_lobby_reads.bind("lobby/%d" % screen.get_instance_id(), now, RefreshClock.DUELS_LOBBY_BACKUP_MS if hinted else _unhinted_lobby_ms())
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

## Shows Home's row while the server says duels are on: this session's
## capabilities when they say so, else the public switch the phone last heard
## (services/server_switches.gd: the app-status answer at launch, kept on
## disk). Home asks nothing for it. A tap reads the capabilities first when
## this session has none (Main._show_duels), and the lobby opens on those.
func offer(menu: Control) -> void:
	if menu != null and is_instance_valid(menu) and menu.has_method("show_duels"): menu.show_duels(offered())

func offered() -> bool:
	return supported() or ServerSwitches.shared().on_for(host.api, "duels")

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
	screen.energy_cost = energy().shown()
	screen.energy_meter = energy().meter()
	screen.closed.connect(_left)
	screen.notice.connect(func(text: String, _news: bool) -> void: host._toast(text))
	screen.start_requested.connect(_open_challenge)
	screen.party_requested.connect(_open_party)
	screen.ghosts_requested.connect(_open_ghosts)
	screen.public_requested.connect(func() -> void: public().open_list())
	screen.duel_action.connect(_on_duel_action)
	screen.refresh_requested.connect(_refresh)
	host.add_child(screen)
	var kept: Dictionary = client().last_lobby()
	screen.public_shown = public().supported()
	screen.public_on = public().switched_on()
	if not kept.is_empty(): screen.show_lobby(kept)
	_rules_due = true
	set_process(true)
	energy().opened()
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
	screen.public_shown = public().supported()
	screen.public_on = public().switched_on()
	screen.show_lobby(answer.get("lobby", {}), not answer.get("ok", false))
	var ghosts := _race_ghost()
	if ghosts != null and answer.get("ok", false): ghosts.release_ended(answer.lobby)
	var overlay: CanvasLayer = screen.overlay()
	if answer.get("ok", false) and overlay is PartyPage: overlay.show_party(answer.lobby.party)
	elif answer.get("ok", false) and overlay != null: public().lobby_read(overlay)
	# The rules card once Duels opened, from its first answer, unless a page other than Party is up by then (the next read asks).
	if answer.get("ok", false) and _rules_due and not _under_page():
		_rules_due = false
		public().ask_rules(answer.lobby)

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

## `kind`: what was asked, "friend" (a challenge or an accept) or "ghost" (a race), for the limit line.
func _toast_failure(answer: Dictionary, kind: String = "friend") -> void:
	var code := str(answer.get("code", ""))
	if code == "duel_limit_reached":
		host._toast((PlayerCopy.DUELS_RACE_LIMIT if kind == "ghost" else PlayerCopy.DUELS_LIMIT) % client().limit(kind))
		return
	host._toast(PlayerCopy.DUELS_FRIEND_NO_PARTNER if code == "opponent_party_required" else PlayerCopy.DUELS_NO_PARTY if code == "party_required" else PlayerCopy.DUELS_ACTION_FAILED)

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
		# A party just made: the rules card before anything public, so the new partner never greys a party join.
		if action == "accept": public().ask_rules(answer.lobby, true)
	else: _toast_failure(answer)

func _open_challenge(anyone: bool = false) -> void:
	if not is_open(): return
	var page := ChallengePage.new()
	page.chapters = _open_chapters()
	page.energy_cost = energy().shown()
	_offer_public(page, anyone)
	var partner: Variant = client().last_lobby().get("party", {}).get("partner")
	page.send_requested.connect(func(friend: String, chapter: String, control: Control) -> void:
		if energy().blocks(page, control): return
		page.tap(control, func() -> void: await _challenge(page, friend, chapter, control)))
	screen.open_overlay(page)
	var friends := await _friends(partner)
	if not is_instance_valid(page): return
	page.friends = friends
	if page.is_inside_tree(): page._render()

func _challenge(page: CanvasLayer, friend: String, chapter: String, control: Control = null) -> void:
	var board := Runs.board_key(chapter)
	var answer: Dictionary = await _send_once("challenge|%s|%s" % [friend, board], func(key: String) -> Dictionary: return await client().challenge(friend, board, key))
	if not is_instance_valid(page): return
	if answer.get("code") == "duel_already_open":
		await _already_open(page, friend, board)
		return
	if not answer.get("ok", false):
		if not energy().refused(page, answer, control, _partner_label()): _toast_failure(answer)
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
	page.energy_cost = energy().shown()
	page.race_requested.connect(func(chapter: String, source: String, entry_id: Variant, control: Control) -> void:
		if energy().blocks(page, control): return
		page.tap(control, func() -> void: await _race(page, chapter, source, entry_id, null, control)))
	page.picker_requested.connect(func(chapter: String, control: Control) -> void: _open_picker(page, chapter, control))
	screen.open_overlay(page)
	var answer: Dictionary = await client().ghosts()
	if is_instance_valid(page): page.show_ghosts(answer.get("boards", []), not answer.get("ok", false))

## The chapter's top 10 picker over the ghost page (duel_race_picker.gd): the
## board Fastest pair reads (services/leaderboard_client.gd, kept a minute, so
## usually no request), drawn through the rows that page draws (Rows.shown).
## Its Race taps go through the page's gate like the page's own.
func _open_picker(page: CanvasLayer, chapter: String, opener: Control) -> void:
	if not is_open() or not is_instance_valid(page): return
	var picker: Control = RacePicker.open(page, chapter, _partner_name(), opener)
	if picker == null: return
	picker.race_requested.connect(_picker_race.bind(page, chapter, picker))
	# Every row would grey from a lobby read that may be old, and a greyed row
	# can't be tapped for the server to say otherwise: read the lobby once first.
	if client().ghost_races_full():
		var answer: Dictionary = await client().lobby()
		if is_open() and answer.get("ok", false) and screen is DuelsScreen: screen.show_lobby(answer.lobby)
	await _fill_picker(page, picker, chapter, false)

## A Race on the picker, through the page's gate; a sheet closed before the finger lifted sends nothing.
func _picker_race(source: String, entry_id: Variant, control: Control, page: CanvasLayer, chapter: String, picker: Variant) -> void:
	if energy().blocks(page, control): return
	page.tap(control, func() -> void:
		if is_instance_valid(picker): await _race(page, chapter, source, entry_id, picker, control))

## Reads the chapter's board (`fresh`: past the phone's minute) and redraws the
## picker; `full`: the server just said the pair has its limit of races going.
func _fill_picker(page: CanvasLayer, picker: Variant, chapter: String, fresh: bool, full: bool = false) -> void:
	var board := Runs.board_key(chapter)
	var boards: RefCounted = LeaderboardClient.shared(host.api, str(host.api.player_id))
	var answer: Dictionary = await boards.board(board, fresh)
	if not is_instance_valid(picker) or not is_instance_valid(page): return
	if not answer.get("ok", false):
		picker.show_failed()
		return
	var shown := Rows.shown(boards, str(host.api.player_id), board, answer.view)
	picker.show_board(shown.rows, shown.mine_by_id, full or client().ghost_races_full(), client().limit("ghost"), page.developer_ticks(chapter))

## The partner's name at the start of a line (duel energy's "Maya is waiting for energy"), or "" with no pair.
func _partner_label() -> String:
	var party: Dictionary = client().last_lobby().get("party", {})
	return _name_of(party.partner) if party.get("intact", false) and party.get("partner") != null else ""

## The partner's name in the middle of a line ("a friend" for one never named), or "" with no pair.
func _partner_name() -> String:
	var party: Dictionary = client().last_lobby().get("party", {})
	var partner: Variant = party.get("partner") if party.get("intact", false) else null
	return host._friend_display_name(str(partner)) if partner != null else ""

## `picker`: the top 10 picker the race was tapped on (closed since, perhaps), or null. A run that left
## the top 10 since the picker's read says so and the picker reads the board
## again; a refused limit greys its rows.
func _race(page: CanvasLayer, chapter: String, source: String, entry_id: Variant, picker: Variant = null, control: Control = null) -> void:
	var board := Runs.board_key(chapter)
	var answer: Dictionary = await _send_once("ghost|%s|%s|%s" % [board, source, entry_id], func(key: String) -> Dictionary: return await client().race_ghost(board, source, entry_id, key))
	if not is_instance_valid(page): return
	if not answer.get("ok", false):
		if energy().refused(page, answer, control, _partner_label()): return
		var code := str(answer.get("code", ""))
		var on_picker := is_instance_valid(picker)
		if on_picker and source == "board" and code == "ghost_not_found":
			host._toast(PlayerCopy.RACE_PICK_LEFT)
			_fill_picker(page, picker, chapter, true)
			return
		_toast_failure(answer, "ghost")
		if on_picker and code == "duel_limit_reached": _fill_picker(page, picker, chapter, false, true)
		return
	page.close()
	# The race ghost keeps the raced run now, so one that leaves the top 10 before the first turn still plays.
	var ghosts := _race_ghost()
	if ghosts != null: ghosts.prefetch(answer.duel)
	_open_duel(answer.duel)

## The race ghost's data (services/race_ghost.gd) while the server has it on and Settings shows it, else null.
func _race_ghost() -> RefCounted:
	var session: RefCounted = host.relay_session
	var saves: Variant = host.get("saves")
	if saves != null and not bool(saves.data.settings.get("race_ghost", true)): return null
	return session.race_ghost() if session != null and session.has_method("race_ghost") else null

func _on_duel_action(view: Dictionary, action: String, control: Control) -> void:
	if not is_open(): return
	match action:
		"accept", "decline":
			if action == "accept" and not ChapterUnlocks.open(view.chapter, host._chapter_unlocks()):
				host._toast(PlayerCopy.DUELS_CHAPTER_CLOSED)
				return
			if action == "accept" and energy().blocks(screen, control): return
			screen.tap(control, func() -> void:
				var answer: Dictionary = await client().act(view.board, view.duel_id, action)
				var keep_note := func(words: String) -> void: if is_open(): screen.note(str(view.duel_id), words)
				if not answer.get("ok", false) and not (action == "accept" and energy().refused(screen, answer, control, _partner_label(), keep_note)): _toast_failure(answer)
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
	page.stranger_requested.connect(func(next: Dictionary, index: int, slot: int) -> void: public().stranger(page, next, index, slot))
	page.leave_requested.connect(func(next: Dictionary) -> void:
		var answer: Dictionary = await client().act(next.board, next.duel_id, "leave")
		if not answer.get("ok", false):
			_toast_failure(answer)
			return
		# The lobby under the page shows the duel as left too (services/duels_client.gd keeps the answer).
		if is_open(): screen.show_lobby(client().last_lobby())
		# A public seat given back before its room was entered: this player is out of the duel.
		if answer.get("left", false) and (answer.duel as Dictionary).is_empty():
			if is_instance_valid(page): page.close()
			_refresh()
			return
		_show_duel(page, answer.duel))
	screen.open_overlay(page)
	# A public duel's page shows the duel extra held so far: its first timed read goes at once and brings it.
	if view.has("public"):
		var now := Time.get_ticks_msec()
		_bind(now)
		_duel_reads.request_now(now)
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
	if answer.get("ok", false) and is_instance_valid(page): page.held = answer.get("held", {})
	if answer.get("ok", false): _show_duel(page, answer.duel)

## A newer copy of the open duel, from a read or this player's own action
## (Leave shows at once): a running duel redraws its page, an ended one swaps in
## the result page. A copy older than the page's, such as a read that went out
## before Leave, changes nothing.
func _show_duel(page: CanvasLayer, duel: Dictionary) -> void:
	if not is_instance_valid(page) or not page.alive() or int(duel.updated_ms) < int(page.view.get("updated_ms", 0)): return
	# A public duel whose open seat beside you just filled says so, once, quietly.
	if duel.status == "running" and DuelModel.open_seats(duel, duel.mine) < DuelModel.open_seats(page.view, page.view.get("mine", 0)): host._toast(PlayerCopy.PUBLIC_PARTNER_JOINED)
	if duel.status == "running":
		page.show_duel(duel)
	else:
		page.close()
		_open_result(duel)

## The lobby's pace without hints, worked out again only when the kept lobby changed (_bind runs every frame).
func _unhinted_lobby_ms() -> int:
	var lobby: Dictionary = client().last_lobby()
	if not is_same(lobby, _paced_lobby):
		_paced_lobby = lobby
		_paced_ms = lobby_refresh_ms(lobby)
	return _paced_ms

## How often the lobby reads again: DUELS_LOBBY_BACKUP_MS while hints come (`hinted`), else
## DUELS_LOBBY_BUSY_INTERVAL_MS with DUELS_BUSY_RUNNING or more duels running, else DUELS_LOBBY_INTERVAL_MS.
static func lobby_refresh_ms(lobby: Dictionary, hinted: bool = false) -> int:
	if hinted: return RefreshClock.DUELS_LOBBY_BACKUP_MS
	var running := 0
	for view: Dictionary in lobby.get("duels", []):
		if view.status == "running": running += 1
	return RefreshClock.DUELS_LOBBY_BUSY_INTERVAL_MS if running >= RefreshClock.DUELS_BUSY_RUNNING else RefreshClock.DUELS_LOBBY_INTERVAL_MS

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
	page.stranger_requested.connect(func(next: Dictionary, index: int, slot: int) -> void: public().stranger(page, next, index, slot))
	screen.open_overlay(page)
	var answer: Dictionary = await client().duel(view.board, view.duel_id)
	if not is_instance_valid(page) or not answer.get("ok", false): return
	page.held = answer.get("held", {})
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
## Whoever of the pair taps Play first makes the room, whatever the turn order
## (DuelModel.your_turn): the other joins it and sees the room's own waiting
## view until their turn. A room step that cannot go on comes back to this
## duel's page with its reason (return_instead), never to the room hub. The
## one exception is another room's saved create or join, which holds every
## room step: the hub's card for it is where it is finished, as for any room.
func _play(view: Dictionary) -> void:
	if not is_open() or host.application_backgrounded or not _opening.is_empty(): return
	if not ChapterUnlocks.open(view.chapter, host._chapter_unlocks()):
		host._toast(PlayerCopy.DUELS_CHAPTER_CLOSED)
		return
	var chapter := _chapter_key(view)
	host.mode = RelayLobbyFlow.MODE_LOBBY
	close()
	host.ui.visible = true
	_open_token += 1
	var token := _open_token
	_opening = view
	_opening_player = str(host.api.player_id)
	await _open_room(view, chapter, token)
	# return_instead already brought the duel back, or another screen took over.
	if token != _open_token: return
	var stopped_quietly := _stepping()
	_stop()
	# A step that stopped without a word, its progress card still up: the duel again.
	if stopped_quietly: _back_to(view, "")

func _open_room(view: Dictionary, chapter: String, token: int) -> void:
	var own: Dictionary = view.sides[view.mine]
	var pending: Dictionary = host.relay_session.pending_lobby() if host.relay_session != null else {}
	if not pending.is_empty() and not _pending_for(view):
		_stop()
		host._return_to_room_hub(PlayerCopy.RELAY_ONLINE_SESSION_8C3AC7311985)
		return
	# This duel's create whose answer was lost goes again first: its room, or the partner's that came first.
	if pending.is_empty():
		if not str(own.get("room_id", "")).is_empty() and own.get("hosting", false):
			_step([])
			if await host.relay_lobby_flow.open_lobby(chapter): await host.relay_lobby_flow.lobby_action("open", own.room_id)
			return
		# A room your partner claimed but never made: make it here instead (the server lets the claim pass after a while).
		if not str(own.get("invite_code", "")).is_empty():
			if not await _step_held(token, ["invite_not_found", "room_deleted"], host.relay_lobby_flow.join_room.bind(own.invite_code)): return
	# The first of you to open the duel makes its room.
	if not await _step_held(token, ["duel_room_taken"], _make_room.bind(view, chapter)): return
	# Your partner's room came first: join it.
	var fresh: Dictionary = await client().duel(view.board, view.duel_id)
	if token != _open_token or not _stepping(): return
	var invite := str(fresh.duel.sides[fresh.duel.mine].get("invite_code", "")) if fresh.get("ok", false) else ""
	if invite.is_empty():
		_stop()
		_back_to(view, PlayerCopy.DUELS_ACTION_FAILED)
		return
	# A room claimed a moment ago may still be on its way: a few tries, a moment apart; the last one's refusal comes back.
	for attempt in range(JOIN_TRIES):
		if not await _step_held(token, ["invite_not_found"] if attempt < JOIN_TRIES - 1 else [], host.relay_lobby_flow.join_room.bind(invite)): return
		await host.get_tree().create_timer(JOIN_AGAIN_S).timeout

## Makes the duel's room; a create whose answer was lost is sent again as it was.
func _make_room(view: Dictionary, chapter: String) -> void:
	if not await host.relay_lobby_flow.open_lobby(chapter): return
	if _pending_for(view): await host.relay_lobby_flow.lobby_action("retry")
	else: await host.relay_lobby_flow.lobby_action("duel", chapter, false, {"duel_id": view.duel_id, "board": view.board})

## Runs one room step whose failures with `codes` Play goes on from, while
## Play still has the screen. True when it failed with one of them; false when
## the room opened, the duel came back or the step stopped some other way.
func _step_held(token: int, codes: Array, run: Callable) -> bool:
	if token != _open_token or not _stepping(): return false
	_step(codes)
	await run.call()
	if token != _open_token or not _held: return false
	_held = false
	return true

## The codes the next step's failure goes on from, with any older answer's code cleared.
func _step(codes: Array) -> void:
	_goes_on = codes
	_held = false
	if host.relay_session != null: host.relay_session.last_lobby_code = ""

## Whether Play's room step still has the screen: its progress card, for the
## player who tapped Play, with no room open. A notification that opened
## another screen, or another player, ends the step.
func _stepping() -> bool:
	return not _opening.is_empty() and host.mode == RelayLobbyFlow.MODE_LOBBY and not is_instance_valid(host.relay_child) and str(host.api.player_id) == _opening_player

## Play's room step is over: a step still out stops at its next check.
func _stop() -> void:
	_opening = {}
	_goes_on = []
	_held = false
	_open_token += 1

## Whether this phone holds this duel's create, its answer lost (services/relay_online_session.gd pending_lobby).
func _pending_for(view: Dictionary) -> bool:
	if host.relay_session == null: return false
	var pending: Dictionary = host.relay_session.pending_lobby()
	var body: Variant = pending.get("body")
	return pending.get("path") == "/v2/rooms" and body is Dictionary and body.get("duel") is Dictionary and body.duel.get("duel_id") == view.duel_id

## Main asks this before a room step returns to the room hub (Main._return_to_room_hub).
## While Play's room step has the screen it answers true: a failure Play goes on
## from waits for it, and anything else (a refusal, a lost connection, Back on
## the progress card) brings the duel's page back with `notice`. Otherwise false,
## and a step that lost the screen ends.
func return_instead(notice: String) -> bool:
	if _opening.is_empty(): return false
	if not _stepping():
		_stop()
		return false
	var code := str(host.relay_session.last_lobby_code) if host.relay_session != null else ""
	# A public seat the board no longer gives you (you left it, or it closed): the duel again, as it is now.
	if code == "duel_pair_only": notice = PlayerCopy.PUBLIC_GONE
	if not code.is_empty() and code in _goes_on:
		_goes_on = []
		_held = true
		return true
	var view := _opening
	_stop()
	_back_to(view, notice)
	return true

## The duel again, over its lobby, as Play left it, with `notice` in the app's pop-up.
func _back_to(view: Dictionary, notice: String) -> void:
	if supported():
		open()
		_open_duel(_latest(view))
	else:
		host.mode = MODE_DUELS
		_left()
	if not notice.is_empty(): host._toast(notice)

## Public duels' glue (public_duels_flow.gd), made once.
func public() -> RefCounted:
	if _public == null: _public = PublicFlow.new(self)
	return _public

## Duel energy's glue (duel_energy_flow.gd), made once.
func energy() -> RefCounted:
	if _energy == null: _energy = EnergyFlow.new(self)
	return _energy

## Settings' Public duels row: shown while the server has them (or last said so) and switched through public_duels_flow.gd.
func public_offered() -> bool:
	return public().offered()

func public_choose(on: bool) -> bool:
	return public().choose(on)

func public_switch() -> bool:
	return public().switch_shown()

## Start a duel's "Anyone" while public duels are open: posting goes through public_duels_flow.gd post().
func _offer_public(page: CanvasLayer, anyone: bool) -> void:
	if not public().supported(): return
	var party: Dictionary = client().last_lobby().get("party", {})
	page.public_offered = true
	page.anyone = anyone
	page.partner_name = _name_of(party.partner) if party.get("intact", false) and party.get("partner") != null else ""
	page.partner_look = party.get("partner_look", {})
	page.party_reason = public().partner_text()
	page.post_requested.connect(func(joining: String, chapter: String, control: Control) -> void:
		if energy().blocks(page, control): return
		page.tap(control, func() -> void: await public().post(page, joining, chapter, false, control)))

## The bundled chapter key for the duel's board (its own version).
func _chapter_key(view: Dictionary) -> String:
	var key := Runs.chapter_of(str(view.board))
	return key if not key.is_empty() else str(view.chapter)
