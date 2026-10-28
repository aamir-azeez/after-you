extends SceneTree
## Leaderboard celebrations: services/leaderboard_placings.gd (which of this
## player's runs a board confirmed in its top 10, shown once each, never one
## still being checked), presentation/leaderboard_celebration.gd (the four
## tiers, their timing, Reduce motion, the gold spread on first place, one 3D
## view made once), and the board screen's restyled states and the board and
## Home showing a celebration. Every request goes to a fake transport.
const Runs = preload("res://services/leaderboard_runs.gd")
const Placings = preload("res://services/leaderboard_placings.gd")
const Client = preload("res://services/leaderboard_client.gd")
const TurnLooks = preload("res://services/turn_looks.gd")
const Outfit = preload("res://services/outfit.gd")
const Screen = preload("res://presentation/leaderboard_screen.gd")
const Rows = preload("res://presentation/leaderboard_rows.gd")
const Celebration = preload("res://presentation/leaderboard_celebration.gd")
const GoldLeaf = preload("res://presentation/pip_wear/gold_leaf.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const OWNER := "OOOOOOOOOOOOOOOOOOOOOO"
const PARTNER := "GGGGGGGGGGGGGGGGGGGGGG"
const BOARD := "sleeping-lighthouse@2"
const RUNS_PATH := "user://celebration-runs-test.json"
const PLACINGS_PATH := "user://celebration-placings-test.json"
const LOOKS_PATH := "user://celebration-looks-test.json"
const CHOICE_PATH := "user://celebration-name-test.json"
const SAVE_PATH := "user://celebration-save-test.json"
## This player's runs on the board: two ranked or ranking, one still checked, one with Forgiving catches.
const MINE := "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"
const SECOND := "a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2"
const NEWEST := "a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3"
const ASSISTED := "a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4"
const HASH := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

var checks := 0
var failures := 0
var _parent: Control
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

class FakeSession extends RefCounted:
	var open := true
	func leaderboards_supported() -> bool: return open

## Friends' page, as far as its flow opens a page over it.
class FakeFriends extends CanvasLayer:
	var overlay: CanvasLayer
	func open_overlay(page: CanvasLayer) -> void:
		overlay = page
		add_child(page)
	func close() -> void: queue_free()

func _run() -> void:
	for path: String in [RUNS_PATH, PLACINGS_PATH, LOOKS_PATH, CHOICE_PATH, SAVE_PATH]: _clear(path)
	_write_runs()
	TurnLooks.use_shared(TurnLooks.new(LOOKS_PATH))
	_placings()
	await _client_learns()
	_parent = Control.new()
	_parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_parent)
	Engine.time_scale = 4.0
	await _tiers()
	await _reduced()
	await _gold()
	Engine.time_scale = 1.0
	await _reduced_fade()
	await _show_once()
	await _screen()
	await _home()
	Placings.use_shared(null)
	TurnLooks.use_shared(null)
	for path: String in [RUNS_PATH, PLACINGS_PATH, LOOKS_PATH, CHOICE_PATH, SAVE_PATH]: _clear(path)
	print("Leaderboard celebration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _clear(path: String) -> void:
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _write_runs() -> void:
	var runs := [
		{"board": BOARD, "entry_id": MINE, "ticks": 6300, "assisted": false, "finished_at": "2026-10-20T10:00:00Z", "partner": PARTNER},
		{"board": BOARD, "entry_id": SECOND, "ticks": 6400, "assisted": false, "finished_at": "2026-10-21T10:00:00Z", "partner": ""},
		{"board": BOARD, "entry_id": NEWEST, "ticks": 6000, "assisted": false, "finished_at": "2026-10-22T10:00:00Z", "partner": PARTNER},
		{"board": BOARD, "entry_id": ASSISTED, "ticks": 5000, "assisted": true, "finished_at": "2026-10-19T10:00:00Z"}]
	var file := FileAccess.open(RUNS_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 1, "players": {OWNER: runs}}))
	file.close()
	Runs.use_path(RUNS_PATH)

