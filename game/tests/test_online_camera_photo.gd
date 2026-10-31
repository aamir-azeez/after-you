extends SceneTree
## The optional camera photo on two phones: the photographer saves a turn, opens
## the camera (After You goes to the background) and comes back with a photo,
## as the host and as the guest, while the friend checks the room or plays their
## own turn. Both phones stay in the room, the photo the camera took reaches the
## server for the saved turn, and the next turn carries on.
## - In memory: Android keeps After You while the camera is open.
## - Restarted: Android ends After You under the camera (low memory, Don't keep
##   activities, a lost GL context) and the app starts again from nothing; it goes
##   straight back to the room.
## - Restarted later, or with the room out of reach: Home asks, and Open room
##   brings the same photo back.
## - Restarted, and the player taps on before the room opens by itself: the tap
##   wins, and the room opened from the hub still offers the same photo.
## - Restarted, and a card the app shows by itself (a Pollen gift, a board
##   placing) comes up on Home as the room opens: once it is closed, the room opens.
const Harness = preload("res://tests/online_harness/harness.gd")
const UserFiles = preload("res://tests/online_harness/user_files.gd")
const Resume = preload("res://services/photo_capture_resume.gd")
const MEMORY := "kept in memory"
const RESTARTED := "restarted under the camera"
const LATER := "restarted, opened again later"
const OFFLINE := "restarted, room out of reach"
const TAPPED := "restarted, player taps on as the room opens"
const CARD := "restarted, a Home card shows as the room opens"
const InGameModal = preload("res://presentation/in_game_modal.gd")
var h: Node
var files: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	files = UserFiles.new()
	h = Harness.new()
	h.trace = true
	root.add_child(h)
	for how: String in [MEMORY, RESTARTED]:
		for photographer: String in ["host", "guest"]:
			await _camera_round_trip(photographer, how)
	for how: String in [LATER, OFFLINE, TAPPED, CARD]:
		await _camera_round_trip("host", how)
	h.print_slowest()
	h.end()
	await process_frame
	files.cleanup()
	print("Online camera photo: %d checks, %d failures" % [h.checks, h.failures])
	quit(1 if h.failures else 0)

