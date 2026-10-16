extends SceneTree
const Client = preload("res://services/room_inbox_client.gd")
var ready := true
var epoch := 1
var response: Dictionary
var calls: Array = []
var client: RefCounted

class FakeApi:
	extends Node
	var base_url := "https://example.test"
	var player_id := "aaaaaaaaaaaaaaaaaaaaaa"
	var device_token := "token"
	var busy := false

func _initialize() -> void: _run.call_deferred()

var player := "aaaaaaaaaaaaaaaaaaaaaa"

func identity() -> Dictionary:
	return {"ready":ready,"player_id":player,"epoch":epoch}

func transport(method: int,path: String,body: Dictionary) -> Dictionary:
	calls.append({"method":method,"path":path,"body":body})
	return response

func room(id: String,sequence: int,at: int,status: String="your_turn") -> Dictionary:
	return {"api_version":1,"room_id":id,"chapter_key":"long-way-home","chapter_title":"Long Way Home","member_ids":["aaaaaaaaaaaaaaaaaaaaaa","bbbbbbbbbbbbbbbbbbbbbb"],"status":status,"revision":4,"remote_activity_sequence":sequence,"activity_at":at}

func server_room(id: String,sequence: int,status: String="your_turn") -> Dictionary:
	return {"room_id":id,"family":"legacy","api_version":1,"chapter":{"id":"long-way-home","version":1},"membership":{"host_id":"aaaaaaaaaaaaaaaaaaaaaa","guest_id":"bbbbbbbbbbbbbbbbbbbbbb","you_are_host":true},"status":status,"revision":4,"remote_activity_sequence":sequence,"activity_at":"2026-10-09T13:00:00.000Z"}

