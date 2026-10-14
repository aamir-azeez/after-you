extends SceneTree
## A late joiner's first look at a long Lighthouse room proves its whole chain
## of stages once. The room coordinator now proves the room's checkpoint on a
## worker as its response arrives (relay_room_coordinator._prove_room_ahead),
## so the full check that follows on the main thread replays no pair again.
## - After the worker, the main-thread check is the same verdict and replays
##   nothing; frames kept drawing while the worker ran.
## - Early stages and other chapters are left to the ordinary check.
const Registry = preload("res://services/chapter_registry.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const RoomProof = preload("res://core/lighthouse/room_proof.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Proofs.directory = "user://room-prove-ahead-" + Crypto.new().generate_random_bytes(6).hex_encode()
	var chain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/v2-chain.json"))
	var key := Registry.LIGHTHOUSE_V2
	var level := Registry.definition(key)
	var known := Registry.descriptor(key)
	var engine := Registry.simulation_script(key)
	var coordinator := Coordinator.new(Callable(), Callable(), Callable(), Callable())
	var room := {"level_id": known.level_id, "level_version": known.level_version, "definition_hash": known.definition_hash, "checkpoint": chain.checkpoints[5]}
	_check(Registry.resolve(room) == key, "A stage-five Lighthouse room")
	var frames := [0]
	var count := func() -> void: frames[0] += 1
	process_frame.connect(count)
	var before := RoomProof.pair_replays
	await coordinator._prove_room_ahead({"ok": true, "data": room})
	process_frame.disconnect(count)
	_check(RoomProof.pair_replays > before and frames[0] >= 1, "The worker proved the chain while frames kept drawing (%d frames, %d pairs)" % [frames[0], RoomProof.pair_replays - before])
	before = RoomProof.pair_replays
	var checked: Dictionary = engine.verify_checkpoint(level, chain.checkpoints[5])
	_check(checked.get("valid", false) and RoomProof.pair_replays == before, "The main-thread check that follows replays no pair")
	frames[0] = 0
	process_frame.connect(count)
	await coordinator._prove_room_ahead({"ok": true, "data": {"room": room.merged({"checkpoint": chain.checkpoints[1]}, true)}})
	await coordinator._prove_room_ahead({"ok": true, "data": {"level_id": "high-and-low"}})
	process_frame.disconnect(count)
	_check(frames[0] == 0, "An early stage or another chapter is left to the ordinary check")
	print("ROOM PROVE AHEAD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
