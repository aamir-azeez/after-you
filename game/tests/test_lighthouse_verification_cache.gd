extends SceneTree
## Reuse must preserve full replay proof, source isolation and bounded memory.
const Simulation = preload("res://core/lighthouse/borrowed_light.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/complete-six-v3.json"))
	if not fixture is Dictionary or not fixture.get("pairs") is Array:
		push_error("Missing six-stage frozen evidence.")
		quit(1)
		return
	var pairs: Array = fixture.pairs
	Simulation._clear_verification_cache()
	_check(Simulation._verified_replays.is_empty(), "A fresh proof cache contains no imported trust")
	var cold := Simulation.checkpoint_from_pairs(pairs)
	_check(cold.valid and Canonical.same(cold.checkpoint, fixture.checkpoints[-1]), "Cold six-stage proof matches the frozen checkpoint")
	var warm := Simulation.checkpoint_from_pairs(pairs)
	_check(warm.valid and Canonical.same(warm, cold), "Warm proof produces exactly the same checkpoint")
	var first: Dictionary = pairs[0].a
	var second: Dictionary = pairs[0].b
	var result := Simulation.verify_recording(second, first)
	var expected := result.duplicate(true)
	result.snapshot.players.p0.x += 1000
	result.snapshot.optics.clear()
	_check(Canonical.same(Simulation.verify_recording(second, first), expected), "Returned nested snapshots cannot poison a later verification")

	var changed := second.duplicate(true)
	changed.actions[0].x = 1 if int(changed.actions[0].x) != 1 else -1
	_check(not Simulation.verify_recording(changed, first).valid, "Changed actions with a stale hash cannot reuse a cached proof")
	changed.recording_hash = Simulation.recording_hash(changed)
	_check(not Simulation.verify_recording(changed, first).valid, "Recomputed content hashes do not replace deterministic replay")
	var source := first.duplicate(true)
	source.actions[0].x = 1 if int(source.actions[0].x) != 1 else -1
	_check(not Simulation.verify_recording(second, source).valid, "An altered source with its old hash is rejected even after a warm B proof")
	source.recording_hash = Simulation.recording_hash(source)
	var rebound := second.duplicate(true)
	rebound.source_recording_hash = source.recording_hash
	rebound.recording_hash = Simulation.recording_hash(rebound)
	_check(not Simulation.verify_recording(rebound, source).valid, "Rebinding hashes to an invalid source does not create a viable pair")
	var checkpoint := Simulation.initial_checkpoint()
	checkpoint.players.p0.x += 8
	_check(not Simulation._verify_at_checkpoint(second, first, checkpoint).valid, "A changed predecessor with an unchanged supplied hash misses the old proof")
	changed = second.duplicate(true)
	changed.definition_hash = "0".repeat(64)
	changed.recording_hash = Simulation.recording_hash(changed)
	_check(not Simulation.verify_recording(changed, first).valid, "Current catalog validation still precedes reuse")
	changed = second.duplicate(true)
	changed.simulation_version = 4
	changed.recording_hash = Simulation.recording_hash(changed)
	_check(not Simulation.verify_recording(changed, first).valid, "Unknown simulation versions cannot reuse earlier results")
	changed = second.duplicate(true)
	changed.extra = true
	_check(not Simulation.verify_recording(changed, first).valid, "Unexpected fields are still rejected before a cache lookup")
	var poisoned := pairs.duplicate(true)
	poisoned[0].b = rebound
	_check(not Simulation.checkpoint_from_pairs(poisoned).valid, "Later cached stages cannot hide a changed earlier pair")
	_check(Canonical.same(Simulation.verify_recording(second, first), expected), "Rejected evidence leaves the original successful proof intact")
	Simulation._clear_verification_cache()
	_check(not Simulation.verify_recording(changed, first).valid and Simulation._verified_replays.is_empty(), "A rejected recording is not cached in a cold process state")
	_check(Canonical.same(Simulation.checkpoint_from_pairs(pairs), cold), "Clearing reuse requires a fresh proof with the same final result")

	_bounded_authentic_rehearsals()
	_check(checks >= 23, "All proof isolation and memory groups ran")
	print("AFTER YOU LIGHTHOUSE VERIFICATION CACHE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _bounded_authentic_rehearsals() -> void:
	Simulation._clear_verification_cache()
	var live := Simulation.new()
	live.reset()
	var incomplete: Dictionary = {}
	for index in range(Simulation.VERIFIED_REPLAY_LIMIT + 4):
		live.step({})
		var record := live.export_recording()
		var result := Simulation.verify_recording(record)
		if index == 0:
			incomplete = record
			_check(result.valid and not result.snapshot.can_commit, "A verified unfinished rehearsal remains uncommittable")
		if not result.valid:
			_check(false, "Authentic rehearsal unexpectedly failed")
	_check(Simulation._verified_replays.size() == Simulation.VERIFIED_REPLAY_LIMIT, "Distinct valid rehearsals cannot exceed the entry budget")
	_check(Simulation._verified_replay_bytes <= Simulation.VERIFIED_REPLAY_BYTES, "Serialized retained evidence stays within its byte budget")
	var restored := Simulation.verify_recording(incomplete)
	_check(restored.valid and not restored.snapshot.can_commit, "An evicted rehearsal can be reproved without becoming accepted")
	var before: int = Simulation._verified_replay_bytes
	# Storage-only boundary: oversized entries are never retained, even when a
	# real positive result is passed to the internal cache helper.
	Simulation._remember_verified_replay("x".repeat(Simulation.VERIFIED_REPLAY_BYTES + 1), restored)
	_check(Simulation._verified_replay_bytes == before, "A single oversized key is not retained")
	Simulation._remember_verified_replay("rejected", {"valid": false, "error": "test"})
	_check(Simulation._verified_replay_bytes == before, "Negative results are never retained")
	Simulation._clear_verification_cache()
	_check(Simulation._verified_replay_bytes == 0 and Simulation._verified_replays.is_empty(), "Cache release drops both contents and accounting")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
