extends "res://tests/test_shared_replays.gd"
## Historical native replay proofs plus the nested viewer's scoped write ceiling.
class Target extends RefCounted:
	var factory: RefCounted
	var room := ""
	var purpose := ""
	func current() -> bool: return factory.current()
	func request(value: Dictionary) -> Dictionary:
		factory.calls.append(value.duplicate(true))
		if not current() or factory.refuse or not str(value.path).begins_with("/v2/rooms/"+room+"/"):
			return {"ok":false,"ignored":true,"status":0,"code":"campaign_context_changed"}
		var response: Dictionary = await factory.api.request_json(value.method,value.path,value.body)
		return response if current() else {"ok":false,"ignored":true,"status":0,"code":"campaign_context_changed"}

class Factory extends RefCounted:
	var api: Node
	var retired := false
	var refuse := false
	var requests: Array = []
	var calls: Array = []
	var contexts: Array[WeakRef] = []
	func current() -> bool: return not retired
	func for_room(room: String, purpose: String) -> RefCounted:
		requests.append({"room":room,"purpose":purpose})
		var target := Target.new()
		target.factory = self
		target.room = room
		target.purpose = purpose
		contexts.append(weakref(target))
		return target

func _case() -> Dictionary:
	var owner := Boundary.new()
	var api := Api.new()
	root.add_child(api)
	var cache := Memory.new()
	var online := OnlineMemory.new()
	var factory := Factory.new()
	factory.api = api
	var collection := Collection.new(api,owner.identity,cache,online,factory)
	_check(collection._ready_owner() and collection._remember_room(_snapshot(Registry.FIRST_STEPS),"chapter"),"Known historical room and its native accepted checkpoint are replay-verified")
	var key := "chapter:"+ROOM
	var entry: Dictionary = await collection.open_memory(key,"p0-1")
	var pair: Dictionary = entry.pair.duplicate(true)
	pair["pair_id"] = "p1-1"
	pair["branch"] = 1
	api.replies["/v2/rooms/"+ROOM+"/collection"] = _ok({"pairs":[{"pair_id":"p1-1","branch":1,"stage_index":1,"a_hash":pair.a.recording_hash,"b_hash":pair.b.recording_hash,"checkpoint_hash":pair.checkpoint.checkpoint_hash}]})
	api.replies["/v2/rooms/"+ROOM+"/pairs/p1-1"] = _ok(pair)
	return {"owner":owner,"api":api,"cache":cache,"online":online,"factory":factory,"collection":collection,"key":key,"entry":entry}

func _run() -> void:
	await _historical_reads()
	await _factory_reconfiguration()
	await _readonly_view()
	print("Campaign replay contexts: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _historical_reads() -> void:
	var c := await _case()
	var rows: Array = await c.collection.refresh_memories(c.key)
	var archived: Dictionary = await c.collection.open_memory(c.key,"p1-1",rows.back())
	_check(Collection.verify_entry(archived,HOST) and c.factory.requests == [{"room":ROOM,"purpose":"replay"},{"room":ROOM,"purpose":"replay"}],"Explicit historical collection and pair GETs use the original room factory and native proof validation")
	_check(c.factory.calls.all(func(row: Dictionary) -> bool: return row.method == HTTPClient.METHOD_GET) and c.online.writes == 0 and c.online.values.is_empty(),"Historical replay never writes ordinary lobby/gameplay state")
	var writes: int = c.cache.writes
	c.factory.refuse = true
	_check((await c.collection.refresh_memories(c.key)).size() == 3 and not (await c.collection.open_memory(c.key,"p1-1")).is_empty() and c.cache.writes == writes,"Held remote authority preserves already verified accepted replay evidence")
	var contexts: int = c.factory.requests.size()
	await c.collection.refresh_rooms()
	_check(c.factory.requests.size() == contexts and c.api.calls[-2].path == "/v1/rooms" and c.api.calls[-1].path == "/v2/rooms","Ordinary and legacy discovery lists do not infer room context from their URL")
	await _dispose(c)

func _factory_reconfiguration() -> void:
	var c := await _case()
	c.api.hold = true
	var done := {"done":false,"entry":{}}
	_open(c.collection,c.key,done)
	var writes: int = c.cache.writes
	var context: WeakRef = c.factory.contexts.back()
	var replacement := Factory.new()
	replacement.api = c.api
	c.collection.configure_context_factory(replacement)
	_check(context.get_ref() != null and c.collection.busy() and c.cache.writes == writes,"Replacing a factory retains the in-flight context while preserving local cache")
	c.api.release.emit()
	await process_frame
	_check(done.done and done.entry.is_empty() and not c.collection.busy() and c.cache.writes == writes,"Old factory response cannot publish newly fetched proof after reconfiguration")
	_check(not (await c.collection.open_memory(c.key,"p1-1")).is_empty(),"New factory can explicitly fetch the same historical proof after prior request drains")
	c.collection.configure_context_factory(null)
	var requests: int = c.api.calls.size()
	_check((await c.collection.refresh_memories(c.key)).size() == 3 and c.api.calls.size() == requests,"Configured-null holds remote chapter access without erasing cached memories")
	await _dispose(c)

func _open(collection: RefCounted, key: String, result: Dictionary) -> void:
	result.entry = await collection.open_memory(key,"p1-1")
	result.done = true

func _readonly_view() -> void:
	var c := await _case()
	var session := View.ReadSession.new(c.api,c.owner.identity,c.online)
	session.photo_targets = Collection.photo_turns(c.entry,HOST)
	session.photo_context_factory = c.factory
	var controller: RefCounted = session.create_photo_controller(Callable())
	var factory: RefCounted = controller._context_factory
	var target: RefCounted = factory.for_room(ROOM,"photo")
	var reference: Dictionary = session.photo_targets[0]
	var photo_path := "/v2/rooms/"+ROOM+"/photos/"+str(reference.turn_id)
	var envelope := {"owner_player_id":HOST,"identity_epoch":1,"method":HTTPClient.METHOD_GET,"path":photo_path,"body":{}}
	c.api.replies[photo_path] = _ok({})
	_check((await target.request(envelope)).get("ok",false),"Nested ReadSession's actual controller retains scoped photo GET access")
	for method: int in [HTTPClient.METHOD_POST,HTTPClient.METHOD_PUT,HTTPClient.METHOD_DELETE]:
		envelope.method = method
		var before: int = c.factory.calls.size()
		_check(not (await target.request(envelope)).get("ok",false) and c.factory.calls.size() == before,"Readonly ceiling rejects upload/replacement/deletion before factory dispatch: "+str(method))
	envelope.method = HTTPClient.METHOD_POST
	envelope.path = photo_path+"/ack"
	envelope.body = {"recording_hash":reference.recording_hash,"photo_revision":1,"sha256":"a".repeat(64)}
	c.api.replies[envelope.path] = _ok({})
	_check((await target.request(envelope)).get("ok",false),"Exact verified contribution delivery ACK remains allowed through scoped replay context")
	envelope.body.recording_hash = "f".repeat(64)
	var before: int = c.factory.calls.size()
	_check(not (await target.request(envelope)).get("ok",false) and c.factory.calls.size() == before,"Mismatched ACK cannot cross the read-only wrapper")
	session.invalidate_identity()
	_check(not factory.current() and not target.current(),"Closing/invalidation of the read-only session retires its wrappers even at the same identity epoch")
	await _dispose(c)

func _dispose(c: Dictionary) -> void:
	c.api.queue_free()
	await process_frame
