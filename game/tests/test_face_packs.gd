extends "res://tests/test_relay_room_coordinator.gd"
## Reaction packs (board 6b): the six pack faces in the face shader and the flat
## art, which packs a player may pick from (owned, a server that takes them,
## never on an iPhone build without the shop), the faces card's pack tabs, the
## Wardrobe's pack rows, faces this build does not know, the in-run pill's
## quick half never offering a pack face the send would strip, and a turn the
## server refuses for an unowned pack face going again without it.

const Look = preload("res://presentation/spirit_look.gd")
const SpiritFace = preload("res://presentation/spirit_face.gd")
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const ReactionCatalog = preload("res://services/reaction_catalog.gd")
const FacePacks = preload("res://services/face_packs.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const Store = preload("res://services/end_reaction_store.gd")
const EndReactions = preload("res://presentation/end_reactions.gd")
const RunReactions = preload("res://presentation/run_reactions.gd")
const RunReactionTrack = preload("res://services/run_reaction_track.gd")
const InboxClient = preload("res://services/room_inbox_client.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const NEW: Array[String] = ["heart_eyes", "proud", "wink", "wow", "crying", "dizzy"]
const HASH_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const HASH_B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

var _paths: Array[String] = []

func _run() -> void:
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b", "initial-checkpoint", "relay-checkpoint", "final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	_clear_default_store()
	_catalog()
	_contours()
	_shader_and_pip()
	_unknown_faces()
	_pickable()
	_wardrobe_rows()
	await _faces_card_tabs()
	await _run_pill()
	await _refused_turn()
	_headers()
	FacePacks.source = Callable()
	PollenSurfaces.set_shared_for_tests(null)
	_clear_default_store()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("Face packs: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _path(label: String) -> String:
	var path := "user://face-packs-test-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

func _clear_default_store() -> void:
	for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(Store.FILE_PATH + suffix))
	Store._picks.clear()

func _area(polygons: Array) -> float:
	var total := 0.0
	for polygon: PackedVector2Array in polygons:
		var area := 0.0
		for index in range(polygon.size()): area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
		total += absf(area) * 0.5
	return total

func _catalog() -> void:
	_check(ReactionCatalog.FACES.size() == 9 and not ReactionCatalog.FACES.any(func(face: String) -> bool: return face in NEW), "The picker's everyday faces are as before")
	_check(ReactionCatalog.PACK_FACES == NEW, "Six pack faces")
	var packed: Array = []
	for pack: String in ReactionCatalog.PACKS: packed.append_array(ReactionCatalog.PACKS[pack])
	_check(packed == NEW and ReactionCatalog.PACKS.keys() == ["garden_faces", "big_feelings"], "Garden faces then Big feelings, three faces each, every pack face in one pack")
	for face: String in NEW:
		_check(ReactionCatalog.is_face(face) and ReactionCatalog.is_pack_face(face), "%s is a known pack face" % face)
		_check(ReactionCatalog.pack_of(face) in ReactionCatalog.PACKS and face in ReactionCatalog.PACKS[ReactionCatalog.pack_of(face)], "%s names its pack" % face)
		_check(Look.has(ReactionCatalog.expression(face)) and ReactionCatalog.spirit_expression(face) == ReactionCatalog.expression(face), "%s draws its own expression" % face)
		_check(not ReactionCatalog.face_name(face).is_empty() and ReactionCatalog.face_name(face) == PlayerCopy.END_REACTION_NAMES[face], "%s has a name for screen readers and its cell" % face)
	for face: String in ReactionCatalog.FACES: _check(ReactionCatalog.pack_of(face).is_empty() and not ReactionCatalog.is_pack_face(face), "%s belongs to no pack" % face)
	for pack: String in ReactionCatalog.PACKS: _check(not ReactionCatalog.pack_name(pack).is_empty(), "%s has a name" % pack)
	_check(ReactionCatalog.face_name("heart_eyes") != ReactionCatalog.face_name("heart"), "Heart eyes is not named Love, the heart's name")

func _contours() -> void:
	for face: String in NEW:
		var expression := ReactionCatalog.expression(face)
		for index: int in range(2):
			var shape: Dictionary = Look.eye_contours(expression, index)
			_check(_area(shape.outer) + _area(shape.pupil) > 0.0 or not shape.strokes.is_empty(), "%s eye %d draws flat" % [face, index])
	var heart: Dictionary = Look.eye_contours(Look.HEART_EYES, 0)
	_check(heart.get("pupil_color") == Look.HEART_RED and _area(heart.pupil) > 0.0 and _area(heart.pupil) < _area(heart.outer), "Heart eyes: a red heart inside a cream heart")
	var wow: Dictionary = Look.eye_contours(Look.WOW, 1)
	_check(not wow.has("pupil_color") and wow.pupil.size() == 1 and (wow.pupil[0] as PackedVector2Array).size() >= 10 and _area(wow.pupil) < _area(wow.outer) * 0.6, "Wow: a dark star in a cream eye")
	var proud: Dictionary = Look.eye_contours(Look.PROUD, 0)
	_check(proud.strokes.size() == 1 and proud.has("blush") and (proud.strokes[0] as PackedVector2Array)[8].y < (proud.strokes[0] as PackedVector2Array)[0].y, "Proud: an arc bowed down, with cheeks")
	var joy: Dictionary = Look.eye_contours(Look.JOY, 0)
	_check((joy.strokes[0] as PackedVector2Array)[8].y > (joy.strokes[0] as PackedVector2Array)[0].y, "Joy still bows up, so Proud and the heart face stay apart")
	_check(Look.eye_contours(Look.WINK, 0).outer.size() > 0 and Look.eye_contours(Look.WINK, 1).strokes.size() == 1, "Wink: the viewer's left eye open, the right shut")
	var crying: Dictionary = Look.eye_contours(Look.CRYING, 1)
	_check(crying.get("streams", []).size() == 1 and _area(crying.streams) > 0.0 and crying.strokes.size() == 1, "Crying: squeezed shut with a tear stream under each eye")
	var left: PackedVector2Array = Look.eye_contours(Look.DIZZY, 0).strokes[0]
	var right: PackedVector2Array = Look.eye_contours(Look.DIZZY, 1).strokes[0]
	_check(left.size() > 40 and is_equal_approx(left[-1].x, -right[-1].x) and is_equal_approx(left[-1].y, right[-1].y), "Dizzy: a spiral in each eye, turning opposite ways")
	for face: String in ["proud", "wink", "crying", "dizzy"]: _check(not Look.is_open(ReactionCatalog.expression(face)), "%s never blinks" % face)
	for face: String in ["heart_eyes", "wow"]: _check(Look.is_open(ReactionCatalog.expression(face)), "%s blinks like an open eye" % face)

func _shader_and_pip() -> void:
	for face: String in NEW:
		var expression := ReactionCatalog.expression(face)
		var shape: Dictionary = SpiritFace._shape(expression)
		_check(SpiritFace.SHAPE_KEYS.all(func(key: String) -> bool: return shape.has(key) and (shape[key] as PackedVector4Array).size() == 2), "%s sets every face shader parameter for both eyes" % face)
		var pip := SpiritVisual.new(Look.PEACH)
		root.add_child(pip)
		pip.set_expression(expression, true)
		_check(pip.expression() == expression and pip.face_art.material.get_shader_parameter(&"eye_shape") == shape.eye_shape, "The pip wears %s" % face)
		pip.free()
	_check(SpiritFace._shape(Look.HEART_EYES).eye_shape[0] == Vector4(Look.SHAPE_HEART, Look.SHAPE_HEART, 0, 0) and SpiritFace._shape(Look.WOW).eye_shape[1] == Vector4(Look.SHAPE_STAR, Look.SHAPE_OVAL, 0, 0), "Heart and star outlines reach the shader")
	_check(SpiritFace._shape(Look.HAPPY).eye_shape[0] == Vector4.ZERO and SpiritFace._shape(Look.HAPPY).tear_stream[0] == Vector4.ZERO, "Every other face draws as before")
	var face := SpiritFace.new(Look.MINT)
	_check(face.material.get_shader_parameter(&"heart_color") == Look.HEART_RED and is_equal_approx(face.material.get_shader_parameter(&"heart_middle"), Look.HEART_MIDDLE) and is_equal_approx(face.material.get_shader_parameter(&"star_round"), Look.STAR_ROUND), "The shader takes the heart and star sizes from spirit_look")

func _unknown_faces() -> void:
	_check(ReactionCatalog.shown_face("wow") == "wow" and ReactionCatalog.shown_face("happy") == "happy", "Known faces show as they are")
	_check(ReactionCatalog.shown_face("rainbow_face") == ReactionCatalog.FALLBACK_FACE and ReactionCatalog.FALLBACK_FACE == "happy", "A face from a later pack shows as Happy")
	for bad: Variant in ["Bad Face", "", 3, null, ["happy"], "x".repeat(41)]: _check(ReactionCatalog.shown_face(bad) == "", "%s is no face" % str(bad))
	_check(not ReactionCatalog.is_face("rainbow_face") and not FacePacks.can_pick("rainbow_face", true), "An unknown face is never picked or sent")
	var track := [{"tick": 3, "id": "rainbow_face"}, {"tick": 9, "id": "dizzy"}]
	_check(RunReactionTrack.parse(track, -1, true) == [{"tick": 3, "id": "happy"}, {"tick": 9, "id": "dizzy"}], "A friend's track with an unknown face plays it as Happy instead of dropping the track")
	_check(RunReactionTrack.parse(track).is_empty(), "A track this phone sends or saves still takes known faces only")
	_check(RunReactionTrack.parse([{"tick": 3, "id": "Bad Face"}], -1, true).is_empty(), "An id out of shape still refuses the track")
	var store := Store.new(_path("unknown"))
	store.note_room(ROOM, {"schema_version": 1, "faces": {HASH_A: "rainbow_face", HASH_B: "wow"}, "partner": "rainbow_face"})
	_check(store.kept(HASH_A) == "happy" and store.kept(HASH_B) == "wow" and store.partner(ROOM) == "happy", "A room's unknown faces are kept as Happy, pack faces as they are")
	var entry: Dictionary = InboxClient._partner_reaction({"partner_reaction": "rainbow_face", "membership": {"you_are_host": true}})
	_check(entry.get("partner_reaction", {}).get("face") == "happy", "The room list shows an unknown friend face as Happy")
	_check(InboxClient._partner_reaction({"partner_reaction": "proud", "membership": {"you_are_host": false}}).partner_reaction.face == "proud", "The room list shows a pack face as it is")
	_check(InboxClient._partner_reaction({"partner_reaction": "Bad Face", "membership": {}}).is_empty(), "A broken face still shows nothing")

func _pickable() -> void:
	var sells := PollenSurfaces.new(true)
	var iphone := PollenSurfaces.new(false)
	var view := {"packs": ["big_feelings", "garden_faces", "not_a_pack"]}
	_check(FacePacks.packs_for(true, view, sells) == ["garden_faces", "big_feelings"], "Owned packs are pickable, in shelf order, and only packs this build draws")
	_check(FacePacks.packs_for(true, view, iphone).is_empty(), "An iPhone build without the shop offers no pack")
	_check(FacePacks.packs_for(false, view, sells).is_empty(), "A server that does not take pack faces is offered none")
	_check(FacePacks.packs_for(true, {"packs": []}, sells).is_empty() and FacePacks.packs_for(true, null, sells).is_empty(), "Nothing owned, nothing offered")
	FacePacks.source = Callable()
	_check(FacePacks.pickable_packs(true).is_empty(), "Before Main says whose wardrobe it is, no pack")
	FacePacks.source = func() -> Dictionary: return {"server": false, "view": {"packs": ["garden_faces"]}}
	PollenSurfaces.set_shared_for_tests(true)
	_check(FacePacks.pickable_packs(false).is_empty() and FacePacks.pickable_packs(true) == ["garden_faces"], "A solo pick may use an owned pack whatever the server takes")
	_check(FacePacks.can_pick("heart_eyes", true) and not FacePacks.can_pick("wow", true) and FacePacks.can_pick("happy") and FacePacks.can_pick("heart"), "Everyday faces always, pack faces from owned packs")
	PollenSurfaces.set_shared_for_tests(false)
	_check(not FacePacks.can_pick("heart_eyes", true), "Never on an iPhone build without the shop")
	PollenSurfaces.set_shared_for_tests(null)
	FacePacks.source = Callable()

func _wardrobe_rows() -> void:
	var view := {"packs": ["garden_faces"], "offered_packs": ["garden_faces", "big_feelings", "later_pack"], "pack_price": 5000}
	var rows := FacePacks.pack_rows(view)
	_check(rows.size() == 2 and rows[0].id == "garden_faces" and rows[0].owned and rows[1].id == "big_feelings" and not rows[1].owned and rows[1].offered and rows[1].price == 5000, "The Faces tab lists each pack sold or owned, with the server's price")
	_check(rows[0].faces == ["heart_eyes", "proud", "wink"] and rows[0].name == PlayerCopy.FACE_PACK_NAMES.garden_faces, "Each row names its pack and its faces")
	_check(FacePacks.faces_tab_visible(view, PollenSurfaces.new(true)), "The Faces tab shows once a pack exists")
	_check(not FacePacks.faces_tab_visible(view, PollenSurfaces.new(false)), "Never on an iPhone build without the shop")
	_check(not FacePacks.faces_tab_visible({"packs": [], "offered_packs": []}, PollenSurfaces.new(true)) and not FacePacks.faces_tab_visible({}, PollenSurfaces.new(true)), "No pack, no Faces tab")

func _host() -> Control:
	var host := VBoxContainer.new()
	host.position = Vector2(400, 520)
	host.size = Vector2(566, 0)
	root.add_child(host)
	return host

func _labels(node: Node) -> Array:
	var found: Array = []
	for label: Node in node.find_children("*", "Label", true, false): found.append((label as Label).text)
	return found

func _faces_card_tabs() -> void:
	root.size = Vector2i(1280, 720)
	EndReactions.FacesCard._last_tab = ""
	var store := Store.new(_path("card"))
	var host := _host()
	var row := EndReactions.attach(host, {"run": HASH_A, "pick": true, "store": store, "packs": ["garden_faces", "big_feelings"], "settings": {"reduced_motion": true}})
	await process_frame
	await process_frame
	row.opener.pressed.emit()
	await process_frame
	var card: CanvasLayer = row.faces_card
	var strip: Control = card.find_child("ReactionTabs", true, false)
	var names: Array = []
	if strip != null:
		for tab: Node in strip.get_children(): names.append((tab as Button).text)
	_check(names == [PlayerCopy.FACE_PACK_FREE_TAB, "Garden faces", "Big feelings"], "Owned packs add a tab each beside Free")
	for tab: Node in strip.get_children(): _check((tab as Control).size.y >= 56.0, "%s is a 56 px target" % (tab as Button).text)
	var grid: GridContainer = card.find_child("ReactionGrid", true, false)
	_check(grid.get_child_count() == 8 and card.tab == "", "It opens on Free with the eight faces")
	(card.tabs["big_feelings"] as Button).pressed.emit()
	await process_frame
	var cells: Array = []
	for cell: Node in grid.get_children(): cells.append(_labels(cell))
	_check(cells == [["Wow"], ["Crying"], ["Dizzy"]] and row.faces_open() and card.cells.has("dizzy") and not card.cells.has("happy") and card.cells.has(Store.HEART), "A tab swaps the grid in place and the card stays open")
	_check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(card.panel_rect()) and not card.panel_rect().intersects(row.pill.get_global_rect()), "The card stays on screen, clear of its pill, after the swap")
	(card.cells["dizzy"] as Button).pressed.emit()
	await process_frame
	_check(row.chosen == "dizzy" and not row.faces_open() and row.own_bubble.face == "dizzy", "A pack face picks and closes the card")
	row.opener.pressed.emit()
	await process_frame
	_check(row.faces_card.tab == "big_feelings", "It opens again on the picked face's pack")
	row.close_faces()
	host.queue_free()
	await process_frame
	# Without an owned pack there are no tabs, and a last pick from a pack that
	# cannot be picked now falls back to Happy on the quick half.
	store.choose(HASH_B, "wow")
	host = _host()
	row = EndReactions.attach(host, {"run": "solo-run", "pick": true, "store": store, "settings": {"reduced_motion": true}})
	await process_frame
	_check(row._quick_icon.face == "happy", "The quick half never offers a pack face that cannot be picked now")
	row.opener.pressed.emit()
	await process_frame
	_check(row.faces_card.find_child("ReactionTabs", true, false) == null and (row.faces_card.find_child("ReactionGrid", true, false) as GridContainer).get_child_count() == 8, "No pack, no tabs: the card is as before")
	row.close_faces()
	host.queue_free()
	await process_frame
	host = _host()
	row = EndReactions.attach(host, {"run": "solo-run-2", "pick": true, "store": store, "packs": ["big_feelings"], "settings": {"reduced_motion": true}})
	await process_frame
	_check(row._quick_icon.face == "wow", "With its pack owned, the last pack face stays on the quick half")
	host.queue_free()
	await process_frame
	# A friend's pack face shows anywhere, owned or not.
	host = _host()
	row = EndReactions.attach(host, {"friend": {"face": "crying", "color": "mint", "name": "Sam"}})
	await process_frame
	_check(row != null and row.friend_bubble.face == "crying", "A friend's pack face shows on a phone without the pack")
	host.queue_free()
	await process_frame
	EndReactions.FacesCard._last_tab = ""

## The in-run pill's quick half takes its face through EndReactions.quick_face
## like the end card's, with the pill's own context (sent with the turn), so it
## shows a pack face only while the send would keep it (FacePacks.can_pick).
func _run_pill() -> void:
	PollenSurfaces.set_shared_for_tests(true)
	var path := _path("run-pill")
	Store.use_last("wow", path)
	var state := {"server": true, "view": {"packs": []}}
	FacePacks.source = func() -> Dictionary: return state
	var pill := RunReactions.new()
	pill.store_path = path
	root.add_child(pill)
	await process_frame
	_check(pill.quick_face == Store.DEFAULT_FACE and pill._quick_icon.face == Store.DEFAULT_FACE and not FacePacks.can_pick("wow"), "The in-run quick half shows Happy while the last pack face cannot be sent")
	state.view = {"packs": ["big_feelings"]}
	pill.hide()
	pill.show()
	await process_frame
	_check(pill.quick_face == "wow" and pill._quick_icon.face == "wow" and FacePacks.can_pick("wow"), "With its pack owned, the last pack face is on the in-run quick half")
	var sent: Array = []
	pill.reacted.connect(func(face: String) -> void: sent.append(face))
	pill.quick.pressed.emit()
	_check(sent == ["wow"], "Its quick half sends that pack face")
	state.server = false
	pill.hide()
	pill.show()
	await process_frame
	_check(pill.quick_face == Store.DEFAULT_FACE and pill._quick_icon.face == Store.DEFAULT_FACE and not FacePacks.can_pick("wow"), "A server that takes no pack faces turns the shown pack face back to Happy")
	pill.queue_free()
	await process_frame

func _refused_turn() -> void:
	_clear_default_store()
	# The phone believes it owns both packs and the server takes pack faces.
	FacePacks.source = func() -> Dictionary: return {"server": true, "view": {"packs": ["garden_faces", "big_feelings"]}}
	PollenSurfaces.set_shared_for_tests(true)
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	boundary.responses.append(_error(403, "face_pack_not_owned"))
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	var track := [{"tick": 12, "id": "dizzy"}, {"tick": 40, "id": "happy"}]
	_check(await coordinator.commit(fixtures["relay-a"], 1, "wow", track), "A turn refused for an unowned pack face goes through without it")
	var posts: Array = boundary.requests.filter(func(request: Dictionary) -> bool: return request.method == HTTPClient.METHOD_POST)
	_check(posts.size() == 2, "Sent twice: once refused, once without the face")
	if posts.size() == 2:
		var first: Dictionary = posts[0].body
		var again: Dictionary = posts[1].body
		_check(first.end_reaction == "wow" and first.run_reactions.size() == 2, "The first send carried the pack faces")
		_check(not again.has("end_reaction") and again.run_reactions == [{"tick": 40, "id": "happy"}], "The second drops only the pack faces")
		_check(Canonical.same(first.recording, again.recording) and again.tries == 1 and first.idempotency_key != again.idempotency_key and boundary.all_posts_persisted, "Same recording and tries, a new key, saved before it is sent")
	_check(coordinator.pending().is_empty() and Store.new().kept(str(fixtures["relay-a"].recording_hash)).is_empty(), "Nothing waits, and no face is kept for the turn")
	# A server from before the pack faces refuses the face it does not know: the same resend.
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	boundary.responses.append(_error(400, "invalid_end_reaction"))
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	_check(await coordinator.commit(fixtures["relay-a"], 0, "proud"), "An older server's refusal of a pack face also resends without it")
	var old_posts: Array = boundary.requests.filter(func(request: Dictionary) -> bool: return request.method == HTTPClient.METHOD_POST)
	_check(old_posts.size() == 2 and old_posts[0].body.end_reaction == "proud" and not old_posts[1].body.has("end_reaction"), "The second send has no face")
	# A pack face that cannot be picked now is never sent.
	FacePacks.source = func() -> Dictionary: return {"server": true, "view": {"packs": ["garden_faces"]}}
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	_check(await coordinator.commit(fixtures["relay-a"], 0, "wow", [{"tick": 12, "id": "wink"}, {"tick": 20, "id": "crying"}]), "A turn with a face from a pack not owned goes through")
	var sent: Dictionary = boundary.requests.filter(func(request: Dictionary) -> bool: return request.method == HTTPClient.METHOD_POST)[0].body
	_check(not sent.has("end_reaction") and sent.run_reactions == [{"tick": 12, "id": "wink"}], "Only faces that can be picked now are sent")
	FacePacks.source = Callable()
	PollenSurfaces.set_shared_for_tests(null)
	# Any other refusal, or one for a turn without pack faces, is held as before.
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	boundary.responses.append(_error(403, "face_pack_not_owned"))
	_check(not await coordinator.commit(fixtures["relay-a"], 0, "happy"), "Without a pack face the refusal is not retried")
	_check(boundary.requests.filter(func(request: Dictionary) -> bool: return request.method == HTTPClient.METHOD_POST).size() == 1 and coordinator.pending().held, "It waits, held, as any refusal")
	_clear_default_store()

func _headers() -> void:
	for case: Array in [[HTTPClient.METHOD_GET, "/v2/capabilities", true], [HTTPClient.METHOD_GET, "/v1/room-inbox", true], [HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM, true],
		[HTTPClient.METHOD_POST, "/v2/rooms/" + ROOM + "/turns", true], [HTTPClient.METHOD_GET, "/v2/rooms/" + ROOM + "/end-reactions", true],
		[HTTPClient.METHOD_POST, "/v2/rooms/join", false], [HTTPClient.METHOD_GET, "/v1/friends", false], [HTTPClient.METHOD_POST, "/v2/rooms/" + ROOM + "/fork", false]]:
		_check(RoomsApi.capability_headers(case[0], case[1]).has(RoomsApi.FACE_PACKS_HEADER) == case[2], "%s says it draws pack faces: %s" % [case[1], case[2]])
