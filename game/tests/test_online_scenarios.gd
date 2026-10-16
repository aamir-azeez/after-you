extends SceneTree
## Scripted Play with a friend scenarios on two phones against the harness
## server: the order a careful player follows, and the orders real players
## use (leaving early, coming back, closing mid-turn, double taps, restarts).
const Harness = preload("res://tests/online_harness/harness.gd")
const UserFiles = preload("res://tests/online_harness/user_files.gd")
var h: Node
var files: RefCounted
var host: Node
var guest: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	files = UserFiles.new()
	h = Harness.new()
	h.trace = true
	root.add_child(h)
	for scenario: Callable in scenarios():
		await scenario.call()
	h.print_slowest()
	h.end()
	await process_frame
	files.cleanup()
	print("%s: %d checks, %d failures" % [suite_name(), h.checks, h.failures])
	quit(1 if h.failures else 0)

## This suite's half of the scenarios; test_online_scenarios_more runs the rest
## (each suite stays well inside CI's per-suite limit).
func scenarios() -> Array[Callable]:
	return [_happy_path, _host_leaves_before_join, _leave_mid_turn, _leave_at_stage_boundary, _guest_leaves_and_rejoins, _expired_and_closed_invites]

func suite_name() -> String:
	return "Online scenarios"

func _begin(name: String) -> void:
	await h.begin(name)
	host = h.host
	guest = h.guest

## The careful order: host, friend joins, both stages, both see it finished.
func _happy_path() -> void:
	await _begin("happy path")
	await h.step("host opens the hub", func(): h.open_hub(host))
	await h.step("guest opens the hub", func(): h.open_hub(guest))
	await h.step("host hosts", func(): h.host_room(host))
	var room: String = h.current_room(host)
	h.check(not room.is_empty(), "the host is in the new room")
	await h.step("host plays stage 1 A", func(): await h.take_turn(host))
	var code: String = h.invitation(host)
	h.check(code.begins_with("room-"), "the host has an invitation to share")
	await h.step("guest joins", func(): h.join_room(guest, code))
	h.check(h.current_room(guest) == room, "the guest is in the host's room")
	await h.step("guest plays stage 1 B", func(): await h.take_turn(guest))
	await h.step("guest plays stage 2 A", func(): await h.take_turn(guest))
	await h.step("host notices", func(): h.nudge(host))
	await h.step("host plays stage 2 B", func(): await h.take_turn(host))
	h.check(h.server.room_state(room) == "complete", "the room finished on the server")
	await h.step("host leaves the room", func(): h.back(host))
	await h.step("guest notices", func(): h.nudge(guest))
	await h.step("guest leaves the room", func(): h.back(guest))
	h.check(h.server.room_state(room) == "transferred", "both phones saved the finished room's replay")
	for device: Node in [host, guest]: await h.check_replays(device, room, "happy path")
	await h.finish()

## Host, go back to the hub before the friend joins, come back later.
func _host_leaves_before_join() -> void:
	await _begin("host leaves before the friend joins")
	await h.step("host opens the hub", func(): h.open_hub(host))
	await h.step("host hosts", func(): h.host_room(host))
	var room: String = h.current_room(host)
	var code: String = h.invitation(host)
	await h.step("host goes back", func(): h.back(host))
	h.check(host.hub() != null and h.room_listed(host, room), "the hub lists the waiting room")
	await h.step("guest opens the hub", func(): h.open_hub(guest))
	await h.step("guest joins while the host is away", func(): h.join_room(guest, code))
	h.check(h.current_room(guest) == room, "the guest is in the room")
	await h.step("guest goes back", func(): h.back(guest))
	await h.step("host refreshes the hub", func(): h.nudge(host))
	await h.step("host opens the room again", func(): h.open_room_card(host, room))
	h.check(h.current_room(host) == room, "the host is back in the room")
	await h.play_out(room)
	await h.finish()

