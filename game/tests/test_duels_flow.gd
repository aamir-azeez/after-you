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
		requests.append([name, path])
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
	func open_lobby(chapter: String = "") -> bool:
		calls.append(["open_lobby", chapter])
		return true
	func lobby_action(action: String, value: String = "", _hard: bool = false, duel: Dictionary = {}) -> void:
		calls.append([action, value, duel])
		session.last_lobby_code = "duel_room_taken" if taken and action == "duel" else ""
	func join_room(code: String) -> void:
		calls.append(["join", code])

class FakeFriends extends RefCounted:
	func view() -> Dictionary: return {"friends": [{"player_id": MAYA, "status": "accepted"}, {"player_id": FINN, "status": "accepted"}]}
	func refresh(_manual: bool = false) -> bool: return true

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
	func _friends_client(_create: bool) -> RefCounted: return FakeFriends.new()
	func _friend_display_name(id: String) -> String: return {MAYA: "Maya", FINN: "Finn"}.get(id, "a friend")
	func _toast(text: String) -> void: toasts.append(text)
	func _chapter_unlocks() -> Dictionary: return unlocks
	func _full_journey_access() -> bool: return false
	func _paid_content_hidden() -> bool: return false

func _view(own: Dictionary, status: String = "running") -> Dictionary:
	var side := {"members": [ME, MAYA], "you": true, "steps": 0, "ticks": 0, "assisted": false, "turn": null, "finished": false, "left": false, "check": "none", "room_id": null, "invite_code": null, "hosting": false}
	side.merge(own, true)
	return {"schema_version": 1, "duel_id": DUEL, "kind": "friend", "board": BOARD, "status": status, "steps": 4, "created_ms": 1, "accepted_ms": 2, "updated_ms": 3, "mine": 0,
		"ghost": null, "result": null, "eligible": true, "sides": [side, {"members": [FINN, null], "you": false, "steps": 0, "ticks": 0, "assisted": false, "turn": null, "finished": false, "left": false, "check": "none"}]}

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
	# Room tags and duel clears come from what the client kept.
	api.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_view({"room_id": ROOM, "finished": true, "check": "waiting"})]}}
	await flow.client().lobby()
	_check(flow.room_kind(ROOM) == "friend" and flow.finished_chapters() == [BOARD], "a duel room is tagged and its clear counts")
	flow.close()
	await _frames(2)
	_check(not flow.is_open(), "close takes the lobby away")
	main.queue_free()
	api.queue_free()
	await process_frame
	_clear()
	print("AFTER YOU DUELS FLOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _frames(count: int) -> void:
	for index in range(count): await process_frame

func _clear() -> void:
	for candidate: String in [Client.SAVE_PATH, Client.SAVE_PATH + ".tmp", Client.SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
