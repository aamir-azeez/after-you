extends RefCounted
## The Sprigs (leaf): the pip's own leaf in a new colour, as the sprig tiles
## on the Orchard board draw them (Fruits board 4a). One art script serves the
## four, each descriptor naming it; the colour is picked by the worn leaf's id.
## No geometry: the leaf keeps its mesh and is drawn with a shared material
## (kit/primitives.gd, released at shutdown), so it costs no draw call.
const Primitives = preload("res://presentation/kit/primitives.gd")

## Each Sprig's colour by item id.
const COLOURS := {
	"sprig_coral": Color("f2a988"),
	"sprig_plum": Color("c98bc0"),
	"sprig_sun": Color("e9c35a"),
	"sprig_sky": Color("8cc5d9"),
}
## As matte as the pip's own leaf (spirit_visual.gd _body_material).
const ROUGHNESS := 0.9

static func wear(look: RefCounted) -> void:
	var id := str(look.outfit.get("leaf", ""))
	if not COLOURS.has(id): return
	look.set_material(look.leaf(), Primitives.shared_material(COLOURS[id], ROUGHNESS))
