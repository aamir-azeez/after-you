extends RefCounted
## The looks pips wore in turns, kept on this phone so a replay draws each turn
## in its own look (backend/src/pollen/room-looks.ts), whatever either player
## wears now.
##
## - turns: recording hash -> look ({slot: id}). A recording hash names one
##   turn's recording everywhere, so no room or server scope is needed. Filled
##   from room reads and turn replies (`turn_looks`, the other member's turns),
##   from replay transfers (every turn), and from this player's own accepted
##   turns. A turn with no entry was played in the default look.
## - members: player id -> the look that member wears now, from `partner_look`,
##   for a room's waiting view and the partner's live pip.
##
## Kept separate from hard runs and every other turn record on purpose:
## services/hard_mode.gd valid_run counts a run's fields exactly, so a look
## must never ride in one. One small file written whole with AtomicFile, only
## when something changed; a file that cannot be read reads as empty (looks
## come again with the next room read). The oldest entries go past the bounds.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const Wardrobe = preload("res://services/wardrobe.gd")

const PATH := "user://turn_looks.json"
const VERSION := 1
const MAX_TURNS := 512
const MAX_MEMBERS := 64
const HASH_PATTERN := "^[a-f0-9]{64}$"
const PLAYER_PATTERN := "^[A-Za-z0-9_-]{22}$"

static var _shared: RefCounted = null
static var _hash := RegEx.create_from_string(HASH_PATTERN)
static var _player := RegEx.create_from_string(PLAYER_PATTERN)

var path := PATH
## Insertion ordered: the oldest key first.
var _turns: Dictionary = {}
var _members: Dictionary = {}

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/turn_looks.gd").new()
	return _shared

## Installs a store as the shared one (tests), or clears it with null.
static func use_shared(store: RefCounted) -> void:
	_shared = store

func _init(storage_path: String = PATH) -> void:
	path = storage_path
	_load()

static func valid_hash(value: Variant) -> bool:
	return value is String and _hash.search(value) != null

static func valid_player(value: Variant) -> bool:
	return value is String and _player.search(value) != null

## The look a turn was played in ({} for the default look or an unknown turn).
func look(recording_hash: String) -> Dictionary:
	return (_turns.get(recording_hash, {}) as Dictionary).duplicate()

func has(recording_hash: String) -> bool:
	return _turns.has(recording_hash)

## The look a room member wore when this phone last heard ({} when unknown).
func member(player_id: String) -> Dictionary:
	return (_members.get(player_id, {}) as Dictionary).duplicate()

## One turn's look. The default look is kept too, so a known default turn is
## told apart from one this phone never heard of.
func note_turn(recording_hash: String, value: Variant) -> bool:
	if not valid_hash(recording_hash) or not value is Dictionary: return false
	var kept := Wardrobe.checked_look(value)
	if kept.size() != (value as Dictionary).size(): return false
	if _turns.get(recording_hash) == kept: return false
	_put(_turns, recording_hash, kept, MAX_TURNS)
	_save()
	return true

## A reply's `turn_looks` ({recording hash: look}); returns how many were new. One save at most.
func note_turns(value: Variant) -> int:
	if not value is Dictionary or value.size() > MAX_TURNS: return 0
	var noted := 0
	for recording_hash: Variant in value:
		var entry: Variant = value[recording_hash]
		if not valid_hash(recording_hash) or not entry is Dictionary: continue
		var kept := Wardrobe.checked_look(entry)
		if kept.size() != (entry as Dictionary).size() or _turns.get(recording_hash) == kept: continue
		_put(_turns, recording_hash, kept, MAX_TURNS)
		noted += 1
	if noted > 0: _save()
	return noted

## A reply's `partner_look` for `player_id`.
func note_member(player_id: String, value: Variant) -> bool:
	if not valid_player(player_id) or not value is Dictionary: return false
	var kept := Wardrobe.checked_look(value)
	if kept.size() != (value as Dictionary).size() or _members.get(player_id) == kept: return false
	_put(_members, player_id, kept, MAX_MEMBERS)
	_save()
	return true

static func _put(map: Dictionary, key: String, value: Dictionary, limit: int) -> void:
	map.erase(key)
	map[key] = value
	while map.size() > limit: map.erase(map.keys()[0])

func _load() -> void:
	_turns = {}
	_members = {}
	var parsed: Variant = _parsed(AtomicFile.read_text(path, func(text: String) -> bool:
		var value: Variant = _parsed(text)
		return value is Dictionary and Typed.equal(value.get("schema_version"), VERSION)))
	if not parsed is Dictionary: return
	for pair: Array in [[parsed.get("turns"), _turns, MAX_TURNS, func(key: Variant) -> bool: return valid_hash(key)],
			[parsed.get("members"), _members, MAX_MEMBERS, func(key: Variant) -> bool: return valid_player(key)]]:
		var saved: Variant = pair[0]
		if not saved is Dictionary: continue
		for key: Variant in saved:
			var entry: Variant = saved[key]
			if not (pair[3] as Callable).call(key) or not entry is Dictionary: continue
			var kept := Wardrobe.checked_look(entry)
			if kept.size() == (entry as Dictionary).size(): _put(pair[1], key, kept, pair[2])

## JSON text as a value, or null, without logging an error for a missing or damaged file.
static func _parsed(text: String) -> Variant:
	var json := JSON.new()
	return json.data if not text.is_empty() and json.parse(text) == OK else null

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "turns": _turns, "members": _members}))
