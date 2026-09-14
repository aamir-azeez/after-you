extends SceneTree

const Storage = preload("res://services/local_save.gd")
const State = preload("res://services/turn_state.gd")
const Purchases = preload("res://services/purchases.gd")
const Levels = preload("res://core/levels.gd")
const Main = preload("res://main.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
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
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path+suffix):
				DirAccess.remove_absolute(path+suffix)
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
	_check(app.mode=="collection" and app.collection_preview,"Completed collection preview retains read-only origin")
	_check(_find_button(app.overlay,"Keep this island")==null,"Collection preview does not offer a second commitment")
	var generation: int=app.saves.data.generation
	app._commit_turn()
	_check(app.saves.data.generation==generation,"Direct duplicate collection commitment does not write a save")
	app._preview(second,true)
	for _i: int in range(601):
		app._physics_process(1.0/30.0)
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
