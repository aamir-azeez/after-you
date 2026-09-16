extends SceneTree
const Photos = preload("res://tests/test_reaction_photos.gd")
const Safety = preload("res://tests/test_safety_client.gd")
const Flow = preload("res://presentation/reaction_photo_flow.gd")
const Client = preload("res://services/safety_client.gd")
const Store = preload("res://services/safety_store.gd")
class Session extends Photos.PhotoSession:
	var policy: RefCounted
	func safety_client() -> RefCounted: return policy

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func frames() -> void:
	for _i in range(4): await process_frame
func button(screen: Node, text: String) -> Button:
	for value: Node in screen.find_children("*", "Button", true, false):
		if value.text == text: return value
	return null
func _run() -> void:
	var host := Photos.Host.new()
	root.add_child(host)
	var identity := Safety.Identity.new()
	var api := Safety.Server.new()
	root.add_child(api)
	var session := Session.new()
	session.policy = Client.new(api, identity.current, Store.new("user://safety-photo-" + str(Time.get_ticks_usec())))
	var capture := Photos.Capture.new()
	var image := Image.create(24, 32, false, Image.FORMAT_RGB8)
	image.fill(Color(0.2, 0.6, 0.4))
	capture.bytes = image.save_jpg_to_buffer(0.7)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(capture.bytes)
	capture.metadata = {"status": "kept", "photo_id": Photos.PHOTO, "mime": "image/jpeg", "width": 24, "height": 32, "byte_count": capture.bytes.size(), "sha256": digest.finish().hex_encode(), "metadata_removed": true, "uploaded": false}
	var controller := Photos.PhotoController.new()
	controller.selection_value = capture.metadata.duplicate(true)
	var flow := Flow.new()
	flow.capture_override = capture
	flow.controller_override = controller
	flow.configure(host, session)
	host.add_child(flow)
	var receipt := {"room_id": Photos.ROOM, "idempotency_key": Photos.KEY, "turn_id": "t0-0-a", "recording_hash": Photos.HASH}
	await flow.offer(receipt, Callable())
	check(not flow._local_preview.is_empty() and controller.uploads == 0, "Opening genuine JPEG preview does not upload")
	await flow._share()
	await frames()
	check(controller.uploads == 0 and is_instance_valid(flow._terms_screen), "Share without current acceptance opens rules, preserving photo")
	check(api.calls.all(func(value: Dictionary): return value.method == HTTPClient.METHOD_GET), "Checking consent is GET-only")
	button(flow._terms_screen, "I accept the community rules").pressed.emit()
	await frames()
	check(api.accepted and controller.uploads == 0, "Explicit rule acceptance never uploads the waiting photo")
	button(flow._terms_screen, "Back to your photo").pressed.emit()
	await frames()
	check(not is_instance_valid(flow._terms_screen) and host.has_button("Share photo with this room"), "Returning from rules restores visible separate Share action")
	await flow._share()
	check(controller.uploads == 1 and controller.selection().is_empty(), "Second explicit Share checks current terms then uploads once")
	controller.selection_value = capture.metadata.duplicate(true)
	await flow.offer(receipt, Callable())
	api.hold_path = "/v1/safety/terms"
	flow._share()
	await frames()
	check(api.waiting and flow._checking_rules, "Deferred terms read holds upload")
	flow._continue()
	api.release.emit()
	await frames()
	check(controller.uploads == 1 and not flow.active and not controller.selection().is_empty(), "Continue while consent check waits cannot upload or erase local selection")
	api.hold_path = ""
	api.corrupt = true
	await flow.offer(receipt, Callable())
	await flow._share()
	await frames()
	check(controller.uploads == 1 and is_instance_valid(flow._terms_screen), "Future service config cannot reuse earlier positive consent")
	flow.invalidate()
	host.queue_free()
	api.queue_free()
	await frames()
	print("After You safety photo consent: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
