extends SceneTree
## A shared replay part just downloaded is checked on a worker
## (shared_replay_collection._verify_on_worker), not in one frame: a Turn of the
## Tide stage took seconds. The verdict is exactly verify_entry's, a success
## is remembered as verify_entry remembers it, and frames keep drawing.
const Collection = preload("res://services/shared_replay_collection.gd")
const Registry = preload("res://services/chapter_registry.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const OTHER := "SSSSSSSSSSSSSSSSSSSSSS"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _entry(chapter: String, fixture: String) -> Dictionary:
	var checkpoint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + fixture + ".json"))
	var index := int(checkpoint.stage_index) - 1
	return {"schema_version": 1, "room": {"family": "chapter", "room_id": ROOM, "host_id": HOST, "guest_id": GUEST, "chapter_key": chapter, "title": "Saved chapter"}, "pair": {"pair_id": "p0-%d" % index, "branch": 0, "stage_index": index, "a": checkpoint.proof.a.duplicate(true), "b": checkpoint.proof.b.duplicate(true), "checkpoint": checkpoint}}

func _run() -> void:
	var entry := _entry(Registry.WISHING_WELL, "cooperative/the-wishing-well-final-checkpoint")
	var tampered := entry.duplicate(true)
	tampered.pair.b.actions[0].x = int(tampered.pair.b.actions[0].x) + 1 if int(tampered.pair.b.actions[0].x) < 100 else 99
	var frames := [0]
	var count := func() -> void: frames[0] += 1
	process_frame.connect(count)
	var proven: bool = await Collection._verify_on_worker(entry, HOST)
	process_frame.disconnect(count)
	_check(proven, "A downloaded Wishing Well part passes on the worker")
	_check(frames[0] >= 1, "Frames kept drawing while it was checked (%d)" % frames[0])
	_check(Collection._verified_proofs.has(Collection._entry_proof_key(entry, HOST)), "Its proof is remembered, so the cache check that follows replays nothing")
	_check(not await Collection._verify_on_worker(tampered, HOST) and not Collection.verify_entry(tampered, HOST), "A changed recording fails on the worker as it fails here")
	_check(not await Collection._verify_on_worker(entry, OTHER) and not Collection.verify_entry(entry, OTHER), "Another identity is refused on the worker as here")
	print("PART VERIFY WORKER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
