extends "res://tests/test_campaign_terminal_session.gd"
const Mapping = preload("res://services/campaign_terminal_admission.gd")
const Lobby = preload("res://services/campaign_lobby_protocol.gd")
const Wire = preload("res://services/campaign_protocol.gd")

class MappingHarness extends Harness:
	var pending: Dictionary = {}
	var accepted: Dictionary = {}
	var cancellation := false
	func current_pending() -> Dictionary:
		if pending.is_empty(): return {}
		var value := pending.duplicate(true)
		value["accepted_campaign"] = accepted.duplicate(true)
		value["cancel_requested"] = cancellation
		return value

func _run() -> void:
	_mapping_validation()
	_local_witnesses()
	_preservation_and_retry()
	_mapping_lifetimes()
	_unsupported_mapping()
	_maximum_disk_roundtrip()
	_mapping_account_cleanup()
	print("CAMPAIGN TERMINAL ADMISSION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _mh() -> MappingHarness:
	var h := MappingHarness.new()
	h.tree = self
	h.pending = _request()
	return h

func _mapping(h: MappingHarness, storage: RefCounted = null) -> RefCounted:
	return Mapping.new(h.current_identity,h.current,h if storage == null else storage,h)

func _request(n: int = 1, owner: String = OWNER, maximum: bool = false) -> Dictionary:
	var body := {"schema_version":1,"idempotency_key":"terminal-create-key-"+str(n).pad_zeros(4),
		"campaign_key":{"campaign_id":"mapping-fixture","campaign_version":1,"definition_hash":"d".repeat(64)}}
	if maximum:
		body.idempotency_key = "k".repeat(72)+str(n).pad_zeros(8)
		body.campaign_key.campaign_id = "x".repeat(48)
		body.campaign_key.campaign_version = Wire.MAX_SAFE_INTEGER
	return {"path":"/v2/campaigns","body":body,"request_hash":Lobby.request_hash(owner,"/v2/campaigns",body)}

func _terminal(request: Dictionary, anchor: String = ANCHOR, owner: String = OWNER) -> Dictionary:
	return {"schema_version":1,"operation":"campaign_terminal_admission","admission":"create","status":"terminal",
		"player_id":owner,"idempotency_key":request.body.idempotency_key,"request_hash":request.request_hash,"campaign_room_id":anchor}

func _server(request: Dictionary, anchor: String = ANCHOR) -> Dictionary:
	return {"kind":"server_create","terminal":_terminal(request,anchor)}

func _join(n: int = 1, maximum: bool = false) -> Dictionary:
	var request := _request(n,OWNER,maximum)
	request.path = "/v2/campaigns/join"
	request.body.schema_version = 2
	request.body["invite_code"] = "AB".repeat(10)
	request.body["supported_simulation_versions"] = [6] if not maximum else [9007199254740984,9007199254740985,9007199254740986,9007199254740987,9007199254740988,9007199254740989,9007199254740990,9007199254740991]
	request.request_hash = Lobby.request_hash(OWNER,request.path,request.body)
	return request

func _accepted(request: Dictionary, anchor: String = ANCHOR) -> Dictionary:
	return {"kind":"accepted_reference","reference":{"campaign_room_id":anchor,"campaign_key":request.body.campaign_key.duplicate(true)},"cleanup":_receipt(anchor)}

func _entry(request: Dictionary, anchor: String = ANCHOR) -> Dictionary:
	return {"request":request,"witness":_server(request,anchor)}

func _ledger(owner: String = OWNER) -> Dictionary:
	return {"schema_version":1,"owner_player_id":owner,"mappings":[]}

func _mapping_validation() -> void:
	var request := _request()
	var receipt := _terminal(request)
	_check(Mapping.request_valid(request,OWNER) and Mapping.terminal_valid(receipt,request,OWNER),"Exact original Create and separate typed terminal correlation validate")
	_check(not Mapping.terminal_valid(_receipt(),request,OWNER),"A cleanup receipt is not an admission mapping")
	for mode: String in ["path","cancel-path","join","schema-bool","schema-future","body-extra","key-short","key-long","campaign-extra","hash","hash-extra","owner"]:
		var altered := request.duplicate(true)
		match mode:
			"path": altered.path = "/v2/campaigns/"+ANCHOR
			"cancel-path": altered.path = "/v2/campaigns/cancel"
			"join": altered.path = "/v2/campaigns/join"
			"schema-bool": altered.body.schema_version = true
			"schema-future": altered.body.schema_version = 2
			"body-extra": altered.body["accepted_campaign"] = ANCHOR
			"key-short": altered.body.idempotency_key = "short"
			"key-long": altered.body.idempotency_key = "x".repeat(81)
			"campaign-extra": altered.body.campaign_key["current_index"] = 0
			"hash": altered.request_hash = "e".repeat(64)
			"hash-extra": altered["cancel_requested"] = true
			"owner": altered.request_hash = Lobby.request_hash(PEER,altered.path,altered.body)
		# Rehash malformed original bodies: shape, not just a stale digest, must reject.
		if mode not in ["hash","owner"]: altered.request_hash = Lobby.request_hash(OWNER,altered.path,altered.body)
		_check(not Mapping.request_valid(altered,OWNER),"Malformed original request holds after rehash: "+mode)
	for mode: String in ["schema-bool","future","operation","admission","status","owner","key","hash","anchor","extra"]:
		var altered := receipt.duplicate(true)
		match mode:
			"schema-bool": altered.schema_version = true
			"future": altered.schema_version = 2
			"operation": altered.operation = "campaign_admission_cancel"
			"admission": altered.admission = "join"
			"status": altered.status = "accepted"
			"owner": altered.player_id = PEER
			"key": altered.idempotency_key = _request(2).body.idempotency_key
			"hash": altered.request_hash = "e".repeat(64)
			"anchor": altered.campaign_room_id = "../room"
			"extra": altered["campaign"] = {}
		_check(not Mapping.terminal_valid(altered,request,OWNER),"Only the exact eight-field result is correlation: "+mode)
	var h := _mh()
	var helper := _mapping(h)
	_check(helper.restore_owner() and h.writes == 0 and h.calls.is_empty(),"Empty mapping restoration never writes or calls transport")
	_check(not helper.record_mapping(request,_server(request),Callable()) and h.writes == 0,"Recording requires a current exact pending observer")
	h.pending = _request(2)
	_check(not helper.record_mapping(request,_server(request),h.current_pending) and h.writes == 0,"Another pending Create cannot authorize this correlation")

func _local_witnesses() -> void:
	for admission: String in ["create","join"]:
		var h := _mh()
		h.pending = _request() if admission == "create" else _join()
		var request := h.pending.duplicate(true)
		var anchor := ANCHOR if admission == "create" else ("v2:"+str(request.body.invite_code)).sha256_text().substr(0,22)
		var witness := _accepted(request,anchor)
		var helper := _mapping(h)
		_check(Mapping.witness_valid(witness,request,OWNER),"Strict accepted reference plus cleanup validates for "+admission)
		_check(not helper.record_mapping(request,witness,h.current_pending) and h.writes == 0,"Accepted reference must already exist in durable pending")
		h.accepted = witness.reference.duplicate(true)
		_check(helper.record_mapping(request,witness,h.current_pending),"Original accepted "+admission+" request is durable before local retirement")
		_check(Mapping.mapped_anchor(helper.mapping_for(request),OWNER) == anchor,"Validated witness resolves only its exact anchor")
		h.pending = {}
		h.accepted = {}
		_check(helper.mapping_for(request).witness.kind == "accepted_reference","Local evidence remains explicitly distinct from server correlation")
	for mode: String in ["key","anchor","receipt-owner","receipt-anchor","receipt-extra","future","missing-receipt"]:
		var request := _join()
		var anchor := ("v2:"+str(request.body.invite_code)).sha256_text().substr(0,22)
		var witness := _accepted(request,anchor)
		match mode:
			"key": witness.reference.campaign_key.definition_hash = "f".repeat(64)
			"anchor": witness.reference.campaign_room_id = OTHER
			"receipt-owner": witness.cleanup.player_id = PEER
			"receipt-anchor": witness.cleanup.campaign_room_id = OTHER
			"receipt-extra": witness.cleanup["request_hash"] = request.request_hash
			"future": witness.cleanup.schema_version = 2
			"missing-receipt": witness.erase("cleanup")
		_check(not Mapping.witness_valid(witness,request,OWNER),"Accepted-reference witness refuses unrelated evidence: "+mode)
	var h := _mh()
	h.pending = _join()
	var request := h.pending.duplicate(true)
	var anchor := ("v2:"+str(request.body.invite_code)).sha256_text().substr(0,22)
	var invitation := {"kind":"join_invitation","cleanup":_receipt(anchor)}
	var helper := _mapping(h)
	_check(helper.record_mapping(request,invitation,h.current_pending),"Lost Join2 response can be preserved via its exact invitation and cleanup receipt")
	_check(Mapping.mapped_anchor(helper.mapping_for(request),OWNER) == anchor,"Join witness uses the original invitation digest")
	_check(not Mapping.witness_valid(_server(request,anchor),request,OWNER),"Local Join evidence cannot fabricate a Create server result")
	_check(not Mapping.witness_valid(invitation,_request(),OWNER),"Unknown Create never inherits Join invitation authority")
	var changed := invitation.duplicate(true)
	changed.cleanup.campaign_room_id = OTHER
	_check(not Mapping.witness_valid(changed,request,OWNER),"Unrelated terminal anchor cannot settle the original Join")
	for mode: String in ["join1","extra","bad-invite","empty-versions","duplicate-versions","boolean-version"]:
		var altered := request.duplicate(true)
		match mode:
			"join1": altered.body.schema_version = 1
			"extra": altered.body["legacy"] = true
			"bad-invite": altered.body.invite_code = "ab".repeat(10)
			"empty-versions": altered.body.supported_simulation_versions = []
			"duplicate-versions": altered.body.supported_simulation_versions = [6,6]
			"boolean-version": altered.body.supported_simulation_versions = [true]
		altered.request_hash = Lobby.request_hash(OWNER,altered.path,altered.body)
		_check(not Mapping.request_valid(altered,OWNER),"Unrecognized/malformed Join stays held after rehash: "+mode)
	var create_h := _mh()
	var create_helper := _mapping(create_h)
	var create := create_h.pending.duplicate(true)
	_check(create_helper.record_mapping(create,_server(create),create_h.current_pending),"Actual server correlation may precede cleanup")
	create_h.accepted = _accepted(create).reference
	_check(not create_helper.record_mapping(create,_accepted(create),create_h.current_pending),"Later local knowledge never overwrites the original server witness")
	_check(Mapping.mapped_anchor(create_helper.mapping_for(create),OWNER) == ANCHOR,"Owner can reuse the retained same-request witness before retirement")

func _preservation_and_retry() -> void:
	var h := _mh()
	var protected := {"gameplay":{"pending":{"recording":"original"}},"photos":{"pending":{"asset":"original"}},"keepsakes":{"earned":true},_scope():_empty()}
	h.saved = protected.duplicate(true)
	var helper := _mapping(h)
	var request := h.pending.duplicate(true)
	var receipt := _server(request)
	h.fail_write = 1
	_check(not helper.record_mapping(request,receipt,h.current_pending) and helper.mappings().is_empty(),"Failed write exposes no in-memory correlation")
	_check(Canonical.same(h.saved,protected) and h.pending == request,"Failed write preserves original pending and all other journals")
	_check(helper.record_mapping(request,receipt,h.current_pending),"Explicit exact retry durably records the mapping")
	for key: String in protected: _check(h.saved[key] == protected[key],"Mapping cannot touch protected scope: "+key)
	var written := h.writes
	_check(helper.record_mapping(request,receipt,h.current_pending) and h.writes == written,"An identical repeat performs no duplicate write")
	var conflict := _server(request,OTHER)
	_check(not helper.record_mapping(request,conflict,h.current_pending) and h.writes == written,"Same request cannot be rebound to another anchor")
	var alias := request.duplicate(true)
	alias.body.campaign_key.definition_hash = "e".repeat(64)
	alias.request_hash = Lobby.request_hash(OWNER,alias.path,alias.body)
	h.pending = alias
	_check(not helper.record_mapping(alias,_server(alias,OTHER),h.current_pending) and h.writes == written,"Same idempotency key with a different valid body/hash holds")
	h.pending = {}
	var cold := _mapping(h)
	_check(cold.restore_owner() and cold.mapping_for(request) == {"request":request,"witness":receipt},"Cold mapping remains readable after pending is cleared separately")
	_check(not cold.record_mapping(request,receipt,h.current_pending) and h.writes == written,"A repeat cannot reactivate a cleared pending request")
	var copied: Dictionary = cold.mapping_for(request)
	copied.witness.terminal.campaign_room_id = OTHER
	_check(cold.mapping_for(request).witness.terminal.campaign_room_id == ANCHOR,"Read copies cannot mutate permanent evidence")
	_check(h.calls.is_empty(),"No mapping operation has a transport side effect")

func _mapping_lifetimes() -> void:
	for phase: String in ["load","save"]:
		for change: String in ["identity","epoch","retire","lifetime","pending"]:
			var h := _mh()
			var helper := _mapping(h)
			var request := h.pending.duplicate(true)
			var change_state := func() -> void:
				match change:
					"identity": h.identity.player_id = PEER
					"epoch": h.identity.epoch += 1
					"retire": helper.retire()
					"lifetime": h.guard_value = false
					"pending": h.pending = _request(2)
			if phase == "load": h.on_load = change_state
			else: h.on_save = func(_value: Dictionary) -> void: change_state.call()
			_check(not helper.record_mapping(request,_server(request),h.current_pending),"Identity/lifetime/pending change cannot accept a mapping: "+phase+"/"+change)
			_check(helper.mapping_for(request).is_empty(),"Retired in-flight context exposes no correlation")
			_check(h.writes == (0 if phase == "load" else 1),"Callback race cannot cause another write or relabel evidence")
			if phase == "save":
				_check(h.saved.has(Mapping.scope_for(OWNER)) and not h.saved.has(Mapping.scope_for(PEER)),"Any completed write remains bound to the original owner")
			h.on_load = Callable()
			h.on_save = Callable()
	for bad: Variant in [false,1,"true",null]:
		var h := _mh()
		h.guard_value = bad
		var helper := _mapping(h)
		_check(not helper.restore_owner() and not helper.record_mapping(h.pending,_server(h.pending),h.current_pending) and h.writes == 0,"Lifetime guard requires an explicit true boolean")
	var h := _mh()
	var helper := _mapping(h)
	_check(helper.record_mapping(h.pending,_server(h.pending),h.current_pending),"Owner has durable evidence before same-epoch invalidation")
	helper.invalidate_identity()
	_check(helper.mappings().is_empty(),"Explicit identity invalidation immediately hides loaded evidence")
	_check(helper.restore_owner() and helper.mappings().size() == 1,"An explicit valid reload can observe the same original durable proof")
	helper.retire()
	_check(not helper.restore_owner() and helper.mappings().is_empty(),"Permanent retirement cannot be undone by same identity reload")

func _unsupported_mapping() -> void:
	for mode: String in ["future","foreign","extra","duplicate-key","duplicate-hash","bad-request","bad-receipt","over-capacity"]:
		var h := _mh()
		var value := _ledger()
		var request := _request()
		value.mappings.append(_entry(request))
		match mode:
			"future": value.schema_version = 2
			"foreign": value.owner_player_id = PEER
			"extra": value["released"] = []
			"duplicate-key":
				var alias := request.duplicate(true)
				alias.body.campaign_key.definition_hash = "e".repeat(64)
				alias.request_hash = Lobby.request_hash(OWNER,alias.path,alias.body)
				value.mappings.append(_entry(alias,OTHER))
			"duplicate-hash": value.mappings.append(value.mappings[0].duplicate(true))
			"bad-request": value.mappings[0].request.path = "/v2/campaigns/cancel"
			"bad-receipt": value.mappings[0].witness.terminal.operation = "campaign_terminal_cleanup"
			"over-capacity":
				for n in range(2,130):
					var more := _request(n)
					value.mappings.append(_entry(more,str(n).pad_zeros(22)))
		h.saved[Mapping.scope_for(OWNER)] = value.duplicate(true)
		var helper := _mapping(h)
		_check(not helper.restore_owner() and helper.read_only,"Unknown/malformed journal holds: "+mode)
		_check(not helper.record_mapping(h.pending,_server(h.pending),h.current_pending) and h.writes == 0,"Read-only mapping cannot overwrite existing evidence")
		_check(h.saved[Mapping.scope_for(OWNER)] == value,"Unsupported journal source remains unchanged")

func _maximum_disk_roundtrip() -> void:
	var h := _mh()
	var full := _ledger()
	for n in range(128):
		var request := _join(n,true)
		var anchor := ("v2:"+str(request.body.invite_code)).sha256_text().substr(0,22)
		full.mappings.append({"request":request,"witness":_accepted(request,anchor)})
	var bytes := JSON.stringify(full).to_utf8_buffer().size()
	_check(Mapping.journal_valid(full,OWNER) and bytes < Mapping.MAX_BYTES,"Maximum128 entries with maximum-length fields fit the strict journal bounds")
	var location := directory.path_join("mapping-maximum")
	var storage := Store.new(location)
	_check(storage.save_scope(Mapping.scope_for(OWNER),full).ok,"Actual Store writes the maximum mapping journal")
	var cold := _mapping(h,Store.new(location))
	_check(cold.restore_owner() and Canonical.same(cold.mappings(),full.mappings),"Actual LocalSave cold roundtrip preserves all128 exact requests and receipts")
	h.pending = full.mappings[127].request.duplicate(true)
	h.accepted = full.mappings[127].witness.reference.duplicate(true)
	var path := location.path_join(Mapping.scope_for(OWNER).sha256_text()+".json")
	var before := FileAccess.get_file_as_bytes(path)
	_check(cold.record_mapping(h.pending,full.mappings[127].witness,h.current_pending) and FileAccess.get_file_as_bytes(path) == before,"Identical repeat at capacity does not write a new generation")
	h.pending = _request(129,OWNER,true)
	h.accepted = {}
	_check(not cold.record_mapping(h.pending,_server(h.pending),h.current_pending) and FileAccess.get_file_as_bytes(path) == before,"The129th mapping cannot evict or overwrite evidence")
	_check(Store._value_limit(_scope()) == 49152 and Store._file_limit(_scope()) == 65536,"Existing cleanup ledger limits remain unchanged")
	_check(Store._value_limit("relay-room-v2:"+OWNER+":"+ANCHOR) == 3145728 and Store._file_limit("relay-lobby-v2:"+OWNER) == 4194304,"Ordinary scope limits remain unchanged")
	_check(Store._value_limit(Mapping.scope_for(OWNER)) == 196608 and Store._file_limit(Mapping.scope_for(OWNER)) == 262144,"Larger bounds apply only to the exact new scope")
	_check(not storage.save_scope(_scope(),{"padding":"x".repeat(49152)}).ok,"Larger mapping cap cannot weaken an existing campaign scope")
	for invalid: String in ["relay-campaign-admission-terminal-v2:"+OWNER,Mapping.scope_for(OWNER)+":"+ANCHOR,"relay-campaign-admission-terminal-v1:../owner"]:
		_check(not Store.new(location).load_scope(invalid).ok,"Unknown mapping scope cannot open a file")
	for mode: String in ["envelope","journal","truncated"]:
		var site := directory.path_join("mapping-future-"+mode)
		var disk := Store.new(site)
		_check(disk.save_scope(Mapping.scope_for(OWNER),full).ok,"Future-preservation fixture begins with a real valid journal")
		var target := site.path_join(Mapping.scope_for(OWNER).sha256_text()+".json")
		var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(target))
		if mode == "envelope": envelope.version = 9
		elif mode == "journal": envelope.relay_online_value.schema_version = 9
		_write(target,"{interrupted" if mode == "truncated" else envelope)
		var original := FileAccess.get_file_as_bytes(target)
		var held := _mapping(h,Store.new(site))
		_check(not held.restore_owner() and held.read_only and not held.record_mapping(h.pending,_server(h.pending),h.current_pending),"Unknown/corrupt actual save holds: "+mode)
		_check(FileAccess.get_file_as_bytes(target) == original,"Failed restore preserves exact file bytes")
	print("TERMINAL ADMISSION MAXIMUM: %d value bytes; %d envelope bytes; 128 mappings" % [bytes,before.size()])

