extends "res://tests/test_campaign_owned_restore.gd"
const ORDINARY := "OOOOOOOOOOOOOOOOOOOOOO"
const Presence = preload("res://services/friend_presence.gd")
const PresenceFixtures = preload("res://tests/test_friend_presence.gd")

class ConcretePresenceApi extends PresenceFixtures.Api:
	var campaign_calls := 0
	func request_campaign_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		campaign_calls += 1
		return await request_json(method,path,body)

func _run() -> void:
	fixture = _json("res://tests/fixtures/campaign/control-v2.json")
	await _historical()
	await _routes()
	await _paused_safety()
	await _receipt_room()
	await _await_retirement()
	await _external_presence()
	await _presence_service()
	await _journal_holds()
	await _ambiguous_factory()
	await _bounded_history()
	await _factory_failures()
	print("Campaign auxiliary authority: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _envelope(path: String, method: int = HTTPClient.METHOD_GET, body: Dictionary = {}) -> Dictionary:
	return {"owner_player_id":HOST,"identity_epoch":1,"method":method,"path":path,"body":body}

func _historical() -> void:
	var c := await _make()
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var context: RefCounted = factory.for_room(c.anchor,"replay")
	_check(factory.current() and context.current(),"Exact identity owns the auxiliary lifetime")
	_check(factory.for_room(c.anchor,"replay") == context,"Repeated target lookup preserves an existing in-flight context")
	var before: Dictionary = c.h.store.saved.duplicate(true)
	var calls: int = c.h.campaign_calls.size()
	var response: Dictionary = await context.request(_envelope("/v2/rooms/"+c.anchor))
	_check(response.get("ok") == true and c.h.campaign_calls.size() == calls+1,"Historical room read uses explicit campaign negotiation")
	_check(Canonical.same(before,c.h.store.saved),"Auxiliary verification does not write gameplay, owner or room selection")
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh() and await c.owner.select_current() and c.owner.adopt_selected(),"Actual verified handoff advances the visible chapter")
	_check(context.current() and (await context.request(_envelope("/v2/rooms/"+c.anchor))).get("ok") == true,"Historical target survives a selected chapter change")
	_check(c.owner.release_for_ordinary(),"Story is deliberately released")
	_check(context.current() and (await context.request(_envelope("/v2/rooms/"+c.anchor))).get("ok") == true,"Release retains exact historical authority without rebinding the story")
	_check(c.owner.bound_campaign().is_empty() and c.online.last_room() == c.target,"A historical read cannot select its old chapter")
	c.h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	var ordinary: RefCounted = factory.for_room(ORDINARY,"replay")
	calls = c.h.campaign_calls.size()
	_check((await ordinary.request(_envelope("/v2/rooms/"+ORDINARY))).get("ok") == true and c.h.campaign_calls.size() == calls,"An explicit ordinary target keeps unmarked transport")
	c.h.free()

func _routes() -> void:
	var c := await _make()
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var path: String = "/v2/rooms/"+c.anchor
	var cases := [
		["replay",HTTPClient.METHOD_POST,path+"/turns",{}],
		["replay",HTTPClient.METHOD_GET,path+"/pairs/p0-0/trailing",{}],
		["photo",HTTPClient.METHOD_GET,path+"/operations/x",{}],
		["photo",HTTPClient.METHOD_PUT,path+"/photos/t0-0-a",{}],
		["photo",HTTPClient.METHOD_GET,"/v2/rooms/"+c.target+"/photos/t0-0-a",{}],
		["presence",HTTPClient.METHOD_GET,path,{}],
		["presence",HTTPClient.METHOD_POST,"/v1/presence/heartbeat",{}],
		["safety",HTTPClient.METHOD_POST,"/v1/safety/report",{"room_family":"relay","room_id":c.target}],
		["safety",HTTPClient.METHOD_GET,"/v1/safety/reports/retained-key",{}]]
	var count: int = c.h.calls.size()
	for item: Array in cases:
		var context: RefCounted = factory.for_room(c.anchor,item[0])
		var response: Dictionary = await context.request(_envelope(item[2],item[1],item[3]))
		_check(response.get("ignored") == true and c.h.calls.size() == count,"Purpose and exact target prohibit unrelated auxiliary routes")
	var photo: RefCounted = factory.for_room(c.anchor,"photo")
	for key: String in ["saved-operation_16","a".repeat(80)]:
		await photo.request(_envelope(path+"/operations/"+key))
		count += 1
		_check(c.h.calls.size() == count,"Retained operation keys preserve the complete existing supported range")
	c.h.free()

