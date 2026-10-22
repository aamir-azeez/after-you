extends "res://tests/test_online_scenarios.gd"
## Room moments that used to strand a player: the app paused while Host or a
## friend's Join waits for its reply.

func scenarios() -> Array[Callable]:
	return [_pause_while_hosting, _pause_while_joining_from_friends]

func suite_name() -> String:
	return "Online robustness"

## Frames until `condition` holds, bounded by the clock like the harness's settle().
func _until(condition: Callable, limit_ms: int = 10000) -> bool:
	var deadline := Time.get_ticks_msec() + limit_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await h.frames(1)
	return condition.call()

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
