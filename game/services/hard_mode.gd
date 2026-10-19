extends RefCounted
## Hard mode: a chapter played whole, in one go, with no retries, solo or with
## a friend. One place for its rules, which chapters have it and when it
## unlocks, its completion marks, the archive of hard runs and the hand-off
## that opens a chapter in hard mode. Hard mode changes no chapter's rules,
## recordings, checkpoints or hashes; it only takes the ways to play a turn
## again away and ends the run when one is taken anyway.
##
## - Rules: a hard run offers none of WITHHELD; a second start of a turn
##   (TurnTries count past 1) or a finished turn that cannot be kept ends it.
## - Unlocks come from the keepsake marks (ChapterCompletion): a chapter
##   finished solo or with a friend opens both hard plays. Those marks are
##   rebuilt from the journals and shared replays, so no unlock is kept here.
## - Marks: which hard plays are done, in their own small file (MARKS_PATH).
##   A mark only ever turns on.
## - Runs: the last MAX_FAILED failed runs per chapter and mode, and the last
##   finished solo run, in one file per chapter beside its journal.
const AtomicFile = preload("res://services/atomic_file.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Typed = preload("res://services/typed_values.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const MARKS_PATH := "user://hard-mode-v1.json"
const VERSION := 1
const SOLO := "solo"
const TOGETHER := "together"
const MODES := [SOLO, TOGETHER]
## A mark's look on the menus.
const LOCKED := "locked"
const OPEN := "open"
const DONE := "done"
## Every way to play a turn or a stage again, or take one back.
const WITHHELD := ["retry", "try_again", "restart", "checkpoints", "solo_redo", "redo", "redo_answer"]
## How a run ended early: a second start of a turn, a turn that could not be
## kept, a turn the water took.
const REASONS := ["retry", "failed_turn", "drowned"]
const FAILED := "failed"
const COMPLETE := "complete"
const MAX_FAILED := 5
const MAX_RUNS_BYTES := 2097152
const MAX_MARKS_BYTES := 16384
const MAX_STAGES := 64

static var _launch: Dictionary = {}

var path := MARKS_PATH
var _marks: Dictionary = {}

func _init(marks_path: String = MARKS_PATH) -> void:
	path = marks_path
	_load()


# Rules ------------------------------------------------------------------

## Whether a hard run offers the action (an action_buttons.gd or RoomActions id).
static func offers(action_id: String) -> bool:
	return action_id not in WITHHELD

## A turn started for the second time (its TurnTries count) ends the run.
static func slipped(tries: int) -> bool:
	return tries > 1

## Why a finished turn ends the run, from its verified check ({valid,
## snapshot}): "drowned", "failed_turn" (it cannot be kept, so the only way on
## would be a retry), or "" when the turn can be kept.
static func failure(verified: Dictionary) -> String:
	var snapshot: Variant = verified.get("snapshot", {})
	if snapshot is Dictionary and snapshot.get("drowned") is Dictionary and not snapshot.drowned.is_empty(): return "drowned"
	if not bool(verified.get("valid", false)) or not snapshot is Dictionary or not bool(snapshot.get("can_commit", false)): return "failed_turn"
	return ""

## The waiting friend's note when the other one slipped on `stage_index`.
static func notice_text(partner: String, stage_index: int) -> String:
	return PlayerCopy.HARD_FRIEND_NOTICE % [partner if not partner.is_empty() else PlayerCopy.HARD_FRIEND_FALLBACK, stage_index + 1]

## The scope a solo hard run counts tries under, apart from the chapter's own.
static func tries_key(chapter_key: String) -> String:
	return chapter_key + "#hard"


# Chapters and unlocks ----------------------------------------------------

## Whether a chapter has hard plays: every offered chapter with its own solo
## screen. The Lighthouse (its own card and migration) and the earlier
## islands have none.
static func eligible(chapter_key: String) -> bool:
	return chapter_key in Registry.offered_keys() and not Registry.solo_scene(chapter_key).is_empty() and not Registry.is_lighthouse(chapter_key)

static func eligible_keys() -> Array[String]:
	var keys: Array[String] = []
	for key: String in Registry.offered_keys():
		if eligible(key): keys.append(key)
	return keys

## Both hard plays open once the chapter is finished solo or with a friend.
## `marks` is ChapterCompletion.chapters(...).
static func unlocked(marks: Dictionary, chapter_key: String) -> bool:
	var mark: Variant = marks.get(chapter_key, {})
	return eligible(chapter_key) and mark is Dictionary and (_true(mark.get("solo")) or _true(mark.get("friend")))

## A mark's look: LOCKED, OPEN or DONE.
func state(marks: Dictionary, chapter_key: String, mode: String) -> String:
	if completed(chapter_key, mode): return DONE
	return OPEN if unlocked(marks, chapter_key) else LOCKED

## {chapter_key: {"solo": look, "together": look}} for every eligible chapter.
func states(marks: Dictionary) -> Dictionary:
	var result := {}
	for key: String in eligible_keys(): result[key] = {SOLO: state(marks, key, SOLO), TOGETHER: state(marks, key, TOGETHER)}
	return result

## [done, total] over every eligible chapter's two hard plays.
func count() -> Array:
	var done := 0
	var keys := eligible_keys()
	for key: String in keys:
		for mode: String in MODES: done += int(completed(key, mode))
	return [done, keys.size() * MODES.size()]


# Marks -------------------------------------------------------------------

func completed(chapter_key: String, mode: String) -> bool:
	var mark: Variant = _marks.get(Registry.offered_key(chapter_key), {})
	return mark is Dictionary and _true(mark.get(mode))

static func _true(value: Variant) -> bool:
	return value is bool and value

## Records a finished hard play. True when it is on disk.
func record(chapter_key: String, mode: String) -> bool:
	if mode not in MODES: return false
	_load()
	var key := Registry.offered_key(chapter_key)
	if completed(key, mode): return true
	var mark: Dictionary = _marks.get(key, {SOLO: false, TOGETHER: false}).duplicate()
	mark[mode] = true
	var next := _marks.duplicate(true)
	next[key] = mark
	if not AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "marks": next}, "", false), true): return false
	_marks = next
	return true

