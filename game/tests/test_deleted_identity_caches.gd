extends SceneTree
const Cleanup = preload("res://services/deleted_identity_cache_cleanup.gd")
const Ack = preload("res://services/deleted_identity_ack.gd")
const Photos = preload("res://services/deleted_identity_photo_cleanup.gd")
const Main = preload("res://main.gd")
const Harness = preload("res://tests/test_app_state.gd")
const Save = preload("res://services/local_save.gd")
const Relay = preload("res://services/relay_online_store.gd")
const Shared = preload("res://services/shared_replay_store.gd")
const Safety = preload("res://services/safety_store.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const PEER := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

class PhotoProbe:
	extends Node
	var calls := 0
	var succeeds := true
	func clear_owner(_owner: String) -> Dictionary:
		calls += 1
		return {"ok": succeeds}

class AckApi:
	extends Node
	var player_id := OWNER
	var device_token := "synthetic-old-credential"
	var busy := false
	var calls: Array = []
	var drop := true
	var wrong_shape := false
	var before: Callable
	var changed := false
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		calls.append([method, path, body.duplicate(true)])
		if before.is_valid(): before.call()
		await get_tree().process_frame
		if changed: device_token = "changed-owner-credential"
		if drop: return {"ok": false, "code": "connection_interrupted"}
		return {"ok": true, "data": {"schema_version": 2 if wrong_shape else 1, "acknowledged": true}}

var checks := 0
var failures := 0
var directory := ""
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func write(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value if value is String else JSON.stringify(value))
	file.close()
func bytes(path: String) -> PackedByteArray: return FileAccess.get_file_as_bytes(path)
func cleanup_at(path: String) -> RefCounted:
	var cleanup := Cleanup.new()
	cleanup.relay_directory = path.path_join("relay-online")
	cleanup.shared_directory = path.path_join("shared-replays")
	cleanup.safety_directory = path.path_join("safety")
	return cleanup

func _run() -> void:
	directory = "user://delete-cache-test-" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	_test_purge()
	await _test_ack()
	await _test_main_order()
	print("AFTER YOU DELETED IDENTITY CACHES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_purge() -> void:
	var cleanup: RefCounted = cleanup_at(directory.path_join("purge"))
	var relay := Relay.new(cleanup.relay_directory)
	var shared := Shared.new(cleanup.shared_directory)
	var safety := Safety.new(cleanup.safety_directory)
	var own: Array[String] = []
	var others: Dictionary = {}
	for owner: String in [OWNER, PEER]:
		for scope: String in ["relay-lobby-v2:" + owner, "relay-room-v2:" + owner + ":" + ROOM]:
			check(relay.save_scope(scope, {"schema_version": 1, "pending": {"proof": "retained"}}).ok, "Real Relay store fixture")
			check(relay.save_scope(scope, {"schema_version": 1, "pending": {"proof": "latest"}}).ok, "Real recoverable Relay backup")
			var path: String = cleanup.relay_directory.path_join(scope.sha256_text() + ".json")
			for suffix: String in ["", ".backup"]:
				if owner == OWNER: own.append(path + suffix)
				else: others[path + suffix] = bytes(path + suffix)
		for scope: String in ["shared-replays:" + owner + ":index", "shared-replays:" + owner + ":chapter:" + ROOM, "shared-replays:" + owner + ":legacy:" + ROOM]:
			check(shared.save_scope(scope, {"schema_version": 1, "proof": "preserved"}), "Real Shared replay store fixture")
			var path: String = cleanup.shared_directory.path_join(scope.sha256_text() + ".json")
			if owner == OWNER: own.append(path)
			else: others[path] = bytes(path)
		check(safety.write(owner, Safety.empty(owner), Safety.empty(owner)), "Real safety store fixture")
		var path: String = cleanup.safety_directory.path_join(owner.sha256_text() + ".json")
		if owner == OWNER: own.append(path)
		else: others[path] = bytes(path)
	var solo := directory.path_join("lighthouse-solo.json")
	write(solo, {"private_solo_proof": "unchanged"})
	others[solo] = bytes(solo)
	# Ownership survives malformed primary through exact healthy backup.
	write(own[2], "{interrupted")
	var future: Variant = JSON.parse_string(FileAccess.get_file_as_string(own[4]))
	future.version = 77
	write(own[4], future)
	check(cleanup.erase_owner(OWNER).ok, "Purge explicit owner including future owned payload and corrupt generation")
	for path: String in own: check(not FileAccess.file_exists(path), "Every owned generation erased")
	for path: String in others: check(bytes(path) == others[path], "Other identity and solo bytes unchanged")
	check(cleanup.erase_owner(OWNER).ok, "Repeated purge is harmless")
	check(not cleanup.erase_owner("../unsafe").ok, "Invalid owner does not construct paths")
	var unknown: String = cleanup.shared_directory.path_join("unknown".sha256_text() + ".json")
	write(unknown, "{unreadable")
	check(not cleanup.erase_owner(OWNER).ok and bytes(unknown) == "{unreadable".to_utf8_buffer(), "Unattributable corrupt group held byte for byte")
	DirAccess.remove_absolute(unknown)
	var forged: String = cleanup.shared_directory.path_join("wrong-name".sha256_text() + ".json")
	write(forged, {"shared_replay_scope": "shared-replays:" + OWNER + ":index"})
	check(not cleanup.erase_owner(OWNER).ok and FileAccess.file_exists(forged), "Mismatched filename cannot confer ownership")

func _test_ack() -> void:
	var save := Save.new(directory.path_join("ack.json"))
	save.load_data()
	var api := AckApi.new()
	root.add_child(api)
	check(not (await Ack.finish(api, save, OWNER)).ok and api.calls.is_empty(), "No cleanup authorization means no ACK")
	save.update_values({Photos.MARKER_KEY: {"schema_version": 1, "owner": OWNER}})
	api.before = func(): check(save.data.has(Ack.KEY) and not save.data[Ack.KEY].acknowledged, "Local completion is durable before HTTP")
	check(not (await Ack.finish(api, save, OWNER)).ok, "Lost ACK remains pending")
	check(api.calls[0] == [HTTPClient.METHOD_POST, "/v1/identity/deletion-ack", {"schema_version": 1}], "Only exact harmless ACK is sent")
	var cold := Save.new(save.path)
	cold.load_data()
	check(Ack.valid_marker(cold.data[Ack.KEY], OWNER) and not cold.data[Ack.KEY].acknowledged, "Cold restart preserves pending ACK without credential data")
	api.drop = false
	api.wrong_shape = true
	check(not (await Ack.finish(api, cold, OWNER)).ok, "Future response is not completion")
	api.wrong_shape = false
	api.changed = true
	check(not (await Ack.finish(api, cold, OWNER)).ok, "Changed credential rejects late acknowledgment")
	api.changed = false
	check((await Ack.finish(api, cold, OWNER)).ok and cold.data[Ack.KEY].acknowledged, "Already-absent server receipt retry completes durably")
	var count: int = api.calls.size()
	api.player_id = ""
	api.device_token = ""
	check((await Ack.finish(api, cold, OWNER)).ok and api.calls.size() == count, "Confirmed durable ACK survives secret removal without network")
	check(not Ack.permitted(cold, PEER), "Other owner cannot reuse confirmed ACK")
	cold.data[Ack.KEY].schema_version = 2
	check(not (await Ack.finish(api, cold, OWNER)).ok, "Unknown marker held, never silently overwritten")
	api.queue_free()
	await process_frame

func _test_main_order() -> void:
	var app := Main.new()
	app.saves = Save.new(directory.path_join("main.json"))
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.config["revenuecat_public_key"] = ""
	var api := AckApi.new()
	app.add_child(api)
	app.api = api
	var secrets := Harness.TestSecrets.new()
	app.add_child(secrets)
	app.secrets = secrets
	secrets.completed.connect(app._secret_completed)
	secrets.failed.connect(app._secret_failed)
	var photos := PhotoProbe.new()
	app.add_child(photos)
	app.deletion_photo_cleanup = photos
	app.deletion_cache_cleanup = cleanup_at(directory.path_join("main-caches"))
	app.deleted_identity_owner = OWNER
	app.identity_data = {"player_id": OWNER, "device_token": api.device_token}
	app.identity_loading = false
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.saves.update_values({"room": {"old": true}, "pending_turn": {"keep_until_cleanup": true}, "room_draft": {}, "completed": {"solo": true}})
	api.before = func(): check(photos.calls > 0 and app.saves.data.room.is_empty() and not app.saves.data.has("pending_turn") and secrets.calls.is_empty(), "Real main clears local owned data before ACK and retains credentials")
	photos.succeeds = false
	await app._clear_deleted_identity()
	check(api.calls.is_empty() and secrets.calls.is_empty(), "Failed photo cleanup neither ACKs nor forgets")
	photos.succeeds = true
	await app._clear_deleted_identity()
	check(api.calls.size() == 1 and secrets.calls.is_empty() and app.saves.data.has(Photos.MARKER_KEY), "Lost ACK in real main holds old credentials and retry marker")
	api.drop = false
	secrets.fail_remove = true
	await app._clear_deleted_identity()
	check(app.saves.data[Ack.KEY].acknowledged and app.identity_data.player_id == OWNER, "Confirmed ACK survives failed secret removal")
	api.before = Callable()
	var count: int = api.calls.size()
	secrets.fail_remove = false
	await app._clear_deleted_identity()
	check(api.calls.size() == count and app.identity_data.is_empty() and app.api.device_token.is_empty(), "Retry clears credentials only after persisted server confirmation")
	check(not app.saves.data.has(Photos.MARKER_KEY) and not app.saves.data.has(Ack.KEY) and app.saves.data.completed == {"solo": true}, "Cleanup markers removed last; solo completion retained")
	app.queue_free()
	await process_frame
