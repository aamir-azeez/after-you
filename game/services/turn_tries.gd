extends RefCounted
## How many tries each turn took, for the Try pill in play and the counts in
## Replays. Presentation only: a count is never part of a recording, its hash,
## a checkpoint or a replay's bytes.
##
## A turn being played has an open count under its slot (slot_for): the solo
## chapter or the room and its branch, the stage, the role and the start it is
## played from. Each start of the slot counts one try: the first, every Retry
## from review or pause, and a restart after a failed ending. Resuming a saved
## draft is not a start, so a turn resumed after the app closed keeps its
## count. When the turn is saved or sent its count is kept under the
## recording's hash; a friend's counts read from the server are kept the same
## way. Open counts live in their own small file, written on every start; kept
## counts change only on a save, a send or a server read. Every change re-reads
## its file first, so screens that each hold one of these never undo each
## other's counts.
##
## The open counts change on taps (Begin, Retry), so their file is written
## on a worker, never in the tap's frame (a whole small-file write and
## read-back held the Begin frame 6 to 10 ms on a desktop). One worker at a
## time writes a file, always the newest counts, and until they are written
## every holder reads them instead of the file. The kept counts are written as
## before.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const FILE_PATH := "user://turn-tries.json"
const VERSION := 1
const MAX_TRIES := 999
const MAX_OPEN := 64
## Counts of one are not kept: a first try shows nothing, as a turn from an
## older build does.
const MAX_KEPT := 1024
const MAX_READS := 128
const SOLO := "solo"
const ROOM := "room"
## Kept counts and, per room, what the last server read covered.
var path := FILE_PATH
var open_path := ""
var _open: Dictionary = {}
var _kept: Dictionary = {}
var _reads: Dictionary = {}
## Open counts not written yet, as the file's text by its path, and the paths
## a worker is writing. Shared with the workers: only under _lock.
static var _soon: Dictionary = {}
static var _writing: Dictionary = {}
static var _lock := Mutex.new()

func _init(storage_path: String = FILE_PATH) -> void:
	path = storage_path
	open_path = storage_path.get_basename() + "-open.json"
	_load_open()
	_load_kept()

## The slot of the turn a journey (solo) or room coordinator (online) is on.
static func slot_for(journey: RefCounted, chapter_key: String, online: bool) -> String:
	var scope := solo_scope(chapter_key)
	if online:
		var room: Dictionary = journey.snapshot()
		scope = "%s|%s|%d" % [ROOM, str(room.get("room_id", "")), int(room.get("branch", -1))]
	return "|".join([scope, str(journey.stage_id()), str(journey.role()), str(journey.checkpoint().get("checkpoint_hash", "")), str(journey.prior_recording().get("recording_hash", ""))])

## Every solo slot of a chapter starts with this; a redo moves a room to a
## new branch instead, so its turns start new counts by themselves.
static func solo_scope(chapter_key: String) -> String:
	return SOLO + "|" + chapter_key

## One start of the turn in `slot`. Returns the try it is now on.
func start(turn_slot: String) -> int:
	_load_open()
	var tries := mini(count(turn_slot) + 1, MAX_TRIES)
	_open.erase(turn_slot)
	_open[turn_slot] = tries
	_trim(_open, MAX_OPEN)
	_save_open()
	return tries

## The open count of `slot`; 0 before its first start.
func count(turn_slot: String) -> int:
	return int(_open.get(turn_slot, 0))

## A resumed draft is the try it was started on. A draft from before counts
## were kept (or one trimmed out) is taken as the first try.
func resume(turn_slot: String) -> int:
	return count(turn_slot) if count(turn_slot) > 0 else start(turn_slot)

## The turn is being saved or sent: its count is kept under the recording,
## and returned (0 when the turn was never started here). The slot stays open
## until close(), so a refused send and another Retry go on counting.
func freeze(turn_slot: String, recording_hash: String) -> int:
	_load_open()
	var tries := count(turn_slot)
	if tries > 1 and _hash(recording_hash):
		_load_kept()
		_keep(recording_hash, tries)
		_save_kept()
	return tries

## The turn was saved or accepted; its slot is done.
func close(turn_slot: String) -> void:
	_load_open()
	if _open.erase(turn_slot): _save_open()

## A solo redo or restart: every open count of the chapter starts again.
func restart_solo(chapter_key: String) -> void:
	_load_open()
	var changed := false
	for key: String in _open.keys():
		if key.begins_with(solo_scope(chapter_key) + "|"):
			_open.erase(key)
			changed = true
	if changed: _save_open()

## The count a saved turn took; 0 when it is unknown or was a first try.
func tries(recording_hash: String) -> int:
	return int(_kept.get(recording_hash, 0))

