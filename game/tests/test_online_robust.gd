extends "res://tests/test_online_scenarios.gd"
## Room moments that used to strand a player: a room read that lands while the
## phone is unfocused or in the background, New room on a finished room while
## a room read is out, the app paused while Host or a friend's Join waits for
## its reply, and an earlier-island invitation code the server refuses.

func scenarios() -> Array[Callable]:
	return [_read_lands_unfocused.bind(false), _read_lands_unfocused.bind(true), _new_room_during_read, _pause_while_hosting, _pause_while_joining_from_friends, _earlier_island_join_refused]

func suite_name() -> String:
	return "Online robustness"

## Frames until `condition` holds, bounded by the clock like the harness's settle().
func _until(condition: Callable, limit_ms: int = 10000) -> bool:
	var deadline := Time.get_ticks_msec() + limit_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await h.frames(1)
	return condition.call()

## The guest waits for the host's last turn. The read that would show the
## finished room is out when the guest pulls down the notification shade
## (focus only) or switches away (paused); its reply lands then. Back in
## front, the guest's card shows the room finished, not the wait.
func _read_lands_unfocused(paused: bool) -> void:
	await _begin("last turn read lands while " + ("paused" if paused else "unfocused"))
	var room: String = await h.hosted_and_joined()
	await h.step("host takes stage 1 A", func(): await h.take_turn(host))
	await h.step("guest notices", func(): h.nudge(guest))
	await h.step("guest takes stage 1 B", func(): await h.take_turn(guest))
	await h.step("guest takes stage 2 A", func(): await h.take_turn(guest))
	# The guest reads nothing more until this test asks.
	guest.child().refresh_schedule._due += 600000
	await h.step("host notices", func(): h.nudge(host))
	await h.step("host takes the last turn", func(): await h.take_turn(host))
	h.check(h.server.room_state(room) == "complete", "the room finished on the server")
	h.check(guest.child().mode == "online_waiting", "the guest still shows the waiting card before reading")
	guest.api.faults.append({"path": "/v2/rooms/" + room, "method": HTTPClient.METHOD_GET, "kind": "hold"})
	h.nudge(guest)
	h.check(await _until(func() -> bool: return guest.api.held > 0), "the guest's room read is out")
	if paused: guest.background()
	else: guest.viewport.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await h.frames(4)
	guest.api.release_held()
	# The reply is checked (on a worker) and kept while the phone is away.
	h.check(await _until(func() -> bool: return guest.api.held == 0 and not guest.app.relay_session.busy() and guest.child().journey.chapter_complete()), "the read lands while the phone is away")
	await h.frames(6)
	if paused: guest.foreground()
	else: guest.viewport.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await h.step("a few seconds pass", func(): h.elapse(guest))
	await h.step("a few more seconds pass", func(): h.elapse(guest))
	var child: Node = guest.child()
	h.check(child != null and child.mode == "complete", "the guest's card shows the finished room, not the wait (at %s)" % [child.mode if child != null else "none"])
	await h.finish()

## New room on a finished room's card, tapped while that card's room read is
## out, waits for the read and opens the new room instead of an error.
func _new_room_during_read() -> void:
	await _begin("new room while the finished room is read")
	var room: String = await h.hosted_and_joined()
	await h.play_out(room)
	var device: Node = host if h.current_room(host) == room and host.child().mode == "complete" else guest
	h.check(device.child() != null and device.child().mode == "complete", "a player is on the finished room's card")
	var before: int = h.server.rooms.size()
	device.api.faults.append({"path": "/v2/rooms/" + room, "method": HTTPClient.METHOD_GET, "kind": "hold"})
	h.nudge(device)
	h.check(await _until(func() -> bool: return device.api.held > 0), "the finished room's read is out")
	h.check(h.press(device, "New room"), "New room can be tapped")
	await h.frames(6)
	h.check(device.button("Checking room…") != null and device.button("New room") == null, "New room says it is checking the room while the read is out")
	device.api.release_held()
	await h.step("the read lands", func(): pass)
	var child: Node = device.child()
	h.check(child != null and child.mode != "error", "no error card replaces the finished room (at %s)" % [device.where()])
	h.check(h.server.rooms.size() == before + 1, "exactly one new room is made")
	h.check(child != null and h.current_room(device) != room and not h.current_room(device).is_empty(), "the player is in the new room")
	await h.finish()

## Host a Friends room, and the app goes to the background before the reply
## lands. Back in front, the room opens and is shared with friends.
func _pause_while_hosting() -> void:
	await _begin("pause while hosting")
	await h.step("host opens the hub", func(): h.open_hub(host))
	host.api.faults.append({"path": "/v2/rooms", "method": HTTPClient.METHOD_POST, "kind": "hold"})
	h.host_room(host)
	h.check(await _until(func() -> bool: return host.api.held > 0), "the create request is out")
	host.background()
	await h.frames(4)
	host.api.release_held()
	await h.frames(12)
	host.foreground()
	await _until(func() -> bool: return host.child() != null, 5000)
	await h.step("a moment passes", func(): pass)
	h.check(host.app.mode != "relay_rooms", "the host is not left on the room progress card")
	var room: String = h.current_room(host)
	h.check(not room.is_empty(), "the hosted room opens")
	h.check(h.server.players[host.player_id].get("shared_room") is Dictionary and str(h.server.players[host.player_id].shared_room.get("room_id")) == room, "the Friends room is shared with friends")
	await h.finish()

## Join on a friend's room in Friends, and the app goes to the background while
## the rooms are checked. Back in front, the join goes on into the room.
func _pause_while_joining_from_friends() -> void:
	await _begin("pause while joining from Friends")
	h.server.befriend(host.player_id, guest.player_id)
	await h.step("host opens the hub", func(): h.open_hub(host))
	await h.step("host hosts for friends", func(): h.host_room(host, "friends"))
	var room: String = h.current_room(host)
	await h.step("guest opens Friends", func(): await guest.app._show_friends())
	guest.api.faults.append({"path": "/v2/rooms", "method": HTTPClient.METHOD_GET, "kind": "hold"})
	h.check(h.press(guest, "Join"), "Friends offers Join on the host's room")
	h.check(await _until(func() -> bool: return guest.api.held > 0), "the rooms check is out")
	guest.background()
	await h.frames(4)
	guest.api.release_held()
	await h.frames(12)
	guest.foreground()
	await _until(func() -> bool: return guest.child() != null, 5000)
	await h.step("a moment passes", func(): pass)
	h.check(guest.app.mode != "relay_rooms", "the guest is not left on the room progress card")
	h.check(h.current_room(guest) == room and not room.is_empty(), "the guest is in the friend's room")
	await h.finish()

## An earlier-island invitation code typed on the hub whose join the server
## refuses: the player stays on the hub with the reason, never on a screen
## with no hub behind a stale Home.
func _earlier_island_join_refused() -> void:
	await _begin("earlier-island join refused")
	var code := "B1B1B1B1B1B1B1B1B1B1"
	h.server.legacy_invites[code] = [410, "invite_expired"]
	await h.step("guest opens the hub", func(): h.open_hub(guest))
	await h.step("guest joins with an expired earlier-island code", func(): h.join_room(guest, "room-" + code), [guest])
	h.check(guest.hub() != null and guest.hub().visible, "the guest is still on the hub (at %s)" % guest.where())
	h.check(guest.hub() != null and not guest.hub()._message.is_empty(), "the hub says why the join failed")
	h.check(guest.api.requests.any(func(entry: Dictionary) -> bool: return entry.path == "/v1/rooms/join"), "the earlier-island join was asked for")
	await h.finish()
