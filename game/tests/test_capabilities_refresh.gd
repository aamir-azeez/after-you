extends SceneTree
## The launch and resume capabilities read (services/capabilities_refresh.gd):
## it reads once the player is known and once per player; before its first
## answer buttons show as if they work (pending); a failed read goes again on
## 2, 5, 15, 30 seconds and a minute, never while the app is behind or the
## screen up does not let it, then waits for something to change (a resume, the
## phone coming back online, a new player); while the phone reads as offline it
## waits for the probe; the phone coming back online reads at once; coming back to the
## front reads again only once the last good read is five minutes old; a read
## not wanted now (the room session busy) is asked again soon without counting
## as a failure; a tap before the first answer waits for it, briefly.
const Refresh = preload("res://services/capabilities_refresh.gd")
const Connectivity = preload("res://services/connectivity.gd")
const Session = preload("res://services/relay_online_session.gd")

## A server whose capabilities answer waits while `hold` is on (a slow network).
class HeldApi extends Node:
	signal release
	var player_id := "CCCCCCCCCCCCCCCCCCCCCC"
	var device_token := "synthetic-device-token"
	var base_url := "https://capabilities-refresh.invalid"
	var hold := false
	var asked := 0
	func configured() -> bool: return true
	func request_json(_method: int, path: String, _body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		if path == "/v2/capabilities": asked += 1
		while hold: await release
		if path == "/v2/capabilities": return {"ok": true, "status": 200, "data": {"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true, "validation": "structural_client_replay_required", "chapters": []}}
		return {"ok": false, "status": 404, "code": "not_found"}

class SessionStore extends RefCounted:
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary: return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = value.duplicate(true)
		return {"ok": true}

var checks := 0
var failures := 0
var now := 0
var answers: Array = []
var reads := 0
var allowed := true

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _read() -> Variant:
	reads += 1
	await process_frame
	return answers.pop_front() if not answers.is_empty() else true

## Moves the clock to `at` and lets a due read run and land.
func _at(refresh: Node, at: int) -> void:
	now = at
	refresh.tick()
	await process_frame
	await process_frame

## The launch read out while a screen asks for capabilities (Friends, Duels,
## Play): the screen waits for that read and takes its answer, never a busy
## refusal, and Play's wait (until_capabilities_read) lasts until it lands.
func _shared_read() -> void:
	var api := HeldApi.new()
	root.add_child(api)
	var session: RefCounted = Session.new(api, func() -> Dictionary: return {"ready": true, "player_id": api.player_id, "epoch": 1}, SessionStore.new())
	api.hold = true
	var first := {"done": false, "ok": false}
	var second := {"done": false, "ok": false}
	var launch := func() -> void:
		first.ok = await session.load_capabilities(func() -> bool: return true)
		first.done = true
	var screen := func() -> void:
		second.ok = await session.load_capabilities()
		second.done = true
	launch.call()
	await process_frame
	screen.call()
	await process_frame
	_check(not second.done and session.reading_capabilities_only() and api.asked == 1, "A screen asking while the launch read is out waits for it, and Play's wait holds")
	api.hold = false
	api.release.emit()
	for i in range(4): await process_frame
	_check(first.done and second.done and first.ok and second.ok and api.asked == 1 and not session.capabilities.is_empty(), "Both take the one answer: %s %s, %d asked" % [first, second, api.asked])
	api.free()

func _run() -> void:
	var state: RefCounted = Connectivity.new()
	Connectivity.use_shared(state)
	var refresh: Node = Refresh.new()
	refresh.read = _read
	refresh.may_read = func() -> bool: return allowed
	refresh.clock = func() -> int: return now
	root.add_child(refresh)
	refresh.set_process(false)
	await process_frame
	_check(not refresh.pending() and not refresh.known(), "Before a player is known nothing is pending or read")
	answers = [false, false, false, false, false, false, true]
	refresh.identity_ready("server|PLAYER")
	_check(refresh.pending(), "Once the player is known, buttons show as if they work")
	await _at(refresh, 0)
	_check(reads == 1 and refresh.failures() == 1 and refresh.pending(), "It reads at once; a failure keeps it pending")
	var at := 0
	for wait: int in Refresh.RETRY_MS:
		await _at(refresh, at + wait - 1)
		var before := reads
		await _at(refresh, at + wait)
		at += wait
		_check(reads == before + 1, "The next read waits %d ms (%d reads)" % [wait, reads])
	await _at(refresh, at + 3600000)
	_check(reads == 6 and refresh.pending(), "After those, an hour later, nothing more: a server answering with errors gets six reads")
	at += 3600000
	refresh.resumed()
	await _at(refresh, at)
	_check(reads == 7 and refresh.known() and not refresh.pending() and refresh.failures() == 0, "The next resume reads again; an answer: known, no longer pending")
	refresh.identity_ready("server|PLAYER")
	await _at(refresh, at + 1)
	_check(reads == 7, "The same player again reads nothing more")
	# Resume: once the last good read is five minutes old.
	refresh.resumed()
	await _at(refresh, at + 1000)
	_check(reads == 7, "Back in front a minute later: no read")
	now = at + Refresh.RESUME_GAP_MS
	refresh.resumed()
	await _at(refresh, now)
	_check(reads == 8, "Back in front five minutes later: one read")
	at = now
	# A new player reads again; failures while offline wait for the phone to come back.
	answers = [false]
	refresh.identity_ready("server|OTHER")
	await _at(refresh, at)
	_check(reads == 9 and refresh.pending(), "A new player reads at once")
	state.force(false)
	await _at(refresh, at + 600000)
	_check(reads == 9, "While offline its own retries wait (the probe asks)")
	state.note_reached()
	await _at(refresh, at + 600001)
	_check(reads == 10 and refresh.known(), "Back online it reads at once")
	at += 600001
	# Behind, or a screen that does not let it: nothing runs until it may.
	answers = [false, true]
	refresh.identity_ready("server|THIRD")
	allowed = false
	await _at(refresh, at)
	_check(reads == 10, "A screen that does not let it: no read")
	allowed = true
	refresh.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await _at(refresh, at + 1)
	_check(reads == 10 and not refresh.is_processing(), "Behind: no read and no frame work")
	refresh.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _at(refresh, at + 2)
	_check(reads == 11 and refresh.failures() == 1, "In front again it reads")
	# Not now (the room session busy): asked again soon, not a failure.
	answers = [null]
	await _at(refresh, at + 2 + 2000)
	_check(reads == 12 and refresh.failures() == 1, "A read not wanted now is no failure")
	await _at(refresh, at + 2 + 2000 + Refresh.NOT_NOW_MS)
	_check(reads == 13 and refresh.known(), "It goes again soon after")
	# A tap before the first answer waits for it.
	answers = [true]
	refresh.identity_ready("server|FOURTH")
	var known: bool = await refresh.until_read()
	_check(known and reads == 14, "A tap before the first answer waits for it and opens")
	answers = [false]
	refresh.identity_ready("server|FIFTH")
	known = await refresh.until_read()
	_check(not known and refresh.pending() and reads == 15, "One that fails goes on without it")
	refresh.free()
	await _shared_read()
	Connectivity.use_shared(null)
	print("AFTER YOU CAPABILITIES REFRESH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
