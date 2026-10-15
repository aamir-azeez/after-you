extends SceneTree
const Client = preload("res://services/friend_room_events_client.gd")
var player_id := "aaaaaaaaaaaaaaaaaaaaaa"
var friend_id := "bbbbbbbbbbbbbbbbbbbbbb"
var request_id := "cccccccccccccccccccccc"
var ready := true
var change_context := false
## Holds the next reply until released is emitted (a slow network).
var hold := false
signal released
var next_response: Dictionary = {}
var calls: Array[Dictionary] = []
var api: FakeApi
var client: RefCounted

class FakeApi:
	extends Node
	var base_url := "https://social.example.test"
	var player_id := "aaaaaaaaaaaaaaaaaaaaaa"
	var device_token := "local-test-credential"
	var busy := false

func _initialize() -> void: _run.call_deferred()

func identity() -> Dictionary:
	return {"ready":ready,"player_id":player_id,"epoch":1 if not change_context else 2}

func transport(method: int, path: String, body: Dictionary) -> Dictionary:
	calls.append({"method":method,"path":path,"body":body.duplicate(true)})
	if hold:
		hold = false
		await released
	if change_context: change_context = false; player_id = friend_id
	return next_response.duplicate(true)

func _run() -> void:
	api = FakeApi.new()
	root.add_child(api)
	client = Client.new(api,identity,transport)
	var room := {"api_version":2,"room_id":"dddddddddddddddddddddd"}
	check(Client.valid_room(room),"accepts a shared room reference")
	check(not Client.valid_room({"api_version":3,"room_id":room.room_id}),"rejects unknown room families")
	check(Client.new_publication_id().length() == 22,"publication ID uses 16-byte base64url form")
	check(Client.valid_publication_id("Abcdefghijklmnopqrstuv"),"validates publication IDs")
	check(not Client.valid_publication_id("bad/id"),"rejects malformed publication IDs")
	check(Client.valid_publication_ack({"schema_version":1,"publication_epoch":2,"queued":20}),"validates bounded publication acknowledgement")
	check(not Client.valid_publication_ack({"schema_version":1,"publication_epoch":2,"queued":21}),"rejects oversized queue count")
	var event := {"event_id":friend_id+"_4","category":"room_available","player_id":friend_id,"request_id":request_id,"publication_epoch":4,"room":room,"published_at":1780000000000}
	var preference := {"player_id":friend_id,"request_id":request_id,"enabled":true}
	var inbox := {"schema_version":1,"available":true,"events":[event],"preferences":[preference]}
	check(Client.valid_inbox(inbox),"validates event and preference inbox projections")
	# The real API parses every JSON number as a float (2.0, 4.0).
	var parsed: Variant = JSON.parse_string(JSON.stringify(inbox))
	check(parsed.events[0].room.api_version is float and Client.valid_inbox(parsed),"accepts a hosting event exactly as the parsed server reply carries it")
	check(Client.valid_room(JSON.parse_string(JSON.stringify(room))),"accepts a parsed room reference with a float version")
	var wrong_epoch: Dictionary = parsed.events[0].duplicate(true); wrong_epoch.event_id = friend_id+"_4.0"
	check(not Client.valid_event(wrong_epoch),"still requires the server's integer event id")
	check(not Client.valid_room({"api_version":2.5,"room_id":room.room_id}),"rejects a fractional room version")
	check(not Client.valid_inbox({"schema_version":1,"available":false,"events":[],"preferences":[],"extra":true}),"rejects unknown inbox response fields")
	var malformed_event: Dictionary = event.duplicate(true); malformed_event.room.extra = true
	check(not Client.valid_event(malformed_event),"rejects malformed nested room reference")

	# A lost response keeps the same publication id for the next client instance.
	check(client.owe(room),"a hosted room owes its alert before any request")
	next_response = {"ok":false,"code":"network_error"}
	var first: Dictionary = await client.publish(room)
	check(not first.get("ok",false) and calls.size() == 1,"failed publication is returned to caller without throwing")
	var publication_id: String = calls[0].body.publication_id
	check(Client.valid_publication_id(publication_id),"publication uses a valid idempotency key")
	client = Client.new(api,identity,transport)
	next_response = {"ok":true,"data":{"schema_version":1,"publication_epoch":1,"queued":0}}
	var published: Dictionary = await client.publish(room)
	check(published.get("ok",false) and calls[1].body.publication_id == publication_id,"retry reuses durable idempotency key")
	check(calls[1].path == "/v1/social/publication" and calls[1].body.room == room,"publication sends the strict endpoint request shape")

	# An owed alert is saved before any request and survives a restart.
	check(not client.owes(room),"a sent alert is no longer owed")
	check(client.owe(room) and client.owes(room),"a hosted room owes one alert")
	var owed_id: String = client._pending_publication_id
	client = Client.new(api,identity,transport)
	check(client.owes({"api_version":2.0,"room_id":room.room_id}),"the owed alert survives a restart, whatever the number type")
	next_response = {"ok":true,"data":{"schema_version":1,"publication_epoch":2,"queued":1}}
	await client.publish(room)
	check(calls.back().body.publication_id == owed_id and not client.owes(room),"the owed alert goes out with the id saved when it became owed")
	# A slow reply: a second publish meanwhile sends nothing, the alert goes out
	# once under its saved id, and once it lands nothing is sent again.
	var sent_before := calls.size()
	client.owe(room)
	var slow_id: String = client._pending_publication_id
	hold = true
	next_response = {"ok":true,"data":{"schema_version":1,"publication_epoch":3,"queued":0}}
	var results: Array = []
	var send := func(target: Dictionary) -> void: results.append(await client.publish(target))
	send.call(room)
	await client.publish(room)
	check(calls.size() == sent_before+1,"a second publish while the alert is on its way sends nothing")
	released.emit()
	await process_frame
	check(results.size() == 1 and results[0].get("ok",false) and not client.owes(room),"the slow alert lands")
	await client.publish(room)
	check(calls.size() == sent_before+1 and calls.back().body.publication_id == slow_id,"the alert went out exactly once, under its saved id, and is not sent again after it lands")
	# Another room owed while one alert's reply is slow keeps its own alert.
	var other := {"api_version":2,"room_id":"eeeeeeeeeeeeeeeeeeeeee"}
	client.owe(room)
	hold = true
	results.clear()
	send.call(room)
	check(client.owe(other),"a new room owes its alert while the last one is on its way")
	var other_id: String = client._pending_publication_id
	released.emit()
	await process_frame
	check(results.size() == 1 and results[0].get("ok",false) and client.owes(other) and Client.new(api,identity,transport).owes(other),"the landed reply does not clear the newer room's alert")
	await client.publish(other)
	check(calls.back().body.publication_id == other_id and calls.back().body.room == other and not client.owes(other),"the newer room's alert goes out under its own id")
	client.owe(room)
	client.forget({"api_version":1,"room_id":room.room_id})
	check(client.owes(room),"forgetting another room keeps this room's alert")
	client.forget(room)
	check(not client.owes(room) and not Client.new(api,identity,transport).owes(room),"forgetting a closed room drops its alert on disk too")
	client.owe(room)
	client._pending_owed_at -= Client.OWED_TTL_S
	client._save_pending()
	client = Client.new(api,identity,transport)
	check(not client.owes(room) and not Client.new(api,identity,transport).owes(room),"an alert owed for a day or more is dropped")
	# 0.6.0 left a failed publication behind with no owed time: never sent later.
	var legacy := ConfigFile.new()
	legacy.load(Client.PENDING_PATH)
	var section: String = client._cache_section()
	legacy.set_value(section,"publication_id",Client.new_publication_id())
	legacy.set_value(section,"room",room)
	if legacy.has_section_key(section,"owed_at"): legacy.erase_section_key(section,"owed_at")
	legacy.save(Client.PENDING_PATH)
	client = Client.new(api,identity,transport)
	check(not client.owes(room),"a 0.6.0 leftover publication is not treated as owed")

	calls.clear()
	next_response = {"ok":true,"data":inbox}
	var fetched: Dictionary = await client.inbox()
	check(fetched.get("ok",false) and calls[0].path == "/v1/social/inbox" and calls[0].method == HTTPClient.METHOD_GET,"inbox is an explicit authenticated GET")
	check(client.hosting_preferences() == {friend_id:true},"the inbox read keeps the enabled hosting alerts for a reopened page")
	next_response = {"ok":true,"data":{"schema_version":1,"acknowledged":true,"request_id":request_id}}
	check(await client.acknowledge_rendered(event),"acknowledges a valid event only through explicit caller method")
	check(calls[1].path == "/v1/friends/"+friend_id+"/notifications" and calls[1].body.action == "ack","ack includes event and friendship token")
	next_response = {"ok":true,"data":{"schema_version":1,"subscribed":true,"request_id":request_id}}
	check(await client.set_hosting_alert({"player_id":friend_id,"request_id":request_id,"status":"accepted"},true),"accepts subscribe acknowledgement bound to request id")
	check(calls[2].body.action == "subscribe","subscribe sets hosting alert only")
	check(client.hosting_preferences() == {friend_id:true},"a saved subscribe is kept for a reopened page")
	next_response = {"ok":true,"data":{"schema_version":1,"subscribed":false,"request_id":request_id}}
	check(await client.set_hosting_alert({"player_id":friend_id,"request_id":request_id},false),"accepts unsubscribe acknowledgement")
	check(calls[3].body.action == "unsubscribe","unsubscribe remains a separate explicit action")
	check(client.hosting_preferences().is_empty(),"a saved unsubscribe clears the kept hosting alert")
	next_response = {"ok":true,"data":{"schema_version":1,"subscribed":true,"request_id":"eeeeeeeeeeeeeeeeeeeeee"}}
	check(not await client.set_hosting_alert({"player_id":friend_id,"request_id":request_id},true),"rejects acknowledgement for a stale friendship token")
	check(not await client.acknowledge_rendered({"event_id":friend_id+"_4","player_id":friend_id,"request_id":request_id}),"rejects incomplete event acknowledgement")

	next_response = {"ok":true,"data":inbox}
	await client.inbox()
	check(client.hosting_preferences() == {friend_id:true},"a later inbox read restores the kept hosting alerts")
	# An identity change while a request is in flight must discard its response.
	change_context = true
	next_response = {"ok":true,"data":inbox}
	var safe_response: Dictionary = await client.inbox()
	check(not safe_response.get("ok",false) and safe_response.get("code") == "context_changed","drops a response after identity context changes")
	check(client.hosting_preferences().is_empty(),"another identity never sees the previous identity's hosting alerts")
	if failures == 0: print("FRIEND_ROOM_EVENTS_CLIENT_TESTS_PASSED")
	quit(1 if failures else 0)

var failures := 0
func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error(label)
