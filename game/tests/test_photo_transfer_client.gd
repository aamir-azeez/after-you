extends SceneTree
## Transport/journal fault tests; image decoding is tested by the library and Worker.
const Client = preload("res://services/photo_transfer_client.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Save = preload("res://services/local_save.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"

class Identity:
	extends RefCounted
	var player := OWNER
	var epoch := 1
	func current() -> Dictionary:
		return {"ready": true, "player_id": player, "epoch": epoch}

class Library:
	extends RefCounted
	var entries: Dictionary = {}
	var fail_import := false
	var fail_read := false
	func add(count: int) -> void:
		for index in range(count):
			var id := str(index).sha256_text()
			var bytes := ("transport-fixture-%d" % index).to_utf8_buffer()
			entries[id] = {"entry_id": id, "room_id": OWNER, "turn_id": "t0-0-a", "recording_hash": "recording".sha256_text(), "photo_revision": 0, "photo_owner": OWNER, "local_only": true, "sha256": bytes.get_string_from_utf8().sha256_text(), "width": 16, "height": 16, "byte_length": bytes.size(), "created_at": "2026-09-15T00:00:00.000Z", "jpeg_base64": Marshalls.raw_to_base64(bytes), "deleted": false}
	func list_entries(_owner: String) -> Dictionary:
		return {"ok": true, "entries": entries.values().map(func(value: Dictionary) -> Dictionary: return {"entry_id": value.entry_id})}
	func export_entry(_owner: String, id: String) -> Dictionary:
		return {"ok": false} if fail_read or not entries.has(id) else {"ok": true, "entry": entries[id].duplicate(true)}
	func import_entry(_owner: String, value: Dictionary) -> Dictionary:
		if fail_import: return {"ok": false}
		entries[value.entry_id] = value.duplicate(true)
		return {"ok": true, "durable": true, "entry_id": value.entry_id}

class Server:
	extends RefCounted
	var entries: Dictionary = {}
	var receipts: Dictionary = {}
	var session: Dictionary = {}
	var posts := 0
	var uploads := 0
	var acks := 0
	var drop_operation := ""
	var corrupt := false
	var identity_change: Callable
	func request(method: int, path: String, body: Dictionary) -> Dictionary:
		if method == HTTPClient.METHOD_GET:
			return _ok({"schema_version": 1, "session": null if session.is_empty() else session, "entry_count": entries.size(), "bytes_used": 0, "max_entries": 1000, "max_bytes": 33554432, "entries": entries.values().map(_metadata)})
		posts += 1
		if path.ends_with("/sessions"):
			if not session.is_empty() and session.session_id != body.idempotency_key: return {"ok": false, "status": 429, "code": "transfer_cooldown", "retry_after_ms": 86400000}
			session = {"session_id": body.idempotency_key, "created_at": "2026-09-15T00:00:00.000Z", "expires_at": "2026-09-29T00:00:00.000Z", "next_session_at": "2026-09-16T00:00:00.000Z"}
			return _ok({"schema_version": 1, "session": session})
		if path.ends_with("/read"):
			var result: Array = []
			for id: String in body.entry_ids:
				if not entries.has(id): return {"ok": false, "status": 404, "code": "transfer_entry_not_found"}
				result.append(entries[id].duplicate(true))
			if corrupt and not result.is_empty(): result[0].sha256 = "wrong".sha256_text()
			if identity_change.is_valid(): identity_change.call()
			return _ok({"schema_version": 1, "entries": result})
		var operation := "restore_ack" if path.ends_with("/restore-ack") else "upload"
		var material := body.duplicate(true)
		material.merge({"operation": operation, "session_id": null if operation == "restore_ack" else session.session_id})
		var hash := Canonical.digest(material)
		if receipts.has(body.idempotency_key):
			return _ok({"schema_version": 1, "receipt": receipts[body.idempotency_key]}) if receipts[body.idempotency_key].request_hash == hash else {"ok": false, "status": 409, "code": "idempotency_key_reused"}
		var accepted: Array = []
		for value: Dictionary in body.entries:
			if operation == "upload":
				var stored := value.duplicate(true)
				stored.entry_revision = 1
				stored.expires_at = "2026-09-29T00:00:00.000Z"
				entries[value.entry_id] = stored
				accepted.append({"entry_id": value.entry_id, "sha256": value.sha256, "entry_revision": 1})
			else:
				entries.erase(value.entry_id)
				accepted.append(value.duplicate(true))
		if operation == "upload": uploads += 1
		else: acks += 1
		var receipt := {"idempotency_key": body.idempotency_key, "request_hash": hash, "operation": operation, "session_id": material.session_id, "entries": accepted, "evicted_entry_ids": []}
		receipts[body.idempotency_key] = receipt
		if drop_operation == operation:
			drop_operation = ""
			return {"ok": false, "status": 0, "code": "connection_interrupted"}
		return _ok({"schema_version": 1, "receipt": receipt})
	func _metadata(value: Dictionary) -> Dictionary:
		var result := value.duplicate(true)
		result.erase("jpeg_base64")
		return result
	func _ok(value: Dictionary) -> Dictionary:
		return {"ok": true, "status": 200, "data": value}

var checks := 0
var failures: Array[String] = []
var folder := "user://photo-transfer-tests-" + str(Time.get_ticks_usec())

func _init() -> void:
	_run.call_deferred()

func check(value: bool, name: String) -> void:
	checks += 1
	if not value: failures.append(name)

func _run() -> void:
	var identity := Identity.new()
	var sender := Library.new()
	sender.add(41)
	var server := Server.new()
	var client := Client.new(server.request, identity.current, sender, folder + "/sender", 0)
	check(await client.refresh(), "read-only status works")
	check(server.posts == 0, "opening transfer never uploads private photos")
	server.drop_operation = "upload"
	check(not await client.prepare(), "lost upload confirmation pauses")
	check(server.entries.size() == 16 and server.uploads == 1, "first upload accepted once")
	var resumed := Client.new(server.request, identity.current, sender, folder + "/sender", 0)
	check(await resumed.resume_upload(), "restart resumes exact saved upload")
	check(server.entries.size() == 41 and server.uploads == 3, "bounded batches deduplicate lost confirmation")
	check(not resumed.has_pending_upload(), "completed local upload plan cleared")
	var receiver := Library.new()
	var receiving := Client.new(server.request, identity.current, receiver, folder + "/receiver", 0)
	receiver.fail_import = true
	check(not await receiving.receive(), "failed local write stops receive")
	check(server.entries.size() == 41 and server.acks == 0, "failed local save cannot delete server photos")
	receiver.fail_import = false
	server.corrupt = true
	check(not await receiving.receive(), "mismatched content rejected")
	check(server.acks == 0, "mismatched batch not acknowledged")
	server.corrupt = false
	server.drop_operation = "restore_ack"
	check(not await receiving.receive(), "lost deletion confirmation pauses")
	check(receiver.entries.size() == 16 and server.entries.size() == 25, "accepted delete follows durable import")
	var recovering := Client.new(server.request, identity.current, receiver, folder + "/receiver", 0)
	receiver.fail_read = true
	var posts_before := server.posts
	check(not await recovering.receive(), "restart rechecks actual local data before ack retry")
	check(server.posts == posts_before, "no retry ACK when received disk data cannot be read")
	receiver.fail_read = false
	check(await recovering.receive(), "lost ack reconciles idempotently then continues")
	check(receiver.entries.size() == 41 and server.entries.is_empty() and server.acks == 3, "all photos received once and temporary storage cleared")
	check(not await resumed.prepare(), "second new session in same day blocked")
	check(sender.entries.size() == 41, "cooldown never deletes local photos")
	# A different case checks an identity rotation during an awaited read.
	var other_server := Server.new()
	var other_client := Client.new(other_server.request, identity.current, sender, folder + "/another-sender", 0)
	check(await other_client.prepare(), "identity case transfer prepared")
	var empty := Library.new()
	var changed := Client.new(other_server.request, identity.current, empty, folder + "/changed", 0)
	other_server.identity_change = func(): identity.epoch += 1
	check(not await changed.receive(), "identity change discards stale network result")
	check(empty.entries.is_empty() and other_server.acks == 0, "old-owner response cannot write or ACK for new epoch")
	await _clear_plan_and_journal()
	await _pacing()
	print("Photo transfer client: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

class Clock extends RefCounted:
	var time := 0
	var calls: Array[int] = []
	var on_wait: Callable
	func now() -> int: return time
	func sleep_ms(milliseconds: int) -> void:
		time += milliseconds
		if on_wait.is_valid(): on_wait.call()

func _clear_plan_and_journal() -> void:
	var identity := Identity.new()
	var library := Library.new()
	library.add(20)
	var server := Server.new()
	server.drop_operation = "upload"
	var path := folder + "/clear"
	var client := Client.new(server.request, identity.current, library, path, 0)
	check(not await client.prepare() and client.has_pending_work(), "uncertain upload creates an actual persisted plan")
	var photos := Canonical.digest(library.entries)
	var remote := Canonical.digest(server.entries)
	var requests := server.posts
	check(client.abandon_local_plan() and not client.has_pending_work(), "explicit clear releases the expired or unwanted local plan")
	check(Canonical.digest(library.entries) == photos and Canonical.digest(server.entries) == remote and server.posts == requests, "clear keeps original photos and server copies byte-for-byte without any request")
	var reopened := Client.new(server.request, identity.current, library, path, 0)
	check(not reopened.has_pending_work(), "cleared plan stays cleared after disk reopen")
	check(not await reopened.prepare() and reopened.has_pending_upload(), "new attempt still respects the server cooldown")
	check(reopened.abandon_local_plan() and server.posts == requests + 1, "cooldown plan can be cleared without bypassing cooldown or deleting data")
	for variant: String in ["invalid", "future", "future_backup", "corrupt_only_backup"]:
		var directory := folder + "/journal-" + variant
		DirAccess.make_dir_recursive_absolute(directory)
		var file_path := directory.path_join(OWNER.sha256_text() + ".json")
		var state := {"schema_version": 1, "owner": OWNER, "upload": {}, "pending": {}}
		var envelope := Save.defaults()
		envelope.photo_transfer = state
		if variant == "invalid": envelope.photo_transfer.pending = {"path": "/unrelated"}
		if variant == "future": envelope.photo_transfer.schema_version = 2
		var file := FileAccess.open(file_path + (".backup" if variant == "corrupt_only_backup" else ""), FileAccess.WRITE)
		file.store_string("unreadable" if variant == "corrupt_only_backup" else JSON.stringify(envelope))
		file.close()
		if variant == "future_backup":
			envelope.version = 2
			file = FileAccess.open(file_path + ".backup", FileAccess.WRITE)
			file.store_string(JSON.stringify(envelope))
			file.close()
		var hashes := _journal_hashes(file_path)
		var held := Client.new(server.request, identity.current, library, directory, 0)
		requests = server.posts
		check(not await held.prepare() and not held.abandon_local_plan(), "invalid or future journal remains held: " + variant)
		check(_journal_hashes(file_path) == hashes and server.posts == requests, "held generations remain exactly unchanged: " + variant)

func _journal_hashes(path: String) -> Dictionary:
	var result := {}
	for suffix: String in ["", ".backup", ".tmp"]:
		if FileAccess.file_exists(path + suffix): result[suffix] = FileAccess.get_sha256(path + suffix)
	return result

func _pacing() -> void:
	var identity := Identity.new()
	var library := Library.new()
	library.add(1000)
	var server := Server.new()
	var clock := Clock.new()
	var transport := func(method: int, path: String, body: Dictionary) -> Dictionary:
		clock.calls.append(clock.time)
		return server.request(method, path, body)
	var client := Client.new(transport, identity.current, library, folder + "/paced-1000", Client.REQUEST_INTERVAL_MS, clock.now, clock.sleep_ms)
	check(await client.prepare() and server.entries.size() == 1000, "1000 photos upload in one continuous paced operation")
	var recipient := Library.new()
	var receive := Client.new(transport, identity.current, recipient, folder + "/paced-receive", Client.REQUEST_INTERVAL_MS, clock.now, clock.sleep_ms)
	clock.time += Client.REQUEST_INTERVAL_MS
	check(await receive.receive() and recipient.entries.size() == 1000 and server.entries.is_empty(), "1000 photos receive durably without manually continuing batches")
	var spaced := true
	for index in range(1, clock.calls.size()):
		if clock.calls[index] - clock.calls[index - 1] < Client.REQUEST_INTERVAL_MS: spaced = false
	check(spaced and clock.calls.size() > 120, "all upload/read/ACK requests respect the production interval under a virtual clock")
	var failed_calls := [0]
	var error_transport := func(_method: int, _path: String, _body: Dictionary) -> Dictionary:
		failed_calls[0] += 1
		return {"ok": false, "status": 429, "code": "rate_limited", "retry_after_ms": 5000}
	var limited := Client.new(error_transport, identity.current, library, folder + "/rate-limit", Client.REQUEST_INTERVAL_MS, clock.now, clock.sleep_ms)
	check(not await limited.refresh() and failed_calls[0] == 1, "rate-limit error returns immediately without automatic retry")
	var before := clock.time
	check(not await limited.refresh() and failed_calls[0] == 2 and clock.time - before >= 5000, "an explicit retry respects Retry-After")
	var real_calls := [0]
	var real_transport := func(_method: int, _path: String, _body: Dictionary) -> Dictionary:
		real_calls[0] += 1
		return server._ok({"schema_version": 1, "entries": [], "entry_count": 0})
	var timer_client := Client.new(real_transport, identity.current, library, folder + "/timer-cancel", 1000)
	check(await timer_client.refresh(), "first request is not artificially delayed")
	var state := {"done": false, "ok": true}
	var run := func(): state.ok = await timer_client.refresh(); state.done = true
	run.call()
	check(timer_client.busy and not state.done and real_calls[0] == 1, "second request waits on a real cancellable timer")
	timer_client.invalidate()
	var deadline := Time.get_ticks_msec() + 1500
	while not state.done and Time.get_ticks_msec() < deadline: await process_frame
	check(state.done and not state.ok and real_calls[0] == 1, "Back/invalidation cancels the timed request without sending it")
	clock.on_wait = func(): identity.epoch += 1
	var changed := Client.new(transport, identity.current, library, folder + "/paced-owner", Client.REQUEST_INTERVAL_MS, clock.now, clock.sleep_ms)
	check(await changed.refresh(), "identity pacing case begins with one authenticated read")
	var count := clock.calls.size()
	check(not await changed.refresh() and clock.calls.size() == count, "account change during a pacing wait prevents the next request")
