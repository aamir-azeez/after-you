extends "res://tests/test_friends_navigation.gd"
## The pop-up (presentation/toast.gd): its held line, Reduce motion, safe area
## and layer, and Friends news through it: no View on Friends, View elsewhere,
## and a View that waits while play is in the way.
const Toast = preload("res://presentation/toast.gd")
const Copy = preload("res://presentation/player_copy.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
## A synthetic friend who sends this player a request.
const ASKER := "QQQQQQQQQQQQQQQQQQQQQQ"
var reduced := false
var requested := false

class FreshMain:
	extends "res://main.gd"
	func _new_relay_session() -> RefCounted:
		var session := super._new_relay_session()
		session._store = preload("res://tests/test_relay_online.gd").MemoryStore.new()
		return session

func _run() -> void:
	await _component()
	await _in_app()
	print("TOAST: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _toast() -> Toast:
	var toast := Toast.new()
	toast.reduced_motion = func() -> bool: return reduced
	root.add_child(toast)
	toast.set_process(false)
	return toast

func _component() -> void:
	var toast := _toast()
	await process_frame
	_check(toast.layer > 50 and toast.layer > 60 and toast.layer < 100,"The pop-up draws above Friends (50) and the room hub (60), under the version badge")
	_check(toast.card.mouse_filter == Control.MOUSE_FILTER_IGNORE and toast.label.mouse_filter == Control.MOUSE_FILTER_IGNORE,"The card lets taps through to the screen under it")
	toast.post("Plain line")
	_check(toast.visible and toast.text == "Plain line" and not toast._action.visible and not toast._icon_disc.visible and toast.label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,"A plain line keeps today's centred look")
	_check(is_equal_approx(toast.card.size.x,Toast.WIDTH) and is_equal_approx(toast.card.size.y,Toast.HEIGHT) and is_equal_approx(toast.card.position.y,Toast.TOP),"It keeps today's size and spot")
	var pressed := [0]
	toast.post("New friend request",Toast.FRIENDS_ICON,"View",func() -> void: pressed[0] += 1)
	_check(toast.text == "New friend request" and toast._action.visible and toast._action.text == "View" and toast._icon_disc.visible and toast.label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,"Friend news gets the icon, left text and its View")
	_check(toast._action.mouse_filter == Control.MOUSE_FILTER_STOP and toast._bar.visible,"Only View takes taps, and the bar shows the time left")
	toast.post("Error line")
	_check(toast.text == "Error line" and not toast._action.visible and toast._held.get("text") == "New friend request","A plain line shows at once and holds the View line")
	toast._process(1.0)
	toast.post("Second error")
	_check(toast.text == "Second error" and toast._held.get("text") == "New friend request","A plain line replaces a plain line at once and the View line stays held")
	toast._process(Toast.SHOW_SEC + 0.1)
	_check(toast.showing() and toast.text == "New friend request" and toast._action.visible and toast._current.left >= Toast.HELD_MIN_SEC,"The held View line comes back once the plain line goes")
	toast.post("Room available",Toast.FRIENDS_ICON,"View",func() -> void: pass)
	toast.post("Third error")
	_check(toast._held.get("text") == "Room available","A newer View line replaces the held one")
	toast._process(Toast.SHOW_SEC + 0.1)
	toast._action.pressed.emit()
	_check(not toast.visible and pressed[0] == 0 and toast._held.is_empty(),"View runs its own line's action and closes the pop-up")
	toast.post("New friend request",Toast.FRIENDS_ICON,"View",func() -> void: pressed[0] += 1)
	toast._action.pressed.emit()
	toast._action.pressed.emit()
	_check(pressed[0] == 1 and not toast.visible,"View runs once")
	# The hub takes a plain line for its own notice; a held View line comes back.
	toast.post("New friend request",Toast.FRIENDS_ICON,"View",func() -> void: pass)
	toast.post("Room unavailable")
	_check(toast.take_plain() == "Room unavailable" and toast.showing() and toast.text == "New friend request" and toast._action.visible,"The hub takes the plain line and the held View line comes back")
	_check(toast.take_plain() == "" and toast.showing(),"A View line is never taken as a plain notice")
	toast.post("Plain after")
	toast.drop_actions()
	_check(toast.showing() and toast.text == "Plain after" and toast._held.is_empty(),"Dropping action lines keeps the plain line and forgets the held View")
	toast.post("Room available",Toast.FRIENDS_ICON,"View",func() -> void: pass)
	toast.drop_actions()
	_check(not toast.visible,"Dropping action lines closes a View line that shows")
	# Motion: a fade and a draining bar, or neither with Reduce motion.
	reduced = false
	toast.post("Fading",Toast.FRIENDS_ICON)
	_check(toast.visible and toast._root.modulate.a < 0.01 and toast._bar.visible,"Without Reduce motion the pop-up fades in")
	toast._process(Toast.FADE_SEC * 2.0)
	_check(toast._root.modulate.a > 0.99,"The fade in ends")
	toast._process(Toast.SHOW_SEC)
	_check(toast.visible and toast._fade < 0,"It fades out at the end")
	toast._process(Toast.FADE_SEC * 2.0)
	_check(not toast.visible,"The fade out ends hidden")
	reduced = true
	toast.post("Still",Toast.FRIENDS_ICON)
	_check(toast.visible and toast._root.modulate.a > 0.99 and not toast._bar.visible,"With Reduce motion it shows at once without the draining bar")
	var placed := toast.card.position
	toast._process(1.0)
	_check(toast.card.position == placed and not toast._bar.visible,"With Reduce motion nothing moves while it shows")
	toast._process(Toast.SHOW_SEC)
	_check(not toast.visible,"With Reduce motion it goes at once")
	reduced = false
	# Header row and safe area.
	toast.in_header = func() -> bool: return true
	toast.post("New friend request",Toast.FRIENDS_ICON)
	_check(is_equal_approx(toast.card.position.y,Toast.HEADER_TOP) and toast.card.size.x <= Toast.HEADER_WIDTH,"With a header row it sits in that row")
	await process_frame
	await process_frame
	_check(toast.card.get_global_rect().grow(0.5).encloses(toast.label.get_global_rect()) and toast.card.get_global_rect().grow(0.5).encloses(toast._icon_disc.get_global_rect()),"Its icon and line sit inside the card in the header row: card %s line %s" % [toast.card.get_global_rect(),toast.label.get_global_rect()])
	toast.in_header = Callable()
	# A left camera cutout, in the screen's own pixels (as test_cutout_full_bleed does).
	var native := toast.get_viewport().get_screen_transform() * toast.get_viewport().get_visible_rect()
	SafeArea.simulate(Rect2(native.position + Vector2(native.size.x * 0.1, 0), native.size - Vector2(native.size.x * 0.1, 0)))
	toast._place()
	var safe := SafeArea.rect(toast.get_viewport())
	_check(safe != toast.get_viewport().get_visible_rect() and safe.encloses(toast.card.get_global_rect()) and is_equal_approx(toast.card.position.y,safe.position.y + Toast.TOP) and is_equal_approx(toast.card.get_global_rect().get_center().x,safe.get_center().x),"It keeps inside the safe area under a camera cutout: safe %s card %s" % [safe,toast.card.get_global_rect()])
	SafeArea.simulate(Rect2())
	toast.post("A long line that wraps ".repeat(8))
	_check(toast.card.size.y > Toast.HEIGHT and toast.label.get_line_count() >= 2,"A long line grows the card instead of spilling out")
	toast.queue_free()
	await process_frame

func _in_app() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var path := "user://toast-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var app := FreshMain.new()
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
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id":HOST,"device_token":"synthetic-device-token"}
	app._show_home()
	await process_frame
	_check(app.toast.get_parent() == app and app.toast.layer > 60,"Main's pop-up is its own layer above Friends and the hub")
	app.saves.data.settings.reduced_motion = true
	_check(app.toast._reduced(),"Main's pop-up follows the Reduce motion setting")
	app.saves.data.settings.reduced_motion = false
	# Friends: its lines go to the pop-up, in the header row, news without View.
	await app._show_friends()
	await process_frame
	_check(app.friends_flow.is_open() and app.toast.layer > app.friends_flow.screen.layer,"The pop-up draws above the open Friends screen")
	app.friends_flow.screen.notice.emit("New friend request",true)
	_check(app.toast.showing() and app.toast.text == "New friend request" and not app.toast._action.visible and app.toast._icon_disc.visible,"On Friends a new request shows without View, since its row is on the page")
	_check(is_equal_approx(app.toast.card.position.y,Toast.HEADER_TOP),"On Friends it sits in the header row")
	await process_frame
	await process_frame
	_check(app.toast.card.get_global_rect().grow(0.5).encloses(app.toast.label.get_global_rect()),"On Friends its line sits inside the card: card %s line %s" % [app.toast.card.get_global_rect(),app.toast.label.get_global_rect()])
	app.friends_flow.screen.notice.emit("Friends unavailable",false)
	_check(app.toast.text == "Friends unavailable" and not app.toast._icon_disc.visible,"A Friends error keeps its text and the plain look")
	app.toast.dismiss()
	app.friends_flow.screen.close()
	await process_frame
	_check(app.mode == "home" and not app.friends_flow.is_open(),"Back on Home")
	# Elsewhere: View opens Friends.
	app.notification_flow._friends_news("New friend request")
	_check(app.toast.showing() and app.toast._action.visible and app.toast._action.text == Copy.FRIENDS_VIEW and is_equal_approx(app.toast.card.position.y,Toast.TOP),"On Home a request offers View in the usual spot")
	app.toast._action.pressed.emit()
	for _i in 4: await process_frame
	_check(app.friends_flow.is_open() and app.mode == "friends","View opens Friends")
	app.friends_flow.screen.close()
	await process_frame
	# In play: View waits quietly and opens Friends after.
	app.notification_flow._friends_news("New friend request")
	app.running = true
	app.toast._action.pressed.emit()
	await process_frame
	app.notification_flow.service_friends()
	await process_frame
	_check(not app.friends_flow.is_open() and not app.toast.showing() and not app.notification_flow._view_wanted.is_empty(),"View during play waits without a line")
	app.running = false
	app.notification_flow.service_friends()
	for _i in 4: await process_frame
	_check(app.friends_flow.is_open(),"Friends opens once play is over")
	app.friends_flow.screen.close()
	await process_frame
	# A View from an older identity does nothing.
	app.notification_flow._friends_news("New friend request")
	app.relay_identity_epoch += 1
	app.toast._action.pressed.emit()
	app.notification_flow.service_friends()
	for _i in 3: await process_frame
	_check(not app.friends_flow.is_open() and app.notification_flow._view_wanted.is_empty(),"A View from before an identity change does nothing")
	# A live request hint on another screen reads the list once and offers View.
	app.toast.dismiss()
	requested = true
	friend_clock = Time.get_ticks_msec() + 600000
	app.friends_client.clock_ms = func() -> int: return friend_clock
	var reads := _friend_reads(api)
	app.live_connection.friends_changed.emit(true)
	app.notification_flow.service_friends()
	for _i in 3: await process_frame
	_check(_friend_reads(api) == reads and not app.toast.showing(),"An early friends hint (a shared room) reads nothing off Friends")
	app.live_connection.friends_changed.emit(false)
	app.notification_flow.service_friends()
	for _i in 4: await process_frame
	_check(_friend_reads(api) == reads + 1 and app.toast.showing() and app.toast.text.begins_with("New friend request") and app.toast._action.visible,"A request hint off Friends reads the list once and offers View")
	app.live_connection.friends_changed.emit(false)
	app.notification_flow.service_friends()
	for _i in 3: await process_frame
	_check(_friend_reads(api) == reads + 1,"A second hint waits for the list's own floor")
	app.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)

func _friend_reads(api: FakeApi) -> int:
	return api.calls.filter(func(call: Dictionary) -> bool: return call.path == "/v1/friends" and call.method == HTTPClient.METHOD_GET).size()

func _server(request: Dictionary, api: FakeApi) -> Dictionary:
	if request.path == "/v1/friends" and requested:
		return _ok({"schema_version":1,"friend_code":request.owner,"refresh_after_seconds":30,"shared_room":null,"friends":[{"player_id":ASKER,"request_id":"R".repeat(22),"status":"incoming","online":false,"join_available":false,"expires_after_seconds":0}]})
	return super._server(request,api)
