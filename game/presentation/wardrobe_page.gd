extends Control
## The Wardrobe page as Pollen board 5b draws it ("Wardrobe, always open"):
## - the header: the coral back square, "Wardrobe" over its note, and the
##   balance chip with the grain (kit/pollen_chip.gd), whose + opens the Pollen
##   store only while bundles sell;
## - on the left, the big pip wearing what is picked, with the "Your pip" /
##   "As your friend sees you" switch (the friend's room shows your pip in mint),
##   "Drag to turn your pip." and one main button: Buy for [grain] N about $X,
##   Wear, or Take off;
## - on the right, the All items and Owned tabs with "Every item stays in the
##   shop", the "Featured this week" shelf in its own tinted panel, the slot
##   chips (Hat, Body, Leaf: only slots that have something to show), and the
##   item cards in their tier frames (kit/tier_frame.gd) with the tier mark and
##   word, and the price with its grain and about line, or Yours and Wearing.
##   An earned item has the Earned frame and a "Not for sale" lock chip.
## Every item stays in the shop: nothing here counts down, runs out or leaves.
##
## Without the shop (a build that sells nothing, as iOS, or a server with
## POLLEN_SHOP off) the same frame shows only the Owned tab and what the player
## owns: no price, no Buy, no shelf, no + and no sale wording.
##
## A view only. presentation/wardrobe_flow.gd builds the model and answers the
## signals; render(model) redraws from it. The model:
##   balance (int, -1 while unknown), status, retry, shop (bool), bundles (bool:
##   the chip's +), tab ("all" or "owned"), kind (the slot chip picked), kinds
##   (slots that have something in this tab), selected (id or ""), view ("you"
##   or "friend"), preview (the look the big pip wears), featured (ids), and
##   items: Array of {id, name, tier, slot, price, owned, worn, locked,
##   unlock_name, sold}, in shop order.
## Cards draw still pips (kit/pip_avatar.gd still mode), so a long list shares
## the one offscreen renderer; only the big pip is live, and it is made again
## only when the switch changes its colour.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const TierFrame = preload("res://presentation/kit/tier_frame.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const Outfit = preload("res://services/outfit.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const BACK_ICON = preload("res://assets/ui/social/arrow-left.svg")

const CREAM := ShopKit.CREAM
const MUTED := ShopKit.MUTED
const INK := ShopKit.INK
const INK_SOFT := ShopKit.INK_SOFT
const PANEL := Color("173f39")
const SHOP := Color("f3efdf")
const SHELF := Color("e4eee0")
const PICTURE := Color("efe8d4")
const CHIP := Color("e6e0cc")
const MINT := Color("a6d9c4")
const CARD_SIZE := Vector2(206, 158)
const SHELF_CARD_SIZE := Vector2(150, 150)
const CARD_PIP := Vector2(56, 70)
const SHELF_PIP := Vector2(50, 62)
const BIG_PIP := Vector2(230, 270)

signal back_pressed
signal tab_chosen(tab: String)
signal kind_chosen(kind: String)
signal view_chosen(view: String)
signal item_chosen(id: String)
signal action_pressed(id: String)
signal retry_pressed
signal plus_pressed

var back_button: Button
var action_button: Button
var preview: Control
## The balance chip (kit/pollen_chip.gd), made again only when what it shows changes.
var chip: Button
var _chip_box: HBoxContainer
var _chip_shown := []
var _status: Label
var _retry: Button
var _name: Label
var _hint: Label
var _note: Label
var _tabs := {}
var _tab_row: HBoxContainer
var _stays: Label
var _views := {}
var _kinds: HBoxContainer
var _shelf: PanelContainer
var _featured: HBoxContainer
var _grid: HFlowContainer
var _pip_box: CenterContainer
var _reduced := false
var _view := "you"
var _model: Dictionary = {}
## What the cards were last built from; a redraw that changes only the pick restyles them instead.
var _cards_key := ""

func _init(reduced: bool = false) -> void:
	_reduced = reduced
	name = "WardrobePage"
	theme = ShopKit.page_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.12, 0.12, 0.97)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.bleed(shade)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 28)
	for side: String in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	margin.add_child(outer)
	outer.add_child(_header())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	body.add_child(_pip_panel())
	body.add_child(_shop_panel())

