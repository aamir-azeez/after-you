extends SceneTree
## Optional target-factory seams with real Controller journals and old fixtures.
## Concrete campaign classification/header/proof checks belong to root composition.
const Controller = preload("res://services/turn_photo_controller.gd")
const Fixtures = preload("res://tests/test_turn_photo.gd")
const Delivery = preload("res://tests/test_photo_delivery_client.gd")
const UI = preload("res://tests/test_reaction_photos.gd")
const Flow = preload("res://presentation/reaction_photo_flow.gd")
const Strip = preload("res://presentation/reaction_photo_strip.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const ROOM := Fixtures.ROOM
const OTHER := "OOOOOOOOOOOOOOOOOOOOOO"

class TargetContext:
	extends RefCounted
	signal release
	var factory: WeakRef
	var server: RefCounted
	var room := ""
	var hold := false
	var refuse := false
	var calls: Array = []
	func current() -> bool:
		var owner: RefCounted = factory.get_ref()
		return owner != null and owner.current()
	func request(envelope: Dictionary) -> Dictionary:
		calls.append(envelope.duplicate(true))
		if not current() or refuse or not str(envelope.path).begins_with("/v2/rooms/"+room+"/"):
			return {"ok":false,"ignored":true,"status":0,"code":"campaign_context_changed"}
		if hold:
			hold = false
			await release
		if not current(): return {"ok":false,"ignored":true,"status":0,"code":"campaign_context_changed"}
		return await server.request(envelope)

class Factory:
	extends RefCounted
	var server: RefCounted
	var retired := false
	var refuse := false
	var null_next := false
	var hold_next := false
	var selected := ROOM
	var requests: Array = []
	var contexts: Array[WeakRef] = []
	var keys := 0
	func current() -> bool: return not retired
	func for_room(room: String, purpose: String) -> RefCounted:
		requests.append({"room":room,"purpose":purpose})
		if null_next:
			null_next = false
			return null
		var context := TargetContext.new()
		context.factory = weakref(self)
		context.server = server
		context.room = room
		context.hold = hold_next
		context.refuse = refuse
		hold_next = false
		contexts.append(weakref(context))
		return context
	func key() -> String:
		keys += 1
		return "photo-context-key-%04d" % keys

class CachedLibrary:
	extends RefCounted
	var reads := 0
	var writes := 0
	var metadata: Dictionary = {}
	var bytes := "verified-cache-fixture".to_utf8_buffer()
	func read_cache(_owner: String, _room: String, _expected: Dictionary) -> Dictionary:
		reads += 1
		return {"ok":true,"found":true,"photo":metadata.duplicate(true),"bytes":bytes.duplicate(),"delivery_ack":true,"entry_id":"retained"}
	func mark_deleted(_owner: String, _room: String, _photo: Dictionary) -> Dictionary:
		writes += 1
		return {"ok":true}
	func store_cache(_owner: String, _room: String, _photo: Dictionary, _bytes: PackedByteArray) -> Dictionary:
		writes += 1
		return {"ok":true,"durable":true}
	func mark_ack(_owner: String, _entry: String) -> void: writes += 1

class FactorySession:
	extends RefCounted
	var seen: Array = []
	func create_photo_controller(_local: Callable, factory: RefCounted = null) -> RefCounted:
		seen.append(factory)
		return UI.PhotoController.new()

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)

func _case(library: RefCounted = null) -> Dictionary:
	var server := Fixtures.Server.new()
	var store := Fixtures.Store.new()
	var identity := Fixtures.Identity.new()
	var local := Fixtures.Local.new()
	var factory := Factory.new()
	factory.server = server
	var controller := Controller.new(server.request,store.load_scope,store.save_scope,identity.current,local.request,factory.key,library,factory)
	return {"controller":controller,"server":server,"store":store,"identity":identity,"local":local,"factory":factory}

