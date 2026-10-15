extends "res://tests/test_online_scenarios.gd"
## Room history on two phones (replay transfer schema 2): finished attempts leave
## the server once both phones keep them, come back for a restart of a finished
## room, reach a phone recovered without its files through the friend's phone,
## and stay put when one phone runs an older build or offload is off.
const RoomsApi = preload("res://services/rooms_api.gd")
const Store = preload("res://services/history_store.gd")

## This suite's half; test_online_history_more runs the rest (each stays inside CI's per-suite limit).
func scenarios() -> Array[Callable]:
	return [_offload_after_both_keep, _restart_finished_room]

func suite_name() -> String:
	return "Online history"

func _run() -> void:
	# Desktop builds never claim durable storage; these phones stand in for Android ones.
	RoomsApi.history_supported = true
	await super._run()

func _history(on: bool = true) -> void:
	h.server.history_offload_enabled = on

func _kept(device: Node, room: String) -> Dictionary:
	var key: String = str(device.api.base_url).sha256_text()
	return Store.new().index(key, device.player_id, room)

## From the hub's Completed tab, Watch replay on the room (which saves its attempts first).
func _watch(device: Node, room: String) -> void:
	await h.to_hub(device)
	await h.step(device.label + " opens the Completed tab", func(): device.hub()._select_tab("Completed"))
	await h.step(device.label + " taps Watch replay", func(): h.open_room_card(device, room))

func _leave_both(room: String) -> void:
	await h.step("host leaves the room", func(): h.back(host))
	await h.step("guest notices", func(): h.nudge(guest))
	await h.step("guest leaves the room", func(): h.back(guest))
	h.check(h.server.room_state(room) != "in_play", "the room is finished")

## Plays a room to the end and has both phones leave it.
func _finished_room() -> String:
	var room: String = await h.hosted_and_joined()
	await h.play_out(room)
	await _leave_both(room)
	return room

func _offload_after_both_keep() -> void:
	await _begin("history: both phones keep the attempt, the server lets it go")
	_history()
	var room := await _finished_room()
	h.check(h.server.attempt_states(room) == ["offloaded"], "the finished attempt left the server (%s)" % [h.server.attempt_states(room)])
	h.check(h.server.room_state(room) == "transferred", "the finished room keeps only its record")
	for device: Node in [host, guest]: h.check(_kept(device, room).has(0), "%s keeps the attempt" % device.label)
	h.check(not h.server.requests.any(func(entry: Dictionary) -> bool: return str(entry.path).ends_with("/replay-transfer/ack")), "no replay transfer v1 ACK in a history room")
	for device: Node in [host, guest]: await h.check_replays(device, room, "history")
	await h.finish()

func _restart_finished_room() -> void:
	await _begin("history: a finished room restarts from this phone's copy")
	_history()
	var room := await _finished_room()
	# No screen restarts a finished room yet; the room's coordinator does it the
	# way a redo accept does, restoring the attempt first.
	h.check(host.app.relay_session.coordinator.snapshot().get("room_id") == room, "the host's session still holds the finished room")
	var forked := [false]
	await h.step("host restarts the room", func(): forked[0] = await host.app.relay_session.coordinator.fork(0))
	h.check(forked[0] and h.server.room_state(room) == "in_play", "the restart sent the attempt back and forked (%s)" % h.server.room_state(room))
	h.check(h.server.attempt_states(room) == ["held"], "the attempt is held again while only the host confirmed it")
	await h.to_hub(host)
	await h.step("guest refreshes", func(): h.nudge(guest))
	await h.play_out(room)
	await _leave_both(room)
	h.check(h.server.attempt_states(room) == ["offloaded", "offloaded"], "both attempts left the server (%s)" % [h.server.attempt_states(room)])
	var app: Node = guest.app
	await _watch(guest, room)
	var parts: Array = app.shared_replays.listed("chapter:" + room) if app.shared_replays != null else []
	h.check(parts.size() == 4, "the guest's replays list both attempts' parts (%d)" % parts.size())
	var opened := [{}]
	await h.step("guest opens the first attempt's last part", func(): opened[0] = await app.shared_replays.open_memory("chapter:" + room, "p0-1"))
	h.check(not opened[0].is_empty(), "a part the server let go plays from the guest's copy")
	await h.step("guest leaves replays", func(): h.back(guest))
	await h.finish()

func _new_phone_asks_friend() -> void:
	await _begin("history: a recovered phone gets its attempts back from the friend's phone")
	_history()
	var room := await _finished_room()
	await h.step("guest recovers onto a new phone", func(): guest.new_phone())
	h.check(_kept(guest, room).is_empty(), "the new phone has no attempts")
	await _watch(guest, room)
	var wanted: Array = h.server.rooms[room].history.attempts.map(func(record: Dictionary) -> Array: return record.wanted)
	h.check(wanted == [[guest.player_id]], "the new phone asked for the attempt (%s)" % [wanted])
	await h.step("guest leaves replays", func(): h.back(guest))
	await _watch(host, room)
	h.check(h.server.attempt_states(room) == ["held"], "the host's phone sent the attempt back")
	await h.step("host leaves replays", func(): h.back(host))
	await h.to_hub(guest)
	await h.check_replays(guest, room, "recovered phone")
	h.check(_kept(guest, room).has(0), "the recovered phone keeps the attempt now")
	h.check(h.server.attempt_states(room) == ["offloaded"], "and the server let it go again")
	await h.finish()

func _older_build_keeps_rooms() -> void:
	await _begin("history: a friend on an older build keeps today's behaviour")
	_history()
	guest.force_quit()
	guest.legacy_060 = true
	guest.boot()
	var room := await _finished_room()
	h.check(h.server.attempt_states(room) == ["held"], "nothing leaves while one phone never said it keeps attempts")
	h.check(h.server.rooms[room].history.members.get(guest.player_id, 0) == 0, "the older phone never claimed support")
	h.check(h.server.room_state(room) == "complete", "the room keeps every row")
	await h.check_replays(host, room, "older friend")
	await h.finish()

func _offload_off() -> void:
	await _begin("history: offload off on the server")
	_history(false)
	var room := await _finished_room()
	h.check(h.server.attempt_states(room) == ["held"] and h.server.room_state(room) == "complete", "nothing leaves while offload is off")
	for device: Node in [host, guest]: h.check(_kept(device, room).has(0), "%s still keeps the attempt" % device.label)
	h.check(not h.server.requests.any(func(entry: Dictionary) -> bool: return str(entry.path).ends_with("/ack") and entry.status == 503), "no phone asks to confirm while offload is off")
	for device: Node in [host, guest]: await h.check_replays(device, room, "offload off")
	await h.finish()
