extends SceneTree
## Public duels on the phone: the spot rules against the server's own table
## (tests/fixtures/public_duels/spots.json), the replies the phone keeps (list
## rows, a public duel view, the lobby's switch part, the held duel extra and
## its receipt line), how a seat is named (never by a stranger's id), and every
## surface that shows one: the list (board 2), the join cards (3, 4), Start a
## duel's Anyone (5A), a lobby tile (5C), the duel page with its stranger card
## and block card (6.3, 6.4), the first-time card (6.2), the result's held
## extra, Settings' rows (6.1) and Reports & blocked players. Layouts are checked
## at phone sizes. Synthetic ids only.
const SafeArea = preload("res://presentation/safe_area.gd")
const Spots = preload("res://services/public_duel_spots.gd")
const PublicClient = preload("res://services/public_duels_client.gd")
const DuelsClient = preload("res://services/duels_client.gd")
const DuelModel = preload("res://services/duel_model.gd")
const ListPage = preload("res://presentation/duels/public_list_page.gd")
const Sheets = preload("res://presentation/duels/public_sheets.gd")
const Seats = preload("res://presentation/duels/public_seats.gd")
const DuelsScreen = preload("res://presentation/duels/duels_screen.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const ResultPage = preload("res://presentation/duels/duel_result_page.gd")
const ChallengePage = preload("res://presentation/duels/duel_challenge_page.gd")
const SafetyClient = preload("res://services/safety_client.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Breakdown = preload("res://presentation/pollen_breakdown.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PartnerFriends = preload("res://services/partner_friends.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const ME := "MMMMMMMMMMMMMMMMMMMMMM"
const MAYA := "AAAAAAAAAAAAAAAAAAAAAA"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const BOARD := "sleeping-lighthouse@2"
const SCREENS := [[Vector2i(2340, 1080), Vector4.ZERO, "2340x1080 phone"], [Vector2i(1600, 738), Vector4.ZERO, "1600x738 phone"], [Vector2i(1280, 720), Vector4.ZERO, "1280x720 phone"],
	[Vector2i(2400, 1080), Vector4(110, 0, 0, 30), "2400x1080 phone, cutout and gesture bar"], [Vector2i(2034, 1398), Vector4(0, 252, 0, 63), "iPhone Duo outer"]]

var checks := 0
var failures := 0

## Answers every request with `answer`, and keeps what was asked.
class FakeApi extends Node:
	var answer: Dictionary = {}
	var asked: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		asked.append([method, path, body])
		return answer

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _settle() -> void:
	for i in range(4): await process_frame

func _run() -> void:
	_spots()
	_replies()
	_names()
	_receipts()
	_safety()
	await _leave()
	await _surfaces()
	print("AFTER YOU PUBLIC DUELS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

# The spot rules ---------------------------------------------------------------

func _spots() -> void:
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/public_duels/spots.json"))
	_check(table is Dictionary and table.get("cases") is Array and table.cases.size() >= 10, "The shared spot table reads")
	if not table is Dictionary: return
	for item: Dictionary in table.cases:
		var answer := Spots.spot_for(item.seats, str(item.as), int(item.wanted) if item.wanted != null else -1)
		if item.has("seat"): _check(int(answer.get("seat", -1)) == int(item.seat), "%s: seat %s, got %s" % [item.name, item.seat, answer])
		else: _check(str(answer.get("reason", "")) == str(item.reason), "%s: %s, got %s" % [item.name, item.reason, answer])
	var row := _row([false, true, true, true], [1, 0])
	_check(Spots.greyed(row, Spots.ALONE, {}) == "", "A row with a spot beside a player is open to a player alone")
	_check(Spots.greyed(row, Spots.PARTY, {"partner_on": true}) == "", "With a whole pair open it is open to a party too")
	_check(Spots.greyed(row, Spots.PARTY, {"partner_on": false}) == Spots.PARTNER_OFF, "A partner who has public duels off greys it for the party")
	_check(Spots.greyed(row, Spots.ALONE, {"chapter_open": false}) == Spots.CHAPTER, "A chapter you can't play greys it")
	_check(Spots.greyed(row, Spots.ALONE, {"at_limit": true}) == Spots.LIMIT, "Ten duels going greys it")
	var mine := row.duplicate(true)
	mine.mine = true
	_check(Spots.greyed(mine, Spots.ALONE, {"chapter_open": false}) == Spots.MINE, "A duel you're in says so first")
	_check(Spots.greyed(_row([false, false, false, true], [2, 1]), Spots.PARTY, {"partner_on": true}) == Spots.ONE_LEFT, "One spot left greys a party")
	_check(Spots.greyed(_row([false, true, false, true], [2, 1]), Spots.PARTY, {"partner_on": true}) == Spots.SPLIT, "Spots in different pairs grey a party")

## A list row as the server sends it, read through the client's check. `open`: four seat flags; `steps`: each side's.
func _row(open: Array, steps: Array, labels: Array = ["Kite", "", "", ""], posted: int = 0) -> Dictionary:
	var sides: Array = []
	for index in range(2):
		var seats: Array = []
		for slot in range(2):
			var seat := index * 2 + slot
			seats.append({"open": open[seat], "label": null if open[seat] or str(labels[seat]).is_empty() else labels[seat]} if not open[seat] else {"open": true, "label": null})
		sides.append({"steps": steps[index], "seats": seats})
	return PublicClient.valid_row({"duel_id": "b".repeat(32), "board": BOARD, "posted_ms": posted, "open_until_ms": posted + 7 * 86_400_000, "steps": 12, "mine": false, "sides": sides})

# What the phone keeps -----------------------------------------------------------

func _replies() -> void:
	var row := _row([false, true, true, true], [1, 0])
	_check(not row.is_empty() and row.sides[0].seats[0].label == "Kite" and row.sides[0].seats[1].open, "A list row reads, with its seats")
	_check(PublicClient.valid_row({"duel_id": "b".repeat(32), "board": BOARD}).is_empty(), "A row without its seats is refused")
	var bad := {"duel_id": "b".repeat(32), "board": BOARD, "posted_ms": 1, "open_until_ms": 2, "steps": 12, "sides": [{"steps": 0, "seats": [{"open": false, "label": 5}, {"open": true}]}, {"steps": 0, "seats": [{"open": true}, {"open": true}]}]}
	_check(PublicClient.valid_row(bad).is_empty(), "A seat whose label is not text is refused")
	var page := PublicClient.valid_list({"schema_version": 1, "page": 0, "next": 1, "rows": [_wire_row()]})
	_check(page.get("next") == 1 and page.rows.size() == 1, "A list page reads with its next page")
	_check(PublicClient.valid_list({"schema_version": 1, "page": 0, "next": null, "rows": []}).get("next") == -1, "The last page has no next")
	_check(PublicClient._taken_row({"error": {"code": "spot_taken", "row": _wire_row()}}).duel_id == "b".repeat(32), "A spot_taken refusal carries the row as it is now")
	_check(PublicClient._taken_row({"error": {"code": "spot_taken", "row": null}}).is_empty(), "A closed duel's refusal carries no row")
	var view := DuelsClient.valid_view(_public_view())
	_check(view.has("public") and view.sides[0].seats[0].you and not view.sides[0].seats[1].open and view.sides[1].seats[0].label == "Kite", "A public duel view keeps its seats and list times")
	var broken := _public_view()
	broken.sides[1].erase("seats")
	_check(DuelsClient.valid_view(broken).is_empty(), "A public duel with a side missing its seats is refused")
	var lobby := DuelsClient.valid_lobby({"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [],
		"public": {"version": 1, "on": true, "show_name": false, "partner_on": null, "paused": false, "running": 3}})
	_check(lobby.public == {"on": true, "show_name": false, "partner_on": null, "paused": false, "running": 3}, "The lobby keeps its public part")
	_check(not DuelsClient.valid_lobby({"schema_version": 1, "party": {"partner": null, "intact": false, "invites_in": [], "invite_out": null}, "duels": []}).has("public"), "A lobby from a server without public duels has no public part")
	_check(DuelsClient._held({"amount": 40, "state": "forfeit", "reason": "left"}) == {"amount": 40, "state": "forfeit", "reason": "left"} and DuelsClient._held({"amount": 40, "state": "kept"}).is_empty(), "The held extra reads only in its three states")
	_check(DuelsClient._pay({"turns": 2, "plain": 100, "blooms": 0, "duel": 0, "duel_percent": 50, "boost": 0, "boost_percent": 0, "total": 100, "held": 50}).held == 50, "A public duel's pay keeps its held part")

static func _wire_row() -> Dictionary:
	return {"duel_id": "b".repeat(32), "board": BOARD, "posted_ms": 1, "open_until_ms": 2, "steps": 12, "mine": false,
		"sides": [{"steps": 1, "seats": [{"open": false, "label": "Kite", "look": {"hat": "daisy"}}, {"open": true, "label": null}]}, {"steps": 0, "seats": [{"open": true, "label": null}, {"open": true, "label": null}]}]}

## A public duel as the server sends it to this player, beside Kite with the other pair open.
static func _public_view(mine_open: bool = false, other: Array = [false, true]) -> Dictionary:
	return {"schema_version": 1, "duel_id": "c".repeat(32), "kind": "friend", "board": BOARD, "status": "running", "steps": 12,
		"created_ms": 1, "accepted_ms": 2, "updated_ms": 3, "mine": 0, "ghost": null, "result": null, "eligible": true,
		"public": {"posted_ms": 1, "open_until_ms": 9, "seats_open": 1 + int(mine_open)},
		"sides": [{"members": [ME, null], "you": true, "steps": 0 if mine_open else 1, "ticks": 630, "turn": 0, "finished": false, "left": false, "check": "none", "room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": true,
			"seats": [{"open": false, "you": true, "label": null}, {"open": mine_open, "you": false, "label": null}], "looks": [{}, {"hat": "daisy"}]},
			{"members": [null, null], "you": false, "steps": 1, "ticks": 630, "turn": 1, "finished": false, "left": false, "check": "none",
			"seats": [{"open": other[0], "you": false, "label": null if other[0] else "Kite"}, {"open": other[1], "you": false, "label": null}], "looks": [{"hat": "daisy"}, {}]}]}

# Names --------------------------------------------------------------------------

func _names() -> void:
	var name_of := func(id: Variant) -> String: return "You" if id == ME else "Maya" if id == MAYA else ""
	var view := DuelsClient.valid_view(_public_view())
	_check(DuelModel.pair_title(view, 1, name_of) == "Kite + open spot", "A named stranger with an open spot: %s" % DuelModel.pair_title(view, 1, name_of))
	_check(DuelModel.pair_title(view, 0, name_of) == "You + A player", "Your unnamed stranger partner: %s" % DuelModel.pair_title(view, 0, name_of))
	var open_pair := DuelsClient.valid_view(_public_view(false, [true, true]))
	_check(DuelModel.pair_title(open_pair, 1, name_of) == PlayerCopy.PUBLIC_OPEN_PAIR and DuelModel.turn_line(open_pair, 1, name_of) == PlayerCopy.PUBLIC_NOBODY_YET, "An open pair says so, with Nobody yet")
	var strangers := _public_view(false, [false, false])
	strangers.sides[1].seats[0].label = null
	var both := DuelsClient.valid_view(strangers)
	_check(DuelModel.pair_title(both, 1, name_of) == PlayerCopy.LEADERBOARD_A_PAIR, "Two unnamed strangers are A pair, as the leaderboard says")
	var alone := DuelsClient.valid_view(_public_view(true))
	alone.sides[0].turn = -1
	_check(DuelModel.your_turn(alone, ME) and DuelModel.turn_line(alone, 0, name_of) == PlayerCopy.DUEL_YOUR_TURN, "Alone on a new pair, you go first")
	_check(DuelModel.partner_name(alone, ME, name_of) == "", "An open seat beside you has no partner name")
	var waiting := DuelsClient.valid_view(_public_view(true))
	waiting.sides[0].turn = 1
	_check(not DuelModel.your_turn(waiting, ME) and DuelModel.turn_line(waiting, 0, name_of) == PlayerCopy.PUBLIC_WAITING_PARTNER, "The next turn belongs to a partner who hasn't joined")
	_check(DuelModel.looks(view, 1)[0] == {"hat": "daisy"} and DuelModel.looks(view, 1)[1] == {}, "A stranger wears their look; an open seat wears nothing")
	_check(not DuelModel.seat_stranger(view, 0, 0) and DuelModel.seat_stranger(view, 0, 1) and DuelModel.seat_stranger(view, 1, 0), "You are no stranger; the other seats are")
	var ended := DuelsClient.valid_view(_public_view())
	ended.status = "unfinished"
	ended.result = {"outcome": "none", "reason": "nobody_joined", "margin_ticks": -1}
	_check(DuelModel.result_line(ended) == PlayerCopy.PUBLIC_RESULT_NOBODY, "Nobody joined has its own line")
	var paid := DuelModel.pay_lines({}, {}, true, false, {"amount": 60, "state": "paid", "reason": ""})
	_check(paid.lines == [[PlayerCopy.PUBLIC_HELD_PAID, 60]] and paid.total == 60, "A paid held extra adds to the total")
	var lost := DuelModel.pay_lines({}, {}, true, false, {"amount": 60, "state": "forfeit", "reason": "left"})
	_check(lost.lines.is_empty() and lost.note == PlayerCopy.PUBLIC_HELD_LEFT and lost.note_amount == 60, "A forfeited held extra says why, outside the total")
	_check(ListPage.status_line(_row([false, true, true, true], [1, 0])) == "Kite has played 1 step", "One named player's progress")
	_check(ListPage.status_line(_row([false, false, false, true], [2, 2], ["", "", "Juniper", ""])) == "Both pairs have played 2 steps", "Both pairs level")
	_check(ListPage.status_line(_row([false, false, true, true], [5, 0], ["Pebble", "", "", ""])) == "5 of 12 steps", "A pair with an unnamed player")
	_check(ListPage.posted_text(0, 4 * 60_000) == "Posted 4 min ago" and ListPage.posted_text(0, 3 * 3_600_000) == "Posted 3 h ago", "Posted times read as drawn")
	_check(ListPage.reason_text(Spots.PARTNER_OFF, "Maya", 10) == "Maya hasn't turned on public duels" and ListPage.reason_text(Spots.LIMIT, "", 10) == "You have 10 duels going", "Greyed lines name the reason")

# Receipts -----------------------------------------------------------------------

func _receipts() -> void:
	var turn := {"kind": "bank", "amount": 100, "total": 100, "bonuses": [], "bonus_percent": 0, "bloom": 1, "bloom_extra": 0, "boost_percent": 0, "boost": 0, "base": 100, "bonus_percents": [], "duel_held": 50, "duel_percent": 50}
	var kept := PollenWallet.checked_receipt({"schema_version": 1, "earned": 100, "balance": 900, "turn": turn, "clears": []})
	_check(int(kept.get("turn", {}).get("duel_held", 0)) == 50, "A public duel turn's receipt keeps its held extra")
	var rows := Breakdown.rows({"schema_version": 1, "earned": 100, "turn": turn, "clears": []})
	_check(rows.any(func(row: Dictionary) -> bool: return row.kind == "reason" and str(row.label).contains("paid when the duel ends")), "The turn card says the duel extra is paid when the duel ends")
	_check(rows.filter(func(row: Dictionary) -> bool: return row.kind == "total")[0].value == "100", "This turn's total leaves the held extra out")

# Safety -------------------------------------------------------------------------

func _safety() -> void:
	_check(SafetyClient.valid_version("2026-11-03") and SafetyClient.valid_version(SafetyClient.TERMS_VERSION) and not SafetyClient.valid_version("soon"), "Any dated rules version reads")
	_check(SafetyClient.valid_duel_blocks([{"handle": "h".repeat(22), "label": null}, {"handle": "k".repeat(22), "label": "Kite"}]).size() == 2, "Duel blocks read by handle")
	_check(SafetyClient.valid_duel_blocks([{"handle": "bad id!", "label": null}]) == null, "A handle that is not one is refused")
	for path: String in ["/v1/safety/config", "/v1/safety/terms", "/v1/safety/blocks"]:
		_check(RoomsApi.capability_headers(HTTPClient.METHOD_GET, path).has(RoomsApi.PUBLIC_DUELS_SAFETY_HEADER), "%s asks with the public duels header, so the server sends their rules and duel blocks" % path)
	_check(not RoomsApi.capability_headers(HTTPClient.METHOD_GET, "/v1/friends").has(RoomsApi.PUBLIC_DUELS_SAFETY_HEADER), "Other routes do not send it")

# A seat given back ------------------------------------------------------------

func _leave() -> void:
	var api := FakeApi.new()
	var client: RefCounted = DuelsClient.new(api, "", "user://test-public-duels.json")
	client._lobby = {"party": {}, "duels": [DuelsClient.valid_view(_public_view())], "limits": {}}
	api.answer = {"ok": true, "status": 200, "data": {"schema_version": 1, "duel": null, "left": true}}
	var answer: Dictionary = await client.act(BOARD, "c".repeat(32), "leave")
	_check(answer.ok and answer.left and (answer.duel as Dictionary).is_empty(), "A seat given back answers left with no duel")
	_check(client.last_lobby().duels.is_empty(), "and the duel leaves the kept lobby")
	var post := PublicClient.new(api, client)
	api.answer = {"ok": false, "status": 409, "code": "spot_taken", "data": {"error": {"code": "spot_taken", "row": _wire_row()}}}
	var taken: Dictionary = await post.join(BOARD, "b".repeat(32), Spots.ALONE, -1, "k".repeat(22))
	_check(not taken.ok and taken.code == "spot_taken" and taken.row.duel_id == "b".repeat(32), "A spot taken first comes back with its row")
	_check(api.asked[-1][2] == {"schema_version": 1, "idempotency_key": "k".repeat(22), "as": "alone", "seat": null}, "Join sends its key and lets the server pick: %s" % [api.asked[-1][2]])
	api.free()

# Surfaces -----------------------------------------------------------------------

func _surfaces() -> void:
	var original := {"size": root.size, "content_scale_size": root.content_scale_size, "content_scale_mode": root.content_scale_mode, "content_scale_aspect": root.content_scale_aspect}
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	for screen: Array in SCREENS: await _screen(screen[0], screen[1], screen[2])
	SafeArea.simulate(Rect2())
	SafeArea.poll(self)
	for property: String in original: root.set(property, original[property])
	await _settle()

func _screen(size: Vector2i, insets: Vector4, name: String) -> void:
	root.size = size
	SafeArea.simulate(Rect2(insets.x, insets.y, size.x - insets.x - insets.z, size.y - insets.y - insets.w))
	SafeArea.poll(self)
	await _settle()
	var safe := SafeArea.rect(root)
	var name_of := func(id: Variant) -> String: return "You" if id == ME else "Maya" if id == MAYA else ""
	var lobby := DuelsScreen.new()
	lobby.me = ME
	lobby.name_of = name_of
	lobby.public_shown = true
	root.add_child(lobby)
	await _settle()
	lobby.show_lobby(DuelsClient.valid_lobby({"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_public_view()],
		"public": {"version": 1, "on": false, "show_name": false, "partner_on": true, "paused": false, "running": 1}}))
	await _settle()
	var row := lobby.root.find_child("DuelsPublic", true, false) as Button
	_check(row != null and row.is_visible_in_tree() and _inside(row, safe), "%s: the lobby's Public duels row shows" % name)
	_check(lobby.root.find_child("PublicTag", true, false) != null, "%s: a public duel's tile wears its tag" % name)
	_check(_texts(row).has(PlayerCopy.PUBLIC_DUELS_ROW_OFF), "%s: with the switch off the row invites you in" % name)
	var asked := [false]
	lobby.public_requested.connect(func() -> void: asked[0] = true)
	row.pressed.emit()
	_check(asked[0], "%s: the row asks for the list" % name)
	# The list (board 2), Alone and With Maya.
	var page := ListPage.new()
	page.partner_name = "Maya"
	page.boards = [[BOARD, BOARD]]
	page.known = func(_row: Dictionary) -> Dictionary: return {"chapter_open": true, "partner_on": true, "at_limit": false}
	lobby.open_overlay(page)
	await _settle()
	page.show_rows([_row([false, true, true, true], [1, 0]), _row([false, false, false, true], [2, 2], ["", "", "Juniper", ""]), _row([false, true, false, true], [2, 2], ["", "", "Moss", ""])], 1)
	await _settle()
	_check(_fits(page, "PublicList"), "%s: the list page's header and filters fit" % name)
	var joins := page.root.find_children("PublicJoin", "Button", true, false)
	_check(joins.size() == 3 and joins.all(func(button: Button) -> bool: return not button.disabled), "%s: every row joins alone" % name)
	_check(page.root.find_child("PublicMore", true, false) != null, "%s: Show more reads the next page" % name)
	for button: Button in joins: _check(_inside(button, safe), "%s: Join is inside the safe area" % name)
	page._set_joining(Spots.PARTY)
	await _settle()
	joins = page.root.find_children("PublicJoin", "Button", true, false)
	_check(not joins[0].disabled and joins[1].disabled and joins[2].disabled, "%s: with Maya, only the duel with a whole open pair joins" % name)
	var reasons := page.root.find_children("PublicReason", "Label", true, false).map(func(label: Label) -> String: return label.text)
	_check(reasons.has(PlayerCopy.PUBLIC_REASON_ONE_LEFT) and reasons.has(PlayerCopy.PUBLIC_REASON_SPLIT), "%s: greyed rows say why: %s" % [name, reasons])
	var tapped := []
	page.join_requested.connect(func(item: Dictionary, seat: int, _control: Control) -> void: tapped.append(seat))
	joins[0].pressed.emit()
	_check(tapped == [-1], "%s: Join asks for the server's pick" % name)
	page.update_row("b".repeat(32), _row([false, false, true, true], [1, 0]), PlayerCopy.PUBLIC_SPOT_TAKEN)
	await _settle()
	_check(page.root.find_children("PublicReason", "Label", true, false).any(func(label: Label) -> bool: return label.text == PlayerCopy.PUBLIC_SPOT_TAKEN), "%s: a spot taken first says so on its row" % name)
	# The join cards (boards 3 and 4).
	var confirmed := [0]
	for case: Array in [[Spots.ALONE, 1], [Spots.ALONE, 2], [Spots.PARTY, 2]]:
		var card := Sheets.join(page.root, _row([false, true, true, true], [1, 0]), case[1], case[0], {"title": "Sleeping Lighthouse", "partner": "Maya"}, func() -> void: confirmed[0] += 1)
		page.hold_modal(card)
		await _settle()
		var go := card.find_child("PublicJoinConfirm", true, false) as Button
		_check(go != null and _inside(go, safe), "%s: the %s join card's Join and play shows" % [name, case[0]])
		var title: String = card.title_label.text
		_check(title == ("Join beside Kite?" if case[1] == 1 else "Take a pair spot?" if case[0] == Spots.ALONE else "Join with Maya?"), "%s: the join card reads %s" % [name, title])
		go.pressed.emit()
		await _settle()
	_check(confirmed[0] == 3, "%s: Join and play runs after the card closes" % name)
	page.close()
	await _settle()
	# Start a duel's Anyone (board 5A).
	var start := ChallengePage.new()
	start.chapters = [BOARD]
	start.public_offered = true
	start.anyone = true
	start.partner_name = "Maya"
	lobby.open_overlay(start)
	await _settle()
	start._pick_chapter(BOARD)
	await _settle()
	var send := start.root.find_child("DuelSend", true, false) as Button
	_check(send.text == PlayerCopy.PUBLIC_POST_DUEL and not send.disabled, "%s: Anyone posts, with Post duel" % name)
	_check(start.root.find_child("PublicPostPreview", true, false) != null, "%s: the seats others will see show under Post as" % name)
	var posted := []
	start.post_requested.connect(func(joining: String, chapter: String, _control: Control) -> void: posted.append([joining, chapter]))
	send.pressed.emit()
	_check(posted == [["party", BOARD]], "%s: Post duel posts with Maya on the chapter" % name)
	start.close()
	await _settle()
	# The duel page (boards 3 and 6), its stranger card and block card.
	var duel := DuelPage.new()
	duel.me = ME
	duel.name_of = name_of
	duel.view = DuelsClient.valid_view(_public_view())
	lobby.open_overlay(duel)
	await _settle()
	duel.held = {"amount": 45, "state": "running", "reason": ""}
	await _settle()
	_check(duel.root.find_child("PublicTag", true, false) != null, "%s: the duel page wears the PUBLIC tag" % name)
	var held := duel.root.find_child("DuelHeld", true, false) as Label
	_check(held != null and held.text.contains("45"), "%s: the duel extra held so far shows" % name)
	var card := duel.root.find_child("DuelTurnCard", true, false) as Control
	_check(card != null and _inside(card, safe), "%s: the turn card shows whole (%s in %s)" % [name, card.get_global_rect() if card != null else Rect2(), safe])
	var strangers := []
	duel.stranger_requested.connect(func(_view: Dictionary, index: int, slot: int) -> void: strangers.append([index, slot]))
	var kite := duel.root.find_child("DuelSeat1_0", true, false)
	_check(kite is Button, "%s: a stranger's pip is a button" % name)
	if kite is Button: kite.pressed.emit()
	_check(strangers == [[1, 0]], "%s: it asks for the stranger's card" % name)
	_check(not (duel.root.find_child("DuelSeat0_0", true, false) is Button), "%s: your own pip is no button" % name)
	var actions := {"report": func() -> void: pass, "block": func() -> void: pass}
	var stranger := Sheets.stranger(duel.root, {"name": "Kite", "partner": false, "color": "peach", "over": false, "duel_id": "c".repeat(32)}, {}, actions)
	await _settle()
	_check(stranger.find_child("PublicReport", true, false) != null and stranger.find_child("PublicBlock", true, false) != null and stranger.find_child("PublicAddFriend", true, false) == null, "%s: a running duel's stranger card has Report and Block, no Add friend" % name)
	stranger.close()
	actions["befriend"] = func() -> void: pass
	stranger = Sheets.stranger(duel.root, {"name": "Kite", "partner": true, "color": "peach", "over": true, "duel_id": "c".repeat(32)}, {}, actions)
	await _settle()
	_check(stranger.find_child("PublicAddFriend", true, false) != null, "%s: after the duel, Add friend" % name)
	stranger.close()
	var block := Sheets.block(duel.root, "Kite", true, func() -> void: pass)
	await _settle()
	_check((block.find_child("PublicBlockConfirm", true, false) as Button).text == PlayerCopy.PUBLIC_BLOCK_LEAVE, "%s: blocking your partner reads Block and leave" % name)
	block.close()
	var first := Sheets.first_time(duel.root, false, func(_named: bool) -> void: pass)
	await _settle()
	_check(first.find_child("PublicShowNameSwitch", true, false) != null and _inside(first.find_child("PublicTurnOn", true, false), safe), "%s: the first-time card has the name switch and Turn on" % name)
	first.close()
	duel.close()
	await _settle()
	# The result's held extra.
	var result := ResultPage.new()
	result.me = ME
	result.name_of = name_of
	var ended := DuelsClient.valid_view(_public_view())
	ended.status = "unfinished"
	ended.result = {"outcome": "none", "reason": "nobody_joined", "margin_ticks": -1}
	result.view = ended
	result.held = {"amount": 30, "state": "forfeit", "reason": "nobody_joined"}
	lobby.open_overlay(result)
	await _settle()
	_check(result.root.find_child("DuelHeldNote", true, false) != null, "%s: a held extra not paid says why" % name)
	result.close()
	lobby.close()
	await _settle()

func _fits(page: CanvasLayer, page_name: String) -> bool:
	var scroll := page.root.find_child(page_name + "Scroll", true, false) as ScrollContainer
	return scroll != null and scroll.get_v_scroll_bar().max_value <= scroll.size.y + 0.5

static func _inside(control: Control, safe: Rect2) -> bool:
	return control != null and safe.grow(0.5).encloses(control.get_global_rect())

static func _texts(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
