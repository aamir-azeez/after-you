extends RefCounted
## Proofs a solo journey has already made, so opening a chapter does not replay
## every saved turn again.
##
## A finished pair can only be checked by replaying it, and every engine check
## also replays the whole chain of earlier stages. Opening Turn of the Tide on
## its last turn used to replay the same turns about a dozen times. Here:
## - A save this device wrote or fully checked is remembered by a digest of its
##   exact accepted turns (pairs and first turn) with the checkpoint they proved.
##   The same bytes later reuse that checkpoint; any other bytes are checked.
## - A save not remembered yet is checked once, stage by stage, from the start
##   checkpoint; each stage's checkpoint is built from the one just proved.
## - A draft is never remembered or trusted. Loading checks only its shape;
##   it is replayed in full when the player resumes it (RelayJourney.draft()).
## - Saves not remembered yet can be proved ahead, on a worker, while the
##   player is idle at Home (journey_proof_warmup.gd).
## - The next live turn is set up from the journey's proven checkpoint and
##   partner turn without replaying them again.
## All structural and version rules still run in RelayJourney._validate_state.
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const JourneySimulation = preload("res://core/journey/simulation.gd")
const CooperativeSimulation = preload("res://core/cooperative/simulation.gd")
const LighthouseSimulation = preload("res://core/lighthouse/room_simulation.gd")
const LighthouseProof = preload("res://core/lighthouse/room_proof.gd")

## One small file per chapter, never a journal.
const DIRECTORY := "user://journey-proofs"
const SCHEMA := 1
## Bump when the meaning of a proven solo save changes.
const PROOF_VERSION := 1
## The current save, its backup and a write in progress, with room to spare.
const ENTRIES_PER_CHAPTER := 4
const MAX_FILE_BYTES := 2097152

static var directory := DIRECTORY
static var _mutex := Mutex.new()
## chapter -> Array of [key, digest of the checkpoint bytes, checkpoint], oldest first.
static var _chapters: Dictionary = {}
## chapter -> [what the last remember call recorded in short, its key].
static var _last_remembered: Dictionary = {}
## Stages proved in this process, so a save and its backup (which share their
## earlier stages) replay each stage once: key -> the checkpoint it built.
const STAGES_KEPT := 16
static var _stages: Dictionary = {}


## A pending draft's check, as a wait to expect on Resume.
const DRAFT_CHECK_ESTIMATE_USEC := 1000000

## load_data's check of one saved generation, through _validate_state. A
## draft's shape is checked here; its replay waits for Resume. Also Home's
## keepsake check, on a worker: cancelled, when given, stops the proof between
## stages and the result is {"valid": false, "stopped": true}; remember_proof
## false checks without adding to the cache (an archived attempt).
static func validate(journey: RefCounted, value: Variant, cancelled: Callable = Callable(), remember_proof: bool = true) -> Dictionary:
	prepare_memo(str(journey._chapter_key))
	var accepted: Variant = _without_draft(value)
	var trusted := recall(journey, accepted)
	var checked: Dictionary = {}
	if not trusted.is_empty():
		checked = journey._validate_state(accepted, trusted)
	if not checked.get("valid", false):
		var proven := _prove(journey, accepted, cancelled)
		if cancelled.is_valid() and cancelled.call(): return {"valid": false, "error": "", "stopped": true}
		checked = journey._validate_state(accepted, proven)
		# Any failure is reported exactly as the full check reports it.
		if not checked.get("valid", false) and not proven.is_empty(): checked = journey._validate_state(accepted)
		if checked.get("valid", false) and remember_proof: remember(journey, accepted, checked.checkpoint)
	if not checked.get("valid", false): return checked
	return _draft_shape(journey, value, checked)

## After load_data took a save: a draft in it is not checked yet. RelayJourney
## replays it from the proven checkpoint when the player resumes it, and a
## screen expects that wait.
static func loaded(journey: RefCounted) -> void:
	if journey.read_only or journey._state.get("draft", {}).is_empty(): return
	journey._draft_replay_verified = false
	journey._last_check_usec = maxi(int(journey._last_check_usec), DRAFT_CHECK_ESTIMATE_USEC)

