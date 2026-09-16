extends RefCounted
## Explicit, confirmed deletion only. Flat known stores; no recursive removal.
const Relay = preload("res://services/relay_online_store.gd")
const Shared = preload("res://services/shared_replay_store.gd")
const Safety = preload("res://services/safety_store.gd")
const Photos = preload("res://services/deleted_identity_photo_cleanup.gd")
const MAX_FILES := 4096
var relay_directory := "user://relay-online"
var shared_directory := "user://shared-replays"
var safety_directory := "user://safety"

func erase_owner(owner: String) -> Dictionary:
	if not Photos.valid_owner(owner): return {"ok": false, "error": "invalid_owner"}
	# Resolve ownership of every group before changing either store. An unknown
	# corrupt group is held, never guessed to belong to this or another player.
	var relay := _owned_files(owner, relay_directory, "relay_online_scope", Relay.MAX_BYTES)
	var shared := _owned_files(owner, shared_directory, "shared_replay_scope", Shared.MAX_BYTES)
	if not relay.ok or not shared.ok: return {"ok": false, "error": "cache_ownership_unreadable"}
	for path: String in relay.paths + shared.paths:
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			return {"ok": false, "error": "cache_cleanup_unfinished"}
	if not Safety.new(safety_directory).erase(owner): return {"ok": false, "error": "safety_cleanup_unfinished"}
	return {"ok": true}

func _owned_files(owner: String, directory: String, field: String, max_bytes: int) -> Dictionary:
	var result := {"ok": false, "paths": []}
	if not DirAccess.dir_exists_absolute(directory):
		result.ok = not FileAccess.file_exists(directory)
		return result
	var parent := DirAccess.open(directory.get_base_dir())
	if parent == null or parent.is_link(directory.get_file()): return result
	var dir := DirAccess.open(directory)
	if dir == null or dir.list_dir_begin() != OK: return result
	var groups: Dictionary = {}
	var count := 0
	var name := dir.get_next()
	while not name.is_empty():
		count += 1
		if count > MAX_FILES or dir.current_is_dir() or dir.is_link(name):
			dir.list_dir_end()
			return result
		if not Safety.matches(name, "^[a-f0-9]{64}\\.json(?:\\.backup|\\.tmp)?$"):
			dir.list_dir_end()
			return result
		var base := name.get_slice(".", 0) + ".json"
		if not groups.has(base): groups[base] = []
		groups[base].append(directory.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	for base: String in groups:
		var scoped_owner := ""
		var anchor := ""
		# Index/lobby filenames alone identify these exact owner scopes, even
		# after an interrupted write. Room groups require a surviving envelope.
		var known := ("relay-lobby-v2:" if field == "relay_online_scope" else "shared-replays:") + owner
		if field != "relay_online_scope": known += ":index"
		if base == known.sha256_text() + ".json": scoped_owner = owner
		for path: String in groups[base]:
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null or file.get_length() > max_bytes: return result
			var parser := JSON.new()
			var parsed := parser.parse(file.get_as_text())
			file.close()
			if parsed != OK: continue
			if not parser.data is Dictionary or not parser.data.get(field) is String: continue
			var scope: String = parser.data[field]
			var valid := Relay._valid_scope(scope) if field == "relay_online_scope" else Shared._scope_valid(scope)
			if not valid or base != scope.sha256_text() + ".json": return result
			var candidate := scope.get_slice(":", 1)
			if not scoped_owner.is_empty() and candidate != scoped_owner: return result
			scoped_owner = candidate
			anchor = path
		if scoped_owner.is_empty(): return result
		if scoped_owner == owner:
			# Keep a readable ownership envelope until the final removal so an
			# interrupted purge can identify remaining truncated generations.
			for path: String in groups[base]:
				if path != anchor: result.paths.append(path)
			if not anchor.is_empty(): result.paths.append(anchor)
	result.ok = true
	return result
