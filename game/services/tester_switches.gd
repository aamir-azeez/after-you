extends RefCounted
## What a tester's own test codes switched on this phone (backend src/test-codes.ts). The server
## only says yes to a code typed in the tester code field and names the action; this keeps it, per
## server and player (a scope), so a restart keeps it too. Nothing here is a gameplay record:
## the keepsake ledger, the Hard marks, the chapter journals, cloud save and Pollen claims are
## never written, so a switch can always be undone and a real clear is never lost.
##
## Keepsakes, as Home, the chapter chain and the Hard picker see them (Main reads them through
## earned() and hard()):
## - "" (unset): the real marks.
## - "all" (grant_keepsakes): every keepsake place solo and with a friend, and both Hard marks
##   of every chapter that has them, so every keepsake shows with every upgrade and every
##   chapter and Hard play is open.
## - "fresh" (reset_keepsakes): a new player's Home. Only what this phone's play records from
##   then on shows (a stage kept, a room's turn saved, a Hard play finished: note_award and
##   note_hard), and the chapters already played no longer stay open on their own.
## The same code again goes back to the real marks; the other code switches straight over.
##
## Full Journey: while the server has this player's switch on (the code's answer, then every
## capabilities read: full_journey_off), Main treats them as without Full Journey. Their store
## purchase and tester grant are untouched.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const HardMode = preload("res://services/hard_mode.gd")
const Registry = preload("res://services/chapter_registry.gd")

const PATH := "user://tester_switches.json"
const VERSION := 1
const ALL := "all"
const FRESH := "fresh"
const MODES := [ALL, FRESH]
## The actions the server may name (tester_access.gd checks replies against these).
const ACTIONS := ["grant_keepsakes", "reset_keepsakes", "full_journey_off", "full_journey_on"]
## Scopes kept; more than this keeps the newest.
const MAX_SCOPES := 8
const MAX_KEY := 64

static var _shared: RefCounted = null

var path := PATH
## () -> {server, owner} for the signed-in player, or {} (Main._names_scope). Tests set their own.
var scope_source: Callable
## The scope scope_source last named. A chapter screen replaces Main (its scope_source then goes
## invalid) and records its awards there, so they count for the player Main last had signed in.
var _last_key := ""
## Moves on with every change, so a view built from these switches knows to build again.
var generation := 0
## scope -> {"keepsakes": "" | ALL | FRESH, "earned": {place: {solo, friend}}, "hard": {key: {solo, together}}, "full_journey_off": bool}
var _scopes: Dictionary = {}

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/tester_switches.gd").new()
	return _shared

## Installs a store as the shared one (tests), or clears it with null.
static func use_shared(store: RefCounted) -> void:
	_shared = store

func _init(storage_path: String = PATH) -> void:
	path = storage_path
	_load()

static func scope_key(server: String, owner: String) -> String:
	return server.strip_edges().trim_suffix("/") + "|" + owner

func _current_key() -> String:
	if not scope_source.is_valid(): return _last_key
	var value: Variant = scope_source.call()
	if not value is Dictionary or str(value.get("owner", "")).is_empty() or str(value.get("server", "")).strip_edges().is_empty(): _last_key = ""
	else: _last_key = scope_key(str(value.server), str(value.owner))
	return _last_key

func _entry(key: String) -> Dictionary:
	return _scopes.get(key, {}) if not key.is_empty() else {}

# Reading ------------------------------------------------------------------

## "", ALL or FRESH for the signed-in player.
func keepsakes() -> String:
	return str(_entry(_current_key()).get("keepsakes", ""))

## Whether the signed-in player is to be treated as without Full Journey.
func full_journey_off() -> bool:
	return _entry(_current_key()).get("full_journey_off", false) == true

## Keepsake places as Home reads them: `real` is HomeKeepsakes.earned_descriptors().
func earned(real: Array[Dictionary]) -> Array[Dictionary]:
	match keepsakes():
		ALL: return _descriptors(func(item: Dictionary) -> Dictionary: return {"solo": true, "friend": bool(item.get("friend_available", true))})
		FRESH:
			var marks: Dictionary = _entry(_current_key()).get("earned", {})
			return _descriptors(func(item: Dictionary) -> Dictionary: return marks.get(item.id, {}))
	return real

## Hard marks as Home reads them: `real` is HardMode.marks().
func hard(real: Dictionary) -> Dictionary:
	match keepsakes():
		ALL:
			var marks := {}
			for key: String in HardMode.eligible_keys(): marks[key] = {HardMode.SOLO: true, HardMode.TOGETHER: true}
			return marks
		FRESH: return (_entry(_current_key()).get("hard", {}) as Dictionary).duplicate(true)
	return real

static func _descriptors(mark_of: Callable) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in Catalog.all():
		var mark: Dictionary = mark_of.call(item)
		var solo: bool = mark.get("solo", false) == true
		var friend: bool = mark.get("friend", false) == true and bool(item.get("friend_available", true))
		if not solo and not friend: continue
		item.solo = solo
		item.friend = friend
		result.append(item)
	return result

# Changing -------------------------------------------------------------------

