extends "res://tests/test_campaign_owned_restore.gd"
## Concrete Owner/Online factory composition; the API alone supplies finite replies.
const SafetyClient = preload("res://services/safety_client.gd")
const SafetyStore = preload("res://services/safety_store.gd")
const ReplayView = preload("res://presentation/shared_replay_view.gd")
const ORDINARY_ROOM := "OOOOOOOOOOOOOOOOOOOOOO"

class ConsumerHarness extends RestoreHarness:
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if path not in ["/v1/safety/block", "/v1/safety/report"] and not path.ends_with("/ack"):
			return await super.request_json(method, path, body)
		if busy: return {"ok":false,"status":0,"code":"request_busy"}
		busy = true
		calls.append({"method":method,"path":path,"body":body.duplicate(true)})
		await get_tree().process_frame
		busy = false
		if path == "/v1/safety/block":
			return {"ok":true,"status":200,"data":{"schema_version":1,"blocked":true,"player_id":GUEST}}
		if path == "/v1/safety/report":
			var material := body.duplicate(true)
			material.merge({"operation":"safety_report","reporter_id":player_id})
			return {"ok":true,"status":200,"data":{"schema_version":1,"received":true,"report_id":(player_id+":"+str(body.idempotency_key)).sha256_text(),"request_hash":Canonical.digest(material)}}
		return {"ok":true,"status":200,"data":{}}

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	await _paused_consumers()
	print("Campaign auxiliary consumers: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _consumer_case() -> Dictionary:
	var h := ConsumerHarness.new()
	h.store = RestoreStore.new()
	root.add_child(h)
	h.view = fixture.active_view.duplicate(true)
	var anchor: String = h.view.campaign_room_id
	h.rooms[anchor] = _room("high-and-low",anchor,false)
	h.rooms[ORDINARY_ROOM] = _room("high-and-low",ORDINARY_ROOM,false)
	var online := Online.new(h,h.identity,h.store)
	_check(await online.open_room(anchor),"Concrete consumer fixture starts from native-verified gameplay")
	online.capabilities = {"mutations_enabled":true}
	var owner := Owner.new(online,h.identity,[fixture.definition],h.leave_ready,h.store)
	_check(owner.restore_owner() and owner.bind_campaign(anchor,Protocol.key(fixture.definition)),"Concrete auxiliary factory has a retained campaign owner")
	_check(await owner.refresh() and await owner.select_current() and owner.adopt_selected(),"Concrete owner adopts the exact verified source")
	var record := _json("res://tests/fixtures/cooperative/upper-path-a.json")
	_check(online.coordinator.save_draft(record),"A real native rehearsal is saved before paused auxiliary actions")
	online.capabilities.mutations_enabled = false
	h.leave_allowed = false
	return {"h":h,"online":online,"owner":owner,"anchor":anchor,"record":record}

func _paused_consumers() -> void:
	var c := await _consumer_case()
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var before: Dictionary = c.h.store.saved.duplicate(true)
	for room: String in [c.anchor,ORDINARY_ROOM]:
		var path := "user://concrete-safety-"+str(Time.get_ticks_usec())
		var safety := SafetyClient.new(c.h,c.h.identity,SafetyStore.new(path),Callable(),factory)
		var target := {"room_family":"relay","room_id":room,"peer_id":GUEST}
		var marked: int = c.h.campaign_calls.size()
		_check(await safety.block(target),"Actual SafetyClient accepts a room-bound block while gameplay mutations are paused")
		_check(await safety.report(target,"harassment") and safety.pending_report().is_empty(),"A blocked peer remains reportable and the exact accepted report settles its safety journal")
		_check(c.h.campaign_calls.size() == marked+(2 if room == c.anchor else 0),"Actual accepted Safety requests mark only the campaign target")
		_check(Canonical.same(before,c.h.store.saved) and Canonical.same(c.online.coordinator.draft(),c.record),"Safety leaves the active rehearsal and all gameplay/owner journals byte-equivalent")
		await _paused_readonly_ack(c,factory,room)
	_check(not c.owner.can_leave() and not c.online.capabilities.mutations_enabled,"Auxiliary success does not release the draft or re-enable gameplay writes")
	c.h.free()

func _paused_readonly_ack(c: Dictionary, factory: RefCounted, room: String) -> void:
	var session := ReplayView.ReadSession.new(c.h,c.h.identity,c.h.store)
	session.capabilities = {"mutations_enabled":false}
	session.photo_context_factory = factory
	session.photo_targets = [{"room_id":room,"turn_id":"t0-0-a","recording_hash":c.record.recording_hash}]
	var controller: RefCounted = session.create_photo_controller(Callable())
	var restricted: RefCounted = controller._context_factory.for_room(room,"photo")
	var envelope := {"owner_player_id":HOST,"identity_epoch":1,"method":HTTPClient.METHOD_POST,
		"path":"/v2/rooms/"+room+"/photos/t0-0-a/ack",
		"body":{"recording_hash":c.record.recording_hash,"photo_revision":1,"sha256":"a".repeat(64)}}
	var calls: int = c.h.calls.size()
	var marked: int = c.h.campaign_calls.size()
	_check((await restricted.request(envelope)).get("ok") == true and c.h.calls.size() == calls+1,"Concrete replay wrapper allows its verified-target ACK with gameplay writes paused")
	_check(c.h.campaign_calls.size() == marked+(1 if room == c.anchor else 0),"Paused replay ACK retains exact ordinary or campaign dispatch")
	calls = c.h.calls.size()
	envelope.body.recording_hash = "f".repeat(64)
	_check((await restricted.request(envelope)).get("ignored") == true and c.h.calls.size() == calls,"Even with a valid campaign factory, an ACK for another contribution stops before dispatch")
	envelope.path = "/v2/rooms/"+room+"/photos/t0-0-a"
	for method: int in [HTTPClient.METHOD_POST,HTTPClient.METHOD_PUT,HTTPClient.METHOD_DELETE]:
		envelope.method = method
		_check((await restricted.request(envelope)).get("ignored") == true and c.h.calls.size() == calls,"Concrete scoped replay rejects upload, replacement and deletion before transport")
	session.invalidate_identity()
	_check(not restricted.current(),"Retiring the read-only viewer retires its concrete wrapper without retiring the parent factory")
	_check(factory.current(),"Closing the read-only viewer leaves the active story and safety lifetime intact")
