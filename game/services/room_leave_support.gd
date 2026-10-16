extends RefCounted
## Whether the server lets a member leave a finished room (capability
## room_leave_version 1). It reads only that field of /v2/capabilities, once per
## identity, through the API's request queue. The relay session's own
## capabilities are left alone: loading those clears its room lists.
const Typed = preload("res://services/typed_values.gd")

var _supported := false
var _identity := ""
var _reading := false

## The answer last read for this identity; false until one is read.
func offered(identity: String) -> bool:
	return _supported and not identity.is_empty() and identity == _identity

## Reads the answer unless this identity already has one. A failed read leaves
## it unknown, so the next call asks again.
func read(api: Node, identity: String, current: Callable) -> void:
	if identity.is_empty() or identity == _identity or _reading: return
	_reading = true
	var response: Dictionary = await api.request_json(HTTPClient.METHOD_GET,"/v2/capabilities")
	_reading = false
	var data: Variant = response.get("data")
	if not current.call() or not response.get("ok",false) or not data is Dictionary: return
	_supported = Typed.equal(data.get("room_leave_version"), 1.0)
	_identity = identity

## After a refused or failed leave: the next read asks the server again.
func forget() -> void:
	_identity = ""
