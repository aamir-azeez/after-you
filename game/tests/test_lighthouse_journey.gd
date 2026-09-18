extends SceneTree

const Journey = preload("res://services/lighthouse_journey.gd")
const Storage = preload("res://services/local_save.gd")
const Simulation = preload("res://core/lighthouse/borrowed_light.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0
var paths: Array[String] = []
var pair: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture := JSON.new()
	_check(fixture.parse(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/borrowed-light-v3.json")) == OK, "Frozen pair parses")
	if not fixture.data is Dictionary:
		_finish()
		return
	pair = fixture.data
	_check(Simulation.verify_recording(pair.b, pair.a).valid, "Frozen pair replays with this engine")
	_progression()
	_writes_and_recovery()
	_draft_context()
	_attempt_forks()
	_check(checks >= 30, "Every journal group executed")
	_finish()

func _progression() -> void:
	var path := _path("progress")
	var journal := Journey.new(path)
	journal.load_data()
	_check(not journal.read_only and journal.stage_id() == "borrowed-light" and journal.role() == "a", "New journal starts at the first contribution")
	_check(not FileAccess.file_exists(path), "Reading an empty journal does not fabricate a save")
	var live: RefCounted = journal.create_live_simulation()
	live.step({})
	var incomplete: Dictionary = live.export_recording()
	_check(journal.save_live_draft(live) and not journal.accept_recording(incomplete), "Incomplete authentic input persists as a draft, never a committed turn")
	journal = Journey.new(path)
	journal.load_data()
	_check(not journal.read_only and Canonical.same(journal.draft(), incomplete), "Restart verifies and preserves the exact unfinished input")
	_check(journal.accept_recording(pair.a) and journal.role() == "b" and journal.draft().is_empty(), "A acceptance changes role and clears only the draft")
	_check(not journal.accept_recording(pair.a), "Duplicate A cannot be accepted as B")
	journal = Journey.new(path)
	journal.load_data()
	_check(Canonical.same(journal.prior_recording(), pair.a) and journal.role() == "b", "The immutable earlier contribution survives restart")
	_check(journal.accept_recording(pair.b) and journal.stage_id() == "missing-piece", "Verified B advances to the second stage")
	var derived: Dictionary = Simulation.checkpoint_from_pairs([pair])
	_check(Canonical.same(journal.checkpoint(), derived.checkpoint), "The checkpoint comes from replayed evidence")
	var copy: Dictionary = journal.checkpoint()
	copy.players.p0.x = 99999
	_check(Canonical.same(journal.checkpoint(), derived.checkpoint), "Returned checkpoints cannot mutate accepted progress")
	var source: RefCounted = journal.create_live_simulation()
	_check(source.snapshot().active_slot == "p1", "Second stage reverses roles without swapping physical players")
	_move(source, [-80, int(source.snapshot().players.p1.z)])
	_move(source, [-80, 0])
	source.step({"interact": true})
	for _i in range(20): source.step({})
	var second_a: Dictionary = source.export_recording()
	_check(source.can_commit() and journal.accept_recording(second_a), "Actual mirror inputs produce an accepted second-stage source")
	var receiver: RefCounted = journal.create_live_simulation()
	var position: Dictionary = receiver.snapshot().players.p0
	_move(receiver, [int(position.x), 0])
	_move(receiver, [-48, 0])
	_move(receiver, [-48, -356])
	_move(receiver, [40, -356])
	receiver.step({"interact": true})
	receiver.step({})
	_check(receiver.snapshot().props["portable-lens"].status == "carried" and journal.save_live_draft(receiver), "A lens in transit is preserved independently of a checkpoint")
	journal = Journey.new(path)
	journal.load_data()
	var resumed: RefCounted = Simulation.new()
	_check(resumed.resume_recording(journal.draft(), journal.prior_recording(), journal.pairs()), "Restart restores the actual carried lens from its input history")
	_move(resumed, [-48, -356])
	_move(resumed, [-48, 60])
	_move(resumed, [40, 60])
	resumed.step({"interact": true})
	_check(resumed.can_commit() and journal.accept_recording(resumed.export_recording()), "A completed return is committed only after replay and durable write")
	_check(journal.pairs().size() == 2 and journal.role() == "a", "Both contributions are retained at the new checkpoint")
	_check(not journal.chapter_complete(), "Two stages are never described as the complete six-stage chapter")
	journal = Journey.new(path)
	journal.load_data()
	_check(not journal.read_only and journal.pairs().size() == 2 and journal.draft().is_empty(), "Restart preserves both completed stages")

func _writes_and_recovery() -> void:
	var path := _path("recovery")
	var journal := Journey.new(path)
	journal.load_data()
	_check(journal.accept_recording(pair.a), "Seed a real committed contribution")
	var text := FileAccess.get_file_as_string(path)
	var original: Dictionary = JSON.parse_string(text)
	var newer: Dictionary = original.duplicate(true)
	newer.generation += 1
	_write(path + ".tmp", JSON.stringify(newer))
	journal = Journey.new(path)
	journal.load_data()
	_check(not journal.read_only and journal.role() == "b" and journal._storage.loaded_from == path + ".tmp", "The latest complete interrupted generation is recovered")
	_write(path + ".backup", text)
	_write(path + ".tmp", "{unfinished")
	journal = Journey.new(path)
	journal.load_data()
	_check(not journal.read_only and journal.role() == "b", "An incomplete temporary generation does not erase a verified prior save")
	var damaged_archive := path + ".tmp.unreadable-" + FileAccess.get_sha256(path + ".tmp") + ".json"
	paths.append(damaged_archive)
	_check(FileAccess.file_exists(damaged_archive), "Damaged data is preserved before later writes")
	var future: Dictionary = original.duplicate(true)
	future.lighthouse.simulation_version = 400
	_write(path + ".tmp", JSON.stringify(future))
	var before := FileAccess.get_sha256(path)
	journal = Journey.new(path)
	journal.load_data()
	_check(journal.read_only and not journal.accept_recording(pair.b), "A future generation holds the journal instead of falling back and overwriting it")
	_check(FileAccess.get_sha256(path) == before, "A held save stays byte-identical")
	var tampered: Dictionary = original.duplicate(true)
	tampered.lighthouse.a.actions[0].move_x = 777
	_write(path + ".tmp", JSON.stringify(tampered))
	journal = Journey.new(path)
	journal.load_data()
	_check(journal.read_only, "Unsupported recorded movement cannot become a trusted checkpoint")
	var blocked := Journey.new("user://directory-that-does-not-exist/lighthouse.json")
	blocked.load_data()
	_check(not blocked.accept_recording(pair.a) and blocked.role() == "a" and blocked.prior_recording().is_empty(), "Failed storage leaves acceptance and role unchanged")
	var collision := Journey.new(Storage.PATH)
	collision.load_data()
	_check(collision.read_only, "The journal refuses to open the original journey path")
	var relay := Journey.new("user://relay-journey-v2.json")
	relay.load_data()
	_check(relay.read_only, "The journal refuses to open the distributed Relay path")

func _draft_context() -> void:
	var journal := Journey.new(_path("live"))
	journal.load_data()
	var live: RefCounted = journal.create_live_simulation()
	live.step({})
	var foreign := Simulation.new()
	foreign.reset()
	foreign.step({})
	_check(not journal.save_live_draft(foreign), "Another engine cannot use the fast internal save path")
	_check(journal.save_live_draft(live), "The registered engine can preserve its current rehearsal")
	_check(journal.save_draft({}) and not journal.save_live_draft(live), "Clearing a draft invalidates its previous live writer")
	live = journal.create_live_simulation()
	live.step({})
	live._checkpoint.players.p0.x += 8
	_check(not journal.save_live_draft(live), "Mutating a trusted checkpoint invalidates its live writer even if its hash is kept")

func _attempt_forks() -> void:
	var path := _path("fork")
	var journal := Journey.new(path)
	journal.load_data()
	_check(not journal.fork_from_stage(0), "An untouched checkpoint does not create an empty archive")
	_check(journal.accept_recording(pair.a) and journal.accept_recording(pair.b), "Fork source is a real completed first stage")
	var state_before: Dictionary = journal._state.duplicate(true)
	var bytes_before := FileAccess.get_file_as_string(path)
	_check(not journal.fork_from_stage(-1) and not journal.fork_from_stage(2), "Unavailable checkpoints cannot prune accepted progress")
	_check(FileAccess.get_file_as_string(path) == bytes_before, "Invalid fork writes nothing")
	_check(journal.fork_from_stage(0) and journal.role() == "a" and journal.pairs().is_empty(), "A new attempt returns to the requested checkpoint")
	var archive := path + ".attempt-" + Canonical.digest(state_before) + ".json"
	paths.append(archive)
	paths.append(archive + ".tmp")
	var archived: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(archive))
	_check(Canonical.same(archived.lighthouse, state_before), "Every replaced contribution is retained exactly in the earlier attempt")
	_check(Simulation.checkpoint_from_pairs(archived.lighthouse.pairs).valid, "Archived accepted evidence still replays independently")
	var archive_hash := FileAccess.get_sha256(archive)
	_check(journal.accept_recording(pair.a) and journal.accept_recording(pair.b) and journal.fork_from_stage(0), "Repeating the same evidence can reuse its identical immutable archive")
	_check(FileAccess.get_sha256(archive) == archive_hash, "A later fork cannot rewrite earlier attempt bytes")
	journal = Journey.new(path)
	journal.load_data()
	_check(journal.role() == "a" and journal.pairs().is_empty(), "The active fork survives restart separately from the archived attempt")
	_check(journal.archived_attempts().size() == 1 and Canonical.same(journal.archived_pairs(Canonical.digest(state_before)), state_before.pairs), "Archived Lighthouse replay is discoverable even before the first new stage")
	_check(journal.archived_pairs("../other").is_empty(), "Lighthouse archive selection cannot resolve arbitrary paths")
	var failing_path := _path("fork-write-failure")
	var storage := FailingStorage.new(failing_path)
	var failing := Journey.new(failing_path, storage)
	failing.load_data()
	failing.accept_recording(pair.a)
	state_before = failing._state.duplicate(true)
	storage.reject_write = true
	_check(not failing.fork_from_stage(0) and Canonical.same(failing.prior_recording(), pair.a), "A failed active write cannot replace the earlier contribution even after archiving")
	archive = failing_path + ".attempt-" + Canonical.digest(state_before) + ".json"
	paths.append(archive)
	paths.append(archive + ".tmp")
	_check(FileAccess.file_exists(archive), "The extra safe archive is retained after an active-write failure")
	storage.reject_write = false
	_write(archive, "corrupted existing archive")
	_check(not failing.fork_from_stage(0) and failing.role() == "b", "A conflicting earlier archive holds the fork and preserves the current turn")
	_check(FileAccess.get_file_as_string(archive) == "corrupted existing archive", "Fork never overwrites an unknown earlier archive")
	var capacity_path := _path("fork-capacity")
	var capacity := Journey.new(capacity_path)
	capacity.load_data()
	capacity.accept_recording(pair.a)
	for index in range(Journey.MAX_ARCHIVED_ATTEMPTS):
		var retained := capacity_path + ".attempt-retained-%d.json" % index
		paths.append(retained)
		_write(retained, "retained")
	_check(not capacity.fork_from_stage(0) and capacity.role() == "b", "Archive capacity holds progress instead of silently deleting old attempts")

class FailingStorage extends "res://services/local_save.gd":
	var reject_write := false
	func update_values(values: Dictionary, erase_keys: Array = []) -> bool:
		if reject_write:
			last_error = "Injected storage failure after archive."
			return false
		return super.update_values(values, erase_keys)

func _move(sim: RefCounted, target: Array) -> void:
	for _i in range(200):
		if sim.finished: return
		var state: Dictionary = sim.snapshot()
		var p: Dictionary = state.players[state.active_slot]
		var dx := int(target[0]) - int(p.x)
		var dz := int(target[1]) - int(p.z)
		if absi(dx) <= 4 and absi(dz) <= 4: return
		sim.step({"move_x": signi(dx) if absi(dx) > 4 else 0, "move_z": 0 if absi(dx) > 4 else signi(dz)})

func _path(label: String) -> String:
	var value := "user://test-lighthouse-journal-%d-%s.json" % [Time.get_ticks_usec(), label]
	for suffix: String in ["", ".tmp", ".backup"]: paths.append(value + suffix)
	return value

func _write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _finish() -> void:
	for path: String in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("LIGHTHOUSE JOURNAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
