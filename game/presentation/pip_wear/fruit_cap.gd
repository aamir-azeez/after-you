extends RefCounted
## Fruit cap (hat): half a ripe Fruit worn as a cap, as the Orchard board
## draws it (Fruits board 4a): a rose dome over the top of the head, a cream
## band round its rim, and the Fruit's stem and leaf on top. The rose and the
## green are the Fruit's own (kit/fruit_mark.gd). The stem stands off the
## middle, toward the side away from the pip's leaf, so a carried seed clears
## it. One baked mesh, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const FruitMark = preload("res://presentation/kit/fruit_mark.gd")

## The dome's rose: this far from the Fruit's light rose toward its deep one.
const ROSE_DEPTH := 0.45
const BAND := Color("f2dfcf")
const GREEN := FruitMark.GREEN
## Head space: the dome's rim height and its half sizes (it is a little wider
## than the head there, and its top stays under a carried seed).
const RIM_Y := 0.15
const DOME := Vector3(0.36, 0.185, 0.33)
## The dome's roundness from rim to top: above 2 its sides rise steeply and
## round over, so the cap fills out over the head as a Fruit's half would.
## Seen from above it stays an oval, inside its band.
const DOME_POWER := 2.6
const DOME_SEGMENTS := 16
const DOME_RINGS := 6
## The band: a flat ring over the dome's rim, squashed to the head's shape.
const BAND_INNER := 0.34
const BAND_OUTER := 0.38
const BAND_SIZE := Vector3(1.0, 1.3, 0.9)
## The stem, from inside the dome up and out, and the leaf off its tip, its
## broad side turned toward the front so it reads in every pip view.
const STEM: Array[Vector3] = [Vector3(0.085, 0.31, -0.02), Vector3(0.095, 0.35, -0.022), Vector3(0.112, 0.378, -0.025)]
const STEM_RADIUS := 0.016
const LEAF_AT := Vector3(0.19, 0.398, -0.025)
const LEAF_SIZE := Vector3(0.08, 0.014, 0.046)
const LEAF_TURN := Vector3(0.9, 0.25, 0.42)

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("fruit_cap", _build), Kit.vertex_material())

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	parts.add(_dome(), FruitMark.ROSE_LIGHT.lerp(FruitMark.ROSE_DEEP, ROSE_DEPTH), Kit.Parts.place(Vector3(0, RIM_Y, 0), Vector3.ZERO, DOME))
	parts.ring(BAND, Vector3(0, RIM_Y, 0), BAND_INNER, BAND_OUTER, BAND_SIZE, Vector3.ZERO, 24, 4)
	for index in range(STEM.size() - 1): parts.rod(GREEN, STEM[index], STEM[index + 1], STEM_RADIUS)
	parts.blob(GREEN, LEAF_AT, LEAF_SIZE, LEAF_TURN, 8, 3)
	return parts.commit()

## A unit dome, open below: oval across, its side's profile rounded by DOME_POWER.
static func _dome() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring in range(DOME_RINGS + 1):
		var lat := PI * 0.5 * float(ring) / float(DOME_RINGS)
		for segment in range(DOME_SEGMENTS + 1):
			var lon := TAU * float(segment) / float(DOME_SEGMENTS)
			# Out from the middle and up, on the profile |out|^p + |up|^p = 1.
			var reach := pow(pow(sin(lat), DOME_POWER) + pow(cos(lat), DOME_POWER), -1.0 / DOME_POWER)
			var out := sin(lat) * reach
			var up := cos(lat) * reach
			var across := Vector3(sin(lon), 0.0, cos(lon))
			vertices.append(across * out + Vector3.UP * up)
			var slope := across * pow(out, DOME_POWER - 1.0) + Vector3.UP * pow(up, DOME_POWER - 1.0)
			normals.append(slope.normalized())
	var row := DOME_SEGMENTS + 1
	for ring in range(DOME_RINGS):
		for segment in range(DOME_SEGMENTS):
			var a := ring * row + segment
			var b := a + row
			indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var made := ArrayMesh.new()
	made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return made
