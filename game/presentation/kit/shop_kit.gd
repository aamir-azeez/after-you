extends RefCounted
## The shared pieces of the Pollen pages (the Wardrobe, board 5b, and the
## Pollen store, board 2): their type, any amount of Pollen with its grain, and
## the "about $X" line beside a price. Every Pollen amount on those pages is
## built here, so the grain always comes from kit/pollen_mark.gd sized from its
## amount's font, and the about figure always comes from services/pollen_money.gd.
##
## Fonts are made once and shared. Every piece takes no input unless it is a button.
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const FREDOKA = preload("res://assets/fonts/fredoka.ttf")
const NUNITO = preload("res://assets/fonts/nunito.ttf")

const CREAM := UiTokens.CREAM
const MUTED := Color("afc6be")
const INK := Color("1d3230")
const INK_SOFT := Color("4d625d")

static var _fonts := {}

static func _font(base: Font, weight: float) -> FontVariation:
	var key := "%s|%d" % [base.resource_path, int(weight)]
	if not _fonts.has(key):
		var font := FontVariation.new()
		font.base_font = base
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[key] = font
	return _fonts[key]

## Titles and big numbers.
static func heading_font() -> Font:
	return _font(FREDOKA, 600.0)

## Names and amounts.
static func bold_font() -> Font:
	return _font(NUNITO, 800.0)

## Everything else.
static func body_font() -> Font:
	return _font(NUNITO, 600.0)

## A page's theme: the body font, cream labels and the game's buttons.
static func page_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = body_font()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", CREAM)
	ThemeRules.install_buttons(theme)
	return theme

## A label that takes no input.
static func text(value: String, font_size: int, color: Color, font: Font = null) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", font if font != null else body_font())
	return label

## An amount of Pollen: the grain, then the grouped number ("24,000"), with an
## optional `before` ("−") and `after` (" more") around the number.
static func amount(value: int, font_size: int, color: Color, before: String = "", after: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "PollenAmount"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", maxi(4, int(font_size / 4.0)))
	if not before.is_empty(): row.add_child(text(before, font_size, color, bold_font()))
	row.add_child(PollenMark.beside(font_size))
	var number := text(PollenMoney.grouped(value) + after, font_size, color, bold_font())
	number.name = "PollenAmountValue"
	row.add_child(number)
	return row

## "about $3.96" for an amount of Pollen.
static func about(value: int, font_size: int, color: Color) -> Label:
	var label := text(PlayerCopy.WARDROBE_ABOUT % PollenMoney.about(value), font_size, color)
	label.name = "PollenAbout"
	return label

## A price as an item card shows it: the amount over its about line.
static func price(value: int, font_size: int, color: Color, soft: Color) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "PollenPrice"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	column.add_child(amount(value, font_size, color))
	column.add_child(about(value, font_size - 3, soft))
	return column

## A label-free button with `content` laid inside it, for a button whose words
## sit beside a grain ("Buy for [grain] 20,000 about $3.96"). The content takes
## no input, so the whole button is the target.
static func content_button(content: Control, height: float = 54.0) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, height)
	var holder := CenterContainer.new()
	holder.name = "ButtonContent"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(holder)
	_ignore(content)
	holder.add_child(content)
	return button

## Swaps the content of a content_button().
static func set_button_content(button: Button, content: Control) -> void:
	var holder := button.get_node_or_null("ButtonContent")
	if holder == null: return
	for child: Node in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	_ignore(content)
	holder.add_child(content)
	button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, content.get_combined_minimum_size().x + 36.0)

static func _ignore(node: Node) -> void:
	if node is Control: (node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children(): _ignore(child)
