extends RefCounted
## Who this player is already linked with, kept from the last friends list so
## screens that never load the list (a room, the room list) can tell a friend
## from a room partner. Statuses are the list's: accepted, outgoing (a request
## this player sent) and incoming. A request sent from a room is outgoing at
## once, before the next list read confirms it.
##
## One shared instance (shared()) backs every screen; tests make their own.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const DisplayNames = preload("res://services/display_names.gd")
const PATH := "user://friend_roster.json"
const VERSION := 1
const STATUSES := ["accepted", "outgoing", "incoming"]
## The friends list holds at most 20 rows; a few more leave room for requests
## sent from rooms before the next read.
const MAX_ENTRIES := 40

static var _shared: RefCounted = null

var path := PATH
var _scopes: Dictionary = {}

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/friend_roster.gd").new()
	return _shared

static func use_shared(store: RefCounted) -> void:
	_shared = store

func _init(storage_path: String = PATH) -> void:
	path = storage_path
	_load()

static func _key(server: String, owner: String) -> String:
	return DisplayNames.scope_key(server, owner)

## A player's status with this player: accepted, outgoing, incoming or "".
func status(server: String, owner: String, player: String) -> String:
	return str(_scopes.get(_key(server, owner), {}).get(player, ""))

## Whether this phone has read the friends list for this player at least once.
func known(server: String, owner: String) -> bool:
	return _scopes.has(_key(server, owner))

## A friends list page replaces what an earlier page said.
func take_page(server: String, owner: String, page: Dictionary) -> void:
	if owner.is_empty() or server.strip_edges().is_empty(): return
	var rows := {}
	for row: Variant in page.get("friends", []):
		if row is Dictionary and row.get("player_id") is String and row.get("status") in STATUSES: rows[row.player_id] = row.status
	if _scopes.get(_key(server, owner)) == rows: return
	_scopes[_key(server, owner)] = rows
	_save()

## A request this player just sent; the next list read confirms or replaces it.
func note_request(server: String, owner: String, player: String) -> void:
	if owner.is_empty() or player.is_empty() or server.strip_edges().is_empty(): return
	var rows: Dictionary = _scopes.get(_key(server, owner), {})
	if rows.has(player) or rows.size() >= MAX_ENTRIES: return
	rows[player] = "outgoing"
	_scopes[_key(server, owner)] = rows
	_save()

func clear_owner(owner: String) -> void:
	var changed := false
	for key: String in _scopes.keys():
		if key.get_slice("|", 1) == owner:
			_scopes.erase(key)
			changed = true
	if changed: _save()

func _load() -> void:
	_scopes = {}
	var parsed: Variant = JSON.parse_string(AtomicFile.read_text(path, func(text: String) -> bool: return JSON.parse_string(text) is Dictionary))
	if not parsed is Dictionary or not Typed.equal(parsed.get("schema_version"), VERSION) or not parsed.get("scopes") is Dictionary: return
	for key: Variant in parsed.scopes:
		var rows: Variant = parsed.scopes[key]
		if not key is String or not key.contains("|") or not rows is Dictionary: continue
		var kept := {}
		for player: Variant in rows:
			if player is String and player.length() == 22 and rows[player] in STATUSES and kept.size() < MAX_ENTRIES: kept[player] = rows[player]
		_scopes[key] = kept

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "scopes": _scopes}))
