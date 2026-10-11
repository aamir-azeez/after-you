extends RefCounted
## The one seed every world draws: a golden body with two green leaves, shaped
## like the First Light keepsake on the Home island pedestal. Callers keep their
## own size, colour states and glow; only this builder decides the shape.
const LEAF := Color("82a87a")
const META := "seed_visual"
## Keepsake proportions, in its own units: a 0.24 sphere stretched 0.8 x 1.2.
const BODY_HALF_HEIGHT := 0.288
const BODY_RADIUS := 0.192
const LEAF_RADIUS := 0.19
const LEAVES := [[Vector3(-0.19, 0.26, 0), -0.65], [Vector3(0.17, 0.30, 0), 0.65]]

## Returns the seed body. `radius` is its vertical half extent, so a carried,
## resting or flying seed sits where the old round seed of that radius sat.
## The body owns its material; the leaves are children with their own.
static func create(world: Node3D, radius: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var scale := radius / BODY_HALF_HEIGHT
	var shape := SphereMesh.new()
	shape.radius = BODY_RADIUS * scale
	shape.height = BODY_HALF_HEIGHT * 2.0 * scale
	shape.radial_segments = 16
	shape.rings = 8
	var body: MeshInstance3D = world.mesh_node(shape, color, at, parent)
	body.name = "Seed"
	body.set_meta(META, true)
	for index in range(LEAVES.size()):
		var leaf: MeshInstance3D = world.sphere(LEAF_RADIUS * scale, LEAF, LEAVES[index][0] * scale, body)
		leaf.name = "SeedLeaf%d" % index
		leaf.scale = Vector3(0.5, 1.0, 0.28)
		leaf.rotation.z = LEAVES[index][1]
	return body

static func leaves(body: Node) -> Array[Node]:
	var found: Array[Node] = []
	if body == null: return found
	for child: Node in body.get_children():
		if child.name.begins_with("SeedLeaf"): found.append(child)
	return found
