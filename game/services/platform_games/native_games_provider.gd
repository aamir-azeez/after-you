extends "res://services/platform_games/games_provider.gd"
## Play Games (Android) and Game Center (iOS) through the app's one native plugin. Both plugins
## answer the same games_* methods with the same games_result / games_error signals, so this one
## provider serves both; only kind() differs. Payloads are bounded and parsed here; platform
## account ids never reach GDScript (the plugin sends a one-way player_key instead).
const Typed = preload("res://services/typed_values.gd")

const OPERATIONS := ["status", "sign_in", "credential", "snapshot_open", "snapshot_commit", "snapshot_resolve", "snapshot_discard"]
## Quiet checks and server credentials answer in seconds; the plugin gives up a little earlier.
const QUIET_TIMEOUT_MS := 15000
## The sign-in sheet waits for the player.
const SIGN_IN_TIMEOUT_MS := 120000
const SNAPSHOT_TIMEOUT_MS := 30000
const MAX_PAYLOAD := 4_400_000
const HANDLE := "^[a-f0-9]{32}$"
const PLAYER_KEY := "^[a-f0-9]{64}$"

var _kind := NONE
var _native: Object
var _connected := false
var _tree: SceneTree
var _pending: Dictionary = {}
var _results: Dictionary = {}
var _last_player_key := ""

## native: the plugin singleton (tests pass a fake). kind: PLAY_GAMES or GAME_CENTER.
func _init(native: Object, provider_kind: String, tree: SceneTree) -> void:
	_native = native
	_kind = provider_kind
	_tree = tree

func kind() -> String:
	return _kind

func available() -> bool:
	return _native != null and _connect()

func _connect() -> bool:
	if _connected: return true
	if not is_instance_valid(_native): return false
	for name: String in ["games_result", "games_error", "games_account_changed"]:
		if not _native.has_signal(name): return false
	_native.connect("games_result", _on_result)
	_native.connect("games_error", _on_error)
	_native.connect("games_account_changed", _on_account_changed)
	_connected = true
	return true

## One native request: games_<operation>(...args, request_id), answered once by signal or timeout.
func _call(operation: String, arguments: Array, timeout_ms: int) -> Dictionary:
	if operation not in OPERATIONS: return {"ok": false, "code": "failed"}
	if not _connect() or _tree == null: return {"ok": false, "code": "unavailable"}
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	_pending[id] = operation
	var args := arguments.duplicate()
	args.append(id)
	# Android's JNI singleton dispatches through callv; Object.has_method cannot see its methods.
	_native.callv("games_" + operation, args)
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not _results.has(id) and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	var result: Dictionary = _results.get(id, {"ok": false, "code": "timeout"})
	_pending.erase(id)
	_results.erase(id)
	return result

func _on_result(id: String, operation: String, payload_json: String) -> void:
	if _pending.get(id) != operation or _results.has(id): return
	if payload_json.length() > MAX_PAYLOAD:
		_results[id] = {"ok": false, "code": "failed"}
		return
	var parsed: Variant = JSON.parse_string(payload_json)
	_results[id] = {"ok": true, "data": parsed} if parsed is Dictionary else {"ok": false, "code": "failed"}

func _on_error(id: String, operation: String, code: String) -> void:
	if _pending.get(id) != operation or _results.has(id): return
	# Only known codes pass; anything else is "failed", so no platform text reaches the UI.
	_results[id] = {"ok": false, "code": code if code in ["unavailable", "signed_out", "cancelled", "offline", "timeout", "busy", "not_configured"] else "failed"}

func _on_account_changed(_payload_json: String) -> void:
	account_changed.emit()

static var _patterns: Dictionary = {}
static func _matches(text: String, pattern: String) -> bool:
	if not _patterns.has(pattern): _patterns[pattern] = RegEx.create_from_string(pattern)
	return (_patterns[pattern] as RegEx).search(text) != null

func authenticate(interactive: bool) -> Dictionary:
	var answer := await _call("sign_in" if interactive else "status", [], SIGN_IN_TIMEOUT_MS if interactive else QUIET_TIMEOUT_MS)
	if not answer.ok: return answer
	var data: Dictionary = answer.data
	if not data.get("signed_in") is bool: return {"ok": false, "code": "failed"}
	if not data.signed_in: return {"ok": true, "signed_in": false}
	var key: Variant = data.get("player_key")
	if not key is String or not _matches(key, PLAYER_KEY): return {"ok": false, "code": "failed"}
	if not _last_player_key.is_empty() and _last_player_key != key: account_changed.emit()
	_last_player_key = key
	return {"ok": true, "signed_in": true, "player_key": key}

func server_credential(web_client_id: String) -> Dictionary:
	var answer := await _call("credential", [web_client_id], QUIET_TIMEOUT_MS)
	if not answer.ok: return answer
	var credential: Variant = answer.data.get("credential")
	if not credential is Dictionary or credential.is_empty() or JSON.stringify(credential).length() > 6000: return {"ok": false, "code": "failed"}
	return {"ok": true, "credential": credential}

func _snapshot_answer(answer: Dictionary) -> Dictionary:
	if not answer.ok: return answer
	var data: Dictionary = answer.data
	var handle: Variant = data.get("handle")
	if not handle is String or not _matches(handle, HANDLE) or not data.get("data") is String: return {"ok": false, "code": "failed"}
	var out := {"ok": true, "handle": handle, "data": Marshalls.base64_to_raw(data.data) if not data.data.is_empty() else PackedByteArray()}
	var conflict: Variant = data.get("conflict")
	if conflict is Dictionary:
		if not conflict.get("data") is String: return {"ok": false, "code": "failed"}
		out.conflict = {"data": Marshalls.base64_to_raw(conflict.data) if not conflict.data.is_empty() else PackedByteArray()}
	return out

func snapshot_open(name: String) -> Dictionary:
	return _snapshot_answer(await _call("snapshot_open", [name], SNAPSHOT_TIMEOUT_MS))

func snapshot_commit(handle: String, data: PackedByteArray, description: String) -> Dictionary:
	var answer := await _call("snapshot_commit", [handle, Marshalls.raw_to_base64(data), description], SNAPSHOT_TIMEOUT_MS)
	if not answer.ok: return answer
	return {"ok": true} if Typed.equal(answer.data.get("committed"), true) else {"ok": false, "code": "failed"}

func snapshot_resolve(handle: String, data: PackedByteArray) -> Dictionary:
	return _snapshot_answer(await _call("snapshot_resolve", [handle, Marshalls.raw_to_base64(data)], SNAPSHOT_TIMEOUT_MS))

func snapshot_discard(handle: String) -> Dictionary:
	var answer := await _call("snapshot_discard", [handle], QUIET_TIMEOUT_MS)
	return {"ok": true} if answer.ok else answer