func _load() -> void:
	var text := AtomicFile.read_text(path, func(value: String) -> bool: return _parse_marks(value) != null)
	var parsed: Variant = _parse_marks(text)
	_marks = parsed if parsed != null else {}

static func _parse_marks(text: String) -> Variant:
	if text.is_empty() or text.length() > MAX_MARKS_BYTES: return null
	var parser := JSON.new()
	if parser.parse(text) != OK: return null
	var value: Variant = parser.data
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), VERSION) or not value.get("marks") is Dictionary: return null
	var marks := {}
	for key: Variant in value.marks:
		var mark: Variant = value.marks[key]
		if not key is String or key.length() > 64 or not mark is Dictionary: continue
		marks[key] = {SOLO: _true(mark.get(SOLO)), TOGETHER: _true(mark.get(TOGETHER))}
	return marks


# Paths ---------------------------------------------------------------------

## The solo hard run's own journal, beside the chapter's.
static func journal_path(chapter_key: String) -> String:
	return _beside(chapter_key, "-hard.json")

## The chapter's hard runs (runs()).
static func runs_path(chapter_key: String) -> String:
	return _beside(chapter_key, "-hard-runs.json")

static func _beside(chapter_key: String, suffix: String) -> String:
	var journal := str(Registry.descriptor(chapter_key).get("local_path", ""))
	return "" if journal.is_empty() else journal.get_basename() + suffix


# Solo journal --------------------------------------------------------------

