extends Control
## The duel energy cost chip, and the one place it is made (ENERGY-PLAN.md
## "Colours for the build", board-10-energy-lobby): a small fully rounded pill,
## ink filled with a mint ring inside, the full sprout (kit/sprout_mark.gd) and
## a cream "1" in a heavy weight. It reads the same on the cream and the dark
## buttons, so it is never tinted by the button under it.
##
## Every button that starts or joins a duel wears one through on_button(): the
## chip sits at the button's right inside room added to the button's own
## padding, so its words keep their place and their text (the tap gate's "..."
## still shows). A row that lays out its own words takes make() beside them.
## A held button (presentation/offline_hold.gd) fades its children, the chip
## with them; a button greyed for another reason fades it too (fade()).
## Drawn once per resize, never per frame; it takes no input.
const SproutMark = preload("res://presentation/kit/sprout_mark.gd")
const DashedBox = preload("res://presentation/kit/dashed_box.gd")
const SettingsKit = preload("res://presentation/settings_kit.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")

## What a start or a join costs (backend/src/pollen/energy.ts spendEnergy).
const COST := 1
const NAME := "EnergyCost"
const FILL := UiTokens.INK
const RING := UiTokens.MINT
const NUMBER := UiTokens.CREAM
const RING_WIDTH := 1.5
## The pill's room round its sprout and number (board: 2 9 2 5, 3 between).
const PAD_LEFT := 5.0
const PAD_RIGHT := 9.0
const PAD_Y := 2.0
const BETWEEN := 3.0
## The room left between a button's words and its chip, and between the chip and the button's edge.
const BUTTON_GAP := 6.0
const BUTTON_EDGE := 8.0
const STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]
## How much of a chip shows on a button greyed for its own reason.
const FADED := 0.45

var sprout := 22.0
var font_size := 17
var _font: Font

## A chip with a `sprout_side` pixel sprout and the number at `number_size`.
static func make(sprout_side: float = 22.0, number_size: int = 17) -> Control:
	var chip: Control = load("res://presentation/kit/energy_chip.gd").new()
	chip.name = NAME
	chip.sprout = sprout_side
	chip.font_size = number_size
	chip._font = SettingsKit.font(800)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.custom_minimum_size = chip.chip_size()
	chip.resized.connect(chip.queue_redraw)
	return chip

## The chip's own size.
func chip_size() -> Vector2:
	var number := _font.get_string_size(str(COST), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return Vector2(ceilf(PAD_LEFT + sprout + BETWEEN + number.x + PAD_RIGHT), ceilf(maxf(sprout, number.y) + PAD_Y * 2.0))

## Puts a chip on `button`'s right end, in room added to its padding, and
## takes away a right icon it had (Start a duel's arrow, as the board draws
## it). Once per button; returns the chip.
static func on_button(button: Button, sprout_side: float = 20.0, number_size: int = 17) -> Control:
	var existing := button.get_node_or_null(NAME) as Control
	if existing != null: return existing
	if button.icon != null and button.icon_alignment == HORIZONTAL_ALIGNMENT_RIGHT: button.icon = null
	var chip := make(sprout_side, number_size)
	var shape: Vector2 = chip.custom_minimum_size
	chip.anchor_left = 1.0
	chip.anchor_right = 1.0
	chip.anchor_top = 0.5
	chip.anchor_bottom = 0.5
	chip.offset_top = -shape.y * 0.5
	chip.offset_bottom = shape.y * 0.5
	button.add_child(chip)
	if button.disabled: chip.modulate.a = FADED
	# The button's styles come from the theme of the screen it joins: padded once it is there.
	if button.is_inside_tree(): _pad(button, chip)
	else: button.ready.connect(_pad.bind(button, chip), CONNECT_ONE_SHOT)
	return chip

## Fades `button`'s chip while the button is greyed for its own reason (not offline: the hold fades it).
static func fade(button: Button, faded: bool) -> void:
	var chip := button.get_node_or_null(NAME) as Control if button != null else null
	if chip != null: chip.modulate.a = FADED if faded else 1.0

## Sets each of the button's styles' right padding to the chip, its gap and a small edge (as the
## board tucks the chip near the button's end), and sets the chip in that room.
static func _pad(button: Button, chip: Control) -> void:
	if not is_instance_valid(button) or not is_instance_valid(chip) or button.has_meta(NAME): return
	button.set_meta(NAME, true)
	var edge := BUTTON_EDGE
	for state: String in STATES:
		var style := button.get_theme_stylebox(state)
		if style == null: continue
		var wider := style.duplicate() as StyleBox
		var right := style.get_content_margin(SIDE_RIGHT)
		if state == "normal": edge = minf(right, BUTTON_EDGE)
		wider.content_margin_right = minf(right, BUTTON_EDGE) + chip.custom_minimum_size.x + BUTTON_GAP
		button.add_theme_stylebox_override(state, wider)
	chip.offset_right = -edge
	chip.offset_left = -edge - chip.custom_minimum_size.x

func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	if box.size.x <= 2.0 or box.size.y <= 2.0: return
	var outline := DashedBox.outline(box, box.size.y * 0.5)
	draw_colored_polygon(outline, FILL)
	var inset := RING_WIDTH * 0.5
	var ring := DashedBox.outline(box.grow(-inset), box.size.y * 0.5 - inset)
	ring.append(ring[0])
	draw_polyline(ring, RING, RING_WIDTH, true)
	SproutMark.draw_sprout(self, Rect2(Vector2(PAD_LEFT, (size.y - sprout) * 0.5), Vector2(sprout, sprout)), true)
	var ascent := _font.get_ascent(font_size)
	var descent := _font.get_descent(font_size)
	var baseline := (size.y + ascent - descent) * 0.5
	draw_string(_font, Vector2(PAD_LEFT + sprout + BETWEEN, baseline), str(COST), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, NUMBER)
