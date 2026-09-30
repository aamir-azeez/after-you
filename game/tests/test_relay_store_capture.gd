extends SceneTree
const Store = preload("res://services/relay_online_store.gd")
const Save = preload("res://services/local_save.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
var directory := "user://relay-capture-" + Crypto.new().generate_random_bytes(8).hex_encode()
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var scope := "relay-room-v2:" + OWNER + ":" + ROOM
	var store := Store.new(directory)
	var path := directory.path_join(scope.sha256_text() + ".json")
	_check(Store.decode_scope(store.capture_scope(scope)) == store.load_scope(scope), "Missing scope stays missing through immutable capture")
	_check(store.save_scope(scope, {"draft": "first"}).ok and store.save_scope(scope, {"draft": "second"}).ok, "Prepare recoverable generations")
	var captured := store.capture_scope(scope)
	_check(Canonical.same(Store.decode_scope(captured), Store.new(directory).load_scope(scope)), "Worker selects same current generation as synchronous read")
	_check(store.save_scope(scope, {"draft": "third"}).ok and Store.decode_scope(captured).value.draft == "second", "Capture cannot observe a later write")
	var envelope: Dictionary = Save.defaults()
	envelope.merge({"relay_online_scope": scope, "relay_online_value": {"draft": "probe"}, "generation": 10})
	for scenario: String in ["truncated", "future", "foreign", "negative", "fractional", "not_dictionary", "newer_tmp", "bad_settings"]:
		var value: Variant = envelope.duplicate(true)
		match scenario:
			"truncated": value = "{interrupted"
			"future": value.version = 2
			"foreign": value.relay_online_scope = "relay-room-v2:" + "G".repeat(22) + ":" + ROOM
			"negative": value.generation = -1
			"fractional": value.generation = 2.5
			"not_dictionary": value = []
			"bad_settings": value.settings = []
		_write(path, value)
		if scenario == "newer_tmp":
			var newer := envelope.duplicate(true)
			newer.generation = 11
			_write(path + ".tmp", newer)
		var before := _hashes(path)
		var decoded := Store.decode_scope(store.capture_scope(scope))
		var loaded := Store.new(directory).load_scope(scope)
		_check(Canonical.same(decoded, loaded), "Capture recovery agrees for " + scenario)
		_check(_hashes(path) == before, "Read-only recovery preserves bytes for " + scenario)
		if FileAccess.file_exists(path + ".tmp"): DirAccess.remove_absolute(path + ".tmp")
	_check(not store.capture_scope("../../journey").ok and not Store.decode_scope({"ok": true, "scope": scope, "raw": [PackedByteArray(), PackedByteArray(), PackedByteArray(), PackedByteArray()]}).ok, "Invalid scopes and excess generations never decode")
	for file: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
	print("RELAY STORE CAPTURE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _write(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value if value is String else JSON.stringify(value))
	file.close()

func _hashes(path: String) -> Array:
	var result: Array = []
	for suffix: String in ["", ".tmp", ".backup"]:
		result.append(FileAccess.get_sha256(path + suffix) if FileAccess.file_exists(path + suffix) else "absent")
	return result
