extends RefCounted
## Device-local friend labels. Entries are separated by the API server and identity owner.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const MAX_LENGTH := 32
const FILE_PATH := "user://friend_nicknames.json"
const VERSION := 1
var path := FILE_PATH
var _entries: Array[Dictionary] = []

func _init(storage_path: String = FILE_PATH) -> void:
	path = storage_path
	_load()

func nickname(server: String, owner: String, friend: String) -> String:
	for entry: Dictionary in _entries:
		if entry.server == server and entry.owner == owner and entry.friend == friend:
			return str(entry.nickname)
	return ""

## What a friend is called when this player has given them no nickname. Players
## never see a raw player id as a name.
const FALLBACK := "a friend"

## The single friend-label resolver. Returns this device's nickname when set,
## otherwise the supplied fallback, otherwise "a friend". Reuse this everywhere
## a friend is named so hub, room, Friends and replay screens stay consistent.
func display_name(server: String, owner: String, friend: String, fallback: String = "") -> String:
	var name := nickname(server, owner, friend)
	if not name.is_empty(): return name
	return fallback if not fallback.is_empty() else FALLBACK

## A friend's name at the start of a sentence: "A friend" for the fallback, a
## nickname exactly as the player typed it.
static func sentence_start(name: String) -> String:
	return "A friend" if name == FALLBACK else name

func set_nickname(server: String, owner: String, friend: String, value: String) -> bool:
	if server.strip_edges().is_empty() or owner.is_empty() or friend.is_empty(): return false
	var nickname := value.strip_edges()
	if not _valid_nickname(nickname): return false
	var remaining: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if entry.server != server or entry.owner != owner or entry.friend != friend: remaining.append(entry)
	_entries = remaining
	if not nickname.is_empty(): _entries.append({"server":server,"owner":owner,"friend":friend,"nickname":nickname})
	return _save()

func clear_friend(server: String, owner: String, friend: String) -> void:
	var remaining: Array[Dictionary] = []
	var changed := false
	for entry: Dictionary in _entries:
		if entry.server == server and entry.owner == owner and entry.friend == friend: changed = true
		else: remaining.append(entry)
	if changed:
		_entries = remaining
		_save()

func clear_owner(owner: String, server: String = "") -> void:
	var remaining: Array[Dictionary] = []
	var changed := false
	for entry: Dictionary in _entries:
		if entry.owner == owner and (server.is_empty() or entry.server == server): changed = true
		else: remaining.append(entry)
	if changed:
		_entries = remaining
		_save()

static func _valid_nickname(value: String) -> bool:
	if value.length() > MAX_LENGTH: return false
	for i in range(value.length()):
		var codepoint := value.unicode_at(i)
		if codepoint < 32 or codepoint in range(127,160): return false
	return true

func _load() -> void:
	_entries.clear()
	# A copy left by a write cut off part way is read only when the file itself is missing or damaged.
	var entries: Variant = _entries_from(AtomicFile.read_text(path, func(text: String) -> bool: return _entries_from(text) != null))
	if entries != null: _entries = entries

## The valid entries in a saved file's text, or null when the file is not one.
func _entries_from(text: String) -> Variant:
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not parsed is Dictionary or not Typed.equal(parsed.get("schema_version"), VERSION) or not parsed.get("entries") is Array: return null
	var entries: Array[Dictionary] = []
	for value: Variant in parsed.entries:
		if not value is Dictionary or value.size() != 4: continue
		var server: Variant = value.get("server")
		var owner: Variant = value.get("owner")
		var friend: Variant = value.get("friend")
		var nickname: Variant = value.get("nickname")
		if not server is String or server.strip_edges().is_empty() or not owner is String or owner.is_empty() or not friend is String or friend.is_empty() or not nickname is String: continue
		if nickname.strip_edges() != nickname or not _valid_nickname(nickname) or nickname.is_empty(): continue
		entries.append({"server":server,"owner":owner,"friend":friend,"nickname":nickname})
	return entries

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version":VERSION,"entries":_entries}))
