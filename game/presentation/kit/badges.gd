extends RefCounted
## World kit: the "You" / "Memory" / "Waiting" badge above each spirit, one
## style in every chapter. Worlds keep their own badge dictionaries
## (actor_badges on the day worlds, _badges on the Lighthouse lineage).
##
## The badge keeps a fixed size on screen: with an orthographic camera, a
## fixed-size label is a constant fraction of the view height, so it reads the
## same in a wide fit-all chapter, a close follow camera and under pinch zoom.
## Its letters are FONT_SIZE * PIXEL_SIZE / 2 of the view height: about 24 px
## on a 720 px tall view, the same proportion as the HUD text.

const NUNITO = preload("res://assets/fonts/nunito.ttf")
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
const CREAM := Color("e9edd6")
const OUTLINE := Color("102133")
const FONT_SIZE := 48
const PIXEL_SIZE := 0.0014
const OUTLINE_SIZE := 12
## Height of the anchor above the spirit's feet; the text grows up from it,
## clear of the head and anything carried.
const ANCHOR_Y := 1.42

## A badge added under spirit. Depth flags keep it readable when scenery
## crosses its anchor; reaction photos hide it by its meta.
static func make(spirit: Node3D) -> Label3D:
	var badge := Label3D.new()
	badge.set_meta("replay_role_badge", true)
	badge.no_depth_test = true
	badge.outline_render_priority = 1
	badge.render_priority = 2
	var font := FontVariation.new()
	font.base_font = NUNITO
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700.0}
	badge.font = font
	badge.font_size = FONT_SIZE
	badge.pixel_size = PIXEL_SIZE
	badge.fixed_size = true
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	badge.position.y = ANCHOR_Y
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.modulate = CREAM
	badge.outline_modulate = OUTLINE
	badge.outline_size = OUTLINE_SIZE
	spirit.add_child(badge)
	return badge

## A small glyph over a world sign that keeps its size on screen (Turn of the
## Tide's gauge waves): billboard letters in the label bubbles' heavy font,
## outlined, growing up from `at` under parent.
static func glyph(parent: Node3D, text: String, at: Vector3, color: Color, outline: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = LabelBubble.shared_font()
	label.font_size = 64
	label.pixel_size = 0.0011
	label.fixed_size = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.outline_modulate = outline
	label.outline_size = 14
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.position = at
	parent.add_child(label)
	return label
