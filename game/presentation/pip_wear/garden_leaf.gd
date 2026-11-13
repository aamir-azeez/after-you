extends RefCounted
## The garden leaves (leaf): Bud, Feather, Maple, Twin sprout, Warm tip and
## Pond bud, as the leaf items board draws them. One art script serves the
## six, each descriptor naming it; the look is picked by the worn leaf's id
## from LEAVES, a list of parts built from a few shared shapes:
##   stem:  a green rod up from the stalk;
##   blade: a flat leaf blade, both faces drawn, its outline one of OUTLINES
##          (an oval, a feather with two broad cuts, a round pad with a notch);
##   maple: a five lobed blade, lighter toward its top;
##   drop:  a plump closed teardrop shaded toward a pale tip;
##   blob:  a round closed bud.
## The parts are baked into one mesh drawn in the leaf's place, so a garden
## leaf costs no draw call. It grows from the leaf's own stalk and keeps the
## leaf's rig: it sways, turns, hides and is raised with the leaf, with no
## motion of its own. Each leaf stands up from the plain leaf's lean by its
## "stand", tips back by its "tip_back" (radians) and is drawn at "scale", as
## the board draws it.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const OVAL := "oval"
const FEATHER := "feather"
const PAD := "pad"
## Leaf space: the stalk at the origin, up the leaf in y, its front in z. A
## part's "at" is where it starts, "turn" its roll (radians, positive leaning
## away from the head's middle like the leaf), "size" its length and half
## width (a blob's half sizes).
const LEAVES := {
	"bud": {"stand": -0.22, "tip_back": 0.2, "scale": 1.24, "parts": [
		["stem", Color("7d9e5e"), Vector3(0.0, 0.0, 0.0), 0.19, 0.0, 0.011],
		["blade", Color("7d9e5e"), Vector3(0.0, 0.05, 0.004), Vector2(0.12, 0.052), 0.95, OVAL],
		["blob", Color("e6a6ad"), Vector3(0.006, 0.205, 0.0), Vector3(0.042, 0.05, 0.04), 0.0],
		["blob", Color("dc9097"), Vector3(0.0, 0.18, 0.004), Vector3(0.05, 0.03, 0.046), 0.0]]},
	"feather": {"stand": -0.22, "tip_back": 0.22, "scale": 1.12, "parts": [
		["stem", Color("648f9e"), Vector3(0.0, 0.0, 0.0), 0.06, 0.0, 0.009],
		["blade", Color("9ec8d6"), Vector3(0.0, 0.04, 0.0), Vector2(0.25, 0.085), -0.04, FEATHER],
		["stem", Color("648f9e"), Vector3(0.0, 0.05, 0.007), 0.22, -0.04, 0.0055]]},
	"maple": {"stand": -0.2, "tip_back": 0.22, "scale": 1.2, "parts": [
		["stem", Color("a8703f"), Vector3(0.0, 0.0, 0.0), 0.075, 0.0, 0.009],
		["maple", Color("c88855"), Vector3(0.0, 0.142, 0.0), Vector2(0.1, 0.098), 0.0, Color("e1ae68")]]},
	"twin_sprout": {"stand": -0.1, "tip_back": 0.2, "scale": 1.3, "parts": [
		["stem", Color("7e9d60"), Vector3(0.0, 0.0, 0.0), 0.085, 0.0, 0.011],
		["blade", Color("7e9d60"), Vector3(-0.004, 0.08, 0.0), Vector2(0.11, 0.046), 0.95, OVAL, Color("b4c888")],
		["blade", Color("7e9d60"), Vector3(0.004, 0.08, 0.0), Vector2(0.11, 0.046), -0.95, OVAL, Color("b4c888")]]},
	"warm_tip": {"stand": -0.3, "tip_back": 0.2, "scale": 1.2, "parts": [
		["stem", Color("c98d4f"), Vector3(0.0, 0.0, 0.0), 0.04, 0.0, 0.01],
		["drop", Color("e9ac69"), Vector3(0.0, 0.02, 0.0), Vector2(0.21, 0.062), 0.0, Color("f0cf8b")]]},
	"pond_bud": {"stand": -0.3, "tip_back": 0.0, "scale": 1.2, "parts": [
		["stem", Color("7a9a66"), Vector3(0.0, 0.0, 0.0), 0.07, 0.0, 0.01],
		["blade", Color("8cae77"), Vector3(0.0, 0.05, -0.02), Vector2(0.148, 0.088), 0.3, PAD],
		["blob", Color("eee9d4"), Vector3(0.0, 0.12, 0.035), Vector3(0.042, 0.052, 0.04), 0.0],
		["blob", Color("e7c27d"), Vector3(0.0, 0.17, 0.035), Vector3(0.017, 0.012, 0.017), 0.0]]},
}
## How finely each shape is drawn: a blade's rings along it, a maple's
## outline points, a teardrop's rings and sides, a blob's sides and rings.
const BLADE_RINGS := 5
const MAPLE_POINTS := 20
const DROP := Vector2i(6, 7)
const BLOB := Vector2i(6, 3)
## A pad lies tipped forward this much, so its face shows from above.
const PAD_TIP := 0.6

