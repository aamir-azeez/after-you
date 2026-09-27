extends RefCounted
## Retained target factories never select a gameplay room or keep its owner alive.
const Canonical = preload("res://core/v2/canonical.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
var _online: WeakRef
var _owner: WeakRef
var _lifetime: Dictionary = {}
var _contexts: Dictionary = {}

class Target extends RefCounted:
	var factory: RefCounted
	var binding: Dictionary
	func _init(source: RefCounted, value: Dictionary) -> void:
		factory = source
		binding = value.duplicate(true)
	func current() -> bool: return factory.current()
	func request(value: Dictionary) -> Dictionary:
		return await factory.dispatch(binding,value)
	func request_on(api: Node, identity: Callable, value: Dictionary) -> Dictionary:
		return await factory.dispatch(binding,value,api,identity)

func _init(online: RefCounted, owner: RefCounted, lifetime: Dictionary) -> void:
	_online = weakref(online) if online != null else null
	_owner = weakref(owner) if owner != null else null
	_lifetime = lifetime.duplicate(true)

func current() -> bool:
	var online: RefCounted = _online.get_ref() if _online != null else null
	var owner: RefCounted = _owner.get_ref() if _owner != null else null
	return online != null and online.auxiliary_lifetime_current(_lifetime,owner)

func for_room(room_id: String, purpose: String) -> RefCounted:
	var binding := {"room_id":room_id,"purpose":purpose,"kind":"held"}
	if current() and Protocol.id_valid(room_id) and purpose in ["photo","presence","safety","replay"]:
		var owner: RefCounted = _owner.get_ref() if _owner != null else null
		var detail: Dictionary = owner.auxiliary_room_binding(room_id) if owner != null else {"kind":"ordinary"}
		binding.merge(detail,true)
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

func _authority(binding: Dictionary) -> Dictionary:
	if not current() or binding.kind == "held": return {}
	var owner: RefCounted = _owner.get_ref() if _owner != null else null
	var detail: Dictionary = owner.auxiliary_room_binding(binding.room_id) if owner != null else {"kind":"ordinary"}
	if detail.get("kind") != binding.kind: return {}
	if binding.kind == "ordinary": return detail
	if not Canonical.same(detail.get("reference"),binding.get("reference")) or not Canonical.same(detail.get("pin"),binding.get("pin")): return {}
	return detail

func dispatch(binding: Dictionary, value: Dictionary, external_api: Node = null, external_identity: Callable = Callable()) -> Dictionary:
	var authority := _authority(binding)
	if authority.is_empty(): return _held("campaign_context_changed")
	if not _route(binding,value): return _held("campaign_route_unavailable")
	var online: RefCounted = _online.get_ref()
	if online == null: return _held("identity_changed")
	var external := {}
	if external_api != null:
		external = _external_binding(external_api,external_identity)
		if external.is_empty() or external_api.busy: return _held("campaign_context_changed")
	var response: Dictionary
	if external_api != null:
		if authority.kind == "campaign":
			if not external_api.has_method("request_campaign_json"): return _held("campaign_transport_unavailable")
			response = await external_api.request_campaign_json(value.method,value.path,value.body)
		else: response = await external_api.request_json(value.method,value.path,value.body)
	else:
		if binding.purpose == "safety": response = await online.auxiliary_safety_transport(value,authority.kind == "campaign")
		elif binding.purpose == "photo" and delivery_ack(value): response = await online.auxiliary_photo_ack_transport(value,authority.kind == "campaign")
		else: response = await online.campaign_transport(value) if authority.kind == "campaign" else await online.transport(value)
	if not current(): return _held("identity_changed")
	if external_api != null and not Canonical.same(external,_external_binding(external_api,external_identity)): return _held("identity_changed")
	var after := _authority(binding)
	if after.is_empty(): return _held("campaign_context_changed")
	if authority.kind == "campaign":
		# Selection may advance. The exact target's membership cannot change under
		# an outstanding response, including a nested accepted-turn receipt.
		for field: String in ["host_id","guest_id","player_slot"]:
			if authority.publication.get(field) != after.publication.get(field): return _held("campaign_context_changed")
		if response.get("ok") == true and not _response_matches(binding,after,response,value): return _held("campaign_room_mismatch")
	return response

func _external_binding(api: Node, identity: Callable) -> Dictionary:
	if not is_instance_valid(api) or not identity.is_valid(): return {}
	var value: Variant = identity.call()
	if not value is Dictionary or value.get("ready") != true or value.get("player_id") != _lifetime.owner or value.get("epoch") != _lifetime.epoch: return {}
	if str(api.player_id) != _lifetime.owner or str(api.device_token).sha256_text() != _lifetime.device_hash or str(api.base_url) != _lifetime.base_url: return {}
	return {"player_id":str(api.player_id),"epoch":value.epoch,"device_hash":str(api.device_token).sha256_text(),"base_url":str(api.base_url)}

func _route(binding: Dictionary, value: Dictionary) -> bool:
	if not Protocol.exact(value,["owner_player_id","identity_epoch","method","path","body"]) or value.owner_player_id != _lifetime.owner or value.identity_epoch != _lifetime.epoch or not value.path is String or not value.body is Dictionary or not Protocol.integer(value.method,0,8): return false
	var root_path: String = "/v2/rooms/"+binding.room_id
	var path: String = value.path
	var method: int = int(value.method)
	if method == HTTPClient.METHOD_GET and not value.body.is_empty(): return false
	match binding.purpose:
		"presence": return method == HTTPClient.METHOD_GET and path == root_path+"/presence"
		"replay":
			return method == HTTPClient.METHOD_GET and (path == root_path or path == root_path+"/collection" or _suffix(path,root_path+"/pairs/","^p([0-9]|[12][0-9]|3[01])-[01]$"))
		"safety":
			return method == HTTPClient.METHOD_POST and path in ["/v1/safety/block","/v1/safety/report"] and value.body.get("room_family") == "relay" and value.body.get("room_id") == binding.room_id
		"photo":
			if method == HTTPClient.METHOD_GET and (_suffix(path,root_path+"/operations/","^[A-Za-z0-9_-]{16,80}$") or _suffix(path,root_path+"/photo-operations/","^[A-Za-z0-9_-]{16,80}$")): return true
			if not path.begins_with(root_path+"/photos/"): return false
			var tail := path.trim_prefix(root_path+"/photos/")
			var turn := tail.get_slice("/",0)
			if RegEx.create_from_string("^t([0-9]|[12][0-9]|3[01])-[01]-[ab]$").search(turn) == null: return false
			if tail == turn: return method in [HTTPClient.METHOD_GET,HTTPClient.METHOD_POST,HTTPClient.METHOD_DELETE]
			return (tail == turn+"/delivery" and method == HTTPClient.METHOD_GET) or (tail == turn+"/ack" and delivery_ack(value))
	return false

func _suffix(path: String, prefix: String, pattern: String) -> bool:
	return path.begins_with(prefix) and RegEx.create_from_string(pattern).search(path.trim_prefix(prefix)) != null

func _response_matches(binding: Dictionary, authority: Dictionary, response: Dictionary, request: Dictionary) -> bool:
	var root_path: String = "/v2/rooms/"+binding.room_id
	var room: Variant = null
	if request.path == root_path: room = response.get("data")
	elif binding.purpose == "photo" and request.path.begins_with(root_path+"/operations/"):
		var data: Variant = response.get("data")
		room = data.get("room") if data is Dictionary else null
	else: return true
	var owner: RefCounted = _owner.get_ref() if _owner != null else null
	return owner != null and owner.auxiliary_room_matches(room,binding,authority.publication)

static func _held(code: String) -> Dictionary:
	return {"ok":false,"ignored":true,"status":0,"code":code}

static func delivery_ack(value: Dictionary) -> bool:
	if value.get("method") != HTTPClient.METHOD_POST or not Protocol.matches(value.get("path"),"^/v2/rooms/[A-Za-z0-9_-]{22}/photos/t([0-9]|[12][0-9]|3[01])-[01]-[ab]/ack$"): return false
	var body: Variant = value.get("body")
	return Protocol.exact(body,["photo_revision","sha256","recording_hash"]) and Protocol.integer(body.photo_revision,1,1000000) and Protocol.matches(body.sha256,"^[a-f0-9]{64}$") and Protocol.matches(body.recording_hash,"^[a-f0-9]{64}$")
