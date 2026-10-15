extends "res://tests/test_relay_online.gd"
## Every way out of the room hub lands on a screen the player can use, even
## when the single request slot is busy: Friends, Open and Join wait it out
## with the hub up, say why on the hub when they cannot go on, and Android Back
## always has somewhere to go.

const Copy = preload("res://presentation/player_copy.gd")

func _run() -> void:
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name]=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	root.add_child(viewport)
	var path := "user://hub-exits-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	cleanup_paths.append(path)
	var app := Main.new()
	app.saves=Save.new(path)
	app.saves.data.settings.sound=false
	app.saves.data.settings.haptics=false
	_check(app.saves.flush(),"Prepare isolated muted profile")
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := _api()
	root.remove_child(api)
	app.add_child(api)
	app.api=api
	api.exists=true
	api.joined=true
	app.identity_read_state=Main.IdentityReadState.LOADED
	app.identity_data={"player_id":HOST,"device_token":"synthetic-device-token"}
	app.relay_session=Session.new(api,app._relay_identity,MemoryStore.new())
	if "hub_tap_wait_ms" in app: app.hub_tap_wait_ms=400
	await _friends(app,api)
	await _back_without_hub(app)
	await _open_while_busy(app,api)
	await _join_notices(app,api)
	viewport.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("HUB EXITS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _hub(app: Node) -> void:
	if not is_instance_valid(app.room_hub_screen): app._open_room_hub("",false)
	await _frames(2)

func _friends(app: Node, api: FakeApi) -> void:
	await _hub(app)
	var hub: Node = app.room_hub_screen
	# A saved legacy turn refuses Friends: the hub stays with the reason on it.
	app.saves.data["pending_turn"]={"idempotency_key":"held"}
	hub.friends_requested.emit()
	await _frames(3)
	_check(is_instance_valid(hub) and hub==app.room_hub_screen and app.mode=="rooms" and not is_instance_valid(app.friends_screen),"A refused Friends open keeps the hub instead of a blank screen")
	_check(is_instance_valid(hub) and hub._message==Copy.MAIN_8184DEB41266,"The refusal's reason shows on the hub")
	app.saves.data.erase("pending_turn")
	# A request still out: Friends waits with the hub up, then opens.
	api.busy=true
	hub.friends_requested.emit()
	await _frames(3)
	_check(is_instance_valid(hub) and app.mode=="rooms" and not is_instance_valid(app.friends_screen),"Friends waits with the hub up while a request is out")
	api.busy=false
	await _frames(4)
	_check(is_instance_valid(app.friends_screen) and app.mode=="friends" and not is_instance_valid(app.room_hub_screen),"Friends opens once the request lands, and only then releases the hub")
	if is_instance_valid(app.friends_screen): app.friends_screen.closed.emit()
	await _frames(3)
	# A replay save between retries holds the room session only: Friends never waits for it.
	await _hub(app)
	app.relay_session._transfer_busy=true
	app.room_hub_screen.friends_requested.emit()
	await _frames(2)
	_check(is_instance_valid(app.friends_screen) and app.mode=="friends","Friends opens at once while only a replay save holds the room session")
	app.relay_session._transfer_busy=false
	if is_instance_valid(app.friends_screen): app.friends_screen.closed.emit()
	await _frames(3)
	# A request that never lands: the wait ends on the hub with a reason.
	await _hub(app)
	hub=app.room_hub_screen
	api.busy=true
	hub.friends_requested.emit()
	await create_timer(0.8).timeout
	_check(is_instance_valid(hub) and app.mode=="rooms" and not is_instance_valid(app.friends_screen) and hub._message==Copy.MAIN_8184DEB41266,"A wait that runs out keeps the hub and says why")
	api.busy=false

func _back_without_hub(app: Node) -> void:
	await _hub(app)
	# Some room flow left mode "rooms" without its hub.
	app.room_hub_screen.queue_free()
	app.room_hub_screen=null
	await _frames(1)
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(2)
	_check(app.mode=="home" and app.ui.visible,"Android Back with no hub left goes Home")

func _open_while_busy(app: Node, api: FakeApi) -> void:
	app.mode="rooms"
	await _hub(app)
	var hub: Node=app.room_hub_screen
	# Watch replay on a finished room never waits: its page handles a save in progress.
	api.busy=true
	app.relay_session._transfer_busy=true
	hub.room_open_requested.emit({"api_version":2,"room_id":ROOM,"status":"completed"})
	_check(not is_instance_valid(app.room_hub_screen) and app.mode in ["shared_replays","shared_memories"],"A finished room's card opens its Together page at once while a replay save is out")
	api.busy=false
	app.relay_session._transfer_busy=false
	app._show_home()
	app.mode="rooms"
	await _hub(app)
	hub=app.room_hub_screen
	api.busy=true
	hub.room_open_requested.emit({"api_version":2,"room_id":ROOM,"status":"your_turn"})
	await _frames(3)
	_check(is_instance_valid(hub) and hub==app.room_hub_screen and hub._message==Copy.HUB_OPENING_ROOM,"Open during the hub's own request waits on the hub, saying it is opening the room")
	api.busy=false
	for _frame in range(40):
		await process_frame
		if is_instance_valid(app.relay_child): break
	_check(is_instance_valid(app.relay_child) and app.mode=="relay_online","The waiting Open goes on to the room once the request lands")
	if is_instance_valid(app.relay_child): await _ready_card_poll(app)
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	await _frames(4)

## The ready card keeps Begin live during its room poll: a tap then is kept,
## shown as "Checking room…", and runs once the poll lands on the same turn.
func _ready_card_poll(app: Node) -> void:
	var preview: Node = app.relay_child
	preview.set_process(false)
	preview.set_physics_process(false)
	await _frames(2)
	_check(preview.mode=="ready" and preview.journey.my_turn(),"The host's room opens on its ready card")
	var record: Button = null
	for button: Button in preview._ready_turn_buttons:
		if is_instance_valid(button) and button.get_meta("turn_tap","")=="record": record=button
	_check(record!=null,"The ready card has Begin")
	if record==null: return
	var label := record.text
	app.relay_session._busy=true
	preview._process(1.0/30.0)
	_check(not record.disabled,"Begin stays enabled while a room poll is out")
	record.pressed.emit()
	_check(preview.mode=="ready" and not preview.running and record.text==Copy.ROOM_CHECKING,"A Begin tap during the poll is kept and the button says the room is being checked")
	preview._process(1.0/30.0)
	_check(preview.mode=="ready" and not preview.running,"The kept tap waits while the poll is out")
	app.relay_session._busy=false
	preview._process(1.0/30.0)
	_check(preview.mode=="play" and preview.running,"The kept Begin runs once the poll lands and it is still this player's turn")
	preview._pause()
	preview._show_ready()
	await _frames(1)
	for button: Button in preview._ready_turn_buttons:
		if is_instance_valid(button) and button.get_meta("turn_tap","")=="record": record=button
	_check(record.text==label,"A fresh ready card shows Begin as usual")
	# A request that never lands: the kept tap is dropped and the card comes back.
	app.relay_session._busy=true
	record.pressed.emit()
	preview._queued_turn_at-=preview.QUEUED_TURN_TAP_MS+1000
	preview._process(1.0/30.0)
	app.relay_session._busy=false
	for button: Button in preview._ready_turn_buttons:
		if is_instance_valid(button) and button.get_meta("turn_tap","")=="record": record=button
	_check(preview.mode=="ready" and not preview.running and record.text==label and preview._queued_turn_tap.is_empty(),"A tap kept past the bound is dropped and Begin reads as usual again")

func _join_notices(app: Node, api: FakeApi) -> void:
	if app.mode!="rooms": app.mode="rooms"
	await _hub(app)
	var hub: Node=app.room_hub_screen
	await app._join_from_room_hub("friend-"+"a".repeat(22))
	_check(is_instance_valid(hub) and hub._message==Copy.SHARE_CODE_FRIEND_NOT_ROOM,"A friend code typed into Join shows its error on the hub")
	api.busy=true
	app._join_from_room_hub("room-"+"a1".repeat(10))
	await _frames(3)
	_check(is_instance_valid(hub) and hub._message==Copy.HUB_JOINING and app.mode=="rooms","Join during a request waits on the hub, saying it is joining")
	api.busy=false
	await _frames(1)

func _frames(count: int) -> void:
	for _frame in range(count): await process_frame
