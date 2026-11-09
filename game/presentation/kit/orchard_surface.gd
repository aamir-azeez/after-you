extends RefCounted
## The Orchard material, and the one place it is defined (Fruits boards 2, 3,
## 4a, 5a, 5b, 6a): ripe plum at dusk with a soft rose rim and peach accents.
## Only Fruit surfaces wear it: Fruit packs, the Orchard shelf, the Fruit tile
## on Full Journey, Fruit amounts on the chip and the monthly card, Fruit
## buttons. Pollen keeps the game's cream cards. Every plum fill, edge and
## peach button is made here, so the Orchard looks the same on every screen.
##
## A plum card (card()) is a PanelContainer that paints its own back: a rounded
## rectangle whose plum runs from a lighter top left to a deep bottom, with its
## rim (and, framed, a second rim inset as the Barrel card draws it). It paints
## once per resize, never per frame, under whatever the card holds.
const ControlTheme = preload("res://presentation/control_theme.gd")
const DashedBox = preload("res://presentation/kit/dashed_box.gd")

## A card's plum: lit at the top left, ripe in the middle, deep at the bottom right.
const TOP := Color("6a3459")
const MIDDLE := Color("46213f")
const DEEP := Color("2a1530")
## Where the middle plum sits between the light and the deep end.
const MIDDLE_AT := 0.44
## The flat plum of small pieces (the chip's Fruit half, the picked Fruits tab, a Fruit tile).
const PLUM := Color("4f2e49")
const PLUM_DARK := Color("411f3c")
const PLUM_LIGHT := Color("6d405d")
## The peach rim round a plum piece, and the framed card's inner line.
const RIM := Color(0.949, 0.718, 0.612, 0.5)
const FRAME := Color(0.949, 0.718, 0.612, 0.4)
## Ripe peach: names, bonus lines and the ribbon on plum.
const RIPE := Color("f7d2b4")
## Peach buttons (the best pack's price) and their plum ink.
const PEACH := Color("f6c9a6")
const PEACH_LIGHT := Color("fbdcc2")
const PEACH_INK := Color("3a1733")
## Words on plum.
const TEXT := Color("fbeee4")
const TEXT_SOFT := Color("e2c3d6")
## A Fruit number on a cream card ("First pack 110").
const ON_CREAM := Color("8a3d6e")
## The framed card's inner rim sits this far in.
const FRAME_INSET := 12.0
const CORNER_STEPS := 8

## A plum card: `card_radius` round, `is_framed` adds the inner rim, `pad` is
## the room between its edge and what it holds.
static func card(card_radius: float = 22.0, is_framed: bool = false, pad: Vector2 = Vector2(16, 16)) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ControlTheme.padded(StyleBoxEmpty.new(), pad.x, pad.y))
	panel.draw.connect(func() -> void: paint(panel, card_radius, is_framed))
	panel.resized.connect(panel.queue_redraw)
	return panel

## A flat plum style: `fill` with the rim, `card_radius` round.
static func flat(card_radius: int, fill: Color = PLUM, edge: Color = RIM, edge_width: int = 2) -> StyleBoxFlat:
	var style := ControlTheme.rounded(fill, card_radius, edge)
	style.set_border_width_all(edge_width)
	return style

## A plum button with words on plum (Fruits boards 4a and 4b: Buy for a Fruit
## price, Get Fruits; Sunshine's Buy), every state drawn.
static func plum_button(button: Button, card_radius: int = 16) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var fill := PLUM
		if state == "hover": fill = PLUM_LIGHT
		if state in ["pressed", "hover_pressed"]: fill = PLUM_DARK
		if state == "disabled": fill = Color(PLUM, 0.5)
		button.add_theme_stylebox_override(state, flat(card_radius, fill, TEXT if state == "focus" else RIM))
		button.add_theme_color_override("font_color" if state == "normal" else "font_%s_color" % state, TEXT)

## A peach button with plum ink (the best pack's price), every state drawn.
static func peach_button(button: Button, card_radius: int = 14) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var fill := PEACH
		if state == "hover": fill = PEACH_LIGHT
		if state in ["pressed", "hover_pressed"]: fill = PEACH.darkened(0.08)
		if state == "disabled": fill = Color(PEACH, 0.45)
		var style := ControlTheme.rounded(fill, card_radius)
		if state == "focus":
			style = ControlTheme.rounded(Color.TRANSPARENT, card_radius, TEXT)
			style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_color" if state == "normal" else "font_%s_color" % state, PEACH_INK)

## Paints the plum back over all of `control` (from its draw signal).
static func paint(control: Control, card_radius: float, is_framed: bool) -> void:
	var size := control.size
	if size.x <= 2.0 or size.y <= 2.0: return
	var outline := DashedBox.outline(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), card_radius, CORNER_STEPS)
	var colours := PackedColorArray()
	for point: Vector2 in outline:
		colours.append(shade(clampf(0.7 * point.y / size.y + 0.3 * point.x / size.x, 0.0, 1.0)))
	control.draw_polygon(outline, colours)
	var ring := outline.duplicate()
	ring.append(outline[0])
	control.draw_polyline(ring, RIM, 2.0, true)
	if is_framed:
		var inner := DashedBox.outline(Rect2(Vector2.ONE * FRAME_INSET, size - Vector2.ONE * FRAME_INSET * 2.0), maxf(card_radius - FRAME_INSET * 0.5, 4.0), CORNER_STEPS)
		inner.append(inner[0])
		control.draw_polyline(inner, FRAME, 2.0, true)

## The card's plum at `t` (0 the lit top left, 1 the deep bottom right).
static func shade(t: float) -> Color:
	return TOP.lerp(MIDDLE, t / MIDDLE_AT) if t < MIDDLE_AT else MIDDLE.lerp(DEEP, (t - MIDDLE_AT) / (1.0 - MIDDLE_AT))
