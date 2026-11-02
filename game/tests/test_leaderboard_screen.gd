extends SceneTree
## Leaderboards on the phone: services/leaderboard_runs.gd (which runs are
## ours, their ids and times), services/leaderboard_client.gd (reading a board
## and the name choice) and presentation/leaderboard_screen.gd (the board, the
## pinned "Your best" and still pips only). The restyled
## board's states and its celebrations: tests/test_leaderboard_celebration.gd.
const Runs = preload("res://services/leaderboard_runs.gd")
const Client = preload("res://services/leaderboard_client.gd")
const Screen = preload("res://presentation/leaderboard_screen.gd")
const Rows = preload("res://presentation/leaderboard_rows.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const Placings = preload("res://services/leaderboard_placings.gd")
const Celebration = preload("res://presentation/leaderboard_celebration.gd")
const TurnLooks = preload("res://services/turn_looks.gd")
const Outfit = preload("res://services/outfit.gd")
const OWNER := "OOOOOOOOOOOOOOOOOOOOOO"
const ROOM := "AAAAAAAAAAAAAAAAAAAAAA"
const RUNS_PATH := "user://leaderboard-runs-test.json"
const CHOICE_PATH := "user://leaderboard-name-test.json"
const PLACINGS_PATH := "user://leaderboard-placings-test.json"
const LOOKS_PATH := "user://leaderboard-looks-test.json"
const PARTNER := "GGGGGGGGGGGGGGGGGGGGGG"

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

func _run() -> void:
	for path: String in [RUNS_PATH, CHOICE_PATH, PLACINGS_PATH, LOOKS_PATH]: _clear(path)
	Runs.use_path(RUNS_PATH)
	TurnLooks.use_shared(TurnLooks.new(LOOKS_PATH))
	# The looks here are items the server offers once Pollen is live; this suite wears them as the celebration suite does.
	Outfit.show_unreleased = true
	Placings.use_shared(Placings.new(PLACINGS_PATH))
	_ids_and_times()
	_own_runs()
	_views()
	await _choice()
	await _screen()
	await _waiting_first()
	Placings.use_shared(null)
	TurnLooks.use_shared(null)
	Outfit.show_unreleased = false
	for path: String in [RUNS_PATH, CHOICE_PATH, PLACINGS_PATH, LOOKS_PATH]: _clear(path)
	print("Leaderboard screen: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _clear(path: String) -> void:
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _ids_and_times() -> void:
	# backend/test/leaderboards.test.ts pins the same id for the same room and branch.
	_check(Runs.entry_id(ROOM, 3) == "950c0a948aa0ab431b848fba650fa348", "a run's id is the server's hash of its room and branch")
	_check(Runs.board_key(Registry.RELAY) == "relay-isles@2" and Runs.board_key(Registry.LIGHTHOUSE_V2) == "sleeping-lighthouse@2", "a board is a chapter version")
	var relay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/final-checkpoint.json"))
	_check(Runs.run_time(Registry.RELAY, relay) == {"ticks": 588, "assisted": true}, "a run's time sums every turn, and catch assistance marks it")
	var chain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/v2-chain.json"))
	_check(Runs.run_time(Registry.LIGHTHOUSE_V2, chain.checkpoints[-1]) == {"ticks": 1470, "assisted": false}, "a Lighthouse run is never assisted")
	_check(Runs.run_time(Registry.LIGHTHOUSE_V2, chain.checkpoints[-2]).is_empty(), "an unfinished run has no time")
	_check(Runs.time_text(0) == "0:00.0" and Runs.time_text(1470) == "0:49.0" and Runs.time_text(1801) == "1:00.0" and Runs.time_text(1803) == "1:00.1", "times read as minutes, seconds and tenths")

func _snapshot(room: String, branch: int, checkpoint: Dictionary, complete: bool = true, guest: Variant = "GGGGGGGGGGGGGGGGGGGGGG") -> Dictionary:
	return {"room_id": room, "branch": branch, "active_role": "complete" if complete else "a", "host_id": OWNER, "guest_id": guest, "checkpoint": checkpoint, "updated_at": "2026-10-20T10:00:0%dZ" % branch}

func _own_runs() -> void:
	var chain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/v2-chain.json"))
	var final: Dictionary = chain.checkpoints[-1]
	Runs.note(OWNER, _snapshot(ROOM, 1, final, false), Registry.LIGHTHOUSE_V2)
	Runs.note(OWNER, _snapshot(ROOM, 1, final, true, null), Registry.LIGHTHOUSE_V2)
	_check(Runs.runs_of(OWNER).is_empty(), "a room still in play or without a partner is not a run")
	Runs.note(OWNER, _snapshot(ROOM, 1, final), Registry.LIGHTHOUSE_V2)
	Runs.note(OWNER, _snapshot(ROOM, 1, final), Registry.LIGHTHOUSE_V2)
	Runs.note(OWNER, _snapshot(ROOM, 2, final), Registry.LIGHTHOUSE_V2)
	var mine := Runs.on_board(OWNER, "sleeping-lighthouse@2")
	_check(mine.size() == 2 and mine[0].entry_id == Runs.entry_id(ROOM, 1) and mine[0].ticks == 1470, "each finished branch is one run, kept once: %s" % [mine])
	Runs.use_path(RUNS_PATH)
	_check(Runs.on_board(OWNER, "sleeping-lighthouse@2").size() == 2 and Runs.runs_of("someone-else").is_empty(), "runs survive a restart and stay per player")
	# Account deletion forgets one player's runs, straight after a start too; the other players' runs stay.
	Runs.note(PARTNER, _snapshot(ROOM, 1, final), Registry.LIGHTHOUSE_V2)
	_check(Runs.runs_of(PARTNER).size() == 1, "the partner keeps their own run on a shared phone")
	Runs.use_path(RUNS_PATH)
	Runs.clear_owner(PARTNER)
	Runs.use_path(RUNS_PATH)
	_check(Runs.runs_of(PARTNER).is_empty() and Runs.on_board(OWNER, "sleeping-lighthouse@2").size() == 2, "forgetting a player (account deletion) drops only their runs")
	var damaged := "user://leaderboard-runs-damaged-test.json"
	var file := FileAccess.open(damaged, FileAccess.WRITE)
	file.store_string("{damaged")
	file.close()
	var aside := damaged + ".unreadable-" + FileAccess.get_sha256(damaged)
	Runs.use_path(damaged)
	Runs.clear_owner(PARTNER)
	_check(FileAccess.file_exists(damaged) and not FileAccess.file_exists(aside) and JSON.parse_string(FileAccess.get_file_as_string(damaged)) is Dictionary, "forgetting a player replaces a damaged runs file and removes the copy kept aside")
	DirAccess.remove_absolute(damaged)
	Runs.use_path(RUNS_PATH)

func _views() -> void:
	var good := {"schema_version": 1, "board": "relay-isles@2", "top": [{"rank": 1, "entry_id": "a".repeat(32), "ticks": 300, "finished_on": "2026-10-20", "names": null, "gold_leaf": true}], "checking": ["b".repeat(32)]}
	_check(not Client.valid_view(good, "relay-isles@2").is_empty(), "a well formed board is read")
	_check(Client.valid_view(good, "first-steps@1").is_empty(), "a board for another chapter is refused")
	var named := good.duplicate(true)
	named.top[0].names = ["Ada"]
	_check(Client.valid_view(named, "relay-isles@2").is_empty(), "names come in twos or not at all")
	var bad_id := good.duplicate(true)
	bad_id.checking = ["not an id"]
	_check(Client.valid_view(bad_id, "relay-isles@2").is_empty(), "a checking id must be an id")
	# Looks on rows (backend leaderboards/run-looks.ts): kept in slot order, cleaned, and never a reason to refuse a board.
	_check(Client.valid_view(good, "relay-isles@2").top[0].looks == [], "a board from a server before looks reads with no looks")
	var dressed := good.duplicate(true)
	dressed.top[0].looks = [{"hat": "straw_hat"}, {"hat": "daisy", "cape": "red", "body": "no_such_item"}]
	var read := Client.valid_view(dressed, "relay-isles@2")
	_check(read.top[0].looks == [{"hat": "straw_hat"}, {"hat": "daisy"}], "a row keeps both looks in slot order, without unknown slots or items: %s" % [read.top[0].looks])
	for odd: Variant in [[{"hat": "daisy"}], "daisy", [1, null], [[], {}]]:
		var strange := good.duplicate(true)
		strange.top[0].looks = odd
		var kept := Client.valid_view(strange, "relay-isles@2")
		_check(not kept.is_empty() and kept.top[0].looks in [[], [{}, {}]], "odd looks never refuse the board: %s" % [odd])

func _choice() -> void:
	var api := FakeApi.new()
	root.add_child(api)
	var client := Client.new(api, OWNER, CHOICE_PATH)
	_check(not client.show_name(), "names are off by default")
	api.replies["GET /v1/leaderboards/me"] = {"ok": true, "data": {"schema_version": 1, "show_name": true}}
	await client.sync()
	_check(client.show_name(), "with nothing pending the server's choice is read, as after a reinstall")
	api.replies["PUT /v1/leaderboards/me"] = {"ok": false, "code": "service_unavailable"}
	_check(client.set_show_name(false), "a choice is kept on the phone at once")
	for frame in range(4): await process_frame
	var again := Client.new(api, OWNER, CHOICE_PATH)
	_check(not again.show_name(), "a choice the server has not taken stays after a restart")
	api.replies["PUT /v1/leaderboards/me"] = {"ok": true, "data": {"schema_version": 1, "show_name": false}}
	api.requests.clear()
	await again.sync()
	_check(api.requests.size() == 1 and api.requests[0][0] == "PUT" and api.requests[0][2] == {"schema_version": 1, "show_name": false}, "the pending choice goes on the next sync: %s" % [api.requests])
	api.requests.clear()
	await again.sync()
	_check(api.requests.is_empty(), "once taken and read, a sync asks nothing: %s" % [api.requests])
	api.queue_free()

func _screen() -> void:
	var api := FakeApi.new()
	root.add_child(api)
	var mine := Runs.entry_id(ROOM, 1)
	var view := {"schema_version": 1, "board": "sleeping-lighthouse@2", "checking": [Runs.entry_id(ROOM, 2)], "top": [
		{"rank": 1, "entry_id": "a".repeat(32), "ticks": 900, "finished_on": "2026-10-19", "names": ["Ada", "Bo"], "gold_leaf": true},
		{"rank": 2, "entry_id": mine, "ticks": 1470, "finished_on": "2026-10-20", "names": null, "gold_leaf": false, "looks": [{"hat": "daisy"}, {"hat": "seashell"}]},
		{"rank": 3, "entry_id": "c".repeat(32), "ticks": 1500, "finished_on": "2026-10-21", "names": null, "gold_leaf": false, "looks": [{"hat": "straw_hat"}, {"hat": "daisy"}]}]}
	TurnLooks.shared().note_member(PARTNER, {"hat": "straw_hat"})
	api.replies["GET /v1/leaderboards/sleeping-lighthouse@2"] = {"ok": true, "data": view}
	api.replies["GET /v1/leaderboards/me"] = {"ok": true, "data": {"schema_version": 1, "show_name": false}}
	var screen := Screen.new()
	screen.client = Client.new(api, OWNER, CHOICE_PATH)
	screen.player_id = OWNER
	screen.chapter_filter = func(key: String) -> bool: return key == Registry.LIGHTHOUSE_V2
	root.add_child(screen)
	for frame in range(10): await process_frame
	var board: Node = screen.find_child("LeaderboardBoard", true, false)
	_check(board != null and board.find_child("LeaderboardRow1", true, false) != null and board.find_child("LeaderboardRow3", true, false) != null, "the board shows its ranked runs")
	_check(screen.find_child("LeaderboardFastestPair", true, false) != null and screen.find_child("LeaderboardAllTime", true, false) != null, "one board, Fastest pair, all time")
	var first: Node = board.find_child("LeaderboardRow1", true, false)
	_check(_texts(first).has(PlayerCopy.LEADERBOARD_NAMES % ["Ada", "Bo"]) and first.find_child("LeaderboardGoldLeaf", true, false) != null, "a pair that shows its names, with the Gold leaf on first place")
	var third: Node = board.find_child("LeaderboardRow3", true, false)
	_check(_texts(third).has(PlayerCopy.LEADERBOARD_A_PAIR) and third.find_child("LeaderboardReport", true, false) != null, "a pair without names reads A pair and can be reported")
	_check(board.find_child("LeaderboardRow2", true, false).find_child("LeaderboardReport", true, false) == null, "a player's own run has no Report")
	var third_pips := third.find_children("*", "", true, false).filter(func(node: Node) -> bool: return node is PipAvatar)
	_check(third_pips.size() == 2 and third_pips[0].outfit == {"hat": "straw_hat"} and third_pips[1].outfit == {"hat": "daisy"} and third_pips.all(func(pip: Node) -> bool: return pip.still), "a pair that hides its names still wears its looks, as still pips")
	var first_pips := first.find_children("*", "", true, false).filter(func(node: Node) -> bool: return node is PipAvatar)
	_check(first_pips.size() == 2 and first_pips.all(func(pip: Node) -> bool: return pip.outfit.is_empty()), "a row with no looks shows the default pips")
	var own: Node = screen.find_child("LeaderboardOwnRow", true, false)
	var own_pips := own.find_children("*", "", true, false).filter(func(node: Node) -> bool: return node is PipAvatar)
	_check(own_pips.size() == 2 and not own_pips[0].own and own_pips[0].outfit == {"hat": "daisy"} and own_pips[1].outfit == {"hat": "seashell"}, "Your best on a ranked run draws the pair as its row does")
	var unlisted: Control = Rows.own(1470, 0, "", false, Callable(), TurnLooks.shared().member(PARTNER))
	var unlisted_pips := unlisted.find_children("*", "", true, false).filter(func(node: Node) -> bool: return node is PipAvatar)
	_check(unlisted_pips.size() == 2 and unlisted_pips[0].own and unlisted_pips[1].outfit == {"hat": "straw_hat"}, "Your best on a run the board does not list dresses the partner in the look this phone last heard for them")
	unlisted.free()
	_check(own != null and _texts(own).has("2") and _texts(own).has(Runs.time_text(1470)), "Your best is pinned with its rank")
	_check(screen.find_child("LeaderboardWaiting", true, false) == null, "a run listed as checking that is no faster than the pair's ranked run shows no clock")
	var celebration: Node = screen.find_child(Celebration.NODE_NAME, true, false)
	var pips := screen.find_children("*", "SubViewport", true, false).filter(func(view: Node) -> bool: return celebration == null or not celebration.is_ancestor_of(view))
	_check(pips.is_empty(), "rows and Your best draw still pips, never a view of their own: %d views" % pips.size())
	_check(screen.find_child(Celebration.NODE_NAME, true, false) != null, "this player's confirmed second place is celebrated")
	var avatars := screen.find_children("*", "", true, false).filter(func(node: Node) -> bool: return node is PipAvatar)
	_check(avatars.size() == 8 and avatars.all(func(pip: Node) -> bool: return pip.still), "two still pips a row: %d" % avatars.size())
	var reads := api.requests.filter(func(item: Array) -> bool: return item[1] == "/v1/leaderboards/sleeping-lighthouse@2").size()
	screen._load(false)
	for frame in range(4): await process_frame
	_check(api.requests.filter(func(item: Array) -> bool: return item[1] == "/v1/leaderboards/sleeping-lighthouse@2").size() == reads, "a board read a moment ago is not asked for again")
	screen.go_back()
	await process_frame
	_check(is_instance_valid(screen) and not screen.is_queued_for_deletion(), "Back leaves the celebration first")
	screen.go_back()
	await process_frame
	_check(not is_instance_valid(screen) or screen.is_queued_for_deletion(), "Back closes the page")
	api.queue_free()

## A run of this player's waiting for its check that would be first: on this
## phone it stands first with the clock and the Gold leaf, named as the board
## will name the pair (their row on another board this phone read), and the
## first place it passes loses the leaf here. Its check failing takes the row
## away quietly and the leaf goes back.
func _waiting_first() -> void:
	var path := "user://leaderboard-runs-waiting-test.json"
	var waiting := Runs.entry_id("WWWWWWWWWWWWWWWWWWWWWW", 1)
	var relay := Runs.entry_id("RRRRRRRRRRRRRRRRRRRRRR", 1)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 1, "players": {OWNER: [
		{"board": "sleeping-lighthouse@2", "entry_id": waiting, "ticks": 1470, "assisted": false, "finished_at": Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - 30) + "Z", "partner": PARTNER},
		{"board": "relay-isles@2", "entry_id": relay, "ticks": 5000, "assisted": false, "finished_at": "2026-10-20T10:00:00Z", "partner": PARTNER}]}}))
	file.close()
	Runs.use_path(path)
	var api := FakeApi.new()
	root.add_child(api)
	var top := [{"rank": 1, "entry_id": "f".repeat(32), "ticks": 2000, "finished_on": "2026-10-19", "names": ["Cy", "Di"], "gold_leaf": true},
		{"rank": 2, "entry_id": "e".repeat(32), "ticks": 2100, "finished_on": "2026-10-19", "names": null, "gold_leaf": false}]
	api.replies["GET /v1/leaderboards/sleeping-lighthouse@2"] = {"ok": true, "data": {"schema_version": 1, "board": "sleeping-lighthouse@2", "top": top, "checking": [waiting]}}
	var screen := Screen.new()
	screen.client = Client.new(api, OWNER, CHOICE_PATH)
	screen.client._choice = {"show": true, "pending": false, "synced": true}
	screen.client._views["relay-isles@2"] = {"at": Time.get_ticks_msec(), "view": {"schema_version": 1, "board": "relay-isles@2", "checking": [],
		"top": [{"rank": 3, "entry_id": relay, "ticks": 5000, "finished_on": "2026-10-20", "names": ["Ada", "Bo"], "gold_leaf": false}]}}
	screen.player_id = OWNER
	screen.chapter_filter = func(key: String) -> bool: return key == Registry.LIGHTHOUSE_V2
	root.add_child(screen)
	for frame in range(10): await process_frame
	var board: Node = screen.find_child("LeaderboardBoard", true, false)
	var first: Node = board.find_child("LeaderboardRow1", true, false) if board != null else null
	var second: Node = board.find_child("LeaderboardRow2", true, false) if board != null else null
	_check(first != null and first.find_child("LeaderboardWaiting", true, false) != null and first.find_child("LeaderboardGoldLeaf", true, false) != null and _texts(first).has(Runs.time_text(1470)), "a waiting run that would be first stands first with its clock and the Gold leaf")
	_check(first != null and _texts(first).has(PlayerCopy.LEADERBOARD_NAMES % ["Ada", "Bo"]), "named as the board will name the pair: %s" % [_texts(first) if first != null else []])
	_check(second != null and _texts(second).has(PlayerCopy.LEADERBOARD_NAMES % ["Cy", "Di"]) and second.find_child("LeaderboardGoldLeaf", true, false) == null, "the first place it passes loses the leaf on this phone")
	var own: Node = screen.find_child("LeaderboardOwnRow", true, false)
	_check(own != null and own.find_child("LeaderboardWaiting", true, false) != null and _texts(own).has(PlayerCopy.LEADERBOARD_NAMES % ["Ada", "Bo"]), "Your best is the waiting first place, named too")
	# The check fails: the board lists it nowhere.
	api.replies["GET /v1/leaderboards/sleeping-lighthouse@2"] = {"ok": true, "data": {"schema_version": 1, "board": "sleeping-lighthouse@2", "top": top, "checking": []}}
	screen._load(true)
	for frame in range(6): await process_frame
	first = board.find_child("LeaderboardRow1", true, false)
	_check(first != null and first.find_child("LeaderboardGoldLeaf", true, false) != null and first.find_child("LeaderboardWaiting", true, false) == null and _texts(first).has(PlayerCopy.LEADERBOARD_NAMES % ["Cy", "Di"]) and screen.find_children("LeaderboardWaiting", "", true, false).is_empty(), "a failed check takes the row away quietly and the first place has its leaf back")
	screen.queue_free()
	await process_frame
	# On a narrow screen the leaf, the place and the clock still fit the place column.
	for compact: bool in [false, true]:
		var row: Control = Rows.ranked({"rank": 1, "entry_id": waiting, "ticks": 1470, "names": null, "gold_leaf": true, "pending": true, "looks": []}, true, Callable(), compact)
		root.add_child(row)
		await process_frame
		var cell: Control = row.get_child(0).get_child(0)
		var wide := cell.get_combined_minimum_size().x
		_check(cell.find_child("LeaderboardGoldLeaf", false, false) != null and cell.find_child("LeaderboardWaiting", false, false) != null and wide <= (Rows.PLACE.y if compact else Rows.PLACE.x) + 0.5, "%s: the waiting first place's leaf, place and clock fit their column: %.0f px" % ["compact" if compact else "wide", wide])
		row.queue_free()
	api.queue_free()
	Runs.use_path(RUNS_PATH)
	_clear(path)

func _texts(node: Node) -> Array:
	var result: Array = []
	for label: Node in node.find_children("*", "Label", true, false): result.append(label.text)
	return result
