extends SceneTree
## An open turns room (core/physical/open_turns.gd) through the real room
## coordinator, Turn of the Tide@3's Set the Tide with its fixture turns, the
## server doubled as the fingerprints wire says (tests/open_turns_server.gd):
## - turn 2 passes: its upload carries no checkpoint, is checked as a pass that
##   waited out its memory, and its receipt names no pair and keeps the room's
##   checkpoint;
## - turn 3 closes the stage: its receipt's turn id has turn 3's letter (t0-0-c),
##   as the server numbers turns, and it is taken.
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
const OpenTurnStore = preload("res://services/open_turn_store.gd")
const Server = preload("res://tests/open_turns_server.gd")
const TIDE := "turn-of-the-tide@3"
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const ROOT := "user://open-turns-room-test"
var checks := 0
var failures := 0

class Phone:
	extends RefCounted
	var player := ""
	var disk: Dictionary = {}
	var keys := 0
	var room: RefCounted
	func _init(player_id: String, server: RefCounted) -> void:
		player = player_id
		room = Coordinator.new(Callable(server, "transport"), load_store, save_store, identity, key)
		room.turn_store_root = ROOT
	func identity() -> Dictionary:
		return {"ready": true, "player_id": player, "epoch": 1}
	func load_store(scope: String) -> Dictionary:
		return {"ok": true, "found": disk.has(scope), "value": disk.get(scope, {}).duplicate(true)}
	func save_store(scope: String, value: Dictionary) -> Dictionary:
		disk[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok": true}
	func key() -> String:
		keys += 1
		return "%s-operation-%04d" % [player.left(4), keys]

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for player: String in [HOST, GUEST]: OpenTurnStore.erase_owner(player, ROOT)
	var start := Registry.initial_checkpoint(TIDE)
	var fixtures := {}
	for letter: String in ["a", "b", "c"]: fixtures[letter] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-%s.json" % letter))
	var server := Server.new(TIDE, ROOM, HOST, GUEST)
	var host := Phone.new(HOST, server)
	var guest := Phone.new(GUEST, server)
	_check(host.room.bind_room(ROOM) and await host.room.refresh() and host.room.my_turn(), "The host opens the room on turn 1 (%s)" % host.room.last_code)
	_check(await host.room.commit(fixtures.a), "Turn 1 is sent (%s)" % host.room.last_code)
	_check(guest.room.bind_room(ROOM) and await guest.room.refresh() and guest.room.my_turn(), "The friend opens the room on turn 2 (%s)" % guest.room.last_code)
	_check(await guest.room.commit(fixtures.b), "Turn 2 is sent as a pass (%s)" % guest.room.last_code)
	var receipt: Dictionary = server.receipts.values()[-1] if not server.receipts.is_empty() else {}
	_check(receipt.get("pair_id", "") == null and receipt.get("checkpoint_hash") == start.checkpoint_hash and guest.room.pending().is_empty(), "Its receipt names no pair and keeps the room's checkpoint, and the phone takes it")
	_check(int(guest.room.open_turns().get("turn", 0)) == 3 and not guest.room.my_turn(), "Turn 3 is the host's")
	_check(await host.room.refresh() and host.room.my_turn(), "The host opens the room on turn 3 (%s)" % host.room.last_code)
	_check(await host.room.commit(fixtures.c), "Turn 3 closes the stage and is taken (%s)" % host.room.last_code)
	receipt = server.receipts.values()[-1]
	_check(receipt.turn_id == "t0-0-c" and host.room.pending().is_empty() and int(host.room.snapshot().get("stage_index", -1)) == 1, "Turn 3's id (%s) has its own letter and the room moves to the next stage" % receipt.turn_id)
	for player: String in [HOST, GUEST]: OpenTurnStore.erase_owner(player, ROOT)
	print("OPEN TURNS ROOM: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