func _header() -> Control:
	var header := HBoxContainer.new()
	header.name = "WardrobeHeader"
	header.add_theme_constant_override("separation", 18)
	back_button = Button.new()
	back_button.name = "WardrobeBack"
	back_button.custom_minimum_size = Vector2(56, 56)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_button.tooltip_text = PlayerCopy.WARDROBE_BACK
	back_button.accessibility_name = PlayerCopy.WARDROBE_BACK
	back_button.expand_icon = true
	ThemeRules.danger(back_button, BACK_ICON)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	header.add_child(back_button)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	titles.add_child(ShopKit.text(PlayerCopy.WARDROBE_TITLE, 40, CREAM, ShopKit.heading_font()))
	titles.add_child(ShopKit.text(PlayerCopy.WARDROBE_NOTE, 16, MUTED))
	header.add_child(titles)
	_chip_box = HBoxContainer.new()
	_chip_box.name = "WardrobeBalance"
	_chip_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_chip_box)
	return header

func _pip_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "WardrobePipPanel"
	panel.custom_minimum_size.x = 340
	panel.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(PANEL, 22, Color("21504a")), 18, 16))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	column.add_child(_view_switch())
	_pip_box = CenterContainer.new()
	_pip_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_pip_box)
	_make_preview(SpiritLook.PEACH)
	_name = ShopKit.text("", 26, CREAM, ShopKit.heading_font())
	_name.name = "WardrobeItemName"
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_name)
	_hint = ShopKit.text(PlayerCopy.WARDROBE_DRAG, 14, MUTED)
	_hint.name = "WardrobeDragHint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)
	_note = ShopKit.text("", 15, MUTED)
	_note.name = "WardrobeItemNote"
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 280
	column.add_child(_note)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	column.add_child(gap)
	action_button = ShopKit.content_button(Control.new(), 58)
	action_button.name = "WardrobeAction"
	action_button.pressed.connect(func() -> void: if not str(_model.get("selected", "")).is_empty(): action_pressed.emit(str(_model.selected)))
	column.add_child(action_button)
	return panel

## "Your pip" / "As your friend sees you": a small two-part switch.
func _view_switch() -> Control:
	var holder := PanelContainer.new()
	holder.name = "WardrobeViewSwitch"
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(Color("0f302c"), 14, Color("2c5a52")), 4, 4))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	holder.add_child(row)
	for view: Array in [["you", PlayerCopy.WARDROBE_YOUR_PIP], ["friend", PlayerCopy.WARDROBE_FRIEND_VIEW]]:
		var button := Button.new()
		button.name = "WardrobeView_" + view[0]
		button.text = view[1]
		button.custom_minimum_size = Vector2(0, 40)
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(func() -> void: view_chosen.emit(view[0]))
		row.add_child(button)
		_views[view[0]] = button
	return holder

func _make_preview(color: Color) -> void:
	if is_instance_valid(preview):
		_pip_box.remove_child(preview)
		preview.queue_free()
	preview = PipAvatar.new(_reduced, color, BIG_PIP)
	preview.name = "WardrobePip"
	_pip_box.add_child(preview)

func _shop_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "WardrobeShopPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(SHOP, 22), 18, 14))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	_tab_row = HBoxContainer.new()
	_tab_row.name = "WardrobeTabs"
	_tab_row.add_theme_constant_override("separation", 6)
	_tab_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_tab_row)
	for tab: Array in [["all", PlayerCopy.WARDROBE_ALL], ["owned", PlayerCopy.WARDROBE_OWNED]]:
		var button := Button.new()
		button.name = "WardrobeTab_" + tab[0]
		button.text = tab[1]
		button.custom_minimum_size = Vector2(0, 44)
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(func() -> void: tab_chosen.emit(tab[0]))
		_tab_row.add_child(button)
		_tabs[tab[0]] = button
	_stays = ShopKit.text(PlayerCopy.WARDROBE_STAYS, 14, INK_SOFT)
	_stays.name = "WardrobeStays"
	_stays.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_stays)
	_status = ShopKit.text("", 18, INK)
	_status.name = "WardrobeStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_retry = Button.new()
	_retry.name = "WardrobeRetry"
	_retry.text = PlayerCopy.WARDROBE_TRY_AGAIN
	_retry.custom_minimum_size = Vector2(0, 48)
	_retry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_retry.pressed.connect(func() -> void: retry_pressed.emit())
	column.add_child(_retry)
	var scroll := ScrollContainer.new()
	scroll.name = "WardrobeScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ThemeRules.touch_scroll(scroll)
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	list.add_child(_shelf_panel())
	_kinds = HBoxContainer.new()
	_kinds.name = "WardrobeKinds"
	_kinds.add_theme_constant_override("separation", 8)
	list.add_child(_kinds)
	_grid = HFlowContainer.new()
	_grid.name = "WardrobeItems"
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	list.add_child(_grid)
	return panel