func _camera_round_trip(who: String, how: String) -> void:
	await h.begin("%s photo, %s" % [who, how])
	h.server.photos_enabled = true
	for device: Node in h.devices: device.add_camera()
	var room: String = await h.hosted_and_joined()
	var photographer: Node = h.host if who == "host" else h.guest
	var friend: Node = h.guest if who == "host" else h.host
	if h.server.active_player(room) != photographer.player_id:
		await h.step(friend.label + " takes a turn", func(): await h.take_turn(friend))
		await h.step(photographer.label + " notices", func(): h.nudge(photographer))
	await h.step(photographer.label + " plays", func(): await h.play_turn(photographer))
	await h.step(photographer.label + " saves the turn", func(): h.save_turn(photographer))
	var turn: Dictionary = h.server.rooms[room].turns.back()
	h.check(turn.player_id == photographer.player_id, "the photographer's turn is saved on the server")
	h.check(photographer.button("PhotoTake") != null, "the photo card offers Take photo after the saved turn (at %s)" % photographer.where())
	await h.step(photographer.label + " taps Take photo", func(): h.press(photographer, "PhotoTake"))
	var native: RefCounted = photographer.photo_native
	h.check(not native.camera_request.is_empty(), "the camera opened for the saved turn")
	await h.step("the camera takes over the screen", func(): photographer.background())
	await h.step(friend.label + " checks the room meanwhile", func(): h.nudge(friend))
	if h.server.active_player(room) == friend.player_id:
		await h.step(friend.label + " plays their turn meanwhile", func(): await h.take_turn(friend))
	if how == MEMORY:
		native.return_with_photo()
		await h.step(photographer.label + " comes back from the camera", func():
			photographer.foreground()
			await _until(func() -> bool: return photographer.button("PhotoSend") != null))
	else:
		native.game_lost_under_camera()
		if how == LATER: _age_resume_entries(photographer.player_id)
		var restart := func():
			await h.reopen(photographer)
			# The room is out of reach for a moment: every capability read fails.
			if how == OFFLINE: photographer.api.faults.append({"path": "/v2/capabilities", "kind": "status", "status": 503, "count": 20})
			if how == TAPPED:
				# The player taps Play with your friend while the room is still opening by itself.
				await _until(func() -> bool: return photographer.app._photo_resume_checked and photographer.child() == null and photographer.app.relay_session != null and photographer.app.relay_session.busy())
				h.open_hub(photographer)
				return
			if how == CARD:
				await _until(func() -> bool: return photographer.app._photo_resume_checked and photographer.child() == null and photographer.app.relay_session != null and photographer.app.relay_session.busy())
				var card: Control = InGameModal.open(photographer.app.ui, "HarnessHomeCard", "A card the app shows by itself")
				await _until(func() -> bool: return not photographer.app.relay_session.busy(), 5000)
				await h.frames(10)
				h.check(photographer.child() == null and photographer.app.find_child("PhotoResumeModal", true, false) == null, photographer.label + " waits under a card Home shows by itself (at %s)" % photographer.where())
				card.close(false)
			await _until(func() -> bool: return photographer.button("PhotoSend") != null or photographer.button("PhotoResumeOpen") != null)
		await h.step("Android starts After You again after the camera", restart, [photographer] if how == OFFLINE else [])
		if how == TAPPED:
			# The Play tap waits for the busy session ("Opening…"), then opens the hub.
			h.check(photographer.hub() != null and photographer.child() == null and photographer.app.find_child("PhotoResumeModal", true, false) == null, photographer.label + "'s tap wins over the room opening by itself (at %s)" % photographer.where())
			h.check(photographer.toasts.is_empty(), photographer.label + "'s tap opens the hub without an error (%s)" % [photographer.toasts])
			await h.step(photographer.label + " opens the room from the hub", func():
				h.open_room_card(photographer, room)
				await _until(func() -> bool: return photographer.button("PhotoSend") != null))
		if how in [LATER, OFFLINE]:
			h.check(photographer.app.mode == "home" and photographer.button("PhotoResumeOpen") != null and photographer.child() == null, photographer.label + " is asked on Home before the room opens (at %s)" % photographer.where())
			h.check(photographer.toasts.is_empty(), photographer.label + " sees no error for a room that did not open by itself (%s)" % [photographer.toasts])
			await h.step(photographer.label + " taps Open room", func():
				h.press(photographer, "PhotoResumeOpen")
				await _until(func() -> bool: return photographer.button("PhotoSend") != null))
	var label := " after the camera (%s)" % how
	h.check(h.current_room(photographer) == room, photographer.label + " is in the room" + label + " (at %s)" % photographer.where())
	h.check(photographer.app.find_child("PhotoResumeModal", true, false) == null, photographer.label + " has no Home prompt left" + label)
	h.check(photographer.button("PhotoSend") != null, photographer.label + "'s photo card shows the photo ready to send" + label)
	h.check(h.current_room(friend) == room, friend.label + " stays in the room while " + photographer.label + " is in the camera")
	# A sent photo leaves the phone's cache, so the camera's pictures are noted first.
	var taken: Array = native.cache.values().map(func(kept: Dictionary) -> String: return kept.metadata.sha256)
	await h.step(photographer.label + " sends the photo with the turn", func():
		h.press(photographer, "PhotoSend")
		await _until(func() -> bool: return photographer.button("PhotoDone") != null))
	var sent: Dictionary = h.server.turn_photo(room, turn.turn_id)
	h.check(not sent.is_empty() and sent.owner_player_id == photographer.player_id and sent.recording_hash == turn.recording.recording_hash and sent.sha256 in taken, "the photo the camera took reached the server for the saved turn")
	await h.step(photographer.label + " carries on", func():
		h.press(photographer, "PhotoDone")
		await h.continue_after_turn(photographer))
	h.check(h.current_room(photographer) == room and photographer.child().mode in ["online_waiting", "ready"], photographer.label + " is back on the room panel (at %s)" % photographer.where())
	# Whoever is due next plays: a guest's turn ends the stage, and the friend may have played.
	var next: Node = h.host if h.server.active_player(room) == h.host.player_id else h.guest
	await h.step(next.label + " notices", func(): h.nudge(next))
	var before: int = h.server.rooms[room].turns.size()
	await h.step(next.label + " takes the next turn", func(): await h.take_turn(next))
	h.check(h.server.rooms[room].turns.size() == before + 1, "the next turn carries on in the same room")
	h.check(h.current_room(photographer) == room and h.current_room(friend) == room, "both phones are still in the room")
	await h.finish()

## The camera opened longer ago than a just-closed return.
func _age_resume_entries(owner: String) -> void:
	var store := Resume.new()
	var list: Array[Dictionary] = store.entries(owner)
	for entry: Dictionary in list: entry.started_unix = int(entry.started_unix) - Resume.RETURN_SEC - 60
	h.check(not list.is_empty() and store._write(owner, list), "the waiting turn is kept while the camera is open")

## Lets frames pass until `ready` holds, bounded by the clock.
func _until(ready: Callable, limit_ms: int = 20000) -> void:
	var deadline := Time.get_ticks_msec() + limit_ms
	while Time.get_ticks_msec() < deadline and not ready.call():
		await h.frames(1)
