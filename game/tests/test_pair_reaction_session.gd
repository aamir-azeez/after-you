extends SceneTree
const Session = preload("res://services/relay_online_session.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Spec = preload("res://tests/test_pair_reaction_controller.gd")
const ReactionPanel = preload("res://presentation/pair_reaction_panel.gd")

class RefreshPreview:
	extends "res://relay_preview.gd"
	var rebuilt := 0
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func _show_ready() -> void: rebuilt += 1

class Api:
	extends Node
	var player_id := Spec.HOST
	var device_token := "synthetic-not-a-credential"
	var busy := false
	var room: Dictionary = {}
	var archived: Dictionary = {}
	var reactions: RefCounted
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		busy = true
		var result: Dictionary
		if path == "/v2/rooms/" + Spec.ROOM:
			result = {"ok": true, "data": room.duplicate(true)}
		elif "/pairs/" in path:
			result = {"ok": true, "data": archived.duplicate(true)}
		else:
			result = await reactions.request({"method": method, "path": path, "body": body, "owner_player_id": player_id, "identity_epoch": 1})
		busy = false
		return result

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for chapter: String in Registry.keys(): await _chapter(chapter)
	print("After You pair reaction session: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _chapter(chapter: String) -> void:
	var disk := Spec.Harness.new()
	var reactions := Spec.Harness.new()
	var api := Api.new()
	api.reactions = reactions
	api.room = _room(chapter)
	root.add_child(api)
	var session := Session.new(api, disk.identity, disk)
	session.room_ids()
	session.capabilities = {"mutations_enabled": true, "preset_reactions_enabled": true}
	session.pair_reaction_store = reactions
	_check(await session.open_room(Spec.ROOM), chapter + " complete checkpoint passes real native coordinator")
	var accepted_before := Canonical.digest(disk.values)
	var snapshot_before := Canonical.digest(session.coordinator.snapshot())
	var photos_before := session.replay_photo_turns(0, session.chapter_pairs()[0])
	var reference: Dictionary = session.pair_reaction_reference(0)
	_check(reference.pair_id == "p0-0" and reference.a_hash == session.chapter_pairs()[0].a.recording_hash, "active pair reference uses exact accepted chain")
	_check(session.pair_reaction_reference(-1).is_empty() and session.pair_reaction_reference(2).is_empty(), "out-of-range/incomplete pair cannot produce action reference")
	var controller := session.create_pair_reaction_controller()
	_check(controller.bind(reference), "session controller binds verified target")
	reactions.server_state = {"schema_version": 1, "room_id": reference.room_id, "pair_id": reference.pair_id, "a_hash": reference.a_hash, "b_hash": reference.b_hash, "reactions": []}
	_check(await controller.refresh() and await controller.choose("love"), "real session routes optional read and explicit preset")
	_check(Canonical.digest(disk.values) == accepted_before and Canonical.digest(session.coordinator.snapshot()) == snapshot_before, "reaction does not rewrite gameplay/lobby proof or snapshot")
	_check(session.replay_photo_turns(0, session.chapter_pairs()[0]) == photos_before, "photo contribution ownership/hashes remain exact")
	await _manual_and_paused_refresh(session, reactions, reference)
	session.capabilities.preset_reactions_enabled = false
	_check(not controller.can_choose() and await controller.refresh(), "independent preset capability pauses mutation only")
	# Simulate a later current branch while selecting an archived pair explicitly.
	# The archived checkpoint is genuinely derived and replay-verified by fetch_pair.
	var pair: Dictionary = session.chapter_pairs()[0]
	var engine: Script = Registry.simulation_script(chapter)
	var derived: Dictionary = engine.derive_checkpoint(Registry.definition(chapter), Registry.initial_checkpoint(chapter), pair.a, pair.b)
	api.archived = {"pair_id": "p0-0", "branch": 0, "stage_index": 0, "a": pair.a, "b": pair.b, "checkpoint": derived.checkpoint}
	api.room.branch = 1
	api.room.completed_pair_ids = ["p1-0", "p1-1"]
	api.room.revision += 1
	_check(await session.coordinator.refresh(), "later active branch snapshot remains supported")
	var archived: Dictionary = await session.archived_pair_reaction_reference("p0-0")
	_check(archived == reference and session.pair_reaction_reference(0).pair_id == "p1-0", "archived reference never borrows current branch ID")
	api.archived.a.recording_hash = "f".repeat(64)
	_check((await session.archived_pair_reaction_reference("p0-0")).is_empty(), "tampered archived replay cannot authorize a reaction reference")
	session.invalidate_identity()
	_check(not controller.can_choose() and controller.state().is_empty(), "session identity invalidation reaches optional controller")
	api.queue_free()
	await process_frame

func _manual_and_paused_refresh(session: RefCounted, reactions: RefCounted, reference: Dictionary) -> void:
	var screen := RefreshPreview.new()
	screen.online_session = session
	screen.journey = session.coordinator
	root.add_child(screen)
	var panel := ReactionPanel.new()
	screen.add_child(panel)
	panel.size = Vector2(600, 400)
	panel.configure(session, reference, func(text: String, callback: Callable, _primary: bool) -> Button:
		var button := Button.new()
		button.text = text
		button.pressed.connect(callback)
		return button)
	screen.pair_reaction_panel = panel
	panel.service(Time.get_ticks_msec(), true)
	await process_frame
	var previous_calls: int = reactions.calls.size()
	reactions.set_row(reactions.row(Spec.GUEST, "again", 1))
	await screen._online_refresh()
	screen._service_pair_reactions()
	await process_frame
	_check(screen.rebuilt == 0 and reactions.calls.size() == previous_calls + 1, "manual unchanged room refresh queues metadata without rebuilding scene")
	_check(panel.get_node("PairReactionSummary").text.contains("Your friend reacted: Again soon"), "manual refresh displays independent partner metadata")
	screen.mode = "paused"
	screen.replay_pair_index = 0
	screen.replay_cursor = 17
	panel.request_refresh()
	screen._service_pair_reactions()
	await process_frame
	_check(screen.mode == "paused" and screen.replay_cursor == 17 and screen.rebuilt == 0, "paused replay metadata read preserves its cursor and mode")
	previous_calls = reactions.calls.size()
	screen.backgrounded = true
	panel.request_refresh()
	screen._service_pair_reactions()
	_check(reactions.calls.size() == previous_calls, "background screen never polls metadata")
	screen.queue_free()
	await process_frame

func _room(chapter: String) -> Dictionary:
	var level := Registry.definition(chapter)
	var folder := "first_steps" if chapter == Registry.FIRST_STEPS else "v2"
	var checkpoint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + folder + "/final-checkpoint.json"))
	return {"schema_version": 2, "api_version": 2, "room_id": Spec.ROOM, "revision": 5, "branch": 0, "stage_index": 2, "level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level), "host_id": Spec.HOST, "guest_id": Spec.GUEST, "checkpoint": checkpoint, "a_turn_id": null, "completed_pair_ids": ["p0-0", "p0-1"], "invite_code": "A1".repeat(10), "invite_expires_at": "2026-09-21T12:00:00Z", "created_at": "2026-09-14T12:00:00Z", "updated_at": "2026-09-14T12:00:00Z", "active_role": "complete", "first_player_id": null, "active_player_id": null, "player_slot": "p0", "stage_id": "", "recording_a": null, "validation": "structural_client_replay_required"}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
