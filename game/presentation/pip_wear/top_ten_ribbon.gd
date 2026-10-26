extends RefCounted
## Top 10 ribbon (hat, earned): a rosette with a gold middle and two tails,
## facing forward on the head's front upper corner across from the leaf, clear
## of the eye. It is seated on the head's curved surface: moved out along its
## own facing just until no part is inside the head. One baked mesh, one draw
## call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")

const BLUE := Color("4f7fc4")
const BLUE_LIGHT := Color("6b95d3")
const GOLD := Color("e9b949")
## Head space: the point it is seated nearest (a direction from the head's
## centre), and how it faces. Seated, it lands where the approved art pins it
## (about 0.19, 0.225, 0.27), with the eye and the views' frames clear.
const AT := Vector3(0.22, 0.26, 0.28)
const TURN := Vector3(-0.3, 0.12, -0.1)
## Its size against the first art.
const SIZE := 1.35
const FOLDS := 10
## How far outside the head's surface every part stays (head_level).
const CLEAR := 1.01

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("top_ten_ribbon", _build), Kit.vertex_material())

static func _build() -> Mesh:
	var vertices: PackedVector3Array = _rosette(Transform3D.IDENTITY).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var basis := Basis.from_euler(TURN)
	var start: Vector3 = Meshes.head_surface(AT)[0]
	var out := basis * Vector3.BACK
	var place := Transform3D(basis, start)
	for step in range(200):
		place.origin = start + out * (0.001 * float(step))
		if _clear(place, vertices): break
	return _rosette(place)

## The rosette placed by `place` (in its own space it faces +z).
static func _rosette(place: Transform3D) -> ArrayMesh:
	var parts := Kit.Parts.new()
	parts.push(place * Transform3D(Basis().scaled(Vector3.ONE * SIZE), Vector3.ZERO))
	for index in range(FOLDS):
		var a := TAU * float(index) / float(FOLDS)
		parts.blob(BLUE if index % 2 == 0 else BLUE_LIGHT, Vector3(cos(a), sin(a), 0) * 0.042, Vector3(0.026, 0.017, 0.012), Vector3(0, 0, a), 6, 2)
	parts.blob(GOLD, Vector3(0, 0, 0.01), Vector3(0.027, 0.027, 0.014), Vector3.ZERO, 8, 4)
	for side: float in [-1.0, 1.0]:
		parts.blob(BLUE, Vector3(0.04 + 0.022 * side, -0.062, -0.004), Vector3(0.015, 0.038, 0.007), Vector3(0, 0, 0.5 + 0.2 * side), 5, 2)
	parts.pop()
	return parts.commit()

static func _clear(place: Transform3D, vertices: PackedVector3Array) -> bool:
	for vertex: Vector3 in vertices:
		if Meshes.head_level(place * vertex) < CLEAR: return false
	return true