func _paused_safety() -> void:
	var c := await _make()
	c.h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	c.online.capabilities.mutations_enabled = false
	c.h.leave_allowed = false
	var factory: RefCounted = c.online.auxiliary_context_factory()
	for room: String in [c.anchor,ORDINARY]:
		var context: RefCounted = factory.for_room(room,"safety")
		for path: String in ["/v1/safety/block","/v1/safety/report"]:
			var calls: int = c.h.calls.size()
			var marked: int = c.h.campaign_calls.size()
			var response: Dictionary = await context.request(_envelope(path,HTTPClient.METHOD_POST,{"schema_version":1,"room_family":"relay","room_id":room}))
			_check(c.h.calls.size() == calls+1 and response.get("code") != "v2_mutations_disabled","Safety still dispatches with gameplay writes paused and a draft departure guard")
			_check(c.h.campaign_calls.size() == marked+(1 if room == c.anchor else 0),"Paused safety negotiates only the exact campaign target")
	c.h.free()

func _receipt_room() -> void:
	for changed: String in ["none","pin","partner","simulation","room"]:
		var c := await _make()
		var record := _json("res://tests/fixtures/cooperative/upper-path-a.json")
		_check(not await c.online.coordinator.commit(record),"A native A turn retains its exact lost-response key")
		var pending: Dictionary = c.online.coordinator.pending()
		var room: Dictionary = c.h.rooms[c.anchor].duplicate(true)
		room.revision = 2
		room.recording_a = record
		room.a_turn_id = "t0-0-a"
		room.active_role = "b"
		room.active_player_id = GUEST
		var receipt := {"schema_version":2,"room_id":c.anchor,"idempotency_key":pending.body.idempotency_key,"request_hash":pending.request_hash,
			"operation":"turns","accepted_revision":2,"branch":0,"stage_index":0,"stage_id":record.stage_id,
			"turn_id":"t0-0-a","recording_hash":record.recording_hash,"pair_id":null,"checkpoint_hash":room.checkpoint.checkpoint_hash}
		match changed:
			"pin": room.definition_hash = "a".repeat(64)
			"partner": room.guest_id = OTHER
			"simulation": room.simulation_version = 99
			"room": room.room_id = c.target
		c.h.operation_reply = {"ok":true,"status":200,"data":{"receipt":receipt,"room":room}}
		c.online.photo_store = c.h.store
		var controller: RefCounted = c.online.create_photo_controller(Callable())
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var okay: bool = await controller.open_owned_turn(c.anchor,pending.body.idempotency_key)
		_check(okay == (changed == "none"),"Actual photo controller verifies the accepted room's "+changed+" binding")
		_check(Canonical.same(before,c.h.store.saved) and Canonical.same(c.online.coordinator.pending(),pending),"Opening or rejecting a photo does not alter the retained gameplay request")
		if changed != "none": _check(controller._scope.is_empty() and controller._state.is_empty(),"Mismatched nested receipt cannot install a photo target")
		c.h.free()

func _await_retirement() -> void:
	for change: String in ["owner","online","epoch","device","backend"]:
		var c := await _make()
		var factory: RefCounted = c.online.auxiliary_context_factory()
		var context: RefCounted = factory.for_room(c.anchor,"replay")
		c.h.on_request = func():
			match change:
				"owner":
					c.owner.invalidate_identity()
					c.owner.restore_owner()
				"online": c.online.invalidate_identity()
				"epoch": c.h.identity_value.epoch += 1
				"device": c.h.device_token = "rotated-synthetic-device"
				"backend": c.h.base_url = "https://changed.synthetic.invalid"
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var response: Dictionary = await context.request(_envelope("/v2/rooms/"+c.anchor))
		_check(response.get("ignored") == true and not context.current(),"Retired "+change+" completes as ignored rather than an offline cache opportunity")
		_check(Canonical.same(before,c.h.store.saved),"Retirement leaves every durable scope unchanged")
		c.h.on_request = Callable()
		c.h.free()

