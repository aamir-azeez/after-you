extends SceneTree
## Duels on the phone: what services/duel_model.gd says about a duel, how
## services/duels_client.gd checks and keeps the server's answers (the duel
## rooms and duel clears it saves), and the pages' states (presentation/duels/):
## the lobby's party, challenges and tiles, the duel page with times, the
## result page with the real pay lines, the party page, Start a duel, Race a
## recorded run, Home's Duels row and the Duel tag. Every request goes to a
## fake transport; synthetic ids only.
const DuelModel = preload("res://services/duel_model.gd")
const Client = preload("res://services/duels_client.gd")
const Lobby = preload("res://presentation/duels/duels_screen.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const ResultPage = preload("res://presentation/duels/duel_result_page.gd")
const PartyPage = preload("res://presentation/duels/duel_party_page.gd")
const ChallengePage = preload("res://presentation/duels/duel_challenge_page.gd")
const GhostPage = preload("res://presentation/duels/duel_ghost_page.gd")
const HomeMenu = preload("res://presentation/home_menu.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Registry = preload("res://services/chapter_registry.gd")
const ME := "MMMMMMMMMMMMMMMMMMMMMM"
const MAYA := "AAAAAAAAAAAAAAAAAAAAAA"
const FINN := "FFFFFFFFFFFFFFFFFFFFFF"
const NOOR := "NNNNNNNNNNNNNNNNNNNNNN"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const BOARD := "sleeping-lighthouse@2"
const SAVE_PATH := "user://duels-test.json"
const DUEL := "d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0"

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

class FakeApi extends Node:
	var replies: Dictionary = {}
	var requests: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		var name: String = {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_POST: "POST"}.get(method, "?")
		requests.append([name, path, body])
		await Engine.get_main_loop().process_frame
		return replies.get(name + " " + path, {"ok": false, "code": "not_found"}).duplicate(true)

func _name_of(id: Variant) -> String:
	return {ME: PlayerCopy.DUEL_YOU, MAYA: "Maya", FINN: "Finn", NOOR: "Noor"}.get(id, "")

## A duel as the server sends it (backend duels/model.ts DuelView), from this player's side 0.
func _wire(status: String = "running", overrides: Dictionary = {}) -> Dictionary:
	var view := {"schema_version": 1, "duel_id": DUEL, "kind": "friend", "board": BOARD, "status": status, "steps": 12,
		"created_ms": 1, "accepted_ms": 2, "updated_ms": 3, "mine": 0, "ghost": null, "result": null, "eligible": true,
		"sides": [
			{"members": [ME, MAYA], "you": true, "steps": 3, "ticks": 3240, "assisted": false, "turn": 0, "finished": false, "left": false, "check": "none", "room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": true},
			{"members": [FINN, null], "you": false, "steps": 2, "ticks": 2760, "assisted": true, "turn": 1, "finished": false, "left": false, "check": "none"}]}
	view.merge(overrides, true)
	return view

func _run() -> void:
	_clear(SAVE_PATH)
	_model()
	await _client()
	await _pages()
	await _home()
	_clear(SAVE_PATH)
	print("AFTER YOU DUELS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _model() -> void:
	var view := Client.valid_view(_wire())
	_check(not view.is_empty(), "a running duel reads")
	_check(DuelModel.time_text(3240) == "1:48.0" and DuelModel.time_text(2760) == "1:32.0", "times read as the board shows them")
	_check(DuelModel.pair_title(view, 0, _name_of) == "You + Maya", "your pair reads You + Maya")
	_check(DuelModel.pair_title(view, 1, _name_of) == "Finn + Finn's partner", "a player the server did not name reads as a partner: " + DuelModel.pair_title(view, 1, _name_of))
	_check(DuelModel.turn_line(view, 0, _name_of) == PlayerCopy.DUEL_YOUR_TURN and DuelModel.turn_line(view, 1, _name_of) == PlayerCopy.DUEL_WAITING_FOR % PlayerCopy.DUEL_PARTNER, "whose turn each pair shows")
	_check(DuelModel.action(view, ME) == "play" and DuelModel.action(view, MAYA) == "open", "Play for the player whose turn it is, Open for the partner")
	var level := Client.valid_view(_wire("running", {"sides": [_wire().sides[0].merged({"steps": 4, "ticks": 3000}, true), _wire().sides[1].merged({"steps": 4, "ticks": 3360}, true)]}))
	_check(DuelModel.ahead_line(level) == PlayerCopy.DUEL_AHEAD % ["0:12.0", 2], "ahead once both pairs finished the same stage: " + DuelModel.ahead_line(level))
	_check(DuelModel.ahead_line(view) == "", "no ahead line mid stage")
	_check(DuelModel.margin_text(720) == PlayerCopy.DUEL_MARGIN_SECONDS % 24 and DuelModel.margin_text(2) == PlayerCopy.DUEL_MARGIN_HUNDREDTHS % (2.0 / 30.0), "the gap reads seconds, or hundredths under a tenth")
	var won := Client.valid_view(_wire("decided", {"result": {"outcome": "won", "reason": "faster", "margin_ticks": 720, "decided_ms": 9}}))
	_check(DuelModel.result_title(won, _name_of) == "You and Maya won" and DuelModel.result_line(won) == PlayerCopy.DUEL_FASTER % (PlayerCopy.DUEL_MARGIN_SECONDS % 24), "the result title and line")
	_check(DuelModel.action(won, ME) == "result", "a decided duel is a result tile")
	var checking := Client.valid_view(_wire("running", {"sides": [_wire().sides[0].merged({"finished": true, "check": "waiting"}, true), _wire().sides[1]]}))
	_check(DuelModel.result_title(checking, _name_of) == PlayerCopy.DUEL_CHECKING_TITLE and DuelModel.result_line(checking) == PlayerCopy.DUEL_CHECKING_LINE, "a finished pair waits for the check")
	var pay := {"turns": 6, "plain": 600, "blooms": 111, "duel": 300, "boost": 60, "boost_percent": 10, "total": 1071}
	var lines := DuelModel.pay_lines(pay, {"amount": 250, "counted": true, "reason": ""})
	_check(lines.total == 1321 and lines.lines.size() == 4 and lines.lines[1][0] == PlayerCopy.DUEL_PAY_PREMIUM and lines.lines[3][0] == PlayerCopy.DUEL_PAY_WIN, "the real pay: turns, duel bonus, boost, win bonus: %s" % lines)
	var quiet := DuelModel.pay_lines(pay, {}, false)
	_check(quiet.total == 1071 and quiet.lines.size() == 2, "where Full Journey is not named, the boost folds into the turns line")
	_check(DuelModel.pay_lines({}, {"amount": 0, "counted": false, "reason": "same_pair"}).lines[0][0] == PlayerCopy.DUEL_PAY_WIN_SAME, "a win that did not count says why")
	var ghost := Client.valid_view(_wire("running", {"kind": "ghost", "ghost": {"source": "developer", "ticks": 3000, "rank": null, "names": null}, "sides": [_wire().sides[0], null]}))
	_check(not ghost.is_empty() and DuelModel.pair_title(ghost, 1, _name_of) == PlayerCopy.DUEL_GHOST_PAIR and DuelModel.ticks(ghost, 1) == 3000 and DuelModel.steps(ghost, 1) == Vector2i(12, 12), "a ghost race shows the recorded run's whole time")
	# Answers this build cannot read are refused whole.
	_check(Client.valid_view(_wire("bogus")).is_empty() and Client.valid_view(_wire("running", {"duel_id": "x"})).is_empty() and Client.valid_view(_wire("running", {"sides": []})).is_empty(), "malformed duels are refused")
	_check(Client.valid_lobby({"schema_version": 1, "party": {"partner": "short", "intact": true, "invites_in": [], "invite_out": null}, "duels": []}).is_empty(), "a malformed party is refused")

func _client() -> void:
	var api := FakeApi.new()
	root.add_child(api)
	var lobby := {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null},
		"duels": [_wire("running", {"sides": [_wire().sides[0].merged({"finished": true, "check": "waiting"}, true), _wire().sides[1]]})], "limits": {"friend": 3, "ghost": 3}}
	api.replies["GET /v1/duels"] = {"ok": true, "data": lobby}
	var client := Client.new(api, ME, SAVE_PATH)
	var answer: Dictionary = await client.lobby()
	_check(answer.ok and answer.lobby.party.partner == MAYA, "the lobby reads")
	_check(client.room_kind(ROOM) == "friend" and client.room_kind("other") == "", "a duel's room is known for the Duel tag")
	var again := Client.new(api, ME, SAVE_PATH)
	_check(again.room_kind(ROOM) == "friend", "it survives a restart")
	_check(Client.new(api, MAYA, SAVE_PATH).room_kind(ROOM) == "", "and belongs to this player only")
	api.replies["POST /v1/duels/challenge"] = {"ok": true, "data": {"schema_version": 1, "duel": _wire("challenged")}}
	var key := Client.new_key()
	var sent: Dictionary = await client.challenge(FINN, BOARD, key)
	_check(sent.ok and api.requests[-1][2].idempotency_key == key and api.requests[-1][2].friend == FINN, "a challenge carries its tap's key")
	api.replies["GET /v1/duels/%s/%s" % [BOARD, DUEL]] = {"ok": true, "data": {"schema_version": 1, "duel": _wire("decided", {"result": {"outcome": "won", "reason": "faster", "margin_ticks": 30}}), "pay": {"turns": 6, "plain": 1, "blooms": 0, "duel": 1, "boost": 0, "boost_percent": 0, "total": 2}, "win_bonus": {"amount": 250, "counted": true}}}
	var detail: Dictionary = await client.duel(BOARD, DUEL)
	_check(detail.ok and detail.pay.turns == 6 and detail.win_bonus.amount == 250, "a duel's pay and win bonus read")
	api.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {}, "duels": "nope"}}
	_check(not (await client.lobby()).ok and not client.last_lobby().is_empty(), "a bad answer keeps the last good lobby")
	api.queue_free()
	await process_frame

