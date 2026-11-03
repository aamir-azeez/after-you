extends SceneTree
## Chapter times on Google Play Games and Game Center (services/platform_games/platform_boards.gd
## and the service around it): the one config of board ids against the offered chapters, the time
## units at tick edges, which runs go up and when (slower than tenth at once, a run that could
## place only once ranked, never once dropped, nothing without a read), the best only per account,
## the name switch, the server switch, the kept file, the native provider's checks and the
## leaderboard screen's button. Headless; every file is the test's own.
const Service = preload("res://services/platform_games/platform_games.gd")
const GamesProvider = preload("res://services/platform_games/games_provider.gd")
const NativeProvider = preload("res://services/platform_games/native_games_provider.gd")
const Ids = preload("res://services/platform_games/platform_board_ids.gd")
const Policy = preload("res://services/platform_games/platform_boards.gd")
const Store = preload("res://services/platform_games/platform_board_store.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const BoardStatus = preload("res://services/board_status.gd")
const Registry = preload("res://services/chapter_registry.gd")
const LeaderboardClient = preload("res://services/leaderboard_client.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const Button_ = preload("res://presentation/platform_board_button.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const OWNER := "o_synthetic_player_00a"
const KEY_A := "a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0"
const KEY_B := "b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"
const RELAY := "relay-isles@2"

class FakeProvider extends "res://services/platform_games/games_provider.gd":
	var platform := GAME_CENTER
	var posts: Array = []
	var shows: Array = []
	var answer: Dictionary = {"ok": true}
	var hold_show := false
	signal release
	func kind() -> String: return platform
	func available() -> bool: return true
	func authenticate(_interactive: bool) -> Dictionary: return {"ok": true, "signed_in": true, "player_key": "a".repeat(64)}
	func submit_score(board: String, score: int) -> Dictionary:
		posts.append([board, score])
		await Engine.get_main_loop().process_frame
		return answer.duplicate()
	func show_board(board: String) -> Dictionary:
		shows.append(board)
		if hold_show: await release
		await Engine.get_main_loop().process_frame
		return {"ok": true}

class FakeAccount extends RefCounted:
	var player := OWNER
	func api() -> Node: return null
	func identity_state() -> String: return "ready"
	func player_id() -> String: return player
	func cloud_sources() -> RefCounted: return null

## Main's api as the leaderboard client uses it: one board read, answered with `view`.
class FakeApi extends Node:
	var view: Dictionary = {}
	func request_json(_method: int, _path: String, _body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		await Engine.get_main_loop().process_frame
		return {"ok": true, "status": 200, "data": view}

class FakeNative extends Object:
	signal games_result(request_id: String, operation: String, payload_json: String)
	signal games_error(request_id: String, operation: String, code: String)
	signal games_account_changed(payload_json: String)
	var calls: Array = []
	func games_available() -> bool: return true
	func games_submit_score(board: String, score: int, request_id: String) -> void:
		calls.append(["submit_score", board, score])
		games_result.emit.call_deferred(request_id, "submit_score", JSON.stringify({"submitted": true}))
	func games_show_board(board: String, request_id: String) -> void:
		calls.append(["show_board", board])
		games_error.emit.call_deferred(request_id, "show_board", "Some platform text")

var checks := 0
var failures := 0
var _dir := ""
var _serial := 0

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _entry() -> String:
	_serial += 1
	return ("synthetic entry %d" % _serial).sha256_text().left(32)

func _run_of(ticks: int, board: String = RELAY, finished: String = "2026-11-01T10:00:00Z", assisted: bool = false) -> Dictionary:
	return {"board": board, "entry_id": _entry(), "ticks": ticks, "assisted": assisted, "finished_at": finished, "partner": "", "refused": ""}

## A board as services/leaderboard_client.gd kept_for hands it over: the view and when it was read.
func _read(view: Dictionary, read_unix: float) -> Dictionary:
	return {"view": view, "read_unix": read_unix}

func _view(board: String, times: Array, checking: Array = []) -> Dictionary:
	var top: Array = []
	for index in range(times.size()):
		var row: Variant = times[index]
		var id: String = row.entry_id if row is Dictionary else ("listed %s %d" % [board, index]).sha256_text().left(32)
		top.append({"rank": index + 1, "entry_id": id, "ticks": int(row.ticks) if row is Dictionary else int(row), "names": null, "gold_leaf": false, "finished_on": "", "replay_hash": null, "looks": []})
	return {"board": board, "top": top, "checking": checking}

func _run() -> void:
	_dir = "user://platform-boards-test-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_ids()
	_units()
	_judging()
	_store()
	await _native()
	await _service()
	await _button()
	print("PLATFORM BOARDS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## One config place, matching the chapters offered: one board per offered chapter version.
func _ids() -> void:
	var offered: Array = []
	for key: String in Registry.offered_keys(): offered.append(Runs.board_key(key))
	offered.sort()
	var configured: Array = Ids.BOARDS.keys()
	configured.sort()
	_check(configured == offered, "Every offered chapter version has one row of platform ids, and no other row: %s" % [configured])
	var seen := {}
	var shape := RegEx.create_from_string("^afteryou\\.[a-z_]+\\.v[0-9]+$")
	for board: String in Ids.BOARDS:
		var id := Ids.id(board, GamesProvider.GAME_CENTER)
		_check(shape.search(id) != null and not seen.has(id), "Game Center ids are unique and use letters, digits, dots and underscores: %s" % id)
		_check(id.ends_with(".v" + board.get_slice("@", 1)), "A Game Center id names its chapter version: %s" % id)
		seen[id] = true
		var play := Ids.id(board, GamesProvider.PLAY_GAMES)
		_check(play.is_empty() or RegEx.create_from_string(NativeProvider.BOARD_ID).search(play) != null, "A Play Games id has the shape the plugin takes")
	_check(Ids.boards(GamesProvider.GAME_CENTER).size() == 10 and Ids.id("unknown@1", GamesProvider.GAME_CENTER).is_empty() and Ids.id(RELAY, GamesProvider.NONE).is_empty(), "Unknown boards and platforms have no id")

## Hundredths cut down like our tenths; Play Games gets them times 10.
func _units() -> void:
	_check(Policy.hundredths(6661) == 22203 and Policy.score(GamesProvider.GAME_CENTER, 22203) == 22203 and Policy.score(GamesProvider.PLAY_GAMES, 22203) == 222030, "6661 ticks post 22203 hundredths on Game Center and 222030 ms on Play Games")
	_check([Policy.hundredths(1), Policy.hundredths(2), Policy.hundredths(3), Policy.hundredths(29), Policy.hundredths(30), Policy.hundredths(0), Policy.hundredths(-4)] == [3, 6, 10, 96, 100, 0, 0], "Tick edges round down")
	for ticks: int in [1, 29, 30, 6661, 5939, 17999]:
		var ours := Runs.time_text(ticks)
		var time := Policy.hundredths(ticks)
		var theirs := "%d:%02d.%02d" % [time / 6000, (time / 100) % 60, time % 100]
		_check(theirs.begins_with(ours), "The platform time starts with ours: %s and %s" % [ours, theirs])

## Which runs go up, and when.
func _judging() -> void:
	var now := Time.get_unix_time_from_datetime_string("2026-11-01T12:00:00")
	var full := _view(RELAY, [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000])
	var slow := _run_of(1000)
	var fast := _run_of(950)
	var assisted := _run_of(5000, RELAY, "2026-11-01T10:00:00Z", true)
	var other := _run_of(2000, "first-steps@1")
	var runs := [slow, fast, assisted, other]
	var first := Policy.judge(runs, {RELAY: _read(full, now)}, {})
	_check(first.get(slow.entry_id) == Policy.GO, "A run as slow as tenth place on a full board goes at once")
	_check(not first.has(assisted.entry_id), "An assisted run never goes")
	_check(not first.has(other.entry_id), "A run whose board this phone has not read waits for a read, with no verdict kept")
	_check(first.get(fast.entry_id) == Policy.NEVER, "A faster run the read lists nowhere, long after it finished, was dropped by our board")
	# A run still checking waits; ranked, it goes; settled off the board, never.
	var waiting := _run_of(450, RELAY, "2026-11-01T11:58:00Z")
	var listed := _view(RELAY, [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000], [waiting.entry_id])
	var verdicts := Policy.judge([waiting], {RELAY: _read(listed, now)}, {})
	_check(verdicts.get(waiting.entry_id) == Policy.WAIT, "A run listed as checking waits")
	_check(Policy.judge([waiting], {}, verdicts).get(waiting.entry_id) == Policy.WAIT, "A waiting run keeps waiting with no read")
	var ranked := _view(RELAY, [100, 200, 300, 400, waiting, 600, 700, 800, 900, 1000])
	_check(Policy.judge([waiting], {RELAY: _read(ranked, now)}, verdicts).get(waiting.entry_id) == Policy.GO, "Once a read shows it ranked it goes")
	_check(Policy.judge([waiting], {RELAY: _read(full, now + 3600)}, verdicts).get(waiting.entry_id) == Policy.NEVER, "Settled off the board after the settle window, it never goes")
	_check(Policy.judge([waiting], {RELAY: _read(full, now)}, verdicts).get(waiting.entry_id) == Policy.WAIT, "Within the settle window a run the read lists nowhere still waits")
	# A read made before the run finished says nothing about it, however late the pass runs.
	var early := _run_of(450, RELAY, "2026-11-01T11:59:00Z")
	_check(Policy.judge([early], {RELAY: _read(_view(RELAY, [100, 200]), now - 3600)}, {}).get(early.entry_id) == Policy.WAIT, "A board read before the run finished keeps it waiting, never dropped")
	_check(Policy.judge([early], {RELAY: _read(full, now - 3600)}, {}).get(early.entry_id) == Policy.WAIT and BoardStatus.below_tenth(slow, full) and not BoardStatus.below_tenth(early, full), "Faster than tenth on an old read still waits; the tenth place rule is board_status.gd's")
	# A board with fewer than ten runs: anything could place, so it waits.
	var short := _view(RELAY, [100, 200])
	var recent := _run_of(9000, RELAY, "2026-11-01T11:59:00Z")
	_check(Policy.judge([recent], {RELAY: _read(short, now)}, {}).get(recent.entry_id) == Policy.WAIT, "On a board with fewer than ten runs even a slow run waits for its check")
	# A run listed in the top 10 is never judged by its time alone.
	var ten := _view(RELAY, [100, 200, 300, 400, 500, 600, 700, 800, 900, slow])
	_check(Policy.judge([slow], {RELAY: _read(ten, now)}, {}).get(slow.entry_id) == Policy.GO, "A run ranked tenth goes")
	# Verdicts once GO or NEVER stay, whatever a later read says.
	_check(Policy.judge([slow, fast], {RELAY: _read(short, now)}, first) == {slow.entry_id: Policy.GO, fast.entry_id: Policy.NEVER}, "GO and NEVER are final")
	# Best only, per board, and only when it beats what this account posted.
	var faster_go := _run_of(1500)
	var go := {slow.entry_id: Policy.GO, faster_go.entry_id: Policy.GO, fast.entry_id: Policy.NEVER, other.entry_id: Policy.GO}
	var boards := [RELAY, "first-steps@1"]
	_check(Policy.due([slow, faster_go, fast, other], go, boards, {}) == {RELAY: Policy.hundredths(1000), "first-steps@1": Policy.hundredths(2000)}, "The fastest GO run of each board is due")
	_check(Policy.due([slow, faster_go, other], go, boards, {RELAY: Policy.hundredths(1000)}) == {"first-steps@1": Policy.hundredths(2000)}, "A time no better than the one posted is not due again")
	_check(Policy.due([slow, other], go, [RELAY], {RELAY: Policy.hundredths(1200)}) == {RELAY: Policy.hundredths(1000)}, "A new best is due; a board the platform lacks is not")

func _store() -> void:
	var path := _dir.path_join("store.json")
	var store := Store.new(path)
	_check(store.judged.is_empty() and store.posted.is_empty(), "No file, nothing kept")
	var id := _entry()
	_check(store.keep_verdicts({id: Policy.WAIT}) and store.remember_posted(Store.account(GamesProvider.GAME_CENTER, KEY_A), RELAY, 3300), "Verdicts and posts are kept")
	var again := Store.new(path)
	_check(again.judged == {id: Policy.WAIT} and again.posted_for(Store.account(GamesProvider.GAME_CENTER, KEY_A)) == {RELAY: 3300} and again.posted_for(Store.account(GamesProvider.GAME_CENTER, KEY_B)).is_empty(), "They read back, per account")
	var text := FileAccess.get_file_as_string(path)
	_check(not text.contains(OWNER), "The file names no player")
	AtomicFile.write_text(path, JSON.stringify({"schema_version": 1, "judged": {"not an id": "go", id: "maybe"}, "posted": {"someone": {RELAY: 1}, Store.account(GamesProvider.PLAY_GAMES, KEY_B): {RELAY: -3, "first-steps@1": 400}}}))
	var cleaned := Store.new(path)
	_check(cleaned.judged.is_empty() and cleaned.posted == {Store.account(GamesProvider.PLAY_GAMES, KEY_B): {"first-steps@1": 400}}, "Only well formed entries are read")
	AtomicFile.write_text(path, "{not json")
	_check(Store.new(path).judged.is_empty(), "A damaged file reads as empty")
	var kept := _dir.path_join("kept.json")
	var holder := Store.new(kept)
	holder.keep_verdicts({_entry(): Policy.GO})
	holder.remember_posted(Store.account(GamesProvider.GAME_CENTER, KEY_A), RELAY, 900)
	_check(Store.forget_verdicts(kept) and Store.new(kept).judged.is_empty() and Store.new(kept).posted_for(Store.account(GamesProvider.GAME_CENTER, KEY_A)) == {RELAY: 900}, "Erasure forgets every verdict and keeps the platform bests")
	_check(Store.forget_verdicts(_dir.path_join("never-written.json")), "Erasure with no file is done")
	var many := Store.new(_dir.path_join("many.json"))
	var verdicts := {}
	for index in range(Store.MAX_JUDGED + 20): verdicts[_entry()] = Policy.GO
	many.keep_verdicts(verdicts)
	_check(Store.new(_dir.path_join("many.json")).judged.size() == Store.MAX_JUDGED, "The newest verdicts are kept, up to the limit")

## The native provider checks before it asks the plugin, and lets no platform text through.
func _native() -> void:
	var native := FakeNative.new()
	var provider := NativeProvider.new(native, GamesProvider.GAME_CENTER, self)
	_check("submit_score" in NativeProvider.OPERATIONS and "show_board" in NativeProvider.OPERATIONS, "Both calls are native operations")
	_check((await provider.submit_score("afteryou.relay_isles.v2", 3300)).ok and native.calls[-1] == ["submit_score", "afteryou.relay_isles.v2", 3300], "A post reaches the plugin with the platform id and score")
	var before := native.calls.size()
	_check((await provider.submit_score("bad id!", 3300)).code == "failed" and (await provider.submit_score("afteryou.relay_isles.v2", 0)).code == "failed" and native.calls.size() == before, "A bad id or score never reaches the plugin")
	var shown: Dictionary = await provider.show_board("afteryou.relay_isles.v2")
	_check(shown == {"ok": false, "code": "failed"}, "Platform text in an error becomes 'failed'")
	native.free()

func _service_with(provider: RefCounted, name: String, boards: bool = true) -> Node:
	var service: Node = Service.new()
	service.configure(provider, _dir.path_join(name + ".json"))
	root.add_child(service)
	service.attach(FakeAccount.new())
	service.state.remember_capability({"play_games": provider.kind() == GamesProvider.PLAY_GAMES, "game_center": provider.kind() == GamesProvider.GAME_CENTER, "boards": boards, "web_client_id": ""})
	service.sign_in = Service.SignIn.SIGNED_IN
	service.set("_player_key", KEY_A)
	return service

## The player's "Show my name on leaderboards", as the shared client holds it.
func _choose_name(client: RefCounted, show: bool) -> void:
	client._choice = {"show": show, "pending": false, "synced": true}

func _service() -> void:
	Runs.use_path(_dir.path_join("runs.json"))
	var api := FakeApi.new()
	root.add_child(api)
	var client: RefCounted = LeaderboardClient.shared(api, OWNER)
	var slow_ticks := 1500
	var full := _view(RELAY, [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000])
	client._views[RELAY] = {"at": Time.get_ticks_msec(), "unix": Time.get_unix_time_from_system(), "view": full}
	# The run list keeps only rooms with a real final checkpoint; the test puts its run in directly.
	var run := _run_of(slow_ticks)
	Runs._data[OWNER] = [run]
	Runs._loaded = true
	_check(Runs.runs_of(OWNER).size() == 1, "The test's run is this player's")
	# Without a shared client of this player, the name choice comes from the phone's file.
	var choices := _dir.path_join("names.json")
	AtomicFile.write_text(choices, JSON.stringify({OWNER: {"show": true, "pending": false, "synced": true}, "x_synthetic_player_00c": {"show": false, "pending": false, "synced": true}}))
	_check(LeaderboardClient.name_shown(OWNER, choices) and not LeaderboardClient.name_shown("x_synthetic_player_00c", choices) and not LeaderboardClient.name_shown("", choices), "The name choice reads from the file when no client holds it")
	_check(LeaderboardClient.kept_for("x_synthetic_player_00c").is_empty() and LeaderboardClient.kept_for(OWNER).get(RELAY, {}).get("view") == full, "Kept boards come only from this player's client, and asking makes none")

	# Name hidden: judged and kept, nothing posted.
	_choose_name(client, false)
	var provider := FakeProvider.new()
	var service := _service_with(provider, "names")
	_check(service.boards_offered() and service.board_offered(RELAY), "The boards are offered while the server says so")
	await service.post_boards()
	_check(provider.posts.is_empty(), "Nothing goes up while the player hides their name")
	_check(Store.new(_dir.path_join("names-boards.json")).judged.get(run.entry_id) == Policy.GO, "The verdict is kept anyway")
	# Turning the name on posts the best once; a second pass posts nothing.
	_choose_name(client, true)
	await service.post_boards()
	_check(provider.posts == [["afteryou.relay_isles.v2", Policy.hundredths(slow_ticks)]], "The best goes up once, in hundredths, on the Game Center id: %s" % [provider.posts])
	await service.post_boards()
	_check(provider.posts.size() == 1, "The same best never goes again")
	# Another account on this phone posts its own best.
	service.set("_player_key", KEY_B)
	await service.post_boards()
	_check(provider.posts.size() == 2, "Another platform account posts the best again")
	# A failure is not remembered, and stops the pass.
	var failing := FakeProvider.new()
	failing.answer = {"ok": false, "code": "offline"}
	var offline := _service_with(failing, "offline")
	await offline.post_boards()
	await offline.post_boards()
	_check(failing.posts.size() == 2 and Store.new(_dir.path_join("offline-boards.json")).posted.is_empty(), "An offline post is tried again at the next moment")
	# Server switch off, signed out, Play Games without ids: nothing posts.
	var off_provider := FakeProvider.new()
	var off := _service_with(off_provider, "off", false)
	await off.post_boards()
	var signed_out_provider := FakeProvider.new()
	var signed_out := _service_with(signed_out_provider, "signed-out")
	signed_out.sign_in = Service.SignIn.SIGNED_OUT
	await signed_out.post_boards()
	var play := FakeProvider.new()
	play.platform = GamesProvider.PLAY_GAMES
	var android := _service_with(play, "android")
	await android.post_boards()
	_check(off_provider.posts.is_empty() and signed_out_provider.posts.is_empty() and not off.board_offered(RELAY), "Off or signed out: nothing goes up and no button shows")
	_check(android.board_offered(RELAY) and not play.posts.is_empty() and play.posts.all(func(post: Array) -> bool: return str(post[0]).begins_with("CgkI")), "Play Games posts to its own board ids: %s" % [play.posts])
	_check(Service.LEADERBOARD_LISTENERS == LeaderboardClient.LISTENERS, "The service listens on the group the leaderboard client tells")
	# A run that could place waits; the board read that shows it ranked (the end card's, Home's or
	# the board screen's, all through the shared client) is what posts it, a moment later.
	var waiting := _run_of(450, RELAY, Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - 60) + "Z")
	Runs._data[OWNER] = [run, waiting]
	var checking := _view(RELAY, [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000], [waiting.entry_id])
	client._views[RELAY] = {"at": Time.get_ticks_msec(), "unix": Time.get_unix_time_from_system(), "view": checking}
	await service.post_boards()
	_check(provider.posts.size() == 2, "A run still being checked does not go up")
	var ranked := _view(RELAY, [100, 200, 300, 400, waiting, 600, 700, 800, 900, 1000])
	ranked.schema_version = 1
	api.view = ranked
	_check((await client.board(RELAY, true)).ok, "The board read answers")
	await create_timer(Service.BOARD_POST_DELAY_S + 0.5).timeout
	_check(provider.posts.size() == 3 and provider.posts[-1] == ["afteryou.relay_isles.v2", Policy.hundredths(450)], "The read that shows it ranked posts it, with no request of its own: %s" % [provider.posts])
	for node: Node in [service, offline, off, signed_out, android, api]: node.queue_free()
	LeaderboardClient._shared = null

func _button() -> void:
	var provider := FakeProvider.new()
	var service := _service_with(provider, "button")
	var notices: Array = []
	var button: Button = Button_.new(service, func(text: String) -> void: notices.append(text))
	root.add_child(button)
	button.show_for(RELAY)
	_check(button.visible and button.text == PlayerCopy.PLATFORM_GAMES_GAME_CENTER, "The button shows Game Center for a board Game Center has")
	button.show_for("unknown@1")
	_check(not button.visible, "No button for a board the platform lacks")
	button.show_for(RELAY)
	provider.hold_show = true
	button.pressed.emit()
	await process_frame
	button.pressed.emit()
	await process_frame
	_check(provider.shows == ["afteryou.relay_isles.v2"] and service.board_showing(), "A tap opens the platform's board, once while it opens")
	provider.release.emit()
	for frame in range(3): await process_frame
	_check(service.board_showing(), "Another tap waits a moment after it opened")
	var told := [0]
	service.changed.connect(func() -> void: told[0] += 1)
	await create_timer(Service.BOARD_SHOW_GAP_MS / 1000.0 + 0.2).timeout
	_check(not service.board_showing() and told[0] >= 1, "When the gap is over the service tells the button again, so it is live")
	service.state.remember_capability({"game_center": true, "boards": false, "web_client_id": ""})
	service.changed.emit()
	_check(not button.visible, "The server switching the boards off hides the button at the next change")
	var desktop: Button = Button_.new(null)
	root.add_child(desktop)
	desktop.show_for(RELAY)
	_check(not desktop.visible, "No service (desktop): no button")
	for node: Node in [button, desktop, service]: node.queue_free()
