extends Node
## Drives two phones (host and guest) through Play with a friend against one
## FakeServer, and checks the online invariants after every step:
## - no stuck state: each phone's screen has a way forward or back;
## - no error toast or error card unless the step injected a real failure;
## - no "<null>", raw room or player id on screen;
## - the hub's room list agrees with the server once refreshed;
## - every turn a player saved reaches the server or stays saved on the phone;
## - no unbounded retry or polling: request counts stay within a budget;
## - every room ends completed, closed or deleted on both phones (finish()).
const FakeServer = preload("res://tests/online_harness/fake_server.gd")
const Device = preload("res://tests/online_harness/device.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const RelayStore = preload("res://services/relay_online_store.gd")
const RELAY := "relay-isles@2"
const IDLE_FRAMES := 3
const SETTLE_MS := 30000
## Requests one phone may send within one step, and POSTs to one path: more
## means a retry storm, not a player's action.
const STEP_REQUEST_CAP := 25
const STEP_POST_CAP := 3

var server: RefCounted
var host: Node
var guest: Node
var devices: Array[Node] = []
var fixtures: Dictionary = {}
var checks := 0
var failures := 0
var scenario := ""
var steps: Array[String] = []
## Devices whose current step injected a failure; their toasts are expected.
var faulted: Dictionary = {}
## Accepted turns each player saved (recording hashes by room), for "never lost".
var saved_turns: Dictionary = {}
var _created: Array[String] = []
## One line per step (OS env AFTER_YOU_HARNESS_TRACE=1, or set by a suite).
var trace := OS.get_environment("AFTER_YOU_HARNESS_TRACE") == "1"
var _trace_marks: Dictionary = {}
var _notices: Dictionary = {}
## [milliseconds, step] for every step, for the slowest-steps report.
var timings: Array = []

func print_slowest(count: int = 12) -> void:
	timings.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var total := 0
	for item: Array in timings: total += int(item[0])
	print("Harness steps: %d, %d ms in steps; slowest: %s" % [timings.size(), total, timings.slice(0, count).map(func(item: Array) -> String: return "%d ms %s" % item)])
var _user_files_before: Dictionary = {}

func _ready() -> void:
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error("[%s] %s" % [scenario, message])
		print("FAIL [%s] %s\n  steps: %s" % [scenario, message, " > ".join(steps.slice(maxi(0, steps.size() - 12)))])
		for device: Node in devices: print("  %s at %s; toasts %s; errors %s\n    requests: %s" % [device.label, device.where(), device.toasts, device.error_cards, device.recent_requests()])
		if server != null and not server.unknown.is_empty(): print("  server did not know: %s" % [server.unknown])
	return condition

## Starts a scenario with a fresh server and two freshly installed phones.
func begin(name: String, seed: int = 0) -> void:
	end()
	scenario = name
	steps.clear()
	faulted.clear()
	saved_turns.clear()
	server = FakeServer.new()
	# Ids differ per scenario: phones keep owner-scoped files between scenarios.
	server.set_seed(hash(name) ^ seed)
	host = Device.new("host", server)
	guest = Device.new("guest", server)
	devices = [host, guest]
	for device: Node in devices:
		add_child(device)
		device.install()
	await settle()

func end() -> void:
	for device: Node in devices:
		if is_instance_valid(device):
			device.force_quit()
			remove_child(device)
			device.free()
	devices.clear()
	host = null
	guest = null

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
		for device: Node in devices:
			device.observe()
			_hold_play_clock(device)

## In play the harness feeds every tick through advance_input. The room's own
## physics clock would add still ticks, as many as the machine's speed allows,
## and a turn that drifts from its recording no longer fits the friend's
## recorded reply. Play can begin inside the room's own _process (a Resume
## held for a busy session), so the clock runs only in a replay, the one other
## mode it moves. This also leaves out the memory wait's Skip and fast-forward
## during play, which no scenario uses.
static func _hold_play_clock(device: Node) -> void:
	var child: Node = device.child()
	if child != null: child.set_physics_process(child.mode == "replay")

## Waits until both phones are quiet: no request in flight and nothing busy.
## Bounded by wall-clock time: the app's own waits (a queued request, a quiet
## retry) are timers, so a fast machine must not run out of frames first.
func settle(limit_ms: int = SETTLE_MS) -> void:
	var quiet := 0
	var deadline := Time.get_ticks_msec() + limit_ms
	while Time.get_ticks_msec() < deadline:
		await frames(1)
		quiet = quiet + 1 if _quiet() else 0
		if quiet >= IDLE_FRAMES: return
	print("      settle: still busy after %d ms: %s" % [limit_ms, " | ".join(devices.map(func(device: Node) -> String: return device.label + " " + device.where()))])

func _quiet() -> bool:
	for device: Node in devices:
		if not device.running(): continue
		var app: Node = device.app
		if device.api._queue.busy() or device.api.held > 0: return false
		if app.relay_session != null and app.relay_session.busy(): return false
		if app.room_hub_flow.inbox != null and app.room_hub_flow.inbox.busy: return false
		# A hosting alert and its quiet retries belong to the step that hosted.
		if (app.friend_room_events != null and app.friend_room_events.busy) or app.room_sharing.retrying(): return false
		if app.replays_flow._shared_archive_sync or app.replays_flow._shared_photo_sync or not app.replays_flow.replay_saves.is_empty(): return false
		if app.shared_replays != null and app.mode in ["shared_replays", "shared_memories"] and app.shared_replays.local_loading(): return false
		var child: Node = device.child()
		if child != null and _child_busy(child): return false
		if app.mode == "relay_rooms": return false
	return true

## A room screen on its way somewhere by itself: a request, a load, or a bloom
## still counting down.
static func _child_busy(child: Node) -> bool:
	if child.mode in ["online_request", "turn_wait", "loading", "creating_room", "leaving"]: return true
	return child.has_method("completion_counting") and child.completion_counting()

## Runs one user action, lets both phones settle and checks the invariants.
func step(label: String, action: Callable, faults_on: Array = []) -> void:
	steps.append(label)
	for device: Node in devices:
		device.toasts.clear()
		device.error_cards.clear()
	faulted.clear()
	for device: Node in faults_on: faulted[device] = true
	for device: Node in devices: _trace_marks[device] = device.api.requests.size() if device.running() else 0
	var started := Time.get_ticks_msec()
	await action.call()
	await settle()
	timings.append([Time.get_ticks_msec() - started, scenario + ": " + label])
	# A fault belongs to its step: one the step never triggered is dropped.
	for device: Node in devices:
		if device.running(): device.api.faults.clear()
	_check_step_budget(label)
	if trace:
		print("  [%s] %s -> %s" % [scenario, label, " | ".join(devices.map(func(device: Node) -> String: return device.label + " " + device.where()))])
		for device: Node in devices:
			if device.running() and device.api.requests.size() > int(_trace_marks.get(device, 0)):
				print("      %s: %s" % [device.label, device.recent_requests(device.api.requests.size() - int(_trace_marks.get(device, 0)))])
			if not device.toasts.is_empty(): print("      %s toasts: %s" % [device.label, device.toasts])
	verify(label)

func _check_step_budget(label: String) -> void:
	for device: Node in devices:
		if not device.running() or not _trace_marks.has(device): continue
		var sent: Array = device.api.requests.slice(int(_trace_marks[device]))
		check(sent.size() <= STEP_REQUEST_CAP, "%s: %s sends a bounded number of requests (%d)" % [label, device.label, sent.size()])
		var posts := {}
		for item: Dictionary in sent:
			if item.method == HTTPClient.METHOD_POST: posts[item.path] = int(posts.get(item.path, 0)) + 1
		for path: String in posts:
			check(int(posts[path]) <= STEP_POST_CAP, "%s: %s does not repeat a POST (%d x %s)" % [label, device.label, posts[path], path])
		check(device.api.repeated_keys.is_empty(), "%s: %s never sends a write again after its reply arrived (%s)" % [label, device.label, device.api.repeated_keys])

## Every turn a player saved reached the server, or (in a room closed
## meanwhile) is still in that phone's room journal.
func check_saved_turns(label: String) -> void:
	var store := RelayStore.new()
	for room_id: String in saved_turns:
		for recording_hash: String in saved_turns[room_id]:
			if recording_hash in server.ever_accepted(room_id): continue
			var owner: String = saved_turns[room_id][recording_hash]
			var kept := false
			var loaded: Dictionary = store.load_scope("relay-room-v2:" + owner + ":" + room_id)
			var state: Variant = loaded.get("value")
			if state is Dictionary:
				var places: Array = [state.get("draft", {}), state.get("pending", {}).get("body", {})] + state.get("held_drafts", [])
				for place: Variant in places:
					if place is Dictionary and place.get("recording", {}).get("recording_hash") == recording_hash: kept = true
			check(kept, "%s: a turn saved in room %s reached the server or stays on the phone" % [label, room_id.left(4)])

func verify(label: String) -> void:
	for device: Node in devices:
		if not device.running(): continue
		_check_screen(device, label)
		_check_texts(device, label)
		if not faulted.has(device):
			check(device.toasts.is_empty(), "%s: %s shows no error toast (saw %s)" % [label, device.label, device.toasts])
			check(device.error_cards.is_empty(), "%s: %s shows no error card (saw %s)" % [label, device.label, device.error_cards])
			var hub: Node = device.hub()
			# A notice from a step that did fail stays on that hub until the player moves on.
			var kept: bool = hub != null and _notices.get(device, {}).get("hub") == hub and _notices[device].text == hub._message
			if hub != null and not kept: check(hub._message.is_empty(), "%s: %s hub shows no error notice (saw '%s')" % [label, device.label, hub._message])
		elif device.hub() != null:
			_notices[device] = {"hub": device.hub(), "text": device.hub()._message}

func _check_screen(device: Node, label: String) -> void:
	var app: Node = device.app
	var child: Node = device.child()
	if child != null:
		var ways: Array = device.buttons().filter(func(button: Button) -> bool: return child.is_ancestor_of(button))
		check(not ways.is_empty() or child.mode in ["play", "bloom", "replay"], "%s: %s room screen '%s' has a control" % [label, device.label, child.mode])
		return
	if device.hub() != null:
		check(device.hub().visible, "%s: %s hub is visible" % [label, device.label])
		return
	check(not device.buttons().is_empty(), "%s: %s screen '%s' has a control" % [label, device.label, app.mode])
	check(app.mode != "relay_rooms", "%s: %s is not left on the room progress card" % [label, device.label])

func _check_texts(device: Node, label: String) -> void:
	var ids := RegEx.create_from_string("(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{22}(?![A-Za-z0-9_-])")
	for text: String in device.visible_texts():
		check(not text.contains("<null>") and not text.to_lower().contains("null"), "%s: %s shows no null text: %s" % [label, device.label, text])
		for found: RegExMatch in ids.search_all(text):
			var token := found.get_string()
			check(not server.known_id(token), "%s: %s shows no raw id: %s" % [label, device.label, text])

## The hub's list after its own refresh agrees with the server's inbox.
func check_hub_matches(device: Node, label: String) -> void:
	var hub: Node = device.hub()
	if hub == null or device.app.room_hub_flow.inbox == null or device.app.room_hub_flow.inbox.stale: return
	var shown := {}
	for room: Dictionary in device.app.room_hub_flow.inbox.view().rooms: shown[str(room.room_id)] = str(room.status)
	var expected: Dictionary = server.inbox_statuses(device.player_id)
	for room_id: String in expected:
		if expected[room_id] == "completed": continue
		check(shown.get(room_id) == expected[room_id] or (expected[room_id] == "closed" and not shown.has(room_id)), "%s: %s hub shows room %s as %s (server %s)" % [label, device.label, room_id.left(4), shown.get(room_id, "missing"), expected[room_id]])
	for room_id: String in shown:
		if shown[room_id] in ["completed", "closed"]: continue
		check(expected.has(room_id), "%s: %s hub lists a room the server does not (%s, %s)" % [label, device.label, room_id.left(4), shown[room_id]])

## Request budget: while nobody does anything, each phone sends at most one
## room read per 3 s poll. Four polls' worth of time pass (see elapse()), so a
## phone may send four reads, plus one inbox read on a hub; more is a loop.
func watch_idle(label: String) -> void:
	var before := {}
	for device: Node in devices: before[device] = device.api.requests.size() if device.running() else 0
	for poll in 4:
		for device: Node in devices: elapse(device)
		await frames(12)
	for device: Node in devices:
		if not device.running(): continue
		var sent: Array = device.api.requests.slice(before[device])
		check(sent.size() <= 5, "%s: %s stays quiet while idle (%d requests: %s)" % [label, device.label, sent.size(), sent.map(func(item: Dictionary) -> String: return item.path)])

# Player actions. Each presses the control a player would press, in the
# current screen, and returns without waiting for the result (step settles).

func press(device: Node, which: String, times: int = 1) -> bool:
	var target: Button = device.button(which)
	if target == null: return false
	for i in times: target.pressed.emit()
	_hold_play_clock(device)
	return true

## Home -> Play with your friend.
func open_hub(device: Node) -> void:
	if device.hub() != null: return
	if device.child() != null: return
	if device.app.mode != "home": device.app._show_home()
	press(device, "Play with your friend")

## Hub: choose relay-isles@2 and press Host a room (`times` presses).
func host_room(device: Node, visibility: String = "friends", times: int = 1) -> bool:
	var hub: Node = device.hub()
	if hub == null: return false
	hub._choose_chapter(RELAY)
	hub._set_visibility("Invitation only" if visibility == "invitation_only" else "Friends")
	return press(device, "HostRoom", times)

## The room-<code> text the host shares, read from the host's room card.
func invitation(device: Node) -> String:
	if not device.running() or device.app.relay_session == null: return ""
	var code: String = device.app.relay_session.invitation_code()
	return "" if code.is_empty() else "room-" + code

## Hub: type a code and press Join.
func join_room(device: Node, code: String, times: int = 1) -> bool:
	var hub: Node = device.hub()
	if hub == null: return false
	hub._join_code.text = code
	hub._update_join()
	return press(device, "Join", times)

## Hub: the room card's main action (Open, Continue or Watch replay).
func open_room_card(device: Node, room_id: String, times: int = 1) -> bool:
	var hub: Node = device.hub()
	if hub == null: return false
	for card: Node in hub._rooms_list.get_children():
		for button: Button in card.find_children("*", "Button", true, false):
			if button.name != "RemoveRoom" and not button.disabled and button.text in ["Open", "Continue", "Watch replay"] and _card_room(hub, card) == room_id:
				for i in times: button.pressed.emit()
				return true
	return false

func _card_room(hub: Node, card: Node) -> String:
	var index := card.get_index()
	return str(hub._visible_rooms[index].room_id) if index < hub._visible_rooms.size() else ""

## Hub: a finished room's "..." menu, then Hide from my list; on any other
## card, the trash button, then the confirm in its dialog.
func remove_room_card(device: Node, room_id: String) -> bool:
	var hub: Node = device.hub()
	if hub == null: return false
	for card: Node in hub._rooms_list.get_children():
		if _card_room(hub, card) != room_id: continue
		var menu_button: Button = card.find_child("RoomMenu", true, false)
		if menu_button != null:
			if menu_button.disabled: return false
			menu_button.pressed.emit()
			var menu: CanvasLayer = hub.room_menu()
			if menu == null: return false
			for row: Button in menu.rows:
				if row.get_meta("menu_id") == "hide":
					row.pressed.emit()
					return true
			return false
		var remove: Button = card.find_child("RemoveRoom", true, false)
		if remove == null or remove.disabled: return false
		remove.pressed.emit()
		var modal: Node = hub._modal
		if not is_instance_valid(modal): return false
		for button: Button in modal.find_children("*", "Button", true, false):
			if button.text in ["Close room", "Remove"]:
				button.pressed.emit()
				return true
	return false

func room_listed(device: Node, room_id: String) -> bool:
	var hub: Node = device.hub()
	return hub != null and hub._visible_rooms.any(func(room: Dictionary) -> bool: return room.room_id == room_id)

func current_room(device: Node) -> String:
	var child: Node = device.child()
	return str(child.journey.snapshot().get("room_id", "")) if child != null else ""

## The fixture this player records now, from the room's stage and role.
func fixture_for(child: Node) -> String:
	var stage: String = child.journey.stage_id()
	var role: String = child.journey.role()
	return ("relay-" if stage == "relay" else "garden-") + role

## Starts a turn and plays `fraction` of its inputs (1.0 plays it to the end).
func play_turn(device: Node, fraction: float = 1.0) -> bool:
	var child: Node = device.child()
	if child == null or child.mode != "ready" or not child.journey.my_turn(): return false
	var recording: Dictionary = fixtures[fixture_for(child)]
	if not press(device, "record"): return false
	if child.mode != "play": return false
	var inputs: Array = Simulation.expand_recording_inputs(recording)
	var count := inputs.size() if fraction >= 1.0 else int(inputs.size() * fraction)
	for index in count:
		child.advance_input(inputs[index])
		if child.mode != "play": break
	if fraction >= 1.0: await _to_review(child)
	return true

## Plays the rest of a turn started by play_turn(fraction < 1).
func finish_turn(device: Node) -> void:
	var child: Node = device.child()
	if child == null or child.mode != "play": return
	var inputs: Array = Simulation.expand_recording_inputs(fixtures[fixture_for(child)])
	for index in range(int(child.sim.snapshot().tick), inputs.size()):
		child.advance_input(inputs[index])
		if child.mode != "play": break
	await _to_review(child)

## Bounded by the clock, like settle(): a loaded machine may take many frames.
func _to_review(child: Node) -> void:
	var deadline := Time.get_ticks_msec() + SETTLE_MS
	while is_instance_valid(child) and Time.get_ticks_msec() < deadline:
		# A first turn ends when the player presses Finish.
		if child.mode == "play" and not child.finish_button.disabled: child.finish_button.pressed.emit()
		# The completion bloom plays out at once; the review follows it.
		if child.mode == "bloom": child._process(child.COMPLETION_DURATION)
		if child.mode not in ["bloom", "turn_wait"]: return
		await frames(1)
	check(not is_instance_valid(child) or child.mode not in ["bloom", "turn_wait"], "a played turn reaches its review (still %s)" % [child.mode if is_instance_valid(child) else "gone"])

## Review -> Save turn, then past the optional photo and the checkpoint card.
func save_turn(device: Node, times: int = 1) -> bool:
	var child: Node = device.child()
	if child == null or child.mode != "review": return false
	if device.button("save") == null:
		var session: RefCounted = child.online_session
		print("      %s: Save turn is disabled (session busy %s, coordinator busy %s, api busy %s, mutations %s)" % [device.label, session.busy(), child.journey.busy(), device.api._queue.busy(), session.mutations_enabled()])
		return false
	var room_id := str(child.journey.snapshot().get("room_id", ""))
	if not saved_turns.has(room_id): saved_turns[room_id] = {}
	saved_turns[room_id][str(child.review.get("recording_hash", ""))] = device.player_id
	return press(device, "save", times)

## Skips an optional photo offer and continues past a stage checkpoint card,
## waiting by the clock for a save or a bloom still on its way to them. Each
## card is answered once; a card that stays is reported, never pressed again.
func continue_after_turn(device: Node) -> void:
	var deadline := Time.get_ticks_msec() + SETTLE_MS
	var answered := ""
	while Time.get_ticks_msec() < deadline:
		var child: Node = device.child()
		if child == null: return
		var card: String = "photo" if child.mode == "photo" or (is_instance_valid(child.reaction_photos) and child.reaction_photos.active) else child.mode
		if card != answered and card == "photo" and (press(device, "Skip") or press(device, "Keep playing")):
			answered = card
			await settle()
		elif card != answered and card == "checkpoint" and press(device, "continue"):
			answered = card
			await settle()
		elif card in ["photo", "checkpoint"] or _child_busy(child):
			await frames(1)
		else:
			return
	check(false, "%s moves on after its turn (at %s)" % [device.label, device.where()])

## A whole turn: play, save, continue.
func take_turn(device: Node) -> bool:
	if not await play_turn(device): return false
	if not save_turn(device): return false
	await settle()
	await continue_after_turn(device)
	return true

## Back from the room screen (Android Back) or the hub's Back.
func back(device: Node) -> void:
	device.system_back()

## The other phone notices changes the way a push or a resume makes it check.
func nudge(device: Node) -> void:
	var child: Node = device.child()
	if child != null: child.online_refresh_queued = true
	elif device.hub() != null: device.app.room_hub_flow.refresh_when_idle(device.hub())

## Brings a phone to its hub with a fresh list, from wherever it is.
func to_hub(device: Node) -> void:
	for attempt in 4:
		if not device.running(): return
		if device.hub() != null: break
		if device.child() != null or device.app.mode in ["relay_rooms", "shared_replays", "shared_memories"]: back(device)
		elif device.app.mode == "home": open_hub(device)
		else: device.app._show_home()
		await settle()
	if device.hub() != null:
		await device.app.room_hub_flow.refresh_when_idle(device.hub())
		await settle()

## Force-quits a phone and starts it again on the same saved state.
func reopen(device: Node) -> void:
	device.force_quit()
	await frames(2)
	device.boot()

## Deletes the app and installs it again: a new identity, nothing saved.
func reinstall(device: Node) -> void:
	device.force_quit()
	await frames(2)
	device.install()

## A host with a room, and a guest who joined it, both in the room.
func hosted_and_joined() -> String:
	await step("host opens the hub", func(): open_hub(host))
	await step("guest opens the hub", func(): open_hub(guest))
	await step("host hosts", func(): host_room(host))
	var room := current_room(host)
	var code := invitation(host)
	await step("guest joins", func(): join_room(guest, code))
	check(current_room(guest) == room and not room.is_empty(), "the guest is in the host's room")
	# The host's waiting card polls every 3 s and sees the friend arrive.
	await step("a few seconds pass", func(): elapse(host))
	return room

## Plays every remaining turn in order, each player when it is their turn.
func play_out(room: String) -> void:
	for turn in 4:
		if server.room_state(room) != "in_play": return
		var active: Variant = server.active_player(room)
		var device: Node = host if active == host.player_id else guest
		if current_room(device) != room:
			await to_hub(device)
			await step(device.label + " opens the room", func(): open_room_card(device, room))
		else:
			await step(device.label + " notices", func(): nudge(device))
		await step(device.label + " takes a turn", func(): await take_turn(device))
	check(server.room_state(room) == "complete", "the room is finished on the server")

## Both phones end at their hubs and tidy up the way a player would: a room
## still in play is closed from the hub, then each closed room is removed.
## Afterwards every room is finished or closed on the server, neither hub lists
## a room in play or a closed one, and no phone keeps a link to a closed room.
func finish() -> void:
	for device: Node in devices:
		if device.running(): await to_hub(device)
	for device: Node in devices:
		if not device.running(): continue
		check(device.hub() != null, "finish: %s reaches its hub (at %s)" % [device.label, device.where()])
		check_hub_matches(device, "finish")
	for device: Node in devices:
		if device.hub() == null: continue
		for room: Dictionary in device.hub()._visible_rooms.duplicate():
			if room.status in ["waiting_for_friend", "your_turn", "waiting_for_their_turn"]:
				await step("%s closes room %s" % [device.label, str(room.room_id).left(4)], remove_room_card.bind(device, room.room_id))
	for device: Node in devices:
		if device.hub() == null: continue
		await step("%s refreshes" % device.label, nudge.bind(device))
		for room: Dictionary in device.hub()._visible_rooms.duplicate():
			if room.status in ["closed", "unavailable"]:
				await step("%s removes room %s" % [device.label, str(room.room_id).left(4)], remove_room_card.bind(device, room.room_id))
	for room_id: String in server.rooms:
		check(server.room_state(room_id) != "in_play", "finish: room %s is finished or closed on the server" % room_id.left(4))
	for device: Node in devices:
		if device.hub() == null: continue
		for room: Dictionary in device.hub()._visible_rooms:
			check(room.status not in ["waiting_for_friend", "your_turn", "waiting_for_their_turn", "closed"], "finish: %s hub no longer lists room %s as %s" % [device.label, str(room.room_id).left(4), room.status])
		for room_id: String in server.rooms:
			if server.room_state(room_id) == "closed": check(not server.linked(device.player_id, room_id), "finish: %s keeps no link to closed room %s" % [device.label, room_id.left(4)])
	check_saved_turns("finish")
	await watch_idle("finish")

## Lets `ms` of wall time pass for this phone's refresh schedulers: the room
## poll, the legacy foreground poll and the notification route retry. The extra
## wait an idle room's backoff added passes too, so one elapse is still one poll.
func elapse(device: Node, ms: int = 3200) -> void:
	if not device.running(): return
	var child: Node = device.child()
	if child != null: _shift(child.refresh_schedule, ms)
	_shift(device.app.foreground_schedule, ms)
	device.app.notification_flow.route_retry_ms -= ms

static func _shift(schedule: RefCounted, ms: int) -> void:
	if schedule == null: return
	schedule._due -= ms + schedule.idle_extra_ms()
	schedule._cooldown_until -= ms

## From the hub, Watch replay on a finished room shows every part at once,
## without a manual refresh; then Back returns home and the hub opens again.
func check_replays(device: Node, room: String, label: String) -> void:
	await to_hub(device)
	await step(device.label + " opens the Completed tab", func(): device.hub()._select_tab("Completed"))
	check(room_listed(device, room), "%s: %s lists the finished room under Completed" % [label, device.label])
	await step(device.label + " taps Watch replay", open_room_card.bind(device, room))
	var key := "chapter:" + room
	var app: Node = device.app
	check(app.mode == "shared_memories" and app.replays_flow.shared_replay_room == key, "%s: %s Watch replay opens that room's replays (at %s)" % [label, device.label, device.where()])
	var parts: Array = app.shared_replays.listed(key) if app.shared_replays != null else []
	if not check(parts.size() == 2, "%s: %s sees both parts of the finished room without a refresh (%d)" % [label, device.label, parts.size()]) and app.shared_replays != null:
		print("      saved rooms %s; memories %d; error '%s'; attempts %s" % [app.shared_replays.rooms().map(func(item: Dictionary) -> String: return str(item.get("family")) + ":" + str(item.get("room_id", "")).left(4)), app.shared_replays.memories(key, true).size(), app.shared_replays.last_error, app.replays_flow._shared_archive_attempts.keys()])
		var session: RefCounted = app.relay_session
		if session != null: print("      busy %s %s %s %s; proven %s; idle %s; transfer %s; index rooms %s; standalone %s" % [session.busy(), app.api._queue.busy(), app.replays_flow._shared_archive_sync, app.replays_flow._shared_photo_sync, session.standalone_room_proven(room), app.replays_flow._replay_save_idle(), session.capabilities.get("replay_transfer_version"), session._index.get("room_ids", []).map(func(id: String) -> String: return id.left(4)), session._index.get("standalone_ids", []).map(func(id: String) -> String: return id.left(4))])
	await step(device.label + " leaves replays", back.bind(device))
	await to_hub(device)

## The phone was registered for turn notifications and the player taps one
## for `room_id` (as the native bridge hands Main a route).
func tap_notification(device: Node, room_id: String, revision: int) -> void:
	var app: Node = device.app
	var notifications: Node = app.turn_notifications
	var next: Dictionary = app.saves.data.settings.duplicate(true)
	next.turn_notifications = true
	app.saves.update_values({"settings": next})
	var epoch := "E".repeat(22)
	notifications._binding = {"schema_version": 1, "owner": device.player_id, "credential_hash": str(device.device_token).sha256_text(), "binding_epoch": epoch}
	notifications._route = {"schema_version": "1", "event_id": "turn-" + room_id.left(12) + str(revision), "kind": "turn_ready", "room_id": room_id, "room_family": "relay", "revision": str(revision), "binding_epoch": epoch}
	app.notification_flow.route_retry_ms = 0
