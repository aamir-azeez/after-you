extends "res://tests/test_friends_client.gd"
const Screen = preload("res://presentation/friends_screen.gd")
var screen: CanvasLayer
var joins := 0
var closes := 0

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
	var input: LineEdit = screen.find_child("FriendCode",true,false)
	input.text = "partly-typed-code"
	input.text_changed.emit(input.text)
	input.grab_focus()
	input.caret_column = 6
	input.select(2,6)
	var count := calls.size()
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
	check(client.view().is_empty() and not screen._busy,"background unshare removes cached join affordances and releases screen busy state")
	hold = false
	response = {"ok":true,"data":page()}
	response.data.shared_room = {"api_version":1,"room_id":OWNER}
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await screen._refresh()
	check(calls.size() == count + 2 and calls.back().method == HTTPClient.METHOD_GET,"returning to foreground refreshes invalidated friends once")
	check(not find_button(screen,"Join").disabled,"foreground refresh restores the actual friend controls")
	response = {"ok":true,"data":{"schema_version":1,"shared_room":null}}
	count = calls.size()
	hold = true
	_close_during_mutation.call_deferred()
	await screen._act("unshare")
	check(closes == 1,"Android Back closes an in-flight friends mutation")
	check(calls.size() == count + 1 and client.view().is_empty(),"closed mutation cannot start another friends read or retain stale joins")
	hold = false
	await process_frame
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
