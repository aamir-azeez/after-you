extends RefCounted
## Public duels' glue (boards 1 to 6), owned by the duels flow
## (presentation/duels/duels_flow.gd), which hosts the lobby and the pages over
## it. Every request goes through services/public_duels_client.gd, and every
## duel it answers opens on the duel flow's own pages:
## - open_list(): the list (public_list_page.gd). Public duels are on by default
##   (the server's switch, backend leaderboards/member.ts publicDuelsChosen).
##   With the player's switch turned off, the first-time card asks first
##   (public_sheets.gd first_time); its Turn on shows the community rules when
##   they are not accepted yet (the safety screen every photo share uses), then
##   sets the switch and the name choice. A player who never turned it off
##   meets the same card, with Continue, at their first post or join: the
##   server refuses both until the rules in force are accepted, and the post or
##   join goes again once they are.
## - ask_rules(): the same card, with Continue, before anything public happens:
##   the first lobby read after Duels opens (once a launch) and a party invite
##   just accepted, while the lobby says this player has not accepted the rules
##   in force and their switch is on. So a partner has normally accepted before
##   a party post or join, which greys (with the reason) while the lobby says
##   they have not; the server's partner_rules_required stays the backstop.
## - join(): the join card, then the join with the attempt's idempotency key.
##   A spot someone took first redraws its row with a note; a duel that closed
##   leaves the list with a word. A joined duel opens at once.
## - post(): Start a duel's "Anyone" (duel_challenge_page.gd), with its key.
## While duel energy is on (the duels flow's energy()), Join, Join and play and
## Post a duel wear the cost chip; a join tapped with none left opens the
## out-of-energy card in place of the join card, and a refusal for energy is
## answered there (a partner without energy is a note under the row's Join).
## - stranger(): a stranger's card from the duel page: faces, Report, Block
##   (leaving when it's your partner) and Add friend once the duel is over.
## Each request is refused at once while the phone is offline (offline_hold.gd),
## and every key is kept until the server answers it, so a retry after a lost
## answer is the same post, join or report, never a second one.
const PublicClient = preload("res://services/public_duels_client.gd")
const Spots = preload("res://services/public_duel_spots.gd")
const DuelModel = preload("res://services/duel_model.gd")
const ListPage = preload("res://presentation/duels/public_list_page.gd")
const Sheets = preload("res://presentation/duels/public_sheets.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const ServerSwitches = preload("res://services/server_switches.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const LeaderboardClient = preload("res://services/leaderboard_client.gd")
const SafetyScreen = preload("res://presentation/safety_screen.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const ChallengePage = preload("res://presentation/duels/duel_challenge_page.gd")

## The duels flow this belongs to; Main through its host.
var flow: Node
## The list's chapter and sort, kept for this launch, so it opens as it was left.
static var _scope := "all"
static var _sort := "newest"
## Whether the lobby's rules card showed this launch (ask_rules), so opening Duels again asks no more.
static var _rules_asked := false
## Each attempt's idempotency key, by what it asked, until the server answers it.
var _keys: Dictionary = {}
## Friend requests sent this launch, by duel and seat, so the card offers each once.
var _befriended: Dictionary = {}
## True while Turn on runs (the rules, then the switch), so a second tap waits for it.
var _turning_on := false
## True while the list's open asks about the rules, so a second tap opens nothing more.
var _opening := false
## What Settings' switch shows while its request is out (true or false), or null when none is.
var _switch_asked: Variant = null
## True while ask_rules checks the safety client, so a second ask waits for it.
var _asking_rules := false

func _init(duels_flow: Node) -> void:
	flow = duels_flow

func host() -> Node:
	return flow.host

func client() -> RefCounted:
	return PublicClient.new(host().api, flow.client())

## Whether the server has public duels open: this session's capabilities, else the switch last heard.
func offered() -> bool:
	return supported() or ServerSwitches.shared().on_for(host().api, "public_duels")

func supported() -> bool:
	return host().relay_session != null and host().relay_session.public_duels_supported()

## The player's own switch, as the server last said.
func switched_on() -> bool:
	return flow.client().public_on()

func _public() -> Dictionary:
	return flow.client().last_lobby().get("public", {})

func _partner() -> Dictionary:
	var party: Dictionary = flow.client().last_lobby().get("party", {})
	if not party.get("intact", false) or party.get("partner") == null: return {}
	return {"id": party.partner, "name": flow._name_of(party.partner), "look": party.get("partner_look", {})}

## The list, over the lobby; the first-time card first while the switch is off or the rules in
## force are not accepted yet (asked once a launch; a failed ask opens the list, and the server
## still refuses a post or join until the rules are accepted).
func open_list() -> void:
	if _opening or not flow.is_open() or not supported(): return
	_opening = true
	var listed := switched_on()
	if listed: listed = await _rules_accepted()
	_opening = false
	if not flow.is_open(): return
	if listed: _show_list()
	else: _first_time(func() -> void: _show_list())

## Whether this player accepted the community rules in force, as far as this launch knows: the
## lobby's word, else the safety client's last answer, else one ask. Anything but a clear "not
## accepted" answers true.
func _rules_accepted() -> bool:
	if _public().get("rules") == true: return true
	var safety := _safety()
	if safety == null or safety.terms_accepted: return true
	if not await safety.check_terms(): return true
	return safety.terms_accepted

func _safety() -> RefCounted:
	return host().relay_session.safety_client() if host().relay_session != null and host().relay_session.has_method("safety_client") else null

## The rules card before anything public (the first lobby read after Duels opens, once a launch,
## and with `again` a party invite just accepted): only while public duels are open, the
## player's switch is on (a phone switched off, say a child's, is never asked) and `lobby` says
## the rules in force are not accepted. The server's safety answer has the last word: when it
## says they are, that same acceptance is sent again, which writes the lobby's copy that went
## missing. Not now leaves everything as it was; Continue reads the lobby again, so the
## partner's greying clears.
func ask_rules(lobby: Dictionary, again := false) -> void:
	if _asking_rules or (_rules_asked and not again) or not supported() or not switched_on() or not flow.is_open(): return
	var rules: Variant = lobby.get("public", {}).get("rules")
	if not rules is bool or rules: return
	var safety := _safety()
	if safety == null: return
	# Asked afresh: a kept answer may be for the rules before public duels were on.
	_asking_rules = true
	var checked: bool = await safety.check_terms()
	_asking_rules = false
	if not checked or not flow.is_open() or not switched_on(): return
	if safety.terms_accepted:
		safety.accept_rules()
		return
	# A page opened over the lobby meanwhile (a duel, a result): its next read asks instead.
	if not again and flow._under_page():
		flow._rules_due = true
		return
	_first_time(func() -> void: flow._refresh())

## The first-time card over whatever page is in front; `then` runs once the rules are accepted and the switch is on.
## With the switch on (the default) its Continue only asks for the rules and the name choice: it never sends the
## switch, so a phone that has not heard the server's word yet can't turn a parent's off back on. Any card shown
## counts as the launch's ask, so opening Duels after it asks no more (ask_rules).
func _first_time(then: Callable) -> void:
	_rules_asked = true
	var page: CanvasLayer = flow.screen.overlay() if flow.screen.overlay() != null else flow.screen
	var name_on: bool = LeaderboardClient.shared(host().api, str(host().api.player_id)).show_name()
	var continuing := switched_on()
	page.hold_modal(Sheets.first_time(page.root, name_on, func(show_name: bool) -> void:
		if await turn_on(show_name, not continuing) and flow.is_open(): then.call(), PlayerCopy.PUBLIC_FIRST_CONTINUE if continuing else PlayerCopy.PUBLIC_TURN_ON))

## A post or join the server refused for the rules (terms_acceptance_required): the first-time card and the
## rules, then `again` once. False for any other answer, or for a second refusal (then said as usual).
func _rules_first(answer: Dictionary, retried: bool, again: Callable) -> bool:
	if not rules_refusal(answer, retried): return false
	_first_time(again)
	return true

## Whether a post or join answer asks for the rules first: the refusal, the first time only.
static func rules_refusal(answer: Dictionary, retried: bool) -> bool:
	return not retried and not answer.get("ok", false) and str(answer.get("code", "")) == "terms_acceptance_required"

## Turns the switch on: the community rules first when not accepted, then the name choice and
## the switch (`set_switch` false: the rules and the name only). False when it did not go through (said in a toast).
func turn_on(show_name: Variant = null, set_switch := true) -> bool:
	if _turning_on or OfflineHold.refuse(host()._toast): return false
	_turning_on = true
	var done := await _turn_on(show_name, set_switch)
	_turning_on = false
	return done

func _turn_on(show_name: Variant, set_switch: bool) -> bool:
	var safety := _safety()
	if safety == null: return _say(PlayerCopy.DUELS_ACTION_FAILED)
	if not await safety.check_terms(): return _say(safety.last_error if not str(safety.last_error).is_empty() else PlayerCopy.DUELS_ACTION_FAILED)
	if not safety.terms_accepted:
		# The rules screen every photo share shows; Accept there sets terms_accepted.
		var rules := SafetyScreen.new(safety, {}, Callable(), Callable(), true)
		host().add_child(rules)
		# Over the duel pages, whose layers start at 61; it takes Back itself, so Duels waits for it.
		rules.layer = 90
		if flow.is_open(): flow.screen.hold_back(rules)
		await rules.tree_exited
		if not safety.terms_accepted: return false
	if show_name is bool:
		var names: RefCounted = LeaderboardClient.shared(host().api, str(host().api.player_id))
		if names.show_name() != show_name: names.set_show_name(show_name)
	if not set_switch: return true
	var answer: Dictionary = await client().set_on(true)
	if not answer.get("ok", false): return _say(_failure_text(answer))
	if flow.is_open(): flow._refresh()
	return true

## Settings' Public duels switch as it shows: what a request still out asked for, else the server's last word.
func switch_shown() -> bool:
	return bool(_switch_asked) if _switch_asked != null else switched_on()

## Settings' Public duels switch: on goes through turn_on (the rules first), off at once. The
## switch shows the ask until the server answers, then Settings reads it again; a refusal is a toast.
## Off while Turn on is still out waits for it.
func choose(on: bool) -> bool:
	if _switch_asked != null or _turning_on: return true
	if OfflineHold.refuse(host()._toast): return false
	_settle_switch(on)
	return true

func _settle_switch(on: bool) -> void:
	_switch_asked = on
	if on: await turn_on()
	else:
		var answer: Dictionary = await client().set_on(false)
		if not answer.get("ok", false): _say(_failure_text(answer))
	_switch_asked = null
	var settings: Variant = host().get("settings_flow")
	if settings != null and is_instance_valid(settings): settings.refresh()

func _show_list() -> void:
	if not flow.is_open(): return
	var page := ListPage.new()
	var partner := _partner()
	page.partner_name = str(partner.get("name", ""))
	page.partner_look = partner.get("look", {})
	page.boards = _boards()
	page.scope = _scope if _scope == "all" or page.boards.any(func(board: Array) -> bool: return board[0] == _scope) else "all"
	page.sort = _sort
	page.limit = flow.client().limit("friend")
	page.energy_cost = flow.energy().shown()
	page.known = _known
	page.refresh_requested.connect(func() -> void: _read(page, 0, true))
	page.more_requested.connect(func(control: Control) -> void: page.tap(control, func() -> void: await _read(page, page.next_page())))
	page.join_requested.connect(func(row: Dictionary, seat: int, control: Control) -> void: _ask_join(page, row, seat, control))
	page.post_requested.connect(func(_control: Control) -> void: flow._open_challenge(true))
	flow.screen.open_overlay(page)
	_read(page, 0)

## One page of the list: the first replaces it, a later one adds to it. Each read carries its
## serial, scope and sort, so an answer that a newer read or another filter overtook is dropped.
## A pull (`pulled`) while the partner greys the party join reads the lobby too, so a partner who
## accepted the rules or switched on since shows at once.
func _read(page: CanvasLayer, index: int, pulled := false) -> void:
	_scope = page.scope
	_sort = page.sort
	if pulled and partner_waiting(): flow._refresh()
	var serial: int = page.begin_read()
	var asked_scope: String = page.scope
	var asked_sort: String = page.sort
	var answer: Dictionary = await client().list(asked_scope, asked_sort, index)
	if not is_instance_valid(page) or not page.alive() or not page.answered(serial, asked_scope, asked_sort): return
	if answer.get("ok", false): page.show_rows(answer.rows, int(answer.next), index > 0)
	elif index == 0: page.show_failed()
	else: host()._toast(PlayerCopy.PUBLIC_LIST_FAILED)

## [[board key, chapter key]] for every chapter with a board, in the Chapters order: a duel on any
## of them may be listed, and one you can't play yet greys with its reason.
func _boards() -> Array:
	var found: Array = []
	for key: String in ChapterUnlocks.chain():
		var board := Runs.board_key(key)
		if board.is_empty() or (host()._paid_content_hidden() and bool(Registry.descriptor(key).get("premium", false))): continue
		found.append([board, key])
	return found

## What greys a row (services/public_duel_spots.gd greyed): the chapter for you (and your partner,
## whose Start a duel checks theirs), your partner's switch and rules, and the shared limit.
func _known(row: Dictionary) -> Dictionary:
	var public := _public()
	var chapter := Runs.chapter_of(str(row.board))
	return {"chapter_open": not chapter.is_empty() and ChapterUnlocks.open(chapter, host()._chapter_unlocks()),
		"partner_on": public.get("partner_on") != false, "partner_rules": public.get("partner_rules"), "at_limit": int(public.get("running", 0)) >= flow.client().limit("friend")}

## What the lobby says of your partner for a party post or join (Spots.partner_reason).
func _partner_known() -> Dictionary:
	var public := _public()
	return {"partner_on": public.get("partner_on") != false, "partner_rules": public.get("partner_rules")}

## Whether an intact party's partner greys a party post or join now (switch off or rules not accepted).
func partner_waiting() -> bool:
	return not _partner().is_empty() and not Spots.partner_reason(_partner_known()).is_empty()

## The words under Post duel with your partner (Start a duel), or "" when nothing greys it.
func partner_text() -> String:
	var partner := _partner()
	if partner.is_empty(): return ""
	return ListPage.reason_text(Spots.partner_reason(_partner_known()), str(partner.name), flow.client().limit("friend"))

## Whether a lobby hint should read the lobby while `page` covers it: the list or Start a duel,
## while the partner greys a party post or join there (the hint may say they accepted the rules).
func reads_under(page: CanvasLayer) -> bool:
	return (page is ListPage or page is ChallengePage) and partner_waiting()

## A lobby read landed (duels_flow.gd _read_lobby, the one read path) while `page` is up: the list
## and Start a duel draw the partner as it says now (accepted, switched off, or gone, which joins
## and posts alone).
func lobby_read(page: CanvasLayer) -> void:
	if not is_instance_valid(page) or not page.alive(): return
	var partner := _partner()
	if page is ListPage:
		page.partner_name = str(partner.get("name", ""))
		page.partner_look = partner.get("look", {})
		if page.partner_name.is_empty(): page.joining = Spots.ALONE
		page.redraw()
	elif page is ChallengePage: page.set_partner(str(partner.get("name", "")), partner.get("look", {}), partner_text())

## A post or join refused for the partner (their switch, their rules, or no party any more):
## the lobby again, so the page greys with the reason instead of saying it once more on the next tap.
func _partner_refused(answer: Dictionary) -> void:
	if str(answer.get("code", "")) in ["partner_public_off", "partner_rules_required", "party_required"]: flow._refresh()

func _ask_join(page: CanvasLayer, row: Dictionary, seat: int, control: Control) -> void:
	var reason: String = page.reason_of(row)
	var spot := Spots.spot_for(Spots.open_flags(row.sides), page.joining, seat)
	if reason.is_empty() and spot.has("reason"): reason = str(spot.reason)
	if not reason.is_empty():
		host()._toast(ListPage.reason_text(reason, page.partner_name, page.limit))
		return
	if flow.energy().blocks(page, control): return
	var partner := _partner()
	var names := {"title": _chapter_title(str(row.chapter)), "partner": str(partner.get("name", "")), "partner_look": partner.get("look", {}), "energy_cost": page.energy_cost}
	# A tapped ring is sent as tapped; Join lets the server pick again, so a spot taken meanwhile finds the next one.
	page.hold_modal(Sheets.join(page.root, row, int(spot.seat), page.joining, names, func() -> void:
		page.tap(control, func() -> void: await _join(page, row, seat, page.joining, false, control))))

func _join(page: CanvasLayer, row: Dictionary, seat: int, joining: String, retried := false, control: Control = null) -> void:
	if OfflineHold.refuse(host()._toast): return
	var asked := "join|%s|%d|%s" % [row.duel_id, seat, joining]
	var answer := await _keyed(asked, func(key: String) -> Dictionary: return await client().join(str(row.board), str(row.duel_id), joining, seat, key))
	if not is_instance_valid(page) or not page.alive() or not flow.is_open(): return
	if _rules_first(answer, retried, func() -> void: if is_instance_valid(page) and page.alive(): await _join(page, row, seat, joining, true, control)): return
	# The partner's wait shows under the row's Join, the list's own note; an empty meter opens its card.
	if str(answer.get("code", "")) == "partner_energy_empty":
		page.update_row(str(row.duel_id), row, flow.energy().waiting_words(str(_partner().get("name", ""))))
		return
	if flow.energy().refused(page, answer, control): return
	if answer.get("ok", false):
		page.close()
		flow._refresh()
		flow._open_duel(answer.duel)
		return
	match str(answer.get("code", "")):
		"spot_taken":
			var fresh: Dictionary = answer.get("row", {})
			page.update_row(str(row.duel_id), fresh, PlayerCopy.PUBLIC_SPOT_TAKEN)
			if fresh.is_empty(): host()._toast(PlayerCopy.PUBLIC_GONE)
		"duel_not_found", "duel_not_running", "public_closed":
			page.update_row(str(row.duel_id), {})
			host()._toast(PlayerCopy.PUBLIC_GONE)
		_:
			host()._toast(_failure_text(answer))
			_partner_refused(answer)

## Start a duel's Post duel: `joining` "alone" or "party" on `chapter`. A switch turned off,
## or rules not yet accepted, go through the first-time card first; a posted duel opens at once.
func post(page: CanvasLayer, joining: String, chapter: String, retried := false, control: Control = null) -> void:
	if OfflineHold.refuse(host()._toast): return
	var again := func() -> void: if is_instance_valid(page) and page.alive(): await post(page, joining, chapter, true, control)
	if not switched_on():
		_first_time(again)
		return
	var board := Runs.board_key(chapter)
	var answer := await _keyed("post|%s|%s" % [board, joining], func(key: String) -> Dictionary: return await client().post(board, joining, key))
	if not is_instance_valid(page) or not page.alive() or not flow.is_open(): return
	if _rules_first(answer, retried, again): return
	if not answer.get("ok", false):
		if flow.energy().refused(page, answer, control, str(_partner().get("name", ""))): return
		host()._toast(_failure_text(answer))
		_partner_refused(answer)
		return
	host()._toast(PlayerCopy.PUBLIC_POSTED)
	page.close()
	flow._refresh()
	flow._open_duel(answer.duel)

## A stranger's card from the duel page: the player in seat `slot` of side `index`.
func stranger(page: CanvasLayer, view: Dictionary, index: int, slot: int) -> void:
	if not DuelModel.seat_stranger(view, index, slot): return
	var seat := index * 2 + slot
	var name := DuelModel.seat_name(view, index, slot, flow._name_of)
	var partner: bool = index == view.mine
	var over: bool = view.status != "running"
	var actions := {
		"report": func() -> void: page.hold_modal(Sheets.report(page.root, name, func(reason: String) -> void: _report(view, seat, reason))),
		"block": func() -> void: page.hold_modal(Sheets.block(page.root, name, partner and not over, func() -> void: _block(page, view, seat))),
	}
	if over: actions["befriend"] = func() -> void: _befriend(view, seat)
	var who := {"name": name, "partner": partner, "color": "peach" if slot == 0 else "mint", "look": DuelModel.looks(view, index)[slot], "over": over,
		"friend_sent": _befriended.has("%s|%d" % [view.duel_id, seat]), "duel_id": view.duel_id}
	var settings: Dictionary = host().settings_flow.show_settings() if "settings_flow" in host() and host().settings_flow != null else {}
	page.hold_modal(Sheets.stranger(page.root, who, settings, actions))

func _report(view: Dictionary, seat: int, reason: String) -> void:
	if OfflineHold.refuse(host()._toast): return
	var answer := await _keyed("report|%s|%d|%s" % [view.duel_id, seat, reason], func(key: String) -> Dictionary: return await client().report(str(view.board), str(view.duel_id), seat, reason, key))
	host()._toast(PlayerCopy.PUBLIC_REPORTED if answer.get("ok", false) else _failure_text(answer))

func _block(page: CanvasLayer, view: Dictionary, seat: int) -> void:
	if OfflineHold.refuse(host()._toast): return
	var answer: Dictionary = await client().block(str(view.board), str(view.duel_id), seat)
	if not answer.get("ok", false):
		host()._toast(_failure_text(answer))
		return
	host()._toast(PlayerCopy.PUBLIC_BLOCKED)
	if not flow.is_open(): return
	flow._refresh()
	# Blocking your partner left the duel: the page shows it as the server has it now.
	if answer.get("left", false) and is_instance_valid(page) and page.alive():
		var fresh: Dictionary = await flow.client().duel(str(view.board), str(view.duel_id))
		if fresh.get("ok", false) and is_instance_valid(page): flow._show_duel(page, fresh.duel)

func _befriend(view: Dictionary, seat: int) -> void:
	if OfflineHold.refuse(host()._toast): return
	var answer: Dictionary = await client().befriend(str(view.board), str(view.duel_id), seat)
	if answer.get("ok", false): _befriended["%s|%d" % [view.duel_id, seat]] = true
	host()._toast(PlayerCopy.PUBLIC_FRIEND_SENT if answer.get("ok", false) else _failure_text(answer))

## Sends `request` with the key kept for `asked`, made on its first try, dropped once the server answers it.
func _keyed(asked: String, request: Callable) -> Dictionary:
	if not _keys.has(asked): _keys[asked] = RoomsApi.new_key()
	var answer: Dictionary = await request.call(_keys[asked])
	var status := int(answer.get("status", 0))
	if answer.get("ok", false) or (status >= 400 and status < 500): _keys.erase(asked)
	return answer

## The words for a refused public duel request.
func _failure_text(answer: Dictionary) -> String:
	var partner := str(_partner().get("name", PlayerCopy.DUEL_PARTNER))
	match str(answer.get("code", "")):
		"public_duels_off": return PlayerCopy.PUBLIC_TURN_ON_FIRST
		"partner_public_off": return PlayerCopy.PUBLIC_PARTNER_OFF % partner
		"partner_rules_required": return PlayerCopy.PUBLIC_PARTNER_RULES % partner
		"public_paused": return PlayerCopy.PUBLIC_PAUSED
		"public_list_full": return PlayerCopy.PUBLIC_LIST_FULL
		"terms_acceptance_required": return PlayerCopy.PUBLIC_RULES_FIRST
		"duel_limit_reached": return PlayerCopy.DUELS_LIMIT % flow.client().limit("friend")
		"party_required": return PlayerCopy.DUELS_NO_PARTY
		"chapter_creation_disabled": return PlayerCopy.DUELS_CHAPTER_CLOSED
		"duel_not_found", "duel_not_running": return PlayerCopy.PUBLIC_GONE
	return PlayerCopy.DUELS_ACTION_FAILED

func _say(text: String) -> bool:
	host()._toast(text)
	return false

static func _chapter_title(key: String) -> String:
	return RoomChapterTitle.title(key, str(Registry.descriptor(key).get("title", key)))
