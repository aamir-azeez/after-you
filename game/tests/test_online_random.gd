extends SceneTree
## Seeded random walks through Play with a friend on two phones: every step is
## a real player action on a random phone (taps, double taps, Back, leaving,
## backgrounding, force quits, a lost or refused request, time passing). The
## harness checks every invariant after each step. Seeds are fixed so a failure
## repeats; AFTER_YOU_HARNESS_SEEDS="a,b,c" and AFTER_YOU_HARNESS_STEPS override.
const Harness = preload("res://tests/online_harness/harness.gd")
const UserFiles = preload("res://tests/online_harness/user_files.gd")
const SEEDS := [11, 23]
const STEPS := 45
var h: Node
var rng := RandomNumberGenerator.new()

## This suite's seeds; test_online_random_more and _extra walk four others.
func seeds() -> Array:
	return SEEDS

func suite_name() -> String:
	return "Online random walks"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var files := UserFiles.new()
	h = Harness.new()
	h.trace = OS.get_environment("AFTER_YOU_HARNESS_TRACE") == "1"
	root.add_child(h)
	var walk_seeds: Array = seeds()
	if not OS.get_environment("AFTER_YOU_HARNESS_SEEDS").is_empty():
		walk_seeds = Array(OS.get_environment("AFTER_YOU_HARNESS_SEEDS").split(",")).map(func(item: String) -> int: return int(item))
	var steps := int(OS.get_environment("AFTER_YOU_HARNESS_STEPS")) if not OS.get_environment("AFTER_YOU_HARNESS_STEPS").is_empty() else STEPS
	for seed: int in walk_seeds:
		await _walk(seed, steps)
	h.print_slowest()
	h.end()
	await process_frame
	files.cleanup()
	print("%s: %d checks, %d failures" % [suite_name(), h.checks, h.failures])
	quit(1 if h.failures else 0)

func _walk(seed: int, steps: int) -> void:
	rng.seed = seed
	await h.begin("random walk %d" % seed, seed)
	var before: int = h.failures
	for index in steps:
		var device: Node = h.host if rng.randi() % 2 == 0 else h.guest
		var action: String = _choose(device)
		await h.step("%02d %s %s" % [index, device.label, action], _act.bind(device, action), [device] if action.begins_with("fault") or action in ["reinstall", "join stale code"] else [])
		if h.failures > before:
			print("random walk %d: first failure at step %d; rerun with AFTER_YOU_HARNESS_SEEDS=%d AFTER_YOU_HARNESS_TRACE=1" % [seed, index, seed])
			break
	# However the walk went, every room both players are in can still be
	# played to the end, and its replay then opens whole on both phones.
	for room_id: String in h.server.rooms.keys():
		var room: Dictionary = h.server.rooms[room_id]
		if h.server.room_state(room_id) != "in_play" or room.guest_id == null: continue
		if h.host.player_id not in [room.host_id, room.guest_id] or h.guest.player_id not in [room.host_id, room.guest_id]: continue
		await h.play_out(room_id)
		for device: Node in [h.host, h.guest]: await h.check_replays(device, room_id, "random walk %d" % seed)
	await h.finish()

## Weighted choice among the actions that make sense on this screen.
func _choose(device: Node) -> String:
	var options: Dictionary = {"back": 3, "background": 1, "force quit": 1, "time passes": 2, "fault next request": 1}
	var child: Node = device.child()
	if child != null:
		match str(child.mode):
			"ready":
				if child.journey.my_turn(): options.merge({"take turn": 8, "start turn": 2, "double save": 2})
				else: options.merge({"refresh": 2})
			"online_waiting": options.merge({"refresh": 3, "check saved": 2})
			"play": options.merge({"finish turn": 6})
			"review": options.merge({"save": 6, "double save": 2})
			"checkpoint", "photo": options.merge({"continue": 6, "double continue": 1})
			"complete": options.merge({"back": 4})
	elif device.hub() != null:
		# Mostly one shared game at a time, the way two friends play.
		var rooms: Array = device.hub()._visible_rooms
		var active := rooms.filter(func(room: Dictionary) -> bool: return room.status != "completed").size()
		var my_turn := rooms.any(func(room: Dictionary) -> bool: return room.status == "your_turn")
		options.merge({"open room": 8 if my_turn else 2, "double open room": 1, "remove room": 1, "refresh hub": 2, "join stale code": 1})
		if active < 2: options.merge({"host": 3, "double host": 1})
		if not _code_from(_other(device)).is_empty(): options.merge({"join": 8, "double join": 2})
	else:
		options.merge({"open hub": 6})
	if rng.randi() % 40 == 0: options["reinstall"] = 1
	var total := 0
	for weight: int in options.values(): total += weight
	var pick := rng.randi() % total
	for name: String in options:
		pick -= int(options[name])
		if pick < 0: return name
	return "time passes"

func _other(device: Node) -> Node:
	return h.guest if device == h.host else h.host

func _act(device: Node, action: String) -> void:
	if not device.running() and action != "force quit":
		device.boot()
		return
	match action:
		"back": h.back(device)
		"background":
			device.background()
			await h.frames(5)
			device.foreground()
		"force quit": await h.reopen(device)
		"reinstall": await h.reinstall(device)
		"time passes":
			h.elapse(device)
			h.elapse(_other(device))
		"fault next request":
			var kinds := ["drop_after", "drop_before", "status"]
			device.api.faults.append({"path": "", "kind": kinds[rng.randi() % kinds.size()], "status": 503, "code": "service_unavailable"})
			h.nudge(device)
		"take turn": await h.take_turn(device)
		"start turn": await h.play_turn(device, 0.4)
		"finish turn": await h.finish_turn(device)
		"save": h.save_turn(device)
		"double save":
			if device.child() != null and device.child().mode == "ready": await h.play_turn(device)
			h.save_turn(device, 2)
		"continue": await h.continue_after_turn(device)
		"double continue": h.press(device, "continue", 2)
		"refresh": h.nudge(device)
		"check saved":
			if not h.press(device, "check_saved"): h.nudge(device)
		"open hub": h.open_hub(device)
		"refresh hub": h.nudge(device)
		"host": h.host_room(device)
		"double host": h.host_room(device, "friends", 2)
		"join", "double join":
			var code: String = _code_from(_other(device))
			if not code.is_empty(): h.join_room(device, code, 2 if action == "double join" else 1)
		"join stale code":
			var codes: Array = h.server.rooms.values().filter(func(room: Dictionary) -> bool: return room.deleted).map(func(room: Dictionary) -> String: return "room-" + room.invite_code)
			if not codes.is_empty(): h.join_room(device, codes[rng.randi() % codes.size()])
		"open room", "double open room":
			var rooms: Array = device.hub()._visible_rooms
			var turns: Array = rooms.filter(func(room: Dictionary) -> bool: return room.status == "your_turn")
			if not turns.is_empty() and rng.randi() % 10 < 7: rooms = turns
			if not rooms.is_empty(): h.open_room_card(device, rooms[rng.randi() % rooms.size()].room_id, 2 if action == "double open room" else 1)
		"remove room":
			var rooms: Array = device.hub()._visible_rooms
			if not rooms.is_empty(): h.remove_room_card(device, rooms[rng.randi() % rooms.size()].room_id)

## The newest open invitation the other player hosts: what they would share.
func _code_from(other: Node) -> String:
	var best := ""
	var newest := ""
	for room: Dictionary in h.server.rooms.values():
		if room.host_id == other.player_id and not room.deleted and room.guest_id == null and str(room.created_at) > newest:
			newest = str(room.created_at)
			best = "room-" + str(room.invite_code)
	return best
