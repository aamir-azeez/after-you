extends "res://tests/test_relay_room_coordinator.gd"
## End-of-run reactions: the faces and what the phone keeps of them, the
## picker and bubbles, their sound, the face a room turn carries and what a
## room read brings back, the room list, Replays chips and the chapter screen.

const Store = preload("res://services/end_reaction_store.gd")
const EndReactions = preload("res://presentation/end_reactions.gd")
const EndReactionScreen = preload("res://presentation/end_reaction_screen.gd")
const Look = preload("res://presentation/spirit_look.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Soundscape = preload("res://services/soundscape.gd")
const SoundCues = preload("res://services/sound_cues.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const InboxClient = preload("res://services/room_inbox_client.gd")
const RoomHubScreen = preload("res://presentation/room_hub_screen.gd")
const Replays = preload("res://presentation/replays_flow.gd")
const Preview = preload("res://relay_preview.gd")
const Journey = preload("res://services/relay_journey.gd")
const HASH_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const HASH_B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

var _paths: Array[String] = []

func _run() -> void:
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b", "initial-checkpoint", "relay-checkpoint", "final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	_clear_default_store()
	_catalog()
	_store()
	await _picker()
	await _faces_card()
	await _bubbles_and_freeing()
	_sound()
	_rooms_api()
	await _room_turns()
	_inbox()
	_replays()
	await _screen_glue()
	await _solo_screen()
	_clear_default_store()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("End reactions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _path(label: String) -> String:
	var path := "user://end-reactions-test-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

## The default file the screens and the coordinator use; this suite runs on its own user dir.
func _clear_default_store() -> void:
	for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(Store.FILE_PATH + suffix))
	Store._picks.clear()
	EndReactions._greeted.clear()

func _catalog() -> void:
	_check(Store.FACES.size() == 9 and Store.FACES[-1] == Store.HEART and Store.FACES[0] == "happy", "Eight faces then the heart, Happy first")
	_check(Store.EXPRESSIONS.size() == 8 and not Store.EXPRESSIONS.values().has(Look.NORMAL) and Store.EXPRESSIONS.knocked_out == Look.KNOCKED_OUT, "Every face is a real spirit expression, Knocked out in, Normal out")
	for face: String in Store.FACES:
		_check(not EndReactions.face_name(face).is_empty(), "%s has a name for screen readers" % face)
		if face != Store.HEART: _check(Look.has(Store.expression(face)), "%s draws the spirit's own %s" % [face, Store.expression(face)])
	var names := {}
	for face: String in Store.FACES: names[EndReactions.face_name(face)] = true
	_check(names.size() == Store.FACES.size() and EndReactions.face_name("knocked_out") == "Knocked out", "Names are distinct, and the X X face is Knocked out")
	_check(Store.expression(Store.HEART) == &"" and not Store.is_face("normal") and not Store.is_face(3), "The heart has no expression, and only known ids are faces")

func _store() -> void:
	var path := _path("store")
	var store := Store.new(path)
	_check(store.last_face() == "happy", "With no face used yet, the quick face is Happy")
	store.choose(HASH_A, "squeeze")
	_check(Store.picked(HASH_A) == "squeeze" and store.face(HASH_A) == "squeeze" and store.kept(HASH_A).is_empty(), "A pick is remembered for its run, not yet kept")
	_check(Store.new(path).last_face() == "squeeze", "The last face used survives the app closing")
	store.choose(HASH_A, "sad")
	_check(Store.picked(HASH_A) == "sad", "A pick can be changed until it is sent")
	store.keep(HASH_A, "sad")
	var reloaded := Store.new(path)
	_check(reloaded.kept(HASH_A) == "sad" and Store.picked(HASH_A).is_empty(), "A saved or sent face is kept, and its pick is done")
	reloaded.keep("not-a-hash", "happy")
	reloaded.keep(HASH_B, "normal")
	_check(Store.new(path).kept(HASH_B).is_empty() and Store.new(path).kept("not-a-hash").is_empty(), "Only real recording hashes and known faces are kept")
	store = Store.new(path)
	store.note_room(ROOM, {"schema_version": 1, "faces": {HASH_B: "heart", "c".repeat(64): "wink", "short": "happy"}, "partner": "heart"})
	_check(store.kept(HASH_B) == "heart" and store.kept("c".repeat(64)).is_empty() and store.partner(ROOM) == "heart", "A room read keeps known faces one by one, and the friend's latest")
	store.note_room(ROOM, {"schema_version": 1, "faces": {}})
	_check(store.partner(ROOM).is_empty() and store.kept(HASH_B) == "heart", "A later read without a friend face clears it and keeps the turns' faces")
	store.note_room(ROOM, {"schema_version": 2, "faces": {HASH_B: "angry"}, "partner": "angry"})
	store.note_room(ROOM, "junk")
	_check(store.kept(HASH_B) == "heart" and store.partner(ROOM).is_empty(), "A read of another shape changes nothing")
	var crowded := {}
	for index in range(Store.MAX_LISTED + 1): crowded["%064x" % (index + 1)] = "happy"
	store.note_room(ROOM, {"schema_version": 1, "faces": crowded})
	_check(store.kept("%064x" % 1).is_empty(), "A list longer than a room can hold is refused")
	_check(store.read_wanted(ROOM, "parts-1"), "A room never read is read")
	store.remember({HASH_A: "angry"}, ROOM, "parts-1")
	_check(not Store.new(path).read_wanted(ROOM, "parts-1") and Store.new(path).read_wanted(ROOM, "parts-2") and Store.new(path).kept(HASH_A) == "angry", "A Replays read is kept with what it covered")
	var junk := FileAccess.open(path, FileAccess.WRITE)
	junk.store_string("{not json")
	junk.close()
	_check(Store.new(path).kept(HASH_A).is_empty() and Store.new(path).last_face() == "happy", "A damaged file reads as empty, never as a crash")

func _row(context: Dictionary, parent: Control) -> Control:
	var row := EndReactions.attach(parent, context)
	return row

func _host(size: Vector2) -> Control:
	var host := VBoxContainer.new()
	host.position = Vector2(400, 300)
	host.size = size
	root.add_child(host)
	return host

func _picker() -> void:
	root.size = Vector2i(1280, 720)
	var host := _host(Vector2(566, 0))
	_check(EndReactions.attach(host, {"run": HASH_A}) == null and host.get_child_count() == 0, "Nothing to pick and nothing to show adds nothing")
	var sounds: Array = []
	var picks: Array = []
	var store := Store.new(_path("picker"))
	var row := _row({"run": HASH_A, "pick": true, "color": "mint", "store": store, "settings": {"reduced_motion": true},
		"sound": func(face: String) -> void: sounds.append(face), "on_pick": func(face: String) -> void: picks.append(face)}, host)
	await process_frame
	_check(row != null and is_instance_valid(row.pill) and is_instance_valid(row.quick) and is_instance_valid(row.opener), "The split pill shows its quick face and React")
	_check(row.pill.find_child("PillDivider", true, false) != null, "A divider splits the pill's halves")
	for button: Control in [row.quick, row.opener]:
		_check(button.size.x >= 56.0 and button.size.y >= 56.0, "%s is a 56 px target" % button.name)
	_check(row.opener.text == PlayerCopy.END_REACTIONS_REACT and row.quick.accessibility_name == PlayerCopy.END_REACTIONS_QUICK % "Happy", "React and the quick face say what they do")
	_check(not row.own_bubble.visible, "No bubble before a pick")
	row.quick.pressed.emit()
	_check(row.chosen == "happy" and Store.picked(HASH_A) == "happy" and row.own_bubble.visible and sounds == ["happy"] and picks == ["happy"], "The quick half picks the last face: bubble, sound and the host told")
	row.choose("happy")
	_check(sounds.size() == 1 and picks.size() == 2, "Picking the same face again makes no second sound")
	row._last_sound -= EndReactions.SOUND_GUARD_MS
	row.choose("knocked_out")
	_check(row.chosen == "knocked_out" and sounds == ["happy", "knocked_out"] and row.own_bubble.face == "knocked_out", "A new face replaces the bubble and pops its sound")
	row.choose("sad")
	_check(sounds.size() == 2 and row.chosen == "sad", "Taps within the guard change the face without stacking sounds")
	_check(row.own_bubble.accessibility_name == PlayerCopy.END_REACTIONS_YOU_NAMED % "Sad", "The bubble names the face for screen readers")
	host.queue_free()
	await process_frame
	# A card rebuilt for the same run keeps the pick.
	host = _host(Vector2(566, 0))
	row = _row({"run": HASH_A, "pick": true, "store": store}, host)
	await process_frame
	_check(row.chosen == "sad" and row.own_bubble.visible and row._quick_icon.face == "sad", "A rebuilt card keeps the run's pick")
	host.queue_free()
	await process_frame
	host = _host(Vector2(566, 0))
	row = _row({"run": HASH_A, "pick": true, "locked": "heart", "store": store}, host)
	await process_frame
	_check(row.chosen == "heart" and row.pill == null and row.find_child("OwnReaction", true, false) != null, "A face already sent shows without the pill")
	row.choose("happy")
	_check(row.chosen == "heart", "A sent face cannot change")
	host.queue_free()
	await process_frame
	host = _host(Vector2(566, 0))
	row = _row({"friend": {"face": "angry", "color": "peach", "name": "Sam"}, "settings": {"left_handed": false}}, host)
	await process_frame
	var friend: Control = row.find_child("FriendReaction", true, false)
	_check(friend != null and row.pill == null and _has_label(friend, PlayerCopy.END_REACTIONS_FRIEND % "Sam") and row.friend_bubble.accessibility_name == PlayerCopy.END_REACTIONS_FRIEND_NAMED % ["Sam", "Angry"], "The friend's face shows with who sent it")
	host.queue_free()
	await process_frame
	host = _host(Vector2(566, 0))
	row = _row({"friend": {"face": "angry", "name": "Sam"}, "compact": true}, host)
	await process_frame
	_check(not _has_label(row, PlayerCopy.END_REACTIONS_FRIEND % "Sam") and row.friend_bubble.size.y < EndReactions.BUBBLE_SIZE.y, "A compact friend face is small and has no caption")
	host.queue_free()
	await process_frame
	# The pill sits on the player's hand side.
	for left: bool in [false, true]:
		host = _host(Vector2(566, 0))
		row = _row({"run": HASH_B, "pick": true, "friend": {"face": "happy", "name": "Sam"}, "settings": {"left_handed": left}, "store": store}, host)
		await process_frame
		await process_frame
		var own: Control = row.find_child("OwnReaction", true, false)
		var theirs: Control = row.find_child("FriendReaction", true, false)
		_check((own.position.x < theirs.position.x) == left, "Left-handed puts the pill on the left, right-handed on the right" if left else "Right-handed puts the pill on the right")
		host.queue_free()
		await process_frame

func _has_label(node: Node, text: String) -> bool:
	if node is Label and node.text == text: return true
	for child: Node in node.get_children():
		if _has_label(child, text): return true
	return false

func _faces_card() -> void:
	var store := Store.new(_path("card"))
	for case: Array in [[Vector2i(1280, 720), false], [Vector2i(1560, 720), false], [Vector2i(1600, 720), true]]:
		root.size = case[0]
		var host := _host(Vector2(566, 0))
		host.position = Vector2(float(case[0].x) * 0.5 - 283.0, 520.0)
		var row := _row({"run": HASH_B, "pick": true, "note": PlayerCopy.END_REACTIONS_ROOM_NOTE, "settings": {"left_handed": case[1], "reduced_motion": true}, "store": store}, host)
		await process_frame
		await process_frame
		row.opener.pressed.emit()
		await process_frame
		await process_frame
		var card: CanvasLayer = row.faces_card
		_check(row.faces_open() and card != null, "React opens the faces card at %s" % str(case[0]))
		var grid: GridContainer = card.find_child("ReactionGrid", true, false)
		_check(grid != null and grid.columns == 4 and grid.get_child_count() == 8, "Eight faces in a 4 x 2 grid")
		_check(card.cells.has(Store.HEART) and not grid.get_children().has(card.cells[Store.HEART]) and _labels(card.cells[Store.HEART]).is_empty(), "The heart sits in the header, icon only")
		var names: Array = []
		for cell: Node in grid.get_children(): names.append(_labels(cell))
		_check(names == [["Happy"], ["Squeeze"], ["Surprised"], ["Sad"], ["Annoyed"], ["Angry"], ["Sleepy"], ["Knocked out"]], "Design 4's order, with Knocked out in Normal's place")
		for face: String in card.cells:
			var cell: Control = card.cells[face]
			_check(cell.size.x >= 56.0 and cell.size.y >= 56.0, "%s is a 56 px target" % face)
		var view := Rect2(Vector2.ZERO, Vector2(case[0]))
		var rect: Rect2 = card.panel_rect()
		var pill: Rect2 = row.pill.get_global_rect()
		_check(view.encloses(rect) and not rect.intersects(pill), "The card stays on screen and never covers its pill")
		if case[0].x >= 1560:
			# On a phone's 720 tall UI it opens beside the pill on the hand side, over the world.
			_check(rect.end.x <= pill.position.x if case[1] else rect.position.x >= pill.end.x, "It opens beside the pill on the hand side at %s" % str(case[0]))
			_check(rect.position.y < pill.get_center().y and rect.end.y > pill.get_center().y, "Level with the pill")
		else:
			# A window too narrow beside it: above or below, its edge on the pill's edge on the hand side.
			_check(absf((rect.position.x if case[1] else rect.end.x) - (pill.position.x if case[1] else pill.end.x)) < 1.0, "Its edge lines up with the pill on the hand side")
		_check(_has_label(card, PlayerCopy.END_REACTIONS_ROOM_NOTE) and _has_label(card, PlayerCopy.END_REACTIONS_TITLE), "Its title and note show")
		(card.cells["surprised"] as Button).pressed.emit()
		await process_frame
		_check(row.chosen == "surprised" and not row.faces_open(), "A face picks and closes the card")
		row.opener.pressed.emit()
		await process_frame
		(row.faces_card.shade as ColorRect).gui_input.emit(_click())
		await process_frame
		_check(not row.faces_open() and row.chosen == "surprised", "A tap outside closes it and keeps the pick")
		row.opener.pressed.emit()
		await process_frame
		host.queue_free()
		await process_frame
		await process_frame
		_check(not is_instance_valid(card) or card.is_queued_for_deletion(), "The card goes with the screen that held it")
	root.size = Vector2i(1280, 720)

func _click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click

func _labels(node: Node) -> Array:
	var found: Array = []
	if node is Label: found.append(node.text)
	for child: Node in node.get_children(): found.append_array(_labels(child))
	return found

func _bubbles_and_freeing() -> void:
	var host := _host(Vector2(566, 0))
	var row := _row({"run": HASH_B, "pick": true, "store": Store.new(_path("free")), "settings": {"reduced_motion": false}}, host)
	await process_frame
	row.choose("angry")
	_check(row.own_bubble.scale.x < 1.0, "With motion, the bubble pops in from small")
	host.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(row), "A card closed mid-pop frees its bubble and tween without an error")
	host = _host(Vector2(566, 0))
	row = _row({"run": HASH_B, "pick": true, "store": Store.new(_path("still")), "settings": {"reduced_motion": true}}, host)
	await process_frame
	row.choose("angry")
	_check(row.own_bubble.scale == Vector2.ONE, "Under Reduce motion the bubble just appears")
	host.queue_free()
	var layer := Control.new()
	root.add_child(layer)
	var popped: Control = EndReactions.pop(layer, Vector2(300, 300), "heart", "peach", {"reduced_motion": true}, 0.05)
	_check(popped != null and popped.position == Vector2(300 - EndReactions.BUBBLE_SIZE.x * 0.5, 300 - EndReactions.BUBBLE_SIZE.y), "A free bubble's tail sits on its point")
	_check(EndReactions.pop(layer, Vector2.ZERO, "normal", "peach") == null, "Only faces pop")
	await create_timer(0.6).timeout
	_check(not is_instance_valid(popped), "A free bubble fades and frees itself")
	layer.queue_free()
	await process_frame

func _sound() -> void:
	_check(SoundCues.problems().is_empty(), "The sound tables, the reaction pop included, check out")
	var identity := ["relay-isles@2", "relay", "a", HASH_A, "happy"]
	var pitch := Soundscape.reaction_pitch(identity)
	_check(pitch == Soundscape.reaction_pitch(identity.duplicate()) and pitch >= SoundCues.REACTION.range.x and pitch <= SoundCues.REACTION.range.y, "A reaction's pitch is the same every time and inside its span")
	var pitches := {}
	for face: String in Store.FACES: pitches[Soundscape.reaction_pitch(["relay-isles@2", "relay", "a", HASH_A, face])] = true
	_check(pitches.size() > 4, "Different faces sound different")
	var scape := Soundscape.new()
	root.add_child(scape)
	scape.sound_enabled = true
	scape.begin_turn("relay-isles@2", "relay")
	scape.play_reaction(identity)
	_check(scape._ordinals.is_empty() and scape.last_steps.is_empty(), "A reaction never moves a turn's cue identities")
	scape.queue_free()

func _rooms_api() -> void:
	for case: Array in [[HTTPClient.METHOD_GET, "/v2/capabilities", true], [HTTPClient.METHOD_GET, "/v1/room-inbox", true], [HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM, true],
		[HTTPClient.METHOD_POST, "/v2/rooms/" + ROOM + "/turns", true], [HTTPClient.METHOD_POST, "/v2/rooms/join", false], [HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM + "/collection", false],
		[HTTPClient.METHOD_POST, "/v2/rooms/" + ROOM + "/fork", false], [HTTPClient.METHOD_DELETE, "/v2/rooms/" + ROOM, false], [HTTPClient.METHOD_GET, "/v1/friends", false]]:
		_check(RoomsApi.capability_headers(case[0], case[1]).has(RoomsApi.END_REACTIONS_HEADER) == case[2], "%s asks for reactions: %s" % [case[1], case[2]])
	var api := RoomsApi.new()
	var room := {"room_id": ROOM, "revision": 2, "end_reactions": {"schema_version": 1, "faces": {HASH_A: "happy"}, "partner": "happy"}}
	var result: Dictionary = api._result([HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(room).to_utf8_buffer()], HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM)
	_check(result.ok and not result.data.has("end_reactions") and result.data.room_id == ROOM and result.end_reactions.partner == "happy", "A room's faces leave the reply beside it, and the room is as it was")
	var plain: Dictionary = api._result([HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"room_id": ROOM}).to_utf8_buffer()], HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM)
	_check(not plain.has("end_reactions"), "A reply without faces has none")
	api.free()

