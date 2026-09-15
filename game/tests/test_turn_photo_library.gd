extends SceneTree

const Library = preload("res://services/turn_photo_library.gd")
const Store = preload("res://services/turn_photo_store.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const OWNER := "AAAAAAAAAAAAAAAAAAAAAA"
const OTHER := "BBBBBBBBBBBBBBBBBBBBBB"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const HASH := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var checks := 0
var failures := 0
var roots: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _root(label: String) -> String:
	var path := "user://test-photo-library-" + label + "-" + str(Time.get_ticks_usec())
	roots.append(path)
	return path

func _jpeg(color: Color) -> PackedByteArray:
	var image := Image.create(20, 16, false, Image.FORMAT_RGB8)
	image.fill(color)
	return image.save_jpg_to_buffer(0.8)

func _photo(bytes: PackedByteArray, revision: int = 1) -> Dictionary:
	return {"schema_version": 1, "turn_id": "t0-0-a", "owner_player_id": OWNER, "recording_hash": HASH, "photo_revision": revision, "sha256": Library._digest(bytes), "width": 20, "height": 16, "byte_length": bytes.size(), "updated_at": "2026-09-15T12:00:%02d.000Z" % revision}

func _metadata(bytes: PackedByteArray) -> Dictionary:
	return {"status": "kept", "photo_id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "mime": "image/jpeg", "width": 20, "height": 16, "byte_count": bytes.size(), "sha256": Library._digest(bytes), "metadata_removed": true, "uploaded": false}

func _run() -> void:
	var jpeg := _jpeg(Color.CYAN)
	var photo := _photo(jpeg)
	var root_path := _root("main")
	var library := Library.new(root_path)
	_check(Library._safe_jpeg(jpeg), "Synthetic engine JPEG has permitted metadata-free framing")
	var stored := library.store_cache(OWNER, ROOM, photo, jpeg)
	_check(stored.get("ok", false) and stored.get("durable", false), "Verified JPEG and provenance are persisted before delivery ACK")
	if not stored.get("ok", false):
		_finish()
		return
	var id: String = stored.entry_id
	var reopened := Library.new(root_path)
	var read := reopened.read_cache(OWNER, ROOM, photo)
	_check(read.get("found", false) and read.get("bytes") == jpeg, "Cold exact lookup uses persisted original bytes")
	_check(not read.delivery_ack, "A stored image is not falsely treated as server-acknowledged")
	_check(reopened.mark_ack(OWNER, id).ok, "Exact-version ACK is durably recorded")
	var entry_path := root_path.path_join(OWNER.sha256_text()).path_join("entries").path_join(id + ".json")
	var acked := FileAccess.get_file_as_bytes(entry_path)
	_check(reopened.mark_ack(OWNER, id).ok and FileAccess.get_file_as_bytes(entry_path) == acked, "Repeated ACK avoids rewriting or changing the version")
	_check(reopened.store_cache(OWNER, ROOM, photo, jpeg).entry_id == id and FileAccess.get_file_as_bytes(entry_path) == acked, "Exact delivery retry preserves ACK and local generation")
	_check(not reopened.read_cache(OTHER, ROOM, photo).get("found", false), "Another local owner cannot read this owner's library")
	_check(not reopened.read_cache(OWNER, OTHER, photo).get("found", false), "Same pixels in another room are not a per-turn cache hit")
	var replacement := _photo(_jpeg(Color.YELLOW), 2)
	var second := reopened.store_cache(OWNER, ROOM, replacement, _jpeg(Color.YELLOW))
	_check(second.ok and second.entry_id != id and not reopened.read_cache(OWNER, ROOM, replacement).delivery_ack, "Replacement revision has distinct provenance and no inherited ACK")
	var latest := reopened.read_cache(OWNER, ROOM, {"turn_id": photo.turn_id, "recording_hash": HASH})
	_check(latest.get("entry_id") == second.entry_id, "Offline unpinned lookup selects newest exact-turn version")
	var tomb := replacement.duplicate(true)
	tomb.merge({"photo_revision": 3, "sha256": null, "width": null, "height": null, "byte_length": 0, "updated_at": "2026-09-15T12:00:03.000Z"}, true)
	_check(reopened.mark_deleted(OWNER, ROOM, tomb).ok, "Owner deletion stores a scoped visibility tombstone")
	_check(not reopened.read_cache(OWNER, ROOM, photo).get("found", false) and not reopened.read_cache(OWNER, ROOM, replacement).get("found", false), "Old shared versions cannot reappear after removal")
	var exported := reopened.export_entry(OWNER, id)
	_check(exported.ok and exported.entry.deleted and Marshalls.base64_to_raw(exported.entry.jpeg_base64) == jpeg, "Deleted visibility and retained bytes remain privately exportable")
	var restored := Library.new(_root("restore"))
	_check(restored.import_entry(OWNER, exported.entry).ok, "Transfer imports exact byte/hash/provenance")
	_check(not restored.read_cache(OWNER, ROOM, photo).get("found", false), "Restoring archived deleted bytes never revives a shared bubble")
	_check(restored.export_entry(OWNER, id).entry == exported.entry, "Transfer roundtrip preserves hidden visibility and exact bytes")
	_check(restored.import_entry(OWNER, exported.entry).ok, "Exact restore retry remains safe")
	var malformed: Dictionary = exported.entry.duplicate(true)
	malformed.sha256 = "b".repeat(64)
	_check(not restored.import_entry(OWNER, malformed).ok, "Invalid import checksum/entry identity cannot be acknowledged")
	malformed = exported.entry.duplicate(true)
	malformed.room_id = 42
	_check(not restored.import_entry(OWNER, malformed).ok, "Malformed import field type returns a failure rather than a script exception")
	var own_local := reopened.store_local(OWNER, {"room_id": ROOM, "turn_id": "t0-0-b", "recording_hash": HASH, "owner_player_id": OWNER}, _metadata(jpeg), jpeg)
	_check(own_local.ok, "Own unshared selection is durable before any upload")
	_check(not reopened.read_cache(OWNER, ROOM, {"turn_id": "t0-0-b", "recording_hash": HASH}).get("found", false), "Unshared pixels do not become shared replay bubbles")
	_check(reopened.read_cache(OWNER, ROOM, {"turn_id": "t0-0-b", "recording_hash": HASH, "include_local": true}).get("found", false), "Explicit own local preview can read an unshared image offline")
	_check(not reopened.mark_ack(OWNER, own_local.entry_id).ok, "Local-only image cannot generate a delivery acknowledgement")
	var local_export := reopened.export_entry(OWNER, own_local.entry_id)
	_check(local_export.ok and local_export.entry.local_only and local_export.entry.photo_revision == 0, "Explicit private transfer can include local-only photos without treating them as shared")
	_check(not restored.import_entry(OTHER, local_export.entry).ok, "Unshared original cannot be imported into another account's namespace")
	_test_shared_inventory(jpeg, photo)
	_test_repair_and_unknown(jpeg, photo)
	_test_large_library(jpeg, photo)
	_test_scopes()
	_check(reopened.erase_owner(OWNER).ok and not reopened.store_cache(OWNER, ROOM, photo, jpeg).ok, "Confirmed account cleanup prevents a late same-instance write from recreating photos")
	_finish()

func _test_shared_inventory(jpeg: PackedByteArray, photo: Dictionary) -> void:
	var path := _root("shared-inventory")
	var library := Library.new(path)
	var target := {"room_id": ROOM, "turn_id": photo.turn_id, "recording_hash": HASH, "owner_player_id": OWNER}
	var local := library.store_local(OWNER, target, _metadata(jpeg), jpeg)
	var shared := library.store_cache(OWNER, ROOM, photo, jpeg)
	var listing := Library.new(path).list_entries(OWNER)
	_check(local.ok and shared.ok and local.entry_id != shared.entry_id and listing.entries.size() == 1 and listing.entries[0].entry_id == shared.entry_id, "One capture subsequently shared occupies one gallery/transfer inventory entry")
	_check(DirAccess.get_files_at(path.path_join(OWNER.sha256_text()).path_join("entries")).size() == 2 and library.export_entry(OWNER, local.entry_id).entry.local_only, "Inventory collapse preserves both original metadata references and exact local export")
	_check(library.read_cache(OWNER, ROOM, {"turn_id": photo.turn_id, "recording_hash": HASH, "photo_revision": 0, "include_local": true}).get("entry_id") == local.entry_id, "Existing selection can still resolve its local revision after sharing")
	var different := _jpeg(Color.MAGENTA)
	_check(library.store_local(OWNER, target, _metadata(different), different).ok and library.list_entries(OWNER).entries.size() == 2, "A distinct unshared capture for the same turn is not collapsed")
	target.room_id = OTHER
	_check(library.store_local(OWNER, target, _metadata(jpeg), jpeg).ok and library.list_entries(OWNER).entries.size() == 3, "Identical pixels in another room retain their own inventory reference")

func _test_repair_and_unknown(jpeg: PackedByteArray, photo: Dictionary) -> void:
	var path := _root("repair")
	var library := Library.new(path)
	var result := library.store_cache(OWNER, ROOM, photo, jpeg)
	var blob := path.path_join(OWNER.sha256_text()).path_join("objects").path_join(str(photo.sha256) + ".jpg")
	var broken := PackedByteArray([1,2,3,4])
	var file := FileAccess.open(blob, FileAccess.WRITE)
	file.store_buffer(broken)
	file.close()
	_check(not library.read_cache(OWNER, ROOM, photo).ok and not library.mark_ack(OWNER, result.entry_id).ok, "Corrupt local file never counts as downloaded or ACK-ready")
	_check(library.store_cache(OWNER, ROOM, photo, jpeg).ok and library.read_cache(OWNER, ROOM, photo).bytes == jpeg, "Verified redownload repairs corruption without erasing other valid versions")
	var quarantined := false
	for name: String in DirAccess.get_files_at(blob.get_base_dir()):
		if name.contains(".corrupt-"):
			quarantined = FileAccess.get_file_as_bytes(blob.get_base_dir().path_join(name)) == broken
	_check(quarantined, "The damaged copy is preserved during repair")
	var entry_path := path.path_join(OWNER.sha256_text()).path_join("entries").path_join(str(result.entry_id) + ".json")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry_path))
	doc.schema_version = 99
	file = FileAccess.open(entry_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(doc))
	file.close()
	var original := FileAccess.get_file_as_bytes(entry_path)
	_check(not library.store_cache(OWNER, ROOM, photo, jpeg).ok and FileAccess.get_file_as_bytes(entry_path) == original, "Future metadata schema remains unchanged and cannot be silently overwritten")
	var collision := _root("blocked")
	file = FileAccess.open(collision, FileAccess.WRITE)
	file.store_string("synthetic storage blocker")
	file.close()
	_check(not Library.new(collision).store_cache(OWNER, ROOM, photo, jpeg).ok, "Storage failure never returns durable success")