static func _row(rank: int, entry: String, ticks: int, names: Variant = null, gold: bool = false, replay: Variant = HASH) -> Dictionary:
	return {"rank": rank, "entry_id": entry, "ticks": ticks, "finished_on": "2026-10-20", "names": names, "gold_leaf": gold, "replay_hash": replay}

static func _view(top: Array, checking: Array = []) -> Dictionary:
	return {"board": BOARD, "top": top, "checking": checking}

static func _others(count: int, from: int = 1) -> Array:
	var rows: Array = []
	for index in range(count): rows.append(_row(from + index, ("%02d" % (from + index)).repeat(16), 6000 + 30 * (from + index), ["Ada", "Bo"] if index % 2 == 0 else null, from + index == 1))
	return rows

func _placings() -> void:
	_check(Placings.tier(1) == Placings.FIRST and Placings.tier(2) == Placings.SECOND and Placings.tier(3) == Placings.THIRD and Placings.tier(4) == Placings.TOP_TEN and Placings.tier(10) == Placings.TOP_TEN, "places 1, 2, 3 and 4 to 10 are the four tiers")
	_check(Placings.tier(0).is_empty() and Placings.tier(11).is_empty(), "nothing outside the top 10 is celebrated")
	_check(Runs.on_board(OWNER, BOARD)[0].get("partner") == "" and Runs.on_board(OWNER, BOARD).any(func(run: Dictionary) -> bool: return run.partner == PARTNER), "a kept run reads back its partner, and an older one without it reads none")
	_check(Runs.chapter_of(BOARD) == Registry.LIGHTHOUSE_V2 and Runs.chapter_of("nowhere@1").is_empty(), "a board names its chapter")
	var store: RefCounted = Placings.new(PLACINGS_PATH)
	_check(not store.learn(OWNER, BOARD, _view(_others(3), [NEWEST])) and store.next(OWNER).is_empty(), "other pairs' runs and a run being checked are never a placing")
	_check(not store.learn(OWNER, BOARD, _view([_row(1, NEWEST, 6000)], [NEWEST])), "a run both listed and still checked is never celebrated")
	_check(not store.learn(OWNER, BOARD, _view([_row(1, ASSISTED, 5000)])), "a run with Forgiving catches is never celebrated")
	_check(not store.learn("", BOARD, _view([_row(2, MINE, 6300)])) and not store.learn(OWNER, BOARD, {}), "no player or no board learns nothing")
	_check(store.learn(OWNER, BOARD, _view(_others(1) + [_row(2, MINE, 6300, ["Ada", "Bo"])])), "this player's ranked run is a placing")
	var waiting: Dictionary = store.next(OWNER)
	_check(waiting.entry_id == MINE and waiting.rank == 2 and waiting.ticks == 6300 and waiting.board == BOARD and waiting.names == ["Ada", "Bo"] and waiting.partner == PARTNER, "the placing keeps what its card shows: %s" % [waiting])
	_check(store.learn(OWNER, BOARD, _view([_row(1, MINE, 6300)])) and store.next(OWNER).rank == 1, "a placing waiting follows its board's newest read")
	_check(not store.learn(OWNER, BOARD, _view([_row(1, MINE, 6300)])), "the same read changes nothing")
	_check(store.learn(OWNER, BOARD, _view(_others(10))) and store.next(OWNER).is_empty(), "a placing its board no longer lists (pushed out or struck) is not celebrated")
	store.learn(OWNER, BOARD, _view([_row(4, MINE, 6300), _row(9, SECOND, 6400)]))
	store.mark_shown(OWNER, MINE)
	_check(store.was_shown(OWNER, MINE) and store.next(OWNER).entry_id == SECOND, "a shown placing goes; the next one waits")
	_check(not store.learn(OWNER, BOARD, _view([_row(1, MINE, 6300), _row(9, SECOND, 6400)])) and store.next(OWNER).entry_id == SECOND, "a run shown once is never celebrated again, even when it moves up")
	var again: RefCounted = Placings.new(PLACINGS_PATH)
	_check(again.was_shown(OWNER, MINE) and again.next(OWNER).entry_id == SECOND and again.has_pending(OWNER) and not again.has_pending("someone-else"), "shown and waiting placings survive a restart, per player")
	var bad := FileAccess.open(PLACINGS_PATH, FileAccess.WRITE)
	bad.store_string("{\"version\": 1, \"players\": {\"%s\": {\"shown\": [\"zz\"], \"pending\": [{\"entry_id\": \"%s\", \"board\": \"%s\", \"rank\": 40, \"ticks\": 1, \"names\": null, \"gold_leaf\": false, \"partner\": \"\"}]}}}" % [OWNER, MINE, BOARD])
	bad.close()
	var damaged: RefCounted = Placings.new(PLACINGS_PATH)
	_check(not damaged.has_pending(OWNER) and not damaged.was_shown(OWNER, "zz"), "a damaged file keeps only what checks out")
	_clear(PLACINGS_PATH)

