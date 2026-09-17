extends Node
## Deterministic transport test double. Never used by the application.
var player_id := "host"
var base_url := ""
var device_token := "test-device-token"
var busy := false
var calls: Array = []
var responses: Array = []

func configured() -> bool:
	return true

func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
	calls.append({"method": method, "path": path, "body": body.duplicate(true)})
	return responses.pop_front() if not responses.is_empty() else {"ok": false, "status": 0, "error": "Injected transport interruption", "code": "connection_interrupted"}
