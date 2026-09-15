extends "res://tests/test_photo_fast_skip.gd"
## Actual replay-strip GET -> paused replay edit -> one receipt GET, no provider.
const Strip = preload("res://presentation/reaction_photo_strip.gd")

class DeferredApi:
	extends "res://tests/test_photo_fast_skip.gd".Api
	var hold_photo := false
	var receipt_failure: Dictionary = {}
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		if hold_photo and "/photos/" in path:
			hold_photo = false
			busy = true
			var request := {"method":method,"path":path,"body":body.duplicate(true),"owner":player_id}
			calls.append(request)
			await release
			var response: Dictionary = respond.call(request)
			busy = false
			return response
		if not receipt_failure.is_empty() and "/operations/" in path:
			calls.append({"method":method,"path":path,"body":body.duplicate(true),"owner":player_id})
			return receipt_failure.duplicate(true)
		return await super.request_json(method,path,body)

class Replay:
	extends "res://tests/test_reaction_photos.gd".TestPreview
	var resumed := 0
	func _clear_reaction_view() -> void:
		super._clear_reaction_view()
		if is_instance_valid(reaction_strip): reaction_strip.clear()
	func _resume_replay() -> void:
		resumed += 1
		mode = "replay"

var clock := 1000

func _receipt_count(api: DeferredApi) -> int:
	return api.calls.filter(func(call: Dictionary) -> bool: return "/operations/" in call.path).size()

func _wait_until(condition: Callable, timeout_ms: int = 2500) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(condition.call())

func _share_state(host: Control, enabled: bool) -> bool:
	var button: Button = host.button_named("Share photo with this room")
	return button != null and button.disabled == (not enabled)

func _diagnostic(flow: Node) -> String:
	return Flow._diagnostic_text(flow.last_open_diagnostic())

func _hold_replay_read(strip: Control, api: DeferredApi, reference: Dictionary) -> void:
	api.hold_photo = true
	strip.show_turns([reference])