func _pages() -> void:
	var lobby_data := Client.valid_lobby({"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [
		_wire(), _wire("challenged", {"duel_id": "d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1", "mine": 1, "sides": [_wire().sides[1].merged({"you": false}, true), _wire().sides[0].merged({"you": true}, true)]}),
		_wire("decided", {"duel_id": "d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2", "result": {"outcome": "won", "reason": "faster", "margin_ticks": 30}}),
		_wire("declined", {"duel_id": "d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3"})]})
	_check(not lobby_data.is_empty(), "the page lobby reads")
	var lobby := Lobby.new()
	lobby.me = ME
	lobby.name_of = _name_of
	lobby.boost_percent = 10
	root.add_child(lobby)
	await process_frame
	_check(lobby.find_child("DuelsTiles", true, false).get_child_count() == 0 and _has_text(lobby, PlayerCopy.DUELS_LOADING), "the lobby says it is loading until its lobby arrives")
	lobby.show_lobby(lobby_data)
	await process_frame
	var tiles: Node = lobby.find_child("DuelsTiles", true, false)
	_check(tiles.get_child_count() == 2, "running duels and results are tiles; a declined challenge fades: %d" % tiles.get_child_count())
	_check(str(tiles.get_child(0).name).begins_with("Tile_d0") and tiles.get_child(0).find_child("TileAction", true, false).text == PlayerCopy.DUELS_PLAY, "your move comes first, with Play")
	_check(_has_text(tiles.get_child(0), "1:48.0") and _has_text(tiles.get_child(0), "1:32.0"), "a tile shows both pairs' times")
	var open: Node = lobby.find_child("DuelsOpenList", true, false)
	_check(open.get_child_count() == 1 and open.find_child("Accept", true, false) != null and open.find_child("NotNow", true, false) != null, "a challenge to you has Accept and Not now")
	_check(_has_text(lobby, PlayerCopy.DUELS_BOOST % 10) and _has_text(lobby, "Maya"), "your party with its boost")
	var pips: Array = lobby.find_children("*", "", true, false).filter(func(node: Node) -> bool: return node is PipAvatar)
	_check(not pips.is_empty() and pips.all(func(pip: Node) -> bool: return pip.still), "the lobby draws still pips only")
	var seen: Array = []
	lobby.duel_action.connect(func(view: Dictionary, action: String, _control: Control) -> void: seen.append(action))
	(open.find_child("Accept", true, false) as Button).pressed.emit()
	(tiles.get_child(1).find_child("TileAction", true, false) as Button).pressed.emit()
	_check(seen == ["accept", "result"], "taps say what they are: %s" % [seen])
	# A page over the lobby closes first on Back.
	var page := DuelPage.new()
	page.me = ME
	page.name_of = _name_of
	page.view = Client.valid_view(_wire())
	lobby.open_overlay(page)
	await process_frame
	_check(page.find_child("DuelTime0", true, false).text == "1:48.0" and page.find_child("DuelTime1", true, false).text == "1:32.0", "the duel page shows both times so far")
	_check(_has_text(page, PlayerCopy.DUEL_STEPS % [3, 12]) and _has_text(page, PlayerCopy.DUEL_WAITING_NO_TIME) and page.find_child("DuelPlay", true, false).text == PlayerCopy.DUEL_PLAY_TURN, "steps, the waiting note and Play your turn")
	var waiting := Client.valid_view(_wire("running", {"sides": [_wire().sides[0].merged({"turn": 1}, true), _wire().sides[1]]}))
	page.show_duel(waiting)
	_check(page.find_child("DuelPlay", true, false).text == PlayerCopy.DUEL_VIEW_TURNS and _has_text(page, PlayerCopy.DUEL_WAITING_TITLE % "Maya"), "while your partner plays: View turns")
	lobby.go_back()
	await process_frame
	_check(not is_instance_valid(page) or page.is_queued_for_deletion(), "Back closes the page over the lobby first")
	_check(is_instance_valid(lobby) and not lobby.is_queued_for_deletion(), "and keeps the lobby")
	# The result page: the real pay, and nothing about who has Full Journey.
	var result := ResultPage.new()
	result.me = ME
	result.name_of = _name_of
	result.view = Client.valid_view(_wire("decided", {"result": {"outcome": "won", "reason": "faster", "margin_ticks": 720}, "sides": [_wire().sides[0].merged({"steps": 12, "finished": true, "check": "passed"}, true), _wire().sides[1].merged({"steps": 12, "finished": true, "check": "passed"}, true)]}))
	result.pay = {"turns": 6, "plain": 600, "blooms": 0, "duel": 300, "boost": 60, "boost_percent": 10, "total": 960}
	result.win_bonus = {"amount": 250, "counted": true, "reason": ""}
	lobby.open_overlay(result)
	await process_frame
	_check(result.find_child("DuelResultHeadline", true, false).text == "You and Maya won" and _has_text(result, PlayerCopy.DUEL_WINNER), "the winner's title and card")
	var pollen: Node = result.find_child("DuelPollen", true, false)
	_check(pollen != null and _has_text(pollen, PlayerCopy.DUEL_PAY_PREMIUM) and _has_text(pollen, PlayerCopy.DUEL_PAY_WIN) and _has_text(pollen, "1,210"), "Pollen earned lists the duel's real pay and its total")
	_check(not _has_text(result, "member in your party"), "no Full Journey member line")
	result.close()
	var hidden := ResultPage.new()
	hidden.view = result.view
	hidden.pay = result.pay
	hidden.show_pollen = false
	lobby.open_overlay(hidden)
	await process_frame
	_check(hidden.find_child("DuelPollen", true, false) == null, "no Pollen card where Pollen is off")
	hidden.close()
	# The party page.
	var party := PartyPage.new()
	party.name_of = _name_of
	party.party = {"partner": null, "intact": false, "invites_in": [FINN], "invite_out": NOOR}
	party.friends = [{"id": NOOR, "name": "Noor"}, {"id": MAYA, "name": "Maya"}]
	lobby.open_overlay(party)
	await process_frame
	_check(_has_text(party, PlayerCopy.DUELS_PARTY_COUNT % 1) and _has_text(party, PlayerCopy.DUELS_PARTY_INVITED % "Finn") and _has_text(party, PlayerCopy.DUELS_PARTY_ASKED), "one of two, an invite to answer and an ask out")
	var actions: Array = []
	party.party_action.connect(func(action: String, friend: String, _control: Control) -> void: actions.append([action, friend]))
	(party.find_child("Friend_" + MAYA.left(6), true, false).find_children("*", "Button", true, false)[0] as Button).pressed.emit()
	_check(actions == [["invite", MAYA]], "Ask invites the friend")
	party.show_party({"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null})
	_check(_has_text(party, PlayerCopy.DUELS_PARTY_COUNT % 2) and party.find_child("DuelPartyLeave", true, false) != null, "a full party with Leave")
	party.close()
	# Start a duel: Send waits for both choices.
	var challenge := ChallengePage.new()
	challenge.friends = [{"id": FINN, "name": "Finn"}]
	challenge.chapters = [Registry.FIRST_STEPS, BOARD]
	lobby.open_overlay(challenge)
	await process_frame
	var send: Button = challenge.find_child("DuelSend", true, false)
	_check(send.disabled, "Send waits for a pair and a chapter")
	(challenge.find_child("Pair_" + FINN.left(6), true, false) as Button).pressed.emit()
	(challenge.find_child("Chapter_" + BOARD.replace("@", "_"), true, false) as Button).pressed.emit()
	_check(not send.disabled, "then it is ready")
	var sent: Array = []
	challenge.send_requested.connect(func(friend: String, chapter: String, _control: Control) -> void: sent.append([friend, chapter]))
	send.pressed.emit()
	_check(sent == [[FINN, BOARD]], "Send names both")
	challenge.close()
	# Race a recorded run.
	var ghosts := GhostPage.new()
	ghosts.chapters = [BOARD]
	lobby.open_overlay(ghosts)
	await process_frame
	_check(_has_text(ghosts, PlayerCopy.DUELS_LOADING), "the ghost list loads")
	ghosts.show_ghosts([{"board": BOARD, "developer": 1470, "top": [{"entry_id": "e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1", "ticks": 1400, "rank": 1, "names": null}]}])
	_check(ghosts.find_child("Race_developer", true, false) != null and ghosts.find_child("Race_board_e1e1e1", true, false) != null and _has_text(ghosts, "0:49.0"), "our run and the board's runs with their times")
	ghosts.close()
	# Nothing at all: the hand drawn empty art the other lists use, in the owner's pick.
	lobby.show_lobby(Client.valid_lobby({"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": []}))
	await process_frame
	var empty: Node = lobby.find_child("EmptyState", true, false)
	_check(empty != null and empty.art == Lobby.EMPTY_ART and _has_text(empty, PlayerCopy.DUELS_EMPTY_TITLE), "an empty lobby draws its empty art")
	lobby.show_lobby(lobby_data)
	await process_frame
	_check(lobby.find_child("EmptyState", true, false) == null or lobby.find_child("EmptyState", true, false).is_queued_for_deletion(), "and it goes once a duel arrives")
	lobby.close()
	await process_frame

func _home() -> void:
	var holder := Control.new()
	holder.size = Vector2(1280, 720)
	root.add_child(holder)
	var menu := HomeMenu.new()
	holder.add_child(menu)
	var none := func() -> void: pass
	menu.build({"play": func(_button: Button) -> void: pass, "solo": none, "friends": none, "duels": none, "replays": none, "invite": none, "whats_new": none, "settings": none, "full_journey": none}, preload("res://assets/fonts/nunito.ttf"))
	await process_frame
	_check(not menu.duels_button.visible, "Home hides Duels until the server says they are on")
	var index := menu.duels_button.get_index()
	_check(menu.duels_button.get_parent() == menu.friends_button.get_parent() and index == menu.friends_button.get_index() + 1, "Duels sits under Friends")
	menu.show_duels(true)
	await process_frame
	_check(menu.duels_button.visible and menu.duels_button.custom_minimum_size.y >= 48.0, "then shows, at least 48 high")
	_check(menu.get_node("HomeMenuMargin").get_combined_minimum_size().y <= menu.size.y + 0.5, "and the column still fits 720")
	holder.queue_free()
	await process_frame
	var hub := preload("res://presentation/room_hub_screen.gd").new()
	var tag: Control = hub._duel_tag()
	_check(tag.name == "DuelTag" and (tag.get_child(0) as Label).text == PlayerCopy.DUEL_TAG, "a duel's room card carries the Duel tag")
	tag.free()
	hub.free()

func _has_text(node: Node, text: String) -> bool:
	if node == null: return false
	for child: Node in node.find_children("*", "", true, false):
		if (child is Label or child is Button) and str(child.text).contains(text): return true
	return false

func _clear(path: String) -> void:
	for candidate: String in [path, path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
