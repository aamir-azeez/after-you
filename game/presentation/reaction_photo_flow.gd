extends Node
## Optional after-accept presentation. Native Use keeps locally; Share uploads.
## Uploads additionally require the live service capability and explicit Share.
const FEATURE_ENABLED := true
const OPEN_WAIT_MS := 5000
const Capture = preload("res://services/optional_photo_capture.gd")
const Local = preload("res://services/turn_photo_local.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var capture_override: Node
var controller_override: RefCounted
var prompts_enabled: Callable
var save_prompt_preference: Callable
var clock_ms: Callable = Time.get_ticks_msec
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
var _return_label := "Keep playing"
var _local_preview := PackedByteArray()
var _preview_selection: Dictionary = {}
var _requested: Dictionary = {}
var _open_diagnostic: Dictionary = {}
var _last_logged_diagnostic := ""

func last_open_diagnostic() -> Dictionary:
	return _safe_diagnostic(_open_diagnostic)

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

func offer(receipt: Dictionary, continuation: Callable, automatic: bool = false) -> void:
	receipt = receipt.duplicate(true)
	if automatic and prompts_enabled.is_valid() and prompts_enabled.call() == false:
		invalidate()
		# Preserve later manual editing even when the player disables prompts.
		# A local-media failure never rolls back an accepted gameplay turn.
		_session.remember_photo_receipt(receipt)
		if continuation.is_valid(): continuation.call()
		return
	_start(continuation)
	_requested = receipt.duplicate(true)
	var generation := _generation
	# Continue can invalidate the first HTTP response. Keep the verified receipt
	# lookup first, without touching any existing pending photo or gameplay state.
	if not _session.remember_photo_receipt(receipt):
		_open_diagnostic = {"phase": "hint", "http_status": 0, "code": "hint_unavailable"}
		_show_problem(_session.last_error)
		return
	_show_loading("Your contribution is saved.", "A photo is optional. You can keep playing without one.")
	var identity: Dictionary = _session.photo_identity()
	if not await _wait_for_photo_api(generation, identity):
		return
	var opened: bool = await controller.open_owned_turn(str(receipt.get("room_id", "")), str(receipt.get("idempotency_key", "")))
	if not _current(generation):
		return
	if _session.photo_identity() != identity:
		_open_diagnostic = {"phase": "identity", "http_status": 0, "code": "identity_changed"}
		_show_problem("Your identity changed. Return to rooms before reopening this photo.")
		return
	if not opened or controller.target().get("turn_id") != receipt.get("turn_id") or controller.target().get("recording_hash") != receipt.get("recording_hash"):
		_open_diagnostic = controller.last_open_diagnostic()
		if opened:
			_open_diagnostic = {"phase": "receipt", "http_status": 200, "code": "unsupported_target"}
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

func _wait_for_photo_api(generation: int, identity: Dictionary) -> bool:
	var deadline := int(clock_ms.call()) + OPEN_WAIT_MS
	while _current(generation):
		if not identity.get("ready", false) or _session.photo_identity() != identity:
			_open_diagnostic = {"phase": "identity", "http_status": 0, "code": "identity_changed"}
			_show_problem("Your identity changed. Return to rooms before reopening this photo.")
			return false
		if not _session.photo_request_busy():
			return true
		if int(clock_ms.call()) >= deadline:
			_open_diagnostic = {"phase": "wait", "http_status": 0, "code": "request_busy"}
			_show_problem("Another room update is still finishing. Try photo again in a moment, or keep playing. Your kept photo has not been changed.")
			return false
		# Wait only for an already running request; never retry an HTTP request.
		await get_tree().create_timer(0.1).timeout
	return false

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
			_open_diagnostic = {"phase": "local_preview", "http_status": 0, "code": "local_photo_unavailable"}
			message = "The kept photo is unavailable or changed. Retake it or skip; it has not been shared."
	_show_card(message)

func _load_selected_preview(generation: int) -> bool:
	_local_preview = PackedByteArray()
	_preview_selection = {}
	_open_diagnostic = {"phase": "local_preview", "http_status": 0, "code": "local_photo_unavailable"}
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
	_open_diagnostic = {}
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
	var shared: bool = current.get("sha256") != null
	var title := "Add a tiny reaction?"
	var text := "Your turn is saved. Take an optional photo, then tap Share photo with this room."
	if shared:
		title = "Photo shared with your friend"
		text = "Saved to this turn. It will appear above your spirit when your friend opens its replay."
	if not selected.is_empty():
		title = "Ready to share your photo"
		text = "Tap Share photo with this room below to send it to your friend. It is only on this device until you share."
	if not pending.is_empty():
		title = "Photo confirmation needed"
		text = "Your turn is saved. Check the photo request to find out whether it reached your friend."
	if message != "":
		text += "\n\n" + message
	if not _uploads_enabled():
		text += "\n\nNew photo sharing is unavailable from this service. Existing photos can still be viewed or removed."
	var card: VBoxContainer = _host._card(title, text)
	_report_diagnostic()
	var pixels: PackedByteArray = _local_preview if not selected.is_empty() else controller.image_bytes()
	# Put the next action above the image, extra options and preference so it
	# remains visible without scrolling on a landscape phone.
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
		elif shared:
			card.add_child(_host._button("Done — continue playing", _continue))
	_add_preview(card, pixels)
	if pending.is_empty():
		if _capture.is_available():
			var camera: Button = _host._button("Take another photo" if not selected.is_empty() else "Optional camera photo", _open_camera)
			camera.disabled = not _uploads_enabled()
			camera.tooltip_text = "Photo sharing is unavailable from this service." if camera.disabled else ""
			card.add_child(camera)
		else:
			card.add_child(_host._label("Camera photos are unavailable in this build. You can skip this step.", 17))
		if current.get("sha256") != null:
			card.add_child(_host._button("Remove shared photo", _confirm_delete))
	if not pending.is_empty():
		card.add_child(_host._button("Keep request and continue", _continue))
	elif not selected.is_empty():
		card.add_child(_host._button("Keep on device & continue", _continue))
	elif not shared:
		card.add_child(_host._button("Continue without a photo", _continue))
	_add_prompt_preference(card)

func _show_loading(title: String, text: String) -> void:
	var card: VBoxContainer = _host._card(title, text)
	_add_prompt_preference(card)
	card.add_child(_host._button(_return_label, _continue))

func _show_problem(message: String) -> void:
	var card: VBoxContainer = _host._card("Your contribution is already saved.", message if message != "" else "Photo sharing is unavailable. You can keep playing.")
	_report_diagnostic()
	_add_prompt_preference(card)
	if not _requested.is_empty():
		card.add_child(_host._button("Try photo again", func(): offer(_requested, _continuation)))
	card.add_child(_host._button("Skip and continue", _continue))

func _report_diagnostic() -> void:
	var diagnostic := _diagnostic_text(_open_diagnostic)
	if OS.is_debug_build() and not diagnostic.is_empty() and diagnostic != _last_logged_diagnostic:
		_last_logged_diagnostic = diagnostic
		print(diagnostic) # Fixed sanitized fields only; never a request or payload.

static func _diagnostic_text(value: Dictionary) -> String:
	var safe := _safe_diagnostic(value)
	return "" if safe.is_empty() else "Photo check: %s · HTTP %d · %s" % [safe.phase, safe.http_status, safe.code]

static func _safe_diagnostic(value: Dictionary) -> Dictionary:
	if value.is_empty(): return {}
	var phase := str(value.get("phase", "unknown"))
	if phase not in ["input", "hint", "wait", "identity", "receipt", "journal", "local_preview"]: phase = "unknown"
	var code := str(value.get("code", "photo_unavailable"))
	if code not in ["identity_changed", "hint_unavailable", "storage_unavailable", "unsupported_save", "unsupported_target", "invalid_target", "invalid_photo_response", "photo_busy", "request_busy", "connection_interrupted", "rate_limited", "room_not_found", "operation_not_found", "photo_unavailable", "local_photo_unavailable"]: code = "photo_unavailable"
	var status: Variant = value.get("http_status", 0)
	if not (status is int or status is float) or not is_finite(float(status)) or status < 0 or status > 599 or status != int(status): status = 0
	return {"phase": phase, "http_status": int(status), "code": code}

func _add_prompt_preference(card: VBoxContainer) -> void:
	if not prompts_enabled.is_valid() or not save_prompt_preference.is_valid(): return
	var toggle := CheckBox.new()
	toggle.name = "PhotoPromptOptOut"
	toggle.text = "Don't ask after each turn"
	toggle.custom_minimum_size.y = 44
	toggle.button_pressed = not bool(prompts_enabled.call())
	toggle.tooltip_text = "You can still add a photo from a replay, or turn prompts back on in Settings."
	var status: Label = _host._label("", 16)
	status.name = "PhotoPromptPreferenceStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toggle.toggled.connect(func(disabled: bool):
		if save_prompt_preference.call(not disabled) != true:
			toggle.set_pressed_no_signal(not bool(prompts_enabled.call()))
			status.text = "This preference could not be saved. Please try again."
		else:
			status.text = "")
	card.add_child(toggle)
	card.add_child(status)

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
		_show_card("The photo could not be prepared. Try taking it again, or keep playing without one.")

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
		_show_card() # The verified upload receipt is already durable; show Done now.
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
		_show_card()
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
	# A native Use chose to keep this image. Continuing must not silently erase
	# that durable selection; it can be shared later from the same turn.
	# Uncertain requests stay intact too. Invalidation cancels only live callbacks.
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
	_open_diagnostic = {}
	_last_logged_diagnostic = ""
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
	var scale := minf(96.0 / image.get_width(), 96.0 / image.get_height())
	image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	var view := TextureRect.new()
	view.name = "LocalReactionPreview"
	view.texture = ImageTexture.create_from_image(image)
	view.custom_minimum_size = Vector2(96, 96)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(view)
