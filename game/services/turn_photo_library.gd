class_name TurnPhotoLibrary
extends RefCounted
## Persistent optional media, independent of gameplay and network transport.
## One scene/main-thread writer per owner. Successful writes are flushed, renamed
## and read back before callers may acknowledge remote delivery. Never auto-evicts.

const Canonical = preload("res://core/v2/canonical.gd")
const Capture = preload("res://services/optional_photo_capture.gd")
const MAX_BYTES := 160 * 1024
const MAX_EDGE := 960
const MAX_METADATA := 8192
const MIN_FREE_BYTES := 2 * 1024 * 1024
const PHOTO_KEYS := ["schema_version", "turn_id", "owner_player_id", "recording_hash", "photo_revision", "sha256", "width", "height", "byte_length", "updated_at"]
const ENTRY_KEYS := ["schema_version", "entry_id", "room_id", "photo", "local_only", "delivery_ack", "created_at"]
var directory := "user://photo-library"
var _retired: Dictionary = {}

func _init(root_path: String = "user://photo-library") -> void:
	directory = root_path

func store_cache(owner: String, room_id: String, photo: Dictionary, bytes: PackedByteArray) -> Dictionary:
	return _store(owner, room_id, photo, bytes, false)

func store_local(owner: String, target: Dictionary, metadata: Dictionary, bytes: PackedByteArray) -> Dictionary:
	if not _owner(owner) or not Capture._metadata_valid(metadata) or target.get("owner_player_id", "") != owner or not _id(target.get("room_id")) or not _turn(target.get("turn_id")) or not _hash(target.get("recording_hash")):
		return _error("invalid_local_photo")
	var photo := {"schema_version": 1, "turn_id": target.turn_id, "owner_player_id": owner, "recording_hash": target.recording_hash, "photo_revision": 0, "sha256": metadata.sha256, "width": metadata.width, "height": metadata.height, "byte_length": metadata.byte_count, "updated_at": _now()}
	return _store(owner, target.room_id, photo, bytes, true)

func read_cache(owner: String, room_id: String, target: Dictionary) -> Dictionary:
	if not _owner(owner) or not _id(room_id) or not _target(target):
		return _error("invalid_photo_target")
	if target.has("owner_player_id") and target.has("sha256") and target.has("photo_revision"):
		var local_only := int(target.photo_revision) == 0
		if local_only and not target.get("include_local", false):
			return {"ok": true, "found": false}
		var id := _entry_id(room_id, target, local_only)
		var loaded := _read_doc(_entry_path(owner, id))
		if not loaded.ok or not loaded.get("found", false):
			return loaded
		if not _entry(loaded.get("value"), owner) or loaded.value.entry_id != id:
			return _error("unreadable_photo_library")
		var entry: Dictionary = loaded.value
		var tomb := _tombstone(owner, room_id, entry.photo)
		if not tomb.ok: return tomb
		var visible := _visibility(owner, entry, tomb.get("value", {}))
		if not visible.ok: return visible
		if visible.deleted: return {"ok": true, "found": false}
		var image := _read_bytes(owner, entry.photo)
		if not image.ok: return image
		return {"ok": true, "found": true, "photo": entry.photo.duplicate(true), "bytes": image.bytes, "entry_id": id, "delivery_ack": entry.delivery_ack, "local_only": local_only}
	# Selection reads retain access to the original local reference even when the
	# gallery/transfer inventory represents identical pixels by their shared entry.
	var listing := list_entries(owner, true)
	if not listing.get("ok", false):
		return listing
	for entry: Dictionary in listing.entries:
		var photo: Dictionary = entry.photo
		if entry.room_id != room_id or photo.turn_id != target.turn_id or photo.recording_hash != target.recording_hash or entry.deleted:
			continue
		if entry.local_only and not target.get("include_local", false):
			continue
		if target.has("owner_player_id") and photo.owner_player_id != target.owner_player_id:
			continue
		if target.has("sha256") and photo.sha256 != target.sha256:
			continue
		if target.has("photo_revision") and photo.photo_revision != target.photo_revision:
			continue
		var loaded := _read_bytes(owner, photo)
		if not loaded.get("ok", false):
			return loaded
		return {"ok": true, "found": true, "photo": photo.duplicate(true), "bytes": loaded.bytes, "entry_id": entry.entry_id, "delivery_ack": entry.delivery_ack, "local_only": entry.local_only}
	return {"ok": true, "found": false}

