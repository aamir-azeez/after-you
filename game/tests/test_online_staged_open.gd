extends "res://tests/test_world_fingerprint.gd"
## Main's online room open (main.gd _enter_online_relay) builds the room's
## world over frames behind the room screen's own loading card
## (relay_preview.staged_room_open), as a solo chapter open does behind its
## card. It built the whole world in the frame Main added the screen.
## - In the frame the screen is added it is still building and shows its
##   loading card; the build itself starts in the next frame.
## - Built staged, the room's world is the same, node for node (the world
##   fingerprint), as a room screen built at once, and the room's view (ready
##   or waiting) follows with the world the build made: its stage is built
##   once, straight to the room's stage, never the first stage and then the
##   room's in one frame.
## - Back during the build waits for it, then leaves the room as before.
## - A room screen made any other way builds at once, as before.
const Preview = preload("res://relay_preview.gd")
const Session = preload("res://services/relay_online_session.gd")
const Online = preload("res://tests/test_relay_online.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "40173cc9d5bee436613f7a"
## As tests/test_staged_build.gd: the most nodes one step may add.
const MOST_NODES_PER_STEP := 300
## The sessions' identities, kept alive while their screens are (a session holds only their callable).
var _identities: Array = []

func _suite() -> String:
	return "online_staged_open"

func _run() -> void:
	# Stage at every step, so the screen builds over frames on any machine.
	Preview.staged_build_usec = 1
	await _room(Registry.RELAY, 0)
	await _room(Registry.RELAY, 1)
	await _room(Registry.WISHING_WELL, 0)
	await _room(Registry.LIGHTHOUSE_V2, 0)
	await _room("turn-of-the-tide@2", 0)
	await _back_mid_build(Registry.RELAY)
	Preview.staged_build_usec = 0
	print("ONLINE STAGED OPEN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))

## The room as the server sends it to the host: the first stage of any
## chapter before the friend joins (the host's turn), or the Relay's second
## stage (its test fixtures), the friend joined and the friend's turn.
func _snapshot(key: String, index: int) -> Dictionary:
	var d := Registry.descriptor(key)
	var level := Registry.definition(key)
	var room := {"api_version": 2, "schema_version": 2, "room_id": ROOM, "revision": 2 * index, "branch": 0, "stage_index": index,
		"level_id": d.level_id, "level_version": d.level_version, "definition_hash": d.definition_hash,
		"host_id": HOST, "guest_id": GUEST if index > 0 else null, "checkpoint": Registry.initial_checkpoint(key) if index == 0 else _fixture("relay-checkpoint"),
		"a_turn_id": null, "completed_pair_ids": ["p0-0"] if index > 0 else [], "invite_expires_at": "2026-12-21T12:00:00Z",
		"created_at": "2026-10-31T12:00:00Z", "updated_at": "2026-10-31T12:00:00Z", "active_role": "a", "first_player_id": HOST if index == 0 else GUEST,
		"active_player_id": HOST if index == 0 else GUEST, "player_slot": "p0", "stage_id": level.stages[index].id, "recording_a": null,
		"validation": "structural_client_replay_required", "invite_code": "A1".repeat(10)}
	return room

func _answer(request: Dictionary, key: String, index: int) -> Dictionary:
	var d := Registry.descriptor(key)
	if request.path == "/v2/capabilities":
		return {"ok": true, "status": 200, "data": {"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true, "validation": "structural_client_replay_required",
			"chapters": [{"level_id": d.level_id, "level_version": d.level_version, "definition_hash": d.definition_hash, "premium": d.premium, "simulation_version": d.simulation_version, "recording_version": d.recording_version}]}}
	if request.path == "/v2/rooms" and request.method == HTTPClient.METHOD_GET:
		return {"ok": true, "status": 200, "data": {"rooms": [_snapshot(key, index)]}}
	if request.path == "/v2/rooms/" + ROOM:
		return {"ok": true, "status": 200, "data": _snapshot(key, index)}
	return {"ok": false, "status": 404, "code": "not_found", "error": "Synthetic missing feature."}

## A room screen for key's room at stage index, as Main adds it (staged or not).
func _screen(key: String, index: int, staged: bool, label: String) -> Node:
	var api := Online.FakeApi.new()
	api.responder = _answer.bind(key, index)
	root.add_child(api)
	var identity := Online.Identity.new()
	_identities.append(identity)
	var session := Session.new(api, identity.get_value, Online.MemoryStore.new())
	var opened: bool = await session.load_lobby() and await session.open_room(ROOM)
	if not _check(opened, label + ": the synthetic room opens"): return null
	var screen := Preview.new()
	screen.online_session = session
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true}
	screen.staged_room_open = staged
	screen.set_meta("api", api)
	return screen

func _room(key: String, index: int) -> void:
	var label := "%s room at stage %d" % [key, index + 1]
	var direct_view := _viewport()
	var direct: Node = await _screen(key, index, false, label + " at once")
	var staged_view := _viewport()
	var staged: Node = await _screen(key, index, true, label + " staged")
	if direct == null or staged == null: return
	direct_view.add_child(direct)
	_check(not direct.building() and direct.mode in ["ready", "online_waiting"], label + ": a room screen made without Main's request builds at once (%s)" % direct.mode)
	staged_view.add_child(staged)
	var first_step: int = staged.world.find_children("*", "", true, false).size()
	_check(staged.building() and staged.mode == "loading", label + ": in the frame it is added, the room screen waits in loading while its world builds")
	_check(staged.world.build_budget_usec == 0 and first_step <= MOST_NODES_PER_STEP, label + ": the build starts in the next frame, none of it in the frame the screen is added (%d world nodes)" % first_step)
	_check(staged.overlay.find_children("*", "Button", true, false).size() >= 1, label + ": its loading card, with Back, is up in that frame")
	var guard := 0
	var terrain_id := 0
	var drawn_half_built := false
	while (staged.building() or staged.mode == "loading") and guard < 900:
		await process_frame
		guard += 1
		if staged.building() and is_instance_valid(staged.world.terrain): terrain_id = staged.world.terrain.get_instance_id()
		if staged.world.build_budget_usec > 0 and staged.world.visible: drawn_half_built = true
	_check(not staged.building() and staged.mode == direct.mode and guard >= 2, label + ": the room's view follows the build (%d frames, %s)" % [guard, staged.mode])
	_check(not drawn_half_built and staged.world.visible == direct.world.visible, label + ": the half-built world is never drawn, and shows once whole")
	# Worlds that name the stage they show (journey worlds) must show the room's.
	var shown: Variant = staged.world.get("displayed_stage_id")
	_check(staged.world.terrain.get_instance_id() == terrain_id and (shown == null or str(shown) == str(Registry.definition(key).stages[index].id)), label + ": the room's own stage is built once, staged, and kept")
	_check(staged.world.process_mode == direct.world.process_mode, label + ": the world runs again once whole")
	guard = 0
	while (staged.world.scenery_folding() or direct.world.scenery_folding()) and guard < 900:
		await process_frame
		guard += 1
	_check(_fingerprint(staged.world, key, true, "room").hash == _fingerprint(direct.world, key, true, "room").hash, label + ": the same world as a room screen built at once")
	for screen: Node in [direct, staged]: (screen.get_meta("api") as Node).queue_free()
	direct_view.free()
	staged_view.free()
	await process_frame

## Back during the build waits for it; the room then closes as Back always did.
func _back_mid_build(key: String) -> void:
	var label := key + " room back"
	var view := _viewport()
	var screen: Node = await _screen(key, 0, true, label)
	if screen == null: return
	var closed := [0]
	screen.closed.connect(func() -> void: closed[0] += 1)
	view.add_child(screen)
	await process_frame
	_check(screen.building(), label + ": still building")
	screen._leave()
	_check(screen.mode == "loading" and not screen._leaving and screen._leave_after_build and closed[0] == 0, label + ": Back waits for the build instead of leaving a half-built world")
	var guard := 0
	while screen.building() and guard < 900:
		await process_frame
		guard += 1
	_check(closed[0] == 1 and screen._leaving, label + ": once whole, the room closes as Back asked")
	(screen.get_meta("api") as Node).queue_free()
	view.free()
	await process_frame
