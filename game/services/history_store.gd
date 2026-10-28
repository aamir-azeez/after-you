extends RefCounted
## This phone's copy of room attempts the server may let go once both phones
## confirm them. Each attempt is the exact bytes the server sent (an encoding byte
## and the payload), one file an attempt, plus one small index a room. Nothing is
## re-encoded: the bytes uploaded later are the bytes downloaded. Nothing is ever
## removed automatically, because an offloaded attempt may be the only copy left.

const NativeFiles = preload("res://services/native_files.gd")
const BlobCodec = preload("res://services/blob_codec.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Typed = preload("res://services/typed_values.gd")

const ROOT := "user://history"
const MAX_ATTEMPT_BYTES := 4 * 1024 * 1024
const MAX_ATTEMPTS := 32
const MAX_INDEX_BYTES := 64 * 1024
const ENCODING_RAW := BlobCodec.ENCODING_RAW
const ENCODING_DEFLATE := BlobCodec.ENCODING_DEFLATE
const LINK_SCHEMA := "after-you.history.v1"
const ZERO_LINK := "0000000000000000000000000000000000000000000000000000000000000000"
const RECORD_KEYS := ["position", "link", "digest", "byte_length", "file"]

var root := ROOT

func _init(root_path: String = ROOT) -> void:
	root = root_path

## The canonical bytes inside a stored or sent attempt (services/blob_codec.gd), or
## empty when they are not exactly `byte_length` long.
static func decode(tagged: PackedByteArray, byte_length: int) -> PackedByteArray:
	return BlobCodec.decode(tagged, byte_length, MAX_ATTEMPT_BYTES)

static func digest(bytes: PackedByteArray) -> String:
	return BlobCodec.digest(bytes)

## The server's chain link for an attempt: room, chapter version, place, the link before it, and the bytes.
static func link(room: Dictionary, position: int, previous: String, attempt_digest: String, byte_length: int) -> String:
	return Canonical.digest({"schema": LINK_SCHEMA, "room_id": room.get("room_id"), "level_id": room.get("level_id"), "level_version": room.get("level_version"),
		"definition_hash": room.get("definition_hash"), "position": position, "branch": position, "previous": previous, "digest": attempt_digest, "byte_length": byte_length})

## The canonical bytes when `tagged` is exactly the attempt the record describes.
static func verified_bytes(tagged: PackedByteArray, record: Dictionary) -> PackedByteArray:
	if not _record_shape(record): return PackedByteArray()
	var bytes := decode(tagged, int(record.byte_length))
	return bytes if not bytes.is_empty() and digest(bytes) == record.digest else PackedByteArray()

static func _hash(value: Variant) -> bool:
	return value is String and value.length() == 64 and RegEx.create_from_string("^[a-f0-9]{64}$").search(value) != null

static func _record_shape(record: Variant) -> bool:
	return record is Dictionary and (record.get("position") is int or record.get("position") is float) and int(record.position) >= 0 and int(record.position) < MAX_ATTEMPTS \
		and _hash(record.get("link")) and _hash(record.get("digest")) and (record.get("byte_length") is int or record.get("byte_length") is float) and int(record.byte_length) > 0 and int(record.byte_length) <= MAX_ATTEMPT_BYTES

static func _id(value: String) -> bool:
	return RegEx.create_from_string("^[a-zA-Z0-9_-]{22}$").search(value) != null

func room_directory(server_key: String, owner: String, room_id: String) -> String:
	if not _hash(server_key) or not _id(owner) or not _id(room_id): return ""
	return root.path_join(server_key.left(16)).path_join(owner).path_join(room_id)

## position -> {position, link, digest, byte_length, file}; empty when the room has none or its index is unreadable.
func index(server_key: String, owner: String, room_id: String) -> Dictionary:
	var directory := room_directory(server_key, owner, room_id)
	if directory.is_empty() or not FileAccess.file_exists(directory.path_join("index.json")): return {}
	var file := FileAccess.open(directory.path_join("index.json"), FileAccess.READ)
	if file == null or file.get_length() > MAX_INDEX_BYTES: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not Typed.equal(parsed.get("schema_version"), 1.0) or not Typed.equal(parsed.get("room_id"), room_id) or not parsed.get("attempts") is Array: return {}
	var result := {}
	for item: Variant in parsed.attempts:
		if not item is Dictionary or item.size() != RECORD_KEYS.size() or not _record_shape(item) or not Typed.equal(item.get("file"), _file_name(int(item.position), str(item.link))): return {}
		var record := {"position": int(item.position), "link": item.link, "digest": item.digest, "byte_length": int(item.byte_length), "file": item.file}
		result[record.position] = record
	return result

static func _file_name(position: int, attempt_link: String) -> String:
	return "%d-%s.bin" % [position, attempt_link.left(16)]

## True when this phone has exactly the attempt with this link.
func has(server_key: String, owner: String, room_id: String, position: int, attempt_link: String) -> bool:
	var entry: Dictionary = index(server_key, owner, room_id).get(position, {})
	return entry.get("link") == attempt_link and FileAccess.file_exists(room_directory(server_key, owner, room_id).path_join(entry.file))

## The stored bytes as sent and their canonical content, checked against the index's digest.
func read_attempt(server_key: String, owner: String, room_id: String, position: int) -> Dictionary:
	var entry: Dictionary = index(server_key, owner, room_id).get(position, {})
	if entry.is_empty(): return {"ok": false, "code": "history_missing"}
	var path := room_directory(server_key, owner, room_id).path_join(entry.file)
	if not FileAccess.file_exists(path): return {"ok": false, "code": "history_missing"}
	var tagged := FileAccess.get_file_as_bytes(path)
	var bytes := verified_bytes(tagged, entry)
	if bytes.is_empty(): return {"ok": false, "code": "history_corrupt"}
	return {"ok": true, "record": entry, "tagged": tagged, "bytes": bytes}

## Writes the attempt durably, reads it back, checks it, and only then records it
## in the room's index. A false return means the server must not be told we have it.
func save(server_key: String, owner: String, room_id: String, record: Dictionary, tagged: PackedByteArray) -> bool:
	var directory := room_directory(server_key, owner, room_id)
	if directory.is_empty() or verified_bytes(tagged, record).is_empty(): return false
	var position := int(record.position)
	var name := _file_name(position, record.link)
	var path := directory.path_join(name)
	if not NativeFiles.write(path, tagged) or FileAccess.get_file_as_bytes(path) != tagged: return false
	var entries := index(server_key, owner, room_id)
	var previous: Dictionary = entries.get(position, {})
	entries[position] = {"position": position, "link": record.link, "digest": record.digest, "byte_length": int(record.byte_length), "file": name}
	if not _write_index(directory, room_id, entries): return false
	# A different attempt at the same place (the room was rebuilt elsewhere) is replaced only after the new one is safe.
	if not previous.is_empty() and previous.file != name: DirAccess.remove_absolute(directory.path_join(previous.file))
	return true

func _write_index(directory: String, room_id: String, entries: Dictionary) -> bool:
	var positions := entries.keys()
	positions.sort()
	var attempts: Array = positions.map(func(position: int) -> Dictionary: return entries[position])
	var text := JSON.stringify({"schema_version": 1, "room_id": room_id, "attempts": attempts}, "", true)
	var path := directory.path_join("index.json")
	return text.length() <= MAX_INDEX_BYTES and NativeFiles.write(path, text.to_utf8_buffer()) and FileAccess.get_file_as_string(path) == text

## Bytes of every attempt this phone keeps (for the line in Settings).
func usage_bytes() -> int:
	return _size(root)

func _size(path: String) -> int:
	var total := 0
	var directory := DirAccess.open(path)
	if directory == null: return 0
	for name: String in directory.get_files():
		if not name.ends_with(".bin"): continue
		var file := FileAccess.open(path.path_join(name), FileAccess.READ)
		if file != null: total += file.get_length()
	for name: String in directory.get_directories(): total += _size(path.path_join(name))
	return total

## "820 KB" or "2.3 MB", for the Settings line.
static func size_text(bytes: int) -> String:
	return "%d KB" % ceili(bytes / 1024.0) if bytes < 1024 * 1024 else "%.1f MB" % (bytes / 1048576.0)

## Removes one identity's attempts on every server (identity deletion only).
func erase_owner(owner: String) -> bool:
	if not _id(owner): return false
	var servers := DirAccess.open(root)
	if servers == null: return true
	var ok := true
	for server: String in servers.get_directories():
		var path := root.path_join(server).path_join(owner)
		if DirAccess.dir_exists_absolute(path): ok = _remove_tree(path) and ok
	return ok

func _remove_tree(path: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null: return false
	var ok := true
	for name: String in directory.get_directories(): ok = _remove_tree(path.path_join(name)) and ok
	for name: String in directory.get_files(): ok = DirAccess.remove_absolute(path.path_join(name)) == OK and ok
	return DirAccess.remove_absolute(path) == OK and ok

## Startup check: a durable write that reads back exactly. Only then may this phone
## tell the server it keeps attempts.
func self_test() -> bool:
	var path := root.path_join("self-test.bin")
	var bytes := Crypto.new().generate_random_bytes(64)
	var ok := NativeFiles.write(path, bytes) and FileAccess.get_file_as_bytes(path) == bytes
	DirAccess.remove_absolute(path)
	return ok
