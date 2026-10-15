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
	app.hub_tap_wait_ms=400
	await _friends(app,api)
	await _back_without_hub(app)
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

func _frames(count: int) -> void:
	for _frame in range(count): await process_frame
