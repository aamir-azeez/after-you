extends Node
## Optional after-accept presentation. Native Use keeps locally; Share uploads.
## Uploads additionally require the live service capability and explicit Share.
const FEATURE_ENABLED := true
const Capture = preload("res://services/optional_photo_capture.gd")
const Local = preload("res://services/turn_photo_local.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var capture_override: Node
var controller_override: RefCounted
var _host: Node
var _session: RefCounted
var _capture: Node
var _local: Node
var controller: RefCounted
var active := false
var _generation := 0
var _capture_request := ""
var _capture_context: Dictionary = {}
var _continuation: Callable
var _return_label := "Continue without a photo"
var _local_preview := PackedByteArray()
var _preview_selection: Dictionary = {}
var _requested: Dictionary = {}

func configure(host: Node, session: RefCounted) -> void:
	_host = host
	_session = session

func _ready() -> void:
	_capture = Capture.new() if capture_override == null else capture_override
	add_child(_capture)
	_local = Local.new(_capture)
	add_child(_local)
	controller = _session.create_photo_controller(_local.request) if controller_override == null else controller_override
	_capture.kept.connect(_kept)
	_capture.skipped.connect(_skipped)
	_capture.failed.connect(_capture_failed)

func offer(receipt: Dictionary, continuation: Callable) -> void:
	_start(continuation)
	_requested = receipt.duplicate(true)
	var generation := _generation
	_show_loading("Your contribution is saved.", "A photo is optional. You can keep playing without one.")
	var opened: bool = await controller.open_owned_turn(str(receipt.get("room_id", "")), str(receipt.get("idempotency_key", "")))
	if not _current(generation):
		return
	if not opened or controller.target().get("turn_id") != receipt.get("turn_id") or controller.target().get("recording_hash") != receipt.get("recording_hash"):
		_show_problem(controller.last_error)
		return
	# Preserve only the receipt-backed optional journal, even on Skip. It permits
	# later edits for this device without adding fields to any gameplay save.
	if controller.selection().is_empty() and controller.pending().is_empty():
		if not controller.skip_local():
			_show_problem(controller.last_error)
			return
	if controller.cleanup_count() > 0:
		await controller.cleanup_local()
		if not _current(generation):
			return
	await _refresh_card(generation)

func open_owned(reference: Dictionary, continuation: Callable) -> void:
	var key: String = _session.local_photo_key(reference.room_id, reference.turn_id, reference.recording_hash)
	if key == "":
		_start(continuation)
		_show_problem("This device does not have the original turn receipt for editing this photo. The shared replay remains available.")
		return
	offer({"room_id": reference.room_id, "turn_id": reference.turn_id, "recording_hash": reference.recording_hash, "idempotency_key": key}, continuation)

func _start(continuation: Callable) -> void:
	invalidate()
	active = true
	_continuation = continuation
	_host.mode = "photo"

func _refresh_card(generation: int) -> void:
	if not controller.pending().is_empty():
		_show_card()
		return
	await controller.refresh_photo()
	if not _current(generation):
		return
	var message: String = controller.last_error
	if not controller.selection().is_empty():
		_show_loading("Your kept photo is on this device.", "Checking its local preview before offering Share. Nothing is being uploaded.")
		var loaded := await _load_selected_preview(generation)
		if not _current(generation):
			return
		if not loaded:
			message = "The kept photo is unavailable or changed. Retake it or skip; it has not been shared."
	_show_card(message)

func _load_selected_preview(generation: int) -> bool:
	_local_preview = PackedByteArray()
	_preview_selection = {}
	var selected: Dictionary = controller.selection()
	if selected.is_empty() or not Capture._metadata_valid(selected):
		return false
	var result: Dictionary = await _local.request("read", selected.photo_id)
	if not _current(generation) or not Canonical.same(selected, controller.selection()):
		return false
	if not result.get("ok", false) or not Canonical.same(result.get("metadata"), selected) or not result.get("bytes") is PackedByteArray:
		return false
	var bytes: PackedByteArray = result.bytes
	if bytes.size() != selected.byte_count or bytes.size() > Capture.MAX_BYTES:
		return false
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	if digest.finish().hex_encode() != selected.sha256:
		return false
	var image := Image.new()
	if image.load_jpg_from_buffer(bytes) != OK or image.get_width() != int(selected.width) or image.get_height() != int(selected.height):
		return false
	_local_preview = bytes.duplicate()
	_preview_selection = selected.duplicate(true)
	return true

func _preview_matches_selection() -> bool:
	return not _local_preview.is_empty() and not _preview_selection.is_empty() and Canonical.same(_preview_selection, controller.selection())

func _uploads_enabled() -> bool:
	var capabilities: Variant = _session.get("capabilities") if _session != null else null
	return capabilities is Dictionary and capabilities.get("photo_uploads_enabled") == true and _session.mutations_enabled()

func _show_card(message: String = "") -> void:
	if not active:
		return
	var selected: Dictionary = controller.selection()
	var pending: Dictionary = controller.pending()
	var current: Dictionary = controller.photo_metadata()
	var text := "Keep a small memory with this contribution. Only the two people in this room can view it."
	if not selected.is_empty():
		text = "This photo is kept on this device. Share sends it to your room; Use photo in the camera alone does not upload it."
	if not pending.is_empty():
		text = "Your game contribution is already saved. Check this separate photo request, or continue playing and return later."
	if message != "":
		text += "\n\n" + message
	if not _uploads_enabled():
		text += "\n\nNew photo sharing is unavailable from this service. Existing photos can still be viewed or removed."
	var card: VBoxContainer = _host._card("A memory, if you like.", text)
	var pixels: PackedByteArray = _local_preview if not selected.is_empty() else controller.image_bytes()
	_add_preview(card, pixels)
	if not pending.is_empty():
		card.add_child(_host._button("Check photo request", _reconcile))
		if pending.get("held", false):
			card.add_child(_host._button("Discard rejected photo request", _abandon))
	else:
		if not selected.is_empty():
			var share: Button = _host._button("Share photo with this room", _share)
			share.disabled = not _uploads_enabled() or not _preview_matches_selection()
			share.tooltip_text = "Photo sharing is unavailable from this service." if not _uploads_enabled() else "A readable preview of the kept photo is required." if share.disabled else ""
			card.add_child(share)
		if _capture.is_available():
			var camera: Button = _host._button("Take another photo" if not selected.is_empty() else "Optional camera photo", _open_camera)
			camera.disabled = not _uploads_enabled()
			camera.tooltip_text = "Photo sharing is unavailable from this service." if camera.disabled else ""
			card.add_child(camera)
		else:
			card.add_child(_host._label("Camera photos are unavailable in this build. You can skip this step.", 17))
		if current.get("sha256") != null:
			card.add_child(_host._button("Remove shared photo", _confirm_delete))
	card.add_child(_host._button("Skip for now" if pending.is_empty() else "Keep request and continue", _continue))

func _show_loading(title: String, text: String) -> void:
	var card: VBoxContainer = _host._card(title, text)
	card.add_child(_host._button(_return_label, _continue))

func _show_problem(message: String) -> void:
	var card: VBoxContainer = _host._card("Your contribution is already saved.", message if message != "" else "Photo sharing is unavailable. You can keep playing.")
	if not _requested.is_empty():
		card.add_child(_host._button("Try photo again", func(): offer(_requested, _continuation)))
	card.add_child(_host._button("Skip and continue", _continue))

func _open_camera() -> void:
	if not active or controller.busy() or not controller.pending().is_empty():
		return
	if not _uploads_enabled():
		_show_card()
		return
	_capture_context = controller.selection_context()
	if _capture_context.is_empty():
		_show_problem("Reopen this contribution before taking a photo.")
		return
	_show_loading("Your camera, your choice.", "Skip or close the camera at any point. A kept photo still needs a separate Share action.")
	_capture_request = _capture.capture() # Only this explicit button starts it.

func _kept(request: String, metadata: Dictionary) -> void:
	if not active or request != _capture_request:
		return
	_capture_request = ""
	var generation := _generation
	if not controller.choose_local(metadata, _capture_context):
		_show_problem(controller.last_error)
		return
	_show_loading("Photo kept on this device.", "Preparing its local preview. Nothing has been uploaded.")
	var loaded := await _load_selected_preview(generation)
	if not _current(generation):
		return
	_show_card("Local preview unavailable; you can retake or skip." if not loaded else "")

func _skipped(request: String) -> void:
	if active and request == _capture_request:
		_capture_request = ""
		_show_card()

func _capture_failed(request: String, operation: String, _code: String) -> void:
	if active and operation == "capture" and request == _capture_request:
		_capture_request = ""
		_show_card("The camera could not open. You can keep playing without a photo.")

func _share() -> void:
	if not active or controller.busy():
		return
	if not _uploads_enabled() or not _preview_matches_selection():
		_show_card("A readable local preview and an available photo service are required before sharing.")
		return
	var generation := _generation
	_show_loading("Sharing your optional photo…", "Your contribution is already safe. You can continue while this separate request finishes.")
	var shared: bool = await controller.upload_selected()
	if not _current(generation):
		return
	if shared:
		_local_preview = PackedByteArray()
		_preview_selection = {}
		await controller.cleanup_local()
		if _current(generation):
			await _refresh_card(generation)
	else:
		_show_card(controller.last_error)

func _reconcile() -> void:
	if not active or controller.busy():
		return
	var generation := _generation
	_show_loading("Checking the photo receipt…", "The original photo request is retained exactly; this does not resubmit your game turn.")
	var accepted: bool = await controller.reconcile()
	if not _current(generation):
		return
	if accepted:
		_local_preview = PackedByteArray()
		_preview_selection = {}
		await controller.cleanup_local()
		if _current(generation):
			await _refresh_card(generation)
	else:
		_show_card(controller.last_error)

func _abandon() -> void:
	if controller.abandon_rejected_request():
		_refresh_card(_generation)
	else:
		_show_card(controller.last_error)

func _confirm_delete() -> void:
	var card: VBoxContainer = _host._card("Remove this room photo?", "Your recorded contribution and replay stay unchanged. This removes only the optional photo.")
	card.add_child(_host._button("Remove photo", _delete))
	card.add_child(_host._button("Keep photo", _show_card))

func _delete() -> void:
	if not active or controller.busy():
		return
	var generation := _generation
	_show_loading("Removing the photo…", "Your replay and game progress are unchanged.")
	var removed: bool = await controller.delete_photo()
	if _current(generation):
		_show_card("Photo removed." if removed else controller.last_error)

func _continue() -> void:
	if not active:
		return
	var continuation := _continuation
	# Keep uncertain requests intact. Clean selected cache only when no mutation
	# is in flight; camera cancellation itself is handled by wrapper invalidation.
	if not controller.busy() and controller.pending().is_empty():
		controller.skip_local()
	invalidate()
	if continuation.is_valid():
		continuation.call()

func invalidate() -> void:
	_generation += 1
	active = false
	_capture_request = ""
	_capture_context = {}
	_local_preview = PackedByteArray()
	_preview_selection = {}
	_requested = {}
	_continuation = Callable()
	if is_instance_valid(_local):
		_local.invalidate()
	if is_instance_valid(_capture):
		_capture.invalidate()
	if controller != null:
		controller.invalidate_identity()

func _current(generation: int) -> bool:
	return is_inside_tree() and active and generation == _generation and is_instance_valid(_host)

func _exit_tree() -> void:
	invalidate()

static func _add_preview(card: Control, bytes: PackedByteArray) -> void:
	if bytes.is_empty() or bytes.size() > 160 * 1024:
		return
	var image := Image.new()
	if image.load_jpg_from_buffer(bytes) != OK or image.get_width() > 960 or image.get_height() > 960:
		return
	var scale := minf(90.0 / image.get_width(), 120.0 / image.get_height())
	image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	var view := TextureRect.new()
	view.name = "LocalReactionPreview"
	view.texture = ImageTexture.create_from_image(image)
	view.custom_minimum_size = Vector2(90, 120)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(view)
