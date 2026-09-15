extends SceneTree
const Controller = preload("res://services/pair_reaction_controller.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

class Harness:
	extends RefCounted
	signal release
	var owner := HOST
	var epoch := 1
	var enabled := true
	var values: Dictionary = {}
	var writes := 0
	var calls: Array = []
	var server_state: Dictionary = {}
	var receipts: Dictionary = {}
	var fail_save := false
	var fail_after_post := false
	var drop := false
	var drop_before := false
	var hold := false
	var pending_before_post := true
	var response_override: Dictionary = {}
	func identity() -> Dictionary:
		return {"ready": true, "player_id": owner, "epoch": epoch}
	func allowed() -> bool: return enabled
	func load_scope(scope: String) -> Dictionary:
		return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		if fail_save: return {"ok": false}
		writes += 1
		values[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok": true}
	func target_fixture(pair_id: String = "p0-0") -> Dictionary:
		return {"room_id": ROOM, "pair_id": pair_id, "host_id": HOST, "guest_id": GUEST, "a_hash": "a".repeat(64), "b_hash": "b".repeat(64)}
	func create(pair_id: String = "p0-0") -> RefCounted:
		var controller := Controller.new(request, load_scope, save_scope, identity, allowed)
		controller.bind(target_fixture(pair_id))
		if server_state.is_empty():
			server_state = {"schema_version": 1, "room_id": ROOM, "pair_id": pair_id, "a_hash": "a".repeat(64), "b_hash": "b".repeat(64), "reactions": []}
		return controller
	func row(player: String, reaction: String, revision: int) -> Dictionary:
		return {"schema_version": 1, "pair_id": server_state.pair_id, "a_hash": server_state.a_hash, "b_hash": server_state.b_hash, "player_id": player, "reaction": reaction, "reaction_revision": revision}
	func set_row(value: Dictionary) -> void:
		server_state.reactions = server_state.reactions.filter(func(old: Dictionary) -> bool: return old.player_id != value.player_id)
		server_state.reactions.append(value)
		server_state.reactions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.player_id == HOST and b.player_id != HOST)
	func request(input: Dictionary) -> Dictionary:
		calls.append(input.duplicate(true))
		if hold:
			hold = false
			await release
		if not response_override.is_empty(): return response_override.duplicate(true)
		if input.method == HTTPClient.METHOD_GET:
			if "/reaction-operations/" in input.path:
				var key: String = input.path.get_file()
				return {"ok": true, "data": {"receipt": receipts[key], "state": server_state.duplicate(true)}} if receipts.has(key) else {"ok": false, "status": 404, "code": "operation_not_found"}
			return {"ok": true, "data": server_state.duplicate(true)}
		var body: Dictionary = input.body
		var found := false
		for journal: Dictionary in values.values():
			if journal.owner == input.owner_player_id and Canonical.same(journal.pending.get("body"), body): found = true
		pending_before_post = pending_before_post and found
		if drop_before:
			drop_before = false
			return {"ok": false, "status": 0, "code": "connection_interrupted"}
		if not receipts.has(body.idempotency_key):
			var accepted := row(input.owner_player_id, body.reaction, int(body.expected_reaction_revision) + 1)
			set_row(accepted)
			var receipt := accepted.duplicate(true)
			receipt.merge({"room_id": ROOM, "idempotency_key": body.idempotency_key, "request_hash": Controller.request_hash(server_state.pair_id, body)})
			receipts[body.idempotency_key] = receipt
		if fail_after_post: fail_save = true
		if drop:
			drop = false
			return {"ok": false, "status": 0, "code": "connection_interrupted"}
		return {"ok": true, "data": {"receipt": receipts[body.idempotency_key], "state": server_state.duplicate(true)}}

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	await _normal_and_current_state()
	await _uncertain_and_restart()
	await _storage_boundaries()
	await _malformed_and_identity()
	await _disabled_and_rejected()
	print("After You pair reaction controller: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _normal_and_current_state() -> void:
	var h := Harness.new()
	var c := h.create()
	_check(not c.can_choose() and not await c.choose("love"), "selection requires an authenticated first read")
	_check(await c.refresh() and c.can_choose(), "empty metadata is verified absence")
	_check(await c.choose("love") and h.pending_before_post, "request is durable before the only POST")
	_check(c.pending().is_empty() and c.state().reactions[0].reaction == "love", "confirmed own reaction shown")
	var state_writes := h.writes
	_check(await c.refresh() and h.writes == state_writes, "unchanged polling does not rewrite journal")
	h.set_row(h.row(GUEST, "sparkles", 1))
	_check(await c.refresh() and c.state().reactions.size() == 2, "partner metadata refresh is independent of gameplay")
	_check(await c.choose("again") and c.last_receipt().reaction_revision == 2, "partner revision does not advance own revision")
	_check(h.calls[-1].body.expected_reaction_revision == 1, "replacement binds last own revision")
	var before: Dictionary = c.state()
	before.reactions.clear()
	_check(c.state().reactions.size() == 2, "returned state is a defensive copy")
	# An old accepted operation may now return a later own value from another
	# authenticated client. Its immutable receipt must not overwrite that value.
	h.drop = true
	_check(not await c.choose("love") and not c.pending().is_empty(), "lost acknowledgement leaves exact pending request")
	h.set_row(h.row(HOST, "again", 4))
	_check(await c.check_pending(), "receipt reconciles after later own update")
	_check(c.last_receipt().reaction == "love" and c.state().reactions[0].reaction == "again" and c.state().reactions[0].reaction_revision == 4, "latest state is separate from old receipt")
	h.owner = GUEST
	var guest := h.create()
	_check(await guest.refresh() and await guest.choose("again"), "other participant can independently replace preset")
	_check(h.calls[-1].body.expected_reaction_revision == 1 and not c.can_choose(), "new owner uses own revision and invalidates previous identity")

func _uncertain_and_restart() -> void:
	var h := Harness.new()
	var c := h.create("p31-1")
	_check(await c.refresh(), "explicit archived pair reference accepted")
	h.drop_before = true
	_check(not await c.choose("sparkles"), "uncertain before-send failure is retained")
	var body: Dictionary = c.pending().body
	var calls := h.calls.size()
	_check(not await c.choose("again") and h.calls.size() == calls, "new preset cannot replace unknown request")
	var reopened := h.create("p31-1")
	_check(Canonical.same(reopened.pending().body, body) and not reopened.retry_allowed, "cold reopen restores key without assuming absence")
	_check(not await reopened.retry_pending() and h.calls.size() == calls, "retry requires owner receipt lookup first")
	_check(not await reopened.check_pending() and reopened.retry_allowed, "authenticated operation-not-found permits explicit exact retry")
	_check(h.calls[-1].method == HTTPClient.METHOD_GET, "receipt reconciliation never POSTs")
	_check(await reopened.retry_pending() and Canonical.same(h.calls[-1].body, body), "explicit retry uses identical canonical key and body")
	_check(h.calls[-1].path.ends_with("/reactions/p31-1"), "archived branch is not replaced by active branch")

func _storage_boundaries() -> void:
	var h := Harness.new()
	var c := h.create()
	_check(await c.refresh(), "storage fixture loaded")
	h.fail_save = true
	var calls := h.calls.size()
	_check(not await c.choose("love") and h.calls.size() == calls and c.pending().is_empty(), "I/O failure before POST sends nothing")
	h.fail_save = false
	h.fail_after_post = true
	_check(not await c.choose("love") and not c.pending().is_empty(), "accepted response I/O failure preserves request")
	h.fail_save = false
	h.fail_after_post = false
	var reopened := h.create()
	_check(await reopened.check_pending() and reopened.pending().is_empty(), "cold reconcile recovers accepted request after I/O failure")
	var scope: String = h.values.keys()[0]
	h.values[scope].schema_version = 2
	var original := Canonical.digest(h.values)
	var future := h.create()
	_check(future.read_only and not await future.refresh() and Canonical.digest(h.values) == original, "future journal remains read-only and unchanged")
	h.values[scope].schema_version = 1
	h.values[scope].last_receipt.request_hash = "f".repeat(64)
	var tampered := h.create()
	_check(tampered.read_only, "tampered durable receipt is rejected")

func _malformed_and_identity() -> void:
	var h := Harness.new()
	var c := h.create()
	_check(await c.refresh(), "malformed fixture ready")
	var good: Dictionary = h.server_state.duplicate(true)
	var variants: Array = []
	var wrong := good.duplicate(true)
	wrong.extra = true
	variants.append(wrong)
	wrong = good.duplicate(true)
	wrong.a_hash = "c".repeat(64)
	variants.append(wrong)
	wrong = good.duplicate(true)
	wrong.reactions = [h.row("X".repeat(22), "love", 1)]
	variants.append(wrong)
	wrong = good.duplicate(true)
	wrong.reactions = [h.row(HOST, "love", 1), h.row(HOST, "again", 2)]
	variants.append(wrong)
	wrong = good.duplicate(true)
	wrong.reactions = [h.row(HOST, "arbitrary text", 1)]
	variants.append(wrong)
	wrong = good.duplicate(true)
	wrong.reactions = [h.row(HOST, "love", 0)]
	variants.append(wrong)
	var digest_before := Canonical.digest(h.values)
	for value: Dictionary in variants:
		h.response_override = {"ok": true, "data": value}
		_check(not await c.refresh() and Canonical.digest(h.values) == digest_before, "malformed metadata never mutates the journal")
	h.response_override = {}
	h.hold = true
	var finished := [false]
	# Hold actual async request across identity replacement, then release it.
	_deferred_refresh(c, finished)
	_check(c.busy(), "in-flight request is observable")
	h.epoch += 1
	h.release.emit()
	await process_frame
	_check(finished[0] and Canonical.digest(h.values) == digest_before, "stale identity result is ignored without persistence")
	_check(not c.can_choose(), "old credential epoch cannot submit")

func _deferred_refresh(controller: RefCounted, finished: Array) -> void:
	await controller.refresh()
	finished[0] = true

func _disabled_and_rejected() -> void:
	var h := Harness.new()
	var c := h.create()
	h.enabled = false
	_check(await c.refresh() and not c.can_choose(), "capability off allows reads but no new preset")
	h.enabled = true
	h.response_override = {"ok": false, "status": 409, "code": "stale_reaction_revision"}
	_check(not await c.choose("love") and c.pending().rejected == "stale_reaction_revision", "definitive stale rejection remains explicitly recoverable")
	_check(c.keep_current_reaction() and c.pending().is_empty(), "only explicit action dismisses a definitive rejection")
	_check(not c.can_choose(), "known stale state cannot immediately submit another preset")
	h.response_override = {}
	_check(await c.refresh() and c.can_choose(), "fresh authenticated state restores selection after rejection")
	h.drop = true
	_check(not await c.choose("again") and not c.keep_current_reaction(), "uncertain result cannot be dismissed as rejected")
	h.enabled = false
	_check(await c.check_pending(), "disabled capability still permits checking already accepted receipt")
	h.enabled = true
	for status: int in [401, 403, 404]:
		h.response_override = {"ok": false, "status": status, "code": "room_not_found"}
		_check(not await c.refresh() and not c.can_choose() and not c.state().is_empty(), "terminal room failure disables presets while preserving existing state")
		h.response_override = {}
		_check(await c.refresh() and c.can_choose(), "successful explicit read can recover terminal eligibility")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
