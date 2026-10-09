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

func identity() -> Dictionary:
	return {"ready":ready,"player_id":"aaaaaaaaaaaaaaaaaaaaaa","epoch":epoch}

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
	check(not client.unread(server_old),"first observation establishes a read baseline")
	server_old.remote_activity_sequence = 3
	response = {"ok":true,"data":{"schema_version":1,"rooms":[server_old,server_new]}}
	var refreshed_second: bool = await client.refresh()
	check(refreshed_second and client.unread(server_old),"later remote activity is unread and refresh does not clear it")
	check(not client.confirm_room_rendered(1,"ffffffffffffffffffffff"),"unknown room cannot be acknowledged")
	check(client.unread(server_old),"opening unknown room does not affect seen state")
	check(client.confirm_room_rendered(1,server_old.room_id),"caller may acknowledge after successful room render")
	check(not client.unread(server_old),"only explicit render confirmation clears activity")
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
	if failures == 0: print("ROOM_INBOX_CLIENT_TESTS_PASSED")
	quit(1 if failures else 0)

var failures := 0
func check(value: bool,label: String) -> void:
	if not value: failures += 1; push_error(label)
