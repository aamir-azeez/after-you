extends "res://tests/test_friends_navigation.gd"
## Invite links through the real app with a fake native inbox: cold and warm delivery,
## duplicates, invalid links and confirmation before any request.
const ShareCodes = preload("res://services/share_codes.gd")
const InviteShare = preload("res://services/invite_share.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ChapterLoadingCard = preload("res://presentation/chapter_loading_card.gd")
const InviteLinkBridge = preload("res://services/invite_link_bridge.gd")
const PEER := "PPPPPPPPPPPPPPPPPPPPPP"
const OTHER := "Qq_-abcdefghijklmnopqr"
var friend_rows: Array = []

## Same single-slot, take-once contract as the Android inbox.
class FakeNative extends Node:
	signal invite_link_available
	var pending := ""
	var takes := 0
	func invite_link_take() -> String:
		takes += 1
		var value := pending
		pending = ""
		return value
	func offer(value: String) -> void:
		pending = value
		invite_link_available.emit()

class LinkMain:
	extends "res://main.gd"
	var toasts: Array[String] = []
	var friends_fail := false
	var friends_opens := 0
	func _show_friends(_report: Callable = Callable()) -> void:
		friends_opens += 1
		if friends_fail: return
		await super._show_friends()
	func _toast(text: String) -> void:
		toasts.append(text)
		super._toast(text)
	func _new_relay_session() -> RefCounted:
		var session := super._new_relay_session()
		session._store = preload("res://tests/test_relay_online.gd").MemoryStore.new()
		return session

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var path := "user://invite-links-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var native := FakeNative.new()
	root.add_child(native)
	# Cold start: the launch link waits in the native inbox before Main starts.
	native.pending = ShareCodes.link(ShareCodes.FRIEND,PEER)
	var app := LinkMain.new()
	app.invite_link_native = native
	app.saves = Save.new(path)
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	app.saves.flush()
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := _api()
	root.remove_child(api)
	app.add_child(api)
	app.api = api
	_check(PEER.length() == 22 and OTHER.length() == 22,"Fixtures use the server friend ID shape")
	var received := [0]
	app.invite_link_bridge.received.connect(func(_result: Dictionary): received[0] += 1)
	await _frames(3)
	_check(native.takes >= 1 and native.pending.is_empty() and app.invite_link_pending == PEER,"Cold start takes the launch link once and keeps it pending in memory")
	_check(not FileAccess.get_file_as_string(path).contains(PEER),"A pending invite link is never written to the save")
	# Identity not ready yet: wait quietly, without navigation or requests.
	await app._service_invite_link()
	_check(app.invite_link_pending == PEER and not app.friends_flow.is_open() and api.calls.is_empty() and app.toasts.is_empty(),"An unread identity keeps the link pending without a message or request")
	# No identity yet: a link from outside never creates one. It waits for the player's own Friends visit.
	app.identity_read_state = Main.IdentityReadState.MISSING
	api.player_id = ""
	for _i in 3: await app._service_invite_link()
	await _frames(2)
	_check(app.invite_link_pending == PEER and app.friends_opens == 0 and not app.friends_flow.is_open() and app.toasts.is_empty(),"Without an identity the link stays pending quietly and Friends is not opened")
	_check(api.calls.filter(func(call: Dictionary) -> bool: return call.path == "/v1/identity").is_empty() and api.calls.is_empty(),"A link never posts a new identity or makes any request")
	# The player opens Friends themselves (their identity is ready after that visit).
	api.player_id = HOST
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id":HOST,"device_token":"synthetic-device-token"}
	await app._show_friends()
	await _frames(2)
	_check(app.mode == "friends" and _modal(app) == null and app.invite_link_pending == PEER,"Opening Friends leaves the link for the next safe check")
	await app._service_invite_link()
	await _frames(3)
	var modal := _modal(app)
	_check(app.mode == "friends" and app.friends_flow.is_open() and modal != null,"Once the player is in Friends with an identity the invite confirmation opens")
	_check(app.friends_opens == 1,"The link reused the Friends screen the player opened")
	_check(app.invite_link_pending.is_empty(),"The pending link is cleared after one use")
	_check(modal != null and _label_in(modal,"friend-"+PEER) and _label_in(modal,PlayerCopy.INVITE_LINK_TITLE),"The confirmation names the typed friend code")
	_check(_requests(api).is_empty(),"Opening an invite link never adds a friend by itself")
	if modal != null:
		var confirm: Button = modal.find_child("ModalConfirm",true,false)
		var cancel: Button = modal.find_child("ModalCancel",true,false)
		_check(confirm != null and confirm.text == "Add friend" and not confirm.has_theme_stylebox_override("normal"),"Add friend is the theme's cream primary")
		var outline: StyleBoxFlat = cancel.get_theme_stylebox("normal") if cancel != null else null
		_check(cancel != null and cancel.text == "Cancel" and outline != null and outline.border_width_left > 0 and outline.bg_color != Color("eceddb") and outline.bg_color != Color("e9b3aa"),"Cancel is an outlined secondary, not coral or cream")
		if cancel != null: cancel.pressed.emit()
	await _frames(2)
	_check(_modal(app) == null and _requests(api).is_empty() and app.friends_flow.is_open(),"Cancel closes the confirmation and sends nothing")
	# Warm link from Home; duplicate hints and resume polls deliver it once.
	app.friends_flow.screen.close()
	await _frames(1)
	app._show_home()
	native.offer(ShareCodes.link(ShareCodes.FRIEND,OTHER).replace("#","?c="))
	await _frames(2)
	var before: int = received[0]
	native.invite_link_available.emit()
	app.invite_link_bridge._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _frames(2)
	_check(received[0] == before and app.invite_link_pending == OTHER,"Duplicate native hints and resume polls deliver a warm link once")
	await app._service_invite_link()
	await _frames(3)
	modal = _modal(app)
	_check(modal != null and _label_in(modal,"friend-"+OTHER) and app.friends_flow.screen.find_children("InviteLinkModal","",true,false).size() == 1,"The warm query-form link opens one confirmation for that friend")
	if modal != null:
		var confirm: Button = modal.find_child("ModalConfirm",true,false)
		_check(confirm.disabled,"Add friend starts disabled right after the automatic navigation")
		confirm.pressed.emit()
		await _frames(2)
		_check(_modal(app) == modal and _requests(api).is_empty(),"An immediate stray press does not confirm")
		await create_timer(0.5).timeout
		_check(not confirm.disabled,"Add friend arms after a short delay")
		confirm.pressed.emit()
		confirm.pressed.emit()
	await _frames(3)
	var adds := _requests(api)
	_check(adds.size() == 1 and adds[0].body == {"schema_version":1,"friend_code":OTHER},"Confirm uses the existing add path once with the bare ID")
	_check(app.friends_flow.screen._message.is_empty() and _screen_label(app.friends_flow.screen,"Request sent"),"The new request appears through the normal add result")
	# Invalid links are ignored with the existing gentle error.
	for bad: String in ["invalid","https://evil.test/after-you/link#friend-"+PEER,"https://aamirazeez.com/after-you/link#room-0123456789ABCDEF0123"]:
		app.toasts.clear()
		native.offer(bad)
		await _frames(2)
		_check(app.toasts == [PlayerCopy.FRIEND_CODE_INVALID] and app.invite_link_pending.is_empty() and _modal(app) == null,"An invalid link shows only the existing error: "+bad)
	# Own code and an existing friend use messages, never a confirmation.
	native.offer(ShareCodes.link(ShareCodes.FRIEND,HOST))
	await _frames(2)
	await app._service_invite_link()
	await _frames(2)
	_check(_modal(app) == null and app.friends_flow.screen._message == PlayerCopy.FRIEND_CODE_OWN,"Your own invite link explains itself without a confirmation")
	friend_rows = [{"player_id":PEER,"request_id":"R".repeat(22),"status":"accepted","online":false,"expires_after_seconds":0,"join_available":false}]
	app.friends_client.invalidate()
	await app.friends_flow.screen._refresh(true)
	native.offer(ShareCodes.link(ShareCodes.FRIEND,PEER))
	await _frames(2)
	await app._service_invite_link()
	await _frames(2)
	_check(_modal(app) == null and app.friends_flow.screen._message == PlayerCopy.FRIEND_ALREADY_ADDED,"An existing friend's link says you are already friends")
	_check(_requests(api).size() == 1,"Own and existing-friend links send no request")
	# A short-name link opens the same confirmation, naming friend-<name>.
	native.offer("https://aamirazeez.com/after-you/link#friend-Aamir")
	await _frames(2)
	_check(app.invite_link_pending == "aamir","A short-name link arrives lowercased")
	await app._service_invite_link()
	await _frames(3)
	var named := _modal(app)
	_check(named != null and _label_in(named,"friend-aamir") and _requests(api).size() == 1,"A short-name link asks before adding")
	if named != null: (named.find_child("ModalCancel",true,false) as Button).pressed.emit()
	await _frames(2)
	# Active play defers the link with one short note, then opens it when safe.
	app.friends_flow.screen.close()
	await _frames(1)
	app._show_home()
	app.running = true
	app.toasts.clear()
	native.offer(ShareCodes.link(ShareCodes.FRIEND,"Z".repeat(22)))
	await _frames(2)
	await app._service_invite_link()
	await app._service_invite_link()
	_check(app.toasts == [PlayerCopy.INVITE_LINK_WAITING] and not app.friends_flow.is_open() and app.invite_link_pending == "Z".repeat(22),"Gameplay keeps the link and notes it once")
	app.running = false
	await app._service_invite_link()
	await _frames(3)
	_check(_modal(app) != null and _label_in(_modal(app),"friend-"+"Z".repeat(22)),"Leaving play opens the waiting confirmation")
	app.friends_flow.screen.close()
	await _frames(1)
	# Bounded: expiry and an identity change both drop an unopened link.
	app._show_home()
	native.offer(ShareCodes.link(ShareCodes.FRIEND,PEER))
	await _frames(2)
	app.invite_link_expires_ms = 0
	await app._service_invite_link()
	_check(app.invite_link_pending.is_empty() and not app.friends_flow.is_open(),"An expired link is dropped without navigation")
	native.offer(ShareCodes.link(ShareCodes.FRIEND,PEER))
	await _frames(2)
	app.invite_link_busy = true
	app.invite_link_expires_ms = 0
	await app._service_invite_link()
	app.invite_link_busy = false
	_check(app.invite_link_pending.is_empty(),"Expiry is checked even while an earlier open is still in progress")
	# Three failed opens drop the link; the retry delay spaces them out.
	native.offer(ShareCodes.link(ShareCodes.FRIEND,PEER))
	await _frames(2)
	app.friends_fail = true
	app.friends_opens = 0
	await app._service_invite_link()
	await app._service_invite_link()
	_check(app.friends_opens == 1 and app.invite_link_attempts == 1 and app.invite_link_pending == PEER,"A failed open waits for the retry delay")
	app.invite_link_retry_ms = 0
	await app._service_invite_link()
	_check(app.friends_opens == 2 and app.invite_link_pending == PEER,"A second failed open keeps the link")
	app.invite_link_retry_ms = 0
	await app._service_invite_link()
	_check(app.friends_opens == 3 and app.invite_link_pending.is_empty(),"The third failed open drops the link")
	app.invite_link_retry_ms = 0
	await app._service_invite_link()
	_check(app.friends_opens == 3,"No open is attempted after the retries are used up")
	app.friends_fail = false
	await _blocked_cases(app,native,api)
	native.offer(ShareCodes.link(ShareCodes.FRIEND,PEER))
	await _frames(2)
	app._invalidate_relay_identity()
	_check(app.invite_link_pending.is_empty(),"Identity recovery or deletion drops an unopened link")
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id":HOST,"device_token":"synthetic-device-token"}
	await _home_share(app,api)
	await _typed_room_joins(app,api)
	app.queue_free()
	await process_frame
	viewport.queue_free()
	native.queue_free()
	await process_frame
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	await _waiting_link_outlives_main()
	print("INVITE LINKS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

## Home "Invite your friends" uses the Friends share path; a not-ready identity
## goes through the Friends entry and its existing message instead.
func _home_share(app: Node, api: FakeApi) -> void:
	app._show_home()
	await _frames(2)
	var share: Button = app.overlay.find_child("HomeInvite",true,false)
	_check(share != null and share.is_visible_in_tree() and share.text == PlayerCopy.HOME_INVITE and share.icon != null and share.tooltip_text == PlayerCopy.INVITE_LINK_SHARE and share.size.y >= 48,"Home offers Invite your friends with its share icon")
	if share == null: return
	var shared: Array = []
	var copied: Array = []
	var sheet := [true]
	app.invite_share_text = func(text: String) -> bool:
		shared.append(text)
		return sheet[0]
	app.invite_clipboard_copy = func(text: String) -> void: copied.append(text)
	var calls: int = api.calls.size()
	share.pressed.emit()
	await _frames(2)
	_check(shared == [InviteShare.message(HOST)] and copied.is_empty(),"Home sends the invite link plus friend code once")
	_check(shared.size() == 1 and shared[0].contains(ShareCodes.link(ShareCodes.FRIEND,HOST)) and shared[0].contains("friend-"+HOST),"The Home share text has both the link and the typed code")
	_check(app.mode == "home" and not app.friends_flow.is_open() and api.calls.size() == calls,"Sharing from Home stays on Home and makes no request")
	sheet[0] = false
	shared.clear()
	share.pressed.emit()
	await _frames(2)
	_check(shared.size() == 1 and copied == ["friend-"+HOST],"Without a share sheet Home copies the friend code, like Friends")
	# Not ready: the existing Friends entry checks identity and shows its message.
	shared.clear()
	copied.clear()
	app.toasts.clear()
	api.player_id = ""
	app.identity_read_state = Main.IdentityReadState.MISSING
	share.pressed.emit()
	await _frames(3)
	_check(shared.is_empty() and copied.is_empty() and app.mode == "home" and app.toasts.size() == 1 and app.toasts[0] == PlayerCopy.MAIN_3E8E7DA4CEE6,"A not-ready identity routes to the Friends entry and its existing message")
	api.player_id = HOST
	app.identity_read_state = Main.IdentityReadState.LOADED

## Busy or unlisted states keep the link without navigating; only real activity notes it.
func _blocked_cases(app: Node, native: FakeNative, api: FakeApi) -> void:
	app._show_home()
	await _frames(1)
	var cases := [
		["room draft", func(): app.saves.data.room_draft = {"room_id":"X"}, func(): app.saves.data.room_draft = {}, true],
		["journey mode", func(): app.mode = "journey", func(): app.mode = "home", true],
		["foreground refresh", func(): app.foreground_refresh_running = true, func(): app.foreground_refresh_running = false, false],
	]
	for entry: Array in cases:
		app.toasts.clear()
		native.offer(ShareCodes.link(ShareCodes.FRIEND,PEER))
		await _frames(2)
		entry[1].call()
		app.friends_opens = 0
		await app._service_invite_link()
		await app._service_invite_link()
		var noted: bool = app.toasts == [PlayerCopy.INVITE_LINK_WAITING]
		_check(app.friends_opens == 0 and app.invite_link_pending == PEER and noted == entry[3] and (noted or app.toasts.is_empty()),"%s keeps the link %s" % [entry[0],"with one note" if entry[3] else "quietly"])
		entry[2].call()
		app.invite_link_pending = ""
	# Read-only saves cannot open Friends: the link is dropped without a message.
	app.toasts.clear()
	native.offer(ShareCodes.link(ShareCodes.FRIEND,PEER))
	await _frames(2)
	app.saves.read_only = true
	await app._service_invite_link()
	app.saves.read_only = false
	_check(app.invite_link_pending.is_empty() and app.toasts.is_empty() and app.friends_opens == 0,"Read-only saves drop the link without the waiting note")

## Typed room-<code> input reaches the hub resolver and the legacy join as the bare code.
func _typed_room_joins(app: Node, api: FakeApi) -> void:
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	if app.relay_session == null: app.relay_session = app._new_relay_session()
	app.toasts.clear()
	await app.room_hub_flow.show_rooms()
	await _frames(2)
	var before: int = api.calls.size()
	await app.room_hub_flow._join("friend-" + PEER)
	_check(api.calls.size() == before and is_instance_valid(app.room_hub_flow.screen) and app.room_hub_flow.screen._message == PlayerCopy.SHARE_CODE_FRIEND_NOT_ROOM,"A friend code in the room hub is rejected locally with a clear message the player sees on the hub")
	await app.room_hub_flow._join("room-" + "a1".repeat(10))
	var resolved: Array = api.calls.slice(before).filter(func(call: Dictionary) -> bool: return call.path == "/v1/invitations/resolve")
	_check(resolved.size() == 1 and resolved[0].body == {"invite_code":"A1".repeat(10)},"The room hub resolves a typed room code as the bare code")
	# With the resolver live its parsed reply carries api_version 2.0, which must still join.
	resolve_reply = {"schema_version":1,"family":"relay","api_version":2}
	app.toasts.clear()
	await app.room_hub_flow.show_rooms()
	await _frames(2)
	before = api.calls.size()
	await app.room_hub_flow._join("room-" + "a1".repeat(10))
	await _frames(2)
	var joined: Array = api.calls.slice(before).filter(func(call: Dictionary) -> bool: return call.path == "/v2/rooms/join")
	_check(not app.toasts.has("Invitation unavailable") and joined.size() == 1 and joined[0].body.invite_code == "A1".repeat(10),"A resolved chapter code from the room hub joins instead of showing Invitation unavailable")
	resolve_reply = {}
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	await _frames(2)
	before = api.calls.size()
	app._show_home()
	await _frames(2)
	await app._join_room("room-" + LEGACY_CODE)
	var joins: Array = api.calls.slice(before).filter(func(call: Dictionary) -> bool: return call.path == "/v1/rooms/join")
	_check(joins.size() == 1 and joins[0].body.invite_code == LEGACY_CODE,"The legacy join sends a typed room code as the bare code")

func _frames(count: int) -> void:
	for _i in count: await process_frame

func _modal(app: Node) -> Control:
	if not app.friends_flow.is_open(): return null
	var found: Node = app.friends_flow.screen.find_child("InviteLinkModal",true,false)
	return found if found is Control and not found.is_queued_for_deletion() else null

func _label_in(node: Node, text: String) -> bool:
	return node.find_children("*","Label",true,false).any(func(label: Label) -> bool: return label.text == text)

func _screen_label(screen: Node, text: String) -> bool:
	return _label_in(screen,text)

func _requests(api: FakeApi) -> Array:
	return api.calls.filter(func(call: Dictionary) -> bool: return call.path == "/v1/friends/request")

var resolve_reply: Dictionary = {}
func _server(request: Dictionary, api: FakeApi) -> Dictionary:
	if request.path == "/v1/invitations/resolve" and not resolve_reply.is_empty(): return _ok(resolve_reply)
	if request.path == "/v1/friends":
		var rows: Array = friend_rows.duplicate(true)
		for peer: Dictionary in _added:
			if not rows.any(func(row: Dictionary) -> bool: return row.player_id == peer.player_id): rows.append(peer.duplicate(true))
		return _ok({"schema_version":1,"friend_code":request.owner,"refresh_after_seconds":60,"shared_room":null,"friends":rows})
	if request.path == "/v1/friends/request":
		var row := {"player_id":str(request.body.friend_code),"request_id":"S".repeat(22),"status":"outgoing","online":false,"expires_after_seconds":0,"join_available":false}
		_added.append(row)
		return _ok({"schema_version":1,"player_id":row.player_id,"request_id":row.request_id,"status":"outgoing"})
	return super._server(request,api)

var _added: Array = []

## A link waiting in Play Solo is still there for the Main that comes back after
## a real solo chapter replaced it; an expired one is not.
func _waiting_link_outlives_main() -> void:
	var costs := "user://invite-links-costs-%s.json" % Crypto.new().generate_random_bytes(4).hex_encode()
	ChapterLoadingCard.costs_path = costs
	InviteLinkBridge.take_held()
	change_scene_to_file("res://main.tscn")
	if not await _scene_is("res://main.tscn"): return
	_check(current_scene.invite_link_pending.is_empty(),"A fresh Main starts with no link")
	if not await _scene_is("res://main.tscn"): return
	var app: Node = current_scene
	app._show_journey()
	await _frames(2)
	app._invite_link_received({"ok":true,"type":ShareCodes.FRIEND,"id":PEER})
	_check(app.invite_link_pending == PEER,"A link waits while Play Solo is open")
	var open: Button = null
	for button: Button in app.overlay.find_children("ChapterOpen","Button",true,false):
		if button.is_visible_in_tree() and not button.disabled and open == null: open = button
	_check(open != null,"Play Solo offers a chapter")
	if open == null: return
	open.pressed.emit()
	var chapter := await _scene_changed_from("res://main.tscn")
	_check(not chapter.is_empty(),"The chapter replaced Main (%s)" % chapter)
	if is_instance_valid(current_scene) and current_scene.has_method("_leave"): current_scene._leave(true)
	if not await _scene_is("res://main.tscn"): return
	_check(current_scene.invite_link_pending == PEER,"The Main back from the chapter still holds the waiting link")
	current_scene.invite_link_pending = ""
	InviteLinkBridge.hold(PEER,Time.get_ticks_msec() - 1)
	change_scene_to_file("res://first_steps_preview.tscn")
	await _scene_is("res://first_steps_preview.tscn")
	change_scene_to_file("res://main.tscn")
	if not await _scene_is("res://main.tscn"): return
	_check(current_scene.invite_link_pending.is_empty() and InviteLinkBridge.take_held().is_empty(),"An expired held link is dropped")
	current_scene.queue_free()
	await _frames(3)
	if FileAccess.file_exists(costs): DirAccess.remove_absolute(costs)

func _scene_is(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			await process_frame
			return true
	_check(false,"Scene navigation reaches " + path)
	return false

func _scene_changed_from(path: String) -> String:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path != path and not current_scene.scene_file_path.is_empty():
			for i in range(3): await process_frame
			return current_scene.scene_file_path
	return ""
