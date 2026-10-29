extends "res://tests/test_relay_room_coordinator.gd"
## Reactions made during a run: the shared faces, the track and its rules, what
## the phone keeps, their sound, the React pill and its card in play, a room
## turn's track and the friend's coming back, and the chapter screen recording
## them live and playing them on the memory, never touching the recording.

const Faces = preload("res://services/reaction_catalog.gd")
const EndStore = preload("res://services/end_reaction_store.gd")
const Track = preload("res://services/run_reaction_track.gd")
const RunStore = preload("res://services/run_reaction_store.gd")
const RunReactions = preload("res://presentation/run_reactions.gd")
const EndReactions = preload("res://presentation/end_reactions.gd")
const Player = preload("res://presentation/run_reaction_player.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
const Soundscape = preload("res://services/soundscape.gd")
const SoundCues = preload("res://services/sound_cues.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const Preview = preload("res://relay_preview.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Look = preload("res://presentation/spirit_look.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const HASH_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const HASH_B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

var _paths: Array[String] = []

func _run() -> void:
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b", "initial-checkpoint", "relay-checkpoint", "final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	_clear_default_store()
	_catalog()
	_track()
	_store()
	_sound()
	_live_slots()
	await _player()
	await _pill_and_card()
	_rooms_api()
	await _replays_list()
	await _room_turns()
	await _screen()
	_clear_default_store()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("Run reactions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _path(label: String) -> String:
	var path := "user://run-reactions-test-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

## The default files the screens and the coordinator use; this suite runs on its own user dir.
func _clear_default_store() -> void:
	for file: String in [RunStore.FILE_PATH, EndStore.FILE_PATH]:
		for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(file + suffix))

func _catalog() -> void:
	_check(EndStore.FACES == Faces.FACES and EndStore.HEART == Faces.HEART, "End reactions read the one shared catalog")
	_check(Faces.FACES.size() == 9 and not Faces.FACES.has("normal") and Faces.FACES.has("knocked_out"), "Eight faces with Knocked out in Normal's place, and the heart")
	for face: String in Faces.FACES:
		_check(Look.has(Faces.spirit_expression(face)) and not Faces.face_name(face).is_empty(), "%s gives its spirit a real face and has a name" % face)
	_check(Faces.expression(Faces.HEART) == &"" and Faces.spirit_expression(Faces.HEART) == Look.JOY and Faces.HEART_EXPRESSION == Look.JOY, "The heart is an icon only, and its spirit makes the ^ ^ Joy face")
	_check(Faces.spirit_expression("happy") == Look.HAPPY and Faces.expression("happy") == Look.HAPPY, "The Happy reaction still makes the Happy face")

func _track() -> void:
	var track := Track.new()
	_check(track.add(0, "happy") == 0 and track.add(Track.COOLDOWN_TICKS - 1, "sad") == -1 and track.add(Track.COOLDOWN_TICKS, "sad") == 1, "Three seconds of the turn's ticks between reactions")
	_check(track.add(500, "normal") == -1 and track.add(500, "") == -1, "Only catalog faces")
	_check(is_equal_approx(track.cooldown(Track.COOLDOWN_TICKS), 1.0) and is_equal_approx(track.cooldown(Track.COOLDOWN_TICKS * 2), 0.0) and track.cooldown(Track.COOLDOWN_TICKS + 45) == 0.5, "The cooldown runs from 1 to 0 over its ticks")
	var full := Track.new()
	for index in range(Track.MAX_PER_TURN): full.add(index * Track.COOLDOWN_TICKS, Faces.FACES[index % Faces.FACES.size()])
	_check(full.full() and full.add(99999, "happy") == -1 and full.cooldown(99999) == 0.0, "Twenty a turn, then no more")
	_check(Track.parse(full.track(), (Track.MAX_PER_TURN - 1) * Track.COOLDOWN_TICKS) == full.track(), "A full track reads back as it was")
	var refused: Array = [null, [], {}, "happy", [{"tick": 1}], [{"tick": 1, "id": "happy", "x": 1}], [{"tick": 1.5, "id": "happy"}], [{"tick": -1, "id": "happy"}],
		[{"tick": 4, "id": "happy"}, {"tick": 4, "id": "sad"}], [{"tick": 4, "id": "happy"}, {"tick": 2, "id": "sad"}], [{"tick": 1, "id": "Happy"}], [[1, "happy"]]]
	var many: Array = []
	for index in range(Track.MAX_PER_TURN + 1): many.append({"tick": index, "id": "happy"})
	refused.append(many)
	for value: Variant in refused: _check(Track.parse(value).is_empty(), "A track out of shape is refused whole: %s" % str(value).left(60))
	_check(Track.parse([{"tick": 141.0, "id": "sad"}], 140).is_empty() and Track.parse([{"tick": 140.0, "id": "sad"}], 140) == [{"tick": 140, "id": "sad"}], "Its last tick is within the turn, and JSON numbers read as whole ticks")
	var cursor := Track.Cursor.new([{"tick": 10, "id": "happy"}, {"tick": 100, "id": "sad"}, {"tick": 200, "id": "heart"}])
	_check(cursor.due(9).is_empty() and cursor.due(10) == [0] and cursor.due(11).is_empty(), "Playback shows a reaction on its own tick, once")
	_check(cursor.due(100 + Track.LATE_TICKS + 1).is_empty() and cursor.due(400).is_empty(), "One passed long ago (a skip) is dropped, never shown late")

func _store() -> void:
	var path := _path("store")
	var store := RunStore.new(path)
	var entries := [{"tick": 30, "id": "happy"}, {"tick": 130, "id": "heart"}]
	store.keep(HASH_A, entries)
	store.keep("short", entries)
	store.keep(HASH_B, [{"tick": 5, "id": "normal"}])
	_check(RunStore.new(path).track(HASH_A) == entries and RunStore.new(path).track("short").is_empty() and RunStore.new(path).track(HASH_B).is_empty(), "A turn's track is kept by its recording hash, and only a valid one")
	store.note({"schema_version": 1, "tracks": {HASH_B: [{"tick": 7.0, "id": "sad"}], "bad": [{"tick": 1, "id": "happy"}], HASH_A: "nope"}})
	var read := RunStore.new(path)
	_check(read.track(HASH_B) == [{"tick": 7, "id": "sad"}] and read.track(HASH_A) == entries, "A reply's tracks are kept one by one, the bad ones skipped")
	store.note({"schema_version": 2, "tracks": {HASH_B: [{"tick": 8, "id": "sad"}]}})
	store.note(null)
	_check(RunStore.new(path).track(HASH_B) == [{"tick": 7, "id": "sad"}], "A reply of another shape changes nothing")
	var other := RunStore.new(path)
	store.keep(HASH_B, [{"tick": 9, "id": "angry"}])
	other.keep(HASH_A, [{"tick": 1, "id": "sad"}])
	_check(RunStore.new(path).track(HASH_B) == [{"tick": 9, "id": "angry"}], "Two holders of the file never undo each other")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	_check(RunStore.new(path).track(HASH_A).is_empty(), "A damaged file reads as empty")

func _sound() -> void:
	var track := [{"tick": 30, "id": "happy"}, {"tick": 130, "id": "happy"}, {"tick": 230, "id": "sad"}]
	var first := Soundscape.run_reaction_pitch("relay-isles@2", "relay", "p0", track, 1)
	_check(first == Soundscape.run_reaction_pitch("relay-isles@2", "relay", "p0", track.duplicate(true), 1), "The same recorded reaction always has the same pitch")
	for index in range(1, track.size()):
		_check(absf(Soundscape.run_reaction_pitch("relay-isles@2", "relay", "p0", track, index) - Soundscape.run_reaction_pitch("relay-isles@2", "relay", "p0", track, index - 1)) >= Soundscape.CUE_MIN_MOVE - 0.001, "Neighbouring reactions differ in pitch")
	for index in range(track.size()):
		var pitch := Soundscape.run_reaction_pitch("relay-isles@2", "relay", "p0", track, index)
		_check(pitch >= SoundCues.REACTION.range.x and pitch <= SoundCues.REACTION.range.y, "Within the pop's range")
	_check(Soundscape.run_reaction_pitch("relay-isles@2", "relay", "p0", track, 0) == Soundscape.run_reaction_pitch("relay-isles@2", "relay", "p0", track.slice(0, 1), 0), "A reaction's pitch reads only the track up to it, so live and playback agree")

## Every chapter's engine names the live spirit's slot the way its recording
## does, so a reaction made live and the same one played back share a spirit
## and a pitch.
func _live_slots() -> void:
	var still := {"move_x": 0.0, "move_z": 0.0, "interact": false}
	for key: String in Registry.keys():
		var level := Registry.definition(key)
		var stages: Variant = level.get("stages")
		if not stages is Array or stages.is_empty(): continue
		var stage: Dictionary = stages[0]
		var sim: RefCounted = Registry.simulation_script(key).new()
		if not Registry.reset_simulation(sim, key, level, str(stage.id), Registry.initial_checkpoint(key), {}, "a"):
			_check(false, "%s resets a first turn" % key)
			continue
		for index in range(3): sim.step(still)
		var slot := str(sim.snapshot().get("active_slot", ""))
		var recorded := str(sim.export_recording().get("player_slot", slot))
		_check(slot in ["p0", "p1"] and slot == str(stage.get("first_player_slot", "p0")) and slot == recorded, "%s names its live slot as its recording does (%s)" % [key, slot])

func _player() -> void:
	var world := FakeWorld.new()
	root.add_child(world)
	var hud := Control.new()
	hud.size = Vector2(1280, 720)
	root.add_child(hud)
	var scape := FakeScape.new()
	root.add_child(scape)
	await process_frame
	var player := Player.new()
	player.world = world
	player.hud = hud
	player.soundscape = scape
	player.settings = {"reduced_motion": true}
	player.begin("p1")
	var memory := {"player_slot": "p0", "recording_hash": HASH_A}
	player.play(memory, [{"tick": 10, "id": "surprised"}], PlayerCopy.RUN_REACTIONS_MEMORY)
	player.play({"player_slot": "nope"}, [{"tick": 10, "id": "sad"}])
	_check(player.react(5, "happy") and not player.react(20, "sad") and player.live.track() == [{"tick": 5, "id": "happy"}], "The live spirit records its own reaction on its tick, and the cooldown refuses the next")
	_check(world.actors.p1.faces == [[Look.HAPPY, Track.FACE_SECONDS]] and scape.played == [["p1", 0, "happy"]] and scape.haptics == 1, "It makes the face, the pop and a light tap at once")
	_check(_bubbles(hud).size() == 1 and _bubbles(hud)[0].face == "happy" and _bubbles(hud)[0].color == "mint" and _bubbles(hud)[0].find_child("BubbleCaption", true, false) == null, "A bubble over the player's own spirit, in its colour, without a caption")
	var explore: Node = preload("res://presentation/camera_exploration.gd").new()
	root.add_child(explore)
	_check(_bubbles(hud)[0].process_priority > explore.process_priority, "A bubble follows its spirit after pinch zoom and pan move the camera")
	explore.free()
	player.step(9)
	_check(world.actors.p0.faces.is_empty(), "Nothing before the memory's tick")
	player.step(10)
	_check(world.actors.p0.faces == [[Look.SURPRISED, Track.FACE_SECONDS]] and scape.played.back() == ["p0", 0, "surprised"], "The memory makes its recorded face on its tick, with its sound")
	var captions: Array = []
	for bubble: Control in _bubbles(hud):
		var caption: Label = bubble.find_child("BubbleCaption", true, false)
		if caption != null: captions.append(caption.text)
	_check(captions == [PlayerCopy.RUN_REACTIONS_MEMORY], "The friend's bubble says it is from their turn")
	player.begin()
	_check(not player.react(500, "happy") and player.live.track().is_empty(), "A replay records nothing")
	world.queue_free()
	hud.queue_free()
	scape.queue_free()
	await create_timer(Track.BUBBLE_SECONDS + 0.5).timeout

func _bubbles(node: Node) -> Array:
	return node.find_children("*", "", true, false).filter(func(found: Node) -> bool: return found is EndReactions.Bubble and not found.is_queued_for_deletion())

func _pill_and_card() -> void:
	for case: Array in [[Vector2i(1280, 720), false], [Vector2i(1600, 738), false], [Vector2i(1280, 720), true]]:
		var viewport := SubViewport.new()
		viewport.size = case[0]
		viewport.handle_input_locally = true
		root.add_child(viewport)
		var controls := Controls.new()
		controls.settings = {"left_handed": case[1]}
		viewport.add_child(controls)
		var pill := RunReactions.new()
		pill.settings = controls.settings
		var faces_path := _path("pill-faces")
		pill.store_path = faces_path
		controls.dock_beside_finish(pill, RunReactions.SIZE)
		controls.show_play()
		await process_frame
		await process_frame
		var rect := pill.get_global_rect()
		var finish := controls.finish_button.get_global_rect()
		var action := controls.action_button.get_global_rect()
		var stick := controls.stick.get_global_rect()
		_check(not rect.intersects(finish.grow(Controls.DOCK_GAP - 1.0)) and not rect.intersects(action) and not rect.intersects(stick) and is_equal_approx(rect.get_center().y, finish.get_center().y), "The pill sits level with Finish, apart from every control at %s, left handed %s" % [str(case[0]), case[1]])
		_check((rect.position.x > finish.end.x) == case[1] and rect.size.y >= finish.size.y, "On the inner side of Finish, at least as tall")
		_check(not controls.hint_label.get_global_rect().intersects(rect), "The hint line keeps clear of it")
		var sent: Array = []
		pill.reacted.connect(func(face: String) -> void: sent.append(face))
		var quick_rect := pill.quick.get_global_rect()
		var react_rect := pill.opener.get_global_rect()
		_check(pill.quick.is_visible_in_tree() and pill.quick_face == EndStore.DEFAULT_FACE and pill._quick_icon.face == EndStore.DEFAULT_FACE, "The split pill's left half shows the last face (Happy before any)")
		_check(is_equal_approx(quick_rect.position.x, rect.position.x) and is_equal_approx(quick_rect.size.y, rect.size.y) and quick_rect.end.x <= react_rect.position.x + 0.5 and is_equal_approx(react_rect.end.x, rect.end.x), "The quick half is the pill's left end, the divider then React's half to its right end")
		_check(quick_rect.size.x >= EndReactions.TARGET and react_rect.size.x >= EndReactions.TARGET * 2.0, "Both halves are full size tap targets")
		_check(pill.quick.accessibility_name == PlayerCopy.END_REACTIONS_QUICK % "Happy" and pill.accessibility_name == PlayerCopy.END_REACTIONS_CHOOSE, "Each half says what it does")
		await _tap(viewport, quick_rect.get_center())
		_check(sent == ["happy"] and not pill.faces_open(), "The first tap on the quick half sends the last face, and opens nothing")
		_check(not FileAccess.file_exists(faces_path) and EndStore.last_known(faces_path) == "happy", "A face sent in play writes no file then")
		await _tap(viewport, react_rect.get_center())
		var card: CanvasLayer = pill.faces_card
		_check(pill.is_visible_in_tree() and pill.faces_open() and card.cells.size() == 9, "The first tap on React opens the shared faces card")
		var note: Label = card.panel.find_child("ReactionNote", true, false)
		_check(note != null and note.text == PlayerCopy.RUN_REACTIONS_NOTE, "The card's footer says the reactions are saved with the turn")
		var panel: Rect2 = card.panel_rect()
		_check(Rect2(Vector2.ZERO, Vector2(case[0])).encloses(panel), "The card stays on screen")
		for other: Rect2 in [rect, finish, action, stick]: _check(not panel.intersects(other), "The card never covers the pill, the action button, Finish or the joystick")
		_check(panel.end.y <= rect.position.y, "It opens above the pill, inward")
		_check(card.shade.mouse_filter == Control.MOUSE_FILTER_IGNORE and card.shade.color.a == 0.0, "Nothing under it is dimmed or blocked")
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.button_mask = MOUSE_BUTTON_MASK_LEFT
		press.pressed = true
		press.position = stick.get_center() + Vector2(30, 0)
		press.global_position = press.position
		viewport.push_input(press, true)
		await process_frame
		_check(controls.stick.value != Vector2.ZERO and pill.faces_open(), "The joystick keeps working while the card is open, and it stays open")
		var release: InputEventMouseButton = press.duplicate()
		release.pressed = false
		release.button_mask = 0
		viewport.push_input(release, true)
		await process_frame
		(card.cells["sad"] as Button).pressed.emit()
		await process_frame
		_check(sent == ["happy", "sad"] and not pill.faces_open(), "A face sends and closes the card")
		_check(pill.quick_face == "sad" and pill._quick_icon.face == "sad" and pill.quick.accessibility_name == PlayerCopy.END_REACTIONS_QUICK % "Sad", "The face sent becomes the quick face")
		pill.show_cooldown(0.5, false)
		_check(pill.disabled and pill.quick.disabled and not pill.can_send() and pill.modulate.a == 1.0, "The pill rests while the cooldown runs, its sweep shown at full strength")
		pill.pressed.emit()
		await _tap(viewport, quick_rect.get_center())
		_check(not pill.faces_open() and sent == ["happy", "sad"], "and neither half does anything then")
		pill.show_cooldown(0.0, false)
		pill.pressed.emit()
		await process_frame
		var world_tap := InputEventMouseButton.new()
		world_tap.button_index = MOUSE_BUTTON_LEFT
		world_tap.pressed = true
		pill.faces_card._unhandled_input(world_tap)
		await process_frame
		_check(not pill.faces_open(), "A tap on the world closes it")
		pill.show_cooldown(0.0, true)
		_check(pill.disabled and pill.modulate.a < 1.0, "Once the turn's reactions are used up the pill greys out")
		pill.show_cooldown(0.0, false)
		pill.pressed.emit()
		await process_frame
		card = pill.faces_card
		controls.hud.visible = false
		await process_frame
		_check(not pill.faces_open(), "A pause (the hud hidden) closes the card")
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(faces_path))
		_check(saved is Dictionary and saved.get("last") == "sad" and not EndStore.has_unsaved(faces_path), "Once the pill hides, the face used in play is written as the last face")
		var end_card := Control.new()
		viewport.add_child(end_card)
		var row: Control = EndReactions.attach(end_card, {"run": HASH_A, "pick": true, "store": EndStore.new(faces_path)})
		_check(row != null and row._quick_icon.face == "sad", "The end card's quick half offers the face used in play")
		pill.color = "mint"
		_check(pill._quick_icon.color == "mint", "The quick face is drawn in the player's spirit colour")
		controls.hud.visible = true
		pill.show_cooldown(0.0, false)
		EndStore.new(faces_path).choose(HASH_B, "angry")
		pill.visible = false
		pill.visible = true
		_check(pill.quick_face == "angry", "A face picked on an end card is the quick face when the pill next shows, read from memory")
		viewport.queue_free()
		await process_frame

## A real press and release, as a finger's tap.
func _tap(viewport: SubViewport, at: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	viewport.push_input(press, true)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	release.button_mask = 0
	viewport.push_input(release, true)
	await process_frame

func _rooms_api() -> void:
	var turns := "/v2/rooms/" + ROOM + "/turns"
	for case: Array in [[HTTPClient.METHOD_GET, "/v2/capabilities", true], [HTTPClient.METHOD_GET, "/v1/room-inbox", false], [HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM, true],
		[HTTPClient.METHOD_POST, turns, true], [HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM + "/end-reactions", true], [HTTPClient.METHOD_POST, "/v2/rooms/" + ROOM + "/end-reactions", false],
		[HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM + "/pairs/p0-0", false], [HTTPClient.METHOD_POST, "/v2/rooms/join", false]]:
		_check(RoomsApi.capability_headers(case[0], case[1]).has(RoomsApi.RUN_REACTIONS_HEADER) == case[2], "%s %s asks for run reactions: %s" % [case[0], case[1], case[2]])
	var api := RoomsApi.new()
	var tracks := {"schema_version": 1, "tracks": {HASH_A: [{"tick": 3, "id": "happy"}]}}
	var result: Dictionary = api._result([HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"room_id": ROOM, "run_reactions": tracks}).to_utf8_buffer()], HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM)
	_check(result.ok and not result.data.has("run_reactions") and result.data.room_id == ROOM and result.run_reactions.tracks.has(HASH_A), "The friend's track leaves the reply beside it, and the room is as it was")
	api.free()

