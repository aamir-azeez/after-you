extends RefCounted
## One cream panel on the Full Journey card (pollen-concepts board 3): an icon
## on the left, then a title, an explainer and, for the monthly Pollen, the
## ladder line in bold. presentation/full_journey_benefits.gd says what each
## panel holds; this only draws it. Panels take no input, so a drag that starts
## on one still scrolls the card.
const FullJourneyArt = preload("res://presentation/full_journey_art.gd")
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

## A panel for `spec` ({name, icon, title, body, ladder}).
static func make(spec: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = str(spec.get("name", "FullJourneyPanel"))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_kind := str(spec.get("icon", "room"))
	var style := ControlTheme.rounded(FILL.get(icon_kind, FILL.room), 16)
	ControlTheme.padded(style, 14.0, 10.0)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	row.add_child(_icon(icon_kind))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	var title := _text(str(spec.get("title", "")), TITLE_SIZE, UiTokens.INK, _font(FREDOKA, 600.0))
	title.name = "PanelTitle"
	column.add_child(title)
	var body := _text(str(spec.get("body", "")), BODY_SIZE, BODY, null)
	body.name = "PanelBody"
	column.add_child(body)
	var ladder := str(spec.get("ladder", ""))
	if not ladder.is_empty():
		var line := _text(ladder, BODY_SIZE, UiTokens.INK, _font(NUNITO, 800.0))
		line.name = "PanelLadder"
		column.add_child(line)
	return panel

static func _icon(kind: String) -> Control:
	if kind == "pollen": return FullJourneyArt.grain(ICON)
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