func _external_presence() -> void:
	var c := await _make()
	var external := Boundaries.Harness.new()
	root.add_child(external)
	external.rooms = c.h.rooms.duplicate(true)
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var context: RefCounted = factory.for_room(c.anchor,"presence")
	var request := _envelope("/v2/rooms/"+c.anchor+"/presence")
	c.online._busy = true
	var response: Dictionary = await context.request_on(external,external.identity,request)
	_check(response.get("ok") == true and external.campaign_calls.size() == 1,"Presence uses its independent API even while the gameplay API is occupied")
	var count: int = external.calls.size()
	external.device_token = "wrong-external-device"
	_check((await context.request_on(external,external.identity,request)).get("ignored") == true and external.calls.size() == count,"Presence refuses mismatched external credentials before dispatch")
	external.device_token = c.h.device_token
	external.on_request = func(): external.identity_value.epoch += 1
	_check((await context.request_on(external,external.identity,request)).get("ignored") == true,"Presence rechecks its live identity observer after await")
	c.online._busy = false
	external.on_request = Callable()
	external.free()
	c.h.free()

func _presence_service() -> void:
	var c := await _make()
	var service := Presence.new()
	var api := ConcretePresenceApi.new()
	var clock := PresenceFixtures.Clock.new()
	service.api = api
	service.clock_ms = clock.read
	root.add_child(service)
	service.set_process(false)
	var identity: Dictionary = c.h.identity()
	identity.merge({"device_token":c.h.device_token,"base_url":c.h.base_url})
	service.set_identity(identity)
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var context: RefCounted = factory.for_room(c.anchor,"presence")
	service.monitor_room("v2",c.anchor,context,true)
	c.online._busy = true
	await service.service()
	_check(api.calls.size() == 1 and api.campaign_calls == 0 and api.calls[0].path == "/v1/presence","Actual Presence heartbeat remains ordinary with a concrete story context")
	await service.service()
	_check(api.calls.size() == 2 and api.campaign_calls == 1 and service.view("v2",c.anchor).state == "online","Actual Presence service negotiates its independent scoped room read")
	_check(api.player_id.is_empty() and api.device_token.is_empty(),"Actual scoped Presence clears its temporary credentials")
	service._next_read = 0
	api.held = true
	service.service()
	var generation: int = service._room_generation
	service.monitor_room("v2",c.anchor,factory.for_room(c.anchor,"presence"),true)
	_check(api.busy and service._room_generation == generation,"Concrete factory reuse preserves a held real Presence read")
	c.owner.invalidate_identity()
	c.owner.restore_owner()
	api.release.emit()
	await process_frame
	_check(not service._busy and service.view("v2",c.anchor).state != "online" and api.device_token.is_empty(),"Same-epoch Owner retirement drains the actual Presence callback and hides stale status")
	c.online._busy = false
	service.queue_free()
	await process_frame
	c.h.free()

func _journal_holds() -> void:
	for changed: String in ["missing","future","deleting","read_only"]:
		var c := await _make()
		var factory: RefCounted = c.online.auxiliary_context_factory()
		var context: RefCounted = factory.for_room(c.anchor,"replay")
		match changed:
			"missing": c.h.store.saved.erase(_journal(c.anchor))
			"future": c.h.store.saved[_journal(c.anchor)].schema_version = 99
			"deleting": c.h.store.saved[_journal(c.anchor)].view.state = "deleting"
			"read_only": c.owner.read_only = true
		var count: int = c.h.calls.size()
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var response: Dictionary = await context.request(_envelope("/v2/rooms/"+c.anchor))
		_check(response.get("ignored") == true and c.h.calls.size() == count,"Retained "+changed+" authority cannot silently downgrade to ordinary transport")
		_check(Canonical.same(before,c.h.store.saved),"Auxiliary holds never repair or erase retained journals")
		c.h.free()

