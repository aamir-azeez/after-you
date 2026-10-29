extends RefCounted
## Home's extra islands for the keepsakes, as the older Home had: a tide isle
## beside the right island and two journey isles behind, each joined to a Home
## island by a fixed plank bridge. The two Home islands themselves come from
## the level (bounds, gap and its lowering bridge).
##
## A keepsake names its island in its descriptor (content/chapters/index.gd);
## an isle is built only when a keepsake Home stands stands on it, so a build
## that sells nothing has the tide isle and no journey isles. The isles are
## plain geometry made once into Home's terrain, before Home folds it
## (home_stage.gd), so they draw in Home's own shared batches; nothing keeps
## hold of their nodes. A second Home over the same terrain finds them made.
const Parts = preload("res://presentation/keepsakes/keepsake_parts.gd")
const NODE_NAME := "HomeIsles"
## Home's own grass (the Home level's palette).
const GRASS := Color("a6c9a0")
const ROOTS := Color("456b59")
## Each isle: its middle and size in metres, and its plank bridge from the
## Home island's edge into the isle.
const ISLES := {
	"tide": {"center": Vector2(8.9, 0.2), "size": Vector2(4.8, 6.4), "bridge": [Vector2(5.6, 0.0), Vector2(6.6, 0.0)]},
	"journey_left": {"center": Vector2(-3.5, -8.9), "size": Vector2(5.0, 8.6), "bridge": [Vector2(-3.0, -2.9), Vector2(-3.0, -4.8)]},
	"journey_right": {"center": Vector2(3.5, -8.9), "size": Vector2(5.0, 8.6), "bridge": [Vector2(3.2, -2.9), Vector2(3.2, -4.8)]},
}
const BRIDGE_WIDTH := 1.0
const PLANK_STEP := 0.34

static func is_isle(id: String) -> bool:
	return ISLES.has(id)

## The isles `ids` names, made under `terrain` once.
static func build(world: Node3D, terrain: Node3D, ids: Array) -> void:
	if not is_instance_valid(terrain) or terrain.get_node_or_null(NODE_NAME) != null: return
	var holder := Node3D.new()
	holder.name = NODE_NAME
	terrain.add_child(holder)
	for id: String in ISLES:
		if not ids.has(id): continue
		var isle: Dictionary = ISLES[id]
		var land := Node3D.new()
		land.name = "Isle_" + id
		holder.add_child(land)
		var middle: Vector2 = isle.center
		var size: Vector2 = isle.size
		world.island_shell(middle.x, middle.y, size.x, size.y, GRASS, land)
		_dress(land, middle, size)
		_bridge(holder, id, isle.bridge)

## Hanging roots, tufts and pebbles, as the Home islands have.
static func _dress(land: Node3D, middle: Vector2, size: Vector2) -> void:
	var half := size * 0.5
	for index in range(5):
		var root := Parts.cyl(land, 0.025, 0.7 + (index % 3) * 0.08, ROOTS, Vector3(middle.x + sin(index * 2.8) * (half.x - 0.3), -1.35, middle.y + cos(index) * half.y))
		root.rotation.z = sin(index) * 0.3
	for index in range(8):
		var at := Vector3(middle.x + sin(index * 2.7) * (half.x - 0.3), 0.03, middle.y + cos(index * 1.8) * (half.y - 0.25))
		if index % 3 == 0:
			Parts.sph(land, 0.11, Color("d7d8bb"), at, Vector3(1.2, 0.55, 1.2))
		else:
			for blade in range(3): Parts.box(land, Vector3(0.025, 0.13 + blade * 0.05, 0.035), Color("638d69"), at + Vector3(blade * 0.04, 0.03 + blade * 0.015, 0), Vector3(0, 0, (blade - 1) * 0.24))

static func _bridge(holder: Node3D, id: String, ends: Array) -> void:
	var from: Vector2 = ends[0]
	var to: Vector2 = ends[1]
	var length := from.distance_to(to)
	var bridge := Node3D.new()
	bridge.name = "Bridge_" + id
	holder.add_child(bridge)
	bridge.transform = Transform3D(Basis.looking_at(Vector3(to.x - from.x, 0, to.y - from.y), Vector3.UP), Vector3(from.x, 0, from.y))
	var count := maxi(3, ceili(length / PLANK_STEP))
	var step := length / count
	for index in range(count): Parts.box(bridge, Vector3(BRIDGE_WIDTH, 0.1, step - 0.03), Parts.PLANK, Vector3(0, -0.06, -(index + 0.5) * step))
	for side: int in [-1, 1]:
		for index in range(0, count + 1, 2): Parts.cyl(bridge, 0.04, 0.38, Parts.POST, Vector3(side * (BRIDGE_WIDTH * 0.5 - 0.06), 0.15, -index * step))

## Each isle's floor (inset from its edges), by id.
static func floors(ids: Array, inset: float) -> Dictionary:
	var result := {}
	for id: String in ISLES:
		if not ids.has(id): continue
		var isle: Dictionary = ISLES[id]
		result[id] = Rect2((isle.center as Vector2) - (isle.size as Vector2) * 0.5, isle.size).grow(-inset)
	return result

## Each built isle's bridge: [from, to] on the ground.
static func bridges(ids: Array) -> Array:
	var result: Array = []
	for id: String in ISLES:
		if ids.has(id): result.append(ISLES[id].bridge)
	return result
