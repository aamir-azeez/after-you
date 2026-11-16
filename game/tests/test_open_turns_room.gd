extends SceneTree
## An open turns room (core/physical/open_turns.gd) through the real room
## coordinator, Turn of the Tide@3's Set the Tide with its fixture turns, the
## server doubled as backend/src/v2/room.ts answers:
## - turn 2 passes: its upload carries no checkpoint, is checked as a pass that
##   waited out its memory, and its receipt names no pair and keeps the room's
##   checkpoint;
## - turn 3 closes the stage: its receipt's turn id has turn 3's letter (t0-0-c),
##   as the server numbers turns, and it is taken.
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const TIDE := "turn-of-the-tide@3"
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
var checks := 0
var failures := 0

## The server's side of one open turns room: its turns so far on stage 0, or the next stage once closed.
class Server:
	extends RefCounted
	var level: Dictionary
	var revision := 3
	var turns: Array = []
	var checkpoint: Dictionary
	var stage_index := 0
	var receipts: Array = []
	func _init(definition: Dictionary, start: Dictionary, played: Array) -> void:
		level = definition
		checkpoint = start
		turns = played.duplicate(true)
	func view(player: String) -> Dictionary:
		var finished: bool = stage_index >= level.stages.size()
		var stage: Dictionary = level.stages[mini(stage_index, level.stages.size() - 1)]
		var turn: int = 0 if finished else turns.size() + 1
		var next: String = HOST if OpenTurns.slot(str(stage.first_player_slot), maxi(turn, 1)) == "p0" else GUEST
		var value := {"api_version": 2, "schema_version": 2, "room_id": ROOM, "revision": revision, "branch": 0, "stage_index": stage_index,
			"level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level), "host_id": HOST, "guest_id": GUEST,
			"checkpoint": checkpoint.duplicate(true), "a_turn_id": "t0-%d-a" % stage_index if not turns.is_empty() else null, "completed_pair_ids": ["p0-0"].slice(0, stage_index),
			"invite_expires_at": "2026-12-01T12:00:00Z", "created_at": "2026-11-16T12:00:00Z", "updated_at": "2026-11-16T12:%02d:00Z" % revision,
			"active_role": "complete" if finished else ("a" if turns.is_empty() else "b"), "first_player_id": null if finished else (HOST if stage.first_player_slot == "p0" else GUEST),
			"active_player_id": null if finished else next, "player_slot": "p0" if player == HOST else "p1", "stage_id": "" if finished else str(stage.id),
			"recording_a": turns[0].duplicate(true) if not turns.is_empty() else null, "validation": "structural_client_replay_required", "simulation_version": int(level.simulation_version),
			"open_turns": {"turn": turn, "cap": 0 if finished else OpenTurns.cap(stage), "must_finish": false, "pass_bytes": 262144, "passes": turns.slice(1).duplicate(true)}}
		if player == HOST: value["invite_code"] = "A1".repeat(10)
		return value
	func transport(request: Dictionary) -> Dictionary:
		var player := str(request.owner_player_id)
		if request.method == HTTPClient.METHOD_GET: return _json({"ok": true, "status": 200, "data": view(player)})
		var body: Dictionary = request.body
		var recording: Dictionary = body.recording
		var number: int = turns.size() + 1
		var closes: bool = recording.completed == true
		revision += 1
		var receipt := {"schema_version": 2, "room_id": ROOM, "idempotency_key": body.idempotency_key, "request_hash": Coordinator._request_hash("turns", body), "operation": "turns",
			"accepted_revision": revision, "branch": 0, "stage_index": stage_index, "stage_id": str(level.stages[stage_index].id), "turn_id": OpenTurns.turn_id(0, stage_index, number),
			"recording_hash": recording.recording_hash, "pair_id": "p0-%d" % stage_index if closes else null, "checkpoint_hash": body.checkpoint.checkpoint_hash if closes else checkpoint.checkpoint_hash}
		receipts.append(receipt)
		if closes:
			checkpoint = body.checkpoint.duplicate(true)
			stage_index += 1
			turns = []
		else: turns.append(recording.duplicate(true))
		return _json({"ok": true, "status": 200, "data": {"receipt": receipt, "room": view(player)}})
	static func _json(value: Dictionary) -> Dictionary:
		return JSON.parse_string(JSON.stringify(value))

class Phone:
	extends RefCounted
	var player := ""
	var disk: Dictionary = {}
	var keys := 0
	func _init(player_id: String) -> void:
		player = player_id
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
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var fixtures := {}
	for letter: String in ["a", "b", "c"]: fixtures[letter] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-%s.json" % letter))
	var server := Server.new(level, start, [fixtures.a])
	var guest := Phone.new(GUEST)
	var guest_room := Coordinator.new(Callable(server, "transport"), Callable(guest, "load_store"), Callable(guest, "save_store"), Callable(guest, "identity"), Callable(guest, "key"))
	_check(guest_room.bind_room(ROOM) and await guest_room.refresh() and guest_room.my_turn(), "The friend opens the room on turn 2 (%s)" % guest_room.last_code)
	_check(await guest_room.commit(fixtures.b), "Turn 2 is sent as a pass (%s)" % guest_room.last_code)
	_check(server.receipts[-1].pair_id == null and server.receipts[-1].checkpoint_hash == start.checkpoint_hash and guest_room.pending().is_empty(), "Its receipt names no pair and keeps the room's checkpoint, and the phone takes it")
	_check(int(guest_room.open_turns().get("turn", 0)) == 3 and not guest_room.my_turn(), "Turn 3 is the host's")
	var host := Phone.new(HOST)
	var host_room := Coordinator.new(Callable(server, "transport"), Callable(host, "load_store"), Callable(host, "save_store"), Callable(host, "identity"), Callable(host, "key"))
	_check(host_room.bind_room(ROOM) and await host_room.refresh() and host_room.my_turn(), "The host opens the room on turn 3 (%s)" % host_room.last_code)
	_check(await host_room.commit(fixtures.c), "Turn 3 closes the stage and its receipt (%s) is taken (%s)" % [server.receipts[-1].turn_id, host_room.last_code])
	_check(server.receipts[-1].turn_id == "t0-0-c" and host_room.pending().is_empty() and int(host_room.snapshot().get("stage_index", -1)) == 1, "Turn 3's id has its own letter and the room moves to the next stage")
	print("OPEN TURNS ROOM: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