func _room_turns() -> void:
	_clear_default_store()
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	boundary.responses.append(func(request: Dictionary) -> Dictionary:
		var reply := _ok(_receipt(request, _snapshot(HOST, 0, true, 2)))
		reply["end_reactions"] = {"schema_version": 1, "faces": {str(fixtures["relay-a"].recording_hash): "squeeze"}}
		return reply)
	_check(await coordinator.commit(fixtures["relay-a"], 0, "squeeze"), "A room turn is sent with its face")
	var sent: Dictionary = boundary.requests.back().body
	_check(sent.get("end_reaction") == "squeeze" and not sent.has("tries") and Canonical.same(sent.recording, fixtures["relay-a"]), "The face travels beside the recording, which is unchanged")
	_check(Store.new().kept(str(fixtures["relay-a"].recording_hash)) == "squeeze", "Once accepted, the turn's face is kept on this phone")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	_check(not await coordinator.commit(fixtures["relay-a"], 2, "heart"), "A lost answer leaves the turn and its face pending")
	_check(coordinator.pending_reaction() == "heart", "The screen can show the waiting face, fixed")
	var pending: Dictionary = coordinator.pending().duplicate(true)
	coordinator = _coordinator(boundary)
	_check(coordinator.bind_room(ROOM) and Canonical.same(coordinator.pending(), pending) and pending.body.end_reaction == "heart" and pending.body.tries == 2, "The pending turn reloads with its face and count, so a resend is byte for byte")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	_check(await coordinator.commit(fixtures["relay-a"], 0, "") and not boundary.requests.back().body.has("end_reaction"), "No face sends the old body")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	await coordinator.commit(fixtures["relay-a"], 0, "angry")
	var scope := "relay-room-v2:" + HOST + ":" + ROOM
	boundary.disk[scope].pending.body.end_reaction = "normal"
	coordinator = _coordinator(boundary)
	_check(not coordinator.bind_room(ROOM) and coordinator.read_only, "A stored face this build does not know is not trusted")
	boundary = Boundary.new()
	boundary.identity.player_id = GUEST
	coordinator = _coordinator(boundary)
	_check(coordinator.bind_room(ROOM), "The guest binds the room")
	var waiting := _snapshot(GUEST, 0, true, 2)
	boundary.responses.append({"ok": true, "status": 200, "data": waiting, "end_reactions": {"schema_version": 1, "faces": {str(fixtures["relay-a"].recording_hash): "happy"}, "partner": "happy"}})
	_check(await coordinator.refresh() and Canonical.same(coordinator.snapshot(), waiting), "A room read with faces beside it keeps exactly the room it checked")
	_check(Store.new().kept(str(fixtures["relay-a"].recording_hash)) == "happy" and Store.new().partner(ROOM) == "happy", "The friend's face is kept for the turn and as their latest")
	boundary.responses.append({"ok": true, "status": 200, "data": _snapshot(GUEST, 0, true, 1), "end_reactions": {"schema_version": 1, "faces": {}, "partner": "sad"}})
	_check(not await coordinator.refresh() and Store.new().partner(ROOM) == "happy", "Faces beside a stale read that is refused are not kept")
	_clear_default_store()