func _mapping_account_cleanup() -> void:
	var cleanup := Cleanup.new()
	cleanup.relay_directory = directory.path_join("mapping-cleanup/relay")
	cleanup.shared_directory = directory.path_join("mapping-cleanup/shared")
	cleanup.safety_directory = directory.path_join("mapping-cleanup/safety")
	var storage := Store.new(cleanup.relay_directory)
	var owned: Array[String] = []
	var peers := {}
	for owner: String in [OWNER,PEER]:
		for scope: String in [Mapping.scope_for(owner),_scope(owner),"relay-lobby-v2:"+owner]:
			_check(storage.save_scope(scope,{"first":true}).ok and storage.save_scope(scope,{"second":true}).ok,"Both owners retain new and old recoverable scopes")
			for suffix: String in ["",".backup"]:
				var path := cleanup.relay_directory.path_join(scope.sha256_text()+".json"+suffix)
				if owner == OWNER: owned.append(path)
				else: peers[path] = FileAccess.get_file_as_bytes(path)
	_write(owned[0],"{interrupted")
	_write(owned[1],"{interrupted")
	_check(cleanup.erase_owner(OWNER).ok,"Confirmed account erase recognizes even truncated new mapping generations")
	for path: String in owned: _check(not FileAccess.file_exists(path),"Only confirmed owner's known mapping/old scopes are removed")
	for path: String in peers: _check(FileAccess.get_file_as_bytes(path) == peers[path],"Other owner's mapping and retained scopes remain byte-identical")
