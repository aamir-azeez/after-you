extends RefCounted
## Retained control sessions must not keep their owner alive through a callback.
var _owner: WeakRef
var _binding: Dictionary = {}

func _init(owner: RefCounted, binding: Dictionary) -> void:
	_owner = weakref(owner)
	_binding = binding.duplicate(true)

func request(value: Dictionary) -> Dictionary:
	var owner: RefCounted = _owner.get_ref()
	if owner == null: return {"ok":false,"status":0,"code":"campaign_context_changed"}
	return await owner.dispatch_campaign_request(_binding,"control",value)