## "Featured this week" in its own tinted panel: the title, then the six cards.
func _shelf_panel() -> Control:
	_shelf = PanelContainer.new()
	_shelf.name = "WardrobeShelf"
	_shelf.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(SHELF, 16, Color("d3e2d0")), 12, 10))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_shelf.add_child(column)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 8)
	var spark := Sparkle.new()
	spark.custom_minimum_size = Vector2(16, 16)
	spark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_child(spark)
	title.add_child(ShopKit.text(PlayerCopy.WARDROBE_FEATURED, 17, INK, ShopKit.bold_font()))
	column.add_child(title)
	_featured = HBoxContainer.new()
	_featured.name = "WardrobeFeatured"
	_featured.add_theme_constant_override("separation", 10)
	column.add_child(_featured)
	return _shelf

## Redraws the page from the flow's model.
func render(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_show_chip(int(model.get("balance", -1)), bool(model.get("balance_known", int(model.get("balance", -1)) >= 0)), bool(model.get("bundles", false)))
	var status := str(model.get("status", ""))
	_status.text = status
	_status.visible = not status.is_empty()
	_retry.visible = bool(model.get("retry", false))
	var shop := bool(model.get("shop", PollenSurfaces.shared().shop_visible()))
	var tab := str(model.get("tab", "all"))
	_tabs.all.visible = shop
	_stays.visible = shop
	for key: String in _tabs:
		if key == tab: _pill(_tabs[key], true)
		else: _pill(_tabs[key], false)
	var view := str(model.get("view", "you"))
	if view != _view:
		_view = view
		_make_preview(SpiritLook.MINT if view == "friend" else SpiritLook.PEACH)
	for key: String in _views: _switch_style(_views[key], key == view)
	var by_id := {}
	for entry: Dictionary in model.get("items", []): by_id[entry.id] = entry
	var featured: Array = (model.get("featured", []) as Array).filter(func(id: String) -> bool: return by_id.has(id)).map(func(id: String) -> Dictionary: return by_id[id])
	var kind := str(model.get("kind", ""))
	var shown: Array = (model.get("items", []) as Array).filter(func(entry: Dictionary) -> bool: return (tab == "all" or bool(entry.owned)) and (kind.is_empty() or entry.slot == kind))
	var key := var_to_str([featured, shown, model.get("kinds", []), kind, shop])
	if key != _cards_key:
		_cards_key = key
		_fill(_featured, featured, true)
		_fill_kinds(model.get("kinds", []), kind)
		_fill(_grid, shown, false)
	else:
		_restyle(_featured)
		_restyle(_grid)
	_shelf.visible = shop and tab == "all" and not featured.is_empty()
	if tab == "owned" and shown.is_empty() and status.is_empty():
		_status.text = PlayerCopy.WARDROBE_NOTHING_OWNED if shop else PlayerCopy.WARDROBE_NOTHING_EARNED
		_status.visible = true
	_show_selected(by_id.get(str(model.get("selected", "")), {}), shop)
	if preview.has_method("wear"): preview.wear(model.get("preview", {}))

## The chip for `balance`, with its plus while bundles sell; none until the server has said.
func _show_chip(balance: int, known: bool, plus: bool) -> void:
	var wanted := [balance, known, plus]
	if wanted == _chip_shown: return
	_chip_shown = wanted
	if is_instance_valid(chip):
		_chip_box.remove_child(chip)
		chip.queue_free()
	chip = null
	if not known: return
	chip = PollenChip.make(balance, plus)
	chip.pressed.connect(func() -> void: if plus: plus_pressed.emit())
	_chip_box.add_child(chip)

func _show_selected(entry: Dictionary, shop: bool) -> void:
	action_button.visible = not entry.is_empty()
	_name.text = str(entry.get("name", ""))
	_hint.visible = true
	_note.text = ""
	_note.visible = false
	if entry.is_empty(): return
	action_button.disabled = false
	var label := ""
	if bool(entry.owned):
		label = PlayerCopy.WARDROBE_TAKE_OFF if bool(entry.worn) else PlayerCopy.WARDROBE_WEAR
	elif not bool(entry.sold) or not shop:
		action_button.visible = false
		if entry.tier == "earned" and shop: _set_note(PlayerCopy.WARDROBE_EARNED)
	elif bool(entry.locked):
		action_button.disabled = true
		_set_note(PlayerCopy.WARDROBE_LOCKED % str(entry.unlock_name))
	action_button.text = ""
	action_button.tooltip_text = ""
	if not label.is_empty():
		ShopKit.set_button_content(action_button, ShopKit.text(label, 22, INK, ShopKit.bold_font()))
		action_button.accessibility_name = label
		_cream(action_button)
		return
	if not action_button.visible: return
	# Buy for [grain] 20,000 about $3.96, all inside the one button.
	var price := int(entry.price)
	var row := HBoxContainer.new()
	row.name = "WardrobeBuyContent"
	row.add_theme_constant_override("separation", 10)
	row.add_child(ShopKit.text(PlayerCopy.WARDROBE_BUY_FOR, 22, INK, ShopKit.bold_font()))
	row.add_child(ShopKit.amount(price, 22, INK))
	var about := ShopKit.about(price, 15, INK_SOFT)
	about.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(about)
	ShopKit.set_button_content(action_button, row)
	action_button.accessibility_name = PlayerCopy.WARDROBE_BUY % str(price)
	_cream(action_button)

func _set_note(text: String) -> void:
	_note.text = text
	_note.visible = true

func _fill(box: Container, entries: Array, small: bool) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var shop := bool(_model.get("shop", false))
	for entry: Dictionary in entries: box.add_child(_card(entry, small, shop))

## Marks the picked card in `box` without making the cards again.
func _restyle(box: Container) -> void:
	var picked := str(_model.get("selected", ""))
	for card: Node in box.get_children():
		if not card is Button: continue
		var id := str(card.get_meta("item_id", ""))
		var tier := str(card.get_meta("tier", "common"))
		var on := id == picked
		(card as Button).set_pressed_no_signal(on)
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			card.add_theme_stylebox_override(state, TierFrame.style(tier, 16, on or state in ["pressed", "hover_pressed"]))

func _fill_kinds(kinds: Array, picked: String) -> void:
	for child: Node in _kinds.get_children():
		_kinds.remove_child(child)
		child.queue_free()
	_kinds.visible = kinds.size() > 1
	for kind: Variant in kinds:
		var button := Button.new()
		button.name = "WardrobeKind_" + str(kind)
		button.text = str(PlayerCopy.WARDROBE_SLOTS.get(kind, kind))
		button.custom_minimum_size = Vector2(76, 40)
		button.add_theme_font_size_override("font_size", 15)
		var chosen: bool = kind == picked
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var fill := INK if chosen else (CHIP if state in ["normal", "focus"] else CHIP.darkened(0.06))
			button.add_theme_stylebox_override(state, ThemeRules.padded(ThemeRules.rounded(fill, 12), 14, 6))
			button.add_theme_color_override("font_color" if state == "normal" else "font_%s_color" % state, CREAM if chosen else INK)
		button.pressed.connect(func() -> void: kind_chosen.emit(str(kind)))
		_kinds.add_child(button)

## One item card in its tier frame. `small` is a shelf card.
func _card(entry: Dictionary, small: bool, shop: bool) -> Control:
	var card := Button.new()
	card.name = ("WardrobeShelfCard_" if small else "WardrobeCard_") + str(entry.id)
	card.custom_minimum_size = SHELF_CARD_SIZE if small else CARD_SIZE
	card.toggle_mode = true
	var picked := str(_model.get("selected", "")) == str(entry.id)
	card.set_pressed_no_signal(picked)
	card.accessibility_name = str(entry.name)
	var tier := str(entry.tier)
	card.set_meta("item_id", str(entry.id))
	card.set_meta("tier", tier)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		card.add_theme_stylebox_override(state, TierFrame.style(tier, 16, picked or state in ["pressed", "hover_pressed"]))
	card.pressed.connect(func() -> void: item_chosen.emit(str(entry.id)))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 8 if small else 10)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)
	var picture := PanelContainer.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.add_theme_stylebox_override("panel", ThemeRules.rounded(PICTURE, 12))
	picture.custom_minimum_size.y = 64 if small else 72
	column.add_child(picture)
	var pip := PipAvatar.new(true, SpiritLook.PEACH, SHELF_PIP if small else CARD_PIP, true)
	pip.outfit = Outfit.of(str(entry.id))
	pip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	picture.add_child(pip)
	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_row)
	var title := ShopKit.text(str(entry.name), 13 if small else 15, INK, ShopKit.bold_font())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(title)
	if not small: title_row.add_child(TierFrame.label(tier, 11, ShopKit.bold_font()))
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 6)
	column.add_child(bottom)
	if tier == "earned" and shop and not small: bottom.add_child(_lock_chip())
	if bool(entry.worn) or bool(entry.owned):
		var spacer := Control.new()
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if tier == "earned" and shop and not small: bottom.add_child(spacer)
		bottom.add_child(_tag(PlayerCopy.WARDROBE_WEARING if bool(entry.worn) else PlayerCopy.WARDROBE_OWNED_TAG))
	elif bool(entry.sold) and shop:
		bottom.add_child(ShopKit.price(int(entry.price), 13 if small else 15, INK, INK_SOFT))
	return card