func list_entries(owner: String, include_redundant_local: bool = false) -> Dictionary:
	if not _owner(owner):
		return _error("invalid_owner")
	var folder := _folder(owner).path_join("entries")
	var names := _names(folder)
	if not names.ok:
		return names
	var result: Array[Dictionary] = []
	for name: String in names.names:
		var doc := _read_doc(folder.path_join(name))
		if not doc.get("ok", false) or not doc.get("found", false) or not _entry(doc.get("value"), owner) or name != str(doc.value.entry_id) + ".json":
			return _error("unreadable_photo_library")
		var entry: Dictionary = doc.value.duplicate(true)
		var tomb := _tombstone(owner, entry.room_id, entry.photo)
		if not tomb.ok:
			return tomb
		var visibility := _visibility(owner, entry, tomb.get("value", {}))
		if not visibility.ok:
			return visibility
		entry["deleted"] = visibility.deleted
		result.append(entry)
	if not include_redundant_local:
		var shared: Dictionary = {}
		for entry: Dictionary in result:
			if not entry.local_only:
				shared[_pixels_reference(entry)] = true
		var visible: Array[Dictionary] = []
		for entry: Dictionary in result:
			if not entry.local_only or not shared.has(_pixels_reference(entry)):
				visible.append(entry)
		result = visible
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.created_at != b.created_at:
			return a.created_at > b.created_at
		if a.photo.photo_revision != b.photo.photo_revision:
			return a.photo.photo_revision > b.photo.photo_revision
		return a.entry_id > b.entry_id)
	return {"ok": true, "entries": result}

func mark_ack(owner: String, entry_id: String) -> Dictionary:
	var loaded := _load_entry(owner, entry_id)
	if not loaded.ok:
		return loaded
	var entry: Dictionary = loaded.value
	if entry.local_only or entry.photo.photo_revision < 1:
		return _error("invalid_delivery_ack")
	# Recheck the actual JPEG at the ACK boundary, not only its catalog presence.
	var image := _read_bytes(owner, entry.photo)
	if not image.ok:
		return image
	if entry.delivery_ack:
		return {"ok": true, "durable": true}
	entry.delivery_ack = true
	return _write_doc(_entry_path(owner, entry_id), entry)

func mark_deleted(owner: String, room_id: String, photo: Dictionary) -> Dictionary:
	if not _owner(owner) or not _id(room_id) or not _photo(photo, false, true) or photo.sha256 != null:
		return _error("invalid_photo_tombstone")
	var prior := _tombstone(owner, room_id, photo)
	if not prior.ok:
		return prior
	if prior.get("value", {}).get("photo_revision", 0) >= photo.photo_revision:
		return {"ok": true, "durable": true}
	return _write_doc(_tomb_path(owner, room_id, photo), {"schema_version": 1, "room_id": room_id, "turn_id": photo.turn_id, "recording_hash": photo.recording_hash, "owner_player_id": photo.owner_player_id, "photo_revision": photo.photo_revision, "updated_at": photo.updated_at})

func export_entry(owner: String, entry_id: String) -> Dictionary:
	var loaded := _load_entry(owner, entry_id)
	if not loaded.ok:
		return loaded
	var entry: Dictionary = loaded.value
	var image := _read_bytes(owner, entry.photo)
	if not image.ok:
		return image
	var tomb := _tombstone(owner, entry.room_id, entry.photo)
	if not tomb.ok:
		return tomb
	var photo: Dictionary = entry.photo
	var visibility := _visibility(owner, entry, tomb.get("value", {}))
	if not visibility.ok:
		return visibility
	return {"ok": true, "entry": {"entry_id": entry_id, "room_id": entry.room_id, "turn_id": photo.turn_id, "recording_hash": photo.recording_hash, "photo_revision": photo.photo_revision, "photo_owner": photo.owner_player_id, "local_only": entry.local_only, "sha256": photo.sha256, "width": photo.width, "height": photo.height, "byte_length": photo.byte_length, "created_at": entry.created_at, "jpeg_base64": Marshalls.raw_to_base64(image.bytes), "deleted": visibility.deleted}}