func _inbox() -> void:
	var server := {"room_id": ROOM, "family": "relay", "api_version": 2, "chapter": {"id": "relay-isles", "version": 2},
		"membership": {"host_id": HOST, "guest_id": GUEST, "you_are_host": true}, "status": "your_turn", "revision": 3,
		"remote_activity_sequence": 1, "activity_at": "2026-10-19T00:00:00.000Z"}
	_check(InboxClient.valid_server_room(server), "A room without a friend face is valid as before")
	var with_face := server.duplicate(true)
	with_face.partner_reaction = "happy"
	var left := with_face.duplicate(true)
	left.partner_left = true
	_check(InboxClient.valid_server_room(with_face) and InboxClient.valid_server_room(left), "The friend's face is an optional key, with or without partner_left")
	var bad := with_face.duplicate(true)
	bad.partner_reaction = 3
	var extra := with_face.duplicate(true)
	extra.other = 1
	_check(not InboxClient.valid_server_room(bad) and not InboxClient.valid_server_room(extra), "Anything else in its place, or another new key, is refused")
	var future := with_face.duplicate(true)
	future.partner_reaction = "wink"
	_check(InboxClient.valid_server_room(future), "A face a later build knows is still a valid room")
	var api_node := Node.new()
	var client := InboxClient.new(api_node, func() -> Dictionary: return {})
	var normal: Dictionary = client._normalize_room(with_face)
	_check(normal.partner_reaction == {"face": "happy", "color": "mint"} and InboxClient.valid_room(normal), "Kept for the card with the friend's colour: the host's friend is the mint guest")
	with_face.membership.you_are_host = false
	_check(client._normalize_room(with_face).partner_reaction.color == "peach", "The guest's friend is the peach host")
	_check(not client._normalize_room(future).has("partner_reaction") and InboxClient.valid_room(client._normalize_room(future)), "A face this build does not know is left off the card")
	var hub := RoomHubScreen.new()
	var line: Control = hub._status_line(normal, "your_turn")
	_check(line.name == "StatusLine" and line.find_child("FriendReaction", true, false) != null, "The room card shows the friend's face beside its status")
	var chip_only: Control = hub._status_line(client._normalize_room(server), "your_turn")
	_check(chip_only is PanelContainer, "A room without one shows only its status")
	for node: Node in [line, chip_only, hub, api_node]: node.free()

