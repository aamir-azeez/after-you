extends SceneTree
## A photo taken while Android closed After You under the camera comes back for the same saved
## turn after the restart, and is never skipped on the player's behalf.
const Flow = preload("res://presentation/reaction_photo_flow.gd")
const Prompt = preload("res://presentation/photo_resume_prompt.gd")
const Resume = preload("res://services/photo_capture_resume.gd")
const Copy = preload("res://presentation/player_copy.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PhotoDate = preload("res://presentation/photo_date.gd")
## When the camera wrote the photo: 2026-10-15 12:00 UTC.
const TAKEN_AT := 1792065600
const UI = preload("res://tests/test_reaction_photos.gd")
const OWNER := UI.OWNER
const GUEST := UI.GUEST
const ROOM := UI.ROOM
const OTHER_ROOM := "50173cc9d5bee436613f7b"
const DIRECTORY := "user://test-photo-resume-after-restart"
var checks := 0
var failures := 0
var continuations := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _continued() -> void:
	continuations += 1

func _store() -> RefCounted:
	var store: RefCounted = Resume.new(DIRECTORY)
	for owner: String in [OWNER, GUEST]: store.erase_owner(owner)
	return store

func _receipt() -> Dictionary:
	return {"room_id": ROOM, "idempotency_key": UI.KEY, "turn_id": "t0-0-a", "recording_hash": UI.HASH}

func _target(owner: String = OWNER, room: String = ROOM) -> Dictionary:
	return {"room_id": room, "turn_id": "t0-0-a", "recording_hash": UI.HASH, "gameplay_key": UI.KEY, "owner_player_id": owner}

func _photo(capture: Node) -> Dictionary:
	var image := Image.create(24, 32, false, Image.FORMAT_RGB8)
	image.fill(Color(0.3, 0.5, 0.7))
	capture.bytes = image.save_jpg_to_buffer(0.8)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(capture.bytes)
	capture.metadata = {"status": "kept", "photo_id": UI.PHOTO, "mime": "image/jpeg", "width": 24, "height": 32, "byte_count": capture.bytes.size(), "sha256": digest.finish().hex_encode(), "metadata_removed": true, "uploaded": false}
	return capture.metadata.duplicate(true)

func _flow(host: Node, capture: Node, controller: RefCounted, store: RefCounted, prompts: bool) -> Node:
	var flow := Flow.new()
	flow.capture_override = capture
	flow.controller_override = controller
	flow.resume_store = store
	flow.prompts_enabled = func() -> bool: return prompts
	flow.save_prompt_preference = func(_enabled: bool) -> bool: return true
	flow.configure(host, UI.PhotoSession.new())
	host.add_child(flow)
	return flow

func _frames(count: int = 4) -> void:
	for _i: int in count:
		await process_frame

func _run() -> void:
	await _store_rules()
	await _process_death_round_trip()
	await _missing_photo_is_offered_again()
	await _other_owner_and_unmatched_photo()
	await _room_hook()
	_store().erase_owner(OWNER)
	DirAccess.remove_absolute(DIRECTORY)
	print("After You photo resume after restart: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _store_rules() -> void:
	var store := _store()
	_check(store.entries(OWNER).is_empty(), "A fresh phone has no turn waiting for a photo")
	_check(store.begin(OWNER, _target(), "capture-1"), "A turn waiting for a photo is saved before the camera opens")
	_check(not store.begin(OWNER, _target(GUEST), "capture-2"), "An entry can only be saved for its own owner")
	_check(store.begin(OWNER, _target(), "capture-3") and store.entries(OWNER).size() == 1 and store.entries(OWNER)[0].request_id == "capture-3", "Retaking for the same turn replaces its entry")
	var capture := UI.Capture.new()
	var photo := _photo(capture)
	capture.free()
	_check(not store.attach_photo(OWNER, "capture-1", photo) and store.attach_photo(OWNER, "capture-3", photo), "A recovered photo attaches only to the capture that asked for it")
	var bad := photo.duplicate(true)
	bad.uploaded = true
	_check(not store.attach_photo(OWNER, "capture-3", bad), "Recovered metadata is validated before it is saved")
	_check(Canonical.same(store.entry_for_room(OWNER, ROOM).photo, photo) and store.entry_for_room(GUEST, ROOM).is_empty(), "Entries are per owner")
	var file := FileAccess.open(store._path(OWNER), FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	_check(store.entries(OWNER).is_empty(), "A damaged resume file reads as nothing waiting, without an error")
	store.clock = func() -> int: return 2000000000
	_check(store.begin(OWNER, _target(), "capture-4"), "A damaged file is replaced by the next entry")
	store.clock = func() -> int: return 2000000000 + Resume.MAX_AGE_SEC + 1
	_check(store.entries(OWNER).is_empty(), "Old entries expire")
	_check(store.erase_owner(OWNER) and not FileAccess.file_exists(store._path(OWNER)), "Account deletion removes the owner's resume file")

func _process_death_round_trip() -> void:
	var store := _store()
	# Session one: the turn is saved, the player opens the camera, and Android ends the game.
	var host := UI.Host.new()
	root.add_child(host)
	var capture := UI.Capture.new()
	var photo := _photo(capture)
	photo.taken_at = TAKEN_AT # The native side keeps the camera's write time with the photo.
	capture.metadata = photo.duplicate(true)
	var jpeg: PackedByteArray = capture.bytes
	var controller := UI.PhotoController.new()
	controller.bytes = jpeg
	var flow := _flow(host, capture, controller, store, true)
	await flow.offer(_receipt(), _continued, true)
	flow._open_camera()
	var request: String = flow._capture_request
	_check(store.entry_for_room(OWNER, ROOM).get("request_id") == request, "Before the camera opens, the turn it is for is saved")
	host.queue_free() # Process death: no kept, skipped or failed callback ever arrives.
	await _frames()
	_check(store.entry_for_room(OWNER, ROOM).get("request_id") == request, "Losing the game under the camera keeps the entry")
	# Session two: Android recovered the photo natively; Home reads it once.
	var native := UI.Capture.new()
	native.recovered = {"recovered": true, "request_id": request, "photo": photo}
	native.bytes = jpeg
	native.metadata = photo.duplicate(true)
	var prompt := Prompt.new()
	prompt.capture_override = native
	prompt.resume_store = store
	root.add_child(prompt)
	prompt.add_child(native)
	var waiting: Dictionary = await prompt.check(OWNER)
	_check(waiting.get("room_id") == ROOM and Canonical.same(waiting.photo, photo), "On the next start the recovered photo is attached to its saved turn")
	_check(native.forgets == [UI.PHOTO] and native.recovered.recovered == false, "Only after the entry holds it does the native side forget the recovered photo")
	var parent := Control.new()
	parent.size = Vector2(1280, 720)
	root.add_child(parent)
	var opened: Array = []
	prompt.open_requested.connect(func(room: String): opened.append(room))
	prompt.show_prompt(parent, waiting)
	var modal: Control = parent.get_node("PhotoResumeModal")
	_check(modal != null and modal.find_children("*", "Label", true, false).any(func(label: Label) -> bool: return label.text == Copy.PHOTO_RESUME_BODY), "Home says the photo is waiting and offers to open the room")
	(modal.find_child("PhotoResumeOpen", true, false) as Button).pressed.emit()
	_check(opened == [ROOM], "Open room asks Main to open that exact room")
	prompt.show_prompt(parent, waiting)
	parent.hide()
	await _frames()
	_check(not is_instance_valid(prompt.modal), "Leaving Home another way closes the prompt; the room offers the photo itself")
	parent.show()
	# Back in the room, with prompts switched off: the photo is offered for the same turn.
	var room_host := UI.Host.new()
	root.add_child(room_host)
	var room_controller := UI.PhotoController.new()
	native.get_parent().remove_child(native)
	var room_flow := _flow(room_host, native, room_controller, store, false)
	var before := continuations
	var resumed: bool = await room_flow.resume_for_room(ROOM, _continued)
	await _frames()
	_check(resumed and room_flow.active and continuations == before, "The recovered photo is offered again, even with prompts off, and never auto-skipped")
	_check(room_controller.chooses == 1 and room_controller.skips == 0 and room_controller.selection().photo_id == UI.PHOTO, "The same photo is chosen for the same saved turn, with no skip")
	_check(room_host.title() == Copy.PHOTO_RECOVERED_TITLE and room_host.photo_shown() and not room_host.button_named("PhotoSend").disabled, "The polaroid shows the recovered photo with Send with turn ready")
	var date: Label = room_host.card.find_child("PolaroidDate", true, false)
	_check(int(room_controller.selection().get("taken_at", 0)) == TAKEN_AT and date != null and date.text == PhotoDate.local(TAKEN_AT), "A photo recovered after a restart keeps its original capture date")
	_check(store.entries(OWNER).is_empty() and room_controller.uploads == 0, "The turn's journal now holds the photo; nothing was sent yet")
	await room_flow._share()
	_check(room_controller.uploads == 1 and room_host.title() == Copy.PHOTO_SENT_TITLE, "Send with turn attaches the photo to the already saved turn")
	room_flow._continue()
	for node: Node in [room_host, parent, prompt]: node.queue_free()
	await _frames()

func _missing_photo_is_offered_again() -> void:
	var store := _store()
	_check(store.begin(OWNER, _target(), "capture-9"), "A capture whose photo never came back is still recorded")
	var host := UI.Host.new()
	root.add_child(host)
	var native := UI.Capture.new()
	var controller := UI.PhotoController.new()
	var flow := _flow(host, native, controller, store, false)
	var before := continuations
	var resumed: bool = await flow.resume_for_room(ROOM, _continued)
	await _frames()
	_check(resumed and flow.active and continuations == before, "A lost photo is not dropped silently: its card opens again")
	_check(host.title() == Copy.PHOTO_MISSING_TITLE and host.has_button(Copy.PHOTO_TAKE) and host.has_button(Copy.PHOTO_SKIP), "The card says the photo didn't come back and offers Take photo")
	_check(store.entries(OWNER).is_empty() and controller.chooses == 0, "The missing-photo offer is shown once")
	flow._continue()
	host.queue_free()
	await _frames()

func _other_owner_and_unmatched_photo() -> void:
	var store := _store()
	_check(store.begin(GUEST, _target(GUEST), "capture-guest"), "Another account on this phone has a waiting turn")
	var host := UI.Host.new()
	root.add_child(host)
	var native := UI.Capture.new()
	var photo := _photo(native)
	native.recovered = {"recovered": true, "request_id": "capture-nobody", "photo": photo}
	var controller := UI.PhotoController.new()
	var flow := _flow(host, native, controller, store, true)
	var resumed: bool = await flow.resume_for_room(ROOM, _continued)
	_check(not resumed and not flow.active and controller.chooses == 0, "Another owner's waiting turn is never opened for this player")
	_check(native.forgets == [UI.PHOTO] and store.entries(GUEST).size() == 1 and store.entries(OWNER).is_empty(), "A recovered photo no entry asked for is released without touching any entry")
	_check(store.begin(OWNER, _target(OWNER, OTHER_ROOM), "capture-elsewhere"), "A turn in another room waits too")
	var elsewhere: bool = await flow.resume_for_room(ROOM, _continued)
	_check(not elsewhere and store.entries(OWNER).size() == 1, "Opening one room never opens another room's photo")
	host.queue_free()
	store.erase_owner(GUEST)
	await _frames()

func _room_hook() -> void:
	var preview := UI.TestPreview.new()
	preview.set_process(false)
	preview.set_physics_process(false)
	var offer := UI.Offer.new()
	var coordinator := UI.PairCoordinator.new()
	coordinator.room = {"room_id": ROOM}
	preview.online_session = UI.PhotoSession.new()
	preview.journey = coordinator
	preview.reaction_photos = offer
	preview.add_child(offer)
	root.add_child(preview)
	preview.mode = "online_waiting"
	preview._resume_photo()
	_check(offer.resumes == [ROOM], "Opening a room looks for a photo still waiting for one of its turns")
	preview.mode = "play"
	preview._resume_photo()
	_check(offer.resumes == [ROOM], "A room in play is never interrupted by the photo card")
	preview.queue_free()
	await _frames()
