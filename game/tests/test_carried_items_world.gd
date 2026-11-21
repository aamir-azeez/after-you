extends SceneTree
## Rules 16's looks in the journey world (presentation/journey_world.gd
## _build_items, _present_items) on the witness level (tests/carried_items_level.gd),
## from the real engine's snapshots:
## - each item in its style (a pin by id, the slot's default, a float as a raft),
##   every style of both slots built (kit/pieces/carried_item.gd, current.gd);
## - picked up, the item is held over the carrier's head, its middle on the
##   spirit's carry point as the seed and the lens are; put down, it rests at its
##   place; a float rests on the water by the float rule (kit/floats.gd): its
##   keel its draft under the surface, its deck clear of it;
## - the both-hands ladder wears rungs, so a carrier's stop has its cause;
## - the current's legs are bright while their wheel shows their value;
## - what moves is kept whole by the static fold.
const World = preload("res://presentation/journey_world.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Level = preload("res://tests/carried_items_level.gd")
const CarriedItemKit = preload("res://presentation/kit/pieces/carried_item.gd")
const Floats = preload("res://presentation/kit/floats.gd")
const CurrentKit = preload("res://presentation/kit/pieces/current.gd")
const Styles = preload("res://content/dressing/prop_styles.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	# The seed style asks a world for its meshes (presentation/seed_visual.gd).
	var holder := IslandWorld.new()
	root.add_child(holder)
	for style: String in Styles.SLOTS.carried_item:
		var piece: RefCounted = CarriedItemKit.build(style, Vector3.ZERO, holder, {"id": style, "world": holder})
		_check(piece.style == style and _meshes(piece.root) > 0 and piece.moving_parts() == [piece.root], "Carried item %s builds and keeps its root moving" % style)
	_check(CarriedItemKit.build("teapot", Vector3.ZERO, holder).style == "parcel", "An unknown item style builds the parcel")
	for style: String in Styles.SLOTS.current:
		var piece: RefCounted = CurrentKit.build(style, [{"from": Vector3.ZERO, "to": Vector3(2, 0, 0), "control_id": "c", "value": "v"}], holder)
		_check(piece.style == style and piece.moving_parts().size() == 2 and _meshes(piece.root) == 2 and (piece.moving_parts()[0].get_child(0) as MeshInstance3D).mesh.get_faces().size() >= 6 * 36, "Current %s lays its marks in a bright row and a faint one, one mesh a row" % style)
	holder.free()
	await _world()
	print("CARRIED ITEMS WORLD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _world() -> void:
	var level := Level.definition()
	var start := Level.initial_checkpoint(level)
	var world: Node3D = World.new()
	world.descriptor_override = {"piece_styles": {"pipsport": "pipsport"}}
	root.add_child(world)
	world.reduced_motion = true
	world.set_process(false)
	await world.load_level(level)
	var pieces: Dictionary = world._item_pieces
	_check(pieces.has("pipsport") and pieces.pipsport.style == "pipsport" and pieces.raft.style == "raft", "The pipsport wears its pinned style and the float is a raft")
	_check(world._current_piece == null, "A stage with no current legs builds none")
	_check(_meshes_within(world.terrain, Rect2(-1.0, -0.32, 1.0, 0.64)) >= 8, "The both-hands ladder wears rungs")
	var keep: Array = world._static_keep()
	_check(keep.has(pieces.pipsport.root) and keep.has(pieces.raft.root), "Items are kept whole by the static fold")
	var sim := Simulation.new()
	sim.simulation_version = int(level.simulation_version)
	sim._reset_trusted(level, "hand-up", start, {}, "a")
	world.present(sim.snapshot(), true)
	_check(pieces.pipsport.root.get_parent() == world.terrain and pieces.pipsport.root.position.is_equal_approx(world._at({"position_cm": [-350, 80], "surface_id": "dock"})), "At first the pipsport rests in the post box")
	_check(pieces.raft.root.get_parent() == world.terrain and pieces.raft.moving(), "The raft floats at its mooring")
	var surface: float = world._item_point(sim.snapshot().mechanisms.items.raft).y
	_check(is_equal_approx(pieces.raft.root.position.y, surface - float(Floats.kind("raft").draft)), "The raft sits its draft deep, its deck over the water")
	_walk(sim, [-350, 60])
	sim.step({})
	sim.step({"interact": true})
	world.present(sim.snapshot(), true)
	var held: Node3D = pieces.pipsport.root
	var p0: Node3D = world.actors.get("p0")
	_check(p0 != null and pieces.pipsport.holder == p0 and held.get_parent() == world.terrain and (held.position + held.basis * pieces.pipsport.middle).is_equal_approx(p0.carry_point()), "Picked up, it is held over the carrier's head, on the carry point")
	_check(p0 != null and p0.carrying_seed and is_equal_approx(p0.carried_radius, pieces.pipsport.radius) and held.scale.is_equal_approx(Vector3.ONE), "The pip carries it at its own size, as it carries the seed")
	_walk(sim, [-250, 0])
	sim.step({})
	sim.step({"interact": true})
	world.present(sim.snapshot(), true)
	_check(pieces.pipsport.root.get_parent() == world.terrain and pieces.pipsport.root.position.is_equal_approx(world._at({"position_cm": [-250, 0], "surface_id": "dock"})) and pieces.pipsport.holder == null and not p0.carrying_seed, "Put down, it rests where the pip stood, and the pip's head is free")
	await world.show_stage(level.stages[1])
	var current: RefCounted = world._current_piece
	_check(current != null and current.style == "ripples" and current._legs.size() == 2, "The drift stage lays its two legs in the default style")
	var state: Dictionary = sim.snapshot()
	state.stage_id = "drift"
	state.controls = {"current": "south"}
	world.present(state, true)
	_check(current._legs.all(func(leg: Dictionary) -> bool: return not leg.live.visible and leg.faint.visible), "With the wheel south both legs are faint")
	state.controls = {"current": "north"}
	world.present(state, true)
	_check(current._legs.all(func(leg: Dictionary) -> bool: return leg.live.visible and not leg.faint.visible), "Turned north, both legs run bright")
	_check(world._static_keep().has(current._legs[0].live), "The current's rows are kept whole by the static fold")
	world.queue_free()
	await process_frame

func _walk(sim: RefCounted, target: Array) -> void:
	for axis: String in ["x", "z"]:
		for _step in range(300):
			var distance := int(target[0 if axis == "x" else 1]) - int(sim._players[sim.active_slot][axis])
			if absi(distance) <= 1: break
			sim.step({"move_" + axis: clampf(float(distance) / 8.0, -1.0, 1.0)})

func _meshes(node: Node) -> int:
	return node.find_children("*", "MeshInstance3D", true, false).size() + (1 if node is MeshInstance3D else 0)

## Meshes whose centre stands inside `rect` (x, z in metres) under `node`.
func _meshes_within(node: Node3D, rect: Rect2) -> int:
	var count := 0
	for mesh: Node in node.find_children("*", "MeshInstance3D", true, false):
		var at: Vector3 = node.to_local((mesh as Node3D).global_position)
		if rect.has_point(Vector2(at.x, at.z)): count += 1
	return count

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)