## Replays read every turn's track beside the end reactions list, through
## rooms_api.gd's reply (which takes the tracks out beside it).
func _replays_list() -> void:
	_clear_default_store()
	var api := RoomsApi.new()
	var path := "/v2/rooms/" + ROOM + "/end-reactions"
	var listed := {"schema_version": 1, "faces": {HASH_A: "happy"}, "run_reactions": {"schema_version": 1, "tracks": {HASH_B: [{"tick": 50, "id": "angry"}]}}}
	var collection := ListedReplays.new()
	collection.reply = api._result([HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(listed).to_utf8_buffer()], HTTPClient.METHOD_GET, path)
	collection.end_reactions_supported = func() -> bool: return true
	await collection._refresh_end_reactions({"room_id": ROOM, "family": "chapter"}, [{"id": "p0-0", "a_hash": HASH_A, "b_hash": HASH_B}])
	_check(RunStore.new().track(HASH_B) == [{"tick": 50, "id": "angry"}], "A Replays list read keeps every turn's track")
	_check(EndStore.new().kept(HASH_A) == "happy", "and the faces as before")
	api.free()
	_clear_default_store()

func _room_turns() -> void:
	_clear_default_store()
	var recording: Dictionary = fixtures["relay-a"]
	var hash := str(recording.recording_hash)
	var track := [{"tick": 12, "id": "happy"}, {"tick": 120, "id": "heart"}]
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	_check(await coordinator.commit(recording, 0, "", track), "A room turn is sent with its track")
	var sent: Dictionary = boundary.requests.back().body
	_check(sent.get("run_reactions") == track and Canonical.same(sent.recording, recording) and not sent.has("end_reaction"), "The track travels beside the recording, which is unchanged")
	_check(RunStore.new().track(hash) == track, "Once accepted, the turn's track is kept on this phone")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	_check(await coordinator.commit(recording, 0, "", []) and not boundary.requests.back().body.has("run_reactions"), "No reactions send the old body")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	_check(await coordinator.commit(recording, 0, "", [{"tick": 999, "id": "happy"}]) and not boundary.requests.back().body.has("run_reactions"), "A track that runs past the turn is never sent")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	_check(not await coordinator.commit(recording, 0, "sad", track), "A lost answer leaves the turn and its track pending")
	var pending: Dictionary = coordinator.pending().duplicate(true)
	coordinator = _coordinator(boundary)
	_check(coordinator.bind_room(ROOM) and Canonical.same(coordinator.pending(), pending) and pending.body.run_reactions == track, "The pending turn reloads with its track, so a resend is byte for byte")
	var scope := "relay-room-v2:" + HOST + ":" + ROOM
	boundary.disk[scope].pending.body.run_reactions = [{"tick": 12, "id": "normal"}]
	coordinator = _coordinator(boundary)
	_check(not coordinator.bind_room(ROOM) and coordinator.read_only, "A stored track this build does not trust is refused")
	boundary = Boundary.new()
	boundary.identity.player_id = GUEST
	coordinator = _coordinator(boundary)
	_check(coordinator.bind_room(ROOM), "The guest binds the room")
	var waiting := _snapshot(GUEST, 0, true, 2)
	boundary.responses.append({"ok": true, "status": 200, "data": waiting, "run_reactions": {"schema_version": 1, "tracks": {hash: [{"tick": 40, "id": "surprised"}]}}})
	_check(await coordinator.refresh() and Canonical.same(coordinator.snapshot(), waiting), "A room read with the friend's track beside it keeps exactly the room it checked")
	_check(RunStore.new().track(hash) == [{"tick": 40, "id": "surprised"}], "The friend's track is kept for their memory")
	_clear_default_store()

