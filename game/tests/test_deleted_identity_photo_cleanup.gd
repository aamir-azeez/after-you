extends SceneTree

const Cleanup = preload("res://services/deleted_identity_photo_cleanup.gd")
const Photos = preload("res://services/turn_photo_store.gd")
const Save = preload("res://services/local_save.gd")
const Main = preload("res://main.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const OWNER := "AAAAAAAAAAAAAAAAAAAAAA"
const OTHER := "BBBBBBBBBBBBBBBBBBBBBB"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

class Bridge extends Node:
	signal completed(id: String, operation: String, payload: Dictionary)
	signal failed(id: String, operation: String, code: String)
	var available := true
	var outcome := "success"
	var calls := 0
	func is_available() -> bool:
		return available
	func clear_photos() -> String:
		calls += 1
		var id := "clear-" + str(calls)
		# Deliberately synchronous and noisy: neither an unrelated id nor an
		# operation's receipt may authorize journal or credential deletion.
		completed.emit("old", "clear", {"cleared": true})
		completed.emit(id, "discard", {"cleared": true})
		if outcome == "failure":
			failed.emit(id, "clear", "private native diagnostic must not propagate")
		elif outcome == "extra":
			completed.emit(id, "clear", {"cleared": true, "unexpected": true})
		elif outcome == "false":
			completed.emit(id, "clear", {"cleared": false})
		else:
			completed.emit(id, "clear", {"cleared": true})
		return id

class PhotoProbe extends RefCounted:
	var calls: Array[String] = []
	var success := true
	func erase_owner(owner: String) -> Dictionary:
		calls.append(owner)
		return {"ok": success}

class CleanupProbe extends Node:
	var calls: Array[String] = []
	var success := false
	func clear_owner(owner: String) -> Dictionary:
		calls.append(owner)
		await get_tree().process_frame
		return {"ok": success}

class SecretsProbe extends Node:
	signal completed(id: String, operation: String, payload: Dictionary)
	signal failed(id: String, operation: String, code: String)
	var identity: Dictionary = {}
	var removes := 0
	var outcome := "success"
	func is_available() -> bool:
		return true
	func remove_secret(_name: String) -> String:
		removes += 1
		var id := "remove-" + str(removes)
		_reply.call_deferred(id)
		return id
	func _reply(id: String) -> void:
		if outcome == "failure":
			failed.emit(id, "remove", "secure_storage_unavailable")
		elif outcome == "false":
			completed.emit(id, "remove", {"removed": false})
		else:
			identity = {}
			completed.emit(id, "remove", {"removed": true})

var checks := 0
var failures := 0
var paths: Array[String] = []
var folders: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	await _test_helper()
	_test_store()
	await _test_main()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)
	for folder: String in folders:
		DirAccess.remove_absolute(folder) # Only empty, individually created test directories.
	print("Deleted identity photo cleanup: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_helper() -> void:
	var helper := Cleanup.new()
	var bridge := Bridge.new()
	var store := PhotoProbe.new()
	helper.bridge = bridge
	helper.store = store
	helper.require_native = true
	helper.add_child(bridge)
	root.add_child(helper)
	for invalid: String in ["", "short", "../" + OWNER, OWNER + "\n"]:
		_check(not (await helper.clear_owner(invalid)).ok, "Invalid owner cannot trigger native or file cleanup")
	_check(bridge.calls == 0 and store.calls.is_empty(), "Invalid requests perform no destructive action")
	_check(Cleanup.marker_owner({"schema_version": 1, "owner": OWNER}) == OWNER, "Exact owner-only marker is recognized")
	for invalid: Variant in [{}, {"schema_version": 2, "owner": OWNER}, {"schema_version": 1, "owner": OWNER, "token": "ignored"}, {"schema_version": 1, "owner": OWNER + "\n"}]:
		_check(Cleanup.marker_owner(invalid).is_empty(), "Unknown or malformed deletion marker remains held")
	bridge.available = false
	_check(not (await helper.clear_owner(OWNER)).ok and store.calls.is_empty(), "Android bridge absence cannot claim orphan cache removal")
	helper.require_native = false
	_check((await helper.clear_owner(OWNER)).ok and store.calls == [OWNER], "Desktop without native cache still erases the exact owner's journals")
	helper.require_native = true
	bridge.available = true
	store.calls.clear()
	for outcome: String in ["failure", "extra", "false"]:
		bridge.outcome = outcome
		var result: Dictionary = await helper.clear_owner(OWNER)
		_check(not result.ok and not JSON.stringify(result).contains("private native"), "Failure and malformed acknowledgements produce bounded errors")
		_check(store.calls.is_empty(), "Unconfirmed native clear never removes the retry journal")
	bridge.outcome = "success"
	store.success = false
	_check(not (await helper.clear_owner(OWNER)).ok and store.calls == [OWNER], "File cleanup failure remains incomplete after successful native cleanup")
	store.success = true
	_check((await helper.clear_owner(OWNER)).ok and store.calls == [OWNER, OWNER], "Cleanup can safely retry the same owner")
	helper.busy = true
	var previous := bridge.calls
	_check(not (await helper.clear_owner(OWNER)).ok and bridge.calls == previous, "Overlapping cleanup cannot start a second native clear")
	helper.busy = false
	helper.queue_free()
	await process_frame

func _test_store() -> void:
	var directory := "user://delete-photo-test-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Photos.new(directory)
	var owner_scope := "turn-photo-v1:" + OWNER + ":" + ROOM + ":t0-0-a"
	var other_scope := "turn-photo-v1:" + OTHER + ":" + ROOM + ":t0-0-b"
	for scope: String in [owner_scope, other_scope]:
		_check(store.save_scope(scope, {"selected": "synthetic-cache-reference"}).ok, "Create isolated owner photo journal")
		_check(store.save_scope(scope, {"selected": "second-synthetic-reference"}).ok, "Create recoverable backup generation")
		paths.append(store._path(scope))
	var other_before := FileAccess.get_file_as_bytes(store._path(other_scope))
	var other_backup := FileAccess.get_file_as_bytes(store._path(other_scope) + ".backup")
	var owner_folder: String = store._path(owner_scope).get_base_dir()
	var other_folder: String = store._path(other_scope).get_base_dir()
	folders.append_array([owner_folder, other_folder, directory])
	var unknown := owner_folder.path_join("preserve-unknown.txt")
	_write(unknown, "unrecognized local data")
	paths.append(unknown)
	_check(not store.erase_owner(OWNER).ok and FileAccess.file_exists(unknown), "Unknown owner-directory files are preserved and prevent a false complete result")
	_check(not FileAccess.file_exists(store._path(owner_scope)) and not FileAccess.file_exists(store._path(owner_scope) + ".backup"), "Recognized primary and backup photo journals are erased")
	_check(FileAccess.get_file_as_bytes(store._path(other_scope)) == other_before and FileAccess.get_file_as_bytes(store._path(other_scope) + ".backup") == other_backup, "Other owner's primary and backup bytes remain unchanged")
	DirAccess.remove_absolute(unknown)
	_check(store.erase_owner(OWNER).ok and store.erase_owner(OWNER).ok, "Retry and already-empty owner cleanup are idempotent")
	_check(not store._stores.has(owner_scope) and store._stores.has(other_scope), "In-memory journals are cleared only for the deleted owner")
	DirAccess.remove_absolute(owner_folder)
	_write(owner_folder, "directory replaced with a file")
	_check(not store.erase_owner(OWNER).ok, "A non-directory obstruction is not reported as an empty cache")
	DirAccess.remove_absolute(owner_folder)

func _test_main() -> void:
	var path := "user://delete-main-test-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	paths.append(path)
	var app := Main.new()
	app.saves = Save.new(path)
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.soundscape.configure({"sound": false, "haptics": false})
	app.config["revenuecat_public_key"] = ""
	var api := FakeApi.new()
	app.add_child(api)
	app.api = api
	var storage := SecretsProbe.new()
	app.add_child(storage)
	app.secrets = storage
	storage.completed.connect(app._secret_completed)
	storage.failed.connect(app._secret_failed)
	var cleanup := CleanupProbe.new()
	app.add_child(cleanup)
	app.deletion_photo_cleanup = cleanup
	_set_identity(app, api, storage)
	_check(app.saves.update_values({"completed": {"first_light": true}, "room": {"room_id": ROOM}}), "Create isolated ordinary save")
	var solo_before: Dictionary = app.saves.data.completed.duplicate(true)
	api.responses = [{"ok": false, "status": 401, "error": "Not signed in"}]
	await app._delete_identity()
	_check(not app.saves.data.has(Cleanup.MARKER_KEY) and cleanup.calls.is_empty() and storage.removes == 0, "HTTP failure is never treated as remote deletion confirmation")
	api.responses = [{"ok": true, "data": {}}]
	await app._delete_identity()
	_check(cleanup.calls == [OWNER] and storage.removes == 0 and not storage.identity.is_empty(), "Failed photo cleanup retains encrypted identity")
	_check(Cleanup.marker_owner(app.saves.data.get(Cleanup.MARKER_KEY)) == OWNER, "Confirmed deletion persists an owner-only retry marker")
	_check(not JSON.stringify(app.saves.data).contains(storage.identity.device_token), "Deletion marker never writes the device credential to ordinary saves")
	_check(not await app._ensure_identity() and api.calls.size() == 2, "Pending cleanup prevents new identities and online calls")
	var reloaded := Save.new(path)
	reloaded.load_data()
	app.saves = reloaded
	app.deleted_identity_owner = ""
	app.identity_restart_required = false
	app.identity_request = "restart-read"
	app._secret_completed("restart-read", "get", {"found": true, "value": JSON.stringify(storage.identity)})
	_check(app.identity_restart_required and app.deleted_identity_owner == OWNER and not storage.identity.is_empty(), "Restart reads the retained identity and restores the cleanup obligation")
	app._show_account()
	_check(_button(app, "Retry device cleanup") != null and _button(app, "Show my recovery details") == null, "Account screen offers retry instead of using the deleted account")
	cleanup.success = true
	storage.outcome = "false"
	await app._clear_deleted_identity()
	_check(app.saves.data.has(Cleanup.MARKER_KEY) and not app.identity_data.is_empty(), "A false Keystore removal receipt is not cleanup success")
	storage.outcome = "success"
	app._show_account()
	var retry := _button(app, "Retry device cleanup")
	_check(retry != null, "Retry remains visible after credential cleanup failure")
	if retry != null:
		retry.pressed.emit()
		await process_frame
		while app.deletion_cleanup_busy:
			await process_frame
	_check(app.identity_data.is_empty() and storage.identity.is_empty() and not app.saves.data.has(Cleanup.MARKER_KEY), "Actual retry action clears the marker only after photo and Keystore acknowledgements")
	_check(app.saves.data.completed == solo_before and app.saves.data.room.is_empty(), "Account deletion retains solo progress while clearing online room state")
	_check(_button(app, "Close After You") != null and _button(app, "Retry device cleanup") == null, "Completed UI appears only after every local step succeeds")
	# No implicit deletion: calling cleanup without confirmation, then a
	# read-only marker write, cannot clear photos or credentials.
	_set_identity(app, api, storage)
	var previous := cleanup.calls.size()
	await app._clear_deleted_identity()
	_check(cleanup.calls.size() == previous, "Direct cleanup without a confirmed marker or response performs no deletion")
	app.deleted_identity_owner = OWNER
	app.saves.read_only = true
	await app._clear_deleted_identity()
	_check(cleanup.calls.size() == previous and not storage.identity.is_empty(), "Failed durable marker write stops before destructive cleanup")
	app.saves.read_only = false
	_check(app.saves.update_values({Cleanup.MARKER_KEY: {"schema_version": 1, "owner": OTHER}}), "Create explicit mismatched-owner marker fixture")
	await app._clear_deleted_identity()
	_check(cleanup.calls.size() == previous and not storage.identity.is_empty(), "Mismatched marker cannot remove another retained identity")
	app.queue_free()
	await process_frame
	await process_frame

func _set_identity(app: Node, api: Node, storage: SecretsProbe) -> void:
	storage.identity = {"player_id": OWNER, "device_token": "D".repeat(43), "recovery_code": "C".repeat(43)}
	app.identity_data = storage.identity.duplicate(true)
	app.identity_read_state = app.IdentityReadState.LOADED
	app.identity_restart_required = false
	app.deleted_identity_owner = ""
	api.player_id = OWNER
	api.device_token = storage.identity.device_token

func _button(app: Node, text: String) -> Button:
	for button: Button in app.overlay.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
