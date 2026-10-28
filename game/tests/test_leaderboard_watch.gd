extends SceneTree
## Watching a top 10 run: services/leaderboard_replay.gd (the server's answer,
## decoded through the shared blob format into viewer parts that name no room
## or player), the Watch button (presentation/leaderboard_rows.gd and
## leaderboard_screen.gd), and Friends' flow opening the shared replay viewer in
## its leaderboard mode over everything, with Back returning to the board.
## Every request goes to a fake transport.
const Client = preload("res://services/leaderboard_client.gd")
const Screen = preload("res://presentation/leaderboard_screen.gd")
const FriendsFlow = preload("res://presentation/friends_flow.gd")
const View = preload("res://presentation/shared_replay_view.gd")
const LeaderboardReplay = preload("res://services/leaderboard_replay.gd")
const BlobCodec = preload("res://services/blob_codec.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const OWNER := "OOOOOOOOOOOOOOOOOOOOOO"
const BOARD := "relay-isles@2"
const CHOICE_PATH := "user://leaderboard-watch-name-test.json"
const FIXTURE := "res://tests/fixtures/v2/final-checkpoint.json"
const ENTRY := "e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0"
const OTHER := "f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1"

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

## A stand-in for services/rooms_api.gd: answers from `replies` by "METHOD path" and records each request.
class FakeApi extends Node:
	var replies: Dictionary = {}
	var requests: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		var name: String = {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_PUT: "PUT", HTTPClient.METHOD_POST: "POST"}.get(method, "?")
		requests.append([name, path, body])
		await Engine.get_main_loop().process_frame
		return replies.get(name + " " + path, {"ok": false, "code": "not_found"}).duplicate(true)

class FakeSound extends RefCounted:
	var backgrounded := false
	func set_backgrounded(value: bool) -> void: backgrounded = value

class FakeSaves extends RefCounted:
	var data := {"settings": {"sound": false, "haptics": false, "reduced_motion": true}}

## Friends' page, as far as its flow closes it.
class FakeFriends extends CanvasLayer:
	func close() -> void: queue_free()

## The part of Main that Friends' flow uses to play a replay.
class FakeHost extends Node:
	var shared_replay_child: Node3D
	var application_backgrounded := false
	var api: Node
	var saves := FakeSaves.new()
	var soundscape := FakeSound.new()
	var world_visible := true
	func _relay_identity() -> Dictionary: return {"ready": true, "player_id": "OOOOOOOOOOOOOOOOOOOOOO"}
	func _set_world_visible(value: bool) -> void: world_visible = value

func _run() -> void:
	_clear()
	var answer := _answer()
	_parts(answer)
	await _watch(answer)
	_clear()
	print("Leaderboard watch: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _clear() -> void:
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(CHOICE_PATH + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(CHOICE_PATH + suffix))

## The server's answer for the fixture's final checkpoint, encoded as the backend encodes it.
func _answer() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(FIXTURE)
	var tagged := PackedByteArray([BlobCodec.ENCODING_DEFLATE])
	tagged.append_array(bytes.compress(FileAccess.COMPRESSION_DEFLATE))
	return {"schema_version": 1, "board": BOARD, "entry_id": ENTRY, "rank": 1, "ticks": 588, "finished_on": "2026-10-20", "names": null, "gold_leaf": true,
		"digest": BlobCodec.digest(bytes), "byte_length": bytes.size(), "body": Marshalls.raw_to_base64(tagged)}

func _parts(answer: Dictionary) -> void:
	var hash: String = answer.digest
	var parts := LeaderboardReplay.parts(answer, BOARD, ENTRY, hash, Registry.RELAY)
	_check(parts.size() == 2 and parts[0].pair.stage_index == 0 and parts[1].pair.stage_index == 1, "a whole run becomes one part a stage: %d" % parts.size())
	_check(parts.all(func(part: Dictionary) -> bool: return part.room == {"family": "chapter", "chapter_key": Registry.RELAY}), "a part names only its chapter")
	var text := var_to_str(parts)
	_check(not ("host_id" in text or "guest_id" in text or "room_id" in text or "player_id" in text), "nothing in a part names a room or a player")
	_check(View.valid_board_sequence(parts, Registry.RELAY), "the viewer replays every part of the run")
	_check(not View.valid_board_sequence(parts.slice(0, 1), Registry.RELAY), "half a run is not a leaderboard run")
	_check(not View.valid_board_sequence(parts, Registry.LIGHTHOUSE_V2), "a run of another chapter is refused")
	_check(LeaderboardReplay.parts(answer, BOARD, ENTRY, "0".repeat(64), Registry.RELAY).is_empty(), "a replay other than the row's is refused")
	_check(LeaderboardReplay.parts(answer, BOARD, OTHER, hash, Registry.RELAY).is_empty(), "a replay of another run is refused")
	_check(LeaderboardReplay.parts(answer, BOARD, ENTRY, hash, Registry.LIGHTHOUSE_V2).is_empty(), "a checkpoint of another chapter is refused")
	var cut := answer.duplicate()
	cut.body = Marshalls.raw_to_base64(Marshalls.base64_to_raw(answer.body).slice(0, 40))
	_check(LeaderboardReplay.parts(cut, BOARD, ENTRY, hash, Registry.RELAY).is_empty(), "a cut off body is refused")
	var longer := answer.duplicate()
	longer.byte_length = int(answer.byte_length) + 1
	_check(LeaderboardReplay.parts(longer, BOARD, ENTRY, hash, Registry.RELAY).is_empty(), "a body of another length is refused")
	var later := answer.duplicate()
	later.added_later = true
	_check(LeaderboardReplay.parts(later, BOARD, ENTRY, hash, Registry.RELAY).size() == 2, "a field a later server adds is ignored")
	var missing := answer.duplicate()
	missing.erase("digest")
	_check(LeaderboardReplay.parts(missing, BOARD, ENTRY, hash, Registry.RELAY).is_empty(), "an answer without its hash is refused")
	var view := {"schema_version": 1, "board": BOARD, "checking": [], "top": [{"rank": 1, "entry_id": ENTRY, "ticks": 588, "finished_on": "2026-10-20", "names": null, "gold_leaf": true, "replay_hash": "A".repeat(64)}]}
	_check(Client.valid_view(view, BOARD).is_empty(), "a replay hash must be lowercase hex")
	view.top[0].erase("replay_hash")
	_check(Client.valid_view(view, BOARD).top[0].replay_hash == null, "a server before replays shows no Watch")

func _watch(answer: Dictionary) -> void:
	var api := FakeApi.new()
	root.add_child(api)
	api.replies["GET /v1/leaderboards/me"] = {"ok": true, "data": {"schema_version": 1, "show_name": false}}
	api.replies["GET /v1/leaderboards/" + BOARD] = {"ok": true, "data": {"schema_version": 1, "board": BOARD, "checking": [], "top": [
		{"rank": 1, "entry_id": ENTRY, "ticks": 588, "finished_on": "2026-10-20", "names": null, "gold_leaf": true, "replay_hash": answer.digest},
		{"rank": 2, "entry_id": OTHER, "ticks": 600, "finished_on": "2026-10-21", "names": null, "gold_leaf": false, "replay_hash": null}]}}
	api.replies["GET /v1/leaderboards/%s/replay/%s" % [BOARD, ENTRY]] = {"ok": true, "data": answer}
	var host := FakeHost.new()
	host.api = api
	root.add_child(host)
	var friends := FakeFriends.new()
	root.add_child(friends)
	var flow := FriendsFlow.new(host)
	flow.screen = friends
	var board := Screen.new()
	board.client = Client.new(api, OWNER, CHOICE_PATH)
	board.player_id = OWNER
	board.chapter_filter = func(key: String) -> bool: return key == Registry.RELAY
	var notices: Array = []
	board.notice.connect(func(text: String, _news: bool) -> void: notices.append(text))
	# As friends_flow._open_leaderboards wires a board it opens.
	board.watch_requested.connect(func(parts: Array, chapter_key: String) -> void: flow._watch_replay(board, parts, chapter_key))
	friends.add_child(board)
	for frame in range(10): await process_frame
	var first: Node = board.find_child("LeaderboardRow1", true, false)
	var second: Node = board.find_child("LeaderboardRow2", true, false)
	var watch: Button = first.find_child("LeaderboardWatch", true, false) if first != null else null
	_check(watch != null and watch.text == PlayerCopy.LEADERBOARD_WATCH, "a run with a kept replay shows Watch")
	_check(second != null and second.find_child("LeaderboardWatch", true, false) == null, "a run without one shows no Watch")
	if watch == null: return
	watch.pressed.emit()
	watch.pressed.emit()
	var deadline := Time.get_ticks_msec() + 20000
	while not is_instance_valid(host.shared_replay_child) and Time.get_ticks_msec() < deadline: await process_frame
	var replay_reads := api.requests.filter(func(item: Array) -> bool: return str(item[1]).contains("/replay/"))
	_check(replay_reads.size() == 1, "the first tap fetches the replay once; a second tap while it loads waits: %s" % [replay_reads])
	_check(notices.has(PlayerCopy.LEADERBOARD_WATCH_LOADING) and not notices.has(PlayerCopy.LEADERBOARD_REPLAY_FAILED), "the tap says the run is loading: %s" % [notices])
	var view: Node = host.shared_replay_child
	_check(view is View and view.leaderboard_chapter == Registry.RELAY and view.sequence.size() == 2 and view.get_parent() == host, "Watch opens the shared replay viewer in its leaderboard mode")
	_check(not board.visible and not friends.visible and not host.world_visible and host.soundscape.backgrounded, "the board, Friends and Home hide while the run plays")
	if not view is View: return
	while view.mode in ["loading", "preparing"] and Time.get_ticks_msec() < deadline: await process_frame
	_check(view.mode == "replay" and view.running and view._photos == null and not is_instance_valid(view.strip), "the run plays, with no photos: %s" % view.mode)
	_check(view.controls.chapter_label.text.begins_with("LEADERBOARD RUN"), "the viewer says it is a leaderboard run: %s" % view.controls.chapter_label.text)
	board.go_back()
	await process_frame
	_check(is_instance_valid(board) and not board.is_queued_for_deletion(), "Back while the run plays never closes the board beneath it")
	view._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(view.mode == "paused" and not _buttons(view).has("Report or block player"), "Back pauses the run, with no Report or block for a leaderboard run: %s" % [_buttons(view)])
	view._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(host.shared_replay_child == null and (not is_instance_valid(view) or view.is_queued_for_deletion()), "Back again leaves the replay")
	_check(board.visible and friends.visible and host.world_visible and not host.soundscape.backgrounded, "Back returns to the board as it was")
	_check(board.find_child("LeaderboardRow1", true, false) != null, "the board still shows its runs")
	api.replies["GET /v1/leaderboards/%s/replay/%s" % [BOARD, ENTRY]] = {"ok": false, "code": "replay_not_found"}
	notices.clear()
	(board.find_child("LeaderboardRow1", true, false).find_child("LeaderboardWatch", true, false) as Button).pressed.emit()
	for frame in range(10): await process_frame
	_check(notices.has(PlayerCopy.LEADERBOARD_REPLAY_FAILED) and host.shared_replay_child == null and board.visible, "a replay the server no longer keeps says so and stays on the board: %s" % [notices])
	# Friends closing (an account change, a room opening) takes a replay it opened with it.
	api.replies["GET /v1/leaderboards/%s/replay/%s" % [BOARD, ENTRY]] = {"ok": true, "data": answer}
	(board.find_child("LeaderboardRow1", true, false).find_child("LeaderboardWatch", true, false) as Button).pressed.emit()
	deadline = Time.get_ticks_msec() + 20000
	while not is_instance_valid(host.shared_replay_child) and Time.get_ticks_msec() < deadline: await process_frame
	var again: Node = host.shared_replay_child
	_check(again is View, "Watch opens the run again")
	flow.close()
	await process_frame
	_check(host.shared_replay_child == null and not is_instance_valid(again) and host.world_visible and not host.soundscape.backgrounded, "closing Friends closes its replay and brings Home back")
	for node: Node in [host, api]: node.queue_free()
	flow.free()
	await process_frame

func _buttons(node: Node) -> Array:
	var result: Array = []
	for button: Node in node.find_children("*", "Button", true, false): if button.is_visible_in_tree(): result.append(button.text)
	return result