## Proves one saved generation ahead of an open, if nothing is remembered for
## it, and remembers the result. Never replays a draft and never reports an
## error: an open checks anything this could not prove. Safe on a worker.
static func warm(journey: RefCounted, value: Variant, cancelled: Callable = Callable()) -> String:
	var accepted: Variant = _without_draft(value)
	if _key(journey, accepted).is_empty(): return "empty"
	if not recall(journey, accepted).is_empty(): return "known"
	var proven := _prove(journey, accepted, cancelled)
	if proven.is_empty(): return "cancelled" if cancelled.is_valid() and cancelled.call() else "unproven"
	var checked: Dictionary = journey._validate_state(accepted, proven)
	if not checked.get("valid", false): return "unproven"
	remember(journey, accepted, checked.checkpoint)
	return "proven"

## The same state with no draft, for checks that never replay one.
static func _without_draft(value: Variant) -> Variant:
	if not value is Dictionary or not value.get("draft") is Dictionary or value.draft.is_empty(): return value
	var accepted: Dictionary = value.duplicate()
	accepted.draft = {}
	return accepted

## A draft that cannot belong to the next turn at all (finished chapter,
## other rules, role or stage) is refused on load by the full check, with its
## exact verdict; any other draft waits for Resume.
static func _draft_shape(journey: RefCounted, value: Variant, checked: Dictionary) -> Dictionary:
	var draft: Dictionary = value.draft
	if draft.is_empty(): return checked
	var next_stage := str(checked.checkpoint.get("next_stage_id", ""))
	var fits: bool = not next_stage.is_empty() and draft.get("stage_id") == next_stage and draft.get("role") == ("a" if value.a.is_empty() else "b")
	if str(journey._chapter_key) != Registry.FIRST_STEPS and draft.get("simulation_version") != value.simulation_version: fits = false
	if fits: return checked
	var full: Dictionary = journey._validate_state(value)
	return full if not full.get("valid", false) else journey._invalid(PlayerCopy.LIGHTHOUSE_JOURNEY_2A6C3206C0FC)


## A trusted check for _validate_state when these exact accepted turns were
## proven on this device, else {}.
static func recall(journey: RefCounted, value: Variant) -> Dictionary:
	var chapter := str(journey._chapter_key)
	var key := _key(journey, value)
	if key.is_empty(): return {}
	_mutex.lock()
	var found: Array = []
	for entry: Array in _entries(chapter):
		if entry[0] == key: found = entry
	_mutex.unlock()
	if found.is_empty(): return {}
	var checkpoint: Dictionary = found[2]
	var pairs: Array = value.pairs
	var index: Variant = checkpoint.get("stage_index")
	# A damaged entry is dropped and a mismatched one ignored; the save is
	# then checked.
	if _bytes_digest(checkpoint) != found[1]:
		_mutex.lock()
		_entries(chapter).erase(found)
		_mutex.unlock()
		return {}
	if not (index is int or index is float) or int(index) != pairs.size() or not checkpoint.get("next_stage_id") is String:
		return {}
	if not pairs.is_empty():
		var last: Variant = pairs[-1]
		if not last is Dictionary or not last.get("a") is Dictionary or not last.get("b") is Dictionary: return {}
		if checkpoint.get("a_recording_hash") != last.a.get("recording_hash") or checkpoint.get("b_recording_hash") != last.b.get("recording_hash"): return {}
	return {"pairs": pairs.size(), "checkpoint": checkpoint.duplicate(true), "a_verified": true}


