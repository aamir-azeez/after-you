extends SceneTree
const Flow = preload("res://presentation/reaction_photo_flow.gd")
const Strip = preload("res://presentation/reaction_photo_strip.gd")
const Preview = preload("res://relay_preview.gd")
const Session = preload("res://services/relay_online_session.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "40173cc9d5bee436613f7a"
const KEY := "accepted-gameplay-key"
const HASH := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const PHOTO := "11111111111111111111111111111111"

class Host:
	extends Control
	var mode := ""
	var card: VBoxContainer
	func _card(title: String, body: String) -> VBoxContainer:
		if is_instance_valid(card):
			remove_child(card)
			card.queue_free()
		card = VBoxContainer.new()
		add_child(card)
		card.add_child(_label(title))
		card.add_child(_label(body))
		return card
	func _button(text: String, action: Callable) -> Button:
		var button := Button.new()
		button.text = text
		button.pressed.connect(action)
		return button
	func _label(text: String, _size: int = 20) -> Label:
		var label := Label.new()
		label.text = text
		return label
	func has_button(text: String) -> bool:
		return is_instance_valid(card) and card.get_children().any(func(child: Node) -> bool: return child is Button and child.text == text)
	func button_named(text: String) -> Button:
		for child: Node in card.get_children():
			if child is Button and child.text == text:
				return child
		return null

class Capture:
	extends Node
	signal kept(id: String, metadata: Dictionary)
	signal skipped(id: String)
	signal bytes_ready(id: String, metadata: Dictionary, bytes: PackedByteArray)
	signal completed(id: String, operation: String, result: Dictionary)
	signal failed(id: String, operation: String, code: String)
	signal release_read
	var count := 0
	var sequence := 0
	var invalidations := 0
	var available := true
	var bytes := PackedByteArray()
	var metadata: Dictionary = {}
	var hold_read := false
	var reads := 0
	func is_available() -> bool:
		return available
	func capture() -> String:
		count += 1
		sequence += 1
		return "capture-%d" % sequence
	func read_photo(_id: String) -> String:
		sequence += 1
		var key := "read-%d" % sequence
		_emit_read.call_deferred(key)
		return key
	func _emit_read(key: String) -> void:
		reads += 1
		if hold_read:
			hold_read = false
			await release_read
		bytes_ready.emit(key, metadata.duplicate(true), bytes.duplicate())
	func discard_photo(_id: String) -> String:
		sequence += 1
		var key := "discard-%d" % sequence
		_emit_discard.call_deferred(key)
		return key
	func _emit_discard(key: String) -> void:
		completed.emit(key, "discard", {"discarded": true})
	func invalidate() -> void:
		invalidations += 1

class PhotoController:
	extends RefCounted
	signal release
	var last_error := ""
	var last_code := ""
	var read_targets: Array[String] = []
	var read_active := false
	var read_collisions := 0
	var uploads := 0
	var deletes := 0
	var cleanups := 0
	var skips := 0
	var chooses := 0
	var checks := 0
	var hold_open := false
	var hold_read := false
	var fail_upload := false
	var fail_open := false
	var generation := 0
	var selection_value: Dictionary = {}
	var pending_value: Dictionary = {}
	var metadata: Dictionary = {}
	var bytes := PackedByteArray()
	var bound := false
	func last_open_diagnostic() -> Dictionary:
		return {"phase": "receipt", "http_status": 0, "code": "photo_unavailable"}
	func open_owned_turn(_room: String, _key: String) -> bool:
		if hold_open:
			hold_open = false
			await release
		bound = not fail_open
		last_error = "Photo service unavailable." if fail_open else ""
		return not fail_open
	func target() -> Dictionary:
		return {"room_id": ROOM, "turn_id": "t0-0-a", "recording_hash": HASH} if bound else {}
	func selection_context() -> Dictionary:
		return {"generation": generation}
	func choose_local(value: Dictionary, context: Dictionary) -> bool:
		if context != selection_context() or not bound:
			return false
		chooses += 1
		selection_value = value.duplicate(true)
		return true
	func selection() -> Dictionary:
		return selection_value.duplicate(true)
	func pending() -> Dictionary:
		return pending_value.duplicate(true)
	func photo_metadata() -> Dictionary:
		return metadata.duplicate(true)
	func image_bytes() -> PackedByteArray:
		return bytes.duplicate() if not metadata.is_empty() else PackedByteArray()
	func cleanup_count() -> int:
		return 0
	func busy() -> bool:
		return false
	func refresh_photo() -> bool:
		return true
	func skip_local() -> bool:
		skips += 1
		selection_value = {}
		return true
	func upload_selected() -> bool:
		uploads += 1
		if fail_upload:
			pending_value = {"operation": "photo_upload", "held": false}
			last_error = "Photo reply interrupted."
			return false
		selection_value = {}
		metadata = {"sha256": HASH}
		return true
	func reconcile() -> bool:
		checks += 1
		pending_value = {}
		selection_value = {}
		metadata = {"sha256": HASH}
		return true
	func delete_photo() -> bool:
		deletes += 1
		metadata = {}
		return true
	func abandon_rejected_request() -> bool:
		pending_value = {}
		return true
	func cleanup_local() -> bool:
		cleanups += 1
		return true
	func invalidate_identity() -> void:
		generation += 1
		bound = false
	func read_shared(_room: String, _turn: String, _hash: String) -> Dictionary:
		if read_active:
			read_collisions += 1
			last_code = "request_busy"
			return {}
		read_active = true
		read_targets.append(_turn)
		if hold_read:
			hold_read = false
			await release
		read_active = false
		last_code = ""
		return {"photo": {"sha256": HASH}, "bytes": bytes.duplicate()}

class PhotoSession:
	extends RefCounted
	var last_error := ""
	var key := KEY
	var epoch := 1
	var created := 0
	var capabilities: Dictionary = {"photo_uploads_enabled": true}
	func create_photo_controller(_io: Callable) -> RefCounted:
		created += 1
		return PhotoController.new()
	func local_photo_key(_room: String, _turn: String, _hash: String) -> String:
		return key
	func remember_photo_receipt(_receipt: Dictionary) -> bool:
		return true
	func photo_identity() -> Dictionary:
		return {"ready": true, "player_id": OWNER, "epoch": epoch}
	func busy() -> bool:
		return false
	func mutations_enabled() -> bool:
		return true
	func photo_request_busy() -> bool:
		return busy()

class GameCoordinator:
	extends RefCounted
	var accepted := true
	var commits := 0
	func pending() -> Dictionary:
		return {}
	func commit(_review: Dictionary) -> bool:
		commits += 1
		return accepted
	func last_receipt() -> Dictionary:
		return {"operation": "turns", "room_id": ROOM, "turn_id": "t0-0-a", "recording_hash": HASH, "idempotency_key": KEY}

class Offer:
	extends Node
	var active := false
	var offers := 0
	var continuation: Callable
	func offer(_receipt: Dictionary, callback: Callable, _automatic: bool = false) -> void:
		offers += 1
		active = true
		continuation = callback
	func open_owned(reference: Dictionary, callback: Callable) -> void:
		offer(reference, callback)
	func invalidate() -> void:
		active = false

class TestPreview:
	extends "res://relay_preview.gd"
	var continued := 0
	var waiting := 0
	var photo_clears := 0
	var photo_loads := 0
	func _ready() -> void:
		pass
	func _card(_title: String, _body: String) -> VBoxContainer:
		var card := VBoxContainer.new()
		add_child(card)
		return card
	func _button(text: String, callback: Callable, _primary: bool = true) -> Button:
		var button := Button.new()
		button.text = text
		button.pressed.connect(callback)
		return button
	func _after_accept() -> void:
		continued += 1
	func _show_online_waiting() -> void:
		waiting += 1
	func _clear_reaction_view() -> void:
		photo_clears += 1
	func _load_replay_photos() -> void:
		photo_loads += 1

class Memory:
	extends RefCounted
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = value.duplicate(true)
		return {"ok": true}

class Api:
	extends Node
	var busy := false
	var player_id := OWNER
	var device_token := "synthetic-not-a-credential"

class PairCoordinator:
	extends RefCounted
	var room: Dictionary = {}
	var start: Dictionary = {}
	var invalidated := false
	func snapshot() -> Dictionary:
		return room.duplicate(true)
	func checkpoint() -> Dictionary:
		return start.duplicate(true)
	func invalidate_identity() -> void:
		invalidated = true

	func chapter_key() -> String:
		return "relay-isles@2"

var checks := 0
var failures := 0
var continuations := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _prompt()
	await _restored_preview()
	await _strip()
	await _accepted_hook()
	_session_references()
	print("After You reaction photo presentation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _receipt() -> Dictionary:
	return {"room_id": ROOM, "idempotency_key": KEY, "turn_id": "t0-0-a", "recording_hash": HASH}

func _continued() -> void:
	continuations += 1

func _synthetic() -> PackedByteArray:
	var image := Image.create(24, 32, false, Image.FORMAT_RGB8)
	image.fill(Color(0.2, 0.6, 0.4))
	return image.save_jpg_to_buffer(0.7)

func _metadata(bytes: PackedByteArray) -> Dictionary:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return {"status": "kept", "photo_id": PHOTO, "mime": "image/jpeg", "width": 24, "height": 32, "byte_count": bytes.size(), "sha256": digest.finish().hex_encode(), "metadata_removed": true, "uploaded": false}

func _prompt() -> void:
	var host := Host.new()
	root.add_child(host)
	var capture := Capture.new()
	capture.bytes = _synthetic()
	capture.metadata = _metadata(capture.bytes)
	var controller := PhotoController.new()
	controller.bytes = capture.bytes
	var session := PhotoSession.new()
	var flow := Flow.new()
	flow.capture_override = capture
	flow.controller_override = controller
	flow.configure(host, session)
	host.add_child(flow)
	_check(capture.count == 0 and controller.uploads == 0, "constructing photo flow opens no camera or upload")
	await flow.offer(_receipt(), _continued)
	_check(host.mode == "photo" and host.has_button("Optional camera photo"), "confirmed receipt opens optional camera/Skip card")
	_check(controller.skips == 1 and controller.uploads == 0, "optional journal retained without uploading")
	flow._open_camera()
	_check(capture.count == 1 and controller.uploads == 0, "explicit camera button only opens camera")
	var request: String = flow._capture_request
	capture.kept.emit(request, capture.metadata)
	await process_frame
	await process_frame
	_check(controller.chooses == 1 and controller.uploads == 0, "native Use keeps local selection without upload")
	_check(host.has_button("Share photo with this room"), "separate explicit Share action exposed after local Use")
	_check(host.card.get_children().filter(func(child: Node) -> bool: return child is Button)[0].text == "Share photo with this room", "Share is the first action after native capture, above preview and preferences")
	_check(host.has_button("Keep on device & continue") and not host.has_button("Skip for now"), "Kept photo has an unambiguous local-only continuation")
	_check(host.card.find_child("LocalReactionPreview", true, false) != null, "kept local photo shown before explicit Share")
	controller.fail_upload = true
	await flow._share()
	_check(controller.uploads == 1 and host.has_button("Check photo request"), "photo failure exposes exact reconcile action")
	_check(host.has_button("Keep request and continue"), "photo failure still offers game continuation")
	await flow._reconcile()
	_check(controller.checks == 1 and controller.cleanups == 1, "confirmed photo receipt triggers bounded cleanup")
	_check(host.has_button("Done — continue playing") and not host.has_button("Skip for now"), "Confirmed upload shows Done, never Skip")
	_check(host.card.get_child(0).text == "Photo shared with your friend", "Confirmed shared photo has explicit success heading")
	flow._confirm_delete()
	_check(controller.deletes == 0 and host.has_button("Remove photo"), "shared photo removal has explicit confirmation")
	await flow._delete()
	_check(controller.deletes == 1, "explicit removal does not need gameplay commit")
	flow._continue()
	_check(continuations == 1 and not flow.active, "Skip/continue leaves optional flow")
	await flow.offer(_receipt(), _continued)
	flow._open_camera()
	request = flow._capture_request
	flow._continue()
	capture.kept.emit(request, capture.metadata)
	await process_frame
	_check(controller.chooses == 1 and continuations == 2, "late camera callback after navigation cannot attach another photo")
	controller.hold_open = true
	flow.offer(_receipt(), _continued)
	await process_frame
	flow._continue()
	controller.release.emit()
	await process_frame
	_check(not flow.active and continuations == 3, "Skip while receipt request waits ignores late response")
	session.key = ""
	flow.open_owned({"room_id": ROOM, "turn_id": "t0-0-a", "recording_hash": HASH}, _continued)
	_check(not host.has_button("Try photo again") and host.has_button("Skip and continue"), "missing historical key gives honest continue path")
	flow.invalidate()
	_check(not flow.active and flow._local_preview.is_empty(), "identity invalidation removes optional local pixels")
	host.queue_free()
	await process_frame

func _restored_preview() -> void:
	var host := Host.new()
	root.add_child(host)
	var capture := Capture.new()
	capture.bytes = _synthetic()
	capture.metadata = _metadata(capture.bytes)
	var controller := PhotoController.new()
	controller.selection_value = capture.metadata.duplicate(true)
	var session := PhotoSession.new()
	var flow := Flow.new()
	flow.capture_override = capture
	flow.controller_override = controller
	flow.configure(host, session)
	host.add_child(flow)
	await flow.offer(_receipt(), Callable())
	_check(capture.reads == 1 and capture.count == 0 and controller.chooses == 0 and controller.uploads == 0, "restored selection reads exact native cache without recapture or upload")
	_check(host.card.find_child("LocalReactionPreview", true, false) != null and not host.button_named("Share photo with this room").disabled, "restored valid JPEG is visibly previewed before Share becomes available")
	var saved_selection: Dictionary = controller.selection()
	capture.bytes = PackedByteArray([1, 2, 3])
	await flow._refresh_card(flow._generation)
	_check(host.card.find_child("LocalReactionPreview", true, false) == null and host.button_named("Share photo with this room").disabled, "changed or missing cached bytes cannot offer blind Share")
	await flow._share()
	_check(controller.uploads == 0 and controller.selection() == saved_selection and host.has_button("Take another photo") and host.has_button("Keep on device & continue"), "direct Share is guarded while unavailable selection remains recoverable by retake or later sharing")
	capture.bytes = _synthetic()
	capture.metadata.width = 25
	await flow._refresh_card(flow._generation)
	_check(flow._local_preview.is_empty(), "read metadata mismatch cannot reuse a previous preview")
	capture.metadata = _metadata(capture.bytes)
	for capabilities: Dictionary in [{}, {"photo_uploads_enabled": false}]:
		session.capabilities = capabilities
		controller.metadata = {"sha256": HASH}
		await flow._refresh_card(flow._generation)
		_check(not flow._local_preview.is_empty() and host.button_named("Share photo with this room").disabled and host.button_named("Take another photo").disabled, "absent or false capability leaves readable preview but disables new sharing/capture")
		await flow._share()
		flow._open_camera()
		_check(controller.uploads == 0 and capture.count == 0 and host.has_button("Remove shared photo"), "disabled uploads cannot be bypassed; existing photo removal remains available")
		await flow._delete()
	_check(controller.deletes == 2, "deletion works when upload capability is absent or disabled")
	session.capabilities = {"photo_uploads_enabled": true}
	capture.hold_read = true
	flow._refresh_card(flow._generation)
	await process_frame
	flow._continue()
	capture.release_read.emit()
	await process_frame
	await process_frame
	_check(not flow.active and flow._local_preview.is_empty() and controller.uploads == 0, "late restored cache read after Skip cannot resurrect pixels or upload")
	_check(controller.selection() == saved_selection, "Continuing preserves the exact locally kept photo for later sharing")
	await flow.offer(_receipt(), Callable())
	_check(not host.button_named("Share photo with this room").disabled and controller.uploads == 0, "Reopening a kept photo restores Share without silently uploading")
	flow.invalidate()
	host.queue_free()
	await process_frame

func _strip() -> void:
	var session := PhotoSession.new()
	var controller := PhotoController.new()
	controller.bytes = _synthetic()
	var strip := Strip.new()
	strip.controller_override = controller
	strip.configure(session)
	root.add_child(strip)
	var references := [{"room_id": ROOM, "turn_id": "t0-0-a", "recording_hash": HASH, "own": true, "player_slot": "p1"}, {"room_id": ROOM, "turn_id": "t0-0-b", "recording_hash": HASH, "own": false, "player_slot": "p0"}]
	await strip.show_turns(references)
	_check(strip.visible and strip.get_child_count() == 2, "verified replay can show compact own and partner images")
	_check(strip.get_child(0).get_node("EditPhoto") is Button and not strip.get_child(0).get_node("EditPhoto").disabled, "own photo edits enabled after read batch releases transport")
	_check(strip.get_child(1).mouse_filter == Control.MOUSE_FILTER_IGNORE and strip.get_child(1).get_node_or_null("EditPhoto") == null, "partner bubble never intercepts pointer input")
	await _bubble_placement(strip)
	var reads_before := controller.read_targets.size()
	controller.hold_read = true
	strip.show_turns(references)
	await process_frame
	var superseded: Array = references.duplicate(true)
	superseded[0].turn_id = "t0-1-a"
	superseded[1].turn_id = "t0-1-b"
	strip.show_turns(superseded)
	var latest: Array = references.duplicate(true)
	latest[0].turn_id = "t1-1-a"
	latest[1].turn_id = "t1-1-b"
	strip.show_turns(latest)
	_check(controller.read_targets.size() == reads_before + 1 and strip.get_child_count() == 0, "new replay coalesces behind the old transport owner without another read")
	controller.release.emit()
	await process_frame
	_check(controller.read_collisions == 0 and controller.read_targets.slice(reads_before) == ["t0-0-a", "t1-1-a", "t1-1-b"], "old request drains before only the latest exact replay context is read")
	_check(strip.get_child_count() == 2 and strip.get_child(0).get_meta("reference").turn_id == "t1-1-a", "queued current photos appear without requiring another replay or refresh")
	controller.hold_read = true
	strip.show_turns(references)
	await process_frame
	strip.clear()
	controller.release.emit()
	await process_frame
	_check(strip.get_child_count() == 0 and not strip.visible, "late thumbnail after stage navigation cannot reappear")
	controller.hold_read = true
	strip.show_turns(references)
	await process_frame
	session.epoch += 1
	controller.release.emit()
	await process_frame
	_check(strip.get_child_count() == 0, "changed identity epoch suppresses late replay photo")
	var now := [0]
	strip.clock_ms = func() -> int: return now[0]
	controller.hold_read = true
	strip.show_turns(references)
	await process_frame
	strip.show_turns(latest)
	reads_before = controller.read_targets.size()
	now[0] = Strip.WAIT_LIMIT_MS + 1
	controller.release.emit()
	await process_frame
	_check(not strip._draining and strip.get_child_count() == 0 and controller.read_targets.size() == reads_before, "expired queued context is dropped after old owner drains, with no retries")
	controller.bytes = PackedByteArray()
	await strip.show_turns(references)
	_check(strip.get_child_count() == 0, "missing photos show no floating placeholders for either player")
	reads_before = controller.read_targets.size()
	var invalid: Array = references.duplicate(true)
	invalid[0].erase("player_slot")
	await strip.show_turns(invalid)
	invalid[0].player_slot = "p0"
	await strip.show_turns(invalid)
	_check(controller.read_targets.size() == reads_before, "missing or ambiguous player slots cannot fetch or misattribute a bubble")
	strip.queue_free()
	await process_frame

func _bubble_placement(strip: Control) -> void:
	var old_size := root.size
	root.size = Vector2i(1280, 720)
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12
	camera.position = Vector3(0, 0, 10)
	scene.add_child(camera)
	camera.make_current()
	var p0 := Node3D.new()
	var p1 := Node3D.new()
	scene.add_child(p0)
	scene.add_child(p1)
	var own_badge := Label3D.new()
	own_badge.text = "You"
	own_badge.set_meta("replay_role_badge", true)
	p1.add_child(own_badge)
	var hidden_badge := Label3D.new()
	hidden_badge.set_meta("replay_role_badge", true)
	hidden_badge.hide()
	p0.add_child(hidden_badge)
	var unrelated := Label3D.new()
	unrelated.text = "Unrelated hint"
	p1.add_child(unrelated)
	p0.position.x = -2
	p1.position.x = 2
	var actors := {"p0": p0, "p1": p1}
	strip.position = Vector2(80, 20)
	strip.scale = Vector2(1.25, 1.25)
	var safe := Rect2(0, 0, 900, 500)
	await process_frame
	strip.position_over_spirits(camera, actors, safe)
	var own: Control = strip.get_child(0)
	var partner: Control = strip.get_child(1)
	var projected := strip.get_global_transform_with_canvas().affine_inverse() * camera.unproject_position(p1.global_position + Vector3(0, 1.5, 0))
	_check(own.visible and partner.visible and own.position.is_equal_approx(projected - Vector2(36, 108)), "real camera projection follows verified p1 despite reference order and scaled/inset canvas")
	_check(own.position.x > partner.position.x and own.size == Vector2(72, 96), "small photo frames follow distinct physical spirits instead of fixed HUD positions")
	_check(not own_badge.visible and not hidden_badge.visible and unrelated.visible, "visible bubble suppresses only its tagged role badge, preserving unrelated labels")
	strip.position_over_spirits(camera, actors, safe)
	_check(not own_badge.visible, "repeated positioning does not replace original badge visibility with temporary hidden state")
	var edits: Array = []
	strip.edit_requested.connect(func(reference: Dictionary): edits.append(reference))
	own.get_node("EditPhoto").pressed.emit()
	_check(edits.size() == 1 and edits[0].player_slot == "p1" and edits[0].turn_id == "t0-0-a", "own bubble click retains exact accepted turn identity")
	var blocked: Array[Rect2] = [Rect2(own.position, own.size)]
	strip.position_over_spirits(camera, actors, safe, blocked)
	_check(not own.visible and partner.visible, "bubble hides instead of covering an essential HUD control")
	_check(own_badge.visible and not hidden_badge.visible, "HUD exclusion restores exact prior role visibility for only the hidden bubble")
	p1.position.x = 100
	strip.position_over_spirits(camera, actors, safe)
	_check(not own.visible, "off-screen spirit has no edge-clamped misleading photo")
	_check(own_badge.visible, "offscreen photo cannot leave its role badge suppressed")
	p1.position = Vector3(2, 0, 20)
	strip.position_over_spirits(camera, actors, safe)
	_check(not own.visible, "spirit behind camera cannot display photo")
	p1.position = p0.position
	strip.position_over_spirits(camera, actors, safe)
	_check(own.visible and not partner.visible, "overlapping spirit photos do not cover one another")
	_check(not own_badge.visible and not hidden_badge.visible, "hidden-by-default partner badge remains hidden when its bubble is obscured")
	strip.hide()
	_check(own_badge.visible and not hidden_badge.visible and strip._hidden_badges.is_empty(), "hiding replay photo overlay restores exact badge state immediately")
	strip.show()
	strip.position_over_spirits(camera, actors, safe)
	strip.clear()
	_check(own_badge.visible and not hidden_badge.visible and strip._hidden_badges.is_empty(), "clearing or changing replay context restores labels without enabling previously hidden badges")
	scene.queue_free()
	root.size = old_size
	await process_frame

func _accepted_hook() -> void:
	var preview := TestPreview.new()
	preview.set_process(false)
	preview.set_physics_process(false)
	var session := PhotoSession.new()
	var coordinator := GameCoordinator.new()
	var offer := Offer.new()
	preview.online_session = session
	preview.journey = coordinator
	preview.reaction_photos = offer
	preview.add_child(offer)
	root.add_child(preview)
	await preview._accept()
	_check(coordinator.commits == 1 and offer.offers == 1 and preview.continued == 0, "real accept hook offers photo only after confirmed game commit")
	offer.continuation.call()
	_check(preview.continued == 1 and coordinator.commits == 1, "photo continuation cannot recommit gameplay")
	coordinator.accepted = false
	await preview._accept()
	_check(offer.offers == 1 and preview.waiting == 1, "unconfirmed game request never offers photo")
	var card := VBoxContainer.new()
	preview.add_child(card)
	preview._add_recent_photo_action(card)
	_check(card.get_child_count() == 1 and card.get_child(0).text == "Photo for your last contribution", "own photo can be revisited before partner finishes replay pair")
	preview.overlay = Control.new()
	preview.add_child(preview.overlay)
	preview.hud = Control.new()
	preview.add_child(preview.hud)
	preview.mode = "replay"
	preview.running = true
	preview.replay_pair_index = 0
	var prior_clears := preview.photo_clears
	preview._edit_replay_photo({"room_id": ROOM, "turn_id": "t0-0-a", "recording_hash": HASH})
	_check(preview.photo_clears == prior_clears + 1, "opening photo edit immediately clears previous replay pixels")
	offer.continuation.call()
	_check(preview.photo_loads == 1 and preview.running and preview.mode == "replay", "return after remove/replace reloads current thumbnails without resetting replay")
	preview.identity_invalidated()
	_check(not offer.active, "existing main identity hook invalidates child photo flow")
	preview.queue_free()
	await process_frame

func _session_references() -> void:
	var api := Api.new()
	var memory := Memory.new()
	var photo_store := Memory.new()
	var session := Session.new(api, func() -> Dictionary: return {"ready": true, "player_id": OWNER, "epoch": 1}, memory)
	session.photo_store = photo_store
	# Establish the existing lobby identity without any network request.
	_check(session.photo_identity().player_id == OWNER and session._ready(), "session photo identity uses existing owner readiness")
	var coordinator := PairCoordinator.new()
	var a: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/relay-a.json"))
	var b: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/relay-b.json"))
	coordinator.start = {"stage_index": 1, "proof": {"a": a, "b": b, "previous_checkpoint": {"stage_index": 0}}}
	coordinator.room = {"room_id": ROOM, "branch": 4, "host_id": OWNER, "guest_id": GUEST, "completed_pair_ids": ["p1-0"]}
	session.coordinator = coordinator
	var references: Array = session.replay_photo_turns(0, {"a": a, "b": b})
	_check(references.size() == 2 and references[0].turn_id == "t1-0-a", "replay photos bind retained pair branch rather than latest room branch")
	_check(references[0].own and not references[1].own, "photo ownership follows stable player slots")
	_check(references[0].player_slot == a.player_slot and references[1].player_slot == b.player_slot, "bubble slots come from exact verified recordings, never role order")
	var changed: Dictionary = b.duplicate(true)
	changed.recording_hash = HASH
	_check(session.replay_photo_turns(0, {"a": a, "b": changed}).is_empty(), "unverified replacement pair cannot select photos")
	var scope := "turn-photo-v1:" + OWNER + ":" + ROOM + ":t1-0-a"
	photo_store.values[scope] = {"schema_version": 1, "target": {"room_id": ROOM, "owner_player_id": OWNER, "turn_id": "t1-0-a", "recording_hash": a.recording_hash, "gameplay_key": KEY}}
	_check(session.local_photo_key(ROOM, "t1-0-a", a.recording_hash) == KEY, "local journal locates exact accepted receipt for later own edit")
	_check(session.local_photo_key(ROOM, "t1-0-a", HASH) == "", "local receipt lookup rejects another recording hash")
	var controller: RefCounted = session.create_photo_controller(Callable())
	controller._owner = OWNER
	session.invalidate_identity()
	_check(controller._owner == "" and coordinator.invalidated, "session invalidation retires registered photo and gameplay controllers")
	_check(memory.values.is_empty(), "photo lookup does not alter gameplay/lobby storage")
	api.free()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
