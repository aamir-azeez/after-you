extends Node
## Deterministic transport test double. Never used by the application.
var player_id := "host"
var base_url := ""
var device_token := "test-device-token"
var busy := false
var calls: Array = []
var responses: Array = []
## Runs as each request is made, so a test can look at the app mid-request.
var on_call: Callable

func configured() -> bool:
	return true

func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
	calls.append({"method": method, "path": path, "body": body.duplicate(true)})
	if on_call.is_valid(): on_call.call()
	return responses.pop_front() if not responses.is_empty() else {"ok": false, "status": 0, "error": "Injected transport interruption", "code": "connection_interrupted"}