## Records that this state's accepted turns prove checkpoint. Every caller has
## proven both (a full or stage-by-stage check, or a write of a checked turn).
static func remember(journey: RefCounted, value: Variant, checkpoint: Dictionary) -> void:
	var chapter := str(journey._chapter_key)
	# A draft saved every second of play leaves the accepted turns as they
	# were; skip the digests then. Skipping only ever costs a later full check.
	var summary := _summary(value, checkpoint)
	var slot := directory + "|" + chapter
	_mutex.lock()
	var last: Array = _last_remembered.get(slot, [])
	var unchanged := false
	if not summary.is_empty() and not last.is_empty() and last[0] == summary:
		for entry: Array in _entries(chapter):
			if entry[0] == last[1]: unchanged = true
	_mutex.unlock()
	if unchanged: return
	var key := _key(journey, value)
	if key.is_empty() or checkpoint.is_empty(): return
	var digest := _bytes_digest(checkpoint)
	_mutex.lock()
	_last_remembered[slot] = [summary, key]
	var entries := _entries(chapter)
	# The common case: a draft saved over turns already remembered.
	if not entries.is_empty() and entries[-1][0] == key and entries[-1][1] == digest:
		_mutex.unlock()
		return
	for index in range(entries.size() - 1, -1, -1):
		if entries[index][0] == key: entries.remove_at(index)
	entries.append([key, digest, checkpoint.duplicate(true)])
	while entries.size() > ENTRIES_PER_CHAPTER: entries.remove_at(0)
	_write(chapter, entries)
	_mutex.unlock()
	save_memo(chapter)


## A draft's rehearsal from a checkpoint this journey has proven: its own
## replay (and its partner turn's), without the chain behind the checkpoint.
static func rehearse(journey: RefCounted, draft: Dictionary, checkpoint: Dictionary, prior_a: Dictionary) -> Dictionary:
	var family: Script = journey._simulation
	if _runtime_family(family): return family._proof(family._record_version(draft))._verify_raw(journey._level, draft, checkpoint, prior_a)
	return family.verify_recording(journey._level, draft, checkpoint, prior_a)


## Sets up a fresh live turn as Registry.reset_simulation does. A job from a
## journey (proven) holds a checkpoint and partner turn that journey has
## proven, so for the shared runtime rules they are not replayed again; every
## other rule of the family's reset still runs. Anything else, and every
## refusal, goes through the family's own reset.
static func reset_live(simulation: RefCounted, job: Dictionary) -> bool:
	var chapter := str(job.chapter)
	if not _trusted_setup(job) or simulation.get_script() != job.family: return Registry.reset_simulation(simulation, chapter, job.level, str(job.stage), job.checkpoint, job.prior, str(job.role), job.saved)
	var level: Dictionary = job.level
	var stage := str(job.stage)
	var checkpoint: Dictionary = job.checkpoint
	var prior: Dictionary = job.prior
	var role := str(job.role)
	var saved: Dictionary = job.saved
	var lighthouse := Registry.is_lighthouse(chapter)
	# The rules Registry.reset_simulation hands both runtime facades.
	var rules := int(saved.get("simulation_version", prior.get("simulation_version", Registry.preferred_rules(chapter))))
	var family: Script = job.family
	# The Lighthouse facade plays only its chapter's pinned rules.
	var allowed: bool = (rules in Registry.supported_rules(chapter) if lighthouse else family.rules_allowed(level, rules)) and not (role == "b" and prior.get("simulation_version") != rules)
	var fits: bool = role in ["a", "b"] and not stage.is_empty() and stage == checkpoint.get("next_stage_id") and not (role == "a" and not prior.is_empty())
	if allowed and fits:
		simulation.simulation_version = rules
		simulation._reset_trusted(level, stage, checkpoint, prior, role)
		# The facade reports a stage requirement it refuses; the full reset names it.
		if not lighthouse or str(simulation.get("error")).is_empty(): return true
	return Registry.reset_simulation(simulation, chapter, level, stage, checkpoint, prior, role, saved)

## Whether reset_live may take job's checkpoint and partner turn as proven:
## a journey's job (proven) under the shared runtime rules.
static func _trusted_setup(job: Dictionary) -> bool:
	var chapter := str(job.get("chapter", ""))
	return job.get("proven", false) == true and _runtime_family(job.get("family")) and (Registry.is_cooperative(chapter) or Registry.is_lighthouse(chapter))

