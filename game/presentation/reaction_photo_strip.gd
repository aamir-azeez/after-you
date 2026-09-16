extends Control
## Optional replay memories follow verified physical player slots. One read batch
## owns transport; navigation coalesces to the newest request until it drains.
signal edit_requested(reference: Dictionary)
signal report_requested(reference: Dictionary)
const WAIT_LIMIT_MS := 25000
const BUBBLE_SIZE := Vector2(72, 96)
var controller_override: RefCounted
var clock_ms: Callable = Time.get_ticks_msec
var _session: RefCounted
var _controller: RefCounted
var _generation := 0
var _identity: Dictionary = {}
var _queued: Dictionary = {}
var _draining := false
var _bubbles: Array[Control] = []
var _hidden_badges: Array[Dictionary] = []

func configure(session: RefCounted) -> void:
	_session = session

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controller = _session.create_photo_controller(Callable()) if controller_override == null else controller_override
	hide()

func show_turns(references: Array) -> void:
	clear()
	_identity = _session.photo_identity()
	if not _identity.get("ready", false) or references.is_empty() or references.size() > 2:
		return
	var slots: Array = []
	for reference: Variant in references:
		if not reference is Dictionary or reference.get("player_slot") not in ["p0", "p1"] or reference.player_slot in slots:
			return
		slots.append(reference.player_slot)
	_queued = {"generation": _generation, "identity": _identity.duplicate(true), "references": references.duplicate(true), "deadline": int(clock_ms.call()) + WAIT_LIMIT_MS}
	if not _draining:
		await _drain()

func _current(request: Dictionary) -> bool:
	return is_inside_tree() and request.generation == _generation and int(clock_ms.call()) <= request.deadline and _session.photo_identity() == request.identity

func _drain() -> void:
	_draining = true
	while not _queued.is_empty() and is_inside_tree():
		var request: Dictionary = _queued
		_queued = {}
		for reference: Dictionary in request.references:
			if not _allowed(reference): continue
			var value: Dictionary = {}
			while _current(request):
				# Timed waiting is bounded by this context, and does not issue any
				# request while the session owns another operation.
				if _session.busy():
					await get_tree().create_timer(0.5).timeout
					continue
				value = await _controller.read_shared(reference.room_id, reference.turn_id, reference.recording_hash)
				if not _current(request):
					break
				if value.is_empty() and _controller.get("last_code") == "request_busy":
					await get_tree().create_timer(0.5).timeout
					continue
				break
			if not _current(request):
				break
			if _allowed(reference): _add_bubble(reference, value)
		if _current(request):
			# Editing uses the same API owner. Enable it only after both reads.
			for bubble: Control in _bubbles:
				var button := bubble.get_node_or_null("EditPhoto") as Button
				if button != null:
					button.disabled = false
		elif request.generation == _generation:
			clear() # Expired/changed-identity partial batches cannot remain visible.
	_draining = false

func _add_bubble(reference: Dictionary, value: Dictionary) -> void:
	var bytes: PackedByteArray = value.get("bytes", PackedByteArray())
	if bytes.is_empty() or bytes.size() > 160 * 1024:
		return # No image means no floating placeholder, including for the owner.
	var image := Image.new()
	if image.load_jpg_from_buffer(bytes) != OK or image.get_width() > 960 or image.get_height() > 960:
		return
	var scale := minf(66.0 / image.get_width(), 90.0 / image.get_height())
	image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	var editable: bool = reference.get("own", false) and _session.local_photo_key(reference.room_id, reference.turn_id, reference.recording_hash) != ""
	var bubble := Panel.new()
	bubble.name = "Memory_" + str(reference.player_slot)
	bubble.set_meta("player_slot", reference.player_slot)
	bubble.set_meta("reference", reference.duplicate(true))
	var photo: Dictionary = value.get("photo", {})
	if not reference.get("own", false) and photo.get("sha256") is String and photo.get("photo_revision", 0) > 0:
		bubble.set_meta("report_photo", {"turn_id": reference.turn_id, "photo_revision": photo.photo_revision, "sha256": photo.sha256})
	bubble.size = BUBBLE_SIZE
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("203f3b")
	frame.border_color = Color("a6d9c4") if reference.get("own", false) else Color("f1c48a")
	frame.set_border_width_all(3)
	frame.set_corner_radius_all(12)
	frame.shadow_color = Color(0, 0, 0, 0.2)
	frame.shadow_size = 3
	bubble.add_theme_stylebox_override("panel", frame)
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(30, 94), Vector2(42, 94), Vector2(36, 103)])
	tail.color = frame.border_color
	bubble.add_child(tail)
	var view := TextureRect.new()
	view.texture = ImageTexture.create_from_image(image)
	view.position = Vector2(4, 4)
	view.size = BUBBLE_SIZE - Vector2(8, 8)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(view)
	if editable:
		var button := Button.new()
		button.name = "EditPhoto"
		button.flat = true
		button.disabled = true
		button.tooltip_text = "Your photo — tap to edit"
		button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.pressed.connect(func(): edit_requested.emit(reference.duplicate(true)))
		bubble.add_child(button)
	elif bubble.has_meta("report_photo"):
		var report := Button.new()
		report.name = "ReportPhoto"
		report.flat = true
		report.tooltip_text = "Report photo or block player"
		report.mouse_filter = Control.MOUSE_FILTER_PASS
		report.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var target := reference.duplicate(true)
		target["photo"] = bubble.get_meta("report_photo").duplicate(true)
		report.pressed.connect(func(): report_requested.emit(target.duplicate(true)))
		bubble.add_child(report)
	add_child(bubble)
	_bubbles.append(bubble)
	bubble.hide() # Only a valid projected position makes it visible.
	show()

