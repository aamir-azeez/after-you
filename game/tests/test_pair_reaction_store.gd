extends SceneTree
## Synthetic isolated directories only. No gameplay/photo/credential files.
const Store = preload("res://services/pair_reaction_store.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
var root_path := ""
var checks := 0
var failures := 0

func _initialize() -> void:
	root_path = "user://pair-reaction-store-test-" + Crypto.new().generate_random_bytes(8).hex_encode()
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL pair reaction store: " + message)

func _scope(owner: String = OWNER, room: String = ROOM, pair: String = "p0-0") -> String:
	return "pair-reaction-v1:" + owner + ":" + room + ":" + pair

func _write(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "synthetic fixture writable")
		return
	file.store_string(value if value is String else JSON.stringify(value))
	file.close()

func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func _journal(scope: String, counter: int = 1) -> Dictionary:
	var parts := scope.split(":")
	return {"schema_version": 1, "owner": parts[1], "target": {"room_id": parts[2], "pair_id": parts[3], "a_hash": "a".repeat(64), "b_hash": "b".repeat(64), "host_id": OWNER, "guest_id": GUEST}, "state": {"counter": counter}, "pending": {}, "last_receipt": {}}

func _envelope(scope: String, counter: int = 1, generation: int = 1) -> Dictionary:
	return {"version": 1, "generation": generation, "pair_reaction_scope": scope, "pair_reaction_value": _journal(scope, counter)}

func _run() -> void:
	_roundtrip_and_owners()
	_recover_and_hold()
	_value_and_file_bounds()
	_capacity_and_paths()
	_cleanup_failures()
	_remove_test_tree(root_path)
	print("Pair reaction store checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)

func _roundtrip_and_owners() -> void:
	var folder := root_path.path_join("roundtrip")
	var disk := Store.new(folder)
	var own := _scope()
	var other := _scope(GUEST)
	_check(disk.load_scope(own) == {"ok": true, "found": false, "value": {}}, "missing journal is empty")
	_check(not DirAccess.dir_exists_absolute(folder), "read alone creates no directory")
	_check(disk.save_scope(own, _journal(own, 1)).get("ok", false), "first owner save")
	_check(disk.save_scope(own, _journal(own, 2)).get("ok", false), "second generation")
	_check(disk.save_scope(other, _journal(other, 50)).get("ok", false), "other owner separate save")
	var path: String = disk._path(own)
	var other_path: String = disk._path(other)
	_check(path == folder.path_join(OWNER.sha256_text()).path_join(own.sha256_text() + ".json"), "only hashed owner and scope enter path")
	var before := _bytes(path)
	var other_before := _bytes(other_path)
	var restarted := Store.new(folder)
	var restored: Dictionary = restarted.load_scope(own)
	# Compare against the same JSON number representation as a cold disk read.
	var expected: Dictionary = JSON.parse_string(JSON.stringify(_journal(own, 2)))
	_check(restored.get("ok", false) and restored.value == expected, "cold load keeps exact latest JSON value")
	_check(_bytes(path) == before, "load does not rewrite generations")
	restored.value.state.counter = 999
	_check(restarted.load_scope(own).value.state.counter == 2, "returned value is detached")
	_check(disk.erase_owner(OWNER).get("ok", false), "confirmed deletion removes own files")
	_check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".backup"), "all own generations erased")
	_check(not disk.save_scope(own, _journal(own, 3)).get("ok", false), "late same-instance write cannot revive erased owner")
	_check(not disk.load_scope(own).get("ok", false), "same-instance deleted owner remains retired")
	_check(_bytes(other_path) == other_before and disk.load_scope(other).value.state.counter == 50, "other owner bytes and cached scope preserved")
	_check(disk.erase_owner(OWNER).get("ok", false), "deletion retry is idempotent")
	_check(Store.new(folder).load_scope(own).get("found") == false, "cold deleted scope has no restored bytes")

