extends "res://tests/test_online_scenarios.gd"
## The live socket on two phones against a harness server that offers it:
## a turn reaches the waiting friend with one read and no poll, the room page
## polls at the safety pace while the socket is up and at today's pace while
## it is down, a reconnect catches up, and a friend's hosted room shows on an
## open Friends page at once.
const LiveConnection = preload("res://services/live_connection.gd")
const RefreshSchedule = preload("res://services/refresh_schedule.gd")

func scenarios() -> Array[Callable]:
	return [_turn_reaches_the_waiting_friend, _socket_drop_falls_back_and_catches_up, _hub_reads_on_a_hint, _hosted_room_shows_on_friends]

func suite_name() -> String:
	return "Online live"

func _begin(name: String) -> void:
	await h.begin(name)
	h.server.live_enabled = true
	host = h.host
	guest = h.guest

## Frames until `condition` holds or `limit_ms` of wall time passes (the
## socket's own delays are real time).
func _until(condition: Callable, limit_ms: int = 8000) -> bool:
	var deadline := Time.get_ticks_msec() + limit_ms
	while not condition.call():
		if Time.get_ticks_msec() > deadline: return false
		await h.frames(1)
	return true

func _room_reads(device: Node, room: String) -> int:
	return device.api.requests.filter(func(entry: Dictionary) -> bool: return entry.method == HTTPClient.METHOD_GET and entry.path == "/v2/rooms/" + room).size()

func _turn_reaches_the_waiting_friend() -> void:
	await _begin("live: a turn reaches the waiting friend")
	var room: String = await h.hosted_and_joined()
	h.check(await _until(func() -> bool: return host.app.live_connection.healthy() and guest.app.live_connection.healthy()), "both phones hold a live socket")
	h.check(guest.child().refresh_schedule._interval == LiveConnection.SAFETY_POLL_MS, "a healthy socket slows the room poll to the safety pace")
	var reads := _room_reads(guest, room)
	await h.step("host plays stage 1 A", func(): await h.take_turn(host))
	h.check(await _until(func() -> bool: return guest.child().journey.my_turn(), 3000), "the friend sees their turn with no poll and no nudge")
	h.check(_room_reads(guest, room) == reads + 1, "one read for one hint (%d)" % [_room_reads(guest, room) - reads])
	await h.step("guest plays stage 1 B", func(): await h.take_turn(guest))
	await h.step("guest plays stage 2 A", func(): await h.take_turn(guest))
	h.check(await _until(func() -> bool: return host.child() != null and host.child().journey.my_turn(), 3000), "the host sees their turn the same way")
	await h.step("host plays stage 2 B", func(): await h.take_turn(host))
	h.check(h.server.room_state(room) == "complete", "the room finished on the server")
	h.check(h.server.live_hints >= 4, "the server sent a hint per change (%d)" % h.server.live_hints)
	await h.finish()

func _socket_drop_falls_back_and_catches_up() -> void:
	await _begin("live: a dropped socket falls back and catches up")
	var room: String = await h.hosted_and_joined()
	h.check(await _until(func() -> bool: return guest.app.live_connection.healthy()), "the guest holds a live socket")
	h.server.drop_live_sockets()
	await h.frames(2)
	h.check(not guest.app.live_connection.healthy(), "a server deploy drops the socket")
	h.check(guest.child().refresh_schedule._interval == RefreshSchedule.ROOM_INTERVAL_MS, "the room poll is back at today's pace at once")
	# The host's turn lands while the guest has no socket: its hint is lost.
	await h.step("host plays stage 1 A", func(): await h.take_turn(host))
	h.check(await _until(func() -> bool: return guest.app.live_connection.healthy(), 8000), "the guest reconnects after a short delay")
	h.check(await _until(func() -> bool: return guest.child().journey.my_turn(), 3000), "the reconnect's catch-up read shows the turn it missed")
	await h.step("guest plays stage 1 B", func(): await h.take_turn(guest))
	await h.finish()

## The hub has no timer: a hint is what tells it a room moved.
func _hub_reads_on_a_hint() -> void:
	await _begin("live: the hub reads on a hint")
	var room: String = await h.hosted_and_joined()
	await h.step("guest goes back to the hub", func(): await h.to_hub(guest))
	h.check(await _until(func() -> bool: return guest.app.live_connection.healthy()), "the hub holds the live socket")
	var status := func() -> String:
		var hub: RefCounted = guest.app.room_hub_flow.inbox
		for entry: Dictionary in (hub.view().rooms if hub != null else []):
			if entry.room_id == room: return str(entry.status)
		return ""
	h.check(status.call() == "waiting_for_their_turn", "the hub lists the room as the host's turn (%s)" % status.call())
	await h.step("host plays stage 1 A", func(): await h.take_turn(host))
	h.check(await _until(func() -> bool: return status.call() == "your_turn", 8000), "the hub shows the guest's turn with no nudge (%s)" % status.call())
	await h.finish()

func _hosted_room_shows_on_friends() -> void:
	await _begin("live: a hosted room shows on Friends")
	h.server.befriend(host.player_id, guest.player_id)
	await h.step("guest opens Friends", func(): await guest.app._show_friends())
	h.check(guest.app.friends_flow.is_open(), "Friends is up")
	h.check(await _until(func() -> bool: return guest.app.live_connection.healthy(), 10000), "Friends opens the live socket")
	var screen: CanvasLayer = guest.app.friends_flow.screen
	var joinable := func() -> bool:
		var rows: Array = screen.client.view().get("friends", [])
		return not rows.is_empty() and rows[0].get("join_available", false)
	h.check(not joinable.call(), "no room yet")
	await h.step("host opens the hub", func(): h.open_hub(host))
	var started := Time.get_ticks_msec()
	await h.step("host hosts for friends", func(): h.host_room(host, "friends"))
	h.check(await _until(joinable, 5000), "the friend's Friends page shows the room without waiting for its minute")
	h.check(Time.get_ticks_msec() - started < 20000, "well inside the old minute (%d ms)" % (Time.get_ticks_msec() - started))
	await h.step("guest leaves Friends", func(): guest.app.friends_flow.close())
	await h.finish()
