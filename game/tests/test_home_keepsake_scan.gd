extends SceneTree
## Home remembers which journals its keepsake check has already read, across
## visits (home_keepsakes.gd, SCAN_VERSION), and checks a journal the way the
## chapter's own load does, through the proof cache. Every return to Home used
## to replay every unfinished journal again on a worker, and every chapter
## open waited for it.
## - A second visit over unchanged journals starts no check at all.
## - A changed journal, a new build (stamp) and a ledger that lost the places
##   each start exactly one check again, and the places come out the same.
## - A failed check earns nothing and is never remembered as earning.
## - A check stopped for a chapter open is checked again; nothing is lost or
##   earned twice.
## - The places are the ones the full, uncached check gives, and the check
##   leaves the proof the chapter's open then reuses.
## - Archived attempts are checked without adding to the proof cache, so many
##   of them never push out the live save's proof: the next open proves
##   nothing again.
const Keepsakes = preload("res://services/home_keepsakes.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const WELL := Registry.WISHING_WELL
const TIDE := Registry.TURN_OF_THE_TIDE

var checks := 0
var failures := 0
var directory := ""
var proofs_before := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _fixture(name: String) -> Dictionary:
	for folder: String in ["cooperative", "journey"]:
		var path := "res://tests/fixtures/" + folder + "/" + name + ".json"
		if FileAccess.file_exists(path): return JSON.parse_string(FileAccess.get_file_as_string(path))
	return {}

func _forget_proofs(clear_disk: bool) -> void:
	Proofs._chapters.clear()
	Proofs._stages.clear()
	Proofs._last_remembered.clear()
	if clear_disk and DirAccess.dir_exists_absolute(Proofs.directory):
		for name: String in DirAccess.get_files_at(Proofs.directory): DirAccess.remove_absolute(ProjectSettings.globalize_path(Proofs.directory.path_join(name)))

func _ledger(sources: Dictionary, name: String = "keepsakes.json") -> RefCounted:
	var ledger: RefCounted = Keepsakes.new(directory.path_join(name), null, sources)
	ledger.load_data()
	return ledger

## Runs Home's reconciliation to the end; the number of checks it started.
func _drain(ledger: RefCounted, stop_first: bool = false) -> int:
	var started := 0
	var last: Thread = null
	ledger.reconcile_solo()
	var guard := 0
	while ledger.backfill_pending() and guard < 20000:
		if ledger._worker != null and ledger._worker != last:
			started += 1
			last = ledger._worker
			if stop_first and started == 1: ledger.stop_worker()
		ledger.advance_backfill(1)
		if ledger._worker != null and ledger._worker != last:
			started += 1
			last = ledger._worker
			if stop_first and started == 1: ledger.stop_worker()
		await process_frame
		guard += 1
	return started

func _earned(ledger: RefCounted) -> Array:
	var ids: Array = []
	for row: Dictionary in ledger.earned_descriptors(): ids.append([row.id, row.solo, row.friend])
	return ids

func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _run() -> void:
	directory = "user://keepsake-scan-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	proofs_before = Proofs.directory
	Proofs.directory = directory.path_join("proofs")
	# A Wishing Well journal with its first stage kept, on its second stage.
	var well_path := directory.path_join("well.json")
	var well := Journey.new(well_path, null, WELL)
	well.load_data()
	var stages: Array = well._level.stages
	_check(well.accept_recording(_fixture(str(stages[0].id) + "-a")) and well.accept_recording(_fixture(str(stages[0].id) + "-b")), "A saved first stage to check")
	var first_place := Catalog.chapter_place(WELL, str(stages[0].id))
	var second_place := Catalog.chapter_place(WELL, str(stages[1].id))
	# The journal's write remembered its proof; start from a device that has
	# none, as after an engine update.
	Keepsakes._unclaimed.clear()
	_forget_proofs(true)
	var sources := {WELL: well_path}
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(well_path)).relay

	# The places from the full, uncached check, as Home made it before.
	var full: Dictionary = Journey.new(well_path, null, WELL)._validate_state(state)
	_check(full.get("valid", false), "The saved journal passes the full check")
	var first := _ledger(sources)
	var started := await _drain(first)
	_check(started == 1, "A first visit checks the unfinished journal once (%d)" % started)
	_check(_earned(first) == [[first_place, true, false]], "Its kept stage earns exactly its own place: " + str(_earned(first)))
	_check(not Proofs.recall(Journey.new(well_path, null, WELL), state).is_empty(), "Home's check leaves the proof the chapter's own open reuses")
	var scan_path := directory.path_join("keepsakes-scan.json")
	_check(FileAccess.file_exists(scan_path), "What Home checked is kept beside the ledger")
	_check(not FileAccess.get_file_as_string(scan_path).contains("recording"), "The scan file holds no recording")
	var expected := _earned(first)

	var again := _ledger(sources)
	_check(await _drain(again) == 0, "A second visit over the unchanged journal starts no check")
	_check(_earned(again) == expected, "and the places are unchanged")

	# A new build may judge a journal differently: everything is checked again.
	var rebuilt := _ledger(sources)
	rebuilt.scan_stamp = "another build"
	rebuilt.load_data()
	_check(await _drain(rebuilt) == 1, "A new build checks the journal again, once")
	_check(_earned(rebuilt) == expected, "with the same places")
	_check(await _drain(_ledger(sources)) == 1, "Back on this build, the journal is checked once more")

	# A ledger that lost its places (cleared, restored) earns them again.
	_remove(directory.path_join("keepsakes.json"))
	var lost := _ledger(sources)
	_check(_earned(lost).is_empty(), "The ledger lost its places")
	_check(await _drain(lost) == 1, "A ledger without the remembered places checks the journal again")
	_check(_earned(lost) == expected, "and earns the same places, once")

	# A changed journal is checked again.
	_check(well.accept_recording(_fixture(str(stages[1].id) + "-a")), "The journal moves on: the second stage's first turn")
	Keepsakes._unclaimed.clear()
	_forget_proofs(true)
	var changed := _ledger(sources)
	_check(await _drain(changed) == 1, "A changed journal is checked again, once")
	_check(_earned(changed) == expected, "A first turn alone earns nothing more")
	# A draft saved during play is checked for shape, as the chapter's own load
	# does; the places come from the accepted pairs, as the full check gives.
	_check(well.save_draft(_fixture(str(stages[1].id) + "-b")), "A draft of the next turn is saved")
	state = JSON.parse_string(FileAccess.get_file_as_string(well_path)).relay
	_check(not state.draft.is_empty(), "The journal holds the draft")
	var drafted: Dictionary = Keepsakes._verify_source_snapshot({"kind": "chapter", "chapter": WELL, "path": well_path, "raw": [FileAccess.get_file_as_string(well_path)]}, Journey.new(well_path, null, WELL))
	var full_drafted: Dictionary = Journey.new(well_path, null, WELL)._validate_state(state)
	_check(full_drafted.get("valid", false) and drafted.get("ok", false) and str(drafted.get("ids")) == str([first_place]), "A journal with a draft earns the full check's places")

	# Stopped for a chapter open: checked again, and the places are the same.
	_remove(scan_path)
	_remove(directory.path_join("keepsakes.json"))
	_forget_proofs(true)
	var stopped := _ledger(sources)
	var runs := await _drain(stopped, true)
	_check(runs >= 1 and runs <= 2, "A check stopped for an open is checked again (%d runs)" % runs)
	_check(_earned(stopped) == expected, "A stopped check loses no place and earns none twice: " + str(_earned(stopped)))
	_check(await _drain(_ledger(sources)) == 0, "Once finished it is remembered as any other")
	# Directly: a stop request before the first stage ends the check unearned.
	_forget_proofs(true)
	var stop := Keepsakes.StopRequest.new()
	stop.stop()
	var snapshot := {"kind": "chapter", "chapter": WELL, "path": well_path, "raw": [FileAccess.get_file_as_string(well_path)]}
	var held: Dictionary = Keepsakes._verify_source_snapshot(snapshot.duplicate(true), Journey.new(well_path, null, WELL), stop)
	_check(held.get("stopped", false) and not held.get("ok", true) and held.get("ids", [1]).is_empty(), "A stopped check earns nothing")
	var proved: Dictionary = Keepsakes._verify_source_snapshot(snapshot.duplicate(true), Journey.new(well_path, null, WELL))
	var recalled: Dictionary = Keepsakes._verify_source_snapshot(snapshot.duplicate(true), Journey.new(well_path, null, WELL))
	_check(proved == recalled and str(proved.get("ids")) == str([first_place]) and proved.get("ok", false), "Proved and recalled checks earn the full check's places")

	# A journal that fails its check earns nothing, and stays unearned.
	var tide_path := directory.path_join("tide.json")
	var tide := Journey.new(tide_path, null, TIDE)
	tide.load_data()
	var tide_stage := str(tide._level.stages[0].id)
	_check(tide.accept_recording(_fixture(tide_stage + "-a")) and tide.accept_recording(_fixture(tide_stage + "-b")), "A saved Turn of the Tide stage")
	Keepsakes._unclaimed.clear()
	var broken: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(tide_path))
	broken.relay.pairs[0].b.inputs = []
	var file := FileAccess.open(tide_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(broken))
	file.close()
	_remove(tide_path + ".backup")
	_forget_proofs(true)
	var both := {WELL: well_path, TIDE: tide_path}
	var failing := _ledger(both, "failing.json")
	_check(await _drain(failing) == 2, "A new ledger checks both journals")
	_check(_earned(failing) == expected, "A journal that fails its check earns nothing: " + str(_earned(failing)))
	var later := _ledger(both, "failing.json")
	_check(await _drain(later) == 0 and _earned(later) == expected, "A failed check is remembered as failed, never as earned")

	await _archives_keep_live_proof()

	# A damaged scan file is ignored as a whole and never holds the ledger.
	file = FileAccess.open(scan_path, FileAccess.WRITE)
	file.store_string("{damaged")
	file.close()
	var damaged := _ledger(sources)
	_check(not damaged.read_only and damaged.last_error.is_empty(), "A damaged scan file never holds the ledger")
	_check(await _drain(damaged) == 1 and _earned(damaged) == expected, "and only means the journal is checked again")

	for folder: String in [Proofs.directory, directory]:
		if not DirAccess.dir_exists_absolute(folder): continue
		for name: String in DirAccess.get_files_at(folder): DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Proofs.directory))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	Proofs.directory = proofs_before
	_forget_proofs(false)
	print("HOME KEEPSAKE SCAN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _archives_keep_live_proof() -> void:
	_forget_proofs(true)
	var path := directory.path_join("tide-archives.json")
	var tide := Journey.new(path, null, TIDE)
	tide.load_data()
	var stage := str(tide._level.stages[0].id)
	_check(tide.accept_recording(_fixture(stage + "-a")) and tide.accept_recording(_fixture(stage + "-b")), "A live Turn of the Tide save with a kept stage")
	Keepsakes._unclaimed.clear()
	var live: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)).relay
	_check(not Proofs.recall(Journey.new(path, null, TIDE), live).is_empty(), "The live save's proof is remembered")
	# More archived attempts than the cache keeps a chapter, each a valid
	# kept first stage played another way.
	var made := 0
	for variant: String in ["half", "half-winch", "high", "low-half-first-stones"]:
		var a := _fixture(stage + "-" + variant + "-a")
		var b := _fixture(stage + "-" + variant + "-b")
		if a.is_empty() or b.is_empty(): continue
		var attempt := live.duplicate(true)
		attempt.pairs = [{"a": a, "b": b}]
		attempt.a = {}
		attempt.draft = {}
		var file := FileAccess.open(path + ".attempt-" + Canonical.digest(attempt) + ".json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"archive_version": 1, "relay": attempt}))
		file.close()
		made += 1
	_check(made >= Proofs.ENTRIES_PER_CHAPTER, "As many archived attempts as the cache keeps a chapter (%d)" % made)
	var ledger := _ledger({TIDE: path}, "archives.json")
	_check(await _drain(ledger) == made + 1, "Home checks the live save and every archived attempt")
	_check(_earned(ledger) == [[Catalog.chapter_place(TIDE, stage), true, false]], "The archived attempts earn the same place, once: " + str(_earned(ledger)))
	# A fresh process: only what is on disk.
	_forget_proofs(false)
	_check(not Proofs.recall(Journey.new(path, null, TIDE), live).is_empty(), "The archived attempts left the live save's proof in place")
	var opened := Journey.new(path, null, TIDE)
	opened.load_data()
	_check(not opened.read_only and Proofs._stages.is_empty(), "The chapter's next open proves no stage again")
