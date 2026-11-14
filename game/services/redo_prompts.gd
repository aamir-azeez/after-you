extends RefCounted
## What this phone remembers about redo prompts, so each shows only when it
## should (presentation/redo_flow.gd, presentation/redo_home_card.gd):
## - the nudge: per turn being played, when this phone first started it and
##   whether the nudge already showed for it (once per turn);
## - Home's request card: the requests whose card got Not now, so Not now
##   only puts the card away (the request stays on the room page);
## - the redo alerts question: asked once, whatever the answer.
## Presentation only and never sent. One small file, written through
## atomic_file.gd; a damaged file reads as empty, which at worst shows a
## prompt once more.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const PATH := "user://redo-prompts.json"
const VERSION := 1
## Kept per kind; the oldest go first.
const MAX_KEPT := 32
## The nudge's thresholds (owner, 2026-11-13): 8 tries or 5 minutes on the same turn.
const NUDGE_TRIES := 8
const NUDGE_SECONDS := 300

static var _shared: RefCounted

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/redo_prompts.gd").new()
	return _shared

## Tests point the shared store at their own file.
static func use_shared(store: RefCounted) -> void:
	_shared = store

var path := PATH
var _turns: Dictionary = {}
var _dismissed: Dictionary = {}
var _alerts_asked := false
var _loaded := false

func _init(storage_path: String = PATH) -> void:
	path = storage_path

## A turn's key: its try slot (services/turn_tries.gd slot_for), hashed short.
static func turn_key(slot: String) -> String:
	return slot.sha256_text().substr(0, 24)

## A request's key on Home: the room and the exact turn it names (the
## revision moves with every turn; the stage is kept for reading).
static func request_key(room_id: String, revision: int, stage_index: int) -> String:
	return "%s:%d:%d" % [room_id, revision, stage_index]

## Notes a start of the turn `key` at `now_s` (unix seconds) and answers
## whether its nudge is due: NUDGE_TRIES tries, or NUDGE_SECONDS since this
## phone first started it, and not shown yet. Showing it is mark_nudged's.
func nudge_due(key: String, tries: int, now_s: int) -> bool:
	_load()
	var turn: Dictionary = _turns.get(key, {})
	if turn.is_empty():
		turn = {"first": now_s, "shown": false}
		_turns[key] = turn
		_trim(_turns)
		_save()
	if turn.shown: return false
	return tries >= NUDGE_TRIES or now_s - int(turn.first) >= NUDGE_SECONDS

func mark_nudged(key: String) -> void:
	_load()
	var turn: Dictionary = _turns.get(key, {"first": int(Time.get_unix_time_from_system())})
	turn.shown = true
	_turns.erase(key)
	_turns[key] = turn
	_trim(_turns)
	_save()

func dismissed(key: String) -> bool:
	_load()
	return _dismissed.has(key)

func dismiss(key: String) -> void:
	_load()
	_dismissed.erase(key)
	_dismissed[key] = true
	_trim(_dismissed)
	_save()

## The player already answered the redo alerts question (presentation/notification_flow.gd).
func alerts_asked() -> bool:
	_load()
	return _alerts_asked

func note_alerts_asked() -> void:
	_load()
	_alerts_asked = true
	_save()

static func _trim(map: Dictionary) -> void:
	while map.size() > MAX_KEPT: map.erase(map.keys()[0])

func _load() -> void:
	if _loaded: return
	_loaded = true
	var value: Variant = AtomicFile.read_json(path, func(parsed: Variant) -> bool: return parsed is Dictionary and Typed.equal(parsed.get("version"), VERSION))
	if not value is Dictionary: return
	var turns: Variant = value.get("turns")
	if turns is Dictionary:
		for key: Variant in turns:
			var turn: Variant = turns[key]
			if key is String and key.length() <= 32 and turn is Dictionary and Typed.whole_number(turn.get("first")) and turn.get("shown") is bool: _turns[key] = {"first": int(turn.first), "shown": turn.shown}
	var gone: Variant = value.get("dismissed")
	if gone is Array:
		for key: Variant in gone:
			if key is String and key.length() <= 64: _dismissed[key] = true
	_alerts_asked = value.get("alerts_asked") == true
	_trim(_turns)
	_trim(_dismissed)

func _save() -> void:
	AtomicFile.write_text(path, JSON.stringify({"version": VERSION, "turns": _turns, "dismissed": _dismissed.keys(), "alerts_asked": _alerts_asked}))