func position_over_spirits(camera: Camera3D, actors: Dictionary, safe_rect: Rect2, exclusions: Array[Rect2] = []) -> void:
	if not is_visible_in_tree():
		_restore_role_badges()
		return
	var placed: Array[Rect2] = []
	var covered_badges: Array[Label3D] = []
	for bubble: Control in _bubbles:
		bubble.hide()
		var actor: Node3D = actors.get(bubble.get_meta("player_slot"))
		if not is_instance_valid(camera) or not is_instance_valid(actor) or not actor.is_inside_tree():
			continue
		var anchor_height: float = actor.photo_anchor_height() if actor.has_method("photo_anchor_height") else 1.5
		var above := actor.global_position + Vector3(0, anchor_height, 0)
		if camera.is_position_behind(above):
			continue
		var anchor := get_global_transform_with_canvas().affine_inverse() * camera.unproject_position(above)
		var bounds := Rect2(anchor - Vector2(BUBBLE_SIZE.x * 0.5, BUBBLE_SIZE.y + 12), BUBBLE_SIZE + Vector2(0, 8))
		if not safe_rect.encloses(bounds):
			continue
		var blocked := false
		for obstruction: Rect2 in exclusions + placed:
			if bounds.intersects(obstruction):
				blocked = true
				break
		if blocked:
			continue
		bubble.position = bounds.position
		bubble.show()
		placed.append(bounds)
		# Only the intended role label is replaced by a visible memory. Other
		# character labels and actors without photos retain their own visibility.
		for child: Node in actor.get_children():
			if child is Label3D and child.get_meta("replay_role_badge", false) == true:
				covered_badges.append(child)
	_update_role_badges(covered_badges)

func _update_role_badges(covered: Array[Label3D]) -> void:
	var retained: Array[Dictionary] = []
	for saved: Dictionary in _hidden_badges:
		var badge: Label3D = saved.reference.get_ref()
		if not is_instance_valid(badge):
			continue
		if badge in covered:
			retained.append(saved)
			covered.erase(badge)
		else:
			badge.visible = saved.visible
	for badge: Label3D in covered:
		retained.append({"reference": weakref(badge), "visible": badge.visible})
		badge.hide()
	_hidden_badges = retained

func _restore_role_badges() -> void:
	var none: Array[Label3D] = []
	_update_role_badges(none)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_restore_role_badges()

func clear() -> void:
	_restore_role_badges()
	_generation += 1
	_identity = {}
	_queued = {}
	if _controller != null:
		_controller.invalidate_identity()
	_bubbles.clear()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	hide()

func _exit_tree() -> void:
	clear()

func _allowed(reference: Dictionary) -> bool:
	return not _session.has_method("partner_photos_allowed") or _session.partner_photos_allowed(reference)

func report_targets() -> Array:
	var result: Array = []
	for bubble: Control in _bubbles:
		if bubble.has_meta("report_photo"): result.append(bubble.get_meta("report_photo").duplicate(true))
	return result
