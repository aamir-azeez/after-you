extends SceneTree
## Owner reports after a friend finished a room while the owner was away: the
## unread dot that never cleared, a part missing until a manual refresh, a part
## row that vanished on tap, a raw id as the friend's name, and replay badges
## that said You / Memory from the recorder's side.
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const KEY := "chapter:" + ROOM
const Badges = preload("res://presentation/kit/badges.gd")
const IslandWorld = preload("res://presentation/island_world.gd")

class Main extends "res://main.gd":
	var test_identity := {"ready": true, "player_id": HOST, "epoch": 1}
	var opened_replays: Array = []
	var drawn: Array = []
	var refreshes := 0
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _exit_tree() -> void: pass
	func _relay_identity() -> Dictionary: return test_identity.duplicate(true)
	func _production_replay_key_allowed(_key: String) -> bool: return true
	func open_shared_replay_room(room_id: String) -> void: opened_replays.append(room_id)
	func _draw_shared_replay_memories(rows: Array, _message: String = "") -> void: drawn.append(rows.duplicate(true))
	func _fetch_missing_shared_photos(_key: String) -> void: pass

class Inbox extends RefCounted:
	var confirmed: Array = []
	func confirm_room_rendered(version: int, room_id: String) -> bool:
		confirmed.append([version, room_id])
		return true

class Replays extends RefCounted:
	var sequence: Array = []
	var rows: Array = [{"id": "p0-0", "cached": true}, {"id": "p0-1", "cached": false}]
	var refreshed := 0
	var saved: Array = []
	func local_loading() -> bool: return false
	func local_sequence(_key: String) -> Array: return sequence
	func busy() -> bool: return false
	func memories(_key: String, _cached: bool = false) -> Array: return rows.filter(func(row: Dictionary) -> bool: return row.cached)
	func listed(_key: String) -> Array: return rows.duplicate(true)
	func refresh_memories(_key: String) -> Array:
		refreshed += 1
		return rows.duplicate(true)
	func open_memory(_key: String, id: String, _row: Dictionary = {}) -> Dictionary:
		saved.append(id)
		for row: Dictionary in rows:
			if row.id == id: row.cached = true
		return {"schema_version": 1, "room": {}, "pair": {"pair_id": id}}
	func rooms() -> Array: return [{"family": "chapter", "room_id": ROOM, "host_id": HOST, "guest_id": GUEST, "chapter_key": "the-wishing-well@1", "title": "The Wishing Well"}]
	func updated_at(_room: Dictionary) -> int: return 0

class Nicknames extends RefCounted:
	var names: Dictionary = {}
	func nickname(_server: String, _owner: String, friend: String) -> String: return str(names.get(friend, ""))
	func display_name(_server: String, _owner: String, friend: String, fallback: String = "") -> String: return str(names.get(friend, fallback if not fallback.is_empty() else friend.substr(0, 8)))

class Api extends Node:
	var busy := false
	var base_url := "https://rooms.test"
	var player_id := HOST

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _app() -> Main:
	var app := Main.new()
	app.api = Api.new()
	app.add_child(app.api)
	root.add_child(app)
	return app

func _run() -> void:
	await _completed_room_clears_its_dot()
	await _room_lists_every_part()
	await _download_row_stays()
	_friend_names()
	_badges()
	await process_frame
	print("SHARED ROOM FOLLOWUPS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _completed_room_clears_its_dot() -> void:
	var app := _app()
	var inbox := Inbox.new()
	app.room_inbox = inbox
	app.ui = Control.new()
	app.add_child(app.ui)
	app.mode = "rooms"
	await app._open_room_from_hub({"api_version": 2, "room_id": ROOM, "status": "completed", "remote_activity_sequence": 3})
	_check(app.opened_replays == [ROOM], "Watch replay opens the finished room's replay")
	_check(inbox.confirmed == [[2, ROOM]], "Watching a finished room's replay marks its activity seen, so the dot and the count clear: %s" % [inbox.confirmed])
	app.queue_free()

func _room_lists_every_part() -> void:
	var app := _app()
	var replays := Replays.new()
	app.shared_replays = replays
	app.mode = "shared_memories"
	app.shared_replay_room = KEY
	await app._check_shared_room_parts(KEY)
	_check(replays.refreshed == 1, "A room missing its last part asks the server once when it opens")
	_check(not app.drawn.is_empty() and app.drawn[-1].size() == 2, "Every part shows without a manual refresh: %s" % [app.drawn])
	await app._check_shared_room_parts(KEY)
	_check(replays.refreshed == 1, "It asks only once a session")
	var complete := _app()
	var whole := Replays.new()
	whole.sequence = [{}, {}]
	complete.shared_replays = whole
	complete.mode = "shared_memories"
	complete.shared_replay_room = KEY
	await complete._check_shared_room_parts(KEY)
	_check(whole.refreshed == 0, "A room whose every part is saved here sends nothing")
	app.queue_free()
	complete.queue_free()

func _download_row_stays() -> void:
	var app := _app()
	var replays := Replays.new()
	app.shared_replays = replays
	app.mode = "shared_memories"
	app.shared_replay_room = KEY
	await app._save_shared_memory(KEY, {"id": "p0-1", "cached": false})
	_check(replays.saved == ["p0-1"], "Selecting a part that is not saved downloads it")
	var last: Array = app.drawn[-1] if not app.drawn.is_empty() else []
	_check(last.size() == 2 and last[1].id == "p0-1" and last[1].cached, "The row stays listed and now reads as saved: %s" % [last])
	app.queue_free()

func _friend_names() -> void:
	var app := _app()
	var names := Nicknames.new()
	app.friend_nicknames = names
	var room: Dictionary = Replays.new().rooms()[0]
	_check(app._room_partner_name(room) == "a friend", "A friend without a nickname is 'a friend', never a raw id")
	names.names[GUEST] = "Sam"
	_check(app._room_partner_name(room) == "Sam" and app._room_partner_nickname(room) == "Sam", "A nickname names the friend")
	app.test_identity.player_id = GUEST
	_check(app._room_partner_name(room) == "a friend", "The guest sees the host by their own nickname list")
	app.queue_free()

func _badges() -> void:
	var world := IslandWorld.new()
	var state := {"active_slot": "p1", "players": {"p0": {"ghost": true}, "p1": {}}}
	_check(world._role_badge_text(state, "p1") == "You" and world._role_badge_text(state, "p0") == "Memory", "Live turns keep You and Memory")
	var host_view := Badges.viewer_labels(state, "p0", "Sam")
	_check(world._role_badge_text(host_view, "p0") == "You" and world._role_badge_text(host_view, "p1") == "Sam", "In a replay the host's spirit is You and the friend's is their nickname")
	var guest_view := Badges.viewer_labels(state, "p1", "")
	_check(world._role_badge_text(guest_view, "p1") == "You" and world._role_badge_text(guest_view, "p0") == "Friend", "Without a nickname the friend's spirit reads Friend")
	_check(not state.has("viewer_slot") and Badges.viewer_labels(state, "", "Sam") == state, "The simulation's state is never changed, and an unknown viewer keeps the usual badges")
	world.free()