func _replays() -> void:
	_clear_default_store()
	var store := Store.new()
	store.keep(HASH_A, "squeeze")
	store.keep(HASH_B, "heart")
	var flow := Replays.new()
	flow._faces = Store.new()
	flow._turn_tries = preload("res://services/turn_tries.gd").new(_path("tries"))
	var shared: Control = flow._tries_row(Replays._turn_owners("p0", true, "Sam", HASH_A, HASH_B))
	_check(shared != null and shared.get_child_count() == 2, "A shared part shows each turn's face")
	var first: Control = shared.get_child(0)
	_check(first.name == "ReactionChip" and first.accessibility_name == PlayerCopy.END_REACTIONS_YOU_NAMED % "Squeeze" and shared.get_child(1).accessibility_name == PlayerCopy.END_REACTIONS_FRIEND_NAMED % ["Sam", "Love"], "Each face says who sent it")
	var solo: Control = flow._tries_row(Replays._solo_turns({"chapter_key": "relay-isles@2", "pair": {"a": {"recording_hash": "c".repeat(64), "stage_id": "garden"}, "b": {"recording_hash": HASH_B}}}))
	_check(solo != null and solo.get_child_count() == 1 and solo.get_child(0).accessibility_name == PlayerCopy.END_REACTIONS_YOU_NAMED % "Love", "A solo part shows the player's own face")
	var turns := Replays._solo_turns({"chapter_key": "relay-isles@2", "pair": {"a": {"recording_hash": HASH_A, "stage_id": "garden"}, "b": {"recording_hash": HASH_B}}})
	_check(turns[0][2] == "mint" and turns[1][2] == "peach", "A solo stage the second spirit starts colours its first turn mint")
	_check(flow._tries_row(Replays._solo_turns({"pair": {"a": {"recording_hash": "c".repeat(64)}, "b": {}}})) == null, "A part with no face and no count shows nothing")
	for node: Node in [shared, solo, flow]: node.free()
	_clear_default_store()