func _ambiguous_factory() -> void:
	var c := await _make()
	c.h.view = fixture.accepted_result.campaign.duplicate(true)
	_check(await c.owner.refresh(),"Ambiguity fixture has a real published second child")
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var context: RefCounted = factory.for_room(c.target,"replay")
	var lobby: Dictionary = c.h.store.saved["relay-campaign-lobby-v1:"+HOST].duplicate(true)
	var reference: Dictionary = lobby.campaigns[0].duplicate(true)
	reference.campaign_room_id = c.target
	lobby.campaigns.append(reference)
	c.h.store.saved["relay-campaign-lobby-v1:"+HOST] = lobby
	_check(c.owner.restore_owner(true),"A second retained anchor collides with the first campaign's child")
	var count: int = c.h.calls.size()
	_check((await context.request(_envelope("/v2/rooms/"+c.target))).get("ignored") == true and c.h.calls.size() == count,"An existing target context rejects newly ambiguous ownership")
	var held: RefCounted = factory.for_room(c.target,"replay")
	_check((await held.request(_envelope("/v2/rooms/"+c.target))).get("ignored") == true and c.h.calls.size() == count,"A newly requested ambiguous target is held instead of choosing a reference")
	c.h.free()

func _bounded_history() -> void:
	var c := await _make()
	var lobby: Dictionary = c.h.store.saved["relay-campaign-lobby-v1:"+HOST].duplicate(true)
	var template: Dictionary = c.h.store.saved[_journal(c.anchor)].duplicate(true)
	for index in range(127):
		var invitation: String = ("%020x" % (index+1000)).to_upper()
		var anchor: String = ("v2:"+invitation).sha256_text().substr(0,22)
		var reference: Dictionary = lobby.campaigns[0].duplicate(true)
		reference.campaign_room_id = anchor
		lobby.campaigns.append(reference)
		var state: Dictionary = template.duplicate(true)
		state.campaign_room_id = anchor
		state.view.campaign_room_id = anchor
		state.view.invite_code = invitation
		state.view.chapters[0].room_id = anchor
		state.selected_room = anchor
		_check(Owner.Campaign.saved_state_valid(state,anchor,HOST,fixture.definition),"Populated history uses valid retained journals")
		c.h.store.saved[_journal(anchor)] = state
	c.h.store.saved["relay-campaign-lobby-v1:"+HOST] = lobby
	_check(c.owner.restore_owner(true),"The legal maximum history restores without selecting another campaign")
	var reads := {"count":0}
	c.h.store.on_load = func(_scope: String): reads.count += 1
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var started := Time.get_ticks_usec()
	var context: RefCounted = factory.for_room(c.anchor,"replay")
	var discovery_ms := float(Time.get_ticks_usec()-started)/1000.0
	_check(reads.count >= 128 and reads.count <= 132,"First authority discovery scans bounded retained history once")
	reads.count = 0
	started = Time.get_ticks_usec()
	_check((await context.request(_envelope("/v2/rooms/"+c.anchor))).get("ok") == true,"A populated history still admits the exact historical read")
	var request_ms := float(Time.get_ticks_usec()-started)/1000.0
	_check(reads.count == 2,"Before/after request authority re-reads only its exact journal")
	print("Auxiliary history diagnostic ms (128 valid in-memory journals; includes await frame): discovery=%.3f request=%.3f" % [discovery_ms,request_ms])
	c.h.store.on_load = Callable()
	c.h.free()

func _factory_failures() -> void:
	var c := await _make()
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var owner_ref: WeakRef = weakref(c.owner)
	c.erase("owner")
	await process_frame
	_check(owner_ref.get_ref() == null and not factory.current(),"Media contexts do not retain a replaced campaign owner")
	var held: RefCounted = c.online.auxiliary_context_factory()
	_check(held != null and not held.current(),"A configured but absent owner supplies an explicit held factory")
	var count: int = c.h.calls.size()
	_check((await held.for_room(c.anchor,"photo").request(_envelope("/v2/rooms/"+c.anchor+"/photos/t0-0-a"))).get("ignored") == true and c.h.calls.size() == count,"Held factory cannot fall back to ordinary media requests")
	c.h.free()
