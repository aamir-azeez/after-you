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
##       to stand. Relay Isles @3 makes it solid (core/solid_footprint.gd); as
##       an item spot its base and leaves stay inside the spot's radius.
##   garden(): the garden planter the seed is planted in, a low stone drum
##       with dark soil and a ring the colour the world gives. Its drum and
##       soil are cylinders right under the root: the planting finds the soil
##       there (plant_animation.gd soil()).
##   landing(): the ring of eight cream ticks round a teal ring that marks
##       where a thrown seed lands, the ring the landing spot's radius.
##   pedestal(): First Steps' stone pedestal, a drum, a cream cap a little
##       wider and a gold ring, the seed resting on the cap.
##   item_spot(): a rules 16 item spot (core/physical/carried_items.gd) in the
##       "item_spot" style its piece resolves to (content/dressing/piece_styles.gd):
##       "pedestal", "planter" (garden()), "nest" (relay()), "winch" (winch()),
##       "cradle" (cradle()) or "none". A solid
##       spot (core/solid_footprint.gd) sizes a pedestal's drum to its solid
##       circle; a planter takes the spot's radius. rest_height() is how high an
##       item resting there sits.
##   winch(): a rope winch on two posts whose front post has the square
##       socket a winch handle fits (tools/blender/models/winch.py); a handle
##       resting at the spot (carried_item.gd "winch_handle") sits in it.
##   cradle(): a lens cradle (light pieces, core/physical/light_pieces.gd: a
##       spot where a resting lens lights a lamp): a low slate drum with a
##       ring the colour the world gives and three brass notches round where
##       the lens stands on its edge, CRADLE_TOP up (lighthouse_world.gd's).
## drawn_radius() and landing_radius() are how far from its centre each look
## reaches on the floor, so the level checker keeps the pieces on one floor
## apart as drawn (kit/prop_rules.gd control_bodies).
const Primitives = preload("res://presentation/kit/primitives.gd")
const Models = preload("res://presentation/kit/models.gd")
const Parts = preload("res://presentation/kit/pieces/parts.gd")
const ContactShadows = preload("res://presentation/kit/contact_shadows.gd")

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
## The landing ring's radius, how far past it its ticks stand and their
## length (metres).
const LANDING := 0.66
const LANDING_TICKS := 0.17
const TICK := Vector3(0.06, 0.025, 0.13)
## A relay nest's stone base (metres): its teal ring and leaves scale with it.
const NEST_BASE := 0.42
## A ring's tube reaches this far past its radius (Primitives.ring_mesh).
const RING_TUBE := 0.025
## A pedestal's drum height, its cap (radius, height), the top a seed rests on
## (@1's seed_height_cm 205 on its 160 cm loft) and its stone (metres).
const DRUM_HEIGHT := 0.35
const CAP := Vector2(0.37, 0.10)
const PEDESTAL_TOP := 0.45
const PEDESTAL_STONE := Color("bbccb5")
## Where a seed rests in the nest: 35 cm up, the v2 engine's socket height.
const NEST_REST := 0.35
## The top of a lens cradle's drum (m): a lens resting there stands on it.
const CRADLE_TOP := 0.12
## The cradle's slate drum radius (m).
const CRADLE_DRUM := 0.31
## Where the lens's middle sits over the drum, and the notches round it (m).
const CRADLE_LENS := 0.21
const CRADLE_SLATE := Color("728994")
const CRADLE_BRASS := Color("d5b876")
## The winch model and the height of its socket's middle, where a resting
## handle's stub sits (its origin 2 cm under the stub's middle).
const WINCH := "res://assets/models/winch.glb"
const WINCH_AXLE := 0.40
## How far the winch model reaches from its spot on the floor: its far back
## corner, 17 cm to a side and 33 cm back.
const WINCH_REACH := 0.38
const WINCH_COLORS := {"stone": Color("9a8d76"), "wood": Color("7a5d45"), "wood_dark": Color("5f4a38"), "rope": Color("d1b98c"), "metal": Color("4f5458")}
## How high an item resting at a spot of each "item_spot" style sits (metres).
const REST := {"pedestal": PEDESTAL_TOP, "planter": PLANTER + 0.02, "nest": NEST_REST, "winch": WINCH_AXLE, "cradle": CRADLE_TOP}

