extends RefCounted
## The frame the two card money pages share (the Pollen page, Pollen board 7b,
## and the Fruits page, Fruits board 6a): the night shade to every screen edge,
## the page margin, a header with the coral back square, the title and its line
## and the chip's slot, then a row for the cards. Each card's list scrolls on
## its own in a column that fills the card, with room kept for the scroll bar
## while it shows. Also the chip swap (a chip already in place stays, so a
## redraw never replaces one under a finger), clearing columns for a redraw,
## and the status line with Try again a page shows before its data is in.
## Pure building: the page keeps what it gets back; nothing here keeps state.
const SafeArea = preload("res://presentation/safe_area.gd")
const PageMargin = preload("res://presentation/kit/page_margin.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const BACK_ICON = preload("res://assets/ui/social/arrow-left.svg")

## The cream card both pages draw their cream cards on.
const CARD := Color("f3efdf")
## Room kept for a list's scroll bar while it shows, so a long list's amounts stay clear of it.
const GUTTER := 12
const SHADE := Color(0.025, 0.10, 0.10, 0.94)

## Builds the frame into `page`: {back (the back square, named `back_name`,
## its `back_words` for screen readers, `back` on a tap), chip_slot, body (the
## cards' row), title (the title label, named `title_name`)}.
static func build(page: Control, parts: Dictionary, title_font: Font, back: Callable) -> Dictionary:
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = SHADE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.bleed(shade)
	page.add_child(shade)
	var margin := PageMargin.new(22, 22)
	page.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	margin.add_child(outer)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	outer.add_child(header)
	var back_button := Button.new()
	back_button.name = str(parts.back_name)
	back_button.custom_minimum_size = Vector2(56, 56)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_button.tooltip_text = str(parts.back_words)
	back_button.accessibility_name = str(parts.back_words)
	back_button.expand_icon = true
	ControlTheme.danger(back_button, BACK_ICON)
	back_button.pressed.connect(func() -> void: back.call())
	header.add_child(back_button)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	var title := ShopKit.text(str(parts.title), 34, UiTokens.CREAM)
	title.name = str(parts.title_name)
	if title_font != null: title.add_theme_font_override("font", title_font)
	titles.add_child(title)
	titles.add_child(ShopKit.text(str(parts.subtitle), 17, UiTokens.MUTED))
	var chip_slot := HBoxContainer.new()
	chip_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(chip_slot)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	return {"back": back_button, "chip_slot": chip_slot, "body": body, "title": title}

## A cream card named `card_name` in `body`, its padded panel.
static func cream_card(body: Control, card_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = card_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(CARD, 18), 22.0, 18.0))
	body.add_child(panel)
	return panel

## A scrolling column inside `parent` that fills its height (so the room under a
## short list is the card's own), with room for the scroll bar while it shows.
static func scrolling(parent: Control, separation: int = 10) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)
	var bar := scroll.get_v_scroll_bar()
	bar.visibility_changed.connect(func() -> void: inset.add_theme_constant_override("margin_right", GUTTER if bar.visible else 0))
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", separation)
	inset.add_child(column)
	return column

## Puts `chip` (a Control, or null for none) in `slot`; a chip already there stays.
static func show_chip(slot: Container, chip: Variant) -> void:
	for child: Node in slot.get_children():
		if child == chip: continue
		slot.remove_child(child)
		child.queue_free()
	if chip is Control and (chip as Control).get_parent() != slot: slot.add_child(chip)

## Empties each of `columns` for a redraw.
static func clear(columns: Array) -> void:
	for column: Node in columns:
		for child: Node in column.get_children():
			column.remove_child(child)
			child.queue_free()

## The line a page shows before its data is in (`line`, named `prefix` +
## "Status"), and Try again under it (named `prefix` + "Retry") when `retry` is valid.
static func status(column: Container, line: String, color: Color, prefix: String, retry_words: String, retry: Callable) -> void:
	var said := ShopKit.text(line, 17, color)
	said.name = prefix + "Status"
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(said)
	if not retry.is_valid(): return
	var again := Button.new()
	again.name = prefix + "Retry"
	again.text = retry_words
	again.custom_minimum_size = Vector2(0, 50)
	again.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	again.pressed.connect(func() -> void: retry.call())
	column.add_child(again)