func _client_learns() -> void:
	var store: RefCounted = Placings.new(PLACINGS_PATH)
	Placings.use_shared(store)
	var api := FakeApi.new()
	root.add_child(api)
	var data := {"schema_version": 1, "board": BOARD, "top": [_row(1, "f".repeat(32), 5000, null, true), _row(3, MINE, 6300)], "checking": [NEWEST]}
	api.replies["GET /v1/leaderboards/" + BOARD] = {"ok": true, "data": data}
	var client := Client.new(api, OWNER, CHOICE_PATH)
	var answer: Dictionary = await client.board(BOARD, true)
	_check(answer.ok and store.next(OWNER).entry_id == MINE and store.next(OWNER).rank == 3, "a board read tells the placings about this player's ranked run")
	api.queue_free()
	_clear(PLACINGS_PATH)
	Placings.use_shared(Placings.new(PLACINGS_PATH))

func _placing(rank: int, gold: bool = false, names: Variant = null) -> Dictionary:
	return {"entry_id": MINE, "board": BOARD, "rank": rank, "ticks": 6300, "names": names, "gold_leaf": gold, "partner": PARTNER}

func _nodes(node: Node) -> int:
	return node.find_children("*", "", true, false).size()

func _settle(made: Control) -> Array:
	var counts: Array = []
	var deadline := Time.get_ticks_msec() + 8000
	while is_instance_valid(made) and made.is_processing() and Time.get_ticks_msec() < deadline:
		await process_frame
		counts.append(_nodes(made))
	return counts