## Whether setting job's turn up replays a recorded turn: a partner turn that
## reset_live cannot take as proven.
static func setup_replays(job: Dictionary) -> bool:
	return job.get("prior") is Dictionary and not job.prior.is_empty() and not _trusted_setup(job)


## Proves the accepted turns once, stage by stage. {} when this family has no
## such path or anything fails; the caller then runs the full check.
static func _prove(journey: RefCounted, value: Variant, cancelled: Callable = Callable()) -> Dictionary:
	var family: Script = journey._simulation
	var level: Dictionary = journey._level
	if not _runtime_family(family) or not value is Dictionary or not value.get("pairs") is Array or not value.get("a") is Dictionary: return {}
	if value.pairs.size() > level.get("stages", []).size(): return {}
	var derived: Dictionary = Registry.initial_checkpoint(str(journey._chapter_key))
	if derived.is_empty(): return {}
	for index in range(value.pairs.size()):
		if cancelled.is_valid() and cancelled.call(): return {}
		var pair: Variant = value.pairs[index]
		if not pair is Dictionary or not pair.get("a") is Dictionary or not pair.get("b") is Dictionary: return {}
		var stage_key := "|".join(PackedStringArray([str(PROOF_VERSION), str(journey._chapter_key), str(Registry.supported_rules(str(journey._chapter_key))), str(derived.get("checkpoint_hash", "")), Canonical.digest(pair.a), Canonical.digest(pair.b)]))
		_mutex.lock()
		var known: Variant = _stages.get(stage_key)
		_mutex.unlock()
		if known is Dictionary:
			derived = known.duplicate(true)
			continue
		var engine: RefCounted = family._proof(family._record_version(pair.a))
		if index == 0:
			# The first stage starts from the start checkpoint: the public path.
			var first_stage: Dictionary = engine.derive_checkpoint(level, derived, pair.a, pair.b)
			if not first_stage.get("valid", false): return {}
			derived = first_stage.checkpoint
		else:
			# derive_checkpoint, without proving again the checkpoint just built.
			var check: Dictionary = engine._verify_pair(level, derived, pair.a, pair.b)
			if not check.get("valid", false): return {}
			derived = engine._build_checkpoint(level, derived, pair.a, pair.b, check.snapshot)
		_mutex.lock()
		_stages[stage_key] = derived.duplicate(true)
		while _stages.size() > STAGES_KEPT: _stages.erase(_stages.keys()[0])
		_mutex.unlock()
	var first: Dictionary = value.a
	if not first.is_empty():
		if cancelled.is_valid() and cancelled.call(): return {}
		if str(derived.get("next_stage_id", "")).is_empty() or first.get("role") != "a": return {}
		var turn: RefCounted = family._proof(family._record_version(first))
		var checked: Dictionary = turn.verify_recording(level, first, derived) if value.pairs.is_empty() else turn._verify_raw(level, first, derived, {})
		if not checked.get("valid", false) or not checked.get("snapshot", {}).get("can_commit", false): return {}
	return {"pairs": value.pairs.size(), "checkpoint": derived, "a_verified": true}

static func _summary(value: Variant, checkpoint: Dictionary) -> String:
	if not value is Dictionary or not value.get("pairs") is Array or not value.get("a") is Dictionary: return ""
	var last: Variant = value.pairs[-1] if not value.pairs.is_empty() else {}
	var closing: String = str(last.get("b", {}).get("recording_hash", "")) if last is Dictionary and last.get("b") is Dictionary else ""
	return "%d|%s|%s|%s" % [value.pairs.size(), str(value.a.get("recording_hash", "")), closing, str(checkpoint.get("checkpoint_hash", ""))]

static func _runtime_family(family: Variant) -> bool:
	return family == JourneySimulation or family == CooperativeSimulation or family == LighthouseSimulation


## sleeping-lighthouse@2 checks a checkpoint by replaying every nested stage;
## its proof (core/lighthouse/room_proof.gd) remembers checkpoints it verified.
## That memo is kept here, next to the solo proofs, so a restart re-checks only
## checkpoints it has not seen: solo journeys, rooms and shared replays alike.
const MEMO_FILE := "sleeping-lighthouse-v2-verified.json"
## directory -> memo size at its last load or save.
static var _memo_sizes: Dictionary = {}

