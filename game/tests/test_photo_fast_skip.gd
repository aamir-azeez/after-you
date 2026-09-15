extends SceneTree
## Real session/controller/disk journal with deferred synthetic HTTP, no provider.
const Session = preload("res://services/relay_online_session.gd")
const PhotoStore = preload("res://services/turn_photo_store.gd")
const Flow = preload("res://presentation/reaction_photo_flow.gd")
const UI = preload("res://tests/test_reaction_photos.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "40173cc9d5bee436613f7a"

class Memory:
	extends RefCounted
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok":true,"found":values.has(scope),"value":values.get(scope,{}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = value.duplicate(true)
		return {"ok":true}

class Identity:
	extends RefCounted
	var player := OWNER
	var epoch := 1
	var ready := true
	func read() -> Dictionary:
		return {"ready":ready,"player_id":player,"epoch":epoch}

class Disk:
	extends RefCounted
	var store: RefCounted
	var writes := 0
	var fail_write := false
	var fail_read := false
	var fail_code := "storage_unavailable"
	func _init(path: String) -> void:
		store = PhotoStore.new(path)
	func load_scope(scope: String) -> Dictionary:
		return {"ok":false} if fail_read else store.load_scope(scope)
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		if fail_write: return {"ok":false,"error":fail_code}
		writes += 1
		return store.save_scope(scope,value)

class Api:
	extends Node
	signal release
	var player_id := OWNER
	var device_token := "synthetic-not-a-credential"
	var base_url := "https://synthetic.invalid"
	var busy := false
	var hold_receipt := false
	var deny_receipt := false
	var exists := false
	var joined := false
	var index := 0
	var has_a := false
	var revision := 0
	var calls: Array = []
	var receipts: Dictionary = {}
	var respond: Callable
	func configured() -> bool:
		return true
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		busy = true
		var request := {"method":method,"path":path,"body":body.duplicate(true),"owner":player_id}
		calls.append(request)
		if hold_receipt and "/operations/" in path:
			hold_receipt = false
			await release
		var result: Dictionary = respond.call(request)
		busy = false
		return result

var checks := 0
var failures := 0
var continued := 0
var fixtures: Dictionary = {}
var level := Catalog.relay_isles()
var test_directory := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _continued() -> void:
	continued += 1

func _ok(value: Dictionary) -> Dictionary:
	return {"ok":true,"status":200,"data":value}

func _snapshot(api: Api, owner: String) -> Dictionary:
	var i := api.index
	var first: Variant = OWNER if i == 0 else GUEST
	var second: Variant = GUEST if i == 0 else OWNER
	var state := {"api_version":2,"schema_version":2,"room_id":ROOM,"revision":api.revision,"branch":0,"stage_index":i,"level_id":"relay-isles","level_version":2,"definition_hash":Canonical.digest(level),"host_id":OWNER,"guest_id":GUEST if api.joined else null,"checkpoint":fixtures[["initial-checkpoint","relay-checkpoint","final-checkpoint"][i]].duplicate(true),"a_turn_id":"t0-%d-a"%i if api.has_a else null,"completed_pair_ids":["p0-0","p0-1"].slice(0,i),"invite_expires_at":"2026-09-21T12:00:00Z","created_at":"2026-09-14T12:00:00Z","updated_at":"2026-09-14T12:00:00Z","active_role":"complete" if i==2 else ("b" if api.has_a else "a"),"first_player_id":null if i==2 else first,"active_player_id":null if i==2 else (second if api.has_a else first),"player_slot":"p0" if owner==OWNER else "p1","stage_id":"" if i==2 else level.stages[i].id,"recording_a":fixtures["relay-a" if i==0 else "garden-a"].duplicate(true) if api.has_a else null,"validation":"structural_client_replay_required"}
	if not api.joined and state.active_player_id == GUEST: state.active_player_id = null
	if owner == OWNER: state["invite_code"] = "A1".repeat(10)
	return state

func _server(request: Dictionary, api: Api) -> Dictionary:
	var path: String = request.path
	var body: Dictionary = request.body
	if path == "/v2/capabilities":
		return _ok({"api_version":2,"recording_version":2,"simulation_version":2,"mutations_enabled":true,"photo_uploads_enabled":true,"validation":"structural_client_replay_required","chapters":[{"level_id":"relay-isles","level_version":2,"definition_hash":Canonical.digest(level),"premium":false}]})
	if path == "/v2/rooms":
		if request.method == HTTPClient.METHOD_POST:
			api.exists = true
			return _ok(_snapshot(api,request.owner))
		return _ok({"rooms":[_snapshot(api,request.owner)] if api.exists else []})
	if path == "/v2/rooms/" + ROOM: return _ok(_snapshot(api,request.owner))
	if "/operations/" in path:
		var key := path.get_file()
		if api.deny_receipt or not api.receipts.has(key): return {"ok":false,"status":404,"code":"operation_not_found"}
		return _ok({"receipt":api.receipts[key].duplicate(true),"room":_snapshot(api,request.owner)})
	if "/photos/" in path:
		return _ok({"photo":null,"jpeg_base64":null}) if request.method == HTTPClient.METHOD_GET else {"ok":false,"status":0,"code":"connection_interrupted"}
	if path.ends_with("/turns"):
		var record: Dictionary = body.recording
		var key: String = body.idempotency_key
		var index := api.index
		var material := body.duplicate(true)
		material["operation"] = "turns"
		api.revision += 1
		api.has_a = record.role == "a"
		if record.role == "b": api.index += 1
		var receipt := {"schema_version":2,"room_id":ROOM,"idempotency_key":key,"request_hash":Canonical.digest(material),"operation":"turns","accepted_revision":api.revision,"branch":0,"stage_index":index,"stage_id":record.stage_id,"turn_id":"t0-%d-%s"%[index,record.role],"recording_hash":record.recording_hash,"pair_id":"p0-%d"%index if record.role=="b" else null,"checkpoint_hash":fixtures[["initial-checkpoint","relay-checkpoint","final-checkpoint"][api.index]].checkpoint_hash}
		api.receipts[key] = receipt
		return _ok({"receipt":receipt,"room":_snapshot(api,request.owner)})
	return {"ok":false,"status":404,"code":"not_found"}

func _run() -> void:
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	test_directory = "user://photo-fast-skip-%d" % Time.get_ticks_usec()
	var api := Api.new()
	api.respond = _server.bind(api)
	root.add_child(api)
	var identity := Identity.new()
	var memory := Memory.new()
	var disk := Disk.new(test_directory)
	var session := Session.new(api,identity.read,memory)
	session.photo_store = disk
	_check(await session.load_lobby() and await session.create_room() == ROOM,"Create a real verified coordinator through synthetic transport")
	_check(session.coordinator.save_draft(fixtures["relay-a"]) and await session.coordinator.commit(fixtures["relay-a"]),"Actual first contribution accepted and natively verified")
	var first: Dictionary = session.coordinator.last_receipt()
	var scope := "turn-photo-v1:" + OWNER + ":" + ROOM + ":t0-0-a"
	_check(not disk.load_scope(scope).found,"Fresh accepted turn initially has no optional photo journal")
	var host := UI.Host.new()
	root.add_child(host)
	var capture := UI.Capture.new()
	var flow := Flow.new()
	flow.capture_override = capture
	flow.configure(host,session)
	host.add_child(flow)
	api.hold_receipt = true
	flow.offer(first,_continued)
	_check(api.busy and flow.controller.busy(),"Real photo controller is busy awaiting its initial receipt GET")
	_check(disk.load_scope(scope).found and session.local_photo_key(ROOM,"t0-0-a",first.recording_hash)==first.idempotency_key,"Receipt hint reaches the real disk journal before any await")
	_check(host.has_button("Keep playing"),"Continue remains available during the HTTP wait")
	flow._continue()
	api.release.emit()
	await process_frame
	_check(continued==1 and not flow.active and flow.controller.target().is_empty(),"Fast Skip invalidates late busy-controller response without restoring UI")
	_check(capture.count==0 and api.calls.all(func(call: Dictionary) -> bool: return not ("/photos/" in call.path and call.method != HTTPClient.METHOD_GET)),"Fast Skip starts no camera or media mutation")
	# The partner completes stage0 and accepts its stage1 A. The local coordinator
	# then replays that exact snapshot and genuinely commits its own second turn.
	api.joined = true
	api.index = 1
	api.has_a = true
	api.revision = 4
	_check(await session.coordinator.refresh(),"New partner checkpoint/source passes actual native replay verification")
	_check(session.coordinator.save_draft(fixtures["garden-b"]) and await session.coordinator.commit(fixtures["garden-b"]),"Next own contribution genuinely overwrites the latest gameplay receipt")
	_check(session.coordinator.last_receipt().turn_id=="t0-1-b" and session.coordinator.last_receipt().idempotency_key!=first.idempotency_key,"Latest receipt no longer contains the original key")
	flow.queue_free()
	await process_frame
	session.invalidate_identity()
	var restarted := Session.new(api,identity.read,memory)
	var restarted_disk := Disk.new(test_directory)
	restarted.photo_store = restarted_disk
	_check(await restarted.load_lobby() and await restarted.open_room(ROOM),"Restart loads saved gameplay and current room")
	_check(restarted.local_photo_key(ROOM,"t0-0-a",first.recording_hash)==first.idempotency_key,"Original historical key survives a later own receipt and a fresh disk-store instance")
	# The same regression can be run against the exact pre-fix product files,
	# before tests for the new retention API. This is a test-only early exit.
	if OS.get_cmdline_user_args().has("--regression-only"):
		await _finish(restarted_disk,host,api)
		return
	flow = Flow.new()
	flow.capture_override = UI.Capture.new()
	flow.configure(host,restarted)
	host.add_child(flow)
	var reference := {"room_id":ROOM,"turn_id":"t0-0-a","recording_hash":first.recording_hash}
	await flow.open_owned(reference,_continued)
	_check(flow.controller.target().get("gameplay_key")==first.idempotency_key and host.has_button("Optional camera photo"),"Historical entry re-fetches original authenticated receipt before allowing editing")
	_check(api.calls.any(func(call: Dictionary) -> bool: return call.path.ends_with("/operations/"+str(first.idempotency_key))),"Historical editing uses the exact retained operation key")
	flow._continue()
	await _guards(restarted,restarted_disk,api,identity,first,host,flow)
	await _finish(restarted_disk,host,api)

func _finish(disk: Disk, host: Node, api: Api) -> void:
	host.queue_free()
	api.queue_free()
	await process_frame
	_check(disk.store.erase_owner(OWNER).ok,"Erase only synthetic owner journals")
	_check(disk.store.erase_owner(GUEST).ok,"Other synthetic owner has no leaked journal")
	var owner_directory := test_directory.path_join(OWNER.sha256_text())
	if DirAccess.dir_exists_absolute(owner_directory): DirAccess.remove_absolute(owner_directory)
	if DirAccess.dir_exists_absolute(test_directory): DirAccess.remove_absolute(test_directory)
	print("After You photo fast Skip: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _guards(session: RefCounted, disk: Disk, api: Api, identity: Identity, first: Dictionary, host: Control, flow: Node) -> void:
	var latest: Dictionary = session.coordinator.last_receipt()
	var scope := "turn-photo-v1:" + OWNER + ":" + ROOM + ":" + str(latest.turn_id)
	var changed := latest.duplicate(true)
	changed.recording_hash = "f".repeat(64)
	var writes := disk.writes
	_check(not session.remember_photo_receipt(changed) and disk.writes==writes,"Mismatched receipt cannot create a hint even with plausible identifiers")
	var bare := {"room_id":ROOM,"turn_id":latest.turn_id,"recording_hash":latest.recording_hash,"idempotency_key":latest.idempotency_key}
	_check(not session.remember_photo_receipt(bare),"Arbitrary replay reference cannot seed a previously absent hint")
	disk.fail_write = true
	var calls := api.calls.size()
	await flow.offer(latest,_continued)
	_check(host.has_button("Skip and continue") and host.has_button("Try photo again") and api.calls.size()==calls,"Failed synchronous local write reports retry/Continue without dispatching optional HTTP")
	flow._continue()
	_check(not disk.load_scope(scope).found and session.coordinator.last_receipt()==latest,"Failed hint write leaves gameplay receipt and progress intact")
	disk.fail_code = "local_photo_history_full"
	await flow.offer(latest,_continued)
	_check(host.has_button("Skip and continue") and api.calls.size()==calls and session.coordinator.last_receipt()==latest,"Local photo-history capacity failure remains optional and cannot fail gameplay")
	flow._continue()
	disk.fail_write = false
	_check(session.remember_photo_receipt(latest),"Explicit retry persists the latest verified receipt after storage recovers")
	var saved: Dictionary = disk.load_scope(scope).value
	# A valid outstanding delete request plus cleanup work must remain untouched.
	var body := {"idempotency_key":"synthetic-photo-delete","recording_hash":latest.recording_hash,"expected_photo_revision":0,"expected_photo_hash":null}
	var material := body.duplicate(true)
	material.merge({"operation":"photo_delete","turn_id":latest.turn_id})
	saved.pending = {"operation":"photo_delete","body":body,"request_hash":Canonical.digest(material),"local_photo_id":"","held":false}
	saved.selection = {"status":"kept","photo_id":"2".repeat(32),"mime":"image/jpeg","width":1,"height":1,"byte_count":1,"sha256":"a".repeat(64),"metadata_removed":true,"uploaded":false}
	saved.cleanup = ["1".repeat(32)]
	_check(disk.save_scope(scope,saved).ok,"Store a structurally valid uncertain photo request")
	var before := JSON.stringify(disk.load_scope(scope).value)
	var journal_path: String = disk.store._path(scope)
	var before_bytes := FileAccess.get_file_as_bytes(journal_path)
	writes = disk.writes
	_check(session.remember_photo_receipt(latest) and disk.writes==writes and JSON.stringify(disk.load_scope(scope).value)==before and FileAccess.get_file_as_bytes(journal_path)==before_bytes,"Remembering a matching receipt preserves exact pending/selection/cleanup journal bytes with no write")
	var controller: RefCounted = session.create_photo_controller(Callable())
	_check(await controller.open_owned_turn(ROOM,latest.idempotency_key) and not controller.pending().is_empty(),"Unchanged strict controller accepts the preserved outstanding request")
	controller.invalidate_identity()
	disk.fail_read = true
	writes = disk.writes
	_check(not session.remember_photo_receipt(latest) and disk.writes==writes,"Unreadable journal is held, never overwritten")
	disk.fail_read = false
	api.deny_receipt = true
	await flow.open_owned({"room_id":ROOM,"turn_id":first.turn_id,"recording_hash":first.recording_hash},_continued)
	_check(not host.has_button("Optional camera photo") and flow.controller.target().is_empty(),"A durable hint alone cannot bypass authoritative receipt GET denial")
	flow._continue()
	api.deny_receipt = false
	api.hold_receipt = true
	flow.open_owned({"room_id":ROOM,"turn_id":first.turn_id,"recording_hash":first.recording_hash},_continued)
	_check(flow.controller.busy(),"Historical receipt verification is genuinely pending before identity epoch changes")
	writes = disk.writes
	identity.epoch += 1
	session.invalidate_identity()
	flow.invalidate()
	api.release.emit()
	await process_frame
	_check(not flow.active and flow.controller.target().is_empty() and disk.writes==writes,"Changed identity epoch discards the old response without photo journal or UI revival")
	identity.player = GUEST
	api.player_id = GUEST
	writes = disk.writes
	_check(not session.remember_photo_receipt(latest) and disk.writes==writes,"Changed owner cannot reuse the previous owner's coordinator receipt or journal")
	_check(session.local_photo_key(ROOM,first.turn_id,first.recording_hash)=="","Previous owner's historical hint is invisible after identity switch")
	identity.ready = false
	_check(not session.remember_photo_receipt(first) and disk.writes==writes,"Deleted/unready identity cannot retain a new hint")