func _run() -> void:
	var api := FakeApi.new()
	api.base_url += str(Time.get_ticks_usec())
	root.add_child(api)
	client = Client.new(api,identity,transport)
	var old_room := room("cccccccccccccccccccccc",2,10)
	var newer_room := room("dddddddddddddddddddddd",3,20)
	var equal_time := room("eeeeeeeeeeeeeeeeeeeeee",1,20)
	var seen := {Client.room_key(1,old_room.room_id):1}
	check(Client.is_unread(old_room,seen),"remote sequence newer than seen state is unread")
	check(not Client.is_unread(equal_time,{Client.room_key(1,equal_time.room_id):1}),"baseline existing room stays read")
	var ordered := Client.ordered([old_room,newer_room,equal_time],seen)
	check(ordered[0].room_id == old_room.room_id and ordered[1].room_id == newer_room.room_id,"unread rooms sort before read rooms")
	check(ordered[1].room_id == newer_room.room_id and ordered[2].room_id == equal_time.room_id,"activity sorts newest first within unread/read groups")
	var server_old := server_room(old_room.room_id,2)
	var server_new := server_room(newer_room.room_id,3)
	check(Client.valid_page({"schema_version":1,"rooms":[server_old,server_new]}),"accepts the backend nested room projection")
	response = {"ok":true,"data":{"schema_version":1,"rooms":[server_old,server_new]}}
	check(await client.refresh(),"inbox accepts schema-v1 room summaries")
	check(calls.size() == 1 and calls[0].path == "/v1/room-inbox","refresh is one explicit metadata request")
	var normalized: Dictionary = client.view().rooms[0]
	check(normalized.chapter_title == "Long Way Home" and normalized.member_ids.size() == 2,"nested metadata is normalized for the room cards")
	check(normalized.chapter_key == "legacy-long-way-home","earlier-island rooms map to their thumbnail key")
	var relay_room := server_room("ffffffffffffffffffffff",1)
	relay_room.family = "relay"
	relay_room.api_version = 2
	relay_room.chapter = {"id":"high-and-low","version":1}
	var relay_view: Dictionary = client._normalize_room(relay_room)
	check(relay_view.chapter_key == "high-and-low@1" and relay_view.chapter_title == "High and Low","chapter rooms map id and version to the registry key and title")
	check(not client.unread(server_old),"first observation establishes a read baseline")
	server_old.remote_activity_sequence = 3
	response = {"ok":true,"data":{"schema_version":1,"rooms":[server_old,server_new]}}
	var refreshed_second: bool = await client.refresh()
	check(refreshed_second and client.unread(server_old),"later remote activity is unread and refresh does not clear it")
	check(not client.confirm_room_rendered(1,"ffffffffffffffffffffff"),"unknown room cannot be acknowledged")
	check(client.unread(server_old),"opening unknown room does not affect seen state")
	check(client.confirm_room_rendered(1,server_old.room_id),"caller may acknowledge after successful room render")
	check(not client.unread(server_old),"only explicit render confirmation clears activity")
	# A real reply is parsed JSON: every number, api_version included, is a float.
	response = {"ok":true,"data":JSON.parse_string(JSON.stringify({"schema_version":1,"rooms":[server_old,server_new]}))}
	check(response.data.rooms[0].api_version is float and await client.refresh(),"a parsed reply with float versions refreshes")
	check(not client.unread(server_old) and client.confirm_room_rendered(1,server_new.room_id),"parsed rooms keep the same integer room keys")
	check(Client.room_key(1,"x") == "1:x","room keys use the integer version")
	response = {"ok":false,"code":"network_error"}
	check(not await client.refresh(),"failed refresh reports failure")
	var stale_view: Dictionary = client.view()
	check(stale_view.stale and stale_view.rooms.size() == 2,"failed refresh retains cached rooms as stale/offline")
	var local_room := room("llllllllllllllllllllll",5,30)
	client.local = func() -> Array: return [local_room]
	var merged_view: Dictionary = client.view()
	check(merged_view.rooms.size() == 3,"local history rooms appear alongside cached inbox rooms")
	check(not client.unread(local_room),"a local-history room with no server baseline shows no unread dot")
	client.local = func() -> Array: return [local_room,room("cccccccccccccccccccccc",9,99)]
	check(client.view().rooms.size() == 3,"local history never duplicates a room the inbox already lists")
	var cold_api := FakeApi.new()
	cold_api.base_url = "https://cold.test" + str(Time.get_ticks_usec())
	root.add_child(cold_api)
	var cold := Client.new(cold_api,identity,transport)
	cold.local = func() -> Array: return [room("mmmmmmmmmmmmmmmmmmmmmm",0,0)]
	response = {"ok":false,"status":404}
	check(not await cold.refresh(),"a missing inbox endpoint reports a failed refresh")
	var cold_view: Dictionary = cold.view()
	check(cold_view.rooms.size() == 1 and cold_view.stale,"the hub still lists local history when the inbox endpoint is unavailable")
	var invalid := {"schema_version":1,"rooms":[server_old.duplicate(true)]}
	invalid.rooms[0].status = "unknown"
	check(not Client.valid_page(invalid),"unknown room status is rejected safely")
	var invalid_snapshot := server_room("ffffffffffffffffffffff",0,"unavailable")
	invalid_snapshot.chapter.extra = true
	check(not Client.valid_page({"schema_version":1,"rooms":[invalid_snapshot]}),"metadata projection rejects unexpected nested fields")
	await _transferred_room_case()
	await _account_switch_case()
	if failures == 0: print("ROOM_INBOX_CLIENT_TESTS_PASSED")
	quit(1 if failures else 0)

