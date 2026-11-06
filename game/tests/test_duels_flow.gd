extends SceneTree
## presentation/duels/duels_flow.gd against a stand-in Main: duels hide while
## the server has them off, Play opens your pair's room, joins the one your
## partner made, or makes it, and joins your partner's when both of you made
## one at once; a chapter you have not reached is never played; Accept and
## Not now go to the server once per tap; the community rules card comes before
## anything public (public_duels_flow.gd ask_rules). Synthetic ids only.
const Flow = preload("res://presentation/duels/duels_flow.gd")
const Client = preload("res://services/duels_client.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Registry = preload("res://services/chapter_registry.gd")
const LogWatch = preload("res://tests/log_watch.gd")
const Clock = preload("res://services/refresh_schedule.gd")
const ResultPage = preload("res://presentation/duels/duel_result_page.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const GhostPage = preload("res://presentation/duels/duel_ghost_page.gd")
const Icons = preload("res://presentation/kit/icons.gd")
const PublicFlow = preload("res://presentation/duels/public_duels_flow.gd")
const ChallengePage = preload("res://presentation/duels/duel_challenge_page.gd")
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
	var pending := {}
	var public_on := false
	var safety: RefCounted
	func duels_supported() -> bool: return on
	func public_duels_supported() -> bool: return public_on
	func safety_client() -> RefCounted: return safety
	func pollen_supported() -> bool: return true
	func load_capabilities() -> void: pass
	func pending_lobby() -> Dictionary: return pending.duplicate(true)

## The room steps as relay_lobby_flow.gd takes them: a refusal sets the
## session's code and returns to the hub through Main; a step that goes through
## enters the room. `refuse` refuses the next steps, in order, with those codes
## ("" goes through); `taken` and `missing` refuse every create and join.
class FakeLobby extends RefCounted:
	var calls: Array = []
	var session: FakeSession
	var host: Node
	var taken := false
	var missing := false
	var refuse: Array = []
	## Frames each step takes.
	var frames := 0
	## False: the lobby check stops without a word, its card left up.
	var lobby_ok := true
	## Moved on by Main's return to the hub, as relay_lobby_flow.gd cancel(): a step still out stops.
	var generation := 0
	func open_lobby(chapter: String = "") -> bool:
		calls.append(["open_lobby", chapter])
		return lobby_ok
	func lobby_action(action: String, value: String = "", _hard: bool = false, duel: Dictionary = {}) -> void:
		calls.append([action, value, duel])
		await _answer("duel_room_taken" if taken and action == "duel" else "")
	func join_room(code: String) -> void:
		calls.append(["join", code])
		await _answer("invite_not_found" if missing else "")
	func _answer(code: String) -> void:
		var started := generation
		for index in range(frames): await Engine.get_main_loop().process_frame
		if started != generation: return
		if not refuse.is_empty(): code = refuse.pop_front()
		session.last_lobby_code = code
		if code.is_empty(): host.enter_room()
		else: host._return_to_room_hub("refused " + code)

## The safety client as the rules card uses it: the server's answer (`server_accepts`) a frame later.
class FakeSafety extends RefCounted:
	var terms_accepted := false
	var server_accepts := false
	var checks := 0
	var accepts := 0
	var last_error := ""
	func check_terms() -> bool:
		checks += 1
		await Engine.get_main_loop().process_frame
		terms_accepted = server_accepts
		return true
	func accept_rules() -> bool:
		accepts += 1
		terms_accepted = true
		return true

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
	var duels_flow: Node
	var relay_child: Node
	## The room hub opened, and the rooms entered.
	var hubs := 0
	var hub_notices: Array = []
	var entered := 0
	func ensure_relay_session() -> void: pass
	func _return_to_room_hub(notice: String = "", _refresh: bool = true) -> void:
		relay_lobby_flow.generation += 1
		if duels_flow.return_instead(notice): return
		hubs += 1
		hub_notices.append(notice)
		mode = "rooms"
	func enter_room() -> void:
		entered += 1
		mode = "relay_online"
		if not is_instance_valid(relay_child):
			relay_child = Node.new()
			add_child(relay_child)
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
	main.duels_flow = flow
	main.relay_lobby_flow.host = main
	api.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_view({}, "challenged")]}}
	# Off: nothing opens and no room is tagged.
	main.relay_session.on = false
	flow.open()
	_check(not flow.is_open() and flow.room_kind(ROOM) == "", "duels stay hidden while the server has them off")
	var ghost_wait := {"kind": "ghost", "mine": 0, "sides": [{"check": "waiting"}, null]}
	_check(Flow.refresh_ms(ghost_wait) == Clock.DUEL_CHECK_INTERVAL_MS and Flow.refresh_ms({"kind": "ghost", "mine": 0, "sides": [{"check": "none"}, null]}) == Clock.DUEL_INTERVAL_MS and Flow.refresh_ms({"kind": "friend", "mine": 1, "sides": [{"check": "none"}, {"check": "waiting"}]}) == Clock.DUEL_INTERVAL_MS and Clock.DUEL_INTERVAL_MS == 60000, "without hints an open duel reads once a minute, a ghost race waiting for its check too")
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
	_leave_room(main)
	flow.open()
	await _frames(2)
	await flow._play(Client.valid_view(_view({"room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": false})))
	_check(main.relay_lobby_flow.calls == [["join", "abcdefabcdefabcdefab"]], "Play joins the room your partner made: %s" % [main.relay_lobby_flow.calls])
	# Play: no room yet, so this phone makes it for the duel.
	main.relay_lobby_flow.calls.clear()
	_leave_room(main)
	flow.open()
	await _frames(2)
	await flow._play(Client.valid_view(_view({})))
	_check(main.relay_lobby_flow.calls == [["open_lobby", Registry.FIRST_STEPS], ["duel", Registry.FIRST_STEPS, {"duel_id": DUEL, "board": BOARD}]], "Play makes the pair's room for the duel: %s" % [main.relay_lobby_flow.calls])
	# Both made one at once: the server kept your partner's, so this phone joins it.
	main.relay_lobby_flow.calls.clear()
	main.relay_lobby_flow.taken = true
	api.replies["GET /v1/duels/%s/%s" % [BOARD, DUEL]] = {"ok": true, "data": {"schema_version": 1, "duel": _view({"room_id": ROOM, "invite_code": "fedcbafedcbafedcbafe", "hosting": false})}}
	_leave_room(main)
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
	_leave_room(main)
	await flow._play(Client.valid_view(_view({"room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": false})))
	_check(main.relay_lobby_flow.calls.size() == 3 and main.relay_lobby_flow.calls[2][0] == "duel", "a room that never appeared is made here: %s" % [main.relay_lobby_flow.calls])
	main.relay_lobby_flow.missing = false
	await _play_orders(main, api, flow)
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
	await _picker(main, api, flow)
	await _rules_card(main, api, flow)
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
	# Without hints an open duel reads once a minute; the lobby under it does not read on its own.
	api.replies["GET " + duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": _view({})}}
	flow._open_duel(Client.valid_view(_view({})))
	await _frames(3)
	var lobby_reads: int = reads.call(lobby_path)
	var duel_reads: int = reads.call(duel_path)
	var at := t + 600000
	flow._tick(at)
	flow._tick(at + 59999)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads, "an open duel does not read before a minute")
	flow._tick(at + 60000)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 1 and reads.call(lobby_path) == lobby_reads, "an open duel reads after a minute, and the lobby under it does not")
	flow._notification(NOTIFICATION_APPLICATION_PAUSED)
	flow._tick(at + 100000)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 1, "an open duel does not read in the background")
	flow._notification(NOTIFICATION_APPLICATION_RESUMED)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 2 and reads.call(lobby_path) == lobby_reads, "coming back reads the open duel once, and not the lobby under it")
	api.replies["GET " + duel_path] = {"ok": false, "code": "connection_interrupted"}
	flow._tick(at + 160000)
	await _frames(3)
	for later: int in [165000, 205000]: flow._tick(at + later)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 3, "a failed duel read is not retried within a minute")
	flow._tick(at + 220000)
	await _frames(3)
	_check(reads.call(duel_path) == duel_reads + 4, "an open duel reads again a minute after a failed read")
	# A ghost race waiting for its check reads once a minute.
	var ghost := _view({"members": [ME, null], "finished": true, "check": "waiting"})
	ghost.kind = "ghost"
	ghost.ghost = {"source": "developer", "ticks": 900}
	ghost.sides[1] = null
	api.replies["GET " + duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": ghost}}
	flow._open_duel(Client.valid_view(ghost))
	await _frames(3)
	duel_reads = reads.call(duel_path)
	at = t + 900000
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

## Play in every order, for either member of the pair, in a friend duel and a
## ghost race: the room opens or the duel comes back, never the room hub.
func _play_orders(main: FakeMain, api: FakeApi, flow: Node) -> void:
	var lobby: FakeLobby = main.relay_lobby_flow
	var duel_path := "GET /v1/duels/%s/%s" % [BOARD, DUEL]
	var shown := func() -> bool:
		var page: CanvasLayer = flow.screen.overlay() if flow.is_open() else null
		return page is DuelPage and page.view.duel_id == DUEL and main.mode == Flow.MODE_DUELS
	for kind: String in ["friend", "ghost"]:
		var made := func(own: Dictionary) -> Dictionary: return Client.valid_view(_server_view(kind, own))
		var hubs := main.hubs
		var entered := main.entered
		# The member whose turn is second taps Play before anyone opened the duel: they make the room (whoever opens first does).
		await _tap_play(main, flow, made.call({"turn": 1}))
		_check(lobby.calls.size() == 2 and lobby.calls[1][0] == "duel" and main.entered == entered + 1 and main.hubs == hubs, "%s: the second-turn member's Play makes the pair's room and opens it: %s" % [kind, lobby.calls])
		# The partner already made it: the second member joins and sees the room wait for the partner's turn.
		await _tap_play(main, flow, made.call({"turn": 1, "room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": false}))
		_check(lobby.calls == [["join", "abcdefabcdefabcdefab"]] and main.entered == entered + 2 and main.hubs == hubs, "%s: the room the partner made is joined: %s" % [kind, lobby.calls])
		# The first member opens after the second made the room, from a page read before it: the create is refused and the room joined.
		api.replies[duel_path] = {"ok": true, "data": {"schema_version": 1, "duel": _server_view(kind, {"room_id": ROOM, "invite_code": "fedcbafedcbafedcbafe", "hosting": false})}}
		await _tap_play(main, flow, made.call({"turn": 0}), ["duel_room_taken"])
		_check(lobby.calls.size() == 3 and lobby.calls[2] == ["join", "fedcbafedcbafedcbafe"] and main.entered == entered + 3 and main.hubs == hubs, "%s: a page from before the partner's room joins it: %s" % [kind, lobby.calls])
		# Both tapped at once and the partner's room is still on its way: another join a moment later.
		await _tap_play(main, flow, made.call({}), ["duel_room_taken", "invite_not_found", ""])
		var joins: Array = lobby.calls.filter(func(call: Array) -> bool: return call[0] == "join")
		_check(joins.size() == 2 and main.entered == entered + 4 and main.hubs == hubs, "%s: both at once, a room still on its way is joined on a second try: %s" % [kind, lobby.calls])
		# A refusal Play cannot go on from: the duel's page again, with the reason, never the hub.
		await _tap_play(main, flow, made.call({}), ["duel_not_running"])
		_check(shown.call() and "refused duel_not_running" in main.toasts and main.hubs == hubs, "%s: a refused room brings the duel back with its reason" % kind)
		# The partner's room is gone and making one here is refused too: still the duel.
		await _tap_play(main, flow, made.call({"room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": false}), ["invite_not_found", "room_limit_reached"])
		_check(shown.call() and "refused room_limit_reached" in main.toasts and main.hubs == hubs, "%s: a fallback that fails brings the duel back too" % kind)
		# The lobby check stops without a word: the duel again.
		lobby.lobby_ok = false
		await _tap_play(main, flow, made.call({}))
		lobby.lobby_ok = true
		_check(shown.call() and main.hubs == hubs, "%s: a room step that stops quietly brings the duel back" % kind)
		# Back on the progress card while the room is made: the duel at once; the late answer opens nothing.
		lobby.frames = 4
		_leave_room(main)
		flow._play(made.call({}))
		await _frames(1)
		main._return_to_room_hub("")
		_check(shown.call() and main.hubs == hubs, "%s: Back while the room is made brings the duel back" % kind)
		await _frames(8)
		lobby.frames = 0
		_check(shown.call() and main.entered == entered + 4 and main.hubs == hubs, "%s: the step Back left opens no room afterwards" % kind)
		# Two taps: the second does nothing while the first opens the room.
		lobby.calls.clear()
		lobby.frames = 3
		_leave_room(main)
		var view: Dictionary = made.call({})
		flow._play(view)
		flow._play(view)
		await _frames(8)
		lobby.frames = 0
		_check(lobby.calls.size() == 2 and main.entered == entered + 5, "%s: a second tap while the room opens does nothing: %s" % [kind, lobby.calls])
		# The answer to this duel's create was lost: Play sends that same create again.
		main.relay_session.pending = {"path": "/v2/rooms", "body": {"duel": {"duel_id": DUEL, "board": BOARD}}}
		await _tap_play(main, flow, made.call({}))
		main.relay_session.pending = {}
		_check(lobby.calls.size() == 2 and lobby.calls[1][0] == "retry" and main.entered == entered + 6, "%s: a create whose answer was lost is sent again: %s" % [kind, lobby.calls])
		# Leaving the room afterwards goes to the hub as any room does.
		_leave_room(main)
		main._return_to_room_hub("")
		_check(main.hubs == hubs + 1, "%s: leaving a duel's room goes to the room hub as before" % kind)
		await _more_orders(main, api, flow, made)
		main.mode = "home"
	# Duels switched off while a room was being made: Home, not the hub.
	var hubs_before := main.hubs
	if not flow.is_open(): flow.open()
	await _frames(2)
	lobby.calls.clear()
	lobby.refuse = ["duels_disabled"]
	main.relay_session.on = false
	await flow._play(Client.valid_view(_view({})))
	main.relay_session.on = true
	await _frames(2)
	_check(not flow.is_open() and main.hubs == hubs_before and main.ui.visible, "duels switched off meanwhile: back to Home, never the hub")

## The orders the critic found: a lost create with the partner's room made
## meanwhile, a partner's room that never arrives, another room's saved
## request, and another screen or player taking over mid-step.
func _more_orders(main: FakeMain, api: FakeApi, flow: Node, made: Callable) -> void:
	var lobby: FakeLobby = main.relay_lobby_flow
	var kind: String = made.call({}).kind
	var shown := func() -> bool:
		var page: CanvasLayer = flow.screen.overlay() if flow.is_open() else null
		return page is DuelPage and page.view.duel_id == DUEL and main.mode == Flow.MODE_DUELS
	var hubs := main.hubs
	var entered := main.entered
	# This duel's create lost its answer and the partner made the room meanwhile: the same create goes first, is refused as taken, and the partner's room is joined.
	main.relay_session.pending = {"path": "/v2/rooms", "body": {"duel": {"duel_id": DUEL, "board": BOARD}}}
	await _tap_play(main, flow, made.call({"room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": false}), ["duel_room_taken"])
	main.relay_session.pending = {}
	_check(lobby.calls.size() == 3 and lobby.calls[1][0] == "retry" and lobby.calls[2] == ["join", "fedcbafedcbafedcbafe"] and main.entered == entered + 1 and main.hubs == hubs, "%s: a lost create goes again before the partner's room is joined: %s" % [kind, lobby.calls])
	# The partner's room never arrives: three joins, then the duel with the reason.
	await _tap_play(main, flow, made.call({}), ["duel_room_taken", "invite_not_found", "invite_not_found", "invite_not_found"])
	var joins: Array = lobby.calls.filter(func(call: Array) -> bool: return call[0] == "join")
	_check(joins.size() == Flow.JOIN_TRIES and shown.call() and "refused invite_not_found" in main.toasts and main.hubs == hubs, "%s: a partner's room that never arrives brings the duel back after %d joins: %s" % [kind, Flow.JOIN_TRIES, lobby.calls])
	# Another room's saved create or join holds every room step: the hub's card for it, as for any room.
	main.relay_session.pending = {"path": "/v2/rooms/join", "body": {"invite_code": "fedcbafedcbafedcbafe"}}
	await _tap_play(main, flow, made.call({}))
	main.relay_session.pending = {}
	_check(lobby.calls.is_empty() and main.hubs == hubs + 1 and main.hub_notices.back() == PlayerCopy.RELAY_ONLINE_SESSION_8C3AC7311985 and not flow.is_open(), "%s: another room's saved request goes to the hub's card for it" % kind)
	# Another screen (a notification) takes over mid-step: the duel never comes back over it, and that screen's own hub return goes on.
	for change: String in ["screen", "player"]:
		hubs = main.hubs
		_leave_room(main)
		if not flow.is_open(): flow.open()
		await _frames(2)
		lobby.frames = 4
		lobby.refuse = ["duel_not_running"]
		flow._play(made.call({}))
		await _frames(1)
		if change == "screen": main.mode = "friends"
		else: api.player_id = FINN
		await _frames(8)
		api.player_id = ME
		lobby.frames = 0
		lobby.refuse = []
		_check(not flow.is_open() and main.hubs == hubs + 1, "%s: a %s that changes mid-step gets no duel back over it" % [kind, change])
		main._return_to_room_hub("")
		_check(main.hubs == hubs + 2, "%s: after a %s change, a later hub return is never held for the duel" % [kind, change])
	main.mode = "home"

## Opens `view`'s page over the lobby and taps Play, the room steps answering `refuse` in order.
func _tap_play(main: FakeMain, flow: Node, view: Dictionary, refuse: Array = []) -> void:
	var lobby: FakeLobby = main.relay_lobby_flow
	_leave_room(main)
	lobby.calls.clear()
	main.toasts.clear()
	if not flow.is_open(): flow.open()
	await _frames(2)
	flow._open_duel(view)
	await _frames(1)
	lobby.refuse = refuse.duplicate()
	await flow._play(view)
	await _frames(2)
	lobby.refuse = []

## The room entered last is left, as Duels only opens with no room up.
func _leave_room(main: FakeMain) -> void:
	if is_instance_valid(main.relay_child): main.relay_child.free()
	main.relay_child = null

## The top 10 picker over Race a recorded run: the board's rows with Race,
## a run that left the board before the tap, and the pair's race limit.
func _picker(main: FakeMain, api: FakeApi, flow: Node) -> void:
	var board_path := "GET /v1/leaderboards/" + BOARD
	var row := func(rank: int, entry: String, ticks: int) -> Dictionary: return {"rank": rank, "entry_id": entry.repeat(32), "ticks": ticks, "gold_leaf": rank == 1, "names": ["Lee", "Sam"]}
	api.replies[board_path] = {"ok": true, "data": {"schema_version": 1, "board": BOARD, "top": [row.call(1, "a", 1400), row.call(2, "b", 1500)], "checking": []}}
	flow.open()
	await _frames(2)
	flow._open_ghosts()
	await _frames(4)
	var page: CanvasLayer = flow.screen.overlay()
	_check(page is GhostPage, "Race a recorded run opens")
	if not page is GhostPage: return
	var reads := func() -> int: return api.requests.filter(func(item: Array) -> bool: return "GET " + item[1] == board_path).size()
	var before: int = reads.call()
	await flow._open_picker(page, Registry.FIRST_STEPS, null)
	var picker: Node = page.root.find_child("RacePicker", true, false)
	_check(picker != null and reads.call() == before + 1, "the leaderboard button opens the chapter's top 10, read once")
	if picker == null: return
	var races: Array = picker.find_children("LeaderboardRace", "Button", true, false)
	_check(races.size() == 2 and races.all(func(button: Button) -> bool: return not button.disabled), "each top 10 row has its own Race: %d" % races.size())
	var line: Label = picker.modal.find_child("RacePickerLine", true, false)
	_check(line != null and line.text == PlayerCopy.RACE_PICK_WITH % "Maya", "the sheet names the partner you race with")
	_check((picker.modal.find_child("ModalHeadingIcon", true, false) as TextureRect).texture == Icons.LEADERBOARD, "with the shared leaderboard trophy beside the chapter")
	# The second run left the board between the read and the tap.
	api.replies["POST /v1/duels/ghost"] = {"ok": false, "status": 404, "code": "ghost_not_found"}
	api.replies[board_path] = {"ok": true, "data": {"schema_version": 1, "board": BOARD, "top": [row.call(1, "a", 1400)], "checking": []}}
	before = reads.call()
	(races[1] as Button).pressed.emit()
	await _frames(10)
	_check(main.toasts.back() == PlayerCopy.RACE_PICK_LEFT and reads.call() == before + 1, "a run that left the top 10 says so and the board is read again: %s" % main.toasts.back())
	_check(is_instance_valid(picker) and picker.find_children("LeaderboardRace", "Button", true, false).size() == 1, "the picker shows the board as it is now")
	# Three races going: every Race greys before a tap, under the lobby's limit line.
	var kept_lobby: Dictionary = api.replies["GET /v1/duels"]
	var going: Array = []
	for index in range(3):
		var race := _server_view("ghost", {})
		race.duel_id = str(index).repeat(32)
		going.append(race)
	var lobby := {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": going}
	api.replies["GET /v1/duels"] = {"ok": true, "data": lobby}
	await flow.client().lobby()
	_check(flow.client().ghost_races_full(), "three ghost races going fill the pair's limit")
	await flow._fill_picker(page, picker, Registry.FIRST_STEPS, false)
	var greyed: Array = picker.find_children("LeaderboardRace", "Button", true, false)
	_check(not greyed.is_empty() and greyed.all(func(button: Button) -> bool: return button.disabled) and picker.find_child("RacePickerLimit", true, false) != null, "at the limit every Race greys under the limit line")
	var one_done: Dictionary = lobby.duplicate(true)
	one_done.duels[0].sides[0].finished = true
	_check(Client.ghost_races_going(Client.valid_lobby(one_done)) == 2, "a race whose own side finished no longer counts, as on the server")
	# Opened at the limit, the picker reads the lobby once first: an old lobby never greys rows the server would race.
	var lobby_reads := func() -> int: return api.requests.filter(func(item: Array) -> bool: return item[0] == "GET" and item[1] == "/v1/duels").size()
	api.replies["GET /v1/duels"] = kept_lobby
	page.go_back()
	await _frames(2)
	var asked_lobby: int = lobby_reads.call()
	await flow._open_picker(page, Registry.FIRST_STEPS, null)
	picker = page.root.find_child("RacePicker", true, false)
	_check(lobby_reads.call() == asked_lobby + 1 and not flow.client().ghost_races_full() and picker != null and picker.find_children("LeaderboardRace", "Button", true, false).all(func(button: Button) -> bool: return not button.disabled), "a picker opened at the limit reads the lobby once and races what the server allows")
	# The server says the limit is reached after all: the toast, and the rows grey.
	api.replies["POST /v1/duels/ghost"] = {"ok": false, "status": 409, "code": "duel_limit_reached"}
	(picker.find_children("LeaderboardRace", "Button", true, false)[0] as Button).pressed.emit()
	await _frames(10)
	_check(main.toasts.back() == PlayerCopy.DUELS_RACE_LIMIT % Client.GHOST_LIMIT and picker.find_children("LeaderboardRace", "Button", true, false).all(func(button: Button) -> bool: return button.disabled), "a race refused at the limit says so and greys every row")
	api.replies.erase("POST /v1/duels/ghost")
	# Closed while its board read is out: nothing writes to the gone sheet.
	page.go_back()
	await _frames(2)
	var watch: LogWatch = LogWatch.start(["previously freed", "Invalid"])
	api.delays[board_path] = 6
	flow._open_picker(page, Registry.FIRST_STEPS, null)
	await _frames(1)
	api.replies[board_path] = {"ok": true, "data": {"schema_version": 1, "board": BOARD, "top": [row.call(1, "a", 1400)], "checking": []}}
	page.go_back()
	await _frames(10)
	_check(watch.count("previously freed") == 0 and watch.count("Invalid") == 0 and page.alive(), "a picker closed while its board loads is left alone")
	watch.stop()
	api.delays.erase(board_path)
	# Back closes the sheet first, then the page.
	await flow._open_picker(page, Registry.FIRST_STEPS, null)
	page.go_back()
	await _frames(2)
	_check(is_instance_valid(page) and page.alive() and page.root.find_child("RacePicker", true, false) == null, "Back closes the picker and leaves Race a recorded run open")
	page.close()
	flow.close()
	await _frames(2)

## The community rules card before anything public: the first lobby read after Duels opens (once a
## launch) and a party invite just accepted, only while public duels are open, the switch is on and
## the lobby says the rules are not accepted. A partner without them greys Post duel with the reason.
func _rules_card(main: FakeMain, api: FakeApi, flow: Node) -> void:
	var safety := FakeSafety.new()
	main.relay_session.safety = safety
	main.relay_session.public_on = true
	var party := {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}
	var lobby := func(rules: bool, partner_rules: Variant, on := true) -> Dictionary:
		return {"ok": true, "data": {"schema_version": 1, "party": party, "duels": [],
			"public": {"version": 1, "on": on, "show_name": false, "partner_on": true, "paused": false, "running": 0, "rules": rules, "partner_rules": partner_rules}}}
	var card := func() -> bool: return flow.is_open() and flow.screen.find_child("PublicFirstTime", true, false) != null
	var reopen := func() -> void:
		if flow.is_open(): flow.close()
		await _frames(2)
		flow.open()
		await _frames(8)
	PublicFlow._rules_asked = false
	# Switched off (a child's phone): never asked.
	api.replies["GET /v1/duels"] = lobby.call(false, true, false)
	await reopen.call()
	_check(not card.call() and safety.checks == 0, "a player who switched public duels off is never asked for the rules")
	# Accepted: nothing asked, nothing checked.
	api.replies["GET /v1/duels"] = lobby.call(true, true)
	await reopen.call()
	_check(not card.call() and safety.checks == 0, "a player whose lobby says the rules are accepted is not asked")
	# The lobby lost its copy but the server holds the acceptance: sent again, no card.
	api.replies["GET /v1/duels"] = lobby.call(false, true)
	safety.server_accepts = true
	await reopen.call()
	_check(not card.call() and safety.checks == 1 and safety.accepts == 1, "an acceptance the server holds is sent again for the lobby's copy, with no card")
	# Not accepted: the card on opening Duels, once a launch.
	safety.server_accepts = false
	await reopen.call()
	_check(card.call(), "opening Duels without the rules shows the rules card first")
	await reopen.call()
	_check(not card.call(), "opening Duels again the same launch asks no more")
	# A party invite just accepted asks again, after the accept went through.
	api.replies["POST /v1/duels/party/accept"] = lobby.call(false, null)
	flow._open_party()
	await _frames(4)
	var accepted: CanvasLayer = flow.screen.overlay()
	await flow._party(accepted, "accept", MAYA)
	await _frames(4)
	_check(api.requests.any(func(item: Array) -> bool: return item[1] == "/v1/duels/party/accept") and accepted.find_child("PublicFirstTime", true, false) != null, "a party invite accepted shows the rules card after it")
	accepted.close()
	await _frames(2)
	# A partner without the rules: Start a duel's Post duel with them greys with the approved line.
	api.replies["GET /v1/duels"] = lobby.call(true, false)
	await reopen.call()
	flow._open_challenge(true)
	await _frames(4)
	var start: CanvasLayer = flow.screen.overlay()
	_check(start is ChallengePage and start.party_reason == PlayerCopy.PUBLIC_PARTNER_RULES % "Maya", "Post duel with a partner who has not accepted the rules says why: %s" % [start.get("party_reason") if start != null else null])
	# Maya accepts while the page is up: the next lobby read (the one read path) clears it there.
	api.replies["GET /v1/duels"] = lobby.call(true, true)
	flow._refresh()
	await _frames(6)
	_check(start.party_reason == "" and start.partner_name == "Maya", "a lobby read after the partner accepted clears the reason on Start a duel")
	# Maya leaves the party: Start a duel posts alone, never live with a partner who is gone.
	api.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": null, "intact": false, "invites_in": [], "invite_out": null}, "duels": [],
		"public": {"version": 1, "on": true, "show_name": false, "partner_on": null, "paused": false, "running": 0, "rules": true, "partner_rules": null}}}
	flow._refresh()
	await _frames(6)
	_check(start.partner_name == "" and not start._posting_party(), "a partner who left takes With partner off Start a duel")
	if start != null: start.close()
	await _frames(2)
	flow.close()
	await _frames(2)
	main.relay_session.public_on = false
	main.relay_session.safety = null
	PublicFlow._rules_asked = false

## A duel as the server answers it, with this phone's side as `own` says.
func _server_view(kind: String, own: Dictionary) -> Dictionary:
	var view := _view(own)
	if kind == "ghost":
		view.kind = "ghost"
		view.sides[1] = null
		view.ghost = {"source": "developer", "entry_id": null, "rank": null, "ticks": 588, "names": null}
	return view

func _frames(count: int) -> void:
	for index in range(count): await process_frame

func _clear() -> void:
	for candidate: String in [Client.SAVE_PATH, Client.SAVE_PATH + ".tmp", Client.SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
