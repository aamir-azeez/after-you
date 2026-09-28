extends SceneTree
const Session = preload("res://services/campaign_terminal_session.gd")
const Store = preload("res://services/relay_online_store.gd")
const Cleanup = preload("res://services/deleted_identity_cache_cleanup.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const PEER := "GGGGGGGGGGGGGGGGGGGGGG"
const ANCHOR := "RRRRRRRRRRRRRRRRRRRRRR"
const OTHER := "SSSSSSSSSSSSSSSSSSSSSS"
var checks := 0
var failures := 0
var directory := "user://terminal-journal-test-"+Crypto.new().generate_random_bytes(8).hex_encode()

class Harness:
	extends RefCounted
	var tree: SceneTree
	var identity := {"ready":true,"player_id":"HHHHHHHHHHHHHHHHHHHHHH","epoch":1}
	var guard_value: Variant = true
	var saved: Dictionary = {}
	var calls: Array = []
	var at_request: Array = []
	var writes := 0
	var fail_write := -1
	var response: Dictionary = {}
	var on_request: Callable
	var on_save: Callable
	var on_load: Callable
	func current_identity() -> Dictionary: return identity.duplicate(true)
	func current() -> Variant: return guard_value
	func load_scope(scope: String) -> Dictionary:
		var result := {"ok":true,"found":saved.has(scope),"value":saved.get(scope,{}).duplicate(true)}
		if on_load.is_valid(): on_load.call()
		return result
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		writes += 1
		if fail_write == writes: return {"ok":false}
		saved[scope] = value.duplicate(true)
		if on_save.is_valid(): on_save.call(value.duplicate(true))
		return {"ok":true}
	func transport(request: Dictionary) -> Dictionary:
		calls.append(request.duplicate(true))
		at_request.append(saved.get("relay-campaign-terminal-v1:"+str(request.owner_player_id),{}).duplicate(true))
		if on_request.is_valid(): on_request.call(request)
		await tree.process_frame
		if not response.is_empty(): return response.duplicate(true)
		return {"ok":true,"status":200,"data":{"schema_version":1,"operation":"campaign_terminal_cleanup","status":"released",
			"player_id":request.owner_player_id,"campaign_room_id":str(request.path).get_slice("/",3)}}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_parsing()
	await _lost_reply_and_repeated_cleanup()
	await _write_failures()
	await _identity_and_lifetime()
	await _reply_validation()
	await _strict_ledger_and_capacity()
	await _real_store()
	print("CAMPAIGN TERMINAL SESSION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(label)

func _harness() -> Harness:
	var value := Harness.new()
	value.tree = self
	return value

func _session(h: Harness, storage: RefCounted = null) -> RefCounted:
	return Session.new(h.transport,h.current_identity,h.current,h if storage == null else storage,h)

func _scope(owner: String = OWNER) -> String: return "relay-campaign-terminal-v1:"+owner
func _receipt(anchor: String = ANCHOR, owner: String = OWNER) -> Dictionary:
	return {"schema_version":1,"operation":"campaign_terminal_cleanup","status":"released","player_id":owner,"campaign_room_id":anchor}

func _empty(owner: String = OWNER) -> Dictionary:
	return {"schema_version":1,"owner_player_id":owner,"pending":{},"released":[]}

func _hint(anchor: String = ANCHOR) -> Dictionary:
	return {"ok":false,"status":409,"code":Session.HINT_CODE,"data":{"error":{"code":Session.HINT_CODE,"campaign_room_id":anchor}}}

func _parsing() -> void:
	_check(Session.parse_hint(_hint()) == ANCHOR,"Only the exact typed list response exposes a cleanup target")
	var value := _hint()
	value.data.error["retryable"] = false
	_check(Session.parse_hint(value) == ANCHOR,"The known generic error retryable field may be false")
	for mode: String in ["status","ok","top-code","nested-code","anchor","extra-error","extra-data","retryable","oversize"]:
		value = _hint()
		match mode:
			"status": value.status = 404
			"ok": value.ok = true
			"top-code": value.code = "campaign_deleted"
			"nested-code": value.data.error.code = "not_found"
			"anchor": value.data.error.campaign_room_id = "../private"
			"extra-error": value.data.error.deleted = true
			"extra-data": value.data.receipt = _receipt()
			"retryable": value.data.error.retryable = true
			"oversize": value.extra = "x".repeat(4096)
		_check(Session.parse_hint(value).is_empty(),"Malformed or generic hint holds: "+mode)
	_check(Session.receipt_valid(_receipt(),OWNER,ANCHOR),"Receipt is exactly owner and anchor bound")
	for owner: String in [PEER,""]:
		_check(not Session.receipt_valid(_receipt(),owner,ANCHOR),"A receipt cannot authorize another owner")
	var h := _harness()
	var session := _session(h)
	_check(session.restore_owner(),"An empty ledger restores locally")
	Session.parse_hint(_hint())
	_check(h.calls.is_empty() and h.writes == 0 and session.pending().is_empty(),"Loading and hint parsing perform no writes or POST")
	_check(not session.begin("invalid") and h.writes == 0,"Invalid anchors cannot create a file")

func _lost_reply_and_repeated_cleanup() -> void:
	var h := _harness()
	var untouched := {"ordinary":{"pending":{"photo":"original"}},"campaign":{"pending":{"continue":"original"}},"keepsakes":{"kept":true}}
	h.saved = untouched.duplicate(true)
	var session := _session(h)
	_check(session.begin(ANCHOR) and h.calls.is_empty(),"Explicit begin durably stages without sending")
	var intent: Dictionary = session.pending()
	_check(intent == {"campaign_room_id":ANCHOR,"path":Session.path_for(ANCHOR),"body":{"schema_version":1}},"The saved cleanup request contains only its exact path/body/anchor")
	intent.body.schema_version = 9
	_check(session.pending().body.schema_version == 1,"Callers cannot mutate the retained request")
	h.response = {"ok":false,"status":0,"code":"connection_interrupted"}
	_check(not await session.reconcile() and not session.pending().is_empty(),"A lost reply retains the exact durable intent")
	_check(h.at_request[0].pending == session.pending(),"Transport only sees an already durable request")
	var cold := _session(h)
	_check(cold.restore_owner() and cold.pending() == session.pending(),"Restart reloads the same body without a new key")
	h.response = {}
	_check(await cold.reconcile() and cold.pending().is_empty() and cold.cleanup_settled(ANCHOR),"Exact retry saves the typed receipt before exposing settlement")
	_check(h.calls.size() == 2 and h.calls[0] == h.calls[1],"Lost-reply retry sends the identical owner/path/body")
	_check(cold.terminal_receipt(ANCHOR) == _receipt(),"The released receipt is durable owner/anchor evidence")
	var third := _session(h)
	_check(third.restore_owner() and third.cleanup_settled(ANCHOR) and h.calls.size() == 2,"Cold receipt restoration does not automatically POST")
	_check(third.begin(ANCHOR) and not third.cleanup_settled(ANCHOR),"Later typed discovery can stage another same-anchor cleanup")
	_check(third.terminal_receipt(ANCHOR) == _receipt(),"A repeated link cleanup never revokes permanent terminal proof")
	var writes := h.writes
	_check(third.begin(ANCHOR) and h.writes == writes,"Repeated begin on the same pending anchor is idempotent")
	_check(not third.begin(OTHER) and third.pending().campaign_room_id == ANCHOR,"Another anchor cannot replace a pending request")
	_check(await third.reconcile() and third.released_receipts().size() == 1,"A repeat emits a fresh POST and deduplicates only the retained receipt")
	_check(h.calls.size() == 3,"A saved prior receipt never permanently suppresses explicit POST")
	for scope: String in untouched:
		_check(Canonical.same(h.saved[scope],untouched[scope]),"Cleanup journal never changes unrelated drafts, proofs or keepsakes")

func _write_failures() -> void:
	var h := _harness()
	var session := _session(h)
	h.fail_write = 1
	_check(not session.begin(ANCHOR) and h.calls.is_empty() and h.saved.is_empty(),"Failed intent write sends nothing")
	h.fail_write = -1
	_check(session.begin(ANCHOR),"The exact explicit request can be staged after storage recovers")
	var saved := h.saved.duplicate(true)
	h.fail_write = h.writes+1
	_check(not await session.reconcile() and session.terminal_receipt(ANCHOR).is_empty(),"A received but unsaved receipt cannot settle locally")
	_check(Canonical.same(saved,h.saved) and not session.pending().is_empty(),"Failed receipt write preserves durable pending bytes")
	var cold := _session(h)
	h.fail_write = -1
	_check(cold.restore_owner() and await cold.reconcile(),"Restart retries the monotone POST after a receipt-write failure")
	_check(h.calls.size() == 2 and cold.cleanup_settled(ANCHOR),"Durable receipt repair needs no new request identity")
	_check(cold.begin(ANCHOR),"Existing terminal proof may have a new explicit pending cleanup")
	h.fail_write = h.writes+1
	_check(not await cold.reconcile() and cold.terminal_receipt(ANCHOR) == _receipt() and not cold.cleanup_settled(ANCHOR),"Failed repeat receipt preserves old proof plus fresh pending intent")

func _identity_and_lifetime() -> void:
	for mode: String in ["owner","epoch","guard","retire"]:
		var h := _harness()
		var session := _session(h)
		_check(session.begin(ANCHOR),"Race request is durable before dispatch")
		var saved := h.saved.duplicate(true)
		h.on_request = func(_request: Dictionary) -> void:
			match mode:
				"owner": h.identity.player_id = PEER
				"epoch": h.identity.epoch = 2
				"guard": h.guard_value = false
				"retire": session.retire()
		_check(not await session.reconcile(),"A changed captured context refuses late receipt: "+mode)
		_check(Canonical.same(saved,h.saved) and session.terminal_receipt(ANCHOR).is_empty(),"Late callback cannot expose/write receipt after "+mode)
		h.on_request = Callable()
	for mode: String in ["owner","guard","retire"]:
		var h := _harness()
		var session := _session(h)
		h.on_save = func(_value: Dictionary) -> void:
			match mode:
				"owner": h.identity.player_id = PEER
				"guard": h.guard_value = false
				"retire": session.retire()
		_check(not session.begin(ANCHOR),"Synchronous save-hook context flip refuses in-memory commit: "+mode)
		_check(h.saved.has(_scope()) and not h.saved.has(_scope(PEER)) and session.pending().is_empty(),"A completed old-owner write never migrates into the new identity")
		h.on_save = Callable()
	var receipt_h := _harness()
	var receipt_session := _session(receipt_h)
	_check(receipt_session.begin(ANCHOR),"Receipt-save race starts with an exact pending request")
	receipt_h.on_save = func(_value: Dictionary) -> void: receipt_h.identity.player_id = PEER
	_check(not await receipt_session.reconcile() and receipt_session.terminal_receipt(ANCHOR).is_empty(),"Owner flip after durable receipt save does not expose old-owner settlement")
	_check(receipt_h.saved[_scope()].released == [_receipt()] and not receipt_h.saved.has(_scope(PEER)),"Receipt already written remains in the captured owner's file only")
	receipt_h.on_save = Callable()
	_check(receipt_session.restore_owner() and receipt_session.terminal_receipt(ANCHOR).is_empty(),"New owner restores independently after the late save")
	receipt_h.identity.player_id = OWNER
	var receipt_cold := _session(receipt_h)
	_check(receipt_cold.restore_owner() and receipt_cold.cleanup_settled(ANCHOR),"Original owner can recover its completed durable receipt later")
	var load_h := _harness()
	var load_session := _session(load_h)
	load_h.saved[_scope()] = _empty()
	load_h.saved[_scope()].released = [_receipt()]
	load_h.on_load = func() -> void:
		load_h.on_load = Callable()
		load_h.identity.player_id = PEER
		load_session.invalidate_identity()
		_check(load_session.restore_owner() and load_session.begin(OTHER),"Newer owner may load while an older storage callback unwinds")
	_check(not load_session.restore_owner(),"Superseded local load result is refused")
	_check(load_session.pending().campaign_room_id == OTHER and load_session.terminal_receipt(ANCHOR).is_empty(),"Old storage callback cannot discard or contaminate the newer owner")
	var h := _harness()
	var session := _session(h)
	_check(session.begin(ANCHOR),"Old owner has a durable request")
	h.on_request = func(_request: Dictionary) -> void:
		h.on_request = Callable()
		h.identity.player_id = PEER
		session.invalidate_identity()
		_check(session.restore_owner() and session.begin(OTHER),"New owner can restore while retired callback drains")
	_check(not await session.reconcile(),"Old response is rejected after a newer owner generation")
	_check(session.pending().campaign_room_id == OTHER and h.saved[_scope(PEER)].pending.campaign_room_id == OTHER,"Old response does not discard the newer owner journal")
	var invalid := _session(h)
	h.guard_value = 1
	_check(not invalid.restore_owner(),"Transport guard requires bool true, not truthiness")
	h.guard_value = true
	var missing := Session.new(h.transport,h.current_identity,Callable(),h,h)
	_check(not missing.restore_owner(),"Missing original-API guard fails closed")
	invalid = null
	missing = null
	session = null
	h = null
	var released: WeakRef = await _lifetime_probe()
	await process_frame
	_check(released.get_ref() == null,"Retained transport releases after the caller's capture scope exits")

func _lifetime_probe() -> WeakRef:
	# Keep this local lambda capture out of the scope which verifies destruction.
	var lifetime_h := _harness()
	var independent_store := _harness()
	var hold: WeakRef = weakref(lifetime_h)
	var retained := Session.new(lifetime_h.transport,lifetime_h.current_identity,lifetime_h.current,independent_store)
	lifetime_h.on_request = func(_request: Dictionary) -> void:
		var target: Harness = hold.get_ref()
		target.on_request = Callable()
		retained.retire()
	lifetime_h = null
	_check(hold.get_ref() != null and retained.begin(ANCHOR),"A separate Store cannot mask automatic retention of the transport target")
	_check(not await retained.reconcile() and not independent_store.saved[_scope()].pending.is_empty(),"Retirement inside an actual awaited request preserves its durable intent")
	_check(independent_store.saved[_scope()].released.is_empty(),"Draining retired transport cannot publish a receipt")
	retained = null
	return hold

func _reply_validation() -> void:
	for mode: String in ["generic404","hint","status202","owner","anchor","extra","boolean","oversize"]:
		var h := _harness()
		var session := _session(h)
		_check(session.begin(ANCHOR),"Invalid-reply case stages its exact request")
		var reply := {"ok":true,"status":200,"data":_receipt()}
		match mode:
			"generic404": reply = {"ok":false,"status":404,"code":"not_found"}
			"hint": reply = _hint()
			"status202": reply.status = 202
			"owner": reply.data.player_id = PEER
			"anchor": reply.data.campaign_room_id = OTHER
			"extra": reply.data.deleted = true
			"boolean": reply.data = {"deleted":true}
			"oversize": reply.extra = "x".repeat(4096)
		h.response = reply
		var before := h.saved.duplicate(true)
		_check(not await session.reconcile() and not session.pending().is_empty(),"Only a strict released receipt clears pending: "+mode)
		_check(Canonical.same(before,h.saved) and not session.cleanup_settled(ANCHOR),"Invalid result leaves journal unchanged: "+mode)

func _strict_ledger_and_capacity() -> void:
	for mode: String in ["future","foreign","extra","duplicate","pending-path","pending-body","over-capacity","oversize"]:
		var h := _harness()
		var value := _empty()
		match mode:
			"future": value.schema_version = 2
			"foreign": value.owner_player_id = PEER
			"extra": value.adopted = true
			"duplicate": value.released = [_receipt(),_receipt()]
			"pending-path": value.pending = {"campaign_room_id":ANCHOR,"path":"/v2/campaigns/"+ANCHOR+"/continue","body":{"schema_version":1}}
			"pending-body": value.pending = {"campaign_room_id":ANCHOR,"path":Session.path_for(ANCHOR),"body":{"schema_version":1,"deleted":true}}
			"over-capacity":
				for n in range(129): value.released.append(_receipt(str(n).pad_zeros(22)))
			"oversize": value.pending = {"unknown":"x".repeat(Session.MAX_BYTES)}
		h.saved[_scope()] = value.duplicate(true)
		var session := _session(h)
		_check(not session.restore_owner() and session.read_only,"Unknown/corrupt ledger holds: "+mode)
		_check(not session.begin(ANCHOR) and not await session.reconcile() and h.writes == 0 and h.calls.is_empty(),"Held ledger cannot be overwritten or transmitted")
		_check(h.saved[_scope()] == value,"Unsupported source data remains unchanged")
	var h := _harness()
	var full := _empty()
	for n in range(128): full.released.append(_receipt(str(n).pad_zeros(22)))
	h.saved[_scope()] = full
	var session := _session(h)
	_check(session.restore_owner(),"Maximum bounded receipt history restores")
	_check(not session.begin(ANCHOR) and h.writes == 0,"The129th distinct anchor holds without eviction")
	var retained_anchor := str(127).pad_zeros(22)
	_check(session.begin(retained_anchor) and session.terminal_receipt(retained_anchor) == _receipt(retained_anchor),"A same-anchor repeat is allowed at capacity and preserves terminal proof")
	_check(await session.reconcile() and session.released_receipts().size() == 128,"Full-history repeat settles without growing or pruning the ledger")
	var copy: Array = session.released_receipts()
	copy.clear()
	_check(session.released_receipts().size() == 128,"Callers cannot mutate retained receipt history")

func _write(path: String, value: Variant) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value if value is String else JSON.stringify(value))
	file.close()

func _real_store() -> void:
	var h := _harness()
	var location := directory.path_join("roundtrip")
	var session := _session(h,Store.new(location))
	_check(session.begin(ANCHOR),"Default Store accepts only the new exact owner scope")
	var cold := _session(h,Store.new(location))
	_check(cold.restore_owner() and Canonical.same(cold.pending(),session.pending()),"Default Store cold reload preserves the exact pending request")
	_check(await cold.reconcile(),"Default Store saves a typed receipt through LocalSave generations")
	var final := _session(h,Store.new(location))
	_check(final.restore_owner() and Canonical.same(final.terminal_receipt(ANCHOR),_receipt()),"Receipt survives a real file-backed restart")
	var path := location.path_join(_scope().sha256_text()+".json")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	envelope.version = 9
	_write(path,envelope)
	var before := FileAccess.get_file_as_bytes(path)
	var future := _session(h,Store.new(location))
	_check(not future.restore_owner() and future.read_only and not future.begin(OTHER),"A readable future LocalSave envelope holds over a prior valid backup")
	_check(FileAccess.get_file_as_bytes(path) == before,"Unsupported file bytes remain unchanged")
	for invalid: String in ["relay-campaign-terminal-v2:"+OWNER,"relay-campaign-terminal-v1:"+OWNER+":"+ANCHOR,"relay-campaign-terminal-v1:../private"]:
		_check(not Store.new(location).load_scope(invalid).ok,"Unknown terminal scopes cannot reach a file")
	var cleanup := Cleanup.new()
	cleanup.relay_directory = directory.path_join("cleanup/relay")
	cleanup.shared_directory = directory.path_join("cleanup/shared")
	cleanup.safety_directory = directory.path_join("cleanup/safety")
	var storage := Store.new(cleanup.relay_directory)
	var owned: Array[String] = []
	var peers := {}
	for owner: String in [OWNER,PEER]:
		for scope: String in [_scope(owner),"relay-lobby-v2:"+owner,"relay-campaign-v1:"+owner+":"+ANCHOR]:
			_check(storage.save_scope(scope,{"first":true}).ok and storage.save_scope(scope,{"second":true}).ok,"Existing and terminal owner scopes keep their recoverable generations")
			for suffix: String in ["",".backup"]:
				var file := cleanup.relay_directory.path_join(scope.sha256_text()+".json"+suffix)
				if owner == OWNER: owned.append(file)
				else: peers[file] = FileAccess.get_file_as_bytes(file)
	# The exact owner-only hash is sufficient even when every generation of
	# this new ledger is truncated; foreign scopes still require preservation.
	_write(owned[0],"{interrupted")
	_write(owned[1],"{interrupted")
	_check(cleanup.erase_owner(OWNER).ok,"Confirmed account cleanup recognizes a fully truncated terminal ledger")
	for file: String in owned: _check(not FileAccess.file_exists(file),"Confirmed cleanup removes only this owner's known generations")
	for file: String in peers: _check(FileAccess.get_file_as_bytes(file) == peers[file],"Another owner's prior and new scopes remain byte-identical")
