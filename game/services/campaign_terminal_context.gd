extends RefCounted
## Retains transport lifetime without retaining the Owner or Online service.
var _owner: WeakRef
var _online: WeakRef
var _lifetime: Dictionary

func _init(owner: RefCounted, online: RefCounted, lifetime: Dictionary) -> void:
	_owner = weakref(owner)
	_online = weakref(online)
	_lifetime = lifetime.duplicate(true)

func current() -> bool:
	var owner: RefCounted = _owner.get_ref()
	var online: RefCounted = _online.get_ref()
	return owner != null and online != null and online.terminal_lifetime_current(_lifetime,owner)

func request(value: Dictionary) -> Dictionary:
	var owner: RefCounted = _owner.get_ref()
	if owner == null or not current(): return {"ok":false,"ignored":true,"status":0,"code":"campaign_context_changed"}
	return await owner.dispatch_terminal_request(self,value)