func _test_large_library(jpeg: PackedByteArray, photo: Dictionary) -> void:
	var path := _root("uncapped")
	var library := Library.new(path)
	var complete := true
	for index in range(1001):
		if not library.store_cache(OWNER, "%022d" % index, photo, jpeg).get("ok", false):
			complete = false
			break
	var listing := Library.new(path).list_entries(OWNER)
	_check(complete and listing.get("entries", []).size() == 1001, "Local library retains more than1000 entries; only temporary server transfer has that limit")
	_check(DirAccess.get_files_at(path.path_join(OWNER.sha256_text()).path_join("objects")).size() == 1, "Identical originals across many room references consume one content-addressed JPEG")
	# Exact lookup is independent of unrelated catalog corruption or enumeration.
	var stray := FileAccess.open(path.path_join(OWNER.sha256_text()).path_join("entries/unknown.txt"), FileAccess.WRITE)
	stray.store_string("synthetic unrelated metadata failure")
	stray.close()
	_check(library.read_cache(OWNER, "%022d" % 1000, photo).get("found", false), "Pinned replay lookup reads its exact entry without scanning1000 unrelated records")
	_check(not library.list_entries(OWNER).ok, "A full inventory still holds unknown entries for safe review")

func _test_scopes() -> void:
	var path := _root("journals")
	var store := Store.new(path)
	var scope := "turn-photo-v1:" + OWNER + ":" + ROOM + ":t0-0-a"
	var value := {"target": {"owner_player_id": OWNER}, "selection": {}, "cleanup": []}
	_check(store.save_scope(scope, value).ok, "Existing photo journal schema remains compatible")
	var scopes := Store.new(path).list_scopes(OWNER)
	_check(scopes.ok and scopes.scopes.size() == 1 and scopes.scopes[0].scope == scope and Canonical.same(scopes.scopes[0].value, value), "Migration enumerates only exact owner-scoped recoverable photo journals")
	_check(Store.new(path).list_scopes(OTHER).scopes.is_empty(), "Migration never enumerates another owner's journal")
	_check(store.erase_owner(OWNER).ok and not store.save_scope(scope, value).ok, "Retired journal store blocks late recreation after account deletion")

func _finish() -> void:
	for path: String in roots:
		_remove(path)
	print("Turn photo library: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _remove(path: String) -> void:
	# Only this test's unique user:// prefixes, never retained game/library paths.
	assert(path.begins_with("user://test-photo-library-"))
	if DirAccess.dir_exists_absolute(path):
		for child: String in DirAccess.get_directories_at(path): _remove(path.path_join(child))
		for file: String in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
