extends SceneTree
## An open turns room (core/physical/open_turns.gd) through the real room
## coordinator, Turn of the Tide@3's Set the Tide with its fixture turns, the
## server doubled as the fingerprints wire says (tests/open_turns_server.gd):
## - turn 2 passes: its upload carries no checkpoint, is checked as a pass that
##   waited out its memory, and its receipt names no pair and keeps the room's
##   checkpoint;
## - turn 3 closes the stage: its receipt's turn id has turn 3's letter (t0-0-c),
##   as the server numbers turns, and it is taken.
## Carry-over turns (claude-20261011/carry-over-turns/design.md), on the phone:
## - the shared timeline as OpenTurnStore plays it, on The Falls' example
##   (8 s, 40 s, 70 s, 45 s): what each turn watches before its hand-off, how
##   long the friend's replay plays beside it, a stage replay's stretches, and
##   the stage's first pip from the checkpoint;
## - the room gives the turn its playback: from turn 3 the friend's turn up to
##   the hand-off, and before a later stage's first turn the closing turn
##   whole; none for turns recorded before carry-over turns.
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
const OpenTurnStore = preload("res://services/open_turn_store.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
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
	_timeline()
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
	var shown: Dictionary = host.room.playback()
	if OpenTurnStore.carried(fixtures.b): _check(shown.get("turns", []).size() == 2 and shown.turns[-1].recording_hash == fixtures.b.recording_hash and int(shown.ticks) == OpenTurns.handoff_tick(OpenTurnStore.lengths([fixtures.a, fixtures.b]), 3), "Turn 3 first watches the friend's turn 2 up to its hand-off")
	else: _check(shown.is_empty(), "Turns from before carry-over turns have no playback")
	_check(await host.room.commit(fixtures.c), "Turn 3 closes the stage and is taken (%s)" % host.room.last_code)
	receipt = server.receipts.values()[-1]
	_check(receipt.turn_id == "t0-0-c" and host.room.pending().is_empty() and int(host.room.snapshot().get("stage_index", -1)) == 1, "Turn 3's id (%s) has its own letter and the room moves to the next stage" % receipt.turn_id)
	var next: Phone = guest if OpenTurnStore.first_slot(Registry.definition(TIDE).stages[1], host.room.checkpoint()) == "p1" else host
	if await next.room.refresh() and next.room.my_turn():
		shown = next.room.playback()
		if OpenTurnStore.carried(fixtures.c): _check(shown.get("turns", []).size() == 3 and shown.turns[-1].recording_hash == fixtures.c.recording_hash and int(shown.ticks) == -1 and str(shown.stage_id) == str(fixtures.c.stage_id), "The next stage's first turn first watches the closing turn whole")
		else: _check(shown.is_empty(), "A stage closed before carry-over turns has no playback")
	for player: String in [HOST, GUEST]: OpenTurnStore.erase_owner(player, ROOT)
	print("OPEN TURNS ROOM: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A turn of the shared timeline lasting `seconds`.
static func _turn(seconds: float) -> Dictionary:
	return {"duration_ticks": int(seconds * 30.0), OpenTurns.HANDOFF_TICK: 0}

func _timeline() -> void:
	var falls: Array = [_turn(8), _turn(40), _turn(70), _turn(45)]
	_check(OpenTurnStore.playback(falls.slice(0, 1)).is_empty(), "Turn 2 watches nothing: it hands off at tick 0")
	_check(OpenTurnStore.replay_ticks(falls[0], []) == 240, "Turn 1 replays whole beside turn 2 (8 s)")
	var three := OpenTurnStore.playback(falls.slice(0, 2))
	_check(three.get("turns", []).size() == 2 and int(three.get("ticks", 0)) == 240, "Turn 3 watches turn 2 from its start to 8 s")
	_check(OpenTurnStore.replay_ticks(falls[1], falls.slice(0, 1)) == 960, "The rest of turn 2 (32 s) plays beside turn 3")
	_check(int(OpenTurnStore.playback(falls.slice(0, 3)).get("ticks", 0)) == 960, "Turn 4 watches turn 3 from its start to 32 s")
	_check(OpenTurnStore.replay_ticks(falls[2], falls.slice(0, 2)) == 1140, "The rest of turn 3 (38 s) plays beside turn 4")
	_check(OpenTurnStore.replay_ticks(_turn(38), falls.slice(0, 3)) == 0, "A turn that ended exactly with its friend's replay leaves nothing beside the next")
	_check(OpenTurnStore.timeline(falls) == [{"turn": 1, "ticks": 240}, {"turn": 2, "ticks": 960}, {"turn": 3, "ticks": -1}], "A stage replay plays turn 2 to 8 s, turn 3 to 32 s and turn 4 to its end (%s)" % str(OpenTurnStore.timeline(falls)))
	_check(OpenTurnStore.timeline([_turn(0), _turn(3), _turn(2)]) == [{"turn": 2, "ticks": -1}], "A turn handed over at its tick 0 has no stretch of its own")
	var closing := OpenTurnStore.playback([], falls)
	_check(closing.get("turns", []) == falls and int(closing.get("ticks", 0)) == -1, "A later stage's first turn watches the closing turn whole")
	_check(OpenTurnStore.playback([]).is_empty(), "A level's first turn watches nothing")
	var before: Array = [{"duration_ticks": 240}, {"duration_ticks": 1200}, {"duration_ticks": 2100}]
	_check(OpenTurnStore.playback(before).is_empty() and OpenTurnStore.playback([], before).is_empty() and OpenTurnStore.timeline(before).is_empty() and OpenTurnStore.replay_ticks(before[1], before.slice(0, 1)) == 1200, "Turns from before carry-over turns play as they always have")
	_check(OpenTurnStore.first_slot({"first_player_slot": "p0"}, {}) == "p0" and OpenTurnStore.first_slot({"first_player_slot": "p0"}, {OpenTurns.NEXT_FIRST_SLOT: "p1"}) == "p1", "A stage's first pip is the checkpoint's next_first_slot, else the stage's own")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
