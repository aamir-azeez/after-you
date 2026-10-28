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
const DuelsScreen = preload("res://presentation/duels/duels_screen.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const ResultPage = preload("res://presentation/duels/duel_result_page.gd")
const PartyPage = preload("res://presentation/duels/duel_party_page.gd")
const ChallengePage = preload("res://presentation/duels/duel_challenge_page.gd")
const GhostPage = preload("res://presentation/duels/duel_ghost_page.gd")
const DuelsClient = preload("res://services/duels_client.gd")
const DuelModel = preload("res://services/duel_model.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Main's mode while Duels is up.
const MODE_DUELS := "duels"
## How often an open duel page reads its duel again.
const DUEL_REFRESH_SECONDS := 15.0

signal home_requested

var host: Node
var screen: CanvasLayer
var _duel_timer: Timer

func _init(main: Node = null) -> void:
	host = main

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
	screen.boost_percent = 10 if host._full_journey_access() and _surfaces().full_journey_visible() else 0
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
	_refresh()

## Closes Duels for a screen Main shows instead; Main sets its mode first.
func close() -> void:
	if not is_open(): return
	var page := screen
	screen = null
	page.close()

func _left() -> void:
	screen = null
	if host.mode == MODE_DUELS:
		host.ui.visible = true
		home_requested.emit()

func _refresh() -> void:
	if not is_open(): return
	var answer: Dictionary = await client().lobby()
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
	page.set_friends(await _friends())

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
	page.friends = await _friends(partner)
	if is_instance_valid(page) and page.is_inside_tree(): page._render()

func _challenge(page: CanvasLayer, friend: String, chapter: String) -> void:
	var answer: Dictionary = await client().challenge(friend, Runs.board_key(chapter), DuelsClient.new_key())
	if not is_instance_valid(page): return
	if not answer.get("ok", false):
		_toast_failure(answer)
		return
	host._toast(PlayerCopy.DUELS_SENT)
	page.close()

func _open_ghosts() -> void:
	if not is_open(): return
	var page := GhostPage.new()
	page.chapters = _open_chapters()
	page.race_requested.connect(func(chapter: String, source: String, entry_id: Variant, control: Control) -> void: page.tap(control, func() -> void: await _race(page, chapter, source, entry_id)))
	screen.open_overlay(page)
	var answer: Dictionary = await client().ghosts()
	if is_instance_valid(page): page.show_ghosts(answer.get("boards", []), not answer.get("ok", false))

func _race(page: CanvasLayer, chapter: String, source: String, entry_id: Variant) -> void:
	var answer: Dictionary = await client().race_ghost(Runs.board_key(chapter), source, entry_id, DuelsClient.new_key())
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
		if not answer.get("ok", false): _toast_failure(answer)
		elif is_instance_valid(page): page.show_duel(answer.duel))
	screen.open_overlay(page)
	_watch_duel(page)
	# The phone's room may be ahead of the duel (a lost note): ask the server to look once.
	var own: Dictionary = view.sides[view.mine]
	if view.status == "running" and not own.finished and not str(own.get("room_id", "")).is_empty():
		var synced: Dictionary = await client().act(view.board, view.duel_id, "sync")
		if synced.get("ok", false) and is_instance_valid(page): page.show_duel(synced.duel)

## Reads the open duel again every DUEL_REFRESH_SECONDS while its page is up; a result swaps in the result page.
func _watch_duel(page: CanvasLayer) -> void:
	if is_instance_valid(_duel_timer): _duel_timer.queue_free()
	_duel_timer = Timer.new()
	_duel_timer.wait_time = DUEL_REFRESH_SECONDS
	page.add_child(_duel_timer)
	_duel_timer.timeout.connect(func() -> void:
		if not is_instance_valid(page) or host.application_backgrounded: return
		var answer: Dictionary = await client().duel(page.view.board, page.view.duel_id)
		if not is_instance_valid(page) or not answer.get("ok", false): return
		if answer.duel.status == "running": page.show_duel(answer.duel)
		else:
			page.close()
			_open_result(answer.duel))
	_duel_timer.start()

func _open_result(view: Dictionary) -> void:
	if not is_open(): return
	var page := ResultPage.new()
	page.me = str(host.api.player_id)
	page.name_of = _name_of
	page.show_boost = _surfaces().full_journey_visible()
	page.show_pollen = _surfaces().earning_visible() and host.relay_session != null and host.relay_session.pollen_supported()
	page.view = view
	page.watch_requested.connect(func(next: Dictionary, control: Control) -> void: _play(next))
	screen.open_overlay(page)
	var answer: Dictionary = await client().duel(view.board, view.duel_id)
	if is_instance_valid(page) and answer.get("ok", false): page.show_result(answer.duel, answer.get("pay", {}), answer.get("win_bonus", {}))

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
