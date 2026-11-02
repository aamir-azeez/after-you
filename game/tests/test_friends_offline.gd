extends "res://tests/test_friends_client.gd"
## Friends offline (presentation/friends_screen.gd with presentation/offline_hold.gd):
## every action that needs the server greys and says why in the pop-up (Add
## friend, Accept, Decline, Cancel request, Join, Notify, Remove friend, Host a
## room, Return to room, Share, Stop sharing, Refresh, Leaderboards); Back, your
## code's Copy and Share Invite and a friend's nickname stay; everything comes
## back online on its own, typing a code offline keeps Add friend greyed, and
## the countdown's own enabling never undoes the grey.
const Screen = preload("res://presentation/friends_screen.gd")
const Connectivity = preload("res://services/connectivity.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const RoomActions = preload("res://presentation/room_actions.gd")
var screen: CanvasLayer
var said: Array = []

func _run() -> void:
	var state: RefCounted = Connectivity.new()
	Connectivity.use_shared(state)
	api = Transport.new()
	root.add_child(api)
	client = Client.new(api,identity,request)
	client.clock_ms = func(): return now
	var data := page()
	data.shared_room = {"api_version":1,"room_id":OWNER}
	data.friends.append({"player_id":REQUEST,"request_id":PEER,"status":"incoming","online":false,"expires_after_seconds":0,"join_available":false})
	response = {"ok":true,"data":data}
	await client.refresh()
	screen = Screen.new()
	screen.client = client
	screen.shareable_room = {"api_version":1,"room_id":PEER}
	screen.room_title = "Relay Isles"
	screen.openable_room = true
	screen.notice.connect(func(text: String, _news: bool) -> void: said.append(text))
	root.add_child(screen)
	await process_frame
	await process_frame
	screen.show_leaderboards(true)
	state.force(false)
	var greyed := _buttons_named(["Join","Accept","Host a room","Return to room",RoomActions.SHARE,RoomActions.STOP_SHARING])
	for name: String in greyed:
		var button: Button = greyed[name]
		check(button.disabled and OfflineHold.held(button) and button.is_visible_in_tree(),"Offline Friends greys %s and keeps it on the page" % name)
	for description: String in ["Decline","Remove friend",PlayerCopy.LEADERBOARDS]:
		var icon := _icon(description)
		check(icon != null and icon.disabled and OfflineHold.held(icon),"Offline Friends greys %s" % description)
	for description: String in ["Back"]:
		var icon := _icon(description)
		check(icon != null and not icon.disabled,"Offline Friends keeps %s" % description)
	var copy: Button = screen.find_child("CopyFriendCode",true,false)
	var share := find_button(screen,"Share Invite")
	var rename := _icon("Edit nickname")
	check(copy != null and not copy.disabled and share != null and not share.disabled,"Offline your code's Copy and Share Invite stay (no server needed)")
	check(rename != null and not rename.disabled,"Offline a friend's nickname stays editable (kept on this phone)")
	# Typing a code offline never enables Add friend.
	var field: LineEdit = screen.find_child("FriendCode",true,false)
	check(field != null,"The add-friend field is on the page")
	if field != null:
		field.text = "friend-" + PEER
		field.text_changed.emit(field.text)
	var add := find_button(screen,"Add friend")
	check(add != null and add.disabled,"Typing a code offline keeps Add friend greyed")
	# The countdown's own enabling (every second) keeps the grey.
	screen._update_countdowns()
	check(_buttons_named(["Join"]).values().all(func(b: Button) -> bool: return b.disabled),"The countdown's refresh keeps Join greyed")
	check(_icon("Refresh").disabled,"And Refresh")
	client.clock_ms = func(): return now + 600000
	screen._update_countdowns()
	check(_icon("Refresh").disabled and OfflineHold.held(_icon("Refresh")),"Refresh's wait ending offline leaves it greyed by the hold")
	# A tap on a greyed one says why in the pop-up.
	var hold: Node = greyed["Join"].get_node(NodePath(OfflineHold.NAME))
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = false
	hold._on_input(tap)
	check(said.has(PlayerCopy.OFFLINE_NEEDS_CONNECTION),"A tap on a greyed action says why in Friends' pop-up")
	state.note_reached()
	for name: String in ["Join","Accept","Host a room","Return to room",RoomActions.SHARE,RoomActions.STOP_SHARING,"Add friend"]:
		var button := find_button(screen,name)
		check(button != null and not button.disabled,"Online again %s comes back by itself" % name)
	check(not _icon("Decline").disabled and not _icon(PlayerCopy.LEADERBOARDS).disabled and not _icon("Refresh").disabled,"And the icon actions come back, Refresh too")
	field.text = ""
	field.text_changed.emit("")
	check(find_button(screen,"Add friend").disabled,"Online an empty code still keeps Add friend off")
	screen.queue_free()
	Connectivity.use_shared(null)
	await process_frame
	print("AFTER YOU FRIENDS OFFLINE: %d failures" % failures)
	quit(1 if failures else 0)

func _buttons_named(names: Array) -> Dictionary:
	var found := {}
	for name: String in names:
		var button := find_button(screen,name)
		check(button != null,"Friends shows %s" % name)
		if button != null: found[name] = button
	return found

func _icon(description: String) -> Button:
	for button: Button in screen.find_children("*","Button",true,false):
		if button.tooltip_text.begins_with(description): return button
	return null

func find_button(node: Node, text: String) -> Button:
	if node is Button and (node.text == text or node.tooltip_text == text): return node
	for child: Node in node.get_children():
		var found := find_button(child,text)
		if found != null: return found
	return null