static func wear(look: RefCounted) -> void:
	var id := str(look.outfit.get("leaf", ""))
	if not LEAVES.has(id): return
	var leaf: MeshInstance3D = look.leaf()
	look.swap_mesh(leaf, Kit.cached_mesh(id, _build.bind(id)))
	look.set_material(leaf, Kit.vertex_material())

static func _build(id: String) -> Mesh:
	var made: Dictionary = LEAVES[id]
	var parts := Kit.Parts.new()
	parts.push(Transform3D((Basis(Vector3.BACK, float(made.stand)) * Basis(Vector3.RIGHT, -float(made.tip_back))).scaled_local(Vector3.ONE * float(made.scale)), Vector3.ZERO))
	for part: Array in made.parts:
		match str(part[0]):
			"stem": _stem(parts, part)
			"blade": _blade(parts, part)
			"maple": _maple(parts, part)
			"drop": _drop(parts, part)
			"blob": parts.blob(part[1], part[2], part[3], Vector3(0.0, 0.0, float(part[4])), BLOB.x, BLOB.y)
	parts.pop()
	return parts.commit()

## A rod from `at`, `length` long, rolled `turn`, of `radius`; it starts a
## little inside the head, as the leaf's own stalk does.
static func _stem(parts: RefCounted, part: Array) -> void:
	var at: Vector3 = part[2]
	var up := Vector3.UP.rotated(Vector3.BACK, float(part[4]))
	parts.rod(part[1], at - up * 0.02, at + up * float(part[3]), float(part[5]), 5)

## A blade's half width at `t` along it (0 at its base, 1 at its tip).
static func _width(outline: String, t: float) -> float:
	match outline:
		FEATHER:
			var cut := 0.5 if absf(t - 0.4) < 0.07 or absf(t - 0.68) < 0.06 else 1.0
			return sin(PI * pow(t, 0.75)) * cut
		PAD: return sqrt(maxf(0.0, 1.0 - pow(t * 2.0 - 1.0, 2.0)))
	return pow(sin(PI * pow(t, 0.8)), 0.8)

## A flat blade along its length (y), both faces drawn: its middle a little
## proud of its edges, its front in `part[6]` when given (a lighter top face).
static func _blade(parts: RefCounted, part: Array) -> void:
	var size: Vector2 = part[3]
	var outline := str(part[5])
	var back: Color = part[1]
	var front: Color = part[6] if part.size() > 6 else back
	var frame := Transform3D(Basis(Vector3.BACK, float(part[4])), part[2])
	if outline == PAD: frame = frame * Transform3D(Basis(Vector3.RIGHT, PAD_TIP), Vector3.ZERO)
	parts.push(frame)
	var rows: Array[PackedVector3Array] = []
	for ring in range(BLADE_RINGS + 1):
		var t := float(ring) / float(BLADE_RINGS)
		var w := size.y * _width(outline, t)
		# A pad's notch: its stalk side is cut in to the middle.
		var middle := Vector3(0.0, size.x * t, 0.006 * w / maxf(size.y, 0.001))
		if outline == PAD and t < 0.5: middle.y = size.x * 0.5 * (1.0 - cos(PI * t)) + size.x * 0.12
		rows.append(PackedVector3Array([Vector3(-w, size.x * t, 0.0), middle, Vector3(w, size.x * t, 0.0)]))
	var faces := PackedVector3Array()
	for ring in range(BLADE_RINGS):
		for strip in range(2):
			var a := rows[ring][strip]
			var b := rows[ring][strip + 1]
			var c := rows[ring + 1][strip + 1]
			var d := rows[ring + 1][strip]
			faces.append_array(PackedVector3Array([a, b, c, a, c, d]))
	parts.facets(front, faces, Vector3(0.0, size.x * 0.5, -1.0))
	parts.facets(back, faces, Vector3(0.0, size.x * 0.5, 1.0))
	parts.pop()

