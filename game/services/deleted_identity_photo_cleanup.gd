class_name DeletedIdentityPhotoCleanup
extends Node
## Called only after the server confirms explicit account deletion. No network,
## credential removal, sign-out hooks, or automatic invocation on capture exit.
const Capture = preload("res://services/optional_photo_capture.gd")
const PhotoStore = preload("res://services/turn_photo_store.gd")
const MARKER_KEY := "deleted_identity_cleanup"
const TIMEOUT_MS := 16000
var bridge: Node
var store: RefCounted
var require_native := OS.has_feature("android")
var busy := false
var _results: Dictionary = {}

func _ready() -> void:
	if bridge == null:
		bridge = Capture.new()
		add_child(bridge)
	if store == null:
		store = PhotoStore.new()
	bridge.completed.connect(_completed)
	bridge.failed.connect(_failed)

static func valid_owner(owner: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]{22}$")
	var found := pattern.search(owner)
	return found != null and found.get_string() == owner

static func marker_owner(value: Variant) -> String:
	if not value is Dictionary or value.size() != 2 or value.get("schema_version") != 1 or not value.get("owner") is String:
		return ""
	return value.owner if valid_owner(value.owner) else ""

func clear_owner(owner: String) -> Dictionary:
	if busy:
		return {"ok": false, "error": "cleanup_busy"}
	if not valid_owner(owner):
		return {"ok": false, "error": "invalid_owner"}
	busy = true
	_results.clear()
	if bridge.is_available():
		# Observers are registered before dispatch; synchronous test doubles and
		# deferred native responses both resolve against the exact request id.
		var request: String = bridge.clear_photos()
		var deadline := Time.get_ticks_msec() + TIMEOUT_MS
		while not _results.has(request) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		var result: Dictionary = _results.get(request, {"ok": false, "error": "native_cleanup_timeout"})
		_results.clear()
		if not result.get("ok", false):
			busy = false
			return {"ok": false, "error": "native_photo_cleanup_failed"}
	elif require_native:
		busy = false
		return {"ok": false, "error": "native_photo_cleanup_unavailable"}
	# On desktop there is no native Android cache. Owner-scoped journals still
	# need erasing. On Android, an unavailable bridge must remain retryable.
	var erased: Dictionary = store.erase_owner(owner)
	busy = false
	return {"ok": true} if erased.get("ok") is bool and erased.ok else {"ok": false, "error": "photo_journal_cleanup_failed"}

func _completed(id: String, operation: String, acknowledgement: Dictionary) -> void:
	if busy and operation == "clear" and _results.size() < 16:
		_results[id] = {"ok": acknowledgement.size() == 1 and acknowledgement.get("cleared") is bool and acknowledgement.cleared}

func _failed(id: String, operation: String, _code: String) -> void:
	if busy and operation == "clear" and _results.size() < 16:
		_results[id] = {"ok": false}
