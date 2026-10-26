extends RefCounted
## Daisy (hat): a flower and a small leaf on the head's upper corner across
## from the leaf. Each part is placed on the head's surface (spirit_meshes
## head_surface), clear of the eyes and a carried seed. One baked mesh, one
## draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")

const PETAL := Color("fffaf0")
const HEART := Color("f2b54e")
const GREEN := Color("7fb35f")
## Where the flower sits, as a direction from the head's centre (head space).
const AT := Vector3(0.19, 0.238, 0.165)
const PETALS := 6
## Petal half sizes: along, through (thickness), across.
const PETAL_SIZE := Vector3(0.05, 0.016, 0.034)
const PETAL_REACH := 0.07
const HEART_SIZE := Vector3(0.04, 0.024, 0.04)
## The leaf beside it, as a direction from the head's centre, and its turn
## about the surface normal (radians).
const LEAF_AT := Vector3(0.29, 0.2, 0.06)
const LEAF_SIZE := Vector3(0.05, 0.012, 0.024)
const LEAF_TURN := 0.9
## Clearance kept between each part's underside and the head.
const GAP := 0.003

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("daisy", _build), Kit.vertex_material())

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	var centre: Array[Vector3] = Meshes.head_surface(AT)
	var normal: Vector3 = centre[1]
	var across := normal.cross(Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var along := across.cross(normal).normalized()
	for index in range(PETALS):
		var angle := TAU * float(index) / float(PETALS)
		var out := (along * cos(angle) + across * sin(angle))
		parts.blob_at(PETAL, _on_head(centre[0] + out * PETAL_REACH, out, PETAL_SIZE), 8, 3)
	parts.blob_at(HEART, _on_head(centre[0], along, HEART_SIZE, PETAL_SIZE.y * 1.2), 8, 4)
	var leaf_centre: Array[Vector3] = Meshes.head_surface(LEAF_AT)
	var leaf_dir := Basis(leaf_centre[1], LEAF_TURN) * along
	parts.blob_at(GREEN, _on_head(leaf_centre[0], leaf_dir, LEAF_SIZE), 8, 3)
	return parts.commit()

## An ellipsoid of half sizes `size` lying on the head's surface under `near`:
## its x along `toward`, its y the surface normal there, raised so its
## underside clears the surface by GAP (plus `extra`).
static func _on_head(near: Vector3, toward: Vector3, size: Vector3, extra: float = 0.0) -> Transform3D:
	var surface: Array[Vector3] = Meshes.head_surface(near)
	var up: Vector3 = surface[1]
	var x := (toward - up * toward.dot(up)).normalized()
	var z := x.cross(up).normalized()
	var basis := Basis(x * size.x, up * size.y, z * size.z)
	return Transform3D(basis, surface[0] + up * (size.y + GAP + extra))
