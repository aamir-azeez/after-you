extends SceneTree
## Solo "Redo my previous turn" in the shared chapter journey. Each step takes
## back exactly one accepted turn: an accepted first turn is cleared, or the
## last saved stage reopens at its second turn with its first turn restored.
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
const Offer = preload("res://presentation/solo_redo_offer.gd")
const Retained = preload("res://tests/retained_chapter_fixture.gd")

class FailingStorage extends "res://services/local_save.gd":
	var reject_write := false
	func update_values(values: Dictionary, erase_keys: Array = []) -> bool:
		if reject_write:
			last_error = "Injected redo write failure."
			return false
		return super.update_values(values, erase_keys)

class CountingRelay extends "res://services/relay_journey.gd":
	static var calls := 0
	func _validate_state(value: Variant, trusted: Dictionary = {}) -> Dictionary:
		calls += 1
		return super(value, trusted)

class Counting extends "res://services/solo_replay_collection.gd":
	func _validator(job: Dictionary) -> RefCounted:
		return CountingRelay.new(str(job.path), null, str(job.chapter))

var checks := 0
var failures := 0
var paths: Array[String] = []
var directory := "user://solo-redo-" + Crypto.new().generate_random_bytes(6).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	_nothing_to_redo()
	_first_turn()
	_stage_and_chain()
	_failed_write_and_retry()
	_unverified_draft()
	_archive_cap()
	_first_steps_rules()
	_offer_copy()
	_keepsakes_survive()
	await _replay_collection()
	_family(Registry.WISHING_WELL, "cooperative")
	_family(Registry.TURN_OF_THE_TIDE, "journey")
	_cleanup()
	print("SOLO REDO: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _nothing_to_redo() -> void:
	var path := _seeded("empty")
	var journey := Journey.new(path)
	_check(journey.redo_plan().is_empty(), "A journey that has not loaded offers nothing and reads nothing")
	journey.load_data()
	var bytes := _save_bytes(path)
	_check(journey.redo_plan().is_empty(), "Stage one with no saved turn has nothing to redo")
	_check(not journey.redo_previous({}) and not journey.redo_previous({"kind": "stage", "stage_index": 0, "pairs": 0}), "Redo with nothing saved is refused")
	_check(Canonical.same(bytes, _save_bytes(path)) and _attempts(path).is_empty(), "A refused redo writes nothing")

func _first_turn() -> void:
	var path := _seeded("first")
	var journey := Journey.new(path)
	journey.load_data()
	_check(journey.accept_recording(_fixture("v2/relay-a")) and journey.save_draft(_fixture("v2/relay-b")), "Relay first turn accepted with a second-turn draft")
	var plan := journey.redo_plan()
	_check(plan.get("kind") == "first_turn" and plan.get("stage_index") == 0 and plan.get("pairs") == 0 and plan.get("drops_draft") == true, "An accepted first turn offers the first-turn redo and names the draft it drops: " + str(plan))
	var stale := plan.duplicate()
	stale.turn = "0".repeat(64)
	var bytes := _save_bytes(path)
	_check(not journey.redo_previous(stale) and journey.last_error == PlayerCopy.LIGHTHOUSE_JOURNEY_66C3BEF32753 and Canonical.same(bytes, _save_bytes(path)), "An offer that no longer matches is refused without writing")
	var version: int = journey.simulation_version()
	var checkpoint: Dictionary = journey.checkpoint()
	_check(journey.redo_previous(plan), "The first-turn redo is accepted")
	_check(journey.role() == "a" and journey.stage_id() == "relay" and journey.pairs().is_empty() and journey.prior_recording().is_empty() and journey.draft().is_empty(), "The first turn and its draft are cleared on the same stage")
	_check(journey.simulation_version() == version and version == 2 and Canonical.same(journey.checkpoint(), checkpoint), "Rules and checkpoint are unchanged")
	_check(_attempts(path).is_empty(), "Clearing a first turn keeps no archive")
	_check(journey.redo_plan().is_empty(), "Back at the start, nothing is left to redo")
	var reopened := Journey.new(path)
	reopened.load_data()
	_check(not reopened.read_only and Canonical.same(reopened._state, journey._state), "The redone journal loads back through the full check")
	# An offer taken before another accepted turn is stale afterwards.
	_check(journey.accept_recording(_fixture("v2/relay-a")), "Accept the first turn again")
	var earlier := journey.redo_plan()
	_check(journey.accept_recording(_fixture("v2/relay-b")), "Accept the second turn")
	_check(not journey.redo_previous(earlier) and journey.pairs().size() == 1, "An offer from before a later save cannot take back the wrong turn")

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
	_check(plan.get("kind") == "stage" and plan.get("stage_index") == 0 and plan.get("drops_draft") == false, "A saved stage offers to reopen it: " + str(plan))
	_check(journey.redo_previous(plan), "Reopening stage one is accepted")
	_check(journey.role() == "b" and journey.stage_id() == "relay" and journey.pairs().is_empty() and Canonical.same(journey.prior_recording(), _fixture("v2/relay-a")) and journey.draft().is_empty(), "The second turn is taken back and the first turn restored")
	_check(Canonical.same(journey.checkpoint(), initial), "The checkpoint returns to the start of that stage")
	_check(Canonical.same(Archive.load_attempt(path, "relay", Canonical.digest(saved_stage), Journey.MAX_SAVE_BYTES), saved_stage), "The reopened attempt is archived exactly, keyed by its content")
	_check(journey.simulation_version() == 2, "An older-rules journal keeps its rules when its first stage reopens")
	var step := journey.redo_plan()
	_check(step.get("kind") == "first_turn" and journey.redo_previous(step) and journey.role() == "a" and journey.prior_recording().is_empty(), "A second redo clears the restored first turn")
	_check(journey.simulation_version() == 2, "Stepping back to the start keeps the rules (a whole-chapter restart is the only upgrade)")
	for name: String in ["relay-a", "relay-b", "garden-a"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Accept again " + name)
	plan = journey.redo_plan()
	_check(plan.get("kind") == "first_turn" and plan.get("stage_index") == 1 and journey.redo_previous(plan), "Stage two's first turn can be taken back")
	_check(journey.role() == "a" and journey.stage_id() == "garden" and journey.pairs().size() == 1 and Canonical.same(journey.checkpoint(), after_first), "Stage one stays saved with the same checkpoint")
	for name: String in ["garden-a", "garden-b"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Finish " + name)
	_check(journey.chapter_complete(), "The chapter is complete")
	var complete := journey._state.duplicate(true)
	plan = journey.redo_plan()
	_check(plan.get("kind") == "stage" and plan.get("stage_index") == 1 and journey.redo_previous(plan), "The final stage reopens from the completed chapter")
	var derived: Dictionary = family.derive_checkpoint(level, initial, _fixture("v2/relay-a"), _fixture("v2/relay-b"))
	_check(not journey.chapter_complete() and journey.role() == "b" and journey.stage_id() == "garden" and Canonical.same(journey.prior_recording(), _fixture("v2/garden-a")), "Redo after completion leaves the chapter unfinished at the last second turn")
	_check(derived.get("valid", false) and Canonical.same(journey.checkpoint(), derived.checkpoint), "Its checkpoint equals derive_checkpoint over the kept prefix")
	_check(Canonical.same(Archive.load_attempt(path, "relay", Canonical.digest(complete), Journey.MAX_SAVE_BYTES), complete), "The completed attempt is archived exactly")
	_check(journey.archived_attempts().size() == 2, "Each reopened stage left one replayable archive")
	var reopened := Journey.new(path)
	reopened.load_data()
	_check(not reopened.read_only and Canonical.same(reopened._state, journey._state) and Canonical.same(reopened.checkpoint(), journey.checkpoint()), "A fresh load after redo validates the same state")
	# Contrast: only a whole-chapter restart moves an older journal to new rules.
	_check(journey.fork_from_stage(0) and journey.simulation_version() == Registry.preferred_rules(Registry.RELAY), "A whole-chapter restart still upgrades the rules as before")

func _failed_write_and_retry() -> void:
	var path := _seeded("failed")
	var storage := FailingStorage.new(path)
	var journey := Journey.new(path, storage)
	journey.load_data()
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Failure fixture accepts " + name)
	var complete := journey._state.duplicate(true)
	var bytes := _save_bytes(path)
	var plan := journey.redo_plan()
	storage.reject_write = true
	_check(not journey.redo_previous(plan) and journey.chapter_complete() and Canonical.same(journey._state, complete), "A failed write leaves the completed journey intact")
	_check(Canonical.same(bytes, _save_bytes(path)), "A failed write keeps every saved generation")
	var archive := path + ".attempt-" + Canonical.digest(complete) + ".json"
	var archive_hash := FileAccess.get_sha256(archive)
	_check(not archive_hash.is_empty(), "The archive written before the failed save is kept")
	storage.reject_write = false
	_check(journey.redo_previous(plan) and journey.role() == "b" and journey.pairs().size() == 1, "Retrying after the interruption completes the same redo")
	_check(FileAccess.get_sha256(archive) == archive_hash and _attempts(path).size() == 1, "The retry reuses the same archive and writes no second copy")
	storage.reject_write = true
	var role_b := journey._state.duplicate(true)
	_check(not journey.redo_previous(journey.redo_plan()) and Canonical.same(journey._state, role_b) and journey.role() == "b", "A failed first-turn write keeps the first turn")
	storage.reject_write = false

## A reopened journal checks its saved draft only on Resume. Redo drops that
## draft without replaying it, and leaves no draft behind to check.
func _unverified_draft() -> void:
	var path := _seeded("unverified")
	var journey := Journey.new(path)
	journey.load_data()
	_check(journey.accept_recording(_fixture("v2/relay-a")) and journey.save_draft(_fixture("v2/relay-b")), "A first turn and a second-turn draft are saved")
	var reopened := Journey.new(path)
	reopened.load_data()
	_check(not reopened.read_only and reopened.has_draft() and not reopened._draft_replay_verified, "The reopened draft waits for Resume to be checked")
	var plan := reopened.redo_plan()
	_check(plan.get("kind") == "first_turn" and plan.get("drops_draft") == true and reopened.redo_previous(plan), "Redo takes back the first turn of a reopened journal")
	_check(not reopened.read_only and not reopened.has_draft() and reopened._draft_replay_verified and reopened.draft().is_empty() and reopened.role() == "a", "No unchecked draft is left after redo")
	var again := Journey.new(path)
	again.load_data()
	_check(not again.read_only and Canonical.same(again._state, reopened._state), "The redone journal loads back unchanged")
	for name: String in ["relay-a", "relay-b"]:
		_check(again.accept_recording(_fixture("v2/" + name)), "Unverified-draft fixture accepts " + name)
	_check(again.save_draft(_fixture("v2/garden-a")), "A first-turn draft is saved on stage two")
	var third := Journey.new(path)
	third.load_data()
	_check(third.has_draft() and not third._draft_replay_verified, "The stage-two draft waits for Resume to be checked")
	plan = third.redo_plan()
	_check(plan.get("kind") == "stage" and plan.get("drops_draft") == true and third.redo_previous(plan), "Reopening stage one drops the unchecked stage-two draft")
	_check(third.role() == "b" and third.pairs().is_empty() and not third.has_draft() and third._draft_replay_verified and Canonical.same(third.prior_recording(), _fixture("v2/relay-a")), "Stage one is open at its second turn with no draft")

func _archive_cap() -> void:
	var path := _seeded("cap")
	var journey := Journey.new(path)
	journey.load_data()
	for name: String in ["relay-a", "relay-b"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Cap fixture accepts " + name)
	for index in range(Journey.MAX_ARCHIVED_ATTEMPTS):
		var filler := path + ".attempt-" + Crypto.new().generate_random_bytes(32).hex_encode() + ".json"
		var file := FileAccess.open(filler, FileAccess.WRITE)
		file.store_string("{}")
		file.close()
	var bytes := _save_bytes(path)
	var state := journey._state.duplicate(true)
	_check(not journey.redo_previous(journey.redo_plan()) and journey.last_error == PlayerCopy.LIGHTHOUSE_JOURNEY_28364B9E3ABB, "At the archive limit reopening a stage is refused with the existing message")
	_check(Canonical.same(journey._state, state) and Canonical.same(bytes, _save_bytes(path)) and _attempts(path).size() == Journey.MAX_ARCHIVED_ATTEMPTS, "The refused redo leaves the journey and archives unchanged")
	_check(journey.accept_recording(_fixture("v2/garden-a")), "Accept a first turn at the limit")
	_check(journey.redo_previous(journey.redo_plan()) and journey.role() == "a" and journey.pairs().size() == 1, "Clearing a first turn still works at the limit")

func _first_steps_rules() -> void:
	var path := _seeded("first-steps", Registry.FIRST_STEPS)
	var journey := Journey.new(path, null, Registry.FIRST_STEPS)
	journey.load_data()
	var envelope: int = journey.simulation_version()
	for name: String in ["cumulative-lift-a", "cumulative-lift-b"]:
		_check(journey.accept_recording(_fixture("first_steps/" + name)), "First Steps accepts " + name)
	var plan := journey.redo_plan()
	_check(plan.get("kind") == "stage" and journey.redo_previous(plan), "First Steps reopens its first stage")
	_check(journey.simulation_version() == envelope and int(journey.prior_recording().get("simulation_version", -1)) == 5, "The authored envelope stays and the restored first turn keeps its own rules")
	var live: RefCounted = journey.create_live_simulation()
	_check(live != null and int(live.simulation_version) == 5, "The second turn is set up under the restored first turn's rules")
	_check(journey.accept_recording(_fixture("first_steps/cumulative-lift-b")) and journey.pairs().size() == 1, "The same second turn can be saved again")
	var reopened := Journey.new(path, null, Registry.FIRST_STEPS)
	reopened.load_data()
	_check(not reopened.read_only and Canonical.same(reopened._state, journey._state), "The First Steps journal loads back unchanged")

func _offer_copy() -> void:
	_check(Offer.confirm_copy({}).is_empty() and Offer.confirm_copy({"kind": "other"}).is_empty(), "No offer copy without a plan")
	var first := Offer.confirm_copy({"kind": "first_turn", "stage_index": 0, "drops_draft": false})
	_check(first.title == PlayerCopy.SOLO_REDO_FIRST_TURN_TITLE and first.body == PlayerCopy.SOLO_REDO_FIRST_TURN_BODY, "Stage one's first-turn copy does not mention earlier stages")
	var later := Offer.confirm_copy({"kind": "first_turn", "stage_index": 1, "drops_draft": true})
	_check(later.body.contains(PlayerCopy.SOLO_REDO_KEEPS_EARLIER) and later.body.contains(PlayerCopy.SOLO_REDO_DROPS_DRAFT), "A later first turn mentions the kept stages and the dropped draft")
	var stage := Offer.confirm_copy({"kind": "stage", "stage_index": 1, "drops_draft": false})
	_check(stage.title == "Go back to stage 2?" and stage.body == PlayerCopy.SOLO_REDO_STAGE_BODY, "The stage copy names the stage by its displayed number")
	for text: String in [PlayerCopy.SOLO_REDO_ACTION, first.title, first.body, later.body, stage.title, stage.body]:
		_check(not text.contains("—") and not text.contains("–") and not text.contains("  "), "Offer copy is plain: " + text)

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
	for step in range(4):
		var plan := journey.redo_plan()
		_check(not plan.is_empty() and journey.redo_previous(plan), "Redo step %d" % step)
	_check(journey.pairs().is_empty() and journey.prior_recording().is_empty(), "Every saved turn has been taken back")
	_check(_mark(ledger, "relay-isles/relay") and _mark(ledger, "relay-isles/garden"), "Redo never revokes an earned keepsake")
	_check(ledger._storage.data.generation == generation and FileAccess.get_file_as_bytes(directory.path_join("ledger.json")) == ledger_bytes, "Redo writes no keepsake generation")
	var reopened := Keepsakes.new(directory.path_join("ledger.json"))
	reopened.load_data()
	_check(reopened.earned_descriptors() == ledger.earned_descriptors(), "Keepsakes read back the same after redo")
	ledger.deactivate()

func _replay_collection() -> void:
	var path := _seeded("collection")
	var verified := directory.path_join("verified.json")
	var journey := Journey.new(path)
	journey.load_data()
	for name: String in ["relay-a", "relay-b"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Collection fixture accepts " + name)
	var untouched := journey._state.duplicate(true)
	_check(Archive.save(path, "relay", untouched, Journey.MAX_SAVE_BYTES, Journey.MAX_ARCHIVED_ATTEMPTS).is_empty(), "An earlier archive exists before redo")
	for name: String in ["garden-a", "garden-b"]:
		_check(journey.accept_recording(_fixture("v2/" + name)), "Collection fixture accepts " + name)
	var sources := {Registry.RELAY: path}
	Collection._verified.clear()
	var before := Collection.new(sources, verified)
	await _drain(before)
	var rows_before := before.items()
	var current_before: Array[Dictionary] = rows_before.filter(func(row: Dictionary) -> bool: return not row.archived)
	var untouched_before: Array[Dictionary] = rows_before.filter(func(row: Dictionary) -> bool: return row.archived)
	_check(current_before.size() == 2 and untouched_before.size() == 1, "Before redo: two current rows and the earlier archive's row")
	var index_path := directory.path_join("index.json")
	var index := Index.new(index_path)
	_check(index.store_display(before.settled_items(false), before.pending_chapters()) and index.rows().size() == rows_before.size(), "The replay index holds the scan from before redo")
	var index_bytes := FileAccess.get_file_as_bytes(index_path)
	var plan := journey.redo_plan()
	_check(journey.redo_previous(plan), "Reopen the final stage")
	_check(not index_bytes.is_empty() and FileAccess.get_file_as_bytes(index_path) == index_bytes, "Redo never writes the replay index")
	var stand_in := Index.new(index_path).rows()
	_check(stand_in.size() == rows_before.size() and stand_in.all(func(row: Dictionary) -> bool: return row.checking), "Until the next scan its rows only stand in, marked as being checked")
	Collection._verified.clear()
	CountingRelay.calls = 0
	var trusted := Counting.new(sources, verified)
	await _drain(trusted)
	var trusted_calls := CountingRelay.calls
	var rows := trusted.items()
	var current: Array[Dictionary] = rows.filter(func(row: Dictionary) -> bool: return not row.archived)
	var archived: Array[Dictionary] = rows.filter(func(row: Dictionary) -> bool: return row.archived)
	_check(current.size() == 1 and current[0].id == current_before[0].id, "The popped stage leaves the current rows; the kept stage keeps its id")
	_check(not current.any(func(row: Dictionary) -> bool: return row.stage_index == 1), "No current row remains for the reopened stage")
	_check(archived.size() == 3 and archived.filter(func(row: Dictionary) -> bool: return row.stage_index == 1).size() == 1, "The archive of the reopened attempt adds its rows")
	_check(untouched_before.all(func(old: Dictionary) -> bool: return archived.any(func(row: Dictionary) -> bool: return row.id == old.id)), "The earlier archive's row is unchanged")
	_check(index.store_display(trusted.settled_items(false), trusted.pending_chapters()), "The next scan writes the replay index")
	var indexed: Array = Index.new(index_path).rows().map(func(row: Dictionary) -> String: return str(row.id))
	var scanned: Array = rows.map(func(row: Dictionary) -> String: return str(row.id))
	indexed.sort()
	scanned.sort()
	_check(indexed == scanned and not Index.new(index_path).rows().any(func(row: Dictionary) -> bool: return not row.archived and int(row.stage_index) == 1), "After that scan the index lists exactly its rows, with no current row for the reopened stage")
	Collection._verified.clear()
	CountingRelay.calls = 0
	var full := Counting.new(sources, "")
	await _drain(full)
	_check(Canonical.same(full.items(), rows), "Rows from kept checks equal a full check")
	_check(CountingRelay.calls - trusted_calls == 1, "Only the untouched archive keeps its earlier check (%d full, %d kept)" % [CountingRelay.calls, trusted_calls])
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
	_check(plan.get("kind") == "first_turn" and journey.redo_previous(plan) and journey.role() == "a" and journey.pairs().is_empty(), chapter + ": the first turn is taken back")
	for index in range(names.size()):
		for role: String in ["a", "b"]:
			_check(journey.accept_recording(_fixture(folder + "/" + names[index] + "-" + role)), "%s: accept %s-%s" % [chapter, names[index], role])
	_check(journey.chapter_complete(), chapter + ": complete")
	var complete := journey._state.duplicate(true)
	plan = journey.redo_plan()
	_check(plan.get("kind") == "stage" and plan.get("stage_index") == names.size() - 1 and journey.redo_previous(plan), chapter + ": the last stage reopens")
	_check(journey.role() == "b" and journey.stage_id() == names[-1] and Canonical.same(journey.prior_recording(), _fixture(folder + "/" + names[-1] + "-a")), chapter + ": its first turn is restored")
	_check(journey.simulation_version() == version and Canonical.same(Archive.load_attempt(path, "relay", Canonical.digest(complete), Journey.MAX_SAVE_BYTES), complete), chapter + ": rules unchanged and the completed attempt archived")
	_check(journey.accept_recording(_fixture(folder + "/" + names[-1] + "-b")) and journey.chapter_complete(), chapter + ": the same last turn completes it again")
	var reopened := Journey.new(path, null, chapter)
	reopened.load_data()
	_check(not reopened.read_only and Canonical.same(reopened._state, journey._state), chapter + ": the journal loads back unchanged")
	print("%s redo checks took %d ms" % [chapter, Time.get_ticks_msec() - started])

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
	for filename: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)