## Whether a room's counts should be read again: `covered` names what the
## room lists (its parts), and changes when a turn is added.
func read_wanted(room_id: String, covered: String) -> bool:
	return _reads.get(room_id) != covered

## Counts read from the server for a room, by recording hash, and what the
## read covered.
func remember(counts: Dictionary, room_id: String = "", covered: String = "") -> void:
	_load_kept()
	for recording_hash: Variant in counts:
		var value: Variant = counts[recording_hash]
		if not recording_hash is String or not _hash(recording_hash) or not Typed.whole_number(value) or int(value) < 1 or int(value) > MAX_TRIES: continue
		if int(value) > 1 and tries(recording_hash) != int(value): _keep(recording_hash, int(value))
	if not room_id.is_empty():
		_reads.erase(room_id)
		_reads[room_id] = covered
		_trim(_reads, MAX_READS)
	_save_kept()

func _keep(recording_hash: String, tries_value: int) -> void:
	_kept.erase(recording_hash)
	_kept[recording_hash] = tries_value
	_trim(_kept, MAX_KEPT)

## Oldest first: a key is re-added at the end whenever it changes.
static func _trim(values: Dictionary, limit: int) -> void:
	while values.size() > limit: values.erase(values.keys()[0])

static func _hash(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number()

static func _count(value: Variant, least: int) -> bool:
	return Typed.whole_number(value) and int(value) >= least and int(value) <= MAX_TRIES

func _load_open() -> void:
	_lock.lock()
	var waiting: Variant = _soon.get(open_path)
	_lock.unlock()
	var text: String = waiting if waiting is String else AtomicFile.read_text(open_path, func(saved: String) -> bool: return _parse_open(saved) != null)
	var parsed: Variant = _parse_open(text)
	_open = parsed if parsed != null else {}

func _load_kept() -> void:
	var parsed: Variant = _parse_kept(AtomicFile.read_text(path, func(text: String) -> bool: return _parse_kept(text) != null))
	_kept = parsed.kept if parsed != null else {}
	_reads = parsed.reads if parsed != null else {}

## The checked open counts in a saved file's text, or null when it is not one.
## Entries that do not fit are dropped one by one.
static func _parse_open(text: String) -> Variant:
	var value: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), VERSION) or not value.get("open") is Dictionary: return null
	var open := {}
	for key: Variant in value.open:
		if key is String and key.length() <= 512 and _count(value.open[key], 1): open[key] = int(value.open[key])
	_trim(open, MAX_OPEN)
	return open

static func _parse_kept(text: String) -> Variant:
	var value: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), VERSION) or not value.get("kept") is Dictionary or not value.get("reads") is Dictionary: return null
	var kept := {}
	for key: Variant in value.kept:
		if _hash(key) and _count(value.kept[key], 2): kept[key] = int(value.kept[key])
	var reads := {}
	for key: Variant in value.reads:
		if key is String and key.length() <= 64 and value.reads[key] is String and value.reads[key].length() <= 64: reads[key] = value.reads[key]
	_trim(kept, MAX_KEPT)
	_trim(reads, MAX_READS)
	return {"kept": kept, "reads": reads}

## Hands the open counts to the file's worker (see the top). Without a
## worker they are written here.
func _save_open() -> void:
	_lock.lock()
	_soon[open_path] = _open_text()
	var start := not _writing.has(open_path)
	if start: _writing[open_path] = true
	_lock.unlock()
	# A worker still running writes these counts before it ends.
	if not start: return
	Reaper.ensure()
	var thread := Thread.new()
	if thread.start(Callable(get_script(), "_write_open").bind(open_path)) == OK:
		Reaper.adopt(thread)
	else:
		_write_open(open_path)

func _open_text() -> String:
	return JSON.stringify({"schema_version": VERSION, "open": _open}, "", false)

## The worker: writes the newest waiting counts of file until none are left.
static func _write_open(file: String) -> void:
	while true:
		_lock.lock()
		var text: Variant = _soon.get(file)
		if not text is String:
			_writing.erase(file)
			_lock.unlock()
			return
		_lock.unlock()
		AtomicFile.write_text(file, text)
		_lock.lock()
		# Newer counts handed over meanwhile stay waiting for the next pass.
		if _soon.get(file) == text: _soon.erase(file)
		_lock.unlock()

## Whether open counts of file are still waiting to be written.
static func writing(file: String) -> bool:
	_lock.lock()
	var busy := _writing.has(file) or _soon.has(file)
	_lock.unlock()
	return busy

func _save_kept() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "kept": _kept, "reads": _reads}, "", false))
