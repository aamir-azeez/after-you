extends SceneTree
## Open turns (core/physical/open_turns.gd) never say a turn's part is done,
## and every open turns chapter gets the goal beacon (kit/goal_beacon.gd) as a
## late guide, with no code of its own (owner, 2026-11-16):
## - on every open turns chapter's solo screen a first turn that may be saved
##   keeps its own hint (no ready line), shows no count of its part and leaves
##   the waiting spot unlit; there is no opening glance, the guide stays hidden
##   until the turn has played GUIDE_AFTER_TICKS and shows then;
## - in a later turn the guide stands on the stage's goal once due, and the
##   edge pointer points at it; a goal found first keeps it hidden; a new try
##   waits again; a hard run, a replay (not live) and a complete stage hide it;
## - published rules are unchanged: the ready line, the card's count and the
##   lit waiting spot still show, and Turn of the Tide's beacon shows at once,
##   in a hard run too.
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const Journey = preload("res://services/relay_journey.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const GoalBeacon = preload("res://presentation/kit/goal_beacon.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
## A published journey chapter whose first stage has a waiting spot.
const PUBLISHED := "long-way-home@2"
const PUBLISHED_BEACON := "turn-of-the-tide@1"
var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(2340, 1080)
	directory = "user://open-hints-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var open: Array[String] = []
	for key: String in Registry.keys():
		if Registry.is_journey(key) and OpenTurns.pinned(Registry.definition(key)): open.append(key)
	_check(open.size() >= 3 and "long-way-home@3" in open and "conservatory@2" in open, "Every open turns chapter is checked: %s" % [open])
	for key: String in open:
		await _first_turn(key, true)
		await _guide(key)
	_check(not OpenTurns.pinned(Registry.definition(PUBLISHED)), "%s plays published rules" % PUBLISHED)
	await _first_turn(PUBLISHED, false)
	await _published_beacon()
	for filename: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("OPEN HINTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The first turn through the chapter's own solo screen.
func _first_turn(key: String, open: bool) -> void:
	var journal := Journey.new(directory.path_join("%s.json" % key.replace("@", "-")), null, key)
	journal.load_data()
	var screen: Node = load(Index.data(key).scene).instantiate()
	screen.journey = journal
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": false, "assistance": true}
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.set_process(false)
	await process_frame
	screen.world.set_process(false)
	screen._begin()
	_check(screen.mode == "play" and screen.role == "a", "%s: the first turn plays" % key)
	_check(not screen._glancing, "%s: no opening glance at the goal" % key)
	screen.advance_input({})
	var state: Dictionary = screen.sim.snapshot()
	var saved := state.duplicate()
	saved.can_commit = true
	var waiting := state.duplicate()
	waiting.can_commit = false
	screen._update_hud(waiting)
	var hint: String = screen.controls.hint_label.text
	screen._update_hud(saved)
	var ready: String = screen.controls.hint_label.text
	screen.world.present(saved, false)
	var ring: MeshInstance3D = screen.world.get("_waiting_ring")
	var lit := is_instance_valid(ring) and (ring.material_override as StandardMaterial3D).emission_enabled
	if open:
		_check(screen.sim.can_commit() and ready == hint and ready != PlayerCopy.MAIN_1AAC5BE95E22 and not hint.is_empty(), "%s: a turn that may be saved keeps its own hint, no ready line (%s)" % [key, ready])
		_check(state.get("objective_display", {}).is_empty() and not screen.controls.objective_panel.value_label.visible, "%s: no card counts the first turn's part" % key)
		_check(not lit, "%s: the waiting spot stays unlit" % key)
		var beacon: GoalBeacon = screen.world._goal_beacon
		_check(is_instance_valid(beacon) and beacon.guide, "%s: the guide is built from open turns alone" % key)
		if is_instance_valid(beacon):
			while int(screen.sim.tick) < GoalBeacon.GUIDE_AFTER_TICKS - 1 and screen.mode == "play": screen.advance_input({})
			_check(int(screen.sim.tick) == GoalBeacon.GUIDE_AFTER_TICKS - 1 and not beacon.visible and not beacon.shown(), "%s: the guide stays hidden for the first %d ticks" % [key, GoalBeacon.GUIDE_AFTER_TICKS - 1])
			screen.advance_input({})
			var due: bool = not beacon._spots.get("a", []).is_empty()
			_check(beacon.visible == due and beacon.shown() == due, "%s: on tick %d the guide shows at the first turn's end spot (%d spots)" % [key, int(screen.sim.tick), beacon._spots.get("a", []).size()])
	else:
		_check(ready == PlayerCopy.MAIN_1AAC5BE95E22 and hint != ready, "%s: published rules still say the turn is ready" % key)
		var card: Dictionary = state.get("objective_display", {})
		_check(card.has("label") and card.has("current") and not state.has("turn_number"), "%s: published rules keep the first turn's card and snapshot" % key)
		_check(is_instance_valid(ring) and lit, "%s: published rules light the waiting spot" % key)
		_check(screen.world._goal_beacon == null, "%s: published rules build no guide" % key)
	root.remove_child(screen)
	screen.free()
	await process_frame

## A later turn over an early first turn: the guide at the stage's goal.
func _guide(key: String) -> void:
	var level := Registry.definition(key)
	var stage: Dictionary = level.stages[0]
	var start := Registry.initial_checkpoint(key)
	var simulation: Script = Registry.simulation_script(key)
	var a: RefCounted = simulation.new()
	a.reset(level, stage.id, start, {}, "a")
	for _tick in range(5): a.step({})
	var b: RefCounted = simulation.new()
	_check(b.reset(level, stage.id, start, a.export_recording(), "b"), "%s: a later turn plays over an early first turn (%s)" % [key, b.error])
	var world: Node3D = Registry.world_script(key).new()
	root.add_child(world)
	world.reduced_motion = true
	world.set_process(false)
	await world.load_level(level)
	world.present_history(start)
	var beacon: GoalBeacon = world._goal_beacon
	var view := CooperativeCatalog.stage_definition(level, str(stage.id))
	_check(is_instance_valid(beacon) and beacon._beacons.b.size() == 1 and (beacon._beacons.b[0].root as Node3D).position.is_equal_approx(world._at(view.goal)), "%s: the later turns' guide stands on the stage's goal" % key)
	if not is_instance_valid(beacon):
		world.free()
		return
	world.set_goal_beacon_live(true)
	world.present(b.snapshot(), true)
	_check(not beacon.visible, "%s: at the turn's start the guide is hidden" % key)
	_check(int(b.duration_limit()) > GoalBeacon.GUIDE_AFTER_TICKS, "%s: a turn runs past the guide's wait (%d ticks)" % [key, int(b.duration_limit())])
	while int(b.tick) < GoalBeacon.GUIDE_AFTER_TICKS - 1: b.step({})
	world.present(b.snapshot(), false)
	_check(not beacon.visible, "%s: one tick before its wait the guide is still hidden" % key)
	var due: Dictionary = b.step({})
	world.present(due, false)
	_check(beacon.visible and beacon._beacons.b[0].root.visible and not b.can_commit(), "%s: once due the guide shows at the goal" % key)
	# The goal off screen: the edge pointer points at it.
	world._frame_camera()
	world.camera.global_position += Vector3(40.0, 0.0, 40.0)
	beacon.follow(world.camera)
	var lamp: Vector3 = (beacon._beacons.b[0].root as Node3D).global_position + Vector3(0, GoalBeacon.MAST_HEIGHT, 0)
	var camera: Camera3D = world.camera
	var rect: Rect2 = camera.get_viewport().get_visible_rect()
	var centre: Vector2 = Rect2(rect.position + rect.size * GoalBeacon.SAFE.position, rect.size * GoalBeacon.SAFE.size).get_center()
	var toward: float = (camera.unproject_position(lamp) - centre).angle()
	_check(beacon._pointer.visible and absf(angle_difference(beacon._pointer.rotation, toward)) < 0.01, "%s: with the goal off screen the edge pointer points at it (%.2f, %.2f rad)" % [key, beacon._pointer.rotation, toward])
	# Ended: hidden only when the stage is complete.
	var complete := due.duplicate()
	complete.complete = true
	world.present(complete, false)
	_check(not beacon.visible, "%s: a complete stage hides the guide" % key)
	world.present(due, false)
	# A new try waits again, and a goal found first keeps it hidden.
	var restart := due.duplicate()
	restart.tick = 0
	world.present(restart, false)
	_check(not beacon.visible, "%s: a new try waits again" % key)
	var found := restart.duplicate()
	found.tick = 10
	found.players = restart.players.duplicate(true)
	found.players[str(found.active_slot)].x = int(view.goal.position_cm[0])
	found.players[str(found.active_slot)].z = int(view.goal.position_cm[1])
	world.present(found, false)
	var late := due.duplicate()
	late.tick = GoalBeacon.GUIDE_AFTER_TICKS + 30
	world.present(late, false)
	_check(beacon._guide == GoalBeacon.FOUND and not beacon.visible, "%s: a goal found before the wait keeps the guide hidden that try" % key)
	# Hard runs and replays.
	world.present(restart, false)
	world.set_goal_beacon_live(true, true)
	world.present(late, false)
	_check(not beacon.visible, "%s: a hard run never shows the guide" % key)
	world.set_goal_beacon_live(true)
	_check(beacon.visible, "%s: out of a hard run it shows once due" % key)
	world.set_goal_beacon_live(false)
	_check(not beacon.visible and not beacon._pointer.visible, "%s: out of live play (a replay) it hides" % key)
	world.free()

## Turn of the Tide's published beacon: built from its descriptor, shown at
## once, in a hard run too.
func _published_beacon() -> void:
	var key := PUBLISHED_BEACON
	var level := Registry.definition(key)
	var stage: Dictionary = level.stages[0]
	var start := Registry.initial_checkpoint(key)
	var a: RefCounted = Registry.simulation_script(key).new()
	a.reset(level, stage.id, start, {}, "a")
	var world: Node3D = Registry.world_script(key).new()
	root.add_child(world)
	world.reduced_motion = true
	world.set_process(false)
	await world.load_level(level)
	world.present_history(start)
	var beacon: GoalBeacon = world._goal_beacon
	_check(is_instance_valid(beacon) and not beacon.guide, "%s: the descriptor's beacon is no guide" % key)
	if is_instance_valid(beacon):
		world.set_goal_beacon_live(true, true)
		world.present(a.snapshot(), true)
		_check(beacon.visible and beacon.shown(), "%s: its beacon shows at the turn's start, in a hard run too" % key)
	world.free()

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
