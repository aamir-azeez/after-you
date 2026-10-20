extends RefCounted
## What's new: the card with this version's highlights, and the marks on the Home
## button (a dot and a small tip) while those highlights are unseen. The Home
## button and the Settings row open the same card.
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const ICON_DIR := "res://assets/ui/whats_new/"
# One step lighter than the shared pop-up's panel, so the tiles read on it.
const TILE := Color("2a5a50")
const ICON_TINT := Color("9ed8c2")
const GIFT_TILE := Color("33695e")
const GIFT_TINT := Color("f0c9a6")
const TEXT := Color("dfe6dc")
const DOT := Color("f0b38a")
const DOT_RING := Color("163c36")
const CREAM := Color("eceddb")
const INK := Color("14352f")

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

## Opens the card for one version's entry. `see_all` is empty where the full notes
## are not linked (iOS); then "Got it" is the only button.
static func open(parent: Control, entry: Dictionary, see_all: Callable, opener: Control = null) -> Control:
	var modal := InGameModal.open(parent, "WhatsNewCard", PlayerCopy.WHATS_NEW, PlayerCopy.WHATS_NEW_VERSION % entry.version, opener) as InGameModal
	modal.widen(620.0)
	var header := modal.content.get_child(0) as HBoxContainer
	header.add_theme_constant_override("separation", 14)
	var gift := tile("gift", 48.0, GIFT_TILE, GIFT_TINT)
	header.add_child(gift)
	header.move_child(gift, 0)
	var titles := header.get_child(1) as Control
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(titles.get_child(0) as Label).add_theme_font_size_override("font_size", 32)
	_gap(modal.content, 12.0)
	var list := VBoxContainer.new()
	list.name = "WhatsNewHighlights"
	# A long list (a big release) sits a little tighter so it still fits a 720 high screen.
	list.add_theme_constant_override("separation", 16 if entry.highlights.size() <= 4 else 10)
	modal.content.add_child(list)
	for item: Dictionary in entry.highlights:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		list.add_child(row)
		row.add_child(tile(str(item.icon), 40.0, TILE, ICON_TINT))
		var line := modal.label(str(item.text), 21, row)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_theme_color_override("font_color", TEXT)
	_gap(modal.content, 14.0)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	modal.content.add_child(footer)
	if see_all.is_valid():
		var all := _action(footer, "WhatsNewSeeAll", PlayerCopy.WHATS_NEW_SEE_ALL, see_all)
		ControlTheme.secondary(all)
	_action(footer, "WhatsNewGotIt", PlayerCopy.WHATS_NEW_GOT_IT, func() -> void: modal.close())
	modal._trap_focus()
	return modal

## Where the tip goes: under the button (centred), above it (from its left edge,
## for a button at the bottom of the screen), or beside it (to its right).
const BELOW := "below"
const ABOVE := "above"
const BESIDE := "beside"

