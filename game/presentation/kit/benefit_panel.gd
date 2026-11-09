extends RefCounted
## One cream panel on the Full Journey card (pollen-concepts board 3): an icon
## on the left, then a title, an explainer and, for the monthly Pollen, the
## ladder line in bold. While Fruits show, the monthly gifts are a row of two
## tiles (Fruits board 5a): the Pollen tile in the warm cream and the Fruit tile
## on the Orchard plum (kit/orchard_surface.gd), each mark from
## kit/currency_mark.gd. The duel energy perk is a cool cream panel with the
## sprout (kit/sprout_mark.gd) and its row of sprouts at the right
## (board-10-energy-full-journey). presentation/full_journey_benefits.gd says what each
## panel holds; this only draws it. Panels take no input, so a drag that starts
## on one still scrolls the card.
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")
const Orchard = preload("res://presentation/kit/orchard_surface.gd")
const SproutMark = preload("res://presentation/kit/sprout_mark.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ROOM_ICON = preload("res://assets/ui/social/users.svg")
const FREDOKA = preload("res://assets/fonts/fredoka.ttf")
const NUNITO = preload("res://assets/fonts/nunito.ttf")

## The room boost panel is a cool mint cream, the monthly Pollen a warm cream.
const FILL := {"room": Color("e8f0e6"), "pollen": Color("f5eedb")}
const BODY := Color("4f6661")
const TITLE_SIZE := 18
const BODY_SIZE := 13
const ICON := 30.0
## The energy perk's sprouts at its right (spec `sprouts`).
const SPROUT := 18.0
const SPROUT_GAP := 3.0

## A panel for `spec` ({name, icon, title, body, ladder, rich, sprouts}), or a row of
## tiles for {name, tiles: [specs]}. `sprouts`: a row of that many full sprouts at the right.
static func make(spec: Dictionary) -> Control:
	if spec.has("tiles"): return _row(spec)
	var icon_kind := str(spec.get("icon", "room"))
	var plum := icon_kind == CurrencyMark.FRUITS
	var panel: PanelContainer
	if plum: panel = Orchard.card(16, false, Vector2(14, 10))
	else:
		panel = PanelContainer.new()
		var style := ControlTheme.rounded(FILL.get(icon_kind, FILL.room), 16)
		ControlTheme.padded(style, 14.0, 10.0)
		panel.add_theme_stylebox_override("panel", style)
	panel.name = str(spec.get("name", "FullJourneyPanel"))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	row.add_child(_icon(icon_kind, float(spec.get("icon_size", ICON))))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	var title := _text(str(spec.get("title", "")), TITLE_SIZE, Orchard.TEXT if plum else UiTokens.INK, _font(FREDOKA, 600.0))
	title.name = "PanelTitle"
	column.add_child(title)
	var words := str(spec.get("body", ""))
	if bool(spec.get("rich", false)): column.add_child(_rich(words, Orchard.TEXT_SOFT if plum else BODY, Orchard.RIPE if plum else UiTokens.INK))
	elif not words.is_empty():
		var body := _text(words, BODY_SIZE, Orchard.TEXT_SOFT if plum else BODY, null)
		body.name = "PanelBody"
		column.add_child(body)
	var ladder := str(spec.get("ladder", ""))
	if not ladder.is_empty():
		var line := _text(ladder, BODY_SIZE, UiTokens.INK, _font(NUNITO, 800.0))
		line.name = "PanelLadder"
		column.add_child(line)
	var sprouts := int(spec.get("sprouts", 0))
	if sprouts > 0:
		var row_of := SproutMark.row(sprouts, sprouts, SPROUT, SPROUT_GAP)
		row_of.name = "PanelSprouts"
		row.add_child(row_of)
	return panel

## Two tiles side by side, each as wide as the other, as tall as the taller.
static func _row(spec: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = str(spec.get("name", "FullJourneyTiles"))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	for tile: Dictionary in spec.tiles:
		var made := make(tile)
		made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(made)
	return row

## A body whose [b] part stands out (the welcome basket), still taking no input.
static func _rich(words: String, color: Color, strong: Color) -> RichTextLabel:
	var body := RichTextLabel.new()
	body.name = "PanelBody"
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Its own scroll bar never shows (fit_content); it must not catch a drag either.
	body.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_font_size_override("normal_font_size", BODY_SIZE)
	body.add_theme_font_size_override("bold_font_size", BODY_SIZE)
	body.add_theme_font_override("normal_font", _font(NUNITO, 600.0))
	body.add_theme_font_override("bold_font", _font(NUNITO, 800.0))
	body.add_theme_color_override("default_color", color)
	body.text = words.replace("[b]", "[b][color=#%s]" % strong.to_html(false)).replace("[/b]", "[/color][/b]")
	return body

static func _icon(kind: String, side: float = ICON) -> Control:
	if kind == "energy":
		var sprout := SproutMark.make(true, side)
		sprout.name = "EnergyIcon"
		return sprout
	if kind in [CurrencyMark.POLLEN, CurrencyMark.FRUITS]:
		var mark := CurrencyMark.make(kind, side)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return mark
	var icon := TextureRect.new()
	icon.name = "RoomIcon"
	icon.texture = ROOM_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(ICON, ICON) * 0.6
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate = Color(UiTokens.INK, 0.8)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

static func _text(text: String, font_size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font != null: label.add_theme_font_override("font", font)
	return label

## A weighted font. Each panel makes its own (two panels on a card), so no
## static cache outlives the session.
static func _font(base: Font, weight: float) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = base
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return font
