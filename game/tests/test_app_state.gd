extends SceneTree

const Storage = preload("res://services/local_save.gd")
const State = preload("res://services/turn_state.gd")
const Purchases = preload("res://services/purchases.gd")
const Levels = preload("res://core/levels.gd")
const Main = preload("res://main.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const TEST_SAVED_PLAYER := "SSSSSSSSSSSSSSSSSSSSSS"
const TEST_RECOVERY_PLAYER := "RRRRRRRRRRRRRRRRRRRRRR"
const TEST_DEVICE_TOKEN := "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"
const TEST_RECOVERY_CODE := "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"

class TestSecrets:
	extends Node
	signal completed(id: String, operation: String, payload: Dictionary)
	signal failed(id: String, operation: String, code: String)
	var read_response: Dictionary={"ok":false}
	var pending_read_response: Dictionary={"ok":true,"payload":{"found":false,"value":null}}
	var calls: Array=[]
	var writes: Array=[]
	var values: Dictionary={}
	var fail_write_names: Array=[]
	var fail_remove := false
	func is_available() -> bool:
		return true
	func get_secret(name: String) -> String:
		var id := "read-"+str(calls.size())
		calls.append({"operation":"get","name":name})
		_finish_read.call_deferred(id,(pending_read_response if name=="recovery_pending" else read_response).duplicate(true))
		return id
	func _finish_read(id: String, response: Dictionary) -> void:
		if response.get("ok",false):
			completed.emit(id,"get",response.payload)
		else:
			failed.emit(id,"get","secure_storage_unavailable")
	func put_secret(name: String, value: String) -> String:
		var id := "write-"+str(calls.size())
		calls.append({"operation":"put","name":name})
		if name in fail_write_names:
			_finish_error.call_deferred(id,"put")
			return id
		writes.append({"name":name,"value":value})
		values[name]=value
		_finish_write.call_deferred(id)
		return id
	func _finish_write(id: String) -> void:
		completed.emit(id,"put",{"stored":true})
	func remove_secret(name: String) -> String:
		var id := "remove-"+str(calls.size())
		calls.append({"operation":"remove","name":name})
		if fail_remove:
			_finish_error.call_deferred(id,"remove")
		else:
			values.erase(name)
			_finish_remove.call_deferred(id)
		return id
	func _finish_remove(id: String) -> void:
		completed.emit(id,"remove",{"removed":true})
	func _finish_error(id: String, operation: String) -> void:
		failed.emit(id,operation,"secure_storage_unavailable")

class DelayedHostingApi:
	extends Node
	var player_id := "hosting-player"
	var device_token := "synthetic-hosting-token"
	var busy := false
	var during_request: Callable
	func configured() -> bool:
		return true
	func request_json(_method: int, _path: String, _body: Dictionary={}) -> Dictionary:
		busy=true
		if during_request.is_valid():
			during_request.call()
		await get_tree().process_frame
		busy=false
		return {"ok":true,"data":{"status":"verified","full_journey":true}}

var checks := 0
var failures := 0
var paths: Array[String] = []
var first: Dictionary
var second: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	first=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json"))
	second=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-b.json"))
	_test_save_generations()
	_test_receipts_and_roles()
	_test_store_offers()
	await _test_main_lifecycle()
	await _test_identity_and_entitlement()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path+suffix):
				DirAccess.remove_absolute(path+suffix)
	await create_timer(0.15).timeout
	print("AFTER YOU APP STATE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _temporary_path() -> String:
	var path := "user://state-test-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	paths.append(path)
	return path

func _write(path: String, data: Variant) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(data if data is String else JSON.stringify(data))
	file.close()

func _test_save_generations() -> void:
	var path := _temporary_path()
	var store := Storage.new(path)
	store.load_data()
	_check(store.data.settings.assistance and not store.read_only,"Missing save starts with complete defaults")
	_check(store.save_attempt("first-light",{"a":first,"b":second,"draft":{}},true),"Completed attempt persisted")
	var saved := store.attempt("first-light")
	saved.a.actions[0].x=999
	_check(store.attempt("first-light").a.actions[0].x!=999,"Read copies cannot mutate committed recordings")
	_check(store.save_attempt("first-light",{"a":{},"b":{},"draft":{}}),"New rehearsal persisted")
	_check(not store.data.replays["first-light"].b.is_empty(),"Completed replay survives a restarted attempt")
	var restored := Storage.new(path)
	restored.load_data()
	_check(restored.data.completed["first-light"] and restored.data.generation==2,"Current save reloads marks and generation")
	_write(path,"{ interrupted")
	restored.load_data()
	_check(restored.loaded_from==path+".backup" and not restored.attempt("first-light").b.is_empty(),"Corrupted primary recovers valid previous generation")
	_check(restored.flush(),"Recovered backup can become a new valid primary")
	var next := restored.data.duplicate(true)
	next.generation+=1
	next["pending_turn"]={"idempotency_key":"kept-after-crash"}
	_write(path+".tmp",next)
	restored.load_data()
	_check(restored.loaded_from==path+".tmp" and restored.data.pending_turn.idempotency_key=="kept-after-crash","Fully written interrupted replacement preserves newest pending submission")
	var future := {"version":99,"private_future_data":"do-not-overwrite"}
	_write(path,future)
	restored.load_data()
	_check(restored.read_only and not restored.flush(),"Future save version cannot be downgraded")
	_check(FileAccess.get_file_as_string(path)==JSON.stringify(future),"Future save bytes remain intact")
	var old_path := _temporary_path()
	_write(old_path,{"version":1,"settings":{"sound":false},"attempts":{},"completed":{},"room":{}})
	var old := Storage.new(old_path)
	old.load_data()
	_check(not old.data.settings.sound and old.data.settings.assistance,"Older partial settings gain defaults without losing preferences")
	var unavailable := Storage.new("user://missing-test-parent-"+Crypto.new().generate_random_bytes(8).hex_encode()+"/journey.json")
	_check(not unavailable.save_attempt("first-light",{"a":first},true),"Unwritable save reports failure")
	_check(unavailable.data.attempts.is_empty() and unavailable.data.completed.is_empty(),"Failed transaction rolls back in-memory commitment")
	var normalized := Storage.normalize_attempt({"a":null,"b":second,"draft":null})
	_check(normalized.a.is_empty() and normalized.draft.is_empty() and not normalized.b.is_empty(),"Nullable network recordings normalize safely")

func _room() -> Dictionary:
	return {"room_id":"room-test","revision":4,"level_id":"first-light","level_index":0,"first_player_id":"host","host_id":"host","guest_id":null,"active_role":"a","recordings":{"a":null,"b":null}}

func _test_receipts_and_roles() -> void:
	var room := _room()
	var pending := {"room_id":room.room_id,"base_revision":room.revision,"recording":first,"idempotency_key":"same-exact-key"}
	_check(State.pending_status(pending,room)=="retry","Unchanged room allows original request retry")
	room.revision+=1
	_check(State.pending_status(pending,room)=="stale","Changed revision cannot be treated as a receipt")
	room.recordings.a=first.duplicate(true)
	_check(State.pending_status(pending,room)=="accepted","Actual saved recording confirms uncertain submission")
	var fresh: Dictionary=State._normalized_value(first)
	_check(State.same_recording(fresh,first),"Native integer recording matches JSON parsed numeric receipt")
	room.recordings.a.actions[0].x+=1
	_check(State.pending_status(pending,room)=="stale","Matching final hash alone is not enough to confirm a turn")
	room.room_id="another-room"
	_check(State.pending_status(pending,room)=="other_room","An unrelated room cannot resolve a queued request")
	room=_room()
	_check(State.my_turn(room,"host") and not State.my_turn(room,"outsider"),"Only room members can start their turn")
	room.active_role="b"
	_check(not State.my_turn(room,"host") and not State.my_turn(room,""),"Missing guest never grants host the second turn")
	room.guest_id="guest"
	_check(State.my_turn(room,"guest"),"Joined guest receives second role")
	room.first_player_id="guest"
	room.active_role="a"
	_check(State.my_turn(room,"guest") and not State.my_turn(room,"host"),"First-player assignment alternates independently of host")
	var check: Dictionary=State.review(Levels.get_level(0),second,{"a":first})
	_check(check.valid and check.can_commit,"Review validates the actual completed recording")
	var altered := second.duplicate(true)
	altered.checkpoints[0].state_hash="0".repeat(64)
	_check(not State.review(Levels.get_level(0),altered,{"a":first}).valid,"Review rejects altered recording despite completion flag")

func _test_store_offers() -> void:
	var offer := {"current_id":"journey","offerings":[{"id":"journey","packages":[{"id":"monthly","type":"MONTHLY","price":"$1.99"},{"id":"lifetime","type":"LIFETIME","price":"AED 18.99"}]}]}
	var chosen: Dictionary=Purchases.select_lifetime_offer(offer)
	_check(chosen.id=="lifetime" and chosen.price=="AED 18.99" and chosen.offering_id=="journey","Native offer shape preserves lifetime ID and exact store-formatted price")
	offer.offerings[0].packages.remove_at(1)
	_check(Purchases.select_lifetime_offer(offer).is_empty(),"Subscription is never presented as a one-time purchase")
	offer.current_id="missing"
	_check(Purchases.select_lifetime_offer(offer).is_empty(),"Noncurrent offering is not selected silently")

func _test_main_lifecycle() -> void:
	var app := Main.new()
	app.saves=Storage.new(_temporary_path())
	root.add_child(app)
	await process_frame
	app.current_level=Levels.get_level(0)
	app.level_index=0
	app.attempt={"a":first.duplicate(true),"b":second.duplicate(true),"draft":{}}
	app._preview(second,true)
	app._physics_process(1.0/30.0)
	var paused_tick: int=app.sim.tick
	app._pause()
	app._physics_process(1.0/30.0)
	_check(app.mode=="paused" and app.sim.tick==paused_tick,"Preview pause freezes simulation")
	var continue_button := _find_button(app.overlay,"Continue")
	continue_button.pressed.emit()
	_check(app.mode=="preview" and app.running,"Continue restores preview mode rather than starting a live turn")
	for _i: int in range(601):
		app._physics_process(1.0/30.0)
	app._advance_completion_moment(2.0)
	_check(app.mode=="collection" and app.collection_preview,"Completed collection preview retains read-only origin")
	_check(_find_button(app.overlay,"Keep this island")==null,"Collection preview does not offer a second commitment")
	var generation: int=app.saves.data.generation
	app._commit_turn()
	_check(app.saves.data.generation==generation,"Direct duplicate collection commitment does not write a save")
	app._preview(second,true)
	for _i: int in range(601):
		app._physics_process(1.0/30.0)
	app._advance_completion_moment(2.0)
	_check(app.mode=="collection","Repeated previews remain read-only")
	app.attempt={"a":{},"b":{},"draft":{}}
	app.role="a"
	app._prepare_turn()
	var invalid := first.duplicate(true)
	invalid.final_state_hash="0".repeat(64)
	app._resume_draft(invalid)
	_check(app.mode=="ready" and not app.running and app.sim.tick==0,"Invalid draft cannot silently start playback or live input")
	app._resume_draft(first)
	_check(app.mode=="review" and not app.running,"Finished rehearsal resumes into review rather than a frozen live turn")
	app.role="b"
	app.attempt={"a":invalid,"b":{},"draft":{}}
	app._prepare_turn()
	_check(app.mode=="journey" and not app.running,"Invalid earlier source fails setup without continuing the old simulation")
	await _test_main_pending(app)
	app.queue_free()
	await process_frame

func _test_main_pending(app: Node) -> void:
	var fake := FakeApi.new()
	app.add_child(fake)
	app.api=fake
	app.identity_loading=false
	app.active_room=_room()
	app.room_play=true
	app.role="a"
	app.current_level=Levels.get_level(0)
	app.attempt={"a":{},"b":{},"draft":{}}
	app.review_recording=first.duplicate(true)
	app.collection_preview=false
	app.mode="review"
	await app._commit_online()
	var pending: Dictionary=app.saves.data.pending_turn.duplicate(true)
	_check(fake.calls.size()==1 and not pending.is_empty(),"Interrupted POST retains durable original request")
	var accepted := _room()
	accepted.recordings.a=first.duplicate(true)
	accepted.active_role="b"
	accepted.revision=5
	fake.responses=[{"ok":true,"status":200,"data":_room()},{"ok":true,"status":200,"data":accepted}]
	await app._reconcile_pending()
	_check(fake.calls.size()==3 and fake.calls[1].method==HTTPClient.METHOD_GET,"Uncertain submission is checked before retry")
	_check(fake.calls[0].body==fake.calls[2].body,"Retry preserves exact request body and idempotency key")
	_check(not app.saves.data.has("pending_turn") and app.active_room.active_role=="b","Successful receipt clears uncertainty and advances room")
	app.saves.update_values({"pending_turn":pending})
	fake.responses=[{"ok":true,"status":200,"data":accepted}]
	var before_calls: int=fake.calls.size()
	await app._reconcile_pending()
	_check(fake.calls.size()==before_calls+1 and not app.saves.data.has("pending_turn"),"Matching saved recording resolves uncertainty without another POST")
	app.saves=Storage.new("user://absent-parent-"+Crypto.new().generate_random_bytes(8).hex_encode()+"/journey.json")
	app.active_room=_room()
	app.review_recording=first.duplicate(true)
	before_calls=fake.calls.size()
	await app._commit_online()
	_check(fake.calls.size()==before_calls and not app.saves.data.has("pending_turn"),"Failed durable pending write prevents network submission")

func _test_identity_and_entitlement() -> void:
	var app := Main.new()
	app.saves=Storage.new(_temporary_path())
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.config["revenuecat_public_key"]=""
	var fake := FakeApi.new()
	app.add_child(fake)
	app.api=fake
	fake.player_id=""
	fake.device_token=""
	var storage := TestSecrets.new()
	app.add_child(storage)
	app.secrets=storage
	storage.completed.connect(app._secret_completed)
	storage.failed.connect(app._secret_failed)
	await process_frame
	await _test_identity_reads(app,fake,storage)
	await _test_live_entitlement(app)
	await _test_hosting_access(app,fake)
	await _test_recovery_interruptions(app,fake,storage)
	app.queue_free()
	await process_frame

func _test_identity_reads(app: Node, api: Node, storage: TestSecrets) -> void:
	_check(not await app._ensure_identity() and api.calls.is_empty(),"An unchecked identity never permits automatic replacement")
	var invalid_responses := [
		{"ok":false},
		{"ok":true,"payload":{"found":true,"value":"{ interrupted"}},
		{"ok":true,"payload":{"found":true,"value":JSON.stringify({"player_id":"existing","device_token":123})}},
		{"ok":true,"payload":{"found":false,"value":"unexpected saved value"}},
		{"ok":true,"payload":{"value":null}},
	]
	for index: int in range(invalid_responses.size()):
		storage.read_response=invalid_responses[index]
		app._load_saved_identity()
		await process_frame
		_check(not app.identity_loading and app.identity_read_state==Main.IdentityReadState.FAILED,"Failed or malformed secure read %d remains distinct from missing" % index)
		_check(not await app._ensure_identity() and api.calls.is_empty() and storage.writes.is_empty(),"Secure read failure %d sends no identity creation and overwrites nothing" % index)
	app._show_account()
	_check(_find_button(app.overlay,"Create anonymous identity")==null and _find_button(app.overlay,"Check saved identity")!=null and _find_button(app.overlay,"Recover a previous identity")!=null,"Failed identity read exposes retry/recovery instead of replacement")
	var identity := {"player_id":TEST_SAVED_PLAYER,"device_token":TEST_DEVICE_TOKEN,"recovery_code":TEST_RECOVERY_CODE}
	storage.read_response={"ok":true,"payload":{"found":true,"value":JSON.stringify(identity)}}
	await app._retry_saved_identity()
	_check(app.identity_read_state==Main.IdentityReadState.LOADED and app.api.player_id==TEST_SAVED_PLAYER,"Retry restores the existing stored identity")
	_check(await app._ensure_identity() and api.calls.is_empty() and storage.writes.is_empty(),"Restored identity is reused without account creation or storage writes")
	api.player_id=""
	api.device_token=""
	app.identity_data={}
	storage.read_response={"ok":true,"payload":{"found":false,"value":null}}
	app._load_saved_identity()
	await process_frame
	_check(app.identity_read_state==Main.IdentityReadState.MISSING,"Explicit missing storage is recognized as a fresh installation")
	api.responses=[{"ok":true,"data":identity}]
	_check(await app._ensure_identity() and api.calls.size()==1 and api.calls[0].path=="/v1/identity" and storage.writes.size()==1,"Confirmed absence permits exactly one persisted new identity")
	_check(app.identity_read_state==Main.IdentityReadState.LOADED,"Persisted creation transitions to loaded state")
	api.player_id=""
	api.device_token=""
	app.identity_read_state=Main.IdentityReadState.FAILED
	api.calls.clear()
	storage.writes.clear()
	api.responses=[{"ok":true,"data":{"player_id":TEST_SAVED_PLAYER,"recovered":true}}]
	await app._recover_identity(TEST_SAVED_PLAYER,TEST_RECOVERY_CODE)
	_check(api.calls.size()==1 and api.calls[0].path=="/v1/identity/recover" and storage.writes.size()==2,"Explicit recovery secures its proposal and resulting identity after a failed secure read")
	_check(app.identity_restart_required and app.identity_read_state==Main.IdentityReadState.LOADED,"Recovered identity is secured and requires restart before reuse")

func _test_live_entitlement(app: Node) -> void:
	app.purchases.customer_info={}
	app._show_earlier_islands()
	var locked_label: String="04  "+str(Levels.get_level(3).title)+"  ·  Full Journey"
	var unlocked_label: String="04  "+str(Levels.get_level(3).title)
	var button := _find_button(app.overlay,locked_label)
	app.purchases.customer_info={"entitlements":{"full_journey":{"active":true}}}
	button.pressed.emit()
	_check(app.mode=="ready" and app.level_index==3,"Existing journey button checks current entitlement instead of captured lock")
	app.purchases.customer_info={}
	app._show_earlier_islands()
	app.purchases._on_customer_info(JSON.stringify({"schema_version":1,"entitlements":{"full_journey":{"active":true}}}))
	await process_frame
	_check(app.mode=="earlier_islands" and _find_button(app.overlay,unlocked_label)!=null and _find_button(app.overlay,locked_label)==null,"Asynchronous customer info refreshes visible earlier-island lock labels without leaving that panel")
	button=_find_button(app.overlay,unlocked_label)
	app.purchases.customer_info={}
	button.pressed.emit()
	_check(app.mode=="paywall","Existing unlocked button also checks entitlement loss before opening premium island")
	app._start_practice(0)
	app._begin_turn()
	app._physics_process(1.0/30.0)
	var tick: int=app.sim.tick
	app.purchases._on_customer_info(JSON.stringify({"schema_version":1,"entitlements":{"full_journey":{"active":true}}}))
	_check(app.mode=="play" and app.running and app.sim.tick==tick,"Entitlement update does not replace an active rehearsal")

func _test_hosting_access(app: Node, api: Node) -> void:
	app.identity_restart_required=false
	api.player_id="hosting-player"
	api.device_token="synthetic-hosting-token"
	api.calls.clear()
	app.purchases.customer_info={"entitlements":{"full_journey":{"active":true}}}
	var original_entitlement: Dictionary=app.purchases.customer_info.duplicate(true)
	app._show_account()
	_check(_find_button(app.overlay,"Check hosting access")!=null,"Authenticated account exposes a hosting verification action")
	var restore := _find_button(app.overlay,"Restore purchases")
	_check(restore!=null and restore.pressed.is_connected(app._restore_store),"Fully unlocked player can restore purchases from Account through the purchase controller")
	app.mode="paywall"
	app._purchase_completed("synthetic-offer","get_offerings",{"current_id":"journey","offerings":[{"id":"journey","packages":[{"id":"lifetime","type":"LIFETIME","price":"$4.99"}]}]})
	restore=_find_button(app.overlay,"Restore purchases")
	_check(restore!=null and restore.pressed.is_connected(app._restore_store),"Fetched offering retains a working restore action after replacing the loading card")
	for access: bool in [false,true]:
		api.responses=[{"ok":true,"data":{"status":"verified","full_journey":access,"environment":"test-store","checked_at":"2026-09-14T00:00:00Z"}}]
		await app._check_hosting_access()
		var expected := "Full Journey confirmed" if access else "Introductory hosting"
		_check(_find_label(app.overlay,expected)!=null,"Verified hosting %s shows the correct server result" % str(access))
		_check(api.calls[-1].method==HTTPClient.METHOD_GET and api.calls[-1].path=="/v1/entitlement" and api.calls[-1].body.is_empty(),"Hosting check uses the authenticated read endpoint without sending purchase claims")
	var unknown_responses := [
		{"ok":true,"data":{"status":"unconfigured","full_journey":false}},
		{"ok":true,"data":{"status":"unavailable","full_journey":false}},
		{"ok":false,"status":0},
		{"ok":false,"status":401},
		{"ok":true,"data":{"status":"verified","full_journey":"true"}},
		{"ok":true,"data":{"status":"unexpected","full_journey":true}},
		{"ok":false,"status":503,"data":{"status":"verified","full_journey":true}},
	]
	for index: int in range(unknown_responses.size()):
		api.responses=[unknown_responses[index]]
		await app._check_hosting_access()
		_check(_find_label(app.overlay,"Hosting access not checked")!=null and _find_label(app.overlay,"Introductory hosting")==null,"Unavailable or malformed hosting result %d remains unknown, not a purchase denial" % index)
	_check(app.purchases.customer_info==original_entitlement,"Server verification never erases or modifies the SDK purchase entitlement")
	var before: int=api.calls.size()
	api.player_id=""
	api.device_token=""
	app.identity_read_state=Main.IdentityReadState.MISSING
	await app._check_hosting_access()
	_check(api.calls.size()==before,"Hosting check without identity performs no request or anonymous account creation")
	api.player_id="hosting-player"
	await app._check_hosting_access()
	_check(api.calls.size()==before,"Hosting check without device credential is also held")
	api.device_token="synthetic-hosting-token"
	app.identity_loading=true
	await app._check_hosting_access()
	_check(api.calls.size()==before,"Hosting check waits for an active identity load")
	app.identity_loading=false
	app.identity_restart_required=true
	await app._check_hosting_access()
	_check(api.calls.size()==before,"Hosting check cannot use a previous identity after recovery")
	app.identity_restart_required=false
	var delayed := DelayedHostingApi.new()
	app.add_child(delayed)
	app.api=delayed
	delayed.during_request=func(): app._show_home()
	await app._check_hosting_access()
	_check(app.mode=="home" and _find_label(app.overlay,"Full Journey confirmed")==null,"Late hosting response does not replace a screen the player navigated to")
	app.api=api
	delayed.queue_free()

func _reset_recovery_case(app: Node, api: Node, storage: TestSecrets) -> void:
	app.pending_recovery={}
	app.recovery_replace_allowed=false
	app.identity_restart_required=false
	app.identity_busy=false
	app.identity_loading=false
	app.identity_read_state=Main.IdentityReadState.UNCHECKED
	app.identity_request=""
	app.recovery_read_request=""
	app.identity_data={}
	api.player_id=""
	api.device_token=""
	api.calls.clear()
	api.responses.clear()
	storage.calls.clear()
	storage.writes.clear()
	storage.values={"player_identity":JSON.stringify({"player_id":"old-player","device_token":"old-synthetic-device-token"})}
	storage.fail_write_names=[]
	storage.fail_remove=false
	storage.pending_read_response={"ok":true,"payload":{"found":false,"value":null}}
	storage.read_response={"ok":true,"payload":{"found":true,"value":storage.values.player_identity}}

func _restart_with_recovery(app: Node, api: Node, storage: TestSecrets) -> void:
	app.pending_recovery={}
	app.identity_restart_required=false
	app.identity_loading=false
	app.identity_data={}
	api.player_id=""
	api.device_token=""
	storage.calls.clear()
	storage.pending_read_response={"ok":true,"payload":{"found":true,"value":storage.values.recovery_pending}}
	app._load_saved_identity()
	await process_frame

func _test_recovery_interruptions(app: Node, api: Node, storage: TestSecrets) -> void:
	_reset_recovery_case(app,api,storage)
	for input: Array in [["short",TEST_RECOVERY_CODE],[TEST_RECOVERY_PLAYER,"mistyped"],[TEST_RECOVERY_PLAYER,"+".repeat(43)]]:
		await app._recover_identity(input[0],input[1])
		_check(api.calls.is_empty() and storage.writes.is_empty() and app.pending_recovery.is_empty() and not app.identity_restart_required,"Mistyped recovery input is rejected before creating, persisting or sending a proposal")
	await app._recover_identity(TEST_RECOVERY_PLAYER,TEST_RECOVERY_CODE)
	var original: Dictionary=api.calls[0].body.duplicate(true)
	var pending: Dictionary=JSON.parse_string(storage.values.recovery_pending)
	_check(pending.request==original and Main._valid_pending_recovery(pending),"Lost recovery response retains the exact secured rotation proposal")
	for field: String in ["player_id","recovery_code","idempotency_key"]:
		var invalid: Dictionary=pending.duplicate(true)
		invalid.request[field]="short"
		_check(not Main._valid_pending_recovery(invalid),"Stored recovery %s must match the backend's exact field format" % field)
	await app._recover_identity(TEST_RECOVERY_PLAYER,"B".repeat(43))
	_check(api.calls.size()==1 and app.pending_recovery.request==pending.request and app.pending_recovery.schema_version==pending.schema_version and JSON.parse_string(storage.values.recovery_pending)==pending,"Ambiguous recovery cannot be replaced by a different code or proposal")
	_check(original.next_device_token.length()==43 and Marshalls.base64_to_raw(original.next_device_token.replace("-","+").replace("_","/")+"=").size()==32 and original.next_device_token!=original.next_recovery_code,"Rotation generates separate 32-byte base64url credentials")
	_check(storage.calls[0].operation=="put" and storage.calls[0].name=="recovery_pending" and not storage.values.player_identity.contains(original.next_device_token),"Pending proposal is saved before posting and unacknowledged credentials never replace the identity")
	_check(not JSON.stringify(app.saves.data).contains(original.next_device_token) and not JSON.stringify(app.saves.data).contains(original.recovery_code),"Recovery secrets never enter the ordinary local save")
	await _restart_with_recovery(app,api,storage)
	_check(app.pending_recovery==pending and app.identity_read_state==Main.IdentityReadState.RECOVERY_PENDING and storage.calls.size()==1 and storage.calls[0].name=="recovery_pending","Restart gives pending recovery priority over possibly revoked stored identity")
	_check(not await app._ensure_identity() and api.calls.size()==1 and api.player_id.is_empty(),"Unfinished recovery blocks ordinary identity use and new account creation")
	api.responses=[{"ok":true,"data":{"player_id":TEST_RECOVERY_PLAYER,"recovered":true}}]
	await app._resume_pending_recovery()
	_check(api.calls.size()==2 and api.calls[1].body==original,"Retry after restart uses identical old code, idempotency key and proposed credentials")
	var stored: Dictionary=JSON.parse_string(storage.values.player_identity)
	_check(stored=={"player_id":TEST_RECOVERY_PLAYER,"device_token":original.next_device_token,"recovery_code":original.next_recovery_code} and not storage.values.has("recovery_pending"),"Ack finalizes only the pre-saved credentials, then removes the pending recovery")
	_check(app.identity_restart_required and app.pending_recovery.is_empty(),"Completed recovery requires restart and leaves no pending rotation")

	_reset_recovery_case(app,api,storage)
	storage.fail_write_names=["recovery_pending"]
	await app._recover_identity(TEST_RECOVERY_PLAYER,TEST_RECOVERY_CODE)
	var unsent: Dictionary=app.pending_recovery.duplicate(true)
	_check(api.calls.is_empty() and not storage.values.has("recovery_pending"),"Failed secure proposal write prevents the recovery POST entirely")
	storage.fail_write_names=[]
	api.responses=[{"ok":true,"data":{"player_id":TEST_RECOVERY_PLAYER,"recovered":true}}]
	await app._resume_pending_recovery()
	_check(api.calls.size()==1 and api.calls[0].body==unsent.request,"Storage retry preserves the original in-memory rotation before sending it")

	_reset_recovery_case(app,api,storage)
	storage.fail_write_names=["player_identity"]
	api.responses=[{"ok":true,"data":{"player_id":TEST_RECOVERY_PLAYER,"recovered":true}}]
	await app._recover_identity(TEST_RECOVERY_PLAYER,TEST_RECOVERY_CODE)
	original=api.calls[0].body.duplicate(true)
	_check(storage.values.has("recovery_pending") and JSON.parse_string(storage.values.player_identity).player_id=="old-player","Identity-write failure after server acceptance keeps the secured proposal for restart")
	await _restart_with_recovery(app,api,storage)
	storage.fail_write_names=[]
	storage.fail_remove=true
	api.responses=[{"ok":true,"data":{"player_id":TEST_RECOVERY_PLAYER,"recovered":true}}]
	await app._resume_pending_recovery()
	_check(api.calls[1].body==original and storage.values.has("recovery_pending") and JSON.parse_string(storage.values.player_identity).device_token==original.next_device_token,"Failed pending cleanup retains exact retry state after the new identity was saved")
	storage.fail_remove=false
	var before: int=api.calls.size()
	await app._retry_identity_storage()
	_check(api.calls.size()==before and not storage.values.has("recovery_pending") and app.pending_recovery.is_empty(),"Secure cleanup retry finishes an acknowledged rotation without another network request")

	_reset_recovery_case(app,api,storage)
	api.responses=[{"ok":true,"data":{"player_id":"different-player","recovered":true}}]
	await app._recover_identity(TEST_RECOVERY_PLAYER,TEST_RECOVERY_CODE)
	_check(storage.values.has("recovery_pending") and JSON.parse_string(storage.values.player_identity).player_id=="old-player","Mismatched recovery ack cannot overwrite the stored identity")
	original=api.calls[0].body.duplicate(true)
	api.responses=[{"ok":true,"data":{"player_id":TEST_RECOVERY_PLAYER,"device_token":"unexpected-server-generated-secret"}}]
	await app._resume_pending_recovery()
	_check(api.calls[-1].body==original and storage.values.has("recovery_pending") and JSON.parse_string(storage.values.player_identity).player_id=="old-player","Legacy secret-bearing response is rejected instead of discarding the persisted proposal")

	_reset_recovery_case(app,api,storage)
	var mismatch := {"ok":false,"status":409,"code":"recovery_request_mismatch"}
	api.responses=[mismatch]
	await app._recover_identity(TEST_RECOVERY_PLAYER,TEST_RECOVERY_CODE)
	original=api.calls[0].body.duplicate(true)
	_check(app.recovery_replace_allowed and _find_button(app.overlay,"Use a different recovery code")!=null,"Definitively rejected mismatched rotation offers entry of a current recovery code")
	api.responses=[mismatch]
	await app._recover_identity(TEST_RECOVERY_PLAYER,TEST_RECOVERY_CODE)
	_check(api.calls.size()==2 and api.calls[1].body==original,"Using the same old code still retries its exact rejected proposal")
	storage.fail_write_names=["recovery_pending"]
	await app._recover_identity(TEST_RECOVERY_PLAYER,"B".repeat(43))
	_check(api.calls.size()==2 and JSON.parse_string(storage.values.recovery_pending).request==original,"Replacement recovery cannot send until its new proposal securely overwrites the rejected one")
	var replacement: Dictionary=app.pending_recovery.request.duplicate(true)
	storage.fail_write_names=[]
	api.responses=[{"ok":true,"data":{"player_id":TEST_RECOVERY_PLAYER,"recovered":true}}]
	await app._resume_pending_recovery()
	_check(api.calls.size()==3 and api.calls[2].body==replacement and replacement.recovery_code=="B".repeat(43) and replacement.idempotency_key!=original.idempotency_key and app.pending_recovery.is_empty(),"Different current code can complete recovery after definitive mismatch rejection")

	for malformed: Dictionary in [{"ok":false},{"ok":true,"payload":{"found":true,"value":"{ malformed pending"}}]:
		_reset_recovery_case(app,api,storage)
		storage.pending_read_response=malformed
		app._load_saved_identity()
		await process_frame
		_check(app.identity_read_state==Main.IdentityReadState.FAILED and storage.calls.size()==1 and not await app._ensure_identity() and api.calls.is_empty(),"Unreadable pending recovery blocks fallback to old credentials or a fresh identity")

	_reset_recovery_case(app,api,storage)
	var legacy: Dictionary=pending.duplicate(true)
	legacy.request.player_id="mistyped-id"
	storage.pending_read_response={"ok":true,"payload":{"found":true,"value":JSON.stringify(legacy)}}
	app._load_saved_identity()
	await process_frame
	app._show_account()
	_check(api.calls.is_empty() and _find_button(app.overlay,"Recover a previous identity")!=null,"Malformed older queued input is never retried and leaves explicit recovery available")
	api.responses=[{"ok":true,"data":{"player_id":TEST_RECOVERY_PLAYER,"recovered":true}}]
	await app._recover_identity(TEST_RECOVERY_PLAYER,TEST_RECOVERY_CODE)
	_check(api.calls.size()==1 and app.pending_recovery.is_empty() and Main._recovery_field_matches(api.calls[0].body.player_id,Main.RECOVERY_ID_PATTERN),"User can correct old malformed input with a valid explicitly requested recovery")

func _find_label(node: Node, text: String) -> Label:
	if node is Label and node.text==text:
		return node
	for child: Node in node.get_children():
		var found := _find_label(child,text)
		if found!=null:
			return found
	return null

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text==text:
		return node
	for child: Node in node.get_children():
		var found := _find_button(child,text)
		if found!=null:
			return found
	return null

func _check(condition: bool, description: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+description)
