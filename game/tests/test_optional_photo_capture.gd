extends SceneTree

const Photos = preload("res://services/optional_photo_capture.gd")
const PHOTO_ID := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const OTHER_ID := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
var checks := 0
var failures := 0
var kept_results: Array = []
var skipped_results: Array = []
var read_results: Array = []
var completed_results: Array = []
var errors: Array = []

class FakeNative extends RefCounted:
	signal photo_result(id: String, operation: String, json: String)
	signal photo_error(id: String, operation: String, code: String)
	var calls: Array = []
	func photo_capture(id: String) -> void:
		calls.append(["capture", id])
	func photo_cancel(target: String, id: String) -> void:
		calls.append(["cancel", target, id])
	func photo_read(target: String, id: String) -> void:
		calls.append(["read", target, id])
	func photo_discard(target: String, id: String) -> void:
		calls.append(["discard", target, id])
	func photo_clear(id: String) -> void:
		calls.append(["clear", id])
	func reply(id: String, operation: String, payload: Dictionary) -> void:
		photo_result.emit(id, operation, JSON.stringify(payload))

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _wrapper(native: Object) -> Node:
	var wrapper := Photos.new(native)
	root.add_child(wrapper)
	wrapper.kept.connect(func(id: String, metadata: Dictionary): kept_results.append([id, metadata]))
	wrapper.skipped.connect(func(id: String): skipped_results.append(id))
	wrapper.bytes_ready.connect(func(id: String, metadata: Dictionary, bytes: PackedByteArray): read_results.append([id, metadata, bytes]))
	wrapper.completed.connect(func(id: String, operation: String, payload: Dictionary): completed_results.append([id, operation, payload]))
	wrapper.failed.connect(func(id: String, operation: String, code: String): errors.append([id, operation, code]))
	return wrapper

func _clear_observations() -> void:
	kept_results.clear()
	skipped_results.clear()
	read_results.clear()
	completed_results.clear()
	errors.clear()

func _bytes() -> PackedByteArray:
	# Synthetic fake-plugin bytes only; this suite tests the facade, not a JPEG codec.
	return PackedByteArray([255, 216, 12, 23, 34, 45, 255, 217])

func _metadata(photo_id: String = PHOTO_ID) -> Dictionary:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(_bytes())
	return {"status": "kept", "photo_id": photo_id, "mime": "image/jpeg", "width": 1, "height": 1, "byte_count": _bytes().size(), "sha256": hash.finish().hex_encode(), "metadata_removed": true, "uploaded": false}

func _read_payload(photo_id: String = PHOTO_ID) -> Dictionary:
	var result := _metadata(photo_id)
	result.jpeg_base64 = Marshalls.raw_to_base64(_bytes())
	return result

