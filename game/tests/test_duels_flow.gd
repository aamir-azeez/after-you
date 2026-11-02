extends SceneTree
## presentation/duels/duels_flow.gd against a stand-in Main: duels hide while
## the server has them off, Play opens your pair's room, joins the one your
## partner made, or makes it, and joins your partner's when both of you made
## one at once; a chapter you have not reached is never played; Accept and
## Not now go to the server once per tap. Synthetic ids only.
const Flow = preload("res://presentation/duels/duels_flow.gd")
const Client = preload("res://services/duels_client.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Registry = preload("res://services/chapter_registry.gd")
const LogWatch = preload("res://tests/log_watch.gd")
const Clock = preload("res://services/refresh_schedule.gd")
const ResultPage = preload("res://presentation/duels/duel_result_page.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const ME := "MMMMMMMMMMMMMMMMMMMMMM"
const MAYA := "AAAAAAAAAAAAAAAAAAAAAA"
const FINN := "FFFFFFFFFFFFFFFFFFFFFF"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const BOARD := "first-steps@1"
const DUEL := "d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0"

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

class FakeApi extends Node:
	var player_id := ME
	var replies: Dictionary = {}
	var requests: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		var name: String = {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_POST: "POST"}.get(method, "?")
		requests.append([name, path, body])
		await Engine.get_main_loop().process_frame
		return replies.get(name + " " + path, {"ok": false, "code": "not_found"}).duplicate(true)

class FakeSession extends RefCounted:
	var on := true
	var capabilities := {"duels_version": 1}
	var last_lobby_code := ""
	func duels_supported() -> bool: return on
	func pollen_supported() -> bool: return true
	func load_capabilities() -> void: pass

class FakeLobby extends RefCounted:
	var calls: Array = []
	var session: FakeSession
	var taken := false
	var missing := false
	func open_lobby(chapter: String = "") -> bool:
		calls.append(["open_lobby", chapter])
		return true
	func lobby_action(action: String, value: String = "", _hard: bool = false, duel: Dictionary = {}) -> void:
		calls.append([action, value, duel])
		session.last_lobby_code = "duel_room_taken" if taken and action == "duel" else ""
	func join_room(code: String) -> void:
		calls.append(["join", code])
		session.last_lobby_code = "invite_not_found" if missing else ""

class FakeFriends extends RefCounted:
	func view() -> Dictionary: return {"friends": [{"player_id": MAYA, "status": "accepted"}, {"player_id": FINN, "status": "accepted"}]}
	func refresh(_manual: bool = false) -> bool: return true

## A page that closes, standing in for the ghost and challenge pages.
class FakePage extends CanvasLayer:
	func close() -> void: queue_free()

## A friends list not read yet this session: it arrives a few frames after it is asked for.
class SlowFriends extends FakeFriends:
	var read := false
	func view() -> Dictionary: return super() if read else {}
	func refresh(_manual: bool = false) -> bool:
		for index in range(4): await Engine.get_main_loop().process_frame
		read = true
		return true

class FakeMain extends Node:
	var api: Node
	var config := {}
	var relay_session := FakeSession.new()
	var relay_lobby_flow := FakeLobby.new()
	var mode := "home"
	var ui := Control.new()
	var application_backgrounded := false
	var toasts: Array = []
	var unlocks := {}
	func ensure_relay_session() -> void: pass
	var friends: RefCounted = FakeFriends.new()
	func _friends_client(_create: bool) -> RefCounted: return friends
	func _friend_display_name(id: String) -> String: return {MAYA: "Maya", FINN: "Finn"}.get(id, "a friend")
	func _toast(text: String) -> void: toasts.append(text)
	func _chapter_unlocks() -> Dictionary: return unlocks
	func _full_journey_access() -> bool: return false
	func _paid_content_hidden() -> bool: return false

func _view(own: Dictionary, status: String = "running") -> Dictionary:
	var side := {"members": [ME, MAYA], "you": true, "steps": 0, "ticks": 0, "turn": null, "finished": false, "left": false, "check": "none", "room_id": null, "invite_code": null, "hosting": false}
	side.merge(own, true)
	return {"schema_version": 1, "duel_id": DUEL, "kind": "friend", "board": BOARD, "status": status, "steps": 4, "created_ms": 1, "accepted_ms": 2, "updated_ms": 3, "mine": 0,
		"ghost": null, "result": null, "eligible": true, "sides": [side, {"members": [FINN, null], "you": false, "steps": 0, "ticks": 0, "turn": null, "finished": false, "left": false, "check": "none"}]}

func _run() -> void:
	_clear()
	var main := FakeMain.new()
	var api := FakeApi.new()
	main.api = api
	main.relay_lobby_flow.session = main.relay_session
	main.unlocks = ChapterUnlocks.unsettled(true)
	root.add_child(main)
	root.add_child(api)
	main.add_child(main.ui)
	var flow := Flow.new(main)
	main.add_child(flow)
	api.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_view({}, "challenged")]}}
	# Off: nothing opens and no room is tagged.
	main.relay_session.on = false
	flow.open()
	_check(not flow.is_open() and flow.room_kind(ROOM) == "", "duels stay hidden while the server has them off")
	var ghost_wait := {"kind": "ghost", "mine": 0, "sides": [{"check": "waiting"}, null]}
	_check(Flow.refresh_ms(ghost_wait) == Clock.DUEL_CHECK_INTERVAL_MS and Flow.refresh_ms({"kind": "ghost", "mine": 0, "sides": [{"check": "none"}, null]}) == Clock.DUEL_INTERVAL_MS and Flow.refresh_ms({"kind": "friend", "mine": 1, "sides": [{"check": "none"}, {"check": "waiting"}]}) == Clock.DUEL_INTERVAL_MS, "a ghost race waiting for its check reads less often, every other duel as before")
	_check(Clock.DUELS_LOBBY_INTERVAL_MS == 60000 and Clock.DUEL_INTERVAL_MS == 30000 and Clock.DUEL_CHECK_INTERVAL_MS == 60000, "the lobby reads once a minute, a duel every 30 s, a ghost race waiting for its check once a minute")
	main.relay_session.on = true
	flow.open()
	await _frames(4)
	_check(flow.is_open() and main.mode == Flow.MODE_DUELS and not main.ui.visible, "the lobby opens over Home")
	# Play: your own room opens.
	await flow._play(Client.valid_view(_view({"room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": true})))
	_check(main.relay_lobby_flow.calls == [["open_lobby", Registry.FIRST_STEPS], ["open", ROOM, {}]], "Play opens the room you made: %s" % [main.relay_lobby_flow.calls])
	_check(not flow.is_open() and main.ui.visible, "the room flow takes over from Duels")
	# Play: your partner's room is joined.
	main.relay_lobby_flow.calls.clear()
	flow.open()
	await _frames(2)
	await flow._play(Client.valid_view(_view({"room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": false})))
	_check(main.relay_lobby_flow.calls == [["join", "abcdefabcdefabcdefab"]], "Play joins the room your partner made: %s" % [main.relay_lobby_flow.calls])
	# Play: no room yet, so this phone makes it for the duel.
	main.relay_lobby_flow.calls.clear()
	flow.open()
	await _frames(2)
	await flow._play(Client.valid_view(_view({})))
	_check(main.relay_lobby_flow.calls == [["open_lobby", Registry.FIRST_STEPS], ["duel", Registry.FIRST_STEPS, {"duel_id": DUEL, "board": BOARD}]], "Play makes the pair's room for the duel: %s" % [main.relay_lobby_flow.calls])
	# Both made one at once: the server kept your partner's, so this phone joins it.
	main.relay_lobby_flow.calls.clear()
	main.relay_lobby_flow.taken = true
	api.replies["GET /v1/duels/%s/%s" % [BOARD, DUEL]] = {"ok": true, "data": {"schema_version": 1, "duel": _view({"room_id": ROOM, "invite_code": "fedcbafedcbafedcbafe", "hosting": false})}}
	flow.open()
	await _frames(2)
	await flow._play(Client.valid_view(_view({})))
	_check(main.relay_lobby_flow.calls.size() == 3 and main.relay_lobby_flow.calls[2] == ["join", "fedcbafedcbafedcbafe"], "a room your partner made first is joined instead: %s" % [main.relay_lobby_flow.calls])
	# A chapter not reached is never played.
	main.relay_lobby_flow.calls.clear()
	main.unlocks = ChapterUnlocks.progress([], {}, {}, false, [])
	flow.open()
	await _frames(2)
	var locked := Client.valid_view(_view({}))
	locked.chapter = Registry.LIGHTHOUSE_V2
	locked.board = Registry.LIGHTHOUSE_V2
	await flow._play(locked)
	_check(main.relay_lobby_flow.calls.is_empty() and PlayerCopy.DUELS_CHAPTER_CLOSED in main.toasts and flow.is_open(), "a chapter you have not reached is never played")
	# Accept goes once per tap and the lobby is read again.
	main.unlocks = ChapterUnlocks.unsettled(true)
	api.replies["POST /v1/duels/%s/%s/accept" % [BOARD, DUEL]] = {"ok": true, "data": {"schema_version": 1, "duel": _view({})}}
	var before := api.requests.size()
	var accept := Button.new()
	flow.screen.root.add_child(accept)
	flow._on_duel_action(Client.valid_view(_view({}, "challenged")), "accept", accept)
	flow._on_duel_action(Client.valid_view(_view({}, "challenged")), "accept", accept)
	await _frames(6)
	var sent: Array = api.requests.slice(before).filter(func(item: Array) -> bool: return item[1].ends_with("/accept"))
	_check(sent.size() == 1, "a second tap while the first runs does nothing: %d" % sent.size())
	_check(api.requests.slice(before).any(func(item: Array) -> bool: return item[1] == "/v1/duels"), "the lobby is read again after it")
	# Room tags come from what the client kept.
	api.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_view({"room_id": ROOM, "finished": true, "check": "waiting"})]}}
	await flow.client().lobby()
	_check(flow.room_kind(ROOM) == "friend", "a duel room is tagged")
	# A room your partner claimed but never made: Play makes one instead.
	main.relay_lobby_flow.calls.clear()
	main.relay_lobby_flow.missing = true
	main.relay_lobby_flow.taken = false
	await flow._play(Client.valid_view(_view({"room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": false})))
	_check(main.relay_lobby_flow.calls.size() == 3 and main.relay_lobby_flow.calls[2][0] == "duel", "a room that never appeared is made here: %s" % [main.relay_lobby_flow.calls])
	# A race or challenge whose answer was lost: a tap again sends the same key, so the server answers the duel the first tap made.
	var asked: CanvasLayer = FakePage.new()
	root.add_child(asked)
	var keys := func(path: String) -> Array: return api.requests.filter(func(item: Array) -> bool: return item[1] == path).map(func(item: Array) -> String: return item[2].idempotency_key)
	for path: String in ["/v1/duels/ghost", "/v1/duels/challenge"]: api.replies["POST " + path] = {"ok": false, "code": "connection_interrupted"}
	for index in range(2):
		await flow._race(asked, Registry.FIRST_STEPS, "developer", null)
		await flow._challenge(asked, FINN, Registry.FIRST_STEPS)
	await flow._race(asked, Registry.FIRST_STEPS, "board", "e".repeat(32))
	var raced: Array = keys.call("/v1/duels/ghost")
	var challenged: Array = keys.call("/v1/duels/challenge")
	_check(raced.size() == 3 and raced[0] == raced[1] and raced[2] != raced[0], "a race tapped again after a lost answer keeps its key; another ghost gets its own: %s" % [raced])
	_check(challenged.size() == 2 and challenged[0] == challenged[1], "a challenge tapped again after a lost answer keeps its key: %s" % [challenged])
	api.replies["POST /v1/duels/challenge"] = {"ok": true, "data": {"schema_version": 1, "duel": _view({}, "challenged")}}
	await flow._challenge(asked, FINN, Registry.FIRST_STEPS)
	_check(not is_instance_valid(asked) or asked.is_queued_for_deletion(), "the answered challenge closes its page")
	asked = FakePage.new()
	root.add_child(asked)
	await flow._challenge(asked, FINN, Registry.FIRST_STEPS)
	challenged = keys.call("/v1/duels/challenge")
	_check(challenged.size() == 4 and challenged[2] == challenged[0] and challenged[3] != challenged[0], "once a challenge is answered, the next one is a new challenge: %s" % [challenged])
	if is_instance_valid(asked): asked.close()
	asked = FakePage.new()
	root.add_child(asked)
	api.replies["POST /v1/duels/challenge"] = {"ok": false, "status": 409, "code": "duel_limit_reached"}
	for index in range(2): await flow._challenge(asked, FINN, Registry.FIRST_STEPS)
	challenged = keys.call("/v1/duels/challenge")
	_check(challenged.size() == 6 and challenged[4] != challenged[3] and challenged[5] != challenged[4], "a refusal from the server settles its key too: %s" % [challenged])
	asked.close()
	# Back on the Party or Start a duel page while the friends list loads: the page is gone, and nothing writes to it.
	var watch: LogWatch = LogWatch.start(["previously freed"])
	for open: Callable in [flow._open_party, flow._open_challenge]:
		main.friends = SlowFriends.new()
		flow.open()
		await _frames(2)
		open.call()
		await _frames(1)
		var page: CanvasLayer = flow.screen.overlay()
		_check(page != null, "the page opens before its friends list arrives")
		if page != null: page.close()
		await _frames(8)
	_check(watch.count("previously freed") == 0, "a page closed while its friends list loads is left alone")
	watch.stop()
	main.friends = FakeFriends.new()
	await _polling(main, api, flow)
	await _leaving(api, flow)
	await _already_open(main, api, flow)
	flow.open()
	await _frames(2)
	flow.close()
	await _frames(2)
	_check(not flow.is_open(), "close takes the lobby away")
	main.queue_free()
	api.queue_free()
	await process_frame
	_clear()
	print("AFTER YOU DUELS FLOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The lobby and an open duel read on their own at the slower pace, never in
## the background or while hidden, and once at once on coming back. The clock
## is driven by hand (_tick) with made-up times; real frames only let the
## stand-in requests answer.
func _polling(main: FakeMain, api: FakeApi, flow: Node) -> void:
	var lobby_path := "/v1/duels"
	var duel_path := "/v1/duels/%s/%s" % [BOARD, DUEL]
	var reads := func(path: String) -> int: return api.requests.filter(func(item: Array) -> bool: return item[0] == "GET" and item[1] == path).size()
	var running_lobby := {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_view({})]}}
	api.replies["GET " + lobby_path] = running_lobby
	flow.close()
	await _frames(4)
	var before: int = reads.call(lobby_path)
	flow.open()
	flow.set_process(false)
	await _frames(3)
	_check(reads.call(lobby_path) == before + 1, "opening the lobby reads it at once: %d" % (reads.call(lobby_path) - before))
	var t := Time.get_ticks_msec() + 1000
	flow._tick(t + 30000)
	await _frames(3)
	_check(reads.call(lobby_path) == before + 1, "the lobby does not read again after 30 s")
	flow._tick(t + 61000)
	await _frames(3)
	_check(reads.call(lobby_path) == before + 2, "the lobby reads again after a minute while a duel runs")
	# In the background nothing reads; coming back reads once, however many signals arrive.
	flow._notification(NOTIFICATION_APPLICATION_PAUSED)
	flow._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	flow._tick(t + 200000)
	await _frames(3)
	_check(reads.call(lobby_path) == before + 2, "nothing reads while the app is in the background")
	flow._notification(NOTIFICATION_APPLICATION_RESUMED)
	flow._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames(3)
	flow._tick(t + 200001)
	await _frames(3)
	_check(reads.call(lobby_path) == before + 3, "coming back reads the lobby once, at once: %d" % (reads.call(lobby_path) - before))
	# Hidden (the other pair's run playing over it): no read until it shows again.
	flow.screen.visible = false
	flow._tick(t + 300000)
	await _frames(3)
	_check(reads.call(lobby_path) == before + 3, "a hidden lobby does not read")
	flow.screen.visible = true
	flow._tick(t + 300001)
	await _frames(3)
	_check(reads.call(lobby_path) == before + 4, "the lobby reads once it shows again")
	# Nothing can change without this player: no timed read, but a page closing still reads at once.
	api.replies["GET " + lobby_path] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_view({}, "decided")]}}
	flow._refresh()
	await _frames(3)
	flow._tick(t + 500000)
	await _frames(3)
	_check(reads.call(lobby_path) == before + 5, "a quiet lobby only reads when asked")
	api.replies["GET " + lobby_path] = running_lobby
	# An open duel reads every 30 s; the lobby under it does not read on its own.
	api.replies["GET " + duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": _view({})}}
	flow._open_duel(Client.valid_view(_view({})))
	await _frames(3)
	var lobby_reads: int = reads.call(lobby_path)
	var duel_reads: int = reads.call(duel_path)
	var at := t + 600000
	flow._tick(at)
	flow._tick(at + 29999)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads, "an open duel does not read before 30 s")
	flow._tick(at + 30000)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 1 and reads.call(lobby_path) == lobby_reads, "an open duel reads after 30 s, and the lobby under it does not")
	flow._notification(NOTIFICATION_APPLICATION_PAUSED)
	flow._tick(at + 100000)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 1, "an open duel does not read in the background")
	flow._notification(NOTIFICATION_APPLICATION_RESUMED)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 2 and reads.call(lobby_path) == lobby_reads, "coming back reads the open duel once, and not the lobby under it")
	# A ghost race waiting for its check reads once a minute.
	var ghost := _view({"members": [ME, null], "finished": true, "check": "waiting"})
	ghost.kind = "ghost"
	ghost.ghost = {"source": "developer", "ticks": 900}
	ghost.sides[1] = null
	api.replies["GET " + duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": ghost}}
	flow._open_duel(Client.valid_view(ghost))
	await _frames(3)
	duel_reads = reads.call(duel_path)
	at = t + 800000
	flow._tick(at)
	flow._tick(at + 30000)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads, "a ghost race waiting for its check does not read after 30 s")
	flow._tick(at + 60000)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 1, "a ghost race waiting for its check reads after a minute")
	lobby_reads = reads.call(lobby_path)
	flow.screen.overlay().close()
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 1, "closing the duel reads the lobby at once")
	flow.close()
	await _frames(2)

