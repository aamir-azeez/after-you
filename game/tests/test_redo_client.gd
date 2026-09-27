extends SceneTree
const Client = preload("res://services/redo_client.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Store = preload("res://services/relay_online_store.gd")
const Cleanup = preload("res://services/deleted_identity_cache_cleanup.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

class MemoryStore:
	extends RefCounted
	var values: Dictionary = {}
	var fail := false
	func read(scope: String) -> Dictionary: return {"ok":true,"value":values.get(scope,{}).duplicate(true)}
	func write(scope: String, value: Dictionary) -> bool:
		if fail: return false
		values[scope] = value.duplicate(true)
		return true
class Identity:
	extends RefCounted
	var player := GUEST
	var epoch := 1
	func current() -> Dictionary: return {"ready":true,"player_id":player,"epoch":epoch}
class Api:
	extends Node
	signal release
	var player_id := GUEST
	var device_token := "synthetic-redo-token"
	var base_url := "https://synthetic.invalid"
	var busy := false
	var room: Dictionary = {}
	var family := "relay"
	var requested: Variant = null
	var calls: Array = []
	var receipts: Dictionary = {}
	var drop_next := false
	var hold_next := false
	var enabled := true
	var terminal_receipt_code := ""
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		busy = true
		var owner := player_id
		calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		if hold_next:
			hold_next = false
			await release
		var response := _reply(owner,method,path,body)
		busy = false
		if drop_next and method==HTTPClient.METHOD_POST:
			drop_next = false
			return {"ok":false,"code":"connection_interrupted"}
		return response
	func _reply(owner: String, method: int, path: String, body: Dictionary) -> Dictionary:
		var source := Client.source_for(family,room)
		if "/operations/" in path:
			if not terminal_receipt_code.is_empty(): return {"ok":false,"status":404,"code":terminal_receipt_code}
			return {"ok":true,"data":receipts[path.get_file()].duplicate(true)} if receipts.has(path.get_file()) else {"ok":false,"status":404,"code":"operation_not_found"}
		if method==HTTPClient.METHOD_POST and not enabled: return {"ok":false,"status":503,"code":"v2_mutations_disabled"}
		if path.ends_with("/redo"):
			if method==HTTPClient.METHOD_POST:
				if not Canonical.same(body.source,source): return {"ok":false,"code":"redo_source_changed"}
				if body.action=="request" and requested==null: requested={"request_id":Canonical.digest(source),"source":source,"status":"pending"}
				elif body.action in ["decline","cancel"]: requested.status="declined" if body.action=="decline" else "cancelled"
			return {"ok":true,"data":{"schema_version":1,"source":null if source.is_empty() else source,"request":requested if not source.is_empty() else null}}
		if path.ends_with("/fork"):
			if receipts.has(body.idempotency_key): return {"ok":true,"data":receipts[body.idempotency_key].duplicate(true)}
			if source.is_empty() or source.revision!=body.base_revision: return {"ok":false,"code":"stale_revision"}
			if owner!=source.first_player_id or requested==null or requested.status!="pending": return {"ok":false,"code":"redo_request_missing"}
			room.revision += 1
			room.active_role = "a"
			var result: Dictionary = {}
			if family=="relay":
				room.branch += 1
				room.recording_a = null
				var hashed := body.duplicate(true)
				hashed.operation="fork"
				var receipt := {"schema_version":2,"room_id":ROOM,"idempotency_key":body.idempotency_key,"request_hash":Canonical.digest(hashed),"operation":"fork","accepted_revision":room.revision,"branch":room.branch,"stage_index":room.stage_index,"stage_id":room.stage_id,"checkpoint_hash":room.checkpoint.checkpoint_hash,"turn_id":null,"recording_hash":null,"pair_id":null}
				result={"receipt":receipt,"room":room.duplicate(true)}
			else:
				room.attempt += 1
				room.recordings={"a":null,"b":null}
				result=room.duplicate(true)
			receipts[body.idempotency_key]=result.duplicate(true)
			return {"ok":true,"data":result}
		return {"ok":false,"code":"not_found"}

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _room(family: String) -> Dictionary:
	var room := {"room_id":ROOM,"revision":2,"host_id":HOST,"guest_id":GUEST,"first_player_id":HOST,"active_role":"b"}
	if family=="relay": room.merge({"branch":0,"stage_index":0,"stage_id":"first-stage","recording_a":{"recording_hash":"a".repeat(64)},"checkpoint":{"checkpoint_hash":"c".repeat(64)}})
	else: room.merge({"attempt":0,"level_index":0,"recordings":{"a":{"final_state_hash":"a".repeat(64)},"b":null}})
	return room
func _run() -> void:
	for family: String in ["relay","legacy"]: await _flow(family)
	await _identity_and_conflict()
	_disk_scope_cleanup()
	print("After You redo client: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func _flow(family: String) -> void:
	var api := Api.new()
	api.family=family
	api.room=_room(family)
	root.add_child(api)
	var identity := Identity.new()
	var storage := MemoryStore.new()
	var guest := Client.new(api,identity.current,storage)
	_check(guest.bind_room(family,api.room) and await guest.refresh() and guest.can_request(),family+" current second player can request")
	storage.fail=true
	var calls := api.calls.size()
	_check(not await guest.request_redo() and api.calls.size()==calls,family+" request is not sent until saved")
	storage.fail=false
	api.drop_next=true
	_check(not await guest.request_redo() and not guest.pending().is_empty(),family+" lost request reply keeps durable source")
	var pending: Dictionary = guest.pending()
	guest=Client.new(api,identity.current,storage)
	_check(guest.bind_room(family,api.room) and Canonical.same(guest.pending(),pending) and await guest.retry(),family+" cold retry restores exact request")
	_check(not guest.can_request() and guest.can_cancel() and not guest.can_accept(),family+" requesting second player cannot accept own request")
	identity.player=HOST
	api.player_id=HOST
	var first := Client.new(api,identity.current,storage)
	_check(first.bind_room(family,api.room) and await first.refresh() and first.can_accept(),family+" first player gets consent controls")
	api.drop_next=true
	_check(not await first.accept() and not first.pending().is_empty(),family+" uncertain fork keeps its single idempotency key")
	pending=first.pending()
	var other := api.room.duplicate(true)
	other.room_id="S".repeat(22)
	_check(not first.bind_room(family,other),family+" navigation cannot hide an uncertain acceptance")
	first=Client.new(api,identity.current,storage)
	_check(first.bind_room(family,api.room) and Canonical.same(first.pending(),pending),family+" accepted-source change still restores pending key")
	if family=="relay": api.enabled=false
	_check(await first.retry(family!="relay") and first.accepted and first.pending().is_empty() and api.receipts.size()==1,family+" cold acceptance retry reconciles old source without a second fork, including a paused chapter service")
	_check(not first.can_accept(),family+" accepted result requires verified gameplay refresh before more actions")
	api.queue_free()
	await process_frame
func _identity_and_conflict() -> void:
	var api := Api.new()
	api.room=_room("relay")
	root.add_child(api)
	var identity := Identity.new()
	var storage := MemoryStore.new()
	var client := Client.new(api,identity.current,storage)
	_check(client.bind_room("relay",api.room) and await client.refresh() and await client.request_redo(),"Conflict fixture has one request")
	identity.player=HOST
	api.player_id=HOST
	client=Client.new(api,identity.current,storage)
	_check(client.bind_room("relay",api.room) and await client.refresh(),"First player reads request before conflict")
	api.room.revision+=1
	api.room.active_role="complete"
	_check(not await client.accept() and client.pending().is_empty() and api.receipts.is_empty(),"Successful B commit supersedes consent without rewinding progress")
	api.room=_room("relay")
	api.requested=null
	identity.player=GUEST
	api.player_id=GUEST
	client=Client.new(api,identity.current,storage)
	_check(client.bind_room("relay",api.room) and await client.refresh(),"New identity fixture binds")
	api.hold_next=true
	var result := {"done":false,"ok":true}
	_request_into(client,result)
	_check(api.busy,"Identity test holds an actual network callback")
	api.base_url="https://other.invalid"
	api.release.emit()
	await process_frame
	_check(result.done and not result.ok and client.view().is_empty() and not client.can_cancel(),"Backend replacement invalidates in-flight room controls")
	api.base_url="https://synthetic.invalid"
	api.room=_room("relay")
	api.requested={"request_id":Canonical.digest(Client.source_for("relay",api.room)),"source":Client.source_for("relay",api.room),"status":"pending"}
	identity.player=HOST
	api.player_id=HOST
	client=Client.new(api,identity.current,storage)
	_check(client.bind_room("relay",api.room) and await client.refresh(),"Deleted-room fixture restores first-player consent")
	api.drop_next=true
	_check(not await client.accept() and not client.pending().is_empty(),"Deleted-room fixture retains uncertain acceptance")
	api.terminal_receipt_code="room_not_found"
	_check(not await client.retry(false) and client.pending().is_empty() and client.last_code=="room_not_found","Definitive missing room on GET receipt releases the navigation hold without another POST")
	api.queue_free()
	await process_frame
func _request_into(client: RefCounted, result: Dictionary) -> void:
	result.ok=await client.request_redo()
	result.done=true
func _disk_scope_cleanup() -> void:
	var directory := "user://redo-cleanup-test-" + str(Time.get_ticks_usec())
	var journal := Store.new(directory)
	var own := "relay-redo-relay-v1:"+HOST+":"+ROOM
	var peer := "relay-redo-legacy-v1:"+GUEST+":"+ROOM
	_check(journal.save_scope(own,{"pending":{"source_hash":"a".repeat(64)}}).get("ok",false) and journal.save_scope(peer,{}).get("ok",false),"Redo uses existing bounded recoverable journal scopes")
	var cleaner := Cleanup.new()
	cleaner.relay_directory=directory
	cleaner.shared_directory=directory+"-shared"
	cleaner.safety_directory=directory+"-safety"
	_check(cleaner.erase_owner(HOST).ok and not FileAccess.file_exists(directory.path_join(own.sha256_text()+".json")) and FileAccess.file_exists(directory.path_join(peer.sha256_text()+".json")),"Confirmed account cleanup removes own redo journal and preserves peer")
	_check(cleaner.erase_owner(GUEST).ok,"Temporary peer redo scope cleans up through normal ownership verification")
	DirAccess.remove_absolute(directory)