## Starts the solo hard run again from its first stage: the journal's files
## go (by exact name) and the journey reloads empty. Never an attempt archive:
## that one keeps 32 and would stop resets after 32 slips. The run itself was
## kept by save_run first.
static func clear_journal(journey: RefCounted) -> bool:
	if journey == null or not journey.has_method("finish_live_draft_save"): return false
	journey.finish_live_draft_save()
	var target := journal_path(str(journey.chapter_key()))
	if target.is_empty() or not AtomicFile.remove(target): return false
	journey.load_data()
	return not journey.read_only and journey.pairs().is_empty() and journey.prior_recording().is_empty() and not journey.has_draft()


# Runs ----------------------------------------------------------------------

## A run as kept: {id, mode, kind, reason, by ("you", "friend" or "" when
## finished), friend (their name then), chapter_key, stage_index, role, at,
## room_id, pairs (the stages done before, solo), slip ({} or {recording,
## checkpoint, prior})}.
static func run_record(chapter_key: String, mode: String, kind: String, reason: String, by: String, stage_index: int, role: String, pairs: Array, slip: Dictionary, friend: String = "", room_id: String = "") -> Dictionary:
	var at := int(Time.get_unix_time_from_system())
	var record := {"id": "", "mode": mode, "kind": kind, "reason": reason, "by": by, "friend": friend.left(64), "chapter_key": chapter_key,
		"stage_index": stage_index, "role": role, "at": at, "room_id": room_id, "pairs": pairs.duplicate(true), "slip": slip.duplicate(true)}
	# A finished run is the same run whenever its card shows again; each
	# failure is its own, even two in the same second.
	var hashes: Array = []
	for pair: Variant in pairs: hashes.append(str(pair.get("b", {}).get("recording_hash", "")) if pair is Dictionary else "")
	var nonce := Crypto.new().generate_random_bytes(8).hex_encode() if kind == FAILED else ""
	record.id = JSON.stringify([chapter_key, mode, kind, nonce, stage_index, role, room_id, str(slip.get("recording", {}).get("recording_hash", "")), hashes]).sha256_text().left(32)
	return record

## Keeps a run: the newest MAX_FAILED failed runs per mode, the newest
## finished solo run, and never more than MAX_RUNS_BYTES (oldest go first).
## A run already kept (its id) is not added twice. True when it is on disk.
static func save_run(record: Dictionary) -> bool:
	if not valid_run(record): return false
	var chapter_key := str(record.chapter_key)
	var target := runs_path(chapter_key)
	if target.is_empty(): return false
	var kept: Array = runs(chapter_key)
	for run: Dictionary in kept:
		if run.id == record.id: return true
	kept.append(record.duplicate(true))
	kept = _bounded(kept)
	while not kept.is_empty() and _runs_text(chapter_key, kept).to_utf8_buffer().size() > MAX_RUNS_BYTES: kept.remove_at(0)
	if kept.is_empty(): return false
	return AtomicFile.write_text(target, _runs_text(chapter_key, kept), true)

## The chapter's kept runs, oldest first. A damaged file reads as none.
static func runs(chapter_key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var target := runs_path(chapter_key)
	if target.is_empty(): return result
	var text := AtomicFile.read_text(target, func(value: String) -> bool: return _parse_runs(value, chapter_key) != null)
	var parsed: Variant = _parse_runs(text, chapter_key)
	if parsed != null: result.assign(parsed)
	return result

## Every eligible chapter's kept runs, newest first.
static func all_runs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in eligible_keys(): result.append_array(runs(key))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.at) > int(b.at) or (int(a.at) == int(b.at) and str(a.id) > str(b.id)))
	return result

## Whether a run has anything to watch.
static func watchable(record: Dictionary) -> bool:
	return not record.get("pairs", []).is_empty() or not record.get("slip", {}).is_empty()

static func _bounded(kept: Array) -> Array:
	var counts := {}
	var result: Array = []
	for index in range(kept.size() - 1, -1, -1):
		var run: Dictionary = kept[index]
		var bucket := str(run.mode) + ":" + str(run.kind)
		var limit := MAX_FAILED if run.kind == FAILED else (1 if run.mode == SOLO else 0)
		counts[bucket] = int(counts.get(bucket, 0)) + 1
		if counts[bucket] <= limit: result.push_front(run)
	return result

