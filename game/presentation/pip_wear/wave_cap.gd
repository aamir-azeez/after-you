extends RefCounted
## Wave cap (hat): three broad blue waves in a row over the head's top, beside
## the leaf and growing toward the far side, as the hats board draws it. Each
## wave is a curl seen from the front: a band that rises from the head, rolls
## over its top and curls back under, thick at its foot and thin at its
## breaking edge, given depth front to back. Its outer half and outer wall are
## blue, its inner half and the wall inside the curl mint, and its breaking
## edge cream. No water moves. It sits clear beside the leaf
## ("pokes_through"). One baked mesh, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")

const BLUE := Color("6797a5")
const MINT := Color("9acbc8")
const CREAM := Color("eee9d4")
## Each wave: where it stands (a direction from the head's centre) and its
## curl's radius.
const WAVES := [[Vector3(0.28, 1.0, -0.04), 0.07], [Vector3(0.64, 1.0, -0.04), 0.082], [Vector3(1.05, 1.0, -0.04), 0.092]]
## The curl in the wave's own plane (x along the row, y up): its middle line
## starts at the wave's foot behind it (START, radians round the curl's
## centre), rolls over the top and ends curled under (END), its radius
## tightening to TIGHTEN of itself.
const START := PI * 1.25
const END := -PI * 0.42
const TIGHTEN := 0.55
## The band: steps along it, its half thickness at the foot and the tip (times
## the curl's radius), and its depth front to back (times the radius).
const STEPS := 7
const THICK := Vector2(0.62, 0.18)
const DEPTH := 1.3
## The last step is the cream breaking edge.
const EDGE_STEPS := 1
## How far a wave's foot sinks into the head, so it never floats.
const SINK := 0.014

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("wave_cap", _build), Kit.vertex_material())

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	for wave: Array in WAVES:
		var on: Array[Vector3] = Meshes.head_surface(wave[0])
		var up: Vector3 = on[1]
		var along := up.cross(Vector3.BACK).normalized()
		parts.push(Transform3D(Basis(along, up, along.cross(up).normalized()), on[0] - up * SINK))
		_wave(parts, float(wave[1]))
		parts.pop()
	return parts.commit()

## One wave in its own frame (its foot at the origin): the band's outer,
## middle and inner lines, then its front and back faces in two strips, its
## outer and inner walls, and the end of its breaking edge.
static func _wave(parts: RefCounted, radius: float) -> void:
	var centre := Vector3(0.0, radius, 0.0)
	var outer := PackedVector3Array()
	var middle := PackedVector3Array()
	var inner := PackedVector3Array()
	for step in range(STEPS + 1):
		var t := float(step) / float(STEPS)
		var angle := lerpf(START, END, t)
		var out := Vector3(cos(angle), sin(angle), 0.0)
		var spine := centre + out * radius * lerpf(1.0, TIGHTEN, t)
		var thick := radius * lerpf(THICK.x, THICK.y, t)
		outer.append(spine + out * thick)
		middle.append(spine)
		inner.append(spine - out * thick)
	var half := Vector3(0.0, 0.0, radius * DEPTH * 0.5)
	for step in range(STEPS):
		var edge := step >= STEPS - EDGE_STEPS
		for side: float in [1.0, -1.0]:
			var z := half * side
			# Each face is turned away from a point well behind it.
			parts.facets(CREAM if edge else BLUE, _quad(outer[step] + z, outer[step + 1] + z, middle[step + 1] + z, middle[step] + z), centre - z * 4.0)
			parts.facets(CREAM if edge else MINT, _quad(middle[step] + z, middle[step + 1] + z, inner[step + 1] + z, inner[step] + z), centre - z * 4.0)
		var spine := (middle[step] + middle[step + 1]) * 0.5
		parts.facets(CREAM if edge else BLUE, _quad(outer[step] + half, outer[step + 1] + half, outer[step + 1] - half, outer[step] - half), spine)
		parts.facets(CREAM if edge else MINT, _quad(inner[step] + half, inner[step + 1] + half, inner[step + 1] - half, inner[step] - half), spine)
	parts.facets(CREAM, _quad(outer[STEPS] + half, inner[STEPS] + half, inner[STEPS] - half, outer[STEPS] - half), middle[STEPS - 1])

static func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> PackedVector3Array:
	return PackedVector3Array([a, b, c, a, c, d])
