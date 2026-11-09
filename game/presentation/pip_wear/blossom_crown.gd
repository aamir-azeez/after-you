extends RefCounted
## Blossom crown (hat): a ring of small five petal blossoms, pink and white in
## turn, on a thin green vine round the top of the head, as the Orchard board
## draws it (Fruits board 4a). Every part lies on the head's surface (kit
## on_head), above the eyes and below a carried seed. Each blossom is one flat
## five lobed shape with a gold heart, so the ring stays light. One baked
## mesh, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")

const PINK := Color("f6c3cf")
const WHITE := Color("fbe1e6")
const HEART := Color("f2b45f")
const VINE := Color("7f9d5f")
const BLOSSOMS := 8
## How far down from the top of the head the ring sits (radians from straight up).
const RING_TILT := 1.0
## The blossom's reach, the gold heart's, and how far the heart stands above the petals.
const BLOSSOM := 0.062
const HEART_SIZE := 0.022
const HEART_LIFT := 0.006
## The blossom's five lobes: points per lobe, and how deep the dips between them are.
const LOBES := 5
const LOBE_POINTS := 5
const LOBE_DIP := 0.45
## The vine: pieces round the head, its thickness, and how far each piece runs past its ends.
const VINE_PIECES := 16
const VINE_RADIUS := 0.008
const VINE_OVERLAP := 0.004
const VINE_SIDES := 4
## Clearance kept between a part and the head.
const GAP := 0.003

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("blossom_crown", _build), Kit.vertex_material())

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	var ring: Array[Vector3] = []
	for index in range(VINE_PIECES):
		var surface: Array[Vector3] = Meshes.head_surface(_around(TAU * index / VINE_PIECES))
		ring.append(surface[0] + surface[1] * (GAP + VINE_RADIUS))
	for index in range(VINE_PIECES):
		var from := ring[index]
		var to := ring[(index + 1) % VINE_PIECES]
		var along := (to - from).normalized() * VINE_OVERLAP
		parts.rod(VINE, from - along, to + along, VINE_RADIUS, VINE_SIDES)
	var flower := _flower(1.0)
	var heart := _flower(0.0)
	for index in range(BLOSSOMS):
		var near := _around(TAU * index / BLOSSOMS)
		var lie := GAP + VINE_RADIUS * 2.0
		parts.add(flower, PINK if index % 2 == 0 else WHITE, Kit.on_head(near, Vector3.UP, Vector3(BLOSSOM, BLOSSOM * 0.2, BLOSSOM), lie))
		parts.add(heart, HEART, Kit.on_head(near, Vector3.UP, Vector3(HEART_SIZE, HEART_SIZE * 0.3, HEART_SIZE), lie + BLOSSOM * 0.2 + HEART_LIFT))
	return parts.commit()

## The direction from the head's centre at `angle` round the ring (0 is the front).
static func _around(angle: float) -> Vector3:
	return Vector3(sin(RING_TILT) * sin(angle), cos(RING_TILT), sin(RING_TILT) * cos(angle))

## A flat shape of reach 1 facing up (+y), its middle raised a little: five
## lobes with `lobed` 1, a plain disc with 0. Its top face only; the head
## hides its underside.
static func _flower(lobed: float) -> ArrayMesh:
	var count := LOBES * LOBE_POINTS
	var vertices := PackedVector3Array([Vector3(0, 1, 0)])
	var normals := PackedVector3Array([Vector3.UP])
	var indices := PackedInt32Array()
	for index in range(count):
		var angle := TAU * index / count
		var reach := 1.0 - lobed * LOBE_DIP * (1.0 - absf(cos(angle * LOBES * 0.5)))
		vertices.append(Vector3(cos(angle) * reach, -1.0, sin(angle) * reach))
		normals.append(Vector3(cos(angle) * 0.25, 1.0, sin(angle) * 0.25).normalized())
	for index in range(count):
		# Clockwise seen from above: the front face.
		indices.append_array(PackedInt32Array([0, 1 + index, 1 + (index + 1) % count]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var made := ArrayMesh.new()
	made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return made