func _run() -> void:
	var regression_only := OS.get_cmdline_user_args().has("--regression-only")
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	test_directory = "user://photo-open-wait-%d" % Time.get_ticks_usec()
	var api := DeferredApi.new()
	api.respond = _server.bind(api)
	root.add_child(api)
	var identity := Identity.new()
	var memory := Memory.new()
	var disk := Disk.new(test_directory)
	var session := Session.new(api,identity.read,memory)
	session.photo_store = disk
	_check(await session.load_lobby() and await session.create_room() == ROOM,"Real session/coordinator accepts synthetic room")
	_check(session.coordinator.save_draft(fixtures["relay-a"]) and await session.coordinator.commit(fixtures["relay-a"]),"First contribution accepted through real coordinator")
	var receipt: Dictionary = session.coordinator.last_receipt()
	_check(session.remember_photo_receipt(receipt),"Accepted receipt hint persisted before photo work")
	var scope := "turn-photo-v1:"+OWNER+":"+ROOM+":"+str(receipt.turn_id)
	var image := Image.create(1,1,false,Image.FORMAT_RGB8)
	image.fill(Color("a7dac4"))
	var bytes := image.save_jpg_to_buffer(0.7)
	var metadata := {"status":"kept","photo_id":"2".repeat(32),"mime":"image/jpeg","width":1,"height":1,"byte_count":bytes.size(),"sha256":Session.PhotoController._digest(bytes),"metadata_removed":true,"uploaded":false}
	var saved: Dictionary = disk.load_scope(scope).value
	saved.selection = metadata.duplicate(true)
	_check(disk.save_scope(scope,saved).ok,"A kept unshared photo has a durable journal")
	var journal_path: String = disk.store._path(scope)
	var journal := FileAccess.get_file_as_bytes(journal_path)
	var host := UI.Host.new()
	root.add_child(host)
	var flow := Flow.new()
	var capture := UI.Capture.new()
	capture.bytes = bytes
	capture.metadata = metadata
	flow.capture_override = capture
	if not regression_only:
		flow.clock_ms = func() -> int: return clock
	flow.configure(host,session)
	host.add_child(flow)
	var strip := Strip.new()
	strip.configure(session)
	host.add_child(strip)
	var replay := Replay.new()
	replay.mode = "paused"
	replay.replay_pair_index = 0
	replay.reaction_strip = strip
	replay.reaction_photos = flow
	root.add_child(replay)
	var reference := {"room_id":ROOM,"turn_id":receipt.turn_id,"recording_hash":receipt.recording_hash,"owner_player_id":OWNER,"own":true,"role":"a","player_slot":"p0"}
	_hold_replay_read(strip,api,reference)
	_check(api.busy and session.busy(),"Actual strip read occupies the shared API before pause-menu edit")
	var calls := _receipt_count(api)
	replay._edit_replay_photo(reference)
	_check(flow.active and host.has_button("Keep playing") and _receipt_count(api)==calls,"Pause-menu edit waits with Continue available, without failing or issuing receipt GET")
	_check(FileAccess.get_file_as_bytes(journal_path)==journal,"Waiting keeps the local selection journal byte-identical")
	api.release.emit()
	await _wait_until(func() -> bool: return _share_state(host,true))
	_check(_receipt_count(api)==calls+1 and flow.controller.target().get("gameplay_key")==receipt.idempotency_key,"Drained replay read permits exactly one authenticated receipt GET")
	_check(_share_state(host,true) and capture.reads==1,"Kept photo restores through the local adapter only after receipt verification")
	_check(FileAccess.get_file_as_bytes(journal_path)==journal and session.coordinator.last_receipt()==receipt,"Open restores preview without changing photo journal or gameplay receipt")
	if regression_only:
		flow.invalidate()
		strip.clear()
		session.invalidate_identity()
		replay.queue_free()
		await _finish(disk,host,api)
		return
	flow._continue()
	_check(replay.resumed==1,"Continue returns to the verified replay")
	_hold_replay_read(strip,api,reference)
	calls = _receipt_count(api)
	replay.mode = "paused"
	replay._edit_replay_photo(reference)
	flow._continue()
	api.release.emit()
	await create_timer(0.2).timeout
	_check(not flow.active and _receipt_count(api)==calls and FileAccess.get_file_as_bytes(journal_path)==journal,"Continue cancels waiting; drained stale request never opens editor or mutates journal")
	_hold_replay_read(strip,api,reference)
	replay.mode = "paused"
	replay._edit_replay_photo(reference)
	clock += Flow.OPEN_WAIT_MS + 1
	await create_timer(0.15).timeout
	_check(host.has_button("Try photo again") and _diagnostic(flow)=="Photo check: wait · HTTP 0 · request_busy","Bounded wait has truthful busy diagnostics and explicit retry")
	_check(_receipt_count(api)==calls and FileAccess.get_file_as_bytes(journal_path)==journal,"Timeout does not issue or retry HTTP or change local journal")
	api.release.emit()
	await create_timer(0.15).timeout
	_check(_receipt_count(api)==calls,"A request draining after timeout does not trigger a hidden retry")
	flow._continue()
	# Cover a busy API outside Session._call as well as the actual strip request.
	var outstanding := saved.duplicate(true)
	var delete_body := {"idempotency_key":"synthetic-photo-delete","recording_hash":receipt.recording_hash,"expected_photo_revision":0,"expected_photo_hash":null}
	var material := delete_body.duplicate(true)
	material.merge({"operation":"photo_delete","turn_id":receipt.turn_id})
	outstanding.pending = {"operation":"photo_delete","body":delete_body,"request_hash":Canonical.digest(material),"local_photo_id":"","held":false}
	outstanding.cleanup = ["1".repeat(32)]
	_check(disk.save_scope(scope,outstanding).ok,"Pre-existing selection, pending request and cleanup queue are durably present")
	var outstanding_bytes := FileAccess.get_file_as_bytes(journal_path)
	api.busy = true
	replay.mode = "paused"
	replay._edit_replay_photo(reference)
	flow._continue()
	api.busy = false
	await create_timer(0.15).timeout
	_check(FileAccess.get_file_as_bytes(journal_path)==outstanding_bytes and _receipt_count(api)==calls,"Cancellation preserves every byte of pending request, selection and cleanup queue")
	_check(disk.save_scope(scope,saved).ok,"Test restores its own original kept-photo journal")
	# The test intentionally saved a fresh atomic generation. From this point,
	# byte preservation compares that generation, not its earlier serialization.
	journal = FileAccess.get_file_as_bytes(journal_path)
	api.busy = true
	replay.mode = "paused"
	replay._edit_replay_photo(reference)
	_check(host.has_button("Keep playing") and _receipt_count(api)==calls,"Another API caller also blocks editor GET before dispatch")
	identity.epoch += 1
	await create_timer(0.15).timeout
	_check(_diagnostic(flow)=="Photo check: identity · HTTP 0 · identity_changed" and _receipt_count(api)==calls,"Changed identity epoch cancels wait before receipt access")
	_check(FileAccess.get_file_as_bytes(journal_path)==journal,"Identity change preserves previous owner's optional journal")
	flow._continue()
	api.busy = false
	_check(await session.load_lobby() and await session.open_room(ROOM),"Current identity explicitly reopens its room")
	api.hold_receipt = true
	flow.open_owned(reference,_continued)
	_check(flow.controller.busy(),"Receipt verification is actually awaiting HTTP before epoch changes")
	identity.epoch += 1
	api.release.emit()
	await process_frame
	_check(_diagnostic(flow)=="Photo check: identity · HTTP 0 · identity_changed" and host.has_button("Skip and continue"),"Identity change after receipt await replaces loading with a safe return path")
	_check(FileAccess.get_file_as_bytes(journal_path)==journal and flow.controller.target().is_empty(),"Old receipt callback cannot restore old-owner state or touch its journal")
	flow._continue()
	_check(await session.load_lobby() and await session.open_room(ROOM),"Explicitly reload room after the second epoch change")
	api.busy = true
	flow.open_owned(reference,_continued)
	identity.player = GUEST
	api.player_id = GUEST
	await create_timer(0.15).timeout
	_check(_diagnostic(flow)=="Photo check: identity · HTTP 0 · identity_changed" and FileAccess.get_file_as_bytes(journal_path)==journal,"Changed account during idle wait cannot access or overwrite the former owner's selection")
	flow._continue()
	api.busy = false
	identity.player = OWNER
	api.player_id = OWNER
	_check(await session.load_lobby() and await session.open_room(ROOM),"Test explicitly reopens original synthetic owner")
	calls = _receipt_count(api)
	api.receipt_failure = {"ok":false,"status":503,"code":"connection_interrupted","error":"never echo request or response bodies"}
	flow.open_owned(reference,_continued)
	await _wait_until(func() -> bool: return host.has_button("Try photo again") and _diagnostic(flow)=="Photo check: receipt · HTTP 503 · connection_interrupted")
	_check(_receipt_count(api)==calls+1 and _diagnostic(flow)=="Photo check: receipt · HTTP 503 · connection_interrupted","Receipt failure identifies fixed phase/status/code without provider body")
	await create_timer(0.15).timeout
	_check(_receipt_count(api)==calls+1 and FileAccess.get_file_as_bytes(journal_path)==journal,"Failed receipt GET is not automatically retried and leaves kept photo unchanged")
	flow._continue()
	api.receipt_failure = {}
	capture.metadata = metadata.duplicate(true)
	capture.metadata.sha256 = "f".repeat(64)
	flow.open_owned(reference,_continued)
	await _wait_until(func() -> bool: return _share_state(host,false) and _diagnostic(flow)=="Photo check: local_preview · HTTP 0 · local_photo_unavailable")
	_check(_diagnostic(flow)=="Photo check: local_preview · HTTP 0 · local_photo_unavailable" and _share_state(host,false),"Local preview failure is visibly distinguished from receipt HTTP failure")
	_check(FileAccess.get_file_as_bytes(journal_path)==journal,"Preview failure leaves the exact kept-photo selection intact")
	_check(Flow._diagnostic_text({"phase":"/private/path","http_status":"secret","code":"secret-key","body":"secret"})=="Photo check: unknown · HTTP 0 · photo_unavailable","Diagnostic formatter refuses untrusted phases/codes/status and ignores extra data")
	var diagnostic: Dictionary = flow.controller.last_open_diagnostic()
	diagnostic.phase = "changed"
	_check(flow.controller.last_open_diagnostic().phase=="journal","Diagnostic accessor does not expose mutable controller state")
	_check(capture.count==0 and api.calls.all(func(call: Dictionary) -> bool: return not ("/photos/" in call.path and call.method != HTTPClient.METHOD_GET)),"Editor scheduling never starts camera, uploads, deletes or re-commits gameplay")
	flow.invalidate()
	strip.clear()
	session.invalidate_identity()
	replay.queue_free()
	await _finish(disk,host,api)

func _finish(disk: Disk, host: Node, api: Api) -> void:
	host.queue_free()
	api.queue_free()
	await process_frame
	_check(disk.store.erase_owner(OWNER).ok,"Erase only synthetic photo journal")
	var owner_directory := test_directory.path_join(OWNER.sha256_text())
	if DirAccess.dir_exists_absolute(owner_directory): DirAccess.remove_absolute(owner_directory)
	if DirAccess.dir_exists_absolute(test_directory): DirAccess.remove_absolute(test_directory)
	print("After You photo open wait: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
