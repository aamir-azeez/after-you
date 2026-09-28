extends "res://tests/test_friends_client.gd"
const Screen = preload("res://presentation/friends_screen.gd")
var screen: CanvasLayer
var joins := 0
var closes := 0
var hosts := 0
var opens := 0

func _run() -> void:
	api = Transport.new()
	root.add_child(api)
	client = Client.new(api,identity,request)
	client.clock_ms = func(): return now
	response = {"ok":true,"data":page()}
	response.data.shared_room = {"api_version":1,"room_id":OWNER}
	await client.refresh()
	screen = Screen.new()
	screen.client = client
	screen.shareable_room = {"api_version":1,"room_id":OWNER}
	screen.room_title = "Relay Isles"
	screen.openable_room = true
	screen.closed.connect(func(): closes += 1)
	screen.join_requested.connect(func(_value: Dictionary): joins += 1)
	root.add_child(screen)
	await process_frame
	await process_frame
	var back := find_button(screen,"Back")
	check(back != null,"Back is available")
	var ancestor: Node = back.get_parent() if back != null else null
	while ancestor != null:
		check(not ancestor is ScrollContainer,"Back remains outside scroll content")
		ancestor = ancestor.get_parent()
	check(not find_button(screen,"Join").disabled,"fresh online friend offers Join")
	check(find_button(screen,"Host a room") != null and find_button(screen,"Return to room") != null,"Friends exposes Host and Return above the list")
	check(find_label(screen,"Relay Isles") != null and find_label(screen,"Shared with friends") != null and find_button(screen,"Share current room") == null,"The named room shows its confirmed sharing status")
	check(find_button(screen,"Stop sharing room") != null,"Stop sharing remains available")
	check(find_button(screen,"Join").get_parent().get_index() < screen.find_child("FriendCode",true,false).get_parent().get_index(),"Available rooms appear before the add-code form")
	check(screen._refresh_button.text == "Refresh (30s)" and screen._refresh_button.disabled and screen._countdown.text == "Auto-refresh in 60s","Both refresh timings are visible")
	ancestor = screen._refresh_button.get_parent()
	while ancestor != null:
		check(not ancestor is ScrollContainer,"Refresh remains visible outside the friend list")
		ancestor = ancestor.get_parent()
	var input: LineEdit = screen.find_child("FriendCode",true,false)
	input.text = "partly-typed-code"
	input.text_changed.emit(input.text)
	input.grab_focus()
	input.caret_column = 6
	input.select(2,6)
	var count := calls.size()
	now += 1000
	screen._next_local_refresh = 0
	screen._process(0)
	check(screen.find_child("FriendCode",true,false) == input and input.has_focus(),"Countdown ticks keep the existing focused input")
	check(screen._refresh_button.text == "Refresh (29s)" and screen._countdown.text == "Auto-refresh in 59s" and calls.size() == count,"Visible countdown updates locally without polling")
	now += 91000
	client._next_refresh = now + 60000
	screen._next_local_refresh = 0
	screen._process(0)
	check(not find_button(screen,"Join").disabled,"Presence expiry preserves access to an explicitly shared asynchronous room")
	check(calls.size() == count,"local presence expiry requires no HTTP")
	input = screen.find_child("FriendCode",true,false)
	check(input.has_focus() and input.text == "partly-typed-code" and input.caret_column == 6 and input.get_selection_from_column() == 2 and input.get_selection_to_column() == 6,"presence updates preserve code input focus and selection")
	check(not client.view().friends[0].online,"The upcoming room join uses an offline friend")
	screen._render()
	var code := "0123456789ABCDEF0123"
	response = {"ok":true,"data":{"schema_version":1,"api_version":2,"room_id":("v2:"+code).sha256_text().substr(0,22),"invite_code":code}}
	hold = true
	_background_join.call_deferred()
	await screen._act("join",page().friends[0])
	check(joins == 0 and closes == 0,"join reply does not navigate while backgrounded")
	hold = false
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	response = {"ok":true,"data":{"schema_version":1,"shared_room":null}}
	count = calls.size()
	hold = true
	_background_join.call_deferred()
	await screen._act("unshare")
	check(calls.size() == count + 1 and calls.back().path == "/v1/friends/share","background mutation finishes without a hidden friends read")
	check(client.view().shared_room == null and not screen._busy,"Background unshare updates only the confirmed sharing choice and releases screen busy state")
	hold = false
	now += Client.JOIN_COOLDOWN_MS
	now += client.refresh_wait_ms()
	response = {"ok":true,"data":page()}
	response.data.shared_room = {"api_version":1,"room_id":OWNER}
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await screen._refresh()
	check(calls.size() == count + 2 and calls.back().method == HTTPClient.METHOD_GET,"Returning to foreground refreshes friends once when the interval is due")
	check(not find_button(screen,"Join").disabled,"foreground refresh restores the actual friend controls")
	now += 60000
	response.data.friends[0].join_available = false
	response.data.friends[0].online = false
	response.data.friends[0].expires_after_seconds = 0
	await screen._refresh()
	check(find_button(screen,"Check room") != null and not find_button(screen,"Check room").disabled,"An offline accepted friend offers Check room even when the list has no shared room")
	count = calls.size()
	response = {"ok":false,"code":"friend_not_joinable"}
	await screen._act("join",client.view().friends[0])
	check(calls.size() == count + 1 and calls.back().path.ends_with("/join") and screen._message == "Room unavailable","Check room performs one immediate descriptor request without waiting for the list")
	check(find_button(screen,"Check room (3s)") != null and find_button(screen,"Check room (3s)").disabled,"Check room displays its short retry cooldown")
	now += 60000
	response = {"ok":true,"data":page()}
	await screen._refresh()
	check(screen._message == "Room available","A later poll announces a newly shared room in the open screen")
	check(screen._change_notice(page(),page()).is_empty(),"An unchanged poll does not repeat the room alert")
	var with_request := page()
	with_request.friends.append({"player_id":"dddddddddddddddddddddd","request_id":"eeeeeeeeeeeeeeeeeeeeee","status":"incoming","online":false,"expires_after_seconds":0,"join_available":false})
	check(screen._change_notice(page(),with_request) == "New friend request","A new incoming request gets a short in-app alert")
	check(find_label(screen,"All friends") != null and find_button(screen,"Share current room") != null,"An unshared current room makes the sharing scope explicit")
	response = {"ok":true,"data":{"schema_version":1,"shared_room":null}}
	count = calls.size()
	hold = true
	_close_during_mutation.call_deferred()
	await screen._act("unshare")
	check(closes == 1,"Android Back closes an in-flight friends mutation")
	check(calls.size() == count + 1 and client.view().shared_room == null,"A closed mutation cannot start another friends read and keeps the confirmed unshared state")
	hold = false
	await process_frame
	await _navigation_controls()
	api.queue_free()
	await process_frame
	print("Friends screen: ",failures," failures")
	quit(0 if failures == 0 else 1)

