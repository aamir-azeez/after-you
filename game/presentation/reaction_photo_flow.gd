extends Node
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Optional after-accept presentation on the polaroid card. The camera keeps the photo on this
## phone; Send with turn uploads it. Uploads also need the live service capability.
## A photo taken while After You was closed under the camera comes back through the resume
## record (photo_capture_resume.gd) and is offered again for the same saved turn.
const FEATURE_ENABLED := true
const OPEN_WAIT_MS := 5000
const Capture = preload("res://services/optional_photo_capture.gd")
const Local = preload("res://services/turn_photo_local.gd")
const Resume = preload("res://services/photo_capture_resume.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const SafetyScreen = preload("res://presentation/safety_screen.gd")
const Polaroid = preload("res://presentation/photo_polaroid_card.gd")
var capture_override: Node
var controller_override: RefCounted
var resume_store: RefCounted
var prompts_enabled: Callable
var save_prompt_preference: Callable
var reduced_motion: Callable
var clock_ms: Callable = Time.get_ticks_msec
var _host: Node
var _session: RefCounted
var _context_factory: RefCounted
var _capture: Node
var _local: Node
var controller: RefCounted
var active := false
var _generation := 0
var _capture_request := ""
var _capture_context: Dictionary = {}
var _capture_target: Dictionary = {}
var _continuation: Callable
var _local_preview := PackedByteArray()
var _preview_selection: Dictionary = {}
var _requested: Dictionary = {}
var _resume: Dictionary = {}
var _recovered := false
var _missing := false
var _fresh_photo := false
var _open_diagnostic: Dictionary = {}
var _last_logged_diagnostic := ""
var _checking_rules := false
var _terms_screen: CanvasLayer

func last_open_diagnostic() -> Dictionary:
	return _safe_diagnostic(_open_diagnostic)

func configure(host: Node, session: RefCounted, context_factory: RefCounted = null) -> void:
	_host = host
	_session = session
	_context_factory = context_factory

func _ready() -> void:
	_capture = Capture.new() if capture_override == null else capture_override
	add_child(_capture)
	_local = Local.new(_capture)
	add_child(_local)
	if resume_store == null:
		resume_store = Resume.new()
	if controller_override != null:
		controller = controller_override
	elif _context_factory != null:
		controller = _session.create_photo_controller(_local.request, _context_factory)
	else:
		controller = _session.create_photo_controller(_local.request)
	_capture.kept.connect(_kept)
	_capture.skipped.connect(_skipped)
	_capture.failed.connect(_capture_failed)

## resume_entry: a photo-capture-resume entry for this turn. It is never the automatic path,
## so a photo the player took is offered again even when prompts are off.
func offer(receipt: Dictionary, continuation: Callable, automatic: bool = false, resume_entry: Dictionary = {}) -> void:
	receipt = receipt.duplicate(true)
	if automatic and resume_entry.is_empty() and prompts_enabled.is_valid() and prompts_enabled.call() == false:
		invalidate()
		# Preserve later manual editing even when the player disables prompts.
		# A local-media failure never rolls back an accepted gameplay turn.
		_session.remember_photo_receipt(receipt)
		if continuation.is_valid(): continuation.call()
		return
	_start(continuation)
	_requested = receipt.duplicate(true)
	_resume = resume_entry.duplicate(true)
	var generation := _generation
	# Continue can invalidate the first HTTP response. Keep the verified receipt
	# lookup first, without touching any existing pending photo or gameplay state.
	if not _session.remember_photo_receipt(receipt):
		_open_diagnostic = {"phase": "hint", "http_status": 0, "code": "hint_unavailable"}
		_show_problem(_session.last_error)
		return
	_show_loading(PlayerCopy.PHOTO_SAVED_TITLE, PlayerCopy.PHOTO_PREPARING_LINE)
	var identity: Dictionary = _session.photo_identity()
	if not await _wait_for_photo_api(generation, identity):
		return
	var opened: bool = await controller.open_owned_turn(str(receipt.get("room_id", "")), str(receipt.get("idempotency_key", "")))
	if not _current(generation):
		return
	if _session.photo_identity() != identity:
		_open_diagnostic = {"phase": "identity", "http_status": 0, "code": "identity_changed"}
		_show_problem(PlayerCopy.REACTION_PHOTO_FLOW_F22FD944C522)
		return
	if not opened or controller.target().get("turn_id") != receipt.get("turn_id") or controller.target().get("recording_hash") != receipt.get("recording_hash"):
		_open_diagnostic = controller.last_open_diagnostic()
		if opened:
			_open_diagnostic = {"phase": "receipt", "http_status": 200, "code": "unsupported_target"}
		_show_problem(controller.last_error)
		return
	if not _resume.is_empty() and not _adopt_resume(str(identity.get("player_id", ""))):
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

## The opened turn takes the photo kept before After You closed. The resume entry goes only
## once the turn's journal holds that photo; an entry without a photo is offered once.
func _adopt_resume(owner: String) -> bool:
	var entry := _resume
	_resume = {}
	var photo: Dictionary = entry.get("photo", {})
	if photo.is_empty():
		_missing = controller.selection().is_empty() and controller.pending().is_empty()
		resume_store.remove(owner, entry.room_id, entry.turn_id)
		return true
	if not controller.pending().is_empty():
		return true # An earlier send is still unconfirmed; that comes first. The entry waits.
	if not controller.choose_recovered(photo, entry):
		return false
	_recovered = true
	_fresh_photo = true
	resume_store.remove(owner, entry.room_id, entry.turn_id)
	return true

func _wait_for_photo_api(generation: int, identity: Dictionary) -> bool:
	var deadline := int(clock_ms.call()) + OPEN_WAIT_MS
	while _current(generation):
		if not identity.get("ready", false) or _session.photo_identity() != identity:
			_open_diagnostic = {"phase": "identity", "http_status": 0, "code": "identity_changed"}
			_show_problem(PlayerCopy.REACTION_PHOTO_FLOW_F22FD944C522)
			return false
		if not _session.photo_request_busy():
			return true
		if int(clock_ms.call()) >= deadline:
			_open_diagnostic = {"phase": "wait", "http_status": 0, "code": "request_busy"}
			_show_problem(PlayerCopy.REACTION_PHOTO_FLOW_F9CD4C279F7B)
			return false
		# Wait only for an already running request; never retry an HTTP request.
		await get_tree().create_timer(0.1).timeout
	return false

func open_owned(reference: Dictionary, continuation: Callable, resume_entry: Dictionary = {}) -> void:
	var key: String = _session.local_photo_key(reference.room_id, reference.turn_id, reference.recording_hash)
	if key == "":
		key = str(resume_entry.get("gameplay_key", "")) # Still verified by the receipt GET.
	if key == "":
		_start(continuation)
		_show_problem(PlayerCopy.REACTION_PHOTO_FLOW_F33AB1CD15E0)
		return
	offer({"room_id": reference.room_id, "turn_id": reference.turn_id, "recording_hash": reference.recording_hash, "idempotency_key": key}, continuation, false, resume_entry)

## Reopens the photo card for a turn of this room that still waits for its photo after After
## You closed under the camera. can_open is checked again after the native read.
func resume_for_room(room_id: String, continuation: Callable, can_open: Callable = Callable()) -> bool:
	if active or resume_store == null or _session == null:
		return false
	var identity: Dictionary = _session.photo_identity()
	if not identity.get("ready", false):
		return false
	var owner := str(identity.get("player_id", ""))
	var generation := _generation
	if _capture.is_available():
		await resume_store.sync_native(owner, _local.request)
	if active or generation != _generation or not is_inside_tree() or _session.photo_identity() != identity:
		return false
	if can_open.is_valid() and can_open.call() != true:
		return false
	var entry: Dictionary = resume_store.entry_for_room(owner, room_id)
	if entry.is_empty():
		return false
	open_owned({"room_id": entry.room_id, "turn_id": entry.turn_id, "recording_hash": entry.recording_hash}, continuation, entry)
	return true

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
		_show_loading(PlayerCopy.PHOTO_FINDING_TITLE, PlayerCopy.PHOTO_STAYS_LINE)
		var loaded := await _load_selected_preview(generation)
		if not _current(generation):
			return
		if not loaded:
			_open_diagnostic = {"phase": "local_preview", "http_status": 0, "code": "local_photo_unavailable"}
			message = PlayerCopy.REACTION_PHOTO_FLOW_501E887479CC
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
	if controller.has_method("keep_selected_bytes") and not controller.keep_selected_bytes(selected, bytes):
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
	var uploads := _uploads_enabled()
	var camera: bool = _capture.is_available()
	var title := PlayerCopy.PHOTO_MISSING_TITLE if _missing else PlayerCopy.PHOTO_ASK_TITLE
	var line := PlayerCopy.PHOTO_MISSING_LINE if _missing else PlayerCopy.PHOTO_ASK_LINE
	if shared:
		title = PlayerCopy.PHOTO_SENT_TITLE
		line = PlayerCopy.PHOTO_SENT_LINE
	if not selected.is_empty():
		title = PlayerCopy.PHOTO_RECOVERED_TITLE if _recovered else PlayerCopy.PHOTO_READY_TITLE
		line = PlayerCopy.PHOTO_RECOVERED_LINE if _recovered else PlayerCopy.PHOTO_READY_LINE
	if not pending.is_empty():
		title = PlayerCopy.PHOTO_PENDING_TITLE
		line = PlayerCopy.PHOTO_PENDING_LINE
	if message != "":
		line = message
	if not camera and pending.is_empty():
		line += "\n" + PlayerCopy.REACTION_PHOTO_FLOW_05242B763D6D
	if not uploads:
		line += "\n" + PlayerCopy.PHOTO_UPLOADS_OFF
	var card := _card(title, line)
	_report_diagnostic()
	var pixels: PackedByteArray = _local_preview if not selected.is_empty() else controller.image_bytes()
	card.show_photo(pixels, _fresh_photo, _taken_at(selected))
	_fresh_photo = false
	# The next action leads the row; the photo sits beside it, so nothing scrolls.
	if not pending.is_empty():
		card.add_primary(PlayerCopy.PHOTO_CHECK, _reconcile, "", "PhotoCheck")
		card.add_secondary(PlayerCopy.PHOTO_NOT_NOW, _continue, "PhotoContinue")
		if pending.get("held", false):
			card.add_extra(PlayerCopy.PHOTO_DISCARD_REQUEST, _abandon, "PhotoDiscardRequest")
	elif not selected.is_empty():
		var send: Button = card.add_primary(PlayerCopy.PHOTO_SEND, _share, "send", "PhotoSend")
		send.disabled = not uploads or not _preview_matches_selection()
		send.tooltip_text = PlayerCopy.REACTION_PHOTO_FLOW_E4147F1F1B98 if not uploads else PlayerCopy.REACTION_PHOTO_FLOW_C16AA580197E if send.disabled else ""
		if camera: _add_retake(card, uploads)
		# Not now keeps the photo with this turn on this phone; it can be sent later.
		card.add_secondary(PlayerCopy.PHOTO_NOT_NOW, _continue, "PhotoContinue")
	elif shared:
		card.add_primary(PlayerCopy.PHOTO_DONE, _continue, "", "PhotoDone")
		if camera: _add_retake(card, uploads)
	else:
		if camera:
			var take: Button = card.add_primary(PlayerCopy.PHOTO_TAKE, _open_camera, "camera", "PhotoTake")
			take.disabled = not uploads
			take.tooltip_text = PlayerCopy.REACTION_PHOTO_FLOW_E4147F1F1B98 if take.disabled else ""
		card.add_secondary(PlayerCopy.PHOTO_SKIP, _continue, "PhotoSkip")
	if pending.is_empty() and shared:
		card.add_extra(PlayerCopy.PHOTO_REMOVE, _confirm_delete, "PhotoRemove")
	_add_prompt_preference(card)

## When the selected photo was taken (UTC seconds), or 0 for a photo kept before that existed.
static func _taken_at(selected: Dictionary) -> int:
	var value: Variant = selected.get("taken_at", 0)
	return int(value) if (value is int or value is float) and value > 0 else 0

func _add_retake(card: Control, uploads: bool) -> void:
	var retake: Button = card.add_icon("retake", PlayerCopy.PHOTO_RETAKE, _open_camera, "PhotoRetake")
	retake.disabled = not uploads
	if retake.disabled: retake.tooltip_text = PlayerCopy.REACTION_PHOTO_FLOW_E4147F1F1B98

func _card(title: String, line: String) -> Control:
	var root: Control = _host._photo_overlay()
	var card: Control = Polaroid.new()
	card.reduced_motion = reduced_motion.is_valid() and reduced_motion.call() == true
	root.add_child(card)
	var font: Variant = _host.get("title_font")
	card.build(title, line, font if font is Font else null)
	return card

func _show_loading(title: String, text: String, pixels: PackedByteArray = PackedByteArray()) -> void:
	var card := _card(title, text)
	card.show_photo(pixels, false, _taken_at(controller.selection()) if not pixels.is_empty() else 0)
	card.add_secondary(PlayerCopy.PHOTO_KEEP_PLAYING, _continue, "PhotoContinue")
	_add_prompt_preference(card)

func _show_problem(message: String) -> void:
	var card := _card(PlayerCopy.PHOTO_SAVED_TITLE, message if message != "" else PlayerCopy.PHOTO_PROBLEM_LINE)
	_report_diagnostic()
	if not _requested.is_empty():
		var requested := _requested
		var continuation := _continuation
		card.add_primary(PlayerCopy.PHOTO_TRY_AGAIN, func(): offer(requested, continuation), "", "PhotoRetry")
	card.add_secondary(PlayerCopy.PHOTO_SKIP, _continue, "PhotoSkip")
	_add_prompt_preference(card)

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

func _add_prompt_preference(card: Control) -> void:
	if not prompts_enabled.is_valid() or not save_prompt_preference.is_valid(): return
	var toggle: Button = card.add_switch(PlayerCopy.PHOTO_ASK_TOGGLE, bool(prompts_enabled.call()))
	toggle.name = "PhotoPromptToggle"
	toggle.tooltip_text = PlayerCopy.REACTION_PHOTO_FLOW_116335ADC805
	var status: Label = card.add_status()
	status.name = "PhotoPromptPreferenceStatus"
	toggle.toggled.connect(func(enabled: bool):
		if save_prompt_preference.call(enabled) != true:
			toggle.set_pressed_no_signal(bool(prompts_enabled.call()))
			toggle.icon = Polaroid.switch_icon(toggle.button_pressed)
			status.text = PlayerCopy.REACTION_PHOTO_FLOW_A2E7A1295771
		else:
			status.text = ""
		status.visible = not status.text.is_empty())

func _open_camera() -> void:
	if not active or controller.busy() or not controller.pending().is_empty():
		return
	if not _uploads_enabled():
		_show_card()
		return
	_capture_context = controller.selection_context()
	if _capture_context.is_empty():
		_show_problem(PlayerCopy.REACTION_PHOTO_FLOW_BD2F56F100B2)
		return
	_capture_target = controller.target()
	_show_loading(PlayerCopy.PHOTO_CAMERA_TITLE, PlayerCopy.PHOTO_STAYS_LINE)
	var owner := str(_capture_target.get("owner_player_id", ""))
	var target := _capture_target.duplicate(true)
	var store := resume_store
	# Only this explicit button starts the camera. Which turn it is for is saved first, so a
	# photo taken while Android closes After You comes back to this turn.
	_capture_request = _capture.capture(func(request: String): store.begin(owner, target, request))

func _kept(request: String, metadata: Dictionary) -> void:
	if not active or request != _capture_request:
		return
	_capture_request = ""
	var generation := _generation
	if not controller.choose_local(metadata, _capture_context):
		_show_problem(controller.last_error)
		return
	_recovered = false
	_missing = false
	_fresh_photo = true
	_show_loading(PlayerCopy.PHOTO_KEEPING_TITLE, PlayerCopy.PHOTO_STAYS_LINE)
	# The turn's journal holds the photo now, so the restart safety net can let it go.
	_end_capture()
	await _local.request("forget_recovered", str(metadata.get("photo_id", "")))
	if not _current(generation):
		return
	var loaded := await _load_selected_preview(generation)
	if not _current(generation):
		return
	_show_card(PlayerCopy.REACTION_PHOTO_FLOW_6B20ACA59BA8 if not loaded else "")

func _skipped(request: String) -> void:
	if active and request == _capture_request:
		_capture_request = ""
		_end_capture()
		_show_card()

func _capture_failed(request: String, operation: String, _code: String) -> void:
	if active and operation == "capture" and request == _capture_request:
		_capture_request = ""
		_end_capture()
		_show_card(PlayerCopy.REACTION_PHOTO_FLOW_156243CB54D5)

func _end_capture() -> void:
	if not _capture_target.is_empty() and resume_store != null:
		resume_store.remove(str(_capture_target.get("owner_player_id", "")), str(_capture_target.get("room_id", "")), str(_capture_target.get("turn_id", "")))
	_capture_target = {}

func _share() -> void:
	if not active or controller.busy() or _checking_rules or is_instance_valid(_terms_screen):
		return
	if not _uploads_enabled() or not _preview_matches_selection():
		_show_card(PlayerCopy.REACTION_PHOTO_FLOW_1DB47511F697)
		return
	var generation := _generation
	var pixels := _local_preview.duplicate()
	if _session.has_method("safety_client"):
		_checking_rules = true
		_show_loading(PlayerCopy.PHOTO_RULES_TITLE, PlayerCopy.PHOTO_STAYS_LINE, pixels)
		var safety: RefCounted = _session.safety_client()
		var checked: bool = await safety.check_terms()
		_checking_rules = false
		if not _current(generation): return
		if not checked or not safety.terms_accepted:
			_terms_screen = SafetyScreen.new(safety, {}, func():
				_terms_screen = null
				if _current(generation): _show_card()
			, Callable(), true)
			add_child(_terms_screen)
			return
		if not _preview_matches_selection(): _show_card(PlayerCopy.REACTION_PHOTO_FLOW_6A7F3CBB1BFE); return
	_show_loading(PlayerCopy.PHOTO_SENDING_TITLE, PlayerCopy.PHOTO_TURN_KEPT_LINE, pixels)
	var shared: bool = await controller.upload_selected()
	if not _current(generation):
		return
	if shared:
		_local_preview = PackedByteArray()
		_preview_selection = {}
		_recovered = false
		_missing = false
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
	_show_loading(PlayerCopy.PHOTO_CHECKING_TITLE, PlayerCopy.PHOTO_TURN_KEPT_LINE, _local_preview)
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
	var card := _card(PlayerCopy.PHOTO_REMOVE_TITLE, PlayerCopy.PHOTO_REMOVE_LINE)
	card.show_photo(controller.image_bytes())
	card.add_primary(PlayerCopy.PHOTO_REMOVE, _delete, "", "PhotoRemoveConfirm")
	card.add_secondary(PlayerCopy.PHOTO_KEEP, _show_card, "PhotoKeep")

func _delete() -> void:
	if not active or controller.busy():
		return
	var generation := _generation
	_show_loading(PlayerCopy.PHOTO_REMOVING_TITLE, PlayerCopy.PHOTO_REMOVE_LINE)
	var removed: bool = await controller.delete_photo()
	if _current(generation):
		_show_card(PlayerCopy.PHOTO_REMOVED if removed else controller.last_error)

func _continue() -> void:
	if not active:
		return
	var continuation := _continuation
	# A kept photo stays with this turn on this phone. Continuing must not silently
	# erase that durable selection; it can be sent later from the same turn.
	# Uncertain requests stay intact too. Invalidation cancels only live callbacks.
	invalidate()
	if continuation.is_valid():
		continuation.call()

func invalidate() -> void:
	_generation += 1
	_checking_rules = false
	if is_instance_valid(_terms_screen):
		_terms_screen.client.invalidate()
		_terms_screen.queue_free()
	_terms_screen = null
	active = false
	_capture_request = ""
	_capture_context = {}
	# The resume entry outlives this: invalidation also runs when the game shuts down under
	# the camera, and the entry is what brings that photo back.
	_capture_target = {}
	_local_preview = PackedByteArray()
	_preview_selection = {}
	_requested = {}
	_resume = {}
	_recovered = false
	_missing = false
	_fresh_photo = false
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