func _tiers() -> void:
	var expected := {7: [Placings.TOP_TEN, 1.0, PlayerCopy.LEADERBOARD_TOP_TEN_TITLE], 3: [Placings.THIRD, 1.6, PlayerCopy.LEADERBOARD_PLACE_TITLE % "3rd"], 2: [Placings.SECOND, 2.1, PlayerCopy.LEADERBOARD_PLACE_TITLE % "2nd"], 1: [Placings.FIRST, 2.8, PlayerCopy.LEADERBOARD_PLACE_TITLE % "1st"]}
	for rank: int in expected:
		var want: Array = expected[rank]
		var made: Control = Celebration.open(_parent, _placing(rank, rank == 1, ["Ada", "Bo"]), false)
		await process_frame
		_check(made.tier == want[0] and is_equal_approx(made.seconds(), want[1]), "place %d is the %s celebration, %.1f s" % [rank, want[0], want[1]])
		_check(_text(made, "CelebrationTitle") == want[2] and _text(made, "CelebrationChapter") == "Sleeping Lighthouse" and _text(made, "CelebrationTime") == Runs.time_text(6300) and _text(made, "CelebrationPair") == PlayerCopy.LEADERBOARD_NAMES % ["Ada", "Bo"], "its card names the place, chapter, pair and time: %s" % _text(made, "CelebrationTitle"))
		_check((made.find_child("CelebrationPlace", true, false) != null) == (rank == 7), "only Top 10 has the place pill")
		_check(made.find_children("*", "SubViewport", true, false).size() == 1, "one view holds the pair")
		var start := Celebration.pose(made.tier, 0.0)
		var final := Celebration.pose(made.tier, made.seconds())
		_check(Celebration.pose(made.tier, made.seconds() + 5.0) == final, "past its length it holds the final pose")
		match made.tier:
			Placings.TOP_TEN: _check(start.ribbon == 0.0 and final.ribbon == 1.0 and start.sparkles == 0.0 and final.sparkles == 1.0 and is_zero_approx(final.lift) and Celebration.pose(made.tier, 0.22).lift > 0.04, "Top 10: one bob, the ribbon settles, then the sparkles")
			Placings.THIRD: _check(start.mark == 0.0 and final.mark == 1.0 and is_equal_approx(final.bow, 0.0) and absf(final.leaves - 1.0) < 0.001 and Celebration.pose(made.tier, 0.75).bow > 0.1, "third: a bow, leaves that lift and fade, the mark settles")
			Placings.SECOND: _check(start.arch == 0.0 and final.arch == 1.0 and is_equal_approx(final.roll, 0.0) and Celebration.pose(made.tier, 1.1).roll > 0.1, "second: the arch draws, the pair lean in and back")
			Placings.FIRST: _check(start.gold == 0.0 and final.gold == 1.0 and is_equal_approx(Celebration.pose(made.tier, 1.0).gold, 0.5) and final.curves == 1.0 and is_zero_approx(final.glint) and Celebration.pose(made.tier, 1.55).glint > 0.9, "first: gold spreads over 0.8 s, one glint, the curves appear")
		var before := _nodes(made)
		var counts: Array = await _settle(made)
		_check(made.settled() and not made.is_processing(), "it settles into its final pose and stops")
		var changes := 0
		var last := before
		for count: int in counts:
			if count != last: changes += 1
			last = count
		_check(changes <= (1 if made.tier == Placings.FIRST else 0), "nothing is made frame by frame (first place dresses its leaves once): %d changes" % changes)
		var boards: Array = []
		made.view_board.connect(func(board: String) -> void: boards.append(board))
		(made.find_child("CelebrationViewBoard", true, false) as Button).pressed.emit()
		_check(boards == [BOARD] and made.is_queued_for_deletion(), "View board leaves it for the board")
		await process_frame
	var outside: Control = Celebration.open(_parent, _placing(11), false)
	_check(outside == null, "no celebration for a place outside the top 10")

func _reduced() -> void:
	var made: Control = Celebration.open(_parent, _placing(3), true)
	await process_frame
	_check(made.settled() and made._pose == Celebration.pose(made.tier, made.seconds()), "Reduce motion starts in the final pose")
	_check(made.modulate.a < 1.0, "and fades in")
	await _settle(made)
	made.go_back()
	_check(made.is_queued_for_deletion(), "Back leaves it")
	await process_frame
	var gold: Control = Celebration.open(_parent, _placing(1, true), true)
	await process_frame
	_check(gold._spirits.all(func(spirit: Node3D) -> bool: return spirit.sprout.material_override == GoldLeaf.material()), "Reduce motion shows the gold leaves already in place")
	gold.close()
	await process_frame

func _reduced_fade() -> void:
	var made: Control = Celebration.open(_parent, _placing(2), true)
	var started := Time.get_ticks_msec()
	await _settle(made)
	var took := (Time.get_ticks_msec() - started) / 1000.0
	_check(is_equal_approx(made.modulate.a, 1.0) and took >= 0.15 and took < 0.6 and made._pose == Celebration.pose(made.tier, made.seconds()), "Reduce motion is a fade of about 0.2 s into the final pose: %.2f s" % took)
	made.close()
	await process_frame

