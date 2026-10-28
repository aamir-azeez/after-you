extends SceneTree
## Step seats (journey_world.gd, the descriptor's "seats"): whoever holds a
## seat's step sits on its prop while still, and stands the tick it moves.
## - Turn of the Tide as shipped seats nobody: its bollard stands on the mill
##   quay's back fender beside the bollard step (its dressing), clear of the
##   step and of a spirit anywhere on its stand spot, and whoever holds the
##   step stands on the spot.
## - Seated by a stand-in descriptor (the bollard as a seat): the HIGH memory
##   sits on it once it has stopped on the bollard step; the first spirit does
##   in its own turn.
## - Sitting never holds a move back: the first input moves the spirit on its
##   own tick and it is up that same tick.
## - Data alone: a stand-in descriptor seating the quay step instead seats
##   the HALF route's spirit there, and builds no bollard seat.
const Registry = preload("res://services/chapter_registry.gd")
const ChapterIndex = preload("res://content/chapters/index.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Tide = preload("res://tests/turn_of_the_tide_witness.gd")
const SpiritIdle = preload("res://presentation/spirit_idle.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const Props = preload("res://presentation/kit/props.gd")
const Dressing = preload("res://content/dressing/turn_of_the_tide.gd")
## A spirit's body radius beyond the point that holds a pad (metres).
const SPIRIT_RADIUS := 0.12
const KEY := "turn-of-the-tide@1"
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_bollard_beside()
	_memory_sits()
	_first_input_stands()
	_data_alone()
	_seat_folds()
	print("STEP SEATS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## As shipped, nobody sits: the bollard nearest the bollard step stands off
## the step, clear of a spirit anywhere on its stand spot, and the spirit
## holding the step stands.
func _bollard_beside() -> void:
	var a := _first_turn("high")
	var world := _world(ChapterIndex.data(KEY))
	_check(ChapterIndex.data(KEY).seats.is_empty() and world.terrain.find_child("Seat_bollard-pad", true, false) == null, "The bollard step has no seat")
	var level := Registry.definition(KEY)
	var pad: Dictionary = level.stages[0].pressure_pads.filter(func(item: Dictionary) -> bool: return item.id == "bollard-pad")[0]
	var spot := Vector2(pad.position_cm[0], pad.position_cm[1]) / 100.0
	var nearest := {}
	for spec: Dictionary in Dressing.DATA.props["*"]:
		if spec.get("kind") != "bollard": continue
		var at := Vector2(spec.at[0], spec.at[1]) / 100.0
		if nearest.is_empty() or at.distance_to(spot) < nearest.at.distance_to(spot): nearest = {"at": at, "radius": (Props.extent(spec).rect as Rect2).size.x * 0.5}
	var step: Array = level.bridges.filter(func(route: Dictionary) -> bool: return route.id == "bollard-step")[0].rect_cm
	var on_step := Rect2(Vector2(step[0], step[1]) / 100.0, Vector2(step[2] - step[0], step[3] - step[1]) / 100.0)
	var footprint := Rect2(nearest.at - Vector2.ONE * nearest.radius, Vector2.ONE * nearest.radius * 2.0)
	_check(nearest.at.distance_to(spot) < 0.8 and not on_step.intersects(footprint), "The bollard step's bollard stands beside it, off the step (%s)" % nearest.at)
	_check(nearest.at.distance_to(spot) - nearest.radius > float(pad.radius_cm) / 100.0 + SPIRIT_RADIUS, "A spirit anywhere on the step's spot stays clear of the bollard")
	world.present(a.snapshot(), true)
	for _tick in range(3): world.present(a.step({}), false)
	_check(world.actors.p0.pose() == SpiritIdle.REST, "The spirit holding the bollard step stands on its spot")
	world.free()

## The bollard as a seat on the step, as Turn of the Tide had it before.
func _seated() -> Dictionary:
	var descriptor: Dictionary = ChapterIndex.data(KEY).duplicate(true)
	descriptor["seats"] = {"bollard-pad": {"kind": "bollard", "size": 1.6}}
	return descriptor

## B's turn on the HIGH memory: the memory reaches the bollard step at t416
## and sits once it has stopped; the live spirit never sits on another's step.
func _memory_sits() -> void:
	var level := Registry.definition(KEY)
	var checkpoint := Catalog.initial_checkpoint(level)
	var a := Tide.source(level, Tide.SET, checkpoint, Tide.a_routes()["high"], 0, Callable(), true)
	var b := Simulation.new()
	_check(b.reset(level, Tide.SET, checkpoint, a.export_recording(), "b"), "B's turn starts on the HIGH memory")
	var world := _world(_seated())
	world.present(b.snapshot(), true)
	var arrived := -1
	while b.tick < 430 and not b.finished:
		var state: Dictionary = b.step({})
		world.present(state, false)
		if arrived < 0 and bool(state.hold_pads.get("bollard-pad", false)): arrived = int(state.tick)
	_check(arrived == 416, "The memory reaches the bollard step at t416 (t%d)" % arrived)
	_check(world.actors.p0.pose() == SpiritIdle.SIT, "The memory sits on the bollard once it has stopped there")
	_check(world.actors.p1.pose() == SpiritIdle.REST, "The live spirit is not seated by another's step")
	world.free()

## The first spirit sits on the bollard step in its own turn; its first move
## is taken on the same tick and it is up at once.
func _first_input_stands() -> void:
	var a := _first_turn("high")
	var world := _world(_seated())
	world.present(a.snapshot(), true)
	for _tick in range(3): world.present(a.step({}), false)
	_check(world.actors.p0.pose() == SpiritIdle.SIT, "The live spirit on the bollard step sits on its bollard")
	var before: Dictionary = a.snapshot().players.p0
	var moved: Dictionary = a.step({"move_x": 0.0, "move_z": 1.0})
	world.present(moved, false)
	_check(int(moved.players.p0.z) != int(before.z), "The first input moves the spirit on its own tick")
	_check(world.actors.p0.pose() == SpiritIdle.REST, "It is up the same tick it moves")
	world.free()

## A stand-in descriptor seats the quay step (a barrel) and not the bollard.
func _data_alone() -> void:
	var descriptor: Dictionary = ChapterIndex.data(KEY).duplicate(true)
	descriptor["seats"] = {"quay-step-pad": {"kind": "barrel"}}
	var a := _first_turn("half")
	var world := _world(descriptor)
	_check(world.terrain.find_child("Seat_quay-step-pad", true, false) != null and world.terrain.find_child("Seat_bollard-pad", true, false) == null, "Data alone: the seat stands on the step the descriptor names")
	world.present(a.snapshot(), true)
	for _tick in range(3): world.present(a.step({}), false)
	_check(world.actors.p0.pose() == SpiritIdle.SIT, "Data alone: the spirit holding that step sits on it")
	world.free()

## The seat is plain scenery: it folds with the rest, and the spirit holding
## its step still sits on it afterwards.
func _seat_folds() -> void:
	var a := _first_turn("high")
	var world := _world(_seated())
	var seat: Node3D = world.terrain.find_child("Seat_bollard-pad", true, false)
	var before := seat.find_children("*", "MeshInstance3D", true, false).size()
	world._bubbles_placed = true
	world.fold_over_frames = false
	world._fold_static_scenery()
	_check(world.terrain.has_meta(StaticBatch.FOLDED_META) and seat.find_children("*", "MeshInstance3D", true, false).size() < before, "The seat folds with the scenery (%d meshes before)" % before)
	world.present(a.snapshot(), true)
	for _tick in range(3): world.present(a.step({}), false)
	_check(world.actors.p0.pose() == SpiritIdle.SIT, "After the fold the spirit holding the step still sits")
	world.free()

func _first_turn(route: String) -> RefCounted:
	var level := Registry.definition(KEY)
	return Tide.source(level, Tide.SET, Catalog.initial_checkpoint(level), Tide.a_routes()[route], 0, Callable(), true)

func _world(descriptor: Dictionary) -> Node3D:
	var level := Registry.definition(KEY)
	var world: Node3D = Registry.world_script(KEY).new()
	world.descriptor_override = descriptor
	root.add_child(world)
	world.reduced_motion = true
	world.set_process(false)
	world.load_level(level)
	world.show_stage(level.stages[0])
	world.present_history(Catalog.initial_checkpoint(level))
	return world

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
