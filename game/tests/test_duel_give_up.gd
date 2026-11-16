extends SceneTree
## Give up, the Your duels tabs and the time left tag (board duels-concepts forfeit-finished, Option A):
## how services/duels_client.gd reads `ends_in_ms` and a side's `give_up`, what services/duel_model.gd
## says of them (the tag's rounding, which tab a duel sits on, why a challenge never started, what Give
## up shows), the lobby's Going and Finished tabs with their counts and Not played, the tags on every
## open challenge and tile, and the duel page's Give up states (A3 to A7) with the result's words.
## No requests; synthetic ids only.
const DuelModel = preload("res://services/duel_model.gd")
const Client = preload("res://services/duels_client.gd")
const Lobby = preload("res://presentation/duels/duels_screen.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const ME := "MMMMMMMMMMMMMMMMMMMMMM"
const MAYA := "AAAAAAAAAAAAAAAAAAAAAA"
const FINN := "FFFFFFFFFFFFFFFFFFFFFF"
const NOOR := "NNNNNNNNNNNNNNNNNNNNNN"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const BOARD := "sleeping-lighthouse@2"
const HOUR := 3_600_000
const DAY := 24 * HOUR

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _name_of(id: Variant) -> String:
	return {ME: PlayerCopy.DUEL_YOU, MAYA: "Maya", FINN: "Finn", NOOR: "Noor"}.get(id, "")

## A duel as the server sends it, from this player's side 0. `id`: two hex characters, repeated.
func _wire(id: String, status: String = "running", own: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var side := {"members": [ME, MAYA], "you": true, "steps": 3, "ticks": 3240, "turn": 0, "finished": false, "left": false, "check": "none", "room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": true}
	if status == "running": side["give_up"] = {"mode": "ask", "asked": null, "asked_at": null}
	side.merge(own, true)
	var view := {"schema_version": 1, "duel_id": id.repeat(16), "kind": "friend", "board": BOARD, "status": status, "steps": 12,
		"created_ms": 1, "accepted_ms": 2, "updated_ms": 3, "mine": 0, "ghost": null, "result": null, "eligible": true,
		"sides": [side, {"members": [FINN, NOOR], "you": false, "steps": 2, "ticks": 2760, "turn": 1, "finished": false, "left": false, "check": "none"}]}
	if status in ["running", "challenged"]: view["ends_in_ms"] = 29 * DAY
	view.merge(extra, true)
	return view

func _run() -> void:
	_client()
	_time_left()
	_sections()
	_give_up_state()
	await _lobby()
	await _page()
	print("AFTER YOU DUEL GIVE UP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _client() -> void:
	var before := Time.get_ticks_msec()
	var view := Client.valid_view(_wire("1a"))
	_check(int(view.ends_at) >= before + 29 * DAY and int(view.ends_at) <= Time.get_ticks_msec() + 29 * DAY, "ends_in_ms is kept as this phone's ticks when it ends")
	_check(view.sides[0].give_up == {"mode": "ask", "asked": -1, "asked_at": -1, "again_at": -1}, "the own side's give up reads: %s" % [view.sides[0].give_up])
	_check(not view.sides[1].has("give_up"), "the other pair carries none")
	var older := Client.valid_view(_wire("1a", "running", {}, {"ends_in_ms": null}))
	older.sides[0].erase("give_up")
	_check(int(older.ends_at) == -1, "a server without the end sends none")
	var server_without := _wire("1a")
	server_without.sides[0].erase("give_up")
	_check(not Client.valid_view(server_without).sides[0].has("give_up"), "a server without Give up sends none, so the page offers none")
	_check(Client.valid_view(_wire("1a", "running", {"give_up": {"mode": "quit"}})).is_empty(), "an unknown give up mode is refused whole")
	var capped := Client.valid_view(_wire("1a", "running", {"give_up": {"mode": "ask", "asked": 1, "asked_at": 5, "again_in_ms": 2 * DAY}}))
	_check(capped.sides[0].give_up.asked == 1 and capped.sides[0].give_up.asked_at == 5 and int(capped.sides[0].give_up.again_at) > Time.get_ticks_msec(), "an ask and the cap read")

func _time_left() -> void:
	var cases := [[29 * DAY, "4 weeks"], [14 * DAY, "2 weeks"], [7 * DAY, "1 week"], [7 * DAY - 1, "6 days"], [DAY, "1 day"], [DAY - 1, "23 hours"], [5 * HOUR + 59 * 60_000, "5 hours"], [HOUR, "1 hour"], [59 * 60_000, "1 hour"], [0, "1 hour"]]
	for case: Array in cases:
		_check(DuelModel.time_left_text(int(case[0])) == case[1], "time left %d ms reads %s, not %s" % [case[0], case[1], DuelModel.time_left_text(int(case[0]))])
	_check(not DuelModel.time_left_urgent(DAY) and DuelModel.time_left_urgent(DAY - 1), "coral only under a day")
	var view := Client.valid_view(_wire("1a"))
	_check(DuelModel.time_left_ms(view, int(view.ends_at) - 3 * DAY) == 3 * DAY, "time left counts down on this phone's clock")
	var over := Client.valid_view(_wire("1a", "decided", {}, {"result": {"outcome": "won", "reason": "faster", "margin_ticks": 30}}))
	_check(DuelModel.time_left_ms(over, 0) == -1, "a duel that is over has no time left")
	_check(DuelModel.give_up_again_text(2 * DAY - 60_000) == PlayerCopy.GIVE_UP_AGAIN_DAYS % 2 and DuelModel.give_up_again_text(HOUR) == PlayerCopy.GIVE_UP_AGAIN_DAY, "Give up again rounds up to whole days")

func _sections() -> void:
	var expect := {"challenged": "challenge", "running": "going", "decided": "finished", "unfinished": "finished", "declined": "not_played", "withdrawn": "not_played", "expired": "not_played", "pair_gone": "not_played"}
	for status: String in expect:
		_check(DuelModel.section(Client.valid_view(_wire("1a", status))) == expect[status], "%s sits on %s" % [status, expect[status]])
	var sent := Client.valid_view(_wire("1a", "declined"))
	var got := Client.valid_view(_wire("1a", "declined", {}, {"mine": 1}))
	_check(DuelModel.not_played_line(sent) == PlayerCopy.DUELS_NOT_PLAYED_SAID and DuelModel.not_played_line(got) == PlayerCopy.DUELS_NOT_PLAYED_YOU_SAID, "not now, by them or by you")
	_check(DuelModel.not_played_line(Client.valid_view(_wire("1a", "expired"))) == PlayerCopy.DUELS_NOT_PLAYED_NO_ANSWER, "no answer in a week")
	_check(DuelModel.not_played_line(Client.valid_view(_wire("1a", "withdrawn"))) == PlayerCopy.DUELS_NOT_PLAYED_YOU_TOOK, "you took it back")
	_check(DuelModel.not_played_line(Client.valid_view(_wire("1a", "pair_gone"))) == PlayerCopy.DUELS_NOT_PLAYED_SPLIT, "a pair split up")

func _give_up_state() -> void:
	var now := Time.get_ticks_msec()
	var plain := Client.valid_view(_wire("1a"))
	_check(DuelModel.give_up(plain, ME, now) == {"mode": "ask", "asked": "", "asked_at": -1, "again_ms": -1}, "a running duel offers Give up")
	_check(DuelModel.give_up(Client.valid_view(_wire("1a", "running", {"give_up": {"mode": "ask", "asked": 0, "asked_at": 4}})), ME, now).asked == "you", "your own ask")
	_check(DuelModel.give_up(Client.valid_view(_wire("1a", "running", {"give_up": {"mode": "ask", "asked": 1, "asked_at": 4}})), ME, now).asked == "friend", "your friend's ask")
	_check(DuelModel.give_up(Client.valid_view(_wire("1a", "running", {"give_up": {"mode": "none", "asked": null, "asked_at": null}})), ME, now).is_empty(), "none when the server says none")
	_check(DuelModel.give_up(Client.valid_view(_wire("1a", "running", {"finished": true, "give_up": {"mode": "none", "asked": null, "asked_at": null}})), ME, now).is_empty(), "none once your pair finished")
	var capped := Client.valid_view(_wire("1a", "running", {"give_up": {"mode": "ask", "asked": null, "asked_at": null, "again_in_ms": 2 * DAY}}))
	_check(DuelModel.give_up(capped, ME, now).again_ms > DAY, "at the cap it says how long until it frees up")
	var race := capped.duplicate(true)
	race.kind = "ghost"
	_check(DuelModel.give_up(race, ME, now).again_ms == -1, "a ghost race is never held to the cap")
	_check(DuelModel.other_pair_names(plain, _name_of) == "Finn and Noor" and DuelModel.give_up_friend(plain, ME, _name_of) == "Maya", "the question names your friend and the other pair")

func _lobby() -> void:
	var lobby: CanvasLayer = Lobby.new()
	lobby.me = ME
	lobby.name_of = _name_of
	root.add_child(lobby)
	await process_frame
	var duels := [_wire("1a"), _wire("2b", "running", {}, {"ends_in_ms": 5 * HOUR + 30 * 60_000}), _wire("3c", "challenged", {}, {"mine": 1, "ends_in_ms": 7 * DAY + HOUR}),
		_wire("4d", "decided", {}, {"result": {"outcome": "won", "reason": "faster", "margin_ticks": 720}}), _wire("5e", "declined"), _wire("6f", "expired")]
	lobby.show_lobby(Client.valid_lobby({"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": duels}))
	await process_frame
	var going := lobby.root.find_child("DuelsTab_going", true, false) as Button
	var finished := lobby.root.find_child("DuelsTab_finished", true, false) as Button
	_check(going != null and going.text == PlayerCopy.DUELS_GOING % 2 and finished.text == PlayerCopy.DUELS_FINISHED % 3, "the tabs count their tiles: %s, %s" % [going.text if going else "", finished.text if finished else ""])
	_check(_tiles(lobby) == ["Tile_" + "1a".repeat(4), "Tile_" + "2b".repeat(4)], "the lobby opens on Going, with the running duels: %s" % [_tiles(lobby)])
	_check(lobby.root.find_child("Challenge_" + "3c".repeat(4), true, false) != null, "a challenge stays in Open duels")
	_check(_tag(lobby, "Tile_" + "1a".repeat(4)) == "4 weeks" and _tag(lobby, "Tile_" + "2b".repeat(4)) == "5 hours" and _tag(lobby, "Challenge_" + "3c".repeat(4)) == "1 week", "every running tile and challenge wears its time left: %s, %s, %s" % [_tag(lobby, "Tile_" + "1a".repeat(4)), _tag(lobby, "Tile_" + "2b".repeat(4)), _tag(lobby, "Challenge_" + "3c".repeat(4))])
	var urgent := lobby.root.find_child("Tile_" + "2b".repeat(4), true, false).find_child("DuelTimeLeft", true, false) as PanelContainer
	_check(urgent != null and (urgent.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == ThemeRules.DANGER_FILL, "under a day the tag is coral")
	finished.pressed.emit()
	await process_frame
	_check(_tiles(lobby) == ["Tile_" + "4d".repeat(4)], "Finished shows the results: %s" % [_tiles(lobby)])
	var not_played: Node = lobby.root.find_child("DuelsNotPlayed", true, false)
	_check(not_played != null and not_played.find_child("NotPlayed_" + "5e".repeat(4), true, false) != null and not_played.find_child("NotPlayed_" + "6f".repeat(4), true, false) != null, "then Not played, with the challenges that never started")
	_check(_tag(lobby, "Tile_" + "4d".repeat(4)) == "", "a finished duel has no time left")
	_check(lobby.root.find_child("Challenge_" + "3c".repeat(4), true, false) != null, "Open duels is the same on Finished")
	_check((lobby.root.find_child("DuelsTab_finished", true, false) as Button).text == PlayerCopy.DUELS_FINISHED % 3, "the tab keeps its count on redraw")
	lobby.queue_free()
	await process_frame

func _tiles(lobby: CanvasLayer) -> Array:
	var names: Array = []
	for child: Node in lobby._tiles.get_children(): if str(child.name).begins_with("Tile_"): names.append(str(child.name))
	return names

func _tag(lobby: CanvasLayer, card: String) -> String:
	var node: Node = lobby.root.find_child(card, true, false)
	var words := node.find_child("DuelTimeLeftWords", true, false) as Label if node != null else null
	return words.text if words != null else ""

func _page() -> void:
	var page: CanvasLayer = DuelPage.new()
	page.me = ME
	page.name_of = _name_of
	page.view = Client.valid_view(_wire("1a"))
	root.add_child(page)
	await process_frame
	await process_frame
	var tags: Node = page.root.find_child("DuelHeaderTags", true, false)
	_check(tags != null and (tags.find_child("DuelTimeLeftWords", true, false) as Label).text == "4 weeks", "the time left stands beside the title")
	var give_up := page.root.find_child("DuelGiveUp", true, false) as Button
	_check(give_up != null and give_up.text == PlayerCopy.GIVE_UP and not give_up.disabled and page.root.find_child("DuelPlay", true, false) != null, "A3: a coral Give up under Play")
	give_up.pressed.emit()
	await process_frame
	var modal: Node = page.root.find_child("DuelGiveUpModal", true, false)
	_check(modal != null and _has_text(modal, PlayerCopy.GIVE_UP_TITLE) and _has_text(modal, PlayerCopy.GIVE_UP_BODY % ["Maya", "Finn and Noor"]) and _has_text(modal, PlayerCopy.GIVE_UP_ASK % "Maya") and _has_text(modal, PlayerCopy.GIVE_UP_KEEP), "A4: the question asks Maya")
	var asked := [-2]
	page.give_up_requested.connect(func(_view: Dictionary, answering: int) -> void: asked[0] = answering)
	(modal.find_child("ModalConfirm", true, false) as Button).pressed.emit()
	await process_frame
	_check(asked[0] == -1, "Ask Maya sends the ask")
	page.show_duel(Client.valid_view(_wire("1a", "running", {"give_up": {"mode": "ask", "asked": 0, "asked_at": 4}}, {"updated_ms": 4})))
	await process_frame
	var box: Node = page.root.find_child("DuelGiveUpAsked", true, false)
	_check(box != null and _has_text(box, PlayerCopy.GIVE_UP_ASKED + "\n" + PlayerCopy.GIVE_UP_WAITING % "Maya") and page.root.find_child("DuelGiveUp", true, false) == null, "A5: you asked, waiting for Maya, with Take it back")
	page.show_duel(Client.valid_view(_wire("1a", "running", {"give_up": {"mode": "ask", "asked": 1, "asked_at": 4}}, {"updated_ms": 5})))
	await process_frame
	var agree := page.root.find_child("DuelGiveUpAgree", true, false) as Button
	_check(agree != null and _has_text(page.root, PlayerCopy.GIVE_UP_ASKED_YOU % "Maya") and _has_text(page.root, PlayerCopy.GIVE_UP_IF_YOU_AGREE % "Finn and Noor") and page.root.find_child("DuelGiveUpKeep", true, false) != null and page.root.find_child("DuelPlay", true, false) == null, "A6: your friend's question replaces the card")
	agree.pressed.emit()
	_check(asked[0] == 4, "Give up on it names the ask")
	page.show_duel(Client.valid_view(_wire("1a", "running", {"give_up": {"mode": "ask", "asked": null, "asked_at": null, "again_in_ms": 2 * DAY - 60_000}}, {"updated_ms": 6})))
	await process_frame
	give_up = page.root.find_child("DuelGiveUp", true, false) as Button
	_check(give_up != null and give_up.disabled and give_up.text == PlayerCopy.GIVE_UP_AGAIN_DAYS % 2, "A7: greyed at the cap with when it frees up")
	var race := _wire("1a", "running", {}, {"updated_ms": 7, "kind": "ghost", "ghost": {"source": "developer", "ticks": 3000, "rank": null, "names": null}})
	race.sides[1] = null
	page.show_duel(Client.valid_view(race))
	await process_frame
	(page.root.find_child("DuelGiveUp", true, false) as Button).pressed.emit()
	await process_frame
	modal = page.root.find_child("DuelGiveUpModal", true, false)
	_check(modal != null and _has_text(modal, PlayerCopy.GIVE_UP_TITLE_RACE) and _has_text(modal, PlayerCopy.GIVE_UP_BODY_RACE % "Maya"), "a race asks with its own words")
	page.close_sheet()
	page.show_duel(Client.valid_view(_wire("1a", "running", {"give_up": {"mode": "none", "asked": null, "asked_at": null}}, {"updated_ms": 8})))
	await process_frame
	_check(page.root.find_child("DuelGiveUp", true, false) == null and page.root.find_child("DuelLeave", true, false) == null, "no Give up, and no solo Leave, where the server offers none")
	page.queue_free()
	await process_frame

func _has_text(node: Node, words: String) -> bool:
	for child: Node in node.find_children("*", "", true, false):
		if (child is Label or child is Button) and child.text == words: return true
	return false