## Back in the middle of a turn, then come back and resume it.
func _leave_mid_turn() -> void:
	await _begin("leave in the middle of a turn")
	var room: String = await h.hosted_and_joined()
	await h.step("host starts stage 1 A", func(): await h.play_turn(host, 0.5))
	await h.step("host presses Back (pause)", func(): h.back(host))
	await h.step("host presses Back again (leave)", func(): h.press(host, "back"))
	h.check(host.hub() != null, "the host is at the hub")
	await h.step("host opens the room again", func(): h.open_room_card(host, room))
	h.check(host.child() != null and host.button("resume") != null, "the room offers Resume for the saved draft")
	await h.step("host resumes", func(): h.press(host, "resume"))
	await h.step("host finishes and saves", _finish_and_save.bind(host))
	await h.step("host continues", func(): await h.continue_after_turn(host))
	h.check(h.server.accepted(room).size() == 1, "the resumed turn reached the server")
	await h.play_out(room)
	await h.finish()

func _finish_and_save(device: Node) -> void:
	await h.finish_turn(device)
	h.save_turn(device)

func _play_and_save(device: Node) -> void:
	await h.play_turn(device)
	h.save_turn(device)

## The guest finishes stage 1 and leaves at the checkpoint card.
func _leave_at_stage_boundary() -> void:
	await _begin("leave at the stage boundary")
	var room: String = await h.hosted_and_joined()
	await h.step("host takes stage 1 A", func(): await h.take_turn(host))
	await h.step("guest notices", func(): h.nudge(guest))
	await h.step("guest plays and saves stage 1 B", _play_and_save.bind(guest))
	await h.step("guest skips the photo", _skip_photo.bind(guest))
	h.check(guest.child() != null and guest.child().mode == "checkpoint", "the guest is at the stage checkpoint")
	await h.step("guest leaves at the checkpoint", func(): h.press(guest, "back"))
	h.check(guest.hub() != null, "the guest is at the hub")
	await h.step("guest refreshes", func(): h.nudge(guest))
	await h.step("guest continues the room", func(): h.open_room_card(guest, room))
	h.check(h.current_room(guest) == room and guest.child().journey.my_turn(), "the guest's stage 2 turn is ready")
	await h.play_out(room)
	await h.finish()

func _skip_photo(device: Node) -> void:
	var child: Node = device.child()
	if child == null or child.mode == "checkpoint": return
	for text: String in ["Skip", "Keep playing"]:
		if h.press(device, text): return

## The guest joins, leaves, joins again by code and by the room card.
func _guest_leaves_and_rejoins() -> void:
	await _begin("guest leaves and rejoins")
	var room: String = await h.hosted_and_joined()
	var code: String = h.invitation(host)
	await h.step("guest goes back", func(): h.back(guest))
	await h.step("guest joins again by code", func(): h.join_room(guest, code))
	h.check(h.current_room(guest) == room, "joining again by code reopens the same room")
	await h.step("guest goes back again", func(): h.back(guest))
	await h.step("guest opens the room card", func(): h.open_room_card(guest, room))
	h.check(h.current_room(guest) == room, "the room card reopens the room")
	await h.play_out(room)
	await h.finish()

## Joining with an invitation that expired, or whose room was closed.
func _expired_and_closed_invites() -> void:
	await _begin("expired and closed invitations")
	await h.step("host opens the hub", func(): h.open_hub(host))
	await h.step("host hosts", func(): h.host_room(host))
	var code: String = h.invitation(host)
	var room: String = h.current_room(host)
	h.server.advance_days(8)
	await h.step("guest opens the hub", func(): h.open_hub(guest))
	await h.step("guest joins with an expired code", func(): h.join_room(guest, code), [guest])
	h.check(guest.hub() != null and not guest.hub()._message.is_empty(), "the guest is told the invitation expired")
	h.check(guest.app.relay_session == null or guest.app.relay_session.pending_lobby().is_empty(), "a refused join is not kept as a request to retry")
	h.check(guest.hub() != null and not guest.hub()._held_panel.visible, "the hub does not hold other rooms behind a refused join")
	await h.step("guest hosts a room of their own", func(): h.host_room(guest))
	var own: String = h.current_room(guest)
	h.check(not own.is_empty(), "the guest can host after a refused join")
	var own_code: String = h.invitation(guest)
	await h.step("host goes back", func(): h.back(host))
	await h.step("host closes the waiting room", func(): h.remove_room_card(host, room))
	h.check(h.server.room_state(room) == "closed", "the room is closed on the server")
	await h.step("guest goes back", func(): h.back(guest))
	await h.step("guest closes their room", func(): h.remove_room_card(guest, own))
	await h.step("host joins the closed room's code", func(): h.join_room(host, own_code), [host])
	h.check(host.hub() != null and host.app.relay_session.pending_lobby().is_empty(), "a closed room's code leaves no held request")
	await h.finish()