func import_entry(owner: String, value: Dictionary) -> Dictionary:
	var keys := ["entry_id", "room_id", "turn_id", "recording_hash", "photo_revision", "photo_owner", "local_only", "sha256", "width", "height", "byte_length", "created_at", "jpeg_base64", "deleted"]
	if not _owner(owner) or not _keys(value, keys) or not value.local_only is bool or not value.deleted is bool or not value.jpeg_base64 is String or value.jpeg_base64.length() > ceili(MAX_BYTES / 3.0) * 4 or not _timestamp(value.created_at):
		return _error("invalid_photo_import")
	if value.local_only and value.photo_owner != owner:
		return _error("invalid_photo_import_owner")
	var bytes := Marshalls.base64_to_raw(value.jpeg_base64)
	if Marshalls.raw_to_base64(bytes) != value.jpeg_base64:
		return _error("invalid_photo_import")
	var photo := {"schema_version": 1, "turn_id": value.turn_id, "owner_player_id": value.photo_owner, "recording_hash": value.recording_hash, "photo_revision": value.photo_revision, "sha256": value.sha256, "width": value.width, "height": value.height, "byte_length": value.byte_length, "updated_at": value.created_at}
	if not _id(value.room_id) or not _hash(value.entry_id) or not _photo(photo, value.local_only) or _entry_id(value.room_id, photo, value.local_only) != value.entry_id:
		return _error("invalid_photo_import_id")
	var saved := _store(owner, value.room_id, photo, bytes, value.local_only, value.created_at)
	if not saved.ok or not value.deleted:
		return saved
	# Preserve invisible archive entries without forging a server revision/tombstone.
	# This flag is local to the imported exact version; its bytes remain exportable.
	return _mark_import_hidden(owner, saved.entry_id)

func erase_owner(owner: String) -> Dictionary:
	if not _id(owner):
		return _error("invalid_owner")
	_retired[owner] = true # Late callbacks on this instance may not recreate deleted data.
	var folder := _folder(owner)
	if not DirAccess.dir_exists_absolute(folder):
		return {"ok": not FileAccess.file_exists(folder)}
	var clean := true
	for child: String in ["entries", "objects", "deleted", "hidden"]:
		var path := folder.path_join(child)
		if not DirAccess.dir_exists_absolute(path):
			if FileAccess.file_exists(path): clean = false
			continue
		if not DirAccess.get_directories_at(path).is_empty():
			clean = false
		for file: String in DirAccess.get_files_at(path):
			if not _matches(file, "^[a-f0-9]{64}\\.(?:json|jpg)(?:\\.tmp|\\.backup|\\.corrupt-[a-f0-9]{16})?$") or DirAccess.remove_absolute(path.path_join(file)) != OK:
				clean = false
		if DirAccess.get_files_at(path).is_empty() and DirAccess.get_directories_at(path).is_empty():
			DirAccess.remove_absolute(path)
	if not DirAccess.get_files_at(folder).is_empty() or not DirAccess.get_directories_at(folder).is_empty():
		clean = false
	if clean:
		clean = DirAccess.remove_absolute(folder) == OK
	return {"ok": clean}

func _store(owner: String, room_id: String, photo: Dictionary, bytes: PackedByteArray, local_only: bool, created_at: String = "") -> Dictionary:
	if not _owner(owner) or not _id(room_id) or not _photo(photo, local_only) or (local_only and photo.owner_player_id != owner) or not _valid_image(photo, bytes):
		return _error("invalid_photo_bytes")
	var id := _entry_id(room_id, photo, local_only)
	var entry := {"schema_version": 1, "entry_id": id, "room_id": room_id, "photo": photo.duplicate(true), "local_only": local_only, "delivery_ack": false, "created_at": photo.updated_at if created_at.is_empty() else created_at}
	var existing := _read_doc(_entry_path(owner, id))
	if not existing.ok:
		return existing
	if existing.get("found", false):
		if not _entry(existing.value, owner) or existing.value.entry_id != id:
			return _error("unreadable_photo_library")
		entry = existing.value # Preserve initial time and delivery ACK on exact retry.
	var path := _folder(owner).path_join("objects").path_join(str(photo.sha256) + ".jpg")
	var written := _write_bytes(path, bytes)
	if not written.ok:
		return written
	if not existing.get("found", false):
		written = _write_doc(_entry_path(owner, id), entry)
		if not written.ok:
			return written
	var readback := _load_entry(owner, id)
	if not readback.ok or not _read_bytes(owner, photo).ok:
		return _error("photo_write_unconfirmed")
	return {"ok": true, "durable": true, "entry_id": id}

