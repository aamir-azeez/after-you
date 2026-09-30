extends SceneTree

const Collection = preload("res://services/shared_replay_collection.gd")
const View = preload("res://presentation/shared_replay_view.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
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
	var samples: Array = []
	for source: Array in [
		[Registry.FIRST_STEPS, "first_steps/final-checkpoint"],
		[Registry.ROLLING_HOME, "cooperative/rolling-home-final-checkpoint"],
		[Registry.LONG_WAY_HOME, "journey/long-way-home-final-checkpoint"],
	]:
		var entry := _entry(source[0], source[1])
		var before := Canonical.digest(entry)
		# Exercise the actual handoff: a library worker verifies the proof, then
		# the viewer verifies an independent copy without replaying it again.
		var worker := Thread.new()
		var started := Time.get_ticks_usec()
		var launched := worker.start(Callable(Collection, "verify_entry").bind(entry.duplicate(true), HOST)) == OK
		_check(launched, "A bounded replay proof worker starts")
		if not launched: continue
		_check(worker.wait_to_finish(), "The native engine accepts the cold saved replay")
		var cold_ms := (Time.get_ticks_usec() - started) / 1000.0
		var cached_key := Collection._entry_proof_key(entry, HOST)
		_check(Collection._verified_proofs.has(cached_key), "Only successful full verification primes the typed content key")
		var warm_ms: Array = []
		for repeat in range(3):
			started = Time.get_ticks_usec()
			_check(View.valid_sequence([entry.duplicate(true)], HOST), "The viewer admits the exact worker-verified copy")
			warm_ms.append((Time.get_ticks_usec() - started) / 1000.0)
		var engine: Script = Registry.simulation_script(source[0])
		var simulation: RefCounted = engine.new()
		started = Time.get_ticks_usec()
		_check(Registry.reset_simulation(simulation, source[0], Registry.definition(source[0]), entry.pair.b.stage_id, Registry.previous_checkpoint(source[0], entry.pair.checkpoint), entry.pair.a, "b", entry.pair.b), "Playback still initializes from the exact prior checkpoint")
		var reset_ms := (Time.get_ticks_usec() - started) / 1000.0
		samples.append({"chapter": source[0], "cold_native_ms": cold_ms, "warm_view_admission_ms": warm_ms, "playback_reset_ms": reset_ms})
		var altered := entry.duplicate(true)
		altered.pair.a.actions[0].x = int(altered.pair.a.actions[0].x) + 1
		var invalid_key := Collection._entry_proof_key(altered, HOST)
		_check(not Collection.verify_entry(altered, HOST) and not Collection._verified_proofs.has(invalid_key), "Changed coordinates with unchanged claimed hashes are rejected and never memoized")
		altered = entry.duplicate(true)
		altered.pair.checkpoint.checkpoint_hash = "0".repeat(64)
		_check(not Collection.verify_entry(altered, HOST), "A changed checkpoint cannot reuse the prior proof result")
		_check(not Collection.verify_entry(entry, OTHER), "Memoized proof does not admit a non-participant")
		_check(Collection._entry_proof_key(entry, GUEST) != cached_key, "Each participant has a distinct verification key")
		altered = entry.duplicate(true)
		altered.pair.stage_index = float(entry.pair.stage_index)
		_check(Collection._entry_proof_key(altered, HOST) != cached_key, "Typed serialization distinguishes integer and floating-point fields")
		_check(Canonical.digest(entry) == before, "Admission and failed tamper checks leave the original replay unchanged")
	# Occupancy keys cannot match owner(22) + ':' + SHA256(64), so they cannot
	# admit any replay. Two real native proofs exercise the fixed eviction bound
	# without requiring hundreds of simulations merely to fill the memo.
	var short_entry := _entry(Registry.FIRST_STEPS, "first_steps/lift-checkpoint")
	Collection._verified_proof_mutex.lock()
	Collection._verified_proofs.clear()
	Collection._verified_proof_mutex.unlock()
	_check(Collection.verify_entry(short_entry, HOST), "A native-verified short replay is the oldest memo entry")
	var first_key := Collection._entry_proof_key(short_entry, HOST)
	Collection._verified_proof_mutex.lock()
	for index in range(Collection.VERIFIED_PROOF_LIMIT - 1):
		Collection._verified_proofs["test-occupancy:%d" % index] = true
	Collection._verified_proof_mutex.unlock()
	var other_room := short_entry.duplicate(true)
	other_room.room.room_id = "0".repeat(22)
	_check(Collection.verify_entry(other_room, HOST), "A new real proof still validates before entering a full memo")
	_check(Collection._verified_proofs.size() == Collection.VERIFIED_PROOF_LIMIT and not Collection._verified_proofs.has(first_key), "The oldest unused proof is evicted at the fixed 256-entry bound")
	_check(Collection.verify_entry(short_entry, HOST) and Collection._verified_proofs.has(first_key), "An evicted replay can earn a fresh positive proof again")
	print(JSON.stringify({"scope": "desktop local replay admission components", "samples": samples}))
	print("Shared replay proof cache: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
