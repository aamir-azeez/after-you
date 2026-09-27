extends RefCounted
## Retained control sessions must not keep their owner alive through a callback.
var _owner: WeakRef
var _binding: Dictionary = {}
var _purpose := "control"
var _coordinator: WeakRef

func _init(owner: RefCounted, binding: Dictionary, purpose: String = "control") -> void:
	_owner = weakref(owner)
	_binding = binding.duplicate(true)
	_purpose = purpose

func request(value: Dictionary) -> Dictionary:
	var owner: RefCounted = _owner.get_ref()
	if owner == null: return {"ok":false,"status":0,"code":"campaign_context_changed"}
	if _purpose == "control": return await owner.dispatch_campaign_request(_binding,"control",value)
	var coordinator: RefCounted = _coordinator.get_ref() if _coordinator != null else null
	return await owner.dispatch_child_request(_binding,_purpose,coordinator,value)

func bind_coordinator(value: RefCounted) -> void:
	if _coordinator == null and value != null: _coordinator = weakref(value)

func permits_live() -> bool:
	var owner: RefCounted = _owner.get_ref()
	var coordinator: RefCounted = _coordinator.get_ref() if _coordinator != null else null
	return owner != null and owner.child_live_allowed(_binding,_purpose,coordinator)

func recovery_only() -> bool:
	var owner: RefCounted = _owner.get_ref()
	var coordinator: RefCounted = _coordinator.get_ref() if _coordinator != null else null
	return owner == null or not owner.child_live_allowed(_binding,_purpose,coordinator,false)