## The dot on the Home button's corner and the tip under it, until the card opens.
## Placed ABOVE or BESIDE, the dot sits on the button's icon instead and the tip
## is a size smaller; place_tip() moves the tip later.
static func mark_unseen(button: Control, version: String, placement: String = BELOW) -> void:
	if button.get_node_or_null("WhatsNewDot") != null: return
	var dot := Panel.new()
	dot.name = "WhatsNewDot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := ControlTheme.rounded(DOT, 8, DOT_RING)
	ring.set_border_width_all(2)
	dot.add_theme_stylebox_override("panel", ring)
	dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dot.offset_left = -8.0
	dot.offset_right = 6.0
	dot.offset_top = -6.0
	dot.offset_bottom = 8.0
	if placement != BELOW and button is Button and (button as Button).icon != null:
		# A badge on the icon's top-right corner.
		var inset := (button as Button).get_theme_stylebox("normal").content_margin_left
		var icon_size := float((button as Button).get_theme_constant("icon_max_width"))
		dot.anchor_left = 0.0
		dot.anchor_right = 0.0
		dot.anchor_top = 0.5
		dot.anchor_bottom = 0.5
		dot.offset_left = inset + icon_size - 9.0
		dot.offset_right = dot.offset_left + 14.0
		dot.offset_top = -icon_size * 0.5 - 5.0
		dot.offset_bottom = dot.offset_top + 14.0
	button.add_child(dot)
	# A small diamond, half covered by the tip, points at the button.
	var pointer := Panel.new()
	pointer.name = "WhatsNewPointer"
	pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointer.add_theme_stylebox_override("panel", ControlTheme.rounded(CREAM, 2))
	pointer.pivot_offset = Vector2(6, 6)
	pointer.rotation_degrees = 45.0
	button.add_child(pointer)
	var tip := PanelContainer.new()
	tip.name = "WhatsNewTip"
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var compact := placement != BELOW
	tip.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(CREAM, 12), 10.0 if compact else 14.0, 7.0 if compact else 8.0))
	button.add_child(tip)
	var words := Label.new()
	words.text = PlayerCopy.WHATS_NEW_TIP % version
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bold := FontVariation.new()
	bold.base_font = preload("res://assets/fonts/nunito.ttf")
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 750.0}
	words.add_theme_font_override("font", bold)
	words.add_theme_font_size_override("font_size", 15 if compact else 16)
	words.add_theme_color_override("font_color", INK)
	tip.add_child(words)
	place_tip(button, placement)

## Moves the tip and its pointer to `placement` (BELOW, ABOVE or BESIDE).
static func place_tip(button: Control, placement: String) -> void:
	var pointer := button.get_node_or_null("WhatsNewPointer") as Control
	var tip := button.get_node_or_null("WhatsNewTip") as Control
	if pointer == null or tip == null: return
	tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tip.grow_vertical = Control.GROW_DIRECTION_END
	match placement:
		ABOVE:
			# Points down at the button's icon; the tip grows up and to the right.
			_anchor(pointer, 0.0, 0.0, Rect2(18.0, -16.0, 12.0, 12.0))
			_anchor(tip, 0.0, 0.0, Rect2(0.0, -10.0, 0.0, 0.0))
			tip.grow_horizontal = Control.GROW_DIRECTION_END
			tip.grow_vertical = Control.GROW_DIRECTION_BEGIN
		BESIDE:
			# Points left at the button, level with it; the tip grows to the right.
			_anchor(pointer, 1.0, 0.5, Rect2(0.0, -6.0, 12.0, 12.0))
			_anchor(tip, 1.0, 0.5, Rect2(6.0, 0.0, 0.0, 0.0))
			tip.grow_horizontal = Control.GROW_DIRECTION_END
			tip.grow_vertical = Control.GROW_DIRECTION_BOTH
		_:
			# Centred under the button, 10 below its bottom edge.
			_anchor(pointer, 0.5, 1.0, Rect2(-6.0, 4.0, 12.0, 12.0))
			_anchor(tip, 0.5, 1.0, Rect2(0.0, 10.0, 0.0, 0.0))

static func _anchor(control: Control, x: float, y: float, offsets: Rect2) -> void:
	control.anchor_left = x
	control.anchor_right = x
	control.anchor_top = y
	control.anchor_bottom = y
	control.offset_left = offsets.position.x
	control.offset_top = offsets.position.y
	control.offset_right = offsets.end.x
	control.offset_bottom = offsets.end.y

## Clears the dot and the tip once the card has been opened.
static func clear_unseen(button: Control) -> void:
	if not is_instance_valid(button): return
	for name: String in ["WhatsNewDot", "WhatsNewPointer", "WhatsNewTip"]:
		var mark := button.get_node_or_null(name)
		if mark != null: mark.queue_free()

static func _action(parent: Container, node_name: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 54
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

static func _gap(parent: Container, height: float) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(gap)
