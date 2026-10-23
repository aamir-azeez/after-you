extends "res://tests/test_relay_online.gd"
## A phone that kept files from the withdrawn Story feature still plays every
## room, practice and the chapter picker. Those files are never read, rewritten
## or sent anywhere; only deleting the identity removes them
## (test_campaign_store covers that removal).

const ANCHOR := "AAAAAAAAAAAAAAAAAAAAAA"
const LEGACY := "LLLLLLLLLLLLLLLLLLLLLL"

func _run() -> void:
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name]=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.handle_input_locally=true
	root.add_child(viewport)
	var path := "user://old-story-saves-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
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
	api.player_id=GUEST
	api.exists=true
	api.joined=true
	app.identity_read_state=Main.IdentityReadState.LOADED
	app.identity_data={"player_id":GUEST,"device_token":"synthetic-device-token"}
	var store := MemoryStore.new()
	# Story files as an older build left them: a lobby, a story journal, its
	# redo journal and both terminal records, one of them damaged.
	store.values["relay-campaign-lobby-v1:"+GUEST]={"schema_version":2,"owner_player_id":GUEST,"campaigns":[{"campaign_room_id":ANCHOR}],"bound_campaign":{"campaign_room_id":ANCHOR},"pending":{}}
	store.values["relay-campaign-v1:"+GUEST+":"+ANCHOR]={"schema_version":1,"selected_room":ANCHOR,"pending":{"operation":"continue"},"seen":{"0":["arrival"]}}
	store.values["relay-campaign-redo-v1:"+GUEST+":"+ANCHOR]={"schema_version":1,"pending":{}}
	store.values["relay-campaign-terminal-v1:"+GUEST]={"retained_unfamiliar_story":true}
	store.values["relay-campaign-admission-terminal-v1:"+GUEST]={"schema_version":1,"receipts":[]}
	var story_files: Dictionary=store.values.duplicate(true)
	app.relay_session=Session.new(api,app._relay_identity,store)
	app.journey_flow.show_journey()
	_check(_button_named(app,"Story")==null,"The chapter picker has no Story entry")
	# Its own server address keeps this run's saved hub list apart from other runs.
	api.base_url="https://old-story-saves-"+path.get_file().get_basename()+".invalid"
	app._return_to_room_hub()
	for _frame in range(4): await process_frame
	var hub: Node=app.room_hub_flow.screen
	_check(is_instance_valid(hub) and hub.room_action(ROOM)!=null and hub.room_action(LEGACY)!=null,"Play with a friend lists the joined chapter and earlier islands beside the old files")
	if is_instance_valid(hub) and hub.room_action(ROOM)!=null:
		hub.room_action(ROOM).pressed.emit()
		for _frame in range(4): await process_frame
	_check(is_instance_valid(app.relay_child) and app.relay_child.chapter_key=="relay-isles@2","The joined chapter opens")
	if is_instance_valid(app.relay_child): app.relay_child._leave()
	await process_frame
	await app._start_practice(0)
	_check(app.mode=="ready" and not app.room_play,"Solo practice opens")
	app._show_home()
	await process_frame
	_check(app.mode=="home","Home opens")
	for scope: String in story_files:
		_check(Canonical.same(store.values.get(scope),story_files[scope]),"The old file is left exactly as it was: "+scope)
	_check(api.calls.filter(func(call: Dictionary) -> bool: return str(call.path).begins_with("/v2/campaigns")).is_empty(),"Nothing asks the server about a Story")
	viewport.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("OLD STORY SAVES: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _inbox_room(room_id: String, family: String, chapter: Dictionary) -> Dictionary:
	return {"room_id":room_id,"family":family,"api_version":1 if family=="legacy" else 2,"chapter":chapter,"membership":{"host_id":HOST,"guest_id":GUEST,"you_are_host":false},"status":"waiting_for_their_turn","revision":1,"remote_activity_sequence":1,"activity_at":"2026-10-09T13:00:00.000Z"}

func _server(request: Dictionary, api: FakeApi) -> Dictionary:
	if request.path=="/v1/room-inbox":
		return _ok({"schema_version":1,"rooms":[_inbox_room(ROOM,"relay",{"id":"relay-isles","version":2}),_inbox_room(LEGACY,"legacy",{"id":"first-light","version":1})]})
	return super._server(request,api)
