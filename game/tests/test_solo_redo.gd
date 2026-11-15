extends SceneTree
## Solo Play my turn again in the shared chapter journey (relay_journey.gd
## begin_replace). It plays exactly the last accepted turn again: an accepted
## first turn, or the last saved stage's second turn with its first turn
## restored. Until a new turn is saved nothing is written and the saved turn
## stays; Keep it as it is, leaving or a reload keep it. The new turn replaces
## it in one write, a reopened stage's old attempt kept as an archive first.
## Rules, earlier pairs, keepsakes and untouched archives never change.
const Journey = preload("res://services/relay_journey.gd")
const Storage = preload("res://services/local_save.gd")
const Archive = preload("res://services/attempt_archive.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const Collection = preload("res://services/solo_replay_collection.gd")
const Index = preload("res://services/solo_replay_index.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Retained = preload("res://tests/retained_chapter_fixture.gd")
const Proofs = preload("res://services/journey_proofs.gd")

class FailingStorage extends "res://services/local_save.gd":
	var reject_write := false
	func update_values(values: Dictionary, erase_keys: Array = []) -> bool:
		if reject_write:
			last_error = "Injected replace write failure."
			return false
		return super.update_values(values, erase_keys)

class TrustSpy extends "res://services/relay_journey.gd":
	var trusted_calls: Array[bool] = []
	func _validate_state(value: Variant, trusted: Dictionary = {}) -> Dictionary:
		trusted_calls.append(not trusted.is_empty())
		return super(value, trusted)

var checks := 0
var failures := 0
var paths: Array[String] = []
var directory := "user://solo-redo-" + Crypto.new().generate_random_bytes(6).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	_nothing_to_play_again()
	_first_turn()
	_stage_and_chain()
	_stage_proof()
	_failed_write_and_retry()
	_unverified_draft()
	_drafts_in_memory()
	_archive_cap()
	_first_steps_rules()
	_keepsakes_survive()
	await _replay_collection()
	_family(Registry.WISHING_WELL, "cooperative")
	_family(Registry.TURN_OF_THE_TIDE, "journey")
	_cleanup()
	print("SOLO REDO: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _nothing_to_play_again() -> void:
	var path := _seeded("empty")
	var journey := Journey.new(path)
	_check(journey.redo_plan().is_empty(), "A journey that has not loaded offers nothing and reads nothing")
	journey.load_data()
	var bytes := _save_bytes(path)
	_check(journey.redo_plan().is_empty(), "Stage one with no saved turn has nothing to play again")
	_check(not journey.begin_replace({}) and not journey.begin_replace({"kind": "stage", "stage_index": 0, "pairs": 0}) and not journey.replacing(), "Playing again with nothing saved is refused")
	_check(Canonical.same(bytes, _save_bytes(path)) and _attempts(path).is_empty(), "A refused replace writes nothing")

func _first_turn() -> void:
	var path := _seeded("first")
	var journey := Journey.new(path)
	journey.load_data()
	_check(journey.accept_recording(_fixture("v2/relay-a")) and journey.save_draft(_fixture("v2/relay-b")), "Relay first turn accepted with a second-turn draft")
	var plan := journey.redo_plan()
	_check(plan.get("kind") == "first_turn" and plan.get("stage_index") == 0 and plan.get("pairs") == 0 and plan.get("drops_draft") == true, "An accepted first turn can be played again: " + str(plan))
	var stale := plan.duplicate()
	stale.turn = "0".repeat(64)
	var bytes := _save_bytes(path)
	var saved := journey._state.duplicate(true)
	_check(not journey.begin_replace(stale) and journey.last_error == PlayerCopy.LIGHTHOUSE_JOURNEY_66C3BEF32753 and not journey.replacing(), "An offer that no longer matches is refused")
	var version: int = journey.simulation_version()
	var checkpoint: Dictionary = journey.checkpoint()
	_check(journey.begin_replace(plan) and journey.replacing(), "The first turn is played again")
	_check(journey.role() == "a" and journey.stage_id() == "relay" and journey.pairs().is_empty() and journey.prior_recording().is_empty() and journey.draft().is_empty(), "It stands where the first turn was, with no draft")
	_check(journey.simulation_version() == version and version == 2 and Canonical.same(journey.checkpoint(), checkpoint), "Rules and checkpoint are unchanged")
	_check(Canonical.same(bytes, _save_bytes(path)) and _attempts(path).is_empty(), "Nothing is written while the turn is played again")
	_check(journey.redo_plan().is_empty() and not journey.begin_replace(plan), "A turn played again cannot be played again on top")
	var reopened := Journey.new(path)
	reopened.load_data()
	_check(not reopened.read_only and Canonical.same(reopened._state, saved), "Leaving keeps the saved turn and its draft")
	journey.end_replace()
	_check(not journey.replacing() and Canonical.same(journey._state, saved) and journey.role() == "b" and Canonical.same(journey.checkpoint(), checkpoint), "Keep it as it is goes back to the saved turn and its draft")
	_check(journey.begin_replace(journey.redo_plan()) and journey.accept_recording(_fixture("v2/relay-a")), "A new first turn is saved in its place")
	_check(not journey.replacing() and journey.role() == "b" and not journey.has_draft() and _attempts(path).is_empty(), "It replaces the old one, its draft gone, with no archive")
	reopened = Journey.new(path)
	reopened.load_data()
	_check(not reopened.read_only and Canonical.same(reopened._state, journey._state), "The replaced journal loads back through the full check")
	# An offer taken before another accepted turn is stale afterwards.
	var earlier := journey.redo_plan()
	_check(journey.accept_recording(_fixture("v2/relay-b")), "Accept the second turn")
	_check(not journey.begin_replace(earlier) and journey.pairs().size() == 1, "An offer from before a later save cannot play the wrong turn again")

func _stage_and_chain() -> void:
	var path := _seeded("stage")
	var journey := Journey.new(path)
	journey.load_data()
	var level := Registry.definition(Registry.RELAY)
	var family: Script = Registry.simulation_script(Registry.RELAY)
	var initial := Registry.initial_checkpoint(Registry.RELAY)
	for name: String in ["relay-a", "relay-b"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Accept " + name)
	var after_first := journey.checkpoint()
	var saved_stage := journey._state.duplicate(true)
	var plan := journey.redo_plan()
	_check(plan.get("kind") == "stage" and plan.get("stage_index") == 0 and plan.get("drops_draft") == false, "A saved stage can be played again: " + str(plan))
	_check(journey.begin_replace(plan), "Stage one reopens")
	_check(journey.role() == "b" and journey.stage_id() == "relay" and journey.pairs().is_empty() and Canonical.same(journey.prior_recording(), _fixture("v2/relay-a")) and journey.draft().is_empty(), "Its second turn is open again with its first turn restored")
	_check(Canonical.same(journey.checkpoint(), initial) and _attempts(path).is_empty(), "The checkpoint is the stage's start, and nothing is archived yet")
	_check(journey.accept_recording(_fixture("v2/relay-b")), "A new second turn is saved")
	_check(Canonical.same(Archive.load_attempt(path, "relay", Canonical.digest(saved_stage), Journey.MAX_SAVE_BYTES), saved_stage), "The replaced attempt is archived exactly, keyed by its content")
	_check(journey.simulation_version() == 2 and Canonical.same(journey.checkpoint(), after_first), "An older-rules journal keeps its rules and reaches the same checkpoint")
	_check(journey.accept_recording(_fixture("v2/garden-a")), "Accept garden-a")
	plan = journey.redo_plan()
	_check(plan.get("kind") == "first_turn" and plan.get("stage_index") == 1 and journey.begin_replace(plan), "Stage two's first turn can be played again")
	_check(journey.role() == "a" and journey.stage_id() == "garden" and journey.pairs().size() == 1 and Canonical.same(journey.checkpoint(), after_first), "Stage one stays saved with the same checkpoint")
	for name: String in ["garden-a", "garden-b"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Finish " + name)
	_check(journey.chapter_complete(), "The chapter is complete")
	var complete := journey._state.duplicate(true)
	plan = journey.redo_plan()
	_check(plan.get("kind") == "stage" and plan.get("stage_index") == 1 and journey.begin_replace(plan), "The final stage reopens from the completed chapter")
	var derived: Dictionary = family.derive_checkpoint(level, initial, _fixture("v2/relay-a"), _fixture("v2/relay-b"))
	_check(not journey.chapter_complete() and journey.role() == "b" and journey.stage_id() == "garden" and Canonical.same(journey.prior_recording(), _fixture("v2/garden-a")), "Playing the last turn again leaves the chapter unfinished at that turn")
	_check(derived.get("valid", false) and Canonical.same(journey.checkpoint(), derived.checkpoint), "Its checkpoint equals derive_checkpoint over the kept prefix")
	journey.end_replace()
	_check(journey.chapter_complete() and Canonical.same(journey._state, complete), "Keep it as it is puts the finished chapter back")
	_check(journey.begin_replace(journey.redo_plan()) and journey.accept_recording(_fixture("v2/garden-b")) and journey.chapter_complete(), "Saving the last turn again finishes it again")
	_check(Canonical.same(Archive.load_attempt(path, "relay", Canonical.digest(complete), Journey.MAX_SAVE_BYTES), complete), "The completed attempt is archived exactly")
	_check(journey.archived_attempts().size() == 2, "Each replaced stage left one replayable archive")
	var reopened := Journey.new(path)
	reopened.load_data()
	_check(not reopened.read_only and Canonical.same(reopened._state, journey._state) and Canonical.same(reopened.checkpoint(), journey.checkpoint()), "A fresh load validates the same state")
	# Start over: only a whole-chapter restart moves an older journal to new rules.
	_check(journey.begin_replace(journey.redo_plan()) and journey.fork_from_stage(0) and not journey.replacing() and journey.simulation_version() == Registry.preferred_rules(Registry.RELAY), "Start over ends a turn played again and upgrades the rules as before")

## Reopening a stage restores a state proven when its first turn was saved,
## so it reuses that proof; with nothing remembered it replays in full.
func _stage_proof() -> void:
	var results: Array[Dictionary] = []
	for remembered: bool in [true, false]:
		var path := _seeded("proof-" + str(remembered))
		var journey := TrustSpy.new(path)
		journey.load_data()
		for name: String in ["relay-a", "relay-b"]:
			_check(journey.accept_recording(_fixture("v2/" + name)), "Proof fixture accepts " + name)
		var plan := journey.redo_plan()
		var saved_directory: String = Proofs.directory
		if not remembered: Proofs.directory = directory.path_join("no-proofs")
		journey.trusted_calls.clear()
		_check(journey.begin_replace(plan), "The stage reopens (%s)" % ("remembered" if remembered else "nothing remembered"))
		Proofs.directory = saved_directory
		var expected: Array[bool] = [remembered]
		_check(journey.trusted_calls == expected, "The reopened state is checked %s: %s" % ["once from the remembered proof" if remembered else "once in full", str(journey.trusted_calls)])
		results.append({"state": journey._state.duplicate(true), "checkpoint": journey.checkpoint()})
	_check(Canonical.same(results[0], results[1]), "Both ways reach the same state and checkpoint")

## A failed write of the new turn leaves the saved turn on disk and the turn
## still being played again; a retry reuses the archive it made.
func _failed_write_and_retry() -> void:
	var path := _seeded("failed")
	var storage := FailingStorage.new(path)
	var journey := Journey.new(path, storage)
	journey.load_data()
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Failure fixture accepts " + name)
	var complete := journey._state.duplicate(true)
	var bytes := _save_bytes(path)
	storage.reject_write = true
	_check(journey.begin_replace(journey.redo_plan()), "Playing a turn again needs no write")
	_check(not journey.accept_recording(_fixture("v2/garden-b")) and journey.replacing() and journey.role() == "b", "A failed write keeps the turn being played again")
	_check(Canonical.same(bytes, _save_bytes(path)), "A failed write keeps every saved generation")
	var archive := path + ".attempt-" + Canonical.digest(complete) + ".json"
	var archive_hash := FileAccess.get_sha256(archive)
	_check(not archive_hash.is_empty(), "The archive written before the failed save is kept")
	storage.reject_write = false
	_check(journey.accept_recording(_fixture("v2/garden-b")) and not journey.replacing() and journey.chapter_complete(), "Retrying saves the same turn")
	_check(FileAccess.get_sha256(archive) == archive_hash and _attempts(path).size() == 1, "The retry reuses the same archive and writes no second copy")

## A reopened journal checks its saved draft only on Resume. Playing a turn
## again sets that draft aside without replaying it, and Keep it as it is
## brings it back still unchecked.
func _unverified_draft() -> void:
	var path := _seeded("unverified")
	var journey := Journey.new(path)
	journey.load_data()
	_check(journey.accept_recording(_fixture("v2/relay-a")) and journey.save_draft(_fixture("v2/relay-b")), "A first turn and a second-turn draft are saved")
	var reopened := Journey.new(path)
	reopened.load_data()
	_check(not reopened.read_only and reopened.has_draft() and not reopened._draft_replay_verified, "The reopened draft waits for Resume to be checked")
	var plan := reopened.redo_plan()
	_check(plan.get("kind") == "first_turn" and plan.get("drops_draft") == true and reopened.begin_replace(plan), "The first turn of a reopened journal is played again")
	_check(not reopened.read_only and not reopened.has_draft() and reopened._draft_replay_verified and reopened.role() == "a", "No unchecked draft stands while it is played again")
	reopened.end_replace()
	_check(reopened.has_draft() and not reopened._draft_replay_verified and reopened.role() == "b", "Keep it as it is brings the draft back, still to be checked on Resume")

## Drafts of a turn played again stay in memory: pause keeps one, a periodic
## save skips, and nothing reaches the journal until the turn is saved.
func _drafts_in_memory() -> void:
	var path := _seeded("drafts")
	var journey := Journey.new(path)
	journey.load_data()
	_check(journey.accept_recording(_fixture("v2/relay-a")), "Drafts fixture accepts the first turn")
	var bytes := _save_bytes(path)
	_check(journey.begin_replace(journey.redo_plan()), "The first turn is played again")
	var live: RefCounted = journey.create_live_simulation()
	var inputs: Array = Registry.simulation_script(Registry.RELAY).expand_recording_inputs(_fixture("v2/relay-a"))
	for input: Dictionary in inputs.slice(0, 20): live.step(input)
	_check(journey.save_live_draft(live, true) and not journey.has_draft(), "A periodic save of a turn played again is skipped")
	_check(journey.save_live_draft(live) and journey.has_draft() and int(journey.draft().get("duration_ticks", -1)) >= 0, "A pause keeps its draft in memory")
	_check(journey.save_draft(_fixture("v2/relay-a")) and journey.has_draft(), "An explicit draft is kept in memory too")
	_check(Canonical.same(bytes, _save_bytes(path)), "No draft of a turn played again is written")
	_check(journey.create_live_simulation(true) != null, "Resume sets the turn up from the draft in memory")

func _archive_cap() -> void:
	var path := _seeded("cap")
	var journey := Journey.new(path)
	journey.load_data()
	for name: String in ["relay-a", "relay-b"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Cap fixture accepts " + name)
	var plan := journey.redo_plan()
	_check(plan.get("kind") == "stage", "Below the archive limit a stage can be played again")
	var fillers: Array[String] = []
	for index in range(Journey.MAX_ARCHIVED_ATTEMPTS):
		var filler := path + ".attempt-" + Crypto.new().generate_random_bytes(32).hex_encode() + ".json"
		var file := FileAccess.open(filler, FileAccess.WRITE)
		file.store_string("{}")
		file.close()
		fillers.append(filler)
	var bytes := _save_bytes(path)
	var state := journey._state.duplicate(true)
	_check(journey.redo_plan().is_empty() and Archive.full(path, journey._state, Journey.MAX_ARCHIVED_ATTEMPTS), "At the archive limit a stage is not offered")
	_check(not journey.begin_replace(plan) and journey.last_error == PlayerCopy.LIGHTHOUSE_JOURNEY_66C3BEF32753, "An offer made before the limit is refused as no longer current")
	_check(Canonical.same(journey._state, state) and Canonical.same(bytes, _save_bytes(path)) and _attempts(path).size() == Journey.MAX_ARCHIVED_ATTEMPTS, "The refused replace leaves the journey and archives unchanged")
	DirAccess.remove_absolute(fillers.pop_back())
	_check(Archive.save(path, "relay", journey._state, Journey.MAX_SAVE_BYTES, Journey.MAX_ARCHIVED_ATTEMPTS).is_empty() and _attempts(path).size() == Journey.MAX_ARCHIVED_ATTEMPTS, "This exact attempt archived ahead fills the last place")
	plan = journey.redo_plan()
	_check(not Archive.full(path, journey._state, Journey.MAX_ARCHIVED_ATTEMPTS) and plan.get("kind") == "stage" and journey.begin_replace(plan) and journey.accept_recording(_fixture("v2/relay-b")) and _attempts(path).size() == Journey.MAX_ARCHIVED_ATTEMPTS, "An attempt already kept needs no room, so its stage is played again at the limit")
	_check(journey.accept_recording(_fixture("v2/garden-a")), "A first turn is saved at the limit")
	_check(journey.begin_replace(journey.redo_plan()) and journey.accept_recording(_fixture("v2/garden-a")) and journey.role() == "b" and journey.pairs().size() == 1, "A first turn is still played again at the limit")

func _first_steps_rules() -> void:
	var path := _seeded("first-steps", Registry.FIRST_STEPS)
	var journey := Journey.new(path, null, Registry.FIRST_STEPS)
	journey.load_data()
	var envelope: int = journey.simulation_version()
	for name: String in ["cumulative-lift-a", "cumulative-lift-b"]:
		_check(journey.accept_recording(_fixture("first_steps/" + name)), "First Steps accepts " + name)
	var plan := journey.redo_plan()
	_check(plan.get("kind") == "stage" and journey.begin_replace(plan), "First Steps reopens its first stage")
	_check(journey.simulation_version() == envelope and int(journey.prior_recording().get("simulation_version", -1)) == 5, "The authored envelope stays and the restored first turn keeps its own rules")
	var live: RefCounted = journey.create_live_simulation()
	_check(live != null and int(live.simulation_version) == 5, "The second turn is set up under the restored first turn's rules")
	_check(journey.accept_recording(_fixture("first_steps/cumulative-lift-b")) and journey.pairs().size() == 1, "The same second turn can be saved again")
	var reopened := Journey.new(path, null, Registry.FIRST_STEPS)
	reopened.load_data()
	_check(not reopened.read_only and Canonical.same(reopened._state, journey._state), "The First Steps journal loads back unchanged")

func _keepsakes_survive() -> void:
	Keepsakes._unclaimed.clear()
	var ledger := Keepsakes.new(directory.path_join("ledger.json"))
	ledger.load_data()
	ledger.activate()
	var path := _seeded("keepsakes")
	var journey := Journey.new(path)
	journey.load_data()
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Keepsake fixture accepts " + name)
	_check(_mark(ledger, "relay-isles/relay") and _mark(ledger, "relay-isles/garden"), "Both saved stages earned their solo keepsakes")
	var generation: int = ledger._storage.data.generation
	var ledger_bytes := FileAccess.get_file_as_bytes(directory.path_join("ledger.json"))
	_check(journey.begin_replace(journey.redo_plan()), "The last stage is played again")
	journey.end_replace()
	_check(_mark(ledger, "relay-isles/relay") and _mark(ledger, "relay-isles/garden"), "Playing a turn again never revokes an earned keepsake")
	_check(ledger._storage.data.generation == generation and FileAccess.get_file_as_bytes(directory.path_join("ledger.json")) == ledger_bytes, "Playing a turn again writes no keepsake generation")
	_check(journey.begin_replace(journey.redo_plan()) and journey.accept_recording(_fixture("v2/garden-b")), "The last stage is saved again")
	_check(_mark(ledger, "relay-isles/relay") and _mark(ledger, "relay-isles/garden"), "Saving it again keeps both keepsakes")
	ledger.deactivate()

## Playing a turn again writes neither the journal nor the replay index; once
## the new turn is saved, the replaced attempt's rows join the archived ones
## and the current rows keep their ids.
func _replay_collection() -> void:
	var path := _seeded("collection")
	var verified := directory.path_join("verified.json")
	var journey := Journey.new(path)
	journey.load_data()
	for name: String in ["relay-a", "relay-b"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Collection fixture accepts " + name)
	var untouched := journey._state.duplicate(true)
	_check(Archive.save(path, "relay", untouched, Journey.MAX_SAVE_BYTES, Journey.MAX_ARCHIVED_ATTEMPTS).is_empty(), "An earlier archive exists")
	for name: String in ["garden-a", "garden-b"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Collection fixture accepts " + name)
	var sources := {Registry.RELAY: path}
	Collection._verified.clear()
	var before := Collection.new(sources, verified)
	await _drain(before)
	var rows_before := before.items()
	var current_before: Array[Dictionary] = rows_before.filter(func(row: Dictionary) -> bool: return not row.archived)
	_check(current_before.size() == 2 and rows_before.size() == 3, "Before: two current rows and the earlier archive's row")
	var index_path := directory.path_join("index.json")
	var index := Index.new(index_path)
	_check(index.store_display(before.settled_items(false), before.pending_chapters()), "The replay index holds the scan from before")
	var index_bytes := FileAccess.get_file_as_bytes(index_path)
	var journal_bytes := _save_bytes(path)
	_check(journey.begin_replace(journey.redo_plan()), "Reopen the final stage")
	_check(FileAccess.get_file_as_bytes(index_path) == index_bytes and Canonical.same(journal_bytes, _save_bytes(path)), "Playing a turn again writes neither the journal nor the replay index")
	_check(journey.accept_recording(_fixture("v2/garden-b")), "Save the last turn again")
	Collection._verified.clear()
	var after := Collection.new(sources, verified)
	await _drain(after)
	var rows := after.items()
	var current: Array[Dictionary] = rows.filter(func(row: Dictionary) -> bool: return not row.archived)
	var archived: Array[Dictionary] = rows.filter(func(row: Dictionary) -> bool: return row.archived)
	_check(current.map(func(row: Dictionary) -> String: return str(row.id)) == current_before.map(func(row: Dictionary) -> String: return str(row.id)), "The current rows keep their ids")
	_check(archived.size() == 3, "The replaced attempt's two rows join the earlier archive's row")
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(verified + suffix): DirAccess.remove_absolute(verified + suffix)

func _family(chapter: String, folder: String) -> void:
	if not Registry.keys().has(chapter):
		_check(false, chapter + " is registered")
		return
	var level := Registry.definition(chapter)
	var names: Array = level.stages.map(func(stage: Dictionary) -> String: return str(stage.id))
	var path := directory.path_join(chapter.validate_filename() + ".json")
	paths.append(path)
	var journey := Journey.new(path, null, chapter)
	journey.load_data()
	var version: int = journey.simulation_version()
	var started := Time.get_ticks_msec()
	_check(journey.accept_recording(_fixture(folder + "/" + names[0] + "-a")), chapter + ": first turn accepted")
	var plan := journey.redo_plan()
	_check(plan.get("kind") == "first_turn" and journey.begin_replace(plan) and journey.role() == "a" and journey.pairs().is_empty(), chapter + ": the first turn is played again")
	for index in range(names.size()):
		for role: String in ["a", "b"]:
			_check(journey.accept_recording(_fixture(folder + "/" + names[index] + "-" + role)), "%s: accept %s-%s" % [chapter, names[index], role])
	_check(journey.chapter_complete(), chapter + ": complete")
	var complete := journey._state.duplicate(true)
	plan = journey.redo_plan()
	_check(plan.get("kind") == "stage" and plan.get("stage_index") == names.size() - 1 and journey.begin_replace(plan), chapter + ": the last stage reopens")
	_check(journey.role() == "b" and journey.stage_id() == names[-1] and Canonical.same(journey.prior_recording(), _fixture(folder + "/" + names[-1] + "-a")), chapter + ": its first turn is restored")
	_check(journey.accept_recording(_fixture(folder + "/" + names[-1] + "-b")) and journey.chapter_complete(), chapter + ": the same last turn completes it again")
	_check(journey.simulation_version() == version and Canonical.same(Archive.load_attempt(path, "relay", Canonical.digest(complete), Journey.MAX_SAVE_BYTES), complete), chapter + ": rules unchanged and the completed attempt archived")
	var reopened := Journey.new(path, null, chapter)
	reopened.load_data()
	_check(not reopened.read_only and Canonical.same(reopened._state, journey._state), chapter + ": the journal loads back unchanged")
	print("%s replace checks took %d ms" % [chapter, Time.get_ticks_msec() - started])

func _drain(service: RefCounted) -> void:
	service.begin_scan()
	var deadline := Time.get_ticks_msec() + 20000
	while service.scan_pending() and Time.get_ticks_msec() < deadline:
		service.advance_scan()
		await process_frame

func _mark(ledger: RefCounted, id: String) -> bool:
	for row: Dictionary in ledger.earned_descriptors():
		if row.id == id: return row.solo
	return false

func _seeded(label: String, chapter: String = Registry.RELAY) -> String:
	var path := directory.path_join(label + ".json")
	paths.append(path)
	_check(Retained.seed(path, chapter), "Seed the published older journal for " + label)
	return path

func _attempts(path: String) -> Array[String]:
	var found: Array[String] = []
	for filename: String in DirAccess.get_files_at(path.get_base_dir()):
		if filename.begins_with(path.get_file() + ".attempt-") and filename.ends_with(".json"): found.append(filename)
	return found

func _save_bytes(path: String) -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".tmp", ".backup"]:
		result[suffix] = FileAccess.get_file_as_bytes(path + suffix) if FileAccess.file_exists(path + suffix) else null
	return result

func _fixture(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + name + ".json"))
	if not value is Dictionary:
		_check(false, "Fixture is readable: " + name)
		return {}
	return value

func _cleanup() -> void:
	var proofs := directory.path_join("no-proofs")
	if DirAccess.dir_exists_absolute(proofs):
		for filename: String in DirAccess.get_files_at(proofs):
			DirAccess.remove_absolute(proofs.path_join(filename))
		DirAccess.remove_absolute(proofs)
	for filename: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)
