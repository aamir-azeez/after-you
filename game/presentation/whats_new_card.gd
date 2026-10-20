extends RefCounted
## What's new: the card with this version's highlights, its Earlier versions list,
## and the marks on the Home button (a dot and a small tip) while those highlights
## are unseen. The Home button and the Settings row open the same card through
## Main._open_whats_new_card.
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
## The Earlier versions list, loaded only when a player opens it.
const HISTORY := "res://presentation/whats_new_history.gd"
const EARLIER_LIST := "WhatsNewEarlierList"
const BACK_ICON = preload("res://assets/ui/social/arrow-left.svg")
## The shared pop-up's vertical padding, and the room kept above and below it.
const PANEL_PADDING := 22.0
const EDGE_MARGIN := 24.0

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

## Opens the card for one version's entry. `earlier` returns the versions before
## it (Changelog.earlier_entries); when it is empty the card has no Earlier
## versions. `see_all` is empty where the full notes are not linked (iOS). Every
## build's card has the same footer, Earlier versions and Got it; See all changes
## ends the Earlier versions list. Back from that list returns to the card.
static func open(parent: Control, entry: Dictionary, earlier: Callable, see_all: Callable, opener: Control = null) -> Control:
	var modal := InGameModal.open(parent, "WhatsNewCard", PlayerCopy.WHATS_NEW, PlayerCopy.WHATS_NEW_VERSION % entry.version, opener) as InGameModal
	modal.widen(620.0)
	var header := modal.content.get_child(0) as HBoxContainer
	header.add_theme_constant_override("separation", 14)
	var gift := tile("gift", 48.0, GIFT_TILE, GIFT_TINT)
	gift.name = "WhatsNewGift"
	header.add_child(gift)
	header.move_child(gift, 0)
	var titles := header.get_child(1) as Control
	titles.name = "WhatsNewTitles"
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(titles.get_child(0) as Label).add_theme_font_size_override("font_size", 32)
	var body := VBoxContainer.new()
	body.name = "WhatsNewCardBody"
	body.add_theme_constant_override("separation", modal.content.get_theme_constant("separation"))
	modal.content.add_child(body)
	_gap(body, 12.0)
	body.add_child(highlight_list(entry.highlights))
	_gap(body, 14.0)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	body.add_child(footer)
	if earlier.is_valid():
		ControlTheme.secondary(_action(footer, "WhatsNewEarlier", PlayerCopy.WHATS_NEW_EARLIER, func() -> void: show_earlier(modal, earlier, see_all)))
	elif see_all.is_valid():
		ControlTheme.secondary(_action(footer, "WhatsNewSeeAll", PlayerCopy.WHATS_NEW_SEE_ALL, see_all))
	_action(footer, "WhatsNewGotIt", PlayerCopy.WHATS_NEW_GOT_IT, func() -> void: modal.close())
	modal.back_step = func() -> bool: return show_card(modal)
	modal._trap_focus()
	return modal

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

## Turns the card into the Earlier versions list. The list is built the first time
## and kept, so going back and forth costs nothing and never stacks.
static func show_earlier(modal: InGameModal, earlier: Callable, see_all: Callable) -> void:
	if not is_instance_valid(modal) or modal.is_queued_for_deletion(): return
	var header := modal.content.get_child(0) as HBoxContainer
	if modal.content.get_node_or_null(EARLIER_LIST) == null:
		var entries: Variant = earlier.call()
		var view: Control = load(HISTORY).new(entries if entries is Array else [], see_all)
		view.name = EARLIER_LIST
		modal.content.add_child(view)
		var back := Button.new()
		back.name = "WhatsNewBack"
		back.icon = BACK_ICON
		back.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		back.expand_icon = true
		back.add_theme_constant_override("icon_max_width", 22)
		back.accessibility_name = PlayerCopy.WHATS_NEW_BACK
		back.tooltip_text = PlayerCopy.WHATS_NEW_BACK
		back.custom_minimum_size = Vector2(48, 48)
		back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var chip := ControlTheme.rounded(TILE if state == "normal" else GIFT_TILE, 12)
			if state == "focus": chip = ControlTheme.rounded(Color.TRANSPARENT, 12, CREAM)
			back.add_theme_stylebox_override(state, chip)
			back.add_theme_color_override("icon_" + state + "_color", CREAM)
		back.pressed.connect(func() -> void: show_card(modal))
		header.add_child(back)
		header.move_child(back, 0)
		modal.resized.connect(func() -> void: _fit_earlier(modal))
	var keyboard := _keyboard_focus(modal)
	_switch(modal, true)
	_fit_earlier(modal)
	if keyboard: (header.get_node("WhatsNewBack") as Control).grab_focus()

## Back to the card from Earlier versions. False when the card already shows.
static func show_card(modal: InGameModal) -> bool:
	if not is_instance_valid(modal) or modal.is_queued_for_deletion(): return false
	var view := modal.content.get_node_or_null(EARLIER_LIST) as Control
	if view == null or not view.visible: return false
	var keyboard := _keyboard_focus(modal)
	_switch(modal, false)
	if keyboard: (modal.content.find_child("WhatsNewEarlier", true, false) as Control).grab_focus()
	return true

## Shows the list (with the back arrow and its title) or the card (with the gift,
## its title and version line).
static func _switch(modal: InGameModal, list: bool) -> void:
	var header := modal.content.get_child(0) as HBoxContainer
	header.get_node("WhatsNewGift").visible = not list
	header.get_node("WhatsNewBack").visible = list
	var titles := header.get_node("WhatsNewTitles") as Control
	(titles.get_child(0) as Label).text = PlayerCopy.WHATS_NEW_EARLIER_TITLE if list else PlayerCopy.WHATS_NEW
	if titles.get_child_count() > 1: (titles.get_child(1) as Control).visible = not list
	modal.content.get_node("WhatsNewCardBody").visible = not list
	modal.content.get_node(EARLIER_LIST).visible = list
	modal._trap_focus()

## Whether a keyboard or pad was moving focus inside the card; a tap leaves none.
static func _keyboard_focus(modal: Control) -> bool:
	var focused := modal.get_viewport().gui_get_focus_owner()
	return focused != null and modal.is_ancestor_of(focused)

## The list scrolls inside the panel, which stays inside the screen: the card's
## height less the panel's padding, its header and a margin above and below.
static func _fit_earlier(modal: InGameModal) -> void:
	if not is_instance_valid(modal): return
	var view := modal.content.get_node_or_null(EARLIER_LIST)
	if view == null: return
	var header := modal.content.get_child(0) as Control
	var chrome := EDGE_MARGIN * 2.0 + PANEL_PADDING * 2.0 + header.get_combined_minimum_size().y + float(modal.content.get_theme_constant("separation"))
	view.fit(modal.size.y - chrome)

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