## What a chapter screen hands end_reaction_screen.gd (relay_preview.gd _end_reaction_context).
class FakeScape extends Node:
	var played: Array = []
	func play_reaction(identity: Array) -> void: played.append(identity)

class FakeWorld extends Node3D:
	var camera := Camera3D.new()
	var actors := {}
	func _init() -> void:
		add_child(camera)
		camera.position = Vector3(0, 6, 8)
		for slot: String in ["p0", "p1"]:
			var actor := Node3D.new()
			actor.position = Vector3(-1 if slot == "p0" else 1, 0, 0)
			add_child(actor)
			actors[slot] = actor
	func _ready() -> void:
		camera.look_at(Vector3.ZERO)

func _screen_glue() -> void:
	_clear_default_store()
	var scape := FakeScape.new()
	root.add_child(scape)
	var pairs: Array = []
	var ctx := {"online": false, "available": true, "chapter_key": "relay-isles@2", "definition": level, "settings": {"reduced_motion": true},
		"soundscape": scape, "pairs": func() -> Array: return pairs, "friend_name": func() -> String: return "Sam"}
	_check(EndReactionScreen.face_to_send(ctx, {"recording_hash": HASH_A}).is_empty(), "Nothing picked sends nothing")
	ctx.online = true
	ctx.available = false
	var host := _host(Vector2(566, 0))
	_check(EndReactionScreen.attach_ending(ctx, host, fixtures["relay-b"], true) == null, "No picker in a room whose server does not take reactions")
	Store.pick(str(fixtures["relay-b"].recording_hash), "sad")
	_check(EndReactionScreen.face_to_send(ctx, fixtures["relay-b"]).is_empty(), "And nothing is sent there")
	ctx.available = true
	ctx.room_id = ROOM
	ctx.viewer_slot = "p1"
	ctx.prior = fixtures["relay-a"]
	Store.new().keep(str(fixtures["relay-a"].recording_hash), "happy")
	var row = EndReactionScreen.attach_ending(ctx, host, fixtures["relay-b"], true)
	await process_frame
	await process_frame
	_check(row != null and row.friend_bubble != null and row.friend_bubble.face == "happy" and is_instance_valid(row.pill), "A second turn's card shows the friend's face on the first turn beside the pill")
	_check(row.context.note == PlayerCopy.END_REACTIONS_ROOM_NOTE and row.context.color == "mint" and row.friend_bubble.color == "peach", "Its note says the friend sees it, and each face is in its spirit's colour")
	_check(scape.played.size() == 1 and scape.played[0] == ["relay-isles@2", "relay", "a", str(fixtures["relay-a"].recording_hash), "happy"], "The friend's face pops with its own reaction's sound")
	row.choose("angry")
	_check(scape.played.back() == ["relay-isles@2", "relay", "b", str(fixtures["relay-b"].recording_hash), "angry"] and EndReactionScreen.face_to_send(ctx, fixtures["relay-b"]) == "angry", "A pick sounds from its own run and is what Save turn sends")
	host.queue_free()
	await process_frame
	host = _host(Vector2(566, 0))
	ctx.pending = true
	ctx.pending_face = "angry"
	row = EndReactionScreen.attach_ending(ctx, host, fixtures["relay-b"], true)
	_check(row.chosen == "angry" and row.pill == null, "A turn waiting to send shows its face fixed")
	ctx.pending_face = ""
	var bare = EndReactionScreen.attach_ending(ctx, host, fixtures["relay-a"], true)
	_check(bare == null, "A turn waiting to send without a face offers no picker, since a pick could not go with it")
	ctx.pending = false
	host.queue_free()
	host = _host(Vector2(566, 0))
	row = EndReactionScreen.attach_ending(ctx, host, fixtures["relay-a"], false)
	_check(row.context.note == PlayerCopy.END_REACTIONS_MOMENT_NOTE and row.friend_bubble == null, "A turn that is not kept says its face is for the moment")
	host.queue_free()
	# The chapter's finish: both last faces, the viewer's own by slot.
	Store.new().keep(str(fixtures["garden-a"].recording_hash), "heart")
	Store.new().keep(str(fixtures["garden-b"].recording_hash), "squeeze")
	pairs.append({"a": fixtures["relay-a"], "b": fixtures["relay-b"]})
	pairs.append({"a": fixtures["garden-a"], "b": fixtures["garden-b"]})
	host = _host(Vector2(566, 0))
	row = EndReactionScreen.attach_completed(ctx, host)
	_check(row != null and row.chosen == "heart" and row.friend_bubble.face == "squeeze" and row.pill == null, "The guest starts the garden, so its first face is theirs and the second the friend's")
	host.queue_free()
	ctx.viewer_slot = "p0"
	host = _host(Vector2(566, 0))
	row = EndReactionScreen.attach_completed(ctx, host)
	_check(row.chosen == "squeeze" and row.friend_bubble.face == "heart", "And for the host the other way round")
	host.queue_free()
	# The room panel's friend strip shows the friend's latest face, still and quiet.
	Store.new().note_room(ROOM, {"schema_version": 1, "faces": {}, "partner": "sleepy"})
	var strip := HBoxContainer.new()
	root.add_child(strip)
	# The finish cards' friend faces sound a frame later; let them before listening.
	await process_frame
	scape.played.clear()
	ctx.settings = {"reduced_motion": false}
	row = EndReactionScreen.attach_friend_latest(ctx, strip)
	await process_frame
	await process_frame
	_check(row != null and row.friend_bubble.face == "sleepy" and row.context.compact and row.friend_bubble.color == "mint", "The friend strip shows their latest face, small, in the guest's colour")
	_check(row.friend_bubble.scale == Vector2.ONE, "A face in a list does not pop")
	_check(scape.played.is_empty(), "A face in a list makes no sound")
	_check(row.store == null, "A face in a list never reads the reactions file")
	strip.queue_free()
	ctx.settings = {"reduced_motion": true}
	# A rewatched turn pops its faces above the spirits.
	var world := FakeWorld.new()
	root.add_child(world)
	var hud := Control.new()
	hud.size = Vector2(1280, 720)
	root.add_child(hud)
	ctx.world = world
	ctx.hud = hud
	await process_frame
	scape.played.clear()
	var hold := EndReactionScreen.pop_replay(ctx, [fixtures["garden-b"], fixtures["garden-a"]])
	_check(hold > 0.0 and hud.get_child_count() == 2 and scape.played.size() == 2, "A rewatched part pops both faces with their sounds and holds a moment")
	_check(scape.played[0] == ["relay-isles@2", "garden", "b", str(fixtures["garden-b"].recording_hash), "squeeze"], "The same reaction sounds the same in a rewatch")
	var popped: Control = hud.get_child(0)
	var before := popped.position
	world.camera.position += Vector3(2, 0, 0)
	world.camera.look_at(Vector3(2, 0, 0))
	await process_frame
	await process_frame
	_check(popped.position != before, "A rewatch bubble stays over its spirit while the camera moves")
	var faceless: Dictionary = fixtures["relay-b"].duplicate(true)
	faceless.recording_hash = "d".repeat(64)
	_check(EndReactionScreen.pop_replay(ctx, [faceless, {}]) == 0.0 and hud.get_child_count() == 2, "A part without faces pops nothing and does not hold")
	for node: Node in [world, hud, scape]: node.queue_free()
	await process_frame
	_clear_default_store()