func _recover_and_hold() -> void:
	var disk := Store.new(root_path.path_join("recovery"))
	var scope := _scope()
	var path: String = disk._path(scope)
	_write(path, "{")
	_write(path + ".backup", _envelope(scope, 1, 1))
	_write(path + ".tmp", _envelope(scope, 3, 3))
	var primary := _bytes(path)
	var temporary := _bytes(path + ".tmp")
	_check(disk.load_scope(scope).value.state.counter == 3, "complete latest temporary recovers truncated primary")
	_check(_bytes(path) == primary and _bytes(path + ".tmp") == temporary, "recovery read writes nothing")
	var future := _envelope(scope, 7, 7)
	future.version = 99
	_write(path + ".backup", future)
	_check(not disk.load_scope(scope).get("ok", false), "future backup holds even with valid newer temporary")
	_check(not disk.save_scope(scope, _journal(scope, 4)).get("ok", false), "cached store cannot bypass future backup")
	_check(_bytes(path + ".tmp") == temporary, "held save preserves pending temporary")
	DirAccess.remove_absolute(path + ".backup")
	DirAccess.remove_absolute(path + ".tmp")
	_write(path, _envelope(scope))
	_check(disk.load_scope(scope).get("ok", false), "known envelope loads again")
	var future_inner := _envelope(scope)
	future_inner.pair_reaction_value.schema_version = 2
	_write(path, future_inner)
	var future_bytes := _bytes(path)
	_check(not disk.save_scope(scope, _journal(scope, 4)).get("ok", false), "cached writer holds a future inner journal")
	_check(_bytes(path) == future_bytes, "future inner journal bytes preserved")
	var wrong_target := _envelope(scope)
	wrong_target.pair_reaction_value.target.pair_id = "p1-0"
	_write(path, wrong_target)
	_check(not disk.load_scope(scope).get("ok", false), "inner target must match scoped pair")
	for invalid: Dictionary in [future, {"version": 1, "generation": 1, "pair_reaction_scope": _scope(GUEST), "pair_reaction_value": {}}, {"version": 1, "generation": 1, "pair_reaction_scope": scope, "pair_reaction_value": {}, "future_flag": true}]:
		_write(path, invalid)
		var saved := _bytes(path)
		_check(not disk.save_scope(scope, _journal(scope, 5)).get("ok", false), "readable unknown generation holds before write")
		_check(_bytes(path) == saved, "unknown generation byte preservation")
	for generation: Variant in [-1, 1.5, 2147483648]:
		var invalid := _envelope(scope)
		invalid.generation = generation
		_write(path, invalid)
		_check(not disk.load_scope(scope).get("ok", false), "invalid generation rejected")
	var old := _envelope(scope)
	old.settings = {"sound": true, "assistance": true}
	_write(path, old)
	_check(disk.load_scope(scope).get("ok", false), "omitted newly introduced inert defaults allowed")
	old.settings.sound = false
	_write(path, old)
	_check(not disk.load_scope(scope).get("ok", false), "reaction journal cannot silently carry active preference state")
	_write(path, _envelope(scope, 1, 2147483647))
	_check(not disk.save_scope(scope, _journal(scope)).get("ok", false), "generation exhaustion never writes an unreadable successor")

func _value_and_file_bounds() -> void:
	var disk := Store.new(root_path.path_join("bounds"))
	var scope := _scope()
	var exact_value := _journal(scope)
	exact_value.state = {"payload": ""}
	var overhead := JSON.stringify(exact_value).to_utf8_buffer().size()
	exact_value.state.payload = "x".repeat(Store.MAX_VALUE - overhead)
	_check(disk.save_scope(scope, exact_value).get("ok", false), "exact UTF8 value byte cap accepted")
	var path: String = disk._path(scope)
	var before := _bytes(path)
	exact_value.state.payload += "x"
	_check(not disk.save_scope(scope, exact_value).get("ok", false), "one byte above cap rejected")
	exact_value.state.payload = String.chr(0x00e9).repeat(Store.MAX_VALUE)
	_check(not disk.save_scope(scope, exact_value).get("ok", false), "UTF8 bytes bounded rather than character count only")
	_check(_bytes(path) == before, "oversize writes preserve primary")
	var cycle := _journal(scope)
	cycle.state.self = cycle.state
	_check(not disk.save_scope(scope, cycle).get("ok", false), "cyclic caller value rejected before serialization")
	cycle.state.clear()
	cycle.state.nan = NAN
	_check(not disk.save_scope(scope, cycle).get("ok", false), "nonfinite JSON value rejected")
	_write(path + ".tmp", "x".repeat(Store.MAX_FILE + 1))
	_check(not disk.load_scope(scope).get("ok", false), "oversized recovery file holds primary fallback")
	_check(_bytes(path) == before, "oversized recovery load preserves primary")