func _gold() -> void:
	Outfit.show_unreleased = true
	TurnLooks.shared().note_member(PARTNER, {"hat": "daisy"})
	var made: Control = Celebration.open(_parent, _placing(1, true), false)
	await process_frame
	_check(made._spirits[1].outfit() == {"hat": "daisy"}, "the partner's pip wears the look last heard for them: %s" % [made._spirits[1].outfit()])
	_check(made._spirits.all(func(spirit: Node3D) -> bool: return spirit.sprout.material_override is ShaderMaterial), "the leaves start as their own colour, ready to turn")
	while made.elapsed() < 1.0 and made.is_processing(): await process_frame
	var progress: float = (made._spirits[0].sprout.material_override as ShaderMaterial).get_shader_parameter("progress")
	_check(progress > 0.0 and progress < 1.0, "gold spreads from base to tip: %.2f" % progress)
	await _settle(made)
	_check(made._spirits.all(func(spirit: Node3D) -> bool: return spirit.sprout.material_override == GoldLeaf.material()), "both leaves end in the Gold leaf's own material")
	_check(made.find_child("CelebrationGoldLeaves", true, false) != null, "it says both get gold leaves")
	made.close()
	await process_frame
	var tie: Control = Celebration.open(_parent, _placing(1, false), false)
	await process_frame
	_check(tie._spreads.is_empty() and tie.find_child("CelebrationGoldLeaves", true, false) == null, "a first place that earned no Gold leaf shows none")
	tie.close()
	Outfit.show_unreleased = false
	await process_frame

func _show_once() -> void:
	var store: RefCounted = Placings.new(PLACINGS_PATH)
	Placings.use_shared(store)
	store.learn(OWNER, BOARD, _view([_row(5, MINE, 6300)]))
	var made: Control = Celebration.show_next(_parent, OWNER, true)
	_check(made != null and made.tier == Placings.TOP_TEN and Celebration.showing(_parent), "a waiting placing is celebrated")
	_check(Celebration.show_next(_parent, OWNER, true) == null, "and only once")
	_check(Placings.new(PLACINGS_PATH).was_shown(OWNER, MINE), "the shown mark is saved as it opens")
	made.close()
	await process_frame
	_check(not Celebration.showing(_parent), "a closed celebration is gone")
	_clear(PLACINGS_PATH)
	Placings.use_shared(Placings.new(PLACINGS_PATH))