func _solo_screen() -> void:
	_clear_default_store()
	root.size = Vector2i(1280, 720)
	var app := Preview.new()
	app.journey = Journey.new(_path("journal"))
	app.turn_tries = preload("res://services/turn_tries.gd").new(_path("tries-solo"))
	app.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	root.add_child(app)
	app.set_physics_process(false)
	app.set_process(false)
	await process_frame
	app._begin()
	await process_frame
	for input: Dictionary in Simulation.expand_recording_inputs(fixtures["relay-a"]): app.advance_input(input)
	app._finish()
	await process_frame
	var row: Control = app.overlay.find_child("EndReactions", true, false)
	_check(app.mode == "review" and row != null and is_instance_valid(row.pill), "The review card offers the picker")
	_check(row.context.note == PlayerCopy.END_REACTIONS_SOLO_NOTE, "Solo, the face is kept with the replay")
	row.choose("knocked_out")
	app._show_review()
	await process_frame
	row = app.overlay.find_child("EndReactions", true, false)
	_check(row.chosen == "knocked_out", "The review card drawn again keeps the pick")
	var saved := str(app.review.get("recording_hash", ""))
	app._accept()
	_check(Store.new().kept(saved) == "knocked_out", "Save turn keeps the face with the turn")
	app._show_ending_card({"kind": "drowned", "badge": &"knocked_out", "water": true, "rows": [["try_again"]], "line": "Oh no, you drowned! Try again?", "color": "peach"})
	await process_frame
	_check(app.overlay.find_child("EndReactions", true, false) != null, "An ending card offers the picker too")
	# A rewatch holding on its faces goes on even if the app went to the background meanwhile.
	app.mode = "replay"
	app.running = false
	app.backgrounded = true
	app._hold_replay_end(0.05)
	await create_timer(0.3).timeout
	app.backgrounded = false
	_check(app.mode != "replay", "A rewatch held on its faces ends, backgrounded or not")
	app.queue_free()
	await process_frame
	_clear_default_store()