## One player closes the room while the other is in the middle of a turn.
func _close_while_partner_mid_turn() -> void:
	await _begin("close while the partner is mid-turn")
	var room: String = await h.hosted_and_joined()
	await h.step("host takes stage 1 A", func(): await h.take_turn(host))
	await h.step("guest notices", func(): h.nudge(guest))
	await h.step("guest starts stage 1 B", func(): await h.play_turn(guest, 0.5))
	await h.step("host goes back", func(): h.back(host))
	await h.step("host closes the room", func(): h.remove_room_card(host, room))
	await h.step("guest finishes and saves", _finish_and_save.bind(guest), [guest])
	h.check(guest.child() == null or guest.child().mode != "online_request", "the guest is not left waiting on a closed room")
	await h.step("guest goes back", func(): h.back(guest), [guest])
	await h.to_hub(guest)
	var listed: Array = guest.hub()._visible_rooms.filter(func(item: Dictionary) -> bool: return item.room_id == room) if guest.hub() != null else []
	h.check(listed.is_empty() or listed[0].status == "closed", "the guest sees the room closed or gone")
	await h.step("guest hosts a new room", func(): h.host_room(guest))
	h.check(not h.current_room(guest).is_empty() and h.current_room(guest) != room, "a turn left in a closed room does not block a new room")
	await h.finish()

func _check_or_refresh(device: Node) -> void:
	if not h.press(device, "check_saved"): h.press(device, "refresh")

## Replies lost after the server saved, requests that never arrived, outages.
func _lost_replies() -> void:
	await _begin("lost replies and outages")
	var room: String = await h.hosted_and_joined()
	host.api.faults.append({"path": "/v2/rooms/" + room + "/turns", "kind": "drop_after"})
	await h.step("host saves stage 1 A; the reply is lost", func(): await h.take_turn(host), [host])
	h.check(h.server.accepted(room).size() == 1, "the server kept the turn")
	await h.step("host checks", _check_or_refresh.bind(host), [host])
	await h.step("host continues", func(): await h.continue_after_turn(host))
	h.check(host.child() != null and host.child().journey.pending().is_empty(), "the lost reply is resolved without a second turn")
	h.check(h.server.accepted(room).size() == 1, "still one turn on the server")
	await h.step("guest notices", func(): h.nudge(guest))
	guest.api.faults.append({"path": "/v2/rooms/" + room + "/turns", "kind": "drop_before"})
	await h.step("guest saves stage 1 B; the request never arrives", func(): await h.take_turn(guest), [guest])
	await h.step("guest retries", _check_or_refresh.bind(guest), [guest])
	await h.step("guest continues", func(): await h.continue_after_turn(guest))
	h.check(h.server.accepted(room).size() == 2, "the guest's turn reached the server once")
	guest.api.faults.append({"path": "/v2/rooms/" + room, "kind": "status", "status": 503, "code": "service_unavailable", "count": 3})
	await h.step("guest refreshes during an outage", func(): h.nudge(guest), [guest])
	await h.play_out(room)
	await h.finish()

