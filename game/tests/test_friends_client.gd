extends SceneTree
const Client = preload("res://services/friends_client.gd")
var failures := 0
var now := 1000
var epoch := 1
var ready := true
const OWNER := "aaaaaaaaaaaaaaaaaaaaaa"
const PEER := "bbbbbbbbbbbbbbbbbbbbbb"
const REQUEST := "cccccccccccccccccccccc"
var response: Dictionary
var calls: Array = []
var hold := false
signal release
var api: Node
var client: RefCounted

class Transport:
	extends Node
	var base_url := "https://example.test"
	var player_id := "aaaaaaaaaaaaaaaaaaaaaa"
	var device_token := "test-credential"
	var busy := false

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error(label)
func identity() -> Dictionary: return {"ready":ready,"player_id":OWNER,"epoch":epoch}
func request(method: int, path: String, body: Dictionary) -> Dictionary:
	calls.append({"method":method,"path":path,"body":body})
	if hold: await release
	# HTTPRequest parses JSON numbers as floats, including API versions.
	var wire: Dictionary = JSON.parse_string(JSON.stringify(response))
	return wire
func page() -> Dictionary:
	return {"schema_version":1,"friend_code":OWNER,"refresh_after_seconds":30,"shared_room":null,"friends":[{"player_id":PEER,"request_id":REQUEST,"status":"accepted","online":true,"expires_after_seconds":90,"join_available":true}]}
func _run() -> void:
	api = Transport.new()
	root.add_child(api)
	client = Client.new(api,identity,request)
	client.clock_ms = func(): return now
	response = {"ok":true,"data":page()}
	check(await client.refresh(),"friends load")
	check(client.view().friends[0].online,"accepted friend is online")
	check(await client.refresh() and calls.size() == 1,"reopening within interval makes no request")
	now += 91000
	check(not client.view().friends[0].online and client.view().friends[0].join_available,"An expired presence lease leaves an explicitly shared asynchronous room joinable")
	check(await client.refresh() and calls.size() == 2,"one refresh after interval")
	var altered := page()
	altered.friends[0].status = "incoming"
	check(not Client.valid_page(altered,OWNER),"pending friend cannot expose presence")
	altered = page()
	altered.friends[0].online = false
	altered.friends[0].expires_after_seconds = 0
	check(Client.valid_page(altered,OWNER),"An offline accepted friend may share a room")
	altered.friends[0].status = "incoming"
	check(not Client.valid_page(altered,OWNER),"An unaccepted request cannot expose an offline shared room")
	altered = page()
	altered.friends.append(altered.friends[0].duplicate(true))
	check(not Client.valid_page(altered,OWNER),"duplicate peer rejected")
	altered = page()
	altered.friend_code = PEER
	check(not Client.valid_page(altered,OWNER),"wrong identity page rejected")
	altered = page()
	altered.erase("shared_room")
	altered["unknown_room"] = null
	check(not Client.valid_page(altered,OWNER),"Missing nullable shared_room cannot be replaced with an unknown field")
	var code := "0123456789ABCDEF0123"
	response = {"ok":true,"data":{"schema_version":1,"api_version":2,"room_id":("v2:"+code).sha256_text().substr(0,22),"invite_code":code}}
	check(not (await client.join_friend(page().friends[0])).is_empty(),"verified chapter invitation allowed")
	response.data.room_id = "dddddddddddddddddddddd"
	check((await client.join_friend(page().friends[0])).is_empty(),"mismatched room invitation rejected")
	response = {"ok":false,"code":"rate_limited","retry_after_ms":120000}
	now += 60000
	check(not await client.refresh(),"server backoff observed")
	var count := calls.size()
	now += 61000
	await client.refresh()
	check(calls.size() == count,"refresh does not bypass server backoff")
	now += 120001
	response = {"ok":true,"data":page()}
	hold = true
	_delayed_change.call_deferred()
	check(not await client.refresh(),"late reply after identity change rejected")
	check(client.view().is_empty() and not client.busy,"identity change clears friends and busy state")
	hold = false
	check(await client.refresh(),"new identity context can load after invalidation")
	client.invalidate()
	response = {"ok":false,"code":"rate_limited","retry_after_ms":120000}
	check(not await client.refresh(),"empty page request fails")
	count = calls.size()
	await client.refresh()
	check(calls.size() == count,"empty page respects request backoff")
	response = {"ok":true,"data":{"schema_version":1,"room":null}}
	count = calls.size()
	check(await client.share_room(null),"Explicit unshare completes its mutation")
	check(calls.size() == count + 1 and calls.back().method == HTTPClient.METHOD_POST,"Mutation completion leaves the next read to a foreground screen")
	check(client.view().is_empty() and client.refresh_due(),"Mutation invalidates stale joins without starting a hidden refresh")
	ready = false
	check(client.view().is_empty(),"unavailable identity sees no friends")
	api.queue_free()
	await process_frame
	print("Friends client: ",failures," failures")
	quit(0 if failures == 0 else 1)
func _delayed_change() -> void:
	epoch += 1
	release.emit()