## A stand under `root` (the spot's node, on its floor): a base `radius`
## across in `base_color`, a ring in `ring_color` round it (none when
## transparent), and a stem in `stem_color` up to a cup in `cup_color` whose
## rim is `top` metres up, where the carried thing rests.
static func stand(root: Node3D, radius: float, top: float, base_color: Color, stem_color: Color, cup_color: Color, ring_color: Color = Color.TRANSPARENT) -> void:
	ContactShadows.mark(root)
	_cyl(root, radius, STEP, base_color, Vector3(0, STEP * 0.5, 0))
	if ring_color.a > 0.0: Parts.ring(radius + 0.01, ring_color, Vector3(0, STEP + 0.01, 0), root)
	var stem := top - CUP_DEPTH - STEP
	_cyl(root, STEM, stem, stem_color, Vector3(0, STEP + stem * 0.5, 0))
	_cyl(root, STEM + 0.01, CUP_DEPTH, cup_color, Vector3(0, top - CUP_DEPTH * 0.5, 0), CUP)
	_ring(root, CUP, CUP_RIM, cup_color.lightened(0.15), Vector3(0, top, 0))

## A relay socket's look under `root` (the socket node the world names), its
## stone base `base` across (the leaves under the nest fan as far in step).
static func relay(root: Node3D, base: float = NEST_BASE) -> void:
	ContactShadows.mark(root)
	var fan := base / NEST_BASE
	_cyl(root, base, 0.10, BASE, Vector3(0, 0.05, 0))
	Parts.ring(base + 0.01, Parts.TEAL, Vector3(0, 0.11, 0), root)
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
		var leaf := Primitives.mesh_node(Primitives.shared_mesh("sphere", 0.16), Primitives.shared_material(LEAF), Vector3(cos(angle) * 0.26 * fan, 0.40, sin(angle) * 0.26 * fan), root)
		leaf.scale = Vector3(0.42 * fan, 0.14, fan)
		leaf.rotation = Vector3(0, -angle + PI / 2.0, 0)
		leaf.rotate_object_local(Vector3.RIGHT, -0.35)

## A garden planter under `root`, `radius` across, its ring in `ring_color`.
## Returns the ring, which the world lights as the goal.
static func garden(root: Node3D, radius: float, ring_color: Color) -> MeshInstance3D:
	ContactShadows.mark(root)
	planter(root, radius, radius - 0.12)
	var ring := Parts.ring(radius + 0.01, ring_color, Vector3(0, PLANTER + 0.03, 0), root)
	ring.name = "GoalRing"
	return ring

## A planter's drum `radius` across and `height` tall and its soil
## `soil_radius` across under `root`, with no ring (a goal's planter rings
## itself, kit/pieces/goal.gd). Returns the soil.
static func planter(root: Node3D, radius: float, soil_radius: float, height: float = PLANTER) -> MeshInstance3D:
	var drum := Parts.cylinder(radius, height, BASE, Vector3(0, height * 0.5, 0), root)
	drum.name = "Planter"
	var soil := Parts.cylinder(soil_radius, 0.035, SOIL, Vector3(0, height + 0.015, 0), root)
	soil.name = "Soil"
	return soil

## A stone pedestal under `root`, its drum `radius` across.
static func pedestal(root: Node3D, radius: float) -> void:
	ContactShadows.mark(root)
	Parts.cylinder(radius, DRUM_HEIGHT, PEDESTAL_STONE, Vector3(0, DRUM_HEIGHT * 0.5, 0), root)
	Parts.cylinder(CAP.x, CAP.y, Parts.CREAM, Vector3(0, DRUM_HEIGHT + CAP.y * 0.5 - 0.01, 0), root)
	Parts.ring(0.31, Parts.GOLD, Vector3(0, PEDESTAL_TOP + 0.005, 0), root)