func _load_entry(owner: String, id: String) -> Dictionary:
	if not _owner(owner) or not _hash(id):
		return _error("invalid_photo_entry")
	var value := _read_doc(_entry_path(owner, id))
	if not value.ok or not value.get("found", false) or not _entry(value.get("value"), owner) or value.value.entry_id != id:
		return _error("unreadable_photo_library")
	return value

func _read_bytes(owner: String, photo: Dictionary) -> Dictionary:
	var path := _folder(owner).path_join("objects").path_join(str(photo.sha256) + ".jpg")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 4 or file.get_length() > MAX_BYTES:
		return _error("local_photo_missing")
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return {"ok": true, "bytes": bytes} if _valid_image(photo, bytes) else _error("local_photo_corrupt")

func _write_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	var corrupt := false
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null: return _error("photo_storage_unavailable")
		var existing := file.get_buffer(file.get_length()) if file.get_length() <= MAX_BYTES else PackedByteArray()
		file.close()
		if existing == bytes: return {"ok": true}
		if not existing.is_empty() and _digest(existing) == path.get_file().trim_suffix(".jpg"):
			return _error("photo_hash_collision")
		corrupt = true
	if not _mkdir(path.get_base_dir(), bytes.size()):
		return _error("photo_storage_unavailable")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return _error("photo_storage_unavailable")
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_bytes(path + ".tmp") != bytes:
		return _error("photo_write_unconfirmed")
	if corrupt and DirAccess.rename_absolute(path, path + ".corrupt-" + Crypto.new().generate_random_bytes(8).hex_encode()) != OK:
		return _error("photo_storage_unavailable")
	if DirAccess.rename_absolute(path + ".tmp", path) != OK or FileAccess.get_file_as_bytes(path) != bytes:
		return _error("photo_write_unconfirmed")
	return {"ok": true}

func _write_doc(path: String, value: Dictionary) -> Dictionary:
	var previous := _read_doc(path)
	if not previous.ok:
		return previous
	var generation: int = int(previous.get("generation", 0)) + 1
	var doc := {"schema_version": 1, "generation": generation, "value": value, "checksum": Canonical.digest(value)}
	var encoded := JSON.stringify(doc).to_utf8_buffer()
	if generation > 2147483647 or encoded.size() > MAX_METADATA or not _mkdir(path.get_base_dir(), encoded.size()):
		return _error("photo_storage_unavailable")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return _error("photo_storage_unavailable")
	file.store_buffer(encoded)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_bytes(path + ".tmp") != encoded:
		return _error("photo_write_unconfirmed")
	if previous.get("found", false) and previous.get("source", "") == path:
		if DirAccess.copy_absolute(path, path + ".backup") != OK:
			return _error("photo_storage_unavailable")
	var renamed := DirAccess.rename_absolute(path + ".tmp", path)
	if renamed != OK and FileAccess.file_exists(path) and DirAccess.remove_absolute(path) == OK:
		renamed = DirAccess.rename_absolute(path + ".tmp", path)
	var checked := _read_doc(path)
	if renamed != OK or not checked.ok or checked.get("generation") != generation or not Canonical.same(checked.get("value"), value):
		return _error("photo_write_unconfirmed")
	return {"ok": true, "durable": true}

func _read_doc(path: String) -> Dictionary:
	var best: Dictionary = {"ok": true, "found": false, "generation": 0}
	var exists := false
	for suffix: String in ["", ".tmp", ".backup"]:
		if not FileAccess.file_exists(path + suffix):
			continue
		exists = true
		var file := FileAccess.open(path + suffix, FileAccess.READ)
		if file == null or file.get_length() > MAX_METADATA:
			return _error("unreadable_photo_library")
		var parser := JSON.new()
		var parse_error := parser.parse(file.get_as_text())
		file.close()
		if parse_error != OK:
			continue
		var doc: Variant = parser.data
		if doc is Dictionary and doc.get("schema_version") != 1:
			return _error("unsupported_photo_library")
		if not doc is Dictionary or not _keys(doc, ["schema_version", "generation", "value", "checksum"]) or not _integer(doc.generation, 1, 2147483647) or not doc.value is Dictionary or doc.checksum != Canonical.digest(doc.value):
			continue
		if not best.found or doc.generation > best.generation:
			best = {"ok": true, "found": true, "generation": int(doc.generation), "value": doc.value.duplicate(true), "source": path + suffix}
	return _error("unreadable_photo_library") if exists and not best.found else best