## A finished room whose replay both players saved: the live server lists it
## as a placeholder with a null chapter. It must never read "<null>".
func _transferred_room_case() -> void:
	var api := FakeApi.new()
	api.base_url = "https://transferred.test" + str(Time.get_ticks_usec())
	root.add_child(api)
	var hub := Client.new(api,identity,transport)
	var me := "aaaaaaaaaaaaaaaaaaaaaa"
	var friend := "bbbbbbbbbbbbbbbbbbbbbb"
	var placeholder := {"room_id":"wwwwwwwwwwwwwwwwwwwwww","family":"relay","api_version":2,"chapter":{"id":null,"version":null},"membership":{"host_id":null,"guest_id":null,"you_are_host":true},"status":"unavailable","revision":null,"remote_activity_sequence":0,"activity_at":null}
	var gone := placeholder.duplicate(true)
	gone.room_id = "xxxxxxxxxxxxxxxxxxxxxx"
	response = {"ok":true,"data":JSON.parse_string(JSON.stringify({"schema_version":1,"rooms":[placeholder,gone]}))}
	check(await hub.refresh(),"the inbox accepts the server's placeholder rows")
	var bare: Dictionary = hub._normalize_room(response.data.rooms[0])
	check(bare.chapter_key == "unknown" and bare.chapter_title == "Unavailable room","a null chapter id normalizes to an unknown room, never <null>: %s" % [bare])
	var saved := {"api_version":2,"room_id":placeholder.room_id,"chapter_key":"the-wishing-well@1","chapter_title":"The Wishing Well","member_ids":[me,friend],"status":"completed","revision":0,"remote_activity_sequence":0,"activity_at":0,"family":"relay"}
	hub.finished = func() -> Array: return [saved]
	var rooms: Array = hub.view().rooms
	var named: Array = rooms.filter(func(row: Dictionary) -> bool: return row.room_id == placeholder.room_id)
	var unnamed: Array = rooms.filter(func(row: Dictionary) -> bool: return row.room_id == gone.room_id)
	check(rooms.size() == 2,"a saved replay names a listed room and adds none: %s" % [rooms])
	check(named.size() == 1 and named[0].chapter_title == "The Wishing Well" and named[0].status == "completed" and named[0].chapter_key == "the-wishing-well@1","the compacted room reads as the finished chapter: %s" % [named])
	check(unnamed.size() == 1 and unnamed[0].chapter_title == "Unavailable room" and unnamed[0].status == "unavailable","a room nothing on the phone knows stays a plain unavailable room: %s" % [unnamed])
	for row: Dictionary in rooms: check(not str(row).contains("<null>"),"no room row carries <null>: %s" % [row])
	# A 0.6.0 cache saved the placeholder as "<null>"; it resolves the same way.
	var cached := saved.duplicate(true)
	cached.chapter_key = "<null>"
	cached.chapter_title = "<null>"
	cached.status = "unavailable"
	hub._rooms.assign([cached])
	var history := saved.duplicate(true)
	hub.finished = Callable()
	hub.local = func() -> Array: return [history]
	var resolved: Array = hub.view().rooms
	check(resolved.size() == 1 and resolved[0].chapter_title == "The Wishing Well" and resolved[0].status == "completed","local history names a cached <null> row: %s" % [resolved])
	api.queue_free()

## The player changes on this phone while a refresh is out: the reply belongs
## to the earlier account, so none of its rooms may show for the new one.
func _account_switch_case() -> void:
	var api := FakeApi.new()
	api.base_url = "https://switch.test" + str(Time.get_ticks_usec())
	root.add_child(api)
	var page := {"ok":true,"data":{"schema_version":1,"rooms":[server_room("ssssssssssssssssssssss",1),server_room("tttttttttttttttttttttt",1)]}}
	var switch := [false]
	var client := Client.new(api,identity,func(_method: int,_path: String,_body: Dictionary) -> Dictionary:
		if switch[0]:
			player = "nnnnnnnnnnnnnnnnnnnnnn"
			api.player_id = player
		return page.duplicate(true))
	check(await client.refresh() and client.view().rooms.size() == 2,"the first account's rooms are listed")
	switch[0] = true
	check(not await client.refresh(),"a refresh whose account changed while it was out reports failure")
	check(client.view().rooms.is_empty(),"the new account sees none of the earlier account's rooms: %s" % [client.view().rooms])
	player = "aaaaaaaaaaaaaaaaaaaaaa"
	api.queue_free()

var failures := 0
func check(value: bool,label: String) -> void:
	if not value: failures += 1; push_error(label)
