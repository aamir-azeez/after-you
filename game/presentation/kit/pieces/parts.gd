extends RefCounted
## World kit: what every piece kit (lever.gd, selector.gd, pad.gd, goal.gd)
## shares: the palette, the shapes, and lighting a mesh. Every shape and colour
## comes from the kit caches (Primitives, released through SessionRelease);
## nothing here keeps a static of its own.
const Primitives = preload("res://presentation/kit/primitives.gd")
const OwnerMark = preload("res://presentation/kit/owner_mark.gd")

## The worlds' own palette (island_world, lighthouse_world read it from here).
const CREAM := Color("e9edd6")
const GOLD := OwnerMark.GOLD
const TEAL := OwnerMark.TEAL
## A lit goal's and a held pad's glow.
const LIGHT := Color("ffe4a5")
## Timber, iron and brass of the machines (winch, bolt, valve) and the harbour.
const TIMBER := Color("7a5d45")
const TIMBER_DARK := Color("5f4a38")
const TIMBER_LIGHT := Color("9b7653")
const IRON := Color("4f5458")
const IRON_LIGHT := Color("7b8287")
const BRASS := Color("b8914f")
const STONE := Color("a8947a")
## A machine's painted marks (a valve's dial ticks, its arrow).
const MARK := Color("f3e6c8")

## The colour of an owner slot ("p0" gold, else teal).
static func owner_color(slot: String) -> Color:
	return GOLD if slot == "p0" else TEAL

static func box(size: Vector3, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.cached_box(size), Primitives.shared_material(color), at, parent)

static func sphere(radius: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.cached_shape(Primitives.sphere_mesh(radius)), Primitives.shared_material(color), at, parent)

static func cylinder(radius: float, height: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.cached_shape(Primitives.cylinder_mesh(radius, height)), Primitives.shared_material(color), at, parent)

## A flat ring lying on the floor, `radius` to its tube's middle.
static func ring(radius: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.cached_shape(Primitives.ring_mesh(radius)), Primitives.shared_material(color), at, parent)

## A small machine sphere (fewer faces than sphere()).
static func ball(radius: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.shared_mesh("sphere", radius), Primitives.shared_material(color), at, parent)

## A cylinder lying along x.
static func rod(radius: float, length: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var node := Primitives.mesh_node(Primitives.shared_mesh("cylinder", radius, length, radius), Primitives.shared_material(color), at, parent)
	node.rotation.z = PI / 2.0
	return node

## A cylinder standing up (top radius `top` when given), with `sides` faces.
static func disc(radius: float, height: float, color: Color, at: Vector3, parent: Node3D, top: float = -1.0, sides: int = 12) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.cached_shape(Primitives.cylinder_mesh(radius, height, top, sides)), Primitives.shared_material(color), at, parent)

## A torus of `radius` to its tube's middle and `tube` thick each side.
static func torus(radius: float, tube: float, color: Color, at: Vector3, parent: Node3D, rings: int = 18, sides: int = 6) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - tube
	shape.outer_radius = radius + tube
	shape.rings = rings
	shape.ring_segments = sides
	return Primitives.mesh_node(Primitives.cached_shape(shape), Primitives.shared_material(color), at, parent)

## A mesh's glow: `energy` of `color`, none at 0. An unlit kit look lights as
## the kit's glowing look of the same colour, which holds exactly the values a
## lit copy would, so meshes that glow alike share one material; anything else
## changes its own copy, never a look other meshes share.
static func glow(node: MeshInstance3D, color: Color, energy: float) -> void:
	var mat := node.material_override as StandardMaterial3D
	if energy <= 0.0 and not mat.emission_enabled: return
	if mat.emission_enabled == (energy > 0.0) and mat.emission == color and is_equal_approx(mat.emission_energy_multiplier, energy): return
	if energy > 0.0 and not mat.emission_enabled and Primitives.is_cached(mat):
		node.material_override = Primitives.shared_material(mat.albedo_color, mat.roughness, color, energy)
		return
	mat = Primitives.own_material(node)
	mat.emission_enabled = energy > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = energy
