extends SceneTree
const Presence = preload("res://services/friend_presence.gd")
const Fixtures = preload("res://tests/test_friend_presence.gd")
const ROOM := Fixtures.ROOM
const OTHER := Fixtures.OTHER

class Context:
	extends RefCounted
	signal release
	var room := ROOM
	var retired := false
	var hold := false
	var calls: Array = []
	func current() -> bool: return not retired
	func request_on(api: Node, identity_observer: Callable, envelope: Dictionary) -> Dictionary:
		if not identity_observer.is_valid(): return _held()
		var identity: Dictionary = identity_observer.call()
		calls.append({"api":weakref(api),"identity":identity.duplicate(true),"envelope":envelope.duplicate(true)})
		if not current() or envelope.method != HTTPClient.METHOD_GET or envelope.path != "/v2/rooms/"+room+"/presence": return _held()
		if hold:
			hold = false
			await release
		if not current() or not identity_observer.is_valid() or identity_observer.call() != identity or api.player_id != identity.player_id or api.device_token != identity.device_token or api.base_url != identity.base_url: return _held()
		var response: Dictionary = await api.request_json(envelope.method,envelope.path,envelope.body)
		return response if current() and identity_observer.is_valid() and identity_observer.call() == identity else _held()
	func _held() -> Dictionary: return {"ok":false,"ignored":true,"status":0,"code":"campaign_context_changed"}

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)

func _identity() -> Dictionary:
	return {"ready":true,"player_id":Fixtures.OWNER,"device_token":"synthetic-presence-credential","base_url":"https://presence.invalid","epoch":1}

func _case() -> Dictionary:
	var service := Presence.new()
	var api := Fixtures.Api.new()
	var clock := Fixtures.Clock.new()
	service.api = api
	service.clock_ms = clock.read
	root.add_child(service)
	service.set_process(false)
	service.set_identity(_identity())
	var context := Context.new()
	service.monitor_room("v2",ROOM,context,true)
	return {"service":service,"api":api,"clock":clock,"context":context}

func _run() -> void:
	await _separate_api_and_ordinary_heartbeat()
	await _null_context_holds()
	await _stable_and_replaced_context()
	await _retirement_same_epoch()
	print("Campaign presence contexts: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _separate_api_and_ordinary_heartbeat() -> void:
	var c := _case()
	c.service.monitor_room("v2",ROOM,c.context,false)
	await c.service.service()
	_check(c.context.calls.is_empty() and c.api.calls.size() == 1 and c.api.calls[0].path == "/v1/presence","Account heartbeat remains ordinary when campaign room presence is configured")
	await c.service.service()
	_check(c.context.calls.size() == 1 and c.context.calls[0].api.get_ref() == c.api and c.context.calls[0].envelope.path == "/v2/rooms/"+ROOM+"/presence","Only the exact room GET uses the retained context on Presence's own API")
	_check(c.service.view("v2",ROOM).state == "online" and c.api.player_id.is_empty() and c.api.device_token.is_empty(),"Valid scoped presence establishes status and clears idle credentials")
	c.context.retired = true
	_check(c.service.view("v2",ROOM).state != "online","Any supplied retired context hides stale online status even without the required flag")
	c.service.set_foreground(false)
	await c.service.service()
	_check(c.context.calls.size() == 1 and c.api.calls.back().path == "/v1/presence" and not c.api.calls.back().body.online,"Queued offline message still retires the old account lease after room context retirement")
	await _dispose(c)

func _null_context_holds() -> void:
	var c := _case()
	c.service.set_enabled(false)
	c.service.monitor_room("v2",ROOM,null,true)
	await c.service.service()
	_check(c.api.calls.is_empty() and c.service.view("v2",ROOM).state != "online","Required context resolver failure sends no ordinary room GET")
	c.service.monitor_room("v2",ROOM)
	await c.service.service()
	_check(c.api.calls.size() == 1 and c.service.view("v2",ROOM).state == "online","Existing two-argument ordinary API remains available when explicitly configured")
	await _dispose(c)

func _stable_and_replaced_context() -> void:
	var c := _case()
	c.service.set_enabled(false)
	c.api.held = true
	c.service.service()
	var generation: int = c.service._room_generation
	c.service.monitor_room("v2",ROOM,c.context,true)
	_check(c.service._room_generation == generation and c.context.calls.size() == 1 and c.api.busy,"Repeated synchronization with one stable context does not cancel its in-flight read")
	var next := Context.new()
	next.room = OTHER
	c.service.monitor_room("v2",OTHER,next,true)
	c.api.release.emit()
	await process_frame
	_check(c.service.view("v2",OTHER).state == "checking" and c.api.calls.size() == 1,"Late prior-room result cannot update the replacement badge")
	c.api.held = false
	await c.service.service()
	_check(next.calls.size() == 1 and c.api.calls.back().path == "/v2/rooms/"+OTHER+"/presence","Replacement context uses its own room on the same independent API")
	await _dispose(c)

func _retirement_same_epoch() -> void:
	var c := _case()
	c.service.set_enabled(false)
	c.context.hold = true
	c.service.service()
	var held: WeakRef = weakref(c.context)
	c.context.retired = true
	c.service.monitor_room("", "")
	c.context = null
	_check(held.get_ref() != null,"Presence request retains context after visible-room fields release it")
	held.get_ref().release.emit()
	await process_frame
	_check(c.api.calls.is_empty() and not c.service._busy and c.api.player_id.is_empty() and c.api.device_token.is_empty(),"Same-epoch retired context drains without room dispatch or retained credentials")
	await _dispose(c)

func _dispose(c: Dictionary) -> void:
	c.service.queue_free()
	await process_frame
