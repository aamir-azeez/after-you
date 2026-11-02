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
	## Frames a request takes to answer, by "METHOD path" (1 when not named).
	var delays: Dictionary = {}
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		var name: String = {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_POST: "POST"}.get(method, "?")
		requests.append([name, path, body])
		for index in range(int(delays.get(name + " " + path, 1))): await Engine.get_main_loop().process_frame
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

## Main's live socket: hints by hand, healthy while `good`.
class FakeLive extends Node:
	signal duels_changed(duel_id: String, at_ms: int)
	signal missed_hints(since_ms: int)
	var good := false
	func healthy() -> bool: return good

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
	var live_connection: Node
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
	main.live_connection = FakeLive.new()
	main.add_child(main.live_connection)
	var flow := Flow.new(main)
	main.add_child(flow)
	api.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_view({}, "challenged")]}}
	# Off: nothing opens and no room is tagged.
	main.relay_session.on = false
	flow.open()
	_check(not flow.is_open() and flow.room_kind(ROOM) == "", "duels stay hidden while the server has them off")
	var ghost_wait := {"kind": "ghost", "mine": 0, "sides": [{"check": "waiting"}, null]}
	_check(Flow.refresh_ms(ghost_wait) == Clock.DUEL_CHECK_INTERVAL_MS and Flow.refresh_ms({"kind": "ghost", "mine": 0, "sides": [{"check": "none"}, null]}) == Clock.DUEL_INTERVAL_MS and Flow.refresh_ms({"kind": "friend", "mine": 1, "sides": [{"check": "none"}, {"check": "waiting"}]}) == Clock.DUEL_INTERVAL_MS, "a ghost race waiting for its check reads less often, every other duel as before")
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
	# The limit line names the number the lobby reported, or the server's own before any lobby said one.
	_check(main.toasts.back() == PlayerCopy.DUELS_LIMIT % Client.FRIEND_LIMIT and Client.FRIEND_LIMIT == 10, "a challenge past the limit says how many duels a party may have: %s" % main.toasts.back())
	api.replies["POST /v1/duels/ghost"] = {"ok": false, "status": 409, "code": "duel_limit_reached"}
	await flow._race(asked, Registry.FIRST_STEPS, "developer", null)
	_check(main.toasts.back() == PlayerCopy.DUELS_RACE_LIMIT % Client.GHOST_LIMIT and Client.GHOST_LIMIT == 3, "a race past its own limit says races, with its own number: %s" % main.toasts.back())
	var kept_lobby: Dictionary = api.replies["GET /v1/duels"]
	api.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [], "limits": {"friend": 7, "ghost": 2}}}
	await flow.client().lobby()
	await flow._challenge(asked, FINN, Registry.FIRST_STEPS)
	_check(main.toasts.back() == PlayerCopy.DUELS_LIMIT % 7, "the server's number wins over the phone's: %s" % main.toasts.back())
	await flow._race(asked, Registry.FIRST_STEPS, "developer", null)
	_check(main.toasts.back() == PlayerCopy.DUELS_RACE_LIMIT % 2, "and for races too: %s" % main.toasts.back())
	api.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [], "limits": {"friend": "lots", "ghost": -1}}}
	await flow.client().lobby()
	_check(flow.client().limit("friend") == Client.FRIEND_LIMIT and flow.client().limit("ghost") == Client.GHOST_LIMIT, "a limit this build cannot read falls back to the server's own")
	api.replies["GET /v1/duels"] = kept_lobby
	api.replies.erase("POST /v1/duels/ghost")
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
	await _hinted(main, api, flow)
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
	# A failed read keeps the minute: no quicker retries.
	api.replies["GET " + lobby_path] = {"ok": false, "code": "connection_interrupted"}
	flow._tick(t + 361000)
	await _frames(3)
	for later: int in [366000, 376000, 391000]: flow._tick(t + later)
	await _frames(3)
	_check(reads.call(lobby_path) == before + 5, "a failed lobby read is not retried within the minute: %d" % (reads.call(lobby_path) - before))
	flow._tick(t + 421000)
	await _frames(3)
	_check(reads.call(lobby_path) == before + 6, "the lobby reads again a minute after a failed read")
	api.replies["GET " + lobby_path] = running_lobby
	# Nothing can change without this player: no timed read, but a page closing still reads at once.
	api.replies["GET " + lobby_path] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_view({}, "decided")]}}
	flow._refresh()
	await _frames(3)
	flow._tick(t + 500000)
	await _frames(3)
	_check(reads.call(lobby_path) == before + 7, "a quiet lobby only reads when asked")
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
	api.replies["GET " + duel_path] = {"ok": false, "code": "connection_interrupted"}
	flow._tick(at + 130000)
	await _frames(3)
	for later: int in [135000, 145000]: flow._tick(at + later)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 3, "a failed duel read is not retried within 30 s")
	flow._tick(at + 160000)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 4, "an open duel reads again 30 s after a failed read")
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
	# Reads of the duel and of the lobby go out before Leave and answer after it, with the older running duel.
	api.replies["GET " + duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": _view({})}}
	api.delays = {"GET " + duel_path: 8, "GET /v1/duels": 8}
	var reads := func(path: String) -> int: return api.requests.filter(func(item: Array) -> bool: return item[0] == "GET" and item[1] == path).size()
	var duel_reads: int = reads.call(duel_path) + 1
	var lobby_reads: int = reads.call("/v1/duels") + 1
	var at := Time.get_ticks_msec() + 2000000
	flow._tick(at)
	flow._tick(at + Clock.DUEL_INTERVAL_MS)
	flow._refresh()
	page.leave_requested.emit(running)
	await _frames(3)
	_check(page.view.sides[0].left and page.find_child("DuelLeave", true, false) == null and page.find_child("DuelPlay", true, false) == null, "the duel page shows Left at once, with nothing left to play")
	var kept: Dictionary = flow.client().last_lobby()
	_check(kept.duels.size() == 1 and kept.duels[0].sides[0].left, "the lobby under it keeps the duel as left too")
	await _frames(10)
	api.delays = {}
	kept = flow.client().last_lobby()
	_check(reads.call(duel_path) == duel_reads and reads.call("/v1/duels") == lobby_reads, "both older reads were out before Leave")
	_check(page.view.sides[0].left and page.find_child("DuelLeave", true, false) == null, "a duel read that went out before Leave does not bring back the running duel")
	_check(kept.duels.size() == 1 and kept.duels[0].sides[0].left, "a lobby read that went out before Leave keeps the duel as left")
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
		# Newer than any copy of this duel the earlier steps kept.
		for view: Dictionary in duels: view.updated_ms = 100
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

## With a healthy socket to a server that sends duel hints, a hint reads only
## the screen it touches, once per burst, and the timed reads drop to the
## backup pace; a dropped socket brings back the old pace, and a socket that
## comes back reads once.
func _hinted(main: FakeMain, api: FakeApi, flow: Node) -> void:
	var lobby_path := "/v1/duels"
	var duel_path := "/v1/duels/%s/%s" % [BOARD, DUEL]
	var other := "e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1"
	var reads := func(path: String) -> int: return api.requests.filter(func(item: Array) -> bool: return item[0] == "GET" and item[1] == path).size()
	var live: FakeLive = main.live_connection
	var running := _view({})
	running.updated_ms = 200
	var hinted_lobby := {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [running], "duel_hints_version": 1}}
	api.replies["GET " + lobby_path] = hinted_lobby
	api.replies["GET " + duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": running, "duel_hints_version": 1}}
	live.good = true
	flow.open()
	flow.set_process(false)
	await _frames(3)
	# The first frame after the open read takes the pace its answer set (a read the older clocks still owed comes here).
	var at := Time.get_ticks_msec() + 4000000
	flow._tick(at)
	await _frames(3)
	var lobby_reads: int = reads.call(lobby_path)
	flow._tick(at + Clock.DUELS_LOBBY_INTERVAL_MS + 1000)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads, "with hints the lobby does not read every minute")
	for index in range(3): live.duels_changed.emit("", 300)
	flow._tick(at + 70000)
	await _frames(3)
	flow._tick(at + 70001)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 1, "hints arriving together read the lobby once: %d" % (reads.call(lobby_path) - lobby_reads))
	live.duels_changed.emit(DUEL, 200)
	flow._tick(at + 80000)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 1, "a hint for a duel the lobby already has as new reads nothing")
	# Each turn in a running duel sends a hint; its tile shows the dots, time and whose turn it is, so that duel alone reads, once per burst.
	var stepped := running.duplicate(true)
	stepped.updated_ms = 252
	stepped.sides[1].steps = 1
	api.replies["GET " + duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": stepped, "duel_hints_version": 1}}
	var single_reads: int = reads.call(duel_path)
	for index in range(3): live.duels_changed.emit(DUEL, 250 + index)
	flow._tick(at + 85000)
	await _frames(3)
	flow._tick(at + 85001)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 1 and reads.call(duel_path) == single_reads + 1, "turn hints for a duel the lobby shows read that duel once, and not the lobby: %d, %d" % [reads.call(lobby_path) - lobby_reads - 1, reads.call(duel_path) - single_reads])
	var tile: Dictionary = flow.client().last_lobby().duels[0]
	_check(int(tile.updated_ms) == 252 and int(tile.sides[1].steps) == 1 and flow.screen._lobby.duels[0].updated_ms == 252, "the duel's newer copy goes into the lobby and its tile redraws")
	live.duels_changed.emit(DUEL, 252)
	flow._tick(at + 85002)
	await _frames(3)
	_check(reads.call(duel_path) == single_reads + 1, "a hint the patched tile already shows reads nothing")
	live.duels_changed.emit(other, 300)
	flow._tick(at + 90000)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 2, "a hint for a duel the lobby lacks reads the lobby")
	flow._tick(at + 90000 + Clock.DUELS_LOBBY_BACKUP_MS)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 3, "the lobby still reads at the backup pace")
	# The socket drops: the minute comes back at once.
	live.good = false
	var dropped := at + 100000 + Clock.DUELS_LOBBY_BACKUP_MS
	flow._tick(dropped)
	flow._tick(dropped + Clock.DUELS_LOBBY_INTERVAL_MS)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 4, "without the socket the lobby reads every minute again")
	# A socket that comes back reads once, unless a read begun since it dropped covers it.
	live.good = true
	live.missed_hints.emit(dropped)
	flow._tick(dropped + Clock.DUELS_LOBBY_INTERVAL_MS + 1)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 4, "a read begun after the socket dropped covers the hints it missed")
	live.missed_hints.emit(dropped + Clock.DUELS_LOBBY_INTERVAL_MS + 1)
	flow._tick(dropped + Clock.DUELS_LOBBY_INTERVAL_MS + 2)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 5, "a socket that comes back reads the lobby once")
	# An open duel: its hint reads it alone, other hints wait for the page to close.
	flow._open_duel(Client.valid_view(running))
	await _frames(3)
	lobby_reads = reads.call(lobby_path)
	var duel_reads: int = reads.call(duel_path)
	var later := dropped + 2 * Clock.DUELS_LOBBY_INTERVAL_MS
	flow._tick(later)
	flow._tick(later + Clock.DUEL_INTERVAL_MS)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads, "with hints an open duel does not read every 30 s")
	live.duels_changed.emit(DUEL, 150)
	live.duels_changed.emit(other, 400)
	live.duels_changed.emit("", 400)
	flow._tick(later + Clock.DUEL_INTERVAL_MS + 1)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads and reads.call(lobby_path) == lobby_reads, "an older hint for the open duel and hints for the lobby under it read nothing")
	# The other pair takes two turns: their hints read the open duel once, and its page shows the new steps.
	var turned := running.duplicate(true)
	turned.updated_ms = 501
	turned.sides[1].steps = 2
	turned.sides[1].ticks = 190
	api.replies["GET " + duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": turned, "duel_hints_version": 1}}
	live.duels_changed.emit(DUEL, 500)
	live.duels_changed.emit(DUEL, 501)
	flow._tick(later + Clock.DUEL_INTERVAL_MS + 2)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 1 and reads.call(lobby_path) == lobby_reads, "hints for the open duel read it once, and not the lobby")
	var open_page: CanvasLayer = flow.screen.overlay()
	_check(open_page != null and int(open_page.view.sides[1].steps) == 2 and int(open_page.view.updated_ms) == 501, "a turn hint brings the other pair's new steps to the open duel")
	flow._tick(later + Clock.DUEL_INTERVAL_MS + 2 + Clock.DUEL_BACKUP_MS)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 2, "an open duel still reads at its backup pace")
	# A server rolled back to one without hints: its next answer brings back the old pace.
	var plain := running.duplicate(true)
	plain.updated_ms = 700
	api.replies["GET " + duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": plain}}
	live.duels_changed.emit(DUEL, 700)
	var ending := later + Clock.DUEL_INTERVAL_MS + 3 + Clock.DUEL_BACKUP_MS
	flow._tick(ending)
	await _frames(3)
	# The next frame takes the pace that answer set.
	flow._tick(ending + 1)
	flow._tick(ending + 1 + Clock.DUEL_INTERVAL_MS)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 4, "a server that stopped sending hints brings back the 30 s pace at its next answer: %d" % (reads.call(duel_path) - duel_reads))
	live.good = false
	flow.close()
	await _frames(2)
	await _hint_reads(main, api, flow)

