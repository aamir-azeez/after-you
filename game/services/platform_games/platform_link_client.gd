extends RefCounted
## The server half of platform games: is it offered, link, unlink and restore. Speaks through the
## app's one RoomsApi (its queue, identity checks and error shapes); never stores credentials.
const Typed = preload("res://services/typed_values.gd")

const CAPABILITY_HEADER := "X-AfterYou-Platform-Games: 1"
const WEB_CLIENT_ID := "^[0-9]{6,20}-[a-z0-9]{8,64}\\.apps\\.googleusercontent\\.com$"
const PLAYER_ID := "^[a-zA-Z0-9_-]{22}$"

var _api: Node

func _init(api: Node) -> void:
	_api = api

## What this server offers, read with the opt-in header: {"ok", "play_games", "web_client_id", "game_center"}.
func capability() -> Dictionary:
	if _api == null: return {"ok": false, "code": "unavailable"}
	var response: Dictionary = await _api.request_json_with_headers(HTTPClient.METHOD_GET, "/v2/capabilities", {}, PackedStringArray([CAPABILITY_HEADER]))
	if not response.get("ok", false) or not response.get("data") is Dictionary: return {"ok": false, "code": _code(response)}
	var data: Dictionary = response.data
	var client: Variant = data.get("play_games_web_client_id")
	var play: bool = Typed.equal(data.get("play_games_version"), 1) and client is String and RegEx.create_from_string(WEB_CLIENT_ID).search(client) != null
	return {"ok": true, "play_games": play, "web_client_id": client if play else "", "game_center": Typed.equal(data.get("game_center_version"), 1)}

## {"ok", "status": linked | conflict | other_account, "changed"} or {"ok": false, "code"}.
## The recovery code proves this phone may set up a restore for its identity (a device token alone may not).
func link(provider: String, credential: Dictionary, replace: bool, recovery_code: String) -> Dictionary:
	var body := {"schema_version": 1, "provider": provider, "credential": credential, "recovery_code": recovery_code}
	if replace: body.replace = true
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, "/v1/platform/link", body)
	if not response.get("ok", false): return {"ok": false, "code": _code(response), "status": int(response.get("status", 0))}
	var data: Dictionary = response.data
	var status: Variant = data.get("status")
	if not Typed.equal(data.get("provider"), provider) or not status is String or status not in ["linked", "conflict", "other_account"] or not data.get("changed") is bool:
		return {"ok": false, "code": "invalid_response", "status": 200}
	return {"ok": true, "status": status, "changed": data.changed}

func unlink(provider: String) -> Dictionary:
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, "/v1/platform/unlink", {"schema_version": 1, "provider": provider})
	if not response.get("ok", false): return {"ok": false, "code": _code(response), "status": int(response.get("status", 0))}
	return {"ok": true, "unlinked": Typed.equal(response.data.get("unlinked"), true)}

## Moves the linked identity to the credentials this phone proposed (held in `pending` and saved
## securely before this call). {"ok", "player_id"} or {"ok": false, "code", "status"}.
func restore(provider: String, credential: Dictionary, pending: Dictionary) -> Dictionary:
	var body := {"schema_version": 1, "provider": provider, "credential": credential, "idempotency_key": pending.idempotency_key,
		"next_device_token": pending.next_device_token, "next_recovery_code": pending.next_recovery_code}
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, "/v1/platform/restore", body)
	if not response.get("ok", false): return {"ok": false, "code": _code(response), "status": int(response.get("status", 0))}
	var data: Dictionary = response.data
	var player: Variant = data.get("player_id")
	if not Typed.equal(data.get("restored"), true) or not player is String or RegEx.create_from_string(PLAYER_ID).search(player) == null:
		return {"ok": false, "code": "invalid_response", "status": 200}
	return {"ok": true, "player_id": player}

## A transport failure (status 0) reads "offline"; otherwise the server's code.
static func _code(response: Dictionary) -> String:
	if int(response.get("status", 0)) == 0: return "offline"
	return str(response.get("code", "failed"))
