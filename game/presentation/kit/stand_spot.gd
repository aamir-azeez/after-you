extends Node3D
## World kit: where a spirit stands to hold a pressure pad. A chapter turns it
## on with its descriptor's "stand_spots" (content/chapters/index.gd), and
## cooperative_world builds one on each of the stage's pressure pads.
##
## A bright filled disc exactly the pad's radius_cm across under a stronger
## rim whose outer edge is that same radius, with the owner's mark at its
## centre: the spot is exactly where the pad counts a spirit, so a step or post
## wider than its pad no longer reads as the place to stand. While the pad is
## held (the snapshot's hold_pads, the simulation's own rule) the disc lights
## and the spot sinks a little under the spirit's feet; the world lights the
## rim (cooperative_world keeps it in _physical_pads).
##
## Presentation only: built from the hashed stage, fed the snapshot, and
## nothing here feeds back into the simulation, a recording or a checkpoint.
## Cost: meshes and looks come from the kit caches (Primitives, which lets go
## of them through SessionRelease); set_held() swaps between two cached looks
## and moves this node, and only when the held state changes.
const Primitives = preload("res://presentation/kit/primitives.gd")
## The disc's top and the mark's top stack between a crossing's remembered
## footsteps (tops 0.0135 above its deck, lighthouse_world) and a spirit's
## ground shadow (SpiritVisual.SHADOW_TOP, 0.02425), each at least 3 mm
## (test_dressing_lint COPLANAR) from the next, so nothing z-fights and a
## spirit standing on the spot casts its shadow on the disc.
const DISC_HEIGHT := 0.0172
## The rim's tube is this thick (its outer edge is the pad's radius) and its
## centre this high above the floor, so it stands proud of the disc.
const RIM_WIDTH := 0.045
const RIM_LIFT := 0.04
## The disc's colour, mixed this far from the owner's colour toward PALE, and
## a faint glow of its own so it stays bright in a dusk chapter's light.
const PALE := Color("fffaf0")
const DISC_MIX := 0.6
const DISC_GLOW := 0.2
## The rim and mark: the owner's colour, this much richer and this much
## darker, a firm edge on both the pale disc and a timber or stone deck.
const RIM_SATURATION := 1.6
const RIM_VALUE := 0.88
## The owner's mark on the disc, in the rim's colour: the first spirit's
## diamond (this side at most) or the second's ring (this wide at most),
## small enough that the disc reads bright, and kept MARK_CLEAR inside the
## rim. Its top stays under a spirit's ground shadow too.
const MARK_SIDE := 0.11
const MARK_RING := 0.08
const MARK_RING_TUBE := 0.03
const MARK_CLEAR := 0.02
const MARK_TOP := 0.0207
const MARK_THICKNESS := 0.012
## A held spot sinks this far and its disc glows `light` at this energy.
const PRESS_DEPTH := 0.012
const HELD_GLOW := 0.8

## The pad's radius in metres: the disc's and the rim's outer edge.
var radius := 0.0
var disc: MeshInstance3D
var rim: MeshInstance3D
var mark: MeshInstance3D
var held := false
var _rest_y := 0.0
var _rest_look: StandardMaterial3D
var _held_look: StandardMaterial3D

## Builds the spot at `at` (the pad's floor point in the parent's space) with
## `radius_m` from the pad's radius_cm, the owner's `slot` and `color`;
## `light` is the glow of a held disc.
func build(at: Vector3, radius_m: float, slot: String, color: Color, light: Color) -> void:
	name = "StandSpot"
	position = at
	_rest_y = at.y
	radius = radius_m
	var pale := color.lerp(PALE, DISC_MIX)
	_rest_look = Primitives.shared_material(pale, 0.9, pale, DISC_GLOW)
	_held_look = Primitives.shared_material(pale, 0.9, light, HELD_GLOW)
	var ink := Primitives.shared_material(ink_color(color))
	disc = Primitives.mesh_node(Primitives.cached_shape(Primitives.cylinder_mesh(radius_m, DISC_HEIGHT, -1.0, 32)), _rest_look, Vector3(0, DISC_HEIGHT * 0.5, 0), self)
	disc.name = "StandDisc"
	rim = Primitives.mesh_node(Primitives.cached_shape(rim_mesh(radius_m)), ink, Vector3(0, RIM_LIFT, 0), self)
	rim.name = "StandRim"
	var room := radius_m - RIM_WIDTH - MARK_CLEAR
	if slot == "p0":
		# A diamond reaches its side times 0.7072 from its centre.
		var side := minf(MARK_SIDE, room / 0.7072)
		mark = Primitives.mesh_node(Primitives.cached_shape(Primitives.box_mesh(Vector3(side, MARK_THICKNESS, side))), ink, Vector3(0, MARK_TOP - MARK_THICKNESS * 0.5, 0), self)
		mark.rotation.y = PI / 4.0
	else:
		var ring := TorusMesh.new()
		ring.outer_radius = minf(MARK_RING, room)
		ring.inner_radius = ring.outer_radius - MARK_RING_TUBE
		ring.rings = 24
		ring.ring_segments = 8
		mark = Primitives.mesh_node(Primitives.cached_shape(ring), ink, Vector3(0, MARK_TOP - MARK_THICKNESS * 0.5, 0), self)
		# A flat ring: the torus's tube is as tall as it is wide.
		mark.scale.y = MARK_THICKNESS / MARK_RING_TUBE
	mark.name = "StandMark"

## The rim's and mark's colour for an owner's `color`.
static func ink_color(color: Color) -> Color:
	return Color.from_hsv(color.h, minf(color.s * RIM_SATURATION, 1.0), color.v * RIM_VALUE)

## The rim's torus: its outer edge exactly `radius_m`.
static func rim_mesh(radius_m: float) -> TorusMesh:
	var shape := TorusMesh.new()
	shape.outer_radius = radius_m
	shape.inner_radius = radius_m - RIM_WIDTH
	shape.rings = 32
	shape.ring_segments = 8
	return shape

## The rim's centre as it stands while the pad is free, in global space: what
## lays out around the pad holds still while a spirit steps on and off.
func rest_rim() -> Vector3:
	var parent := get_parent() as Node3D
	var local := Vector3(position.x, _rest_y + RIM_LIFT, position.z)
	return parent.to_global(local) if parent != null else local

## Lights and sinks the spot while its pad is held; nothing when unchanged.
func set_held(on: bool) -> void:
	if on == held: return
	held = on
	disc.material_override = _held_look if on else _rest_look
	position.y = _rest_y - (PRESS_DEPTH if on else 0.0)
