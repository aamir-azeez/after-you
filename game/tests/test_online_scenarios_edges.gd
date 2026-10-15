extends "res://tests/test_online_scenarios.gd"
## Interruptions at the awkward moments: backgrounding in review, during a
## save and during a replay download, a notification for a room that is gone,
## a friend still on 0.6.0, and a pair with twenty finished rooms behind them.
const Canonical = preload("res://core/v2/canonical.gd")
const Registry = preload("res://services/chapter_registry.gd")

func scenarios() -> Array[Callable]:
	return [_background_at_awkward_moments, _notification_for_gone_room, _friend_on_060, _resend_backs_off, _waiting_polls_answer_small, _tap_while_hub_reads, _host_after_twenty_finished_rooms]

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

## A waiting phone polls its room every few seconds. While nothing moves, the
## server answers small and the waiting card is never rebuilt; a Worker that
## ignores the known-room header sends the full room, which changes nothing either.
func _waiting_polls_answer_small() -> void:
	await _begin("waiting polls answer small")
	var room: String = await h.hosted_and_joined()
	await h.step("host takes stage 1 A", func(): await h.take_turn(host))
	var child: Node = host.child()
	h.check(child != null and child.mode == "online_waiting", "the host waits for the guest")
	if child == null:
		await h.finish()
		return
	# The first poll after a turn also reads the room's turn requests for the first time.
	await h.step("the first poll after the turn", func(): h.elapse(host))
	var card := _overlay_ids(child)
	var small := int(h.server.unchanged_replies)
	for poll in 3: await h.step("a poll passes while the host waits", func(): h.elapse(host))
	h.check(int(h.server.unchanged_replies) >= small + 3, "each waiting poll is answered with the small unchanged reply")
	h.check(_overlay_ids(child) == card and child.mode == "online_waiting", "an unchanged room never rebuilds the waiting card")
	h.server.known_room_polls = false
	small = int(h.server.unchanged_replies)
	for poll in 2: await h.step("a poll to a Worker without the small reply", func(): h.elapse(host))
	h.check(int(h.server.unchanged_replies) == small, "an older Worker sends the full room")
	h.check(_overlay_ids(child) == card and child.mode == "online_waiting", "an identical full room never rebuilds the waiting card")
	h.server.known_room_polls = true
	await h.step("guest notices", func(): h.nudge(guest))
	await h.step("guest takes stage 1 B", func(): await h.take_turn(guest))
	await h.step("a poll passes for the host", func(): h.elapse(host))
	h.check(host.child() != null and int(host.child().journey.snapshot().revision) == int(h.server.rooms[room].revision), "the host's room follows once it moves")
	h.check(h.server.accepted(room).size() == 2, "both turns reached the server once")
	await h.finish()

static func _overlay_ids(child: Node) -> Array:
	return child.overlay.get_children().map(func(node: Node) -> int: return node.get_instance_id())

## A room card tapped while the hub's own room list is still being read opens
## the room once the read lands, with no refusal on the way.
func _tap_while_hub_reads() -> void:
	await _begin("tap while the hub reads its rooms")
	var room: String = await h.hosted_and_joined()
	await h.step("guest goes to the hub", func(): await h.to_hub(guest))
	await h.step("guest taps the room card while the hub's room list is out", _open_during_inbox.bind(guest, room))
	h.check(guest.child() != null and h.current_room(guest) == room, "the tap made during the hub's read opens the room")
	h.check(guest.toasts.is_empty() and guest.error_cards.is_empty(), "no refusal is shown on the way")
	await h.finish()

func _open_during_inbox(device: Node, room: String) -> void:
	device.api.faults.append({"path": "/v1/room-inbox", "kind": "hold"})
	h.nudge(device)
	await h.frames(4)
	h.check(device.api.held > 0, "the hub's room list read is out")
	h.check(h.open_room_card(device, room), "the room card is there to tap")
	await h.frames(4)
	device.api.release_held()

## Twenty earlier rooms both players finished leave the host free to host and
## the guest free to join, and Remove from list takes a finished room off the
## hub only: the server keeps it for both players.
func _host_after_twenty_finished_rooms() -> void:
	await _begin("host after twenty finished rooms")
	var earlier := _finished_rooms(20)
	h.check(earlier.all(func(room: String) -> bool: return h.server.room_state(room) == "complete"), "twenty earlier rooms are finished on the server")
	var room: String = await h.hosted_and_joined()
	h.check(not room.is_empty() and h.server.linked(host.player_id, room) and h.server.linked(guest.player_id, room), "a 21st room is hosted and joined")
	await h.step("host goes to the hub", func(): await h.to_hub(host))
	await h.step("host opens the Completed tab", func(): host.hub()._select_tab("Completed"))
	h.check(h.room_listed(host, earlier[0]), "the hub lists an earlier finished room")
	await h.step("host removes that room from the list", func(): h.remove_room_card(host, earlier[0]))
	h.check(not h.room_listed(host, earlier[0]), "it leaves the host's list")
	h.check(h.server.linked(host.player_id, earlier[0]) and h.server.room_state(earlier[0]) == "complete", "the server keeps the finished room")
	await h.step("host goes back to Your rooms", func(): host.hub()._select_tab("Your rooms"))
	await h.finish()

## Rooms played to the end through the server's own routes with the recorded
## Relay turns, the way earlier chapters leave them.
func _finished_rooms(count: int) -> Array[String]:
	var level: Dictionary = Registry.definition(h.RELAY)
	var middle: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/relay-checkpoint.json"))
	var final: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/final-checkpoint.json"))
	var made: Array[String] = []
	for index in count:
		var created: Dictionary = _send(host, "/v2/rooms", {"idempotency_key": "earlier-room-%02d-0000000000" % index, "level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level)})
		var room_id := str(created.body.get("room_id", ""))
		_send(guest, "/v2/rooms/join", {"invite_code": created.body.get("invite_code", "")})
		for turn: Array in [[host, "relay-a", null], [guest, "relay-b", middle], [guest, "garden-a", null], [host, "garden-b", final]]:
			var state: Dictionary = h.server.rooms[room_id]
			var body := {"base_revision": state.revision, "branch": state.branch, "idempotency_key": "earlier-turn-%02d-%s" % [index, turn[1]], "recording": h.fixtures[turn[1]]}
			if turn[2] != null: body["checkpoint"] = turn[2]
			_send(turn[0], "/v2/rooms/%s/turns" % room_id, body)
		made.append(room_id)
	return made

func _send(device: Node, path: String, body: Dictionary) -> Dictionary:
	return h.server.handle(HTTPClient.METHOD_POST, path, PackedStringArray(["X-Player-Id: " + device.player_id, "Authorization: Bearer " + str(h.server.players[device.player_id].token)]), body)
