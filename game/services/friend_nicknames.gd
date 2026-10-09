extends RefCounted
## Device-local friend labels. Entries are separated by the API server and identity owner.
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
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("schema_version") != VERSION or not parsed.get("entries") is Array: return
	for value: Variant in parsed.entries:
		if not value is Dictionary or value.size() != 4: continue
		var server: Variant = value.get("server")
		var owner: Variant = value.get("owner")
		var friend: Variant = value.get("friend")
		var nickname: Variant = value.get("nickname")
		if not server is String or server.strip_edges().is_empty() or not owner is String or owner.is_empty() or not friend is String or friend.is_empty() or not nickname is String: continue
		if nickname.strip_edges() != nickname or not _valid_nickname(nickname) or nickname.is_empty(): continue
		_entries.append({"server":server,"owner":owner,"friend":friend,"nickname":nickname})

func _save() -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"schema_version":VERSION,"entries":_entries}))
	return file.get_error() == OK
