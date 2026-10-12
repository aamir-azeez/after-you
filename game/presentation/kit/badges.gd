extends RefCounted
## World kit: the "You" / "Memory" / "Waiting" badge above each spirit.
## One factory and named styles; worlds keep their own badge dictionaries
## (actor_badges on the day worlds, _badges on the Lighthouse lineage).

const NUNITO = preload("res://assets/fonts/nunito.ttf")
const CREAM := Color("e9edd6")

const STYLES := {
	# Relay Isles: large, bold, heavy outline, grows up from its anchor.
	"relay": {"weight": 700.0, "font_size": 56, "pixel_size": 0.0085, "y": 1.42, "bottom": true, "modulate": CREAM, "outline": Color("0f2a26"), "outline_size": 18},
	# First Steps: regular weight, thin outline.
	"first_steps": {"weight": 0.0, "font_size": 42, "pixel_size": 0.006, "y": 1.34, "bottom": false, "modulate": CREAM, "outline": Color("193d39"), "outline_size": 8},
	# Lighthouse lineage (every physical and journey chapter).
	"lighthouse": {"weight": 700.0, "font_size": 36, "pixel_size": 0.005, "y": 1.45, "bottom": false, "modulate": Color("e7eff2"), "outline": Color("102133"), "outline_size": 8},
}

## A badge in the named style, added under spirit. Depth flags keep it readable
## when scenery crosses its anchor.
static func make(spirit: Node3D, style_name: String) -> Label3D:
	var style: Dictionary = STYLES[style_name]
	var badge := Label3D.new()
	badge.no_depth_test = true
	badge.outline_render_priority = 1
	badge.render_priority = 2
	if float(style.weight) > 0.0:
		var font := FontVariation.new()
		font.base_font = NUNITO
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): float(style.weight)}
		badge.font = font
	else:
		badge.font = NUNITO
	badge.font_size = int(style.font_size)
	badge.pixel_size = float(style.pixel_size)
	if bool(style.bottom): badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	badge.position.y = float(style.y)
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.modulate = style.modulate
	badge.outline_modulate = style.outline
	badge.outline_size = int(style.outline_size)
	spirit.add_child(badge)
	return badge
