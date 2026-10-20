extends SceneTree
## The goal beacon (presentation/kit/goal_beacon.gd), turned on by a chapter's
## descriptor "goal_beacon" and built by cooperative_world:
## - its end spots come from the hashed stage alone: every stage of every
##   cooperative and journey chapter gets its first turn's spots (but a route
##   that ends on a condition alone) and its second turn's goal;
## - Turn of the Tide's Slack Water (@1 and @2) gets three post beacons for the
##   first turn and the lantern's for the second, hidden until the screen plays
##   a live turn; an open post's lamp is lit and its pieces move while a shut
##   one stands grey and still with its lamp out; beside a post the live
##   spirit sees only its ring; a ready turn hides them; Reduce motion holds
##   them still; the beacon never folds;
## - at the stage start the posts are off screen, so the edge pointer shows; it
##   is worked out again only when the camera moves; the opening glance brings
##   the posts on screen and the pointer goes;
## - the screen: the first try's opening glance holds the turn at tick 0 and a
##   key ends it; Reduce motion and a second try skip it; a card (pause) ends
##   it and hides the beacon, and resuming shows it again; the goal card names
##   the place;
## - a chapter that does not opt in builds no beacon.
const Registry = preload("res://services/chapter_registry.gd")
const ChapterIndex = preload("res://content/chapters/index.gd")
const Index = preload("res://content/chapters/index.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Journey = preload("res://services/relay_journey.gd")
const Tide = preload("res://tests/turn_of_the_tide_witness.gd")
const V2 = preload("res://tests/turn_of_the_tide_v2_witness.gd")
const GoalBeacon = preload("res://presentation/kit/goal_beacon.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const SLACK := "slack-water"
var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(2340, 1080)
	directory = "user://goal-beacon-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	_spots_of()
	for key: String in ["turn-of-the-tide@1", "turn-of-the-tide@2"]: _slack(key)
	await _screen()
	_opt_in()
	for filename: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("GOAL BEACON: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _spots_of() -> void:
	for key: String in Registry.keys():
		if str(ChapterIndex.data(key).family) not in ["cooperative", "journey"]: continue
		var level := Registry.definition(key)
		for stage: Dictionary in level.stages:
			# The stage as cooperative_world builds it.
			var view: Dictionary = CooperativeCatalog.stage_definition(level, str(stage.id))
			var policy: Dictionary = view.get("source_policy", {})
			var condition_only: bool = str(policy.get("kind", "")) in ["route_endpoint", "signal_route"] and not policy.has("endpoint")
			_check(condition_only or not GoalBeacon.spots_of(view, "a").is_empty(), "%s %s: the first turn's end spots are found (%s)" % [key, stage.id, policy.get("kind", "")])
			_check(not GoalBeacon.spots_of(view, "b").is_empty(), "%s %s: the second turn's goal is found" % [key, stage.id])

## Stage one LOW, then Slack Water's first turn from its start.
func _slack(key: String) -> void:
	var level := Registry.definition(key)
	var initial := Registry.initial_checkpoint(key)
	var one := _stage_one(key, level, initial)
	if one.is_empty(): return
	var a := Simulation.new()
	_check(a.reset(level, SLACK, one.checkpoint, {}, "a"), "%s Slack Water starts" % key)
	var world := _world(key, level, one.checkpoint, false)
	var beacon: GoalBeacon = world._goal_beacon
	_check(is_instance_valid(beacon) and beacon._beacons.a.size() == 3 and beacon._beacons.b.size() == 1, "%s builds three post beacons and the lantern's" % key)
	if not is_instance_valid(beacon): return
	world.present(a.snapshot(), true)
	_check(not beacon.visible and not beacon.shown(), "%s: hidden until the screen plays a live turn" % key)
	world.set_goal_beacon_live(true)
	_check(beacon.visible and beacon._beacons.a.all(func(item: Dictionary) -> bool: return item.root.visible) and not beacon._beacons.b[0].root.visible, "%s: live, the first turn's posts show and the lantern's does not" % key)
	_check(beacon._beacons.a.all(func(item: Dictionary) -> bool: return _tint(item) != item.tints[0]), "%s: every post is shut at the start, so every beacon stands dim" % key)
	var open: Dictionary = a.snapshot().duplicate()
	open.bridges = a.snapshot().bridges.duplicate()
	open.bridges["gate-post"] = true
	world.present(open, false)
	var index: int = beacon._spots.a.map(func(spot: Dictionary) -> String: return spot.surface).find("gate-post")
	_check(index >= 0 and _tint(beacon._beacons.a[index]) == beacon._beacons.a[index].tints[0] and _tint(beacon._beacons.a[(index + 1) % 3]) != beacon._beacons.a[(index + 1) % 3].tints[0], "%s: an open post burns bright while the shut ones stay dim" % key)
	var lit: Dictionary = beacon._beacons.a[index]
	var shut: Dictionary = beacon._beacons.a[(index + 1) % 3]
	_check(_lamp(lit) == GoalBeacon.LAMP_LIT and _lamp(shut) == GoalBeacon.LAMP_OUT and _motion(lit) == 1.0 and _motion(shut) == 0.0, "%s: the open post's lamp is lit and it moves; a shut one's is out and it stands still" % key)
	var beside: Dictionary = open.duplicate()
	beside.players = open.players.duplicate(true)
	beside.players[str(open.active_slot)].x = int(roundf((lit.root as Node3D).position.x * 100.0))
	beside.players[str(open.active_slot)].z = int(roundf((lit.root as Node3D).position.z * 100.0)) - 60
	world.present(beside, false)
	_check(lit.nodes[GoalBeacon.RING].visible and not lit.nodes[GoalBeacon.LAMP].visible and shut.nodes[GoalBeacon.LAMP].visible, "%s: beside a post the live spirit sees only its ring" % key)
	world.present(a.snapshot(), false)
	# The pointer: the posts are far west of the bell, so off screen.
	world._frame_camera()
	beacon.follow(world.camera)
	_check(not beacon.on_screen(world.camera) and beacon._pointer.visible, "%s: at the start every post is off screen and the edge pointer shows" % key)
	_check(beacon._pointer.rotation > PI * 0.5 or beacon._pointer.rotation < -PI * 0.5, "%s: the pointer points west, toward the posts (%.2f rad)" % [key, beacon._pointer.rotation])
	var placed := beacon.placements
	beacon.follow(world.camera)
	beacon.follow(world.camera)
	_check(beacon.placements == placed, "%s: a still camera works the pointer out no more" % key)
	# The opening glance brings the posts on screen.
	var length: float = world.glance_at_goal()
	_check(is_equal_approx(length, world.GLANCE_TO + world.GLANCE_BACK), "%s: the glance runs %.1f s" % [key, length])
	for _frame in range(int(world.GLANCE_TO * 60.0) - 6): world._advance_camera(1.0 / 60.0)
	_check(beacon.on_screen(world.camera) and not beacon._pointer.visible and beacon.placements > placed, "%s: the glance brings the posts on screen and the pointer goes" % key)
	_check(is_zero_approx(world.glance_at_goal()), "%s: with a post on screen there is nothing to glance at" % key)
	world.end_glance()
	# Played to its post: a ready turn hides them.
	Tide.play(a, V2.p1_route(one.checkpoint, "sea-lock") if key.ends_with("@2") else Tide.p1_route(one.checkpoint, "sea-lock"), V2.home_probe())
	world.present(a.snapshot(), false)
	_check(a.can_commit() and not beacon.visible and not beacon._pointer.visible, "%s: a ready turn hides the beacons and the pointer" % key)
	# The second turn's beacon stands at the lantern.
	var b := Simulation.new()
	b.reset(level, SLACK, one.checkpoint, a.export_recording(), "b")
	world.present(b.snapshot(), false)
	_check(beacon.visible and beacon._beacons.b[0].root.visible and not beacon._beacons.a[0].root.visible, "%s: the second turn's beacon shows at the lantern" % key)
	world.set_goal_beacon_live(false)
	_check(not beacon.visible, "%s: out of live play it hides" % key)
	_check(beacon in world._static_keep(), "%s: the beacon is kept out of the static fold" % key)
	_check(_motion(beacon._beacons.b[0]) == 1.0, "%s: the lantern's open beacon moves" % key)
	world.free()
	var still := _world(key, level, one.checkpoint, true)
	_check(_motion(still._goal_beacon._beacons.a[0]) == 0.0, "%s: Reduce motion holds every piece still" % key)
	still.free()

## The screen: the opening glance on @2's Slack Water.
func _screen() -> void:
	var key := "turn-of-the-tide@2"
	var level := Registry.definition(key)
	var one := _stage_one(key, level, Registry.initial_checkpoint(key))
	if one.is_empty(): return
	for reduced: bool in [false, true]:
		var journal := Journey.new(directory.path_join("glance-%s.json" % reduced), null, key)
		journal.load_data()
		for recording: Dictionary in [one.a, one.b]: _check(journal.accept_recording(recording), "Stage one is accepted: " + journal.last_error)
		var screen: Node = load(Index.data(key).scene).instantiate()
		screen.journey = journal
		screen.settings = {"sound": false, "haptics": false, "reduced_motion": reduced, "assistance": true}
		root.add_child(screen)
		screen.set_physics_process(false)
		await process_frame
		screen._begin()
		if reduced:
			_check(not screen._glancing and not screen.world.glancing(), "Reduce motion skips the opening glance")
		else:
			_check(screen._glancing and screen.world.glancing(), "The first try opens with a glance at the posts")
			for _frame in range(10): screen._physics_process(1.0 / 30.0)
			_check(int(screen.sim.tick) == 0 and screen._glancing, "The glance holds the turn at tick 0 (tick %d)" % int(screen.sim.tick))
			var key_press := InputEventKey.new()
			key_press.pressed = true
			key_press.keycode = KEY_SPACE
			screen._input(key_press)
			screen._physics_process(1.0 / 30.0)
			_check(not screen._glancing and int(screen.sim.tick) == 1 and not screen.world.glancing(), "A key ends the glance and the turn starts on the next frame")
			var detail: String = screen.controls.objective_panel.detail_label.text
			_check(detail == PlayerCopy.TURN_OF_THE_TIDE_SLACK_GOAL_A, "The goal card names the place (%s)" % detail)
			var beacon: GoalBeacon = screen.world._goal_beacon
			_check(beacon.visible, "In play the beacons show")
			screen._pause()
			_check(screen.mode == "paused" and not beacon.visible and not beacon._pointer.visible, "The pause card hides the beacons and the pointer")
			screen._start_play()
			_check(beacon.visible, "Resuming shows them again")
			screen._begin()
			_check(screen._live_tries == 2 and not screen._glancing and not screen.world.glancing(), "A second try opens without a glance")
		root.remove_child(screen)
		screen.free()
		await process_frame

## A chapter without "goal_beacon" builds none.
func _opt_in() -> void:
	var key := "turn-of-the-tide@1"
	var level := Registry.definition(key)
	var descriptor: Dictionary = ChapterIndex.data(key).duplicate(true)
	descriptor.goal_beacon = false
	var world: Node3D = Registry.world_script(key).new()
	world.descriptor_override = descriptor
	root.add_child(world)
	world.reduced_motion = true
	world.set_process(false)
	world.load_level(level)
	_check(world._goal_beacon == null and is_zero_approx(world.glance_at_goal()), "Without the descriptor's goal_beacon there is no beacon and no glance")
	world.free()
	for other: String in ChapterIndex.keys():
		if not other.begins_with("turn-of-the-tide"): _check(not ChapterIndex.data(other).goal_beacon, "%s leaves the beacon off" % other)

func _stage_one(key: String, level: Dictionary, initial: Dictionary) -> Dictionary:
	var one: Dictionary = V2.pair(level, "set-the-tide", initial, Tide.a_routes()["low"], Tide.b_routes()["low"]) if key.ends_with("@2") \
		else Tide.pair(level, "set-the-tide", initial, Tide.a_routes()["low"], Tide.b_routes()["low"], true)
	_check(one.error.is_empty(), "%s stage one plays: %s" % [key, one.error])
	return one if one.error.is_empty() else {}

func _world(key: String, level: Dictionary, checkpoint: Dictionary, reduced: bool) -> Node3D:
	var world: Node3D = Registry.world_script(key).new()
	root.add_child(world)
	world.reduced_motion = reduced
	world.set_process(false)
	world.load_level(level)
	world.show_stage(level.stages[1])
	world.present_history(checkpoint)
	return world

func _tint(beacon: Dictionary) -> Color:
	return Color((beacon.materials[0] as ShaderMaterial).get_shader_parameter("tint"))

func _motion(beacon: Dictionary) -> float:
	return float((beacon.materials[0] as ShaderMaterial).get_shader_parameter("motion"))

func _lamp(beacon: Dictionary) -> Color:
	return Color((beacon.materials[GoalBeacon.LAMP] as ShaderMaterial).get_shader_parameter("tint"))

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