func _run() -> void:
	await _test_unavailable()
	await _test_capture_and_read()
	await _test_cancellation()
	await _test_validation()
	await _test_invalidation()
	await _test_explicit_clear()
	_check(checks >= 40, "All bounded wrapper test groups executed")
	print("AFTER YOU OPTIONAL PHOTO WRAPPER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_unavailable() -> void:
	_clear_observations()
	var legacy := RefCounted.new()
	var wrapper := _wrapper(legacy)
	_check(not wrapper.is_available(), "A plugin without registered photo signals exposes unavailable")
	var id: String = wrapper.capture()
	await process_frame
	_check(errors == [[id, "capture", "photo_bridge_unavailable"]], "An old plugin fails asynchronously instead of hanging a user-paced capture")
	_check(not wrapper.is_busy() and kept_results.is_empty(), "Unavailable capture cannot create a kept selection")
	wrapper.capture()
	wrapper.invalidate()
	await process_frame
	_check(errors.size() == 1, "Invalidation rejects queued unavailable callbacks and does not call absent methods")
	wrapper.free()

func _test_explicit_clear() -> void:
	_clear_observations()
	var native := FakeNative.new()
	var wrapper := _wrapper(native)
	var capture: String = wrapper.capture()
	var clear: String = wrapper.clear_photos()
	_check(native.calls[-1] == ["clear", clear] and native.calls[-2][0] == "cancel", "Explicit clear cancels the active capture and sends no path or identity")
	native.reply(capture, "capture", _metadata())
	await process_frame
	_check(kept_results.is_empty() and skipped_results.count(capture) == 1, "Clearing retires the capture once and suppresses a late kept selection")
	var busy: String = wrapper.capture()
	await process_frame
	_check(errors[-1] == [busy, "capture", "photo_busy"], "A capture cannot start while local deletion awaits acknowledgement")
	native.reply(clear, "clear", {"cleared": true})
	_check(completed_results[-1] == [clear, "clear", {"cleared": true}] and not wrapper.is_busy(), "Only exact true acknowledgement completes clear")
	var read: String = wrapper.read_photo(PHOTO_ID)
	clear = wrapper.clear_photos()
	native.reply(read, "read", _read_payload())
	await process_frame
	_check(read_results.is_empty() and errors[-1] == [read, "read", "photo_cancelled"], "Clear terminates an earlier read without exposing late bytes")
	native.photo_error.emit(clear, "clear", "photo_cleanup_unavailable")
	_check(errors[-1] == [clear, "clear", "photo_cleanup_unavailable"] and not wrapper.is_busy(), "Incomplete native cleanup stays a retryable failure")
	clear = wrapper.clear_photos()
	native.reply(clear, "clear", {"cleared": true})
	_check(completed_results[-1][0] == clear, "The caller can retry the same cleanup intent with a fresh request ID")
	for payload: Dictionary in [{"cleared": false}, {"cleared": 1}, {"cleared": true, "path": "must-not-surface"}]:
		clear = wrapper.clear_photos()
		native.reply(clear, "clear", payload)
		_check(errors[-1] == [clear, "clear", "invalid_photo_response"], "False, mistyped or extra-field clear acknowledgements cannot report success")
	clear = wrapper.clear_photos()
	wrapper._pending[clear].deadline = Time.get_ticks_msec() - 1
	wrapper._process(0)
	_check(errors[-1] == [clear, "clear", "photo_request_timeout"] and not wrapper.is_busy(), "An unanswered clear expires locally without claiming deletion")
	var completed_count := completed_results.size()
	native.reply(clear, "clear", {"cleared": true})
	_check(completed_results.size() == completed_count, "A late cleanup acknowledgement cannot complete a timed-out request")
	var clear_calls := native.calls.filter(func(item: Array) -> bool: return item[0] == "clear").size()
	wrapper.invalidate()
	wrapper.free()
	_check(native.calls.filter(func(item: Array) -> bool: return item[0] == "clear").size() == clear_calls, "Normal invalidate and scene destruction never clear the entire photo cache")

func _test_capture_and_read() -> void:
	_clear_observations()
	var native := FakeNative.new()
	var wrapper := _wrapper(native)
	_check(native.calls.is_empty() and wrapper.is_available(), "Attaching and checking the bridge never starts capture or reads data")
	var id: String = wrapper.capture()
	_check(native.calls == [["capture", id]], "Only explicit capture invokes the native camera flow")
	var busy: String = wrapper.capture()
	await process_frame
	_check(native.calls.size() == 1 and errors[-1] == [busy, "capture", "photo_busy"], "Concurrent capture is rejected without opening another flow")
	_check(wrapper._pending[id].deadline == 0, "Capture has no nine-second or other time deadline")
	wrapper._process(1000)
	_check(wrapper.is_busy(), "Elapsed process frames do not time out a user-paced capture")
	native.reply(id, "read", _read_payload())
	native.reply("unrelated", "capture", _metadata())
	_check(kept_results.is_empty() and read_results.is_empty() and wrapper.is_busy(), "Mismatched operation and request IDs cannot consume the live flow")
	native.reply(id, "capture", _metadata())
	_check(kept_results.size() == 1 and kept_results[0][0] == id and not wrapper.is_busy(), "Kept acknowledgement resolves exactly its capture request")
	_check(not kept_results[0][1].has("jpeg_base64") and read_results.is_empty() and native.calls.size() == 1, "A kept selection exposes only metadata and never performs an implicit byte read")
	kept_results[0][1].width = 500
	var read_id: String = wrapper.read_photo(PHOTO_ID)
	_check(read_id != id and native.calls[-1] == ["read", PHOTO_ID, read_id], "The explicit byte read uses an opaque photo ID and a different unique request ID")
	native.reply(read_id, "read", _read_payload())
	_check(read_results.size() == 1 and read_results[0][2] == _bytes(), "Explicit read returns exact checksum-verified bounded local bytes")
	_check(read_results[0][1].width == 1 and not read_results[0][1].has("jpeg_base64"), "Metadata and bytes remain separate and consumer metadata edits do not affect the stored reference")
	native.reply(read_id, "read", _read_payload())
	native.reply(id, "capture", _metadata())
	_check(read_results.size() == 1 and kept_results.size() == 1, "Duplicate completed native callbacks are ignored")
	var discard_id: String = wrapper.discard_photo(PHOTO_ID)
	native.reply(discard_id, "discard", {"discarded": true})
	_check(completed_results[-1] == [discard_id, "discard", {"discarded": true}] and wrapper._known.is_empty(), "Explicit discard clears only that local metadata after acknowledgement")
	wrapper.free()

func _test_cancellation() -> void:
	_clear_observations()
	var native := FakeNative.new()
	var wrapper := _wrapper(native)
	var id: String = wrapper.capture()
	var cancel: String = wrapper.cancel_capture()
	_check(native.calls[-1] == ["cancel", id, cancel], "Cancellation targets the exact active capture with its own request ID")
	native.reply(id, "capture", {"status": "skipped", "uploaded": false})
	native.reply(cancel, "cancel", {"cancelled": true})
	_check(skipped_results == [id] and completed_results[-1] == [cancel, "cancel", {"cancelled": true}], "Capture Skip and cancellation acknowledgement remain separately correlated")
	_check(not wrapper.is_busy() and kept_results.is_empty(), "A cancelled flow neither keeps an image nor blocks later explicit capture")
	id = wrapper.capture()
	cancel = wrapper.cancel_capture()
	native.reply(id, "capture", _metadata())
	_check(skipped_results[-1] == id and kept_results.is_empty(), "An already-kept result racing an explicit cancel cannot surface a new selection")
	_check(native.calls[-1][0] == "discard" and native.calls[-1][1] == PHOTO_ID, "Cancellation race discards only its exact new temporary photo")
	native.reply(cancel, "cancel", {"cancelled": false})
	_check(not wrapper.is_busy(), "A completed cancellation race clears local request state")
	id = wrapper.capture()
	cancel = wrapper.cancel_capture()
	native.reply(cancel, "cancel", {"cancelled": true})
	native.reply(id, "capture", {"status": "skipped", "uploaded": false})
	_check(skipped_results.count(id) == 1, "Reordered cancellation acknowledgement and Skip produce one terminal capture event")
	wrapper.free()

func _test_validation() -> void:
	_clear_observations()
	var native := FakeNative.new()
	var wrapper := _wrapper(native)
	for kind: String in ["wrong_id", "size", "width", "fraction", "hash", "extra", "metadata", "mime", "encoding", "hash_newline", "false_boolean"]:
		var id: String = wrapper.read_photo(PHOTO_ID)
		var payload := _read_payload()
		match kind:
			"wrong_id": payload.photo_id = OTHER_ID
			"size": payload.byte_count = Photos.MAX_BYTES + 1
			"width": payload.width = Photos.MAX_EDGE + 1
			"fraction": payload.height = 1.5
			"hash": payload.sha256 = "0".repeat(64)
			"extra": payload.unexpected = "ignored-secret-must-not-surface"
			"metadata": payload.metadata_removed = false
			"mime": payload.mime = "text/plain"
			"encoding": payload.jpeg_base64 += "\n"
			"hash_newline": payload.sha256 += "\n"
			"false_boolean": payload.uploaded = 0
		native.reply(id, "read", payload)
		_check(errors[-1] == [id, "read", "invalid_photo_response"] and read_results.is_empty(), "Invalid local byte response is bounded and rejected: " + kind)
	var before := native.calls.size()
	var invalid: String = wrapper.read_photo("../account-data")
	await process_frame
	_check(native.calls.size() == before and errors[-1] == [invalid, "read", "invalid_photo_id"], "Path-like values never reach native file methods")
	var id: String = wrapper.capture()
	var wrong := _metadata()
	wrong.jpeg_base64 = "extra-bytes"
	native.reply(id, "capture", wrong)
	_check(errors[-1] == [id, "capture", "invalid_photo_response"] and kept_results.is_empty(), "A capture result containing image bytes is rejected rather than forwarded")
	id = wrapper.read_photo(PHOTO_ID)
	native.photo_error.emit(id, "read", "unexpected_sensitive_value")
	_check(errors[-1] == [id, "read", "photo_unavailable"], "Unknown native error text never leaks into public failure messages")
	typed_timeout(wrapper, native)
	wrapper.free()

func typed_timeout(wrapper: Node, native: FakeNative) -> void:
	var id: String = wrapper.read_photo(PHOTO_ID)
	wrapper._pending[id].deadline = Time.get_ticks_msec() - 1
	wrapper._process(0)
	_check(errors[-1] == [id, "read", "photo_request_timeout"] and not wrapper.is_busy(), "Auxiliary file work expires with one bounded error")
	native.reply(id, "read", _read_payload())
	_check(read_results.is_empty(), "A late read after its timeout cannot return old image data")

func _test_invalidation() -> void:
	_clear_observations()
	var native := FakeNative.new()
	var wrapper := _wrapper(native)
	var old: String = wrapper.capture()
	wrapper.invalidate()
	_check(native.calls[-1][0] == "cancel" and native.calls[-1][1] == old, "Owner invalidation cancels only its in-flight native capture")
	var current: String = wrapper.capture()
	native.reply(old, "capture", _metadata())
	native.photo_error.emit(old, "capture", "photo_unavailable")
	_check(kept_results.is_empty() and errors.is_empty() and wrapper._capture_id == current, "Late prior-owner callbacks cannot revive metadata or cancel the new flow")
	native.reply(current, "capture", {"status": "skipped", "uploaded": false})
	var read: String = wrapper.read_photo(PHOTO_ID)
	wrapper.invalidate()
	native.reply(read, "read", _read_payload())
	_check(read_results.is_empty() and not wrapper.is_busy(), "Owner invalidation also suppresses pending byte reads")
	wrapper.read_photo("invalid")
	wrapper.invalidate()
	await process_frame
	_check(errors.is_empty(), "Queued local validation errors are generation-bound as well")
	wrapper.free()
