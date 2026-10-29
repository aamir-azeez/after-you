extends RefCounted
## The one place a cosmetic's tier is drawn (Pollen boards 5b and 4): its frame
## colour, the soft glow that Rare, Epic and Special get in their own colour,
## the small tier mark (one leaf, two leaves, a lavender bud, a lilac flower,
## a gold star flower; a lock for Earned), and the tier word in capitals.
## Colour is never the only signal: every tier also has its own mark and word.
## Every place that frames an item by its tier asks here (the Wardrobe's cards
## today; the item bloom card is to use it too), so a tier's look changes in one file.
##
## Flat styleboxes and one _draw per mark: nothing animates, nothing draws per frame.
const PlayerCopy = preload("res://presentation/player_copy.gd")

const TIERS: Array[String] = ["common", "uncommon", "rare", "epic", "special", "earned"]
## Frame colours, softest to brightest; Earned is a cool silver edge.
const FRAME := {"common": Color("c9d6bd"), "uncommon": Color("8fcaa6"), "rare": Color("a9b5ee"), "epic": Color("dfaee6"), "special": Color("efc777"), "earned": Color("b7cdc6")}
## The mark's own ink, darker than the frame so it reads on cream.
const INK := {"common": Color("7da36f"), "uncommon": Color("3f8f68"), "rare": Color("6d7fd4"), "epic": Color("a95fb6"), "special": Color("d99a2b"), "earned": Color("5f7f78")}
## The tiers that glow, and how far.
const GLOW := {"rare": 10, "epic": 12, "special": 14}
## The card's cream and the selected card's fill.
const CARD := Color("fbf7ea")
const CARD_SELECTED := Color("f4f8ee")

static func known(tier: String) -> bool:
	return tier in TIERS

static func frame(tier: String) -> Color:
	return FRAME.get(tier, FRAME.common)

static func ink(tier: String) -> Color:
	return INK.get(tier, INK.common)

static func glows(tier: String) -> bool:
	return GLOW.has(tier)

## The tier word in capitals ("RARE"), from PlayerCopy.
static func word(tier: String) -> String:
	return str(PlayerCopy.WARDROBE_TIERS.get(tier, "")).to_upper()

## A card's frame: cream, a 2 px edge in the tier's colour (4 px when picked),
## and the tier's soft glow.
static func style(tier: String, radius: int = 16, picked: bool = false, fill: Color = CARD) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = CARD_SELECTED if picked and fill == CARD else fill
	box.border_color = frame(tier)
	box.set_border_width_all(4 if picked else 2)
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	if glows(tier):
		box.shadow_color = Color(frame(tier), 0.55)
		box.shadow_size = int(GLOW[tier])
	return box

## The tier's mark, `side` pixels square. Takes no input.
static func mark(tier: String, side: float = 14.0) -> Control:
	var glyph := Mark.new()
	glyph.tier = tier
	glyph.ink = ink(tier)
	glyph.name = "TierMark"
	glyph.custom_minimum_size = Vector2(side, side)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return glyph

## The mark and the tier word side by side, as a card's corner shows them.
static func label(tier: String, font_size: int = 12, font: Font = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "TierLabel"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	row.add_child(mark(tier, font_size + 5.0))
	var text := Label.new()
	text.text = word(tier)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_size_override("font_size", font_size)
	text.add_theme_color_override("font_color", Color("38504b"))
	if font != null: text.add_theme_font_override("font", font)
	row.add_child(text)
	return row

## A tier's glyph, drawn once from flat shapes.
class Mark extends Control:
	var tier := "common"
	var ink := Color.BLACK

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		match tier:
			"common": _leaf(c, r, 0.0, ink)
			"uncommon":
				_leaf(c + Vector2(-r * 0.22, r * 0.1), r * 0.85, -0.55, ink)
				_leaf(c + Vector2(r * 0.22, r * 0.1), r * 0.85, 0.55, ink)
			"rare":
				for angle: float in [-0.75, 0.0, 0.75]:
					_petal(c + Vector2(0, r * 0.35), r * 0.95, angle, ink)
			"epic":
				for index in range(5): _petal(c, r * 0.62, TAU * index / 5.0, ink)
				draw_circle(c, r * 0.22, Color("f6e2f4"), true, -1.0, true)
			"special":
				var points := PackedVector2Array()
				for index in range(10):
					var reach := r * (0.95 if index % 2 == 0 else 0.45)
					var angle := -PI * 0.5 + TAU * index / 10.0
					points.append(c + Vector2(cos(angle), sin(angle)) * reach)
				draw_colored_polygon(points, ink)
				draw_circle(c, r * 0.2, Color("fff3cc"), true, -1.0, true)
			_:
				# A small padlock: the body and its shackle.
				draw_rect(Rect2(c + Vector2(-r * 0.62, -r * 0.05), Vector2(r * 1.24, r * 0.95)), ink)
				draw_arc(c + Vector2(0, -r * 0.08), r * 0.42, PI, TAU, 12, ink, maxf(1.5, r * 0.22), true)

	## A leaf standing up, tipped by `tilt` radians.
	func _leaf(base: Vector2, reach: float, tilt: float, color: Color) -> void:
		var points := PackedVector2Array()
		for index in range(13):
			var t := float(index) / 12.0
			var half := sin(t * PI) * reach * 0.42
			points.append(Vector2(-half, reach * 0.9 - t * reach * 1.8))
		for index in range(11, 0, -1):
			var t := float(index) / 12.0
			points.append(Vector2(sin(t * PI) * reach * 0.42, reach * 0.9 - t * reach * 1.8))
		var turned := PackedVector2Array()
		for point: Vector2 in points: turned.append(base + point.rotated(tilt))
		draw_colored_polygon(turned, color)

	## One rounded petal from `base`, pointing at `angle` from straight up.
	func _petal(base: Vector2, reach: float, angle: float, color: Color) -> void:
		var tip := base + Vector2(0, -reach).rotated(angle)
		var middle := base.lerp(tip, 0.55)
		draw_circle(middle, reach * 0.34, color, true, -1.0, true)
		draw_circle(base.lerp(tip, 0.25), reach * 0.22, color, true, -1.0, true)
