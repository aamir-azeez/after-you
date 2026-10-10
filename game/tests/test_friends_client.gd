extends SceneTree
const Client = preload("res://services/friends_client.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
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
	check(client.refresh_wait_ms(true) == 30000 and client.refresh_wait_ms() == 60000,"Manual and automatic refresh expose separate server-safe countdowns")
	now += 29999
	await client.refresh(true)
	check(calls.size() == 1,"Manual refresh cannot bypass the server's minimum interval")
	now += 1
	check(client.refresh_due(true) and not client.refresh_due(),"Manual refresh becomes available before automatic polling")
	check(await client.refresh(true) and calls.size() == 2,"Explicit refresh reads once when its cooldown expires")
	now += 91000
	check(not client.view().friends[0].online and client.view().friends[0].join_available,"An expired presence lease leaves an explicitly shared asynchronous room joinable")
	check(await client.refresh() and calls.size() == 3,"one refresh after interval")
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
	var count := calls.size()
	check((await client.join_friend(page().friends[0])).is_empty() and calls.size() == count,"Repeated Join is held by a short local cooldown without HTTP")
	now += Client.JOIN_COOLDOWN_MS
	response.data.room_id = "dddddddddddddddddddddd"
	check((await client.join_friend(page().friends[0])).is_empty() and calls.size() == count + 1,"mismatched room invitation rejected after an actual descriptor reply")
	now += Client.JOIN_COOLDOWN_MS
	response = {"ok":false,"code":"friend_not_joinable"}
	check((await client.join_friend(page().friends[0])).is_empty() and client.last_error == "Room unavailable","A no-longer-shared room gets a useful error")
	check(not client.view().friends[0].join_available,"Unavailable descriptor retires a stale cached Join affordance")
	now += Client.JOIN_COOLDOWN_MS
	var offline := client.view().friends[0] as Dictionary
	offline.online = false
	offline.expires_after_seconds = 0
	response = {"ok":true,"data":{"schema_version":1,"api_version":1,"room_id":code.sha256_text().substr(0,22),"invite_code":code}}
	count = calls.size()
	check(not (await client.join_friend(offline)).is_empty(),"Check room discovers a newly shared offline room before a list refresh")
	check(calls.size() == count + 1 and calls.back().path == "/v1/friends/"+PEER+"/join" and not client.refresh_due(),"Check room resolves only the selected friend and never forces a list poll")
	now += Client.JOIN_COOLDOWN_MS
	response = {"ok":true,"data":{"schema_version":1,"api_version":3,"room_id":("v2:"+code).sha256_text().substr(0,22),"invite_code":code,"campaign_key":{}}}
	check((await client.join_friend(offline)).is_empty(),"Friends cannot admit an archived Story descriptor")
	response = {"ok":false,"code":"rate_limited","retry_after_ms":120000}
	now += 60000
	check(not await client.refresh(),"server backoff observed")
	count = calls.size()
	now += 61000
	await client.refresh()
	await client.refresh(true)
	await client.join_friend(offline)
	check(calls.size() == count and client.refresh_wait_ms(true) == 59000 and client.join_wait_ms() == 59000,"Manual refresh, polling and Check room cannot bypass Retry-After")
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
	response = {"ok":true,"data":{"schema_version":1,"shared_room":null}}
	count = calls.size()
	check(await client.share_room(null),"Explicit unshare completes its mutation")
	check(calls.size() == count + 1 and calls.back().method == HTTPClient.METHOD_POST,"Mutation completion leaves the next read to a foreground screen")
	check(client.view().is_empty() and not client.refresh_due() and not client.refresh_due(true),"Sharing with no cached page does not invent peers, reset backoff or start a hidden refresh")
	client.invalidate()
	response = {"ok":true,"data":page()}
	response.data.refresh_after_seconds = 120
	check(await client.refresh() and client.refresh_wait_ms(true) == 120000 and client.refresh_wait_ms() == 120000,"Longer server refresh floors apply to both controls")
	count = calls.size()
	now += 60000
	await client.refresh(true)
	await client.refresh()
	check(calls.size() == count,"Neither refresh path shortens a longer server floor")
	var observed: int = client._observed_at
	check(Client.same_room({"api_version":2.0,"room_id":PEER},{"api_version":2,"room_id":PEER}),"JSON numeric variants identify the same ordinary room")
	check(not Client.same_room({"api_version":1,"room_id":PEER},{"api_version":2,"room_id":PEER}) and not Client.same_room({"api_version":2,"room_id":PEER},{"api_version":2,"room_id":OWNER}),"Sharing comparison still distinguishes room family and exact room ID")
	check(not Client.same_room({"api_version":3,"room_id":PEER},{"api_version":3,"room_id":PEER}) and not Client.same_room({"api_version":2,"room_id":PEER,"extra":true},{"api_version":2,"room_id":PEER}),"Sharing comparison rejects retired families and extra descriptor fields")
	response = {"ok":true,"data":{"schema_version":1,"shared_room":{"api_version":2,"room_id":PEER}}}
	check(await client.share_room({"api_version":2,"room_id":PEER}) and client.view().shared_room == response.data.shared_room,"Share confirmation updates the named current room immediately")
	check(client._observed_at == observed and client.view().friends.size() == 1 and not client.refresh_due(true),"Sharing does not renew presence leases, hide peers or bypass the list floor")
	response.data.shared_room = null
	check(not await client.share_room({"api_version":2,"room_id":PEER}),"A mismatched sharing acknowledgement is not shown as accepted")
	var row := page().friends[0] as Dictionary
	response = {"ok":true,"data":{"schema_version":1,"player_id":PEER,"request_id":REQUEST,"status":"accepted"}}
	check(await client.accept_friend(row) and client.view().friends[0].status == "accepted" and not client.view().friends[0].join_available,"Accepted link acknowledgement immediately offers Check room without inventing room availability")
	check(not client.view().friends[0].online and client._observed_at == observed and not client.refresh_due(true),"Link updates cannot renew presence or shorten the list cooldown")
	response.data.request_id = "f".repeat(22)
	check(not await client.accept_friend(row) and client.view().friends[0].request_id == REQUEST,"Accept rejects an acknowledgement for a different friendship request")
	response = {"ok":true,"data":{"schema_version":1,"player_id":"d".repeat(22),"request_id":"e".repeat(22),"status":"outgoing"}}
	check(await client.add_friend("d".repeat(22)) and client.view().friends.size() == 2,"Add acknowledgement retains existing peers and shows the new request immediately")
	for typed: String in ["friend-" + "d".repeat(22), " Friend-" + "d".repeat(22) + " ", "https://aamirazeez.com/after-you/link#friend-" + "d".repeat(22), "https://aamirazeez.com/after-you/link/?c=friend-" + "d".repeat(22)]:
		check(await client.add_friend(typed) and calls.back().path == "/v1/friends/request" and calls.back().body == {"schema_version":1,"friend_code":"d".repeat(22)},"Typed, prefixed and invite-link input sends only the bare ID: " + typed)
	count = calls.size()
	for rejected: Array in [["room-0123456789ABCDEF0123",PlayerCopy.SHARE_CODE_ROOM_NOT_FRIEND],["0123456789ABCDEF0123",PlayerCopy.SHARE_CODE_ROOM_NOT_FRIEND],["friend-" + OWNER,PlayerCopy.FRIEND_CODE_OWN],[OWNER,PlayerCopy.FRIEND_CODE_OWN],["friend-" + "d".repeat(21),PlayerCopy.FRIEND_CODE_INVALID],["https://aamirazeez.com/after-you#friend-" + "d".repeat(22),PlayerCopy.FRIEND_CODE_INVALID],["",PlayerCopy.FRIEND_CODE_INVALID]]:
		check(not await client.add_friend(rejected[0]) and client.last_error == rejected[1] and calls.size() == count,"Rejected add input never reaches the server: " + str(rejected[0]))
	response = {"ok":true,"data":{"schema_version":1,"removed":true}}
	check(await client.remove_friend(row) and client.view().friends.size() == 1 and client.view().friends[0].player_id == "d".repeat(22),"Remove only retires its exact acknowledged peer and leaves the other row visible")
	check(not client.refresh_due(true),"Friend mutations preserve the server refresh floor")
	ready = false
	check(client.view().is_empty(),"unavailable identity sees no friends")
	api.queue_free()
	await process_frame
	print("Friends client: ",failures," failures")
	quit(0 if failures == 0 else 1)
func _delayed_change() -> void:
	epoch += 1
	release.emit()