## Item spot `spot` (a definition's item spot) in `style` under `root`, the
## node at the spot's place: nothing for "none" or a style it does not know.
static func item_spot(style: String, root: Node3D, spot: Dictionary) -> void:
	var solid: Variant = spot.get("solid", {})
	var radius := float(solid.radius_cm if solid is Dictionary and solid.has("radius_cm") else spot.get("radius_cm", 30)) / 100.0
	match style:
		"pedestal": pedestal(root, radius)
		"planter": garden(root, float(spot.get("radius_cm", 48)) / 100.0, Parts.GOLD)
		# Base, ring and leaves inside the spot's own radius.
		"nest": relay(root, nest_base(spot))
		"winch": winch(root)
		"cradle": cradle(root, float(spot.get("radius_cm", 30)) / 100.0, Parts.CREAM)

## A winch under `root`, its socket facing the camera over the spot.
static func winch(root: Node3D) -> void:
	ContactShadows.mark(root)
	Models.still(WINCH, "winch_frame", WINCH_COLORS, root)

## A nest item spot's stone base: its ring's outer edge on the spot's radius.
static func nest_base(spot: Dictionary) -> float:
	return float(spot.get("radius_cm", 30)) / 100.0 - 0.01 - RING_TUBE

## How far from its centre item spot `spot` in `style` is drawn on its floor
## (metres): 0 for none.
static func drawn_radius(style: String, spot: Dictionary) -> float:
	var solid: Variant = spot.get("solid", {})
	var radius := float(spot.get("radius_cm", 30)) / 100.0
	match style:
		"pedestal": return maxf(float(solid.radius_cm if solid is Dictionary and solid.has("radius_cm") else spot.get("radius_cm", 30)) / 100.0, CAP.x)
		"planter": return float(spot.get("radius_cm", 48)) / 100.0 + 0.01 + RING_TUBE
		"nest": return radius
		"winch": return WINCH_REACH
		"cradle": return maxf(CRADLE_DRUM, radius + 0.025)
	return 0.0

## How far from its centre a landing mark `radius` across is drawn (metres).
static func landing_radius(radius: float = LANDING) -> float:
	return radius + LANDING_TICKS + TICK.z * 0.5

## How high an item resting at a spot of `style` sits over its floor (metres).
static func rest_height(style: String) -> float:
	return float(REST.get(style, 0.0))

## The landing mark under `root` (the node the world moves to each landing),
## its ring `radius` across (a thrown item's landing spot's own radius).
static func landing(root: Node3D, radius: float = LANDING) -> void:
	Parts.ring(radius, Parts.TEAL, Vector3(0, 0.035, 0), root)
	for index in range(8):
		var angle := float(index) * TAU / 8.0
		var tick := Primitives.mesh_node(Primitives.cached_box(TICK), Primitives.shared_material(Parts.CREAM), Vector3(cos(angle) * (radius + LANDING_TICKS), 0.03, sin(angle) * (radius + LANDING_TICKS)), root)
		tick.rotation.y = -angle

## A lens cradle under `root`, `radius` across, its ring in `ring_color`.
## Returns the ring, which the world lights while the lens rests there.
static func cradle(root: Node3D, radius: float, ring_color: Color) -> MeshInstance3D:
	ContactShadows.mark(root)
	_cyl(root, CRADLE_DRUM, CRADLE_TOP, CRADLE_SLATE, Vector3(0, CRADLE_TOP * 0.5, 0))
	var ring := Parts.ring(radius, ring_color, Vector3(0, CRADLE_TOP + 0.01, 0), root)
	ring.name = "CradleRing"
	# Wider than the lens's own notches, so a resting lens never shares a face with them.
	for index in range(3):
		var angle := float(index) * TAU / 3.0
		Parts.box(Vector3(0.075, 0.12, 0.065), CRADLE_BRASS, Vector3(sin(angle) * 0.25, CRADLE_TOP + CRADLE_LENS + cos(angle) * 0.25, -0.05), root)
	return ring

static func _cyl(root: Node3D, radius: float, height: float, color: Color, at: Vector3, top: float = -1.0) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.cached_shape(Primitives.cylinder_mesh(radius, height, top, 14 if top >= 0.0 else 24)), Primitives.shared_material(color), at, root)

static func _ring(root: Node3D, radius: float, tube: float, color: Color, at: Vector3) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - tube
	shape.outer_radius = radius + tube
	shape.rings = 18
	shape.ring_segments = 6
	return Primitives.mesh_node(Primitives.cached_shape(shape), Primitives.shared_material(color), at, root)
