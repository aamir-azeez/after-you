extends "res://tests/test_friends_client.gd"
const Screen = preload("res://presentation/friends_screen.gd")
const InviteShare = preload("res://services/invite_share.gd")
const ShareCodes = preload("res://services/share_codes.gd")
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
	var base_url := str(client.context().get("base_url",""))
	check(screen._nicknames.set_nickname(base_url,OWNER,PEER,"Sunny"),"A local nickname saves for the friend row")
	screen._render()
	check(find_label(screen,"Sunny") != null,"A nicknamed friend shows the local nickname")
	var row_code: Button = screen.find_child("FriendRowCode",true,false)
	check(row_code != null and row_code.text == "friend-" + PEER and row_code.flat and row_code.clip_text and row_code.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING,"The real friend code stays visible beneath a set nickname, typed like your own and clipped rather than trimmed")
	check(row_code != null and row_code.tooltip_text == "Copy code" and row_code.accessibility_name == "Copy friend code for Sunny","The row code copies and is announced with the friend's name")
	screen._edit_nickname({"player_id":PEER,"status":"accepted"})
	await process_frame
	var modal: Control = screen.find_child("NicknameModal",true,false)
	check(modal != null and modal.mouse_filter == Control.MOUSE_FILTER_STOP,"The nickname editor is an in-game modal that blocks the page behind it")
	var nickname_field: LineEdit = modal.find_child("FriendNickname",true,false) if modal != null else null
	check(nickname_field != null and nickname_field.text == "Sunny" and nickname_field.has_focus(),"The modal opens with the saved nickname and focuses the field")
	nickname_field.text = "Temporary"
	find_button(modal,"Cancel").pressed.emit()
	await process_frame
	check(not is_instance_valid(screen._modal) and screen._nicknames.nickname(base_url,OWNER,PEER) == "Sunny","Cancel closes the modal without changing the nickname")
	screen._edit_nickname({"player_id":PEER,"status":"accepted"})
	await process_frame
	modal = screen.find_child("NicknameModal",true,false)
	(modal.find_child("FriendNickname",true,false) as LineEdit).text = "  Sunny  "
	find_button(modal,"Save").pressed.emit()
	await process_frame
	check(not is_instance_valid(screen._modal) and screen._nicknames.nickname(base_url,OWNER,PEER) == "Sunny","Save trims and stores the nickname locally")
	screen._edit_nickname({"player_id":PEER,"status":"accepted"})
	await process_frame
	modal = screen.find_child("NicknameModal",true,false)
	check((modal.find_child("FriendNickname",true,false) as LineEdit).text == "Sunny" and (modal.find_child("NicknameCounter",true,false) as Label).text == "5 / 32","Reopening shows the saved nickname and its length")
	screen._close_modal()
	await process_frame
	check(not is_instance_valid(screen._modal) and screen._nicknames.nickname(base_url,OWNER,PEER) == "Sunny","Close leaves the saved nickname unchanged")
	var alerts := AlertStub.new()
	screen.event_client = alerts
	await screen._refresh()
	await screen._refresh()
	check(alerts.inbox_calls == 0,"Cached Friends refreshes cannot bypass the social inbox deadline")
	screen._ask_hosting_alert({"player_id":PEER,"status":"accepted"})
	await process_frame
	var alert_modal: Control = screen.find_child("HostingAlertModal",true,false)
	check(alert_modal != null and alert_modal.mouse_filter == Control.MOUSE_FILTER_STOP and find_button(alert_modal,"Notify me") != null,"Notify asks in the same in-game modal")
	find_button(alert_modal,"Cancel").pressed.emit()
	await process_frame
	check(not is_instance_valid(screen._modal) and alerts.calls.is_empty(),"Cancelling the alert prompt changes nothing")
	screen._ask_hosting_alert({"player_id":PEER,"status":"accepted"})
	await process_frame
	find_button(screen.find_child("HostingAlertModal",true,false),"Notify me").pressed.emit()
	await process_frame
	await process_frame
	check(not is_instance_valid(screen._modal) and alerts.calls == [true],"Confirming turns the hosting alert on once")
	var notify_on := find_button(screen,"Notifying")
	check(notify_on != null and find_button(notify_on.get_parent(),"Join") != null and not notify_on.disabled,"An enabled hosting alert stays beside Join for a friend with a room")
	var on_fill: Color = (notify_on.get_theme_stylebox("normal") as StyleBoxFlat).bg_color if notify_on != null else Color.WHITE
	screen.event_client = null
	screen._notification_preferences.clear()
	screen._render()
	var notify_off := find_button(screen,"Notify")
	var off_fill: Color = (notify_off.get_theme_stylebox("normal") as StyleBoxFlat).bg_color if notify_off != null else Color.WHITE
	var join_fill: Color = (find_button(screen,"Join").get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	check(notify_off != null and notify_off.get_parent() == find_button(screen,"Join").get_parent(),"Notify remains available beside Join as an independent choice")
	check(off_fill != join_fill and on_fill != join_fill and on_fill != off_fill,"Notify is a secondary control with a distinct on state, never the Join fill")
	check(notify_off != null and notify_off.custom_minimum_size.y >= 48 and notify_off.get_parent().get_theme_constant("separation") >= 10,"Room actions keep touch-sized targets and clear spacing from Remove friend")
	var share_code := find_button(screen,"Share Invite")
	var copy_code: Button = screen.find_child("CopyFriendCode",true,false)
	check(PlayerCopy.INVITE_LINK_SHARE == "Share Invite" and share_code != null and share_code.text == "Share Invite" and share_code.tooltip_text == "Share Invite" and share_code.custom_minimum_size.y >= 48,"Your friend code offers a labelled Share Invite button")
	check(copy_code != null and copy_code.text.is_empty() and copy_code.icon != null and copy_code.custom_minimum_size == Vector2(54,54) and copy_code.tooltip_text == "Copy code" and copy_code.accessibility_name == "Copy code" and copy_code.get_theme_constant("icon_max_width") == 24,"Copy is a 54-unit square icon button that is still named Copy code")
	var own_field: Control = screen.find_child("OwnFriendCode",true,false)
	await process_frame
	check(own_field != null and own_field.size.x > 0 and copy_code.size.x > 0 and share_code.size.x > 0,"The code row is laid out before checking its order")
	check(share_code != null and copy_code != null and own_field != null and copy_code.get_parent() == share_code.get_parent() and copy_code.get_index() < share_code.get_index() and own_field.get_global_rect().end.x <= copy_code.get_global_rect().position.x and copy_code.get_global_rect().end.x <= share_code.get_global_rect().position.x,"The code row reads field, Copy, then Share Invite")
	var copy_fill: StyleBoxFlat = copy_code.get_theme_stylebox("normal") if copy_code != null else null
	var share_fill: StyleBoxFlat = share_code.get_theme_stylebox("normal") if share_code != null else null
	check(copy_fill != null and share_fill != null and copy_fill.border_width_left > 0 and copy_fill.bg_color != Color("eceddb") and share_fill.bg_color == Color("eceddb"),"Copy is the outlined secondary and Share Invite the cream primary")
	check(screen._compact or (share_code != null and share_code.icon != null),"Share Invite keeps its icon in the full layout")
	check(copy_code != null and absf(copy_code.size.x - copy_code.size.y) <= 0.5,"Copy stays square")
	var own_code: LineEdit = screen.find_child("OwnFriendCode",true,false)
	check(own_code != null and own_code.text == "friend-" + OWNER and not own_code.editable and not own_code.selecting_enabled and own_code.focus_mode == Control.FOCUS_NONE and not own_code.expand_to_text_length,"Your friend code is shown as friend-<id>, read-only from its start")
	var shared: Array = []
	var copied: Array = []
	screen.share_text = func(text: String) -> bool:
		shared.append(text)
		return true
	screen.clipboard_copy = func(text: String) -> void: copied.append(text)
	var count_before_share := calls.size()
	if share_code != null: share_code.pressed.emit()
	check(shared == [InviteShare.message(OWNER)] and copied.is_empty() and shared[0].contains("https://aamirazeez.com/after-you/link#friend-" + OWNER) and shared[0].contains("friend-" + OWNER),"Share Invite sends the link plus the typed code once")
	var copy_icon: Texture2D = copy_code.icon if copy_code != null else null
	if copy_code != null: copy_code.pressed.emit()
	check(copied == ["friend-" + OWNER] and shared.size() == 1 and calls.size() == count_before_share,"Copy places only the typed friend code on the clipboard, without a request")
	check(copy_code != null and copy_code.icon != null and copy_code.icon != copy_icon,"Copy briefly shows a tick")
	await create_timer(1.4).timeout
	check(is_instance_valid(copy_code) and copy_code.icon == copy_icon,"The tick returns to the copy icon")
	# A friend row's code copies the full typed code with a brief tick, over a 44-unit band.
	await _row_code_copy(copied)
	var typed_field: LineEdit = screen.find_child("FriendCode",true,false)
	check(typed_field != null and typed_field.max_length >= ShareCodes.LINK_BASE.length() + 30,"The add field accepts a pasted invite link")
	for wrong: Array in [["room-0123456789ABCDEF0123",PlayerCopy.SHARE_CODE_ROOM_NOT_FRIEND],["0123456789abcdef0123",PlayerCopy.SHARE_CODE_ROOM_NOT_FRIEND],["friend-" + OWNER,PlayerCopy.FRIEND_CODE_OWN],["friend-short",PlayerCopy.FRIEND_CODE_INVALID]]:
		screen._code = wrong[0]
		await screen._act("add")
		check(screen._message == wrong[1] and calls.size() == count_before_share,"Add friend explains rejected input locally: " + str(wrong[0]))
	screen._code = ""
	screen._message = ""
	screen._render()
	await process_frame
	var utilities: Control = screen.find_child("FriendCodeUtilities",true,false)
	check(utilities != null and utilities.get_global_rect().end.y >= screen._scroll.get_global_rect().end.y - 2.0,"The friend list fills the page height instead of leaving empty space below")
	check(screen._nicknames.set_nickname(base_url,OWNER,PEER,""),"The nickname resets for the remaining checks")
	screen._render()
	var back := find_button(screen,"Back")
	check(back != null,"Back is available")
	var ancestor: Node = back.get_parent() if back != null else null
	while ancestor != null:
		check(not ancestor is ScrollContainer,"Back remains outside scroll content")
		ancestor = ancestor.get_parent()
	check(not find_button(screen,"Join").disabled,"fresh online friend offers Join")
	check(find_button(screen,"Host a room") != null and find_button(screen,"Return to room") != null,"Friends exposes Host and Return in the current-room panel")
	check(find_label(screen,"Relay Isles") != null and find_label(screen,"Shared with friends") != null and find_button(screen,"Share current room") == null,"The named room shows its confirmed sharing status")
	check(find_button(screen,"Stop sharing room") != null,"Stop sharing remains available")
	check(screen.find_child("FriendsAndRoom",true,false).get_index() < screen.find_child("FriendCodeUtilities",true,false).get_index(),"Available rooms appear before the add-code form")
	check(screen._refresh_button.text.is_empty() and screen._refresh_button.tooltip_text == "Refresh (30s)" and screen._refresh_button.disabled and screen._countdown.text == "Auto-refresh in 60s","Refresh keeps its icon, retry tooltip, and visible auto-refresh countdown")
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
	check(screen._refresh_button.tooltip_text == "Refresh (29s)" and screen._countdown.text == "Auto-refresh in 59s" and calls.size() == count,"Visible countdown updates locally without polling")
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
	var notify := find_button(screen,"Notify")
	check(notify != null and notify.disabled,"An offline accepted friend without a shared room offers hosting alerts, disabled while the events service is unavailable")
	check(find_button(screen,"Join") == null,"No speculative Join appears while the friends list reports no available room")
	count = calls.size()
	now += 60000
	response = {"ok":true,"data":page()}
	await screen._refresh()
	check(calls.size() == count + 1 and find_button(screen,"Join") != null and not find_button(screen,"Join").disabled,"A later poll surfaces the friend's shared room as a direct Join")
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
	await _cached_feedback_and_empty_room()
	await _navigation_controls()
	await _code_row_widths()
	api.queue_free()
	await process_frame
	print("Friends screen: ",failures," failures")
	quit(0 if failures == 0 else 1)

## The code field, Copy, Share Invite and the Add column must fit
## just above each breakpoint, where the old single-line row overflowed.
func _code_row_widths() -> void:
	now += 60000
	response = {"ok":true,"data":page()}
	await client.refresh()
	check(not client.view().is_empty(),"The width checks start from a loaded friends page")
	var row_fades := {}
	var own_clipped: Array[int] = []
	for width: int in [1560, 1280, 1180, 1150, 1120, 1104, 1100, 1040, 960, 920, 900, 800, 640]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(width,720)
		root.add_child(viewport)
		var view := Screen.new()
		view.client = client
		viewport.add_child(view)
		for _i in 3: await process_frame
		var limit := float(width) - 19.0
		var parts: Array[Control] = []
		for name: String in ["OwnFriendCode","CopyFriendCode","ShareInviteLink","FriendCode"]:
			var part: Control = view.find_child(name,true,false)
			if part != null: parts.append(part)
		var add := find_button(view,"Add friend")
		if add != null: parts.append(add)
		check(parts.size() == 5,"All code utilities are present at %d" % width)
		var outside := parts.filter(func(part: Control) -> bool: return part.get_global_rect().position.x < 19.0 or part.get_global_rect().end.x > limit + 0.5).map(func(part: Control) -> String: return "%s %s" % [part.name,part.get_global_rect()])
		check(outside.is_empty(),"Code utilities stay inside the page margins at %d wide %s" % [width,outside])
		var own: LineEdit = view.find_child("OwnFriendCode",true,false)
		check(own != null and own.size.x >= 110.0 and own.text == "friend-" + OWNER,"The friend code field keeps a readable width at %d wide" % width)
		if own != null:
			var own_fade: TextureRect = own.get_node_or_null("CodeFade")
			var font: Font = own.get_theme_font("font")
			var clipped := font.get_string_size(own.text,HORIZONTAL_ALIGNMENT_LEFT,-1,own.get_theme_font_size("font_size")).x + 32.0 > own.size.x
			check(own_fade != null and own_fade.visible == clipped and own_fade.mouse_filter == Control.MOUSE_FILTER_IGNORE,"The own code fades exactly when it is clipped at %d wide" % width)
			if clipped:
				own_clipped.append(width)
				check(own_fade.get_global_rect().end.x <= own.get_global_rect().end.x - 15.5 and (own_fade.texture as GradientTexture2D).gradient.get_color(1) == Color("14312f"),"A clipped friend code fades into the field fill, inside its padding, at %d wide" % width)
		for code: Button in view.find_children("FriendRowCode","Button",true,false):
			var fade: TextureRect = code.get_node_or_null("CodeFade")
			var text_width := code.get_theme_font("font").get_string_size(code.text,HORIZONTAL_ALIGNMENT_LEFT,-1,code.get_theme_font_size("font_size")).x
			var clipped := text_width > code.size.x + 0.5
			check(fade != null and fade.visible == clipped and (fade.texture as GradientTexture2D).gradient.get_color(1) == Color("123936"),"A row code fades into the card exactly when clipped at %d wide" % width)
			row_fades[clipped] = true
		if width >= 1280:
			# Side by side, the code columns line up with the panels' content edges above.
			var friends_panel: Control = view.find_child("FriendsAndRoom",true,false).get_child(0)
			var room_panel: Control = view.find_child("FriendsAndRoom",true,false).get_child(1)
			var friends_inner: float = friends_panel.get_global_rect().end.x - float(view._friends_inset())
			var room_inner: float = room_panel.get_global_rect().position.x + float(view._room_inset())
			var share_end: float = view.find_child("ShareInviteLink",true,false).get_global_rect().end.x
			var field_start: float = view.find_child("FriendCode",true,false).get_global_rect().position.x
			check(absf(share_end - friends_inner) <= 1.0 and absf(field_start - room_inner) <= 1.0,"Share Invite ends at the friends panel's inner edge and the friend code field starts at the room panel's (%.1f/%.1f, %.1f/%.1f) at %d" % [share_end,friends_inner,field_start,room_inner,width])
			check(view.find_child("FriendCode",true,false).size.x >= 200.0,"The add field keeps its usable width at %d" % width)
		var copy_square: Control = view.find_child("CopyFriendCode",true,false)
		check(copy_square != null and absf(copy_square.size.x - copy_square.size.y) <= 0.5 and copy_square.size.x <= 60.0,"Copy stays a square, never stretched, at %d wide" % width)
		var copy: Control = view.find_child("CopyFriendCode",true,false)
		var share: Control = view.find_child("ShareInviteLink",true,false)
		if own != null and copy != null and share != null:
			var rects := [own.get_global_rect(),copy.get_global_rect(),share.get_global_rect()]
			check(not rects[0].intersects(rects[1]) and not rects[1].intersects(rects[2]) and not rects[0].intersects(rects[2]),"The code field and its buttons never overlap at %d wide" % width)
		view.queue_free()
		viewport.queue_free()
		await process_frame
	# Short ids never clip, so the fade stays hidden.
	var probe := Screen.new()
	probe.client = client
	root.add_child(probe)
	for _i in 3: await process_frame
	var short_field: LineEdit = probe.find_child("OwnFriendCode",true,false)
	if short_field != null:
		short_field.text = "friend-AB"
		probe._place_code_fade(short_field)
		check(not (short_field.get_node("CodeFade") as TextureRect).visible,"A code that fits shows no fade")
	probe.queue_free()
	await process_frame
	check(row_fades.has(true) and row_fades.has(false),"Row codes were seen both clipped (faded) and fitting (unfaded)")
	check(not own_clipped.is_empty(),"A full friend code is clipped and faded at narrower widths %s" % [own_clipped])

func _row_code_copy(copied: Array) -> void:
	var code: Button = screen.find_child("FriendRowCode",true,false)
	check(code != null,"A friend row shows its code")
	if code == null: return
	check(code.size.y < 44.0 and code._has_point(Vector2(code.size.x * 0.5,43.0)) and not code._has_point(Vector2(code.size.x * 0.5,45.0)) and code.hit_height >= 44.0,"The row code keeps one text line but takes taps across 44 units")
	copied.clear()
	code.size.x = 60.0
	code.pressed.emit()
	check(copied.size() == 1 and copied[0] == "friend-" + PEER,"Tapping a clipped row code copies the full typed code")
	check(code.icon != null,"The row code shows a tick after copying")
	await create_timer(1.4).timeout
	check(is_instance_valid(code) and code.icon == null,"The row code's tick clears")
	var normal := code.get_theme_stylebox("hover")
	check(normal is StyleBoxEmpty and code.get_theme_color("font_hover_color") != code.get_theme_color("font_color"),"Hover only brightens the code text, with no fill")

func _background_join() -> void:
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	release.emit()

func _close_during_mutation() -> void:
	screen._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	release.emit()

func find_button(node: Node, text: String) -> Button:
	if node is Button and (node.text == text or node.tooltip_text == text): return node
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

func _cached_feedback_and_empty_room() -> void:
	now += 60000
	response = {"ok":true,"data":page()}
	response.data.friends[0].join_available = false
	await client.refresh()
	screen = Screen.new()
	screen.client = client
	root.add_child(screen)
	await process_frame
	response = {"ok":false,"code":"friend_not_joinable"}
	await screen._act("join",client.view().friends[0])
	check(screen._message == "Room unavailable","A fresh unavailable-room reply is shown on the active screen")
	var count := calls.size()
	screen.close()
	await process_frame
	screen = Screen.new()
	screen.client = client
	root.add_child(screen)
	await process_frame
	check(screen._message.is_empty() and find_label(screen,"Room unavailable") == null and calls.size() == count,"Reopening with a successful cached page does not redisplay the old room error or poll")
	check(client.last_error == "Room unavailable","Clearing screen feedback leaves the client's action result intact")
	await screen._refresh()
	check(screen._message.is_empty() and calls.size() == count,"A successful cached refresh also keeps the stale action error hidden")
	now += 60000
	response = {"ok":false,"code":"offline"}
	await screen._refresh()
	check(calls.size() == count + 1 and screen._message == "Friends unavailable" and find_label(screen,"Friends unavailable") != null,"A fresh failed list request still displays its current error")
	var title := find_label(screen,"No current room")
	var host := find_button(screen,"Host a room")
	check(title != null and find_label(screen,"Host a room") == null and find_label(screen,"Choose a chapter to host, then share it with friends.") != null,"The empty room panel has an explicit state and explains how to start")
	check(host != null and not host.disabled and title != null and host.get_parent() == title.get_parent() and host.size_flags_horizontal == Control.SIZE_EXPAND_FILL,"Empty-room Host is a prominent usable button in the panel body")
	var host_buttons := screen.find_children("*","Button",true,false).filter(func(button: Button): return button.text == "Host a room")
	check(host_buttons.size() == 1,"The empty room panel has one Host action without a duplicate header link")
	var host_events: Array = []
	screen.host_requested.connect(func(): host_events.append(true))
	count = calls.size()
	if host != null: host.pressed.emit()
	check(host_events.size() == 1 and not screen._alive and calls.size() == count,"The empty-room Host button emits navigation and closes without creating a room itself")
	await process_frame

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
	# The friend's shared room becomes visible, so a direct Join is offered even
	# though the friend is offline.
	now += 60000
	response = {"ok":true,"data":page()}
	response.data.friends[0].online = false
	response.data.friends[0].expires_after_seconds = 0
	await client.refresh()
	root.add_child(screen)
	await process_frame
	check(find_button(screen,"Join") != null,"Reopening offers a direct Join for an offline friend's shared room")
	var code := "0123456789ABCDEF0123"
	response = {"ok":true,"data":{"schema_version":1,"api_version":2,"room_id":("v2:"+code).sha256_text().substr(0,22),"invite_code":code}}
	closed_before = closes
	count = calls.size()
	await screen._act("join",client.view().friends[0])
	check(joins == 1 and closes == closed_before + 1 and calls.size() == count + 1,"A direct Join opens the newly shared offline room without a list poll")
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

class AlertStub extends RefCounted:
	var inbox_calls := 0
	func inbox() -> Dictionary:
		inbox_calls += 1
		return {"ok":true,"data":{"events":[],"preferences":[]}}
	var busy := false
	var calls: Array = []
	func set_hosting_alert(_peer: Dictionary, enabled: bool) -> bool:
		calls.append(enabled)
		return true
