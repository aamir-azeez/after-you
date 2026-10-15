extends "res://tests/test_relay_online.gd"
## Every way out of the room hub lands on a screen the player can use, even
## while earlier online work is still running: Friends, Open and Join wait in
## the busy-tap gate with the hub up and the tapped control saying so, say why
## on the hub when they cannot go on, and Android Back always has somewhere to go.

const Copy = preload("res://presentation/player_copy.gd")
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")

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
	# The gate's limit, shortened for the test.
	app._hub_gate = BusyTapGate.new(app.room_hub_screen)
	app._hub_gate.wait_ms = 400

func _friends(app: Node, api: FakeApi) -> void:
	await _hub(app)
	var hub: Node = app.room_hub_screen
	var tab: Button = hub._tab_buttons["Friends"]
	var tab_text := tab.text
	# A saved legacy turn refuses Friends: the hub stays with the reason on it.
	app.saves.data["pending_turn"]={"idempotency_key":"held"}
	tab.pressed.emit()
	await _frames(3)
	_check(is_instance_valid(hub) and hub==app.room_hub_screen and app.mode=="rooms" and not is_instance_valid(app.friends_screen),"A refused Friends open keeps the hub instead of a blank screen")
	_check(is_instance_valid(hub) and hub._message==Copy.MAIN_8184DEB41266,"The refusal's reason shows on the hub")
	_check(tab.text==tab_text,"The tapped control reads as usual again once its flow ends")
	var state: Dictionary = hub.client.view()
	var list_state: String = ("Displaying saved rooms when offline" if not state.get("rooms",[]).is_empty() else str(state.get("error",""))) if state.get("stale",true) else ""
	_check(hub._notice.text == "
".join([Copy.MAIN_8184DEB41266, list_state].filter(func(line: String) -> bool: return not line.is_empty())),"The reason sits above the hub's own list line, never in place of it: '%s'" % hub._notice.text)
	app.saves.data.erase("pending_turn")
	# A room refresh still running: Friends waits with the hub up and says so on its control.
	app.foreground_refresh_running=true
	tab.pressed.emit()
	await _frames(3)
	_check(is_instance_valid(hub) and app.mode=="rooms" and not is_instance_valid(app.friends_screen),"Friends waits with the hub up while the refresh runs")
	_check(tab.text==Copy.HUB_OPENING,"The tapped control says it is opening")
	_check(hub._message.is_empty(),"A new tap clears the last tap's reason")
	app.foreground_refresh_running=false
	await _frames(4)
	_check(is_instance_valid(app.friends_screen) and app.mode=="friends" and not is_instance_valid(app.room_hub_screen),"Friends opens once the refresh ends, and only then releases the hub")
	if is_instance_valid(app.friends_screen): app.friends_screen.closed.emit()
	await _frames(3)
	# A replay save between retries holds the room session only: Friends never waits for it.
	await _hub(app)
	app.relay_session._transfer_busy=true
	app.room_hub_screen._tab_buttons["Friends"].pressed.emit()
	await _frames(2)
	_check(is_instance_valid(app.friends_screen) and app.mode=="friends","Friends opens at once while only a replay save holds the room session")
	app.relay_session._transfer_busy=false
	if is_instance_valid(app.friends_screen): app.friends_screen.closed.emit()
	await _frames(3)
	# Work that never ends: the wait ends on the hub with a reason, and the control reads as usual.
	await _hub(app)
	hub=app.room_hub_screen
	tab=hub._tab_buttons["Friends"]
	tab_text=tab.text
	app.foreground_refresh_running=true
	tab.pressed.emit()
	await create_timer(0.8).timeout
	_check(is_instance_valid(hub) and app.mode=="rooms" and not is_instance_valid(app.friends_screen) and hub._message==Copy.HUB_FRIENDS_WAIT_EXPIRED,"A wait that runs out keeps the hub and says to tap Friends again")
	_check(tab.text==tab_text,"The control gets its own text back")
	app.foreground_refresh_running=false
	# Only the latest tap waits: an earlier one gives its control back and never runs.
	var first := Button.new()
	first.text="First"
	hub.add_child(first)
	var second := Button.new()
	second.text="Second"
	hub.add_child(second)
	var ran: Array = []
	app.foreground_refresh_running=true
	app._hub_tap(first,Copy.HUB_OPENING_ROOM,app._online_flow_idle,"",func() -> void: ran.append("first"))
	app._hub_tap(second,Copy.HUB_OPENING_ROOM,app._online_flow_idle,"",func() -> void: ran.append("second"))
	await _frames(2)
	_check(first.text=="First" and second.text==Copy.HUB_OPENING_ROOM,"A later tap takes the label and the earlier control reads as usual")
	app.foreground_refresh_running=false
	await _frames(3)
	_check(ran==["second"],"Only the latest tap runs: %s" % [ran])
	first.queue_free()
	second.queue_free()

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
	app.foreground_refresh_running=true
	app.relay_session._transfer_busy=true
	hub.room_open_requested.emit({"api_version":2,"room_id":ROOM,"status":"completed"},null)
	_check(not is_instance_valid(app.room_hub_screen) and app.mode in ["shared_replays","shared_memories"],"A finished room's card opens its Together page at once while a replay save is out")
	app.foreground_refresh_running=false
	app.relay_session._transfer_busy=false
	app._show_home()
	app.mode="rooms"
	await _hub(app)
	hub=app.room_hub_screen
	var open := Button.new()
	open.text="Continue"
	hub.add_child(open)
	app.relay_session._busy=true
	hub.room_open_requested.emit({"api_version":2,"room_id":ROOM,"status":"your_turn"},open)
	await _frames(3)
	_check(is_instance_valid(hub) and hub==app.room_hub_screen and open.text==Copy.HUB_OPENING_ROOM,"Open while the room session is busy waits on the hub, its control saying it is opening the room")
	# A refresh that rebuilds the room cards meanwhile: the new card's button carries the label.
	var rebuilt := Button.new()
	rebuilt.text="Continue"
	hub.add_child(rebuilt)
	hub._room_actions[ROOM]=rebuilt
	hub.cards_redrawn.emit()
	_check(rebuilt.text==Copy.HUB_OPENING_ROOM,"A rebuilt room card's button keeps the waiting tap's label")
	app.relay_session._busy=false
	for _frame in range(40):
		await process_frame
		if is_instance_valid(app.relay_child): break
	_check(is_instance_valid(app.relay_child) and app.mode=="relay_online","The waiting Open goes on to the room once the session is free")
	if is_instance_valid(app.relay_child): await _ready_card_poll(app)
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	await _frames(4)

## The ready card keeps Begin live during its room poll: a tap then waits in
## the busy-tap gate, shown as "Checking room…", and runs once the poll lands
## on the same turn.
func _ready_card_poll(app: Node) -> void:
	var preview: Node = app.relay_child
	preview.set_process(false)
	preview.set_physics_process(false)
	await _frames(2)
	_check(preview.mode=="ready" and preview.journey.my_turn(),"The host's room opens on its ready card")
	var record: Button = preview._ready_turn_buttons.get("record")
	_check(record!=null,"The ready card has Begin")
	if record==null: return
	var label := record.text
	app.relay_session._busy=true
	_check(not record.disabled,"Begin stays enabled while a room poll is out")
	record.pressed.emit()
	_check(preview.mode=="ready" and not preview.running and record.text==Copy.ROOM_CHECKING,"A Begin tap during the poll waits and the button says the room is being checked")
	await _frames(3)
	_check(preview.mode=="ready" and not preview.running,"The tap waits while the poll is out")
	# A redraw meanwhile keeps the label on the new Begin.
	preview._show_ready()
	await _frames(1)
	record=preview._ready_turn_buttons.get("record")
	_check(record!=null and record.text==Copy.ROOM_CHECKING,"A redrawn card keeps the waiting tap's label on its Begin")
	app.relay_session._busy=false
	await _frames(3)
	_check(preview.mode=="play" and preview.running,"The waiting Begin runs once the poll lands and it is still this player's turn")
	preview._pause()
	preview._show_ready()
	await _frames(1)
	record=preview._ready_turn_buttons.get("record")
	_check(record.text==label,"A fresh ready card shows Begin as usual")
	# A request that never lands: the tap is dropped and the card comes back.
	preview._turn_gate.wait_ms=300
	app.relay_session._busy=true
	record.pressed.emit()
	await create_timer(0.6).timeout
	app.relay_session._busy=false
	await _frames(2)
	record=preview._ready_turn_buttons.get("record")
	_check(preview.mode=="ready" and not preview.running and record.text==label and not preview._turn_gate.waiting(),"A tap kept past the limit is dropped and Begin reads as usual again")

func _join_notices(app: Node, api: FakeApi) -> void:
	if app.mode!="rooms": app.mode="rooms"
	await _hub(app)
	var hub: Node=app.room_hub_screen
	await app._join_from_room_hub("friend-"+"a".repeat(22))
	_check(is_instance_valid(hub) and hub._message==Copy.SHARE_CODE_FRIEND_NOT_ROOM,"A friend code typed into Join shows its error on the hub")
	app.relay_session._busy=true
	hub._join_code.text="room-"+"a1".repeat(10)
	hub._join.pressed.emit()
	await _frames(3)
	_check(is_instance_valid(hub) and hub._join.text==Copy.HUB_JOINING and app.mode=="rooms","Join while the room session is busy waits on the hub, its button saying it is joining")
	await create_timer(0.8).timeout
	_check(is_instance_valid(hub) and hub._message==Copy.HUB_JOIN_WAIT_EXPIRED and hub._join.text=="Join","A Join wait that runs out says to tap Join again")
	app.relay_session._busy=false
	await _frames(1)

func _frames(count: int) -> void:
	for _frame in range(count): await process_frame
