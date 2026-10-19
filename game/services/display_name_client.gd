extends RefCounted
## Sends this player's display name choice to the server (PUT /v1/profile/name)
## and records the answer in DisplayNames. One send at a time; a choice made
## while one is out goes as soon as it returns. A send that fails for the
## network or a server pause stays pending and goes again on flush().
const DisplayNames = preload("res://services/display_names.gd")
const Presence = preload("res://services/friend_presence.gd")
const Typed = preload("res://services/typed_values.gd")
const PATH := "/v1/profile/name"
## How long Save waits for the server before it closes and sends later.
const SAVE_WAIT_MS := 2000
## Codes that refuse the name itself. Any other failure is sent again later.
const REFUSALS := ["invalid_display_name", "display_name_refused", "display_name_limited", "display_name_locked"]

## A send came back: {"ok", "code"} as DisplayNames recorded it.
signal settled(answer: Dictionary)

var names: RefCounted
var _api: Node
var _identity: Callable
var _transport: Callable
var _sending := false

## transport(method, path, body) -> response, for tests; else the API's queue.
func _init(api: Node, identity: Callable, transport: Callable = Callable(), store: RefCounted = null) -> void:
	_api = api
	_identity = identity
	_transport = transport
	names = store if store != null else DisplayNames.shared()

## {server, owner} of the signed-in player, or {}.
func scope() -> Dictionary:
	var value: Variant = _identity.call() if _identity.is_valid() else null
	if not value is Dictionary or value.get("ready") != true or not Presence.valid_id(value.get("player_id")): return {}
	if not is_instance_valid(_api) or _api.player_id != value.player_id or str(_api.device_token).is_empty(): return {}
	return {"server": str(_api.base_url), "owner": str(value.player_id)}

func sending() -> bool:
	return _sending

## Sends the pending choice and waits at most wait_ms for the answer.
## {"done": true, "ok", "code"} once the server answered, else {"done": false}
## (still out, or kept to send later).
func send(wait_ms: int = SAVE_WAIT_MS) -> Dictionary:
	var context := scope()
	if context.is_empty(): return {"done": false}
	var mine: Dictionary = names.own(context.server, context.owner)
	if mine.state != DisplayNames.PENDING: return {"done": true, "ok": mine.state == DisplayNames.SYNCED, "code": str(mine.code)}
	if not _sending: _start(context)
	var tree := _api.get_tree() if is_instance_valid(_api) and _api.is_inside_tree() else null
	var deadline := Time.get_ticks_msec() + wait_ms
	while _sending and tree != null and Time.get_ticks_msec() < deadline: await tree.process_frame
	var now: Dictionary = names.own(context.server, context.owner)
	if int(now.revision) != int(mine.revision) or now.state == DisplayNames.PENDING: return {"done": false}
	return {"done": true, "ok": now.state == DisplayNames.SYNCED, "code": str(now.code)}

## Sends a choice still waiting, without waiting for it (after a friends read).
func flush() -> void:
	var context := scope()
	if context.is_empty() or _sending: return
	if names.own(context.server, context.owner).state == DisplayNames.PENDING: _start(context)

func _start(context: Dictionary) -> void:
	_sending = true
	var mine: Dictionary = names.own(context.server, context.owner)
	var revision := int(mine.revision)
	var body := {"schema_version": 1, "display_name": null if mine.choice == "anonymous" else str(mine.name), "revision": revision}
	var response: Dictionary = await _request(body)
	_sending = false
	if scope() != context: return
	var code := str(response.get("code", ""))
	var answer := {}
	var data: Variant = response.get("data")
	if response.get("ok", false) and data is Dictionary and Typed.equal(data.get("schema_version"), 1) and (data.get("display_name") == null or DisplayNames.valid_remote(data.get("display_name"))):
		answer = {"ok": true, "display_name": data.get("display_name")}
	elif not response.get("ok", false) and code in REFUSALS:
		answer = {"ok": false, "code": code}
	if not answer.is_empty():
		names.settle(context.server, context.owner, revision, answer)
		settled.emit({"ok": answer.ok, "code": code if not answer.ok else ""})
	# A newer choice made while this one was out goes now.
	var latest: Dictionary = names.own(context.server, context.owner)
	if latest.state == DisplayNames.PENDING and int(latest.revision) != revision: _start(context)

func _request(body: Dictionary) -> Dictionary:
	if _transport.is_valid(): return await _transport.call(HTTPClient.METHOD_PUT, PATH, body)
	return await _api.request_json(HTTPClient.METHOD_PUT, PATH, body)
