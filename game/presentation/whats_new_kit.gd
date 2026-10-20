extends RefCounted
## What's new's shared look: icon tiles, highlight rows and their colours, used by
## the card (whats_new_card.gd) and its Earlier versions list (whats_new_history.gd).
const ControlTheme = preload("res://presentation/control_theme.gd")

const ICON_DIR := "res://assets/ui/whats_new/"
# One step lighter than the shared pop-up's panel, so the tiles read on it.
const TILE := Color("2a5a50")
const ICON_TINT := Color("9ed8c2")
const GIFT_TILE := Color("33695e")
const GIFT_TINT := Color("f0c9a6")
const TEXT := Color("dfe6dc")
const CREAM := Color("eceddb")

static func icon(name: String) -> Texture2D:
	return load(ICON_DIR + name + ".svg")

## A rounded square holding one icon, as on the card and its highlight rows.
static func tile(name: String, size: float, background: Color, tint: Color) -> PanelContainer:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := roundf(size * 0.2)
	holder.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(background, 12), inset, inset))
	var picture := TextureRect.new()
	picture.texture = icon(name)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.self_modulate = tint
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(picture)
	return holder

## Highlight rows, an icon tile and its line each: the card's list, and a version's
## list under its row in Earlier versions.
static func highlight_list(highlights: Array) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.name = "WhatsNewHighlights"
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A long list (a big release) sits a little tighter so it still fits a 720 high screen.
	list.add_theme_constant_override("separation", 16 if highlights.size() <= 4 else 10)
	for item: Dictionary in highlights:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 16)
		list.add_child(row)
		row.add_child(tile(str(item.icon), 40.0, TILE, ICON_TINT))
		var line := Label.new()
		line.text = str(item.text)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 21)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_theme_color_override("font_color", TEXT)
		row.add_child(line)
	return list
