extends RefCounted
## World kit: the matching tags that tie a machine to the crossing it opens
## when no cable can run between them. The same glyph (one bar, two bars, a
## dot, a key...) lies flat beside the machine and again at the crossing's
## end, in the machine's colour, so a player matches them by shape and count.
##
## A world says which family of tags it draws (STYLES: their bar's size and
## spacing) and what each tag shows: tally(style, [glyph, count], colour, at,
## parent). Ownership marks are kit/owner_mark.gd.
##
## Presentation only: built from the hashed stage; nothing here feeds the
## simulation, a recording or a checkpoint. Cost: plain leaves with kit-cached
## meshes and looks (Primitives), folded by the world's static fold into the
## batch of their colour; nothing runs per frame.
const Primitives = preload("res://presentation/kit/primitives.gd")
const OwnerMark = preload("res://presentation/kit/owner_mark.gd")
## Gate cables (cooperative_world floor cables): this wide, their centres this
## high above the floor.
const LINK_WIDTH := 0.025
const LINK_LIFT := 0.03
## A floor-cable family's end tag lies on the crossing's end mark and under a
## cable that meets it there, so its top sits midway between their tops.
const LINK_TAG_THICKNESS := (OwnerMark.ROUTE_LIFT + OwnerMark.THICKNESS * 0.5) + (LINK_LIFT + LINK_WIDTH * 0.5) - 2.0 * LINK_LIFT
## Each family: its bar's size, the spacing between glyphs, how far above `at`
## they lie, and the name its bars take ("" for none).
const STYLES := {
	## cooperative_world's floor cables: a pair of tags at each end.
	&"link_tag": {"bar": Vector3(0.07, LINK_TAG_THICKNESS, 0.18), "spacing": 0.12, "lift": 0.0, "name": "GateLinkTag"},
	## journey_world's crests, a few millimetres above the cable meeting them.
	&"crest": {"bar": Vector3(0.07, 0.014, 0.18), "spacing": 0.12, "lift": 0.006, "name": ""},
	## tide_world's crests: the whole glyph set, inside its crest node.
	&"tide_crest": {"bar": Vector3(0.07, 0.014, 0.18), "spacing": 0.13, "lift": 0.0, "name": ""},
	## house_world's route symbols: one, two or three wider bars.
	&"route_symbol": {"bar": Vector3(0.09, 0.025, 0.20), "spacing": 0.14, "lift": 0.0, "name": ""},
}
## `shape` ([glyph, count]: bar, cross, dot, chevron, ring, pin or key, and how many) of `style` lying flat
## and centred on `at` in `parent`, in `tint`.
static func tally(style: StringName, shape: Array, tint: Color, at: Vector3, parent: Node3D) -> void:
	var spec: Dictionary = STYLES[style]
	var bar: Vector3 = spec.bar
	var lift := float(spec.lift)
	var look := Primitives.shared_material(tint)
	var count := int(shape[1])
	for index in range(count):
		var x := (float(index) - float(count - 1) * 0.5) * float(spec.spacing)
		match str(shape[0]):
			"bar": _named(_box(bar, look, at + Vector3(x, lift, 0), parent), spec)
			"cross": _box(Vector3(bar.z, bar.y, bar.x), look, at + Vector3(0, lift, x), parent)
			"dot": Primitives.mesh_node(Primitives.cached_shape(Primitives.cylinder_mesh(0.05, 0.016)), look, at + Vector3(x, lift, 0), parent)
			"chevron":
				for side in [-1, 1]:
					_box(Vector3(0.04, bar.y, 0.13), look, at + Vector3(x + float(side) * 0.03, lift, 0), parent).rotation.y = float(side) * 0.55
			"ring": _ring(0.055, look, at + Vector3(x, lift, 0), parent)
			"pin":
				_box(Vector3(0.035, bar.y, 0.16), look, at + Vector3(x, lift, 0.02), parent)
				_ring(0.04, look, at + Vector3(x, lift, -0.08), parent)
			"key":
				_ring(0.045, look, at + Vector3(x, lift, -0.07), parent)
				_box(Vector3(0.03, bar.y, 0.14), look, at + Vector3(x, lift, 0.03), parent)
				_box(Vector3(0.05, bar.y, 0.025), look, at + Vector3(x + 0.03, lift, 0.08), parent)
				_box(Vector3(0.04, bar.y, 0.025), look, at + Vector3(x + 0.025, lift, 0.04), parent)
			_: push_error("LevelHints: no glyph '%s'" % shape[0])

static func _box(size: Vector3, look: Material, at: Vector3, parent: Node3D) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.cached_box(size), look, at, parent)

static func _ring(radius: float, look: Material, at: Vector3, parent: Node3D) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.cached_shape(Primitives.ring_mesh(radius)), look, at, parent)

static func _named(node: MeshInstance3D, spec: Dictionary) -> void:
	if not str(spec.name).is_empty(): node.name = str(spec.name)