## A test code's answer for the signed-in player: {"ok", "state"} where state is what now shows
## ("all", "fresh" or "real" for keepsakes; "off" or "on" for Full Journey). ok is false when there
## is no signed-in player, the action is unknown, or the file could not be written (nothing changed).
func apply(action: String) -> Dictionary:
	var key := _current_key()
	if key.is_empty() or not action in ACTIONS: return {"ok": false, "state": ""}
	var entry := _entry(key).duplicate(true)
	var state := ""
	match action:
		"grant_keepsakes", "reset_keepsakes":
			var wanted := ALL if action == "grant_keepsakes" else FRESH
			if str(entry.get("keepsakes", "")) == wanted:
				entry.erase("keepsakes")
				state = "real"
			else:
				entry.keepsakes = wanted
				state = wanted
			# A fresh view starts empty each time it is switched on.
			entry.erase("earned")
			entry.erase("hard")
		_:
			if action == "full_journey_off": entry.full_journey_off = true
			else: entry.erase("full_journey_off")
			state = "off" if action == "full_journey_off" else "on"
	return {"ok": _put(key, entry), "state": state}

## A capabilities read for a scope: whether the server has this player's Full Journey switch on.
func note_full_journey(server: String, owner: String, off: bool) -> void:
	if owner.is_empty() or server.strip_edges().is_empty(): return
	var key := scope_key(server, owner)
	var entry := _entry(key).duplicate(true)
	if (entry.get("full_journey_off", false) == true) == off: return
	if off: entry.full_journey_off = true
	else: entry.erase("full_journey_off")
	_put(key, entry)

## A keepsake award this phone just recorded (HomeKeepsakes.award_observer): kept only while the
## signed-in player's keepsakes are fresh.
func note_award(ids: Array, variant: String) -> void:
	var key := _current_key()
	var entry := _entry(key)
	if entry.get("keepsakes", "") != FRESH or not variant in ["solo", "friend"]: return
	var next := entry.duplicate(true)
	var marks: Dictionary = next.get("earned", {})
	for id: Variant in ids:
		if not id is String or Catalog.by_id(id).is_empty(): continue
		var mark: Dictionary = marks.get(id, {"solo": false, "friend": false})
		mark[variant] = true
		marks[id] = mark
	next.earned = marks
	if next != entry: _put(key, next)

## A Hard play this phone just finished (HardMode.record_observer), kept as note_award keeps awards.
func note_hard(chapter_key: String, mode: String) -> void:
	var key := _current_key()
	var entry := _entry(key)
	if entry.get("keepsakes", "") != FRESH or not mode in HardMode.MODES or chapter_key.length() > MAX_KEY: return
	var next := entry.duplicate(true)
	var marks: Dictionary = next.get("hard", {})
	var offered := Registry.offered_key(chapter_key)
	var mark: Dictionary = marks.get(offered, {HardMode.SOLO: false, HardMode.TOGETHER: false})
	mark[mode] = true
	marks[offered] = mark
	next.hard = marks
	if next != entry: _put(key, next)

## Forgets everything kept for a player on every server (account deletion). False when the file
## could not be written.
func clear_owner(owner: String) -> bool:
	var changed := false
	for key: String in _scopes.keys():
		if key.get_slice("|", 1) == owner:
			_scopes.erase(key)
			changed = true
	if changed: generation += 1
	return _save() and AtomicFile.remove_unreadable(path)

# Storage --------------------------------------------------------------------

## Keeps `entry` for `key` (an entry with nothing switched goes), on disk first. False and
## unchanged when the write fails.
func _put(key: String, entry: Dictionary) -> bool:
	var before := _scopes.duplicate(true)
	_scopes.erase(key)
	if not entry.is_empty(): _scopes[key] = entry
	while _scopes.size() > MAX_SCOPES: _scopes.erase(_scopes.keys()[0])
	if not _save():
		_scopes = before
		return false
	generation += 1
	return true

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "scopes": _scopes}))

func _load() -> void:
	_scopes = {}
	var parsed: Variant = AtomicFile.read_json(path, func(value: Variant) -> bool:
		return value is Dictionary and Typed.equal(value.get("schema_version"), VERSION) and value.get("scopes") is Dictionary)
	if not parsed is Dictionary: return
	for key: Variant in parsed.scopes:
		var entry: Variant = parsed.scopes[key]
		if key is String and key.contains("|") and entry is Dictionary and _valid_entry(entry): _scopes[key] = entry
	while _scopes.size() > MAX_SCOPES: _scopes.erase(_scopes.keys()[0])

## Anything unexpected drops the whole entry: the player then sees their real progress.
static func _valid_entry(entry: Dictionary) -> bool:
	for name: Variant in entry:
		if not name in ["keepsakes", "earned", "hard", "full_journey_off"]: return false
	if entry.has("keepsakes") and not (entry.keepsakes is String and entry.keepsakes in MODES): return false
	if entry.has("full_journey_off") and not Typed.equal(entry.full_journey_off, true): return false
	for name: String in ["earned", "hard"]:
		if not entry.has(name): continue
		if not Typed.equal(entry.get("keepsakes"), FRESH) or not entry[name] is Dictionary or entry[name].size() > Catalog.ROWS.size(): return false
		for id: Variant in entry[name]:
			var mark: Variant = entry[name][id]
			if not id is String or id.length() > MAX_KEY or not mark is Dictionary: return false
			for value: Variant in mark.values():
				if not value is bool: return false
	return true