static func _runs_text(chapter_key: String, kept: Array) -> String:
	return JSON.stringify({"schema_version": VERSION, "chapter_key": chapter_key, "runs": kept}, "", false)

static func _parse_runs(text: String, chapter_key: String) -> Variant:
	if text.is_empty() or text.length() > MAX_RUNS_BYTES: return null
	var parser := JSON.new()
	if parser.parse(text) != OK: return null
	var value: Variant = parser.data
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), VERSION) or not Typed.equal(value.get("chapter_key"), chapter_key) or not value.get("runs") is Array: return null
	var kept: Array = []
	for run: Variant in value.runs:
		if run is Dictionary and valid_run(run) and run.chapter_key == chapter_key: kept.append(_whole_numbers(run))
	return kept

## The shape every kept run has. Recordings and checkpoints are checked again
## by the chapter screen's own replay when one is watched.
static func valid_run(run: Dictionary) -> bool:
	if run.size() != 13 or not run.get("id") is String or run.id.is_empty() or run.id.length() > 64: return false
	if run.get("mode") not in MODES or run.get("kind") not in [FAILED, COMPLETE] or not run.get("chapter_key") is String or run.chapter_key.is_empty(): return false
	if run.kind == FAILED and (run.get("reason") not in REASONS or run.get("by") not in ["you", "friend"]): return false
	if run.kind == COMPLETE and (not Typed.equal(run.get("reason"), "") or not Typed.equal(run.get("by"), "")): return false
	if not run.get("friend") is String or run.friend.length() > 64 or not run.get("room_id") is String or run.room_id.length() > 22: return false
	if not Typed.whole_number(run.get("stage_index")) or int(run.stage_index) < 0 or int(run.stage_index) > MAX_STAGES or run.get("role") not in ["a", "b", ""] or not Typed.whole_number(run.get("at")): return false
	if not run.get("pairs") is Array or run.pairs.size() > MAX_STAGES or not run.get("slip") is Dictionary: return false
	for pair: Variant in run.pairs:
		if not pair is Dictionary or pair.size() != 2 or not pair.get("a") is Dictionary or not pair.get("b") is Dictionary: return false
	var slip: Dictionary = run.slip
	return slip.is_empty() or (slip.size() == 3 and slip.get("recording") is Dictionary and not slip.recording.is_empty() and slip.get("checkpoint") is Dictionary and not slip.checkpoint.is_empty() and slip.get("prior") is Dictionary)

static func _whole_numbers(run: Dictionary) -> Dictionary:
	var copy := run.duplicate(true)
	copy.stage_index = int(copy.stage_index)
	copy.at = int(copy.at)
	return copy


# Opening a chapter in hard mode ----------------------------------------------

## Main hands the next chapter scene a hard open just before it changes to
## it: {"chapter_key", "kind": "play"} for a solo hard run, or "watch" with
## {"run"} for a kept run. The scene claims it once in _ready.
static func hand_over(request: Dictionary) -> void:
	_launch = request.duplicate(true)

## The hand-off for this chapter, once; {} for any other open. A hand-off for
## another chapter is dropped, so it can never reach a later open.
static func claim(chapter_key: String) -> Dictionary:
	var request := _launch
	_launch = {}
	return request if Typed.equal(request.get("chapter_key"), chapter_key) else {}

## An open that never reached its scene.
static func drop() -> void:
	_launch = {}

## What a watch shows, as the chapter screen's replay collection: the stages
## done before the slip, then the slip itself from its own checkpoint, beside
## its first turn's memory ({"a", "b", "start"}).
static func watch_pairs(run: Dictionary) -> Array:
	var pairs: Array = run.get("pairs", []).duplicate(true)
	var slip: Dictionary = run.get("slip", {})
	if not slip.is_empty(): pairs.append({"a": slip.prior.duplicate(true), "b": slip.recording.duplicate(true), "start": slip.checkpoint.duplicate(true)})
	return pairs