func _run() -> void:
	await _owned_pending_and_shared_read()
	await _factory_refusal()
	await _retired_receipt()
	await _cache_retirement()
	await _historical_ack()
	await _presentation_forwarding()
	print("Campaign photo contexts: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _owned_pending_and_shared_read() -> void:
	var c := _case()
	_check(await c.controller.open_owned_turn(ROOM,Fixtures.GAME_KEY),"Explicit target context opens the original receipt-backed edit")
	var owned: RefCounted = c.controller._owned_context
	_check(c.controller.choose_local(c.local.metadata(),c.controller.selection_context()),"Native selection remains in the original local photo scope")
	c.server.drop_before = true
	_check(not await c.controller.upload_selected() and not c.controller.pending().is_empty(),"Lost upload preserves its exact durable pending request")
	var pending: Dictionary = c.controller._state.pending.duplicate(true)
	c.factory.selected = OTHER
	var shared: Dictionary = await c.controller.read_shared(OTHER,"t0-0-a",Fixtures.RECORDING)
	_check(not shared.is_empty() and c.factory.requests.back().room == OTHER and c.controller._owned_context == owned,"A different shared read uses its own context without replacing the owned edit context")
	_check(Canonical.same(pending,c.controller._state.pending) and c.controller.target().room_id == ROOM,"Selection advance/shared read cannot rewrite pending room, key or photo bytes")
	_check(await c.controller.reconcile() and c.server.mutation_count == 1,"Explicit original receipt reconciliation recovers exactly one upload")
	_check(owned.calls.back().path.begins_with("/v2/rooms/"+ROOM+"/") and Canonical.same(owned.calls.back().body,pending.body),"The retry uses its retained original context and exact request body")

func _factory_refusal() -> void:
	var c := _case()
	c.factory.null_next = true
	_check(not await c.controller.open_owned_turn(ROOM,Fixtures.GAME_KEY) and c.server.calls.is_empty(),"Supplied factory returning null holds without ordinary fallback")
	c.factory.refuse = true
	_check((await c.controller.read_shared(ROOM,"t0-0-a",Fixtures.RECORDING)).is_empty() and c.server.calls.is_empty(),"Explicit held context cannot dispatch unmarked transport")

func _retired_receipt() -> void:
	var c := _case()
	c.factory.hold_next = true
	var completed := {"done":false,"result":true}
	_open(c.controller,completed)
	var context: RefCounted = c.factory.contexts.back().get_ref()
	var retained: WeakRef = weakref(context)
	c.controller.invalidate_identity()
	c.factory.retired = true # Numeric identity and epoch deliberately remain equal.
	context = null
	_check(retained.get_ref() != null,"Suspended operation retains context after its controller field is cleared")
	retained.get_ref().release.emit()
	await process_frame
	_check(completed.done and not completed.result and c.store.writes == 0 and c.server.calls.is_empty(),"Retired receipt cannot reach transport or save a target at the same numeric epoch")
	_check(not c.controller.choose_local(c.local.metadata(),{}) and c.controller.target().is_empty(),"Retired factory also refuses subsequent local target edits")

func _open(controller: RefCounted, result: Dictionary) -> void:
	result.result = await controller.open_owned_turn(ROOM,Fixtures.GAME_KEY)
	result.done = true

func _cache_retirement() -> void:
	var cache := CachedLibrary.new()
	var c := _case(cache)
	c.server.fail_status = 503
	c.server.fail_code = "service_unavailable"
	_check(not (await c.controller.read_shared(ROOM,"t0-0-a",Fixtures.RECORDING)).is_empty() and cache.reads == 1,"Current context preserves existing verified offline-cache behavior")
	c.factory.refuse = true
	_check((await c.controller.read_shared(ROOM,"t0-0-a",Fixtures.RECORDING)).is_empty() and cache.reads == 1,"Ignored authority refusal cannot masquerade as an offline cache read")
	c.factory.refuse = false
	c.factory.hold_next = true
	var completed := {"done":false,"value":{}}
	_read(c.controller,completed)
	var context: RefCounted = c.factory.contexts.back().get_ref()
	c.factory.retired = true
	context.release.emit()
	await process_frame
	_check(completed.done and completed.value.is_empty() and cache.reads == 1 and cache.writes == 0,"Same-epoch retirement during delivery read cannot display cache, write or ACK")

func _read(controller: RefCounted, result: Dictionary) -> void:
	result.value = await controller.read_shared(ROOM,"t0-0-a",Fixtures.RECORDING)
	result.done = true

func _historical_ack() -> void:
	var cache := CachedLibrary.new()
	var c := _case(cache)
	var delivery := Delivery.Server.new()
	delivery.photo = {"schema_version":1,"turn_id":"t0-0-a","owner_player_id":Fixtures.OWNER,"recording_hash":Fixtures.RECORDING,"photo_revision":1,"sha256":Controller._digest(cache.bytes),"width":32,"height":24,"byte_length":cache.bytes.size(),"updated_at":"2026-09-15T00:00:00.000Z"}
	cache.metadata = delivery.photo.duplicate(true)
	c.factory.server = delivery
	c.factory.hold_next = true
	# Use a cache with an unacknowledged durable entry for this operation.
	var actual := UnackedLibrary.new()
	actual.metadata = cache.metadata
	c.controller._library = actual
	var completed := {"done":false,"value":{}}
	_read(c.controller,completed)
	var context: RefCounted = c.factory.contexts.back().get_ref()
	c.factory.selected = OTHER
	context.release.emit()
	await process_frame
	_check(completed.done and not completed.value.is_empty() and delivery.acks == 1,"Historical photo remains deliverable after visible selection advances")
	_check(context.calls.size() == 2 and context.calls[1].path == "/v2/rooms/"+ROOM+"/photos/t0-0-a/ack" and actual.writes == 1,"Delivery ACK and durable marker stay in the explicit original room")

class UnackedLibrary:
	extends CachedLibrary
	func read_cache(owner: String, room: String, expected: Dictionary) -> Dictionary:
		var result := super.read_cache(owner,room,expected)
		result.delivery_ack = false
		return result

func _presentation_forwarding() -> void:
	var session := FactorySession.new()
	var factory := Factory.new()
	var host := UI.Host.new()
	root.add_child(host)
	var flow := Flow.new()
	flow.capture_override = UI.Capture.new()
	flow.configure(host,session,factory)
	host.add_child(flow)
	var strip := Strip.new()
	strip.configure(session,factory)
	host.add_child(strip)
	_check(session.seen.size() == 2 and session.seen[0] == factory and session.seen[1] == factory,"Real Flow and Strip retain and forward the optional target factory at construction")
	host.queue_free()
	await process_frame