## Yours or Wearing, in a small mint pill.
func _tag(text: String) -> Control:
	var pill := PanelContainer.new()
	pill.name = "WardrobeTag"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(Color("d6eadf"), 10), 8, 2))
	pill.add_child(ShopKit.text(text, 13, Color("2e5d4f"), ShopKit.bold_font()))
	return pill

## The Earned items' "Not for sale" chip with its lock.
func _lock_chip() -> Control:
	var pill := PanelContainer.new()
	pill.name = "WardrobeNotForSale"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(Color("e3ebe7"), 10, TierFrame.frame("earned")), 8, 2))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	row.add_child(TierFrame.mark("earned", 12.0))
	row.add_child(ShopKit.text(PlayerCopy.WARDROBE_NOT_FOR_SALE, 12, TierFrame.ink("earned"), ShopKit.bold_font()))
	pill.add_child(row)
	return pill

## A tab: the picked one is a mint pill, the others plain words.
func _pill(button: Button, picked: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var fill := MINT if picked else (Color.TRANSPARENT if state in ["normal", "focus"] else CHIP)
		button.add_theme_stylebox_override(state, ThemeRules.padded(ThemeRules.rounded(fill, 14), 16, 6))
		button.add_theme_color_override("font_color" if state == "normal" else "font_%s_color" % state, INK if picked else INK_SOFT)

## A part of the pip switch: picked is mint on the dark panel.
func _switch_style(button: Button, picked: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var fill := MINT if picked else (Color.TRANSPARENT if state in ["normal", "focus"] else Color("1d4a44"))
		button.add_theme_stylebox_override(state, ThemeRules.padded(ThemeRules.rounded(fill, 11), 12, 4))
		button.add_theme_color_override("font_color" if state == "normal" else "font_%s_color" % state, INK if picked else CREAM)

## The main button in cream, as the board draws it.
func _cream(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var fill := Color("f4f1e2")
		if state == "hover": fill = Color("ffffff")
		if state in ["pressed", "hover_pressed"]: fill = Color("e4e0cd")
		if state == "disabled": fill = Color("8f9f97")
		button.add_theme_stylebox_override(state, ThemeRules.rounded(fill, 16))

## The small four-point sparkle beside "Featured this week".
class Sparkle extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var points := PackedVector2Array()
		for index in range(8):
			var reach := r if index % 2 == 0 else r * 0.3
			var angle := -PI * 0.5 + TAU * index / 8.0
			points.append(c + Vector2(cos(angle), sin(angle)) * reach)
		draw_colored_polygon(points, Color("3f8f68"))