func _names(folder: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(folder):
		return _error("photo_storage_unavailable") if FileAccess.file_exists(folder) else {"ok": true, "names": []}
	var listing := DirAccess.open(folder)
	if listing == null or listing.list_dir_begin() != OK:
		return _error("photo_storage_unavailable")
	var names: Dictionary = {}
	var name := listing.get_next()
	while not name.is_empty():
		if listing.current_is_dir() or not _matches(name, "^[a-f0-9]{64}\\.json(?:\\.tmp|\\.backup)?$"):
			listing.list_dir_end()
			return _error("unreadable_photo_library")
		names[name.trim_suffix(".backup").trim_suffix(".tmp")] = true
		name = listing.get_next()
	listing.list_dir_end()
	return {"ok": true, "names": names.keys()}

func _tombstone(owner: String, room_id: String, photo: Dictionary) -> Dictionary:
	var read := _read_doc(_tomb_path(owner, room_id, photo))
	if not read.ok or not read.get("found", false):
		return read
	var value: Dictionary = read.value
	if not _keys(value, ["schema_version", "room_id", "turn_id", "recording_hash", "owner_player_id", "photo_revision", "updated_at"]) or value.schema_version != 1 or value.room_id != room_id or value.turn_id != photo.turn_id or value.recording_hash != photo.recording_hash or value.owner_player_id != photo.owner_player_id or not _integer(value.photo_revision, 1, 256) or not _timestamp(value.updated_at):
		return _error("unreadable_photo_library")
	return read

func _mark_import_hidden(owner: String, id: String) -> Dictionary:
	var result := _write_doc(_folder(owner).path_join("hidden").path_join(id + ".json"), {"entry_id": id, "hidden": true})
	if result.ok:
		result["entry_id"] = id
	return result

func _visibility(owner: String, entry: Dictionary, tomb: Dictionary) -> Dictionary:
	var hidden := _read_doc(_folder(owner).path_join("hidden").path_join(str(entry.entry_id) + ".json"))
	if not hidden.ok:
		return hidden
	if hidden.get("found", false):
		if not _keys(hidden.value, ["entry_id", "hidden"]) or hidden.value.entry_id != entry.entry_id or not hidden.value.hidden is bool or not hidden.value.hidden:
			return _error("unreadable_photo_library")
		return {"ok": true, "deleted": true}
	return {"ok": true, "deleted": _deleted(entry, tomb)}

func _deleted(entry: Dictionary, tomb: Dictionary) -> bool:
	# A newly taken local-only image may follow an earlier remote removal.
	return not tomb.is_empty() and (entry.created_at <= tomb.updated_at if entry.local_only else entry.photo.photo_revision <= tomb.photo_revision)

func _entry_path(owner: String, id: String) -> String:
	return _folder(owner).path_join("entries").path_join(id + ".json")

func _tomb_path(owner: String, room_id: String, photo: Dictionary) -> String:
	return _folder(owner).path_join("deleted").path_join(Canonical.digest([room_id, photo.turn_id, photo.recording_hash]) + ".json")

func _folder(owner: String) -> String:
	return directory.path_join(owner.sha256_text())

func _owner(owner: String) -> bool:
	return _id(owner) and not _retired.has(owner)

static func _mkdir(folder: String, byte_count: int) -> bool:
	# Recursive mkdir logs an engine error when an ancestor is a file. A storage
	# blocker is an ordinary retryable failure, so detect it before calling mkdir.
	var ancestor := ProjectSettings.globalize_path(folder).simplify_path()
	while not ancestor.is_empty():
		if FileAccess.file_exists(ancestor):
			return false
		var parent := ancestor.get_base_dir()
		if parent == ancestor:
			break
		ancestor = parent
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return false
	var access := DirAccess.open(folder)
	return access != null and access.get_space_left() >= byte_count + MIN_FREE_BYTES

static func _entry_id(room_id: String, photo: Dictionary, local_only: bool) -> String:
	return Canonical.digest([room_id, photo.get("turn_id"), photo.get("recording_hash"), photo.get("photo_revision"), photo.get("owner_player_id"), photo.get("sha256"), local_only])

static func _pixels_reference(entry: Dictionary) -> String:
	# Collapse only the redundant local-to-shared representation, never another
	# turn, owner, distinct capture, or visibility state. All disk entries remain.
	var photo: Dictionary = entry.photo
	return Canonical.digest([entry.room_id, photo.turn_id, photo.recording_hash, photo.owner_player_id, photo.sha256, entry.deleted])

static func _entry(value: Variant, owner: String) -> bool:
	return value is Dictionary and _keys(value, ENTRY_KEYS) and value.schema_version == 1 and _id(value.room_id) and value.local_only is bool and value.delivery_ack is bool and (not value.local_only or (value.photo is Dictionary and value.photo.get("owner_player_id") == owner and not value.delivery_ack)) and _photo(value.photo, value.local_only) and _timestamp(value.created_at) and value.entry_id == _entry_id(value.room_id, value.photo, value.local_only)

static func _photo(value: Variant, local_only: bool, allow_tombstone: bool = false) -> bool:
	if not value is Dictionary or not _keys(value, PHOTO_KEYS) or value.schema_version != 1 or not _turn(value.turn_id) or not _id(value.owner_player_id) or not _hash(value.recording_hash) or not _integer(value.photo_revision, 0 if local_only else 1, 0 if local_only else 256) or not _timestamp(value.updated_at):
		return false
	if value.sha256 == null:
		return allow_tombstone and not local_only and value.width == null and value.height == null and value.byte_length == 0
	return _hash(value.sha256) and _integer(value.width, 1, MAX_EDGE) and _integer(value.height, 1, MAX_EDGE) and _integer(value.byte_length, 4, MAX_BYTES)

static func _target(value: Dictionary) -> bool:
	if not _turn(value.get("turn_id")) or not _hash(value.get("recording_hash")):
		return false
	return (not value.has("sha256") or _hash(value.sha256)) and (not value.has("photo_revision") or _integer(value.photo_revision, 0, 256)) and (not value.has("owner_player_id") or _id(value.owner_player_id)) and (not value.has("include_local") or value.include_local is bool)

static func _valid_image(photo: Dictionary, bytes: PackedByteArray) -> bool:
	if bytes.size() != photo.byte_length or not _safe_jpeg(bytes) or _digest(bytes) != photo.sha256:
		return false
	var image := Image.new()
	return image.load_jpg_from_buffer(bytes) == OK and image.get_width() == photo.width and image.get_height() == photo.height

static func _safe_jpeg(bytes: PackedByteArray) -> bool:
	if bytes.size() < 4 or bytes.size() > MAX_BYTES or bytes[0] != 255 or bytes[1] != 216:
		return false
	var index := 2
	var scan := false
	while index < bytes.size():
		if scan:
			var byte: int = bytes[index]
			index += 1
			if byte != 255: continue
			while index < bytes.size() and bytes[index] == 255: index += 1
			if index >= bytes.size(): return false
			var marker: int = bytes[index]
			index += 1
			if marker == 0 or (marker >= 208 and marker <= 215): continue
			return marker == 217 and index == bytes.size()
		if bytes[index] != 255 or index + 3 >= bytes.size(): return false
		var marker: int = bytes[index + 1]
		if marker not in [224, 192, 196, 219, 221, 218]: return false
		index += 2
		var size: int = bytes[index] * 256 + bytes[index + 1]
		if size < 2 or index + size > bytes.size(): return false
		if marker == 224 and (size != 16 or bytes.slice(index + 2, index + 7) != PackedByteArray([74,70,73,70,0]) or bytes[index + 14] != 0 or bytes[index + 15] != 0): return false
		index += size
		scan = marker == 218
	return false

static func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

static func _id(value: Variant) -> bool:
	return _matches(value, "^[A-Za-z0-9_-]{22}$")

static func _hash(value: Variant) -> bool:
	return _matches(value, "^[a-f0-9]{64}$")

static func _turn(value: Variant) -> bool:
	return _matches(value, "^t(?:[0-9]|[12][0-9]|3[01])-[01]-[ab]$")

static func _timestamp(value: Variant) -> bool:
	return _matches(value, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]{1,6})?Z$")

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value) and value >= minimum and value <= maximum

static func _matches(value: Variant, pattern: String) -> bool:
	return Capture._matches(value, pattern)

static func _keys(value: Dictionary, keys: Array) -> bool:
	return value.size() == keys.size() and keys.all(func(key: String) -> bool: return value.has(key))

static func _now() -> String:
	return Time.get_datetime_string_from_system(true) + ".000Z"

static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": code}