func _capacity_and_paths() -> void:
	var disk := Store.new(root_path.path_join("capacity"))
	for invalid: String in [_scope("../escape"), _scope(OWNER, ROOM, "p32-0"), _scope(OWNER, ROOM, "p0-2"), _scope() + "/../x", _scope().replace("pair-reaction-v1", "pair-reaction-v2")]:
		_check(disk._path(invalid).is_empty() and not disk.save_scope(invalid, {}).get("ok", false), "invalid scope never resolves path")
	var last := ""
	for index: int in range(Store.MAX_PAIRS):
		last = _scope(OWNER, str(index).pad_zeros(22))
		_write(disk._path(last), _envelope(last))
		if index == 0: _write(disk._path(last) + ".backup", _envelope(last, 0, 0))
	_check(disk.save_scope(_scope(), _journal(_scope())).get("error") == "local_reaction_history_full", "129th pair rejected without eviction")
	_check(disk.save_scope(last, _journal(last, 2)).get("ok", false), "existing pair can change at capacity")
	_check(disk.save_scope(_scope(GUEST), _journal(_scope(GUEST), 3)).get("ok", false), "capacity belongs to one owner only")
	_check(disk.erase_owner(OWNER).get("ok", false), "bounded capacity directory can be erased")
	_check(disk.load_scope(_scope(GUEST)).value.state.counter == 3, "capacity erasure preserves other owner")

func _cleanup_failures() -> void:
	var disk := Store.new(root_path.path_join("cleanup"))
	var scope := _scope()
	_check(disk.save_scope(scope, _journal(scope, 1)).get("ok", false), "cleanup fixture saved")
	var path: String = disk._path(scope)
	var unknown := path.get_base_dir().path_join("unrecognized-future.json")
	_write(unknown, "keep")
	var before := _bytes(path)
	_check(not disk.erase_owner(OWNER).get("ok", false), "unknown owner file holds cleanup")
	_check(_bytes(path) == before and FileAccess.get_file_as_string(unknown) == "keep", "cleanup never partly deletes an unknown inventory")
	_check(not disk.save_scope(scope, _journal(scope)).get("ok", false), "failed erasure still retires stale writes")
	DirAccess.remove_absolute(unknown)
	_check(disk.erase_owner(OWNER).get("ok", false), "explicit cleanup retry succeeds after obstruction is resolved")
	_check(not disk.erase_owner("../").get("ok", false), "invalid owner deletion rejected")
	var other := _scope(GUEST)
	_write(disk._path(other), _envelope(other))
	var nested := disk._path(other).get_base_dir().path_join("future-folder")
	DirAccess.make_dir_recursive_absolute(nested)
	_write(nested.path_join("keep.txt"), "keep")
	_check(not disk.erase_owner(GUEST).get("ok", false), "owner cleanup does not recurse into directories")
	_check(FileAccess.get_file_as_string(nested.path_join("keep.txt")) == "keep", "nested data preserved")

func _remove_test_tree(path: String) -> void:
	# This test-created UUID root is the only recursive cleanup target.
	if path != root_path and not path.begins_with(root_path + "/"): return
	for folder: String in DirAccess.get_directories_at(path): _remove_test_tree(path.path_join(folder))
	for filename: String in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(filename))
	DirAccess.remove_absolute(path)