func _background_join() -> void:
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	release.emit()

func _close_during_mutation() -> void:
	screen._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	release.emit()

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child: Node in node.get_children():
		var found := find_button(child,text)
		if found != null: return found
	return null

func find_label(node: Node, text: String) -> Label:
	if node is Label and node.text == text: return node
	for child: Node in node.get_children():
		var found := find_label(child,text)
		if found != null: return found
	return null

func _navigation_controls() -> void:
	# Reopen against a primed offline page; each navigation is a separate screen.
	now += 60000
	response = {"ok":true,"data":page()}
	response.data.friends[0].online = false
	response.data.friends[0].expires_after_seconds = 0
	response.data.friends[0].join_available = false
	await client.refresh()
	screen = Screen.new()
	screen.client = client
	screen.host_requested.connect(func(): hosts += 1; screen._host())
	screen.closed.connect(func(): closes += 1)
	root.add_child(screen)
	await process_frame
	var count := calls.size()
	var closed_before := closes
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	screen._host()
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	screen._busy = true
	screen._host()
	screen._busy = false
	check(hosts == 0,"Background or busy Host cannot navigate")
	screen._host()
	screen._host()
	check(hosts == 1 and closes == closed_before + 1 and calls.size() == count,"Host emits once, closes, and leaves room creation to its owner")
	await process_frame
	screen = Screen.new()
	screen.client = client
	screen.openable_room = true
	screen.open_requested.connect(func(): opens += 1; screen._open())
	screen.closed.connect(func(): closes += 1)
	root.add_child(screen)
	await process_frame
	closed_before = closes
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	screen._open()
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	client.busy = true
	screen._open()
	client.busy = false
	check(opens == 0,"Background or client-busy Return cannot navigate")
	screen._open()
	screen._open()
	check(opens == 1 and closes == closed_before + 1 and calls.size() == count,"Return emits once and does not create or share a room")
	await process_frame
	screen = Screen.new()
	screen.client = client
	screen.join_requested.connect(func(_value: Dictionary): joins += 1)
	screen.closed.connect(func(): closes += 1)
	root.add_child(screen)
	await process_frame
	check(find_button(screen,"Check room") != null,"Reopening retains a Check room action for the offline accepted friend")
	var code := "0123456789ABCDEF0123"
	response = {"ok":true,"data":{"schema_version":1,"api_version":2,"room_id":("v2:"+code).sha256_text().substr(0,22),"invite_code":code}}
	closed_before = closes
	await screen._act("join",client.view().friends[0])
	check(joins == 1 and closes == closed_before + 1 and calls.size() == count + 1,"Fresh Check room opens a newly shared offline room without a list poll")
	await process_frame
	screen = Screen.new()
	screen.client = client
	screen.host_requested.connect(func(): hosts += 1)
	root.add_child(screen)
	await process_frame
	epoch += 1
	screen._host()
	check(hosts == 1,"A stale identity cannot launch a room through an old screen")
	screen.close()
	await process_frame
