extends RefCounted
## Open turns fingerprints: this phone's own copy of every turn of an open turns
## room, one folder a stage, one file a turn named by its recording hash, and the
## stage checkpoints it proved, one file each. The server keeps only the newest
## turn in full; earlier turns are fingerprints (the record without `packed`)
## and checkpoints are flat (no proof). Everything a turn plays over, every
## replay and every posted run is rebuilt here from these copies.
## Wire shapes: claude-20261011/open-turns-fingerprints/WIRE.md (private).
## Every file goes through services/atomic_file.gd and is checked on read: a turn
## must hash to its name, a checkpoint to its own checkpoint_hash. Nothing is
## removed automatically: a fingerprinted turn may be the only full copy left.
## A phone that lost a turn gets it back from the partner's phone
## (services/relay_room_coordinator.gd recover_turns) or a Play Games / Game
## Center backup (services/platform_games/cloud_replay_sources.gd).
const AtomicFile = preload("res://services/atomic_file.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Typed = preload("res://services/typed_values.gd")
const Registry = preload("res://services/chapter_registry.gd")
const KnownCheckpoints = preload("res://core/physical/known_checkpoints.gd")
const ROOT := "user://open-turns"
const TURN_SUFFIX := ".turn.json"
const CHECKPOINT_SUFFIX := ".checkpoint.json"
## Names the finished room's final checkpoint (keep_final).
const FINAL := "final.json"
## The widest packed turn is about 84 KB; a file larger than this is not ours.
const MAX_TURN_BYTES := 512 * 1024
const MAX_CHECKPOINT_BYTES := 256 * 1024
const MAX_STAGES := 8
## Turns read back and kept in memory for this room.
const CACHE := 48

var root := ROOT
var owner := ""
var room_id := ""
var _cache: Dictionary = {}

func _init(owner_id: String = "", room: String = "", root_path: String = ROOT) -> void:
	owner = owner_id
	room_id = room
	root = root_path

## Where this room's copies live, or "" for a bad owner or room id.
func directory() -> String:
	if not Typed.valid_id(owner) or not Typed.valid_id(room_id): return ""
	return root.path_join(owner).path_join(room_id)

## A turn's fingerprint (WIRE.md section 2): a record without `packed` or `actions`.
static func fingerprint(record: Variant) -> bool:
	return record is Dictionary and not record.has("packed") and not record.has("actions") and _hash(record.get("recording_hash"))

## A full turn: it carries its inputs, packed or as actions.
static func full(record: Variant) -> bool:
	return record is Dictionary and (record.has("packed") or record.has("actions")) and _hash(record.get("recording_hash"))

## The fingerprint the server keeps of a full turn: every field but its inputs.
static func strip(record: Dictionary) -> Dictionary:
	var value := record.duplicate(true)
	for key: String in ["packed", "actions", "replay_checks"]: value.erase(key)
	return value

## Whether `copy` (full) is the turn `stub` (a fingerprint) names: every field
## the fingerprint has is the copy's, and the copy hashes to it.
static func matches(copy: Dictionary, stub: Dictionary) -> bool:
	return full(copy) and Canonical.same(strip(copy), stub) and hash_ok(copy)

## Whether a full record's recording_hash is its own.
static func hash_ok(record: Dictionary) -> bool:
	var body := record.duplicate(true)
	body.erase("recording_hash")
	return _hash(record.get("recording_hash")) and Canonical.digest(body) == record.recording_hash

static func _hash(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number(false) and value == value.to_lower()

func _stage_directory(stage_index: int) -> String:
	var base := directory()
	return "" if base.is_empty() or stage_index < 0 or stage_index >= MAX_STAGES else base.path_join("s%d" % stage_index)

## Keeps a full turn of stage `stage_index` durably. True once it is on disk
## (already, or now). A turn that does not hash to itself is refused.
func keep_turn(stage_index: int, record: Dictionary) -> bool:
	var folder := _stage_directory(stage_index)
	if folder.is_empty() or not full(record) or not hash_ok(record): return false
	var path := folder.path_join(str(record.recording_hash) + TURN_SUFFIX)
	if FileAccess.file_exists(path) and not turn(stage_index, str(record.recording_hash)).is_empty(): return true
	DirAccess.make_dir_recursive_absolute(folder)
	if not AtomicFile.write_text(path, JSON.stringify(record)): return false
	_remember(record)
	return true

## Stage `stage_index`'s turn `recording_hash` in full, or {} when this phone lacks it.
func turn(stage_index: int, recording_hash: String) -> Dictionary:
	var cached: Variant = _cache.get(recording_hash)
	if cached is Dictionary: return cached.duplicate(true)
	var folder := _stage_directory(stage_index)
	if folder.is_empty() or not _hash(recording_hash): return {}
	var record := _read(folder.path_join(recording_hash + TURN_SUFFIX), MAX_TURN_BYTES)
	if not full(record) or record.recording_hash != recording_hash or not hash_ok(record): return {}
	_remember(record)
	return record.duplicate(true)

func has_turn(stage_index: int, recording_hash: String) -> bool:
	return not turn(stage_index, recording_hash).is_empty()

## A turn by hash on any stage: {"stage_index", "record"}, or {}.
func find_turn(recording_hash: String) -> Dictionary:
	for stage_index in range(MAX_STAGES):
		var found := turn(stage_index, recording_hash)
		if not found.is_empty(): return {"stage_index": stage_index, "record": found}
	return {}

## Every turn file this room keeps: [{"stage_index", "recording_hash", "path"}].
func held() -> Array:
	var result: Array = []
	for stage_index in range(MAX_STAGES):
		var folder := _stage_directory(stage_index)
		if folder.is_empty() or not DirAccess.dir_exists_absolute(folder): continue
		for name: String in DirAccess.get_files_at(folder):
			if name.ends_with(TURN_SUFFIX) and _hash(name.trim_suffix(TURN_SUFFIX)): result.append({"stage_index": stage_index, "recording_hash": name.trim_suffix(TURN_SUFFIX), "path": folder.path_join(name)})
	return result

func _remember(record: Dictionary) -> void:
	_cache.erase(record.recording_hash)
	_cache[record.recording_hash] = record.duplicate(true)
	while _cache.size() > CACHE: _cache.erase(_cache.keys()[0])

## Keeps a stage checkpoint this phone proved, flat, and trusts it by hash from now on.
func keep_checkpoint(proved: Dictionary) -> bool:
	var value := KnownCheckpoints.flat(proved)
	var base := directory()
	if base.is_empty() or not _checkpoint_hashes(value): return false
	var folder := base.path_join("checkpoints")
	var path := folder.path_join(str(value.checkpoint_hash) + CHECKPOINT_SUFFIX)
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(folder)
		if not AtomicFile.write_text(path, JSON.stringify(value)): return false
	KnownCheckpoints.keep(str(value.checkpoint_hash))
	return true

## A checkpoint this phone proved before, flat, or {}. Reading it trusts it again.
func checkpoint(checkpoint_hash: String) -> Dictionary:
	var base := directory()
	if base.is_empty() or not _hash(checkpoint_hash): return {}
	var value := _read(base.path_join("checkpoints").path_join(checkpoint_hash + CHECKPOINT_SUFFIX), MAX_CHECKPOINT_BYTES)
	if value.is_empty() or value.get("checkpoint_hash") != checkpoint_hash or not _checkpoint_hashes(value): return {}
	KnownCheckpoints.keep(checkpoint_hash)
	return value

## Trusts every checkpoint this room kept (a restart, or a turn store brought back).
func trust_all() -> void:
	var folder := directory().path_join("checkpoints") if not directory().is_empty() else ""
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder): return
	for name: String in DirAccess.get_files_at(folder):
		if name.ends_with(CHECKPOINT_SUFFIX): checkpoint(name.trim_suffix(CHECKPOINT_SUFFIX))

static func _checkpoint_hashes(value: Dictionary) -> bool:
	var body := value.duplicate(true)
	body.erase("checkpoint_hash")
	body.erase("proof")
	return _hash(value.get("checkpoint_hash")) and Canonical.digest(body) == value.checkpoint_hash

static func _read(path: String, maximum: int) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > maximum: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

## The current stage's turns of an open turns room as the server sends it
## (WIRE.md section 4), full and in play order, from `room.open_turns.newest` and
## this phone's copies: {"turns": [...], "missing": [hashes this phone lacks]}.
## `turns` is [] while anything is missing or does not match the room.
func stage_turns(room: Dictionary) -> Dictionary:
	var view: Variant = room.get("open_turns")
	if not view is Dictionary or not view.get("turn_hashes") is Array: return {"turns": [], "missing": []}
	var names: Array = view.turn_hashes
	var newest: Variant = view.get("newest")
	var stage_index := Typed.as_int(room.get("stage_index"), -1)
	var turns: Array = []
	var missing: Array = []
	for index in range(names.size()):
		var wanted := str(names[index])
		var found: Dictionary = newest if index == names.size() - 1 and full(newest) and newest.recording_hash == wanted and hash_ok(newest) else turn(stage_index, wanted)
		if found.is_empty(): missing.append(wanted)
		else: turns.append(found)
	if not missing.is_empty(): return {"turns": [], "missing": missing}
	# Turn 1 is also the room's recording_a, as its fingerprint.
	if not turns.is_empty() and (not fingerprint(room.get("recording_a")) or not matches(turns[0], room.recording_a)): return {"turns": [], "missing": []}
	return {"turns": turns, "missing": []}

## The previous stage's checkpoint of `checkpoint` (flat or nested): the
## chapter's initial one before stage 1, else this phone's proved copy; {}.
func previous(chapter_key: String, value: Dictionary) -> Dictionary:
	var stage := Typed.as_int(value.get("stage_index"), -1)
	if stage < 1: return {}
	if value.get("proof") is Dictionary and value.proof.get("checkpoint") is Dictionary: return value.proof.checkpoint.duplicate(true)
	var found: Dictionary = Registry.initial_checkpoint(chapter_key) if stage == 1 else checkpoint(str(value.get("previous_checkpoint_hash", "")))
	return found if not found.is_empty() and found.get("checkpoint_hash") == value.get("previous_checkpoint_hash") else {}

## The turns a flat checkpoint names, full, or [] when any is missing.
func checkpoint_turns(value: Dictionary) -> Array:
	var stage := Typed.as_int(value.get("stage_index"), -1) - 1
	var names: Variant = value.get("turn_hashes")
	if stage < 0 or not names is Array or names.size() < 2: return []
	var turns: Array = []
	for wanted: Variant in names:
		var found := turn(stage, str(wanted))
		if found.is_empty(): return []
		turns.append(found)
	return turns

## The hashes a flat checkpoint's stage needs that this phone lacks.
func checkpoint_missing(value: Dictionary) -> Array:
	var stage := Typed.as_int(value.get("stage_index"), -1) - 1
	var names: Variant = value.get("turn_hashes")
	if stage < 0 or not names is Array: return []
	return names.filter(func(wanted: Variant) -> bool: return not has_turn(stage, str(wanted)))

## Today's nested checkpoint (each stage's proof {checkpoint, turns}), rebuilt
## from this phone's copies, for replays, room history and posted runs; a
## checkpoint that already nests, or the initial one, comes back as it is. {}
## when a turn or an earlier checkpoint is missing here.
func nested(chapter_key: String, value: Dictionary) -> Dictionary:
	if value.is_empty() or value.has("proof") or Typed.as_int(value.get("stage_index"), -1) < 1: return value.duplicate(true)
	var turns := checkpoint_turns(value)
	var before := previous(chapter_key, value)
	if turns.is_empty() or before.is_empty(): return {}
	var inner := nested(chapter_key, before)
	if inner.is_empty(): return {}
	var result := value.duplicate(true)
	result["proof"] = {"checkpoint": inner, "turns": turns}
	return result

## A pair row as the server keeps it (WIRE.md section 5: a and b fingerprints,
## a flat checkpoint) with full turns and its checkpoint nesting one stage, as
## the replay viewer and CheckpointPairs read it; {} when this phone lacks it.
func pair(chapter_key: String, row: Dictionary) -> Dictionary:
	var flat: Variant = row.get("checkpoint")
	if not flat is Dictionary or flat.has("proof"): return row.duplicate(true)
	var turns := checkpoint_turns(flat)
	var before := previous(chapter_key, flat)
	if turns.is_empty() or before.is_empty() or not row.get("a") is Dictionary or not row.get("b") is Dictionary: return {}
	if turns[0].recording_hash != row.a.get("recording_hash") or turns[-1].recording_hash != row.b.get("recording_hash"): return {}
	var result := row.duplicate(true)
	result.a = turns[0]
	result.b = turns[-1]
	result.checkpoint = flat.duplicate(true)
	result.checkpoint["proof"] = {"checkpoint": before, "turns": turns}
	return result

## Proves a flat checkpoint this phone has not proved yet, from its previous
## (proved) checkpoint and the stage's turns: this phone's copies, and `closing`
## (the closing turn the room view carries in full). `engine` derives
## checkpoints (a chapter facade). {"valid", "missing": [hashes]}; a proved one
## is kept here.
func learn(engine: Variant, definition: Dictionary, chapter_key: String, value: Dictionary, closing: Variant = null) -> Dictionary:
	if Typed.as_int(value.get("stage_index"), -1) < 1 or value.has("proof"): return {"valid": true, "missing": []}
	var wanted := str(value.get("checkpoint_hash", ""))
	if not checkpoint(wanted).is_empty(): return {"valid": true, "missing": []}
	# Proved on this phone already (derived, or nested): kept with this room's copies too.
	if KnownCheckpoints.known(wanted): return {"valid": keep_checkpoint(value), "missing": []}
	var stage := Typed.as_int(value.stage_index, 1) - 1
	if full(closing) and value.get("turn_hashes") is Array and not value.turn_hashes.is_empty() and closing.recording_hash == value.turn_hashes[-1]:
		if not keep_turn(stage, closing): return {"valid": false, "missing": []}
	var before := previous(chapter_key, value)
	if before.is_empty():
		# An earlier stage this phone never proved: its own turns first.
		if Typed.as_int(value.stage_index, 1) > 1: return {"valid": false, "missing": [], "previous": str(value.get("previous_checkpoint_hash", ""))}
		return {"valid": false, "missing": []}
	var missing := checkpoint_missing(value)
	if not missing.is_empty(): return {"valid": false, "missing": missing}
	var turns := checkpoint_turns(value)
	var derived: Dictionary = engine.derive_checkpoint(definition, before, turns[0], turns[-1], turns.slice(1, turns.size() - 1)) if turns.size() > 2 else engine.derive_checkpoint(definition, before, turns[0], turns[-1])
	if not derived.get("valid", false) or not Canonical.same(KnownCheckpoints.flat(derived.checkpoint), value): return {"valid": false, "missing": []}
	return {"valid": keep_checkpoint(value), "missing": []}

## learn() over a chain of flat checkpoints, first stage first: a phone that
## lost its copies proves every stage again once the turns are back. The
## missing hashes of every stage come back together.
func learn_chain(engine: Variant, definition: Dictionary, chapter_key: String, chain: Array, closing: Variant = null) -> Dictionary:
	# The checkpoint proved already: by hash only, nothing read.
	var newest: Variant = chain[-1] if not chain.is_empty() else null
	if not newest is Dictionary: return {"valid": false, "missing": []}
	if Typed.as_int(newest.get("stage_index"), -1) < 1 or newest.has("proof") or not checkpoint(str(newest.get("checkpoint_hash", ""))).is_empty(): return {"valid": true, "missing": []}
	if KnownCheckpoints.known(str(newest.get("checkpoint_hash", ""))): return {"valid": keep_checkpoint(newest), "missing": []}
	var missing: Array = []
	for value: Variant in chain:
		if value is Dictionary: missing.append_array(checkpoint_missing(value).filter(func(wanted: Variant) -> bool: return not (full(closing) and closing.recording_hash == wanted)))
	if not missing.is_empty(): return {"valid": false, "missing": missing}
	for value: Variant in chain:
		if not value is Dictionary: return {"valid": false, "missing": []}
		var learned := learn(engine, definition, chapter_key, value, closing)
		if not learned.valid: return learned
	return {"valid": true, "missing": []}

## nested() for `owner`'s copy of room `room_id`: what replays, room history,
## the board's run times and posted runs read. A checkpoint that is not a flat
## open turns one comes back as it is.
static func nested_for(owner_id: String, room: String, chapter_key: String, value: Dictionary, root_path: String = ROOT) -> Dictionary:
	if value.has("proof") or Typed.as_int(value.get("stage_index"), -1) < 1: return value.duplicate(true)
	return load("res://services/open_turn_store.gd").new(owner_id, room, root_path).nested(chapter_key, value)

## The room's final checkpoint once it is finished, kept proved and named, so a
## posted run can be rebuilt later (WIRE.md section 10).
func keep_final(value: Dictionary) -> bool:
	if directory().is_empty() or not keep_checkpoint(value): return false
	return AtomicFile.write_text(directory().path_join(FINAL), JSON.stringify({"checkpoint_hash": value.checkpoint_hash}))

## The finished run as the server takes it from a phone (WIRE.md section 10):
## the final checkpoint nesting every stage, from this phone's copies. {} when
## it is not here.
func final_run(chapter_key: String) -> Dictionary:
	var named := _read(directory().path_join(FINAL), 1024) if not directory().is_empty() else {}
	var last := checkpoint(str(named.get("checkpoint_hash", "")))
	return nested(chapter_key, last) if not last.is_empty() else {}

## Removes every copy `owner_id` keeps (an erased identity): its known layout
## only, folder by folder, never a generic recursive delete.
static func erase_owner(owner_id: String, root_path: String = ROOT) -> bool:
	if not Typed.valid_id(owner_id): return false
	var folder := root_path.path_join(owner_id)
	if not DirAccess.dir_exists_absolute(folder): return true
	for room: String in DirAccess.get_directories_at(folder):
		var base := folder.path_join(room)
		var parts: Array = ["checkpoints"]
		for stage_index in range(MAX_STAGES): parts.append("s%d" % stage_index)
		for part: String in parts:
			var inner := base.path_join(part)
			if not DirAccess.dir_exists_absolute(inner): continue
			for name: String in DirAccess.get_files_at(inner):
				if DirAccess.remove_absolute(inner.path_join(name)) != OK: return false
			if DirAccess.remove_absolute(inner) != OK: return false
		for name: String in DirAccess.get_files_at(base):
			if DirAccess.remove_absolute(base.path_join(name)) != OK: return false
		if DirAccess.remove_absolute(base) != OK: return false
	return DirAccess.remove_absolute(folder) == OK
