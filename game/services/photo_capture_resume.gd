extends RefCounted
## Turns that still wait for a photo after After You closed while the camera was open.
## An entry is written before the camera opens and removed once the turn's photo journal
## holds the photo, or once the player skips. A photo the native side recovered after a
## restart is attached to its entry by request ID. One small file per owner, outside the
## turn-photo journal folder, erased with the rest of an owner's photos on account deletion.
const AtomicFile = preload("res://services/atomic_file.gd")
const Capture = preload("res://services/optional_photo_capture.gd")
const RoomStages = preload("res://services/room_stages.gd")
const MAX_ENTRIES := 8
const MAX_FILE := 32 * 1024
## Long enough to come back after a busy week; an entry is only a hint to reopen a card.
const MAX_AGE_SEC := 14 * 24 * 3600
const ENTRY_KEYS := ["room_id", "turn_id", "recording_hash", "gameplay_key", "request_id", "started_unix", "photo"]
var directory := "user://photo-capture-resume"
var clock: Callable = func() -> int: return int(Time.get_unix_time_from_system())

func _init(root_path: String = "user://photo-capture-resume") -> void:
	directory = root_path

## Valid entries for this owner, newest first.
func entries(owner: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _owner(owner): return result
	var text := ""
	var path := _path(owner)
	# A write whose rename failed after the file was removed leaves only its new copy.
	# Removing the last entry removes that copy too, so it never holds a removed entry.
	if not FileAccess.file_exists(path): path += AtomicFile.TMP
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > MAX_FILE: return result
		text = file.get_as_text()
		file.close()
	if text.is_empty(): return result
	var json := JSON.new()
	if json.parse(text) != OK: return result # A damaged file reads as nothing waiting.
	var parsed: Variant = json.data
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or parsed.get("owner_player_id") != owner or not parsed.get("entries") is Array:
		return result
	var now := int(clock.call())
	for entry: Variant in parsed.entries:
		if valid_entry(entry) and now - int(entry.started_unix) <= MAX_AGE_SEC:
			result.append(entry.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.started_unix) > int(b.started_unix))
	return result

func entry_for_room(owner: String, room_id: String) -> Dictionary:
	for entry: Dictionary in entries(owner):
		if entry.room_id == room_id: return entry
	return {}

## Before the camera opens. target is the opened turn photo controller's target.
func begin(owner: String, target: Dictionary, request_id: String) -> bool:
	var entry := {"room_id": target.get("room_id"), "turn_id": target.get("turn_id"), "recording_hash": target.get("recording_hash"), "gameplay_key": target.get("gameplay_key"), "request_id": request_id, "started_unix": int(clock.call()), "photo": {}}
	if not _owner(owner) or target.get("owner_player_id") != owner or not valid_entry(entry): return false
	var kept: Array[Dictionary] = [entry]
	for other: Dictionary in entries(owner):
		if not _same_turn(other, entry) and kept.size() < MAX_ENTRIES: kept.append(other)
	return _write(owner, kept)

## A photo the native side kept for this request. False when no entry asked for it.
func attach_photo(owner: String, request_id: String, photo: Dictionary) -> bool:
	if not Capture._metadata_valid(photo): return false
	var all := entries(owner)
	var found := false
	for entry: Dictionary in all:
		if entry.request_id == request_id:
			entry.photo = photo.duplicate(true)
			found = true
	return found and _write(owner, all)

func has_request(owner: String, request_id: String) -> bool:
	return entries(owner).any(func(entry: Dictionary) -> bool: return entry.request_id == request_id)

func remove(owner: String, room_id: String, turn_id: String) -> bool:
	var all := entries(owner)
	var kept: Array[Dictionary] = []
	for entry: Dictionary in all:
		if entry.room_id != room_id or entry.turn_id != turn_id: kept.append(entry)
	return kept.size() == all.size() or _write(owner, kept)

## Explicit account deletion only.
func erase_owner(owner: String) -> bool:
	return _owner(owner) and AtomicFile.remove(_path(owner))

## Moves a photo the native side recovered into its entry, then lets the native side forget
## it. local_request is TurnPhotoLocal.request. A recovered photo no entry of this owner asked
## for is released too; the native cache keeps its bytes until account deletion.
func sync_native(owner: String, local_request: Callable) -> Array[Dictionary]:
	if _owner(owner) and local_request.is_valid():
		var found: Variant = await local_request.call("recovered", "")
		if found is Dictionary and found.get("ok", false) and found.get("recovered") == true and found.get("photo") is Dictionary:
			var attached := attach_photo(owner, str(found.get("request_id", "")), found.photo)
			if attached or not has_request(owner, str(found.get("request_id", ""))):
				await local_request.call("forget_recovered", str(found.photo.get("photo_id", "")))
	return entries(owner)

static func valid_entry(value: Variant) -> bool:
	if not value is Dictionary or value.size() != ENTRY_KEYS.size() or not ENTRY_KEYS.all(func(key: String) -> bool: return value.has(key)):
		return false
	return Capture._matches(value.room_id, "^[A-Za-z0-9_-]{22}$") and Capture._matches(value.turn_id, RoomStages.TURN_ID) and Capture._matches(value.recording_hash, "^[a-f0-9]{64}$") and Capture._matches(value.gameplay_key, "^[A-Za-z0-9_-]{16,80}$") and Capture._matches(value.request_id, "^[A-Za-z0-9_-]{1,80}$") and Capture._integer(value.started_unix, 4102444800) and value.photo is Dictionary and (value.photo.is_empty() or Capture._metadata_valid(value.photo))

static func _same_turn(a: Dictionary, b: Dictionary) -> bool:
	return a.room_id == b.room_id and a.turn_id == b.turn_id

static func _owner(owner: String) -> bool:
	return Capture._matches(owner, "^[A-Za-z0-9_-]{22}$")

func _path(owner: String) -> String:
	return directory.path_join(owner.sha256_text() + ".json")

func _write(owner: String, list: Array[Dictionary]) -> bool:
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return false
	var path := _path(owner)
	if list.is_empty():
		return AtomicFile.remove(path)
	var text := JSON.stringify({"schema_version": 1, "owner_player_id": owner, "entries": list})
	var bytes := text.to_utf8_buffer()
	return bytes.size() <= MAX_FILE and AtomicFile.write_bytes(path, bytes)
