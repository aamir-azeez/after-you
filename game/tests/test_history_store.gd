extends SceneTree
## The phone's copy of room attempts: shared vectors with the Worker, exact bytes,
## bounded inflating, durable save with read-back, and identity deletion.

const Store = preload("res://services/history_store.gd")
const NativeFiles = preload("res://services/native_files.gd")

const SERVER := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/history/vectors.json"))
	var canonical := FileAccess.get_file_as_bytes("res://tests/fixtures/history/relay-attempt.json")
	var length := int(vectors.byte_length)
	_check(canonical.size() == length, "The vector blob file holds exactly the canonical bytes")
	_check(Store.digest(canonical) == vectors.digest, "SHA-256 of the canonical bytes matches the Worker's digest")
	var link0 := Store.link(vectors.room, 0, Store.ZERO_LINK, vectors.digest, length)
	_check(link0 == vectors.links[0] and Store.link(vectors.room, 1, link0, vectors.digest, length) == vectors.links[1], "Chain links match the Worker's vectors")
	var moved: Dictionary = vectors.room.duplicate()
	moved.room_id = "S".repeat(22)
	_check(Store.link(moved, 0, Store.ZERO_LINK, vectors.digest, length) != link0, "A link names its room")
	for name: String in ["zlib", "godot"]:
		var tagged := Marshalls.base64_to_raw(vectors.deflate_base64[name])
		_check(tagged[0] == Store.ENCODING_DEFLATE and Store.decode(tagged, length) == canonical, "Godot inflates the %s vector to the exact canonical bytes" % name)
		_check(Store.decode(tagged, length + 1).is_empty() and Store.decode(tagged.slice(0, tagged.size() - 9), length).is_empty(), "A wrong length or a cut-off %s body decodes to nothing" % name)
	var raw := PackedByteArray([Store.ENCODING_RAW])
	raw.append_array(canonical)
	_check(Store.decode(raw, length) == canonical, "A raw attempt decodes to itself")
	var longer := raw.duplicate()
	longer.append(32)
	_check(Store.decode(longer, length).is_empty(), "One extra byte is refused")
	var unknown := raw.duplicate()
	unknown[0] = 2
	_check(Store.decode(unknown, length).is_empty(), "An unknown encoding is refused")
	var mine := PackedByteArray([Store.ENCODING_DEFLATE])
	mine.append_array(canonical.compress(FileAccess.COMPRESSION_DEFLATE))
	_check(Store.decode(mine, length) == canonical and mine.size() * 3 < length, "Godot's own deflate round-trips and is several times smaller")
	var bomb := PackedByteArray([Store.ENCODING_DEFLATE])
	var zeros := PackedByteArray()
	zeros.resize(32 * 1024 * 1024)
	bomb.append_array(zeros.compress(FileAccess.COMPRESSION_DEFLATE))
	var started := Time.get_ticks_msec()
	_check(Store.decode(bomb, Store.MAX_ATTEMPT_BYTES).is_empty() and Time.get_ticks_msec() - started < 3000, "Inflating stops at the expected length, so a bomb decodes to nothing quickly")
	_store(vectors, canonical)
	print("History store: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _store(vectors: Dictionary, canonical: PackedByteArray) -> void:
	var root := "user://history-test-%d" % Time.get_ticks_usec()
	var store := Store.new(root)
	_check(store.self_test(), "The startup check writes and reads back")
	_check(not NativeFiles.durable_available(), "Desktop builds have no synced native write, so they never claim support")
	var tagged := Marshalls.base64_to_raw(vectors.deflate_base64.zlib)
	var record := {"position": 0, "link": vectors.links[0], "digest": vectors.digest, "byte_length": int(vectors.byte_length)}
	_check(store.index(SERVER, OWNER, ROOM).is_empty() and not store.has(SERVER, OWNER, ROOM, 0, record.link), "A new room has no attempts")
	var wrong := record.duplicate()
	wrong.digest = "b".repeat(64)
	_check(not store.save(SERVER, OWNER, ROOM, wrong, tagged), "Bytes that do not match the record are never saved")
	_check(store.index(SERVER, OWNER, ROOM).is_empty(), "A refused save leaves no index entry")
	_check(store.save(SERVER, OWNER, ROOM, record, tagged), "A matching attempt is saved")
	_check(store.has(SERVER, OWNER, ROOM, 0, record.link) and not store.has(SERVER, OWNER, ROOM, 0, "c".repeat(64)), "The room index knows the attempt by its link")
	var loaded := store.read_attempt(SERVER, OWNER, ROOM, 0)
	_check(loaded.get("ok", false) and loaded.tagged == tagged and loaded.bytes == canonical, "The stored bytes are exactly the bytes received, and decode to the attempt")
	var second := record.duplicate()
	second.position = 1
	second.link = vectors.links[1]
	_check(store.save(SERVER, OWNER, ROOM, second, tagged) and store.index(SERVER, OWNER, ROOM).size() == 2, "A second attempt joins the same room index")
	var path := store.room_directory(SERVER, OWNER, ROOM).path_join("0-%s.bin" % record.link.left(16))
	var damaged := tagged.duplicate()
	damaged[40] = damaged[40] ^ 1
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(damaged)
	file.close()
	_check(store.read_attempt(SERVER, OWNER, ROOM, 0).get("code") == "history_corrupt", "A damaged file is reported, never returned")
	_check(store.usage_bytes() >= tagged.size() * 2, "Settings can show the space attempts use")
	_check(store.room_directory(SERVER, "bad", ROOM).is_empty() and store.room_directory("x", OWNER, ROOM).is_empty(), "Only well-formed ids name a folder")
	_check(store.erase_owner(OWNER) and store.index(SERVER, OWNER, ROOM).is_empty() and not DirAccess.dir_exists_absolute(root.path_join(SERVER.left(16)).path_join(OWNER)), "Identity deletion removes that identity's attempts")
	DirAccess.remove_absolute(root.path_join(SERVER.left(16)))
	DirAccess.remove_absolute(root)
