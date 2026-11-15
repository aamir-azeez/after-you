extends RefCounted
## World kit: where the seed rests, is planted and lands, one look each for
## every world that has them (First Steps, Relay Isles and the island world).
## Each builds under the node the world names and places.
##   stand(): a spot a pip stands inside to take or place a carried thing
##       (the Lighthouse's lens rest): a low step-on base the spot's size and
##       a slim stem whose small cup holds the thing where it rests. Nothing
##       wider than the stem and cup rises where the pip stands, so standing
##       in the spot looks natural (prop_rules.gd stands_in()).
##   relay(): the relay socket the seed is passed through, a timber stump with
##       a woven nest and three teal leaves fanned under it. The seed rests in
##       the nest 35 cm up (the v2 engine's socket height), on today's low
##       stone base with its teal ring, so the spot still reads as the place
##       to stand. Relay Isles @3 makes it solid (core/solid_footprint.gd).
##   garden(): the garden planter the seed is planted in, a low stone drum
##       with dark soil and a ring the colour the world gives. Its drum and
##       soil are cylinders right under the root: the planting finds the soil
##       there (plant_animation.gd soil()).
##   landing(): the ring of eight cream ticks round a teal ring that marks
##       where a thrown seed lands.
const Primitives = preload("res://presentation/kit/primitives.gd")
const Parts = preload("res://presentation/kit/pieces/parts.gd")

const BASE := Color("6b847c")
const SOIL := Color("244b46")
const BARK := Color("6a5240")
const NEST := Color("c9a76f")
const NEST_DARK := Color("a8875a")
const LEAF := Color("6fae9c")
## A stand's base height (clear of a seed landing's ticks' tops, 0.0425), its
## stem's radius and its cup's top radius, depth and rim (metres): the cup
## and its rim stay under the lint's SMALL_STAND across, like a stem a pip
## walks through.
const STEP := 0.05
const STEM := 0.022
const CUP := 0.072
const CUP_DEPTH := 0.05
const CUP_RIM := 0.012
## The planter drum's height: its soil and ring sit just over it, all under
## the lint's STEP_ON, so a pip planting stands in soil, not in a drum.
const PLANTER := 0.09
## The landing ring's radius and its ticks' (metres).
const LANDING := 0.66
const LANDING_TICKS := 0.83

## A stand under `root` (the spot's node, on its floor): a base `radius`
## across in `base_color`, a ring in `ring_color` round it (none when
## transparent), and a stem in `stem_color` up to a cup in `cup_color` whose
## rim is `top` metres up, where the carried thing rests.
static func stand(root: Node3D, radius: float, top: float, base_color: Color, stem_color: Color, cup_color: Color, ring_color: Color = Color.TRANSPARENT) -> void:
	_cyl(root, radius, STEP, base_color, Vector3(0, STEP * 0.5, 0))
	if ring_color.a > 0.0: Parts.ring(radius + 0.01, ring_color, Vector3(0, STEP + 0.01, 0), root)
	var stem := top - CUP_DEPTH - STEP
	_cyl(root, STEM, stem, stem_color, Vector3(0, STEP + stem * 0.5, 0))
	_cyl(root, STEM + 0.01, CUP_DEPTH, cup_color, Vector3(0, top - CUP_DEPTH * 0.5, 0), CUP)
	_ring(root, CUP, CUP_RIM, cup_color.lightened(0.15), Vector3(0, top, 0))

## A relay socket's look under `root` (the socket node the world names).
static func relay(root: Node3D) -> void:
	_cyl(root, 0.42, 0.10, BASE, Vector3(0, 0.05, 0))
	Parts.ring(0.43, Parts.TEAL, Vector3(0, 0.11, 0), root)
	# A short timber stump.
	_cyl(root, 0.17, 0.24, BARK, Vector3(0, 0.22, 0), 0.15)
	_ring(root, 0.155, 0.018, BARK.lightened(0.2), Vector3(0, 0.34, 0))
	# A woven nest: three rings stacked wider to the rim.
	_cyl(root, 0.11, 0.06, NEST_DARK, Vector3(0, 0.37, 0), 0.15)
	_ring(root, 0.14, 0.035, NEST, Vector3(0, 0.38, 0))
	_ring(root, 0.17, 0.035, NEST_DARK, Vector3(0, 0.425, 0))
	_ring(root, 0.19, 0.03, NEST, Vector3(0, 0.465, 0))
	# Three teal leaves fanning out under the nest.
	for index in range(3):
		var angle := TAU * index / 3.0 + PI / 2.0
		var leaf := Primitives.mesh_node(Primitives.shared_mesh("sphere", 0.16), Primitives.shared_material(LEAF), Vector3(cos(angle) * 0.26, 0.40, sin(angle) * 0.26), root)
		leaf.scale = Vector3(0.42, 0.14, 1.0)
		leaf.rotation = Vector3(0, -angle + PI / 2.0, 0)
		leaf.rotate_object_local(Vector3.RIGHT, -0.35)

## A garden planter under `root`, `radius` across, its ring in `ring_color`.
## Returns the ring, which the world lights as the goal.
static func garden(root: Node3D, radius: float, ring_color: Color) -> MeshInstance3D:
	var drum := Parts.cylinder(radius, PLANTER, BASE, Vector3(0, PLANTER * 0.5, 0), root)
	drum.name = "Planter"
	var soil := Parts.cylinder(radius - 0.12, 0.035, SOIL, Vector3(0, PLANTER + 0.015, 0), root)
	soil.name = "Soil"
	var ring := Parts.ring(radius + 0.01, ring_color, Vector3(0, PLANTER + 0.03, 0), root)
	ring.name = "GoalRing"
	return ring

## The landing mark under `root` (the node the world moves to each landing).
static func landing(root: Node3D) -> void:
	Parts.ring(LANDING, Parts.TEAL, Vector3(0, 0.035, 0), root)
	for index in range(8):
		var angle := float(index) * TAU / 8.0
		var tick := Primitives.mesh_node(Primitives.cached_box(Vector3(0.06, 0.025, 0.13)), Primitives.shared_material(Parts.CREAM), Vector3(cos(angle) * LANDING_TICKS, 0.03, sin(angle) * LANDING_TICKS), root)
		tick.rotation.y = -angle

static func _cyl(root: Node3D, radius: float, height: float, color: Color, at: Vector3, top: float = -1.0) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.cached_shape(Primitives.cylinder_mesh(radius, height, top, 14 if top >= 0.0 else 24)), Primitives.shared_material(color), at, root)

static func _ring(root: Node3D, radius: float, tube: float, color: Color, at: Vector3) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - tube
	shape.outer_radius = radius + tube
	shape.rings = 18
	shape.ring_segments = 6
	return Primitives.mesh_node(Primitives.cached_shape(shape), Primitives.shared_material(color), at, root)
