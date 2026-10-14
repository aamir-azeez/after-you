extends "res://tests/test_online_scenarios.gd"
## Interruptions at the awkward moments: backgrounding in review, during a
## save and during a replay download, a notification for a room that is gone,
## and a friend still on 0.6.0.

func scenarios() -> Array[Callable]:
	return [_background_at_awkward_moments, _notification_for_gone_room, _friend_on_060, _resend_backs_off]

func suite_name() -> String:
	return "Online scenarios (edges)"

func _background_then_foreground(device: Node) -> void:
	device.background()
	await h.frames(10)
	device.foreground()

func _hold_save_then_background(device: Node, room: String) -> void:
	await h.play_turn(device)
	device.api.faults.append({"path": "/v2/rooms/" + room + "/turns", "kind": "hold"})
	h.save_turn(device)
	await h.frames(4)
	device.background()
	await h.frames(10)
	device.api.release_held()
	await h.frames(4)
	device.foreground()

func _hold_download_then_back(device: Node, room: String) -> void:
	device.api.faults.append({"path": "/v2/rooms/" + room + "/replay-transfer", "kind": "hold"})
	h.back(device)
	await h.frames(30)
	h.back(device)
	await h.frames(4)
	device.api.release_held()

func _background_at_awkward_moments() -> void:
	await _begin("background at awkward moments")
	var room: String = await h.hosted_and_joined()
	await h.step("host plays stage 1 A to review", func(): await h.play_turn(host))
	await h.step("host backgrounds in review", _background_then_foreground.bind(host))
	h.check(host.child() != null and host.child().mode == "review" and host.button("save") != null, "review survives the background with Save turn ready")
	await h.step("host saves", func(): h.save_turn(host))
	await h.step("host continues", func(): await h.continue_after_turn(host))
	await h.step("guest notices", func(): h.nudge(guest))
	await h.step("guest saves stage 1 B while the app goes to the background", _hold_save_then_background.bind(guest, room))
	await h.step("a few seconds pass", func(): h.elapse(guest))
	await h.step("guest continues", func(): await h.continue_after_turn(guest))
	h.check(h.server.accepted(room).size() == 2, "a save interrupted by backgrounding reaches the server once")
	await h.step("guest takes stage 2 A", func(): await h.take_turn(guest))
	await h.step("host notices", func(): h.nudge(host))
	await h.step("host takes the last turn", func(): await h.take_turn(host))
	await h.step("host leaves while the replay downloads, then goes home", _hold_download_then_back.bind(host, room))
	await h.check_replays(host, room, "after an interrupted download")
	await h.step("guest goes back", func(): h.back(guest))
	await h.check_replays(guest, room, "background")
	await h.finish()

func _notification_for_gone_room() -> void:
	await _begin("notification for a room that is gone")
	var room: String = await h.hosted_and_joined()
	await h.step("host takes stage 1 A", func(): await h.take_turn(host))
	await h.step("guest goes back", func(): h.back(guest))
	await h.step("guest goes home", func(): h.back(guest))
	await h.step("host goes back", func(): h.back(host))
	await h.step("host closes the room", func(): h.remove_room_card(host, room))
	await h.step("guest taps the turn notification", func(): h.tap_notification(guest, room, 2), [guest])
	h.check(guest.app.turn_notifications.pending_route().is_empty(), "the notification is settled, not retried")
	h.check(guest.child() == null, "no room opens for a closed room")
	await h.step("time passes", func(): h.elapse(guest))
	await h.step("guest opens the hub", func(): h.open_hub(guest))
	h.check(guest.hub() != null, "the guest can still use Play with a friend")
	# A live room's notification opens it.
	await h.step("host hosts again", func(): h.host_room(host))
	var next: String = h.current_room(host)
	await h.step("guest joins", func(): h.join_room(guest, h.invitation(host)))
	await h.step("host takes stage 1 A", func(): await h.take_turn(host))
	await h.step("guest goes back", func(): h.back(guest))
	await h.step("guest goes home", func(): h.back(guest))
	await h.step("guest taps the turn notification", func(): h.tap_notification(guest, next, 2))
	h.check(h.current_room(guest) == next and guest.child().journey.my_turn(), "a live room's notification opens the turn")
	await h.finish()

func _friend_on_060() -> void:
	await _begin("friend on 0.6.0")
	guest.legacy_060 = true
	guest.api.legacy_060 = true
	h.server.legacy_transferred_unblock = true
	var room: String = await h.hosted_and_joined()
	await h.play_out(room)
	await h.step("host leaves the room", func(): h.back(host))
	await h.check_replays(host, room, "0.6.0 friend")
	await h.finish()

## A saved turn that cannot reach the server is retried on the room poll's
## backoff (5, 15, 30 s), never in a loop, and lands exactly once.
func _outage_while_waiting(device: Node, room: String, counts: Dictionary) -> void:
	device.api.faults.append({"path": "/v2/rooms/" + room, "kind": "status", "status": 503, "code": "service_unavailable", "count": 1000})
	var before: int = device.api.requests.size()
	await h.play_turn(device)
	h.save_turn(device)
	await h.settle()
	# About 32 s of waiting on the room card.
	for tick in 10:
		h.elapse(device)
		await h.frames(8)
		await h.settle()
	var sent: Array = device.api.requests.slice(before)
	counts.posts = sent.filter(func(item: Dictionary) -> bool: return item.path.ends_with("/turns")).size()
	counts.total = sent.size()
	device.api.faults.clear()

func _resend_backs_off() -> void:
	await _begin("resend backs off")
	var room: String = await h.hosted_and_joined()
	var counts := {}
	await h.step("host saves stage 1 A during an outage and waits", _outage_while_waiting.bind(host, room, counts), [host])
	h.check(int(counts.get("posts", 99)) <= 5 and int(counts.get("total", 99)) <= 12, "the saved turn is retried on a backoff, not in a loop (%s)" % [counts])
	h.check(h.server.accepted(room).is_empty(), "nothing reached the server during the outage")
	await h.step("the service is back; half a minute passes", _wait_half_minute.bind(host))
	await h.step("host continues", func(): await h.continue_after_turn(host))
	h.check(h.server.accepted(room).size() == 1, "the turn lands exactly once when the service is back")
	await h.play_out(room)
	await h.finish()

func _wait_half_minute(device: Node) -> void:
	for tick in 10:
		h.elapse(device)
		await h.frames(8)
		await h.settle()
