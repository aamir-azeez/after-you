extends "res://tests/test_archived_story_rooms.gd"
## The real photo, presence, safety and replay request context for ordinary
## chapter rooms (services/auxiliary_room_context.gd): what each purpose may
## send, when a context retires, and that a held one never falls back to the
## ordinary transport. Story rooms are covered in test_archived_story_rooms.
const ReplayView = preload("res://presentation/shared_replay_view.gd")
const AuxiliaryContext = preload("res://services/auxiliary_room_context.gd")

func _run() -> void:
	await _identity_bound()
	await _routes()
	await _paused_safety()
	await _paused_ack()
	await _await_retirement()
	await _external_presence()
	await _held_factory()
	print("Auxiliary room context: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _setup() -> Dictionary:
	var h := ArchiveHarness.new()
	root.add_child(h)
	h.rooms[ORDINARY] = _room("high-and-low",ORDINARY,false)
	h.rooms[NEXT_ROOM] = _room("rolling-home",NEXT_ROOM,false)
	var online := Online.new(h,h.identity,h.store)
	online.capabilities = {"mutations_enabled":true}
	_check(await online.open_room(ORDINARY),"The ordinary room is open")
	return {"h":h,"online":online}

func _envelope(path: String, method: int = HTTPClient.METHOD_GET, body: Dictionary = {}) -> Dictionary:
	return {"owner_player_id":HOST,"identity_epoch":1,"method":method,"path":path,"body":body}

func _identity_bound() -> void:
	var c := await _setup()
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var context: RefCounted = factory.for_room(ORDINARY,"replay")
	_check(factory.current() and context.current(),"The current identity owns the factory and its targets")
	_check(factory.for_room(ORDINARY,"replay") == context,"Asking again returns the same in-flight target")
	_check(c.online.auxiliary_context_factory() == factory,"The session keeps one factory while its identity holds")
	var before: Dictionary = c.h.store.saved.duplicate(true)
	_check((await context.request(_envelope("/v2/rooms/"+ORDINARY))).get("ok") == true,"An ordinary room read goes through")
	_check(Canonical.same(before,c.h.store.saved) and c.online.last_room() == ORDINARY,"A request never writes gameplay data or changes the selected room")
	c.h.free()

func _routes() -> void:
	var c := await _setup()
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var path: String = "/v2/rooms/"+ORDINARY
	var cases := [
		["replay",HTTPClient.METHOD_POST,path+"/turns",{}],
		["replay",HTTPClient.METHOD_GET,path+"/pairs/p0-0/trailing",{}],
		["photo",HTTPClient.METHOD_GET,path+"/operations/x",{}],
		["photo",HTTPClient.METHOD_PUT,path+"/photos/t0-0-a",{}],
		["photo",HTTPClient.METHOD_GET,"/v2/rooms/"+NEXT_ROOM+"/photos/t0-0-a",{}],
		["presence",HTTPClient.METHOD_GET,path,{}],
		["presence",HTTPClient.METHOD_POST,"/v1/presence/heartbeat",{}],
		["safety",HTTPClient.METHOD_POST,"/v1/safety/report",{"room_family":"relay","room_id":NEXT_ROOM}],
		["safety",HTTPClient.METHOD_GET,"/v1/safety/reports/retained-key",{}]]
	var count: int = c.h.calls.size()
	for item: Array in cases:
		var response: Dictionary = await factory.for_room(ORDINARY,item[0]).request(_envelope(item[2],item[1],item[3]))
		_check(response.get("ignored") == true and c.h.calls.size() == count,"A "+item[0]+" target refuses "+item[2]+" before any request")
	var photo: RefCounted = factory.for_room(ORDINARY,"photo")
	for key: String in ["saved-operation_16","a".repeat(80)]:
		await photo.request(_envelope(path+"/operations/"+key))
		count += 1
		_check(c.h.calls.size() == count,"Saved operation keys keep their full supported range")
	c.h.free()

func _paused_safety() -> void:
	var c := await _setup()
	c.online.capabilities.mutations_enabled = false
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var context: RefCounted = factory.for_room(ORDINARY,"safety")
	for path: String in ["/v1/safety/block","/v1/safety/report"]:
		c.h.replies[path] = {"ok":true,"status":200,"data":{}}
		var calls: int = c.h.calls.size()
		var response: Dictionary = await context.request(_envelope(path,HTTPClient.METHOD_POST,{"schema_version":1,"room_family":"relay","room_id":ORDINARY}))
		_check(c.h.calls.size() == calls+1 and response.get("ok") == true,"Safety still sends "+path+" while gameplay writes are paused")
	c.h.free()

func _paused_ack() -> void:
	var c := await _setup()
	var factory: RefCounted = c.online.auxiliary_context_factory()
	var recording_hash := "b".repeat(64)
	var session := ReplayView.ReadSession.new(c.h,c.h.identity,c.h.store)
	session.capabilities = {"mutations_enabled":false}
	session.photo_context_factory = factory
	session.photo_targets = [{"room_id":ORDINARY,"turn_id":"t0-0-a","recording_hash":recording_hash}]
	var controller: RefCounted = session.create_photo_controller(Callable())
	var restricted: RefCounted = controller._context_factory.for_room(ORDINARY,"photo")
	var envelope := _envelope("/v2/rooms/"+ORDINARY+"/photos/t0-0-a/ack",HTTPClient.METHOD_POST,{"recording_hash":recording_hash,"photo_revision":1,"sha256":"a".repeat(64)})
	c.h.replies[envelope.path] = {"ok":true,"status":200,"data":{}}
	var calls: int = c.h.calls.size()
	_check((await restricted.request(envelope)).get("ok") == true and c.h.calls.size() == calls+1,"A replay viewer sends its verified photo delivery ACK with gameplay writes paused")
	envelope.body.recording_hash = "f".repeat(64)
	calls = c.h.calls.size()
	_check((await restricted.request(envelope)).get("ignored") == true and c.h.calls.size() == calls,"An ACK for another contribution stops before any request")
	envelope.path = "/v2/rooms/"+ORDINARY+"/photos/t0-0-a"
	for method: int in [HTTPClient.METHOD_POST,HTTPClient.METHOD_PUT,HTTPClient.METHOD_DELETE]:
		envelope.method = method
		_check((await restricted.request(envelope)).get("ignored") == true and c.h.calls.size() == calls,"A replay viewer cannot upload, replace or delete a photo")
	session.invalidate_identity()
	_check(not restricted.current() and factory.current(),"Closing the viewer retires its wrapper but not the session's factory")
	c.h.free()

func _await_retirement() -> void:
	for change: String in ["online","epoch","device","backend","api"]:
		var c := await _setup()
		var factory: RefCounted = c.online.auxiliary_context_factory()
		var context: RefCounted = factory.for_room(ORDINARY,"replay")
		var replacement := ArchiveHarness.new()
		root.add_child(replacement)
		c.h.on_request = func():
			match change:
				"online": c.online.invalidate_identity()
				"epoch": c.h.identity_value.epoch += 1
				"device": c.h.device_token = "rotated-synthetic-device"
				"backend": c.h.base_url = "https://changed.synthetic.invalid"
				"api": c.online._api = replacement
		var before: Dictionary = c.h.store.saved.duplicate(true)
		var response: Dictionary = await context.request(_envelope("/v2/rooms/"+ORDINARY))
		_check(response.get("ignored") == true and not context.current() and not factory.current(),"A "+change+" change during a request retires it as ignored")
		_check(Canonical.same(before,c.h.store.saved),"Retirement leaves every saved scope unchanged")
		c.h.on_request = Callable()
		replacement.free()
		c.h.free()

func _external_presence() -> void:
	var c := await _setup()
	var external := ArchiveHarness.new()
	root.add_child(external)
	external.rooms = c.h.rooms.duplicate(true)
	var context: RefCounted = c.online.auxiliary_context_factory().for_room(ORDINARY,"presence")
	var request := _envelope("/v2/rooms/"+ORDINARY+"/presence")
	c.online._busy = true
	_check((await context.request_on(external,external.identity,request)).get("ok") == true and external.calls.size() == 1,"Presence uses its own API even while the gameplay API is busy")
	var count: int = external.calls.size()
	external.device_token = "wrong-external-device"
	_check((await context.request_on(external,external.identity,request)).get("ignored") == true and external.calls.size() == count,"Presence refuses mismatched credentials before sending")
	external.device_token = c.h.device_token
	external.on_request = func(): external.identity_value.epoch += 1
	_check((await context.request_on(external,external.identity,request)).get("ignored") == true,"Presence checks the identity again after the request")
	c.online._busy = false
	external.free()
	c.h.free()

func _held_factory() -> void:
	var c := await _setup()
	c.h.identity_value.ready = false
	var factory: RefCounted = c.online.auxiliary_context_factory()
	_check(factory != null and not factory.current(),"Without an identity the session gives a held factory")
	var count: int = c.h.calls.size()
	for purpose: String in ["photo","replay","presence","safety"]:
		var target: RefCounted = factory.for_room(ORDINARY,purpose)
		_check(not target.current() and (await target.request(_envelope("/v2/rooms/"+ORDINARY+"/photos/t0-0-a"))).get("ignored") == true and c.h.calls.size() == count,"A held "+purpose+" target never falls back to the ordinary transport")
	var detached := AuxiliaryContext.new(null,{})
	_check(not detached.current() and (await detached.for_room(ORDINARY,"replay").request(_envelope("/v2/rooms/"+ORDINARY))).get("ignored") == true and c.h.calls.size() == count,"A factory with no session holds every request")
	c.h.free()