## Leave shows at once from the server's answer: the page and the lobby under
## it say Left, a read that went out before Leave cannot bring the old duel
## back, and a duel that Leave ended swaps in its result.
func _leaving(api: FakeApi, flow: Node) -> void:
	var duel_path := "/v1/duels/%s/%s" % [BOARD, DUEL]
	api.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_view({})]}}
	flow.open()
	flow.set_process(false)
	await _frames(3)
	var running := Client.valid_view(_view({}))
	flow._open_duel(running)
	await _frames(3)
	var page: CanvasLayer = flow.screen.overlay()
	_check(page != null and page.find_child("DuelLeave", true, false) != null, "a running duel offers Leave")
	var left := _view({"left": true, "turn": null})
	left.updated_ms = 10
	api.replies["POST %s/leave" % duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": left}}
	page.leave_requested.emit(running)
	await _frames(3)
	_check(page.view.sides[0].left and page.find_child("DuelLeave", true, false) == null and page.find_child("DuelPlay", true, false) == null, "the duel page shows Left at once, with nothing left to play")
	var kept: Dictionary = flow.client().last_lobby()
	_check(kept.duels.size() == 1 and kept.duels[0].sides[0].left, "the lobby under it keeps the duel as left too")
	# A read that went out before Leave answers with the older duel: the page stays as it is.
	api.replies["GET " + duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": _view({})}}
	flow._show_duel(page, Client.valid_view(_view({})))
	_check(page.view.sides[0].left, "an older read does not bring back the running duel")
	# Leave that ends the duel (the other pair had left, or a ghost race): the result opens at once.
	var ended := _view({"left": true, "turn": null}, "decided")
	ended.updated_ms = 20
	ended.result = {"outcome": "none", "reason": "left"}
	api.replies["POST %s/leave" % duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": ended}}
	api.replies["GET " + duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": ended}}
	page.leave_requested.emit(page.view)
	await _frames(3)
	_check(flow.screen.overlay() is ResultPage, "a duel that Leave ended shows its result at once")
	flow.close()
	await _frames(2)

## A challenge the server refuses with duel_already_open: the running duel
## opens, one still waiting for an answer shows on the lobby with a line, and
## with none found only the line shows, never the generic failure.
func _already_open(main: FakeMain, api: FakeApi, flow: Node) -> void:
	api.replies["POST /v1/duels/challenge"] = {"ok": false, "status": 409, "code": "duel_already_open"}
	var lobby_with := func(duels: Array) -> Dictionary: return {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": duels}}
	for case: Array in [["running", true], ["challenged", false], ["", false]]:
		var duels: Array = [] if case[0] == "" else [_view({}, case[0])]
		api.replies["GET /v1/duels"] = lobby_with.call(duels)
		flow.open()
		flow.set_process(false)
		await _frames(3)
		var page: CanvasLayer = FakePage.new()
		root.add_child(page)
		main.toasts.clear()
		await flow._challenge(page, FINN, Registry.FIRST_STEPS)
		await _frames(2)
		var overlay: CanvasLayer = flow.screen.overlay()
		var page_gone := not is_instance_valid(page)
		if case[1]:
			_check(page_gone and overlay is DuelPage and overlay.view.duel_id == DUEL and main.toasts.is_empty(), "a running duel with that pair opens instead")
		else:
			_check(main.toasts == [PlayerCopy.DUELS_ALREADY_OPEN], "the refusal says a duel is already open: %s" % [main.toasts])
			_check(overlay == null and page_gone == (case[0] == "challenged"), "a challenge waiting for an answer shows on the lobby; with none found the page stays")
		if is_instance_valid(page): page.close()
		flow.close()
		await _frames(2)
	api.replies.erase("POST /v1/duels/challenge")

func _frames(count: int) -> void:
	for index in range(count): await process_frame

func _clear() -> void:
	for candidate: String in [Client.SAVE_PATH, Client.SAVE_PATH + ".tmp", Client.SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