## Two quick taps on every main action.
func _double_taps() -> void:
	await _begin("double taps")
	await h.step("host opens the hub", func(): h.open_hub(host))
	await h.step("host taps Host twice", func(): h.host_room(host, "friends", 2))
	h.check(h.server.room_of(host.player_id).size() == 1, "two taps on Host make one room")
	var room: String = h.current_room(host)
	var code: String = h.invitation(host)
	await h.step("guest opens the hub", func(): h.open_hub(guest))
	await h.step("guest taps Join twice", func(): h.join_room(guest, code, 2))
	h.check(h.current_room(guest) == room, "two taps on Join join once")
	await h.step("host plays stage 1 A", func(): await h.play_turn(host))
	await h.step("host taps Save twice", func(): h.save_turn(host, 2))
	await h.step("host continues", func(): await h.continue_after_turn(host))
	h.check(h.server.accepted(room).size() == 1, "two taps on Save save once")
	await h.step("guest goes back", func(): h.back(guest))
	await h.step("guest refreshes", func(): h.nudge(guest))
	await h.step("guest taps Continue twice", func(): h.open_room_card(guest, room, 2))
	h.check(h.current_room(guest) == room, "two taps on Continue open the room once")
	await h.play_out(room)
	await h.step("host goes back", func(): h.back(host))
	await h.to_hub(host)
	await h.step("host taps Watch replay twice", func(): h.open_room_card(host, room, 2))
	await h.finish()

func _save_then_quit(device: Node, room: String) -> void:
	await h.play_turn(device)
	device.api.faults.append({"path": "/v2/rooms/" + room + "/turns", "kind": "hold"})
	h.save_turn(device)
	await h.frames(8)
	await h.reopen(device)

## Force-quit at every step of a game, then reopen and carry on.
func _force_quit_everywhere() -> void:
	await _begin("force quit and reopen")
	var room: String = await h.hosted_and_joined()
	await h.step("host quits and reopens", func(): await h.reopen(host))
	await h.step("host opens the hub", func(): h.open_hub(host))
	await h.step("host opens the room", func(): h.open_room_card(host, room))
	await h.step("host starts a turn", func(): await h.play_turn(host, 0.5))
	await h.step("host quits mid-turn and reopens", func(): await h.reopen(host))
	await h.step("host opens the hub", func(): h.open_hub(host))
	await h.step("host opens the room", func(): h.open_room_card(host, room))
	await h.step("host plays and saves; quits while saving", _save_then_quit.bind(host, room))
	await h.step("host opens the hub", func(): h.open_hub(host))
	await h.step("host opens the room", func(): h.open_room_card(host, room))
	h.check(host.child() != null, "the room opens after a quit during a save")
	await h.step("guest quits and reopens", func(): await h.reopen(guest))
	await h.step("guest opens the hub", func(): h.open_hub(guest))
	await h.play_out(room)
	await h.step("guest quits on the finished room", func(): await h.reopen(guest))
	await h.finish()

## A reinstall makes a new player; the old rooms stay with the old identity.
func _reinstall_with_old_rooms() -> void:
	await _begin("reinstall with old rooms")
	var room: String = await h.hosted_and_joined()
	await h.step("host takes stage 1 A", func(): await h.take_turn(host))
	await h.step("guest reinstalls", func(): await h.reinstall(guest))
	await h.step("guest opens the hub", func(): h.open_hub(guest))
	h.check(not h.room_listed(guest, room), "the new install does not list the old identity's room")
	await h.step("host goes back", func(): h.back(host))
	await h.step("host closes the abandoned room", func(): h.remove_room_card(host, room))
	h.check(h.server.room_state(room) == "closed", "the host can end a room the friend abandoned")
	await h.finish()

func _open_together(device: Node) -> void:
	device.app.room_hub_flow.close()
	device.app.replays_flow.show_shared_replays()

## Skipping the end-of-game replays, and watching parts before the friend ends.
func _skip_and_early_replays() -> void:
	await _begin("skipped and early replays")
	var room: String = await h.hosted_and_joined()
	await h.step("host takes stage 1 A", func(): await h.take_turn(host))
	await h.step("guest notices", func(): h.nudge(guest))
	await h.step("guest takes stage 1 B", func(): await h.take_turn(guest))
	await h.step("host goes back", func(): h.back(host))
	await h.step("host opens Together replays early", _open_together.bind(host))
	await h.step("host leaves replays", func(): h.back(host))
	await h.play_out(room)
	await h.finish()
	h.check(h.server.room_state(room) in ["complete", "transferred"], "the finished room is complete or saved to both phones")
