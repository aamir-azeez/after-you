extends SceneTree
const Client = preload("res://services/friend_room_events_client.gd")
var player_id := "aaaaaaaaaaaaaaaaaaaaaa"
var friend_id := "bbbbbbbbbbbbbbbbbbbbbb"
var request_id := "cccccccccccccccccccccc"
var ready := true
var change_context := false
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
	check(not Client.valid_inbox({"schema_version":1,"available":false,"events":[],"preferences":[],"extra":true}),"rejects unknown inbox response fields")
	var malformed_event: Dictionary = event.duplicate(true); malformed_event.room.extra = true
	check(not Client.valid_event(malformed_event),"rejects malformed nested room reference")

	# A lost response keeps the same publication id for the next client instance.
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

	next_response = {"ok":true,"data":inbox}
	var fetched: Dictionary = await client.inbox()
	check(fetched.get("ok",false) and calls[2].path == "/v1/social/inbox" and calls[2].method == HTTPClient.METHOD_GET,"inbox is an explicit authenticated GET")
	next_response = {"ok":true,"data":{"schema_version":1,"acknowledged":true,"request_id":request_id}}
	check(await client.acknowledge_rendered(event),"acknowledges a valid event only through explicit caller method")
	check(calls[3].path == "/v1/friends/"+friend_id+"/notifications" and calls[3].body.action == "ack","ack includes event and friendship token")
	next_response = {"ok":true,"data":{"schema_version":1,"subscribed":true,"request_id":request_id}}
	check(await client.set_hosting_alert({"player_id":friend_id,"request_id":request_id,"status":"accepted"},true),"accepts subscribe acknowledgement bound to request id")
	check(calls[4].body.action == "subscribe","subscribe sets hosting alert only")
	next_response = {"ok":true,"data":{"schema_version":1,"subscribed":false,"request_id":request_id}}
	check(await client.set_hosting_alert({"player_id":friend_id,"request_id":request_id},false),"accepts unsubscribe acknowledgement")
	check(calls[5].body.action == "unsubscribe","unsubscribe remains a separate explicit action")
	next_response = {"ok":true,"data":{"schema_version":1,"subscribed":true,"request_id":"eeeeeeeeeeeeeeeeeeeeee"}}
	check(not await client.set_hosting_alert({"player_id":friend_id,"request_id":request_id},true),"rejects acknowledgement for a stale friendship token")
	check(not await client.acknowledge_rendered({"event_id":friend_id+"_4","player_id":friend_id,"request_id":request_id}),"rejects incomplete event acknowledgement")

	# An identity change while a request is in flight must discard its response.
	change_context = true
	next_response = {"ok":true,"data":inbox}
	var safe_response: Dictionary = await client.inbox()
	check(not safe_response.get("ok",false) and safe_response.get("code") == "context_changed","drops a response after identity context changes")
	if failures == 0: print("FRIEND_ROOM_EVENTS_CLIENT_TESTS_PASSED")
	quit(1 if failures else 0)

var failures := 0
func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error(label)