func _screen() -> void:
	var api := FakeApi.new()
	root.add_child(api)
	var path := "GET /v1/leaderboards/" + BOARD
	var top: Array = _others(10)
	top[7] = _row(8, MINE, 6300, ["Ada", "Bo"])
	api.replies[path] = {"ok": true, "data": {"schema_version": 1, "board": BOARD, "top": top, "checking": [NEWEST]}}
	api.replies["GET /v1/leaderboards/me"] = {"ok": true, "data": {"schema_version": 1, "show_name": false}}
	var screen := _open_screen(api)
	await _frames(10)
	var board: Node = screen.find_child("LeaderboardBoard", true, false)
	_check(screen.find_child("LeaderboardFastestPair", true, false).text == PlayerCopy.LEADERBOARD_FASTEST_PAIR and screen.find_child("LeaderboardAllTime", true, false) != null and screen.find_child("LeaderboardHeader", true, false) != null, "Fastest pair, all time, with Place, Pair and Time")
	_check(range(1, 11).all(func(rank: int) -> bool: return board.find_child("LeaderboardRow%d" % rank, true, false) != null), "a full board shows ten rows")
	_check(board.find_child("LeaderboardRow1", true, false).find_child("LeaderboardGoldLeaf", true, false) != null and board.find_child("LeaderboardRow3", true, false).find_child("LeaderboardGoldLeaf", true, false) == null, "a gold leaf marks first place")
	_check(_has_text(board.find_child("LeaderboardRow2", true, false), PlayerCopy.LEADERBOARD_A_PAIR) and _has_text(board.find_child("LeaderboardRow1", true, false), PlayerCopy.LEADERBOARD_NAMES % ["Ada", "Bo"]), "hidden names read A pair")
	var mine: PanelContainer = board.find_child("LeaderboardRow8", true, false)
	_check((mine.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == Rows.MINE_FILL and (board.find_child("LeaderboardRow7", true, false).get_theme_stylebox("panel") as StyleBoxFlat).bg_color == Rows.ROW_FILL, "your row is lit")
	_check(mine.find_child("LeaderboardReport", true, false) == null and board.find_child("LeaderboardRow7", true, false).find_child("LeaderboardReport", true, false) != null, "other pairs' rows keep Report")
	var own: Node = screen.find_child("LeaderboardOwnRow", true, false)
	_check(own != null and not board.is_ancestor_of(own) and _has_text(own, "8") and _has_text(own, Runs.time_text(6300)) and own.find_child("LeaderboardWatch", true, false) != null, "Your best is pinned under the list with its place, time and Watch")
	var checking: Control = screen.find_child("LeaderboardChecking", true, false)
	_check(checking.visible and _has_text(checking, PlayerCopy.LEADERBOARD_RUN_CHECKING) and _has_text(checking, Runs.time_text(6000)), "the run being checked shows its time")
	_check(_has_text(screen.find_child("LeaderboardSharedNote", true, false), PlayerCopy.LEADERBOARD_SHARED_BOARD), "normal and duel runs share the board")
	var cards: Array = screen.find_child("LeaderboardChapters", true, false).find_children("Chapter_*", "Button", true, false)
	_check(not cards.is_empty() and cards.all(func(card: Node) -> bool: return (card.find_children("*", "TextureRect", true, false)[0] as TextureRect).texture != null), "each chapter shows its capture")
	var pips: Array = board.find_children("*", "", true, false).filter(func(node: Node) -> bool: return node is PipAvatar)
	_check(pips.size() == 20 and pips.all(func(pip: Node) -> bool: return pip.still), "rows draw still pips only: %d" % pips.size())
	var celebration: Control = screen.find_child(Celebration.NODE_NAME, true, false)
	_check(celebration != null and celebration.tier == Placings.TOP_TEN and screen.find_children("*", "SubViewport", true, false).size() == 1, "a run the board confirmed in its top 10 is celebrated over the board, its view the page's only one")
	screen.go_back()
	await process_frame
	_check(is_instance_valid(screen) and not screen.is_queued_for_deletion() and not Celebration.showing(screen._root), "Back leaves the celebration first, then the page")
	# The checked run passes: a refresh fades its row in, and celebrates it.
	top[4] = _row(5, NEWEST, 6000)
	api.replies[path] = {"ok": true, "data": {"schema_version": 1, "board": BOARD, "top": top, "checking": []}}
	screen._load(true)
	await _frames(4)
	var passed: Control = board.find_child("LeaderboardRow5", true, false)
	_check(passed != null and passed.modulate.a < 1.0 and board.find_child("LeaderboardRow4", true, false).modulate.a == 1.0, "only the row that passed its check fades in")
	_check(not checking.visible, "the checking note goes once its check passes")
	var deadline := Time.get_ticks_msec() + 3000
	while is_instance_valid(passed) and passed.modulate.a < 1.0 and Time.get_ticks_msec() < deadline: await process_frame
	_check(is_instance_valid(passed) and passed.modulate.a == 1.0, "over about 0.4 s")
	celebration = screen.find_child(Celebration.NODE_NAME, true, false)
	_check(celebration != null and celebration.placing.entry_id == NEWEST, "and its celebration shows once it is confirmed")
	screen.go_back()
	await process_frame
	_check(is_instance_valid(screen) and not screen.is_queued_for_deletion(), "Back takes the celebration first")
	screen.go_back()
	await process_frame
	_check(not is_instance_valid(screen) or screen.is_queued_for_deletion(), "then the page")
	# An empty board.
	api.replies[path] = {"ok": true, "data": {"schema_version": 1, "board": BOARD, "top": [], "checking": []}}
	var empty := _open_screen(api)
	await _frames(10)
	var empty_board: Node = empty.find_child("LeaderboardBoard", true, false)
	_check(empty_board.find_child("LeaderboardRow1", true, false) == null and _has_text(empty_board, PlayerCopy.LEADERBOARD_EMPTY) and not empty.find_child("LeaderboardChecking", true, false).visible, "an empty board says so")
	_check(empty.find_child(Celebration.NODE_NAME, true, false) == null, "nothing to celebrate on an empty board")
	empty.close()
	api.queue_free()
	await process_frame
	_clear(PLACINGS_PATH)
	Placings.use_shared(Placings.new(PLACINGS_PATH))

func _open_screen(api: Node) -> CanvasLayer:
	var screen := Screen.new()
	# A fresh client per page: the shared one keeps boards for a minute.
	screen.client = Client.new(api, OWNER, CHOICE_PATH)
	screen.player_id = OWNER
	screen.chapter_filter = func(key: String) -> bool: return key == Registry.LIGHTHOUSE_V2 or key == Registry.RELAY
	screen.chapter_key = Registry.LIGHTHOUSE_V2
	screen.reduced_motion = true
	root.add_child(screen)
	return screen

func _home() -> void:
	Placings.use_shared(Placings.new(PLACINGS_PATH))
	Placings.shared().learn(OWNER, BOARD, _view([_row(2, MINE, 6300)]))
	var storage := Storage.new(SAVE_PATH)
	storage.data.settings.sound = false
	storage.data.settings.reduced_motion = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves = storage
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.identity_loading = false
	await _frames(30)
	app._show_home()
	await _frames(30)
	app.api.player_id = OWNER
	var session := FakeSession.new()
	app.relay_session = session
	app.running = true
	app._service_leaderboard_celebration()
	_check(not Celebration.showing(app.ui), "never in the middle of a turn")
	app.running = false
	session.open = false
	app._service_leaderboard_celebration()
	_check(not Celebration.showing(app.ui), "nothing while the server has leaderboards off")
	session.open = true
	var card := InGameModal.open(app.ui, "SomeCard", "A card")
	app._service_leaderboard_celebration()
	_check(not Celebration.showing(app.ui), "a card on Home is read and closed first")
	card.close()
	await process_frame
	app._service_leaderboard_celebration()
	var shown: Control = app.ui.find_child(Celebration.NODE_NAME, false, false)
	_check(shown != null and shown.tier == Placings.SECOND and app._top_modal() == shown, "Home celebrates a confirmed place, as its top card")
	_check(shown != null and shown.view_board.is_connected(app._view_leaderboard), "its View board leads to the board")
	app.mode = "rooms"
	app._service_leaderboard_celebration()
	await process_frame
	_check(not Celebration.showing(app.ui), "leaving Home another way takes the celebration with it")
	app.mode = "home"
	app._service_leaderboard_celebration()
	_check(not Celebration.showing(app.ui), "shown once")
	Placings.shared().learn(OWNER, BOARD, _view([_row(1, SECOND, 6400)]))
	app._service_leaderboard_celebration()
	_check(Celebration.showing(app.ui), "the next placing waits its turn")
	app._close_top_modal()
	await process_frame
	_check(not Celebration.showing(app.ui), "Back leaves it")
	# View board from Home: Friends' leaderboards, open on the placing's chapter.
	var friends := FakeFriends.new()
	app.add_child(friends)
	app.friends_flow.screen = friends
	app.saves.data.settings.reduced_motion = true
	await app._view_leaderboard(BOARD)
	_check(friends.overlay != null and friends.overlay.chapter_key == Registry.LIGHTHOUSE_V2 and friends.overlay._selected == Registry.LIGHTHOUSE_V2, "View board opens the board on its chapter")
	_check(friends.overlay != null and friends.overlay.reduced_motion, "the board takes the player's Reduce motion")
	viewport.queue_free()
	await _frames(5)

func _frames(count: int) -> void:
	for frame in range(count): await process_frame

func _text(node: Node, child: String) -> String:
	var found: Node = node.find_child(child, true, false)
	return str(found.text) if found is Label else ""

func _has_text(node: Node, text: String) -> bool:
	if node == null: return false
	for label: Node in node.find_children("*", "Label", true, false):
		if label.text == text: return true
	return false