## The chapter screen, solo: the pill in play, a live reaction recorded on its
## tick and kept with the saved turn, the recording unchanged, and the memory
## making it on the same tick in the next turn.
func _screen() -> void:
	_clear_default_store()
	root.size = Vector2i(1280, 720)
	var app := Preview.new()
	app.journey = Journey.new(_path("journal"))
	app.turn_tries = preload("res://services/turn_tries.gd").new(_path("tries"))
	app.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	root.add_child(app)
	app.set_physics_process(false)
	app.set_process(false)
	await process_frame
	_check(not app.run_reactions.is_visible_in_tree(), "No pill before a turn is played")
	var inputs: Array = Simulation.expand_recording_inputs(fixtures["relay-a"])
	# The same turn played once without reactions, then again (Retry) with them.
	app._begin()
	await process_frame
	for input: Dictionary in inputs:
		if app.mode == "play": app.advance_input(input)
	if app.mode == "play": app._finish()
	await process_frame
	var plain: Dictionary = app.review.duplicate(true)
	app._begin()
	await process_frame
	for index in range(30): app.advance_input(inputs[index])
	_check(app.run_reactions.visible and app.run_reactions.can_send(), "The pill shows in play")
	app.run_reactions.toggle_faces()
	await process_frame
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(not app.run_reactions.faces_open() and app.mode == "play" and app.running, "Back closes the card first and play goes on")
	var live_slot: String = app.run_player.live_slot
	_check(app.run_reactions.quick_face == "happy", "The quick half offers Happy before any face is used")
	app.run_reactions.quick.pressed.emit()
	_check(app.run_player.live.track() == [{"tick": 30, "id": "happy"}], "The quick half's tap is recorded on the turn's own tick")
	_check(app.world.actors[live_slot].expression_target() == Look.HAPPY, "The spirit makes the face")
	_check(not _bubbles(app.hud).is_empty(), "A bubble pops over it")
	app.advance_input(inputs[30])
	_check(not app.run_reactions.can_send(), "The pill rests during the cooldown")
	app._react_in_run("sad")
	_check(app.run_player.live.track().size() == 1, "A reaction in the cooldown is not recorded")
	for index in range(31, inputs.size()):
		if app.mode == "play": app.advance_input(inputs[index])
	if app.mode == "play": app._finish()
	await process_frame
	_check(not plain.is_empty() and Canonical.same(app.review, plain), "The recording is byte for byte the one played without reactions")
	_check(not app.run_reactions.is_visible_in_tree(), "The pill goes once the turn ends")
	var saved := str(app.review.get("recording_hash", ""))
	app._accept()
	_check(RunStore.new().track(saved) == [{"tick": 30, "id": "happy"}], "Save turn keeps the track with the turn")
	await process_frame
	app._begin()
	await process_frame
	var memory_slot := str(fixtures["relay-a"].player_slot)
	_check(app.mode == "play" and app.run_player.live_slot != memory_slot, "The next turn plays alongside the memory")
	for index in range(29): app.advance_input(Simulation.expand_recording_inputs(fixtures["relay-b"])[index])
	_check(app.world.actors[memory_slot].expression_target() != Look.HAPPY, "The memory waits for its tick")
	app.advance_input(Simulation.expand_recording_inputs(fixtures["relay-b"])[29])
	_check(app.world.actors[memory_slot].expression_target() == Look.HAPPY, "The memory makes the face on the same tick")
	var captioned := false
	for bubble: Control in _bubbles(app.hud): captioned = captioned or bubble.find_child("BubbleCaption", true, false) != null
	_check(not captioned, "Solo, the memory is the player's own: no friend's caption")
	app._begin_completion(false)
	_check(not app.run_reactions.visible, "The pill goes when the stage blooms")
	app.queue_free()
	await process_frame
	_clear_default_store()

class ListedReplays extends "res://services/shared_replay_collection.gd":
	var reply: Dictionary = {}
	func _init() -> void:
		super(null, Callable())
	func _request_get(_path: String, _chapter_room_id: String = "", _quiet: bool = false) -> Dictionary:
		return reply

class FakeScape extends Node:
	var played: Array = []
	var haptics := 0
	func play_run_reaction(slot: String, track: Array, index: int) -> void: played.append([slot, index, str(track[index].id)])
	func tap_haptic() -> void: haptics += 1

class FakeSpirit extends Node3D:
	var faces: Array = []
	func show_expression(expression: StringName, duration: float) -> void: faces.append([expression, duration])

class FakeWorld extends Node3D:
	var camera := Camera3D.new()
	var actors := {}
	func _init() -> void:
		add_child(camera)
		camera.position = Vector3(0, 6, 8)
		for slot: String in ["p0", "p1"]:
			var actor := FakeSpirit.new()
			actor.position = Vector3(-1 if slot == "p0" else 1, 0, 0)
			add_child(actor)
			actors[slot] = actor
	func _ready() -> void:
		camera.look_at(Vector3.ZERO)
