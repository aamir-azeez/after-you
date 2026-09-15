extends RefCounted
## Optional metadata only. A saved uncertain request is checked by GET; only an
## explicit selection or explicit retry may POST. No gameplay journal writes.
const Canonical = preload("res://core/v2/canonical.gd")
const Labels = preload("res://presentation/room_reactions.gd")
const TARGET_KEYS := ["room_id", "pair_id", "a_hash", "b_hash", "host_id", "guest_id"]
const STATE_KEYS := ["schema_version", "room_id", "pair_id", "a_hash", "b_hash", "reactions"]
const ROW_KEYS := ["schema_version", "pair_id", "player_id", "a_hash", "b_hash", "reaction_revision", "reaction"]
const RECEIPT_KEYS := ["schema_version", "pair_id", "player_id", "a_hash", "b_hash", "reaction_revision", "reaction", "room_id", "idempotency_key", "request_hash"]
const BODY_KEYS := ["idempotency_key", "a_hash", "b_hash", "expected_reaction_revision", "reaction"]
var last_error := ""
var last_code := ""
var retry_after_ms := 0
var terminal := false
var read_only := false
var retry_allowed := false
var _busy := false
var _verified_read := false
var _cooldown_until := 0
var _generation := 0
var _owner := ""
var _epoch := -1
var _scope := ""
var _data: Dictionary = {}
var _transport: Callable
var _load: Callable
var _save: Callable
var _identity: Callable
var _enabled: Callable

func _init(transport: Callable, load_scope: Callable, save_scope: Callable, identity: Callable, enabled: Callable) -> void:
	_transport = transport
	_load = load_scope
	_save = save_scope
	_identity = identity
	_enabled = enabled

func invalidate_identity() -> void:
	_generation += 1
	_owner = ""
	_epoch = -1
	_scope = ""
	_data = {}
	_busy = false
	_verified_read = false
	retry_allowed = false

func bind(reference: Dictionary) -> bool:
	invalidate_identity()
	read_only = false
	last_error = ""
	var identity: Dictionary = _identity.call()
	if not valid_target(reference) or not identity.get("ready", false) or identity.get("player_id") not in [reference.host_id, reference.guest_id]:
		return _error("invalid_target", "This completed stage could not be verified for reactions.")
	_owner = identity.player_id
	_epoch = int(identity.epoch)
	_scope = "pair-reaction-v1:" + _owner + ":" + reference.room_id + ":" + reference.pair_id
	var loaded: Dictionary = _load.call(_scope)
	if not loaded.get("ok", false):
		read_only = true
		return _error("storage_unavailable", "This device could not read its saved reaction. Your gameplay is safe.")
	var value: Variant = loaded.get("value") if loaded.get("found", false) else {"schema_version": 1, "owner": _owner, "target": reference.duplicate(true), "state": {}, "pending": {}, "last_receipt": {}}
	if not _valid_journal(value) or not Canonical.same(value.target, reference):
		read_only = true
		return _error("unsupported_save", "This saved reaction needs a compatible app. It has been kept unchanged.")
	_data = value.duplicate(true)
	return true

func busy() -> bool:
	return _busy

func state() -> Dictionary:
	return _data.get("state", {}).duplicate(true) if _current() else {}

func target() -> Dictionary:
	return _data.get("target", {}).duplicate(true) if _current() else {}

func pending() -> Dictionary:
	return _data.get("pending", {}).duplicate(true) if _current() else {}

func last_receipt() -> Dictionary:
	return _data.get("last_receipt", {}).duplicate(true) if _current() else {}

func can_choose() -> bool:
	return _available() and not terminal and _verified_read and not state().is_empty() and pending().is_empty() and _enabled.call() == true

func refresh() -> bool:
	if not _available(): return false
	var response := await _call(HTTPClient.METHOD_GET, _pair_path())
	if not response.get("ok", false): return _response_error(response)
	var value: Variant = response.get("data")
	if not valid_state(value, _data.target) or not _not_older(value):
		return _error("invalid_response", "The reaction update could not be verified. Your gameplay is unchanged.")
	_verified_read = true
	var next := _data.duplicate(true)
	next.state = value.duplicate(true)
	return _persist(next)

func choose(reaction: String) -> bool:
	if not can_choose() or not Labels.PRESETS.has(reaction): return false
	var revision := 0
	for row: Dictionary in _data.state.reactions:
		if row.player_id == _owner: revision = int(row.reaction_revision)
	var body := {"idempotency_key": Crypto.new().generate_random_bytes(18).hex_encode(), "a_hash": _data.target.a_hash, "b_hash": _data.target.b_hash, "expected_reaction_revision": revision, "reaction": reaction}
	var next := _data.duplicate(true)
	next.pending = {"body": body, "request_hash": request_hash(_data.target.pair_id, body), "rejected": ""}
	if not _persist(next): return false
	return await _post_pending()

