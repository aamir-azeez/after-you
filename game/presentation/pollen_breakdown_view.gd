extends RefCounted
## Draws the Pollen results card's rows (presentation/pollen_breakdown.gd) as
## pollen board 7b lays them out: each row's words on the left and its value on
## the right, a Pollen mark (kit/pollen_mark.gd, the one grain) before every
## amount (`amount_row`, the one row shape every Pollen amount row uses, the
## duel result card's too), thin rules between the rows, "This turn" a size up,
## a lucky bloom as a small tag with its flower beside the bloomed total, and an
## item bloom as the player's own pip wearing the new item beside its tag and
## tier line.
## Words-only rows (why a turn paid a little) take the whole width and wrap by
## words. A Sunshine row's words follow the line sun (kit/sun_mark.gd); each
## achievement a credit paid is a plum line under the rest (Fruits board 6b:
## kit/orchard_surface.gd, its Fruits after the Fruit mark).
## Built once per card, never per frame; nothing moves.
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Breakdown = preload("res://presentation/pollen_breakdown.gd")
const SunMark = preload("res://presentation/kit/sun_mark.gd")
const Orchard = preload("res://presentation/kit/orchard_surface.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")

const FONT_SIZE := 18
const TOTAL_SIZE := 22
const TAG_FILL := Color("f6dada")
const TAG_INK := Color("7e2f36")
const RULE := Color(1, 1, 1, 0.08)
## The meta a plum line keeps its achievement id under.
const FRUIT_ID := "fruit_id"

## The rows as one column. `ink` colours the words (the card's muted text);
## amounts are cream. `pip` makes the still pip an item bloom shows
## (pollen_result_line.gd dropped_pip), `flower` the small bloom flower.
static func build(rows: Array[Dictionary], ink: Color, pip: Callable, flower: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "PollenBreakdown"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		if index > 0 and str(row.kind) in ["bonus", "boost", "duel", "sunshine", "total", "clear", "earned"]: box.add_child(_rule())
		box.add_child(_row(row, ink, pip, flower))
	return box

static func _row(row: Dictionary, ink: Color, pip: Callable, flower: Callable) -> Control:
	match str(row.kind):
		"reason":
			var words := _text(str(row.label), FONT_SIZE, ink)
			words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			return words
		"bloom":
			return _line(tag(str(row.label), flower), str(row.value), TOTAL_SIZE)
		"item_pollen":
			var line := HBoxContainer.new()
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(tag(str(row.label), flower))
			return line
		"item":
			return _item(row, ink, pip, flower)
		"sunshine":
			var words := HBoxContainer.new()
			words.mouse_filter = Control.MOUSE_FILTER_IGNORE
			words.add_theme_constant_override("separation", 6)
			words.add_child(SunMark.beside(FONT_SIZE, ink))
			words.add_child(_text(str(row.label), FONT_SIZE, ink))
			return _line(words, str(row.value), FONT_SIZE, true, true)
		"fruit":
			return fruit_line(row)
	var size := TOTAL_SIZE if str(row.kind) in ["total", "earned"] else FONT_SIZE
	return _line(_text(str(row.label), size, UiTokens.CREAM if size == TOTAL_SIZE else ink), str(row.value), size, bool(row.grain), bool(row.get("plus", false)))

## Fruits board 6b's plum line: the achievement's name on the left, then
## "+ [Fruit] 10 Fruits" in bold peach on the right.
static func fruit_line(row: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "FruitResultLine"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", ControlTheme.padded(Orchard.flat(12, Orchard.PLUM_DARK), 14.0, 8.0))
	var words := _text(str(row.label), FONT_SIZE, Orchard.TEXT)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var amount := _text(str(row.value), TOTAL_SIZE, Orchard.PEACH)
	amount.add_theme_font_override("font", ShopKit.bold_font())
	var line := amount_row(words, amount, TOTAL_SIZE, true, true, Breakdown.FRUITS)
	var plus: Label = line.find_child("PollenPlus", true, false)
	if plus != null: plus.add_theme_font_size_override("font_size", FONT_SIZE)
	panel.add_child(line)
	# Which achievement it shows (pollen_result_line.gd once marks it shown).
	if row.has("id"): panel.set_meta(FRUIT_ID, str(row.id))
	return panel

## Words on the left, the value (after its mark) on the right, in cream.
static func _line(left: Control, value: String, size: int, grain: bool = true, plus: bool = false) -> HBoxContainer:
	return amount_row(left, _text(value, size, UiTokens.CREAM) if not value.is_empty() else null, size, grain, plus)

## One Pollen row: `left` (its words, or a tag) fills the row, then the Pollen
## mark at `size` and `amount` on the right. No amount, no mark. `plus` (a row
## that adds to Base) puts "+" in the amount's own font and ink just before the
## mark ("+[grain] 22"). `currency` picks the mark (kit/currency_mark.gd):
## Pollen's grain unless it names Fruits.
static func amount_row(left: Control, amount: Label, size: int, grain: bool = true, plus: bool = false, currency: String = "") -> HBoxContainer:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 8)
	# Words fill the row; a tag keeps its own size at the row's start.
	var lead := left
	if left is PanelContainer:
		lead = HBoxContainer.new()
		lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lead.add_child(left)
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(lead)
	if amount == null: return line
	if plus:
		# The plus and the mark sit close together, as one sign before the amount.
		var signed := HBoxContainer.new()
		signed.name = "PollenSign"
		signed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		signed.add_theme_constant_override("separation", 2)
		var plus_label := amount.duplicate() as Label
		plus_label.name = "PollenPlus"
		plus_label.text = "+"
		signed.add_child(plus_label)
		if grain: signed.add_child(CurrencyMark.beside(currency, size))
		line.add_child(signed)
	elif grain: line.add_child(CurrencyMark.beside(currency, size))
	amount.name = "PollenAmount"
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(amount)
	return line

## The pip wearing the new item, its tag and "Added to your Wardrobe. Common."
static func _item(row: Dictionary, ink: Color, pip: Callable, flower: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.name = "PollenItemBloom"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(Color(1, 1, 1, 0.05), 14), 12.0, 10.0))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 12)
	panel.add_child(line)
	if pip.is_valid(): line.add_child(pip.call(str(row.item_id)))
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(words)
	var tag_row := HBoxContainer.new()
	tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_row.add_child(tag(str(row.label), flower))
	words.add_child(tag_row)
	var tier := Breakdown.tier_name(str(row.get("tier", "")))
	var added := _text(PlayerCopy.POLLEN_ITEM_ADDED % tier if not tier.is_empty() else PlayerCopy.POLLEN_ITEM_ADDED_PLAIN, 16, ink)
	added.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(added)
	return panel

## A lucky bloom's tag: a small rounded label with its flower.
static func tag(text: String, flower: Callable) -> PanelContainer:
	var tag := PanelContainer.new()
	tag.name = "PollenBloomTag"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(TAG_FILL, 10), 8.0, 3.0))
	var inside := HBoxContainer.new()
	inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.add_theme_constant_override("separation", 6)
	tag.add_child(inside)
	if flower.is_valid(): inside.add_child(flower.call())
	inside.add_child(_text(text, 16, TAG_INK))
	return tag

static func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = RULE
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule

static func _text(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
