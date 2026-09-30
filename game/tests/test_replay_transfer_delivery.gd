extends SceneTree
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

class Main extends "res://main.gd":
	var test_identity := {"ready": true, "player_id": HOST, "epoch": 1}
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _exit_tree() -> void: pass
	func _relay_identity() -> Dictionary: return test_identity.duplicate(true)

class Api extends Node:
	var busy := false

class Room extends RefCounted:
	var value := {"room_id": ROOM, "revision": 5, "active_role": "complete"}
	var unresolved: Dictionary = {}
	func snapshot() -> Dictionary: return value.duplicate(true)
	func pending() -> Dictionary: return unresolved.duplicate(true)

class Session extends RefCounted:
	var coordinator := Room.new()
	var capabilities := {"replay_transfer_version": 1}
	var held := false
	var standalone := true
	var calls: Array = []
	func busy() -> bool: return held
	func standalone_room_proven(_room: String) -> bool: return standalone
	func sync_complete_replay(room: String) -> Dictionary:
		calls.append(room)
		return {"ok": true, "acknowledged": true}

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _app() -> Main:
	var app := Main.new()
	app.api = Api.new()
	app.add_child(app.api)
	app.relay_session = Session.new()
	app.mode = "relay_rooms"
	root.add_child(app)
	return app

func _run() -> void:
	var app := _app()
	await app._deliver_completed_replay()
	await app._deliver_completed_replay()
	_check(app.relay_session.calls == [ROOM], "Completed room leaving play gets one delivery attempt, not a recurring poll")
	app.relay_session.coordinator.value.revision += 1
	await app._deliver_completed_replay()
	_check(app.relay_session.calls.size() == 2, "A genuinely newer completed revision can deliver its new archive")
	app.test_identity.player_id = "GGGGGGGGGGGGGGGGGGGGGG"
	await app._deliver_completed_replay()
	_check(app.relay_session.calls.size() == 3, "A different participant gets an independent delivery attempt")
	app.queue_free()
	for condition: String in ["incomplete", "story", "background", "playback", "pending", "disabled"]:
		app = _app()
		if condition == "incomplete": app.relay_session.coordinator.value.active_role = "b"
		if condition == "story": app.relay_session.standalone = false
		if condition == "background": app.application_backgrounded = true
		if condition == "playback": app.mode = "shared_replay"
		if condition == "pending": app.relay_session.coordinator.unresolved = {"body": {"idempotency_key": "original-key"}}
		if condition == "disabled": app.relay_session.capabilities.replay_transfer_version = 0
		await app._deliver_completed_replay()
		_check(app.relay_session.calls.is_empty() and app._shared_archive_attempts.is_empty(), "Automatic transfer is not started for " + condition)
		app.queue_free()
	for condition: String in ["identity", "navigation", "session", "snapshot"]:
		app = _app()
		var original: RefCounted = app.relay_session
		app.api.busy = true
		get_tree_change.call_deferred(app, condition)
		await app._deliver_completed_replay()
		_check(original.calls.is_empty(), "Context change while waiting for the API cancels transfer: " + condition)
		_check(app._shared_archive_attempts.is_empty(), "Cancelled admission never consumes an attempt: " + condition)
		app.queue_free()
	await process_frame
	print("REPLAY TRANSFER DELIVERY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func get_tree_change(app: Main, condition: String) -> void:
	# This runs after the real method suspends on its bounded wait timer.
	if condition == "identity": app.test_identity.epoch += 1
	if condition == "navigation": app.mode = "shared_memories"
	if condition == "session": app.relay_session = Session.new()
	if condition == "snapshot": app.relay_session.coordinator.value.revision += 1
	app.api.busy = false
