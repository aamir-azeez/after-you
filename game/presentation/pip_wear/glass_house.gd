extends RefCounted
## Glass house (hat): a small greenhouse on the head's top beside the leaf, as
## the hats board draws it: opaque matte mint panels (no glass shader, nothing
## see-through) in a cream frame with a gable roof, and two broad coral petal
## shapes on its front. It leans away from the leaf and sits clear of it
## ("pokes_through"). One baked mesh, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const FRAME := Color("eee9d4")
const PANEL := Color("9fd8c4")
const PETAL := Color("e8ad9b")
## Where the house's floor sits on the head and its turn (head space).
const AT := Vector3(0.17, 0.24, -0.03)
const TURN := Vector3(0.0, 0.42, -0.16)
## Its own space (x across, y up, z front): the walls' half sizes, the roof's
## ridge height over the walls, the panels' inset behind the frame, the
## bars' radius and the floor's thickness.
const WALLS := Vector3(0.15, 0.1, 0.115)
const RIDGE := 0.085
const INSET := 0.006
const BAR := 0.009
const BASE := 0.022
## The petals on the front: each [centre (x, y), half length, half width,
## lean (radians)], lying on the front panel.
const PETALS := [[Vector2(-0.055, 0.105), 0.05, 0.03, 0.35], [Vector2(0.045, 0.095), 0.045, 0.027, -0.45]]
const PETAL_SIDES := 8

## Metres a carried seed or lens sits higher while it is worn, just clear of
## the hat itself (a leaf may touch it; pip_outfit.gd lift_seed).
const SEED_LIFT := 0.225

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("glass_house", _build), Kit.vertex_material())
	look.lift_seed(SEED_LIFT)

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	parts.push(Kit.Parts.place(AT, TURN))
	var w := WALLS
	var low := BASE
	var high := BASE + w.y * 2.0
	var top := high + RIDGE
	var centre := Vector3(0.0, (low + high) * 0.5, 0.0)
	# The floor: a cream slab the house stands on.
	_box(parts, FRAME, Vector3(0.0, BASE * 0.5 - 0.01, 0.0), Vector3(w.x + BAR, BASE * 0.5 + 0.01, w.z + BAR))
	# The mint panels: four walls and the roof's two slopes and two gables.
	var i := Vector3(w.x - INSET, 0.0, w.z - INSET)
	var corners := [Vector3(-i.x, low, i.z), Vector3(i.x, low, i.z), Vector3(i.x, low, -i.z), Vector3(-i.x, low, -i.z)]
	var walls := PackedVector3Array()
	for index in range(4):
		var a: Vector3 = corners[index]
		var b: Vector3 = corners[(index + 1) % 4]
		walls.append_array(PackedVector3Array([a, b, b + Vector3.UP * (high - low), a, b + Vector3.UP * (high - low), a + Vector3.UP * (high - low)]))
	parts.facets(PANEL, walls, centre)
	var ridge := [Vector3(-i.x, top - INSET, 0.0), Vector3(i.x, top - INSET, 0.0)]
	var eaves := [Vector3(-i.x, high, i.z), Vector3(i.x, high, i.z), Vector3(i.x, high, -i.z), Vector3(-i.x, high, -i.z)]
	var roof_inside := Vector3(0.0, high, 0.0)
	parts.facets(PANEL, PackedVector3Array([eaves[0], eaves[1], ridge[1], eaves[0], ridge[1], ridge[0], eaves[3], ridge[0], ridge[1], eaves[3], ridge[1], eaves[2], eaves[0], ridge[0], eaves[3], eaves[1], eaves[2], ridge[1]]), roof_inside)
	# The cream frame: posts, the wall tops, the gables, the ridge and the front's cross bars.
	var outer := [Vector3(-w.x, low, w.z), Vector3(w.x, low, w.z), Vector3(w.x, low, -w.z), Vector3(-w.x, low, -w.z)]
	for index in range(4):
		var a: Vector3 = outer[index]
		var b: Vector3 = outer[(index + 1) % 4]
		parts.rod(FRAME, a, a + Vector3.UP * (high - low), BAR, 4)
		parts.rod(FRAME, a + Vector3.UP * (high - low), b + Vector3.UP * (high - low), BAR, 4)
	var peak := [Vector3(-w.x, top, 0.0), Vector3(w.x, top, 0.0)]
	parts.rod(FRAME, peak[0], peak[1], BAR, 4)
	for side: float in [-1.0, 1.0]:
		for front: float in [-1.0, 1.0]:
			parts.rod(FRAME, Vector3(w.x * side, high, w.z * front), Vector3(w.x * side, top, 0.0), BAR, 4)
	parts.rod(FRAME, Vector3(0.0, low, w.z), Vector3(0.0, top - RIDGE * 0.02, w.z * 0.02), BAR * 0.85, 4)
	parts.rod(FRAME, Vector3(-w.x, (low + high) * 0.5, w.z), Vector3(w.x, (low + high) * 0.5, w.z), BAR * 0.85, 4)
	# The coral petals, lying on the front panel.
	for petal: Array in PETALS:
		var at: Vector2 = petal[0]
		var fan := PackedVector3Array()
		var middle := Vector3(at.x, at.y, w.z + 0.004)
		for corner in range(PETAL_SIDES):
			var angles := [TAU * float(corner) / float(PETAL_SIDES), TAU * float(corner + 1) / float(PETAL_SIDES)]
			fan.append(middle)
			for angle: float in angles:
				var point := Vector2(sin(angle) * float(petal[2]), cos(angle) * float(petal[1]) * (1.0 + 0.25 * cos(angle))).rotated(float(petal[3]))
				fan.append(middle + Vector3(point.x, point.y, 0.0))
		parts.facets(PETAL, fan, middle - Vector3(0.0, 0.0, 0.05))
	parts.pop()
	return parts.commit()

## A box of half sizes `half` about `at`, flat faced.
static func _box(parts: RefCounted, colour: Color, at: Vector3, half: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = half * 2.0
	parts.add(box, colour, Transform3D(Basis(), at))
