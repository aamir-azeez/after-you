extends RefCounted
## Photo, presence, safety and replay requests for one chapter room, made by the
## identity that opened them. Retained targets never select a gameplay room or
## keep the online session alive. A room the server answered as an old Story
## room (RelayOnlineSession.archived_room_kind) is held, never read as ordinary.
const Canonical = preload("res://core/v2/canonical.gd")
const RoomStages = preload("res://services/room_stages.gd")
const Typed = preload("res://services/typed_values.gd")
var _online: WeakRef
var _lifetime: Dictionary = {}
var _contexts: Dictionary = {}

class Target extends RefCounted:
	var factory: RefCounted
	var binding: Dictionary
	func _init(source: RefCounted, value: Dictionary) -> void:
		factory = source
		binding = value.duplicate(true)
	func current() -> bool: return factory.target_current(binding)
	func request(value: Dictionary) -> Dictionary:
		return await factory.dispatch(binding,value)
	func request_on(api: Node, identity: Callable, value: Dictionary) -> Dictionary:
		return await factory.dispatch(binding,value,api,identity)

func _init(online: RefCounted, lifetime: Dictionary) -> void:
	_online = weakref(online) if online != null else null
	_lifetime = lifetime.duplicate(true)

func current() -> bool:
	var online: RefCounted = _online.get_ref() if _online != null else null
	return online != null and online.auxiliary_lifetime_current(_lifetime)

func target_current(binding: Dictionary) -> bool:
	# This also protects cached UI and post-await writes.
	return current() and binding.get("kind") == "ordinary"

func for_room(room_id: String, purpose: String) -> RefCounted:
	var binding := {"room_id":room_id,"purpose":purpose,"kind":"held"}
	if current() and _id(room_id) and purpose in ["photo","presence","safety","replay"]:
		binding.kind = _kind(room_id)
	var key := Canonical.digest(binding)
	# Weak cache preserves a stable in-flight Presence target without cycles.
	if _contexts.has(key):
		var existing: RefCounted = _contexts[key].get_ref()
		if existing != null: return existing
	var result := Target.new(self,binding)
	_contexts[key] = weakref(result)
	if _contexts.size() > 256:
		for old: String in _contexts.keys():
			if _contexts[old].get_ref() == null: _contexts.erase(old)
	return result

func _kind(room_id: String) -> String:
	var online: RefCounted = _online.get_ref() if _online != null else null
	return "ordinary" if online != null and online.archived_room_kind(room_id) != "story" else "held"

func _authorized(binding: Dictionary) -> bool:
	return target_current(binding) and _kind(binding.room_id) == "ordinary"

func dispatch(binding: Dictionary, value: Dictionary, external_api: Node = null, external_identity: Callable = Callable()) -> Dictionary:
	if not _authorized(binding): return _held("campaign_context_changed")
	if not _route(binding,value): return _held("campaign_route_unavailable")
	var online: RefCounted = _online.get_ref()
	if online == null: return _held("identity_changed")
	var external := {}
	if external_api != null:
		external = _external_binding(external_api,external_identity)
		if external.is_empty(): return _held("campaign_context_changed")
	var response: Dictionary
	if external_api != null: response = await external_api.request_json(value.method,value.path,value.body)
	elif binding.purpose == "safety": response = await online.auxiliary_safety_transport(value)
	elif binding.purpose == "photo" and delivery_ack(value): response = await online.auxiliary_photo_ack_transport(value)
	else: response = await online.transport(value)
	if not current(): return _held("identity_changed")
	if external_api != null and not Typed.same(external,_external_binding(external_api,external_identity)): return _held("identity_changed")
	if not _authorized(binding): return _held("campaign_context_changed")
	return response

func _external_binding(api: Node, identity: Callable) -> Dictionary:
	if not is_instance_valid(api) or not identity.is_valid(): return {}
	var value: Variant = identity.call()
	if not value is Dictionary or value.get("ready") != true or value.get("player_id") != _lifetime.owner or value.get("epoch") != _lifetime.epoch: return {}
	if str(api.player_id) != _lifetime.owner or str(api.device_token).sha256_text() != _lifetime.device_hash or str(api.base_url) != _lifetime.base_url: return {}
	return {"player_id":str(api.player_id),"epoch":value.epoch,"device_hash":str(api.device_token).sha256_text(),"base_url":str(api.base_url)}

func _route(binding: Dictionary, value: Dictionary) -> bool:
	if not _exact(value,["owner_player_id","identity_epoch","method","path","body"]) or value.owner_player_id != _lifetime.owner or value.identity_epoch != _lifetime.epoch or not value.path is String or not value.body is Dictionary or not _integer(value.method,0,8): return false
	var root_path: String = "/v2/rooms/"+binding.room_id
	var path: String = value.path
	var method: int = int(value.method)
	if method == HTTPClient.METHOD_GET and not value.body.is_empty(): return false
	match binding.purpose:
		"presence": return method == HTTPClient.METHOD_GET and path == root_path+"/presence"
		"replay":
			return method == HTTPClient.METHOD_GET and (path == root_path or path == root_path+"/collection" or path == root_path+"/tries" or path == root_path+"/end-reactions" or _suffix(path,root_path+"/pairs/","^p([0-9]|[12][0-9]|3[01])-"+RoomStages.DIGIT+"$"))
		"safety":
			return method == HTTPClient.METHOD_POST and path in ["/v1/safety/block","/v1/safety/report"] and value.body.get("room_family") == "relay" and value.body.get("room_id") == binding.room_id
		"photo":
			if method == HTTPClient.METHOD_GET and (_suffix(path,root_path+"/operations/","^[A-Za-z0-9_-]{16,80}$") or _suffix(path,root_path+"/photo-operations/","^[A-Za-z0-9_-]{16,80}$")): return true
			if not path.begins_with(root_path+"/photos/"): return false
			var tail := path.trim_prefix(root_path+"/photos/")
			var turn := tail.get_slice("/",0)
			if RegEx.create_from_string(RoomStages.TURN_ID).search(turn) == null: return false
			if tail == turn: return method in [HTTPClient.METHOD_GET,HTTPClient.METHOD_POST,HTTPClient.METHOD_DELETE]
			return (tail == turn+"/delivery" and method == HTTPClient.METHOD_GET) or (tail == turn+"/ack" and delivery_ack(value))
	return false

func _suffix(path: String, prefix: String, pattern: String) -> bool:
	return path.begins_with(prefix) and RegEx.create_from_string(pattern).search(path.trim_prefix(prefix)) != null

static func _held(code: String) -> Dictionary:
	return {"ok":false,"ignored":true,"status":0,"code":code}

static func delivery_ack(value: Dictionary) -> bool:
	if value.get("method") != HTTPClient.METHOD_POST or not _matches(value.get("path"),"^/v2/rooms/[A-Za-z0-9_-]{22}/photos/" + RoomStages.TURN_ID.trim_prefix("^").trim_suffix("$") + "/ack$"): return false
	var body: Variant = value.get("body")
	return _exact(body,["photo_revision","sha256","recording_hash"]) and _integer(body.photo_revision,1,1000000) and _matches(body.sha256,"^[a-f0-9]{64}$") and _matches(body.recording_hash,"^[a-f0-9]{64}$")

static func _exact(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size(): return false
	for field: Variant in value:
		if field not in fields: return false
	return true

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func _matches(value: Variant, expression: String) -> bool:
	return value is String and RegEx.create_from_string(expression).search(value) != null

static func _id(value: Variant) -> bool: return _matches(value,"^[A-Za-z0-9_-]{22}$")