static func _memo_chapter(chapter: String) -> bool:
	return Registry.simulation_script(chapter) == LighthouseSimulation

## Loads the persisted memo once per process (and per proofs directory).
static func prepare_memo(chapter: String) -> void:
	if not _memo_chapter(chapter): return
	_mutex.lock()
	var path := directory.path_join(MEMO_FILE)
	if not _memo_sizes.has(path):
		LighthouseProof.load_index(path)
		_memo_sizes[path] = LighthouseProof.memo_size()
	_mutex.unlock()

## Writes the memo when it holds checkpoints the file does not; small (128 KiB at most).
static func save_memo(chapter: String) -> void:
	if not _memo_chapter(chapter): return
	prepare_memo(chapter)
	_mutex.lock()
	var path := directory.path_join(MEMO_FILE)
	var size := LighthouseProof.memo_size()
	if size != int(_memo_sizes.get(path, -1)):
		DirAccess.make_dir_recursive_absolute(directory)
		if LighthouseProof.save_index(path): _memo_sizes[path] = size
	_mutex.unlock()


## The exact accepted turns under this build's rules for the chapter; the
## draft is left out, so a draft never makes anything trusted.
static func _key(journey: RefCounted, value: Variant) -> String:
	if not value is Dictionary or not value.get("pairs") is Array or not value.get("a") is Dictionary: return ""
	# A journey with no accepted turn has nothing to prove.
	if value.pairs.is_empty() and value.a.is_empty(): return ""
	var chapter := str(journey._chapter_key)
	if chapter.is_empty(): return ""
	var body: Dictionary = value.duplicate()
	body.erase("draft")
	return "|".join(PackedStringArray([str(PROOF_VERSION), str(Engine.get_version_info().get("string", "")), chapter, str(Registry.supported_rules(chapter)), Canonical.digest(body)])).sha256_text()


static func _bytes_digest(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()


static func _path(chapter: String) -> String:
	return directory.path_join(chapter.validate_filename() + ".bin")


## Callers hold _mutex.
static func _entries(chapter: String) -> Array:
	var cache_key := directory + "|" + chapter
	if _chapters.has(cache_key): return _chapters[cache_key]
	var entries: Array = []
	_chapters[cache_key] = entries
	var path := _path(chapter)
	if not FileAccess.file_exists(path): return entries
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return entries
	if file.get_length() < 1 or file.get_length() > MAX_FILE_BYTES:
		file.close()
		return entries
	var data: Variant = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	# Anything unexpected is ignored as a whole; the next proof rewrites it.
	if not data is Dictionary or data.size() != 3 or data.get("schema_version") != SCHEMA or data.get("chapter") != chapter or not data.get("entries") is Array: return entries
	for entry: Variant in data.entries:
		if not entry is Array or entry.size() != 3 or not entry[0] is String or not entry[1] is String or not entry[2] is Dictionary:
			entries.clear()
			return entries
		entries.append(entry)
	while entries.size() > ENTRIES_PER_CHAPTER: entries.remove_at(0)
	return entries


static func _write(chapter: String, entries: Array) -> void:
	var bytes := var_to_bytes({"schema_version": SCHEMA, "chapter": chapter, "entries": entries})
	if bytes.size() > MAX_FILE_BYTES:
		# Keep only the newest entry rather than nothing.
		while entries.size() > 1: entries.remove_at(0)
		bytes = var_to_bytes({"schema_version": SCHEMA, "chapter": chapter, "entries": entries})
		if bytes.size() > MAX_FILE_BYTES: return
	DirAccess.make_dir_recursive_absolute(directory)
	var path := _path(chapter)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return
	file.store_buffer(bytes)
	file.flush()
	var okay := file.get_error() == OK
	file.close()
	if not okay: return
	var target := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path): DirAccess.remove_absolute(target)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), target)