extends RefCounted
## Authenticated, explicit safety operations. No timer-triggered POSTs.
const Store = preload("res://services/safety_store.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const TERMS_VERSION := "2026-09-16"
const PATHS := ["/privacy", "/account-deletion", "/community-rules"]
var busy := false
var last_error := ""
var last_code := ""
var terms_accepted := false
var config: Dictionary = {}
var _api: Node
var _identity: Callable
var _transport: Callable
var _store: RefCounted
var _owner := ""
var _binding: Dictionary = {}
var _state: Dictionary = {}
var _generation := 0

func _init(api: Node, identity: Callable, store: RefCounted = null, transport: Callable = Callable()) -> void:
	_api = api
	_identity = identity
	_store = Store.new() if store == null else store
	_transport = transport

func invalidate() -> void:
	_generation += 1
	busy = false
	_binding = {}
	_owner = ""
	_state = {}
	terms_accepted = false
	config = {}

func _context() -> Dictionary:
	var value: Variant = _identity.call() if _identity.is_valid() else null
	if not value is Dictionary or value.get("ready") != true or not Store.id(value.get("player_id")): return {}
	var result: Dictionary = value.duplicate(true)
	if is_instance_valid(_api):
		if _api.player_id != value.player_id or _api.device_token.is_empty(): return {}
		result["credential_hash"] = str(_api.device_token).sha256_text()
	return result

func _bound() -> bool:
	var value := _context()
	if value.is_empty(): return _fail("identity_changed")
	if value != _binding:
		invalidate()
		_binding = value
		_owner = value.player_id
	var loaded: Dictionary = _store.read(_owner)
	if not loaded.get("ok", false): return _fail("safety_storage_unavailable")
	_state = loaded.value.duplicate(true)
	return true

func _same(generation: int) -> bool:
	return generation == _generation and not _binding.is_empty() and _context() == _binding

func _begin() -> int:
	if busy: _fail("request_busy"); return -1
	if not _bound(): return -1
	busy = true
	last_error = ""
	last_code = ""
	return _generation

func _finish(generation: int, result: bool) -> bool:
	if not _same(generation): return false
	busy = false
	return result

func _persist(value: Dictionary) -> bool:
	if _context() != _binding: return _fail("identity_changed")
	if Canonical.same(value, _state): return true
	if not _store.write(_owner, value, _state): return _fail("safety_storage_unavailable")
	_state = value.duplicate(true)
	return true

func _net(generation: int, method: int, path: String, body: Dictionary = {}) -> Dictionary:
	if not _same(generation): return {}
	if is_instance_valid(_api) and _api.busy:
		_fail("request_busy"); return {}
	var response: Variant = await _transport.call(method, path, body.duplicate(true)) if _transport.is_valid() else await _api.request_json(method, path, body)
	if not _same(generation): return {}
	if not response is Dictionary: _fail("unsupported_safety_response"); return {}
	if response.get("ok", false) != true:
		_fail(str(response.get("code", "safety_unavailable")))
	return response

func public_url(path: String) -> String:
	if path not in PATHS or not is_instance_valid(_api): return ""
	var base := str(_api.base_url).trim_suffix("/")
	return base + path if base.begins_with("https://") else ""

func open_public(path: String) -> bool:
	var url := public_url(path)
	return not url.is_empty() and OS.shell_open(url) == OK

static func valid_config(value: Variant) -> bool:
	return value is Dictionary and value.size() == 6 and value.get("schema_version") == 1 and value.get("enforced") is bool and value.get("terms_version") == TERMS_VERSION and value.get("privacy_path") == "/privacy" and value.get("deletion_path") == "/account-deletion" and value.get("rules_path") == "/community-rules"

static func valid_terms(value: Variant) -> bool:
	return value is Dictionary and value.size() == 4 and value.get("schema_version") == 1 and value.get("terms_version") == TERMS_VERSION and value.get("accepted") is bool and value.has("accepted_at") and ((value.accepted_at is String and value.accepted_at.length() >= 20 and value.accepted_at.length() <= 40) if value.accepted else value.accepted_at == null)

func check_terms() -> bool:
	var ticket := _begin()
	if ticket < 0: return false
	terms_accepted = false
	config = {}
	var response := await _net(ticket, HTTPClient.METHOD_GET, "/v1/safety/config")
	if not _same(ticket): return false
	if not response.get("ok", false): return _finish(ticket, false)
	if not valid_config(response.get("data")): return _finish(ticket, _fail("unsupported_safety_response"))
	config = response.data.duplicate(true)
	response = await _net(ticket, HTTPClient.METHOD_GET, "/v1/safety/terms")
	if not _same(ticket): return false
	if not response.get("ok", false): return _finish(ticket, false)
	if not valid_terms(response.get("data")): return _finish(ticket, _fail("unsupported_safety_response"))
	terms_accepted = response.data.accepted
	return _finish(ticket, true)

func accept_rules() -> bool:
	# This is called only by the explicit acceptance button after showing rules.
	if not valid_config(config): return _fail("safety_unavailable")
	var ticket := _begin()
	if ticket < 0: return false
	if not valid_config(config): return _finish(ticket, _fail("safety_unavailable"))
	var response := await _net(ticket, HTTPClient.METHOD_POST, "/v1/safety/terms", {"schema_version": 1, "terms_version": TERMS_VERSION})
	if not _same(ticket): return false
	if not response.get("ok", false): return _finish(ticket, false)
	if not valid_terms(response.get("data")) or not response.data.accepted: return _finish(ticket, _fail("unsupported_safety_response"))
	terms_accepted = true
	return _finish(ticket, true)

func blocked_players() -> Array:
	return _state.get("blocked_players", []).duplicate() if _bound() else []

func pending_report() -> Dictionary:
	return _state.get("pending", {}).duplicate(true) if _bound() else {}

func partner_allowed(family: String, room: String, peer: String = "") -> bool:
	return _bound() and _store.partner_allowed(_owner, family, room, peer)

static func valid_room(room: Dictionary) -> bool:
	return room.get("room_family") in ["legacy", "relay"] and Store.id(room.get("room_id")) and Store.id(room.get("peer_id"))

func refresh_blocks() -> bool:
	var ticket := _begin()
	if ticket < 0: return false
	var response := await _net(ticket, HTTPClient.METHOD_GET, "/v1/safety/blocks")
	if not _same(ticket): return false
	if not response.get("ok", false): return _finish(ticket, false)
	var value: Variant = response.get("data")
	if not value is Dictionary or value.size() != 2 or value.get("schema_version") != 1 or not value.get("blocked_players") is Array or value.blocked_players.size() > 128: return _finish(ticket, _fail("unsupported_safety_response"))
	var next := _state.duplicate(true)
	next.blocked_players = value.blocked_players.duplicate()
	for key: String in next.blocked_rooms.keys():
		if next.blocked_rooms[key] not in next.blocked_players: next.blocked_rooms.erase(key)
	if not Store.valid(next, _owner): return _finish(ticket, _fail("unsupported_safety_response"))
	var saved := _persist(next)
	if saved:
		for key: String in Store.suppressed_rooms.keys():
			if key.begins_with(_owner + ":") and Store.suppressed_rooms[key] not in next.blocked_players: Store.suppressed_rooms.erase(key)
	return _finish(ticket, saved)

func block(room: Dictionary) -> bool:
	if not valid_room(room): return _fail("invalid_safety_target")
	var ticket := _begin()
	if ticket < 0: return false
	if room.peer_id == _owner: return _finish(ticket, _fail("invalid_safety_target"))
	var response := await _net(ticket, HTTPClient.METHOD_POST, "/v1/safety/block", {"schema_version": 1, "room_family": room.room_family, "room_id": room.room_id})
	if not _same(ticket): return false
	if not response.get("ok", false): return _finish(ticket, false)
	var value: Variant = response.get("data")
	if not value is Dictionary or value.size() != 3 or value.get("schema_version") != 1 or value.get("blocked") != true or value.get("player_id") != room.peer_id: return _finish(ticket, _fail("unsupported_safety_response"))
	Store.suppressed_rooms[_owner + ":" + room.room_family + ":" + room.room_id] = room.peer_id
	var next := _state.duplicate(true)
	if room.peer_id not in next.blocked_players: next.blocked_players.append(room.peer_id)
	next.blocked_rooms[room.room_family + ":" + room.room_id] = room.peer_id
	return _finish(ticket, _persist(next))

func unblock(player: String) -> bool:
	if not Store.id(player): return _fail("invalid_safety_target")
	var ticket := _begin()
	if ticket < 0: return false
	var response := await _net(ticket, HTTPClient.METHOD_DELETE, "/v1/safety/blocks/" + player)
	if not _same(ticket): return false
	if not response.get("ok", false): return _finish(ticket, false)
	var value: Variant = response.get("data")
	if not value is Dictionary or value.size() != 3 or value.get("schema_version") != 1 or value.get("blocked") != false or value.get("player_id") != player: return _finish(ticket, _fail("unsupported_safety_response"))
	var next := _state.duplicate(true)
	next.blocked_players.erase(player)
	var cleared: Array[String] = []
	for key: String in next.blocked_rooms.keys():
		if next.blocked_rooms[key] == player:
			cleared.append(_owner + ":" + key)
			next.blocked_rooms.erase(key)
	var saved := _persist(next)
	if saved:
		for key: String in cleared: Store.suppressed_rooms.erase(key)
	return _finish(ticket, saved)

func report(room: Dictionary, reason: String, photo: Variant = null) -> bool:
	if not valid_room(room): return _fail("invalid_safety_target")
	var ticket := _begin()
	if ticket < 0: return false
	if not _state.pending.is_empty(): return _finish(ticket, _fail("pending_report"))
	var body := {"schema_version": 1, "idempotency_key": Crypto.new().generate_random_bytes(18).hex_encode(), "room_family": room.room_family, "room_id": room.room_id, "reason": reason, "photo": photo.duplicate(true) if photo is Dictionary else photo}
	if not Store.valid_report(body): return _finish(ticket, _fail("invalid_safety_target"))
	var next := _state.duplicate(true)
	next.pending = body
	if not _persist(next): return _finish(ticket, false)
	return await _send_report(ticket, body)

func retry_report() -> bool:
	var ticket := _begin()
	if ticket < 0: return false
	if _state.pending.is_empty(): return _finish(ticket, _fail("no_pending_report"))
	return await _send_report(ticket, _state.pending.duplicate(true))

func _send_report(ticket: int, body: Dictionary) -> bool:
	var response := await _net(ticket, HTTPClient.METHOD_POST, "/v1/safety/report", body)
	if not _same(ticket): return false
	if not response.get("ok", false): return _finish(ticket, false)
	return _finish(ticket, _accept_receipt(response.get("data"), body))

func check_report() -> bool:
	var ticket := _begin()
	if ticket < 0: return false
	if _state.pending.is_empty(): return _finish(ticket, _fail("no_pending_report"))
	var body: Dictionary = _state.pending.duplicate(true)
	var response := await _net(ticket, HTTPClient.METHOD_GET, "/v1/safety/reports/" + str(body.idempotency_key))
	if not _same(ticket): return false
	if not response.get("ok", false): return _finish(ticket, false)
	return _finish(ticket, _accept_receipt(response.get("data"), body))

func _accept_receipt(value: Variant, body: Dictionary) -> bool:
	var material := body.duplicate(true)
	material.merge({"operation": "safety_report", "reporter_id": _owner})
	if not Store.valid_receipt(value) or value.request_hash != Canonical.digest(material) or value.report_id != (_owner + ":" + str(body.idempotency_key)).sha256_text() or not Canonical.same(_state.pending, body): return _fail("unsupported_safety_response")
	var next := _state.duplicate(true)
	next.pending = {}
	next.receipt = value.duplicate(true)
	return _persist(next)

func clear_pending_report() -> bool:
	if busy or not _bound(): return false
	var next := _state.duplicate(true)
	next.pending = {}
	return _persist(next) # Explicit local discard; does not retract a sent report.

func _fail(code: String) -> bool:
	last_code = code
	var messages := {"identity_changed": "Your account changed. Reopen these controls from your current room.", "request_busy": "Another request is finishing. Wait a moment, then try again.", "safety_storage_unavailable": "Safety settings could not be saved or read. Keep this app's data and retry.", "pending_report": "Check the report already saved on this phone before sending another.", "no_pending_report": "There is no saved report to check.", "invalid_safety_target": "Open this action from a current shared room or photo.", "player_blocked": "Interaction with this player is blocked. Your saved progress is kept.", "terms_acceptance_required": "Read and accept the community rules before sharing a new photo.", "rate_limited": "Please wait before sending another request.", "report_rate_limited": "The daily report limit has been reached. Please try again later.", "report_inbox_full": "Reports are temporarily unavailable. Keep your saved report and try again later.", "unsupported_safety_response": "This safety response could not be verified. Your existing settings are kept."}
	last_error = str(messages.get(code, "Safety controls could not reach the service. Try again later; nothing has been silently accepted."))
	return false
