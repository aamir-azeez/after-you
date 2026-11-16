extends SceneTree
## Achievements on Google Play Games and Game Center (services/platform_games/platform_games.gd
## unlock_achievements): the one table of platform ids against the game's goals, an empty or
## unknown id sending nothing, the native provider's checks, goals paid before this phone first
## read them unlocking too, once per platform account, an offline unlock tried again at the next
## pass, and nothing while signed out or not offered. Headless; every file is the test's own.
const Service = preload("res://services/platform_games/platform_games.gd")
const GamesProvider = preload("res://services/platform_games/games_provider.gd")
const NativeProvider = preload("res://services/platform_games/native_games_provider.gd")
const Ids = preload("res://services/platform_games/platform_achievement_ids.gd")
const Store = preload("res://services/platform_games/platform_board_store.gd")
const FruitWallet = preload("res://services/fruit_wallet.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const AtomicFile = preload("res://services/atomic_file.gd")

const SERVER := "https://achievements.example.test"
const OWNER := "o_synthetic_player_0ach"
const KEY_A := "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"
const KEY_B := "b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1"
## A test's own ids: two achievements on both platforms, one only on Game Center.
const TABLE := {
	"together_first": {"game_center": "afteryou.ach.together_first", "play_games": "CgkIsynthetic01"},
	"hard_first": {"game_center": "afteryou.ach.hard_first", "play_games": "CgkIsynthetic02"},
	"gold_leaf": {"game_center": "afteryou.ach.gold_leaf", "play_games": ""},
}

class FakeProvider extends "res://services/platform_games/games_provider.gd":
	var platform := GAME_CENTER
	var unlocks: Array = []
	var answer: Dictionary = {"ok": true}
	func kind() -> String: return platform
	func available() -> bool: return true
	func authenticate(_interactive: bool) -> Dictionary: return {"ok": true, "signed_in": true, "player_key": KEY_A}
	func unlock_achievement(id: String) -> Dictionary:
		unlocks.append(id)
		await Engine.get_main_loop().process_frame
		return answer.duplicate()

class FakeApi extends Node:
	var base_url := SERVER
	var player_id := OWNER

class FakeAccount extends RefCounted:
	var _api: Node
	func _init(api: Node) -> void: _api = api
	func api() -> Node: return _api
	func identity_state() -> String: return "ready"
	func player_id() -> String: return OWNER
	func cloud_sources() -> RefCounted: return null

class FakeNative extends Object:
	signal games_result(request_id: String, operation: String, payload_json: String)
	signal games_error(request_id: String, operation: String, code: String)
	signal games_account_changed(payload_json: String)
	var calls: Array = []
	func games_available() -> bool: return true
	func games_unlock_achievement(id: String, request_id: String) -> void:
		calls.append(id)
		games_result.emit.call_deferred(request_id, "unlock_achievement", JSON.stringify({"unlocked": true}))

var checks := 0
var failures := 0
var _dir := ""
var _api: Node

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	_dir = "user://platform-achievements-test-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_api = FakeApi.new()
	root.add_child(_api)
	_ids()
	_store()
	await _native()
	await _service()
	_api.queue_free()
	FruitWallet.use_shared(null)
	print("PLATFORM ACHIEVEMENTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## One table, matching the game's goals; the keepsake goals wait until the server counts them.
func _ids() -> void:
	var goals: Array = PlayerCopy.FRUIT_GOALS.keys().filter(func(goal: String) -> bool: return not goal.begins_with("keepsake_"))
	var rows: Array = Ids.ACHIEVEMENTS.keys()
	goals.sort()
	rows.sort()
	_check(rows == goals, "Every counted goal has one row, and only those: %s" % [rows])
	var id_shape := RegEx.create_from_string(NativeProvider.BOARD_ID)
	for goal: String in Ids.ACHIEVEMENTS:
		var row: Dictionary = Ids.ACHIEVEMENTS[goal]
		_check(row.keys().size() == 2 and row.has(GamesProvider.GAME_CENTER) and row.has(GamesProvider.PLAY_GAMES), "%s names both platforms" % goal)
		var center := str(row.game_center)
		var play := str(row.play_games)
		_check(center.is_empty() or center == "afteryou.ach." + goal, "%s keeps its Game Center id" % goal)
		_check(play.is_empty() or (play.begins_with("CgkI") and id_shape.search(play) != null), "%s has a Play Console id or none" % goal)
	_check(Ids.id("not_a_goal", GamesProvider.GAME_CENTER) == "" and Ids.id("gold_leaf", GamesProvider.NONE) == "", "An unknown goal or platform has no id")
	_check(Ids.id("gold_leaf", GamesProvider.PLAY_GAMES, TABLE) == "" and Ids.id("gold_leaf", GamesProvider.GAME_CENTER, TABLE) == "afteryou.ach.gold_leaf", "A table may give one platform an id and not the other")

func _store() -> void:
	var path := _dir.path_join("store.json")
	var account := Store.account(GamesProvider.GAME_CENTER, KEY_A)
	var store := Store.new(path)
	_check(store.unlocked_for(account).is_empty(), "No file, nothing unlocked")
	_check(store.remember_unlocked(account, "afteryou.ach.hard_first") and store.remember_unlocked(account, "afteryou.ach.hard_first"), "An unlock is kept, once")
	var again := Store.new(path)
	_check(again.unlocked_for(account) == ["afteryou.ach.hard_first"] and again.unlocked_for(Store.account(GamesProvider.GAME_CENTER, KEY_B)).is_empty(), "It reads back, per account")
	_check(not FileAccess.get_file_as_string(path).contains(OWNER), "The file names no player")
	_write_json(path, {"schema_version": 1, "judged": {}, "posted": {}, "unlocked": {"someone": ["x"], account: ["afteryou.ach.ok", "bad id!", 3]}})
	_check(Store.new(path).unlocked == {account: ["afteryou.ach.ok"]}, "Only well formed unlocks are read")
	_write_json(path, {"schema_version": 1, "judged": {}, "posted": {account: {"relay-isles@2": 900}}})
	var older := Store.new(path)
	_check(older.unlocked.is_empty() and older.posted_for(account) == {"relay-isles@2": 900}, "A file from before achievements still reads")

func _write_json(path: String, value: Dictionary) -> void:
	AtomicFile.write_text(path, JSON.stringify(value))

## The native provider checks before it asks the plugin.
func _native() -> void:
	var native := FakeNative.new()
	var provider := NativeProvider.new(native, GamesProvider.PLAY_GAMES, self)
	_check("unlock_achievement" in NativeProvider.OPERATIONS, "Unlocking is a native operation")
	_check((await provider.unlock_achievement("CgkIsynthetic01")).ok and native.calls == ["CgkIsynthetic01"], "An unlock reaches the plugin with the platform id")
	_check((await provider.unlock_achievement("bad id!")).code == "failed" and (await provider.unlock_achievement("")).code == "failed" and native.calls.size() == 1, "A bad or empty id never reaches the plugin")
	native.free()

func _service_with(provider: RefCounted, name: String, offered: bool = true) -> Node:
	var service: Node = Service.new()
	service.configure(provider, _dir.path_join(name + ".json"))
	service.achievement_ids = TABLE
	root.add_child(service)
	service.attach(FakeAccount.new(_api))
	service.state.remember_capability({"play_games": offered and provider.kind() == GamesProvider.PLAY_GAMES, "game_center": offered and provider.kind() == GamesProvider.GAME_CENTER, "boards": false, "web_client_id": ""})
	service.sign_in = Service.SignIn.SIGNED_IN
	service.set("_player_key", KEY_A)
	return service

## A wallet read with these goals paid (the server's achievements list).
func _read(paid: Array) -> Dictionary:
	var rows: Array = []
	for goal: String in ["together_first", "hard_first", "gold_leaf", "duel_win_first"]:
		var row := {"id": goal, "fruits": 10, "goal": 1, "progress": 1 if goal in paid else 0, "live": true}
		if goal in paid: row.paid_at = 1763280000000
		rows.append(row)
	return {"fruits": {"schema_version": 1, "balance": 0, "earned": 0, "achievements": rows}}

func _service() -> void:
	var wallet: RefCounted = FruitWallet.new(_dir.path_join("fruit_wallet.json"))
	FruitWallet.use_shared(wallet)
	wallet.set_enabled(SERVER, OWNER, true)
	# The first read only learns what was paid before (no toast), and that still goes up.
	_check(wallet.note_view(SERVER, OWNER, _read(["hard_first", "gold_leaf", "duel_win_first"])) and wallet.unlocks(SERVER, OWNER).is_empty(), "The first read shows no toasts")
	var provider := FakeProvider.new()
	var service := _service_with(provider, "center")
	await service.unlock_achievements()
	_check(provider.unlocks == ["afteryou.ach.hard_first", "afteryou.ach.gold_leaf"], "Goals paid before unlock on the Game Center ids; one with no id sends nothing: %s" % [provider.unlocks])
	await service.unlock_achievements()
	_check(provider.unlocks.size() == 2, "An achievement this account confirmed is never sent again")
	# A receipt that pays another goal: the wallet's change unlocks it a moment later.
	wallet.note_receipt(SERVER, OWNER, {"fruits": {"balance": 10, "paid": [{"id": "together_first", "amount": 10}]}})
	_check(service.get("_unlocks_queued"), "The wallet's change asks for a pass")
	var deadline := Time.get_ticks_msec() + int(Service.BOARD_POST_DELAY_S * 1000.0) + 5000
	while (service.get("_unlocks_queued") or service.get("_unlocking")) and Time.get_ticks_msec() < deadline: await process_frame
	_check(provider.unlocks.size() == 3 and provider.unlocks[-1] == "afteryou.ach.together_first", "A newly paid goal unlocks with no call of its own: %s" % [provider.unlocks])
	# Another platform account on this phone gets them all again.
	service.set("_player_key", KEY_B)
	await service.unlock_achievements()
	_check(provider.unlocks.size() == 6, "Another account unlocks every paid goal again")
	# Offline: nothing is remembered, the pass stops, and the next pass tries again.
	var failing := FakeProvider.new()
	failing.platform = GamesProvider.PLAY_GAMES
	failing.answer = {"ok": false, "code": "offline"}
	var offline := _service_with(failing, "offline")
	await offline.unlock_achievements()
	_check(failing.unlocks == ["CgkIsynthetic02"], "An offline answer ends the pass")
	failing.answer = {"ok": true}
	await offline.unlock_achievements()
	_check(failing.unlocks == ["CgkIsynthetic02", "CgkIsynthetic02", "CgkIsynthetic01"], "The next pass tries again and goes on: %s" % [failing.unlocks])
	var kept := Store.new(_dir.path_join("offline-boards.json")).unlocked_for(Store.account(GamesProvider.PLAY_GAMES, KEY_A))
	_check(kept == ["CgkIsynthetic02", "CgkIsynthetic01"], "Only confirmed unlocks are kept: %s" % [kept])
	# A refused id (not in the console yet) is skipped, not the end of the pass.
	var refusing := FakeProvider.new()
	refusing.answer = {"ok": false, "code": "failed"}
	var refused := _service_with(refusing, "refused")
	await refused.unlock_achievements()
	_check(refusing.unlocks.size() == 3, "A refused unlock goes on to the next one")
	# Signed out, or the server not offering the platform: nothing is sent.
	var out_provider := FakeProvider.new()
	var signed_out := _service_with(out_provider, "signed-out")
	signed_out.sign_in = Service.SignIn.SIGNED_OUT
	await signed_out.unlock_achievements()
	var off_provider := FakeProvider.new()
	var off := _service_with(off_provider, "off", false)
	await off.unlock_achievements()
	off.unlock_achievements_soon()
	_check(out_provider.unlocks.is_empty() and off_provider.unlocks.is_empty() and not off.get("_unlocks_queued"), "Signed out or not offered: nothing goes up")
	for node: Node in [service, offline, refused, signed_out, off]: node.queue_free()