## A five lobed blade about `at`, its upper faces lighter, both faces drawn.
static func _maple(parts: RefCounted, part: Array) -> void:
	var at: Vector3 = part[2]
	var size: Vector2 = part[3]
	var outline := PackedVector3Array()
	for index in range(MAPLE_POINTS):
		var angle := TAU * float(index) / float(MAPLE_POINTS)
		# Five lobes, the bottom one missing where the stem comes in.
		var lobe := 0.62 + 0.38 * pow(absf(cos(angle * 2.5)), 0.45)
		if absf(angle - PI) < 0.45: lobe = 0.35
		outline.append(at + Vector3(sin(angle) * size.y * lobe, cos(angle) * size.x * lobe, 0.0))
	for side: float in [1.0, -1.0]:
		for index in range(MAPLE_POINTS):
			var a := outline[index]
			var b := outline[(index + 1) % MAPLE_POINTS]
			var colour: Color = (part[1] as Color).lerp(part[5], clampf(((a.y + b.y) * 0.5 - at.y) / size.x * 0.5 + 0.5, 0.0, 1.0))
			parts.facets(colour, PackedVector3Array([at + Vector3(0.0, 0.0, 0.006 * side), a, b]), at - Vector3(0.0, 0.0, side))

## A plump closed teardrop from `at` up its length, narrow at its base,
## shaded from its colour to a pale tip.
static func _drop(parts: RefCounted, part: Array) -> void:
	var at: Vector3 = part[2]
	var size: Vector2 = part[3]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for ring in range(DROP.x + 1):
		var t := float(ring) / float(DROP.x)
		# Round at its top, narrow at its base, a little pointed at the tip.
		var w := size.y * pow(sin(PI * pow(t, 0.7)), 0.85)
		var points := PackedVector3Array()
		for side in range(DROP.y):
			var angle := TAU * float(side) / float(DROP.y)
			points.append(at + Vector3(cos(angle) * w, size.x * t, sin(angle) * w * 0.6))
		rings.append(points)
	for ring in range(DROP.x):
		var colour := (part[1] as Color).lerp(part[5], smoothstep(0.45, 1.0, float(ring + 1) / float(DROP.x)))
		for side in range(DROP.y):
			var next := (side + 1) % DROP.y
			var quad := [rings[ring][side], rings[ring][next], rings[ring + 1][next], rings[ring + 1][side]]
			var axis := at + Vector3(0.0, size.x * (float(ring) + 0.5) / float(DROP.x), 0.0)
			for triangle: Array in [[0, 1, 2], [0, 2, 3]]:
				var corners := [quad[triangle[0]], quad[triangle[1]], quad[triangle[2]]]
				var out: Vector3 = (corners[0] + corners[1] + corners[2]) / 3.0 - axis
				if (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(out) > 0.0: corners = [corners[0], corners[2], corners[1]]
				if (corners[1] - corners[0]).cross(corners[2] - corners[0]).length_squared() < 1e-12: continue
				for corner: Vector3 in corners:
					tool.set_color(colour)
					tool.add_vertex(corner)
	tool.index()
	tool.generate_normals()
	parts.add_painted(tool.commit(), Transform3D.IDENTITY)