func check_pending() -> bool:
	# Reconciliation may establish safe retry eligibility, but never sends a POST.
	if not _available() or pending().is_empty(): return false
	retry_allowed = false
	var key: String = _data.pending.body.idempotency_key
	var response := await _call(HTTPClient.METHOD_GET, "/v2/rooms/" + _data.target.room_id + "/reaction-operations/" + key)
	if not response.get("ok", false):
		if response.get("status") == 404 and response.get("code") == "operation_not_found" and _current():
			retry_allowed = true
			return _error("operation_not_found", "The service has not confirmed this reaction. Retry sends the same saved request.")
		return _response_error(response)
	return _accept(response.get("data"))

func retry_pending() -> bool:
	if not _available() or pending().is_empty() or not retry_allowed or _enabled.call() != true:
		return false
	return await _post_pending()

func keep_current_reaction() -> bool:
	# Only an explicit, definitive rejection can be dismissed. Unknown outcomes
	# remain recoverable by their original key across navigation and restart.
	if not _available() or pending().is_empty() or _data.pending.rejected.is_empty(): return false
	var next := _data.duplicate(true)
	next.pending = {}
	retry_allowed = false
	_verified_read = false
	return _persist(next)

func _post_pending() -> bool:
	retry_allowed = false
	var response := await _call(HTTPClient.METHOD_POST, _pair_path(), _data.pending.body)
	if not response.get("ok", false):
		# These responses prove this exact request was rejected. Preserve the key
		# until the user explicitly keeps the current value; never auto-replace it.
		if _current() and response.get("status") == 409 and response.get("code") in ["stale_reaction_revision", "reaction_pair_mismatch", "reaction_history_full", "reaction_room_full"]:
			_verified_read = false
			var next := _data.duplicate(true)
			next.pending.rejected = str(response.code)
			if not _persist(next): return false
		return _response_error(response)
	return _accept(response.get("data"))

func _accept(value: Variant) -> bool:
	if not _current() or not exact(value, ["receipt", "state"]) or not _receipt_valid(value.receipt, _data.target) or not valid_state(value.state, _data.target) or not _not_older(value.state):
		return _error("invalid_response", "The service response could not be verified. Check the saved reaction before sending another.")
	var request: Dictionary = _data.pending
	var receipt: Dictionary = value.receipt
	if receipt.idempotency_key != request.body.idempotency_key or receipt.request_hash != request.request_hash or receipt.reaction != request.body.reaction or int(receipt.reaction_revision) != int(request.body.expected_reaction_revision) + 1:
		return _error("receipt_mismatch", "The receipt did not match the saved reaction. Its original request is kept.")
	var confirmed := false
	for row: Dictionary in value.state.reactions:
		if row.player_id == _owner and int(row.reaction_revision) >= int(receipt.reaction_revision):
			confirmed = int(row.reaction_revision) > int(receipt.reaction_revision) or row.reaction == receipt.reaction
	if not confirmed:
		return _error("receipt_mismatch", "The reaction receipt and latest state disagree. Check again later.")
	_verified_read = true
	var next := _data.duplicate(true)
	next.state = value.state.duplicate(true)
	next.last_receipt = receipt.duplicate(true)
	next.pending = {}
	return _persist(next)

func _call(method: int, path: String, body: Dictionary = {}) -> Dictionary:
	var generation := _generation
	_busy = true
	var response: Dictionary = await _transport.call({"method": method, "path": path, "body": body.duplicate(true), "owner_player_id": _owner, "identity_epoch": _epoch})
	if generation == _generation: _busy = false
	if generation != _generation or not _current():
		return {"ok": false, "code": "identity_changed", "status": 0}
	return response

func _persist(next: Dictionary) -> bool:
	if not _current() or read_only or not _valid_journal(next): return false
	# Unchanged reads do not create a new generation every refresh interval.
	if not Canonical.same(next, _data) and not _save.call(_scope, next.duplicate(true)).get("ok", false):
		return _error("storage_unavailable", "Could not save this reaction on the device. Its previous request is kept; check again before sending another.")
	_data = next.duplicate(true)
	last_error = ""
	last_code = ""
	retry_after_ms = 0
	terminal = false
	return true

func _current() -> bool:
	var identity: Dictionary = _identity.call()
	return not _owner.is_empty() and identity.get("ready", false) and identity.get("player_id") == _owner and identity.get("epoch") == _epoch

func _available() -> bool:
	return _current() and not read_only and not _busy and not _data.is_empty() and Time.get_ticks_msec() >= _cooldown_until

func _pair_path() -> String:
	return "/v2/rooms/" + _data.target.room_id + "/reactions/" + _data.target.pair_id

func _response_error(response: Dictionary) -> bool:
	retry_after_ms = clampi(int(response.get("retry_after_ms", 0)), 0, 120000)
	_cooldown_until = maxi(_cooldown_until, Time.get_ticks_msec() + retry_after_ms)
	terminal = int(response.get("status", 0)) in [401, 403, 404] and response.get("code") != "operation_not_found"
	if terminal: _verified_read = false
	return _error(str(response.get("code", "connection_interrupted")), "Reactions are unavailable right now. Your saved stage is unchanged." if pending().is_empty() else "The reaction is not confirmed yet. Check its saved receipt before sending another.")

