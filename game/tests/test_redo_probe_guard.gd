extends "res://tests/test_redo_session.gd"
## An ordinary redo around the read that checks a room this phone has not
## proven ordinary yet, and the stores both keep.
const DiskStore = preload("res://services/relay_online_store.gd")

func _registered(api: Node, identity: RefCounted, store: RefCounted) -> Dictionary:
	return {"online":Session.new(api,identity.current,store)}

func _run() -> void:
	await _guarded_redo_recovery()
	_scope_union()
	print("Redo probe guard: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _guarded_redo_recovery() -> void:
	var api := Api.new()
	root.add_child(api)
	api.rooms = {ROOM:_room(ROOM,true),OTHER:_room(OTHER,false)}
	var source := Client.source_for("relay",api.rooms[ROOM])
	api.requested = {"request_id":Canonical.digest(source),"source":source,"status":"pending"}
	var identity := Recent.Identity.new()
	identity.player = HOST
	var store := Recent.MemoryStore.new()
	var context := _registered(api,identity,store)
	var online: RefCounted = context.online
	var index_scope := "relay-lobby-v2:"+HOST
	var redo_scope := "relay-redo-relay-v1:"+HOST+":"+ROOM
	if not _check(await online.load_lobby() and await online.open_room(ROOM),"An unproven room is opened with one checked read"):
		api.queue_free()
		return
	_check(store.values[index_scope].schema_version == 2 and store.values[index_scope].standalone_ids == [ROOM],"Native verified old Relay2 receives the bounded standalone proof")
	_check(online.coordinator.snapshot().get("simulation_version") == null,"Retained omitted Relay rules remain omitted after the check")
	var client: RefCounted = online.redo_client()
	_check(client.bind_room("relay",online.coordinator.snapshot()) and await client.refresh() and client.can_accept(),"Actual accepted A exposes the existing ordinary consent request")
	api.drop_accept = true
	_check(not await client.accept() and not client.pending().is_empty(),"Real lost fork reply persists its exact redo key")
	if not store.values.has(redo_scope):
		api.queue_free()
		return
	var held: Dictionary = store.values[redo_scope].duplicate(true)
	var calls: int = api.calls.size()
	_check(not await online.open_room(OTHER) and api.calls.size() == calls and online.last_room() == ROOM,"Warm redo hold blocks the unknown-room probe before HTTP or selection")
	context = _registered(api,identity,store)
	online = context.online
	_check(await online.load_lobby(),"A cold session still lists ordinary rooms")
	calls = api.calls.size()
	_check(not await online.open_room(OTHER) and api.calls.size() == calls and online.last_room() == ROOM,"Cold redo journal blocks ordinary probe before target cache or index writes")
	_check(await online.open_room(ROOM),"Same-room recovery remains reachable")
	client = online.redo_client()
	_check(client.bind_room("relay",online.coordinator.snapshot()) and client.pending().action == "accept","Cold redo restores the original accepted-fork request")
	api.enabled = false
	_check(await online.load_lobby(),"Paused capabilities remain readable")
	calls = api.calls.size()
	_check(await client.retry(false) and client.pending().is_empty(),"Paused exact receipt GET settles the retained redo")
	_check(api.calls.size() == calls+1 and api.calls.back().method == HTTPClient.METHOD_GET,"Redo recovery sends no replacement POST")
	_check(await online.open_room(OTHER),"Settled redo releases the native-verified target probe")
	_check(online.room_ids() == [OTHER,ROOM] and online.room_summaries()[0].last_opened,"Probe success updates Recent ordering and visible room summary")
	_check(store.values[index_scope].standalone_ids.has(OTHER),"Second verified ordinary room retains its own standalone proof")
	var old_cache: Dictionary = store.values["relay-room-v2:"+HOST+":"+ROOM].duplicate(true)
	api.rooms.erase(ROOM)
	_check(await online.load_lobby() and online.room_ids() == [OTHER],"List omission prunes a schema2 ordinary index without invalidating it")
	_check(store.values[index_scope].standalone_ids == [OTHER] and Canonical.same(old_cache,store.values["relay-room-v2:"+HOST+":"+ROOM]),"Pruning removes only membership/proof hints, preserving the old native journal")
	# An old selected pointer can outlive its list row and standalone hint.
	store.values[redo_scope] = held
	store.values[index_scope].last_room = ROOM
	context = _registered(api,identity,store)
	online = context.online
	_check(await online.load_lobby() and online.pending_redo_room() == ROOM,"Cold omitted selection retains its exact redo recovery target")
	calls = api.calls.size()
	_check(not await online.open_room(OTHER) and api.calls.size() == calls,"An omitted source cannot be silently replaced by another ordinary room")
	# Known gap, left for the owner: the one check finds the room gone, but an
	# uncertain redo keeps it held (see test_redo_session).
	_check(not await online.open_room(ROOM) and api.calls.size() == calls and online.pending_redo_room() == ROOM,"The unproven omitted room is not opened before its check")
	_check(not await online.prepare_archived_navigation() and online.pending_redo_room() == ROOM and api.calls.size() == calls+1,"Its one check keeps the uncertain redo")
	_check(Canonical.same(old_cache,store.values["relay-room-v2:"+HOST+":"+ROOM]),"The check preserves the original native room journal")
	api.queue_free()
	await process_frame

func _scope_union() -> void:
	var directory := "user://redo-guard-scopes-"+Crypto.new().generate_random_bytes(8).hex_encode()
	var store := DiskStore.new(directory)
	var scopes: Array[String] = ["relay-redo-legacy-v1:"+HOST+":"+ROOM,"relay-redo-relay-v1:"+HOST+":"+ROOM,
		"relay-campaign-terminal-v1:"+HOST,"relay-campaign-admission-terminal-v1:"+HOST]
	for scope: String in scopes:
		var value := {"scope_witness":scope,"pending":{"key":"retained-exact-key"}}
		_check(store.save_scope(scope,value).ok,"Merged scope persists independently: "+scope)
		_check(Canonical.same(DiskStore.new(directory).load_scope(scope).value,value),"Fresh Store restores exact scope bytes: "+scope)
	var redo_path := directory.path_join(scopes[1].sha256_text()+".json")
	var redo_before := FileAccess.get_file_as_bytes(redo_path)
	_check(not store.save_scope(scopes[1],{"padding":"x".repeat(8192)}).ok,"Redo retains its narrow8KiB value limit")
	_check(FileAccess.get_file_as_bytes(redo_path) == redo_before,"Oversized redo cannot alter the existing generation")
	var large := {"padding":"x".repeat(60000)}
	_check(store.save_scope(scopes[3],large).ok and Canonical.same(DiskStore.new(directory).load_scope(scopes[3]).value,large),"Terminal admission retains its separately reviewed larger disk budget")
	_check(not store.save_scope(scopes[2],large).ok,"Ordinary terminal receipt scope keeps its smaller control limit")
	_check(not store.save_scope(scopes[3],{"padding":"x".repeat(DiskStore.TERMINAL_ADMISSION_VALUE_BYTES)}).ok,"Terminal admission still rejects values above its own fixed cap")
	_check(not store.save_scope("relay-redo-campaign-v1:"+HOST+":"+ROOM,{}).ok,"No unreviewed campaign redo scope is introduced")
