extends RefCounted
## One phone's native photo service for the online harness, with the
## AfterYouAndroid photo contract (OptionalPhotoCapture.kt, PhotoCaptureRecovery.kt):
## photo_capture opens the camera and answers only when the player comes back
## from it, a kept photo stays in the phone's cache, and a photo taken while the
## game was gone waits as the recovered photo until a turn journal holds it.
## It outlives the app on its phone, as the plugin's files do.
signal photo_result(id: String, operation: String, json: String)
signal photo_error(id: String, operation: String, code: String)

## The capture the camera is open for, or "".
var camera_request := ""
## photo_id -> {metadata, bytes}: the phone's kept photos.
var cache: Dictionary = {}
## {request_id, photo} while a photo taken under a lost game waits, or {}.
var recovered: Dictionary = {}
var captures := 0

## The camera takes a picture and the player keeps it: the game hears back.
func return_with_photo() -> void:
	var request := camera_request
	camera_request = ""
	if not request.is_empty(): _reply(request, "capture", _keep())

## Android ended the game while the camera was open; the plugin that starts next
## keeps the picture the camera wrote (PhotoCaptureRecovery.recover).
func game_lost_under_camera() -> void:
	if camera_request.is_empty(): return
	recovered = {"request_id": camera_request, "photo": _keep()}
	camera_request = ""

func photo_capture(id: String) -> void:
	if not camera_request.is_empty():
		_error(id, "capture", "photo_busy")
		return
	camera_request = id
	captures += 1

func photo_cancel(target: String, id: String) -> void:
	var cancelled := not camera_request.is_empty() and camera_request == target
	if cancelled: camera_request = ""
	_reply(id, "cancel", {"cancelled": cancelled})

func photo_read(target: String, id: String) -> void:
	var kept: Variant = cache.get(target)
	if not kept is Dictionary:
		_error(id, "read", "invalid_photo_id")
		return
	var payload: Dictionary = kept.metadata.duplicate(true)
	payload.jpeg_base64 = Marshalls.raw_to_base64(kept.bytes)
	_reply(id, "read", payload)

func photo_discard(target: String, id: String) -> void:
	_reply(id, "discard", {"discarded": cache.erase(target)})

func photo_clear(id: String) -> void:
	cache.clear()
	recovered = {}
	camera_request = ""
	_reply(id, "clear", {"cleared": true})

func photo_recovered(id: String) -> void:
	_reply(id, "recovered", {"recovered": true, "request_id": recovered.request_id, "photo": recovered.photo.duplicate(true)} if not recovered.is_empty() else {"recovered": false})

func photo_forget_recovered(target: String, id: String) -> void:
	var forgotten: bool = not recovered.is_empty() and recovered.photo.photo_id == target
	if forgotten: recovered = {}
	_reply(id, "forget_recovered", {"forgotten": forgotten})

func _keep() -> Dictionary:
	var image := Image.create(40, 30, false, Image.FORMAT_RGB8)
	image.fill(Color(0.2 + 0.1 * (captures % 5), 0.5, 0.7))
	var bytes := image.save_jpg_to_buffer(0.8)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	var metadata := {"status": "kept", "photo_id": Crypto.new().generate_random_bytes(16).hex_encode(), "mime": "image/jpeg", "width": 40, "height": 30,
		"byte_count": bytes.size(), "sha256": digest.finish().hex_encode(), "metadata_removed": true, "uploaded": false}
	cache[metadata.photo_id] = {"metadata": metadata, "bytes": bytes}
	return metadata.duplicate(true)

## The plugin answers on a later frame, never inside the call.
func _reply(id: String, operation: String, payload: Dictionary) -> void:
	call_deferred("_emit", photo_result, id, operation, JSON.stringify(payload))

func _error(id: String, operation: String, code: String) -> void:
	call_deferred("_emit", photo_error, id, operation, code)

func _emit(which: Signal, id: String, operation: String, value: String) -> void:
	which.emit(id, operation, value)