## Hints with the lobby in front: list changes read the lobby at most once per
## DUELS_LIST_HINT_GAP_MS; a duel that ended, or whose read failed, reads the
## lobby too; many duels waiting at once read the lobby instead; a duel read
## answered after a newer lobby keeps the newer copy; nothing reads in the
## background; without hints, five running duels read every two minutes.
func _hint_reads(main: FakeMain, api: FakeApi, flow: Node) -> void:
	var lobby_path := "/v1/duels"
	var reads := func(path: String) -> int: return api.requests.filter(func(item: Array) -> bool: return item[0] == "GET" and item[1] == path).size()
	var live: FakeLive = main.live_connection
	var ids := ["d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0", "e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1", "f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2", "a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3", "b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4"]
	var views: Array = []
	for id: String in ids:
		var view := _view({})
		view.duel_id = id
		view.updated_ms = 1000
		views.append(view)
	var path_of := func(index: int) -> String: return "/v1/duels/%s/%s" % [BOARD, ids[index]]
	for index in range(ids.size()): api.replies["GET " + path_of.call(index)] = {"ok": true, "data": {"schema_version": 1, "duel": views[index], "duel_hints_version": 1}}
	api.replies["GET " + lobby_path] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": views, "duel_hints_version": 1}}
	live.good = true
	flow.open()
	flow.set_process(false)
	await _frames(3)
	var at := Time.get_ticks_msec() + 9000000
	flow._tick(at)
	await _frames(3)
	# A read that begins at `at` for certain: the gap counts from it.
	flow._refresh()
	await _frames(3)
	var lobby_reads: int = reads.call(lobby_path)
	# A burst of list changes reads once, no sooner than the gap after the last read began.
	live.duels_changed.emit("", 1100)
	flow._tick(at + 1000)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads, "a list change right after a read waits for the gap")
	live.duels_changed.emit("c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5", 1100)
	flow._tick(at + Clock.DUELS_LIST_HINT_GAP_MS - 1)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads, "still waiting just before the gap")
	flow._tick(at + Clock.DUELS_LIST_HINT_GAP_MS)
	await _frames(3)
	flow._tick(at + Clock.DUELS_LIST_HINT_GAP_MS + 1)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 1, "list changes in one gap read the lobby once: %d" % (reads.call(lobby_path) - lobby_reads))
	# An own action still reads at once.
	flow._refresh()
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 2, "an own action reads the lobby at once, gap or not")
	lobby_reads += 2
	var t := at + 100000
	# A duel that ended: its read redraws the tile and asks for the lobby, spaced.
	var ended: Dictionary = views[0].duplicate(true)
	ended.status = "decided"
	ended.updated_ms = 1200
	ended.result = {"outcome": "won", "reason": "faster", "margin_ticks": 30, "decided_ms": 1200}
	api.replies["GET " + path_of.call(0)] = {"ok": true, "data": {"schema_version": 1, "duel": ended, "duel_hints_version": 1}}
	var ended_reads: int = reads.call(path_of.call(0))
	live.duels_changed.emit(ids[0], 1200)
	flow._tick(t)
	await _frames(3)
	_check(reads.call(path_of.call(0)) == ended_reads + 1 and flow.client().last_lobby().duels.any(func(view: Dictionary) -> bool: return view.duel_id == ids[0] and view.status == "decided"), "an ended duel's read puts its result on the lobby")
	flow._tick(t + 1)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 1, "an ended duel reads the lobby once after it: %d" % (reads.call(lobby_path) - lobby_reads))
	lobby_reads += 1
	# A duel the server no longer has: the lobby reads, spaced, and nothing retries the duel.
	api.replies["GET " + path_of.call(1)] = {"ok": false, "status": 404, "code": "duel_not_found"}
	live.duels_changed.emit(ids[1], 1300)
	t += 100000
	flow._tick(t)
	await _frames(3)
	flow._tick(t + 1)
	await _frames(3)
	flow._tick(t + 2)
	await _frames(3)
	_check(reads.call(path_of.call(1)) == 1 and reads.call(lobby_path) == lobby_reads + 1, "a duel read that fails reads the lobby once, and never again by itself: %d, %d" % [reads.call(path_of.call(1)), reads.call(lobby_path) - lobby_reads])
	lobby_reads += 1
	api.replies["GET " + path_of.call(1)] = {"ok": true, "data": {"schema_version": 1, "duel": views[1], "duel_hints_version": 1}}
	# Many duels at once (a burst of turns on every tile): the lobby once costs less than each duel's read.
	var singles := func() -> int:
		var count := 0
		for index in range(ids.size()): count += reads.call(path_of.call(index))
		return count
	var before_singles: int = singles.call()
	for index in range(2, 5): live.duels_changed.emit(ids[index], 1400)
	t += 100000
	flow._tick(t)
	await _frames(3)
	flow._tick(t + 1)
	await _frames(3)
	_check(singles.call() == before_singles and reads.call(lobby_path) == lobby_reads + 1, "three duels waiting on one chapter read the lobby once instead: %d, %d" % [singles.call() - before_singles, reads.call(lobby_path) - lobby_reads])
	lobby_reads += 1
	# A duel's read answered after a newer lobby keeps the newer copy.
	var older: Dictionary = views[2].duplicate(true)
	older.updated_ms = 1500
	var newer: Dictionary = views[2].duplicate(true)
	newer.updated_ms = 1600
	newer.sides[1].steps = 3
	api.replies["GET " + path_of.call(2)] = {"ok": true, "data": {"schema_version": 1, "duel": older, "duel_hints_version": 1}}
	api.delays["GET " + path_of.call(2)] = 8
	live.duels_changed.emit(ids[2], 1500)
	t += 100000
	flow._tick(t)
	await _frames(1)
	var fresh: Array = views.duplicate(true)
	fresh[2] = newer
	fresh[0] = ended
	api.replies["GET " + lobby_path] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": fresh, "duel_hints_version": 1}}
	flow._refresh()
	await _frames(12)
	var kept: Dictionary = flow.client().last_lobby().duels.filter(func(view: Dictionary) -> bool: return view.duel_id == ids[2])[0]
	_check(int(kept.updated_ms) == 1600 and int(kept.sides[1].steps) == 3, "a duel read that answers after a newer lobby read leaves the newer copy: %d" % int(kept.updated_ms))
	api.delays.erase("GET " + path_of.call(2))
	# In the background a hinted duel waits; coming back reads the lobby, which covers it.
	var paused_singles: int = singles.call()
	flow._notification(NOTIFICATION_APPLICATION_PAUSED)
	live.duels_changed.emit(ids[3], 1700)
	t += 100000
	flow._tick(t)
	await _frames(3)
	_check(singles.call() == paused_singles, "nothing reads a hinted duel in the background")
	var moved: Array = fresh.duplicate(true)
	moved[3].updated_ms = 1700
	api.replies["GET " + lobby_path] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": moved, "duel_hints_version": 1}}
	lobby_reads = reads.call(lobby_path)
	flow._notification(NOTIFICATION_APPLICATION_RESUMED)
	await _frames(3)
	flow._tick(t + 1)
	await _frames(3)
	flow._tick(t + 2)
	await _frames(3)
	# (The resume's own read runs on the real clock here, so a duel read may come first; services/duel_hint_reads.gd drops one the lobby caught up on.)
	var resumed: Dictionary = flow.client().last_lobby().duels.filter(func(view: Dictionary) -> bool: return view.duel_id == ids[3])[0]
	_check(reads.call(lobby_path) == lobby_reads + 1 and int(resumed.updated_ms) == 1700, "coming back reads the lobby once and shows the duel hinted while away: %d" % (reads.call(lobby_path) - lobby_reads))
	# Without hints: the minute pace, and two minutes with five or more running.
	var four: Array = views.slice(0, 4)
	_check(Flow.lobby_refresh_ms({"duels": four}) == Clock.DUELS_LOBBY_INTERVAL_MS and Flow.lobby_refresh_ms({"duels": views}) == Clock.DUELS_LOBBY_BUSY_INTERVAL_MS and Flow.lobby_refresh_ms({"duels": views}, true) == Clock.DUELS_LOBBY_BACKUP_MS, "five running duels read every two minutes without hints, four every minute")
	var ended_five: Array = views.duplicate(true)
	ended_five[0] = ended
	_check(Flow.lobby_refresh_ms({"duels": ended_five}) == Clock.DUELS_LOBBY_INTERVAL_MS, "only running duels count toward the slower pace")
	live.good = false
	var busy: Array = views.duplicate(true)
	for view: Dictionary in busy: view.updated_ms = 5000
	api.replies["GET " + lobby_path] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": busy}}
	flow._refresh()
	await _frames(3)
	# The read the minute pace still owed: from its answer on, the pace is two minutes.
	t += 100000
	flow._tick(t)
	await _frames(3)
	lobby_reads = reads.call(lobby_path)
	var slow_start := t
	flow._tick(slow_start + Clock.DUELS_LOBBY_INTERVAL_MS + 1)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads, "five running duels do not read after a minute")
	flow._tick(slow_start + Clock.DUELS_LOBBY_BUSY_INTERVAL_MS + 1)
	await _frames(3)
	_check(reads.call(lobby_path) == lobby_reads + 1, "five running duels read after two minutes: %d" % (reads.call(lobby_path) - lobby_reads))
	flow.close()
	await _frames(2)

func _frames(count: int) -> void:
	for index in range(count): await process_frame

func _clear() -> void:
	for candidate: String in [Client.SAVE_PATH, Client.SAVE_PATH + ".tmp", Client.SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