func _error(code: String, message: String) -> bool:
	last_code = code
	last_error = message
	return false

func _not_older(value: Dictionary) -> bool:
	for previous: Dictionary in _data.get("state", {}).get("reactions", []):
		var found := false
		for row: Dictionary in value.reactions:
			if row.player_id == previous.player_id:
				found = int(row.reaction_revision) > int(previous.reaction_revision) or Canonical.same(row, previous)
		if not found: return false
	return true

func _valid_journal(value: Variant) -> bool:
	if not exact(value, ["schema_version", "owner", "target", "state", "pending", "last_receipt"]) or value.schema_version != 1 or value.owner != _owner or not valid_target(value.target) or _owner not in [value.target.host_id, value.target.guest_id] or not value.state is Dictionary or not value.pending is Dictionary or not value.last_receipt is Dictionary:
		return false
	if not value.state.is_empty() and not valid_state(value.state, value.target): return false
	if not value.last_receipt.is_empty() and not _receipt_valid(value.last_receipt, value.target): return false
	var request: Dictionary = value.pending
	if request.is_empty(): return true
	if not exact(request, ["body", "request_hash", "rejected"]) or not exact(request.body, BODY_KEYS) or request.rejected not in ["", "stale_reaction_revision", "reaction_pair_mismatch", "reaction_history_full", "reaction_room_full"]: return false
	var body: Dictionary = request.body
	return matches(body.idempotency_key, "^[A-Za-z0-9_-]{16,80}$") and body.a_hash == value.target.a_hash and body.b_hash == value.target.b_hash and integer(body.expected_reaction_revision, 0, 256) and Labels.PRESETS.has(body.reaction) and request.request_hash == request_hash(value.target.pair_id, body)

func _receipt_valid(value: Variant, reference: Dictionary) -> bool:
	if not exact(value, RECEIPT_KEYS) or value.room_id != reference.room_id or value.player_id != _owner or not matches(value.idempotency_key, "^[A-Za-z0-9_-]{16,80}$") or not matches(value.request_hash, "^[a-f0-9]{64}$"): return false
	var row: Dictionary = value.duplicate(true)
	for key: String in ["room_id", "idempotency_key", "request_hash"]: row.erase(key)
	if not valid_row(row, reference): return false
	var body := {"idempotency_key": value.idempotency_key, "a_hash": value.a_hash, "b_hash": value.b_hash, "expected_reaction_revision": int(value.reaction_revision) - 1, "reaction": value.reaction}
	return value.request_hash == request_hash(reference.pair_id, body)

static func request_hash(pair_id: String, body: Dictionary) -> String:
	var value := body.duplicate(true)
	value.merge({"operation": "pair_reaction", "pair_id": pair_id})
	return Canonical.digest(value)

static func valid_target(value: Variant) -> bool:
	return exact(value, TARGET_KEYS) and matches(value.room_id, "^[A-Za-z0-9_-]{22}$") and matches(value.pair_id, "^p(?:[0-9]|[12][0-9]|3[01])-[01]$") and matches(value.host_id, "^[A-Za-z0-9_-]{22}$") and matches(value.guest_id, "^[A-Za-z0-9_-]{22}$") and value.host_id != value.guest_id and matches(value.a_hash, "^[a-f0-9]{64}$") and matches(value.b_hash, "^[a-f0-9]{64}$")

static func valid_state(value: Variant, reference: Dictionary) -> bool:
	if not exact(value, STATE_KEYS) or value.schema_version != 1 or not value.reactions is Array or value.reactions.size() > 2: return false
	for key: String in ["room_id", "pair_id", "a_hash", "b_hash"]:
		if value[key] != reference[key]: return false
	var order := -1
	for row: Variant in value.reactions:
		if not valid_row(row, reference): return false
		var index := 0 if row.player_id == reference.host_id else 1
		if index <= order: return false
		order = index
	return true

static func valid_row(value: Variant, reference: Dictionary) -> bool:
	if not exact(value, ROW_KEYS) or value.schema_version != 1 or value.player_id not in [reference.host_id, reference.guest_id] or not integer(value.reaction_revision, 1, 256) or not Labels.PRESETS.has(value.reaction): return false
	for key: String in ["pair_id", "a_hash", "b_hash"]:
		if value[key] != reference[key]: return false
	return true

static func exact(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size(): return false
	for key: String in keys:
		if not value.has(key): return false
	return true

static func matches(value: Variant, pattern: String) -> bool:
	if not value is String: return false
	var regex := RegEx.new()
	regex.compile(pattern)
	var found := regex.search(value)
	return found != null and found.get_string() == value

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and value == int(value)
